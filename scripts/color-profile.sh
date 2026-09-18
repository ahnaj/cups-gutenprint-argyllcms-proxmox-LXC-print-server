#!/usr/bin/env bash
#
# scripts/color-profile.sh
#
# ArgyllCMS ICC profiling workflow for a printer attached to cups-print-server.
# Run this INSIDE the LXC (pct enter <CTID>), from a working directory where
# you want the profiling files to live, e.g. /root/color/<printer-name>/.
#
# This script is a runnable reference implementation of the full Argyll
# workflow: generate a test chart -> print it -> read it back with a
# reflective spectrophotometer -> build an ICC profile -> install it and
# bind it to the CUPS queue.
#
# It uses concrete example names (printer "epson-p600", profile
# "epson-p600-matte") — replace these with your actual queue name and paper/
# ink combination. Keeping profiles named `<printer>-<media>` makes it obvious
# which profile goes with which paper when you build several.
#
# Usage:
#   ./color-profile.sh generate   epson-p600 epson-p600-matte
#   ./color-profile.sh print      epson-p600 epson-p600-matte
#   ./color-profile.sh read       epson-p600-matte
#   ./color-profile.sh build      epson-p600-matte
#   ./color-profile.sh install    epson-p600 epson-p600-matte
#
# Requires: argyll (targen, printtarg, chartread, colprof), and a supported
# reflective instrument (e.g. X-Rite i1Pro or ColorMunki Photo) in the LXC
# via USB passthrough (ENABLE_USB_PASSTHROUGH=yes at install time).

set -euo pipefail

CMD="${1:-}"

case "$CMD" in

  generate)
    # ./color-profile.sh generate epson-p600 epson-p600-matte
    PRINTER="${2:?printer queue name required}"
    PROFILE="${3:?profile base name required}"
    echo "==> Generating a 928-patch test chart for ${PROFILE}"
    # -d2: print RGB (not video RGB); -f928: patch count, possibly several sheets.
    targen -v -d2 -f928 "${PROFILE}"
    # TIFF output for CUPS, with the same paper size used in the print step.
    printtarg -v -ii1 -p"${PAPER:-A4}" -t "${PROFILE}"
    echo "==> Chart written: ${PROFILE}.ti1 / ${PROFILE}.tif"
    echo "    Next: ./color-profile.sh print ${PRINTER} ${PROFILE}"
    ;;

  print)
    # ./color-profile.sh print epson-p600 epson-p600-matte
    PRINTER="${2:?printer queue name required}"
    PROFILE="${3:?profile base name required}"
    echo "==> Printing target chart ${PROFILE}.tif to queue '${PRINTER}'"
    # Print with NO color management applied — raw/uncorrected output is
    # what the instrument needs to read to characterize the printer.
    shopt -s nullglob
    charts=("${PROFILE}"*.tif)
    [[ ${#charts[@]} -gt 0 ]] || { echo 'No chart TIFFs found; run generate first.' >&2; exit 1; }
    lp -d "${PRINTER}" -o media="${PAPER:-A4}" -o ColorModel=RGB -o cm-calibration=true "${charts[@]}"
    echo "    Let the print dry fully (5-30 min depending on ink/paper) before reading it."
    ;;

  read)
    # ./color-profile.sh read epson-p600-matte
    PROFILE="${2:?profile base name required}"
    echo "==> Reading the printed chart with your instrument"
    echo "    chartread will prompt you to scan/click through each patch row."
    chartread -v "${PROFILE}"
    echo "==> Measurement file written: ${PROFILE}.ti3"
    ;;

  build)
    # ./color-profile.sh build epson-p600-matte
    PROFILE="${2:?profile base name required}"
    echo "==> Building ICC profile from ${PROFILE}.ti3"
    # High-quality LUT profile from measured RGB printer patches.
    colprof -v -qh -aS -cmt -dpp "${PROFILE}"
    echo "==> Profile written: ${PROFILE}.icc"
    echo "    Inspect it with: iccgamut ${PROFILE}.icc && viewgam ${PROFILE}.gam"
    ;;

  install)
    # ./color-profile.sh install epson-p600 epson-p600-matte
    PRINTER="${2:?printer queue name required}"
    PROFILE="${3:?profile base name required}"
    ICC_DEST="/usr/share/color/icc/custom/$(basename "${PROFILE}").icc"
    echo "==> Installing ${PROFILE}.icc to ${ICC_DEST}"
    install -m 644 "${PROFILE}.icc" "${ICC_DEST}"

    echo "==> Registering profile with colord for queue '${PRINTER}'"
    # Bind the real CUPS device, not an unrelated synthetic colord device.
    export LC_ALL=C
    DEVICE=$(colormgr find-device "cups-${PRINTER}" | awk '/Object Path:/ {print $3}')
    [[ -n "$DEVICE" ]] || { echo 'No colord device for this CUPS queue.' >&2; exit 1; }
    PROFILE_PATH=$(colormgr import-profile "${ICC_DEST}" | awk '/Object Path:/ {print $3}')
    [[ -n "$PROFILE_PATH" ]] || { echo 'Imported profile not found in colord.' >&2; exit 1; }
    colormgr device-add-profile "$DEVICE" "$PROFILE_PATH"
    colormgr device-make-profile-default "$DEVICE" "$PROFILE_PATH"

    echo "==> Removing persistent calibration overrides on '${PRINTER}'"
    lpadmin -p "${PRINTER}" -R cm-calibration
    lpadmin -p "${PRINTER}" -R print-color-profile

    echo "==> Profile registered. Verify selection in a real job's CUPS debug log."
    echo '    Use the same media/ink/quality settings used to print the target.'
    ;;

  *)
    cat <<EOF
Usage: $0 <generate|print|read|build|install> [printer] [profile-name]

  generate <printer> <profile>   Create an Argyll test chart (targen + printtarg)
  print    <printer> <profile>   Print the chart with color management OFF
  read     <profile>             Measure the printed chart (chartread)
  build    <profile>             Build the .icc profile from measurements (colprof)
  install  <printer> <profile>   Install the profile and bind it to the CUPS queue

Example end-to-end run for a printer queue named 'epson-p600', profiling for
matte paper:

  ./color-profile.sh generate epson-p600 epson-p600-matte
  ./color-profile.sh print    epson-p600 epson-p600-matte
  ./color-profile.sh read     epson-p600-matte
  ./color-profile.sh build    epson-p600-matte
  ./color-profile.sh install  epson-p600 epson-p600-matte
EOF
    exit 1
    ;;
esac
