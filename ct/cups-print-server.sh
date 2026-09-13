#!/usr/bin/env bash
#
# cups-print-server.sh
#
# One-liner installer for a CUPS + Gutenprint print server LXC on Proxmox VE.
# Style modeled on community-scripts.org: run directly on the Proxmox host
# via curl | bash, no cloning required.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/cups-print-server.sh)"
#
# Configuration is via environment variables (all optional — sensible
# defaults are used otherwise). Example:
#
#   CTID=150 HOSTNAME=printserver MEMORY_MB=1024 ENABLE_USB_PASSTHROUGH=yes \
#     bash -c "$(curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/cups-print-server.sh)"
#
set -euo pipefail

REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main}"

# Load shared functions. If running via curl|bash there's no local misc/
# directory, so fetch it too; if run from a cloned repo, use the local copy.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd -P || true)"
if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/../misc/build.func" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/../misc/build.func"
else
  TMP_FUNC="$(mktemp)"
  curl -fsSL "${REPO_RAW_BASE}/misc/build.func" -o "$TMP_FUNC"
  # shellcheck source=/dev/null
  source "$TMP_FUNC"
fi

check_root
check_pve
set_defaults
INSTALL_SCRIPT_URL="${REPO_RAW_BASE}/install/cups-print-server-install.sh"

echo "== cups-print-server: Proxmox LXC installer =="
echo "  CTID:        ${CTID}"
echo "  Hostname:    ${HOSTNAME}"
echo "  Storage:     ${STORAGE}"
echo "  Disk:        ${DISK_SIZE_GB}G   Memory: ${MEMORY_MB}M   Cores: ${CORES}"
echo "  Network:     ${NET_CONFIG}"
echo "  USB passthrough: ${ENABLE_USB_PASSTHROUGH}"
echo

ensure_template
create_container

# Pass CUPS admin credentials through to the in-container install script
CUPS_USER="${CUPS_USER:-admin}"
CUPS_PASSWORD="${CUPS_PASSWORD:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)}"

msg_info "Fetching install script into the container..."
pct exec "${CTID}" -- bash -c "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1"
pct exec "${CTID}" -- bash -c "curl -fsSL '${INSTALL_SCRIPT_URL}' -o /root/cups-print-server-install.sh"
pct exec "${CTID}" -- bash -c "CUPS_USER='${CUPS_USER}' CUPS_PASSWORD='${CUPS_PASSWORD}' HOSTNAME='${HOSTNAME}' bash /root/cups-print-server-install.sh"

print_summary
echo -e "   ${CL_CYAN}Admin password:${CL_RESET} ${CUPS_PASSWORD}"
echo
msg_warn "Save that password now — it is not stored anywhere by this script."
