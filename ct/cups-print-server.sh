#!/usr/bin/env bash
# Run as root on Proxmox VE; configuration is via environment variables.
set -Eeuo pipefail

REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT
trap 'printf "Install failed at line %s. Any created CT %s is retained for diagnosis; no existing CT is overwritten.\n" "$LINENO" "${CTID:-unknown}" >&2' ERR
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"

# Fetch the entire payload before creating a CT. A local checkout stays local.
for file in misc/build.func install/cups-print-server-install.sh scripts/add-printer.sh scripts/list-drivers.sh scripts/color-profile.sh; do
  mkdir -p "$WORK_DIR/$(dirname "$file")"
  if [[ -f "$SCRIPT_DIR/../$file" ]]; then
    cp "$SCRIPT_DIR/../$file" "$WORK_DIR/$file"
  else
    curl --fail --silent --show-error --location --retry 3 "$REPO_RAW_BASE/$file" -o "$WORK_DIR/$file"
  fi
done
# shellcheck source=/dev/null
source "$WORK_DIR/misc/build.func"
check_root
check_pve
set_defaults
validate_settings

printf 'Creating CT %s (%s): %s GiB on %s, network %s\n' "$CTID" "$CT_HOSTNAME" "$DISK_SIZE_GB" "$STORAGE" "$NET_CONFIG"
ensure_template
create_container

pct push "$CTID" "$WORK_DIR/install/cups-print-server-install.sh" /root/cups-print-server-install.sh
# Pass values as arguments, never interpolate them into shell source.
pct exec "$CTID" -- env "CUPS_USER=$CUPS_USER" "CUPS_PASSWORD=$CUPS_PASSWORD" \
  "SERVER_NAME=$CT_HOSTNAME" bash /root/cups-print-server-install.sh
for helper in add-printer list-drivers color-profile; do
  pct push "$CTID" "$WORK_DIR/scripts/$helper.sh" "/usr/local/bin/$helper" --perms 0755
done
print_summary