# Computer-Use Market Research From The visual-agent Contract

Date: 2026-06-14
Status: background research only
Source check: official project pages and repositories checked on 2026-06-14.

This report is not a source of product truth. The current authority chain is:

1. `AGENTS.md`
2. `README.md`
3. `README.zh-CN.md`

Use this document only as market calibration for the current thesis:

> visual-agent is a protocol-first framework that helps visual-model hosts safely operate
> software interfaces and simple physical panels.

The product starts from three commitments in the authority chain:

- the core is a L0/L1/L2/L3 protocol and manual system;
- the host owns observation interpretation, decision, approval, and task success judgement;
- the current desktop GUI runtime is a reference runtime, not the project boundary.

## Research Lens

The surrounding market already has agents, sandboxes, browser automation, desktop-control tools,
MCP servers, and perception components. Those projects validate that visual computer use matters.
They do not remove the need for an explicit operational-surface contract.

The visual-agent question is narrower:

```text
What protocol layer lets a visual-model host operate a bounded visible surface safely,
without baking agent judgement, model choice, app scripts, or runtime mechanics into the core?
```

That lens maps to the current four-layer contract:

| Layer | Question |
|---|---|
| L0 Operational Surface Contract | Is this bounded visible interface eligible to enter the loop? |
| L1 Runtime Capability Manual | What can this runtime observe and execute? |
| L2 Surface Manual | What does this concrete surface mean, and what is safe? |
| L3 Scenario Requirements | How does a task intent expand into a safe action plan? |

## Market Map

| Category | Representative projects | What they optimize for | What remains open for visual-agent |
|---|---|---|---|
| Full computer-use infrastructure | [Cua](https://github.com/trycua/cua), [Open Computer Use](https://github.com/e2b-dev/open-computer-use) | Sandboxes, drivers, hosted desktops, benchmarks, cross-environment execution | A model-agnostic surface contract and manual layer above raw computer access |
| Vendor computer-use samples | [OpenAI CUA sample app](https://github.com/openai/openai-cua-sample-app), [Anthropic computer-use demo](https://github.com/anthropics/claude-quickstarts/tree/main/computer-use-demo) | Demonstrating a provider-specific model loop and tool flow | Provider-independent L0/L1/L2/L3 contracts |
| Agent products and frameworks | [Bytebot](https://github.com/bytebot-ai/bytebot), [Agent-S](https://github.com/simular-ai/Agent-S) | End-to-end natural-language task execution and autonomous GUI use | A separable protocol boundary that does not assume the agent loop owns the core |
| Raw desktop runtimes | [usecomputer](https://github.com/remorses/usecomputer), [macos-cua](https://github.com/code-yeongyu/macos-cua) | Screenshots, clicks, typing, scrolling, app state, native OS control | L0 eligibility, L2 surface semantics, L3 task formalization, and task-level verification |
| MCP / tool servers | [mcp-server-macos-use](https://github.com/mediar-ai/mcp-server-macos-use), [MacOS-MCP](https://github.com/CursorTouch/MacOS-MCP) | Tool transport for OS-level capabilities | Manuals, safety semantics, and success verification above tool calls |
| Browser-specialized automation | [browser-use](https://github.com/browser-use/browser-use) | Making websites operable by agents | A surface contract that can also apply outside browser pages |
| Perception and grounding | [OmniParser](https://github.com/microsoft/OmniParser) | Parsing screen images into usable UI elements or targets | Operation contracts, safety policy, runtime results, and verification flow |

## Representative Notes

### Cua

Cua is broad computer-use infrastructure for building, benchmarking, and deploying agents that use
computers. Its current public positioning covers sandboxes, drivers, benchmarks, and desktop
control across operating systems.

visual-agent should treat Cua as a platform-level neighbor. It validates the need for reliable
computer-use infrastructure, but visual-agent should not start as another sandbox or desktop
platform. Its differentiating layer is the L0/L1/L2/L3 contract around operational surfaces.

### OpenAI CUA Sample App

The OpenAI sample is currently positioned as a GPT-5.4 CUA sample app for browser-focused
computer-use workflows, including an operator console, a runner, and shared scenario/runtime
packages. It is useful as an integration and safety reference, but it is tied to one provider's API
shape and a specific sample-app architecture.

visual-agent should remain model-agnostic. A host may use OpenAI, Anthropic, local models, or
another visual model, but the protocol should still define surface eligibility, runtime
capabilities, surface manuals, scenario requirements, machine-readable results, and verification.

### Anthropic Computer-Use Demo

The Anthropic quickstart demonstrates a model loop, tool use, and environment integration for
computer use.

For visual-agent, the lesson is boundary placement. The project should not absorb the full model
loop into the core. The host owns interpretation and judgement; visual-agent owns the contracts
around bounded visible-surface operation.

### Bytebot

Bytebot positions itself as a self-hosted AI desktop agent operating inside a containerized Linux
desktop. As of the 2026-06-14 source check, the GitHub repository is archived and read-only.

Bytebot is useful as a product-form reference for full desktop agency. visual-agent should not copy
that product shape into P0. It should define the contract layer that a desktop agent product could
consume or implement.

### Agent-S

Agent-S is an agentic framework for using computers like a human.

That validates the agent-centric direction in the market. visual-agent takes the complementary
contract-centric direction: it defines the operational-surface, runtime, manual, and scenario
boundaries below the agent.

### Open Computer Use

Open Computer Use focuses on AI computer use with open-source LLMs and an E2B desktop sandbox.

This reinforces that hosted execution and sandboxing are surrounding infrastructure. The
visual-agent core should remain the surface-operation contract, not a hosted desktop environment.

### usecomputer

usecomputer is a desktop automation CLI for AI agents, exposing capabilities such as screenshots,
clicks, typing, and scrolling.

That is close to an L1 runtime capability surface. The gap visual-agent fills is around it and
above it: L0 surface eligibility, L2 surface meaning, L3 scenario formalization, safety routing,
and task-level verification from fresh observation.

### macos-cua

macos-cua explores native macOS computer-use control with a model-friendly action vocabulary and
host-native execution paths.

This is relevant to future desktop GUI runtime implementation choices. It should not define the
project narrative. visual-agent needs to keep the runtime capability boundary separate from L0
eligibility, L2 surface semantics, and L3 scenario requirements.

### macOS MCP Servers

macOS MCP servers expose operating-system capabilities through model tool transports.

They are useful adapter references. They also show why transport is not the core product:
MCP exposes tools, but does not by itself define operational-surface eligibility, manual
semantics, safety policy, or success verification.

### browser-use

browser-use specializes in making websites operable by agents.

Browser pages can become an important future runtime family, but browser automation should not
replace the project boundary. The same L0/L1/L2/L3 contract should apply: browser page eligibility
at L0, browser runtime capability at L1, site or app manual at L2, and task-specific scenario
requirements at L3.

### OmniParser

OmniParser is a screen parsing and grounding component for vision-based GUI agents.

Grounding can improve observation quality for a host. It does not replace the protocol. The host
may use perception tools to interpret visible state, while visual-agent defines how eligible
surfaces, runtime actions, manuals, scenarios, results, and verification are represented.

## What The Market Already Has

The market already has:

- autonomous GUI agents and desktop-agent products;
- provider-specific computer-use API samples;
- hosted desktops and sandbox environments;
- browser-first automation frameworks;
- native OS control libraries and CLIs;
- MCP tool servers;
- screenshot parsing and UI grounding components.

Competing directly as any one of those would blur visual-agent.

## The Missing Layer

The missing layer is a protocol/manual boundary between visual-model reasoning and runtime
execution.

That boundary must answer:

- What is the operational surface and why is it eligible?
- What observation frame and safety envelope apply?
- What can the runtime observe and execute?
- What does the concrete surface mean?
- Which controls or targets are safe?
- Which scenario intent is being formalized?
- Which action plan is allowed?
- What runtime result was emitted?
- What fresh observation verifies or rejects task success?
- Which failures are machine-readable and branchable?

This is exactly the current visual-agent L0/L1/L2/L3 contract.

## Implications For visual-agent

The research supports the current thesis:

- Stay protocol-first, not agent-first.
- Keep model providers outside the core.
- Treat desktop GUI as the first reference runtime, not the product boundary.
- Keep raw actions in L1 and surface meaning in L2.
- Keep task intents in L3 and task success judgement in the host.
- Make L0 explicit so software GUIs, browser pages, mobile screens, simple physical panels, and
  simple embodied-control surfaces can share the same eligibility frame.
- Keep full robotics, navigation, grasping, force control, and world modeling outside P0.
- Use MCP, browser runtimes, native OS runtimes, physical-panel adapters, and embodied-control
  runtimes as adapter or follow-on project directions.

## Non-Implications

This research does not imply that visual-agent should:

- become a full desktop agent product;
- bundle a planner or model loop into the core;
- choose a model provider;
- become an MCP server as the product identity;
- become a browser automation framework;
- become a robotics stack;
- commit to any one runtime implementation beyond the current desktop GUI reference runtime.

## Maintenance Rule

Update this report only when it changes the market calibration around the three-file authority
chain. Do not let it redefine the product scope. If this report conflicts with `AGENTS.md`,
`README.md`, or `README.zh-CN.md`, the three-file authority chain wins.
