#!/usr/bin/env bash
#
# install-udev-rule.sh -- stop the desktop auto-claiming the camera.
#
# Replaces the `pkill -x gvfsd-gphoto2` workaround in capture.sh with something
# that holds across reboots and re-plugs. See tools/udev/99-canonscope-camera.rules
# for why the rule looks the way it does.
#
# Validation runs unprivileged; sudo is used only to copy the file in and
# reload udev.
#
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"

RULE_SRC="${CANONSCOPE_ROOT}/tools/udev/99-canonscope-camera.rules"
RULE_DST="/etc/udev/rules.d/99-canonscope-camera.rules"
VENDOR="04a9"
PRODUCT="31c0"
UNINSTALL=0

usage() {
    cat <<EOF
Usage: ${0##*/} [--uninstall]

Installs ${RULE_DST}

Run WITHOUT sudo. Everything is checked first; the script escalates only to
copy the rule in and reload udev.
EOF
}
while (( $# )); do
    case "$1" in
        --uninstall) UNINSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument '$1'" ;;
    esac
    shift
done

need udevadm install
priv() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# =============================== UNPRIVILEGED ===============================

if (( UNINSTALL )); then
    [[ -f "$RULE_DST" ]] || die "not installed: $RULE_DST"
    info "will remove $RULE_DST and reload udev"
    confirm_exact "remove"
    priv rm -f "$RULE_DST"
    priv udevadm control --reload
    priv udevadm trigger --subsystem-match=usb --action=add
    ok "removed; the desktop will claim the camera again"
    exit 0
fi

[[ -f "$RULE_SRC" ]] || die "rule not found: $RULE_SRC"

# Is the problem even present? A headless Pi OS Lite install has no gvfs at all,
# in which case the rule is harmless insurance rather than a fix.
if [[ -f /lib/udev/rules.d/60-libgphoto2-6.rules || -f /usr/lib/udev/rules.d/60-libgphoto2-6.rules ]]; then
    ok "libgphoto2 udev rules present -- this rule has something to override"
else
    warn "no libgphoto2 udev rules found; installing anyway as insurance,"
    warn "and for the MODE/GROUP it sets (useful on a headless box)"
fi

if command -v gvfsd-gphoto2 >/dev/null 2>&1 || [[ -x /usr/libexec/gvfsd-gphoto2 ]]; then
    ok "gvfsd-gphoto2 is installed -- this is the thing that claims the camera"
else
    warn "gvfsd-gphoto2 not installed (headless?); the rule still does no harm"
fi

# Access after the rule: uaccess needs a seat, which an SSH session does not
# have. Group membership is the headless fallback.
# Capture first, then match. Piping into `grep -q` lets grep exit early, the
# producer takes SIGPIPE, and under `pipefail` the pipeline reports failure --
# which here would silently answer "no seat" / "not in plugdev" when the
# opposite is true. See docs/07-shell-and-provisioning-lessons.md.
HAVE_SEAT=0
SESSION="$(loginctl 2>/dev/null | awk -v u="$USER" '$3==u{print $1; exit}' || true)"
SEAT_INFO="$([[ -n "$SESSION" ]] && loginctl show-session "$SESSION" -p Seat 2>/dev/null || true)"
grep -q 'Seat=seat' <<< "$SEAT_INFO" && HAVE_SEAT=1
IN_PLUGDEV=0
MY_GROUPS="$(id -nG 2>/dev/null || true)"
grep -qx plugdev <<< "${MY_GROUPS// /$'\n'}" && IN_PLUGDEV=1

printf '  seat (grants uaccess ACL) : %s\n' "$( ((HAVE_SEAT)) && echo yes || echo 'no -- headless or SSH' )"
printf '  member of plugdev         : %s\n' "$( ((IN_PLUGDEV)) && echo yes || echo no )"
if (( ! HAVE_SEAT && ! IN_PLUGDEV )); then
    warn "neither a seat nor plugdev membership: you will get no write access."
    warn "Fix with:  sudo usermod -aG plugdev $USER   (then log out and back in)"
fi

echo
echo "will install:"
printf '  %s\n  -> %s\n' "$RULE_SRC" "$RULE_DST"
if [[ -f "$RULE_DST" ]]; then
    if diff -q "$RULE_SRC" "$RULE_DST" >/dev/null 2>&1; then
        ok "already installed and identical -- nothing to do"
        exit 0
    fi
    warn "a different version is already installed; it will be replaced"
fi
echo
confirm_exact "install"

# ==================== ESCALATE ONLY BELOW THIS LINE =========================
priv install -m 0644 -o root -g root "$RULE_SRC" "$RULE_DST"
ok "installed $RULE_DST"
priv udevadm control --reload
ok "udev rules reloaded"
priv udevadm trigger --subsystem-match=usb --action=add
ok "triggered; re-plug the camera if it is currently attached"

# ------------------------------------------------------------------- verify
DEV="$(lsusb 2>/dev/null | awk -v v="$VENDOR" -v p="$PRODUCT" \
    'tolower($6)==v":"p {gsub(":","",$4); printf "/dev/bus/usb/%s/%s", $2, $4}')"
if [[ -z "$DEV" || ! -e "$DEV" ]]; then
    info "camera not attached, so nothing to verify yet"
    info "plug it in, then: udevadm info -q property -n <node> | grep GPHOTO2"
    exit 0
fi
echo
info "verifying against the attached camera at $DEV"
PROPS="$(udevadm info -q property -n "$DEV" 2>/dev/null || true)"
if grep -q '^ID_GPHOTO2=' <<< "$PROPS"; then
    warn "ID_GPHOTO2 is still set -- re-plug the camera and check again"
    warn "(udevadm trigger does not always re-run everything for an existing device)"
else
    ok "ID_GPHOTO2 cleared -- the volume monitor will ignore this camera"
fi
FACL="$(getfacl -p "$DEV" 2>/dev/null || true)"
if grep -q "^user:${USER}:rw" <<< "$FACL"; then
    ok "write access preserved via uaccess ACL"
elif (( IN_PLUGDEV )); then
    ok "write access via plugdev group"
else
    warn "no obvious write access to $DEV -- see the plugdev note above"
fi
