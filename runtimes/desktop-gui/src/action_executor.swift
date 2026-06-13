#!/usr/bin/env swift

// L1 - Runtime Capability Manual, desktop GUI reference executor.
// Surface-agnostic at the L1 boundary: carries no surface semantics, no business fields, no task state.
// The current desktop GUI Target Application binding is supplied by configuration
// (VISUAL_APP_* environment or ActionPlan fields).
//
// ============================================================================================
// AGENT BINDING BLOCK  (symbolic + formal; read this before editing)
// This block is the machine-facing contract. Prose comments below are the human/agent-facing
// rationale. References point ONE WAY only: runtime --> protocols (never edit protocols to match
// code; edit code to match protocols).
// --------------------------------------------------------------------------------------------
// binding:
//   layer: L1
//   role: runtime-capability-executor # performs ActionPlan.actions[]; emits ActionResult; no judgement
//   protocol: ../../../protocol/L1-runtime-capability-manual.md
//   l0: ../../../protocol/L0-operational-surface-contract.md
//   overview: ../../../protocol/README.md
//   implements:
//     - { symbol: TargetApp,                 spec_section: "L1 section 3 Desktop GUI Target Binding" }
//     - { symbol: appObservation,            spec_section: "L1 section 4 AppObservation (desktop GUI reference)" }
//     - { symbol: JSONActionPlan/runPlan,    spec_section: "L1 section 5 ActionPlan, section 11 ActionResult" }
//     - { symbol: executeAction,             spec_section: "L1 section 6 Action Set" }
//     - { symbol: eventPoint,                spec_section: "L1 section 7 Coordinate Spaces" }
//     - { symbol: ensurePointerSafe/runPlan, spec_section: "L1 section 8 Safety Invariants" }
//     - { symbol: postMouseSequence/postEsc/postScroll, spec_section: "L1 section 9 Backends" }
//     - { symbol: visualStats/imageUsableForVision/captureTargetWindowImage, spec_section: "L1 section 10 Capture Usability" }
//     - { symbol: "diagnose/observe/window/screens", spec_section: "L1 section 13 Diagnostics" }
//   invariants:                     # see L1 section 14; violating these breaks the protocol
//     - actions_executed_in_order
//     - coordinates_default_windowTopLeft
//     - state_change_proven_only_by_next_observation   # ok:true means "dispatched", not "succeeded"
//     - reserved_actions_rejected: [type, drag, move, double_click]   # L1 section 6.3
//     - no_surface_semantics_in_this_layer
//   risks:
//     - capture_success_is_not_vision_usable     # L1 section 10; always gate on usableForVision
//     - negative_origin_is_not_an_error          # L1 section 8; judge by active-display containment
//     - countermeasure_targets_may_be_infeasible # L1 section 10; assess feasibility before relying on L1
// ============================================================================================

import Cocoa
import Darwin
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct WindowBounds {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let windowID: CGWindowID
}

struct CapturedWindowImage {
    let image: CGImage
    let backend: String
    let fallbackErrors: [String]
}

struct DisplayInfo {
    let displayID: CGDirectDisplayID
    let bounds: CGRect
    let isMain: Bool
}

enum ActionError: Error, CustomStringConvertible {
    case usage(String)
    case windowNotFound

    var description: String {
        switch self {
        case .usage(let text):
            return text
        case .windowNotFound:
            return "Desktop GUI target window not found"
        }
    }

    // @integration section 4 Error Envelope.
    // Maps an internal error to a stable, machine-readable reason code so hosts can branch on
    // failure cause without parsing free text. windowNotFound is explicit; usage errors are
    // classified by a few well-known phrases, defaulting to a generic usage code.
    var reasonCode: String {
        switch self {
        case .windowNotFound:
            return "window_not_found"
        case .usage(let text):
            let lower = text.lowercased()
            if lower.contains("screen recording") || lower.contains("screen_capture_permission") {
                return "screen_capture_permission_required"
            }
            if lower.contains("reserved action") {
                return "reserved_action"
            }
            if lower.contains("missing required field") {
                return "missing_required_field"
            }
            if lower.contains("refusing pointer action") {
                return "pointer_action_unsafe"
            }
            if lower.contains("unsupported") {
                return "unsupported_request"
            }
            return "usage_error"
        }
    }
}

// @integration section 4 Error Envelope.
// The single machine-readable failure shape emitted on stdout by every runtime entry point.
// stderr still carries the human message and the process still exits non-zero, but hosts parse
// this object: { ok:false, kind:"error", reason:<code>, message:<text> }.
func errorEnvelope(reason: String, message: String) -> [String: Any] {
    ["ok": false, "kind": "error", "reason": reason, "message": message]
}

// @protocol L1 section 3 Desktop GUI Target Binding.
// The desktop GUI reference target is configuration, never inferred by the executor. At least one
// of bundleID / ownerNames must resolve a window; appLabel is only a human-readable echo. Layer 1
// attaches no further meaning to these fields, which keeps this layer free of surface semantics.
struct TargetApp {
    let bundleID: String?
    let ownerNames: [String]
    let label: String

    static func fromEnvironment() -> TargetApp {
        let env = ProcessInfo.processInfo.environment
        let bundleID = env["VISUAL_APP_BUNDLE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerNames = (env["VISUAL_APP_OWNER_NAMES"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let label = env["VISUAL_APP_LABEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TargetApp(
            bundleID: bundleID?.isEmpty == false ? bundleID : nil,
            ownerNames: ownerNames,
            label: label?.isEmpty == false ? label! : "target app"
        )
    }
}

let defaultTargetApp = TargetApp.fromEnvironment()

func usage() -> String {
    """
    Usage:
      swift action_executor.swift schema
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift run-plan '<action_plan_json>'
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift run-plan file:action_plan.json
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift run-plan -

    Diagnostics (non-action):
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift observe
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift observe out.png 760
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift window
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift screens
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift diagnose
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift capabilities
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift capture-permission
      VISUAL_APP_BUNDLE_ID=<id> swift action_executor.swift request-capture-permission

    Notes:
      - x/y are desktop GUI windowTopLeft coordinates from the active observation unless coordinateSpace says otherwise.
      - OpenAI-style scrollY is positive for down; the local CGEvent delta is converted internally.
      - run-plan executes ActionPlan actions[] in order.
      - screenshot actions are limited to the desktop GUI target window or a region inside it.
      - set VISUAL_APP_BUNDLE_ID and/or VISUAL_APP_OWNER_NAMES before running this reference binding.
    """
}

func schema() -> String {
    """
    {
      "schemaVersion": 1,
      "kind": "action_plan",
      "wireFormat": "openai_computer_call_compatible",
      "call_id": "call_local_001",
      "status": "completed",
      "pending_safety_checks": [],
      "confirmationStatus": "not_required",
      "dryRun": false,
      "bundleID": "<opaque>",
      "ownerNames": ["<opaque>"],
      "appLabel": "<opaque>",
      "actions": [
        { "type": "click", "x": 505, "y": 137, "button": "left", "coordinateSpace": "windowTopLeft", "mode": "cliclick", "restoreMouse": true },
        { "type": "scroll", "x": 610, "y": 520, "scrollY": 160, "mode": "hid" },
        { "type": "keypress", "keys": ["ESC"] },
        { "type": "wait", "durationMs": 600 },
        { "type": "screenshot" },
        { "type": "screenshot", "x": 480, "y": 90, "width": 300, "height": 760, "output": "out/region.png", "maxEdge": 640 }
      ]
    }

    Required fields:
      click: type, x, y
      scroll: type, x, y, scrollY, optional scrollX
      keypress: type, keys
      wait: type, optional durationMs
      screenshot: type, optional x/y/width/height/output/maxEdge

    Plan safety:
      - non-empty pending_safety_checks require confirmationStatus=approved for non-dryRun execution.
      - text input, drag, move, and double_click are reserved and rejected at Layer 1.
    Backend notes:
      - cliclick is the stable click/key baseline; it does not support scroll-wheel events.
      - hid posts CGEvent events to kCGHIDEventTap.
      - pid uses postToPid; it keeps the global pointer untouched but is experimental.
    """
}

struct JSONAction: Decodable {
    let type: String
    let x: Double?
    let y: Double?
    let width: Double?
    let height: Double?
    let scrollX: Int?
    let scrollY: Int?
    let times: Int?
    let button: String?
    let keys: [String]?
    let durationMs: Int?
    let output: String?
    let maxEdge: Int?
    let mode: String?
    let coordinateSpace: String?
    let restoreMouse: Bool?
    let dryRun: Bool?
    let allowNegativeWindowOrigin: Bool?
}

struct JSONSafetyCheck: Decodable {
    let id: String?
    let code: String?
    let message: String?
}

struct JSONActionPlan: Decodable {
    let schemaVersion: Int?
    let kind: String?
    let call_id: String?
    let status: String?
    let pending_safety_checks: [JSONSafetyCheck]?
    let confirmationStatus: String?
    let dryRun: Bool?
    let bundleID: String?
    let ownerNames: [String]?
    let appLabel: String?
    let allowNegativeWindowOrigin: Bool?
    let actions: [JSONAction]
}

func buildTargetApp(bundleID rawBundleID: String?, ownerNames rawOwnerNames: [String]?, appLabel rawAppLabel: String?) -> TargetApp {
    let bundleID = rawBundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let ownerNames = rawOwnerNames?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } ?? []
    let appLabel = rawAppLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
    if bundleID?.isEmpty == false || !ownerNames.isEmpty || appLabel?.isEmpty == false {
        return TargetApp(
            bundleID: bundleID?.isEmpty == false ? bundleID : defaultTargetApp.bundleID,
            ownerNames: ownerNames.isEmpty ? defaultTargetApp.ownerNames : ownerNames,
            label: appLabel?.isEmpty == false ? appLabel! : defaultTargetApp.label
        )
    }
    return defaultTargetApp
}

func targetApp(from plan: JSONActionPlan) -> TargetApp {
    buildTargetApp(bundleID: plan.bundleID, ownerNames: plan.ownerNames, appLabel: plan.appLabel)
}

func modeOrDefault(_ value: String?, _ fallback: String) -> String {
    let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

func readJSONPayload(_ arg: String) throws -> String {
    if arg == "-" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActionError.usage("No JSON received on stdin")
        }
        return text
    }
    if arg.hasPrefix("file:") {
        return try String(contentsOfFile: String(arg.dropFirst("file:".count)), encoding: .utf8)
    }
    if arg.hasPrefix("@") {
        return try String(contentsOfFile: String(arg.dropFirst()), encoding: .utf8)
    }
    return arg
}

func require<T>(_ value: T?, _ name: String) throws -> T {
    guard let value else {
        throw ActionError.usage("Missing required field: \(name)")
    }
    return value
}

func printJSON(_ object: [String: Any]) {
    let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    if let data, let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        print("{\"ok\":false,\"error\":\"Could not serialize JSON\"}")
    }
}

func matchesTarget(owner: String, bundleID: String?, target: TargetApp) -> Bool {
    if let targetBundleID = target.bundleID, bundleID == targetBundleID {
        return true
    }
    return target.ownerNames.contains { owner == $0 || owner.contains($0) }
}

func bundleIDForPID(_ pid: pid_t?) -> String? {
    guard let pid else { return nil }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
}

func targetWindow(_ target: TargetApp) throws -> WindowBounds {
    guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        throw ActionError.windowNotFound
    }
    for info in infoList {
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let rawPID = info[kCGWindowOwnerPID as String] as? Int
        let bundleID = bundleIDForPID(rawPID.map { pid_t($0) })
        guard matchesTarget(owner: owner, bundleID: bundleID, target: target) else { continue }
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? Double,
              let y = bounds["Y"] as? Double,
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else { continue }
        let rawWindowID = info[kCGWindowNumber as String] as? UInt32 ?? 0
        return WindowBounds(x: x, y: y, width: width, height: height, windowID: CGWindowID(rawWindowID))
    }
    throw ActionError.windowNotFound
}

func targetPid(_ target: TargetApp) -> pid_t? {
    for app in NSWorkspace.shared.runningApplications {
        if let bundleID = target.bundleID, app.bundleIdentifier == bundleID {
            return app.processIdentifier
        }
        if let appName = app.localizedName, target.ownerNames.contains(where: { appName == $0 || appName.contains($0) }) {
            return app.processIdentifier
        }
    }
    return nil
}

func frontmostApplicationInfo(target: TargetApp) -> [String: Any] {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return ["available": false, "targetIsFrontmost": false]
    }
    let name = app.localizedName ?? ""
    let bundleID = app.bundleIdentifier ?? ""
    return [
        "available": true,
        "name": name,
        "bundleID": bundleID,
        "pid": app.processIdentifier,
        "targetIsFrontmost": matchesTarget(owner: name, bundleID: bundleID, target: target)
    ]
}

func targetIsFrontmost(_ target: TargetApp) -> Bool {
    frontmostApplicationInfo(target: target)["targetIsFrontmost"] as? Bool ?? false
}

func activeDisplayInfos() -> [DisplayInfo] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }
    let mainID = CGMainDisplayID()
    return displayIDs.prefix(Int(count)).map { displayID in
        DisplayInfo(displayID: displayID, bounds: CGDisplayBounds(displayID), isMain: displayID == mainID)
    }
}

func activeDisplays() -> [[String: Any]] {
    activeDisplayInfos().map { display in
        let bounds = display.bounds
        return [
            "displayID": display.displayID,
            "isMain": display.isMain,
            "x": bounds.origin.x,
            "y": bounds.origin.y,
            "width": bounds.width,
            "height": bounds.height,
            "pixelWidth": CGDisplayPixelsWide(display.displayID),
            "pixelHeight": CGDisplayPixelsHigh(display.displayID)
        ]
    }
}

func activeDisplayRects() -> [CGRect] {
    activeDisplayInfos().map(\.bounds)
}

func pointOnActiveDisplay(_ point: CGPoint) -> Bool {
    activeDisplayRects().contains { $0.contains(point) }
}

func windowOnActiveDisplay(_ window: WindowBounds) -> Bool {
    let center = CGPoint(x: window.x + window.width / 2, y: window.y + window.height / 2)
    return pointOnActiveDisplay(center)
}

func displayContaining(_ point: CGPoint) -> DisplayInfo? {
    activeDisplayInfos().first { $0.bounds.contains(point) }
}

// @protocol L1 section 7 Coordinate Spaces.
// Resolves an in-plan coordinate to a global screen point. windowTopLeft is the default origin
// (L1 section 7); the other three spaces exist so an agent may plan in whichever frame it observed in.
func eventPoint(window: WindowBounds, x: Double, y: Double, coordinateSpace: String) throws -> CGPoint {
    switch coordinateSpace {
    case "windowTopLeft":
        return CGPoint(x: window.x + x, y: window.y + y)
    case "windowBottomLeft":
        return CGPoint(x: window.x + x, y: window.y + window.height - y)
    case "screenTopLeft":
        return CGPoint(x: x, y: y)
    case "screenBottomLeft":
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: x, y: mainHeight - y)
    default:
        throw ActionError.usage("Unsupported coordinateSpace: \(coordinateSpace)")
    }
}

func currentMouseLocation() -> CGPoint {
    if let event = CGEvent(source: nil) {
        return event.location
    }
    return NSEvent.mouseLocation
}

func postHIDMove(to point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func postHIDClick(point: CGPoint, restoreMouse: Bool) {
    let before = currentMouseLocation()
    postHIDMove(to: point)
    usleep(20_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    if restoreMouse {
        usleep(180_000)
        postHIDMove(to: before)
    }
}

func cliclickPath() -> String? {
    let candidates = ["/opt/homebrew/bin/cliclick", "/usr/local/bin/cliclick", "/usr/bin/cliclick"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func runCliclick(arguments: [String]) throws {
    guard let path = cliclickPath() else {
        throw ActionError.usage("cliclick not found. Install it or use mode=hid.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ActionError.usage("cliclick failed: \(message ?? "exit \(process.terminationStatus)")")
    }
}

func runCliclickClick(point: CGPoint, restoreMouse: Bool) throws {
    let clickArgument = "c:\(Int(round(point.x))),\(Int(round(point.y)))"
    try runCliclick(arguments: restoreMouse ? ["-r", clickArgument] : [clickArgument])
}

func runCliclickKey(_ key: String) throws {
    try runCliclick(arguments: ["kp:\(key)"])
}

func postMouseSequence(point: CGPoint, mode: String, restoreMouse: Bool, target: TargetApp) throws {
    let source = CGEventSource(stateID: .hidSystemState)
    let events: [(CGEventType, CGMouseButton)] = [
        (.mouseMoved, .left),
        (.leftMouseDown, .left),
        (.leftMouseUp, .left)
    ]
    switch mode {
    case "cliclick":
        try runCliclickClick(point: point, restoreMouse: restoreMouse)
    case "hid":
        postHIDClick(point: point, restoreMouse: restoreMouse)
    case "pid":
        guard let pid = targetPid(target) else { throw ActionError.windowNotFound }
        for (type, button) in events {
            if let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) {
                if type == .leftMouseDown || type == .leftMouseUp {
                    event.setIntegerValueField(.mouseEventClickState, value: 1)
                }
                event.postToPid(pid)
                usleep(80_000)
            }
        }
    default:
        throw ActionError.usage("Unsupported mode: \(mode)")
    }
}

func postHIDEsc() {
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(50_000)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
}

func postPidEsc(target: TargetApp) throws {
    guard let pid = targetPid(target) else { throw ActionError.windowNotFound }
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.postToPid(pid)
    usleep(50_000)
    CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.postToPid(pid)
}

func postEsc(mode: String, target: TargetApp) throws {
    switch mode {
    case "cliclick":
        try runCliclickKey("esc")
    case "hid":
        postHIDEsc()
    case "pid":
        try postPidEsc(target: target)
    default:
        throw ActionError.usage("Unsupported esc mode: \(mode)")
    }
}

func postScroll(screenX: Double, screenY: Double, deltaY: Int, times: Int, mode: String, target: TargetApp) throws {
    let location = CGPoint(x: screenX, y: screenY)
    for _ in 0..<max(1, times) {
        switch mode {
        case "hid":
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(deltaY), wheel2: 0, wheel3: 0) {
                event.location = location
                event.post(tap: .cghidEventTap)
            }
        case "pid":
            guard let pid = targetPid(target) else { throw ActionError.windowNotFound }
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(deltaY), wheel2: 0, wheel3: 0) {
                event.location = location
                event.postToPid(pid)
            }
        case "cliclick":
            throw ActionError.usage("cliclick does not support scroll-wheel events; use mode=hid for scroll.")
        default:
            throw ActionError.usage("Unsupported scroll mode: \(mode)")
        }
        usleep(120_000)
    }
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ActionError.usage("Could not create PNG destination: \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ActionError.usage("Could not write PNG: \(path)")
    }
}

func shareableTargetWindow(matching window: WindowBounds, target: TargetApp) throws -> SCWindow {
    let semaphore = DispatchSemaphore(value: 0)
    var contentResult: SCShareableContent?
    var contentError: Error?
    SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
        contentResult = content
        contentError = error
        semaphore.signal()
    }
    semaphore.wait()
    if let contentError {
        throw ActionError.usage("Could not list shareable windows: \(contentError.localizedDescription). Check Screen Recording permission.")
    }
    guard let content = contentResult else {
        throw ActionError.usage("Could not list shareable windows. Check Screen Recording permission.")
    }
    if let exact = content.windows.first(where: { $0.windowID == window.windowID }) {
        return exact
    }
    if let byOwner = content.windows.first(where: {
        let app = $0.owningApplication
        let bundleMatches = target.bundleID != nil && app?.bundleIdentifier == target.bundleID
        let name = app?.applicationName ?? ""
        let nameMatches = target.ownerNames.contains { name == $0 || name.contains($0) }
        return bundleMatches || nameMatches
    }) {
        return byOwner
    }
    throw ActionError.windowNotFound
}

func captureWindowWithScreenCaptureKit(window: WindowBounds, target: TargetApp) throws -> CapturedWindowImage {
    let shareableWindow = try shareableTargetWindow(matching: window, target: target)
    let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
    let configuration = SCStreamConfiguration()
    let scale = 2.0
    configuration.width = max(1, Int(shareableWindow.frame.width * scale))
    configuration.height = max(1, Int(shareableWindow.frame.height * scale))
    configuration.scalesToFit = true
    configuration.preservesAspectRatio = true
    configuration.showsCursor = false
    let semaphore = DispatchSemaphore(value: 0)
    var capturedImage: CGImage?
    var capturedError: Error?
    SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
        capturedImage = image
        capturedError = error
        semaphore.signal()
    }
    semaphore.wait()
    if let capturedError {
        throw ActionError.usage("Could not capture \(target.label) window: \(capturedError.localizedDescription). Check Screen Recording permission.")
    }
    guard let image = capturedImage else {
        throw ActionError.usage("Could not capture \(target.label) window. Check Screen Recording permission.")
    }
    return CapturedWindowImage(image: image, backend: "screenCaptureKit", fallbackErrors: [])
}

func captureWindowWithCGWindowList(window: WindowBounds, target: TargetApp) throws -> CapturedWindowImage {
    typealias CGWindowListCreateImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    let coreGraphicsPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    guard let handle = dlopen(coreGraphicsPath, RTLD_LAZY) else {
        throw ActionError.usage("Could not load CoreGraphics for CGWindowList fallback.")
    }
    defer { dlclose(handle) }
    guard let symbol = dlsym(handle, "CGWindowListCreateImage") else {
        throw ActionError.usage("CGWindowListCreateImage is unavailable on this macOS runtime.")
    }
    let createImage = unsafeBitCast(symbol, to: CGWindowListCreateImageFunction.self)
    let imageOptions = CGWindowImageOption([.boundsIgnoreFraming, .nominalResolution]).rawValue
    let listOption = CGWindowListOption.optionIncludingWindow.rawValue
    guard let unmanagedImage = createImage(.null, listOption, window.windowID, imageOptions) else {
        throw ActionError.usage("Could not capture \(target.label) window with CGWindowList.")
    }
    let image = unmanagedImage.takeRetainedValue()
    return CapturedWindowImage(image: image, backend: "cgWindowList", fallbackErrors: [])
}

func captureWindowWithCGDisplayCrop(window: WindowBounds, target: TargetApp, coordinateMode: String) throws -> CapturedWindowImage {
    guard targetIsFrontmost(target) else {
        throw ActionError.usage("Display crop fallback requires \(target.label) to be frontmost; otherwise another window may be captured.")
    }
    let center = CGPoint(x: window.x + window.width / 2, y: window.y + window.height / 2)
    guard let display = displayContaining(center) else {
        throw ActionError.usage("Could not find active display containing \(target.label) window center.")
    }
    let windowRect = CGRect(x: window.x, y: window.y, width: window.width, height: window.height)
    let visibleRect = windowRect.intersection(display.bounds)
    guard !visibleRect.isNull, visibleRect.width > 0, visibleRect.height > 0 else {
        throw ActionError.usage("Could not intersect \(target.label) window with active display.")
    }
    let captureRect: CGRect
    switch coordinateMode {
    case "global":
        captureRect = visibleRect
    case "displayLocal":
        captureRect = CGRect(
            x: visibleRect.minX - display.bounds.minX,
            y: visibleRect.minY - display.bounds.minY,
            width: visibleRect.width,
            height: visibleRect.height
        )
    default:
        throw ActionError.usage("Unsupported display capture coordinateMode: \(coordinateMode)")
    }
    typealias CGDisplayCreateImageForRectFunction = @convention(c) (UInt32, CGRect) -> Unmanaged<CGImage>?
    let coreGraphicsPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    guard let handle = dlopen(coreGraphicsPath, RTLD_LAZY) else {
        throw ActionError.usage("Could not load CoreGraphics for CGDisplay fallback.")
    }
    defer { dlclose(handle) }
    guard let symbol = dlsym(handle, "CGDisplayCreateImageForRect") else {
        throw ActionError.usage("CGDisplayCreateImageForRect is unavailable on this macOS runtime.")
    }
    let createImage = unsafeBitCast(symbol, to: CGDisplayCreateImageForRectFunction.self)
    guard let unmanagedImage = createImage(display.displayID, captureRect) else {
        throw ActionError.usage("Could not capture \(target.label) window area from active display.")
    }
    let image = unmanagedImage.takeRetainedValue()
    return CapturedWindowImage(image: image, backend: "cgDisplayCrop:\(coordinateMode)", fallbackErrors: [])
}

func captureTargetWindowImage(window: WindowBounds, target: TargetApp) throws -> CapturedWindowImage {
    var fallbackErrors: [String] = []
    var lastCaptured: CapturedWindowImage?

    func usable(_ captured: CapturedWindowImage) -> Bool {
        imageUsableForVision(visualStats(for: captured.image))
    }

    do {
        let captured = try captureWindowWithScreenCaptureKit(window: window, target: target)
        if usable(captured) {
            return CapturedWindowImage(image: captured.image, backend: captured.backend, fallbackErrors: fallbackErrors)
        }
        fallbackErrors.append("screenCaptureKit: capture returned low-information image")
        lastCaptured = CapturedWindowImage(image: captured.image, backend: captured.backend, fallbackErrors: fallbackErrors)
    } catch {
        fallbackErrors.append("screenCaptureKit: \(error)")
    }

    do {
        let captured = try captureWindowWithCGWindowList(window: window, target: target)
        if usable(captured) {
            return CapturedWindowImage(image: captured.image, backend: captured.backend, fallbackErrors: fallbackErrors)
        }
        fallbackErrors.append("cgWindowList: capture returned low-information image")
        lastCaptured = CapturedWindowImage(image: captured.image, backend: captured.backend, fallbackErrors: fallbackErrors)
    } catch {
        fallbackErrors.append("cgWindowList: \(error)")
    }

    for coordinateMode in ["global", "displayLocal"] {
        do {
            let captured = try captureWindowWithCGDisplayCrop(window: window, target: target, coordinateMode: coordinateMode)
            if usable(captured) {
                return CapturedWindowImage(image: captured.image, backend: captured.backend, fallbackErrors: fallbackErrors)
            }
            fallbackErrors.append("cgDisplayCrop:\(coordinateMode): capture returned low-information image")
            lastCaptured = CapturedWindowImage(image: captured.image, backend: captured.backend, fallbackErrors: fallbackErrors)
        } catch {
            fallbackErrors.append("cgDisplayCrop:\(coordinateMode): \(error)")
        }
    }

    if let lastCaptured {
        return CapturedWindowImage(image: lastCaptured.image, backend: lastCaptured.backend, fallbackErrors: fallbackErrors)
    }
    throw ActionError.usage("Could not capture \(target.label) window with available backends: \(fallbackErrors.joined(separator: " | "))")
}

func cropWindowImage(_ image: CGImage, window: WindowBounds, screenshotX: Double, screenshotY: Double, width: Double, height: Double) -> CGImage {
    let scaleX = Double(image.width) / max(1.0, window.width)
    let scaleY = Double(image.height) / max(1.0, window.height)
    let cropRect = CGRect(
        x: max(0, screenshotX * scaleX),
        y: max(0, screenshotY * scaleY),
        width: max(1, width * scaleX),
        height: max(1, height * scaleY)
    ).integral
    return image.cropping(to: cropRect) ?? image
}

func downscaledImage(_ image: CGImage, maxEdge: Int?) -> CGImage {
    guard let maxEdge, maxEdge > 0 else { return image }
    let originalWidth = image.width
    let originalHeight = image.height
    let longestEdge = max(originalWidth, originalHeight)
    guard longestEdge > maxEdge else { return image }
    let scale = Double(maxEdge) / Double(longestEdge)
    let targetWidth = max(1, Int(Double(originalWidth) * scale))
    let targetHeight = max(1, Int(Double(originalHeight) * scale))
    guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: targetWidth, height: targetHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return image
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
    return context.makeImage() ?? image
}

func visualStats(for image: CGImage) -> [String: Any] {
    let sampleWidth = max(1, min(64, image.width))
    let sampleHeight = max(1, min(64, image.height))
    var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixels, width: sampleWidth, height: sampleHeight,
            bitsPerComponent: 8, bytesPerRow: sampleWidth * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return [
            "width": image.width, "height": image.height,
            "sampleWidth": sampleWidth, "sampleHeight": sampleHeight,
            "usableForVision": true, "note": "stats_unavailable"
        ]
    }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
    var sum = 0.0
    var sumSquares = 0.0
    var darkCount = 0
    var brightCount = 0
    let pixelCount = sampleWidth * sampleHeight
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let r = Double(pixels[index])
        let g = Double(pixels[index + 1])
        let b = Double(pixels[index + 2])
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        sum += luma
        sumSquares += luma * luma
        if luma < 8 { darkCount += 1 }
        if luma > 247 { brightCount += 1 }
    }
    let mean = sum / Double(pixelCount)
    let variance = max(0.0, sumSquares / Double(pixelCount) - mean * mean)
    let stddev = sqrt(variance)
    let darkRatio = Double(darkCount) / Double(pixelCount)
    let brightRatio = Double(brightCount) / Double(pixelCount)
    let blankLike = stddev < 3.0 || darkRatio > 0.98 || brightRatio > 0.98
    return [
        "width": image.width, "height": image.height,
        "sampleWidth": sampleWidth, "sampleHeight": sampleHeight,
        "meanLuma": mean, "stddevLuma": stddev,
        "darkRatio": darkRatio, "brightRatio": brightRatio,
        "blankLike": blankLike, "usableForVision": !blankLike
    ]
}

// @protocol L1 section 10 Capture Usability Contract.
// THE risk gate. A backend returning an image is necessary but NOT sufficient; this flag is what
// callers must check before treating a capture as visual input. When false, the observation is
// marked unobservableWindow and the loop must halt (see appObservation / L1 section 10).
func imageUsableForVision(_ stats: [String: Any]) -> Bool {
    stats["usableForVision"] as? Bool ?? true
}

func captureWindowRegion(window: WindowBounds, target: TargetApp, screenshotX: Double, screenshotY: Double, width: Double, height: Double, outputPath: String, maxEdge: Int?) throws -> CapturedWindowImage {
    let captured = try captureTargetWindowImage(window: window, target: target)
    let croppedImage = cropWindowImage(captured.image, window: window, screenshotX: screenshotX, screenshotY: screenshotY, width: width, height: height)
    let outputImage = downscaledImage(croppedImage, maxEdge: maxEdge)
    try writePNG(outputImage, to: outputPath)
    return CapturedWindowImage(image: outputImage, backend: captured.backend, fallbackErrors: captured.fallbackErrors)
}

// @protocol L1 section 4 AppObservation, section 10 Capture Usability, section 13 Diagnostics.
// Produces the loop's visual-state input. Emits source=bounded-capture. Sets
// stateHint=unobservableWindow whenever the window is off active displays OR the capture is not
// usableForVision; this is the formal halt signal the visual model / host must honor before acting.
func appObservation(target: TargetApp, outputPath: String?, maxEdge: Int?) throws -> [String: Any] {
    let window = try targetWindow(target)
    let captureAllowed = CGPreflightScreenCaptureAccess()
    let visibleOnDisplay = windowOnActiveDisplay(window)
    let frontmostInfo = frontmostApplicationInfo(target: target)
    var observation: [String: Any] = [
        "schemaVersion": 1,
        "kind": "appObservation",
        "source": "bounded-capture",
        "coordinateSpace": "windowTopLeft",
        "app": [
            "bundleIdentifier": target.bundleID ?? "",
            "label": target.label,
            "window": [
                "x": window.x, "y": window.y, "width": window.width, "height": window.height, "windowID": window.windowID
            ]
        ],
        "diagnostics": [
            "captureAllowed": captureAllowed,
            "negativeWindowOrigin": window.x < 0 || window.y < 0,
            "windowOnActiveDisplay": visibleOnDisplay,
            "pointerActionsAllowedByDefault": visibleOnDisplay && frontmostInfo["targetIsFrontmost"] as? Bool == true,
            "frontmostApplication": frontmostInfo,
            "displays": activeDisplays()
        ],
        "stateHint": visibleOnDisplay ? "unknown" : "unobservableWindow"
    ]
    guard captureAllowed else {
        observation["capture"] = ["ok": false, "error": "screen_capture_permission_required", "usableForVision": false]
        observation["stateHint"] = "unobservableWindow"
        return observation
    }
    do {
        let captured = try captureTargetWindowImage(window: window, target: target)
        let outputImage = downscaledImage(captured.image, maxEdge: maxEdge)
        if let outputPath { try writePNG(outputImage, to: outputPath) }
        let stats = visualStats(for: outputImage)
        let usable = imageUsableForVision(stats)
        var screenshot: [String: Any] = ["width": outputImage.width, "height": outputImage.height, "scale": 1]
        if let outputPath { screenshot["path"] = outputPath }
        observation["screenshot"] = screenshot
        var capture: [String: Any] = ["ok": true, "backend": captured.backend, "usableForVision": usable, "visualStats": stats]
        if !captured.fallbackErrors.isEmpty { capture["fallbackErrors"] = captured.fallbackErrors }
        observation["capture"] = capture
        if !usable { observation["stateHint"] = "unobservableWindow" }
        return observation
    } catch {
        observation["capture"] = ["ok": false, "error": "\(error)", "usableForVision": false]
        observation["stateHint"] = "unobservableWindow"
        return observation
    }
}

func openAIScrollDeltaY(from request: JSONAction) throws -> Int {
    if let scrollX = request.scrollX, scrollX != 0 {
        throw ActionError.usage("Horizontal scroll is not implemented")
    }
    let scrollY = try require(request.scrollY, "scrollY")
    return -scrollY
}

// @protocol L1 section 8 Safety Invariants (active-display reachability).
// Guards the window origin. A negative origin is NOT an error by itself (multi-display layouts
// place displays at negative coordinates); the test is whether the window center lies on an
// active display. Override only via allowNegativeWindowOrigin after verifying the layout.
func ensurePointerSafe(window: WindowBounds, request: JSONAction, allowNegativeWindowOrigin: Bool) throws {
    if allowNegativeWindowOrigin || request.allowNegativeWindowOrigin == true { return }
    if window.x < 0 || window.y < 0, !windowOnActiveDisplay(window) {
        throw ActionError.usage("Refusing pointer action because the desktop GUI target window origin is negative and the window center is not inside any active display (x=\(Int(window.x)), y=\(Int(window.y))). Move the window to a visible display or pass allowNegativeWindowOrigin=true after verifying this display setup.")
    }
}

// @protocol L1 section 8 Safety Invariants (event-point containment).
// The resolved event point MUST fall inside some active display rectangle, else the click/scroll
// is refused. This is the second half of the section 8 guard, applied after coordinate resolution.
func ensurePointerSafe(window: WindowBounds, point: CGPoint, request: JSONAction, allowNegativeWindowOrigin: Bool) throws {
    if allowNegativeWindowOrigin || request.allowNegativeWindowOrigin == true { return }
    if !pointOnActiveDisplay(point) {
        throw ActionError.usage("Refusing pointer action because event point is outside all active displays (eventX=\(Int(point.x)), eventY=\(Int(point.y))). Re-read the desktop GUI surface/screen reference or pass allowNegativeWindowOrigin=true after verifying this display setup.")
    }
}

// @protocol L1 section 6 Action Set, section 6.3 Reserved Actions.
// The single dispatch point for one action. Honors the action set and its required fields, and
// REJECTS the reserved types (type/drag/move/double_click) - never silently relax this without a
// matching protocol change. dryRun resolves coordinates and returns results WITHOUT dispatching
// any event or writing files (L1 section 8). Returned ok:true means "dispatched", not "succeeded".
func executeAction(_ request: JSONAction, target: TargetApp, dryRunOverride: Bool? = nil, allowNegativeWindowOrigin: Bool = false) throws -> [String: Any] {
    let dryRun = dryRunOverride ?? request.dryRun ?? false
    switch request.type {
    case "click":
        if let button = request.button, button != "left" {
            throw ActionError.usage("Only left click is implemented")
        }
        let window = try targetWindow(target)
        try ensurePointerSafe(window: window, request: request, allowNegativeWindowOrigin: allowNegativeWindowOrigin)
        let x = try require(request.x, "x")
        let y = try require(request.y, "y")
        let mode = modeOrDefault(request.mode, "cliclick")
        let coordinateSpace = request.coordinateSpace ?? "windowTopLeft"
        let point = try eventPoint(window: window, x: x, y: y, coordinateSpace: coordinateSpace)
        try ensurePointerSafe(window: window, point: point, request: request, allowNegativeWindowOrigin: allowNegativeWindowOrigin)
        if !dryRun {
            try postMouseSequence(point: point, mode: mode, restoreMouse: request.restoreMouse ?? true, target: target)
        }
        return ["ok": true, "type": request.type, "dryRun": dryRun, "mode": mode, "coordinateSpace": coordinateSpace, "eventX": point.x, "eventY": point.y, "appLabel": target.label]
    case "scroll":
        let window = try targetWindow(target)
        try ensurePointerSafe(window: window, request: request, allowNegativeWindowOrigin: allowNegativeWindowOrigin)
        let x = try require(request.x, "x")
        let y = try require(request.y, "y")
        let deltaY = try openAIScrollDeltaY(from: request)
        let times = request.times ?? 1
        let mode = modeOrDefault(request.mode, "hid")
        let screenX = window.x + x
        let screenY = window.y + y
        try ensurePointerSafe(window: window, point: CGPoint(x: screenX, y: screenY), request: request, allowNegativeWindowOrigin: allowNegativeWindowOrigin)
        if !dryRun {
            try postScroll(screenX: screenX, screenY: screenY, deltaY: deltaY, times: times, mode: mode, target: target)
        }
        return ["ok": true, "type": request.type, "dryRun": dryRun, "mode": mode, "screenX": screenX, "screenY": screenY, "localDeltaY": deltaY, "times": times, "appLabel": target.label]
    case "keypress":
        let keys = request.keys ?? []
        guard keys.contains(where: { $0.uppercased() == "ESC" || $0.uppercased() == "ESCAPE" }) else {
            throw ActionError.usage("Only ESC keypress is implemented")
        }
        let mode = modeOrDefault(request.mode, "cliclick")
        if !dryRun { try postEsc(mode: mode, target: target) }
        return ["ok": true, "type": request.type, "keys": keys, "dryRun": dryRun, "mode": mode, "appLabel": target.label]
    case "wait":
        let durationMs = max(0, request.durationMs ?? 600)
        if !dryRun { usleep(useconds_t(durationMs * 1000)) }
        return ["ok": true, "type": request.type, "dryRun": dryRun, "durationMs": durationMs, "appLabel": target.label]
    case "screenshot":
        let window = try targetWindow(target)
        guard let output = request.output else {
            return ["ok": true, "type": request.type, "dryRun": dryRun, "needsScreenshot": true, "appLabel": target.label]
        }
        let x = request.x ?? 0
        let y = request.y ?? 0
        let width = request.width ?? window.width
        let height = request.height ?? window.height
        if !dryRun {
            let captured = try captureWindowRegion(window: window, target: target, screenshotX: x, screenshotY: y, width: width, height: height, outputPath: output, maxEdge: request.maxEdge)
            let stats = visualStats(for: captured.image)
            var response: [String: Any] = ["ok": true, "type": request.type, "dryRun": dryRun, "output": output, "x": x, "y": y, "width": width, "height": height, "appLabel": target.label, "captureBackend": captured.backend, "captureVisualStats": stats, "captureUsableForVision": imageUsableForVision(stats)]
            if let maxEdge = request.maxEdge { response["maxEdge"] = maxEdge }
            if !captured.fallbackErrors.isEmpty { response["captureFallbackErrors"] = captured.fallbackErrors }
            return response
        }
        var response: [String: Any] = ["ok": true, "type": request.type, "dryRun": dryRun, "output": output, "x": x, "y": y, "width": width, "height": height, "appLabel": target.label]
        if let maxEdge = request.maxEdge { response["maxEdge"] = maxEdge }
        return response
    case "type":
        throw ActionError.usage("Reserved action type: type. Text input must be explicitly enabled by an upper layer.")
    case "drag", "move", "double_click":
        throw ActionError.usage("Reserved action type: \(request.type)")
    default:
        throw ActionError.usage("Unsupported action type: \(request.type)")
    }
}

// @protocol L1 section 5 ActionPlan, section 8 Safety Invariants, section 11 ActionResult.
// Plan-level entry point. Enforces the two pre-dispatch gates from section 8 before running any action:
//   1. non-empty pending_safety_checks without confirmationStatus=approved -> refuse (unless dryRun);
//   2. screenshot-with-output without screen-recording permission -> refuse early.
// Then executes actions[] in order (section 5) and emits one ActionResult with one entry per action (section 11).
func runPlan(_ payload: String) throws {
    let data = Data(payload.utf8)
    let plan = try JSONDecoder().decode(JSONActionPlan.self, from: data)
    let dryRun = plan.dryRun ?? false
    let safetyChecks = plan.pending_safety_checks ?? []
    let confirmationStatus = plan.confirmationStatus ?? (safetyChecks.isEmpty ? "not_required" : "pending")

    if !dryRun && !safetyChecks.isEmpty && confirmationStatus != "approved" {
        // @integration section 4 Error Envelope, section 8 Safety-Approval Round Trip.
        // Emit the unified error envelope with reason=pending_safety_approval so a host can detect
        // the gate and re-submit the SAME plan with confirmationStatus=approved. call_id and the
        // pending count are carried as extra fields for the approver.
        var envelope = errorEnvelope(reason: "pending_safety_approval", message: "pending_safety_checks require confirmationStatus=approved")
        envelope["call_id"] = plan.call_id ?? ""
        envelope["pendingSafetyCheckCount"] = safetyChecks.count
        printJSON(envelope)
        return
    }

    let needsLocalCapture = plan.actions.contains { $0.type == "screenshot" && $0.output != nil }
    if !dryRun && needsLocalCapture && !CGPreflightScreenCaptureAccess() {
        // @integration section 4 Error Envelope.
        var envelope = errorEnvelope(reason: "screen_capture_permission_required", message: "Screenshot output requires macOS Screen Recording permission before executing earlier actions.")
        envelope["call_id"] = plan.call_id ?? ""
        printJSON(envelope)
        return
    }

    let planTarget = targetApp(from: plan)
    var results: [[String: Any]] = []
    for (index, action) in plan.actions.enumerated() {
        var result = try executeAction(action, target: planTarget, dryRunOverride: dryRun || (action.dryRun ?? false), allowNegativeWindowOrigin: plan.allowNegativeWindowOrigin ?? false)
        result["index"] = index
        results.append(result)
    }

    printJSON([
        "ok": true, "kind": "action_result",
        "wireFormat": "openai_computer_call_result_compatible",
        "call_id": plan.call_id ?? "",
        "dryRun": dryRun,
        "results": results
    ])
}

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw ActionError.usage(usage())
    }
    let target = defaultTargetApp

    switch command {
    case "help", "-h", "--help":
        print(usage())
    case "schema":
        print(schema())
    case "run-plan":
        guard args.count == 2 else { throw ActionError.usage(usage()) }
        try runPlan(readJSONPayload(args[1]))
    case "observe":
        guard args.count <= 3 else { throw ActionError.usage(usage()) }
        let outputPath = args.count >= 2 ? args[1] : nil
        let maxEdge = args.count == 3 ? Int(args[2]) : nil
        printJSON(try appObservation(target: target, outputPath: outputPath, maxEdge: maxEdge))
    case "window":
        let window = try targetWindow(target)
        printJSON(["ok": true, "appLabel": target.label, "window": ["x": window.x, "y": window.y, "width": window.width, "height": window.height, "windowID": window.windowID]])
    case "screens":
        printJSON(["ok": true, "diagnostic": command, "displays": activeDisplays()])
    case "diagnose":
        let window = try targetWindow(target)
        let captureAllowed = CGPreflightScreenCaptureAccess()
        let negativeOrigin = window.x < 0 || window.y < 0
        let visibleOnDisplay = windowOnActiveDisplay(window)
        let frontmostInfo = frontmostApplicationInfo(target: target)
        var response: [String: Any] = [
            "ok": true, "diagnostic": command, "appLabel": target.label,
            "captureAllowed": captureAllowed,
            "frontmostApplication": frontmostInfo,
            "negativeWindowOrigin": negativeOrigin,
            "windowOnActiveDisplay": visibleOnDisplay,
            "pointerActionsAllowedByDefault": visibleOnDisplay && frontmostInfo["targetIsFrontmost"] as? Bool == true,
            "displays": activeDisplays(),
            "window": ["x": window.x, "y": window.y, "width": window.width, "height": window.height, "windowID": window.windowID],
            "stopReason": visibleOnDisplay ? NSNull() : "target_window_not_on_active_display"
        ]
        if captureAllowed {
            do {
                let captured = try captureTargetWindowImage(window: window, target: target)
                response["captureProbeOk"] = true
                response["captureProbeBackend"] = captured.backend
                response["captureProbeImage"] = ["width": captured.image.width, "height": captured.image.height]
                let stats = visualStats(for: captured.image)
                response["captureVisualStats"] = stats
                response["captureProbeUsableForVision"] = imageUsableForVision(stats)
                if !imageUsableForVision(stats) { response["stopReason"] = "target_window_capture_unusable" }
                if !captured.fallbackErrors.isEmpty { response["captureFallbackErrors"] = captured.fallbackErrors }
            } catch {
                response["captureProbeOk"] = false
                response["captureProbeError"] = "\(error)"
                if visibleOnDisplay { response["stopReason"] = "target_window_capture_failed" }
            }
        } else {
            response["captureProbeOk"] = false
            response["captureProbeError"] = "screen_capture_permission_required"
            if visibleOnDisplay { response["stopReason"] = "screen_capture_permission_required" }
        }
        printJSON(response)
    case "capture-permission":
        printJSON(["ok": true, "diagnostic": command, "allowed": CGPreflightScreenCaptureAccess()])
    case "request-capture-permission":
        printJSON(["ok": true, "diagnostic": command, "allowed": CGRequestScreenCaptureAccess()])
    case "capabilities":
        // @integration section 7 Capability Preflight.
        // Read-only aggregate of runtime prerequisites a host should check before orchestrating.
        // Never prompts for permission (unlike request-capture-permission). targetWindowResolved
        // is best-effort: present only when a target is configured and its window is found.
        var capabilities: [String: Any] = [
            "ok": true,
            "diagnostic": command,
            "swiftAvailable": true,
            "cliclickPath": cliclickPath() ?? NSNull(),
            "screenCapturePermission": CGPreflightScreenCaptureAccess(),
            "activeDisplays": activeDisplays()
        ]
        if target.bundleID != nil || !target.ownerNames.isEmpty {
            if let window = try? targetWindow(target) {
                capabilities["targetWindowResolved"] = true
                capabilities["window"] = ["x": window.x, "y": window.y, "width": window.width, "height": window.height, "windowID": window.windowID]
                capabilities["windowOnActiveDisplay"] = windowOnActiveDisplay(window)
            } else {
                capabilities["targetWindowResolved"] = false
            }
        }
        printJSON(capabilities)
    default:
        throw ActionError.usage(usage())
    }
}

// @integration section 4 Error Envelope.
// Top-level failure path: emit the machine-readable envelope on stdout (for hosts) AND the human
// message on stderr (for terminals), then exit non-zero. ActionError carries a stable reason code;
// any other error falls back to "internal_error".
do {
    try main()
} catch let error as ActionError {
    printJSON(errorEnvelope(reason: error.reasonCode, message: error.description))
    fputs("\(error)\n", stderr)
    exit(1)
} catch {
    printJSON(errorEnvelope(reason: "internal_error", message: "\(error)"))
    fputs("\(error)\n", stderr)
    exit(1)
}
