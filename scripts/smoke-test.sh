#!/usr/bin/env bash
# Headless smoke test (CI-safe: no Screen Recording permission needed).
# Launches the given .app natively on this machine's architecture, then
# checks real power assertions for start / until / stop.
#
#   scripts/smoke-test.sh path/to/DynamicCaffeIsland.app
set -euo pipefail
APP="${1:?usage: smoke-test.sh path/to/DynamicCaffeIsland.app}"
BIN="$APP/Contents/MacOS/DynamicCaffeIsland"

count() { pmset -g assertions | grep -c "Dynamic Caffe Island" || true; }
fail() { echo "❌ $1"; pmset -g assertions || true; exit 1; }

echo "host arch: $(uname -m) · binary: $(lipo -archs "$BIN")"
lipo -archs "$BIN" | grep -q "$(uname -m)" || fail "binary lacks $(uname -m) slice"

# Register the URL scheme with LaunchServices, then launch.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
pkill -x DynamicCaffeIsland 2>/dev/null || true
open "$APP" --args -AppleLanguages "(en)"
for _ in $(seq 1 20); do pgrep -x DynamicCaffeIsland >/dev/null && break; sleep 0.5; done
pgrep -x DynamicCaffeIsland >/dev/null || fail "app did not launch"
sleep 2
[ "$(count)" -eq 0 ] || fail "assertion held at launch"
echo "✅ launched, idle"

open -g "caffe://start?minutes=5"; sleep 2
[ "$(count)" -gt 0 ] || fail "start did not create a power assertion"
echo "✅ start → Mac kept awake"

open -g "caffe://stop"; sleep 2
[ "$(count)" -eq 0 ] || fail "stop did not release the assertion"
echo "✅ stop → released"

open -g "caffe://until/$(date -v+1H +%H%M)"; sleep 2
[ "$(count)" -gt 0 ] || fail "until did not create a power assertion"
open -g "caffe://stop"; sleep 2
echo "✅ until → kept awake, then released"

pgrep -x DynamicCaffeIsland >/dev/null || fail "app crashed during test"
pkill -x DynamicCaffeIsland
echo "smoke test passed"
