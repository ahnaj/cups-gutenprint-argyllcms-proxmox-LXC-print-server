#!/usr/bin/env bash
#
# add-printer.sh — register a printer with CUPS non-interactively.
#
# Run this from the Docker host (it execs lpadmin inside the container),
# or inside the container directly.
#
# Usage:
#   ./add-printer.sh --name <PrinterName> --uri <device-uri> --driver <ppd-or-driver-uri> [--location "Office"] [--description "HP LaserJet"]
#
# Find the device URI with:
#   docker exec cups-print-server lpinfo -v
# Find the Gutenprint driver URI with:
#   ./scripts/list-drivers.sh

set -euo pipefail

CONTAINER="${CONTAINER:-cups-print-server}"
NAME=""
URI=""
DRIVER=""
LOCATION="Default"
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --uri) URI="$2"; shift 2 ;;
    --driver) DRIVER="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$NAME" || -z "$URI" || -z "$DRIVER" ]]; then
  echo "Usage: $0 --name <PrinterName> --uri <device-uri> --driver <driver-uri> [--location L] [--description D]" >&2
  exit 1
fi

echo "==> Registering printer '${NAME}'"
docker exec "${CONTAINER}" lpadmin \
  -p "${NAME}" \
  -v "${URI}" \
  -m "${DRIVER}" \
  -L "${LOCATION}" \
  -D "${DESCRIPTION:-$NAME}" \
  -E

echo "==> Enabling and sharing printer"
docker exec "${CONTAINER}" cupsenable "${NAME}"
docker exec "${CONTAINER}" cupsaccept "${NAME}"
docker exec "${CONTAINER}" lpadmin -p "${NAME}" -o printer-is-shared=true

echo "==> Done. Printer '${NAME}' is ready."
