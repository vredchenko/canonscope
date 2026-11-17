# Storage and CHDK

## SD card limits

The SX200 IS takes **SD and SDHC only, up to 32 GB**. No SDXC (64 GB and up).
MMC formats are also accepted. A microSD card in an adapter works fine.

| Standard | Capacity | Filesystem | SX200 IS |
| --- | --- | --- | --- |
| SD | up to 2 GB | FAT16 | yes |
| SDHC | 4-32 GB | FAT32 | yes |
| SDXC | 64 GB - 2 TB | exFAT | **no** |

**Class 6 or faster** for 720p video. Any Class 10 / U1 card is comfortably
enough.

## CHDK: what it is

A community firmware **add-on**, not a replacement. It loads from the SD card
into RAM and runs alongside Canon's own firmware. Nothing is written to the
camera permanently — **remove the card and the camera is stock again.**

What it adds: RAW/DNG output, manual overrides (long exposures, faster shutter,
ISO and aperture), live histogram, zebra stripes, bracketing, an intervalometer,
motion detection, and Lua / uBASIC scripting.

For this project CHDK is **mandatory, not a nice-to-have**: Canon dropped
PowerShot remote capture around this generation, so the stock firmware offers no
usable programmatic control. See [04-remote-control.md](04-remote-control.md).

Related projects, for context: Magic Lantern (Canon EOS DSLRs), SDM (a CHDK fork
focused on stereo and multi-camera sync), OpenMemories (some Sony models), and
assorted Nikon/Panasonic hacks (mostly video bitrate).

## Getting CHDK onto a card

Download the **1.6.1 rev 6355** build matching the firmware revision you read in
[01-camera-and-firmware.md](01-camera-and-firmware.md) — `100c` or `100d` — from
the [autobuild server](https://mighty-hoernsche.de/).

Two ways to start it:

- **Manual** — load it from the Canon firmware-update menu each time the camera
  powers on.
- **Autoboot** — a bootable card with the **write-protect tab locked**. The
  locked tab is what triggers the boot, so the card is read-only to the camera
  in this mode; this is the right choice for an unattended rig.

**Dual-partition is supported on this port**, so a card larger than 4 GB can
still use the autostart method: a small bootable FAT16 first partition for CHDK
plus a large FAT32 data partition. A plain 2-4 GB card is simply less fiddly if
you have one lying around — it is a convenience, not a constraint.

*Dual-partition support verified 2026-10-30 against the CHDK wiki and
`platform/sx200is/notes.txt`.*

## Reading the card from another machine

Mostly **unnecessary** — remote capture streams images straight to the host over
USB without touching the card at all. See
[04-remote-control.md](04-remote-control.md). This section is kept for the cases
where you do want card-level access.

- **Wi-Fi SD cards:** Eye-Fi and FlashAir are discontinued (FlashAir only
  second-hand). ezShare is still sold but slow and flaky. Not recommended.
- **SD multiplexers** (SDWire, SD Mux) switch one card between the camera and a
  USB host electrically. Check the form factor fits the SX200's slot and the
  closed battery/card door.

> **Never mount the card on two hosts at once.** FAT has no locking, so
> concurrent mounts corrupt the filesystem. Switch only with the camera powered
> off, or avoid the problem entirely by going over USB with `chdkptp`.
