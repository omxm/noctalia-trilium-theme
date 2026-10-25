#!/usr/bin/env bash
# Trilium launcher wrapper (Exec of the user-level triliumnext.desktop).
#
# 1. Reads the Exec line of the system triliumnext.desktop on every launch and starts Trilium with it
#    (so a package update that changes the system Exec line is picked up automatically).
# 2. Waits until Trilium answers, then runs push.sh once to catch up on color changes made while
#    Trilium was closed. ETAPI only exists once Trilium is running, so if anything is pushed the window
#    is already up and needs an F5 (push.sh sends a notification).

set -u

DIR="${TRILIUM_NOCTALIA_DIR:-$HOME/.config/noctalia/trilium}"
DESKTOP_ID="triliumnext.desktop"

# Find the system .desktop entry (not the user-level override that points here)
system_desktop=""
IFS=: read -r -a data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for d in "${data_dirs[@]}"; do
    if [[ -r "$d/applications/$DESKTOP_ID" ]]; then
        system_desktop="$d/applications/$DESKTOP_ID"
        break
    fi
done

if [[ -z "$system_desktop" ]]; then
    notify-send -a "Trilium" "Cannot start Trilium" "System $DESKTOP_ID not found" 2>/dev/null
    exit 1
fi

# Turn the [Desktop Entry] Exec line into an argv (field codes such as %U are replaced by our arguments)
mapfile -d '' -t cmd < <(python3 -I - "$system_desktop" "$@" <<'PY'
import shlex, sys
path, args = sys.argv[1], sys.argv[2:]
exec_line, section = None, None
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if line.startswith("["):
        section = line
    elif section == "[Desktop Entry]" and line.startswith("Exec="):
        exec_line = line[len("Exec="):]
        break
if not exec_line:
    sys.exit(1)
out = []
for tok in shlex.split(exec_line):
    if tok in ("%f", "%u"):
        out.extend(args[:1])
    elif tok in ("%F", "%U"):
        out.extend(args)
    elif tok in ("%i", "%c", "%k"):
        continue
    else:
        out.append(tok.replace("%%", "%"))
sys.stdout.write("\0".join(out))
PY
)

if [[ ${#cmd[@]} -eq 0 ]]; then
    notify-send -a "Trilium" "Cannot start Trilium" "Could not read the Exec line of $system_desktop" 2>/dev/null
    exit 1
fi

setsid -f "${cmd[@]}" >/dev/null 2>&1 < /dev/null

# Wait up to 60 s for Trilium to answer, then run push.sh once
ETAPI_URL="$(sed -n 's/^[[:space:]]*ETAPI_URL=//p' "$DIR/host.conf" 2>/dev/null | tail -n 1)"
[[ -n "$ETAPI_URL" ]] || exit 0
health="${ETAPI_URL%/etapi}/api/health-check"

for _ in $(seq 1 60); do
    if curl -s -m 1 -o /dev/null "$health"; then
        exec "$DIR/bin/push.sh"
    fi
    sleep 1
done
exit 0
