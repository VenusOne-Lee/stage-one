#!/usr/bin/env bash
# Builds Stage One.app and a DMG into dist/.
#   VERSION=0.1.0 ARCHS="arm64 x86_64" scripts/build-app.sh
# Signs ad-hoc unless SIGN_IDENTITY is set (Developer ID for notarised releases).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

arch_flags=()
for a in $ARCHS; do arch_flags+=(--arch "$a"); done

swift build -c release "${arch_flags[@]}" --product StageOne
swift build -c release "${arch_flags[@]}" --product stage
BIN="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

APP="dist/Stage One.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/StageOne" "$APP/Contents/MacOS/StageOne"
cp "$BIN/stage" "$APP/Contents/Helpers/stage"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
# Bundle resources SwiftPM produced (fonts, images), if any.
find "$BIN" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;
if [ -d integrations ]; then cp -R integrations "$APP/Contents/Resources/"; fi

codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

STAGING="dist/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Stage One" -srcfolder "$STAGING" -ov -format UDZO "dist/StageOne-$VERSION.dmg"
rm -rf "$STAGING"
echo "Built dist/StageOne-$VERSION.dmg"
