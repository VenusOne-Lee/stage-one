#!/usr/bin/env bash
# SO-072: SwiftPM doesn't run Xcode's App Intents metadata step, and without
# Contents/Resources/Metadata.appintents macOS won't list Stage One's Focus filter or intents.
# This rebuilds the app module once with Swift const-value extraction and runs
# `appintentsmetadataprocessor` the way Xcode does. Best effort: it never fails the build,
# and says so loudly when it can't produce the metadata.
#   scripts/appintents-metadata.sh "dist/Stage One.app"
set -uo pipefail
cd "$(dirname "$0")/.."
APP="$1"
OUT="$APP/Contents/Resources"
WORK=".build/appintents"
mkdir -p "$WORK"

warn() { echo "warning: App Intents metadata not generated: $*" >&2; exit 0; }

xcrun -f appintentsmetadataprocessor >/dev/null 2>&1 || warn "appintentsmetadataprocessor not found (needs Xcode)"

cat > "$WORK/protocols.json" <<'JSON'
["AppIntent","EntityQuery","AppEntity","TransientEntity","AppEnum","AppShortcutProviding","AppShortcutsProvider","AnyResolverProviding","AppIntentsPackage","DynamicOptionsProvider","SetFocusFilterIntent"]
JSON

HOST_ARCH="$(uname -m)"
swift build -c release --arch "$HOST_ARCH" --product StageOne --scratch-path "$WORK/build" \
    -Xswiftc -emit-const-values \
    -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file -Xswiftc -Xfrontend -Xswiftc "$PWD/$WORK/protocols.json" \
    || warn "const-value build failed"

find "$WORK/build" -name "*.swiftconstvalues" -path "*StageOneApp*" > "$WORK/constvals.txt"
[ -s "$WORK/constvals.txt" ] || warn "no .swiftconstvalues files were emitted"
find "$PWD/Sources/StageOneApp" -name "*.swift" > "$WORK/sources.txt"
BIN="$(find "$WORK/build" -path "*release/StageOne" -type f | head -1)"
[ -n "$BIN" ] || warn "const-value build produced no binary"

TOOLCHAIN="$(dirname "$(dirname "$(dirname "$(xcrun -f swiftc)")")")"
XCODE_VERSION="$(xcodebuild -version 2>/dev/null | awk 'NR==2 {print $3}')"
xcrun appintentsmetadataprocessor \
    --toolchain-dir "$TOOLCHAIN" \
    --module-name StageOneApp \
    --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
    --xcode-version "${XCODE_VERSION:-16A000}" \
    --platform-family macOS \
    --deployment-target 15.0 \
    --bundle-identifier africa.venusone.StageOne \
    --output "$OUT" \
    --target-triple "$HOST_ARCH-apple-macos15.0" \
    --binary-file "$BIN" \
    --dependency-file "$WORK/StageOne.d" \
    --stringsdata-file "$WORK/ExtractedAppShortcutsMetadata.stringsdata" \
    --source-file-list "$WORK/sources.txt" \
    --swift-const-vals-list "$WORK/constvals.txt" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --no-app-shortcuts-localization \
    || warn "appintentsmetadataprocessor failed"

if [ -d "$OUT/Metadata.appintents" ]; then
    echo "App Intents metadata: $(ls "$OUT/Metadata.appintents" | tr '\n' ' ')"
    grep -o '"StageOneFocusFilter"' -r "$OUT/Metadata.appintents" | head -1 || echo "warning: Focus filter missing from metadata" >&2
else
    warn "processor ran but wrote no Metadata.appintents"
fi
