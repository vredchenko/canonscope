# Camera and firmware

## The body

Canon PowerShot SX200 IS, released March 2009.

| | |
| --- | --- |
| Processor | DIGIC IV |
| OS | DryOS |
| Sensor | 1/2.3" CCD, 12.1 MP effective, max image 4000 x 3000; physical matrix 4080 x 3048, 12 bit |
| Lens | 12x optical, 28-336 mm (35 mm equiv.), f/3.4-5.3 |
| LCD | 3", 230k pixels |
| ISO | 80-1600 |
| Video | 1280 x 720 @ 30 fps |
| Output | HDMI |
| Power | NB-5L Li-ion |
| Size / weight | 103 x 61 x 38 mm / 220 g without battery |
| PTP product ID | `0x31C0` |

CHDK-relevant raw geometry, from `platform/sx200is/platform_camera.h`:
`CAM_RAW_ROWPIX 4080`, `CAM_RAW_ROWS 3048`, `CAM_SENSOR_BITS_PER_PIXEL 12`,
active area X 52-4052, Y 14-3014.

[Disassembly and repair guide](https://www.ifixit.com/Guide/Disassembling+Canon+PowerShot+SX200+IS/28471)
if the body needs opening.

## Reading the firmware revision

**Do this first.** Only firmware **1.00C** and **1.00D** have CHDK builds, so
this single check decides whether the project is possible at all. It needs
nothing but a readable SD card and enough power to reach PLAY mode.

The obvious key combo is useless. In PLAY mode, hold **FUNC/SET** and press
**DOWN** and you get only:

```
Firmware Ver. 1.0.0.0

[ OK ]
```

(If that shows a clock instead: hold FUNC/SET, briefly push **DISP**, then
**DOWN**.)

For the real revision, create an **empty file named `ver.req` in the card root**,
then in PLAY mode hold **FUNC/SET** and press **DOWN** *before the clock
displays*:

```
Canon PowerShot SX200 IS
P-ID:31C0 PAL D

Firmware Ver GM1.00C
NoError
Jan 28 2009 14:08:40
```

Keep holding FUNC/SET and press DOWN again for the adjustment and IS firmware
versions:

```
Adj Ver.004.013
IS FIrm Ver. 2.09
IS Param Vers. 2.07
```

Name the file **`vers.req`** instead (note the extra `s`) and one further DOWN
press adds the wear counters — worth recording as a baseline on a 16-year-old
body:

```
Adj Ver.004.013
Total Shoot: (number, alternates with shots done)
Zoom Retry Count: 0
Mecha Condition: 0x00000000
```

**CHDK confirmed running on this body, 2026-10-30** — booted from a locked
write-protect tab, built from `sx200is-100d-1.6.1-6355-full.zip`.

**This camera, read 2026-10-30:**

```
Canon PowerShot SX200 IS
P-ID:31C0 PAL D
Firmware Ver GM1.00D      <- supported; 1.00C and 1.00D are the only builds
Total Shoot: 2287         <- baseline shutter count
```

A low count for a 2009 body — about 150 shots a year — so shutter and zoom wear
should not be a concern.

**Practical note: the combo is fiddly and the screens time out quickly.** Hold
FUNC/SET down continuously and press DOWN to advance; each screen disappears
after a moment, so read the firmware line first and come back for the wear
counters on a second attempt rather than trying to catch everything in one pass.

*Verified 2026-10-30 against the CHDK wiki SX200IS page.*

## CHDK port status

**Supported, and still being built.** The
[autobuild server](https://mighty-hoernsche.de/) currently serves **CHDK 1.6.1,
revision 6355, generated 2026-07-20** for the SX200 IS, for both `100c` and
`100d`, as complete and small zip packages.

**Only 1.00C and 1.00D exist as targets.**
`platform/sx200is/sub/100d/makefile.inc` is a three-line shim:

```make
# sx200is - 100d uses 100c source (identical firmware)
TARGET_FW:=$(PLATFORMSUB)
override PLATFORMSUB=100c
include $(camfw)/makefile.inc
```

So 1.00D builds are 1.00C code; the two firmwares are identical as far as CHDK
is concerned. Any other revision has no port.

Background: the [SX200 porting thread](http://chdk.setepontos.com/index.php/topic,3994.0.html).
The firmware was originally blinked out by OldGit in July 2009; a working udumper
arrived 22 Aug 2009.

*Verified 2026-10-30 against the autobuild server and the CHDK source trunk.*

## Port quirks and known bugs

Behavioural quirks that matter for an automated rig:

- **The camera starts in Playback mode.** Half-press the shutter once to reach
  Record mode, or **hold the Power button ~2 s** to start directly in Record.
- CHDK **`<ALT>` mode is the Print button** on this body.
- **Custom Curves do not work** on the SX200.
- Sound recording is always on when optical zoom is enabled in video record
  mode. No mute function was ever found in the camera; the port's advice is to
  strip the zoom noise in post.
- Manual AF scan in video: set "AF Key" to Set or Shutter in the CHDK menu, then
  press it during recording to force a single AF scan. (The camera has no
  continuous AF in video.)

Shortcut keys:

| Mode | Action | Key |
| --- | --- | --- |
| ALT | Toggle RAW | DISPLAY |
| Half-press shoot | Toggle histogram | DOWN |
| Half-press shoot | Toggle zebra | MENU |
| Half-press shoot | Toggle OSD | RIGHT |
| Half-press shoot | Toggle disable overrides | LEFT |

Open bugs on the port, both affecting RAW:

- **Bad RAW writing** — a blue cast, with small stripes in the upper-right and
  bottom-right corners.
- **Broken RAW in ISO 3200 Scenery mode** — that mode always uses a reduced RAW
  buffer, so a nominally 12 MP RAW comes out as roughly 2 MP of coloured
  stripes.

Everything else on the port's historical to-do list is closed, including AV
bracketing (fixed in build 892) and video-quality overrides (fixed in trunk
886).

Useful LED addresses, if you ever want status signalling without the screen:

```
0xC0220138  Shortcut/Print button LED (blue)
0xC0220134  Green status LED
0xC0223030  AF-LED
```

*Verified 2026-10-30 against the CHDK wiki and `platform/sx200is/notes.txt`.*
