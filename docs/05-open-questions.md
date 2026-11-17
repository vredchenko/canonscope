# Open questions

## Decisions to make

**The 3rd battery terminal: thermistor resistor or remote input?** A fixed ~10k
resistor is needed for the camera to accept a dummy battery, but the same
contact can serve as a CHDK remote trigger input
(`CAM_REMOTE_AtoD_CHANNEL 5`). Bringing the contact out to a header instead of
soldering the resistor in keeps both options open. See
[02-power.md](02-power.md).

**Card size and partitioning.** Dual-partition autoboot works on this port, so a
32 GB SDHC card is viable; a spare 2-4 GB card is just less fiddly. Moot if
remote capture becomes the only workflow, since nothing gets written to the card.
See [03-storage-and-chdk.md](03-storage-and-chdk.md).

## Unresolved

**Where to source an NB-5L dummy battery / DC coupler.** None was found on
Amazon UK at the time of research. The ACK-DC30 kits that exist don't name the SX200, have no
reviews and ship from China. eBay and AliExpress searches for
`NB-5L USB dummy battery` and `DR-30 USB` have not been done yet. Building one is
the documented fallback. See [02-power.md](02-power.md).

**Does Claude Code render an MCP image block as vision, or as base64 text?**
Reports exist of `ImageContent` arriving at the model as raw text — 15–25k
tokens and unreadable. Unverified against current Claude Code. The design in
[10-control-surface.md](10-control-surface.md) returns paths by default so the
answer only affects one explicit tool, but the answer is still needed. One
ten-line server and one 720×240 PNG settle it.

**Needle 3 on the actual board.** *(Moot — Needle dropped 2026-11-06; see ROADMAP.md. Kept because it is the question to answer first if it is ever reopened.)*

 Everything in phase 2b was installed, bundled
and run on the x86_64 workstation on 2026-11-06; the arm64 engine was
cross-fetched and type-checked but **nothing has executed on a Pi 4 with
2 GB**, and there is no published benchmark for that board. Thresholds are set
in advance in [10](10-control-surface.md) §8: peak RSS under 300 MB, under 3 s
per decision, or Needle does not ship on the thumb drive.

**Needle: zero-argument verbs or regex triggers — which one bought the accuracy,
and which lost the refusal?** Experiment 3 in [10](10-control-surface.md) §6
changed both at once; in-domain accuracy went to 8/9 and the out-of-domain
query "what's the weather in Lagos?" went from a correct `[]` to firing
`camera_zoom_in`. Re-run the same tool set without triggers to separate them.
Until then the front end gates the domain with a word list before the model
runs, and treats Needle's own refusal as unreliable.

**Does Pi OS trixie ship CPython 3.13 as `python3`?** ~~Open.~~ **Answered
2026-11-06**: Debian trixie ships `python3` at **3.13.5-1**, verified against
`packages.debian.org/trixie/python3`. The `cp313` wheel sets resolved for
`mcp` are therefore the right ABI. Two caveats keep this short of fully
settled: Raspberry Pi OS tracks Debian but is not identical to it, and this
was read off the package index rather than off the board. Confirm with
`python3 -VV` on the Pi at bring-up.

**Does the MCP server change Claude's behaviour at all?** Claude Code already
has `Bash` and the CLI has `--help`. If Claude reaches for `canonscope`
directly even with the tools present, phase 2a's descriptions are not earning
their keep. Observable in the first sessions; decides whether 2a was worth
building beyond "other MCP clients".

## Answered

**Does remote capture to the host work, without writing to the card?** **Yes.**
`CAM_HAS_FILEWRITETASK_HOOK` is set for this camera, which enables JPG remote
capture; RAW and DNG-header targets are unconditional. CRAW is not available
(no `CAM_HAS_CANON_RAW`), as expected on a compact. Working details and the
on-camera confirmation command in [04-remote-control.md](04-remote-control.md).
*Answered 2026-10-30 from the CHDK source trunk.*

**Is the port still maintained?** Effectively yes — the autobuild server emits
CHDK 1.6.1 rev 6355 (2026-07-20) for both firmware revisions. See
[01-camera-and-firmware.md](01-camera-and-firmware.md).
*Answered 2026-10-30.*

## Settled

**Remote storage targets (S3, SMB) — descoped 2026-10-30.** Captures land on
local storage. Redirecting them later is a small change, and designing for
it now would buy nothing. `rclone` is therefore not part of the build.

**What the rig is for, beyond its first purpose — answered 2026-10-30:
deliberately open.** The project started as "an old camera and a spare board,
and something useful to do with them". That has a real design consequence:
build a **general-purpose tethered capture rig** and do not specialise.

Concretely — keep remote capture to the host as the primary path, since it costs
nothing and serves every eventual use; keep local storage simple; prefer
reversible choices over optimised ones; and stop hedging recommendations against
requirements that do not exist. A general rig narrows towards a specific purpose
easily if one emerges. The reverse is not true.

**Do the port's RAW bugs matter? — answered 2026-10-30: no, they are out of the
path.** The purpose is capturing whiteboards, paper and objects for a Claude
Code session to read ([08-eyes-for-claude.md](08-eyes-for-claude.md)), which
wants JPG. The blue cast with corner stripes and the broken RAW in ISO 3200
Scenery mode therefore never arise. Still recorded in
[01-camera-and-firmware.md](01-camera-and-firmware.md) in case RAW is ever
wanted.

**What firmware revision is the camera running? — answered 2026-10-30:
`GM1.00D`.** One of the two revisions with a CHDK build, so the project is
viable. Shutter count at first reading was 2287. Procedure and the full screen
output are in [01-camera-and-firmware.md](01-camera-and-firmware.md).
