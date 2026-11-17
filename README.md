# canonscope

[![ci](https://github.com/vredchenko/canonscope/actions/workflows/ci.yml/badge.svg)](https://github.com/vredchenko/canonscope/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/vredchenko/canonscope?sort=semver)](https://github.com/vredchenko/canonscope/releases)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-D97757?logo=claude&logoColor=white)](https://claude.com/claude-code)

**Turn an old Canon PowerShot into a USB camera that scripts, and Claude Code,
can drive.**

canonscope revives a **Canon PowerShot SX200 IS** (2009) with
[CHDK](https://chdk.fandom.com/), the Canon Hack Development Kit, and drives
it over USB from a Linux machine: a workstation, a Raspberry Pi, anything with
a USB port. Photos stream straight to the host with nothing written to the
camera's SD card. A small command-line tool wraps the obscure parts: Lua on
the camera, APEX96 exposure units, PTP sessions, and the desktop grabbing the
camera.

The first purpose is **giving a Claude Code session eyes**. Point the camera
at a whiteboard, a notebook page or an object on the desk, and the session can
take a photo and read it, with no phone photos emailed to yourself. The
capture loop works end to end: in the 2026-10-30 acceptance test, a session
transcribed a handwritten page photographed in a dark room.

```
 Claude Code ──MCP──▶ canonscope CLI ──▶ chdkptp ──USB/PTP──▶ SX200 IS running CHDK
 (or you, a script)    (bash, --json)    (bundled)            (autoboots from a locked SD card)
```

## What it does

| Command | |
| --- | --- |
| `canonscope status` | battery, temperatures, card space, zoom, depth of field, exposure — one round trip |
| `canonscope shoot` | take a photo; the JPEG lands on the host, nothing touches the SD card |
| `canonscope preview` | grab live-view frames: no shutter actuation, no wear |
| `canonscope zoom` / `focus` | drive the lens (126 zoom steps; focus in mm) |
| `canonscope lua '...'` | run any of CHDK's ~200 Lua functions: the escape hatch |
| `canonscope-make-card` | write a bootable CHDK SD card, with paranoid safety checks |

Every verb takes `--json`. That output is the contract the MCP server, and
anything else you build, binds to.

### Status

This is a hobby hardware project, and its docs say plainly what has and hasn't
been tested:

- **Verified on the camera:** CHDK autoboot, the firmware read, tethered
  capture via `tools/capture.sh`, and every underlying chdkptp call.
- **Tested against a fake chdkptp only:** the `canonscope` CLI wrapper and the
  MCP server. Their test suites need no camera; real-hardware runs are next on
  the [roadmap](ROADMAP.md).
- **Other cameras:** the CLI is mostly generic chdkptp. `make-card.sh`, the
  flash property (`143`) and the zoom range are SX200 IS specifics. Other
  CHDK bodies are untested; reports welcome.

## Requirements

- A **Canon PowerShot SX200 IS** on firmware **1.00C or 1.00D**, the only
  revisions with a CHDK build. Step 1 below shows how to check.
- An **SD card of 4 GB or less**. This pre-2011 body can only autoboot CHDK
  from FAT16.
- A **Linux host** with USB, amd64 or arm64 (Raspberry Pi OS 64-bit included).
- A charged NB-5L battery. **Never power the camera from a Raspberry Pi's 5 V
  rail**; lens and flash current spikes brown the Pi out.

## Installation

### 1. Prepare the camera

`make-card.sh` partitions and formats a card, so **it destroys data**. It
refuses anything that isn't a removable USB device, shows you the device's
current contents, and makes you type the device name back. Run it as your
normal user; it escalates with `sudo` only after you confirm.

```sh
# a) Find out the camera's firmware revision
canonscope-make-card --device /dev/sdX --mode verreq
#    In the camera: PLAY mode, hold FUNC/SET, press DOWN. Look for "GM1.00C" or "GM1.00D".

# b) Write a bootable CHDK card (downloads the CHDK build first)
canonscope-fetch-assets --only builds
canonscope-make-card --device /dev/sdX --mode chdk

#    Lock the card's write-protect tab, insert it, power on: you should see the CHDK splash.
```

(From a source checkout, these are `./tools/make-card.sh` and
`./tools/fetch-assets.sh`.) Background is in
[docs/01](docs/01-camera-and-firmware.md) and
[docs/03](docs/03-storage-and-chdk.md).

### 2. Install canonscope

**From a release (.deb).** Each package bundles a prebuilt chdkptp and the
udev rule. Use `amd64` for PCs and `arm64` for Raspberry Pi 3/4/5 on 64-bit
Raspberry Pi OS:

```sh
VER=0.0.1 ARCH=$(dpkg --print-architecture)
curl -LO "https://github.com/vredchenko/canonscope/releases/download/v${VER}/canonscope_${VER}_${ARCH}.deb"
sudo apt install "./canonscope_${VER}_${ARCH}.deb"
sudo usermod -aG plugdev "$USER"     # needed headless/over SSH; log in again afterwards
canonscope --version
```

The packages are built on Debian trixie (13). Ubuntu 24.04+ and other
distributions with `libreadline8t64` should work too.

**From source.** This runs from the checkout, with no install step:

```sh
git clone https://github.com/vredchenko/canonscope && cd canonscope
sudo apt install build-essential liblua5.2-dev libusb-dev libreadline-dev git
packaging/build-chdkptp.sh           # builds chdkptp into build/chdkptp
./tools/install-udev-rule.sh         # stops the desktop claiming the camera
./tools/canonscope status
```

### 3. Add it to Claude Code (optional)

This repository is a Claude Code plugin marketplace. The plugin adds the
camera's MCP tools (`camera_capture_photo`, `camera_live_view`,
`camera_set_zoom`, …) and a skill that teaches Claude to use them: check
status first, frame with live view, and fix exposure when auto fails.

```text
/plugin marketplace add vredchenko/canonscope
/plugin install canonscope@canonscope
```

Or, in one step on Claude Code 2.1.275 or later:

```text
/plugin install canonscope --marketplace vredchenko/canonscope
```

From a shell: `claude plugin marketplace add vredchenko/canonscope && claude
plugin install canonscope@canonscope`.

The plugin needs the camera on the same machine, chdkptp (install the `.deb`),
and either [uv](https://docs.astral.sh/uv/) or a Python ≥ 3.11 with
`mcp==2.3.0`. `mcp/run-server.sh` finds or provisions one. Working inside a
clone instead, the root `.mcp.json` registers the same server at project
scope. More detail is in [mcp/README.md](mcp/README.md).

## Usage

```sh
canonscope status                         # is the rig healthy, what is it pointed at
canonscope capabilities                   # what this body supports
canonscope shoot                          # auto everything
canonscope shoot --tv 0.5 --sv 400        # dim room: shutter seconds + ISO
canonscope shoot --sd 2m --out board.jpg  # fixed focus at 2 metres
canonscope preview -n 5 --format png      # live view frames (PNG needs ImageMagick)
canonscope zoom 40                        # also +5, -5, wide, tele
canonscope focus 2000                     # millimetres, or 'auto'
canonscope lua 'return get_temperature(1)'
canonscope --json status                  # machine-readable, for scripts
```

Auto-exposure is what usually fails: a dim room underexposes and a whiteboard
blows out. `--tv` and `--sv` are the fix. The flash is **off by default**,
deliberately: firing it browned the camera out at 69% battery. The CLI also
refuses to drive the zoom motor below 3400 mV on battery.

| Environment variable | Effect |
| --- | --- |
| `CANONSCOPE_CAPTURE_DIR` | where photos and preview frames land (default: `captures/` in a checkout, else `~/.local/share/canonscope/captures`) |
| `CANONSCOPE_ASSETS_DIR` | where `fetch-assets` mirrors CHDK material |
| `CHDKPTP_DIR` | use a specific chdkptp build (directory containing `chdkptp.sh`) |
| `CANONSCOPE_KEEP_GVFS=1` | don't kill `gvfsd-gphoto2` before connecting |
| `CANONSCOPE_FORCE=1` | zoom even on a low battery |
| `CANONSCOPE_ENABLE_LUA=1` | expose `camera_run_lua` in the MCP server (off by default) |

The camera boots into **Playback** mode and can't power itself on. The CLI
switches it to record mode for you, but someone has to press the power button.
[docs/09](docs/09-capability-inventory.md) is the inventory of everything else
the camera can be made to do.

## Development

```
tools/        the CLI and scripts: bash + coreutils only, so they run on a bare install
tools/tests/  CLI and schema tests, run against a fake chdkptp (no camera needed)
mcp/          the MCP server (Python), a thin wrapper over the CLI's --json
skills/       the Claude Code plugin skill
.claude-plugin/  plugin and marketplace manifests
packaging/    chdkptp build, .deb build, version scripts
docs/         research notes, one topic per file; every claim labelled Researched or Verified
experiments/  throwaway investigations, kept with their results
assets/       local mirror of CHDK builds, source and wiki (not tracked; fetch-assets.sh)
```

**Run the tests.** None of them need a camera:

```sh
./tools/tests/run-tests.sh                                 # CLI + schema
uv run --no-project --with 'mcp==2.3.0' python mcp/test-server.py   # MCP server
```

**Or use the dev container**, which runs everything CI runs: shellcheck,
version checks, the private-identifier guard, CLI, schema and MCP suites. It
is Debian trixie, the same base the `.deb`s are built on. Details are in
[.devcontainer/README.md](.devcontainer/README.md).

```sh
docker build -t canonscope-dev -f .devcontainer/Dockerfile .devcontainer
docker run --rm -it -v "$PWD:/workspaces/canonscope" canonscope-dev \
    bash -c '.devcontainer/post-create.sh && .devcontainer/verify.sh'
```

The camera isn't reachable from inside the container (no USB passthrough), so
hardware work happens on the host.

**Build a package** for the current architecture: `packaging/build-deb.sh`,
which writes to `dist/`.

**Conventions** are in [CLAUDE.md](CLAUDE.md) (also available as `AGENTS.md`
for other coding agents) and [CONTRIBUTING.md](CONTRIBUTING.md). The
short version:

- `tools/` stays bash + coreutils.
- Every claim in `docs/` is labelled with its provenance.
- Test card logic against a loopback image, never a real card.
- Install the pre-commit guard with `tools/check-private.sh --install-hook`.

### Releasing

Versions follow [semver](https://semver.org/) and start at `v0.0.1`. `VERSION`
is the source of truth, and both plugin manifests must agree with it:

```sh
packaging/bump-version.sh 0.1.0
git commit -am "chore: release v0.1.0"
git tag -a v0.1.0 -m v0.1.0
git push origin main v0.1.0
```

Pushing the tag runs [`release.yml`](.github/workflows/release.yml). It checks
that the tag matches `VERSION`, builds the `.deb`s natively on amd64 and arm64,
and publishes a GitHub release with the packages, `SHA256SUMS` and the source
of the bundled chdkptp.

## Documentation

[docs/](docs/README.md) holds the research behind every decision: firmware
and CHDK port status, power and dummy batteries, SD card limits, remote
capture, the controller host, and the design of the control surface.
[ROADMAP.md](ROADMAP.md) is what's next.

## License and credits

canonscope is [MIT licensed](LICENSE).

The `.deb` packages bundle **[chdkptp](https://app.assembla.com/spaces/chdkptp)**
by reyalp and contributors, which is GPL-2.0. It is built unmodified from
[the svn2github mirror](https://github.com/svn2github/chdkptp) at the commit
pinned in `assets/chdkptp/PINNED.txt`, and every release attaches its source.
**[CHDK](https://chdk.fandom.com/)** itself is GPL and is downloaded from its
autobuild server, never redistributed here. Thanks to both projects; this
would be impossible without them.

Canon and PowerShot are trademarks of Canon Inc. This project is not
affiliated with Canon.
