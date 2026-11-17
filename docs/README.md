# canonscope documentation

Research and design notes for driving a **Canon PowerShot SX200 IS** (2009,
DIGIC IV, DryOS) programmatically via [CHDK](https://chdk.fandom.com/). There
is one topic per file. For installation and usage, start at the
[top-level README](../README.md).

```
controller (chdkptp) --USB--> SX200 IS (CHDK autoboots from a locked SD card)
                                 ^
                                 +-- battery now; mains-fed dummy battery later
```

## Documents

| File | Contents |
| --- | --- |
| [01-camera-and-firmware.md](01-camera-and-firmware.md) | Camera specs, how to read the firmware revision, CHDK port status |
| [02-power.md](02-power.md) | Replacement batteries, DIY dummy battery, dummy-load test procedure |
| [03-storage-and-chdk.md](03-storage-and-chdk.md) | SD card limits, CHDK install and autoboot, card access |
| [04-remote-control.md](04-remote-control.md) | chdkptp, remote capture, USB remote, rig wiring |
| [05-open-questions.md](05-open-questions.md) | What is still unresolved, and what has been settled |
| [06-controller-host.md](06-controller-host.md) | The machine the camera plugs into: requirements, Raspberry Pi notes, offline-first design |
| [07-shell-and-provisioning-lessons.md](07-shell-and-provisioning-lessons.md) | Patterns and traps for scripts that write to hardware or provision headless boxes |
| [08-eyes-for-claude.md](08-eyes-for-claude.md) | The project's purpose, and what it changes |
| [09-capability-inventory.md](09-capability-inventory.md) | What the camera can be made to do, with worked examples |
| [10-control-surface.md](10-control-surface.md) | The `canonscope` CLI as the contract; the MCP server and a parked local action-model experiment built on top of it |

## Status

**The capture path works end to end.** As of 2026-10-30, the camera runs CHDK
1.6.1 from a locked card, `tools/capture.sh` takes a photo over USB with
nothing written to the SD card, and a Claude Code session reads the file. The
acceptance test passed the same day: handwriting on paper was legible.

The original gating risks are retired. The firmware (`GM1.00D`) is supported,
CHDK autoboots, and remote capture is confirmed on the body, not just inferred
from source. What remains is breadth rather than risk: the `canonscope` CLI
and MCP server still need runs against the real camera, and there is the
optional dedicated-controller build. [ROADMAP.md](../ROADMAP.md) is the task
list.

## Provenance

Every claim in these documents carries one of two labels:

- **Researched** — from shopping and feasibility research (product listings,
  reviews, general electronics practice). Not verified against hardware or
  source.
- **Verified `<date>`** — checked against a named source: the CHDK wiki (via
  `chdk.fandom.com/api.php`, because the rendered wiki is behind Cloudflare),
  the autobuild server, the CHDK source trunk mirror
  [01luna/CHDK](https://github.com/01luna/CHDK), or the physical camera.

Claims verified **against the camera itself** began on 2026-10-30 and are dated
individually. A `Researched` label still means plausible and untested. Where a
document mixes the two, each claim carries its own label. Don't infer one from
the section around it.
