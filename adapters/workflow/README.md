# Tier 2 - Workflow / DAG Node Adapter

Wraps one L3 Scenario intent as a single workflow/DAG step, engine-agnostic. The Host or
orchestrator owns observation interpretation, decision, approval, and task success judgement. This
adapter only maps a node invocation to the runtime and classifies the runtime result into a node
status. It never calls a model, plans autonomously, or judges task success. See
`../../integration/host-embedding.md` sections 3, 4, 5, 8, and 10.

## Node contract

Input (one JSON object; inline arg or stdin `-`):

```json
{
  "manifest": "<path to scenario manifest>",
  "intent": "<intent name>",
  "args": { "x": 480, "y": 120 },
  "state": "<per-session state path, optional>",
  "dryRun": true,
  "mode": "preview | execute"
}
```

Output (single JSON line on stdout):

```json
{ "ok": true, "status": "done|failed|awaiting_approval", "node": { ... }, "result": { ... } }
```

- `status:"done"` - runtime returned `kind:"action_result"`. **Dispatched, not succeeded.** The
  orchestrator MUST verify via a follow-up observation before treating the task as successful
  (OVERVIEW section 4 `dispatched-not-succeeded`).
- `status:"awaiting_approval"` - runtime reported `reason:"pending_safety_approval"` (INT section 8). The
  engine suspends the node, collects approval, then re-submits with `confirmationStatus=approved`.
- `status:"failed"` - any other error envelope; the engine decides retry/abort by the INT section 4
  `reason` code.

## Orchestration guidance

- **Idempotent preview first**: run `mode:"preview"` (default) to validate the plan without
  touching the UI or persisting state, then `mode:"execute"` to dispatch. (INT section 5: preview never
  persists.)
- **Retry semantics**: a retry MUST be preceded by a fresh observation/verification step; never
  blindly re-execute a dispatched action.
- **Session isolation**: give each concurrent workflow run a unique `state` path. (INT section 5)
- **Preflight**: gate the whole workflow on `action_executor capabilities` once at the start.
  (INT section 7)

## Example (dryRun, placeholder reference scenario)

```bash
node node.mjs '{"manifest":"../../runtimes/desktop-gui/examples/reference-surface/manifest.json","intent":"openTargetCapture","args":{"x":480,"y":120,"output":"out/c.png"},"dryRun":true,"mode":"preview"}'
```

Expected: `{ "ok":true, "status":"done", ... "result": { "kind":"action_plan", ... } }` for
preview, or a `kind:"action_result"` under `mode:"execute"`.

## Runtime resolution

Prefers a compiled `../../runtimes/desktop-gui/bin/task_flow` when present (INT section 9), else
`swift ../../runtimes/desktop-gui/src/task_flow.swift`. Build with
`bash ../../runtimes/desktop-gui/scripts/build.sh`.
