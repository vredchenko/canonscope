#!/usr/bin/env bash
# Shared helpers for canonscope tools. Source, don't execute.

# Resolve the install root from this file's location, so scripts work from any
# cwd. In a source checkout that is the repository; in the .deb it is
# /usr/share/canonscope.
CANONSCOPE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANONSCOPE_VERSION="$(sed -n '1p' "${CANONSCOPE_ROOT}/VERSION" 2>/dev/null || true)"
CANONSCOPE_VERSION="${CANONSCOPE_VERSION:-unknown}"

# Where writable data goes. A source checkout keeps it beside the code, as it
# always has (captures/ and assets/ are gitignored). An installed copy is
# read-only, so it uses the XDG data directory instead. Both can be overridden.
if [[ -d "${CANONSCOPE_ROOT}/.git" ]]; then
    CANONSCOPE_DATA="${CANONSCOPE_DATA:-${CANONSCOPE_ROOT}}"
else
    CANONSCOPE_DATA="${CANONSCOPE_DATA:-${XDG_DATA_HOME:-${HOME}/.local/share}/canonscope}"
fi
# shellcheck disable=SC2034  # used by the scripts that source this file
ASSETS_DIR="${CANONSCOPE_ASSETS_DIR:-${CANONSCOPE_DATA}/assets}"
# shellcheck disable=SC2034
CAPTURE_DIR="${CANONSCOPE_CAPTURE_DIR:-${CANONSCOPE_DATA}/captures}"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

info()  { printf '%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%serr %s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

need() {
    local missing=()
    for t in "$@"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
    (( ${#missing[@]} == 0 )) || die "missing required tool(s): ${missing[*]}"
}

# Human-readable size for a byte count. Integer arithmetic only: `bc` is not
# part of a minimal install, and a missing bc used to print "0.0G" here.
human() {
    local b=$1
    if   (( b >= 1073741824 )); then
        printf '%d.%dG\n' "$(( b / 1073741824 ))" "$(( (b % 1073741824) * 10 / 1073741824 ))"
    elif (( b >= 1048576 ));    then echo "$((b/1048576))M"
    elif (( b >= 1024 ));       then echo "$((b/1024))K"
    else echo "${b}B"; fi
}

# Ask for typed confirmation. $1 = the exact string the user must type.
# Honours CANONSCOPE_ASSUME_YES=1 for non-interactive use.
confirm_exact() {
    local expect="$1" answer
    if [[ "${CANONSCOPE_ASSUME_YES:-0}" == "1" ]]; then
        warn "CANONSCOPE_ASSUME_YES=1 -- skipping confirmation for '$expect'"
        return 0
    fi
    [[ -t 0 ]] || die "need an interactive terminal to confirm (or set CANONSCOPE_ASSUME_YES=1)"
    printf '%sType exactly %s%s%s to proceed (anything else aborts): %s' \
        "$C_BOLD" "$C_RED" "$expect" "$C_RESET$C_BOLD" "$C_RESET"
    read -r answer
    [[ "$answer" == "$expect" ]] || die "aborted (got '${answer}')"
}

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
