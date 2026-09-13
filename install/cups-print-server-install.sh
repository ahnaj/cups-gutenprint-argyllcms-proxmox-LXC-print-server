#!/usr/bin/env bash
#
# install/cups-print-server-install.sh
#
# Runs INSIDE the LXC container. Installs CUPS, Gutenprint drivers, and
# Avahi for mDNS/Bonjour discovery, then configures remote administration.
#
# Env vars (all optional):
#   CUPS_USER      - admin username to create (default: admin)
#   CUPS_PASSWORD  - admin password (default: randomly generated)
#   HOSTNAME       - server name CUPS advertises (default: current hostname)

set -euo pipefail

CUPS_USER="${CUPS_USER:-admin}"
CUPS_PASSWORD="${CUPS_PASSWORD:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)}"
SERVER_NAME="${HOSTNAME:-$(hostname)}"

echo "==> Updating apt and installing CUPS, Gutenprint, and Avahi..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  cups \
  cups-bsd \
  cups-client \
  cups-filters \
  printer-driver-gutenprint \
  printer-driver-all \
  avahi-daemon \
  avahi-utils \
  libnss-mdns \
  ipp-usb \
  whois \
  usbutils \
  argyll \
  colord \
  colord-data

echo "==> Creating admin user '${CUPS_USER}' in the lpadmin group..."
if ! id "${CUPS_USER}" &>/dev/null; then
  useradd -m -G lpadmin -s /bin/bash "${CUPS_USER}"
else
  usermod -aG lpadmin "${CUPS_USER}"
fi
echo "${CUPS_USER}:${CUPS_PASSWORD}" | chpasswd

echo "==> Adding '${CUPS_USER}' to plugdev (needed for USB colorimeter/spectrophotometer access)..."
getent group plugdev >/dev/null || groupadd plugdev
usermod -aG plugdev "${CUPS_USER}"

echo "==> Configuring cupsd for LAN/remote administration..."
CUPSD_CONF=/etc/cups/cupsd.conf
cp "${CUPSD_CONF}" "${CUPSD_CONF}.bak"

# Listen on all interfaces, not just localhost
sed -i 's/^Listen localhost:631/Port 631/' "${CUPSD_CONF}"
grep -q '^Port 631' "${CUPSD_CONF}" || echo "Port 631" >> "${CUPSD_CONF}"

# Allow access from the LAN and enable the web interface
python3 - "$CUPSD_CONF" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path) as f:
    conf = f.read()

# Ensure <Location /> and <Location /admin> allow LAN access
conf = re.sub(
    r"<Location />\s*.*?</Location>",
    "<Location />\n  Order allow,deny\n  Allow all\n</Location>",
    conf, flags=re.S
)
conf = re.sub(
    r"<Location /admin>\s*.*?</Location>",
    "<Location /admin>\n  Order allow,deny\n  Allow all\n</Location>",
    conf, flags=re.S
)
if "WebInterface" not in conf:
    conf += "\nWebInterface Yes\n"
else:
    conf = re.sub(r"WebInterface\s+\w+", "WebInterface Yes", conf)

if "Browsing" not in conf:
    conf += "\nBrowsing Yes\nBrowseLocalProtocols dnssd\n"

with open(path, "w") as f:
    f.write(conf)
PYEOF

echo "ServerName ${SERVER_NAME}" >> "${CUPSD_CONF}"

echo "==> Setting up ICC profile storage..."
mkdir -p /usr/share/color/icc/custom
chmod 755 /usr/share/color/icc/custom

echo "==> Enabling and starting services..."
systemctl enable --now avahi-daemon
systemctl enable --now colord
systemctl enable --now cups
systemctl restart cups

echo "==> Opening firewall (if ufw is active)..."
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow 631/tcp
  ufw allow 5353/udp
fi

IP_ADDR="$(hostname -I | awk '{print $1}')"

cat <<EOF

==> cups-print-server install complete.

  Web UI:     https://${IP_ADDR}:631
  Admin user: ${CUPS_USER}
  Password:   ${CUPS_PASSWORD}

Add a printer via the web UI (Administration -> Add Printer), or from the
CLI with lpadmin, e.g.:

  lpinfo -v                                    # list detected devices
  lpinfo -m | grep -i gutenprint                # list Gutenprint drivers
  lpadmin -p MyPrinter -v <device-uri> -m <driver-uri> -E
  cupsenable MyPrinter && cupsaccept MyPrinter
  lpadmin -p MyPrinter -o printer-is-shared=true

ArgyllCMS is installed for building custom ICC profiles (targen, printtarg,
chartread, colprof). See scripts/color-profile.sh in the repo for the full
profiling workflow and how to attach the resulting profile to a printer.

EOF
