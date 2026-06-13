#!/usr/bin/env node
// @integration section 6 Tool-Calling Schema; INT section 3 Invocation Model.
//
// Tier 1 (tool-calling) adapter: a THIN transport mapping. It translates ONE host tool call
// { name, arguments } into a single `task_flow execute-json` invocation and passes the runtime's
// JSON (success or the INT section 4 error envelope) straight back to stdout. It makes NO model
// call, does not choose tools, and does not judge task success. The Host owns observation
// interpretation, decision, approval, and success judgement (INT section 2).
//
// Usage:
//   node invoke.mjs --manifest <manifest.json> [--state <path>] '<toolCallJSON>'
//   echo '<toolCallJSON>' | node invoke.mjs --manifest <manifest.json> [--state <path>] -
//
// toolCallJSON shape (host-agnostic): { "name": "<scenarioIntent>", "arguments": { ... } }
// The adapter merges it into { intent:name, ...arguments } and runs execute-json.
//
// Runtime resolution: prefers runtimes/desktop-gui/bin/task_flow (INT section 9), else `swift`
// on runtimes/desktop-gui/src/task_flow.swift.

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, accessSync, constants } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..");
const runtimeRoot = path.join(repoRoot, "runtimes", "desktop-gui");

function emitErrorAndExit(reason, message) {
  // Mirror the INT section 4 error envelope so hosts get one consistent failure shape.
  process.stdout.write(JSON.stringify({ ok: false, kind: "error", reason, message }) + "\n");
  process.exit(1);
}

// ---- parse args: --manifest <f> [--state <p>] <toolCallJSON|->
const argv = process.argv.slice(2);
let manifest;
let state;
const rest = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--manifest") { manifest = argv[++i]; }
  else if (argv[i] === "--state") { state = argv[++i]; }
  else { rest.push(argv[i]); }
}
if (!manifest) emitErrorAndExit("usage_error", "missing --manifest <file>");
if (rest.length !== 1) emitErrorAndExit("usage_error", "expected exactly one tool-call JSON arg (or '-')");

// ---- read tool call (inline or stdin)
let raw = rest[0];
if (raw === "-") raw = readFileSync(0, "utf8");
let call;
try { call = JSON.parse(raw); } catch (e) { emitErrorAndExit("invalid_json", `tool call not valid JSON: ${e.message}`); }
if (!call || typeof call.name !== "string" || call.name.length === 0) {
  emitErrorAndExit("usage_error", "tool call must have a string 'name'");
}

// ---- map { name, arguments } -> { intent:name, ...arguments }
const intentPayload = { intent: call.name, ...(call.arguments && typeof call.arguments === "object" ? call.arguments : {}) };

// ---- resolve runtime invocation (binary first, then swift script) - INT section 9
const binary = path.join(runtimeRoot, "bin", "task_flow");
const script = path.join(runtimeRoot, "src", "task_flow.swift");
let argvPrefix;
try { accessSync(binary, constants.X_OK); argvPrefix = [binary]; }
catch { argvPrefix = ["swift", script]; }

const cmd = [...argvPrefix, "--manifest", manifest];
if (state) cmd.push("--state", state);
cmd.push("execute-json", JSON.stringify(intentPayload));

// ---- run; pass runtime stdout/stderr/exit straight through
const result = spawnSync("/usr/bin/env", cmd, { encoding: "utf8" });
if (result.error) emitErrorAndExit("l1_spawn_failed", `could not run task_flow: ${result.error.message}`);
if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
process.exit(result.status ?? 0);
