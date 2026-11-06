#!/usr/bin/env bash
# SO-092: zips integrations/alfred/workflow into "Stage One.alfredworkflow".
#   scripts/make-alfred.sh <output-dir>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT_DIR="${1:-dist}"
mkdir -p "$OUT_DIR"
OUT="$(cd "$OUT_DIR" && pwd)/Stage One.alfredworkflow"
rm -f "$OUT"
plutil -lint integrations/alfred/workflow/info.plist >/dev/null 2>&1 || python3 -c "import plistlib,sys;plistlib.load(open('integrations/alfred/workflow/info.plist','rb'))"
(cd integrations/alfred/workflow && zip -qrX "$OUT" info.plist filter.js run.sh)
echo "Built $OUT"
