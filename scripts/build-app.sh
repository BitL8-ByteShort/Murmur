#!/bin/bash
set -euo pipefail
MURMUR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$MURMUR_ROOT"
swift build --product Murmur
MURMUR_BIN="$(swift build --show-bin-path)"
MURMUR_APP="$MURMUR_ROOT/build/Murmur.app"
mkdir -p "$MURMUR_APP/Contents/MacOS" "$MURMUR_APP/Contents/Resources"
cp "$MURMUR_BIN/Murmur" "$MURMUR_APP/Contents/MacOS/Murmur"
cp Resources/Info.plist "$MURMUR_APP/Contents/Info.plist"
cp Resources/Murmur.icns "$MURMUR_APP/Contents/Resources/Murmur.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$MURMUR_APP/Contents/Resources/"
for MURMUR_RESOURCE in "$MURMUR_BIN"/*.bundle; do
    [[ -d "$MURMUR_RESOURCE" ]] || continue
    ditto "$MURMUR_RESOURCE" "$MURMUR_APP/Contents/Resources/$(basename "$MURMUR_RESOURCE")"
done
# Development signature only. This is not a Developer ID or notarized release.
codesign --force --sign "${MURMUR_SIGN_IDENTITY:--}" "$MURMUR_APP"
echo "Built $MURMUR_APP"
if [[ "${1:-}" == "--run" ]]; then open "$MURMUR_APP"; fi
