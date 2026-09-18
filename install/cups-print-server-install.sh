#!/usr/bin/env bash
# Native install: root on Debian 12/13 with systemd, including Proxmox LXC.
set -Eeuo pipefail
die() { printf 'Error: %s\n' "$1" >&2; exit 1; }
[[ "$(id -u)" == 0 ]] || die 'Run as root.'
# shellcheck source=/dev/null
source /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" =~ ^(12|13)$ ]] || die 'Supported OS: Debian 12 or 13.'
[[ -d /run/systemd/system ]] || die 'A running systemd system is required.'

CUPS_USER="${CUPS_USER:-cupsadmin}"
SERVER_NAME="${SERVER_NAME:-$(hostname)}"
[[ "$CUPS_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$CUPS_USER" != root ]] || die 'CUPS_USER must be a non-root Linux account name.'
[[ "$SERVER_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || die 'Invalid SERVER_NAME.'
[[ "${CUPS_PASSWORD:-}" != *$'\n'* && "${CUPS_PASSWORD:-}" != *$'\r'* ]] || die 'CUPS_PASSWORD must be a single line.'
NEW_USER=no
if ! id "$CUPS_USER" >/dev/null 2>&1; then
  NEW_USER=yes
  CUPS_PASSWORD="${CUPS_PASSWORD:-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')}"
else
  [[ "$(id -u "$CUPS_USER")" -ge 1000 ]] || die 'CUPS_USER cannot be a system account.'
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y cups cups-bsd cups-client cups-filters printer-driver-gutenprint \
  printer-driver-all avahi-daemon avahi-utils libnss-mdns usbutils argyll colord

if [[ "$NEW_USER" == yes ]]; then
  useradd -m -G lpadmin -s /bin/bash "$CUPS_USER"
else
  usermod -aG lpadmin "$CUPS_USER"
fi
if [[ -n "${CUPS_PASSWORD:-}" ]]; then
  printf '%s:%s\n' "$CUPS_USER" "$CUPS_PASSWORD" | chpasswd
fi
getent group plugdev >/dev/null || groupadd plugdev
usermod -aG plugdev "$CUPS_USER"
install -d -m 755 /usr/share/color/icc/custom

# Keep Debian's authentication policies and use CUPS' native configuration API.
# Do not install ipp-usb by default: it can claim USB devices needed by Gutenprint.
systemctl enable --now avahi-daemon cups
[[ -e /etc/cups/cupsd.conf.before-print-server ]] || cp -p /etc/cups/cupsd.conf /etc/cups/cupsd.conf.before-print-server
cupsctl --remote-admin --share-printers "ServerName=$SERVER_NAME" \
  WebInterface=Yes Browsing=Yes BrowseLocalProtocols=dnssd DefaultShared=Yes
cupsd -t
systemctl restart cups
systemctl is-active --quiet cups avahi-daemon
lpstat -r
lpinfo -m | grep -i gutenprint >/dev/null || die 'Gutenprint drivers are missing.'

# Existing firewall policy belongs to the administrator; never broaden it silently.
printf '\nCUPS installed. Allow TCP 631 and UDP 5353 from your LAN if a firewall is enabled.\n'
printf 'Admin: %s\n' "$CUPS_USER"
if [[ -n "${CUPS_PASSWORD:-}" ]]; then
  printf 'Password: %s\n' "$CUPS_PASSWORD"
else
  printf 'Existing account password retained.\n'
fi
printf 'Open https://<server-ip>:631 and add a printer. Administration uses your Linux account.\n'