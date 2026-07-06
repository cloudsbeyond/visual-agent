#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const l1Runtime = "runtimes/desktop-gui/src/action_executor.swift";
const l3Runtime = "runtimes/desktop-gui/src/task_flow.swift";
const referenceManifest = "runtimes/desktop-gui/examples/reference-surface/manifest.json";

const checks = [
  {
    name: "ActionPlan",
    schema: "protocol/schemas/action-plan.schema.json",
    valid: ["protocol/fixtures/action-plan.valid.json"],
    invalid: ["protocol/fixtures/action-plan.invalid.json"],
  },
  {
    name: "ActionResult",
    schema: "protocol/schemas/action-result.schema.json",
    valid: ["protocol/fixtures/action-result.valid.json"],
    invalid: ["protocol/fixtures/action-result.invalid.json"],
  },
  {
    name: "ErrorEnvelope",
    schema: "protocol/schemas/error-envelope.schema.json",
    valid: ["protocol/fixtures/error-envelope.valid.json"],
    invalid: ["protocol/fixtures/error-envelope.invalid.json"],
  },
  {
    name: "ScenarioManifest",
    schema: "protocol/schemas/scenario-manifest.schema.json",
    valid: [
      "protocol/fixtures/scenario-manifest.valid.json",
      referenceManifest,
    ],
    invalid: ["protocol/fixtures/scenario-manifest.invalid.json"],
  },
];

const runtimeErrorCases = [
  {
    name: "reserved_action",
    argv: [
      "swift",
      l1Runtime,
      "run-plan",
      JSON.stringify({
        schemaVersion: 1,
        kind: "action_plan",
        call_id: "conformance_reserved_action",
        dryRun: true,
        actions: [{ type: "type" }],
      }),
    ],
    reason: "reserved_action",
  },
  {
    name: "pending_safety_approval",
    argv: [
      "swift",
      l1Runtime,
      "run-plan",
      JSON.stringify({
        schemaVersion: 1,
        kind: "action_plan",
        call_id: "conformance_pending_safety",
        dryRun: false,
        pending_safety_checks: [{ id: "c1", code: "confirm", message: "needs approval" }],
        actions: [{ type: "keypress", keys: ["ESC"] }],
      }),
    ],
    reason: "pending_safety_approval",
  },
  {
    name: "missing_required_field",
    argv: [
      "swift",
      l3Runtime,
      "--manifest",
      referenceManifest,
      "preview-json",
      JSON.stringify({ intent: "openTarget", dryRun: true }),
    ],
    reason: "missing_required_field",
  },
  {
    name: "unsupported_intent",
    argv: [
      "swift",
      l3Runtime,
      "--manifest",
      referenceManifest,
      "preview-json",
      JSON.stringify({ intent: "noSuchIntent", dryRun: true }),
    ],
    reason: "unsupported_intent",
  },
];

function readJSON(relativePath) {
  return JSON.parse(readFileSync(path.join(repoRoot, relativePath), "utf8"));
}

function typeOf(value) {
  if (Array.isArray(value)) return "array";
  if (value === null) return "null";
  if (Number.isInteger(value)) return "integer";
  return typeof value;
}

function typeMatches(expected, value) {
  const actual = typeOf(value);
  if (expected === "number") return actual === "number" || actual === "integer";
  return actual === expected;
}

function sameJSON(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function resolveRef(root, ref) {
  if (!ref.startsWith("#/")) throw new Error(`only local refs are supported: ${ref}`);
  return ref
    .slice(2)
    .split("/")
    .reduce((node, part) => {
      if (!node || typeof node !== "object" || !(part in node)) {
        throw new Error(`unresolvable schema ref: ${ref}`);
      }
      return node[part];
    }, root);
}

function validate(schema, value, root = schema, at = "$") {
  const errors = [];

  if (schema.$ref) {
    return validate(resolveRef(root, schema.$ref), value, root, at);
  }

  if ("const" in schema && !sameJSON(value, schema.const)) {
    errors.push(`${at}: expected const ${JSON.stringify(schema.const)}`);
  }

  if (schema.enum && !schema.enum.some((item) => sameJSON(value, item))) {
    errors.push(`${at}: expected one of ${schema.enum.map((item) => JSON.stringify(item)).join(", ")}`);
  }

  if (schema.type && !typeMatches(schema.type, value)) {
    errors.push(`${at}: expected type ${schema.type}, got ${typeOf(value)}`);
    return errors;
  }

  if (schema.type === "string" || typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) {
      errors.push(`${at}: expected string length >= ${schema.minLength}`);
    }
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
      errors.push(`${at}: expected string to match /${schema.pattern}/`);
    }
  }

  if ((schema.type === "number" || schema.type === "integer") && typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${at}: expected number >= ${schema.minimum}`);
    }
  }

  if (schema.type === "array" || Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${at}: expected array length >= ${schema.minItems}`);
    }
    if (schema.items) {
      value.forEach((item, index) => {
        errors.push(...validate(schema.items, item, root, `${at}[${index}]`));
      });
    }
  }

  if ((schema.type === "object" || (value && typeof value === "object" && !Array.isArray(value))) && value !== null && !Array.isArray(value)) {
    for (const field of schema.required ?? []) {
      if (!(field in value)) errors.push(`${at}: missing required field ${field}`);
    }

    const properties = schema.properties ?? {};
    for (const [field, childSchema] of Object.entries(properties)) {
      if (field in value) {
        errors.push(...validate(childSchema, value[field], root, `${at}.${field}`));
      }
    }

    const keys = Object.keys(value);
    if (schema.minProperties !== undefined && keys.length < schema.minProperties) {
      errors.push(`${at}: expected at least ${schema.minProperties} properties`);
    }

    if (schema.additionalProperties !== undefined) {
      const extras = keys.filter((key) => !(key in properties));
      if (schema.additionalProperties === false && extras.length > 0) {
        errors.push(`${at}: unexpected properties ${extras.join(", ")}`);
      } else if (typeof schema.additionalProperties === "object") {
        for (const key of extras) {
          errors.push(...validate(schema.additionalProperties, value[key], root, `${at}.${key}`));
        }
      }
    }
  }

  return errors;
}

let failures = 0;

for (const check of checks) {
  const schema = readJSON(check.schema);

  for (const fixture of check.valid) {
    const errors = validate(schema, readJSON(fixture));
    if (errors.length > 0) {
      failures += 1;
      console.error(`FAIL valid ${check.name}: ${fixture}`);
      for (const error of errors) console.error(`  ${error}`);
    } else {
      console.log(`OK valid ${check.name}: ${fixture}`);
    }
  }

  for (const fixture of check.invalid) {
    const errors = validate(schema, readJSON(fixture));
    if (errors.length === 0) {
      failures += 1;
      console.error(`FAIL invalid ${check.name}: ${fixture} unexpectedly passed`);
    } else {
      console.log(`OK invalid ${check.name}: ${fixture}`);
    }
  }
}

const errorEnvelopeSchema = readJSON("protocol/schemas/error-envelope.schema.json");

for (const runtimeCase of runtimeErrorCases) {
  const result = spawnSync("/usr/bin/env", runtimeCase.argv, {
    cwd: repoRoot,
    encoding: "utf8",
  });

  if (result.error) {
    failures += 1;
    console.error(`FAIL runtime ${runtimeCase.name}: ${result.error.message}`);
    continue;
  }

  let parsed;
  try {
    parsed = JSON.parse((result.stdout || "").trim());
  } catch (error) {
    failures += 1;
    console.error(`FAIL runtime ${runtimeCase.name}: stdout was not JSON`);
    if (result.stdout) console.error(`  stdout: ${result.stdout.trim()}`);
    if (result.stderr) console.error(`  stderr: ${result.stderr.trim()}`);
    continue;
  }

  const errors = validate(errorEnvelopeSchema, parsed);
  if (errors.length > 0) {
    failures += 1;
    console.error(`FAIL runtime ${runtimeCase.name}: output did not match ErrorEnvelope`);
    for (const error of errors) console.error(`  ${error}`);
    continue;
  }

  if (parsed.reason !== runtimeCase.reason) {
    failures += 1;
    console.error(`FAIL runtime ${runtimeCase.name}: expected reason ${runtimeCase.reason}, got ${parsed.reason}`);
  } else {
    console.log(`OK runtime ${runtimeCase.name}: reason=${parsed.reason}`);
  }
}

if (failures > 0) process.exit(1);
console.log("PROTOCOL_CONFORMANCE_OK");
