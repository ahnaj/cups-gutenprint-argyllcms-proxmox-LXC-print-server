# CUPS print server

One command on a **Proxmox VE host** creates a native Debian LXC with CUPS,
Gutenprint, the distribution's other printer drivers, Avahi discovery,
ArgyllCMS and colord. No Docker or printer-specific filters.

## Install

Run as root on the Proxmox host:

```bash
bash -c 'f=$(mktemp) || exit; trap "rm -f -- \"$f\"" EXIT; curl -fsSL https://raw.githubusercontent.com/ahnaj/cups-gutenprint-argyllcms-proxmox-LXC-print-server/main/ct/cups-print-server.sh -o "$f" && bash "$f"'
```

From a checkout, the equivalent command is:

```bash
bash ct/cups-print-server.sh
```

The installer selects a free guest ID, active storage and an existing bridge,
downloads a Debian 12 template if needed, creates an unprivileged CT, waits for
DNS, installs and checks CUPS, and prints its HTTPS URL and generated admin
password. Save the password. CUPS uses a self-signed certificate initially.

**The server is ready; a printer queue still needs your device URI and driver.**
Open **Administration → Add Printer** at the printed URL. Use the generated
Linux account to authenticate. Network printer discovery requires multicast
connectivity; entering a printer's IP/URI works across networks where discovery
is unavailable. No physical printer is required to install the server.

Prerequisites: Proxmox VE, Internet/package mirror access, an active storage pool
for root filesystems and templates, and a bridge with DHCP (or a static
`NET_CONFIG`). A failed run exits nonzero and keeps any new CT for diagnosis.
It never deletes or overwrites an existing guest. Fix or remove that failed CT
explicitly before trying again; otherwise the next run selects another free ID.

### Configuration

Prefix the install command with environment variables, or export them first:

```bash
export CTID=150 CT_HOSTNAME=printserver STORAGE=local-zfs BRIDGE=vmbr0
bash ct/cups-print-server.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `CTID` | next available | New guest ID; never an existing CT |
| `CT_HOSTNAME` | `cups-print-server` | CT hostname; replaces old `HOSTNAME`, which Bash prepopulates with the Proxmox host name |
| `STORAGE` | active rootdir pool | Prefers `local-lvm`, otherwise first active capable pool |
| `TEMPLATE_STORAGE` | active vztmpl pool | Prefers `local`, otherwise first active capable pool |
| `OS_TEMPLATE` | Debian 12 auto-detection | Full Debian 12/13 template volume ID |
| `BRIDGE` | existing bridge | Prefers `vmbr0`, otherwise first bridge |
| `NET_CONFIG` | `name=eth0,bridge=<bridge>,ip=dhcp` | Full Proxmox net0 setting; supports static IP, gateway and VLAN |
| `DISK_SIZE_GB` / `MEMORY_MB` | `4` / `768` | Disk GiB / RAM MiB |
| `CORES` / `SWAP_MB` | `1` / `512` | CPU count / swap MiB |
| `CUPS_USER` | `cupsadmin` | Non-root admin account |
| `CUPS_PASSWORD` | random 32 hex characters | Optional single-line password; quote shell metacharacters |
| `UNPRIVILEGED` | `1` | Set `0` only if privileged isolation is intended |
| `ENABLE_USB_PASSTHROUGH` | `no` | Mount the entire USB bus; see permissions below |
| `REPO_RAW_BASE` | this repo's `main` raw URL | Payload source for downloaded installs; can point to an immutable commit |

A local checkout supplies **all** installer/helper files locally. Downloaded
installs fetch the complete payload before creating a CT. To pin a release,
use the same commit in both the entrypoint URL and `REPO_RAW_BASE`.

### Existing Debian machine

For Debian 12/13 with systemd (VM, physical host or existing LXC), run as root:

```bash
bash install/cups-print-server-install.sh
```

The same download-and-run command above also works when its URL ends in
`install/cups-print-server-install.sh` instead. This installs the server;
the Proxmox entrypoint additionally copies the helper scripts into
`/usr/local/bin`. On a standalone machine use the helpers from this checkout.

Rerunning the native installer preserves an existing admin password unless
`CUPS_PASSWORD` is explicitly supplied. It preserves queues, uses `cupsctl`
to update sharing, and saves the first CUPS configuration as
`/etc/cups/cupsd.conf.before-print-server`. It does not replace Debian's
authentication policies or enable colord as a boot service (colord is
D-Bus activated).

## Add a printer

Inside the CT (`pct enter <CTID>`):

```bash
list-drivers --devices
list-drivers --search Epson
add-printer --name Office --uri socket://192.168.1.50 --driver '<exact driver URI from lpinfo -m>'
```

For a driverless IPP printer:

```bash
add-printer --name Office --uri ipp://192.168.1.50/ipp/print --driver everywhere
```

Choose Gutenprint for server-side Gutenprint rendering; choose `everywhere`
for a driverless IPP device. Driver support depends on the actual printer;
the distribution driver packages do not support every printer ever made.

On Windows, add the shared queue by URL:
`http://<server-ip>:631/printers/Office`, using the Microsoft IPP Class Driver.

## Defaults, Windows and color

Set queue defaults in **Set Default Options** or with `lpadmin -p Office -o
<option>=<value>`. Plain `lpoptions` can create per-user defaults instead.

As the reference conversation explains, **CUPS defaults do not force Windows
to omit per-job settings**. Paper size, duplex, color and quality can still
be overridden. Already-rendered scaling or color changes cannot be undone
by setting server defaults. This installer does not add universal option
enforcement, clipping repair or page offsets: those require a particular
printer/application and verified calibration.

To inspect a real Windows job, temporarily enable debugging:

```bash
cupsctl --debug-logging
# Print a small test job from Windows.
grep -E 'argv\[5\]|Started filter|CONTENT_TYPE|gutenprint|profile' /var/log/cups/error_log | tail -80
cupsctl --no-debug-logging
```

For measured profiles, use a **reflective print spectrophotometer** supported
by ArgyllCMS, such as an i1Pro. A display-only colorimeter is not suitable
for reading printed targets. Work in a separate directory per printer/media:

```bash
mkdir -p /root/color/office-matte
cd /root/color/office-matte
color-profile generate Office office-matte
color-profile print Office office-matte
color-profile read office-matte
color-profile build office-matte
color-profile install Office office-matte
```

The helper generates RGB TIFF targets, uses A4 consistently (set `PAPER=Letter`
on both generate and print to change it), prints targets with color management
disabled for that job, then registers the measured ICC profile with the real
CUPS colord device. Installation removes any persistent calibration bypass.
Keep driver/media/ink/quality settings fixed. Verify actual profile selection
in a real job's debug log; registering an ICC profile alone is not proof that
every driver/client path applies it. The chart layout defaults to an i1Pro;
other instruments may require different `printtarg` options.

## USB

Network printers need no host passthrough. USB is deliberately opt-in.
`ENABLE_USB_PASSTHROUGH=yes` exposes the host's **whole USB bus** to the CT;
it does not fix host device permissions for remapped unprivileged users.

For a selected USB printer or measuring instrument, run on the host:

```bash
bash scripts/setup-usb-instrument.sh list
bash scripts/setup-usb-instrument.sh grant <vendor:product> <CTID>
```

The existing helper installs a persistent **0666 (world-readable/writable)**
udev rule for that VID:PID and configures the bus mount. Use it only for devices
on a trusted dedicated host. All matching devices are affected. For tighter
isolation, use Proxmox's per-device passthrough and appropriate mapped
ownership instead. Restart the CT after changing passthrough; verify with
`lpinfo -v` or Argyll's `spotread -v`.

The installer does not install `ipp-usb`: it can claim a USB device that the
Gutenprint USB backend needs. Choose IPP-over-USB deliberately if that is your
printer's required interface.

## Network access and updates

CUPS listens on port 631 and permits sharing/remote administration on directly
connected networks via CUPS' native LAN rules. Administration still requires
authentication. Avahi uses UDP 5353 on the local link. Existing host, Proxmox
and guest firewalls are not changed: allow these ports from the intended LAN
if needed. Routed VLANs require explicit CUPS access rules and firewall rules;
do not expose CUPS directly to the Internet.

Update an existing CT from the host without replacing its configuration:

```bash
CTID=150 bash ct/update.sh
```

This updates installed printing/color packages, validates configuration and
checks service health. It does not upgrade the whole guest OS or reinstall
helper scripts.

## Checks

```bash
bash tests/test-install.sh
```

The non-destructive test mocks Proxmox commands and exercises local/downloaded
provisioning, password quoting, storage/template detection and failure paths.
CI also checks ShellCheck and the native install against real Debian CUPS
packages in disposable containers (with a service-manager shim).
On Linux with CUPS installed, root can also run
`bash tests/test-cups-config.sh` to validate configuration and repeatability
in private mount/network namespaces without changing the host server.
Physical printing, USB permissions,
multicast discovery from clients and Proxmox resource creation still need
verification on the target host.
