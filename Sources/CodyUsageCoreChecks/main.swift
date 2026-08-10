import Foundation
import CodyUsageCore

enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(String)
    var description: String { if case .mismatch(let value) = self { return value }; return "check failed" }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.mismatch(message) }
}

func writeRollout(file: URL, source: String, total: Int) throws {
    let lines: [[String: Any]] = [
        ["type": "session_meta", "payload": ["id": "root", "originator": source == "vscode" ? "Codex Desktop" : "codex-tui", "source": source]],
        ["type": "event_msg", "payload": ["type": "token_count", "info": ["last_token_usage": ["total_tokens": total], "model_context_window": 100_000]]],
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

    let context = ContextUsage(threadId: "root", usedTokens: 25_000, modelContextWindow: 100_000, updatedAt: Date())
    try expect(context.remainingPercent == 75, "context calculation")

    for petHeight in [120.0, 200.0, 320.0] {
        let panelHeight = 62.0
        let origin = OverlayGeometry.panelOriginY(
            petWindowMinY: 100,
            petWindowHeight: petHeight,
            panelHeight: panelHeight,
            visibleScreenMinY: 0
        )
        let panelTop = origin + panelHeight
        let feetY = 100 + petHeight * OverlayGeometry.spaceBelowFeetRatio
        try expect(abs(panelTop - feetY - 2) < 0.001, "overlay must touch Cody's feet at every pet size")
    }

    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try writeRollout(file: tempRoot.appendingPathComponent("rollout-root-thread.jsonl"), source: "vscode", total: 25_000)
    try writeRollout(file: tempRoot.appendingPathComponent("rollout-cli-thread.jsonl"), source: "cli", total: 100_000)
    let usage = RolloutReader(sessionsRoot: tempRoot).refresh()
    try expect(usage?.usedTokens == 25_000, "root rollout selection")
    print("All CodyUsageCore checks passed.")
} catch {
    fputs("Check failed: \(error)\n", stderr)
    exit(1)
}
