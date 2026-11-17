import os, json
os.environ["CACTUS_TELEMETRY"] = "0"
import cactus

# Third hypothesis: give each INTENT its own zero-argument verb, use Needle 3's
# regex `triggers` to gate them, and rename the status tool so it stops
# absorbing "what can you see" queries.

@cactus.tool(triggers=[r"\b(photo|photograph|picture|shoot|capture|snap)\b"])
def camera_capture_photo():
    "Take a photograph and save it."
    return {}

@cactus.tool(triggers=[r"\bzoom\b.*\b(in|closer|tele)\b", r"\bzoom in\b"])
def camera_zoom_in():
    "Zoom the camera lens all the way in, to maximum telephoto."
    return {}

@cactus.tool(triggers=[r"\bzoom\b.*\b(out|back|wide)\b", r"\bwide\b"])
def camera_zoom_out():
    "Zoom the camera lens all the way out, to the widest view."
    return {}

@cactus.tool
def camera_focus_at(distance_metres: float):
    "Focus on a subject at the given distance, in METRES."
    return {}

@cactus.tool(triggers=[r"\b(battery|health|temperature|how is|status)\b"])
def camera_check_health():
    "Report battery voltage, temperature and free card space."
    return {}

@cactus.tool(triggers=[r"\b(see|view|looking|look|live)\b"])
def camera_show_live_view():
    "Show the live view through the lens right now, without taking a photo."
    return {}

QUERIES = ["take a photo", "zoom all the way in", "zoom right out",
           "how is the camera doing?", "what's the battery like?",
           "focus on something two metres away",
           "show me what the camera sees right now", "what can you see?",
           "what's the weather in Lagos?"]

w = os.path.expanduser(os.environ["NEEDLE_WEIGHTS"])
tools = [camera_capture_photo, camera_zoom_in, camera_zoom_out,
         camera_focus_at, camera_check_health, camera_show_live_view]
with cactus.Cactus(tools=tools, weights=w, stateless=True) as agent:
    for q in QUERIES:
        out = agent.complete(q)
        fc = out.get("function_calls", out) if isinstance(out, dict) else out
        print(f"{q!r:48} -> {json.dumps(fc, default=str)[:110]}")
