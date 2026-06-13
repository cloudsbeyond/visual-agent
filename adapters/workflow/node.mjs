#!/usr/bin/env node
// @integration section 10 Integration Tiers (T2 workflow); INT sections 3, 4, 5, and 8.
//
// Tier 2 (workflow node) adapter: a minimal, engine-agnostic node wrapper. It implements the
// node contract from README.md so a DAG/workflow engine can call one Scenario intent as a step.
// It performs NO model call, does not plan autonomously, and does not judge task success. The
// Host/orchestrator owns observation interpretation, decision, approval, and success judgement
// (INT section 2).
//
// Node input (one JSON object, inline arg or stdin '-'):
//   { "manifest": "<path>", "intent": "<name>", "args": { ... },
//     "state": "<path?>", "dryRun": <bool?>, "mode": "preview|execute" }
//
// Node output (stdout, single JSON line):
//   { ok, status, node:{...}, result } where status is done|failed|awaiting_approval.
//   - status=done            : runtime returned a kind:"action_result" (events dispatched)
//   - status=awaiting_approval: runtime reported reason=pending_safety_approval (INT section 8)
//   - status=failed          : any other error envelope (host decides retry per INT section 4 reason)
//
// IMPORTANT (OVERVIEW section 4 dispatched-not-succeeded): status=done means DISPATCHED, not
// SUCCEEDED. The orchestrator must verify via a follow-up observation before treating the task as
// successful.

import { spawnSync } from "node:child_process";
import { readFileSync, accessSync, constants } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const runtimeRoot = path.join(repoRoot, "runtimes", "desktop-gui");

function out(obj) { process.stdout.write(JSON.stringify(obj) + "\n"); }
function fail(reason, message) {
  out({ ok: false, status: "failed", node: { reason }, result: { ok: false, kind: "error", reason, message } });
  process.exit(1);
}

// ---- read node input
const argv = process.argv.slice(2);
let raw = argv.length === 1 ? argv[0] : "-";
if (raw === "-") raw = readFileSync(0, "utf8");
let node;
try { node = JSON.parse(raw); } catch (e) { fail("invalid_json", `node input not valid JSON: ${e.message}`); }
if (!node.manifest) fail("usage_error", "node input requires 'manifest'");
if (!node.intent) fail("usage_error", "node input requires 'intent'");

const mode = node.mode === "execute" ? "execute-json" : "preview-json"; // preview is the safe default
const intentPayload = { intent: node.intent, ...(node.args && typeof node.args === "object" ? node.args : {}) };
if (typeof node.dryRun === "boolean") intentPayload.dryRun = node.dryRun;

// ---- resolve runtime (binary first, then swift script) - INT section 9
const binary = path.join(runtimeRoot, "bin", "task_flow");
const script = path.join(runtimeRoot, "src", "task_flow.swift");
let argvPrefix;
try { accessSync(binary, constants.X_OK); argvPrefix = [binary]; }
catch { argvPrefix = ["swift", script]; }

const cmd = [...argvPrefix, "--manifest", node.manifest];
if (node.state) cmd.push("--state", node.state); // per-session isolation, INT section 5
cmd.push(mode, JSON.stringify(intentPayload));

// ---- run and classify into the node status contract
const res = spawnSync("/usr/bin/env", cmd, { encoding: "utf8" });
if (res.error) fail("l1_spawn_failed", `could not run task_flow: ${res.error.message}`);

let parsed;
try { parsed = JSON.parse((res.stdout || "").trim()); }
catch { fail("internal_error", `runtime did not emit JSON: ${(res.stderr || "").trim()}`); }

if (parsed.ok === false && parsed.kind === "error") {
  // INT section 8: surface pending approval distinctly so the engine can suspend the node.
  if (parsed.reason === "pending_safety_approval") {
    out({ ok: false, status: "awaiting_approval", node: { intent: node.intent, mode }, result: parsed });
    process.exit(0); // not a hard failure; the engine collects approval and re-submits with confirmationStatus=approved
  }
  out({ ok: false, status: "failed", node: { intent: node.intent, mode, reason: parsed.reason }, result: parsed });
  process.exit(1);
}

out({ ok: true, status: "done", node: { intent: node.intent, mode }, result: parsed });
process.exit(0);
