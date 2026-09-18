#!/usr/bin/env bash
# Destructive only inside a disposable Debian container; never run on a real host.
# CUPS/Avahi/packages are real. A service-manager shim replaces Docker's missing PID 1.
set -euo pipefail
[[ -f /.dockerenv ]] || { echo 'Run only inside a disposable Docker container.' >&2; exit 1; }
cd /repo
export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
apt-get update
apt-get install -y systemd dbus curl procps
mkdir -p /run/dbus /run/systemd/system
dbus-daemon --system --fork
cat > /usr/local/bin/systemctl <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  enable)
    pgrep -x avahi-daemon >/dev/null || avahi-daemon --daemonize --no-drop-root
    pgrep -x cupsd >/dev/null || /usr/sbin/cupsd
    ;;
  restart)
    pkill -x cupsd || true
    for attempt in {1..50}; do
      pgrep -x cupsd >/dev/null || break
      sleep .1
    done
    /usr/sbin/cupsd
    ;;
  is-active)
    pgrep -x cupsd >/dev/null
    pgrep -x avahi-daemon >/dev/null
    ;;
esac
SH
chmod +x /usr/local/bin/systemctl
export CUPS_USER=smoketest CUPS_PASSWORD="quoted' password:with punctuation"
bash install/cups-print-server-install.sh
original_password=$(getent shadow "$CUPS_USER" | cut -d: -f2)
cp /etc/cups/cupsd.conf.before-print-server /tmp/original-cupsd.conf
driver=$(lpinfo -m | awk 'tolower($0) ~ /gutenprint/ && !found {print $1; found=1}')
bash scripts/add-printer.sh --name Smoke --uri socket://192.0.2.20 --driver "$driver"
lpstat -p Smoke
# Verify the real HTTP interface and protected configuration endpoint.
curl --fail --silent http://localhost:631/ > /dev/null
code=$(curl --silent --output /dev/null --write-out '%{http_code}' http://localhost:631/admin/conf/cupsd.conf)
[[ "$code" == 401 || "$code" == 403 || "$code" == 426 ]]
curl --fail --silent --insecure --user "$CUPS_USER:$CUPS_PASSWORD" \
  https://localhost:631/admin/conf/cupsd.conf > /tmp/authenticated.conf
grep -q 'Require user @SYSTEM' /tmp/authenticated.conf
grep -q 'Browsing Yes' /tmp/authenticated.conf
grep -q 'BrowseLocalProtocols dnssd' /tmp/authenticated.conf
grep -q 'Allow @LOCAL' /tmp/authenticated.conf

unset CUPS_PASSWORD
bash install/cups-print-server-install.sh
[[ "$(getent shadow "$CUPS_USER" | cut -d: -f2)" == "$original_password" ]]
cmp /tmp/original-cupsd.conf /etc/cups/cupsd.conf.before-print-server
lpstat -p Smoke
[[ $(grep -c '^ServerName ' /etc/cups/cupsd.conf) == 1 ]]
cupsd -t
echo 'PASS: real Debian packages, Gutenprint queue, HTTP/TLS authentication and repeat install'
