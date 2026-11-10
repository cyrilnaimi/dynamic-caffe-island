#!/usr/bin/env bash
# Build a universal (arm64 + x86_64) Release .app, ad-hoc sign it, and
# optionally install it to /Applications so Spotlight indexes its shortcuts.
#
#   scripts/build-release.sh            # build into ./dist
#   scripts/build-release.sh --install  # build + copy to /Applications + launch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA:-$ROOT/.build-xcode}"
DIST="$ROOT/dist"
APP_NAME="DynamicCaffeIsland.app"

cd "$ROOT"
xcodegen generate --quiet

APP="$DERIVED/Build/Products/Release/$APP_NAME"
rm -rf "$APP"   # never package a stale product if this build fails

LOG="$DERIVED/build-release.log"
mkdir -p "$DERIVED"
if ! xcodebuild \
  -project DynamicCaffeIsland.xcodeproj \
  -scheme DynamicCaffeIsland \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u >&2
  echo "BUILD FAILED — full log: $LOG" >&2
  exit 1
fi
echo "** BUILD SUCCEEDED **"
[ -d "$APP" ] || { echo "build failed: $APP missing" >&2; exit 1; }

rm -rf "$DIST" && mkdir -p "$DIST"
cp -R "$APP" "$DIST/"
codesign --force --deep --options runtime --sign - "$DIST/$APP_NAME"
echo "architectures: $(lipo -archs "$DIST/$APP_NAME/Contents/MacOS/DynamicCaffeIsland")"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x DynamicCaffeIsland 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME"
  cp -R "$DIST/$APP_NAME" /Applications/
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME"
  open "/Applications/$APP_NAME"
  echo "installed and launched /Applications/$APP_NAME"
fi
