#!/bin/bash
set -euo pipefail
MURMUR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$MURMUR_ROOT"
swift script/app_process.swift stop "$MURMUR_ROOT/build/Murmur.app" /Applications/Murmur.app
# Stable development signing retains the app's identity between local updates.
export MURMUR_SIGN_IDENTITY="${MURMUR_SIGN_IDENTITY:-Apple Development: Christopher Wong (GY2PE6XF2L)}"
./scripts/build-app.sh
if [[ -d /Applications/Murmur.app ]]; then
    # A new signing layout must not inherit obsolete resources from the old app.
    MURMUR_PREVIOUS=$(mktemp -d "$MURMUR_ROOT/build/previous-install.XXXXXX")
    mv /Applications/Murmur.app "$MURMUR_PREVIOUS/Murmur.app"
fi
ditto "$MURMUR_ROOT/build/Murmur.app" /Applications/Murmur.app
codesign --verify --deep --strict /Applications/Murmur.app
open /Applications/Murmur.app
sleep 1
swift script/app_process.swift verify /Applications/Murmur.app "$MURMUR_ROOT/build/Murmur.app"
