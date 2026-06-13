#!/usr/bin/env bash
# visual-agent reference runtime - dryRun protocol-boundary smoke.
#
# Asserts that the runtime (L1/L2/L3) produces protocol-conformant output and is target-agnostic,
# without dispatching real UI events, requiring screen-recording permission, or any human action.
#
# Design note (from L1): dryRun click/scroll/screenshot still resolve the target window (which is
# environment-dependent), while keypress/wait are window-independent. The L1/L2 run-plan checks
# therefore use keypress+wait; the click/scroll/screenshot action shapes are covered by L3
# preview-json (preview does not execute).
#
# Usage: bash runtimes/desktop-gui/scripts/smoke.sh
# Success: prints SMOKE_OK, exit 0. Failure: prints failing items, exit non-zero.

set -u

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT" || exit 1

L1="runtimes/desktop-gui/src/action_executor.swift"
L2="runtimes/desktop-gui/src/scene_runner.swift"
L3="runtimes/desktop-gui/src/task_flow.swift"
PROFILE="runtimes/desktop-gui/examples/reference-surface/profile.json"
MANIFEST="runtimes/desktop-gui/examples/reference-surface/manifest.json"

FAILURES=0

fail() {
  echo "SMOKE_FAIL: $1"
  FAILURES=$((FAILURES + 1))
}

# assert_json <description> <json> <node-boolean-expression>
assert_json() {
  local desc="$1"
  local json="$2"
  local expr="$3"
  local result
  result="$(printf '%s' "$json" | node -e '
    const fs = require("fs");
    const raw = fs.readFileSync(0, "utf8").trim();
    let d;
    try { d = JSON.parse(raw); } catch (e) { console.log("PARSE_ERROR:" + e.message); process.exit(0); }
    let ok;
    try { ok = ('"$expr"'); } catch (e) { console.log("EVAL_ERROR:" + e.message); process.exit(0); }
    console.log(ok ? "PASS" : "FAIL");
  ')"
  if [ "$result" != "PASS" ]; then
    fail "$desc ($result)"
  fi
}

# Window-independent dryRun plan: keypress + wait.
PLAN='{"schemaVersion":1,"kind":"action_plan","call_id":"smoke","dryRun":true,"actions":[{"type":"keypress","keys":["ESC"]},{"type":"wait","durationMs":1}]}'

# ---- L1: target-agnostic run-plan ----
L1_OUT="$(VISUAL_APP_BUNDLE_ID="com.example.smoke" VISUAL_APP_OWNER_NAMES="SmokeApp" VISUAL_APP_LABEL="SmokeApp" swift "$L1" run-plan "$PLAN" 2>/dev/null)"
assert_json "L1 kind=action_result" "$L1_OUT" 'd.kind === "action_result"'
assert_json "L1 ok=true" "$L1_OUT" 'd.ok === true'
assert_json "L1 results length=2" "$L1_OUT" 'Array.isArray(d.results) && d.results.length === 2'
assert_json "L1 every result dryRun:true" "$L1_OUT" 'd.results.every(r => r.dryRun === true)'
assert_json "L1 appLabel=SmokeApp (target-agnostic)" "$L1_OUT" 'd.results.every(r => r.appLabel === "SmokeApp")'

# ---- L2: profile-driven run-plan ----
L2_OUT="$(swift "$L2" --profile "$PROFILE" run-plan "$PLAN" 2>/dev/null)"
assert_json "L2 kind=action_result" "$L2_OUT" 'd.kind === "action_result"'
assert_json "L2 ok=true" "$L2_OUT" 'd.ok === true'
assert_json "L2 every result dryRun:true" "$L2_OUT" 'd.results.every(r => r.dryRun === true)'
assert_json "L2 appLabel=PlaceholderApp (from profile)" "$L2_OUT" 'd.results.every(r => r.appLabel === "PlaceholderApp")'

# ---- L3: manifest-driven preview for every intent ----
INTENTS="$(swift "$L3" --manifest "$MANIFEST" intents 2>/dev/null | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(d.intents.join(" "))')"
if [ -z "$INTENTS" ]; then
  fail "L3 intents listing empty"
fi
for intent in $INTENTS; do
  case "$intent" in
    openTarget) inv='{"intent":"openTarget","x":480,"y":120,"dryRun":true}' ;;
    openTargetCapture) inv='{"intent":"openTargetCapture","x":480,"y":120,"output":"out/smoke.png","dryRun":true}' ;;
    captureRegion) inv='{"intent":"captureRegion","x":10,"y":10,"width":300,"height":600,"output":"out/smoke.png","dryRun":true}' ;;
    scrollRegion) inv='{"intent":"scrollRegion","x":480,"y":400,"scrollY":120,"dryRun":true}' ;;
    closeOverlay) inv='{"intent":"closeOverlay","dryRun":true}' ;;
    *) inv="{\"intent\":\"$intent\",\"dryRun\":true}" ;;
  esac
  L3_OUT="$(swift "$L3" --manifest "$MANIFEST" preview-json "$inv" 2>/dev/null)"
  assert_json "L3 $intent kind=action_plan" "$L3_OUT" 'd.kind === "action_plan"'
  assert_json "L3 $intent actions non-empty" "$L3_OUT" 'Array.isArray(d.actions) && d.actions.length > 0'
  assert_json "L3 $intent every action has type" "$L3_OUT" 'd.actions.every(a => typeof a.type === "string" && a.type.length > 0)'
done

# ---- INT section 4: machine-readable error envelope ----
ERR_OUT="$(swift "$L3" --manifest "$MANIFEST" preview-json '{"intent":"openTarget","dryRun":true}' 2>/dev/null)"
assert_json "INT error ok=false" "$ERR_OUT" 'd.ok === false'
assert_json "INT error kind=error" "$ERR_OUT" 'd.kind === "error"'
assert_json "INT error reason=missing_required_field" "$ERR_OUT" 'd.reason === "missing_required_field"'

ERR2_OUT="$(swift "$L3" --manifest "$MANIFEST" preview-json '{"intent":"noSuchIntent","dryRun":true}' 2>/dev/null)"
assert_json "INT error reason=unsupported_intent" "$ERR2_OUT" 'd.reason === "unsupported_intent"'

# ---- INT section 5: session-isolated state via --state ----
S1="out/smoke-state-a.json"
S2="out/smoke-state-b.json"
rm -f "$S1" "$S2"
swift "$L3" --manifest "$MANIFEST" --state "$S1" plan-json '{"intent":"openTarget","x":11,"y":11,"dryRun":true}' >/dev/null 2>&1
swift "$L3" --manifest "$MANIFEST" --state "$S2" plan-json '{"intent":"openTarget","x":99,"y":99,"dryRun":true}' >/dev/null 2>&1
if [ ! -f "$S1" ] || [ ! -f "$S2" ]; then
  fail "INT state files not created"
else
  X1="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(d.intents.openTarget.x)' "$S1" 2>/dev/null)"
  X2="$(node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(d.intents.openTarget.x)' "$S2" 2>/dev/null)"
  if [ "$X1" != "11" ] || [ "$X2" != "99" ]; then
    fail "INT session isolation: states cross-contaminated (a=$X1 b=$X2)"
  fi
fi
rm -f "$S1" "$S2"

# ---- INT section 6: tool-calling schema ----
TS_OUT="$(swift "$L3" --manifest "$MANIFEST" tools-schema 2>/dev/null)"
assert_json "INT tools-schema has tools[]" "$TS_OUT" 'Array.isArray(d.tools) && d.tools.length > 0'
assert_json "INT tools each have name+parameters" "$TS_OUT" 'd.tools.every(t => typeof t.name === "string" && t.parameters && t.parameters.type === "object")'

# ---- INT section 7: capability preflight (read-only) ----
CAP_OUT="$(swift "$L1" capabilities 2>/dev/null)"
assert_json "INT capabilities ok=true" "$CAP_OUT" 'd.ok === true'
assert_json "INT capabilities has screenCapturePermission" "$CAP_OUT" 'typeof d.screenCapturePermission === "boolean"'
assert_json "INT capabilities has activeDisplays" "$CAP_OUT" 'Array.isArray(d.activeDisplays)'
assert_json "INT capabilities has cliclickPath key" "$CAP_OUT" '("cliclickPath" in d)'

# ---- INT section 8: safety-approval gate emits reason=pending_safety_approval ----
# A non-dryRun plan carrying pending_safety_checks without approval must be refused with the
# unified error envelope (reason=pending_safety_approval), which is what the workflow adapter and
# any host branch on. Uses window-independent actions; the gate fires before any action runs.
SAFETY_PLAN='{"schemaVersion":1,"kind":"action_plan","call_id":"smoke_safety","dryRun":false,"pending_safety_checks":[{"id":"c1","code":"confirm","message":"needs approval"}],"actions":[{"type":"keypress","keys":["ESC"]}]}'
SAFE_OUT="$(VISUAL_APP_BUNDLE_ID="com.example.smoke" VISUAL_APP_LABEL="SmokeApp" swift "$L1" run-plan "$SAFETY_PLAN" 2>/dev/null)"
assert_json "INT safety gate ok=false" "$SAFE_OUT" 'd.ok === false'
assert_json "INT safety gate kind=error" "$SAFE_OUT" 'd.kind === "error"'
assert_json "INT safety gate reason=pending_safety_approval" "$SAFE_OUT" 'd.reason === "pending_safety_approval"'

# ---- INT section 9: compiled-binary path (only if bin/ was built) ----
BIN_DIR="runtimes/desktop-gui/bin"
if [ -x "$BIN_DIR/task_flow" ] && [ -x "$BIN_DIR/action_executor" ]; then
  BIN_OUT="$("$BIN_DIR/task_flow" --manifest "$MANIFEST" execute-json '{"intent":"closeOverlay","dryRun":true}' 2>/dev/null)"
  assert_json "INT binary path kind=action_result" "$BIN_OUT" 'd.kind === "action_result"'
  assert_json "INT binary path dryRun result" "$BIN_OUT" 'd.results.every(r => r.dryRun === true)'
fi

if [ "$FAILURES" -ne 0 ]; then
  echo "SMOKE_FAILED: $FAILURES assertion(s) failed"
  exit 1
fi

echo "SMOKE_OK"
