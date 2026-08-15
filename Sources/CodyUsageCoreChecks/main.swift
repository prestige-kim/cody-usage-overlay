import Foundation
import CodyUsageCore

enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(String)
    var description: String { if case .mismatch(let value) = self { return value }; return "check failed" }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.mismatch(message) }
}

func writeRollout(file: URL, source: String, total: Int, weeklyUsed: Int? = nil) throws {
    var tokenPayload: [String: Any] = [
        "type": "token_count",
        "info": ["last_token_usage": ["total_tokens": total], "model_context_window": 100_000],
    ]
    if let weeklyUsed {
        tokenPayload["rate_limits"] = [
            "limit_id": "codex",
            "primary": ["used_percent": weeklyUsed, "window_minutes": 10_080, "resets_at": 2_000_000_000],
        ]
    }
    let lines: [[String: Any]] = [
        ["type": "session_meta", "payload": ["id": "root", "originator": source == "vscode" ? "Codex Desktop" : "codex-tui", "source": source]],
        ["type": "event_msg", "payload": tokenPayload],
    ]
    let data = try lines.map { try JSONSerialization.data(withJSONObject: $0) + Data([0x0A]) }.reduce(Data(), +)
    try data.write(to: file)
}

do {
    let reversed: [String: Any] = ["rateLimits": [
        "primary": ["usedPercent": 22, "windowDurationMins": 10_080],
        "secondary": ["usedPercent": 7, "windowDurationMins": 300],
    ]]
    let parsed = try RateLimitParser.parse(reversed)
    try expect(parsed.fiveHour?.remainingPercent == 93, "5h duration classification")
    try expect(parsed.weekly?.remainingPercent == 78, "weekly duration classification")

    let multi: [String: Any] = ["rateLimitsByLimitId": ["codex": [
        "primary": ["usedPercent": 40, "window_minutes": 300],
        "secondary": ["usedPercent": 50, "window_minutes": 10_080],
    ]]]
    let multiParsed = try RateLimitParser.parse(multi)
    try expect(multiParsed.fiveHour?.remainingPercent == 60, "multi limit id")

    let modelSpecific: [String: Any] = ["rateLimitsByLimitId": [
        "codex_spark": ["primary": ["usedPercent": 0, "windowDurationMins": 10_080]],
        "codex": ["primary": ["usedPercent": 18, "windowDurationMins": 10_080]],
    ]]
    let modelSpecificParsed = try RateLimitParser.parse(modelSpecific)
    try expect(modelSpecificParsed.weekly?.remainingPercent == 82, "prefer canonical codex bucket")

    let context = ContextUsage(threadId: "root", usedTokens: 25_000, modelContextWindow: 100_000, updatedAt: Date())
    try expect(context.remainingPercent == 75, "context calculation")

    let executableCandidates = AppServerClient.candidateExecutableURLs(
        homeDirectory: URL(fileURLWithPath: "/Users/tester"),
        environmentPath: "/custom/bin:/opt/homebrew/bin"
    ).map(\.path)
    try expect(executableCandidates.contains("/Applications/ChatGPT.app/Contents/Resources/codex"), "system ChatGPT app candidate")
    try expect(!executableCandidates.contains("/Users/tester/Applications/Codex.app/Contents/Resources/codex"), "legacy Codex app candidate removed")
    try expect(executableCandidates.contains("/Users/tester/.local/bin/codex"), "user CLI candidate")
    try expect(executableCandidates.contains("/custom/bin/codex"), "PATH CLI candidate")
    try expect(executableCandidates.filter { $0 == "/opt/homebrew/bin/codex" }.count == 1, "candidate paths must be deduplicated")

    let appStoreRoot = FileManager.default.temporaryDirectory
        .resolvingSymlinksInPath()
        .appendingPathComponent("cody-app-store-check-\(UUID().uuidString)")
    let renamedApp = appStoreRoot.appendingPathComponent("OpenAI Desktop.app")
    let contents = renamedApp.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info = try PropertyListSerialization.data(
        fromPropertyList: ["CFBundleIdentifier": "com.openai.codex"],
        format: .xml,
        options: 0
    )
    try info.write(to: contents.appendingPathComponent("Info.plist"))
    defer { try? FileManager.default.removeItem(at: appStoreRoot) }
    let appStoreCandidates = AppServerClient.candidateExecutableURLs(
        homeDirectory: URL(fileURLWithPath: "/Users/tester"),
        environmentPath: "",
        applicationRoots: [appStoreRoot]
    ).map(\.path)
    try expect(
        appStoreCandidates.contains { $0.hasSuffix("/OpenAI Desktop.app/Contents/Resources/codex") },
        "App Store bundle identifier candidate"
    )

    var visibility = OverlayVisibilityController()
    visibility.dismiss(petIsVisible: true)
    try expect(!visibility.update(petIsVisible: true), "dismissed overlay stays hidden while pet remains visible")
    try expect(!visibility.update(petIsVisible: false), "dismissed overlay waits while pet is hidden")
    try expect(visibility.update(petIsVisible: true), "overlay returns when pet is shown again")

    var hiddenWithoutPet = OverlayVisibilityController()
    hiddenWithoutPet.dismiss(petIsVisible: false)
    try expect(!hiddenWithoutPet.update(petIsVisible: false), "manual overlay remains hidden without pet")
    try expect(hiddenWithoutPet.update(petIsVisible: true), "manual overlay returns on next pet appearance")

    let oppositeAbove = OverlayGeometry.oppositeActivityOriginY(
        petCenterY: 500,
        activityCenterY: 350,
        lastActivityDistance: nil,
        panelHeight: 62,
        visibleScreenMinY: 0,
        visibleScreenMaxY: 900
    )
    try expect(oppositeAbove == 619, "activity below pet must place overlay equally far above")

    let oppositeBelow = OverlayGeometry.oppositeActivityOriginY(
        petCenterY: 400,
        activityCenterY: 550,
        lastActivityDistance: nil,
        panelHeight: 62,
        visibleScreenMinY: 0,
        visibleScreenMaxY: 900
    )
    try expect(oppositeBelow == 219, "activity above pet must place overlay equally far below")

    let clampedOrigin = OverlayGeometry.oppositeActivityOriginY(
        petCenterY: 40,
        activityCenterY: 200,
        lastActivityDistance: nil,
        panelHeight: 62,
        visibleScreenMinY: 20,
        visibleScreenMaxY: 900
    )
    try expect(clampedOrigin == 24, "overlay must stay inside the visible screen")

    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try writeRollout(file: tempRoot.appendingPathComponent("rollout-root-thread.jsonl"), source: "vscode", total: 25_000, weeklyUsed: 18)
    try writeRollout(file: tempRoot.appendingPathComponent("rollout-cli-thread.jsonl"), source: "cli", total: 100_000)
    let usage = RolloutReader(sessionsRoot: tempRoot).refresh()
    try expect(usage?.usedTokens == 25_000, "root rollout selection")
    try expect(usage?.rateLimits?.weekly?.remainingPercent == 82, "rollout rate-limit fallback")
    print("All CodyUsageCore checks passed.")
} catch {
    fputs("Check failed: \(error)\n", stderr)
    exit(1)
}
