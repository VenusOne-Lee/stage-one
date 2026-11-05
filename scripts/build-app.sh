#!/usr/bin/env bash
# Builds Stage One.app (with the `stage` CLI and Sparkle.framework inside) and a DMG into dist/.
#   VERSION=0.1.0 ARCHS="arm64 x86_64" scripts/build-app.sh
#
# Environment:
#   VERSION                 CFBundleShortVersionString (default 0.1.0)
#   BUILD                   CFBundleVersion (default: commit count, which Sparkle compares)
#   ARCHS                   architectures to build (default "arm64 x86_64")
#   SIGN_IDENTITY           codesign identity; "-" (default) signs ad-hoc. A Developer ID
#                           identity also turns on the hardened runtime and a secure timestamp.
#   SPARKLE_ED_PUBLIC_KEY   Sparkle EdDSA public key written to SUPublicEDKey (optional)
#   NO_DMG=1                stop after the .app (the release workflow notarises it first)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-arm64 x86_64}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SPARKLE_ED_PUBLIC_KEY="${SPARKLE_ED_PUBLIC_KEY:-__SPARKLE_PUBLIC_KEY__}"

arch_flags=()
for a in $ARCHS; do arch_flags+=(--arch "$a"); done

# App icon: generated, never committed (see scripts/make-icon.swift).
if [ ! -f Resources/AppIcon.icns ]; then
    swift scripts/make-icon.swift Resources/AppIcon.icns
fi

swift build -c release "${arch_flags[@]}" --product StageOne
swift build -c release "${arch_flags[@]}" --product stage
BIN="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

APP="dist/Stage One.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers" "$APP/Contents/Frameworks"
cp "$BIN/StageOne" "$APP/Contents/MacOS/StageOne"
cp "$BIN/stage" "$APP/Contents/Helpers/stage"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" -e "s|__SPARKLE_PUBLIC_KEY__|$SPARKLE_ED_PUBLIC_KEY|" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Bundle resources SwiftPM produced (fonts, images), if any.
find "$BIN" -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;
if [ -d integrations ]; then cp -R integrations "$APP/Contents/Resources/"; fi

# Sparkle.framework: SwiftPM links it but does not bundle it. Prefer the copy next to the
# products, fall back to the downloaded xcframework slice.
SPARKLE_FW="$(find "$BIN" .build/artifacts -name Sparkle.framework -type d -not -path "*/Sparkle.framework/*" 2>/dev/null | head -1 || true)"
if [ -z "$SPARKLE_FW" ]; then
    echo "error: Sparkle.framework not found in $BIN or .build/artifacts" >&2
    exit 1
fi
echo "Bundling $SPARKLE_FW"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
RPATHS="$(otool -l "$APP/Contents/MacOS/StageOne")"
if ! grep -q "@executable_path/../Frameworks" <<< "$RPATHS"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/StageOne"
fi

# Sign inside out (no --deep): Sparkle's helpers, the framework, the CLI, then the app.
sign_flags=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then sign_flags+=(--options runtime --timestamp); fi
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$FW/XPCServices/Installer.xpc" "$FW/Autoupdate" "$FW/Updater.app"; do
    if [ -e "$item" ]; then codesign "${sign_flags[@]}" "$item"; fi
done
if [ -e "$FW/XPCServices/Downloader.xpc" ]; then
    codesign "${sign_flags[@]}" --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
fi
codesign "${sign_flags[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${sign_flags[@]}" --identifier africa.venusone.StageOne.stage "$APP/Contents/Helpers/stage"
codesign "${sign_flags[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $APP ($VERSION, build $BUILD)"

if [ "${NO_DMG:-0}" != "1" ]; then
    VERSION="$VERSION" SIGN_IDENTITY="$SIGN_IDENTITY" scripts/make-dmg.sh "$APP"
fi
