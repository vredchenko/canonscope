#!/usr/bin/env bash
# Camera helpers for canonscope tools. Source, don't execute.
#
# Everything here funnels through one chdkptp invocation per call. That is a
# deliberate design choice, not laziness: connect+quit was measured at
# 0.51-0.66s over three runs on 2026-11-06, which is cheap enough that a
# persistent daemon buys nothing and costs a lifecycle to manage.
#
# The corollary is that a command wanting six values should ask for all six in
# ONE cam_lua call, not six. See cam_status() for the pattern.

# shellcheck source=./common.sh
[[ -n "${CANONSCOPE_ROOT:-}" ]] || source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Which chdkptp to run, first match wins:
#   $CHDKPTP_DIR/chdkptp.sh      explicit override (the test suite uses this)
#   build/chdkptp/chdkptp.sh     built from source in a checkout
#   /usr/lib/canonscope/chdkptp  bundled with the .deb
#   chdkptp.sh / chdkptp on PATH
cam_find_chdkptp() {
    local c
    if [[ -n "${CHDKPTP_DIR:-}" ]]; then
        printf '%s\n' "${CHDKPTP_DIR}/chdkptp.sh"; return 0
    fi
    for c in "${CANONSCOPE_ROOT}/build/chdkptp/chdkptp.sh" \
             /usr/lib/canonscope/chdkptp/chdkptp.sh; do
        [[ -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
    done
    for c in chdkptp.sh chdkptp; do
        command -v "$c" 2>/dev/null && return 0
    done
    printf '%s\n' "${CANONSCOPE_ROOT}/build/chdkptp/chdkptp.sh"
}
CHDKPTP="$(cam_find_chdkptp)"

# ---------------------------------------------------------------- gvfs -----
#
# On a desktop, gvfsd-gphoto2 claims the camera's PTP session the moment it
# enumerates: the camera screen goes black and chdkptp reports
# "ptp_opensession failed 0x2ff". The udev rule in tools/udev/ is the real fix;
# this is the fallback for machines where it is not installed.
#
# `pkill -x`, never `pkill -f`. With -f the pattern matches against every
# process's full command line -- including this script's own, which contains
# the string -- so -f kills the caller. That has happened here.
cam_free_usb() {
    [[ "${CANONSCOPE_KEEP_GVFS:-0}" == "1" ]] && return 0
    if pgrep -x gvfsd-gphoto2 >/dev/null 2>&1; then
        info "killing gvfsd-gphoto2 (it had claimed the camera)"
        pkill -x gvfsd-gphoto2 || true
        sleep 0.3
    fi
    return 0
}

cam_require() {
    [[ -x "$CHDKPTP" ]] || die "chdkptp not found (looked for ${CHDKPTP}) -- install the .deb, build it with packaging/build-chdkptp.sh, or set CHDKPTP_DIR"
}

# cam_exec <chdkptp command> [more commands...]
#
# Runs commands on one connection and echoes the raw output. Does NOT fail on a
# camera-side error; callers inspect the text. Connection failure IS fatal,
# because every caller cares.
cam_exec() {
    cam_require
    cam_free_usb
    local args=() c out
    for c in "$@"; do args+=(-e"$c"); done
    # `|| true` because chdkptp exits non-zero for benign things such as
    # "already in rec"; the connection check below is the real gate.
    out="$("$CHDKPTP" -c "${args[@]}" -e"quit" 2>&1 || true)"
    # NOTE: no pipe into grep -q here. In a pipefail script grep exits on first
    # match, the producer dies of SIGPIPE (141) and the pipeline reports
    # failure -- so `|| die` fires on success. Match against a variable instead.
    if [[ "$out" != *"connected:"* ]]; then
        printf '%s\n' "$out" >&2
        die "could not connect to the camera -- is it on, CHDK booted, and USB attached?"
    fi
    printf '%s\n' "$out"
}

# cam_lua <lua source>
#
# Runs Lua on the camera and prints whatever it returned, unquoted. Returns
# non-zero and prints nothing if the camera returned no value.
cam_lua() {
    local out val
    out="$(cam_exec "luar $1")"
    # chdkptp prints results as   <serial>:return:'<value>'
    val="$(sed -n "s/^[0-9]\+:return:'\(.*\)'$/\1/p" <<< "$out")"
    if [[ -z "$val" ]]; then
        # A bare number comes back without quotes.
        val="$(sed -n 's/^[0-9]\+:return:\([^'"'"'].*\)$/\1/p' <<< "$out")"
    fi
    [[ -n "$val" ]] || { printf '%s\n' "$out" >&2; return 1; }
    printf '%s\n' "$val"
}

# ---------------------------------------------------------------- JSON -----
#
# Hand-rolled because tools/ is bash + coreutils only -- jq is declared as a
# dependency of fetch-assets.sh alone, and the camera path has to run on a
# freshly installed Pi with nothing added.
json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    printf '%s' "$s"
}

# json_from_pairs <k=v> [k=v...]
# Numeric-looking values are emitted bare; everything else is quoted.
json_from_pairs() {
    local first=1 pair k v
    printf '{'
    for pair in "$@"; do
        k=${pair%%=*}; v=${pair#*=}
        (( first )) || printf ','
        first=0
        printf '"%s":' "$(json_escape "$k")"
        if [[ "$v" =~ ^-?[0-9]+$ ]]; then
            printf '%s' "$v"
        elif [[ "$v" == "true" || "$v" == "false" || "$v" == "null" ]]; then
            printf '%s' "$v"
        else
            printf '"%s"' "$(json_escape "$v")"
        fi
    done
    printf '}\n'
}

# --------------------------------------------------------------- status ----
#
# ONE round trip for every field. The fields are chosen to answer "is the rig
# healthy and what is it pointed at" without a second call.
#
# Note the integer arithmetic: CHDK's on-camera Lua has no floating point
# (3/2 == 1), and string.format("%f") silently emits a literal "f" rather than
# erroring. Every value below is an integer or a string. See
# docs/09-capability-inventory.md.
cam_status_raw() {
    cam_lua 'local b=get_buildinfo()
local d=get_dofinfo()
return string.format(
 "chdk=%s|platform=%s|platsub=%s|zoom=%d|zoom_steps=%d|vbatt_mv=%d|usb_power=%d|temp_optical_c=%d|temp_ccd_c=%d|temp_battery_c=%d|free_kb=%d|jpg_remaining=%d|shutter_count=%d|mode_rec=%d|focal_um=%d|eff_focal_um=%d|dof_near_mm=%d|dof_far_mm=%d|av96=%d|tv96=%d|sv96=%d",
 b.build_number, b.platform, b.platsub,
 get_zoom(), get_zoom_steps(), get_vbatt(), get_usb_power(),
 get_temperature(0), get_temperature(1), get_temperature(2),
 get_free_disk_space(), get_jpg_count(), get_exp_count(),
 (get_mode() and 1 or 0),
 d.focal_length, d.eff_focal_length, d.near, d.far,
 get_current_av96(), get_current_tv96(), get_current_base_sv96())'
}
