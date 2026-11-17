---
name: canonscope
description: Use when the user wants Claude to look at something in the physical world through a tethered CHDK camera — "take a photo", "look at the whiteboard", "read this page", "what is the camera pointed at", zoom or focus the camera, or check the camera's battery and status. Covers the canonscope MCP tools and the `canonscope` CLI.
---

# Using the canonscope camera

A Canon PowerShot running CHDK is attached over USB to the machine where the
canonscope MCP server (or the `canonscope` CLI) runs. Photos stream straight
to that machine; nothing is written to the camera's SD card.

## Prefer the MCP tools

| Want | Tool |
| --- | --- |
| Is the camera awake and healthy? | `camera_get_status` |
| What does this body support? (static, cache it) | `camera_get_capabilities` |
| Check framing or poll for change, with no wear | `camera_live_view` |
| A legible photograph | `camera_capture_photo` |
| Zoom | `camera_set_zoom` (`wide`, `tele`, a step, `+n`/`-n`) |
| Focus | `camera_set_focus` (metres; omit for autofocus) |
| See an image when the client cannot read local files | `camera_show_image` |

The capture tools return a **file path**, not pixels. Read that file to see
the image. Use `camera_show_image` only if you cannot read local files.

If the MCP tools are unavailable, the same verbs exist on the CLI, and every
verb takes `--json`:

```sh
canonscope status
canonscope shoot --tv 0.5 --sv 400        # prints the JPEG path last
canonscope preview -n 1 --format png      # live view, no shutter
canonscope zoom tele
canonscope focus 2000                     # millimetres on the CLI
canonscope lua 'return get_temperature(1)' # escape hatch: ~200 CHDK Lua functions
```

## Getting a usable photo

1. **Call `camera_get_status` first.** If it fails, the camera is off, CHDK
   did not boot, or USB is not attached. The camera cannot power itself on,
   so ask the user to switch it on. Don't keep retrying.
2. **Frame with live view** (`camera_live_view`). It is low resolution
   (720×240) but costs no shutter actuation. The shutter on these old bodies
   is irreplaceable, so don't spend actuations on framing checks.
3. **Capture**, then read the file and judge it honestly.
4. **Auto-exposure is the usual failure.** A dim room underexposes, and a
   whiteboard blows out to white. Retry with explicit settings rather than
   capturing again on auto:
   - dim room or paper: `shutter_seconds=0.5`, `iso=400`
   - bright whiteboard: a faster shutter (`0.05`–`0.1`) and `iso=100`
5. For a fixed rig, pass `focus_distance_metres` so focus does not hunt.

## Power and safety

- The **flash is forced off**. Firing it browned out the camera at 69% battery
  and dropped it off USB mid-shot. The pop-up is also mechanical, so it cannot
  be raised remotely anyway.
- If `vbatt_mv` is below ~3500 and `usb_power` is 0, the battery is sagging.
  Avoid lens movement and tell the user. The CLI refuses to zoom below 3400 mV.
  Don't set `CANONSCOPE_FORCE=1` to get around that unless the user asks.
- The Lua escape hatch (`camera_run_lua`, off unless
  `CANONSCOPE_ENABLE_LUA=1`) can reach raw camera memory. Never use
  `peek`, `poke` or `call_event_proc` casually; they can hard-crash the body.
- On-camera Lua has **no floating point**: `3/2 == 1`, and `%f` prints a
  literal `f`. Use integers and `%d`.

## Where files land

Photos and preview frames go to `$CANONSCOPE_CAPTURE_DIR` if it is set.
Otherwise they go to `captures/` in a source checkout, the plugin's data
directory when the server runs from this plugin, or
`~/.local/share/canonscope/captures` for an installed package.
