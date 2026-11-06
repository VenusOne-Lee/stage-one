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
# Ad-hoc builds aren't notarised, so Gatekeeper blocks the first launch. Say how to open it.
if [ "$SIGN_IDENTITY" = "-" ]; then
    cat > "$STAGING/If macOS won't open it.txt" <<'TXT'
This build of Stage One isn't notarised by Apple yet, so macOS stops the first launch
with "Stage One.app Not Opened". It isn't broken. To open it once:

1. Drag Stage One to Applications and try to open it. Press Done.
2. Open System Settings > Privacy & Security, scroll to Security, and press
   "Open Anyway" next to "Stage One.app was blocked". Confirm with your password.

Or in Terminal:
  xattr -dr com.apple.quarantine "/Applications/Stage One.app"

macOS remembers the choice after that.
TXT
fi
rm -f "$DMG"
hdiutil create -volname "Stage One" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$(dirname "$STAGING")"
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
echo "Built $DMG"
