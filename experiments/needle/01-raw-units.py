import os, json
os.environ["CACTUS_TELEMETRY"] = "0"
import cactus

CALLS = []

@cactus.tool
def camera_capture_photo(shutter_seconds: float = 0.0, iso: int = 0):
    "Take a photograph with the camera and save it to this computer. Use for any request to take, shoot or capture a picture or photo."
    CALLS.append(("capture", shutter_seconds, iso)); return {"ok": True}

@cactus.tool
def camera_set_zoom(step: int):
    "Set the camera's optical zoom to a discrete step from 0 (widest) to 125 (most telephoto)."
    CALLS.append(("zoom", step)); return {"ok": True}

@cactus.tool
def camera_set_focus(distance_mm: int):
    "Focus the camera manually at a subject distance given in millimetres."
    CALLS.append(("focus", distance_mm)); return {"ok": True}

@cactus.tool
def camera_get_status():
    "Report the camera's health: battery voltage, temperature, free card space and current zoom."
    CALLS.append(("status",)); return {"ok": True}

@cactus.tool
def camera_preview(frames: int = 1):
    "Grab live-view frames from the camera without taking a photo or using the shutter."
    CALLS.append(("preview", frames)); return {"ok": True}

QUERIES = [
    "take a photo",
    "zoom all the way in",
    "how is the camera doing?",
    "focus on something two metres away",
    "show me what the camera sees right now",
    "what's the weather in Lagos?",          # should match nothing
]

w = os.path.expanduser(os.environ["NEEDLE_WEIGHTS"])
with cactus.Cactus(tools=[camera_capture_photo, camera_set_zoom, camera_set_focus,
                          camera_get_status, camera_preview], weights=w, stateless=True) as agent:
    for q in QUERIES:
        CALLS.clear()
        try:
            out = agent.complete(q)
            fc = out.get("function_calls", out) if isinstance(out, dict) else out
            print(f"{q!r:52} -> {json.dumps(fc, default=str)[:140]}")
        except Exception as e:
            print(f"{q!r:52} -> ERROR {type(e).__name__}: {e}")
