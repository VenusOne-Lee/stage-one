#!/usr/bin/env bash
# Packs an app bundle into dist/StageOne-$VERSION.dmg with an /Applications link.
#   VERSION=0.1.0 [SIGN_IDENTITY="Developer ID Application: ..."] scripts/make-dmg.sh "dist/Stage One.app"
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/Stage One.app}"
VERSION="${VERSION:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DMG="dist/StageOne-$VERSION.dmg"

STAGING="$(mktemp -d)/Stage One"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$(basename "$APP")"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Stage One" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$(dirname "$STAGING")"
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
echo "Built $DMG"
