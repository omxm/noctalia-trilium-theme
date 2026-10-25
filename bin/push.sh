#!/usr/bin/env bash
# Push the CSS rendered by Noctalia into this machine's Trilium theme note via ETAPI.
#
# - Called by the Noctalia user template's post_hook and by the Trilium launcher wrapper (trilium-launch.sh).
# - Does nothing when the note content and #appThemeBase are already up to date
#   (the post_hook runs on every render, even when nothing changed).
# - After a push, asks for a reload (F5) via notify-send. An open Trilium window only picks up the new CSS after a reload.
# - Exits quietly when Trilium is not running (ETAPI unreachable).
#   Always exits 0 so Noctalia is never held up.
#
# Everything lives in ~/.config/noctalia/trilium/ (prepared by install.sh):
#   machine.conf   MACHINE_NAME=<this machine>; LAYOUT=off drops the layout layer
#   host.conf      ETAPI_URL=... / THEME_NOTE_ID=... (copy of hosts/<name>.conf in the source folder)
#   etapi-token    ETAPI token (mode 600)
#   generated.css  CSS rendered by Noctalia (color layer)
#   layout.css     layout layer (copy of templates/trilium-layout.css), appended after the color layer

set -u

DIR="${TRILIUM_NOCTALIA_DIR:-$HOME/.config/noctalia/trilium}"

notify() {
    notify-send -a "Trilium" -i triliumnext "$1" "${2:-}" 2>/dev/null || true
}

# Read KEY=VALUE settings (never sourced)
conf_get() {
    local file="$1" key="$2"
    [[ -r "$file" ]] || return 1
    sed -n "s/^[[:space:]]*${key}=//p" "$file" | tail -n 1
}

ETAPI_URL="$(conf_get "$DIR/host.conf" ETAPI_URL)"
NOTE_ID="$(conf_get "$DIR/host.conf" THEME_NOTE_ID)"
CSS="$DIR/generated.css"
TOKEN_FILE="$DIR/etapi-token"
LAYOUT_CSS="$DIR/layout.css"
if [[ "$(conf_get "$DIR/machine.conf" LAYOUT)" == "off" || ! -s "$LAYOUT_CSS" ]]; then
    LAYOUT_CSS=""
fi

if [[ -z "$ETAPI_URL" || -z "$NOTE_ID" ]]; then
    notify "Trilium theme: not configured" "Run install.sh ($DIR/host.conf is missing)"
    exit 0
fi
if [[ ! -s "$CSS" ]]; then
    exit 0
fi
if [[ ! -r "$TOKEN_FILE" ]]; then
    notify "Trilium theme: no ETAPI token" "Put one at $TOKEN_FILE"
    exit 0
fi

# Run one at a time when color schemes are switched in quick succession
exec 9>"$DIR/.push.lock"
flock -w 30 9 || exit 0

python3 -I - "$ETAPI_URL" "$NOTE_ID" "$CSS" "$TOKEN_FILE" "$LAYOUT_CSS" <<'PY'
import json, re, subprocess, sys, urllib.error, urllib.request

base, note_id, css_path, token_path, layout_path = sys.argv[1:6]
token = open(token_path).read().strip()
css = open(css_path, encoding="utf-8").read()

# Pick the Next base theme from the "mode: dark|light" line at the top of the template
m = re.search(r"mode:\s*(dark|light)", css)
theme_base = f"next-{m.group(1)}" if m else "next"

content = css
if layout_path:
    content += "\n" + open(layout_path, encoding="utf-8").read()

def notify(title, body=""):
    subprocess.run(["notify-send", "-a", "Trilium", "-i", "triliumnext", title, body],
                   stderr=subprocess.DEVNULL, check=False)

def call(method, path, data=None, ctype="application/json"):
    if data is not None and not isinstance(data, bytes):
        data = json.dumps(data).encode()
    req = urllib.request.Request(base + path, data=data, method=method,
                                 headers={"Authorization": token, "Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=5) as r:
        return r.read()

try:
    note = json.loads(call("GET", f"/notes/{note_id}"))
    current = call("GET", f"/notes/{note_id}/content").decode("utf-8")
except urllib.error.HTTPError as e:
    if e.code == 401:
        notify("Trilium theme: ETAPI token rejected", "Create a new token and put it in place again")
    elif e.code == 404:
        notify("Trilium theme: theme note not found", "Run install.sh again")
    else:
        notify("Trilium theme: push failed", f"HTTP {e.code}")
    sys.exit(0)
except (urllib.error.URLError, OSError):
    # Trilium is not running. The launcher wrapper pushes on the next start.
    sys.exit(0)

base_attr = next((a for a in note["attributes"]
                  if a["type"] == "label" and a["name"] == "appThemeBase"), None)

changed = False
try:
    if current != content:
        call("PUT", f"/notes/{note_id}/content", content.encode("utf-8"), "text/plain")
        changed = True
    if base_attr is None:
        call("POST", "/attributes", {"noteId": note_id, "type": "label",
                                     "name": "appThemeBase", "value": theme_base})
        changed = True
    elif base_attr["value"] != theme_base:
        call("PATCH", f"/attributes/{base_attr['attributeId']}", {"value": theme_base})
        changed = True
except (urllib.error.URLError, OSError) as e:
    notify("Trilium theme: push failed", str(e))
    sys.exit(0)

if changed:
    notify("Trilium theme updated", "Press F5 (or Ctrl+R) in Trilium to apply it")
PY

exit 0
