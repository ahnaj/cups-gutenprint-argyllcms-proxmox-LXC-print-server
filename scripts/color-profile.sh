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
# colorimeter/spectrophotometer -> build an ICC profile -> install it and
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
# instrument (e.g. X-Rite i1Pro/i1Display, ColorMunki) plugged into the LXC
# via USB passthrough (ENABLE_USB_PASSTHROUGH=yes at install time).

set -euo pipefail

CMD="${1:-}"

case "$CMD" in

  generate)
    # ./color-profile.sh generate epson-p600 epson-p600-matte
    PRINTER="${2:?printer queue name required}"
    PROFILE="${3:?profile base name required}"
    echo "==> Generating a 928-patch test chart for ${PROFILE}"
    # -d2: reflective print target, -f928: patch count suited to an A4/Letter sheet
    targen -v -d2 -f928 "${PROFILE}"
    # -p: page size, -R: no randomization of patch order (easier to proof visually)
    printtarg -v -ii1 -pA4 "${PROFILE}"
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
    lp -d "${PRINTER}" -o media=Letter -o ColorModel=RGB -o cm-calibration=true "${PROFILE}.tif"
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
    # -qh: high quality, -aG: gamma+matrix... use -aS for a LUT-based profile
    # if you printed a large enough patch set (400+ patches recommended).
    colprof -v -qh -aS -cmt -dpp "${PROFILE}"
    echo "==> Profile written: ${PROFILE}.icc"
    echo "    Inspect it with: iccgamut ${PROFILE}.icc && viewgam ${PROFILE}.gam"
    ;;

  install)
    # ./color-profile.sh install epson-p600 epson-p600-matte
    PRINTER="${2:?printer queue name required}"
    PROFILE="${3:?profile base name required}"
    ICC_DEST="/usr/share/color/icc/custom/${PROFILE}.icc"
    echo "==> Installing ${PROFILE}.icc to ${ICC_DEST}"
    install -m 644 "${PROFILE}.icc" "${ICC_DEST}"

    echo "==> Registering profile with colord for queue '${PRINTER}'"
    colormgr create-device "cups-${PRINTER}" printer sysfs
    colormgr create-profile "${PROFILE}" icc-model="${PROFILE}" || true
    colormgr import-profile "${ICC_DEST}"
    colormgr device-add-profile "cups-${PRINTER}" "${PROFILE}"
    colormgr device-make-profile-default "cups-${PRINTER}" "${PROFILE}"

    echo "==> Setting the profile as a CUPS default option on '${PRINTER}'"
    lpadmin -p "${PRINTER}" -o cm-calibration=true
    lpadmin -p "${PRINTER}" -o "print-color-profile=${ICC_DEST}"

    echo "==> Done. Print jobs to '${PRINTER}' will now be rendered through ${PROFILE}.icc"
    echo "    Verify with: lpoptions -p ${PRINTER} -l | grep -i color"
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
