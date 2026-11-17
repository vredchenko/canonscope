import os, json
os.environ["CACTUS_TELEMETRY"] = "0"
from typing import Literal
import cactus

# Hypothesis: the model is bad at scales and unit conversions, but fine at
# picking a named thing. So expose SEMANTIC arguments, never raw device units.

@cactus.tool
def camera_capture_photo(lighting: Literal["normal", "dim", "bright"] = "normal"):
    "Take a photograph with the camera and save it. Use for any request to take, shoot or capture a picture or photo."
    return {}

@cactus.tool
def camera_set_zoom(position: Literal["wide", "middle", "tele"]):
    "Set the camera's optical zoom. 'wide' is fully zoomed out, 'tele' is fully zoomed in, 'middle' is halfway."
    return {}

@cactus.tool
def camera_set_focus(distance_metres: float):
    "Focus the camera manually on a subject at the given distance, in METRES."
    return {}

@cactus.tool
def camera_get_status():
    "Report the camera's health: battery, temperature, free card space, current zoom."
    return {}

@cactus.tool
def camera_preview():
    "Show the camera's live view right now WITHOUT taking a photo. Use for 'what can you see', 'show me the view', 'look through the camera'."
    return {}

QUERIES = [
    "take a photo", "zoom all the way in", "zoom right out",
    "how is the camera doing?", "focus on something two metres away",
    "show me what the camera sees right now", "what can you see?",
    "take a picture, the room is quite dark", "what's the weather in Lagos?",
]

w = os.path.expanduser(os.environ["NEEDLE_WEIGHTS"])
tools = [camera_capture_photo, camera_set_zoom, camera_set_focus, camera_get_status, camera_preview]
with cactus.Cactus(tools=tools, weights=w, stateless=True) as agent:
    for q in QUERIES:
        out = agent.complete(q)
        fc = out.get("function_calls", out) if isinstance(out, dict) else out
        print(f"{q!r:48} -> {json.dumps(fc, default=str)[:120]}")
