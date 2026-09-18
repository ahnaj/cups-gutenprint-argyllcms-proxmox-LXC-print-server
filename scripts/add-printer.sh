#!/usr/bin/env bash
#
# add-printer.sh — register a printer with CUPS non-interactively.
#
# Run inside the CUPS server (pct enter <CTID>).
#
# Usage:
#   ./add-printer.sh --name <PrinterName> --uri <device-uri> --driver <ppd-or-driver-uri> [--location "Office"] [--description "HP LaserJet"]
#
# Find the device URI with:
#   lpinfo -v
# Find the Gutenprint driver URI with:
#   ./scripts/list-drivers.sh

set -euo pipefail

NAME=""
URI=""
DRIVER=""
LOCATION="Default"
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" ]] || { echo "Missing value for $1" >&2; exit 1; }
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
[[ "$NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Invalid queue name' >&2; exit 1; }
[[ "$URI" =~ ^(ipp|ipps|socket|lpd|usb|dnssd):// ]] || { echo 'Unsupported printer URI' >&2; exit 1; }

echo "==> Registering printer '${NAME}'"
lpadmin \
  -p "${NAME}" \
  -v "${URI}" \
  -m "${DRIVER}" \
  -L "${LOCATION}" \
  -D "${DESCRIPTION:-$NAME}" \
  -E

echo "==> Enabling and sharing printer"
cupsenable "${NAME}"
cupsaccept "${NAME}"
lpadmin -p "${NAME}" -o printer-is-shared=true

echo "==> Done. Printer '${NAME}' is ready."
