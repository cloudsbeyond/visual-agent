# AGENTS.md

This file is the build charter for agents working on **visual-agent**.

Treat this repository as a project being built from zero to one. The root documents define the
product thesis and architecture contract.

## Project Thesis

I am building **visual-agent**: a protocol-first framework that helps visual-model hosts safely
operate software interfaces and simple physical panels.

The project exists because visual models can understand visible interfaces, but reliable
operation needs more than raw screenshots, input events, device commands, or robot actions. It
needs explicit runtime capabilities, surface manuals, scenario requirements, safety boundaries,
and verification rules.

The name **visual-agent** describes the user-facing concept: a visual model or host operating a
visible surface through an explicit protocol. It does not mean this repository is an autonomous
agent, planner, model adapter, or robotics stack.

An **Operational Surface** is any bounded interface that can be observed, acted on through
declared runtime capabilities, and verified by a fresh observation. It may be a software GUI,
browser page, mobile screen, native app window, device panel, appliance control surface, or a
simple embodied-control surface. This is the protocol's **L0**: it defines what kind of object can
enter the visual-agent loop. The P0 contract covers the surface operation layer, not full robotics,
navigation, manipulation, or world modeling.

## Narrative Rule

Use a top-down pyramid narrative in every public or architectural document:

1. State the thesis.
2. Define the problem this project solves.
3. Define the operating model.
4. Define the layer boundaries.
5. Only then describe files, commands, examples, or implementation details.

Write from the current thesis as the starting point. Public docs should stay free of local
directory aliases, historical names, private paths, and historical local material.

## P0 Contract

P0 is the protocol-first surface, runtime, and manual system behind visual-agent.

The four layers are fixed:

- **L0: Operational Surface Contract** - defines what counts as an operational surface, its
  boundary, observation frame, safety envelope, and minimum verification expectation.
- **L1: Runtime Capability Manual** - describes what a runtime or adapter can observe and
  execute, and returns machine-readable results.
- **L2: Surface Manual** - describes a concrete operational surface: observable states, safe
  targets or controls, action boundaries, and verification rules.
- **L3: Scenario Requirements** - describes task-specific intents and manifests that expand into
  safe runtime action plans.

The external visual model or host owns observation interpretation, decision, and success
judgement. The runtime executes declared actions, emits JSON, and never decides task meaning.

Current desktop GUI assets are a reference implementation of this contract, not the whole product
boundary. Browser, mobile, physical-panel, and embodied-control runtimes may later implement the
same L0/L1/L2/L3 contract through adapters or separate forked projects.

## Non-Goals

This project is not:

- a computer-use agent;
- a planner;
- a model adapter;
- an MCP server as the core product;
- a generic browser automation framework;
- a robotics framework or embodied-intelligence stack;
- a navigation, grasping, force-control, or world-model protocol;
- a collection of app-specific or device-specific scripts inside generic runtime code.

MCP, service wrappers, browser runtimes, model integrations, physical-panel adapters, and
embodied runtimes are future adapters or separate design topics. They must preserve the L0/L1/L2/L3
contract.

## Source Of Truth

The current documentation authority chain has exactly three files:

1. `AGENTS.md` - build charter for agents.
2. `README.md` - public English thesis and product narrative.
3. `README.zh-CN.md` - public Chinese thesis and product narrative.

No other file is currently authoritative for public positioning, architecture, or product scope.

## Open-Source Surface

Prepare the repository as a public project:

- keep public docs portable and first-principles;
- do not commit generated state, secrets, private paths, or review scratch;
- do not commit historical local material;
- keep examples small, safe, and reproducible;
- keep failure modes and verification commands visible.

Project-local coordination notes are ignored by Git and are not project source-of-truth.

## Implementation Rules

- Keep runtime engines generic.
- Treat Operational Surface as L0; do not hide surface eligibility inside L1, L2, or runtime code.
- Put surface-specific knowledge in profiles, manifests, and L2/L3 manuals.
- Do not add concrete app, site, or device workflows to generic runtime code.
- Do not make `ActionResult.ok == true` mean task success. It only means declared actions were
  dispatched or completed at the runtime boundary.
- Preserve the observe -> decide -> act -> verify loop.
- Emit machine-readable errors.
- Route safety approval explicitly.
- Keep adapters thin; they map transports or actuator backends onto the protocol and do not call
  models.
- Use ASCII in source and English docs unless a file is intentionally localized.

## Validation Commands

Run from the repository root when touching runtime or protocol behavior:

```bash
swiftc -typecheck runtimes/desktop-gui/src/action_executor.swift
swiftc -typecheck runtimes/desktop-gui/src/scene_runner.swift
swiftc -typecheck runtimes/desktop-gui/src/task_flow.swift
bash runtimes/desktop-gui/scripts/smoke.sh
```

Expected smoke success: `SMOKE_OK`.

## Spec Checkpoint

When discussing requirements, architecture, public positioning, or formal project direction, pause
and checkpoint:

```text
P0 main path:
<one sentence>

Pruned:
- <merged, deleted, or downgraded points>

Kept but postponed:
- <P1/P2, pending decision, or research items>

Needs confirmation:
- <small number of decisions>
```

Do not expand P1/P2 into P0. Do not rewrite the three-file root contract without explicit user
approval.
