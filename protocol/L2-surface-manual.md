# L2 - Surface Manual Protocol (Template)

- Protocol Layer: 2 (Surface Manual)
- Version: 1
- Status: Normative Template
- Depends on: L0 - Operational Surface Contract; L1 - Runtime Capability Manual Protocol
- Key words convention: see Section 1

## Abstract

This document specifies Layer 2 of the visual-agent L0/L1/L2/L3 protocol. Layer 2 is the Surface
Manual: for a concrete Operational Surface qualified by L0, it defines observed states, safe
targets or controls, action boundaries, and verification signals that map to safe Layer 1 action
plans.

This document is a template: it defines the normative extension points an implementer SHALL fill
in to instantiate Layer 2 for a particular surface and scenario. The current desktop GUI reference
runtime instantiates this template for software windows using a Target Profile. That binding is a
reference-runtime case, not the whole protocol.

## 1. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
RFC 2119.

- **Operational Surface**: the L0-qualified bounded visible interface being operated.
- **Scenario**: a concrete instantiation of Layers 2 and 3 for one Operational Surface and one
  class of operations.
- **Surface Manual**: the Layer 2 instance that describes observable states, target or control
  types, action boundaries, and verification rules for a concrete Operational Surface.
- **Surface Profile**: the configuration record that binds a Scenario to its Operational Surface
  (Section 3).
- **Target Profile**: the current desktop GUI reference-runtime shape for a Surface Profile.
- **Observed State**: a label classifying the current surface appearance for the purpose of
  choosing a safe action (Section 4).
- **Target Type**: a label classifying what visible element an action addresses (Section 5).

## 2. Layer Boundaries

| Layer | Responsibility | Out of scope |
|---|---|---|
| L0 | Qualify the Operational Surface, boundary, observation frame, safety envelope, and minimum verification expectation. | Runtime mechanics, concrete surface semantics, task expansion. |
| L1 | Execute `ActionPlan.actions[]`; expose declared runtime capabilities, backends, capture, results, and errors. | Surface state, surface safety rules, task semantics. |
| L2 | Act as the concrete Surface Manual: classify state; select safe human-equivalent actions; emit L1 `ActionPlan`. | Task aggregation, reporting, business fields, raw dispatch. |
| L3 | Consume Surface Manual outputs; formalize scenario requirements. | Pointer, device, or actuator events; coordinate arithmetic as task logic. |

A Layer 2 instance SHALL NOT reimplement Layer 1 input or capture mechanics; it SHALL delegate
execution to a Layer 1 executor by passing through a Surface Profile or the current desktop GUI
Target Profile.

## 3. Surface Profile Binding (Extension Point E1)

A Layer 2 instance SHALL define a Surface Profile that binds the manual to one L0-qualified
Operational Surface. In the current desktop GUI reference runtime, the Surface Profile is encoded
as a Target Profile providing the Layer 1 binding fields:

```json
{
  "bundleID": "<REQUIRED if ownerNames absent>",
  "ownerNames": ["<REQUIRED if bundleID absent>"],
  "appLabel": "<RECOMMENDED human-readable label>"
}
```

The profile SHALL be supplied to Layer 1 as configuration (for example environment or a profile
file). A Layer 2 instance MUST NOT hardcode a concrete app, site, device, or panel inside Layer 1;
the binding lives in the profile.

## 4. Observed States (Extension Point E2)

A Layer 2 Surface Manual SHALL enumerate the Observed States relevant to its Scenario. For each
state the instance SHALL declare its visual signature and the actions permitted in that state. The
following states are RESERVED by this template and SHALL be honored where applicable:

| State | Meaning | Required handling |
|---|---|---|
| `unobservableWindow` | Capture unusable or window not observable. | Halt actions; restore observability. |
| `nonTargetWindow` | In the desktop GUI reference runtime, a captured window is not the intended subject. | Halt surface actions; recover to the intended surface. |
| `unknown` | The agent cannot reliably classify. | Do not act; re-observe or escalate. |

All other states are surface-defined. Each surface-defined state SHALL be specified as a row with:
visual signature, permitted actions, and forbidden actions.

## 5. Target Types (Extension Point E3)

A Layer 2 Surface Manual SHALL enumerate the Target Types or control types it may act upon. For
each type the instance SHALL declare a decision condition and a forbidden condition. The RESERVED
value `none` SHALL mean "no safe target is present", in which case no action SHALL be issued.

## 6. State-to-Plan Mapping (Extension Point E4)

For each (Observed State, Target Type) pair it supports, a Layer 2 Surface Manual SHALL define the
human-equivalent operation and its mapping to an L1 `ActionPlan`. Each mapping SHALL specify:

1. the triggering Observed State and Target Type;
2. the expected success signal in the next observation;
3. the failure signals and their handling;
4. the resulting L1 `actions[]` (using only the L1 action set and required fields).

Coordinates in the produced plan SHALL derive from the current observation, never from fixed
row/column formulas or reused prior coordinates.

## 7. Surface Feedback Verification

An `ActionResult` with `ok:true` SHALL be treated only as "events dispatched" or "completed at the
runtime boundary". A Layer 2 Surface Manual SHALL verify the effect with the next observation. For
every mapping in Section 6 the instance SHALL define the success observation and the failure
observation, and SHALL NOT count an unverified action as successful.

## 8. Safety Boundaries (Extension Point E5)

A Layer 2 Surface Manual SHALL declare an explicit allow-list and deny-list of actions for its
Operational Surface and Scenario.
The deny-list SHALL, at minimum, forbid any operation that sends, commits, deletes, transmits, or
otherwise mutates remote or persistent state, unless such an operation is the explicit, audited
purpose of the Scenario and has been enabled at Layer 1. Unverified global shortcuts MUST NOT be
used as a default recovery path.

## 9. Decision Object (Optional)

A Layer 2 instance MAY define a decision object emitted by the Visual Model / Host that packages
the Observed State, selected target or control, safety assessment, and the resulting L1
`ActionPlan`. If defined, it SHALL embed a valid L1 `ActionPlan` per the L1 protocol.

## 10. Inheritance / Rewrite Procedure

To instantiate Layer 2 for a new Surface Manual / Scenario, an implementer SHALL, in order:

1. Confirm the Operational Surface satisfies L0.
2. Define the Surface Profile or current desktop GUI Target Profile (E1, Section 3).
3. Enumerate Observed States with visual signatures and permitted actions (E2, Section 4).
4. Enumerate Target Types with decision and forbidden conditions (E3, Section 5).
5. Define the State-to-Plan mappings, each producing a valid L1 `ActionPlan` (E4, Section 6).
6. Define success/failure verification observations for each mapping (Section 7).
7. Declare the Scenario allow-list and deny-list (E5, Section 8).
8. Validate each mapping with `dryRun:true` before any real dispatch.

A Layer 2 instance MUST NOT add fixed-coordinate scripts for a single screen; coordinates SHALL
come from the current observation.

## 11. Invariants

1. Layer 2 holds surface state and safety; it never reimplements Layer 1 mechanics.
2. Every produced plan is a valid L1 `ActionPlan`.
3. Coordinates come from the current observation.
4. Action effects are confirmed only by a subsequent observation.
5. The reserved states `unobservableWindow`, `nonTargetWindow`, and `unknown` halt or defer action.
6. Surface eligibility is inherited from L0, never hidden inside the Surface Manual.
