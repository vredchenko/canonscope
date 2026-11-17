# What the camera can actually do, and how to drive it

Written 2026-11-06, after the first exploratory session against the live body.
This is the "what is possible" document; [04-remote-control.md](04-remote-control.md)
covers the transport and [08-eyes-for-claude.md](08-eyes-for-claude.md) covers why
the project exists.

Everything marked **Verified 2026-11-06** was run against the physical camera on
that date and the output pasted back here unedited. Items marked **Source** were
read out of the port's own code but not executed. Items marked **Untested** are
documented because they exist, not because they have been tried.

## 1. The mental model: three layers

This is the thing to understand first, because almost every confusion downstream
comes from not knowing which layer a command belongs to.

```
  workstation                          camera
  -----------                          ------
  chdkptp.sh  --- PTP over USB --->  Canon firmware (DryOS)
      |                                   |
      |                               CHDK, loaded at boot from the SD card
      |                                   |
      +--- sends Lua source ---------> on-camera Lua interpreter
           <-- gets the result back --+
```

**Layer 1 — Canon's own firmware.** A 2009 compact camera. Knows nothing about
any of this.

**Layer 2 — CHDK.** Community firmware, loaded from the SD card at power-on. It
does not replace Canon's firmware; it loads *alongside* it and hooks into it.
This is what adds the Lua interpreter and the extended PTP commands.

**Layer 3 — chdkptp.** The program on this machine. It speaks PTP (the standard
"Picture Transfer Protocol" every camera implements) over the USB cable, plus
CHDK's private extensions to it.

So when you run a capture, the chain is: your shell → `chdkptp` → USB → Canon's
PTP stack → CHDK's hook → Lua on the camera → the shutter.

**Why this matters practically:** there are *two* command vocabularies, and they
are not interchangeable.

- **chdkptp commands** (`shoot`, `ls`, `download`, `rec`) run on *this* machine
  and orchestrate things.
- **CHDK Lua functions** (`set_zoom`, `get_temperature`, `shoot`) run on *the
  camera*, and you reach them by wrapping them in `lua` or `luar`.

Both have a function called `shoot`. They are different functions.

## 2. The shape of every command

Every invocation in this document looks like this:

```sh
./build/chdkptp/chdkptp.sh -c -e'<command>' -e'quit'
```

Piece by piece:

| Piece | Meaning |
| --- | --- |
| `-c` | **c**onnect to the first CHDK camera found on USB |
| `-e'...'` | **e**xecute one chdkptp command; repeatable, runs in order |
| `-e'quit'` | leave, rather than dropping into the interactive prompt |

Without `-e'quit'` you get chdkptp's own interactive shell, which is a perfectly
good place to explore — type `help` there for the command list.

Two of those chdkptp commands are the gateway to layer 3:

- **`lua <code>`** — send Lua to the camera and *do not wait*. Fire and forget.
- **`luar <code>`** — send Lua, **w**ait for the **r**esult, print it. Shorthand `=`.

`luar` is what you want almost always. Example, verified:

```sh
./build/chdkptp/chdkptp.sh -c -e'luar return get_zoom_steps()' -e'quit'
```
```
connected: Canon PowerShot SX200 IS, max packet size 512
11:return:'126'
```

The `11:` is just a message serial number. Note the `return` — without it the Lua
runs but hands nothing back.

### The one-line health check

**Verified 2026-11-06.** A good first command, and the basis for a future
`canonscope status`:

```sh
./build/chdkptp/chdkptp.sh -c -e'luar return string.format(
  "build=%s plat=%s-%s zoom=%d/%d batt=%dmV usb_pwr=%d temp=%d/%d/%dC free=%dMB",
  get_buildinfo().build_number, get_buildinfo().platform, get_buildinfo().platsub,
  get_zoom(), get_zoom_steps(), get_vbatt(), get_usb_power(),
  get_temperature(0), get_temperature(1), get_temperature(2),
  get_free_disk_space()/1024)' -e'quit'
```

Actual output from this body:

```
build=1.6.1 plat=sx200is-100c zoom=0/126 batt=3580mV usb_pwr=0
temp=19/30/25C free=3867MB
```

Worth noticing: **the platform reports `100c` although this body's firmware is
`GM1.00D`.** That is not a bug and not a mismatch — it is the compile-time fact
recorded in CLAUDE.md showing through at runtime. The `100d` build is literally
compiled from `100c` source.

## 3. Reading state

All **Verified 2026-11-06** unless noted. All are Lua, so wrap in `luar return`.

| Call | Returns | Measured here |
| --- | --- | --- |
| `get_buildinfo()` | table: CHDK version, platform, build date | `1.6.1`, `sx200is-100c` |
| `get_vbatt()` | battery millivolts | `3580` |
| `get_usb_power()` | 1 if running off the USB cable | `0` (on the NB-5L) |
| `get_temperature(0\|1\|2)` | optical / CCD / battery, °C | `19 / 30 / 25` |
| `get_zoom()`, `get_zoom_steps()` | current step, total steps | `0`, `126` |
| `get_free_disk_space()` | free card space, KB | `3867 MB` free |
| `get_jpg_count()` | shots that still fit on the card | `1237` |
| `get_exp_count()` | lifetime shutter actuations | see [01](01-camera-and-firmware.md) |
| `get_propset()` | which property-ID table this body uses | `2` |
| `get_raw_support()` | can it write RAW | `true` |
| `get_nd_present()` | has a neutral-density filter | `0` — none |
| `get_sd_over_modes()` | subject-distance override bitmask | `7` = AF\|AFL\|MF |
| `get_usb_capture_support()` | tethering formats bitmask | `7` = JPG\|RAW\|DNGHDR |
| `get_orientation_sensor()` | which way up the body is | **Untested** |
| `get_dofinfo()` | table of depth-of-field maths | see below |

### `get_dofinfo()` is nicer than it sounds

**Verified 2026-11-06.** It returns the camera's own depth-of-field calculation,
which saves doing the optics yourself:

```
zoom=0/126 focal=5000 eff=27290 near=672 far=10838 hyp=1434
```

**Distances are in 1/1000 units** — micrometres for focal lengths, millimetres
for distances. So that reads as: lens at its widest, **5.0 mm actual focal
length**, **27.3 mm full-frame equivalent**, and everything from **67 cm to
10.8 m** is acceptably sharp, with a hyperfocal distance of **1.43 m**.

For a fixed copy-stand rig this is the number that tells you whether you need to
touch focus at all. Often you do not.

## 4. Exposure: the APEX96 system

This is the part that trips up everyone coming from normal camera controls, so
it gets its own section.

### Why the numbers look wrong

You would expect to set *f/5.6*, *1/125 s*, *ISO 400*. CHDK instead wants
`av96`, `tv96` and `sv96`. These are **APEX values multiplied by 96**.

APEX is a 1960s scheme that turns the multiplicative relationships of photography
into additive ones. Every "stop" — a doubling or halving of light — is **+1 or −1
in APEX**, and therefore **±96 in CHDK's units**. The 96 is there so the integer
arithmetic has enough resolution for 1/3-stop steps (32 units each).

The practical payoff: **adding 96 to any of the three always means exactly one
stop.** "Open up one stop" is `set_av96(get_current_av96() - 96)`, with no
lookup table and no powers of two.

### Verified conversions from this body

**Verified 2026-11-06.** Readings taken in the dim room during the demo:

| Raw | Call | Means |
| --- | --- | --- |
| `av96 = 347` | `av96_to_aperture(347)` → `3500` | **f/3.5** (aperture in 1/1000) |
| `tv96 = 480` | `tv96_to_usec(480)` → `31250` | **1/32 s** (31250 µs) |
| `sv96 = 659` | `sv96_to_iso(659)` → `364` | **ISO 364 "real"** |
| | `sv96_to_iso(sv96_real_to_market(659))` → `599` | ISO 599 "market" |

And the same conversions run backwards, which is how you actually set things:

| Want | Call | Gives |
| --- | --- | --- |
| f/2.8 | `aperture_to_av96(2800)` | `285` |
| 1/125 s | `seconds_to_tv96(1,125)` | `669` |
| ISO 400 | `iso_to_sv96(400)` | `672` |

**Real versus market ISO**: Canon's published ISO numbers do not match the
sensor's measured sensitivity. CHDK exposes both and converts between them.
`tools/capture.sh --sv` takes the **real** value.

The good news for everyday use: **`capture.sh` hides all of this.** `--tv 0.5`
and `--sv 400` are in human units; they pass through to chdkptp's `remoteshoot`,
which does the conversion host-side. Reach for APEX96 only
when you are doing something the script does not cover, such as nudging exposure
by a known fraction of a stop between frames.

### Setting exposure

**Source** (read from `modules/luascript.c`, not individually executed):

- `set_tv96_direct`, `set_av96_direct`, `set_sv96` — set the value directly.
- `set_tv96`, `set_av96` — snap to the nearest value the camera actually offers.
- `set_ev(n)` — exposure compensation, same 96-per-stop units.
- `set_aelock(1)` / `set_aflock(1)` — freeze exposure or focus across a sequence,
  which is what you want for a time-lapse that must not flicker.

## 5. Focus and zoom

**Zoom** is **126 discrete steps** on this body (`get_zoom_steps()`, verified).
Steps are repeatable, so "step 40" is a reproducible framing you can record in a
config file and return to.

```lua
set_zoom(40)        -- absolute step
set_zoom_rel(-5)    -- relative
set_zoom_speed(50)  -- percent, where supported
```

**Untested** — these move the lens and were not run during the demo session.

**Focus** takes **millimetres**:

```lua
set_mf(1)        -- manual focus on
set_focus(2000)  -- 2 metres
get_focus_ok()   -- did it achieve focus
```

The important fact for a fixed rig: `get_sd_over_modes()` returned **7**, meaning
subject-distance override works in **autofocus, AF-lock and manual** modes alike
(**Verified 2026-11-06**). Many CHDK ports only manage one. A fixed
camera-to-subject distance can therefore be a configured constant rather than a
per-shot gamble — which is exactly the whiteboard/copy-stand case.

`tools/capture.sh --sd 2m` already wires this up.

## 6. Live view — the feature that is not photography

**Verified 2026-11-06.** The camera will stream its viewfinder over USB without
taking a photo, writing to the card, or touching the shutter mechanism.

```sh
cd /tmp
chdkptp.sh -c -e'lvdumpimg -vp=lv%04d.ppm -count=1' -e'quit'
convert 'lv%04d.ppm' lv.png
```

A frame came back at **720×240** as a Netpbm `.ppm`, converted to PNG with
ImageMagick and read directly by a Claude Code session.

Two cautions, both learned in that run:

- **The `%04d` is passed through to chdkptp, not expanded by the shell** — quote
  it. With `-count=1` chdkptp wrote a file named literally `lv%04d.ppm`, which is
  harmless but surprising; with a higher count it numbers them properly.
- **`.ppm` is uncompressed** — 518 KB for one 720×240 frame. Convert or pipe;
  do not accumulate them.

Options worth knowing: `-vp` grabs the **viewport** (the live image), `-bm` grabs
the **bitmap** (CHDK's on-screen overlay), and `-count=N` sets how many frames.
`lvdump` writes a single binary stream instead, for feeding a video pipeline.

**Why this matters more than it first appears.** Live view is cheap — no shutter
actuation, no mechanical wear, no card write — on a body whose shutter is
irreplaceable. For "is anything happening yet", poll live view; spend an actual
exposure only when it matters. On a 16-year-old camera with 2287 actuations at
first reading, that distinction is worth designing around.

## 7. Motion detection

**Source** — present in the API, not yet tried on this body.

CHDK can run motion detection **on the camera**, with no host involvement:
`md_detect_motion` lays a grid over the live view, compares cells between frames,
and returns when enough of them change. `md_get_cell_diff` and `md_get_cell_val`
read individual cells.

Because it runs on-camera there is no USB round-trip in the trigger path, which
is why this is the feature people built lightning and wildlife triggers on.

Recorded in [05-open-questions.md](05-open-questions.md) as untried.

## 8. The rest of the inventory

**Source**, from `assets/chdk/source/CHDK/modules/luascript.c` — roughly 200 Lua
functions. Grouped by what they are for:

| Group | Representative calls |
| --- | --- |
| Shooting | `shoot`, `set_record`, `get_shooting`, `is_capture_mode_valid` |
| Exposure | `set_tv96`, `set_av96`, `set_sv96`, `set_ev`, `set_nd_filter`, `set_aelock` |
| Focus | `set_focus`, `set_mf`, `set_aflock`, `get_focus_ok`, `get_dofinfo` |
| Zoom | `set_zoom`, `set_zoom_rel`, `set_zoom_speed` |
| RAW/DNG | `set_raw`, `get_raw_count`, `raw_merge_start`, `set_raw_develop` |
| Histogram | `get_live_histo`, `shot_histo_enable`, `shot_histo_write_to_file` |
| Motion | `md_detect_motion`, `md_get_cell_diff`, `md_af_led_control` |
| Sensors | `get_temperature`, `get_vbatt`, `get_orientation_sensor`, `get_bv96` |
| Screen drawing | `draw_string`, `draw_rect`, `draw_ellipse`, `draw_pixel`, `cls` |
| Hardware | `set_led`, `play_sound`, `set_backlight`, `set_lcd_display`, `shut_down` |
| Input simulation | `is_pressed`, `wait_click`, `post_levent_to_ui`, `wheel_left` |
| Files | `get_image_dir`, `set_file_attributes`, `get_free_disk_space` |
| Config | `get_config_value`, `set_config_value`, `save_config_file` |
| Raw memory | `peek`, `poke`, `call_event_proc`, `call_func_ptr` |
| Time | `get_tick_count`, `get_time`, `set_clock`, `get_day_seconds` |

`set_led` is **Verified 2026-11-06** only in the weak sense that
`set_led(9,1) sleep(600) set_led(9,0)` returned cleanly — nobody was watching the
camera to confirm a lamp lit. **LED channel numbers are camera-specific** and the
mapping for this body is not established.

`peek`, `poke` and `call_event_proc` reach arbitrary camera memory. They are how
ports get developed, and they will hard-crash a camera. Not needed for this
project.

## 9. What this body cannot do

Stated here so it does not get rediscovered. All **Source**, from the port's own
files, except where noted.

- **No remote video.** `CAM_VIDEO_CONTROL` is `#undef` at
  `assets/chdk/platform/sx200is/platform_camera.h:31`, and `get_video_button()`
  returned `false` (**Verified 2026-11-06**). Stills only, remotely. Video can be
  started by hand on the camera; it cannot be driven over USB.
- **No CRAW.** `get_usb_capture_support()` returns `7` — JPG, RAW and DNG header,
  with the `CRAW` bit absent.
- **No ND filter.** `get_nd_present()` returned `0`.
- **The flash cannot be raised.** The mode is settable via `set_prop(143, …)`;
  the pop-up is mechanical. See [08](08-eyes-for-claude.md).
- **The camera cannot power itself on**, and boots into Playback.
- **No floating point.** See the gotchas below — it is a property of this Lua
  build, not of the camera.

## 10. Gotchas

**CHDK's Lua is integer-only.** This surprised a session on 2026-11-06 and cost
several confused minutes. **Verified** on the body:

```
3/2 = 1
```

There is no floating point in the on-camera interpreter. Consequences:

- **`string.format("%f", …)` does not work.** It silently emits a literal `f`
  rather than erroring — `"f/%.2f"` printed `f/f`. Use `%d`.
- **Division truncates.** `364/10` is `36`, not `36.4`.
- This is *why* the API is full of integer-scaled units: apertures in 1/1000,
  distances in millimetres, temperatures in whole degrees, and the whole APEX96
  scheme. They are not arbitrary — they are what you do when you have no floats.

**`gvfsd-gphoto2` steals the camera.** On a desktop, the moment the camera
enumerates, the GNOME volume monitor claims the PTP session; the camera's screen
goes black and chdkptp reports `ptp_opensession failed 0x2ff`.
`tools/capture.sh` kills it; the proper fix is the udev rule in `tools/udev/`,
which is **written but not yet installed on the workstation** — see ROADMAP.md.

**`rec` errors with "already in rec".** Normal for a camera already in shooting
mode. `capture.sh` tolerates it deliberately.

**Returning to playback can crash some bodies** after a remote shoot. `capture.sh`
deliberately does not issue `play`. Untested whether this body is affected; not
worth finding out.

**Watch the battery.** `get_usb_power()` returned `0` and `get_vbatt()` `3580 mV`
during the demo — the camera runs off the NB-5L, and the USB cable is data only.
The flash brownout recorded in [02-power.md](02-power.md) happened at 69%. Live
view and lens motors are the heavy consumers.

## 11. Is a `canonscope` CLI worth building?

Yes, and the measurements say it can stay simple.

**Connection overhead is not a problem.** Timed on 2026-11-06, three runs of
connect → trivial Lua → quit: **0.66 s, 0.51 s, 0.52 s**. So a CLI that opens a
fresh connection per invocation costs about half a second. That is cheap enough
that **v1 needs no daemon and no persistent session** — which is the design
decision that would otherwise dominate everything.

Two things follow:

- **Batch within one invocation.** Several `-e` flags run in order on a single
  connection, so a verb that reads six values should be *one* Lua call returning
  a formatted string, not six round-trips. The health check in §2 is the pattern.
- **Revisit only for live view.** Streaming frames at any rate is the one
  workload where reconnecting per frame would hurt. `lvdumpimg -count=N` already
  stays inside one connection, so even that is covered until something needs
  continuous streaming.

**Shape.** A single dispatcher with subcommands, consistent with `tools/` as it
stands, and bash + coreutils only per the tooling constraint in CLAUDE.md:

```
canonscope status              # the §2 health read, one connection
canonscope shoot [options]     # today's capture.sh
canonscope preview [-n N]      # live view frames, converted to PNG
canonscope zoom <step|+n|-n>
canonscope focus <mm|auto>
canonscope watch               # motion detection, once §7 is tried
canonscope lua '<code>'        # the escape hatch
```

**The escape hatch matters most.** There are ~200 Lua functions and this CLI will
never wrap more than a dozen. `canonscope lua` keeps the other 190 reachable
without anyone editing the tool, and it is three lines to implement.

**What it should absorb from `capture.sh`.** That script already solved the
non-obvious parts and they should move into shared lib code rather than be
rewritten: the gvfs kill with `pkill -x` and not `-f`, the flash default being
off for power reasons, tolerating `already in rec`, and the human-units-to-APEX96
conversion.

**A separate controller changes where this runs, not what it is.** chdkptp must
run on the host the camera is plugged into. So with a Raspberry Pi (or any
other box) as the controller, `canonscope` runs *there* and a workstation
reaches it over SSH. Worth keeping the verbs free of local-path
assumptions from the start so the same script works both places. chdkptp also has
a networked mode (`connect -h=host -p=port`) if that turns out to be nicer than
SSH — **Untested**, and SSH is the simpler default.
