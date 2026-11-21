#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_NAME="HiDPI Quick"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_STAGE="$BUILD_DIR/dmg-stage"
DMG_PATH="$BUILD_DIR/HiDPI-Quick.dmg"
ICON_SOURCE="$ROOT/Resources/AppIcon.png"
ICONSET="$BUILD_DIR/AppIcon.iconset"
APP_ICON="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$DMG_STAGE" "$ICONSET"

cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil --convert icns "$ICONSET" --output "$APP_ICON"

SOURCES=("$ROOT"/Sources/*.swift)
swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    "${SOURCES[@]}" \
    -o "$APP_BUNDLE/Contents/MacOS/HiDPIQuick" \
    -framework Cocoa \
    -framework CoreGraphics \
    -framework IOKit

chmod +x "$APP_BUNDLE/Contents/MacOS/HiDPIQuick"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$APP_ICON" "$DMG_STAGE/.VolumeIcon.icns"

if SETFILE_PATH="$(xcrun --find SetFile 2>/dev/null)"; then
    "$SETFILE_PATH" -a C "$DMG_STAGE"
fi

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
