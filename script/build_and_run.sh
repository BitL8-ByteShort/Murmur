#!/bin/bash
set -euo pipefail
MURMUR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MURMUR_MODE="${1:-run}"
case "$MURMUR_MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
cd "$MURMUR_ROOT"
swift script/app_process.swift stop "$MURMUR_ROOT/build/Murmur.app" /Applications/Murmur.app
# Use the same stable development identity as the installed app.
export MURMUR_SIGN_IDENTITY="${MURMUR_SIGN_IDENTITY:-Apple Development: Christopher Wong (GY2PE6XF2L)}"
./scripts/build-app.sh
MURMUR_APP="$MURMUR_ROOT/build/Murmur.app"
if [[ "$MURMUR_MODE" == --debug ]]; then exec lldb -- "$MURMUR_APP/Contents/MacOS/Murmur"; fi
open -n "$MURMUR_APP"
case "$MURMUR_MODE" in
  --verify) sleep 1; swift script/app_process.swift verify "$MURMUR_APP" /Applications/Murmur.app ;;
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "Murmur"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.saltypanda.murmur.dev"' ;;
esac
