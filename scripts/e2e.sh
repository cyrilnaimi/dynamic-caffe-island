#!/usr/bin/env bash
# End-to-end test of the installed app. Drives it through its public
# surfaces (caffe:// URLs and the CLI) and verifies:
#   - real power assertions via `pmset -g assertions`
#   - what the app did, via its unified-log lines
#   - what it looks like, via screenshots in $OUT
#
#   scripts/e2e.sh            # full run (~2 min, includes a real "until" expiry)
#   QUICK=1 scripts/e2e.sh    # skip the expiry wait
#
# Needs: the app at $APP, Screen Recording permission for the terminal (for
# screenshots / window titles). Spotlight itself can't be scripted — test it
# by hand (see README).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-/Applications/DynamicCaffeIsland.app}"
OUT="${OUT:-$ROOT/.e2e}"
mkdir -p "$OUT"
pass=0; fail=0

ok()  { echo "  ✅ $1"; pass=$((pass + 1)); }
ko()  { echo "  ❌ $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else ko "$1"; fi; }
assertions() { pmset -g assertions | grep -c "Dynamic Caffe Island" || true; }
awake()  { [ "$(assertions)" -gt 0 ]; }
asleep() { [ "$(assertions)" -eq 0 ]; }
send() { open -g "$1"; sleep "${2:-1.5}"; }
logs() { /usr/bin/log show --last "${1:-15s}" --info --style compact --predicate 'subsystem BEGINSWITH "ch.dynamic-caffe-island"' 2>/dev/null; }
logged() { logs "${2:-15s}" | grep -qF -- "$1"; }

# Expected Swift `Date` description (UTC) for the next occurrence of HH:MM.
expected_until() {
  local now t
  now=$(date +%s)
  t=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) $1:00" +%s)
  [ "$t" -le "$now" ] && t=$((t + 86400))
  date -u -r "$t" "+%Y-%m-%d %H:%M:%S +0000"
}

SCREEN_W=$(swift -e 'import AppKit; print(Int(NSScreen.screens.first!.frame.width))' 2>/dev/null || echo 1440)
ISLAND_RECT="$((SCREEN_W / 2 - 280)),0,560,200"
shot() { screencapture -x -R "$ISLAND_RECT" "$OUT/$1.png"; }
window_id() {
  swift -e "import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l where (w[\"kCGWindowOwnerName\"] as? String)?.contains(\"Caffe\") == true && (w[\"kCGWindowName\"] as? String) == \"$1\" { print(w[\"kCGWindowNumber\"]!) }" 2>/dev/null | head -1
}

echo "▶ Launch"
pkill -x DynamicCaffeIsland 2>/dev/null; sleep 1
open "$APP" --args -AppleLanguages "(en)"; sleep 3
check "app is running" 'pgrep -x DynamicCaffeIsland >/dev/null'
archs=$(lipo -archs "$APP/Contents/MacOS/DynamicCaffeIsland")
check "universal binary ($archs)" '[[ "$archs" == *x86_64* && "$archs" == *arm64* ]]'
check "no assertion at launch" asleep
shot 01-idle

echo "▶ Presets"
send "caffe://start?minutes=30" 0.8; shot 02-toast
check "30 min → Mac kept awake" awake
check "30 min → session logged as preset(1800.0)" 'logged "preset(1800.0)"'
sleep 3; shot 03-live
send "caffe://stop"
check "stop → assertion released" asleep
send "caffe://indefinite"
check "indefinite → awake" awake
check "indefinite → logged" 'logged "duration=indefinite"'
send "caffe://stop"
send "caffe://toggle"; check "toggle on" awake
send "caffe://toggle"; check "toggle off" asleep
"$ROOT/scripts/caffe" 5; sleep 1.5
check "CLI 'caffe 5' → preset(300.0)" 'logged "preset(300.0)"'
"$ROOT/scripts/caffe" stop; sleep 1.5
check "CLI 'caffe stop' → released" asleep

echo "▶ Until a specific time"
later=$(date -v+2H +%H:%M); exp=$(expected_until "$later")
send "caffe://until?time=$later"
check "until $later → awake" awake
check "until $later → ends $exp" 'logged "untilClockTime($exp)"'
send "caffe://peek" 1.2; shot 04-expanded-until
sleep 5
earlier=$(date -v-1H +%H:%M); exp=$(expected_until "$earlier")
send "caffe://until?time=$earlier"
check "until $earlier (already passed) → rolls to tomorrow: $exp" 'logged "untilClockTime($exp)"'
compact=$(date -v+3H +%H%M); exp=$(expected_until "${compact:0:2}:${compact:2:2}")
send "caffe://until/$compact"
check "compact form /$compact → $exp" 'logged "untilClockTime($exp)"'
send "caffe://stop"
send "caffe://until?time=25:00"
check "invalid time 25:00 rejected (logged)" 'logged "unrecognised url"'
check "invalid time 25:00 → no session started" asleep
send "caffe://bogus"
check "unknown command rejected" 'logged "unrecognised url caffe://bogus"'

echo "▶ Until-time window"
send "caffe://pick" 2
wid=$(window_id "Keep Awake Until")
check "'Keep Awake Until' window opens" '[ -n "$wid" ]'
[ -n "$wid" ] && screencapture -x -o -l "$wid" "$OUT/05-until-window.png"

if [ -z "${QUICK:-}" ]; then
  echo "▶ Until — real expiry (waits up to ~2 min)"
  # Next minute boundary at least 20 s away.
  t=$(( ( $(date +%s) / 60 + 1 ) * 60 )); [ $((t - $(date +%s))) -lt 20 ] && t=$((t + 60))
  hm=$(date -r "$t" +%H:%M); start=$(date +%s)
  send "caffe://until?time=$hm" 1
  check "until $hm → awake" awake
  # Sessions are clamped to ≥ 60 s.
  end=$(( t > start + 60 ? t : start + 60 ))
  while [ "$(date +%s)" -lt $((end + 3)) ]; do sleep 2; done
  check "after $hm → assertion released automatically" asleep
  check "expiry logged" 'logged "cancelled session" 20s'
  shot 06-after-expiry
fi

echo "▶ Localization (French)"
pkill -x DynamicCaffeIsland; sleep 1
open "$APP" --args -AppleLanguages "(fr)"; sleep 3
send "caffe://pick" 2
check "French window title 'Garder éveillé jusqu’à'" '[ -n "$(window_id "Garder éveillé jusqu’à")" ]'
send "caffe://start?minutes=30" 0.8; shot 07-fr-toast
check "French session still keeps Mac awake" awake
send "caffe://stop"

echo "▶ Footprint"
pid=$(pgrep -x DynamicCaffeIsland)
rss=$(ps -o rss= -p "$pid" | tr -d ' ')
check "resident memory < 80 MB (${rss} KB)" '[ "$rss" -lt 81920 ]'

# Leave the app clean: closes the picker window, no active session.
pkill -x DynamicCaffeIsland; sleep 1; open "$APP"

echo
echo "Result: $pass passed, $fail failed — screenshots in $OUT"
[ "$fail" -eq 0 ]
