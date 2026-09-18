#!/usr/bin/env bash
# Validate cupsctl changes against a real CUPS daemon without touching host config.
# Requires root, CUPS and Linux network namespaces.
set -euo pipefail
if [[ "${1:-}" != --isolated ]]; then
  exec unshare --mount --net bash "$0" --isolated
fi
mount --make-rprivate /
mount -t tmpfs tmpfs /run
mkdir /run/cups
WORK=$(mktemp -d)
PID=''
trap '[[ -z "$PID" ]] || { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }; rm -rf -- "$WORK"' EXIT
chmod 755 "$WORK"
mkdir "$WORK"/{spool,cache,state,tmp}
BASE_CONFIG=/usr/share/cups/cupsd.conf.default
[[ -f "$BASE_CONFIG" ]] || BASE_CONFIG=/etc/cups/cupsd.conf
sed '/^[[:space:]]*Listen /d; s/^LogLevel .*/LogLevel warn/' "$BASE_CONFIG" > "$WORK/cupsd.conf"
printf '\nListen /run/cups/cups.sock\n' >> "$WORK/cupsd.conf"
cat > "$WORK/cups-files.conf" <<EOF
User lp
Group lp
SystemGroup root
ServerRoot $WORK
RequestRoot $WORK/spool
CacheDir $WORK/cache
StateDir $WORK/state
TempDir $WORK/tmp
AccessLog $WORK/access_log
ErrorLog $WORK/error_log
PageLog $WORK/page_log
EOF
cupsd -f -c "$WORK/cupsd.conf" -s "$WORK/cups-files.conf" &
PID=$!
export CUPS_SERVER=/run/cups/cups.sock CUPS_STATEDIR="$WORK/state"
for ((attempt=0; attempt<50; attempt++)); do
  [[ ! -S "$CUPS_SERVER" ]] || break
  sleep .1
done
[[ -S "$CUPS_SERVER" ]] || { tail -20 "$WORK/error_log"; exit 1; }
cupsctl --remote-admin --share-printers ServerName=print-test \
  WebInterface=Yes Browsing=Yes BrowseLocalProtocols=dnssd DefaultShared=Yes
sleep 1
cupsd -t -c "$WORK/cupsd.conf" -s "$WORK/cups-files.conf"
grep -q 'Require user @SYSTEM' "$WORK/cupsd.conf"
grep -q 'Allow @LOCAL' "$WORK/cupsd.conf"
grep -q 'Browsing Yes' "$WORK/cupsd.conf"
grep -q 'BrowseLocalProtocols dnssd' "$WORK/cupsd.conf"
cp "$WORK/cupsd.conf" "$WORK/first.conf"
cupsctl --remote-admin --share-printers ServerName=print-test \
  WebInterface=Yes Browsing=Yes BrowseLocalProtocols=dnssd DefaultShared=Yes
sleep 1
cmp "$WORK/first.conf" "$WORK/cupsd.conf"
echo 'PASS: real CUPS configuration, LAN restrictions, authentication policy and idempotence'
