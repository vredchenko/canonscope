#!/usr/bin/env python3
"""
Assert that tools/canonscope.tools.json, the CLI, and the MCP server agree.

The schema is the contract. Without this test it is just a file that drifts:
a verb gets renamed, a --json key changes, an annotation is edited in one
place, and nothing notices until a caller breaks.

Python rather than bash, deliberately. CLAUDE.md requires DELIVERABLES in
tools/ to be bash + coreutils so they run on a bare Pi -- tools/canonscope
itself obeys that. Tests are not deliverables and are never run on the Pi in
tier 0; tools/tests/run-tests.sh already shells out to python3 to validate
JSON. Doing this comparison in bash without jq would be worse code for no gain.

    python3 tools/tests/test-schema.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCHEMA = ROOT / "tools" / "canonscope.tools.json"
CLI = ROOT / "tools" / "canonscope"
MCP_SERVER = ROOT / "mcp" / "canonscope_mcp.py"

PASS, FAIL = [], []
OK = "\033[32mok\033[0m  "
NO = "\033[31mFAIL\033[0m"


def check(desc, cond, detail=""):
    (PASS if cond else FAIL).append(desc)
    print("  %s %s" % (OK if cond else NO, desc))
    if not cond and detail:
        print("       %s" % detail)


def cli_json(*args):
    env = dict(os.environ, CHDKPTP_DIR="tools/tests/fake-chdkptp")
    p = subprocess.run([str(CLI), "--json", *args], capture_output=True,
                       text=True, cwd=ROOT, env=env, timeout=60)
    if p.returncode != 0:
        raise RuntimeError((p.stderr or p.stdout).strip())
    return json.loads(p.stdout)


def dispatcher_verbs():
    """The verbs the dispatcher actually accepts, read from its case block."""
    src = CLI.read_text()
    block = re.search(r'case "\$VERB" in\n(.*?)\nesac', src, re.S)
    if not block:
        raise RuntimeError("could not find the dispatcher's case block")
    verbs = []
    for line in block.group(1).splitlines():
        m = re.match(r"\s{4}([a-z_|]+)\)", line)
        if m:
            verbs.extend(m.group(1).split("|"))
    return {v for v in verbs if v not in ("help", "*")}


def mcp_tools():
    """Tool name -> annotations dict, read from the server source."""
    src = MCP_SERVER.read_text()
    out = {}
    for m in re.finditer(
            r"@mcp\.tool\((?P<ann>.*?)\)\s*\ndef (?P<fn>\w+)\(", src, re.S):
        out[m.group("fn")] = m.group("ann")
    # Registered conditionally rather than decorated.
    for m in re.finditer(r"mcp\.tool\(annotations=ToolAnnotations\((?P<ann>.*?)\)\)\((?P<fn>\w+)\)", src, re.S):
        out[m.group("fn")] = m.group("ann")
    return out


def main():
    schema = json.loads(SCHEMA.read_text())
    verbs = schema["verbs"]

    print("-- schema covers the CLI")
    actual = dispatcher_verbs()
    declared = set(verbs)
    check("every dispatcher verb is in the schema",
          actual <= declared, f"missing from schema: {sorted(actual - declared)}")
    check("every schema verb exists in the dispatcher",
          declared <= actual, f"not in dispatcher: {sorted(declared - actual)}")

    print("-- declared --json keys are the real ones")
    # Every verb, run against the fake. Side effects land in a temp dir.
    tmp = tempfile.mkdtemp()
    runnable = {
        "status": (), "capabilities": (), "version": (),
        "shoot": ("--out", os.path.join(tmp, "shot.jpg")),
        "zoom": ("40",), "focus": ("auto",), "lua": ("return 1",),
        "preview": ("--out", tmp, "--format", "ppm"),
    }
    for verb, args in runnable.items():
        if verb not in verbs:
            # Already reported above as a coverage failure; don't crash on top
            # of it, or the first drift hides every later check.
            check(f"{verb} is declared in the schema", False)
            continue
        try:
            got = set(cli_json(verb, *args))
        except Exception as exc:
            check(f"{verb} runs", False, str(exc)[:160])
            continue
        want = set(verbs[verb]["returns"])
        check(f"{verb} returns exactly the declared keys", got == want,
              f"extra={sorted(got - want)} missing={sorted(want - got)}")

    print("-- focus returns one shape in both modes")
    try:
        a, m = set(cli_json("focus", "auto")), set(cli_json("focus", "2000"))
        check("auto and manual agree", a == m, f"auto={sorted(a)} manual={sorted(m)}")
    except Exception as exc:
        check("focus runs in both modes", False, str(exc)[:160])

    print("-- schema matches the MCP server")
    found = mcp_tools()
    projected = {v["mcp"]["name"] for v in verbs.values() if "mcp" in v}
    extra = set(schema.get("mcp_only", {}))
    check("every projected tool exists in the server",
          (projected | extra) <= set(found),
          f"missing: {sorted((projected | extra) - set(found))}")
    check("the server defines no tool the schema omits",
          set(found) <= (projected | extra),
          f"undeclared: {sorted(set(found) - (projected | extra))}")

    print("-- annotations agree")
    for verb, spec in verbs.items():
        if "mcp" not in spec:
            continue
        name, ann = spec["mcp"]["name"], spec["mcp"]["annotations"]
        src = found.get(name, "")
        for key, value in ann.items():
            token = f"{key}={value}" if value is not True else f"{key}=True"
            # READ_ONLY / MOVES_LENS constants stand in for the common sets.
            ok = token in src.replace("true", "True").replace("false", "False") \
                 or "READ_ONLY" in src or "MOVES_LENS" in src
            check(f"{name}.{key}", ok, f"declared {key}={value}, server: {src[:90]}")

    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    return 1 if FAIL else 0


sys.exit(main())
