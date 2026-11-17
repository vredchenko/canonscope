# The controller host

The **controller** is whatever machine the camera is plugged into over USB. It
runs `chdkptp` and the `canonscope` tools. chdkptp has to run on the host that
owns the USB connection, so this is the one placement decision that is forced.

**Which machine that is, is deliberately open.** Any Linux box with a USB port
works. Two shapes are in view:

| Shape | Status |
| --- | --- |
| **Workstation-attached.** The camera plugs into the machine you work on, which also runs Claude Code. | **Verified 2026-10-30.** This is how the capture loop was first proven end to end. |
| **Dedicated controller.** A small always-on board (a Raspberry Pi is the reference) owns the camera. A workstation drives it over SSH. | **Untested.** Deferred; the tooling is written so nothing has to change when it happens. |

The second shape exists to make the rig **available on demand and
unattended**: a camera on a mount, pointed at a whiteboard or a desk, that any
session can ask for a photo. The rest of this document is about that shape.
Everything in it is plan or research unless labelled otherwise.

## What a controller needs

- Linux with a USB host port, `bash` and coreutils.
- **chdkptp**, CLI only. The release `.deb` bundles a prebuilt one for amd64
  and arm64. To build it yourself, see
  [`packaging/build-chdkptp.sh`](../packaging/build-chdkptp.sh). There are
  three traps:
  - **Lua 5.2 specifically.** chdkptp's readme says 5.3 is "known to cause
    problems", 5.1 is unsupported, and current distributions default to 5.4.
    `liblua5.2-dev` is still packaged in Debian trixie for amd64 and arm64.
  - **libusb 0.1 API.** chdkptp includes `<usb.h>` and links `-lusb`, so the
    package is `libusb-dev`, **not** `libusb-1.0-0-dev`.
  - **GUI off.** That is the default in `config-sample-linux.mk`, and it avoids
    IUP and CD, the hard-to-build parts.

  *Verified 2026-10-30 against the Debian package archive and the chdkptp
  source mirror; built in a `debian:trixie` container on 2026-11-17.*
- **The udev rule** in `tools/udev/`, so a desktop's `gvfsd-gphoto2` does not
  claim the camera. The `.deb` installs it. On a headless box with no login
  seat, access comes from the `plugdev` group instead of `uaccess`, so the
  controlling user must be in `plugdev`.
- **A separate power supply for the camera.** Never power it from the
  controller's own 5 V rail. Lens and flash current spikes will brown out a
  Raspberry Pi. See [02-power.md](02-power.md).

## Driving a dedicated controller from a workstation

Claude Code runs on the workstation, and the controller is reached over SSH.
The CLI's `--json` output is the contract, so the remote case is just
transport:

```sh
ssh controller canonscope --json shoot --tv 0.5
scp controller:<path from the JSON> .
```

An MCP server on the workstation that shells out over SSH, and chdkptp's own
networked mode (`connect -h=host -p=port`), are both possible. Neither is
built. **Untested.**

There's a practical reason Claude Code stays on the workstation: a 2 GB board
is below Claude Code's 4 GB requirement. That keeps the controller a small,
boring appliance, which is the right shape anyway.

## Raspberry Pi as the reference controller

The reference board is a **Raspberry Pi 4 Model B, 2 GB**. Notes for it, and
for similar boards:

**OS: Raspberry Pi OS Lite 64-bit (trixie).** *Decision, 2026-10-30.* It was
chosen over Ubuntu Server because:

- It is lighter at 2 GB of RAM, with no snapd and no cloud-init stack.
- It has no snapd write-churn on an SD card you are trying not to wear out.
- Native Pi tooling works unguarded: `vcgencmd`, `rpi-eeprom` and firmware
  updates.
- It is Debian trixie underneath, which is what the release `.deb`s and the
  dev container are built on.

**Packages.** If you are not installing the `.deb`:
`build-essential liblua5.2-dev lua5.2 libusb-dev libreadline-dev git`. Add
`tmux` (so long work survives a dropped SSH session), `restic` for backups and
`gphoto2` to sanity-check enumeration as wanted. *Verified present for arm64
in trixie, 2026-10-30.*

**Python.** Debian trixie ships `python3` 3.13, which is what the MCP server
is tested on. *Verified 2026-11-06 against packages.debian.org; not yet
confirmed on a board.*

**Storage.** Boot from a good microSD card and keep incidental writes down,
because card wear comes from churn, not from captures:

- `noatime` on `/`
- journald to volatile storage, capped
- no swap on the card
- nothing container-shaped on the host filesystem

**Don't share the camera's USB bus with a bus-powered spinning disk.** It
contends for bandwidth and, worse, for the power budget the camera's USB
connection depends on.

**Cooling.** A bare Pi 4 throttles at 80 °C, and sustained capture is the kind
of load that finds that limit. Fit a heatsink. `vcgencmd get_throttled` reports
current state in its low bits and "since boot" in bits 16–19, so don't confuse
the two.

**No RTC.** An offline Pi boots with no idea of the time, which corrupts image
filenames and EXIF timestamps. Fit a DS3231-class RTC module, or set the clock
from the workstation on connect. Until then, record a monotonic sequence
number alongside wall-clock time, so drift is at least detectable.

## Offline-first: three connectivity tiers

A dedicated controller should keep working with **no internet, no LAN
services and no external artefact source**. Three tiers, where tier 0 must
stand on its own:

| Tier | What is present | Adds |
| --- | --- | --- |
| **0 — autonomous** | controller + camera + local storage | everything needed to run, rebuild and back up |
| **1 — workstation** | a workstation reachable over LAN or VPN | Claude Code, the MCP server, `git` push/pull, `rsync` |
| **2 — internet** | upstream sources | refreshing the asset mirror, remote storage if ever wanted |

**Nothing in tier 1 or 2 may become a dependency of tier 0.** Concretely:

- **Anything downloaded must also be vendored** onto local media with a
  checksum. That includes OS packages: an offline board cannot
  `apt install liblua5.2-dev`. `tools/fetch-assets.sh` mirrors CHDK but not
  `.deb`s yet (see [ROADMAP.md](../ROADMAP.md)).
- **A prebuilt chdkptp**, so a rebuild needs neither network nor toolchain.
  The release `.deb` now covers this.
- **A copy of this repository** on the local artefact store. `git bundle`
  gives a single file.
- **Assume no NTP and no DNS.** Reach peers by address or an explicit
  `/etc/hosts` entry, and never let the isolated node depend on a network
  resolver. A node whose diagnostics depend on the network breaks exactly when
  you need them.
- **Turn off telemetry** in anything that phones home. A library that tries to
  reach the internet will at best time out quietly, and at worst stall
  startup on DNS.

## Local artefact store and backups

*Proposed; not built.* Use a USB drive, **formatted ext4, not FAT or exFAT**.
restic needs POSIX locks and permissions, and FAT has no permission bits.

```
/artefacts
  git/canonscope.bundle     this repository
  assets/                   rsync of the CHDK asset mirror
  debs/                     cached .deb dependencies
  images/                   the OS image used, for a rebuild from scratch
/restic                     restic repository
```

**Artefacts and backups are two policies, not one store.** Rotation is right
for a backup and wrong for a deliberate keep. Once something stops appearing
in new snapshots, the last snapshot holding it eventually ages out. So keep
captured output in never-pruned, self-describing directories, and let only
config rotate under `restic forget`.

**Run `restic backup` on the controller, but `forget --prune` from the
workstation.** Prune is the memory-hungry phase and grows with repository
age. On 2 GB it can work for weeks and then start failing.

**Decide what the encryption protects against before writing backup code.**
A restic password stored on the controller, for a repository on a drive
attached to the controller, protects nothing: you cannot escrow a secret
inside the failure domain it guards. If the threat is card wear-out, say so,
and keep a low-ceremony password escrowed elsewhere. If the drive travels,
the password must live somewhere that is neither the controller nor the drive.

## Sync tools

Each job has one tool:

| Job | Tool |
| --- | --- |
| Source code | **git** over SSH |
| Asset mirror and other untracked bulk | **rsync** over SSH |
| Snapshots | **restic** to the local drive |

**Continuous sync tools (mutagen and similar) are deliberately out.** git
already moves the workspace. Syncing a checkout wholesale also propagates the
`.git` directory's per-checkout state (index, hooks), which corrupts it.
