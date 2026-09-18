#!/usr/bin/env bash
#
# list-drivers.sh — list available Gutenprint drivers and detected devices.
#
# Usage:
#   ./list-drivers.sh                # list all Gutenprint driver URIs
#   ./list-drivers.sh --devices      # list connected/discovered printers
#   ./list-drivers.sh --search "epson"

set -euo pipefail

case "${1:-}" in
  --devices)
    lpinfo -v
    ;;
  --search)
    query="${2:?Supply a search term}"
    lpinfo -m | grep -i "gutenprint" | grep -iF -- "${query}"
    ;;
  '')
    lpinfo -m | grep -i "gutenprint"
    ;;
  *)
    echo "Usage: $0 [--devices | --search text]" >&2
    exit 1
    ;;
esac
