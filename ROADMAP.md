# Roadmap

Ordered roughly by dependency. `[ ]` open, `[~]` in progress, `[x]` done,
`[-]` deferred by choice. Larger items are welcome as GitHub issues; this file
is the overview.

## Proven so far

- [x] **Firmware read: `GM1.00D`** (2026-10-30), one of the two revisions with
      a CHDK build. The shutter count was 2287, low for a 2009 body.
- [x] **CHDK 1.6.1 autoboots** from a card written by `tools/make-card.sh`
      (254 files, `BOOTDISK` marker written at `0x40` and read back).
- [x] **chdkptp built** from the 2018 source mirror, CLI only, against Lua 5.2
      and libusb 0.1. It negotiates `host:2.8 cam:2.9` with 2026 firmware.
- [x] **Remote capture confirmed on the body.** `get_usb_capture_support()`
      returns 7 (`JPG | RAW | DNG-header`, no CRAW), as predicted from source.
- [x] **The whole loop, end to end.** `tools/capture.sh` takes the photo, and
      a Claude Code session reads it. The acceptance test passed: handwriting
      on paper was legible, at `--tv 0.5 --sv 400` with no flash.
- [x] **Schema test** asserting three-way agreement between
      `tools/canonscope.tools.json`, the CLI and the MCP server.
      Mutation-tested.
- [x] **Packaging**: `.deb` for amd64 and arm64 with a bundled chdkptp, a
      Claude Code plugin and marketplace, and tag-driven GitHub releases.

## Next — on the real camera

- [ ] **Run every CLI verb against the powered-on camera**, with and without
      `--json`, and parse each `--json` output strictly. The chdkptp calls
      underneath were each verified live on 2026-11-06, but the `canonscope`
      wrapper has only run against the fake chdkptp.
- [ ] **Run the MCP server against the real body**, and find out whether
      Claude Code receives `camera_show_image` as vision or as base64 text.
      See [docs/05](docs/05-open-questions.md).
- [ ] **Observe whether the MCP tools change Claude's behaviour** compared
      with plain `Bash` + `canonscope --help`.
- [ ] **Decide whether flash is wanted at all.** The mode is
      software-settable, but the pop-up is mechanical, and a direct flash puts
      a specular hotspot on whiteboards and paper.
      See [docs/08](docs/08-eyes-for-claude.md).
- [ ] **Test `canonscope preview --format png` on hardware.** The test suite
      only covers PPM.
- [ ] **Support output paths containing spaces** in `capture.sh`. The
      `remoteshoot` command line is built as one string.
- [ ] **Install the udev rule on every controller** (the `.deb` does this),
      and drop the `pkill gvfsd-gphoto2` fallback once that is proven.

## Packaging and distribution

- [ ] **Install the arm64 `.deb` on a real Raspberry Pi** and run the
      hardware checks above there. CI builds and smoke-tests it in a
      `debian:trixie` container on a native arm64 runner, but has not run it on
      a board.
- [ ] **armhf build** for 32-bit Raspberry Pi OS, if anyone needs it.
- [ ] **Vendor the `mcp` wheels** for offline installs:
      `pip download 'mcp==2.3.0' --platform manylinux2014_aarch64
      --python-version 3.13 --implementation cp --abi cp313
      --only-binary=:all:` resolved to 28 wheels (9.3 MB) on 2026-11-06.
      Needs an `--only mcp-wheels` group in `tools/fetch-assets.sh`.
- [ ] **Cache `.deb` dependencies** for offline installs (`--only debs`),
      as a local apt repository. See
      [docs/07](docs/07-shell-and-provisioning-lessons.md).
- [ ] **A plugin icon** for the Claude Code plugin listing.

## Power

- [ ] **Mains power via a dummy battery, or a relay across the power
      button.** An on-demand rig has to stay powered: the camera cannot switch
      itself on, and an NB-5L will not sustain continuous running. See
      [docs/02](docs/02-power.md).
- [ ] **Decide the 3rd battery terminal trade-off** before building the dummy
      battery. A ~10k resistor makes the camera accept it, but the same
      contact can be a CHDK remote input (`CAM_REMOTE_AtoD_CHANNEL 5`).
- [ ] **Source an NB-5L dummy battery / DC coupler**, or build one.

## Dedicated controller (deferred, optional)

A separate always-on board as the controller. The Raspberry Pi 4 is the
reference; any Linux box works. Design notes are in
[docs/06](docs/06-controller-host.md).

- [ ] Flash Raspberry Pi OS Lite 64-bit (trixie), and verify whether it ships
      cloud-init before designing first boot. Use key-only auth from first
      boot, with no default account.
- [ ] Fit a heatsink. Apply SD wear measures: `noatime`, volatile journald,
      no swap on the card.
- [ ] Add a default-deny firewall.
- [ ] Add an RTC module (DS3231 class), or set the clock on connect. Until
      then, record a monotonic sequence number with each capture.
- [ ] Add a health check: SoC temperature, throttle state, pending vs. running
      kernel. Report, don't fix.
- [ ] Add local alerting (an LED, or a status file shipped on next sync).
- [ ] Set up a local artefact drive (ext4) with a `git bundle` of this repo,
      the asset mirror, cached `.deb`s and the OS image.
- [ ] **Decide what backup encryption protects against** before writing any
      backup code. This blocks all backup work.
- [ ] Wire the MCP server to a remote controller over SSH.

## Deferred by choice

- [-] **Dual-partition cards.** Single-partition FAT16 caps at 4 GB, which is
      enough. If needed, CHDK's own *Miscellaneous stuff → SD Card → Create
      card with two partitions* is the documented route.
- [-] **The port's RAW bugs** (blue cast with corner stripes; broken RAW in
      ISO 3200 Scenery mode). JPG is the path that matters.
- [-] **A local natural-language front end (Needle).** It was evaluated on
      2026-11-06 and parked: offline-with-no-human wants schedules and
      presets, not a parser. The measurements are in
      [docs/10](docs/10-control-surface.md) §6 and `experiments/needle/`.
      Reopen if a genuine offline-with-a-human scenario appears.
