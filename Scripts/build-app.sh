#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_DIR="$ROOT/.build/app/ScreenCapture.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c "$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/$CONFIG/ScreenCapture" "$MACOS/ScreenCapture"
cp "Resources/Info.plist" "$CONTENTS/Info.plist"

if [ -d ".build/$CONFIG/ScreenCaptureApp_ScreenCaptureApp.resources" ]; then
  cp -R ".build/$CONFIG/ScreenCaptureApp_ScreenCaptureApp.resources/." "$RESOURCES/"
fi

chmod +x "$MACOS/ScreenCapture"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
