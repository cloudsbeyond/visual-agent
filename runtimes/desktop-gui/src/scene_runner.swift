#!/usr/bin/env swift

// L2 - Surface Manual Protocol, desktop GUI profile runner.
// A single wrapper for all desktop GUI reference surfaces: the Surface Profile is supplied by
// `--profile <file>` or by VISUAL_APP_* environment variables, then delegated to the L1 runtime
// capability executor unchanged. No surface or scenario is hardcoded here.
//
// ============================================================================================
// AGENT BINDING BLOCK  (symbolic + formal; read this before editing)
// One-way reference: runtime --> protocols. The state machine / target tables that L2 sections 4-8
// require are authored per surface as DATA + DOCS (see ../examples/reference-surface/), NOT in this file.
// This runner only realizes the profile-binding mechanism (L2 section 3) so one wrapper serves all surfaces.
// --------------------------------------------------------------------------------------------
// binding:
//   layer: L2
//   role: surface-profile-runner   # binds Surface Profile, then delegates to L1 unchanged
//   protocol: ../../../protocol/L2-surface-manual.md
//   l0: ../../../protocol/L0-operational-surface-contract.md
//   overview: ../../../protocol/README.md
//   implements:
//     - { symbol: loadProfile + --profile handling, spec_section: "L2 section 3 Surface Profile Binding (E1)" }
//     - { symbol: process-delegation,               spec_section: "L2 section 2 Layer Boundaries (no L1 re-impl)" }
//   delegates_to: ./action_executor.swift   # L1 executor; resolved as a sibling file
//   externalized_to_surface_data:  # these L2 extension points live in profiles/manifests/docs, not here
//     - "L2 section 4 Observed States (E2)"
//     - "L2 section 5 Target / Control Types (E3)"
//     - "L2 section 6 State-to-Plan Mapping (E4)"
//     - "L2 section 8 Safety Boundaries (E5)"
//   invariants:                    # see L2 section 11
//     - never_reimplement_L1_mechanics      # delegate only
//     - profile_resolution_order: [--profile (highest), VISUAL_APP_* env]
//   risks:
//     - profile_must_resolve_a_reference_window # bundleID/ownerNames must match an on-screen window at runtime
// ============================================================================================

import Foundation

func usage() -> String {
    """
    Usage:
      swift scene_runner.swift [--profile <file>] schema
      swift scene_runner.swift [--profile <file>] run-plan '<action_plan_json>'
      swift scene_runner.swift [--profile <file>] run-plan file:action_plan.json
      swift scene_runner.swift [--profile <file>] run-plan -
      swift scene_runner.swift [--profile <file>] observe [out.png] [maxEdge]
      swift scene_runner.swift [--profile <file>] window
      swift scene_runner.swift [--profile <file>] screens
      swift scene_runner.swift [--profile <file>] diagnose
      swift scene_runner.swift [--profile <file>] capture-permission
      swift scene_runner.swift [--profile <file>] request-capture-permission

    A desktop GUI Surface Profile is currently encoded as a Target Profile JSON object:
      { "bundleID": "<opaque>", "ownerNames": ["<opaque>"], "appLabel": "<opaque>" }

    Resolution order for the desktop GUI Surface Profile:
      1. --profile <file> (highest precedence)
      2. VISUAL_APP_BUNDLE_ID / VISUAL_APP_OWNER_NAMES / VISUAL_APP_LABEL environment
    This runner delegates execution to action_executor.swift (L1) with the profile applied.
    """
}

// @integration section 4 Error Envelope.
// Emit the machine-readable failure shape on stdout so hosts can branch on `reason` without
// parsing free text; the human message still goes to stderr and the process exits non-zero.
func emitError(reason: String, message: String) -> Never {
    let envelope: [String: Any] = ["ok": false, "kind": "error", "reason": reason, "message": message]
    if let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    fputs(message + "\n", stderr)
    exit(1)
}

struct TargetProfile: Decodable {
    let bundleID: String?
    let ownerNames: [String]?
    let appLabel: String?
}

func loadProfile(_ path: String) throws -> TargetProfile {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    guard let data = text.data(using: .utf8) else {
        emitError(reason: "invalid_profile", message: "Invalid profile encoding: \(path)")
    }
    return try JSONDecoder().decode(TargetProfile.self, from: data)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDirectory = scriptURL.deletingLastPathComponent()
let l1ScriptPath = scriptDirectory.appendingPathComponent("action_executor.swift").path

// @integration section 9 Compiled Binary Resolution.
// Prefer a compiled L1 binary at ../bin/action_executor (fast, no per-call recompile, no hard
// `swift` PATH dependency); fall back to interpreting the sibling script. Returns the argv prefix.
func l1Invocation() -> [String] {
    let binary = scriptDirectory.deletingLastPathComponent().appendingPathComponent("bin/action_executor").path
    if FileManager.default.isExecutableFile(atPath: binary) {
        return [binary]
    }
    return ["swift", l1ScriptPath]
}

guard FileManager.default.fileExists(atPath: l1ScriptPath) else {
    emitError(reason: "l1_executor_missing", message: "Missing L1 executor: \(l1ScriptPath)")
}

var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.first == "help" || args.first == "-h" || args.first == "--help" {
    print(usage())
    exit(0)
}

var environment = ProcessInfo.processInfo.environment

// @protocol L2 section 3 Surface Profile Binding (E1).
// Optional --profile <file> consumed here, then translated into VISUAL_APP_* env for the L1
// executor. Precedence: an explicit --profile overrides inherited env (see binding block). Only
// non-empty fields are applied so a partial profile can still layer on top of env.
if let flagIndex = args.firstIndex(of: "--profile") {
    guard flagIndex + 1 < args.count else {
        emitError(reason: "usage_error", message: "--profile requires a file path")
    }
    let profilePath = args[flagIndex + 1]
    do {
        let profile = try loadProfile(profilePath)
        if let bundleID = profile.bundleID, !bundleID.isEmpty {
            environment["VISUAL_APP_BUNDLE_ID"] = bundleID
        }
        if let ownerNames = profile.ownerNames, !ownerNames.isEmpty {
            environment["VISUAL_APP_OWNER_NAMES"] = ownerNames.joined(separator: ",")
        }
        if let appLabel = profile.appLabel, !appLabel.isEmpty {
            environment["VISUAL_APP_LABEL"] = appLabel
        }
    } catch {
        emitError(reason: "invalid_profile", message: "Could not read profile \(profilePath): \(error)")
    }
    args.removeSubrange(flagIndex...(flagIndex + 1))
}

guard !args.isEmpty else {
    print(usage())
    exit(0)
}

// @protocol L2 section 2 Layer Boundaries.
// Delegate the (possibly diagnostic) command to the L1 executor with the bound profile applied via
// environment. L2 MUST NOT reimplement input/capture mechanics; it only forwards. stdout/stderr
// and exit status are passed through transparently so callers see the raw L1 ActionResult.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = l1Invocation() + args
process.environment = environment

let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

do {
    try process.run()
    process.waitUntilExit()
} catch {
    emitError(reason: "l1_spawn_failed", message: "Could not run L1 executor: \(error.localizedDescription)")
}

let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

if let output = String(data: stdoutData, encoding: .utf8), !output.isEmpty {
    print(output, terminator: "")
}
if let errorOutput = String(data: stderrData, encoding: .utf8), !errorOutput.isEmpty {
    fputs(errorOutput, stderr)
}

exit(process.terminationStatus)
