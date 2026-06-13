# Future Adapter Note - MCP / Service Adapter

> Scope: **future adapter note only.** This document sketches a possible service adapter over the
> visual-agent reference runtime. No server implementation is included. It is documented so it can
> be built later by reusing the current runtime and adapter contracts with no change to the
> L0/L1/L2/L3 contract. See `../../integration/host-embedding.md` section 10.

## Why a service

Tiers 1-2 spawn a subprocess per call. A long-running service amortizes startup and, when built on
the compiled binaries (`bash ../../runtimes/desktop-gui/scripts/build.sh`, INT section 9), avoids per-call recompilation
entirely. It gives MCP-style hosts one persistent connection instead of many process spawns.

This does not turn visual-agent into an MCP-server product. The service remains an adapter around
the protocol and runtime boundary.

## Reuse map (no new capability)

```yaml
mcp_adapter_reuses:
  list_tools:    "task_flow tools-schema  -> MCP tools list (one tool per intent)"   # INT section 6
  call_tool:     "task_flow execute-json  -> map { name, arguments } like adapters/tool-calling"  # INT section 3
  preview_tool:  "task_flow preview-json  -> dry validation, no UI, no state write"  # INT section 5
  read_resource: "action_executor capabilities  -> MCP resource: runtime readiness" # INT section 7
  raw_actions:   "action_executor run-plan  -> advanced/low-level action plans (optional)"  # L1 section 5
session:
  model: "one MCP session == one --state <path>"   # INT section 5 session isolation
errors:
  model: "propagate the INT section 4 error envelope verbatim as the tool-call error payload"  # INT section 4
safety:
  model: "reason=pending_safety_approval -> MCP elicitation/approval, resubmit confirmationStatus=approved"  # INT section 8
decide:
  owner: "host / model client; the server never calls a model or judges task success"  # INT section 2
```

## Proposed server shape (when implemented)

```yaml
server:
  transport: "MCP stdio or socket"
  startup:
    - "run action_executor capabilities once; refuse tools that need an unavailable prerequisite"
  tools:
    source: "task_flow tools-schema for a configured manifest or a manifest per registered scenario"
    invoke: "execute-json (or preview-json when the caller requests a dry run)"
  resources:
    - "capabilities (read-only, never prompts)"   # INT section 7
  state:
    - "allocate a unique --state path per MCP session"  # INT section 5
  binary_preference: "prefer ../../runtimes/desktop-gui/bin/* if present, else swift scripts"  # INT section 9
```

## Build/run prerequisites (for the future implementation)

```bash
bash ../../runtimes/desktop-gui/scripts/build.sh   # produce ../../runtimes/desktop-gui/bin/{action_executor,scene_runner,task_flow}
../../runtimes/desktop-gui/bin/action_executor capabilities   # gate: screen recording permission, cliclick, displays
```

## Non-goals for this note

- No server process, transport code, or dependency is added.
- No change to L0/L1/L2/L3 contracts or current desktop GUI manifest/profile wire shapes is
  required to build this later.
- No model call, autonomous planning, or task success judgement belongs inside the service.
