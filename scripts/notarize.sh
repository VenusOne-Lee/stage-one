#!/usr/bin/env bash
# Notarises an .app or .dmg with notarytool and staples the ticket.
#   APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_PASSWORD=... scripts/notarize.sh "dist/Stage One.app"
set -euo pipefail
TARGET="$1"
: "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_PASSWORD:?}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [[ "$TARGET" == *.app ]]; then
    SUBMIT="$WORK/$(basename "$TARGET" .app).zip"
    ditto -c -k --keepParent "$TARGET" "$SUBMIT"
else
    SUBMIT="$TARGET"
fi

auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
echo "Submitting $(basename "$TARGET") for notarisation"
xcrun notarytool submit "$SUBMIT" "${auth[@]}" --wait --timeout 30m --output-format json | tee "$WORK/result.json"
STATUS="$(/usr/bin/plutil -extract status raw -o - "$WORK/result.json" 2>/dev/null || echo unknown)"
ID="$(/usr/bin/plutil -extract id raw -o - "$WORK/result.json" 2>/dev/null || echo "")"
if [ "$STATUS" != "Accepted" ]; then
    echo "error: notarisation finished with status '$STATUS'" >&2
    if [ -n "$ID" ]; then xcrun notarytool log "$ID" "${auth[@]}" >&2 || true; fi
    exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "Notarised and stapled $TARGET"
