#!/usr/bin/env bash
# Regenerates the user-manual screenshots in docs/manual/img/.
#
# Privacy by construction: every capture uses `screencapture -l <windowID>`
# on the app's OWN windows only (island panel, Until window). Nothing else on
# screen — desktop, other apps, notifications, menu bar, cursor — can appear.
#
#   scripts/capture-manual.sh          # English + French
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-/Applications/DynamicCaffeIsland.app}"
IMG="$ROOT/docs/manual/img"
mkdir -p "$IMG"

# Prints the window number of the app window matching layer and/or title.
win() { # $1 = layer or "", $2 = title or ""
  swift -e "import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[\"kCGWindowOwnerName\"] as? String)?.contains(\"Caffe\") == true {
  let layer = w[\"kCGWindowLayer\"] as! Int, name = w[\"kCGWindowName\"] as? String ?? \"\"
  if (\"$1\".isEmpty || String(layer) == \"$1\") && (\"$2\".isEmpty || name == \"$2\") { print(w[\"kCGWindowNumber\"]!); break }
}" 2>/dev/null
}
island() { screencapture -x -o -l "$(win 27 "")" "$IMG/$1.png"; }
send() { open -g "$1"; sleep "${2:-1.5}"; }

for lang in en fr; do
  case $lang in
    en) title="Keep Awake Until" ;;
    fr) title="Garder éveillé jusqu’à" ;;
  esac
  pkill -x DynamicCaffeIsland 2>/dev/null || true; sleep 1
  open "$APP" --args -AppleLanguages "($lang)"; sleep 3

  island "$lang-idle"
  send "caffe://peek" 1.2;             island "$lang-expanded-idle"; sleep 5
  send "caffe://start?minutes=30" 0.7; island "$lang-toast"
  sleep 3;                             island "$lang-live"
  send "caffe://peek" 1.2;             island "$lang-expanded"; sleep 5
  send "caffe://stop" 0.7;             island "$lang-stopped"; sleep 3
  send "caffe://pick" 2
  screencapture -x -o -l "$(win "" "$title")" "$IMG/$lang-until-window.png"
done

sips -Z 256 "$ROOT/App/Assets.xcassets/AppIcon.appiconset/icon_1024.png" --out "$IMG/icon.png" >/dev/null

# Trim transparent margins (island panel canvas is larger than the shape).
python3 - "$IMG" <<'PY' || echo "(Pillow not installed — skipping trim)"
import sys, glob
from PIL import Image
for f in glob.glob(sys.argv[1] + "/*-*.png"):
    im = Image.open(f).convert("RGBA")
    box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if box:
        l, t, r, b = box
        im.crop((max(0, l - 12), t, min(im.width, r + 12), min(im.height, b + 16))).save(f, optimize=True)
PY
pkill -x DynamicCaffeIsland; sleep 1; open "$APP"
ls -1 "$IMG"
