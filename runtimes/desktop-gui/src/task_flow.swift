#!/usr/bin/env swift

// L3 - Scenario Requirements Protocol, manifest-driven engine.
// A single engine for all desktop GUI reference scenarios: the current Scene Manifest artifact
// declares the Surface Profile shape and the Intent set with their action-step templates. This
// engine resolves intent fields, substitutes them into templates, and emits a valid L1 ActionPlan.
// Adding a scenario requires a new manifest, not new generic runtime code.
//
// ============================================================================================
// AGENT BINDING BLOCK  (symbolic + formal; read this before editing)
// One-way reference: runtime --> protocols. This engine is generic; per-scenario behavior is DATA
// (the manifest), per L3 section 7. Do not encode any specific scenario's intents here.
// --------------------------------------------------------------------------------------------
// binding:
//   layer: L3
//   role: scenario-requirements-engine # expands manifest intents into L1 ActionPlans; never emits raw input
//   protocol: ../../../protocol/L3-scenario-requirements.md
//   l0: ../../../protocol/L0-operational-surface-contract.md
//   overview: ../../../protocol/README.md
//   implements:
//     - { symbol: loadManifest,            spec_section: "L3 section 7 Scenario Manifest (E4)" }
//     - { symbol: resolvedIntentFields,    spec_section: "L3 section 6 State Persistence and Merge Rules" }
//     - { symbol: "substitute/buildActions", spec_section: "L3 section 4 Action-Step Templates (E2)" }
//     - { symbol: actionPlan,              spec_section: "L3 section 3 Intent Set, section 10 Invariants" }
//     - { symbol: executePlan,             spec_section: "L3 section 2 Layer Boundary (delegate, no raw events)" }
//   delegates_to: ./action_executor.swift  # L1 executor; resolved as a sibling file
//   not_implemented_here:          # conditional L3 extension points realized by the scenario, not the engine
//     - "L3 section 5 Field/Normalization Conventions (E3)"   # data-collecting scenarios add their own tooling
//     - "L3 section 8 Anonymization Rule (E5)"                 # data-collecting scenarios enforce their own reject-list
//   invariants:                    # see L3 section 10
//     - intents_expand_to_valid_action_plan   # non-empty actions[], each with a type
//     - defaults_are_fallback_only            # surface-observation fields come from the current invocation
//     - merge_order: [manifest_defaults, profile_common, persisted_common, prev_same_intent, current]  # L3 section 6
//     - new_scenario_is_a_manifest_not_code
//   risks:
//     - substitution_is_exact_token_only      # only a whole "${field}" string is substituted (see `substitute`)
//     - missing_required_field_rejects_intent # required[] enforced before plan emission
// ============================================================================================

import Foundation

enum FlowError: Error, CustomStringConvertible {
    case usage(String)
    case invalidJSON(String)
    case manifest(String)

    var description: String {
        switch self {
        case .usage(let text): return text
        case .invalidJSON(let text): return "Invalid JSON: \(text)"
        case .manifest(let text): return "Manifest error: \(text)"
        }
    }

    // @integration section 4 Error Envelope.
    // Stable machine-readable reason code per failure class so hosts can branch without parsing
    // free text. usage errors are refined by a few well-known phrases (unknown intent, missing
    // required field, no manifest), defaulting to a generic usage code.
    var reasonCode: String {
        switch self {
        case .invalidJSON:
            return "invalid_json"
        case .manifest:
            return "invalid_manifest"
        case .usage(let text):
            let lower = text.lowercased()
            if lower.contains("unsupported intent") {
                return "unsupported_intent"
            }
            if lower.contains("missing required field") {
                return "missing_required_field"
            }
            if lower.contains("no manifest") || lower.contains("--manifest") {
                return "manifest_required"
            }
            return "usage_error"
        }
    }
}

// @integration section 4 Error Envelope.
// The single machine-readable failure shape emitted on stdout by this engine's failure path.
func errorEnvelope(reason: String, message: String) -> [String: Any] {
    ["ok": false, "kind": "error", "reason": reason, "message": message]
}

func usage() -> String {
    """
    Usage:
      swift task_flow.swift --manifest <file> schema
      swift task_flow.swift --manifest <file> intents
      swift task_flow.swift --manifest <file> tools-schema
      swift task_flow.swift --manifest <file> [--state <path>] state
      swift task_flow.swift --manifest <file> [--state <path>] preview-json '<intent-json>'
      swift task_flow.swift --manifest <file> [--state <path>] plan-json '<intent-json>'
      swift task_flow.swift --manifest <file> [--state <path>] plan-json file:intent.json
      swift task_flow.swift --manifest <file> [--state <path>] execute-json '<intent-json>'

    The manifest path may also be provided by the SCENE_MANIFEST environment variable.
    --state <path> selects a per-session state file (overrides TASK_FLOW_STATE env and the default).

    Intent invocation is a JSON object carrying at least { "intent": "<name>" } plus any
    surface-observation fields. preview-json resolves without persisting; plan-json resolves and
    persists; execute-json resolves, persists, and dispatches through the L1 executor.
    tools-schema emits JSON-Schema tool definitions (one per intent) for host tool/function calling.
    """
}

// MARK: - JSON helpers

func parseJSONObject(_ payload: String) throws -> [String: Any] {
    guard let data = payload.data(using: .utf8) else { throw FlowError.invalidJSON("not utf8") }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw FlowError.invalidJSON("expected object")
    }
    return object
}

func readPayload(_ arg: String) throws -> String {
    if arg == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FlowError.usage("No JSON received on stdin")
        }
        return text
    }
    if arg.hasPrefix("file:") { return try String(contentsOfFile: String(arg.dropFirst("file:".count)), encoding: .utf8) }
    if arg.hasPrefix("@") { return try String(contentsOfFile: String(arg.dropFirst()), encoding: .utf8) }
    return arg
}

func encodeJSON(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard let text = String(data: data, encoding: .utf8) else { throw FlowError.invalidJSON("could not encode") }
    return text
}

func printJSON(_ object: [String: Any]) throws { print(try encodeJSON(object)) }

// MARK: - Manifest

struct Manifest {
    let scene: String
    let profile: [String: Any]
    let intents: [String: [String: Any]]
    let raw: [String: Any]
}

// @protocol L3 section 7 Scenario Manifest (E4).
// Parses the current desktop GUI manifest artifact:
// { scene, profile, intents{ name -> {required, defaults, steps} } }.
// This is the ONLY scenario-specific input the engine takes; everything below operates generically.
func loadManifest(_ path: String) throws -> Manifest {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let object = try parseJSONObject(text)
    let scene = object["scene"] as? String ?? "scene"
    let profile = object["profile"] as? [String: Any] ?? [:]
    guard let intents = object["intents"] as? [String: Any] else {
        throw FlowError.manifest("missing object field: intents")
    }
    var typed: [String: [String: Any]] = [:]
    for (name, value) in intents {
        guard let intentObject = value as? [String: Any] else {
            throw FlowError.manifest("intent \(name) must be an object")
        }
        typed[name] = intentObject
    }
    return Manifest(scene: scene, profile: profile, intents: typed, raw: object)
}

let profileKeys: Set<String> = ["bundleID", "ownerNames", "appLabel"]

// MARK: - State

// @integration section 5 Session-Isolated State.
// Set from the optional --state <path> flag (parsed in main). When present it takes precedence
// over the TASK_FLOW_STATE env and the default global file, so a host can give each concurrent
// session its own state file and avoid cross-talk.
var stateOverride: String?

// @integration section 5 Session-Isolated State.
// Resolution order (highest first): --state <path>  >  TASK_FLOW_STATE env  >  default global file.
func statePath(for scene: String) -> String {
    if let stateOverride, !stateOverride.isEmpty {
        return stateOverride
    }
    return ProcessInfo.processInfo.environment["TASK_FLOW_STATE"] ?? "out/task-flow-state.\(scene).json"
}

func loadState(_ scene: String) -> [String: Any] {
    let path = statePath(for: scene)
    guard FileManager.default.fileExists(atPath: path),
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return [:]
    }
    return object
}

func saveState(_ state: [String: Any], scene: String) throws {
    let url = URL(fileURLWithPath: statePath(for: scene))
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

// MARK: - Field resolution (merge order per L3 section 6)

// @protocol L3 section 6 State Persistence and Merge Rules.
// Builds the effective intent object by layering, lowest-to-highest precedence:
//   1) manifest intent defaults  2) manifest profile (common)  3) persisted common
//   4) previous input for the SAME intent  5) the current invocation (wins).
// `persist:true` (plan/execute) writes the merged result back; `persist:false` (preview) does not.
// Required fields are enforced here, before any plan is emitted.
func resolvedIntentFields(invocation: [String: Any], manifest: Manifest, intentName: String, persist: Bool) throws -> [String: Any] {
    guard let intentDef = manifest.intents[intentName] else {
        throw FlowError.usage("Unsupported intent: \(intentName)")
    }

    var state = loadState(manifest.scene)
    let storedIntents = state["intents"] as? [String: Any] ?? [:]
    let storedCommon = state["common"] as? [String: Any] ?? [:]
    let previous = storedIntents[intentName] as? [String: Any] ?? [:]

    var merged: [String: Any] = [:]
    // 1. manifest intent defaults
    if let defaults = intentDef["defaults"] as? [String: Any] {
        for (k, v) in defaults { merged[k] = v }
    }
    // 1b. profile defaults from manifest (common, inheritable)
    for (k, v) in manifest.profile where profileKeys.contains(k) { merged[k] = v }
    // 2. inherited common fields persisted previously
    for (k, v) in storedCommon where profileKeys.contains(k) { merged[k] = v }
    // 3. previous input for the same intent
    for (k, v) in previous { merged[k] = v }
    // 4. current invocation
    for (k, v) in invocation { merged[k] = v }

    merged["intent"] = intentName

    // required field check
    if let required = intentDef["required"] as? [String] {
        for field in required where merged[field] == nil {
            throw FlowError.usage("Missing required field: \(field)")
        }
    }

    if persist {
        var updatedIntents = storedIntents
        updatedIntents[intentName] = merged
        state["intents"] = updatedIntents
        var updatedCommon = storedCommon
        for (k, v) in merged where profileKeys.contains(k) { updatedCommon[k] = v }
        state["common"] = updatedCommon
        state["scene"] = manifest.scene
        state["lastIntent"] = intentName
        try saveState(state, scene: manifest.scene)
    }

    return merged
}

// MARK: - Substitution

// @protocol L3 section 4 Action-Step Templates (E2).
// Exact-token substitution only: a value that is precisely "${field}" is replaced by the resolved
// field, preserving its JSON type (number stays number, array stays array). Any other value passes
// through literally. This deliberate narrowness keeps templates unambiguous and type-safe.
func substitute(_ value: Any, fields: [String: Any]) throws -> Any {
    if let token = value as? String,
       token.hasPrefix("${"), token.hasSuffix("}") {
        let name = String(token.dropFirst(2).dropLast(1))
        guard let resolved = fields[name] else {
            throw FlowError.usage("Missing required field: \(name)")
        }
        return resolved
    }
    return value
}

// @protocol L3 section 4 Action-Step Templates (E2).
// Expands an intent's `steps` into concrete L1 actions. Each step yields one action carrying its
// declared `type` plus substituted fields. The produced actions reference only the L1 action set;
// the engine does not validate L1 semantics - L1 (action_executor) is the authority on section 6.
func buildActions(intentDef: [String: Any], fields: [String: Any]) throws -> [[String: Any]] {
    guard let steps = intentDef["steps"] as? [[String: Any]] else {
        throw FlowError.manifest("intent has no steps array")
    }
    var actions: [[String: Any]] = []
    for step in steps {
        guard let type = step["type"] as? String, !type.isEmpty else {
            throw FlowError.manifest("step missing type")
        }
        var action: [String: Any] = ["type": type]
        if let stepFields = step["fields"] as? [String: Any] {
            for (key, raw) in stepFields {
                action[key] = try substitute(raw, fields: fields)
            }
        }
        actions.append(action)
    }
    return actions
}

// @protocol L3 section 3 Intent Set, section 10 Invariants; emits an L1 section 5 ActionPlan.
// Assembles the final, valid L1 ActionPlan: a non-empty actions[] plus the carried Surface Profile
// fields and plan envelope. Enforces the section 10 invariant that an intent expands to a non-empty plan.
func actionPlan(manifest: Manifest, intentName: String, fields: [String: Any]) throws -> [String: Any] {
    guard let intentDef = manifest.intents[intentName] else {
        throw FlowError.usage("Unsupported intent: \(intentName)")
    }
    let actions = try buildActions(intentDef: intentDef, fields: fields)
    guard !actions.isEmpty else { throw FlowError.manifest("intent \(intentName) produced empty actions") }

    var plan: [String: Any] = [
        "schemaVersion": 1,
        "kind": "action_plan",
        "wireFormat": "openai_computer_call_compatible",
        "call_id": fields["callID"] as? String ?? "\(manifest.scene)_\(intentName)",
        "pending_safety_checks": [],
        "confirmationStatus": "not_required",
        "dryRun": fields["dryRun"] as? Bool ?? false,
        "allowNegativeWindowOrigin": fields["allowNegativeWindowOrigin"] as? Bool ?? false,
        "actions": actions
    ]
    if let bundleID = fields["bundleID"] as? String { plan["bundleID"] = bundleID }
    if let ownerNames = fields["ownerNames"] as? [String] { plan["ownerNames"] = ownerNames }
    if let appLabel = fields["appLabel"] as? String { plan["appLabel"] = appLabel }
    return plan
}

// MARK: - Tool-calling schema (Tier 1)

// @integration section 6 Tool-Calling Schema.
// Infers a JSON-Schema primitive type from a manifest default value. Falls back to "string" for
// anything unrecognized; hosts can refine via an optional per-intent `paramTypes` map.
func jsonSchemaType(for value: Any) -> String {
    switch value {
    case is Bool: return "boolean"
    case is Int, is Double: return "number"
    case is [Any]: return "array"
    case is [String: Any]: return "object"
    default: return "string"
    }
}

// @integration section 6 Tool-Calling Schema.
// Converts one manifest intent into a JSON-Schema tool definition: name=intent, description from
// the optional manifest `description`, parameters derived from `required` (+ type hints) and
// `defaults` (type inferred from the default value, unless overridden by `paramTypes`). This lets
// a host expose each intent as a function/tool at its own boundary; the framework makes no model call.
func toolDefinition(intentName: String, intentDef: [String: Any]) -> [String: Any] {
    let required = intentDef["required"] as? [String] ?? []
    let defaults = intentDef["defaults"] as? [String: Any] ?? [:]
    let paramTypes = intentDef["paramTypes"] as? [String: String] ?? [:]
    let description = intentDef["description"] as? String ?? "Scenario intent: \(intentName)"

    var properties: [String: Any] = [:]
    // Required fields first (type from paramTypes hint, else string).
    for field in required {
        properties[field] = ["type": paramTypes[field] ?? "string"]
    }
    // Optional fields: those declared via defaults, type inferred unless hinted.
    for (field, value) in defaults where properties[field] == nil {
        properties[field] = ["type": paramTypes[field] ?? jsonSchemaType(for: value)]
    }

    return [
        "name": intentName,
        "description": description,
        "parameters": [
            "type": "object",
            "properties": properties,
            "required": required
        ]
    ]
}

// @integration section 6 Tool-Calling Schema.
// Emits { tools: [ toolDefinition... ] } across all manifest intents (name-sorted for stability).
func toolsSchema(manifest: Manifest) -> [String: Any] {
    let tools = manifest.intents.keys.sorted().map { name in
        toolDefinition(intentName: name, intentDef: manifest.intents[name] ?? [:])
    }
    return ["schemaVersion": 1, "scene": manifest.scene, "tools": tools]
}

// MARK: - Execute via L1

// @integration section 9 Compiled Binary Resolution.
// Resolve how to invoke the L1 executor. Prefer a compiled binary at ../bin/action_executor
// (fast, no per-call recompile, no hard dependency on `swift` in PATH); fall back to interpreting
// the sibling action_executor.swift so the framework still runs with zero build.
// Returns the argv prefix to run, e.g. ["/path/bin/action_executor"] or ["swift", "/path/...swift"].
func l1ExecutorInvocation() -> [String] {
    let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let binary = dir.deletingLastPathComponent().appendingPathComponent("bin/action_executor").path
    if FileManager.default.isExecutableFile(atPath: binary) {
        return [binary]
    }
    let script = dir.appendingPathComponent("action_executor.swift").path
    return ["swift", script]
}

// @protocol L3 section 2 Layer Boundary.
// The execute path: hand the assembled ActionPlan to the L1 executor as a sibling subprocess.
// L3 never posts raw input events itself - it only produces plans and delegates, so all dispatch
// and safety gating happen in L1 (action_executor). Output and exit status pass through.
func executePlan(_ plan: [String: Any]) throws {
    let json = try encodeJSON(plan)
    let invocation = l1ExecutorInvocation()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = invocation + ["run-plan", json]
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    process.waitUntilExit()
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: stdoutData, encoding: .utf8), !output.isEmpty { print(output, terminator: "") }
    if let errorOutput = String(data: stderrData, encoding: .utf8), !errorOutput.isEmpty { fputs(errorOutput, stderr) }
    if process.terminationStatus != 0 { exit(process.terminationStatus) }
}

// MARK: - Commands

func intentNameOf(_ payload: String) throws -> (String, [String: Any]) {
    let object = try parseJSONObject(payload)
    guard let intent = object["intent"] as? String, !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw FlowError.usage("Missing required field: intent")
    }
    return (intent, object)
}

func main() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    if args.first == "help" || args.first == "-h" || args.first == "--help" {
        print(usage())
        return
    }

    var manifestPath = ProcessInfo.processInfo.environment["SCENE_MANIFEST"]
    if let flagIndex = args.firstIndex(of: "--manifest") {
        guard flagIndex + 1 < args.count else { throw FlowError.usage("--manifest requires a file path") }
        manifestPath = args[flagIndex + 1]
        args.removeSubrange(flagIndex...(flagIndex + 1))
    }

    // @integration section 5 Session-Isolated State.
    // Optional --state <path> selects a per-session state file (overrides env/default). A host
    // SHOULD pass a unique path per concurrent session so persisted intent inputs never collide.
    if let flagIndex = args.firstIndex(of: "--state") {
        guard flagIndex + 1 < args.count else { throw FlowError.usage("--state requires a file path") }
        stateOverride = args[flagIndex + 1]
        args.removeSubrange(flagIndex...(flagIndex + 1))
    }

    guard let command = args.first else { throw FlowError.usage(usage()) }
    guard let manifestPath else { throw FlowError.usage("No manifest. Pass --manifest <file> or set SCENE_MANIFEST.") }
    let manifest = try loadManifest(manifestPath)

    switch command {
    case "schema":
        try printJSON([
            "schemaVersion": 1,
            "scene": manifest.scene,
            "profile": manifest.profile,
            "intents": Array(manifest.intents.keys).sorted()
        ])
    case "intents":
        try printJSON(["ok": true, "scene": manifest.scene, "intents": Array(manifest.intents.keys).sorted()])
    case "tools-schema":
        // @integration section 6 Tool-Calling Schema.
        try printJSON(toolsSchema(manifest: manifest))
    case "state":
        var state = loadState(manifest.scene)
        if state.isEmpty {
            state = ["common": manifest.profile.filter { profileKeys.contains($0.key) }, "intents": [:], "lastIntent": NSNull()]
        }
        try printJSON(["ok": true, "statePath": statePath(for: manifest.scene), "state": state])
    case "preview-json":
        guard args.count == 2 else { throw FlowError.usage(usage()) }
        let (intentName, invocation) = try intentNameOf(try readPayload(args[1]))
        let fields = try resolvedIntentFields(invocation: invocation, manifest: manifest, intentName: intentName, persist: false)
        try printJSON(actionPlan(manifest: manifest, intentName: intentName, fields: fields))
    case "plan-json":
        guard args.count == 2 else { throw FlowError.usage(usage()) }
        let (intentName, invocation) = try intentNameOf(try readPayload(args[1]))
        let fields = try resolvedIntentFields(invocation: invocation, manifest: manifest, intentName: intentName, persist: true)
        try printJSON(actionPlan(manifest: manifest, intentName: intentName, fields: fields))
    case "execute-json":
        guard args.count == 2 else { throw FlowError.usage(usage()) }
        let (intentName, invocation) = try intentNameOf(try readPayload(args[1]))
        let fields = try resolvedIntentFields(invocation: invocation, manifest: manifest, intentName: intentName, persist: true)
        try executePlan(actionPlan(manifest: manifest, intentName: intentName, fields: fields))
    default:
        throw FlowError.usage(usage())
    }
}

// @integration section 4 Error Envelope.
// Top-level failure path: machine-readable envelope on stdout (hosts) + human message on stderr,
// non-zero exit. FlowError carries a stable reason code; anything else is "internal_error".
do {
    try main()
} catch let error as FlowError {
    try? printJSON(errorEnvelope(reason: error.reasonCode, message: error.description))
    fputs("\(error)\n", stderr)
    exit(1)
} catch {
    try? printJSON(errorEnvelope(reason: "internal_error", message: "\(error)"))
    fputs("\(error)\n", stderr)
    exit(1)
}
