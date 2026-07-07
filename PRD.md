# visual-agent PRD

`PRD.md` is the fixed formal L0 projection of the product narrative in `README.md`
and `README.zh-CN.md` for `visual-agent`. Together they define product intent
before protocol layer documents, schemas, fixtures, runtime code, adapters, or
integration guides are changed.

It is intentionally thin. It does not replace the public product narrative, and
it is not a fragmented spec set, implementation plan, or runtime manual.

## L0 Problem

Visual models and hosts can understand visible interfaces, but safe operation
requires a project-owned boundary around which surfaces are eligible, what a
runtime may execute, how surface-specific knowledge is represented, how task
intents expand into actions, and how success is verified by fresh observation.

`visual-agent` exists to provide that protocol-first boundary without becoming
a computer-use agent, planner, model adapter, browser automation framework, MCP
server, or robotics stack.

## P0 Scope

P0 is the protocol-first surface operation system:

- Operational Surface eligibility and boundary.
- Runtime capability declaration and machine-readable action results.
- Surface manuals for concrete operational surfaces.
- Scenario requirements and manifests that expand into safe action plans.
- Fresh-observation verification after declared runtime actions.

The current desktop GUI runtime is a reference implementation of this product
boundary, not the product boundary itself.

## Non-Goals

- Do not use per-layer protocol documents as independent product PRDs.
- Do not let runtime code redefine product scope or layer semantics.
- Do not hide surface eligibility inside runtime, L1, L2, or adapter code.
- Do not add app-specific, site-specific, or device-specific workflows to
  generic runtime code.
- Do not treat `ActionResult.ok == true` as task success.

## Downstream Chain

Formal development flows from the co-equal public narrative and PRD L0 assets
into protocol and runtime assets:

```text
README.md / README.zh-CN.md / PRD.md
  -> AGENTS.md
  -> protocol layer documents
  -> schemas + fixtures + conformance checks
  -> runtime code + adapters + examples
  -> verification evidence
```

Protocol layer documents are downstream contract/manual assets. They can define
protocol-layer L0/L1/L2/L3 behavior, but they must remain aligned with this PRD
and the public product narrative.

## Owner Boundary

Human owner or architect owns product intent, layer semantics, and P0 scope.
Agents and engineers may maintain protocol documents, schemas, fixtures, and
runtime code only under that frozen boundary.

Return to public narrative / PRD review when a change would alter product
scope, layer ownership, safety semantics, adapter boundaries, or verification
meaning.
