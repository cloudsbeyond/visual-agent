# L0 - Operational Surface Contract

- Protocol Layer: 0 (Operational Surface Contract)
- Version: 1
- Status: Normative
- Depends on: root contract (`AGENTS.md`, `README.md`, `README.zh-CN.md`)
- Key words convention: see Section 1

## Abstract

This document specifies Layer 0 of the visual-agent L0/L1/L2/L3 protocol. L0 defines what kind of
bounded visible interface can enter the visual-agent loop before any runtime action, surface
manual, or scenario manifest is considered.

An Operational Surface may be a software GUI, browser page, mobile screen, native app window,
device panel, appliance control surface, instrument display, or a simple embodied-control surface.
The contract covers surface operation: observation, declared action, safety boundary, and fresh
verification. It does not define full robotics, navigation, manipulation, grasping, force control,
world modeling, model planning, or autonomous agent behavior.

## 1. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
RFC 2119.

- **Operational Surface**: a bounded visible interface that can be observed, acted on through
  declared runtime capabilities, and verified by a fresh observation.
- **Surface Boundary**: the declared scope of controls, indicators, coordinate frames, actuator
  targets, and side effects included in the loop.
- **Observation Frame**: the reference frame used to interpret visible state and action targets.
  Examples include a desktop window, browser viewport, mobile screen, panel coordinate plane, or
  device-local view.
- **Safety Envelope**: the allow-list, deny-list, approval gates, and stop conditions that constrain
  operation on the surface.
- **Minimum Verification Expectation**: the fresh observation required after a meaningful action so
  the host can judge whether the task state changed as intended.
- **Runtime / Adapter**: the component exposing L1 capabilities for a specific backend or actuator
  channel.
- **Visual Model / Host**: the external component that interprets observations, decides actions,
  and judges task success.

## 2. Eligibility Contract

A candidate target SHALL qualify as an Operational Surface only when all of the following hold:

1. **Bounded surface**: the boundary of the visible interface can be identified before action.
2. **Observable state**: the current state can be observed in a declared Observation Frame with
   enough fidelity for the host to reason about it.
3. **Declared action channel**: actions are available only through an L1 Runtime Capability Manual
   or adapter that declares its supported observations, actions, errors, and limits.
4. **Surface manual path**: an L2 Surface Manual can describe the surface states, safe targets or
   controls, action boundaries, and verification rules.
5. **Scenario path**: an L3 Scenario Requirements instance can express the task as intents and
   safe runtime action plans.
6. **Verifiable effects**: every meaningful action has a fresh-observation path with expected
   success and failure signals.
7. **Safety envelope**: high-risk, persistent, remote, destructive, or irreversible actions are
   forbidden by default unless explicitly allowed and routed through approval.

If any requirement is missing, the target is outside the L0 contract and MUST NOT be executed
through L1/L2/L3 as if it were eligible.

## 3. Non-Eligible Targets

The following are outside P0 unless a future contract explicitly reopens them:

- unbounded environments where the relevant interface boundary cannot be declared;
- targets that cannot be observed with enough fidelity for a host to reason about current state;
- hidden side-effect channels where action effects cannot be verified by fresh observation;
- full robotics stacks, navigation, grasping, force control, world modeling, or manipulation
  planning;
- autonomous planning agents or model adapters;
- app-specific, site-specific, or device-specific script collections embedded in generic runtime
  code.

## 4. Boundary Of Responsibility

| Layer | Owns | Does not own |
|---|---|---|
| L0 | Surface eligibility, boundary, observation frame, safety envelope, minimum verification expectation. | Runtime mechanics, concrete surface semantics, scenario expansion, model judgement. |
| L1 | Runtime or adapter observations, declared actions, backend limits, machine-readable results and errors. | Surface meaning, task success, hidden eligibility decisions. |
| L2 | Concrete surface states, safe targets or controls, action boundaries, verification rules. | Raw input or actuator dispatch, task aggregation. |
| L3 | Task intents, manifest fields, action-step templates, data handling rules. | Raw pointer, device, or actuator events; task success judgement without fresh observation. |
| Host | Observation interpretation, decision, success judgement, escalation. | Runtime dispatch internals. |

L0 MUST be evaluated before a candidate surface is treated as valid input to L1, L2, or L3.
L1/L2/L3 documents MAY carry backend-specific terms for a reference runtime, but they MUST NOT
hide surface eligibility inside runtime code, profiles, manifests, or adapter glue.

## 5. OperationalSurfaceDescriptor

An implementation MAY represent L0 eligibility with a descriptor. The exact wire shape can vary by
adapter, but it SHOULD preserve the following fields:

```json
{
  "schemaVersion": 1,
  "kind": "operational_surface",
  "surfaceID": "<opaque>",
  "surfaceType": "desktop_gui | browser_page | mobile_screen | physical_panel | simple_embodied_control | other",
  "boundary": {
    "description": "<bounded visible interface>",
    "observationFrame": "<declared frame>",
    "constraints": []
  },
  "observation": {
    "source": "<camera | screenshot | adapter | bounded-capture>",
    "usabilityCriteria": []
  },
  "actionChannels": [
    { "runtime": "<l1-runtime-or-adapter>", "capabilityRef": "<opaque>" }
  ],
  "safety": {
    "forbiddenByDefault": [],
    "requiresApprovalFor": []
  },
  "verification": {
    "freshObservationRequired": true,
    "expectedSignals": []
  }
}
```

Current desktop GUI profiles are the first reference implementation of this idea. They do not yet
need to expose the full descriptor as a public wire object, but their documentation and adapters
MUST preserve the same boundary, safety, and verification semantics.

## 6. Required Invariants

1. L0 qualifies the surface before L1/L2/L3 execution begins.
2. A surface boundary is explicit; the whole machine, world, or device environment is not the
   default surface.
3. Observation and action use declared frames and capabilities.
4. Action dispatch is not task success; task success belongs to the host after fresh observation.
5. High-risk actions are denied or approval-routed by default.
6. Surface-specific knowledge lives in L2 manuals, profiles, manifests, or adapter data, not in
   generic runtime engines.
7. New browser, mobile, physical-panel, or embodied-control backends preserve the L0/L1/L2/L3
   contract as adapters or forked projects unless the root contract is explicitly reopened.
