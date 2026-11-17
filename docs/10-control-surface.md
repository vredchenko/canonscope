# The control surface: CLI, MCP server, local action model

Written 2026-11-06, the same day as the `canonscope` CLI. That CLI is phase 1 and
is built; this document designs phases 2a, 2b and 3 on top of it.
[09-capability-inventory.md](09-capability-inventory.md) is the inventory of
what the camera can do; this is about how things that are not a person at a
shell get to drive it.

Provenance in this document:

- **Verified 2026-11-06** — measured on that date and reported as measured.
  Three kinds, each named where it appears: timings against the camera from
  [09](09-capability-inventory.md) §11; `pip download` resolutions run on the
  workstation; and packages **installed, imported and run locally** on the
  workstation — an **x86_64** box with CPython 3.13. That last caveat matters:
  nothing in phases 2a or 2b has been executed on an arm64 board. Installability
  and cross-fetching are verified; runtime on the Pi is not.
- **Researched** — desk research on 2026-11-06 against package indexes, READMEs,
  changelogs, the MCP specification and public issue trackers and discussion
  threads. Not run. Version strings are quoted exactly as found and will go
  stale; the dates are there so a reader knows how stale.
- **Untested** — design decisions made here. Nothing in phases 2a, 2b or 3 has
  been built, and the phase 1 CLI itself has not yet completed a round trip
  against the camera (ROADMAP.md).

## 1. Four phases, one contract

```
  Claude Code, other MCP clients            a person, typing, offline
          |                                          |
          |  MCP over stdio                          |  natural language
          v                                          v
  camera_mcp_server.py  (phase 2a)        canonscope-say  (phase 2b, Needle)
          |                                          |
          +-------------> canonscope --json <--------+        phase 1, built
                                 |
                                 v
                         chdkptp --USB--> CHDK --> camera
```

**Phase 1 is the `canonscope` CLI**, in `tools/canonscope` with `tools/lib/camera.sh`
under it. Seven verbs — `status`, `capabilities`, `shoot`, `preview`, `zoom`,
`focus`, `lua` — and every verb takes `--json`. It is bash + coreutils only, as
CLAUDE.md requires of anything in `tools/`, so it runs on a freshly installed Pi
with nothing added. Two measurements shaped it and shape everything below
(**Verified 2026-11-06**, [09](09-capability-inventory.md) §11): a chdkptp
connect → trivial Lua → quit costs **0.66 s, 0.51 s, 0.52 s** over three runs,
which is why there is no daemon; and `status` returns **21 fields in one round
trip**, which is the batching pattern every verb follows. `lua` is the escape
hatch to the roughly 200 on-camera Lua functions the other six verbs will never
wrap.

**Phase 2a is an MCP server** that presents the verbs as tools, so Claude Code
and any other MCP client can drive the camera without being taught the CLI.

**Phase 2b is Needle**, a small local function-calling model, so the camera can
be driven in natural language with no cloud and no workstation.

**Phase 3 is the question of whether 2a and 2b have anything to do with each
other** beyond sitting on the same CLI. §7 argues they mostly do not, and that
this is fine.

The design constraint that makes all of this tractable is in the CLI's own
header comment: **the CLI is the contract.** Both higher layers bind to
`canonscope --json` and to nothing underneath it. §4 defends that against the
obvious objection.

## 2. Which tier each phase lives in

[06-controller-host.md](06-controller-host.md) defines three connectivity tiers and one rule:
tier 0 must be self-sufficient, and **nothing in tier 1 or 2 may become a
dependency of it**. The CLI is bash. The MCP server and Needle are both Python,
with wheels and — for Needle — model weights that have to come from somewhere.
That tension needs resolving before any of it is built, not after.

**The CLI is tier 0, and it is the whole of tier 0's control surface.** It
depends on bash, coreutils and a prebuilt chdkptp, all of which are already on
the tier 0 vendoring list. The rule that follows is simple and must stay
simple: **the CLI never imports, calls, sources or reads anything from phase 2a
or 2b.** No `canonscope` verb shells out to Python; no shared config file lives
on the Python side. The dependency arrow points one way, upward, and a test can
enforce it (`grep -l python tools/canonscope tools/lib/*.sh` should stay empty).

**The MCP server is tier 1 by nature, not by accident.** An MCP server is
inert without a model on the other end of the pipe, and the model that drives
it here is Claude Code, which [06](06-controller-host.md) keeps off the 2 GB board. So
MCP only ever happens when the workstation is present — which is exactly the
definition of tier 1. There is no version of phase 2a that works in tier 0, and
no reason to pretend otherwise. Its wheels are still vendored (§5), because
tier 1 is "workstation present", not "internet present".

**Needle is the interesting case: tier-0-compatible, but not tier-0-required.**
Its entire point is to work offline on the Pi, so it belongs on the board and
its wheels and weights belong on the thumb drive. But it is Python, it is a
year-old project that has already renamed its import path once (§6), and a
model that returns the wrong tool is a worse operator than a shell. So Needle is
an **optional extra inside tier 0**: present on the thumb drive, installable
offline, and if it is absent or broken the rig loses natural-language input and
nothing else. The autonomous guarantee is carried by the CLI alone.

Put as a table, because the tier of each thing is the fact people will look up:

| Layer | Runs on | Tier | Depends on | Depended on by |
| --- | --- | --- | --- | --- |
| `canonscope` CLI | the host the camera is plugged into | **0** | bash, coreutils, chdkptp | 2a, 2b, humans |
| MCP server (2a) | the workstation, beside Claude Code | **1** | Python, `mcp`, SSH to the camera host, the CLI | Claude Code |
| Needle front end (2b) | the Pi | **0, optional** | Python, `cactus-compute`, vendored weights, the CLI | a person at the Pi |

**Where the MCP server runs is a decision, not a detail** (**Untested**). It
could run on the Pi and be reached by Claude Code as a stdio command over SSH —
stdio is only pipes, so `ssh pi python3 camera_mcp_server.py` works as a
transport. That would keep the Python next to the camera but it would also mean
every image path the server returns is a Pi path, which Claude Code's `Read`
tool on the workstation cannot open, and the whole point of returning paths
rather than image blocks (§5) is that `Read` can render them. So the server runs
**on the workstation**, and treats the camera host as a transport detail: with
nothing configured it runs `canonscope` locally, which is today's situation;
with a host configured it runs `ssh <host> canonscope --json ...` and pulls
files back with `scp`. The host comes from the environment or
`~/.config/canonscope/`, never from a tracked file — the repo is kept
publishable and `.mcp.json` is tracked. This also keeps the Pi entirely free of
phase 2a, which is the cleanest possible reading of the tier rule. It matches
[09](09-capability-inventory.md) §11: the Pi changes where the CLI runs, not
what it is.

## 3. Phase 1 recap: what the contract actually is

Worth stating precisely, because the two layers above will encode it.

**Success is JSON on stdout and exit 0.** `status --json` and `capabilities
--json` return flat objects of integers and strings (**Source**: `json_from_pairs`
in `tools/lib/camera.sh` emits numeric-looking values bare, `true`/`false`/`null`
bare, everything else quoted). `shoot --json` returns `{"ok":true,"path":...}`;
`preview --json` returns `{"ok":true,"count":N,"frames":[...]}`; `zoom`, `focus`
and `lua` return `ok` plus the resulting value.

**Failure is non-zero exit and a message on stderr, not JSON.** `die` in
`tools/lib/common.sh` prints to stderr and exits 1; connection failure is fatal
in `cam_exec`. That is the right shape for a shell and it is also fine for a
wrapper: exit code non-zero becomes an MCP `isError` result or a Needle
"could not" reply, and stderr becomes its text. The wrappers must not try to
parse stdout on failure.

**`lua --json` returns the camera's value as a string**, whatever its type,
because `cam_lua` strips chdkptp's `<serial>:return:'...'` framing and hands
back text. A wrapper that wants a number does the conversion itself.

**Two safety behaviours live in the CLI, and must stay there** rather than being
re-implemented above it: `zoom` refuses to drive the motor below 3400 mV on
battery (override `CANONSCOPE_FORCE=1`), and `shoot` inherits `capture.sh`'s
flash-off default, which is load-bearing after the 69% brownout in
[02-power.md](02-power.md). Anything the wrappers add is on top of these, not
instead.

**Options the wrappers will expose**, from `tools/capture.sh`: `--tv` shutter in
seconds (`0.5`, `1/60`), `--sv` ISO as Canon "real", `--sd` subject distance
(`2m`), `--flash off|auto|on|keep`, `--out PATH`. From `preview`: `-n N`,
`--out DIR`, `--format ppm|png`. `zoom` takes a step, `+n`, `-n`, `wide` or
`tele`; `focus` takes millimetres or `auto`.

## 4. Shell out, or bind deeper?

The question was put directly: should 2a and 2b shell out to `canonscope
--json`, bind into code beneath the CLI for finer granularity, or both? The
answer comes from the measurement rather than from taste.

**The half-second is chdkptp's, and a binding would not get it back.** The
0.51–0.66 s per invocation (**Verified 2026-11-06**) is the cost of starting the
chdkptp process, enumerating USB, opening a PTP session, exchanging CHDK's
version handshake, and tearing it all down. A Python binding has three ways to
avoid the shell, and only one of them removes that cost:

1. **Subprocess chdkptp from Python.** Identical cost, minus the bash. Nothing
   gained but a second parser for chdkptp's output.
2. **Link chdkptp's C core or drive its Lua from Python.** Still pays the USB
   and PTP open unless the session is held open — at which point this is a
   daemon, with a lifecycle, a stale-connection problem, and the question of
   what happens when the camera auto-powers-off under it.
3. **Reimplement CHDK's PTP extensions over `pyusb`.** This is the only option
   that genuinely drops per-operation latency to tens of milliseconds, and it
   is a rewrite of `chdku.lua` and the protocol negotiation that ROADMAP.md
   records as the project's narrowest surviving risk, against a 2018 client
   mirror because upstream SVN returns 401. It would be a second implementation
   of the one thing in this project nobody can refresh from source.

**So a deeper binding earns its complexity under exactly one condition**: a
workload that needs sustained operations faster than roughly two per second
*and* cannot be batched into one chdkptp invocation *and* cannot be pushed onto
the camera. None of the planned uses meets it, and the CLI already has the two
tools that make it hard to meet:

- **Batching inside one connection.** Several `-e` flags run in order on one
  session; `status` reads 21 values in one round trip for this reason, and
  `preview -n N` streams N frames inside one `lvdumpimg -count=N`.
- **The `lua` escape hatch moves the loop onto the camera.** A focus stack, a
  bracket, a wait-for-motion-then-shoot: each is a dozen lines of on-camera Lua
  that runs with no USB in the trigger path at all. The round-trip count goes
  to one, which is a better answer than making round trips cheaper. This is
  what `lua` does to the binding argument: it removes most of the cases that
  would have justified one.

**Decision: both layers shell out to `canonscope --json`, and only to that**
(**Untested** as an implementation, but the reasoning rests on verified
numbers). The practical consequences are the ones that matter on a project this
small: there is exactly one tested surface (`tools/tests/run-tests.sh`, 38
assertions against a fake chdkptp, which the wrappers inherit for free); there
is one place where the safety behaviours live; and a bug in the camera path
shows up identically whether a person, Claude or Needle triggered it. The MCP
server adds one Python startup per *session*, not per call, because the server
is a long-lived subprocess of Claude Code; Needle adds one model load per
session. Neither moves the per-call cost off the half-second it already is.

**The granularity argument, taken seriously.** Finer-grained control — set
`tv96` here, nudge `av96` there, read a histogram between — is real, and the
answer is not a binding but a verb. If a composite operation is wanted often
enough to name, it becomes a CLI verb, built the same way as the others, and
both wrappers get it by re-reading the schema (§7). Until then it is a `lua`
call. The thing to resist is letting the MCP server or the Needle front end
grow camera logic of their own; the moment either does, there are two places
the APEX96 maths can be wrong.

## 5. Phase 2a — the MCP server

### Protocol and SDK

The protocol facts are **Researched 2026-11-06**; the SDK facts were then
checked by installing it, and are **Verified 2026-11-06 (installed and
imported locally)** on x86_64 with CPython 3.13.

- The current MCP specification revision is **2026-07-28** (the previous was
  2025-06-18). The normative artefact is the TypeScript schema in
  `modelcontextprotocol/specification`; everything else is commentary on it.
  (Researched.)
- The Python SDK is the PyPI package **`mcp`**, and `uv pip install mcp` into a
  Python 3.13 venv installs **2.3.0** cleanly. (Verified.)
- **`from mcp.server import MCPServer` works. `from mcp.server.fastmcp import
  FastMCP` raises `ModuleNotFoundError`.** (Verified.) This is stronger than the
  research suggested: the SDK v2.0 change is not a rename behind a
  compatibility shim, **the old module is gone entirely**. A reader who copies
  any 2025-era tutorial gets an immediate hard failure on the first import,
  not a deprecation warning.
- **The two imports a server needs come from different paths**, which is an
  easy thing to get wrong (Verified):

  ```python
  from mcp.server import MCPServer           # the server class
  from mcp.server.mcpserver import Image     # the image helper; NOT in mcp.server
  ```

  `mcp.types.ImageContent` also exists, for building the block by hand.
- **`MCPServer.tool()` accepts `name`, `title`, `description`, `annotations`
  (typed `ToolAnnotations | None`), `icons` and `meta`** (Verified), so the
  spec's tool annotations are set directly in the decorator rather than bolted
  on afterwards.
- The standalone **`fastmcp`** package (v3.x) is a different and heavier
  project built on the SDK, adding OAuth, server composition and proxying.
  None of that is wanted for a local stdio server on a 2 GB board, and
  **the bare `mcp` SDK is the choice here.** (Researched.)
- Two transports exist, **stdio** and Streamable HTTP; the older HTTP+SSE is
  deprecated. **stdio is correct**: Claude Code spawns the server as a
  subprocess, there is no listener, no port and no authentication surface,
  and it matches the standing "no separate web server" decision in
  [06](06-controller-host.md). (Researched.)

The smallest illustrative shape, with the imports and the decorator's real
signature, and deliberately no more than that:

```python
from mcp.server import MCPServer
from mcp.server.mcpserver import Image
from mcp.types import ToolAnnotations

mcp = MCPServer("canonscope")

@mcp.tool(
    name="camera_get_status",
    annotations=ToolAnnotations(readOnlyHint=True),
)
def camera_get_status() -> dict:
    """Read the rig's health in one round trip ..."""
    return run_cli("status")               # subprocess: canonscope --json status
```

### Registration

`claude mcp add --scope project camera-control -- <command>` writes a
project-scoped `.mcp.json` (**Researched**). That file is project configuration
in the same sense `.claude/settings.json` is, and it should be committed. Two
rules for its contents: **no hostname, address or username**, per the
publishability guard — the camera host comes from the environment at runtime —
and **the command is a bash launcher, not `python3`**. A bare `python3` may
not have the SDK, may be a version-manager shim that refuses to dispatch, and
the system Python should not be modified to fix that. So the launcher
(`mcp/run-server.sh`) finds a virtualenv that has the SDK, or provisions one
through `uv`.

**The server does not live in `tools/`, and that is the constraint deciding
it.** CLAUDE.md requires everything in `tools/` to be bash and coreutils only,
so that it runs unchanged on a freshly installed Pi. A Python MCP server cannot
satisfy that, and putting it there would quietly erode the one rule that makes
tier 0 legible. It lives in `mcp/` instead, alongside `experiments/`, as the
tier-1 half of the tree:

    mcp/run-server.sh        bash launcher, named by .mcp.json
    mcp/canonscope_mcp.py    the server
    mcp/test-server.py       33 assertions, no camera

The launcher searches `build/mcpvenv/bin/python`, then `$CANONSCOPE_PYTHON`,
then `python3`, taking the first that can `import mcp` — and prints setup
instructions rather than an `ImportError` when none can. The venv is created
from the vendored wheels below.

### Vendoring the wheels

**Verified 2026-11-06 (run on this machine).** This is the claim that gates the
Pi story, so it was run rather than reasoned about:

```sh
pip download mcp \
    --platform manylinux2014_aarch64 --python-version 3.13 \
    --implementation cp --abi cp313 --only-binary=:all: -d wheels
```

resolved **28 wheels, 9.3 MB in total**, with no source distributions and
nothing to compile. Exactly **four native wheels**, every one with a prebuilt
aarch64 manylinux build:

- `pydantic_core-2.50.4-cp313-cp313-manylinux2014_aarch64`
- `cryptography-50.0.2-cp311-abi3-manylinux2014_aarch64`
- `cffi-2.1.1-cp313-cp313-manylinux2014_aarch64`
- `rpds_py-2026.9.1-cp313-cp313-manylinux_2_17_aarch64`

So **no Rust or cargo toolchain is needed on the Pi.** The set mirrors onto the
USB artefact store with checksums exactly like the CHDK material — another
`--only` group in `tools/fetch-assets.sh`, landing under `/artefacts/wheels/` —
and installs with `pip install --no-index --find-links=/artefacts/wheels mcp`.

**Bare `mcp`, not `mcp[cli]`.** An earlier resolution of `mcp[cli]` came to
36 wheels and 11 MB; the `[cli]` extra adds the `mcp` command-line tooling and
its dependencies, which a stdio server never invokes. The 28-wheel figure is
the one to plan on.

Three caveats, stated so they are not mistaken for verified. The resolution ran
on x86_64, which is correct — vendoring is meant to happen on the connected workstation
 — but **nothing has been installed or run on an arm64 board**;
installability is verified, runtime on the Pi is not. It targeted
**CPython 3.13** on the assumption that Pi OS trixie ships 3.13 as `python3`
(**Researched**; confirm on the board, re-run the download if the ABI differs).
And `cryptography` and `pyjwt` are in the set only because the SDK depends on
`pyjwt[crypto]` for its auth features; a pure-stdio local server never
exercises them. Dead weight, worth knowing about, not worth fighting at 9.3 MB.

### The tool list

Tool naming follows the `{service}_{action}_{resource}` convention in
snake_case (**Researched**, current best-practice guidance), and every
description is **three or four sentences stating preconditions**, because the
model has no other way to learn that a flash can brown out the camera or that
the shutter is irreplaceable. The spec revision 2026-07-28 formalises the
annotations `readOnlyHint`, `destructiveHint`, `idempotentHint` and
`openWorldHint` and says plainly that they are **hints, not security
guarantees** (**Researched**); the actual gate is Claude Code's permission
prompt, which the hints inform.

| Tool | Wraps | Hints | One line |
| --- | --- | --- | --- |
| `camera_get_status` | `status --json` | read-only | Health and pointing in one round trip: battery, temperatures, zoom, focus, DoF, exposure, shutter count, free card space. |
| `camera_get_capabilities` | `capabilities --json` | read-only, idempotent | Static facts about this body; safe to call once and remember. |
| `camera_live_view` | `preview --json` | — | Live-view frames with **no shutter actuation**; the cheap way to see what the camera sees. Returns paths. |
| `camera_capture_photo` | `shoot --json` | not idempotent | One full exposure. Actuates an irreplaceable shutter; prefer preview for "is anything there". Flash is off by default and should stay off on battery. Returns a path. |
| `camera_set_zoom` | `zoom` | — | Absolute step 0–125, relative ±n, or `wide`/`tele`. Refuses below 3400 mV on battery. |
| `camera_set_focus` | `focus` | — | Manual focus at a distance in millimetres, or back to autofocus. |
| `camera_show_image` | — (reads a file) | read-only | Return a previously captured file as an image block, by path. Explicit, because of the pitfall below. |

Seven tools, with typed arguments, for a model that handles typed arguments
well. Contrast this with the Needle list in §6, which is derived from the same
schema and looks nothing like it — and §6 explains, with data, why.

**`camera_run_lua` is off by default, and opt-in rather than absent.** The
argument for leaving it out entirely is good and stands for Claude Code
specifically: the escape hatch is already reachable there through `Bash` as
`canonscope lua '...'`, where the permission prompt shows the user the exact
code before it runs, so wrapping it as a tool adds a JSON envelope around
arbitrary code and nothing else. The tool list is also a statement of the
camera's *intended* surface, and `lua` is a developer verb.

But that argument is about one client. An MCP client with no shell has no other
route to the remaining ~190 Lua functions, and losing the escape hatch is a
real loss for it. So the implementation registers the tool only when
`CANONSCOPE_ENABLE_LUA=1`, and marks it `destructiveHint` and `openWorldHint`
when it does. The default surface is the seven tools above; nobody gets
arbitrary code execution by accident; and the capability is one environment
variable away for a client that needs it. **Verified 2026-11-06**: the default
server advertises seven tools and the eighth appears only with that variable
set, both asserted in `mcp/test-server.py`.

### Images: return paths, show on request

**Researched, and unverified against current Claude Code.** The wire format for
an image result is a content block `{"type":"image","data":"<base64>",
"mimeType":"image/jpeg"}`, which `mcp.server.mcpserver.Image` produces. There
are multiple reports of an MCP `ImageContent` block reaching the model as **raw
base64 text** rather than as a vision input — token-expensive (figures of
15–25k tokens per image are reported) and useless, because the model cannot see
it. Whether this affects Claude Code today is not known and is the first
experiment in §8.

The design does not wait on the answer. **Capture tools return a path by
default**, which `Read` renders natively (that is the whole premise of
[08-eyes-for-claude.md](08-eyes-for-claude.md)), and **showing an image in-band
is a separate, explicit tool**. If the pitfall turns out to be real,
`camera_show_image` is the only thing that needs a note in its description; if
it turns out to be fixed, the path-first design still costs nothing and keeps
the transcript small. A 720×240 preview PNG is tiny either way; a full JPEG is
not.

## 6. Phase 2b — Needle

### What it is, and which package

The package landscape is **Researched 2026-11-06**; the install itself is
**Verified 2026-11-06 (installed and run locally)** on x86_64.

- The current release is **Needle 3**, shipped 2026-09-17. It is "sliceable":
  one weight set deployable at 2–20 transformer layers, 25–121 M parameters at
  2-bit, an **8–29 MB** binary. `cactus download` takes `--depth`, which is
  how the slice is chosen. (Researched; the flag Verified.)
- Two PyPI packages carry it: **`cactus-needle` 3.2.10** and
  **`cactus-compute` 4.0.1**, the latter being the currently recommended
  unified package; its README says "Migrating from cactus-needle? Use
  `import cactus`". Both Apache-2.0, Python ≥ 3.9. (Researched.)
- **The decorator is `@cactus.tool` with `import cactus`.** The `@needle.tool`
  / `import needle` spelling that circulated with Needle 2 is **stale** and
  does not import against the current package. This matters because that
  spelling is what the original issue for this phase used. (Verified by
  introspection of the installed package.)
- **A third package, `cactus-engine` (v2.2.2), is proprietary** — PyPI lists
  it under "Other/Proprietary License" — from the same company and with a
  confusingly similar name. It must not be pulled in, by hand or by a
  transitive dependency, and the vendoring step should fail if it appears in
  the resolved set. (Researched.)
- **`uv pip install cactus-compute` into a Python 3.13 venv installs 4.0.1
  with a 17-package tree**: `huggingface_hub 2.4.0`, `pillow`, `tqdm`,
  `fsspec`, `hf-xet`, `httpx2`, `PyYAML`, `filelock`, `anyio`, `click` and
  their small dependencies. **No torch, no onnxruntime, no llama.cpp** —
  confirmed by the installed tree, not inferred from a README. (Verified.)
- **The whole venv is 44 MB.** (Verified.) A third-party figure of 741 MB on a
  Pi 4 circulated for the v2-era package; it is **superseded** and should not
  be repeated except to say so.

**Decision: `cactus-compute` 4.0.1, `import cactus`, no extras**
(**Untested** on the board). The recommended package, the current import path,
and the smallest footprint.

### The API, from live introspection

**Verified 2026-11-06 (installed locally).** The two signatures the design
depends on:

```python
cactus.tool(fn=None, *, triggers: list[str] | None = None)

cactus.Cactus(tools=None, system=None, weights=None, tool_index_path=None,
              buffer_size=65536, auto_date=True, generation=None, stateless=False)
```

A tool is a plain function with a docstring under `@cactus.tool`;
`with cactus.Cactus(tools=[...]) as agent:` opens a session; `agent.run(text)`
selects and executes, `agent.complete(text)` returns the proposed call without
executing it. **No match returns an empty list** (`"function_calls": []`) with
no free-text fallback (Verified: the weather query in §6 below did exactly
this). Argument types — `int`, `float`, `str`, `bool`, `Literal` enums,
Pydantic models — are compiled into a constrained decode grammar, so an
out-of-range enum or a string where an integer belongs is structurally
impossible (**Researched**; the experiments below show what the grammar does
*not* protect against).

Two things from the signatures feed straight into the design. **`weights=` is
a constructor argument**, which is a cleaner offline hook than any environment
variable: the front end names the vendored `.cact` file explicitly, in code
that is tracked and tested, instead of relying on a variable being exported in
the right shell. And **`stateless=True` is effectively mandatory** for one-shot
commands: reusing one agent across unrelated queries triggers a built-in
warning that accuracy degrades (Verified, it fired during the experiments).

### The offline bundle, actually built

**Verified 2026-11-06 (run locally).** The whole vendoring path was executed on
the x86_64 workstation, which is where tier-0 vendoring is supposed to happen:

```sh
cactus fetch --platform-tag manylinux2014_aarch64 --out vendor/needle
cactus download needle3 --out vendor/needle
```

- `libcactus.so` — **1.8 MB**, and `file` reports **"ELF 64-bit LSB shared
  object, ARM aarch64, stripped"**. **The arm64 engine cross-fetches from an
  x86 machine**, which is exactly the pattern CLAUDE.md's tier-0 rule wants:
  download connected, carry on the thumb drive, install offline. This is the
  key result for phase 2b.
- `needle3.cact` — **35.34 MB** of weights.
- **Total offline bundle: 36 MB.**

The tool prints its own deployment instructions: copy the engine to
`~/.cache/cactus/engine/4.0.0/<commit>/`, **or point `CACTUS_LIB_PATH` at the
file** — so that variable name is now confirmed. `CACTUS_NEEDLE_WEIGHTS`,
which earlier research mentioned, remains unconfirmed and is unnecessary given
`weights=`; the design does not use it. The bundle joins the wheels on the
thumb drive with checksums, and `HF_HUB_OFFLINE=1` is set in the wrapper so
`huggingface_hub` never tries the network at import time.

The caveat, again, because it is the one that matters: the arm64 artefacts
were **fetched and type-checked, not executed on a Pi**. Cross-fetch is
verified; arm64 runtime is not.

### Telemetry: a dependency that phones home by default

**Verified 2026-11-06.** On first run `cactus-compute` announces that it
**collects anonymous usage counts — function name, version, OS — by default**,
disabled with **`CACTUS_TELEMETRY=0`**.

For most projects that is a footnote. For this one it is a tier-0 concern and
gets an explicit decision rather than a shrug. An autonomous Pi has no route to
the internet; a library that tries to reach one at best times out quietly and
at worst stalls startup on DNS that [06](06-controller-host.md) deliberately does not
provide. In tier 1 and 2 the board *does* have a route, and a camera
controller reporting its function calls to a third party is not something this
project should do by default, however anonymous. **Decision: the Needle wrapper
exports `CACTUS_TELEMETRY=0` unconditionally**, the install script's smoke test
checks that no telemetry notice is printed, and the setting is documented in
the operating notes as deliberate. If the variable name changes in a
later release the smoke test is what catches it.

### Maturity, bluntly

**Researched.** The repository was created 2026-02-24, has 14,517 stars and is
pushed to daily. In under a year it has **renamed its import path and
consolidated repositories**, and it ships a proprietary sibling one letter of
confusion away. Reception of the Needle 3 launch was genuinely mixed: reports
of wrong tool selection, of "utter nonsense" on some queries, and of **accuracy
degrading past roughly ten registered tools** — which the founder largely
conceded as design trade-offs rather than disputed.

That is not a reason to skip it. It is the reason for three things already
decided above: pin exact versions and vendor the wheels, so the next rename
happens on our schedule; treat Needle as optional inside tier 0 (§2), so the
rig does not inherit its churn; and keep its tool list minimal — which the
next section works out from data rather than from the ten-tool rumour.

### What the model actually did

**Verified 2026-11-06 (run locally, x86_64).** Rather than design the Needle
tool list from best practice, Needle 3 was run against camera-shaped tools:
three tool designs, the same nine-ish queries each, `stateless=True`,
`complete()` so nothing executed. The failures are the valuable part.

**Experiment 1 — five tools taking raw device units, no triggers.** Zoom took
a step number, focus took millimetres.

| Query | Result | Verdict |
| --- | --- | --- |
| "take a photo" | `camera_capture_photo` | correct |
| "how is the camera doing?" | `camera_get_status` | correct |
| "what's the weather in Lagos?" | `[]` | **correct refusal** |
| "zoom all the way in" | `camera_set_zoom(step=1)` | **wrong value** — should be 125 |
| "focus on something two metres away" | `camera_set_focus(distance_mm=2)` | **wrong value** — should be 2000 |

Tool *selection* was mostly right. **Argument values were the failure mode**:
the model does no unit conversion and no scale reasoning. The grammar
guaranteed an integer; it did not guarantee a sensible one.

**Experiment 2 — the same intents with semantic arguments.** `distance_metres:
float`; zoom as `Literal["wide","middle","tele"]`; a `lighting:
Literal["normal","dim","bright"]` hint on the photo tool.

| Query | Result | Verdict |
| --- | --- | --- |
| "focus on something two metres away" | `distance_metres=2.0` | **fixed** — moving the conversion out of the model works |
| "zoom all the way in" | `[]` | **worse** — refused rather than pick an enum member |
| "zoom right out" | `[]` | **worse** — same |
| "take a picture, the room is quite dark" | `lighting="bright"` | **inverted** — a valid value, semantically backwards |
| "show me what the camera sees" | `camera_get_status` | **wrong tool** — despite an explicit preview description |
| "what can you see?" | `camera_get_status` | **wrong tool** — same |

Two lessons that cut against the §6 draft this document originally carried.
**A `Literal` enum is not a free win**: a positional enum (`wide`/`tele`) made
the model refuse where a number had at least produced *something*, and an enum
that **encodes a judgment about the world** (`dim`/`bright`) was filled in
backwards. The grammar made the wrong answer well-formed. And **tool names
compete lexically**: `camera_get_status` swallowed two "see" queries until it
was renamed.

**Experiment 3 — one zero-argument verb per intent, plus Needle 3 regex
`triggers`.** `camera_zoom_in` / `camera_zoom_out` as separate verbs, status
renamed `camera_check_health`, preview renamed `camera_show_live_view`.

| Query | Result | Verdict |
| --- | --- | --- |
| zoom in, zoom out, health, battery, live view, "what can you see?" | correct tool each | **in-domain 8/9** |
| "focus on something two metres away" | `camera_zoom_out` | **wrong tool** |
| "what's the weather in Lagos?" | `camera_zoom_in` | **refusal destroyed** — this query returned `[]` in experiments 1 and 2 |

In-domain accuracy jumped, and the out-of-domain refusal collapsed at the same
time. A camera that zooms in when asked about the weather is not a safe
camera, and the mistake it made is the shape of mistake the whole design has
to assume it will make again.

One caution about reading experiment 3: it changed two things at once —
zero-argument verbs *and* triggers — so which change bought the accuracy and
which cost the refusal is **not separated by this data**. That is the first
follow-up experiment in §8.

### Design rules the experiments impose

These replace general best practice; each one is traceable to a row above.

1. **Never give a small model a device unit or a scale.** Metres, not
   millimetres; named positions, not step numbers. The CLI already accepts
   `wide`/`tele` beside raw steps, which this vindicates, and the front end —
   not the model — converts metres to the millimetres `focus` takes.
2. **Prefer one zero-argument verb per intent over one parameterised verb.**
   Arguments are where it fails; removing them removes the failure. The cost
   is tool count, which is the next tension.
3. **Do not use an enum that encodes a judgment.** An enum naming a position
   the user said out loud is tolerable; one requiring an inference about the
   room inverted. Exposure stays on `auto`, or on the shell.
4. **Regex `triggers` are a sharp tool with a real cost.** They bought
   in-domain precision and lost the empty-list refusal. If they are used,
   **something else must gate the domain before Needle is consulted**: a plain
   word-list check in the front end that the sentence mentions the camera at
   all (`camera|photo|picture|zoom|focus|battery|view|see|shoot|snap`),
   with anything that fails it answered without the model ever running. Crude,
   and that is the point — a grep's failure modes are enumerable. **"Needle
   returns `[]` for anything unrelated" is an assumption experiment 3
   falsified**, not a property to build on.
5. **Tool names compete lexically, so choose them against each other**, not
   individually. `check_health` and `show_live_view` share no stems; `status`
   and "see" turned out to be closer than they look.

### The tool list

Applying those rules to the seven CLI verbs:

| Needle tool | CLI call | Arguments | What a person says |
| --- | --- | --- | --- |
| `camera_check_health` | `status --json` | none | "how's the camera", "battery?" |
| `camera_show_live_view` | `preview --json` | none | "what does it see", "show me the view" |
| `camera_take_photo` | `shoot --json` | none | "take a picture", "snap one" |
| `camera_zoom_in` | `zoom +10` | none | "zoom in", "closer" |
| `camera_zoom_out` | `zoom -10` | none | "zoom out", "wider" |
| `camera_focus_at` | `focus <m×1000>` | `distance_metres: float` | "focus at two metres" |
| `camera_focus_auto` | `focus auto` | none | "autofocus", "focus normally" |

Seven tools, six of them with no arguments at all. **The one parameterised
tool is `camera_focus_at`**, kept because experiment 2 showed `distance_metres`
working and because there is no zero-argument form of "two metres" — and it is
also the tool experiment 3 mis-selected, so it is the one to watch in the
follow-up. Exposure (`--tv`, `--sv`, `--flash`) is not exposed at all: it is
exactly the kind of judgment-laden argument rule 3 forbids, the CLI's flash-off
default is the safe answer, and a person who wants ISO 400 has a shell.
`capabilities` is omitted because nobody asks a camera for its propset in
conversation. "Zoom all the way in" becomes a fixed `+10` step and loses its
nuance; that is a deliberate trade of expressiveness for not having a model
guess a number.

The tool count went **up** from five to seven by following rule 2, and sits
closer to the reported ceiling than the first draft did. That is the real
tension in Needle's design: every argument removed becomes a verb added. Seven
is still under ten, and the experiments say the trade is right, but it means
there is no room for a `camera_zoom_wide` / `camera_zoom_tele` pair without
dropping something else. Measure before adding.

**`complete()`, not `run()`, and the CLI executes.** That puts one line of our
code between the model's choice and the shutter, which is where a confirmation
for `camera_take_photo` goes, and it keeps the model from executing anything —
it proposes, the front end decides, the CLI acts. **The empty case does
nothing** and says so, listing the seven things it can do; it never defaults to
a tool. And the domain word-list from rule 4 runs **before** the model, because
after experiment 3 the model's own refusal cannot be trusted to.

### Why `lua` is never exposed to Needle

This was already not a close call; the experiments make it an argument from
evidence rather than from principle. **A model that fired `camera_zoom_in` at a
question about the weather in Lagos must not be holding an arbitrary-code
verb.** Three reasons, each sufficient alone:

1. **The grammar cannot help, and the experiments show what that means.**
   Needle's safety story is that argument values are structurally constrained.
   A `code: str` argument is an unconstrained string, and experiment 2 showed
   that even a *constrained* argument can come back well-formed and wrong. The
   grammar admits any Lua, including `poke` and `call_event_proc`, which
   [09](09-capability-inventory.md) §8 records as the calls that hard-crash a
   camera.
2. **A 25–121 M parameter model is the wrong author.** It could not convert
   two metres to 2000 mm. Generating correct Lua for an integer-only
   interpreter with camera-specific function names, from a sentence, on a
   16-year-old irreplaceable body, is not within reach of a model that does not
   do unit conversion.
3. **It inverts what Needle is for.** The value of a small fixed vocabulary is
   that the failure modes are enumerable — the tables above *are* that
   enumeration. An arbitrary-code verb makes them unbounded, on the one layer
   with no human review step between the model and the hardware.

The same logic says the Needle front end has no free-text "advanced" mode
either. If a person at the Pi wants Lua, the shell is right there.

### Who is talking to it

An honest note on the tier-0 use case. Needle exists so the camera can be
driven in natural language without the workstation. In tier 0 there is no
workstation, so the natural-language input is a **person at the Pi** — a
keyboard on a console, an SSH session from a phone on the same cable, or
eventually something like a microphone, which is out of scope here. Without a
person, Needle has no caller; it is not an automation layer. That is a
genuine but narrow scenario, and it is one more reason Needle is optional
rather than load-bearing.

## 7. Phase 3 — is there a synergy, or two front doors?

> **Updated 2026-11-06, after this section was written.** Needle was dropped
> (ROADMAP.md records why), and the schema below was built — `tools/canonscope.tools.json`
> plus `tools/tests/test-schema.py`. The section stands as the reasoning that
> led there, with two corrections. **One projection, not two**: with a single
> consumer the per-front-end projection structure is an extension point rather
> than a present feature, and the schema says so instead of carrying shape for
> a thing that does not exist. **The MCP server does not build its
> registrations from the file**: its tools stay readable decorated functions
> with real type hints, and the test is what keeps them honest. Generating them
> would have cost legibility without buying safety — the drift that hurts is a
> renamed verb or a changed key, which the test catches either way.
> The argument below that the synergy is real at exactly one layer survives
> intact; it is simply now a one-sided contract rather than a two-sided one,
> which is if anything a stronger reason to have written it down.

The brief asked for original thinking here and for honesty about whether the
synergy is real. The conclusion, argued below: **it is real at exactly one
layer, the schema and the test fixture, and absent at the model layer, where
the two should never be connected.** Two front doors onto one contract is the
right shape, and most attempts to make them more than that would make the rig
less safe.

### Real: one schema, two projections

The MCP tool list (§5) and the Needle tool list (§6) are both derived from
the CLI, and if each is hand-written in its own Python file they *will*
drift — a renamed flag, a new verb, a changed `--json` key, fixed in one and
not the other. The fix is one tracked file, **`tools/canonscope.tools.json`**,
that is the single description of the surface: for each verb, its arguments
with types and enum values, its `--json` result keys, its prose description,
its MCP annotations, and a per-front-end projection — because §5 and §6 show
the two projections are **not** the same list filtered. MCP sees
`camera_set_zoom(step | ±n | wide | tele)`; Needle sees `camera_zoom_in` and
`camera_zoom_out` with no arguments, each bound to a fixed CLI invocation. So
each verb carries an `mcp` block (name, typed arguments, long description,
annotations) and zero or more `needle` entries (name, fixed CLI arguments or
the one permitted float, short description, triggers). Both Python programs
build their registrations from that file at startup. **The asymmetry is then
one file and two projections, and a verb cannot be renamed in the CLI without
both projections being looked at in the same diff.**

**The CLI's test suite is the thing that keeps the file honest.** A test in
`tools/tests/` asserts that every verb the dispatcher accepts appears in the
schema and vice versa, and that each verb's `--json` output against the fake
chdkptp has exactly the keys the schema promises. The CLI stays bash; the
schema is a static JSON file it does not read; the tier-0 arrow still points
one way. This is cheap, mechanical and the only part of phase 3 that should
be built unconditionally.

### Real, and the reverse of the obvious direction: Claude builds Needle's eval

The obvious synergy — Needle as a local pre-filter in front of Claude —
does not hold up (next section). The one that does runs the other way, and the
experiments in §6 are its proof of concept: nine queries, hand-written, found
three design errors in an afternoon. Needle's weakness is tool selection and
argument filling; measuring that needs a fixture of utterances with the right
answer attached, and writing thirty varied ways a person might say "zoom out a
bit" — plus the weather-in-Lagos sentences that must return nothing — is
exactly the job a large model does well and a person finds tedious. So: **a
Claude Code session, with the MCP server attached and therefore seeing the
same schema, generates the eval set for the Needle front end** — utterances,
expected tool, expected arguments, deliberate near-misses between
`show_live_view` and `take_photo`, deliberate out-of-domain sentences. The
fixture is tracked, Needle is scored against it under the fake chdkptp, and the
score decides whether Needle ships on the thumb drive at all (§8). The shared
schema is what makes this mechanical rather than clever.

### Not real: Needle as a router in front of a larger model

The idea is attractive on paper. Natural language arrives; Needle tries first,
locally, for free; if it returns a call, execute it and never spend a cloud
token; if it returns empty, escalate to a big model. Three things are wrong
with it here, and §6 adds a fourth.

**In Claude Code there is nothing to put Needle in front of.** The user is
already talking to Claude; the prompt goes to Claude; Claude decides to call a
tool. There is no interception point, and inserting one would mean building a
different chat client. **A Needle-first interface that escalates requires the
network**, because the thing it escalates to is a model API — so the "offline"
front door becomes an online one the moment it does anything interesting,
which is tier 2 by definition and the opposite of why Needle is here. **The
economics are not this project's economics.** A pre-filter pays off at
volume — a kiosk, a voice assistant answering a thousand "zoom in"s a day. One
person with one camera issuing a handful of commands has no token bill worth
routing around. And **a router depends on the refusal being reliable**, so
that "Needle said nothing" means "escalate"; experiment 3 showed the refusal
collapsing under the very configuration that made the in-domain answers good.
A router built on that would silently execute the weather question.

The honest reading of the offline/online asymmetry is that the two front ends
cover **disjoint situations** — Needle when the workstation is absent, MCP
when it is present — and disjoint coverage is complementarity, not synergy.
It is worth preserving as an option, and it costs nothing to preserve because
both consume the same CLI and schema. It should not be built.

### Actively harmful: chaining the models

Two chains are conceivable, and both should be ruled out explicitly so nobody
drifts into them.

**Claude → Needle** — a Claude Code tool whose implementation is "hand this
sentence to Needle" — is pointless, since Claude already understands the
sentence and already has typed tools; it would add a weaker model's
tool-selection error to a stronger model's correct intent.

**Needle → MCP** — Needle acting as an MCP client — misunderstands what MCP's
value is: a typed schema for a model capable of reading three-sentence
preconditions. Needle does not read descriptions; experiment 2 showed it
ignoring an explicit preview description in favour of a lexically closer name.

Either chain stacks two models' failure modes in series, on a rig whose
irreversible action is a shutter actuation on an irreplaceable body, and hides
the upstream error from whoever is downstream. **Rule: a model's output is
never another model's input in this project.** The only shared thing is below
both of them.

### Where that leaves phase 3

Build the schema file and its test. Build the eval-set generation when Needle
exists to be evaluated — the nine queries in §6 are its seed. Do not build a
router. Do not chain. Then phase 3 is finished, and it is finished by being
small.

## 8. What would make each phase fail, and the cheapest experiment

Ordered by how early each experiment can be run. Several have now been run;
those are marked, and what remains is stated.

**Phase 1 — the CLI has never completed a real round trip.** ROADMAP.md records
that the camera was switched off before `canonscope` could be exercised;
every chdkptp call under it was verified live but the wrapper has not been.
The failure it would reveal is in the parsing — `cam_lua`'s two `sed` patterns
for quoted and bare returns, the `|`-split in `status`. **Experiment**: power
on, run all seven verbs with and without `--json`, and pipe each `--json`
output through a strict parser (`jq` is fine on the workstation; it is not a
runtime dependency). Half an hour; blocks everything else.

**Phase 2a — three ways to fail; one retired, two open.** *The SDK does not
install or import as described*: **run, 2026-11-06** — 2.3.0 installs, the
imports in §5 are the ones that work, and `FastMCP` is gone. *The image
pitfall* (§5): if `ImageContent` arrives as text, `camera_show_image` is
expensive and blind. **Experiment**: a ten-line server with one tool returning
a 720×240 preview PNG via `mcp.server.mcpserver.Image`; ask Claude Code what it
sees and read the token count off the transcript. One hour, no camera needed
if a frame already exists. *Claude ignoring the tools in favour of `Bash`*: not
a failure of the server but of its reason to exist. Watch for it in the first
sessions; if Claude reaches for `canonscope` directly even with the tools
present, the descriptions are not earning their keep, and the fix is better
descriptions or fewer tools, not more.

**Phase 2b — five ways to fail; two retired, one half-answered, two open.**
*It does not install light*: **run, 2026-11-06** — 44 MB venv, 17 packages,
no ML runtime. *The offline bundle cannot be built from the workstation*:
**run, 2026-11-06** — 36 MB, arm64 engine cross-fetched, `weights=` and
`CACTUS_LIB_PATH` confirmed as the hooks. *It picks the wrong tool or fills
the wrong value*: **run in part, 2026-11-06** — §6 has the results, and they
changed the tool list. What remains is the **confound in experiment 3**: run
the zero-argument tool set *without* triggers, on the same queries, to learn
whether the accuracy came from the verbs and the refusal loss from the
triggers. Then the thirty-plus-utterance fixture from §7, with the threshold
fixed in advance: **zero spurious `camera_take_photo` on non-shooting
utterances, zero tool calls on out-of-domain sentences once the word-list gate
is in front**, overall accuracy second. *It does not fit the board*:
**Experiment**: install from the vendored bundle into a venv on the Pi, run
three queries under `/usr/bin/time -v`, read maximum resident set size and
wall time. Thresholds decided now rather than after seeing the number: peak
RSS under 300 MB and under 3 s per decision; above either, Needle does not go
on the thumb drive. This is also the first time any of it executes on arm64.
*The API moves again*: a posture, not an experiment — exact pins, vendored
wheels, `CACTUS_TELEMETRY=0`, and a smoke test (`import cactus; cactus.tool;
cactus.Cactus`, and no telemetry notice on stdout) in the install script so a
rename fails loudly at install time rather than at first use.

**Phase 3 — the schema drifts anyway.** The schema test only protects anything
if it runs. **Experiment**: deliberately rename a `--json` key in the CLI and
confirm the test fails; then wire the test into the pre-commit hook beside
`check-private.sh`, so drift is caught at commit rather than at the next
session that trips over it.

## 9. Decisions made here, and what is left open

**Decided** (all **Untested** as implementations on the board):

- The CLI is the whole of tier 0's control surface, and never depends on 2a
  or 2b. The MCP server is tier 1. Needle is an optional extra inside tier 0.
- Both 2a and 2b shell out to `canonscope --json`; no deeper binding unless a
  workload needs sustained >2 ops/s that neither batching nor on-camera Lua
  can absorb.
- The MCP server runs on the workstation beside Claude Code, with the camera
  host as an SSH transport detail configured outside the repo; bare `mcp`
  SDK 2.3.0 (28 wheels, 9.3 MB, no `[cli]`) with `MCPServer`, stdio,
  project-scoped `.mcp.json`, launched through a bash wrapper into a project
  venv built from vendored wheels.
- Capture tools return paths; in-band image display is a separate explicit
  tool. `camera_run_lua` is not in v1.
- Needle uses `cactus-compute` 4.0.1 and `import cactus`, no `[train]`,
  `weights=` pointing at the vendored 36 MB bundle, `CACTUS_TELEMETRY=0`,
  `stateless=True`, `complete()` not `run()`, a word-list domain gate before
  the model, confirmation before `camera_take_photo`, nothing on an empty
  match, and `lua` never.
- Needle's tools are seven zero-argument verbs per intent (one float
  exception, `camera_focus_at`), in metres and named positions, with no
  exposure controls and no judgment enums — because the experiments said so.
- One tracked schema file with per-front-end projections feeds both front ends
  and is checked by the CLI's test suite. No router, no model-to-model
  chaining.

**Left open**, recorded in [05-open-questions.md](05-open-questions.md) and
ROADMAP.md rather than guessed at:

- Whether Claude Code currently renders MCP image blocks as vision or as text.
- Needle 3 runtime on the actual board — a Pi 4 with 2 GB, arm64 — where
  nothing from phase 2a or 2b has yet executed.
- Which of experiment 3's two changes bought the accuracy and which lost the
  refusal: zero-argument verbs, or regex triggers.
- Whether Pi OS trixie's `python3` is 3.13, which both wheel sets assume.
- Whether the MCP server's descriptions change Claude's behaviour at all
  compared with `Bash` plus the CLI's `--help` — the question that decides
  whether phase 2a was worth having.
