# Reference Surface - L3 Scenario Requirements Instance

This is a worked L3 Scenario Requirements instance for the desktop GUI reference runtime. It is
expressed as the current runtime artifact name, a Scene Manifest (`manifest.json`), consumed by
`task_flow.swift`.

The placeholder target demonstrates the inheritance procedure only. It does not define a real app
workflow and does not change the visual-agent product boundary.

## E1 - Intent Set

| Intent | Required fields | Optional defaults |
|---|---|---|
| `openTarget` | `x`, `y` | `mode=cliclick`, `coordinateSpace=windowTopLeft`, `restoreMouse=true` |
| `openTargetCapture` | `x`, `y`, `output` | `mode=hid`, `durationMs=300`, `maxEdge=760` |
| `captureRegion` | `x`, `y`, `width`, `height`, `output` | `maxEdge=640` |
| `scrollRegion` | `x`, `y`, `scrollY` | `mode=hid` |
| `closeOverlay` | none | `mode=hid` |

Intent fields such as coordinates and regions are surface-observation parameters. They must come
from the current observation or current invocation, not from reused fixed screen coordinates.

## E2 - Action-Step Templates

Declared in `manifest.json` under each intent's `steps`. Fields of the form `${name}` substitute
the resolved intent field. Each step references only the L1 action set:

- `click`
- `wait`
- `screenshot`
- `scroll`
- `keypress`

The produced plan must be a valid L1 `ActionPlan` with a non-empty `actions[]`.

## E3 / E5 - Data Conventions

This reference scenario performs UI operations only and persists no person-related samples, so the
field/normalization conventions (E3) and anonymization rule (E5) are intentionally omitted. A
data-collecting scenario MUST add them per the L3 template.

## Run

Preview a plan without persisting state:

```bash
swift runtimes/desktop-gui/src/task_flow.swift \
  --manifest runtimes/desktop-gui/examples/reference-surface/manifest.json \
  preview-json '{"intent":"openTargetCapture","x":480,"y":120,"output":"out/reference-capture.png","dryRun":true}'
```

List intents declared by the manifest:

```bash
swift runtimes/desktop-gui/src/task_flow.swift \
  --manifest runtimes/desktop-gui/examples/reference-surface/manifest.json intents
```

Execute through L1. This example uses `dryRun:true`; a real dispatch requires a live eligible
target window and permissions:

```bash
swift runtimes/desktop-gui/src/task_flow.swift \
  --manifest runtimes/desktop-gui/examples/reference-surface/manifest.json \
  execute-json '{"intent":"closeOverlay","dryRun":true}'
```

## Inheritance Procedure

1. Confirm the new target is an L0-qualified Operational Surface.
2. Copy this reference surface directory.
3. Replace `profile.json` with the real desktop GUI Surface Profile shape (`bundleID`,
   `ownerNames`, `appLabel`).
4. Edit `manifest.json`: rename intents, set required fields, and adjust step templates.
5. Update the L2 Surface Manual instance with states, target/control types, mappings, safety, and
   verification rules.
6. If collecting data, add field/normalization/aggregation rules and the anonymization rule.
7. Validate every intent with `preview-json`, asserting a non-empty `action_plan`.

No generic runtime source file should change for a new reference surface unless the protocol itself
adds a new runtime capability.
