#!/usr/bin/env bash
#
# Tests for tools/canonscope, run against the fake chdkptp in this directory.
#
# No camera needed, and that is the point: the body is 16 years old, often
# simply switched off, and runs on a battery that sags. Parsing, argument
# validation and JSON emission must be testable without it -- the same reason
# make-card.sh is tested against a loopback image rather than a real card.
#
# These cover every branch, including the ones that are supposed to fail.
# make-card.sh once carried a live bug through five test runs because every run
# had used the same mode.
#
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." || exit 1

export CHDKPTP_DIR="tools/tests/fake-chdkptp"
CLI="./tools/canonscope"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()   { printf '  \033[32mok\033[0m   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; fail=$((fail+1)); }

# expect_ok <description> <command...>
expect_ok() {
    local desc=$1; shift
    local out; out="$("$@" 2>&1)"
    if (( $? == 0 )); then ok "$desc"; else bad "$desc" "$out"; fi
}

# expect_fail <description> <command...>  -- the command MUST exit non-zero
expect_fail() {
    local desc=$1; shift
    local out; out="$("$@" 2>&1)"
    if (( $? != 0 )); then ok "$desc"; else bad "$desc" "expected failure, got success: $out"; fi
}

# expect_match <description> <regex> <command...>
expect_match() {
    local desc=$1 re=$2; shift 2
    local out; out="$("$@" 2>&1)"
    if [[ "$out" =~ $re ]]; then ok "$desc"; else bad "$desc" "no match for /$re/ in: $out"; fi
}

echo "canonscope tests (fake chdkptp, no camera)"

echo "-- status"
expect_ok    "status runs"                      $CLI status
expect_match "status reports the CHDK version"  '1\.6\.1'          $CLI status
expect_match "status names the platform"        'sx200is'          $CLI status
expect_match "status converts um to mm"         '5\.0 mm actual'   $CLI status
expect_match "status converts mm to cm"         '67 cm to 1083 cm' $CLI status
expect_match "status warns on a sagging battery" 'charge before'   env FAKE_VBATT=3400 $CLI status

echo "-- json"
expect_ok "status --json is valid JSON" \
    bash -c "$CLI --json status | /usr/bin/python3 -c 'import json,sys; json.load(sys.stdin)'"
expect_match "numbers are emitted unquoted" '"vbatt_mv":3580'  $CLI --json status
expect_match "strings are emitted quoted"   '"chdk":"1\.6\.1"' $CLI --json status

echo "-- capabilities"
expect_match "decodes the capture bitmask"  'JPG RAW DNG-header' $CLI capabilities
expect_match "notes the absence of CRAW"    'no CRAW'            $CLI capabilities
expect_match "decodes the SD-override mask" 'AF AFL MF'          $CLI capabilities

echo "-- preview"
expect_match "single frame is renamed off the literal %04d pattern" \
    'lv-.*-0001\.ppm' $CLI preview --out "$TMP/pv" --format ppm
expect_match "multi-frame numbering works" \
    'lv-.*-0003\.ppm' $CLI preview -n 3 --out "$TMP/pv" --format ppm
expect_fail  "a bad --format is rejected" $CLI preview --format tiff --out "$TMP/pv"
expect_fail  "a non-numeric --count is rejected" $CLI preview -n lots --out "$TMP/pv"

echo "-- zoom"
expect_ok   "absolute step"            $CLI zoom 40
expect_ok   "named position 'tele'"    $CLI zoom tele
expect_ok   "named position 'wide'"    $CLI zoom wide
expect_ok   "relative step"            $CLI zoom +5
expect_fail "step beyond the range"    $CLI zoom 999
expect_fail "non-numeric step"         $CLI zoom banana
expect_fail "no argument at all"       $CLI zoom
expect_match "refuses to drive the motor on a flat battery" \
    'refusing to drive the zoom motor' env FAKE_VBATT=3300 $CLI zoom 10
expect_ok   "CANONSCOPE_FORCE overrides that refusal" \
    env FAKE_VBATT=3300 CANONSCOPE_FORCE=1 $CLI zoom 10

echo "-- focus"
expect_ok   "distance in mm"      $CLI focus 2000
expect_ok   "auto"                $CLI focus auto
expect_fail "units are rejected"  $CLI focus 2m
expect_fail "no argument at all"  $CLI focus

echo "-- lua escape hatch"
expect_match "returns the value"       '126'       $CLI lua 'return get_zoom_steps()'
expect_match "wraps it in json"        '"result"'  $CLI --json lua 'return get_zoom_steps()'
expect_match "warns on a missing return" "no 'return'" $CLI lua 'set_led(9,1)'
expect_fail  "needs some code"         $CLI lua

echo "-- shoot"
expect_match "lands a JPEG at --out" 'shot\.jpg$' $CLI shoot --out "$TMP/shot.jpg"
expect_match "--json reports the path" '"path":"[^"]*/shot2\.jpg"' $CLI --json shoot --out "$TMP/shot2.jpg"
expect_match "defaults to the capture dir" "$TMP/caps/" \
    env CANONSCOPE_CAPTURE_DIR="$TMP/caps" $CLI shoot
: > "$TMP/log"
FAKE_LOG="$TMP/log" $CLI shoot --out "$TMP/shot3.jpg" >/dev/null 2>&1
expect_match "flash is forced off by default" 'set_prop\(143,2\)' cat "$TMP/log"
: > "$TMP/log"
FAKE_LOG="$TMP/log" $CLI shoot --flash keep --out "$TMP/shot4.jpg" >/dev/null 2>&1
expect_fail "--flash keep leaves the flash alone" grep -q set_prop "$TMP/log"
: > "$TMP/log"
FAKE_LOG="$TMP/log" $CLI shoot --tv 1/60 --sv 400 --sd 2m --out "$TMP/shot5.jpg" >/dev/null 2>&1
expect_match "exposure and focus reach remoteshoot" '-tv=1/60 -sv=400 -sd=2m' cat "$TMP/log"
expect_fail "a bad --flash is rejected" $CLI shoot --flash sometimes --out "$TMP/x.jpg"
expect_fail "an unknown option is rejected" $CLI shoot --frobnicate

echo "-- version"
expect_match "--version prints the VERSION file" "^canonscope $(cat VERSION)\$" $CLI --version
expect_match "version --json"  '"version":"' $CLI --json version

echo "-- dispatch and failure"
expect_fail "no verb"                $CLI
expect_fail "unknown verb"           $CLI frobnicate
expect_ok   "help"                   $CLI help
expect_ok   "help after a verb is not swallowed as a verb" $CLI help zoom
expect_match "a camera that is off is reported clearly" \
    'could not connect' env FAKE_CAM_FAIL=1 $CLI status
expect_fail "and exits non-zero"     env FAKE_CAM_FAIL=1 $CLI status

printf '\n%d passed, %d failed\n' "$pass" "$fail"

# The schema test is a separate program because it compares three things --
# the schema, this CLI and the MCP server -- and doing that in bash without
# jq would be worse code for no gain. It has its own pass/fail line.
echo
echo "schema consistency (tools/canonscope.tools.json)"
if command -v python3 >/dev/null 2>&1; then
    python3 "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/test-schema.py" || fail=$((fail+1))
else
    printf '  \033[33mskip\033[0m python3 not found\n'
fi

(( fail == 0 ))
