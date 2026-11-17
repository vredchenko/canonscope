#!/usr/bin/env bash
#
# make-card.sh -- partition, format and populate an SD card for the SX200 IS.
#
# THIS SCRIPT DESTROYS DATA. Two principles govern its structure (see
# docs/07-shell-and-provisioning-lessons.md):
#
#   1. EVERY CHECK RUNS UNPRIVILEGED. A wrong target is rejected while this
#      script still cannot destroy anything. That is why the size comes from
#      /sys/block/<dev>/size rather than `blockdev --getsize64` -- the latter
#      needs root, so using it would force escalation before deciding whether
#      the target is sane. Nothing above the ESCALATE line needs privilege.
#
#   2. REPLACE A GUARD, NEVER REMOVE IT. Every mode has a positive identifying
#      check. There is no path through this file that accepts an unidentified
#      device, and no flag that skips both checks -- a fixed USB disk swaps the
#      removable+size-cap guards for an exact serial match rather than dropping
#      them.
#
# Modes:
#   verreq  Single FAT16 partition holding only the empty ver.req / vers.req
#           trigger files. Reads the camera's firmware revision. No CHDK.
#           START HERE: only firmware 1.00C and 1.00D have CHDK builds.
#   chdk    Single bootable FAT16 partition with a full CHDK distribution and
#           the "BOOTDISK" marker. Cards 4GB and smaller only -- the SX200 IS
#           is a pre-2011 body and cannot autoboot from FAT32.
#
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"

MODE="verreq"
DEVICE=""
BUILD=""
LABEL=""
KEEP_MOUNTED=0
ALLOW_BIG=0
EXPECT_SERIAL="${EXPECT_SERIAL:-}"

# FAT16 tops out at 65524 clusters; with 64K clusters that is a hair over 4GB.
# The camera is pre-2011 so FAT16 is the only bootable option.
MAX_FAT16_BYTES=$(( 4096 * 1024 * 1024 ))
# Removable mode only: a card larger than this is suspicious for this project.
MAX_REMOVABLE_GB="${MAX_REMOVABLE_GB:-128}"
# Below this it cannot hold anything useful.
MIN_MB="${MIN_MB:-16}"

usage() {
    cat <<EOF
Usage: ${0##*/} --device /dev/sdX [--mode verreq|chdk] [options]

Run WITHOUT sudo: validation happens unprivileged, and the script escalates
only after you have confirmed the target.

Required:
  --device /dev/sdX     the whole-disk device for the SD card (NOT a partition)

Options:
  --mode verreq         firmware-identification card (default)
  --mode chdk           bootable CHDK card; needs --build
  --build <zip>         CHDK distribution zip (default: newest -full.zip in
                        assets/chdk/builds)
  --label <NAME>        FAT label (default: CANONVER / CANONCHDK)
  --expect-serial <S>   for a USB device NOT flagged removable: replaces the
                        removable and size-cap guards with an exact serial
                        match. Find it with: lsblk -ndo SERIAL /dev/sdX
  --keep-mounted        leave the card mounted when done
  --allow-big           permit a card over 4GB in chdk mode (it will NOT
                        autoboot on this camera -- see docs/)
  -h, --help            this text

Examples:
  # Step 1: find out what firmware the camera has
  ${0##*/} --device /dev/sdb --mode verreq

  # Step 2 (once firmware is known to be 1.00C or 1.00D):
  ${0##*/} --device /dev/sdb --mode chdk \\
      --build assets/chdk/builds/sx200is-100c-1.6.1-6355-full.zip
EOF
}

while (( $# )); do
    case "$1" in
        --device) DEVICE="${2:?--device needs a path}"; shift ;;
        --mode)   MODE="${2:?--mode needs a value}"; shift ;;
        --build)  BUILD="${2:?--build needs a path}"; shift ;;
        --label)  LABEL="${2:?--label needs a value}"; shift ;;
        --expect-serial) EXPECT_SERIAL="${2:?--expect-serial needs a value}"; shift ;;
        --keep-mounted) KEEP_MOUNTED=1 ;;
        --allow-big)    ALLOW_BIG=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument '$1'" ;;
    esac
    shift
done

[[ -n "$DEVICE" ]] || { usage >&2; die "--device is required"; }
case "$MODE" in verreq|chdk) ;; *) die "--mode must be verreq or chdk" ;; esac
need sfdisk mkfs.vfat lsblk dd unzip findmnt awk sed

# Escalation helper. The script is meant to be run as an ordinary user; this is
# the ONLY way a privileged command is issued, and it is never called above the
# ESCALATE line.
priv() { if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi; }

# =============================== UNPRIVILEGED ===============================
# Everything from here to the ESCALATE line runs as the invoking user.

# --- shape of the argument ---------------------------------------------------
[[ -b "$DEVICE" ]] || die "$DEVICE is not a block device"
DEV_NAME="$(basename "$(readlink -f "$DEVICE")")"
SYS_BLOCK="/sys/block/${DEV_NAME}"
[[ -d "$SYS_BLOCK" ]] \
    || die "$DEVICE is not a whole disk -- pass /dev/sdX, not /dev/sdX1"

# --- transport: USB only -----------------------------------------------------
# The highest-value single check: an internal NVMe or SATA disk can never be the
# intended target, and this is what stops the /dev/sda-is-my-root accident.
DEV_TRAN="$(lsblk -ndo TRAN "$DEVICE" 2>/dev/null || true)"
[[ "$DEV_TRAN" == "usb" ]] \
    || die "$DEVICE transport is '${DEV_TRAN:-unknown}', not usb -- refusing"

# --- nothing critical may live on it -----------------------------------------
# Check the whole device tree: the dangerous case is a mounted PARTITION of the
# disk about to be overwritten.
MOUNTED="$(lsblk -nro MOUNTPOINTS "$DEVICE" 2>/dev/null | sed '/^$/d' || true)"
if [[ -n "$MOUNTED" ]]; then
    while IFS= read -r mp; do
        case "$mp" in
            /|/boot|/boot/*|/usr|/usr/*|/var|/var/*|/home|/home/*|/etc|/etc/*)
                die "$DEVICE carries $mp -- this looks like a system disk. Refusing." ;;
        esac
    done <<< "$MOUNTED"
fi
# `grep -c` prints 0 but EXITS NON-ZERO when the count is zero, so `|| true`
# (never `|| echo 0`, which would emit a second line). See docs/07.
# /proc/swaps names the resolved device node, so match on that, not on a
# /dev/disk/by-id symlink the user may have passed.
grep -qs "^/dev/${DEV_NAME}" /proc/swaps && die "$DEVICE has active swap on it -- refusing"
HOLDERS="$(lsblk -nro TYPE "$DEVICE" 2>/dev/null | grep -c -e lvm -e raid || true)"
[[ "${HOLDERS:-0}" -eq 0 ]] || die "$DEVICE is an LVM/RAID member -- refusing"
FSTYPES="$(lsblk -rno FSTYPE "$DEVICE" 2>/dev/null || true)"
if grep -qE '^(crypto_LUKS|LVM2_member)$' <<< "$FSTYPES"; then
    die "$DEVICE contains LUKS or LVM members -- refusing"
fi

# --- size, read without privilege --------------------------------------------
# /sys/block/<dev>/size is ALWAYS in 512-byte sectors, whatever the logical
# block size reports.
SIZE_SECTORS="$(cat "${SYS_BLOCK}/size" 2>/dev/null || echo 0)"
[[ "$SIZE_SECTORS" -gt 0 ]] || die "could not read the size of $DEVICE from sysfs"
DEV_BYTES=$(( SIZE_SECTORS * 512 ))
DEV_GB=$(( DEV_BYTES / 1000000000 ))
(( DEV_BYTES / 1048576 >= MIN_MB )) \
    || die "$DEVICE is only $(human "$DEV_BYTES") -- below the ${MIN_MB}MB floor"

DEV_REMOVABLE="$(cat "${SYS_BLOCK}/removable" 2>/dev/null || echo 0)"
DEV_SERIAL="$(lsblk -ndo SERIAL "$DEVICE" 2>/dev/null | tr -d ' ' || true)"
DEV_MODEL="$(lsblk -ndo MODEL "$DEVICE" 2>/dev/null | sed 's/  */ /g;s/^ //;s/ $//' || true)"

# --- the mode-specific identifying guard -------------------------------------
# Exactly one of these must pass. There is no third branch and no flag that
# skips both -- preserve that invariant.
if [[ -n "$EXPECT_SERIAL" ]]; then
    GUARD="serial"
    warn "serial mode: the removable and size-cap guards are REPLACED by an exact serial match"
    [[ -n "$DEV_SERIAL" ]] \
        || die "$DEVICE reports no serial, so --expect-serial cannot be satisfied"
    [[ "$DEV_SERIAL" == "$EXPECT_SERIAL" ]] \
        || die "serial mismatch: $DEVICE is '$DEV_SERIAL', expected '$EXPECT_SERIAL' -- refusing"
    ok "serial matches: $DEV_SERIAL"
else
    GUARD="removable"
    [[ "$DEV_REMOVABLE" == "1" ]] \
        || die "$DEVICE is not flagged removable. If it is a fixed USB device you mean to write, re-run with --expect-serial \"\$(lsblk -ndo SERIAL $DEVICE)\""
    (( DEV_GB <= MAX_REMOVABLE_GB )) \
        || die "$DEVICE is ${DEV_GB}GB, over the ${MAX_REMOVABLE_GB}GB cap for removable mode -- if deliberate, use --expect-serial"
    ok "removable flag set, ${DEV_GB}GB within the ${MAX_REMOVABLE_GB}GB cap"
fi

if [[ "$MODE" == "chdk" ]] && (( DEV_BYTES > MAX_FAT16_BYTES )) && (( ! ALLOW_BIG )); then
    die "$DEVICE is $(human "$DEV_BYTES"), over the 4GB FAT16 ceiling. The SX200 IS cannot autoboot from FAT32 (pre-2011 body), so a single-partition card this size will not autoboot. Use a <=4GB card, see docs/03-storage-and-chdk.md for the dual-partition route, or pass --allow-big to make a non-booting card anyway."
fi

# --- resolve and validate the build (still unprivileged) ---------------------
if [[ "$MODE" == "chdk" ]]; then
    if [[ -z "$BUILD" ]]; then
        BUILD="$(find "${ASSETS_DIR}/chdk/builds" -maxdepth 1 -name '*-full.zip' -printf '%T@ %p\n' 2>/dev/null \
            | sort -rn | sed -n '1{s/^[^ ]* //;p}' || true)"
        [[ -n "$BUILD" ]] \
            || die "no CHDK build given and none found in ${ASSETS_DIR}/chdk/builds (run tools/fetch-assets.sh first)"
        warn "no --build given; using newest full build: $(basename "$BUILD")"
    fi
    [[ -f "$BUILD" ]] || die "build zip not found: $BUILD"
    unzip -tq "$BUILD" >/dev/null 2>&1 || die "build zip is corrupt: $BUILD"
    if [[ "$(basename "$BUILD")" != *-full.zip ]]; then
        warn "$(basename "$BUILD") is not a '-full' build. The bootable-card method"
        warn "wants the complete distribution; this card may be missing modules."
    fi
    # NOT `unzip -l ... | grep -q`: grep -q exits on first match, unzip dies of
    # SIGPIPE (141), and `pipefail` turns that into a failed pipeline -- so the
    # `|| die` fires even though the match succeeded. Capture, then match.
    BUILD_LIST="$(unzip -l "$BUILD")"
    grep -qi 'DISKBOOT.BIN' <<< "$BUILD_LIST" \
        || die "$(basename "$BUILD") contains no DISKBOOT.BIN -- not a bootable distribution"
fi

[[ -n "$LABEL" ]] || LABEL=$([[ "$MODE" == "chdk" ]] && echo CANONCHDK || echo CANONVER)

# --- show the target and make a human say it out loud ------------------------
echo
printf '%s%sAbout to ERASE %s%s\n' "$C_BOLD" "$C_RED" "$DEVICE" "$C_RESET"
printf '  model       : %s\n' "${DEV_MODEL:-unknown}"
printf '  serial      : %s\n' "${DEV_SERIAL:-none}"
printf '  size        : %s (%s bytes)\n' "$(human "$DEV_BYTES")" "$DEV_BYTES"
printf '  removable   : %s\n' "$DEV_REMOVABLE"
printf '  guard       : %s\n' "$GUARD"
printf '  mode        : %s\n' "$MODE"
printf '  label       : %s\n' "$LABEL"
[[ "$MODE" == "chdk" ]] && printf '  CHDK build  : %s\n' "$(basename "$BUILD")"
echo
echo "current contents:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DEVICE" | sed 's/^/  /'
# Show any data about to die, so a wrong device is obvious.
while read -r part; do
    mp="$(findmnt -rno TARGET "$part" 2>/dev/null | sed -n '1p' || true)"
    [[ -n "$mp" ]] || continue
    printf '  %s mounted at %s -- %s file(s), %s used\n' \
        "$part" "$mp" "$(find "$mp" -type f 2>/dev/null | wc -l)" \
        "$(du -sh "$mp" 2>/dev/null | awk '{print $1}')"
done < <(lsblk -rnpo NAME,TYPE "$DEVICE" | awk '$2=="part"{print $1}')
echo
confirm_exact "$DEV_NAME"

# ==================== ESCALATE ONLY BELOW THIS LINE =========================
# Everything above ran as the invoking user. Only now is privilege needed.
if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo not found, and not running as root"
    info "escalating via sudo for the write phase"
fi

info "unmounting any partitions on $DEVICE"
while read -r part; do
    while findmnt -rno TARGET "$part" >/dev/null 2>&1; do
        priv umount "$part" && ok "unmounted $part" || die "could not unmount $part"
    done
done < <(lsblk -rnpo NAME,TYPE "$DEVICE" | awk '$2=="part"{print $1}')
priv udevadm settle 2>/dev/null || true

# Type 06 = FAT16 >32MB. Canon ignores the MBR boot flag entirely, so
# bootability comes from the BOOTDISK marker, not from this table.
info "writing MBR with a single FAT16 partition"
priv wipefs -a "$DEVICE" >/dev/null 2>&1 || true
priv sfdisk --quiet --wipe always --wipe-partitions always "$DEVICE" <<'PART'
label: dos
unit: sectors
start=2048, type=06
PART
priv udevadm settle 2>/dev/null || true
priv partprobe "$DEVICE" 2>/dev/null || true
sleep 1

PART_DEV="$(lsblk -rnpo NAME,TYPE "$DEVICE" | awk '$2=="part"{print $1; exit}')"
[[ -n "$PART_DEV" && -b "$PART_DEV" ]] || die "partition device did not appear after partitioning"
ok "partition: $PART_DEV"

# -F 16 forces FAT16; mkfs picks 64K clusters on a ~4GB volume, keeping the
# cluster count under the FAT16 limit.
info "formatting $PART_DEV as FAT16, label $LABEL"
priv mkfs.vfat -F 16 -n "$LABEL" "$PART_DEV" >/dev/null
CLUSTER_BYTES="$(priv fsck.vfat -nv "$PART_DEV" 2>/dev/null | awk '/bytes per cluster/{print $1}' || echo '?')"
ok "FAT16 created (${CLUSTER_BYTES} bytes per cluster)"

MNT="$(mktemp -d /tmp/canonscope-card.XXXXXX)"
cleanup() {
    if findmnt -rno TARGET "$MNT" >/dev/null 2>&1; then
        sync; priv umount "$MNT" 2>/dev/null || true
    fi
    rmdir "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

priv mount -o uid=0,gid=0,umask=0022 "$PART_DEV" "$MNT"
ok "mounted at $MNT"

case "$MODE" in
    verreq)
        # Empty trigger files. Canon's firmware looks for these in the card root
        # and shows the real firmware revision instead of "1.0.0.0". ver.req
        # gives the revision; vers.req also exposes the shutter count.
        priv touch "${MNT}/ver.req" "${MNT}/vers.req"
        ok "created ver.req and vers.req"
        ;;
    chdk)
        info "unpacking $(basename "$BUILD")"
        priv unzip -q -o "$BUILD" -d "$MNT"
        [[ -f "${MNT}/DISKBOOT.BIN" ]] || die "DISKBOOT.BIN missing after unpack -- wrong zip layout?"
        ok "unpacked $(find "$MNT" -type f | wc -l) files"
        priv touch "${MNT}/ver.req"
        ;;
esac

sync
priv umount "$MNT"
trap - EXIT
rmdir "$MNT"
ok "filesystem flushed"

if [[ "$MODE" == "chdk" ]]; then
    # CHDK bootability for pre-2011 cameras: the ASCII string "BOOTDISK" at
    # offset 0x40 of the partition's FAT16 boot sector. 0x40 lands in the boot
    # *code* area, after the BPB/EBPB, which Canon never executes.
    info "writing BOOTDISK marker at offset 0x40 of $PART_DEV"
    printf 'BOOTDISK' | priv dd of="$PART_DEV" bs=1 seek=64 count=8 conv=notrunc status=none
    sync
    GOT="$(priv dd if="$PART_DEV" bs=1 skip=64 count=8 status=none)"
    [[ "$GOT" == "BOOTDISK" ]] || die "marker verification failed (read back '${GOT}')"
    ok "BOOTDISK marker verified"
fi

info "verifying the finished card"
priv blockdev --rereadpt "$DEVICE" 2>/dev/null || true
priv udevadm settle 2>/dev/null || true
priv fsck.vfat -n "$PART_DEV" >/dev/null 2>&1 && ok "filesystem clean" || warn "fsck reported issues"

MNT2="$(mktemp -d /tmp/canonscope-verify.XXXXXX)"
priv mount -o ro "$PART_DEV" "$MNT2"
echo
echo "card contents:"
# sed -n '1,25p' rather than `head -25`: head exits early, which SIGPIPEs sort
# and trips pipefail. sed consumes all input.
find "$MNT2" -maxdepth 1 -mindepth 1 -printf '  %y %10s  %P\n' | sort -k3 | sed -n '1,25p'
echo "  ($(find "$MNT2" -type f | wc -l) files total)"
priv umount "$MNT2"; rmdir "$MNT2"

if (( KEEP_MOUNTED )); then
    udisksctl mount -b "$PART_DEV" 2>/dev/null || warn "could not re-mount via udisks"
fi

echo
case "$MODE" in
    verreq)
        cat <<EOF
${C_GREEN}Firmware-identification card ready.${C_RESET}

Next, on the camera:
  1. Leave the write-protect tab UNLOCKED. Insert the card, battery in.
  2. Switch to PLAY mode (the arrow/playback button), not shooting mode.
  3. Hold FUNC/SET and press DOWN -- before the clock appears.
  4. Expect something like:
         Canon PowerShot SX200 IS
         P-ID:31C0 PAL D
         Firmware Ver GM1.00C     <-- this is the number that matters
  5. Still holding FUNC/SET, keep pressing DOWN for Adj Ver, IS firmware,
     and finally Total Shoot (the shutter count) -- worth writing down.

Only 1.00C and 1.00D have CHDK builds. If yours is one of them, write a
bootable card next with --mode chdk.
EOF
        ;;
    chdk)
        cat <<EOF
${C_GREEN}Bootable CHDK card ready.${C_RESET}

Next:
  1. ${C_BOLD}Set the write-protect tab to LOCKED.${C_RESET} That slider is what
     triggers the autoboot. CHDK then makes the camera ignore the lock, so you
     can still shoot normally.
  2. Insert the card and power the camera on. You should see the CHDK splash.
  3. The SX200 IS starts in PLAYBACK mode -- half-press the shutter to reach
     Record, or hold Power ~2s to boot straight into Record.
  4. <ALT> mode on this body is the ${C_BOLD}Print${C_RESET} button.
EOF
        ;;
esac
echo
