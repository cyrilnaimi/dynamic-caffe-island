#!/usr/bin/env bash
# Headless smoke test (CI-safe: no Screen Recording permission needed).
# Launches the given .app natively on this machine's architecture, then
# checks real power assertions for start / until / stop.
#
#   scripts/smoke-test.sh "path/to/Caffe Island.app"
set -euo pipefail
APP="${1:?usage: smoke-test.sh path/to/Caffe Island.app}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"   # absolute: `open -a` needs it
BIN="$APP/Contents/MacOS/Caffe Island"

count() { pmset -g assertions | grep -c "Caffe Island" || true; }
# Send URLs to the app under test, not to another installed copy that
# LaunchServices might prefer for caffe://.
url() { open -g -a "$APP" "$1"; }
fail() { echo "❌ $1"; pmset -g assertions || true; exit 1; }

echo "host arch: $(uname -m) · binary: $(lipo -archs "$BIN")"
lipo -archs "$BIN" | grep -q "$(uname -m)" || fail "binary lacks $(uname -m) slice"

# Register the URL scheme with LaunchServices, then launch.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
pkill -x "Caffe Island" 2>/dev/null || true
open "$APP" --args -AppleLanguages "(en)"
for _ in $(seq 1 20); do pgrep -x "Caffe Island" >/dev/null && break; sleep 0.5; done
pgrep -x "Caffe Island" >/dev/null || fail "app did not launch"
sleep 2
[ "$(count)" -eq 0 ] || fail "assertion held at launch"
echo "✅ launched, idle"

url "caffe://start?minutes=5"; sleep 2
[ "$(count)" -gt 0 ] || fail "start did not create a power assertion"
echo "✅ start → Mac kept awake"

url "caffe://stop"; sleep 2
[ "$(count)" -eq 0 ] || fail "stop did not release the assertion"
echo "✅ stop → released"

url "caffe://until/$(date -v+1H +%H%M)"; sleep 2
[ "$(count)" -gt 0 ] || fail "until did not create a power assertion"
url "caffe://stop"; sleep 2
echo "✅ until → kept awake, then released"

sleep 5 & watched=$!
url "caffe://while?pid=$watched"; sleep 2
[ "$(count)" -gt 0 ] || fail "while did not create a power assertion"
wait "$watched"; sleep 2
[ "$(count)" -eq 0 ] || fail "while did not release the assertion after the process exited"
echo "✅ while pid → kept awake until the process exited"

pgrep -x "Caffe Island" >/dev/null || fail "app crashed during test"
pkill -x "Caffe Island"
echo "smoke test passed"
