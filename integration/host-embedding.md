# Runtime Integration - Host Embedding Guide

- Kind: Engineering integration spec (NOT a protocol layer)
- Version: 1
- Status: Normative for integration
- Builds on: the visual-agent L0/L1/L2/L3 contract in `../protocol/` and
  `../runtimes/desktop-gui/src/`
- Section references in code/docs use the prefix `INT section` (for example `INT section 4`)
- Key words convention: see Section 1

## Abstract

This document specifies **runtime integration**: the contract by which an external host invokes the
desktop GUI reference runtime and consumes its results.

Integration is not a new protocol layer and does not add automation capability. It embeds the
existing visual-agent L0/L1/L2/L3 contract:

- L0 qualifies the Operational Surface.
- L1 declares runtime capabilities and returns machine-readable results.
- L2 binds a concrete Surface Manual through profile data.
- L3 expands Scenario Requirements through manifest data.

The Host owns observation interpretation, decision, approval, and task success judgement. The
runtime and adapters expose observe/act/result/fresh-observation boundaries and machine-readable
errors. An adapter is a transport or runtime-backend mapping only: it MUST NOT call models, plan
autonomously, or decide task success.

## 1. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
RFC 2119.

- **Host**: the external system embedding this runtime. The Host may contain a visual model,
  planner, workflow engine, service wrapper, or approval policy. The Host owns decision and task
  success judgement.
- **Runtime entry point**: one of the L1/L2/L3 executables or scripts invoked by the Host.
- **Adapter**: a thin transport or runtime-backend mapping over the runtime entry points.
- **Session**: one Host-scoped unit of work that owns an isolated state file.
- **Desktop GUI reference runtime**: the current `runtimes/desktop-gui/src/` implementation.
  It proves the contract on software windows and is not the whole product boundary.

## 2. Host And Adapter Boundary

- The Host SHALL own observation interpretation, decision, approval, and task success judgement.
- The runtime SHALL execute declared actions, emit JSON, and expose fresh observations or
  verification inputs.
- The runtime MUST NOT decide which task succeeded.
- The runtime MUST NOT call a visual model.
- An adapter MUST NOT call a visual model, plan autonomously, or judge success.
- An adapter SHALL map host transport, workflow, service, or actuator-backend conventions onto the
  declared L0/L1/L2/L3 runtime boundary.
- `ActionResult.ok == true` SHALL mean runtime dispatch/completion only. The Host verifies outcome
  through a fresh observation.

## 3. Invocation Model

A Host SHALL invoke a runtime entry point as a subprocess and exchange JSON:

```yaml
entry_points:
  L1:
    exe: action_executor
    contract: Runtime Capability Manual
    commands: [run-plan, observe, window, screens, diagnose, capabilities, capture-permission, request-capture-permission, schema]
  L2:
    exe: scene_runner
    contract: Surface Manual binding
    flags: ["--profile <file>"]
    delegates_to: L1
  L3:
    exe: task_flow
    contract: Scenario Requirements manifest
    flags: ["--manifest <file>", "--state <path>"]
    commands: [schema, intents, tools-schema, state, preview-json, plan-json, execute-json]
io:
  request: "CLI subcommand + args; JSON payload as an arg, file:<path>, or stdin '-'"
  response: "single JSON object on stdout"
  failure: "error envelope on stdout (Section 4) + human text on stderr + non-zero exit"
```

The current success shapes are defined by the desktop GUI reference runtime:
`action_result`, `action_plan`, `appObservation`, and `verificationObservation`. Integration does
not redefine them.

## 4. Error Envelope

On failure, every runtime entry point SHALL emit a single JSON object on stdout with this shape, in
addition to a human-readable message on stderr and a non-zero exit code:

```yaml
ErrorEnvelope:
  ok: false
  kind: error
  reason: <stable machine-readable code>
  message: <human-readable text>
```

- `reason` SHALL be a stable, lowercase, snake_case code.
- A Host SHALL branch on `reason`, not on `message`.
- The following `reason` codes are RESERVED by integration; an implementation MAY add more but
  SHALL NOT repurpose these:

```yaml
reason_codes:
  # L1 Runtime Capability Manual
  window_not_found: "desktop GUI reference target window could not be resolved"
  screen_capture_permission_required: "screen recording permission is required"
  unobservable_window: "capture not usable for vision; halt and restore observability"
  reserved_action: "a reserved action type was rejected"
  missing_required_field: "a required field was absent"
  pointer_action_unsafe: "event point not on an active display"
  pending_safety_approval: "plan has pending_safety_checks; approval required"
  unsupported_request: "unsupported action/command/argument"
  # L3 Scenario Requirements flow
  unsupported_intent: "intent not declared by the manifest"
  invalid_manifest: "manifest malformed"
  invalid_json: "payload not valid JSON"
  manifest_required: "no manifest provided"
  # L2 Surface Profile / process
  invalid_profile: "surface profile malformed or unreadable"
  l1_executor_missing: "L1 entry point not found"
  l1_spawn_failed: "could not spawn L1 entry point"
  # generic
  usage_error: "argument/usage error"
  internal_error: "unclassified failure"
```

A Host SHALL treat an unrecognized `reason` as a non-retryable error unless it can verify
otherwise.

## 5. Session-Isolated State

L3 persists merged intent inputs. For concurrent embedding:

- L3 SHALL accept an explicit state path. Resolution order, highest precedence first:
  `--state <path>` > `TASK_FLOW_STATE` environment variable > a default global file.
- A Host running concurrent Sessions SHALL pass a unique `--state <path>` per Session so persisted
  inputs never collide.
- `preview-json` SHALL NOT write state.
- `plan-json` and `execute-json` SHALL write to the resolved state path.
- The default path remains for backward compatibility and single-session local use.

## 6. Tool-Calling Schema

To expose Scenario intents to a Host's tool/function-calling interface, L3 SHALL provide a
`tools-schema` command that emits one JSON-Schema tool definition per manifest intent:

```yaml
ToolsSchema:
  schemaVersion: 1
  scene: <current desktop GUI artifact name>
  tools:
    - name: <intentName>
      description: <manifest intent.description, or a default>
      parameters:
        type: object
        properties: { <field>: { type: <json-schema-type> }, ... }
        required: [ <required fields> ]
```

- Property types SHALL be derived from the manifest: an optional per-intent `paramTypes` map
  overrides; otherwise required fields default to `string` and fields present in `defaults` infer
  their type from the default value.
- The manifest MAY add optional `description` and `paramTypes` to an intent; their absence SHALL
  NOT break existing manifests.
- This command performs no model call.
- The Host maps a tool call `{name, arguments}` to
  `task_flow execute-json {intent:name, ...arguments}` through `../adapters/tool-calling/`.

## 7. Capability Preflight

Before orchestrating, a Host SHOULD query runtime prerequisites. L1 SHALL provide a read-only
`capabilities` command that MUST NOT prompt for any permission:

```yaml
Capabilities:
  ok: true
  diagnostic: capabilities
  swiftAvailable: true
  cliclickPath: <path | null>
  screenCapturePermission: <bool>
  activeDisplays: [ { displayID, isMain, x, y, width, height, ... } ]
  # present only when a desktop GUI target is configured via VISUAL_APP_*:
  targetWindowResolved: <bool>
  window: { x, y, width, height, windowID }
  windowOnActiveDisplay: <bool>
```

`request-capture-permission` MAY prompt and SHALL be invoked only with explicit user intent.

## 8. Safety-Approval Round Trip

L1 gates plans carrying `pending_safety_checks`. For Host-mediated approval:

```yaml
approval_loop:
  - "runtime returns an error envelope with reason=pending_safety_approval"
  - "Host surfaces the pending checks to its approver (human or policy)"
  - "on approval, Host re-submits the same plan with confirmationStatus=approved"
  - "on denial, Host does not re-submit; the action is abandoned"
```

A Host MUST NOT auto-approve safety checks without an explicit approver decision.

## 9. Compiled Binary Resolution

To avoid per-call recompilation and a hard dependency on `swift` in PATH:

- A build step MAY compile the desktop GUI reference runtime into executables under
  `runtimes/desktop-gui/bin/` (`action_executor`, `scene_runner`, `task_flow`).
- When an inter-layer call resolves the layer below it, it SHALL prefer an executable at
  the runtime's `bin/<name>` when present and executable, and SHALL otherwise fall back to
  interpreting the sibling `.swift` script.
- The binary path is an optional accelerator, never a requirement.
- The compiled and interpreted paths SHALL produce identical JSON contracts.

## 10. Integration Tiers

Integration is consumed in tiers. Each higher tier reuses the lower ones:

```yaml
tiers:
  T0_core_runtime: "this document + L0/L1/L2/L3 runtime contracts"
  T1_tool_calling: "adapters/tool-calling/ maps one host tool call to one execute-json"
  T2_workflow: "adapters/workflow/ maps one workflow node to preview/execute, retry, approval, --state"
future_notes:
  service_mcp: "docs/future-adapters/mcp-service.md documents a possible long-running service adapter; not the core product"
```

Future service/MCP adapter notes are not implemented adapter tiers. The core product is not an MCP
server.

## 11. Invariants

1. The Host decides and judges task success; the runtime executes declared actions and emits JSON.
2. No model call happens inside the runtime or adapters.
3. Every failure is a machine-readable error envelope with a stable `reason`.
4. Concurrent Sessions use isolated `--state` paths.
5. `capabilities` is read-only and never prompts.
6. Safety approval is always routed to a Host approver; never auto-approved.
7. The compiled binary, when present, is preferred but never required.
8. Integration is not a protocol layer: it changes no L0/L1/L2/L3 contract and does not redefine
   the current desktop GUI manifest/profile wire shapes.
