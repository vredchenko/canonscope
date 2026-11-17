#!/usr/bin/env python3
"""
Tests for the canonscope MCP server, run against the fake chdkptp.

No camera required, for the same reason tools/tests/run-tests.sh needs none:
the body is 16 years old, frequently switched off, and runs on a battery that
sags. Protocol wiring and error handling must be testable without it.

    build/mcpvenv/bin/python mcp/test-server.py
"""
import asyncio, json, os, sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL = [], []

OK = "\033[32mok\033[0m  "
NO = "\033[31mFAIL\033[0m"


def check(desc, cond, detail=""):
    # Not an f-string: a backslash inside an f-string EXPRESSION is a syntax
    # error before Python 3.12, and this file has to parse wherever it lands.
    (PASS if cond else FAIL).append(desc)
    print("  %s %s" % (OK if cond else NO, desc))
    if not cond and detail:
        print("       %s" % detail)

def _params(**extra):
    env = dict(os.environ)
    env["CHDKPTP_DIR"] = "tools/tests/fake-chdkptp"
    env.update(extra)
    return StdioServerParameters(
        command=sys.executable, args=[str(ROOT / "mcp" / "canonscope_mcp.py")],
        env=env, cwd=str(ROOT))


async def main():
    async with stdio_client(_params()) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()

            print("-- registration")
            tools = {t.name: t for t in (await s.list_tools()).tools}
            check("seven tools by default", len(tools) == 7, f"got {sorted(tools)}")
            for name in ("camera_get_status", "camera_get_capabilities",
                         "camera_capture_photo", "camera_live_view",
                         "camera_set_zoom", "camera_set_focus", "camera_show_image"):
                check(f"{name} exists", name in tools)
            check("the lua escape hatch is OFF by default",
                  "camera_run_lua" not in tools)
            for name, t in tools.items():
                check(f"{name} has a description", bool(t.description and len(t.description) > 60))

            print("-- annotations")
            ann = lambda n: tools[n].annotations.model_dump(exclude_none=True)
            check("status is marked read-only", ann("camera_get_status").get("read_only_hint") is True)
            check("live view is marked read-only", ann("camera_live_view").get("read_only_hint") is True)
            check("capture is not read-only", ann("camera_capture_photo").get("read_only_hint") is False)
            check("show_image is read-only", ann("camera_show_image").get("read_only_hint") is True)

            print("-- calls")
            res = await s.call_tool("camera_get_status", {})
            data = json.loads(res.content[0].text)
            check("status returns parsed JSON", data.get("chdk") == "1.6.1", str(data)[:120])
            check("status carries the battery reading", data.get("vbatt_mv") == 3580)

            res = await s.call_tool("camera_get_capabilities", {})
            data = json.loads(res.content[0].text)
            check("capabilities decodes the capture bitmask", data.get("usb_capture") == 7)

            res = await s.call_tool("camera_set_zoom", {"position": "tele"})
            check("zoom accepts a named position", not res.is_error)

            print("-- errors")
            res = await s.call_tool("camera_set_zoom", {"position": "banana"})
            check("a bad argument is an error", res.is_error)
            check("and the CLI's own diagnostic survives",
                  "must be a number" in res.content[0].text, res.content[0].text[:160])

            res = await s.call_tool("camera_set_zoom", {"position": "999"})
            check("an out-of-range step is rejected", res.is_error)

            res = await s.call_tool("camera_show_image", {"path": "/etc/passwd"})
            check("show_image refuses a path outside captures/", res.is_error,
                  res.content[0].text[:120])

    print("-- with CANONSCOPE_ENABLE_LUA=1")
    async with stdio_client(_params(CANONSCOPE_ENABLE_LUA="1")) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = {t.name: t for t in (await s.list_tools()).tools}
            check("the escape hatch appears when enabled", "camera_run_lua" in tools)
            check("eight tools then", len(tools) == 8, f"got {sorted(tools)}")
            if "camera_run_lua" in tools:
                a = tools["camera_run_lua"].annotations.model_dump(exclude_none=True)
                check("lua is marked destructive", a.get("destructive_hint") is True)
                check("lua is marked open-world", a.get("open_world_hint") is True)
                res = await s.call_tool("camera_run_lua", {"code": "return get_zoom_steps()"})
                check("lua returns a value",
                      json.loads(res.content[0].text).get("result") == 126)

    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    return 1 if FAIL else 0

sys.exit(asyncio.run(main()))
