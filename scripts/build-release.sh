#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

usage() {
    echo "Usage: $0 [--version VERSION] [--build-number NUMBER]"
    echo "Build an ad-hoc signed universal macOS app, ZIP, DMG, and SHA256SUMS in build/."
}

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' MacScreenCapture/Info.plist)"
BUILD_NUMBER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version|--build-number)
            [[ $# -ge 2 ]] || { usage >&2; exit 1; }
            if [[ "$1" == "--build-number" ]]; then
                BUILD_NUMBER="$2"
            else
                VERSION="${2#v}"
            fi
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ ! "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
    echo "Invalid version: $VERSION (expected 1.2.3 or 1.2.3-rc.1)" >&2
    exit 1
fi
BUNDLE_VERSION="${VERSION%%-*}"
BUILD_NUMBER="${BUILD_NUMBER:-$BUNDLE_VERSION}"
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Invalid build number: $BUILD_NUMBER" >&2
    exit 1
fi

BUILD_DIR="$PROJECT_ROOT/build"
APP_PATH="$BUILD_DIR/export/MacScreenCapture.app"
DMG_ROOT="$BUILD_DIR/dmg-root"
PACKAGE_NAME="MacScreenCapture-$VERSION-universal-macOS"
REQUIREMENT='designated => identifier "com.blademainer.MacScreenCapture"'

BINARIES=()
RESOURCE_BUNDLE=""
for ARCH in arm64 x86_64; do
    SCRATCH_PATH="$PROJECT_ROOT/.build/package-$ARCH"
    swift build -c release --arch "$ARCH" --scratch-path "$SCRATCH_PATH"
    BIN_PATH="$(swift build -c release --arch "$ARCH" --scratch-path "$SCRATCH_PATH" --show-bin-path)"
    BINARIES+=("$BIN_PATH/MacScreenCapture")
    if [[ "$ARCH" == "arm64" ]]; then
        RESOURCE_BUNDLE="$BIN_PATH/MacScreenCapture_MacScreenCapture.bundle"
    fi
done

# Only the staged bundle is modified; the tracked plist stays unchanged.
rm -rf "$APP_PATH" "$DMG_ROOT"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$DMG_ROOT"
cp MacScreenCapture/Info.plist "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BUNDLE_VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 15.0' "$APP_PATH/Contents/Info.plist"
cp MacScreenCapture/Assets.xcassets/AppIcon.appiconset/AppIcon.icns "$APP_PATH/Contents/Resources/"
ditto "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/MacScreenCapture_MacScreenCapture.bundle"
xcrun lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/MacScreenCapture"
chmod +x "$APP_PATH/Contents/MacOS/MacScreenCapture"
xcrun lipo "$APP_PATH/Contents/MacOS/MacScreenCapture" -verify_arch arm64 x86_64
xcrun lipo -archs "$APP_PATH/Contents/MacOS/MacScreenCapture"
plutil -lint "$APP_PATH/Contents/Info.plist"

# Ad-hoc signing needs no certificate and is not Developer ID signing or notarization.
codesign --force --deep --sign - -r="$REQUIREMENT" \
    --entitlements MacScreenCapture/MacScreenCapture.entitlements "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$PACKAGE_NAME.zip"
ditto "$APP_PATH" "$DMG_ROOT/MacScreenCapture.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname MacScreenCapture -srcfolder "$DMG_ROOT" \
    -ov -format UDZO "$BUILD_DIR/$PACKAGE_NAME.dmg"
hdiutil verify "$BUILD_DIR/$PACKAGE_NAME.dmg"
(
    cd "$BUILD_DIR"
    shasum -a 256 "$PACKAGE_NAME.zip" "$PACKAGE_NAME.dmg" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
echo "Packaged $PACKAGE_NAME in $BUILD_DIR (ad-hoc signed, not notarized)."
