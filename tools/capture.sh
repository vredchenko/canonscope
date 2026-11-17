#!/usr/bin/env bash
#
# capture.sh -- take a photo on the camera and land it on this host.
#
# Nothing is written to the camera's SD card: chdkptp's remoteshoot streams the
# image straight over USB. The point is to hand a Claude Code session a file it
# can read -- see docs/08-eyes-for-claude.md.
#
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/camera.sh"

OUT=""
TV=""          # shutter, seconds (e.g. 0.5, or 1/60)
SV=""          # ISO, Canon "real"
SD=""          # subject distance, e.g. 2m -- fixed focus for a fixed rig
FLASH="off"    # see --flash; off by default, and that default is load bearing
EXTRA=()

usage() {
    cat <<EOF
Usage: ${0##*/} [options]

  --out PATH     where to write (default: <capture dir>/<timestamp>.jpg;
                 the capture dir is \$CANONSCOPE_CAPTURE_DIR, else captures/
                 in a source checkout, else ~/.local/share/canonscope/captures)
  --tv SEC       shutter speed, e.g. 0.5 or 1/60
  --sv ISO       ISO, Canon "real" value
  --sd DIST      subject distance, e.g. 2m -- the port supports SD override in
                 AF, AFL and MF, so a fixed camera-to-target distance can be a
                 configured constant rather than a per-shot gamble
  --flash MODE   off (default) | auto | on | keep
                 Default is OFF deliberately: firing the flash draws a 1.5-2A
                 burst that browned out this camera at 69% battery and dropped
                 it off the USB bus mid-capture, losing the shot. 'keep' leaves
                 whatever the camera is set to.
  --keep-gvfs    don't kill gvfsd-gphoto2 first (see below)
  --            everything after is passed to remoteshoot verbatim

Auto-exposure is usually the thing that fails: a dim room underexposes badly and
a whiteboard blows out the white. --tv and --sv are the fix.

Examples:
  ${0##*/}                                  # auto everything
  ${0##*/} --tv 0.5 --sv 800                # dim room
  ${0##*/} --sd 2m --out /tmp/board.jpg     # fixed focus at 2 metres
EOF
}

while (( $# )); do
    case "$1" in
        --out) OUT="${2:?--out needs a path}"; shift ;;
        --tv)  TV="${2:?--tv needs a value}"; shift ;;
        --sv)  SV="${2:?--sv needs a value}"; shift ;;
        --sd)  SD="${2:?--sd needs a value}"; shift ;;
        --flash) FLASH="${2:?--flash needs off|auto|on}"; shift ;;
        --keep-gvfs) export CANONSCOPE_KEEP_GVFS=1 ;;  # read by cam_free_usb
        --) shift; EXTRA=("$@"); break ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument '$1'" ;;
    esac
    shift
done

cam_require

if [[ -z "$OUT" ]]; then
    # $$ guards against two shots landing in the same second.
    OUT="${CAPTURE_DIR}/$(date +%Y%m%d-%H%M%S)-$$.jpg"
fi
mkdir -p "$(dirname "$OUT")"

# The desktop claims the camera the moment it enumerates (gvfsd-gphoto2); see
# cam_free_usb in lib/camera.sh for the fallback, and tools/udev/ for the fix.
cam_free_usb

# remoteshoot appends the extension itself, so hand it a path without one.
STEM="${OUT%.jpg}"
RS=("remoteshoot" "$STEM" "-jpg")
[[ -n "$TV" ]] && RS+=("-tv=$TV")
[[ -n "$SV" ]] && RS+=("-sv=$SV")
[[ -n "$SD" ]] && RS+=("-sd=$SD")
(( ${#EXTRA[@]} )) && RS+=("${EXTRA[@]}")

# PROPCASE_FLASH_MODE is 143 on propset 2 (this camera): 0 auto, 1 on, 2 off.
# The pop-up itself is mechanical and cannot be driven in software -- this only
# governs whether a raised flash fires.
case "$FLASH" in
    off)  FLASH_PROP=2 ;;
    auto) FLASH_PROP=0 ;;
    on)   FLASH_PROP=1 ;;
    keep) FLASH_PROP="" ;;
    *) die "--flash must be off, auto, on or keep" ;;
esac

info "capturing -> $OUT"
# `rec` errors with "already in rec" when the camera is already there, which is
# the normal case for a rig left powered on. Not a failure, so it is tolerated.
# No `play` afterwards: some cameras crash returning to play mode after a
# remote shoot (remoteshoot -filedummy is the documented workaround if needed).
PRE=()
[[ -n "$FLASH_PROP" ]] && PRE=(-e"luar set_prop(143,${FLASH_PROP})")
OUTPUT="$("$CHDKPTP" -c -e"rec" "${PRE[@]}" -e"${RS[*]}" -e"quit" 2>&1 || true)"

if ! grep -q 'connected:' <<< "$OUTPUT"; then
    printf '%s\n' "$OUTPUT" >&2
    die "could not connect to the camera -- is it on, CHDK booted, and USB attached?"
fi
grep -v -e '^ERROR: already in rec$' <<< "$OUTPUT" | sed '/^$/d' || true

[[ -s "$OUT" ]] || die "no image written to $OUT"
ok "$(du -h "$OUT" | cut -f1)  $OUT"
printf '%s\n' "$OUT"
