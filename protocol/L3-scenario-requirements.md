# L3 - Scenario Requirements Protocol (Template)

- Protocol Layer: 3 (Scenario Requirements)
- Version: 1
- Status: Normative Template
- Depends on: L0 - Operational Surface Contract; L2 - Surface Manual Protocol; L1 - Runtime Capability Manual Protocol
- Key words convention: see Section 1

## Abstract

This document specifies Layer 3 of the visual-agent L0/L1/L2/L3 protocol. Layer 3 is the
Scenario Requirements layer: it turns task-level intents into Layer 1 action plans through the
Layer 2 Surface Manual, and where a task collects data, defines field, normalization,
persistence, and anonymization conventions for that data.

This document is a template: it defines the normative extension points an implementer SHALL fill
in to instantiate Layer 3 for a particular scenario on an L0-qualified Operational Surface. The
current desktop GUI reference runtime expresses an instance as a Scene Manifest consumed by a
manifest-driven engine. That manifest shape is a reference-runtime case, not the whole protocol.

## 1. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in
RFC 2119.

- **Intent**: a named task-level operation requested by the Visual Model / Host (Section 3).
- **Scenario Manifest**: the declarative record that defines a Scenario's Surface Profile and its
  Intent set with their action-step templates (Section 7).
- **Scene Manifest**: the current desktop GUI reference-runtime name for a Scenario Manifest.
- **Surface Manual**: the Layer 2 instance that describes the concrete surface states and safe
  action boundaries this task relies on.
- **Action-Step Template**: a parameterized description of the L1 actions an Intent expands into
  (Section 4).
- **Sample**: a unit of data a data-collecting task persists (Section 5, Section 6).

## 2. Layer Boundary

Layer 3 SHALL consume only the outputs of Layer 2 (the Surface Manual's state classification and
safe target or control selection) and the structured readings produced by the Visual Model / Host.
Layer 3 MUST NOT issue pointer, device, or actuator events directly, and MUST NOT treat coordinate
arithmetic as task logic. It SHALL express operations as Intents that expand into L1 action plans
and are executed through Layer 2 / Layer 1.

## 3. Intent Set Convention (Extension Point E1)

A Layer 3 instance SHALL enumerate its Intents. Each Intent SHALL declare:

1. a unique `intent` name;
2. its required surface-observation parameters (for example coordinates, region, output path);
3. its OPTIONAL parameters and their defaults;
4. the Action-Step Template it expands into (Section 4).

An Intent invocation SHALL be a JSON object carrying at least `intent`. Common envelope fields
`schemaVersion`, `callID`, `dryRun`, and the Surface Profile fields MAY appear on any Intent. In
the current desktop GUI reference runtime, those fields include `bundleID`, `ownerNames`, and
`appLabel`.

## 4. Action-Step Templates (Extension Point E2)

Each Intent SHALL map to an ordered list of Action-Step Templates. Each template SHALL reference
only the L1 action set and SHALL declare which Intent fields substitute into which action fields.
The engine SHALL:

1. resolve each template field from the merged Intent object (Section 6);
2. reject the Intent if a REQUIRED field is missing;
3. emit a single L1 `ActionPlan` whose `actions[]` is the concatenation of the resolved templates;
4. set `kind` to `action_plan` and carry the Surface Profile fields onto the plan.

The produced `actions[]` SHALL be non-empty and every action SHALL carry a `type`.

## 5. Field and Normalization Conventions (Extension Point E3)

For a data-collecting task, a Layer 3 instance SHALL define:

1. the **input field set** the Visual Model / Host provides per reading;
2. a **normalization function** for each field that requires canonicalization, mapping raw values
   to a closed output vocabulary;
3. the **aggregation outputs** computed over collected samples.

Normalization SHALL be deterministic and total: every raw value SHALL map to exactly one output,
including an explicit "unknown / unclassified" output. A non-data-collecting task MAY omit this
section.

## 6. State Persistence and Merge Rules

A Layer 3 engine SHALL support reuse of prior Intent inputs through a persisted state document.
The merge order for producing the effective Intent object SHALL be, from lowest to highest
precedence:

1. Intent defaults declared by the manifest;
2. inherited common fields (the Surface Profile fields are common and SHALL be inheritable across
   Intents);
3. the previous input persisted for the same Intent (surface-observation fields such as
   coordinates, region, and wait duration SHALL be inherited only within the same Intent);
4. the current invocation's fields.

The engine SHALL provide:

- a preview operation that resolves and returns the plan WITHOUT persisting state;
- a plan operation that resolves, returns the plan, AND persists the merged input;
- an execute operation that resolves, persists, and dispatches the plan via Layer 2 / Layer 1;
- a state inspection operation.

Defaults SHALL be treated as fallback only, never as surface fact; coordinates, regions, and
output paths SHALL ultimately originate from the current observation or the current invocation.

## 7. Scenario Manifest (Extension Point E4)

A Layer 3 instance SHALL be expressed as a Scenario Manifest. In the current desktop GUI reference
runtime, this artifact is named a Scene Manifest and SHALL declare the Target Profile and the
Intent set with their Action-Step Templates. A representative shape:

```json
{
  "schemaVersion": 1,
  "scene": "<scene-name>",
  "profile": { "bundleID": "<opaque>", "ownerNames": ["<opaque>"], "appLabel": "<opaque>" },
  "intents": {
    "<intentName>": {
      "required": ["<field>"],
      "defaults": { "<field>": "<value>" },
      "steps": [
        { "type": "<l1-action-type>", "fields": { "<actionField>": "${<intentField>}" } }
      ]
    }
  }
}
```

`${<intentField>}` denotes substitution of a resolved Intent field. Adding a new Scenario SHALL
require only a new manifest; it MUST NOT require new engine source.

## 8. Anonymization Rule (Extension Point E5, Conditional)

If a task persists collected samples, the Layer 3 instance SHALL declare a forbidden-field set of
identity attributes and the engine SHALL reject any sample containing a forbidden field. Persisted
samples SHALL contain only the declared anonymous fields. A task that does not persist
person-related data MAY omit this rule.

## 9. Inheritance / Rewrite Procedure

To instantiate Layer 3 for a new task, an implementer SHALL, in order:

1. Define the Intent set with required and optional parameters (E1, Section 3).
2. Define each Intent's Action-Step Templates over the L1 action set (E2, Section 4).
3. If data is collected, define input fields, normalization, and aggregation outputs
   (E3, Section 5) and the anonymization rule (E5, Section 8).
4. Express all of the above as a Scenario Manifest or current desktop GUI Scene Manifest (E4,
   Section 7).
5. Validate every Intent with the preview operation, asserting a valid, non-empty `action_plan`.

## 10. Invariants

1. Layer 3 expresses operations as Intents expanding into valid L1 action plans; it issues no raw
   input events.
2. Every Intent preview yields `kind:"action_plan"` with a non-empty `actions[]`, each action
   carrying a `type`.
3. Defaults are fallback only; surface-observation parameters come from the current observation.
4. Normalization is deterministic and total with an explicit unknown output.
5. Where samples are persisted, identity fields are rejected and only declared anonymous fields
   are stored.
6. A new task is added by authoring a manifest, not by editing the engine.
7. Scenario requirements inherit surface eligibility from L0 through the L2 Surface Manual.
