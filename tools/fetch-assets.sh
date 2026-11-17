#!/usr/bin/env bash
#
# fetch-assets.sh -- mirror everything canonscope depends on into assets/
#
# The CHDK ecosystem is old and fragile: the wiki sits behind Cloudflare, the
# autobuild server keeps only current builds, and chdkptp's home (Assembla)
# now refuses anonymous access. Keep a local copy of all of it.
#
# Idempotent: already-downloaded files are skipped unless --force.
# Every payload is checksummed into assets/SHA256SUMS.
#
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/common.sh"

CAMERA_PLATFORM="sx200is"
CHDK_VERSION="1.6.1"
CHDK_REVISION="6355"
CHDK_FIRMWARES=(100c 100d)
AUTOBUILD_BASE="https://mighty-hoernsche.de"
WIKI_API="https://chdk.fandom.com/api.php"
SOURCE_MIRROR="https://github.com/01luna/CHDK.git"
CHDKPTP_MIRROR="https://github.com/svn2github/chdkptp.git"
UA='Mozilla/5.0 (X11; Linux x86_64) canonscope-fetch-assets'

# Wiki pages worth having offline, as exact page titles.
WIKI_PAGES=(
    "SX200IS"
    "Prepare your SD card"
    "PTP Extension"
    "USB Remote"
    "CHDK and SD cards greater than 4GB (8GB, 16GB, 32GB, 64GB)"
    "CHDK 1.6 User Manual"
    "FAQ"
    "Lua/Lua Reference"
    "Lua/Lua Reference/Native Function Calls"
    "Lua/Lua syntax"
    "Script commands"
    "Scripts"
    "CHDK scripting"
    "CHDK 1.3.0 User Manual"
)

FORCE=0
ONLY=""
usage() {
    cat <<EOF
Usage: ${0##*/} [--force] [--only builds|source|wiki|chdkptp]

Mirrors CHDK builds, source, wiki pages and the chdkptp source into the assets
directory (\$CANONSCOPE_ASSETS_DIR; assets/ in a source checkout, otherwise
~/.local/share/canonscope/assets).

  --force          re-download even if the file already exists
  --only <group>   fetch just one group (default: all)

Writes into: ${ASSETS_DIR}
EOF
}
while (( $# )); do
    case "$1" in
        --force) FORCE=1 ;;
        --only)  ONLY="${2:?--only needs a group}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1' (try --help)" ;;
    esac
    shift
done

need curl git sha256sum
wanted() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

# download <url> <dest>
download() {
    local url="$1" dest="$2"
    if [[ -s "$dest" && $FORCE -eq 0 ]]; then
        ok "have $(basename "$dest") ($(human "$(stat -c%s "$dest")"))"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    info "GET $url"
    # Download to a temp file so an interrupted run never leaves a truncated asset.
    if ! curl -fsSL -A "$UA" "$url" -o "${dest}.part"; then
        rm -f "${dest}.part"
        err "failed: $url"
        return 1
    fi
    mv "${dest}.part" "$dest"
    ok "saved $(basename "$dest") ($(human "$(stat -c%s "$dest")"))"
}

# ---------------------------------------------------------------- CHDK builds
fetch_builds() {
    info "CHDK ${CHDK_VERSION} rev ${CHDK_REVISION} builds for ${CAMERA_PLATFORM}"
    local dir="${ASSETS_DIR}/chdk/builds" fw name
    for fw in "${CHDK_FIRMWARES[@]}"; do
        # The "full" zip is the complete distribution -- required for the
        # bootable-card method. The small zip omits extras.
        for suffix in "-full" ""; do
            name="${CAMERA_PLATFORM}-${fw}-${CHDK_VERSION}-${CHDK_REVISION}${suffix}.zip"
            download "${AUTOBUILD_BASE}/bins/${name}" "${dir}/${name}" || true
        done
    done
    # Keep the index page too: it is the only record of what was current.
    download "${AUTOBUILD_BASE}/" "${dir}/autobuild-index-$(date +%Y%m%d).html" || true
}

# ------------------------------------------------------------------ CHDK source
fetch_source() {
    info "CHDK source trunk (mirror of the official SVN)"
    local dir="${ASSETS_DIR}/chdk/source/CHDK"
    if [[ -d "${dir}/.git" ]]; then
        if (( FORCE )); then
            info "updating existing clone"
            git -C "$dir" fetch --depth 1 origin && git -C "$dir" reset --hard origin/HEAD
        else
            ok "have source clone ($(git -C "$dir" rev-parse --short HEAD))"
        fi
    else
        mkdir -p "$(dirname "$dir")"
        git clone --depth 1 "$SOURCE_MIRROR" "$dir"
    fi
    # Record exactly what we pinned; the mirror moves.
    git -C "$dir" log -1 --format='%H %cI %s' > "${ASSETS_DIR}/chdk/source/PINNED.txt"
    ok "pinned $(cat "${ASSETS_DIR}/chdk/source/PINNED.txt")"

    # The platform directory is the part we actually reason about -- keep a
    # flat copy so it survives even if the clone is pruned.
    local plat="${dir}/platform/${CAMERA_PLATFORM}"
    if [[ -d "$plat" ]]; then
        mkdir -p "${ASSETS_DIR}/chdk/platform"
        cp -r "$plat" "${ASSETS_DIR}/chdk/platform/"
        ok "copied platform/${CAMERA_PLATFORM}"
    else
        warn "platform/${CAMERA_PLATFORM} not found in the clone"
    fi
}

# -------------------------------------------------------------------- the wiki
fetch_wiki() {
    info "CHDK wiki pages (via api.php -- the rendered wiki is Cloudflare-walled)"
    need jq
    local dir="${ASSETS_DIR}/chdk/wiki" page slug url enc sz
    mkdir -p "$dir"
    for page in "${WIKI_PAGES[@]}"; do
        # Slug for the filename; the API gets the real title URL-encoded.
        slug="$(echo "$page" | tr ' /' '__' | tr -cd '[:alnum:]_().-')"
        enc="$(jq -rn --arg s "$page" '$s|@uri')"
        url="${WIKI_API}?action=parse&prop=wikitext&format=json&formatversion=2&redirects=1&page=${enc}"
        if [[ -s "${dir}/${slug}.wiki" && $FORCE -eq 0 ]]; then
            ok "have ${slug}.wiki"
            continue
        fi
        info "wiki: ${page}"
        # NOTE: `jq -e` on empty input is VERSION-DEPENDENT. jq 1.6 (Ubuntu
        # jammy) exits 0, so an empty .raw.json sails through and writes an
        # empty .wiki; jq 1.7 (Debian trixie) exits 4. Both
        # verified 2026-11-06. The size check below does catch the empty file,
        # but reports it as a "redirect stub" -- the wrong cause. Testing the
        # raw file explicitly makes the behaviour the same on both, and the
        # diagnosis match the fault.
        if curl -fsSL -A "$UA" "$url" -o "${dir}/.raw.json" \
           && [[ -s "${dir}/.raw.json" ]] \
           && jq -e -r '.parse.wikitext' "${dir}/.raw.json" > "${dir}/${slug}.wiki" 2>/dev/null; then
            sz="$(stat -c%s "${dir}/${slug}.wiki")"
            if (( sz < 500 )); then
                warn "${slug}.wiki is only ${sz}B -- likely a redirect stub or error; discarding"
                rm -f "${dir}/${slug}.wiki"
            else
                ok "saved ${slug}.wiki ($(human "$sz"))"
            fi
        else
            rm -f "${dir}/${slug}.wiki"
            warn "could not fetch wiki page '${page}'"
        fi
        rm -f "${dir}/.raw.json"
    done
}

# -------------------------------------------------------------------- chdkptp
fetch_chdkptp() {
    info "chdkptp (host-side PTP client)"
    local dir="${ASSETS_DIR}/chdkptp/svn2github-mirror"
    warn "chdkptp upstream is Assembla SVN, which now returns 401 to anonymous"
    warn "clients. The only free mirror is stale (last commit 2018-09). Treat"
    warn "this as a starting point, not the current release -- see ROADMAP.md."
    if [[ -d "${dir}/.git" ]]; then
        ok "have chdkptp mirror ($(git -C "$dir" rev-parse --short HEAD))"
    else
        mkdir -p "$(dirname "$dir")"
        git clone --depth 1 "$CHDKPTP_MIRROR" "$dir" || warn "chdkptp clone failed"
    fi
    [[ -d "${dir}/.git" ]] && git -C "$dir" log -1 --format='%H %cI %s' \
        > "${ASSETS_DIR}/chdkptp/PINNED.txt" || true
}

# ------------------------------------------------------------------- manifest
write_manifest() {
    info "writing manifest and checksums"
    mkdir -p "$ASSETS_DIR"
    # Git-managed trees are verified by their pinned commit hash, not file by
    # file -- checksumming 8600 clone files would swamp the manifest.
    ( cd "$ASSETS_DIR" && find . \
        \( -path './chdk/source/CHDK' -o -path './chdkptp/svn2github-mirror' \) -prune -o \
        -type f ! -name 'SHA256SUMS' ! -name 'MANIFEST.md' -print0 \
        | sort -z | xargs -0 sha256sum ) > "${ASSETS_DIR}/SHA256SUMS"
    {
        echo "# assets manifest"
        echo
        echo "Generated by \`tools/fetch-assets.sh\` on $(date -Iseconds)."
        echo "Re-run that script to refresh; verify with \`sha256sum -c SHA256SUMS\`."
        echo
        echo "Target: Canon PowerShot SX200 IS (\`${CAMERA_PLATFORM}\`),"
        echo "CHDK ${CHDK_VERSION} rev ${CHDK_REVISION}, firmwares: ${CHDK_FIRMWARES[*]}."
        echo
        echo '| File | Size | SHA256 (first 16) |'
        echo '| --- | --- | --- |'
        while read -r sum path; do
            path="${path#./}"
            printf '| `%s` | %s | `%s` |\n' \
                "$path" "$(human "$(stat -c%s "${ASSETS_DIR}/${path}")")" "${sum:0:16}"
        done < "${ASSETS_DIR}/SHA256SUMS"
    } > "${ASSETS_DIR}/MANIFEST.md"
    ok "$(wc -l < "${ASSETS_DIR}/SHA256SUMS") files checksummed"
}

mkdir -p "$ASSETS_DIR"
wanted builds  && fetch_builds
wanted source  && fetch_source
wanted wiki    && fetch_wiki
wanted chdkptp && fetch_chdkptp
write_manifest
info "done -- assets in ${ASSETS_DIR}"
