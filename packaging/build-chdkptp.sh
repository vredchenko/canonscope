#!/usr/bin/env bash
#
# build-chdkptp.sh -- build chdkptp (CLI only) from the pinned upstream source.
#
# chdkptp is the host-side PTP client that talks to CHDK. Upstream is an
# Assembla SVN repository that now refuses anonymous access, so the source
# comes from the svn2github git mirror, pinned to the exact commit recorded in
# assets/chdkptp/PINNED.txt (last upstream change: 2018-09-15).
#
# Lua 5.2 specifically (5.3 is "known to cause problems" per chdkptp's own
# readme; 5.1 is unsupported) and the libusb 0.1 API (`<usb.h>`, `-lusb`).
# GUI stays off, which avoids IUP and CD entirely.
#
# Build deps (Debian/Ubuntu/Raspberry Pi OS):
#   build-essential liblua5.2-dev libusb-dev libreadline-dev git
#
# Usage: packaging/build-chdkptp.sh [--src DIR] [--out DIR]
#   --src DIR   existing chdkptp source tree (default: the asset mirror if
#               present, otherwise a fresh clone of the pinned commit)
#   --out DIR   where to build (default: build/chdkptp)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

MIRROR="https://github.com/svn2github/chdkptp.git"
PIN="$(cut -d' ' -f1 assets/chdkptp/PINNED.txt)"
SRC=""
OUT="build/chdkptp"
while (( $# )); do
    case "$1" in
        --src) SRC="${2:?--src needs a directory}"; shift ;;
        --out) OUT="${2:?--out needs a directory}"; shift ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument '$1'" >&2; exit 1 ;;
    esac
    shift
done

if [[ -z "$SRC" ]]; then
    if [[ -f assets/chdkptp/svn2github-mirror/Makefile ]]; then
        SRC="assets/chdkptp/svn2github-mirror"
    else
        SRC="build/chdkptp-src"
        if [[ ! -f "${SRC}/Makefile" ]]; then
            echo "==> fetching chdkptp ${PIN:0:12} from ${MIRROR}"
            rm -rf "$SRC"; mkdir -p "$SRC"
            git -C "$SRC" init -q
            git -C "$SRC" fetch -q --depth 1 "$MIRROR" "$PIN"
            git -C "$SRC" checkout -q FETCH_HEAD
        fi
    fi
fi
[[ -f "${SRC}/Makefile" ]] || { echo "no chdkptp Makefile in ${SRC}" >&2; exit 1; }
if [[ -d "${SRC}/.git" ]]; then
    got="$(git -C "$SRC" rev-parse HEAD)"
    [[ "$got" == "$PIN" ]] || echo "warning: ${SRC} is at ${got:0:12}, pinned is ${PIN:0:12}" >&2
fi

# Build out of tree so the source stays a clean pinned checkout.
mkdir -p "$OUT"
cp -a "${SRC}/." "$OUT/"
rm -rf "${OUT}/.git"

# include.mk only `-include`s config.mk; without one LUA_INCLUDE_DIR points at
# ./extlibs/built/lua52/include, which the mirror does not ship, and the
# compile dies on a missing lua.h.
cat > "${OUT}/config.mk" <<'CONFIG'
# Written by packaging/build-chdkptp.sh.
USE_LUA_52=1
READLINE_SUPPORT=1
LUA_INCLUDE_DIR=/usr/include/lua5.2
LUA_LIB=lua5.2
LUASIGNAL_SUPPORT=1
CONFIG

echo "==> building chdkptp in ${OUT} (Lua 5.2, libusb 0.1 API, CLI only)"
make -C "$OUT" -j"$(nproc)"

[[ -x "${OUT}/chdkptp" && -x "${OUT}/chdkptp.sh" ]] \
    || { echo "build produced no ${OUT}/chdkptp" >&2; exit 1; }
"${OUT}/chdkptp.sh" -e"quit" >/dev/null 2>&1 || true
echo "==> built: ${OUT}/chdkptp.sh"
