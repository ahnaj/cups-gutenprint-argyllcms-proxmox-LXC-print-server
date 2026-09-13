# cups-print-server

A one-line installer that spins up a **CUPS + Gutenprint** print server in a
Proxmox VE LXC container — no Docker, no manual steps. Styled after
[community-scripts.org](https://community-scripts.github.io/ProxmoxVE/):
run one command on the Proxmox host and get a ready-to-use print server.

## Quick start

Run this **on the Proxmox VE host shell** (as root):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/cups-print-server.sh)"
```

This will:

1. Auto-detect (or download) a Debian 12 LXC template.
2. Create an unprivileged LXC with sane defaults (1 vCPU, 768MB RAM, 4GB disk).
3. Install CUPS, the full Gutenprint driver set, and Avahi (mDNS/Bonjour
   discovery) directly inside the container — no container-in-container.
4. Create an admin user, open the CUPS web UI to the LAN, and print out the
   URL and a generated password when it's done.

Then just open `https://<container-ip>:631` and add your printer.

## Customizing the install

Every setting has a default but can be overridden with environment
variables on the same command line:

```bash
CTID=150 \
HOSTNAME=printserver \
MEMORY_MB=1024 \
STORAGE=local-lvm \
BRIDGE=vmbr0 \
CUPS_USER=admin \
CUPS_PASSWORD=supersecret \
ENABLE_USB_PASSTHROUGH=yes \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/cups-print-server.sh)"
```

| Variable | Default | Description |
|---|---|---|
| `CTID` | next free ID | Proxmox container ID |
| `HOSTNAME` | `cups-print-server` | Container hostname / CUPS server name |
| `STORAGE` | `local-lvm` | Proxmox storage pool for the rootfs |
| `TEMPLATE_STORAGE` | `local` | Storage pool holding/downloading the CT template |
| `DISK_SIZE_GB` | `4` | Root disk size |
| `MEMORY_MB` | `768` | RAM |
| `SWAP_MB` | `512` | Swap |
| `CORES` | `1` | vCPU cores |
| `BRIDGE` | `vmbr0` | Network bridge |
| `NET_CONFIG` | `name=eth0,bridge=${BRIDGE},ip=dhcp` | Full net0 string, if you need something custom (static IP, VLAN, etc.) |
| `UNPRIVILEGED` | `1` | Unprivileged container (set `0` only if you know you need privileged) |
| `ENABLE_USB_PASSTHROUGH` | `no` | Set `yes` to bind-mount `/dev/bus/usb` into the container for USB printers |
| `CUPS_USER` | `admin` | CUPS admin username |
| `CUPS_PASSWORD` | random | CUPS admin password (auto-generated and printed if unset) |

## Repo layout

```
.
├── ct/
│   ├── cups-print-server.sh   # curl|bash entrypoint — run on the Proxmox host
│   └── update.sh              # updates CUPS/Gutenprint in an existing container
├── install/
│   └── cups-print-server-install.sh   # runs inside the LXC, installs everything natively
├── scripts/
│   ├── color-profile.sh          # ArgyllCMS profiling workflow (chart → read → build → install)
│   └── setup-usb-instrument.sh   # host-side udev fix for USB colorimeter/spectro passthrough
├── misc/
│   └── build.func             # shared shell helpers (LXC creation, logging, etc.)
└── .github/workflows/lint.yml # shellcheck CI
```

Nothing here is specific to any particular Proxmox host, storage layout, or
printer model — every host-specific value is an overridable environment
variable with a generic default.

## Connecting a spectrophotometer/colorimeter

Argyll needs raw USB access to the instrument (i1Pro, i1Display, ColorMunki,
Spyder, etc). Getting this working through an **unprivileged** LXC has one
non-obvious gotcha, so here's the full procedure rather than just "pass
through the USB bus":

**The gotcha:** the USB device node (`/dev/bus/usb/BBB/DDD`) is created by
the *Proxmox host's* kernel and owned `root:root` there. An unprivileged
container's root is remapped to an unprivileged host UID (100000+), so even
after bind-mounting `/dev/bus/usb` into the container, the container's root
still can't open a node it doesn't own. `ENABLE_USB_PASSTHROUGH=yes` handles
the container-side cgroup/mount config, but the device permission itself has
to be fixed **on the host** — that's what `scripts/setup-usb-instrument.sh`
does.

**Steps:**

1. Plug the instrument into the Proxmox host and identify it:
   ```bash
   ./scripts/setup-usb-instrument.sh list
   ```
   Find your device in the `lsusb` output and note its `idVendor:idProduct`
   pair, e.g. `Bus 003 Device 004: ID 0765:5020 X-Rite, Inc.` → `0765:5020`.

2. Grant it permanent 0666 permissions via a host-side udev rule, and (if
   the container already exists) wire up passthrough in the same step:
   ```bash
   ./scripts/setup-usb-instrument.sh grant 0765:5020 150   # 150 = your CTID
   ```
   This writes `/etc/udev/rules.d/70-color-instrument.rules` on the host,
   reloads udev so it applies without unplugging, adds the
   `lxc.cgroup2.devices.allow` / `lxc.mount.entry` lines to
   `/etc/pve/lxc/150.conf` if they aren't already there, and restarts the
   container. If you already ran the main installer with
   `ENABLE_USB_PASSTHROUGH=yes`, the mount/cgroup lines already exist — this
   script just skips that part and focuses on the udev permission fix.

   If you'd rather do it by hand instead of via `pveam`-created template
   values: add these two lines to `/etc/pve/lxc/<CTID>.conf` and
   `pct stop <CTID> && pct start <CTID>`:
   ```
   lxc.cgroup2.devices.allow: c 189:* rwm
   lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
   ```

3. Verify inside the container:
   ```bash
   pct enter 150
   lsusb -d 0765:5020          # should show the instrument
   spotread -v                 # Argyll should detect and open it; Ctrl+C to exit
   ```
   If `spotread` reports "No suitable device found" or a permissions error,
   double check: the udev rule matched (`ls -l /dev/bus/usb/003/004` should
   show mode `666`), the container was actually restarted after the config
   edit, and `${CUPS_USER}` is in the `plugdev` group (the install script
   adds this automatically; `id ${CUPS_USER}` to confirm).

4. Once `spotread` sees the instrument, you're ready to run the full
   profiling workflow in `scripts/color-profile.sh` (generate → print →
   read → build → install).

**Notes:**
- Vendor IDs above (`0765` X-Rite/GretagMacbeth, `1273` Datacolor/Spyder)
  are common examples — always confirm yours with `lsusb`, don't assume.
- The udev rule persists across reboots and reconnects; you only need to run
  `grant` once per instrument, even if you move it between USB ports.
- If you pass the instrument into more than one container over time, rerun
  `grant` with the new CTID — the udev permission fix is host-wide and only
  needs doing once, but the per-container passthrough config needs adding
  to each container that uses it.

## USB printers

Set `ENABLE_USB_PASSTHROUGH=yes` when running the installer, or add these
lines to `/etc/pve/lxc/<CTID>.conf` and restart the container afterwards:

```
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
```

Network/IPP/AirPrint printers need no passthrough — CUPS discovers them over
the LAN automatically once Avahi is running.

## Adding a printer from the CLI

```bash
pct enter <CTID>
lpinfo -v                             # list detected devices
lpinfo -m | grep -i gutenprint        # find the right Gutenprint driver
lpadmin -p MyPrinter -v <device-uri> -m <driver-uri> -E
cupsenable MyPrinter && cupsaccept MyPrinter
lpadmin -p MyPrinter -o printer-is-shared=true
```

## Color management (ArgyllCMS)

The install script also sets up **ArgyllCMS** and **colord**, so you can build
and use real ICC profiles for a given printer/paper/ink combination instead
of relying on generic driver color handling.

`scripts/color-profile.sh` (run inside the LXC) walks through the full
Argyll workflow — generate a target chart, print it uncorrected, measure it
with an instrument, build the profile, and bind it to the CUPS queue:

```bash
pct enter <CTID>
cd ~/color   # or wherever you keep profiling files, one dir per printer/media

./color-profile.sh generate epson-p600 epson-p600-matte   # targen + printtarg -> chart
./color-profile.sh print    epson-p600 epson-p600-matte   # print chart, CM off
./color-profile.sh read     epson-p600-matte              # chartread with your instrument
./color-profile.sh build    epson-p600-matte               # colprof -> .icc
./color-profile.sh install  epson-p600 epson-p600-matte    # install + bind to the queue
```

This assumes a colorimeter/spectrophotometer (e.g. i1Pro, i1Display,
ColorMunki) is attached via USB passthrough (`ENABLE_USB_PASSTHROUGH=yes`).
Name profiles `<printer>-<media>` (e.g. `epson-p600-matte`,
`epson-p600-gloss`) so it's obvious which paper each one is for once you've
built a few.

Under the hood this uses Argyll's `targen`/`printtarg` (chart generation),
`chartread` (instrument reading), and `colprof` (profile building), then
registers the resulting `.icc` with `colord` and sets it as the CUPS queue's
`print-color-profile` option so it's applied automatically on print.

## Updating

```bash
CTID=<your-ctid> bash -c "$(curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/update.sh)"
```

## Security notes

- Change/rotate the CUPS admin password after first login if you let the
  script generate one.
- CUPS is only bound to the container's LAN interface; don't port-forward
  631 to the internet. Use a VPN (Tailscale/WireGuard) for remote printing.
- `ENABLE_USB_PASSTHROUGH=yes` grants the container access to the host's
  entire USB bus (`/dev/bus/usb`) — fine for a dedicated, trusted LXC, but
  worth knowing before enabling it.
