#!/usr/bin/env bash
#
# scripts/setup-usb-instrument.sh
#
# Run this ON THE PROXMOX HOST (not inside the container). It solves the
# part that ENABLE_USB_PASSTHROUGH=yes alone does NOT solve: device node
# permissions.
#
# Why this is needed:
#   USB device nodes (/dev/bus/usb/BBB/DDD) physically enumerate against the
#   Proxmox host's kernel, not the container's. Bind-mounting them into an
#   LXC (see misc/build.func) makes the node visible inside the container,
#   but an UNPRIVILEGED container's root is mapped to an unprivileged host
#   UID (typically 100000+), which does NOT have permission to open a device
#   node that's owned root:root mode 0660 on the host. Nothing inside the
#   container can fix this — the permission has to be granted on the host,
#   because that's where the device node's ownership actually lives.
#
#   The standard fix is a host-side udev rule that matches the instrument's
#   USB vendor:product ID and sets it to mode 0666 as soon as it's plugged
#   in — before it ever gets bind-mounted into the container.
#
# What this script does:
#   1. Lists connected USB devices so you can identify your instrument.
#   2. Writes a udev rule for that vendor:product ID to
#      /etc/udev/rules.d/70-color-instrument.rules on the HOST.
#   3. Reloads udev rules and re-triggers so the fix applies immediately
#      without unplugging the device.
#   4. Prints the exact CTID config lines needed (same as
#      ENABLE_USB_PASSTHROUGH=yes produces) in case you're adding
#      passthrough to an already-created container.
#
# Usage:
#   ./setup-usb-instrument.sh list                # show connected USB devices
#   ./setup-usb-instrument.sh grant <vendor:product> [ctid]
#     e.g. ./setup-usb-instrument.sh grant 0765:5020 150
#
# Common instrument vendor IDs (verify yours with `list` — don't assume):
#   0765  X-Rite / GretagMacbeth   (i1Pro, i1Display, i1iSis, ColorMunki)
#   1273  Datacolor                (Spyder series)

set -euo pipefail

RULES_FILE=/etc/udev/rules.d/70-color-instrument.rules

case "${1:-}" in

  list)
    echo "==> Connected USB devices (look for your colorimeter/spectrophotometer):"
    lsusb
    echo
    echo "Identify the 'idVendor:idProduct' pair, e.g. '0765:5020', then run:"
    echo "  $0 grant 0765:5020 <ctid>"
    ;;

  grant)
    VIDPID="${2:?usage: $0 grant <vendor:product> [ctid]}"
    CTID="${3:-}"
    VID="${VIDPID%%:*}"
    PID="${VIDPID##*:}"

    [[ "$VID" =~ ^[0-9a-fA-F]{4}$ && "$PID" =~ ^[0-9a-fA-F]{4}$ ]] \
      || { echo "Expected format vendor:product, e.g. 0765:5020" >&2; exit 1; }

    echo "==> Confirming device is currently visible on the host..."
    if ! lsusb -d "${VID}:${PID}" >/dev/null 2>&1; then
      echo "Warning: no device with ID ${VID}:${PID} is currently attached." >&2
      echo "Continuing anyway — the rule will apply next time it's plugged in." >&2
    fi

    echo "==> Writing udev rule to ${RULES_FILE}"
    RULE_LINE="SUBSYSTEM==\"usb\", ATTR{idVendor}==\"${VID}\", ATTR{idProduct}==\"${PID}\", MODE=\"0666\", GROUP=\"plugdev\""
    touch "$RULES_FILE"
    if ! grep -qF "idVendor}==\"${VID}\", ATTR{idProduct}==\"${PID}\"" "$RULES_FILE" 2>/dev/null; then
      echo "$RULE_LINE" >> "$RULES_FILE"
    fi

    echo "==> Reloading udev rules"
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=usb

    DEVNODE=$(lsusb -d "${VID}:${PID}" 2>/dev/null | sed -n 's/Bus \([0-9]*\) Device \([0-9]*\).*/\/dev\/bus\/usb\/\1\/\2/p')
    if [[ -n "$DEVNODE" ]]; then
      echo "==> Current permissions on ${DEVNODE}:"
      ls -l "$DEVNODE"
    fi

    if [[ -n "$CTID" ]]; then
      CONF="/etc/pve/lxc/${CTID}.conf"
      if ! grep -q "lxc.cgroup2.devices.allow: c 189" "$CONF" 2>/dev/null; then
        echo "==> Adding USB bus passthrough to CTID ${CTID} config"
        {
          echo "lxc.cgroup2.devices.allow: c 189:* rwm"
          echo "lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir"
        } >> "$CONF"
        echo "==> Restarting CTID ${CTID} to apply"
        pct stop "${CTID}" && pct start "${CTID}"
      else
        echo "==> CTID ${CTID} already has USB bus passthrough configured."
      fi
    else
      echo
      echo "No CTID given — add these lines to /etc/pve/lxc/<CTID>.conf yourself,"
      echo "then 'pct stop <CTID> && pct start <CTID>':"
      echo "  lxc.cgroup2.devices.allow: c 189:* rwm"
      echo "  lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir"
    fi

    echo
    echo "==> Done. Inside the container, verify with:"
    echo "    lsusb -d ${VID}:${PID}"
    echo "    spotread -v          # Argyll should detect and open the instrument"
    ;;

  *)
    cat <<EOF
Usage: $0 <list|grant> [args]

  list                          Show connected USB devices to identify your instrument
  grant <vendor:product> [ctid] Grant 0666 permission via udev rule, optionally
                                 wiring up passthrough for the given CTID

Example:
  $0 list
  $0 grant 0765:5020 150
EOF
    exit 1
    ;;
esac
