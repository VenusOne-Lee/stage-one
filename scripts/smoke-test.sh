#!/usr/bin/env bash
# Launch checks for a built bundle: dyld resolves Sparkle.framework, the app stays up,
# the bundled CLI runs, and the icon is in place.
#   scripts/smoke-test.sh "dist/Stage One.app"
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-dist/Stage One.app}"

test -f "$APP/Contents/Resources/AppIcon.icns"
test -d "$APP/Contents/Frameworks/Sparkle.framework"
LINKS="$(otool -L "$APP/Contents/MacOS/StageOne")"
grep -q "@rpath/Sparkle.framework" <<< "$LINKS"
"$APP/Contents/Helpers/stage" --help >/dev/null
# SO-121: the MCP server answers initialize and lists its tools without the app running.
MCP_OUT="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | "$APP/Contents/Helpers/stage" mcp)"
grep -q '"protocolVersion"' <<< "$MCP_OUT"
grep -q '"rewind_points"' <<< "$MCP_OUT"

# SO-131: the watchdog returns at once for a dead pid and removes an empty parked file.
WD="$(mktemp -d)"
echo "[]" > "$WD/parked.json"
sleep 0 & DEAD=$!; wait "$DEAD" || true
"$APP/Contents/Helpers/stage" watchdog --pid "$DEAD" --file "$WD/parked.json"
test ! -e "$WD/parked.json"
rm -rf "$WD"

"$APP/Contents/MacOS/StageOne" > /tmp/stageone-smoke.log 2>&1 &
PID=$!
sleep 6
if ! kill -0 "$PID" 2>/dev/null; then
    echo "error: Stage One exited during launch" >&2
    cat /tmp/stageone-smoke.log >&2
    exit 1
fi
kill -TERM "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
echo "Smoke test passed"
