# canonscope MCP server

Exposes the camera to Claude Code and any other MCP client as seven tools.
Design reasoning lives in [../docs/10-control-surface.md](../docs/10-control-surface.md);
this file is how to run it.

**It is a thin wrapper over `tools/canonscope`.** Every tool shells out to that
CLI and parses its `--json` output; none of them touch `chdkptp` directly. The
CLI is tier 0 (bash and coreutils, runs on a bare controller); this server is tier 1,
and tier 1 must never become a dependency of tier 0.

## Setup

**Verified 2026-11-06** on CPython 3.13, with `mcp` **2.3.0**.

Usually there is nothing to set up. `mcp/run-server.sh` looks for a Python
that already has the SDK (`$CANONSCOPE_PYTHON`, a venv under `build/`, or
`python3`). Failing that, it runs the server through
[uv](https://docs.astral.sh/uv/) with the pinned SDK, which uv caches after
the first run. To make a venv by hand:

```sh
uv venv build/mcpvenv
uv pip install --python build/mcpvenv/bin/python 'mcp==2.3.0'
```

Offline, from wheels downloaded on a connected machine:

```sh
# connected: 28 wheels, 9.3 MB; all four native wheels have aarch64 builds,
# so no Rust toolchain is needed on a Raspberry Pi
pip download 'mcp==2.3.0' --platform manylinux2014_aarch64 --python-version 3.13 \
    --implementation cp --abi cp313 --only-binary=:all: -d wheels/

# on the controller
pip install --no-index --find-links=wheels/ 'mcp==2.3.0'
```

The server needs the camera attached to the machine it runs on, and a
chdkptp. The CLI finds `build/chdkptp`, the `.deb`'s bundled copy, or one on
`PATH`.

## Register with Claude Code

- **As a plugin**: see the README's "Add it to Claude Code" section. The
  plugin starts this server and adds a skill describing how to use it.
- **Inside a clone**: `.mcp.json` at the repo root declares it at project
  scope, so Claude Code prompts you to approve it.
- **By hand**: `claude mcp add --scope project canonscope -- mcp/run-server.sh`

Don't enable both the plugin and the project-scoped server in the same
session, or the tools will appear twice.

## Tools

| Tool | Annotation | Notes |
| --- | --- | --- |
| `camera_get_status` | read-only | battery, temperatures, card, zoom, exposure — one round trip |
| `camera_get_capabilities` | read-only | static facts; cacheable for a session |
| `camera_capture_photo` | — | **returns a path, not the image** |
| `camera_live_view` | read-only | no shutter, no card write |
| `camera_set_zoom` | — | 126 steps, or `wide`/`tele` |
| `camera_set_focus` | — | **metres**, or omit for autofocus |
| `camera_run_lua` | destructive, open-world | the escape hatch |

**`camera_capture_photo` returns a path deliberately.** Inlining a 4000×3000
JPEG as a base64 `ImageContent` block is extremely token-expensive, and there
are open reports of such blocks arriving at the model as raw text rather than
as a vision block. Returning a path lets the client read the file with its own
image handling. See docs/10.

**Distances are in metres, not millimetres.** The CLI speaks CHDK's native
units; this layer converts. Device units are a reliable source of error for a
model, and that is not a guess — see the Needle experiments in
`experiments/needle/`.

## Tests

```sh
uv run --no-project --with 'mcp==2.3.0' python mcp/test-server.py
.devcontainer/verify.sh            # inside the dev container
```

These drive a real stdio MCP session against the fake `chdkptp` in
`tools/tests/fake-chdkptp/`, so no camera is required.

**Host and dev container keep separate virtualenvs** (`build/mcpvenv` and
`build/mcpvenv-container`). `build/` is bind-mounted, and a shared venv gets
its `bin/python` rewritten to whichever interpreter ran last.

The tests assert that **the CLI's own diagnostics reach the client**. That
isn't automatic: the SDK replaces any ordinary exception with a generic
"raised an unexpected exception", so `CameraError` subclasses the SDK's
`ToolError`, whose message is passed through. Without it, "the camera is
switched off" and "that is not a valid zoom step" look identical to the
caller.

## Not yet true

**The server has never driven the real camera.** Every tool has been exercised
over a real MCP stdio session, but only against the fake `chdkptp`.
