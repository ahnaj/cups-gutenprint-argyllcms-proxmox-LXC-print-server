FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="cups-print-server" \
      org.opencontainers.image.description="CUPS + Gutenprint print server with mDNS/Bonjour discovery"

ENV DEBIAN_FRONTEND=noninteractive \
    CUPS_USER=admin \
    CUPS_PASSWORD=changeme \
    TZ=Etc/UTC

# Core CUPS, Gutenprint drivers, mDNS advertisement, and USB/IPP backends
RUN apt-get update && apt-get install -y --no-install-recommends \
        cups \
        cups-bsd \
        cups-client \
        cups-filters \
        printer-driver-gutenprint \
        printer-driver-all \
        avahi-daemon \
        avahi-utils \
        libnss-mdns \
        dbus \
        whois \
        usbutils \
        ipp-usb \
        supervisor \
        gettext-base \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# Allow remote administration and LAN access (final values templated at runtime)
COPY config/cupsd.conf.template /etc/cups/cupsd.conf.template
COPY config/cups-files.conf.template /etc/cups/cups-files.conf.template

COPY docker/entrypoint.sh /entrypoint.sh
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /entrypoint.sh

EXPOSE 631/tcp
# Avahi mDNS
EXPOSE 5353/udp

VOLUME ["/etc/cups", "/var/log/cups", "/var/spool/cups"]

ENTRYPOINT ["/entrypoint.sh"]
