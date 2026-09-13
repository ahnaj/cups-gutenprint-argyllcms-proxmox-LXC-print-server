#!/bin/bash
set -euo pipefail

: "${CUPS_USER:=admin}"
: "${CUPS_PASSWORD:=changeme}"
: "${CUPS_ADMIN_EMAIL:=admin@example.local}"
: "${SERVER_NAME:=cups-print-server}"

echo "[entrypoint] Rendering CUPS configuration..."
export CUPS_USER CUPS_PASSWORD SERVER_NAME
envsubst < /etc/cups/cupsd.conf.template > /etc/cups/cupsd.conf
envsubst < /etc/cups/cups-files.conf.template > /etc/cups/cups-files.conf

# Create the admin user if it doesn't already exist, and add to lpadmin group
if ! id "$CUPS_USER" &>/dev/null; then
    echo "[entrypoint] Creating CUPS admin user '$CUPS_USER'..."
    useradd -m -G lpadmin -s /usr/sbin/nologin "$CUPS_USER"
    echo "${CUPS_USER}:${CUPS_PASSWORD}" | chpasswd
else
    usermod -aG lpadmin "$CUPS_USER" || true
fi

mkdir -p /var/run/dbus
rm -f /var/run/dbus/pid

echo "[entrypoint] Starting D-Bus, Avahi, and CUPS via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
