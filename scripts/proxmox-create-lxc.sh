#!/usr/bin/env bash
# Compatibility entrypoint: all provisioning now uses the native installer.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec bash "$SCRIPT_DIR/../ct/cups-print-server.sh" "$@"