#!/usr/bin/env python3
"""
An MCP server exposing the camera to Claude Code and other MCP clients.

It is a THIN WRAPPER over tools/canonscope. Every tool here shells out to that
CLI and parses its --json output; none of them talk to chdkptp directly. That
is deliberate:

  * The CLI is tier 0 -- bash and coreutils, runs on a bare Pi. This server is
    tier 1, and tier 1 must never become a dependency of tier 0. Wrapping keeps
    the arrow pointing one way.
  * The 0.5 s cost of a camera round trip is dominated by chdkptp process
    startup, which a deeper Python binding would not avoid unless it
    reimplemented PTP. There is nothing to win by binding below the CLI.
  * One contract. Anything else that drives the camera binds to the same
    verbs, so behaviour cannot drift between front doors.

Verified 2026-11-06 against mcp 2.3.0 on CPython 3.13.

Run:  mcp/run-server.sh          (finds or provisions a Python with the SDK)
Register with Claude Code: install the canonscope plugin, or
      claude mcp add --scope project canonscope -- mcp/run-server.sh
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Annotated, Any

from mcp.server import MCPServer
from mcp.server.mcpserver import Image
from mcp.server.mcpserver.exceptions import ToolError
from mcp.types import ToolAnnotations
from pydantic import Field

REPO_ROOT = Path(__file__).resolve().parent.parent


def _find_cli() -> str:
    """$CANONSCOPE_CLI, else the CLI beside this file, else `canonscope` on PATH."""
    if os.environ.get("CANONSCOPE_CLI"):
        return os.environ["CANONSCOPE_CLI"]
    bundled = REPO_ROOT / "tools" / "canonscope"
    if bundled.is_file():
        return str(bundled)
    return shutil.which("canonscope") or str(bundled)


def _capture_dir() -> Path:
    """Mirror of CAPTURE_DIR in tools/lib/common.sh -- keep the two in step."""
    if os.environ.get("CANONSCOPE_CAPTURE_DIR"):
        return Path(os.environ["CANONSCOPE_CAPTURE_DIR"]).expanduser()
    cli_root = Path(CLI).resolve().parent.parent
    if os.environ.get("CANONSCOPE_DATA"):
        data = Path(os.environ["CANONSCOPE_DATA"]).expanduser()
    elif (cli_root / ".git").exists():
        data = cli_root
    else:
        xdg = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
        data = Path(xdg) / "canonscope"
    return data / "captures"


CLI = _find_cli()
TIMEOUT = int(os.environ.get("CANONSCOPE_TIMEOUT", "120"))

mcp = MCPServer("canonscope")


class CameraError(ToolError):
    """The CLI failed. The message is the CLI's own stderr, unedited.

    Subclasses ToolError rather than RuntimeError deliberately: the SDK
    surfaces a ToolError's message to the caller, but replaces any other
    exception with a generic "raised an unexpected exception". The CLI knows
    the difference between "camera is switched off" and "that is not a valid
    zoom step", and that distinction is exactly what the caller needs.
    """


def _run(*args: str) -> dict[str, Any]:
    """Call the CLI with --json and return the parsed object."""
    if not os.access(CLI, os.X_OK):
        raise CameraError(f"canonscope CLI not found or not executable at {CLI}")
    proc = subprocess.run(
        [CLI, "--json", *args],
        capture_output=True, text=True, timeout=TIMEOUT, cwd=REPO_ROOT,
    )
    if proc.returncode != 0:
        # The CLI's diagnostics are better than anything we could synthesise:
        # it knows the difference between "camera off" and "bad argument".
        raise CameraError((proc.stderr or proc.stdout).strip() or
                          f"canonscope {' '.join(args)} failed ({proc.returncode})")
    out = proc.stdout.strip()
    try:
        return json.loads(out)
    except json.JSONDecodeError as exc:
        raise CameraError(f"could not parse CLI output as JSON: {out[:400]}") from exc


READ_ONLY = ToolAnnotations(readOnlyHint=True, destructiveHint=False, idempotentHint=True)
MOVES_LENS = ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=True)


@mcp.tool(annotations=READ_ONLY)
def camera_get_status() -> dict[str, Any]:
    """Report the camera's current state in a single round trip.

    Returns battery voltage in millivolts, whether it is running on USB power,
    the three temperature sensors in Celsius, free card space, lifetime shutter
    actuations, current zoom step, lens focal length, depth of field, and the
    current exposure triplet in CHDK's APEX96 units.

    Call this before a session to confirm the camera is awake and healthy. A
    vbatt_mv below about 3500 with usb_power 0 means the battery is sagging and
    lens movement may brown the camera out.
    """
    return _run("status")


@mcp.tool(annotations=READ_ONLY)
def camera_get_capabilities() -> dict[str, Any]:
    """Report what this camera body supports. These facts never change, so the
    result may be cached for the life of a session.

    Covers which tethered capture formats work, whether subject-distance
    override is available in each focus mode, the number of zoom steps, RAW
    support, presence of an ND filter, and whether video can be driven
    remotely (on this body it cannot).
    """
    return _run("capabilities")


@mcp.tool(annotations=ToolAnnotations(readOnlyHint=False, destructiveHint=False, idempotentHint=False))
def camera_capture_photo(
    shutter_seconds: Annotated[float | None, Field(
        default=None, gt=0, le=64,
        description="Shutter speed in seconds, e.g. 0.5. Omit for automatic.")] = None,
    iso: Annotated[int | None, Field(
        default=None, ge=50, le=3200,
        description="ISO sensitivity, Canon 'real' value. Omit for automatic.")] = None,
    focus_distance_metres: Annotated[float | None, Field(
        default=None, gt=0,
        description="Fix focus at this distance in METRES. Omit for autofocus.")] = None,
) -> dict[str, Any]:
    """Take a photograph and save it to this computer, returning the file path.

    Nothing is written to the camera's SD card -- the image streams over USB.
    The flash is forced OFF: firing it draws enough current to brown this body
    out, and the pop-up is mechanical and cannot be raised remotely anyway.

    IMPORTANT: this returns a PATH, not the image itself. Read the file at that
    path to actually see the photograph. That is deliberate -- inlining a 4000x3000
    JPEG as base64 is extremely token-expensive.

    Automatic exposure is the usual failure: a dim room underexposes badly and a
    whiteboard blows out to white. If a photograph comes back unusable, retry
    with explicit shutter_seconds and iso rather than hoping.
    """
    args: list[str] = ["shoot"]
    if shutter_seconds is not None:
        args += ["--tv", str(shutter_seconds)]
    if iso is not None:
        args += ["--sv", str(int(iso))]
    if focus_distance_metres is not None:
        # capture.sh documents --sd in the "2m" form, which is also what
        # chdkptp's own remoteshoot accepts. Metres are what a caller thinks
        # in, so no conversion is needed -- just the unit suffix.
        args += ["--sd", f"{focus_distance_metres:g}m"]
    return _run(*args)


@mcp.tool(annotations=READ_ONLY)
def camera_live_view(
    frames: Annotated[int, Field(
        default=1, ge=1, le=30,
        description="How many consecutive viewfinder frames to grab.")] = 1,
) -> dict[str, Any]:
    """Grab frames from the camera's live viewfinder WITHOUT taking a photograph.

    No shutter actuation, no card write, and no mechanical wear -- on a body
    whose shutter is irreplaceable this is the right way to check what the
    camera is pointed at, or to poll whether anything has changed.

    Frames are much lower resolution than a photograph (720x240) and are
    returned as file paths. Use this to check framing; use camera_capture_photo
    when the image actually needs to be legible.
    """
    return _run("preview", "-n", str(frames))


@mcp.tool(annotations=MOVES_LENS)
def camera_set_zoom(
    position: Annotated[str, Field(
        description="A zoom step number from 0 to 125, or one of the names "
                    "'wide' (fully out) or 'tele' (fully in). Relative moves "
                    "are written '+5' or '-5'.")],
) -> dict[str, Any]:
    """Move the optical zoom and report where it ended up.

    The lens has 126 discrete, repeatable steps, so a given step number is a
    reproducible framing worth recording.

    This drives a physical motor -- the heaviest intermittent current draw on
    the body. The CLI refuses to move it below 3400 mV on battery power, and
    that refusal surfaces here as an error. Charge rather than overriding it.
    """
    return _run("zoom", position)


@mcp.tool(annotations=MOVES_LENS)
def camera_set_focus(
    distance_metres: Annotated[float | None, Field(
        default=None, gt=0, le=100,
        description="Subject distance in METRES. Omit to return to autofocus.")] = None,
) -> dict[str, Any]:
    """Focus the lens at a fixed distance, or hand focus back to the camera.

    Subject-distance override works in all three focus modes on this body,
    which is unusual -- so for a fixed rig the camera-to-subject distance can be
    a configured constant rather than a per-shot gamble.

    Call with no argument to restore autofocus.
    """
    if distance_metres is None:
        return _run("focus", "auto")
    return _run("focus", str(int(round(distance_metres * 1000))))


# The escape hatch is OFF by default, and that is a considered decision rather
# than timidity. In Claude Code the Bash tool already reaches
# `canonscope lua '...'` behind a visible permission prompt, so exposing it
# again here adds risk without adding capability. It exists for MCP clients
# that have no shell, and for those it is opt-in:
#     CANONSCOPE_ENABLE_LUA=1
ENABLE_LUA = os.environ.get("CANONSCOPE_ENABLE_LUA", "0") == "1"


def camera_run_lua(
    code: Annotated[str, Field(
        description="Lua source to run on the camera. Must include a 'return' "
                    "to hand a value back, e.g. \"return get_temperature(1)\".")],
) -> dict[str, Any]:
    """Run arbitrary Lua on the camera and return the result. THE ESCAPE HATCH.

    CHDK exposes roughly 200 Lua functions and the tools above wrap a handful;
    this reaches the rest -- sensors, exposure in APEX96, motion detection,
    drawing on the camera's own screen, raw memory access.

    Two warnings. The on-camera Lua interpreter has NO FLOATING POINT: 3/2 is 1,
    and string.format("%f") silently emits a literal "f" rather than erroring,
    so use %d and integer-scaled units. And peek/poke/call_event_proc reach
    arbitrary camera memory and will hard-crash a 16-year-old irreplaceable
    body -- do not use them casually.
    """
    return _run("lua", code)


if ENABLE_LUA:
    mcp.tool(annotations=ToolAnnotations(
        readOnlyHint=False, destructiveHint=True, openWorldHint=True))(camera_run_lua)


@mcp.tool(annotations=READ_ONLY)
def camera_show_image(
    path: Annotated[str, Field(
        description="Path to an image previously returned by camera_capture_photo "
                    "or camera_live_view.")],
) -> Image:
    """Return a previously captured image so it can actually be looked at.

    The capture tools return PATHS, not pixels, because inlining a 4000x3000
    JPEG costs an enormous number of tokens and there are open reports of image
    blocks arriving at a model as raw base64 text rather than as something it
    can see. This tool makes looking at the picture a separate, deliberate act.

    If the client can read local files directly, prefer that over this tool.
    """
    target = Path(path).expanduser()
    if not target.is_absolute():
        target = _capture_dir() / target
    try:
        target = target.resolve(strict=True)
    except OSError as exc:
        raise CameraError(f"no such image: {path}") from exc
    # Only hand back things this rig produced. The server is local and
    # single-user, but a tool that returns the bytes of any path it is given is
    # a worse thing to leave lying around than one that does not.
    allowed = _capture_dir().resolve()
    if not target.is_relative_to(allowed):
        raise CameraError(
            f"refusing to read outside {allowed} -- got {target}")
    suffix = target.suffix.lower().lstrip(".")
    return Image(path=str(target), format="jpeg" if suffix in ("jpg", "jpeg") else suffix)


if __name__ == "__main__":
    if not shutil.which("bash"):
        raise SystemExit("bash is required")
    mcp.run()
