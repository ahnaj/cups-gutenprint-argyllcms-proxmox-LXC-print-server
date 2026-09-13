#!/usr/bin/env bash
#
# list-drivers.sh — list available Gutenprint drivers and detected devices.
#
# Usage:
#   ./list-drivers.sh                # list all Gutenprint driver URIs
#   ./list-drivers.sh --devices      # list connected/discovered printers
#   ./list-drivers.sh --search "epson"

set -euo pipefail

CONTAINER="${CONTAINER:-cups-print-server}"

case "${1:-}" in
  --devices)
    docker exec "${CONTAINER}" lpinfo -v
    ;;
  --search)
    query="${2:-}"
    docker exec "${CONTAINER}" lpinfo -m | grep -i "gutenprint" | grep -i "${query}"
    ;;
  *)
    docker exec "${CONTAINER}" lpinfo -m | grep -i "gutenprint"
    ;;
esac
