#!/usr/bin/env bash
# Non-destructive orchestration regressions. Works on Linux and Git Bash.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
export ROOT TEST_DIR
fail() { echo "FAIL: $*" >&2; exit 1; }
contains() { grep -qF -- "$2" "$1" || fail "Missing $2 in $1"; }
id() { echo 0; }
pveversion() { echo pve-manager/8; }
pvesh() { [[ "${FAIL_NEXTID:-no}" != yes ]] && echo 150; }
pvesm() {
  printf 'Name Type Status Total Used Available %%\n'
  [[ "${NO_STORAGE:-no}" != yes ]] || return 0
  printf 'tank zfspool active 100 0 100 0\n'
}
ip() { echo '2: vmbr1: <BROADCAST> mtu 1500'; }
pveam() {
  printf '%s\n' "$*" >> "$TEST_DIR/templates"
  case "$1" in
    list) [[ "${DOWNLOAD_TEMPLATE:-no}" == yes ]] || echo 'tank:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst 123' ;;
    available) echo 'system debian-12-standard_12.7-1_amd64.tar.zst' ;;
  esac
  return 0
}
pct() {
  printf '%s\n' "$@" >> "$TEST_DIR/pct"
  case "$*" in
    'exec 150 -- getent hosts deb.debian.org') [[ "${FAIL_DNS:-no}" != yes ]] ;;
    'exec 150 -- hostname -I') echo '192.0.2.10' ;;
    'exec 150 -- env '*) [[ "${FAIL_INSTALL:-no}" != yes ]] ;;
    'create '*) [[ "${FAIL_CREATE:-no}" != yes ]] ;;
  esac
}
sleep() { :; }
curl() {
  local source_file='' destination=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      https://*) source_file="$ROOT/${1#https://example.invalid/}" ;;
      -o) destination="$2"; shift ;;
    esac
    shift
  done
  cp "$source_file" "$destination"
}
export -f id pveversion pvesh pvesm ip pveam pct sleep curl

for file in "$ROOT"/{ct,install,scripts,tests}/*.sh "$ROOT"/misc/*.func; do bash -n "$file"; done
unset CTID CT_HOSTNAME STORAGE TEMPLATE_STORAGE BRIDGE NET_CONFIG CUPS_PASSWORD OS_TEMPLATE
export HOSTNAME=proxmox-host ENABLE_USB_PASSTHROUGH=no
bash "$ROOT/ct/cups-print-server.sh" > "$TEST_DIR/output"
contains "$TEST_DIR/pct" cups-print-server
contains "$TEST_DIR/pct" tank:4
contains "$TEST_DIR/output" 'https://192.0.2.10:631'
grep -Eq '^Password: [a-f0-9]{32}$' "$TEST_DIR/output" || fail 'Generated password'
contains "$TEST_DIR/pct" /usr/local/bin/add-printer

# Quotes, substitutions, spaces and punctuation must arrive as literal arguments.
export CUPS_PASSWORD='quote'"'"' $() ; `command` spaces:yes'
bash "$ROOT/ct/cups-print-server.sh" > "$TEST_DIR/output"
contains "$TEST_DIR/pct" "CUPS_PASSWORD=$CUPS_PASSWORD"

# Downloaded entrypoint must fetch every file from the configured origin.
export REPO_RAW_BASE=https://example.invalid DOWNLOAD_TEMPLATE=yes
(cd "$TEST_DIR"; bash -c "$(cat "$ROOT/ct/cups-print-server.sh")") > "$TEST_DIR/output"
contains "$TEST_DIR/templates" 'download tank debian-12-standard_12.7-1_amd64.tar.zst'
unset DOWNLOAD_TEMPLATE

for failure in FAIL_NEXTID NO_STORAGE FAIL_CREATE FAIL_DNS FAIL_INSTALL; do
  : > "$TEST_DIR/pct"
  if env "$failure=yes" bash "$ROOT/ct/cups-print-server.sh" > "$TEST_DIR/output" 2>&1; then
    fail "$failure reported success"
  fi
  if grep -q 'CUPS ready' "$TEST_DIR/output"; then fail "$failure printed success"; fi
done
for setting in CTID=../10 CUPS_USER=root CT_HOSTNAME=bad/name MEMORY_MB=zero; do
  : > "$TEST_DIR/pct"
  if env "$setting" bash "$ROOT/ct/cups-print-server.sh" > "$TEST_DIR/output" 2>&1; then fail "$setting accepted"; fi
  [[ ! -s "$TEST_DIR/pct" ]] || fail 'Invalid setting created a container'
done
if CUPS_PASSWORD=$'bad\ninjected:password' bash "$ROOT/ct/cups-print-server.sh" > "$TEST_DIR/output" 2>&1; then fail 'Multiline password accepted'; fi

lpadmin() { printf '%s\n' "$@" >> "$TEST_DIR/printer"; }
cupsenable() { :; }
cupsaccept() { :; }
lpinfo() { printf 'gutenprint.5.3://epson-model Epson Test\n'; }
export -f lpadmin cupsenable cupsaccept lpinfo
bash "$ROOT/scripts/add-printer.sh" --name Test --uri socket://192.0.2.20 --driver gutenprint.5.3://epson-model > /dev/null
contains "$TEST_DIR/printer" printer-is-shared=true
if bash "$ROOT/scripts/add-printer.sh" --name > /dev/null 2>&1; then fail 'Missing argument accepted'; fi
bash "$ROOT/scripts/list-drivers.sh" --search Epson > "$TEST_DIR/drivers"
contains "$TEST_DIR/drivers" 'Epson Test'

targen() { printf '%s\n' "$*" >> "$TEST_DIR/color"; }
printtarg() { printf '%s\n' "$*" >> "$TEST_DIR/color"; touch target01.tif target02.tif; }
lp() { printf '%s\n' "$@" >> "$TEST_DIR/color"; }
export -f targen printtarg lp
(cd "$TEST_DIR"; bash "$ROOT/scripts/color-profile.sh" generate Smoke target; bash "$ROOT/scripts/color-profile.sh" print Smoke target) > /dev/null
contains "$TEST_DIR/color" '-d2'
contains "$TEST_DIR/color" '-pA4 -t'
contains "$TEST_DIR/color" media=A4
contains "$TEST_DIR/color" target01.tif
contains "$TEST_DIR/color" target02.tif

echo 'PASS: shell syntax, local/download installs, storage/template detection, passwords, failures, native helpers and RGB chart printing'
