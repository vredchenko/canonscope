# Purpose: eyes for a Claude Code session

Stated 2026-10-30, and the first actual purpose the project has had:

> Draw on a whiteboard, write on paper, or point the camera at something in the
> real world, and a Claude Code session can see it — instead of taking a phone
> photo and emailing it to yourself.

This is a good fit for what the rig already is, and it closes several questions
that were open only because the purpose was unknown. It also **re-prioritises
one thing that had been deferred to last**.

## Why the existing design already serves it

**Remote capture is exactly the right primitive**, and it is confirmed supported
on this body ([04-remote-control.md](04-remote-control.md)). Images stream
straight to the host over USB with nothing written to the SD card — so no card
access, no SD multiplexer, no Wi-Fi SD card, no swapping media. The capture path
is a single command.

**Claude Code reads images natively.** Its `Read` tool renders JPG and PNG
visually, so the delivery mechanism is nothing more exotic than *put a JPG where
the session can read it*. No custom protocol, and no plugin strictly required to
get the first version working.

## The minimum viable version

Achievable without any of the deferred hardware work:

1. Camera on, CHDK booted from the locked card, USB to the controller (the
   workstation itself, or a separate board).
2. A capture script runs `chdkptp -c -e"rec" -e"remoteshoot -jpg <path>"` on
   the controller (over SSH if it is a separate board) and lands the JPG where
   the session can read it.
3. The session reads the local file.

That is the whole loop. A canonscope skill wrapping it is polish on top, not a
prerequisite.

## What the purpose changes

### JPG, not RAW — which closes a question

Whiteboard strokes and handwriting need no RAW. **The port's RAW bugs therefore
stop mattering**: the blue cast with corner stripes, and the broken RAW in
ISO 3200 Scenery mode, were listed as unresolved in
[05-open-questions.md](05-open-questions.md) and are now simply out of the path.

### Focus is the main technical risk

Close-range capture of a whiteboard or a sheet of paper is exactly where a
2009 compact's autofocus struggles, and it is the thing most likely to make
captures unusable.

The port helps here. `platform/sx200is/platform_camera.h` defines all three
subject-distance overrides:

```c
#define CAM_SD_OVER_IN_AF   1
#define CAM_SD_OVER_IN_AFL  1
#define CAM_SD_OVER_IN_MF   1
```

So CHDK can **set a fixed focus distance** in AF, AF-lock and manual-focus
modes. For a camera at a fixed distance from a fixed whiteboard, that converts
focus from a per-shot gamble into a configured constant. The port's range is
`CAMERA_MIN_DIST 58` to `CAMERA_MAX_DIST 68447`.

Also available: the port's manual AF-scan feature (set "AF Key" in the CHDK
menu), and the camera's own macro mode.

### Exposure matters more than it would for ordinary photography

A whiteboard is a large, bright, low-detail field with thin dark strokes —
precisely what fools an auto-exposure meter into blowing out the white and
losing the marker. CHDK's manual exposure overrides are the fix, and two of its
display aids exist for exactly this: the **live histogram** and **zebra
stripes** (overexposure warning). Both are listed in the port's shortcut keys.

### The 12x zoom becomes an asset

28–336 mm equivalent means the camera can sit well back and still fill the frame
with a sheet of paper, which keeps it out of the way and reduces perspective
distortion compared with holding it close.

### Always-ready moves mains power onto the critical path

**This reverses an earlier decision.** The dummy battery was deferred to last
([02-power.md](02-power.md)) on the reasoning that two fresh batteries cover
bring-up. That was correct when the purpose was unknown. It is wrong for this
purpose.

An "eyes" rig has to be **available on demand**. But:

- the camera **cannot power itself on**;
- it has **auto-power-off**, which must be disabled for it to stay ready;
- with auto-power-off disabled it is drawing current continuously, and a 1400 mAh
  NB-5L will not sustain that.

So either the camera runs on **mains power** via the dummy battery, or the
**power button gets wired** to a relay or opto so it can be woken on demand.
Those are the two options, and one of them has to happen for the intended use.
Battery power is fine for proving the capture path works; it is not fine for the
actual workflow.

### Captures are ephemeral, which relaxes three things

Whiteboard snapshots are consumed by a session and then largely worthless. That
is quite different from an image archive, and it lowers the stakes on:

- **the RTC** — timestamps matter much less for an ephemeral capture than for an
  archive, so an RTC drops from "requirement" to "nice to have";
- **storage** — 128 GB is vastly more than needed, and the SD-wear concern eases
  because captures need not be kept;
- **backups** — the thumb drive mainly protects the repo and config rather than
  irreplaceable output, which also softens the breakglass problem in
  [07-shell-and-provisioning-lessons.md](07-shell-and-provisioning-lessons.md).

### Latency is now a design constraint

The loop is interactive: point, ask, get an answer. That argues for keeping the
camera already on and in **Record** mode (it boots into Playback), possibly
keeping a chdkptp session warm, and capturing at a modest resolution rather than
full 12 MP. A few seconds is fine; half a minute of mode-switching is not.

## What this still does not settle

**Where does the camera physically live?** Desk-mounted and pointed at a fixed
whiteboard, or picked up and aimed at arbitrary things? **Parked deliberately
(2026-10-30) until the capture path works** — cross that bridge on arrival. It
will eventually determine:

- whether focus and zoom can be fixed constants or must be set per shot;
- whether a wired power button and permanent mains power make sense, or whether
  the rig needs to be portable and battery-powered after all;
- whether framing needs feedback (chdkptp has a rough live view) or whether
  capture-and-look is enough.

**Who triggers a capture?** The cleaner loop is for the session to initiate it —
"take a picture now" — rather than the user pressing something physical. Both
are possible; the choice affects whether a physical trigger is needed at all.

## It works — 2026-10-30

The loop ran end to end on the real hardware: `tools/capture.sh` takes a photo,
the JPEG lands on the host with nothing written to the SD card, and a Claude
Code session reads it with its ordinary `Read` tool. First image was a dark desk
scene; the session could pick out a silver device, a white bottle with a red
stripe, a coiled cable and a curtain edge.

### What the hardware confirmed

**`get_usb_capture_support()` returns 7.** That is
`PTP_CHDK_CAPTURE_JPG(0x1) | RAW(0x2) | DNGHDR(0x4)`, with `CRAW(0x8)` absent —
precisely the value predicted from reading `core/camera_info.c:255-261` and the
`CAM_HAS_FILEWRITETASK_HOOK` define, before any hardware was touched.

**`host:2.8 cam:2.9`.** The 2018 chdkptp mirror negotiates with CHDK 1.6.1,
confirming the compatibility inference from `chdku.lua:133` (`MAJOR ~= major or
MINOR < minor` — majors match, a higher camera minor passes).

**`get_buildinfo()` reports `platsub="100c"`** on a 1.00D camera, corroborating
the makefile shim that builds 100d from 100c source. `platformid=12736` is
`0x31C0`, matching the `P-ID:31C0` on the firmware screen.

### What the hardware taught that reading could not

**The desktop really does claim the camera.** On connect, `gvfsd-gphoto2`
spawns, the camera screen goes black, and chdkptp reports `Device or resource
busy` then `ptp_opensession failed 0x2ff`. Killing that process frees it
immediately. `capture.sh` does this automatically, but it is a workaround: a
udev rule is the real fix, and any controller will need it too.

> **Use `pkill -x`, never `pkill -f`.** With `-f` the pattern matches against
> every process's *full command line* — including the calling script's own,
> which contains the pattern — so it kills the caller. This happened, with exit
> code 144 and no output.

**Auto-exposure is the problem, as predicted — just in the other direction.**
The concern recorded earlier was whiteboards blowing out to white. The first
real shot failed the opposite way: a dim room underexposed so badly the scene
was barely legible. `remoteshoot -tv=0.5 -sv=800` fixed it visibly. Either way
the conclusion holds — **auto-exposure is not good enough for this use, and
CHDK's manual overrides are the reason the project works.**

**The camera stays in Record mode between shots** (`rec` returns `ERROR: already
in rec`). Good for the latency requirement: a rig left powered on does not pay
the mode-switch cost per capture.

**`remoteshoot` exposes `-sd` and `-sdmode`**, the subject-distance override.
That is the predicted answer to the focus problem: for a fixed camera-to-target
distance, focus becomes a configured constant.

### Flash: partly controllable, and probably the wrong tool anyway

Tested 2026-10-30 after the first underexposed shots.

**`remoteshoot` has no flash option at all** — its switches cover exposure,
focus, format and shot sequencing, and nothing else. The only `Flash` symbol in
chdkptp's Lua is a DNG EXIF tag constant.

**The flash mode *is* software-settable** via propset 2:

```
PROPCASE_FLASH_MODE    143    0 = auto, 1 = on, 2 = off
PROPCASE_FLASH_FIRE    122
```

`set_prop(143,1)` works — `get_prop(143)` and `get_flash_mode()` both confirmed
the change.

**But the pop-up itself is mechanical and cannot be driven in software.** The
port's own to-do list records this as closed-won't-fix:

> disable automatic pop-up flash / change to manual control — **Not possible**;
> flash popup is purely mechanical(ly coupled to lens extension/retraction)

The observable consequence: with the flash physically retracted,
`get_flash_ready()` returns **false** and stays false after a 2 s wait, because
the camera will not charge a flash that is down. Mode set to "on" changes
nothing. The documented workarounds are all physical — push it down with a
finger, or tape it down, depending on which way you want it stuck.

**`get_flash_ready()` is therefore the check that matters** before relying on
flash for a shot.

**For this project flash is likely the wrong answer regardless.** Pointing a
direct on-camera flash at a whiteboard or glossy paper produces a specular
hotspot exactly where the text is, and the pop-up cannot be raised or lowered
remotely — so an unattended rig cannot choose per shot. Better: ambient light or
a fixed desk lamp, plus the manual exposure overrides that already work. Flash
stays useful as a fallback for handheld shots of objects in the dark, where the
camera is in your hands and you can flip it up yourself.

### Firing the flash drops the camera off the USB bus

Tested with the flash physically raised and the mode forced on. The result:

```
WARNING: capture_get_data error I/O error
ERROR: I/O error uninit I/O error
attempted to close non-present device 001:021
```

No image was written, the camera went dark, and it vanished from `lsusb`
entirely. **Battery was at 69%**, so this is not a flat cell — it is a voltage
sag under load.

This is the failure [02-power.md](02-power.md) described before any hardware
existed:

> lens and flash draw **1.5-2 A bursts** and a sag looks like a flat battery

Charging and firing the flash is the largest current draw the camera makes, and
an aftermarket NB-5L has higher internal resistance than the Canon original. The
research notes had already flagged that undersized third-party cells make "the
camera cut out" on this body — observed here at 69% charge.

Three consequences:

- **`tools/capture.sh` forces flash off by default** (`--flash off`). An
  accidental flash costs the shot *and* the connection, which on an unattended
  rig is a silent failure.
- **The 470-1000 uF capacitor in the dummy-battery design is not optional.** It
  exists precisely to ride out this burst, and the burst is now measured
  behaviour rather than a figure from a forum.
- **The 2 A worst-case in the dummy-load test procedure is validated.** That
  number was a guess at the time it was written down; it is the right number.

## Acceptance test passed: handwriting is legible

2026-10-30, in a dark room, camera pointed at a notebook and a loose sheet:

```sh
./tools/capture.sh --out page.jpg --tv 0.5 --sv 400
```

The session read back the headings, a bulleted list and a hand-drawn diagram —
enough to transcribe the page and describe the sketch. **This is the use case
working**, not a proxy for it.

### What made it work

**`--tv 0.5 --sv 400`.** Half a second at ISO 400 in a dark room. Lower ISO than
the earlier `800` because text wants low noise more than it wants speed, and the
camera was resting on a surface so a slow shutter costs nothing.

**Paper is self-illuminating relative to a dark room.** The page came out well
exposed while the room stayed black — the subject was the brightest thing in
frame, which is the opposite of the whiteboard-blowout worry and much easier to
work with. The earlier underexposed shots had no bright subject to meter on.

### The image came out rotated 180 degrees, and that is a placement issue

**EXIF `Orientation` was `1` (normal)** — the camera believed itself upright, so
this is the *page* oriented away from the camera, not something the camera can
detect or auto-correct.

For a fixed rig this is a one-time setup concern: orient the camera and the
target once and it stays right. For handheld use it is unavoidable and
unimportant.

**It did not affect legibility.** The session transcribed the inverted page
without trouble. So rotation is a convenience for human viewing only, and
`capture.sh` deliberately does **not** do it: ImageMagick's `convert` is
available on a typical workstation but adding it as a dependency would break the
bash-and-coreutils-only rule that keeps `tools/` runnable on a bare controller. If
rotation is ever wanted, make it an opt-in flag that fails cleanly when
`convert` is absent.

### What this settles

The rig reads handwriting on paper in a dark room with no flash, no tripod and
no special lighting. Everything from here — mounting, mains power, a dedicated controller, a
udev rule — is about making it convenient and unattended, not about making it
work.
