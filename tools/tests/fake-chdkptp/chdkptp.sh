#!/usr/bin/env bash
#
# A stand-in for chdkptp, for testing tools/canonscope without a camera.
#
# The camera is 16 years old, irreplaceable, runs off a battery that sags, and
# is frequently simply switched off -- so the CLI's parsing, argument handling
# and JSON emission must be testable without it. This replays canned chdkptp
# output captured from the real body on 2026-11-06.
#
# Point the CLI at it with:
#   CHDKPTP_DIR=tools/tests/fake-chdkptp ./tools/canonscope status
#
# Set FAKE_CAM_FAIL=1 to simulate a camera that is off or unplugged.
set -uo pipefail

if [[ "${FAKE_CAM_FAIL:-0}" == "1" ]]; then
    echo "ERROR: no matching devices found"
    echo "ERROR: not connected"
    exit 1
fi

echo "connected: Canon PowerShot SX200 IS, max packet size 512"

n=10
reply() { n=$((n+1)); printf "%d:return:'%s'\n" "$n" "$1"; }

# Canned values are the real 2026-11-06 readings where one exists.
for arg in "$@"; do
    [[ "$arg" == -e* ]] || continue
    cmd="${arg#-e}"
    # FAKE_LOG records every command, so tests can assert on what was sent.
    [[ -n "${FAKE_LOG:-}" ]] && printf '%s\n' "$cmd" >> "$FAKE_LOG"
    case "$cmd" in
        remoteshoot*)
            # remoteshoot <stem> -jpg ... writes <stem>.jpg
            stem="${cmd#remoteshoot }"; stem="${stem%% *}"
            printf 'fake jpeg\n' > "${stem}.jpg"
            ;;
        luar*|"= "*)
            code="${cmd#luar }"
            case "$code" in
                *get_buildinfo*get_dofinfo*|*dof_near_mm*|*b.build_number*)
                    reply "chdk=1.6.1|platform=sx200is|platsub=100c|zoom=${FAKE_ZOOM:-0}|zoom_steps=126|vbatt_mv=${FAKE_VBATT:-3580}|usb_power=0|temp_optical_c=19|temp_ccd_c=30|temp_battery_c=25|free_kb=3959808|jpg_remaining=1237|shutter_count=2287|mode_rec=1|focal_um=5000|eff_focal_um=27290|dof_near_mm=672|dof_far_mm=10838|av96=347|tv96=480|sv96=659" ;;
                *get_usb_capture_support*)
                    reply 'usb_capture=7|raw=true|nd_filter=0|sd_override_modes=7|propset=2|zoom_steps=126|video_remote=false|canon_raw=false' ;;
                *get_vbatt*get_usb_power*) reply "${FAKE_VBATT:-3580}|0" ;;
                *get_zoom_steps*)          reply '126' ;;
                *get_zoom*)                reply "${FAKE_ZOOM:-0}" ;;
                *get_focus*)               reply "${FAKE_FOCUS:-2000}" ;;
                *)                         reply 'fake-ok' ;;
            esac
            ;;
        lvdumpimg*)
            # Mimic chdkptp writing the literal pattern when -count=1.
            pat="${cmd#*-vp=}"; pat="${pat%% *}"
            cnt="${cmd##*-count=}"; cnt="${cnt%% *}"
            if [[ "$cnt" == "1" ]]; then
                : > "$pat"
            else
                for ((i=1;i<=cnt;i++)); do
                    printf -v f "$pat" "$i"; : > "$f"
                done
            fi
            echo "$pat"
            ;;
        rec)
            # The normal case for a rig left powered on.
            echo "ERROR: already in rec" ;;
        lua*|play|quit) : ;;
    esac
done
exit 0
