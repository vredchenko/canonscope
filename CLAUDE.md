# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository.
`AGENTS.md` is a symlink to this file.

## What this project is

canonscope drives a **Canon PowerShot SX200 IS** (2009) over USB via CHDK and
chdkptp, from any Linux host: a workstation or a dedicated controller such as
a Raspberry Pi. Read [README.md](README.md) for the overview,
[ROADMAP.md](ROADMAP.md) for current state, and `docs/` for research, one
topic per file.

This is a hardware project. Most work is research, scripting and careful
sequencing, not application code. The camera is 16 years old and
irreplaceable, and the surrounding software ecosystem is largely abandoned.

## Hard constraints — do not re-derive these, and do not contradict them

- **Only firmware 1.00C and 1.00D have CHDK builds.** The `100d` builds are
  compiled from `100c` source (the makefile shim overrides `PLATFORMSUB`), and
  the two published zips are byte-identical.
- **FAT16 only for autoboot.** The SX200 IS shipped in March 2009, and only
  cameras released after **January 2011** can autoboot from FAT32. A
  single-partition bootable card therefore caps at **4 GB**.
- **Bootability comes from the ASCII string `BOOTDISK` at offset `0x40`** of
  the first partition's FAT16 boot sector. Canon cameras ignore the MBR boot
  flag entirely.
- **Remote capture is supported** on this body: `CAM_HAS_FILEWRITETASK_HOOK`
  is set, which gives JPG, and RAW/DNG-header are unconditional. There is no
  CRAW. So tethered shooting needs no SD-card access at all.
- **Never power the camera from a Raspberry Pi's 5 V rail.** Lens and flash
  spikes brown out the Pi.
- **The camera cannot power itself on**, and it boots into **Playback** mode.
- **The flash stays off by default.** Firing it browned the camera out at 69%
  battery, mid-capture.

## Verify, don't remember

CHDK specifics are obscure and easy to misremember. Before stating anything
about CHDK behaviour, check a local mirror (`tools/fetch-assets.sh` builds it
under `assets/`) rather than recalling it:

- `assets/chdk/wiki/*.wiki` — wiki pages as wikitext
- `assets/chdk/platform/sx200is/` — the port's own source, the final authority
  on what this camera supports
- `assets/chdk/source/CHDK/` — full source trunk (pinned commit in
  `assets/chdk/source/PINNED.txt`)

The rendered wiki at `chdk.fandom.com` is **behind Cloudflare**: `WebFetch`
gets HTTP 402 and `curl` gets a JS challenge. Use the `api.php` endpoint, which
answers fine:

```sh
curl -sL "https://chdk.fandom.com/api.php?action=parse&prop=wikitext&format=json&formatversion=2&redirects=1&page=SX200IS" | jq -r '.parse.wikitext'
```

## Writing to SD cards

`tools/make-card.sh` is the only thing that should touch a card, and it is
deliberately paranoid. When working on it or around it:

- **Never run a destructive command against a device the user has not named in
  the current conversation.** Re-check with `lsblk` every session; device
  letters move.
- **Look at what is on a card before erasing it**, and show the user, even when
  they say it is blank.
- Test card logic against a **loopback image** (`truncate -s 3886M img &&
  mkfs.vfat -F 16 img`) rather than real hardware. `mkfs.vfat` and `fsck.vfat`
  work on plain files with no root needed.
- Destructive steps need `sudo`, which usually prompts for a password. Write
  the script and let the user run it.
- Keep its two invariants: **every check runs unprivileged** above the
  `ESCALATE ONLY BELOW THIS LINE` marker, and **a guard is replaced, never
  removed**. See [docs/07](docs/07-shell-and-provisioning-lessons.md).

## Code constraints

- **`tools/` is bash + coreutils only.** It has to run on a freshly installed
  controller with nothing added. That is a constraint on what ships, **not**
  on how you edit files. Python lives in `mcp/` and `experiments/`, and in
  test harnesses.
- **The CLI is the contract.** The MCP server shells out to `tools/canonscope
  --json` and never talks to chdkptp directly. A new verb needs an entry in
  `tools/canonscope.tools.json`; `tools/tests/test-schema.py` enforces
  three-way agreement between schema, CLI and MCP server, and will fail
  otherwise.
- **Everything must be testable without a camera.** Add canned responses to
  `tools/tests/fake-chdkptp/chdkptp.sh` rather than skipping a test.
- **Exercise every branch, not just the default.** `make-card.sh --mode chdk`
  carried a live bug through five test runs because every run used
  `--mode verreq`. A flag that selects a different code path needs its own run.
- **Never pipe into `grep -q` or `head` in a `pipefail` script.** Both exit on
  the first match or line, the producer dies of SIGPIPE (141), and `pipefail`
  reports the pipeline as failed, so `|| die` fires on success. Capture into a
  variable and use `<<<`, or use `sed -n '1,Np'`, which consumes all input.
- **`grep -c` exits non-zero on a zero count.** Use `|| true`, never
  `|| echo 0`.
- **`jq -e` on empty input differs by version.** jq 1.6 (Ubuntu jammy) exits
  0; jq 1.7 (Debian trixie) exits 4. Guard with `[[ -s "$f" ]]` explicitly.
- **`pkill -x`, never `pkill -f`**, when freeing the camera from
  `gvfsd-gphoto2`: `-f` matches the calling script's own command line.
- **CHDK's on-camera Lua has no floating point.** `3/2 == 1`, and
  `string.format("%f")` prints a literal `f`. Use integers and `%d`.
- **Prefer Python over Perl for multi-line edits.** Perl `-pe` interpolates
  `${var}` out of your patterns. `sed`/`awk` with explicit line ranges is the
  fallback.
- Prefer `jq -rn --arg s "$x" '$s|@uri'` for URL-encoding.
- Keep `shellcheck -x -S warning` clean; `.devcontainer/verify.sh` runs it.

## Documentation conventions

- `docs/` holds research, one topic per file, cross-linked with relative links.
  Keep the numeric prefixes and the index table in `docs/README.md` in step.
- **Label every claim with its provenance.** Use either **Researched**
  (product listings, reviews, general practice; unverified) or
  **Verified `<date>`**, naming the source: wiki page, autobuild server,
  source file and line, or the physical camera. This distinction is load
  bearing. Never imply something was tested on hardware when it wasn't.
- Quote exact version strings, revision numbers and register addresses.
  Vague recollection is worse than useless on a port this obscure.
- When something is unresolved, record it in `docs/05-open-questions.md` and
  `ROADMAP.md` rather than guessing and moving on.

## Design decisions

These are settled; don't relitigate them without new information. Reasoning
is in [docs/06](docs/06-controller-host.md) and
[docs/10](docs/10-control-surface.md).

- **The controller is any Linux host.** A Raspberry Pi is the reference for a
  dedicated, always-on controller, but that build is deferred and nothing may
  assume it. chdkptp must run on whichever host owns the USB connection.
- **Claude Code runs on a workstation**, and reaches a separate controller
  over SSH if there is one. A 2 GB board is below Claude Code's requirements.
- **Offline-first.** A controller must work with no internet in "tier 0".
  Nothing in the connected tiers may become a dependency of it. Anything that
  has to be downloaded must also be vendorable, with a checksum. Assume no NTP
  and no DNS when offline: there is no RTC, so an offline boot has no reliable
  clock.
- **Releases are tag-driven semver.** `VERSION` is the source of truth;
  `packaging/bump-version.sh` keeps the plugin manifests in step, and
  `packaging/check-version.sh` enforces it in CI and on release.
- **The `.deb` bundles chdkptp**, because obtaining a working chdkptp (stale
  upstream, Lua 5.2, libusb 0.1) is the hardest part of setup. Release assets
  must keep including its GPL source.
- **The repo root is the Claude Code plugin** (`.claude-plugin/`, `skills/`,
  `mcp/`). Keep the root `.mcp.json` server named `canonscope`, the same as
  the plugin's, so the plugin's definition replaces it rather than adding a
  second one.

## Keep the tree publishable

This repository is public. **Never put a private hostname, address, MAC,
serial, domain or username into a tracked file.** `tools/check-private.sh`
checks for generic patterns (LAN/CGNAT addresses, MACs, home paths, keys,
tokens). Contributors can add their own patterns in
`~/.config/canonscope/private-patterns`, which is outside the repo by
design. Install it as a pre-commit hook with
`tools/check-private.sh --install-hook`. **If the guard fires, fix the
source. Never widen the exclusions to hide it.**

## Style

- Fix the root cause rather than papering over it, and say so plainly when
  something does not work.
- Don't invent progress. If a step is untested, mark it untested.
