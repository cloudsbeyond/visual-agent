# visual-agent

I am building **visual-agent**: a protocol-first framework that helps visual-model hosts safely
operate software interfaces and simple physical panels.

Visual models can see interfaces and reason about visible state. That is not enough to make
operation reliable. A host needs a structure that says what a runtime can observe and execute,
what a concrete surface means, which actions are safe, and how success is verified.

That structure is **visual-agent**.

## The Problem

Most computer-use, GUI automation, device-control, and embodied-control projects start from an
agent loop, a sandbox, a browser, a controller, or a robot stack. Those are useful, but they leave
a gap between visual understanding and trustworthy operation.

The missing layer is a protocol and manual system:

- below agents, planners, and model adapters;
- above screenshots, cameras, input events, device commands, and actuator backends;
- independent of model providers;
- independent of specific software, websites, devices, or control surfaces;
- explicit about safety, state, and verification.

## Operational Surfaces

An **Operational Surface** is a bounded interface that can be:

- observed by a visual model or host;
- acted on through declared runtime capabilities;
- described by a surface-specific manual;
- verified by a fresh observation after each meaningful action.

Examples include software GUIs, browser pages, mobile screens, native app windows, printer or ATM
panels, appliance controls, instrument displays, and simple embodied-control surfaces. The core
protocol is about operating the surface. Full robotics, navigation, grasping, force control, and
world modeling are outside P0.

This is the protocol's **L0: Operational Surface Contract**. L0 defines what kind of visible
interface can enter the visual-agent loop before any runtime action, surface manual, or scenario
manifest is considered.

## The Operating Model

The host owns the intelligence loop:

```text
observe -> decide -> act -> verify
```

This project owns the contract around that loop:

- what operational surface is eligible for the loop;
- what a runtime or adapter can observe and execute;
- how a concrete operational surface is described;
- how a task becomes a safe action plan;
- how results and failures are represented;
- why dispatched actions are not the same as task success.

## The Four Layers

| Layer | Manual / contract | Purpose |
|---|---|---|
| L0 | Operational Surface Contract | Defines what counts as an operational surface, its boundary, observation frame, safety envelope, and minimum verification expectation. |
| L1 | Runtime Capability Manual | Describes what a runtime or adapter can observe and execute, and returns machine-readable results. |
| L2 | Surface Manual | Describes a concrete operational surface: observable states, safe targets or controls, action boundaries, and verification rules. |
| L3 | Scenario Requirements | Describes task-specific intents and manifests that expand into safe runtime action plans. |

The layers are intentionally separated. L0 defines surface eligibility and boundaries. L1 must not
know surface semantics. L2 must not reimplement runtime mechanics. L3 must not issue raw pointer,
device, or actuator events. The host decides; the runtime executes; verification comes from a
fresh observation.

## What I Am Not Building

I am not building:

- a computer-use agent;
- a planner;
- a model adapter;
- an MCP server as the core product;
- a generic browser automation framework;
- a robotics framework or embodied-intelligence stack;
- app-specific or device-specific scripts embedded in generic runtime code.

Those can exist around the project later. They should not define the core. The name
**visual-agent** describes the visible-surface operation concept, not an autonomous agent product.

## Core Contract

P0 is defined as:

- protocol-first L0/L1/L2/L3 surface, runtime, and manual system for visual-agent;
- model-agnostic and surface-agnostic core;
- surface-specific knowledge kept outside generic runtime code;
- `ActionResult.ok == true` means dispatched or completed at the runtime boundary, not
  successful at the task level;
- task success verified only by a fresh observation;
- machine-readable failures;
- explicit safety approval.

The current implementation under `runtimes/desktop-gui` is the first desktop-GUI reference runtime.
It proves the contract on software surfaces, but it is not the product boundary. Browser, mobile,
physical-panel, and embodied-control runtimes can later implement the same L0/L1/L2/L3 contract
as adapters or forked projects.

## Start Here

- Agent build charter: `AGENTS.md`
- Chinese thesis: `README.zh-CN.md`
- Current reference runtime: `runtimes/desktop-gui/README.md`
- Background market research: `docs/research/computer-use-market-research.md`

## Verify

Run from the repository root:

```bash
swiftc -typecheck runtimes/desktop-gui/src/action_executor.swift
swiftc -typecheck runtimes/desktop-gui/src/scene_runner.swift
swiftc -typecheck runtimes/desktop-gui/src/task_flow.swift
bash runtimes/desktop-gui/scripts/smoke.sh
```

Expected smoke result: `SMOKE_OK`.
