# Remote control

## Why CHDK is required

Canon dropped PowerShot remote capture around this generation, so the stock
firmware gives you nothing usable. All programmatic control here goes through
CHDK's PTP extension.

That extension doesn't alter the standard PTP operations — it adds
CHDK-specific ones alongside them, which is why ordinary PTP tools can't see it
and a dedicated client is needed. It is available **over USB on every
CHDK-supported camera** (and over PTP/IP on models with Wi-Fi hardware, which
the SX200 IS does not have).

## chdkptp

[`chdkptp`](https://chdk.fandom.com/wiki/PTP_Extension) is the client: shoot,
change settings, run Lua on the camera, download files, and get a rough live
view. It has a CLI, a GUI and a Lua API — the GUI and CLI are themselves written
in Lua, so it extends easily.

`libgphoto2` has only *partial* CHDK support; `chdkptp` is the one to use.

Command-line form, chaining commands with `-e`:

```sh
chdkptp -c -erec -eshoot -eplay -eimdl    # connect, rec mode, shoot, play mode, download
```

Quoting is a genuine nuisance: `chdkptp` has its own quoting rules *and* the
shell's apply on top. Paths with spaces must be quoted to `chdkptp`, and that
quoting then needs protecting from the shell:

```sh
chdkptp -c -e"remoteshoot -dng '<path>'"
```

`$` and `!` are significant to common Linux shells; the wiki recommends `exec`
over `!` for command-line use. Forward slashes work as separators on all
platforms. Camera-side paths need the full path starting with a capital `A`,
e.g. `download A/DCIM/100CANON/IMG_1234.jpg test.jpg`.

## Remote capture: supported on this camera

**Confirmed from source.** `platform/sx200is/platform_camera.h` defines:

```c
#define CAM_HAS_FILEWRITETASK_HOOK      1
```

and `core/camera_info.c` builds the supported-target bitmask as:

```c
#ifdef CAM_HAS_FILEWRITETASK_HOOK
    PTP_CHDK_CAPTURE_JPG |
#ifdef CAM_HAS_CANON_RAW
    PTP_CHDK_CAPTURE_CRAW |
#endif
#endif
    (PTP_CHDK_CAPTURE_RAW | PTP_CHDK_CAPTURE_DNGHDR),   // target_support
```

So on the SX200 IS:

| Target | Supported | Why |
| --- | --- | --- |
| JPG | yes | gated on `CAM_HAS_FILEWRITETASK_HOOK`, which is set |
| RAW | yes | unconditional |
| DNG header | yes | unconditional |
| CRAW | no | `CAM_HAS_CANON_RAW` is not defined — expected on a compact |

This means `remoteshoot -jpg` / `-dng` / `-raw` **stream straight to the host
with nothing written to the SD card**, which is exactly what the rig wants and
retires the SD-multiplexer and Wi-Fi-SD options in
[03-storage-and-chdk.md](03-storage-and-chdk.md).

The SX200 IS also does **not** define `CAM_FILEWRITETASK_MULTIPASS`, so the
`shooting_get_drive_mode() != 0` bail-out in `remotecap_set_target()` — which
restricts some cameras to a single drive mode during remote capture — does not
apply here.

Confirm on the actual body once CHDK is running:

```sh
chdkptp -c -e"luar return get_usb_capture_support()"
```

A non-zero bitmask means supported. The matching Lua calls are
`init_usb_capture(bitmask[, startline, numlines])`,
`get_usb_capture_target()` and `set_usb_capture_timeout()`.

*Verified 2026-10-30 against the CHDK source trunk
([01luna/CHDK](https://github.com/01luna/CHDK)): `platform/sx200is/platform_camera.h`,
`core/camera_info.c:255-261`, `core/remotecap.c`, `modules/luascript.c`.*

## Known PTP failure modes

From the wiki's troubleshooting section:

- **Camera crashes after remote shooting when switching back to play mode.** A
  known issue on some cameras. Use `remoteshoot -filedummy` to avoid it.
- **Switching to rec mode fails and the screen goes black on plugging in USB.**
  Usually caused by default Linux software grabbing the camera on connect —
  disable or mask whatever auto-mounts PTP devices (gvfs-gphoto2 and friends).
  `chdkptp`'s `unlock` command, or a LogicalEvent, recovers it: DryOS uses
  `post_levent_to_ui(4482)`; `4484` unlocks the keyboard. As of CHDK 1.6 build
  5815, `switch_mode_usb` sends this automatically when needed. On some cameras
  a subsequent rec switch still fails with the lens extending and the camera
  returning to play — a shutter half-press completes the switch.
- **Transfer fails with code `0x2ff`, or the camera crashes on transfer.**
  Usually a wrong camera-side path: use the full path starting with capital `A`.

## Simpler alternative: USB remote

Applying **5 V to the USB port acts as a shutter press** — a Pi GPIO pin plus a
transistor is enough. No PTP, no client, just a trigger. Useful as a fallback or
for a pure intervalometer rig.

Two conveniences on this camera:

- `REMOTE_SYNC_STATUS_LED 0xC0220138` — the blue Print-button LED lights while
  the camera waits for USB remote sync. A free trigger-debugging indicator that
  needs no screen.
- `CAM_REMOTE_AtoD_CHANNEL 5` — the **3rd battery terminal** can also serve as a
  remote input, not just the USB port. This collides with the dummy-battery
  design; see the trade-off note in [02-power.md](02-power.md).

*Verified 2026-10-30 against `platform/sx200is/platform_camera.h`.*

## Rig notes

```
Pi (chdkptp) --USB--> SX200 IS (CHDK autoboot from locked card)
                          ^
                          +-- dummy battery <- separate 5 V supply
```

- **Autoboot CHDK** from a bootable card with the write-protect tab locked
  ([03-storage-and-chdk.md](03-storage-and-chdk.md)).
- **The camera cannot power itself on.** Press the power button once and disable
  auto-power-off, or wire a relay / optocoupler across the power button (a servo
  also works). Note the camera **starts in Playback mode** — half-press the
  shutter to reach Record, or hold Power ~2 s to boot straight into Record.
- **Don't power the camera from the Pi's 5 V rail** — lens and flash spikes will
  brown out the Pi.
- The battery door has a rubber flap for the coupler cable.
