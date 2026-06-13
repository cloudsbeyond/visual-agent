# Reference Surface - L2 Surface Manual Instance

This is a worked L2 Surface Manual instance for the desktop GUI reference runtime. It uses a
placeholder target window to demonstrate how an L0-qualified Operational Surface is described for
safe L1 execution.

It is not bound to a real application and does not define the whole visual-agent product boundary.
To create a real desktop GUI reference surface, replace the placeholder profile and the
state/target tables while keeping the L0/L1/L2/L3 boundaries intact.

## L0 Surface Eligibility

This reference surface is intentionally minimal:

| L0 requirement | Reference instance |
|---|---|
| Bounded surface | One desktop GUI target window selected by `profile.json`. |
| Observation frame | `windowTopLeft` coordinates over the current target window. |
| Declared action channel | L1 desktop GUI runtime actions: `click`, `scroll`, `keypress`, `wait`, `screenshot`. |
| Surface manual path | This L2 instance defines states, target/control types, mappings, and verification signals. |
| Scenario path | `manifest.json` defines L3 intents that expand to L1 action plans. |
| Verification expectation | Every meaningful action is checked by the next observation. |
| Safety envelope | Send, commit, delete, transmit, text entry, drag, move, and double click are denied by default. |

## E1 - Desktop GUI Surface Profile

The current desktop GUI reference runtime encodes a Surface Profile as a Target Profile.

`runtimes/desktop-gui/examples/reference-surface/profile.json`:

```json
{ "bundleID": "com.example.placeholder", "ownerNames": ["PlaceholderApp"], "appLabel": "PlaceholderApp" }
```

Run an L2 diagnostic under this profile:

```bash
swift runtimes/desktop-gui/src/scene_runner.swift \
  --profile runtimes/desktop-gui/examples/reference-surface/profile.json diagnose
```

## E2 - Observed States

| State | Visual signature (placeholder) | Permitted actions |
|---|---|---|
| `base` | A primary view with no overlay present. | Open a target element; capture a region. |
| `overlay` | A transient overlay/panel is visible. | Capture the overlay; close it with ESC. |
| `boundary` | A scrollable region has reached its end marker. | Stop scrolling; scroll back. |
| `unobservableWindow` (reserved) | Capture unusable or target window not observable. | Halt; restore observability. |
| `nonTargetWindow` (reserved) | A non-target desktop window was captured. | Halt; recover to the intended surface. |
| `unknown` (reserved) | Cannot classify reliably. | Do not act; re-observe. |

## E3 - Target / Control Types

| Target or control type | Decision condition (placeholder) | Forbidden condition |
|---|---|---|
| `targetElement` | A visible, addressable element in the base view. | Any control that sends, commits, deletes, or transmits. |
| `scrollArea` | An empty area inside a scrollable region. | Input fields; window chrome; off-window points. |
| `overlayBody` | The body of the current overlay. | Overlay action buttons that mutate state. |
| `none` (reserved) | No safe target is present. | Issue no action. |

## E4 - State-To-Plan Mapping

Mappings are expressed as L3 intents in `manifest.json` and expand to valid L1 plans:

| Observed state + target/control | Intent | Success observation | Failure observation |
|---|---|---|---|
| `base` + `targetElement` | `openTarget` / `openTargetCapture` | Overlay appears (`overlay`). | Still `base`; re-locate or skip. |
| `overlay` + `overlayBody` | `captureRegion` | Region image is `usableForVision`. | Capture unusable; re-capture or halt. |
| `overlay` | `closeOverlay` | Return to `base`. | Overlay persists; retry ESC only if still safe. |
| `base`/`overlay` + `scrollArea` | `scrollRegion` | Region content shifts, state unchanged. | No change or boundary reached. |

Coordinates in emitted plans come from the current observation or current invocation, not fixed
row/column formulas.

## E5 - Safety Boundaries

Allow:

- click an addressable element;
- capture a target-window region;
- scroll within a scroll area;
- press ESC to dismiss an overlay.

Deny:

- send, commit, delete, transmit, or mutate remote/persistent state;
- text entry;
- drag, move, and double click unless the L1 runtime is deliberately extended;
- unverified global shortcuts as a recovery path;
- off-surface points.

## Verification

Every action effect is confirmed by the next observation. `ActionResult.ok == true` is only runtime
dispatch/completion evidence; it is never task success.
