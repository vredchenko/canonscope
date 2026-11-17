#!/usr/bin/env bash
#
# build-deb.sh -- build canonscope_<version>_<arch>.deb for the host architecture.
#
# The package is architecture-specific because it bundles a compiled chdkptp:
# the canonscope tools themselves are bash and arch-independent, but chdkptp
# is the hard part to obtain (stale upstream, Lua 5.2, libusb 0.1), so shipping
# it prebuilt is most of the value of the package.
#
# Run on Debian/Ubuntu/Raspberry Pi OS with the chdkptp build deps installed
# (see packaging/build-chdkptp.sh). CI runs it in a debian:trixie container on
# amd64 and arm64 runners. Output: dist/canonscope_<version>_<arch>.deb
#
# Layout:
#   /usr/bin/canonscope                    -> /usr/share/canonscope/tools/canonscope
#   /usr/bin/canonscope-make-card          -> .../tools/make-card.sh
#   /usr/bin/canonscope-fetch-assets       -> .../tools/fetch-assets.sh
#   /usr/bin/chdkptp                       -> /usr/lib/canonscope/chdkptp/chdkptp.sh
#   /usr/share/canonscope/                 tools, MCP server, VERSION
#   /usr/lib/canonscope/chdkptp/           chdkptp binary + its Lua (GPL-2.0)
#   /usr/lib/udev/rules.d/99-canonscope-camera.rules
#
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$ROOT"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need dpkg-deb; need dpkg; need make; need ldd

VERSION="$(sed -n '1p' VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "bad VERSION '$VERSION'" >&2; exit 1; }
ARCH="$(dpkg --print-architecture)"
PIN="$(cut -d' ' -f1 assets/chdkptp/PINNED.txt)"
WORK="build/deb-${ARCH}"
PKG="${WORK}/pkg"
OUTDIR="dist"
DEB="${OUTDIR}/canonscope_${VERSION}_${ARCH}.deb"

rm -rf "$PKG"
mkdir -p "$PKG" "$OUTDIR"

# ---------------------------------------------------------------- chdkptp
packaging/build-chdkptp.sh --out "${WORK}/chdkptp"
CHD="${PKG}/usr/lib/canonscope/chdkptp"
install -d "$CHD" "${CHD}/lua"
install -m 0755 "${WORK}/chdkptp/chdkptp" "${CHD}/chdkptp"
strip --strip-unneeded "${CHD}/chdkptp" 2>/dev/null || true
install -m 0755 "${WORK}/chdkptp/chdkptp.sh" "${CHD}/chdkptp.sh"
cp -a "${WORK}/chdkptp/lua/." "${CHD}/lua/"
# Lua C modules chdkptp loads via LUA_CPATH="$CHDKPTP_DIR/?.so" (signal.so).
for so in "${WORK}"/chdkptp/*.so; do
    [[ -f "$so" ]] && install -m 0644 "$so" "${CHD}/"
done
install -m 0644 "${WORK}/chdkptp/COPYING" "${CHD}/COPYING"

# ---------------------------------------------------------------- tools
SHARE="${PKG}/usr/share/canonscope"
install -d "${SHARE}/tools/lib" "${SHARE}/tools/udev" "${SHARE}/mcp"
install -m 0644 VERSION "${SHARE}/VERSION"
for f in canonscope capture.sh make-card.sh fetch-assets.sh; do
    install -m 0755 "tools/$f" "${SHARE}/tools/$f"
done
install -m 0644 tools/lib/*.sh "${SHARE}/tools/lib/"
install -m 0644 tools/canonscope.tools.json "${SHARE}/tools/"
install -m 0644 tools/udev/99-canonscope-camera.rules "${SHARE}/tools/udev/"
install -m 0755 mcp/run-server.sh "${SHARE}/mcp/"
install -m 0644 mcp/canonscope_mcp.py "${SHARE}/mcp/"
# fetch-assets.sh and the CHDK build pins live beside the tools.
install -d "${SHARE}/assets/chdkptp" "${SHARE}/assets/chdk/source"
install -m 0644 assets/chdkptp/PINNED.txt "${SHARE}/assets/chdkptp/"
install -m 0644 assets/chdk/source/PINNED.txt "${SHARE}/assets/chdk/source/"

install -d "${PKG}/usr/bin"
ln -s ../share/canonscope/tools/canonscope     "${PKG}/usr/bin/canonscope"
ln -s ../share/canonscope/tools/make-card.sh   "${PKG}/usr/bin/canonscope-make-card"
ln -s ../share/canonscope/tools/fetch-assets.sh "${PKG}/usr/bin/canonscope-fetch-assets"
ln -s ../lib/canonscope/chdkptp/chdkptp.sh     "${PKG}/usr/bin/chdkptp"

install -d "${PKG}/usr/lib/udev/rules.d"
install -m 0644 tools/udev/99-canonscope-camera.rules "${PKG}/usr/lib/udev/rules.d/"

# ---------------------------------------------------------------- docs
DOC="${PKG}/usr/share/doc/canonscope"
install -d "$DOC"
install -m 0644 README.md "${DOC}/README.md"
cat > "${DOC}/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: canonscope
Source: https://github.com/vredchenko/canonscope

Files: *
Copyright: 2026 canonscope contributors
License: MIT

Files: usr/lib/canonscope/chdkptp/*
Copyright: chdkptp authors (reyalp and contributors)
License: GPL-2.0
Comment: Built from https://github.com/svn2github/chdkptp commit ${PIN}.
 The corresponding source is attached to every canonscope GitHub release as
 chdkptp-src-${PIN:0:12}.tar.gz, and the full licence text is installed at
 /usr/lib/canonscope/chdkptp/COPYING.

License: MIT
$(sed 's/^$/./; s/^/ /' LICENSE)
COPYRIGHT

# ---------------------------------------------------------------- control
# Runtime deps: whatever packages own the libraries chdkptp actually links.
mapfile -t LIBS < <(ldd "${CHD}/chdkptp" | awk '/=> \//{print $3}')
DEPS=()
for lib in "${LIBS[@]}"; do
    real="$(readlink -f "$lib")"
    # dpkg -S also prints "diversion by ..." lines; keep only "pkg[:arch]: path".
    p="$( { dpkg -S "$lib" 2>/dev/null; dpkg -S "$real" 2>/dev/null; } \
        | sed -n 's/^\([a-z0-9][a-z0-9.+-]*\)\(:[a-z0-9]*\)\{0,1\}: .*/\1/p' | sed -n '1p' || true)"
    [[ -n "$p" && "$p" != libc6 ]] && DEPS+=("$p")
done
DEPENDS="$(printf '%s\n' bash coreutils util-linux libc6 "${DEPS[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')"
SIZE="$(du -sk "$PKG" | cut -f1)"

install -d "${PKG}/DEBIAN"
cat > "${PKG}/DEBIAN/control" <<CONTROL
Package: canonscope
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: canonscope maintainers <https://github.com/vredchenko/canonscope/issues>
Installed-Size: ${SIZE}
Depends: ${DEPENDS}
Recommends: dosfstools, fdisk, unzip, udev
Suggests: imagemagick, python3, uv, curl, jq, git
Section: graphics
Priority: optional
Homepage: https://github.com/vredchenko/canonscope
Description: drive a CHDK-enabled Canon PowerShot over USB
 canonscope is a small command-line front end to chdkptp for Canon cameras
 running CHDK, built around the PowerShot SX200 IS. It takes tethered photos
 straight to the host (nothing written to the SD card), grabs live-view
 frames, drives zoom and focus, and exposes all of it as JSON so that higher
 layers -- including an MCP server for Claude Code, shipped here too -- can
 bind to it.
 .
 Bundles a prebuilt chdkptp (GPL-2.0) built against Lua 5.2 and libusb 0.1,
 and a udev rule that stops desktop gvfs from claiming the camera.
CONTROL

cat > "${PKG}/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if [ "$1" = configure ] && command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger --subsystem-match=usb --action=add 2>/dev/null || true
fi
cat <<'MSG'
canonscope installed. For camera access over SSH (no desktop seat), add your
user to plugdev:  sudo usermod -aG plugdev "$USER"  and log in again.
MSG
exit 0
POSTINST
cat > "${PKG}/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if command -v udevadm >/dev/null 2>&1; then
    udevadm control --reload-rules 2>/dev/null || true
fi
exit 0
POSTRM
chmod 0755 "${PKG}/DEBIAN/postinst" "${PKG}/DEBIAN/postrm"

dpkg-deb --root-owner-group --build -Zxz "$PKG" "$DEB" >/dev/null
echo "==> ${DEB}"
dpkg-deb --info "$DEB" | sed -n '/Package:/,/Description:/p'
