#!/usr/bin/env bash
# Runs once, after the container is created.
#
# Deliberately cheap: it creates the Python environment the MCP server needs
# and nothing else. It does NOT fetch the 131 MB CHDK mirror or build chdkptp;
# run packaging/build-chdkptp.sh when you want those.
#
# This DOES need the network, to install the MCP SDK -- so a container rebuilt
# with no network fails here. The offline story is vendored wheels (see
# ROADMAP.md); until that exists this step assumes a connection.
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

echo "==> python: $(python3 --version)"

# The workspace is bind-mounted, so host and container share build/. They must
# NOT share a virtualenv: whichever ran last rewrites bin/python to ITS
# interpreter, and the other side is left with a venv pointing at a Python of
# the wrong version. One directory each.
VENV="build/mcpvenv"
[[ "${CANONSCOPE_IN_CONTAINER:-0}" == "1" ]] && VENV="build/mcpvenv-container"
echo "==> venv: ${VENV}"

# Test the venv by USING it, not by checking a file exists.
#
# build/ is gitignored and the workspace is bind-mounted, so a venv created on
# the host is visible in here with an interpreter symlinked to a host path --
# a uv-managed CPython that does not exist in the container. The old check was
# `[[ ! -x .../bin/python ]]`, which correctly came out TRUE (bash stats
# THROUGH a symlink, so -x is false for a dangling one) and so ran `uv venv`
# -- which then refused, because the directory was already occupied. The bug
# was never the test's truth value: it was that the only two states handled
# were "absent" and "fine", with no branch for "present but unusable".
#
# Importing through the venv covers all three, and --clear handles the
# occupied directory.
if ! "${VENV}/bin/python" -c 'import mcp' >/dev/null 2>&1; then
    echo "==> creating ${VENV} (none usable here)"
    uv venv --clear --python "$(command -v python3)" "$VENV"
    # Pinned, like UV_VERSION in the Dockerfile, and kept in step with
    # MCP_SDK in mcp/run-server.sh. Bump deliberately.
    uv pip install --python "${VENV}/bin/python" "mcp==2.3.0"
else
    echo "==> ${VENV} already usable"
fi

cat <<'EOF'

canonscope dev container ready.

  ./tools/tests/run-tests.sh              CLI + schema, no camera needed
  .devcontainer/verify.sh                 everything CI runs: lint, CLI, schema, MCP
  packaging/build-chdkptp.sh              build chdkptp from source (needs network)
  packaging/build-deb.sh                  build the .deb for this architecture

The camera is NOT reachable from in here -- no USB passthrough, and udev runs
on the host. Take photographs from the host.
EOF
