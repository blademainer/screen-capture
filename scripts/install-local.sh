#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="/Applications/MacScreenCapture.app"
BUILD_PATH="$PROJECT_ROOT/.build/release"
STAGING_ROOT="$(mktemp -d)"
STAGED_APP="$STAGING_ROOT/MacScreenCapture.app"
REQUIREMENT='designated => identifier "com.blademainer.MacScreenCapture"'

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

cd "$PROJECT_ROOT"
swift build -c release

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$PROJECT_ROOT/MacScreenCapture/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$BUILD_PATH/MacScreenCapture" "$STAGED_APP/Contents/MacOS/MacScreenCapture"
cp "$PROJECT_ROOT/MacScreenCapture/Assets.xcassets/AppIcon.appiconset/AppIcon.icns" \
    "$STAGED_APP/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_PATH/MacScreenCapture_MacScreenCapture.bundle" \
    "$STAGED_APP/Contents/Resources/"
chmod +x "$STAGED_APP/Contents/MacOS/MacScreenCapture"

codesign --force --deep --sign - \
    -r="$REQUIREMENT" \
    --entitlements "$PROJECT_ROOT/MacScreenCapture/MacScreenCapture.entitlements" \
    "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

pkill -x MacScreenCapture 2>/dev/null || true
rm -rf "$APP_PATH"
ditto "$STAGED_APP" "$APP_PATH"
open -a "$APP_PATH"

echo "Installed $APP_PATH"
