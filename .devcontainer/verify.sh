#!/usr/bin/env bash
# Run everything that does not need a camera. This is also what CI runs.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

echo "=== environment ==="
[[ "${CANONSCOPE_IN_CONTAINER:-0}" == "1" ]] \
    && echo "  running INSIDE the dev container (no USB, no camera)" \
    || echo "  running on the host"

# Each of these is a hard requirement of something in this repo, so a missing
# one must FAIL rather than print an empty field.
#
# NOTE: assign, do not interpolate. A failing pipeline inside a command
# substitution used as a printf ARGUMENT has its status discarded even under
# `set -e`; the same pipeline in an assignment does not. An earlier version of
# this file interpolated, so a missing binary printed blank and passed.
for req in bash python3 jq git lua5.2 uv shellcheck; do
    command -v "$req" >/dev/null 2>&1 || fail "missing required tool: $req"
done
v_python="$(python3 --version 2>&1)"
v_jq="$(jq --version)"
v_lua="$(lua5.2 -v 2>&1 | sed -n '1p')"
# `preview --format png` uses ImageMagick as `magick` (IM7) or `convert` (IM6,
# or IM7's compatibility alias). Require one of the two names.
im="$(command -v magick || command -v convert || true)"
[[ -n "$im" ]] || fail "missing ImageMagick (magick or convert)"
v_im="$("$im" --version 2>&1 | sed -n '1p' | cut -c1-48)"
printf '  %-10s %s\n' bash "$BASH_VERSION" python3 "$v_python" jq "$v_jq" \
       lua "$v_lua" imagemagick "$v_im" uv "$(uv --version)" \
       shellcheck "$(shellcheck --version | sed -n 's/^version: //p')"

echo
echo "=== shell syntax ==="
# Globs do not cross `/`, so each depth needs naming. mcp/run-server.sh is the
# entry point .mcp.json invokes, and tools/tests/fake-chdkptp/chdkptp.sh is
# what every one of the test assertions runs through -- both were missed by an
# earlier version of this sweep, under a message claiming "all".
swept=0
scripts=()
for f in tools/canonscope tools/*.sh tools/lib/*.sh tools/tests/*.sh \
         tools/tests/fake-chdkptp/*.sh mcp/*.sh .devcontainer/*.sh \
         packaging/*.sh experiments/needle/*.sh; do
    [[ -f "$f" ]] || continue
    bash -n "$f" || fail "syntax error in $f"
    scripts+=("$f")
    swept=$((swept + 1))
done
(( swept >= 18 )) || fail "only ${swept} scripts swept -- a glob has stopped matching"
echo "  ok  ${swept} shell scripts parse"
shellcheck -x -S warning "${scripts[@]}" || fail "shellcheck reported warnings"
echo "  ok  shellcheck clean at warning level"

echo
echo "=== versions and plugin manifests ==="
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json tools/canonscope.tools.json; do
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$j" || fail "invalid JSON: $j"
done
echo "  ok  manifests parse"
packaging/check-version.sh

echo
echo "=== private-identifier guard ==="
# Generic patterns (LAN/CGNAT addresses, MACs, home paths, keys, tokens) always
# run. A personal list of your own hostnames and names is added if present --
# see tools/check-private.sh.
./tools/check-private.sh

echo
echo "=== CLI and schema ==="
./tools/tests/run-tests.sh

echo
echo "=== MCP server ==="
# Same split as post-create.sh: host and container keep separate venvs,
# because build/ is bind-mounted and a shared one gets rewritten to whichever
# interpreter ran last.
venv="build/mcpvenv"
[[ "${CANONSCOPE_IN_CONTAINER:-0}" == "1" ]] && venv="build/mcpvenv-container"
[[ -x "${venv}/bin/python" ]] || fail "${venv} missing -- run .devcontainer/post-create.sh"
"${venv}/bin/python" mcp/test-server.py
