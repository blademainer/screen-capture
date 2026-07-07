#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build
APP_PATH="$("$ROOT/Scripts/build-app.sh" | tail -n 1)"
plutil -lint "$APP_PATH/Contents/Info.plist"
test -x "$APP_PATH/Contents/MacOS/ScreenCapture"
codesign --verify --deep --strict "$APP_PATH"
"$APP_PATH/Contents/MacOS/ScreenCapture" --diagnose --menu --output /tmp/screen-capture-smoke

echo "Smoke test passed: $APP_PATH"
