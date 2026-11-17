#!/usr/bin/env bash
#
# check-version.sh [TAG] -- assert that every place a version is written agrees.
#
#   VERSION                          the source of truth, X.Y.Z
#   .claude-plugin/plugin.json       "version"
#   .claude-plugin/marketplace.json  the canonscope plugin entry's "version"
#   TAG (optional)                   must be vX.Y.Z -- the release workflow
#                                    passes the pushed tag here
#
# bash + coreutils + sed only, so it runs anywhere the tools do.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

want="$(sed -n '1p' VERSION)"
[[ "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION '$want' is not X.Y.Z" >&2; exit 1; }

json_versions() { sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1"; }

fail=0
check() {
    if [[ "$2" == "$want" ]]; then echo "  ok   $1 = $2"
    else echo "  FAIL $1 = '${2}', VERSION = ${want}" >&2; fail=1; fi
}
check ".claude-plugin/plugin.json" "$(json_versions .claude-plugin/plugin.json)"
check ".claude-plugin/marketplace.json" "$(json_versions .claude-plugin/marketplace.json)"
if (( $# )); then check "tag $1" "${1#v}"; [[ "$1" == v* ]] || { echo "  FAIL tag must start with v" >&2; fail=1; }; fi
exit "$fail"
