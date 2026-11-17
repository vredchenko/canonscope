#!/usr/bin/env bash
#
# Launch the canonscope MCP server, finding a Python that has the SDK.
#
# This exists so .mcp.json and the Claude Code plugin can name one stable
# command. Search order:
#
#   1. $CANONSCOPE_PYTHON, if set
#   2. a venv under build/ in a source checkout (build/mcpvenv*)
#   3. python3 on PATH, if it can already `import mcp`
#   4. uv, which fetches the pinned SDK into its cache on first run
#
# If none works it prints setup instructions rather than an ImportError.
#
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
root="$(cd "${here}/.." && pwd)"

# Keep in step with .devcontainer/post-create.sh.
MCP_SDK="mcp==2.3.0"

for py in "${CANONSCOPE_PYTHON:-}" \
          "${root}/build/mcpvenv/bin/python" \
          "${root}/build/mcpvenv-container/bin/python" \
          python3; do
    [[ -n "$py" ]] || continue
    command -v "$py" >/dev/null 2>&1 || [[ -x "$py" ]] || continue
    if "$py" -c 'import mcp' 2>/dev/null; then
        exec "$py" "${here}/canonscope_mcp.py" "$@"
    fi
done

if command -v uv >/dev/null 2>&1; then
    exec uv run --quiet --no-project --python '>=3.11' --with "$MCP_SDK" \
        python "${here}/canonscope_mcp.py" "$@"
fi

cat >&2 <<MSG
No Python with the MCP SDK was found, and uv is not installed.

Either install uv (https://docs.astral.sh/uv/) and nothing else is needed, or
set up a virtualenv by hand:

    python3 -m venv build/mcpvenv
    build/mcpvenv/bin/pip install '${MCP_SDK}'

or point CANONSCOPE_PYTHON at an interpreter that already has it.
Offline: download the wheels on a connected machine first, then
    pip install --no-index --find-links=<dir> '${MCP_SDK}'
MSG
exit 1
