#!/usr/bin/env bash
# Install the Noctalia -> Trilium theme sync on this machine. Safe to run any number of times.
#
# Usage:
#   ./install.sh <machine-name>   first run on a machine (creates machine.conf)
#   ./install.sh                  later runs (uses the name in machine.conf)
#
# Requirements:
#   - The Trilium desktop app is running (ETAPI is used to find or create the theme note)
#   - An ETAPI token is at ~/.config/noctalia/trilium/etapi-token (create it in this machine's Trilium: Options -> ETAPI)
#
# What it does:
#   1. Writes the machine name to ~/.config/noctalia/trilium/machine.conf (if missing)
#   2. Creates the "Noctalia Themes" note and this machine's theme note "Noctalia (<name>)" in Trilium (if missing)
#   3. Writes the ETAPI URL and the theme note ID to hosts/<name>.conf in this folder
#   4. Copies the scripts, templates (color and layout) and settings to ~/.config/noctalia/trilium/
#   5. Registers the Noctalia user template in ~/.config/noctalia/trilium.toml
#   6. Places a user-level copy of the system .desktop entry (triliumnext.desktop from the AUR or trilium.desktop
#      from the official .deb, same name) in ~/.local/share/applications/ so launching Trilium re-pushes the latest CSS
#   7. Pushes the current CSS to the theme note (only if it changed). This is also how a layout-only change gets pushed

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$HOME/.config/noctalia/trilium"
NOCTALIA_TOML="$HOME/.config/noctalia/trilium.toml"
DESKTOP_IDS=(triliumnext.desktop trilium.desktop)
DESKTOP_MARK="X-Noctalia-Trilium=true"
DEFAULT_ETAPI_URL="http://127.0.0.1:37840/etapi"
TODAY="$(date +%Y%m%d)"

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

conf_get() {
    [[ -r "$1" ]] || return 0
    sed -n "s/^[[:space:]]*$2=//p" "$1" | tail -n 1
}

# Skip identical files (avoids needless Noctalia config reloads).
# Files written by install.sh are simply overwritten; any other file (no $INSTALL_MARK) is backed up first.
INSTALL_MARK="noctalia-trilium (written by install.sh)"
install_file() {
    local src="$1" dst="$2" mode="$3"
    if [[ -e "$dst" ]] && cmp -s "$src" "$dst"; then
        chmod "$mode" "$dst"
        return 0
    fi
    if [[ -e "$dst" && "$dst" != "$DIR"/* ]] && ! grep -qF "$INSTALL_MARK" "$dst"; then
        cp -p "$dst" "$dst.bak-$TODAY"
        say "backed up: $dst.bak-$TODAY"
    fi
    install -m "$mode" "$src" "$dst"
    say "wrote: $dst"
}

install -d -m 700 "$DIR"
install -d -m 755 "$DIR/bin"

# 1. Machine name
current_name="$(conf_get "$DIR/machine.conf" MACHINE_NAME)"
name="${1:-$current_name}"
[[ -n "$name" ]] || die "give this machine a name (e.g. ./install.sh desktop)"
[[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "use lowercase letters, digits and hyphens only: $name"
if [[ -n "$current_name" && "$current_name" != "$name" ]]; then
    die "this machine is already installed as \"$current_name\" ($DIR/machine.conf). Edit that file first if you want to rename it"
fi
if [[ -z "$current_name" ]]; then
    cat > "$DIR/machine.conf" <<EOF
# Name of this machine (pick one per machine; lowercase letters, digits and hyphens only).
# Used for the Trilium theme "Noctalia (<name>)" and #appTheme=noctalia-<name>.
# Add LAYOUT=off to drop the layout layer and keep colors only.
MACHINE_NAME=$name
EOF
    chmod 644 "$DIR/machine.conf"
    say "machine name: $name"
fi

# ETAPI token
TOKEN_FILE="$DIR/etapi-token"
[[ -s "$TOKEN_FILE" ]] || die "no ETAPI token at $TOKEN_FILE (see README)"
chmod 600 "$TOKEN_FILE"

# 2. Theme note
HOST_CONF="$REPO/hosts/$name.conf"
etapi_url="$(conf_get "$HOST_CONF" ETAPI_URL)"
etapi_url="${etapi_url:-$DEFAULT_ETAPI_URL}"
curl -s -m 3 -o /dev/null "${etapi_url%/etapi}/api/health-check" \
    || die "cannot reach Trilium ($etapi_url). Start the Trilium desktop app and run this again"

note_id="$(python3 -I - "$etapi_url" "$TOKEN_FILE" "$name" <<'PY'
import json, sys, urllib.error, urllib.parse, urllib.request

base, token_path, name = sys.argv[1:4]
token = open(token_path).read().strip()

def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method,
                                 headers={"Authorization": token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            t = r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"error: ETAPI {method} {path} -> HTTP {e.code}" + (" (token rejected)" if e.code == 401 else ""))
    return json.loads(t) if t else None

def search(q):
    return call("GET", "/notes?" + urllib.parse.urlencode({"search": q}))["results"]

def ensure_label(note, label, value=""):
    if not any(a["type"] == "label" and a["name"] == label for a in note["attributes"]):
        call("POST", "/attributes", {"noteId": note["noteId"], "type": "label", "name": label, "value": value})

folders = search("#noctaliaThemes")
if folders:
    folder = folders[0]["noteId"]
else:
    folder = call("POST", "/create-note", {
        "parentNoteId": "root", "title": "Noctalia Themes", "type": "text",
        "content": "<p>Trilium themes that follow the Noctalia color scheme (one per machine). "
                   "They are rewritten automatically; do not edit them by hand.</p>",
    })["note"]["noteId"]
    call("POST", "/attributes", {"noteId": folder, "type": "label", "name": "noctaliaThemes", "value": ""})
    print(f"==> created \"Noctalia Themes\" in Trilium ({folder})", file=sys.stderr)

themes = search(f"#noctaliaMachine={name}")
if themes:
    note = call("GET", f"/notes/{themes[0]['noteId']}")
else:
    note = call("POST", "/create-note", {
        "parentNoteId": folder, "title": f"Noctalia ({name})", "type": "code", "mime": "text/css",
        "content": f"/* Noctalia ({name}): rewritten by push.sh */\n",
    })["note"]
    print(f"==> created \"Noctalia ({name})\" in Trilium ({note['noteId']})", file=sys.stderr)
ensure_label(note, "appTheme", f"noctalia-{name}")
ensure_label(note, "noctaliaMachine", name)
print(note["noteId"])
PY
)"
[[ -n "$note_id" ]] || die "could not prepare the theme note"

# 3. hosts/<name>.conf in this folder (never holds the token)
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
# Settings for machine "$name" ($INSTALL_MARK). The ETAPI token is never stored here.
ETAPI_URL=$etapi_url
THEME_NOTE_ID=$note_id
EOF
if [[ "$(conf_get "$HOST_CONF" ETAPI_URL)" != "$etapi_url" || "$(conf_get "$HOST_CONF" THEME_NOTE_ID)" != "$note_id" ]]; then
    install -d "$REPO/hosts"
    install_file "$tmp" "$HOST_CONF" 644
fi

# 4. Copy to ~/.config/noctalia/trilium/
install_file "$HOST_CONF" "$DIR/host.conf" 644
install_file "$REPO/bin/push.sh" "$DIR/bin/push.sh" 755
install_file "$REPO/bin/trilium-launch.sh" "$DIR/bin/trilium-launch.sh" 755
install_file "$REPO/templates/trilium.css" "$DIR/template.css" 644
install_file "$REPO/templates/trilium-layout.css" "$DIR/layout.css" 644

# 5. Noctalia user template
#    Noctalia does not re-render a template on a plain config reload, but it does render a template id it has
#    not seen before. The id is derived from the template content, so editing the template triggers a render.
tid="trilium_$(sha256sum "$DIR/template.css" | cut -c1-8)"
cat > "$tmp" <<EOF
# $INSTALL_MARK. Do not edit by hand.
# Source folder: $REPO
[theme.templates.user.$tid]
input_path = "$DIR/template.css"
output_path = "$DIR/generated.css"
post_hook = "'$DIR/bin/push.sh'"
EOF
noctalia config validate "$tmp" >/dev/null || die "Noctalia rejected the generated config ($tmp)"
template_changed=0
cmp -s "$tmp" "$NOCTALIA_TOML" 2>/dev/null || template_changed=1
install_file "$tmp" "$NOCTALIA_TOML" 644

# 6. Launcher entry (a copy of the system entry except Exec; the wrapper reads the system Exec on every launch)
#    The user-level copy takes the system entry's name so that it replaces the system entry in launchers.
system_desktop=""
IFS=: read -r -a data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for id in "${DESKTOP_IDS[@]}"; do
    for d in "${data_dirs[@]}"; do
        if [[ -r "$d/applications/$id" ]]; then
            system_desktop="$d/applications/$id"
            break 2
        fi
    done
done
if [[ -z "$system_desktop" ]]; then
    say "no system ${DESKTOP_IDS[*]} found; skipping the launcher entry"
else
    DESKTOP_USER="$HOME/.local/share/applications/${system_desktop##*/}"
    python3 -I - "$system_desktop" "$DIR/bin/trilium-launch.sh" "$DESKTOP_MARK" "$INSTALL_MARK" > "$tmp" <<'PY'
import sys
src, launcher, mark, install_mark = sys.argv[1:5]
section = None
out = [f"# {install_mark}. Based on {src}.",
       "# Exec goes through a wrapper that reads the system entry's Exec line on every launch."]
for line in open(src, encoding="utf-8"):
    line = line.rstrip("\n")
    if line.startswith("["):
        section = line
    if section == "[Desktop Entry]" and line.startswith("Exec="):
        line = f'Exec="{launcher}" %U'
    elif section == "[Desktop Entry]" and line.startswith("TryExec="):
        continue
    out.append(line)
    if line == "[Desktop Entry]":
        out.append(mark)
print("\n".join(out))
PY
    install -d "$(dirname "$DESKTOP_USER")"
    install_file "$tmp" "$DESKTOP_USER" 644
fi

# Wait for Noctalia to render a new template
if [[ $template_changed -eq 1 ]]; then
    say "waiting for Noctalia to render the template..."
    for _ in $(seq 1 20); do
        if [[ "$DIR/generated.css" -nt "$DIR/template.css" ]]; then
            break
        fi
        sleep 0.5
    done
fi
# 7. Push (push.sh does nothing when nothing changed)
if [[ -s "$DIR/generated.css" && "$DIR/generated.css" -nt "$DIR/template.css" ]]; then
    "$DIR/bin/push.sh"
    say "done. Pushed if anything changed (press F5 in Trilium when the notification shows up)"
    say "first time on this machine? Pick \"Noctalia ($name)\" in Trilium: Options -> Appearance"
else
    say "done, but the color CSS has not been rendered yet. Run 'noctalia msg templates-apply', then ./install.sh again"
fi
