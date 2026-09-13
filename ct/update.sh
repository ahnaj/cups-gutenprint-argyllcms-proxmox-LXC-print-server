#!/usr/bin/env bash
#
# ct/update.sh
#
# Updates CUPS/Gutenprint packages inside an existing cups-print-server LXC.
# Run on the Proxmox host:
#
#   CTID=150 bash -c "$(curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/update.sh)"

set -euo pipefail

: "${CTID:?Set CTID to the container ID to update, e.g. CTID=150}"

echo "==> Updating packages in CTID ${CTID}..."
pct exec "${CTID}" -- bash -c "
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq cups cups-filters printer-driver-gutenprint printer-driver-all avahi-daemon
  systemctl restart cups
"
echo "==> Done."
