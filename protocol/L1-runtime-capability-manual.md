# L1 - Runtime Capability Manual Protocol

- Protocol Layer: 1 (Runtime Capability Manual)
- Version: 1
- Status: Normative
- Depends on: L0 - Operational Surface Contract
- Key words convention: see Section 1

## Abstract

This document specifies Layer 1 of the visual-agent L0/L1/L2/L3 protocol. Layer 1 is the Runtime
Capability Manual: it defines what a runtime or adapter can observe and execute after L0 has
qualified a bounded Operational Surface. L1 does not know surface semantics, business meaning, or
task purpose.

The current wire contract is the desktop GUI reference runtime. It uses terms such as Target
Application, Target Window, `AppObservation`, and `windowTopLeft` to describe the first backend.
Those terms are reference-runtime bindings, not the full visual-agent product boundary.

L1 defines a closed loop in which an external visual model / host observes a surface, emits a
typed action plan, the executor performs the declared actions and returns machine-readable
results, and the host re-observes to verify the outcome. `ActionResult.ok == true` means runtime
dispatch or completion only; it is never task success.

## 1. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
RFC 2119.

- **Operational Surface**: the L0-qualified bounded visible interface being operated.
- **Desktop GUI Reference Binding**: the current L1 binding that maps an Operational Surface to a
  desktop application window.
- **Target Application**: in the desktop GUI reference binding, the application whose window is the
  subject of observation and action. It is supplied to the executor as configuration and is opaque
  to Layer 1 semantics.
- **Visual Model / Host**: an external component that consumes an `AppObservation` and produces an
  `ActionPlan`. Its perception, planning, and judgement are out of scope for this protocol.
- **Action Executor**: the local component that performs the actions declared in an `ActionPlan`
  and emits an `ActionResult`. It performs no business or visual judgement.
- **Target Window**: in the desktop GUI reference binding, the on-screen window of the Target
  Application selected for the current loop.
- **Active Display**: a display currently attached and enabled, as reported by the windowing
  system.

## 2. Protocol Model

### 2.1 Closed Loop

After L0 has qualified an Operational Surface, the Layer 1 loop SHALL consist of the following
ordered phases:

```
AppObservation -> ActionPlan -> ActionResult -> VerificationObservation -> (repeat)
```

1. The Visual Model / Host obtains an observation of the Operational Surface. In the current
   desktop GUI reference binding, this is an `AppObservation` of the Target Window.
2. The Visual Model / Host produces an `ActionPlan` containing an ordered list of actions.
3. The Action Executor performs the actions in order and returns an `ActionResult`.
4. A new `VerificationObservation` SHALL be produced before the next planning step.

### 2.2 Separation of Responsibilities

- The Action Executor MUST perform only the actions declared in `ActionPlan.actions[]`.
- The Action Executor MUST NOT decide which target to act upon, nor interpret business meaning.
- A successful `ActionResult` (`ok:true`) SHALL mean only that events were dispatched; it MUST
  NOT be interpreted as task success. Task success SHALL be established only by a subsequent
  observation.

## 3. Desktop GUI Target Binding

The current desktop GUI reference runtime binds an Operational Surface to a Target Application
window. The Target Application SHALL be provided to the executor by configuration, not inferred at
runtime by the executor. An implementation SHALL accept the following identifying fields:

| Field | Meaning | Requirement |
|---|---|---|
| `bundleID` | Platform bundle identifier of the Target Application. | OPTIONAL if `ownerNames` is given |
| `ownerNames` | Candidate window owner names. | OPTIONAL if `bundleID` is given |
| `appLabel` | Human-readable label used in logs and results. | RECOMMENDED |

At least one of `bundleID` or `ownerNames` SHALL be provided. An implementation MAY also accept
these values via environment variables.

## 4. AppObservation

An `AppObservation` describes the current visual state input for the desktop GUI reference
runtime. It MAY originate from the Action Executor's bounded capture, or from any external source
able to produce an equivalent structure. Future non-desktop adapters MAY wrap this shape in a more
general surface observation, but they MUST preserve the same observe -> act -> verify semantics.

```json
{
  "schemaVersion": 1,
  "kind": "appObservation",
  "source": "agent-observation | computer-use-adapter | bounded-capture",
  "coordinateSpace": "windowTopLeft",
  "app": {
    "bundleIdentifier": "<opaque>",
    "label": "<opaque>",
    "window": { "x": 0, "y": 0, "width": 0, "height": 0 }
  },
  "screenshot": { "width": 0, "height": 0, "scale": 1, "path": "<optional>" },
  "capture": { "ok": true, "usableForVision": true, "visualStats": {} },
  "stateHint": "unknown"
}
```

### 4.1 `source`

| Value | Meaning |
|---|---|
| `agent-observation` | Screenshot supplied by an external visual agent or adapter. |
| `computer-use-adapter` | Screenshot supplied by a computer-use style adapter. |
| `bounded-capture` | Screenshot captured by the Action Executor within the desktop GUI Target Window. |

### 4.2 `coordinateSpace`

An `AppObservation` SHALL declare the coordinate space its coordinates are expressed in. The
permitted values are defined in Section 7.

### 4.3 `stateHint`

`stateHint` is an OPTIONAL coarse classification provided to assist the agent. Layer 1 defines
only the reserved value `unobservableWindow` (Section 8); all other values are surface-defined and
opaque to Layer 1.

## 5. ActionPlan

An `ActionPlan` is produced by the Visual Model / Host and consumed by the Action Executor.

```json
{
  "schemaVersion": 1,
  "kind": "action_plan",
  "wireFormat": "openai_computer_call_compatible",
  "call_id": "<opaque>",
  "pending_safety_checks": [],
  "confirmationStatus": "not_required",
  "dryRun": false,
  "bundleID": "<opaque>",
  "ownerNames": ["<opaque>"],
  "appLabel": "<opaque>",
  "allowNegativeWindowOrigin": false,
  "actions": [ { "type": "click", "x": 0, "y": 0 } ]
}
```

- `actions` SHALL be a non-empty ordered array. The executor SHALL perform them in array order.
- `call_id` SHALL be echoed in the corresponding `ActionResult`.
- `wireFormat`, when present, indicates a compatibility envelope; it does not bind the protocol
  to any vendor.

## 6. Action Set

Each element of `actions[]` SHALL declare a `type`. The executor SHALL reject any unknown type.

| `type` | Meaning | Status |
|---|---|---|
| `click` | Single pointer click at a coordinate. | REQUIRED |
| `scroll` | Scroll at a coordinate using `scrollY` (and OPTIONAL `scrollX`). | REQUIRED |
| `keypress` | Key event(s) declared in `keys[]`. | REQUIRED (constrained, see 6.2) |
| `wait` | Idle for `durationMs`. | REQUIRED |
| `screenshot` | Request a new capture; OPTIONALLY write a window region to `output`. | REQUIRED |
| `type` | Text entry. | RESERVED, MUST NOT execute at Layer 1 |
| `drag` | Pointer drag. | RESERVED, MUST NOT execute at Layer 1 |
| `move` | Pointer move. | RESERVED, MUST NOT execute at Layer 1 |
| `double_click` | Double click. | RESERVED, MUST NOT execute at Layer 1 |

### 6.1 Required Fields

| `type` | Required fields |
|---|---|
| `click` | `type`, `x`, `y` |
| `scroll` | `type`, `x`, `y`, `scrollY` |
| `keypress` | `type`, `keys` |
| `wait` | `type` (`durationMs` OPTIONAL) |
| `screenshot` | `type` (`x`/`y`/`width`/`height`/`output`/`maxEdge` OPTIONAL) |

### 6.2 Action Field Reference

| Field | Applies to | Meaning |
|---|---|---|
| `mode` | `click`, `scroll`, `keypress` | Backend selector (Section 9). |
| `coordinateSpace` | `click` | Coordinate space of `x`/`y` (Section 7). |
| `restoreMouse` | `click` | Whether the pointer is restored after the click. |
| `scrollY` / `scrollX` | `scroll` | Scroll delta; positive `scrollY` SHALL mean downward. |
| `keys` | `keypress` | Key names. An implementation MAY constrain the supported set. |
| `durationMs` | `wait` | Idle duration in milliseconds. |
| `x`/`y`/`width`/`height` | `screenshot` | Crop region inside the desktop GUI Target Window. |
| `output` | `screenshot` | Output path; if absent, the executor SHALL signal that a capture is needed without writing a file. |
| `maxEdge` | `screenshot` | Upper bound on the longest output edge in pixels. |
| `allowNegativeWindowOrigin` | `click`, `scroll` | Override for the negative-origin guard (Section 8). |

### 6.3 Reserved Actions

`type`, `drag`, `move`, and `double_click` are RESERVED. The Layer 1 executor MUST reject them.
A higher layer MAY define a profile that permits a reserved action only after the executor has
been extended to implement it safely; until then they MUST NOT execute.

## 7. Coordinate Spaces

An implementation SHALL support the following coordinate spaces. `windowTopLeft` SHALL be the
default when none is declared.

| Value | Origin |
|---|---|
| `windowTopLeft` | Top-left corner of the desktop GUI Target Window. |
| `windowBottomLeft` | Bottom-left corner of the desktop GUI Target Window. |
| `screenTopLeft` | Top-left corner of the screen coordinate system. |
| `screenBottomLeft` | Bottom-left corner of the screen coordinate system. |

`scrollY` polarity SHALL be normalized such that a positive value scrolls downward, regardless
of the platform's native wheel direction.

## 8. Safety Invariants

- If `pending_safety_checks[]` is non-empty and `dryRun` is false, the executor MUST refuse
  execution unless `confirmationStatus` equals `approved`.
- For `click` and `scroll`, the resolved event point MUST lie within the rectangle of some
  Active Display. A negative window origin SHALL NOT by itself constitute a violation; the test
  is active-display containment. The guard MAY be overridden by `allowNegativeWindowOrigin:true`
  only after the display layout has been verified.
- The executor MUST reject reserved action types (Section 6.3).
- `dryRun:true` SHALL compute and return results (including resolved coordinates) without
  dispatching any input event or writing any file.

## 9. Backends

The `mode` field selects the input backend. An implementation SHALL document which backends it
supports and their stability. The following identifiers are reserved:

| `mode` | Applies to |
|---|---|
| `cliclick` | `click`, `keypress` |
| `hid` | `click`, `scroll`, `keypress` |
| `pid` | `click`, `scroll`, `keypress` (experimental) |

`cliclick` SHALL NOT be used for `scroll`. Capture backends for `screenshot` are
implementation-defined and SHALL be subject to the usability contract in Section 10.

## 10. Capture Usability Contract

A capture API reporting success SHALL NOT be treated as sufficient for visual use. An
implementation SHALL compute a usability signal and expose it.

| Field | Meaning |
|---|---|
| `capture.ok` / `captureProbeOk` | A capture backend returned an image. |
| `capture.usableForVision` / `captureProbeUsableForVision` | The image is suitable as visual input. |
| `captureVisualStats` | Downsampled luminance statistics supporting the usability decision. |
| `captureFallbackErrors` | Reasons earlier backends failed or returned low-information images. |
| `stopReason` | Reason to stop: e.g. window not on active display, capture unusable, permission required. |

When `usableForVision` is false, the observation SHALL set `stateHint` to `unobservableWindow`,
and the agent MUST halt action dispatch and restore observability before continuing.

If the current desktop GUI Target Application enforces screenshot countermeasures such that
captures are systematically not usable for vision, this loop is inapplicable for that target;
feasibility MUST be assessed before relying on Layer 1.

## 11. ActionResult

The executor SHALL emit one `ActionResult` per plan.

```json
{
  "ok": true,
  "kind": "action_result",
  "wireFormat": "openai_computer_call_result_compatible",
  "call_id": "<echoed>",
  "dryRun": false,
  "results": [
    { "index": 0, "ok": true, "type": "click", "dryRun": false, "appLabel": "<opaque>" }
  ]
}
```

- `results` SHALL contain one entry per action, in input order, each carrying its `index`.
- Each result SHALL carry `dryRun` reflecting whether the action was actually dispatched.
- If execution is refused by a safety invariant, `ok` SHALL be false and the response SHALL carry
  a machine-readable reason.

## 12. VerificationObservation

After actions are performed, a new observation SHALL be produced as the next planning input.

```json
{
  "schemaVersion": 1,
  "kind": "verificationObservation",
  "call_id": "<echoed>",
  "actionResultRef": "<call_id>",
  "observation": { "kind": "appObservation", "stateHint": "unknown", "capture": { "ok": true, "usableForVision": true } },
  "agentAssessment": { "status": "needs_agent_judgement", "reason": "executor does not decide task success" }
}
```

The embedded `observation` SHALL conform to Section 4. The executor MAY emit
`agentAssessment.status` as `needs_agent_judgement`; the determination of task success belongs to
the Visual Model / Host.

## 13. Diagnostics (Non-Action)

An implementation SHOULD provide read-only diagnostic operations that are not part of the action
loop, for example: locating the desktop GUI Target Window, listing Active Displays, probing capture
usability, and reporting screen-capture permission. These operations MUST NOT dispatch input
events.

## 14. Invariants Summary

1. The executor performs `actions[]` in order; each action declares a `type`.
2. Current desktop GUI coordinates default to `windowTopLeft` unless declared otherwise.
3. State change is proven only by a subsequent observation, never by a result value.
4. High-risk actions (text entry, drag, move, double click, and any send/commit/delete style
   operation) are not Layer 1 default capabilities.
5. Layer 1 carries no surface semantics, no business fields, and no task state.
