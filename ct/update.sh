#!/usr/bin/env bash
# Run on the Proxmox host with CTID=<existing container>.
set -euo pipefail
: "${CTID:?Set CTID to the container ID to update}"
[[ "$CTID" =~ ^[1-9][0-9]{2,8}$ ]] || { echo 'Invalid CTID' >&2; exit 1; }
[[ "$(id -u)" == 0 ]] && command -v pct >/dev/null || { echo 'Run as root on Proxmox VE' >&2; exit 1; }
pct exec "$CTID" -- bash -euo pipefail -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install --only-upgrade -y cups cups-bsd cups-client cups-filters \
    printer-driver-gutenprint printer-driver-all avahi-daemon avahi-utils \
    libnss-mdns usbutils argyll colord
  cupsd -t
  systemctl restart cups avahi-daemon
  systemctl is-active --quiet cups avahi-daemon
  lpstat -r
'
printf 'CT %s packages updated; queues, configuration and passwords retained.\n' "$CTID"