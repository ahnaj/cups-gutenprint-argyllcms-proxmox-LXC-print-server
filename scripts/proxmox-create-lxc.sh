#!/usr/bin/env bash
#
# proxmox-create-lxc.sh
#
# Provisions an unprivileged LXC container on a Proxmox VE node, sized for
# running the cups-print-server Docker stack. Run this ON THE PROXMOX HOST
# (as root, in the Proxmox shell), not inside the container.
#
# Usage:
#   ./proxmox-create-lxc.sh
#
# All values below are placeholders — edit them (or export as env vars
# before running) for your environment. Nothing here is specific to any
# particular install; fill in your own storage pool, bridge, and template.

set -euo pipefail

# ---- Configurable parameters -------------------------------------------
CTID="${CTID:-900}"                          # pick an unused container ID
HOSTNAME="${HOSTNAME:-cups-print-server}"
STORAGE="${STORAGE:-local-lvm}"              # your Proxmox storage pool
TEMPLATE="${TEMPLATE:-local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst}"
BRIDGE="${BRIDGE:-vmbr0}"
DISK_SIZE_GB="${DISK_SIZE_GB:-4}"
MEMORY_MB="${MEMORY_MB:-1024}"
SWAP_MB="${SWAP_MB:-512}"
CORES="${CORES:-1}"
NET_CONFIG="${NET_CONFIG:-name=eth0,bridge=${BRIDGE},ip=dhcp}"
# ---------------------------------------------------------------------

echo "==> Creating unprivileged LXC ${CTID} (${HOSTNAME})"
pct create "${CTID}" "${TEMPLATE}" \
  --hostname "${HOSTNAME}" \
  --storage "${STORAGE}" \
  --rootfs "${STORAGE}:${DISK_SIZE_GB}" \
  --memory "${MEMORY_MB}" \
  --swap "${SWAP_MB}" \
  --cores "${CORES}" \
  --net0 "${NET_CONFIG}" \
  --unprivileged 1 \
  --features nesting=1,keyctl=1 \
  --onboot 1

echo "==> Starting container"
pct start "${CTID}"
sleep 5

echo "==> Installing Docker inside the container"
pct exec "${CTID}" -- bash -c "
  set -e
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo \
    'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable' \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
"

cat <<EOF

==> Container ${CTID} (${HOSTNAME}) is ready with Docker installed.

Next steps:
  pct enter ${CTID}
  git clone <this-repo-url>
  cd cups-print-server
  cp .env.example .env   # edit as needed
  docker compose up -d --build

--- USB printer passthrough (optional) ---
If you're attaching a USB printer directly (rather than a network printer),
run the following ON THE PROXMOX HOST after identifying the device with
'lsusb', then add a matching entry to the container config
(/etc/pve/lxc/${CTID}.conf):

  lxc.cgroup2.devices.allow: c 189:* rwm
  lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir

Then restart the container:
  pct stop ${CTID} && pct start ${CTID}

EOF
