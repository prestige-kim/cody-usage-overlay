import Foundation
import CodyUsageCore

enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(String)
    var description: String { if case .mismatch(let value) = self { return value }; return "check failed" }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.mismatch(message) }
}

func rolloutData(source: String, total: Int, weeklyUsed: Int? = nil) throws -> Data {
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
    return try lines.map { try JSONSerialization.data(withJSONObject: $0) + Data([0x0A]) }.reduce(Data(), +)
}

func writeRollout(file: URL, source: String, total: Int, weeklyUsed: Int? = nil) throws {
    try rolloutData(source: source, total: total, weeklyUsed: weeklyUsed).write(to: file)
}

func appendRolloutLine(_ object: [String: Any], to file: URL) throws {
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: JSONSerialization.data(withJSONObject: object) + Data([0x0A]))
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
    try expect(CodyState.ready.displayName == "준비됨", "ready state label")
    try expect(CodyState.thinking.displayName == "생각 중", "thinking state label")
    try expect(CodyState.acting.displayName == "도구 실행 중", "acting state label")
    try expect(CodyState.waiting.displayName == "입력 대기", "waiting state label")
    try expect(CodyState.complete.displayName == "완료", "complete state label")
    try expect(CodyState.error.displayName == "확인 필요", "error state label")
    try expect(AgentPulse.steady.displayName == "원활", "steady pulse label")
    try expect(AgentPulse.active.displayName == "활발", "active pulse label")
    try expect(AgentPulse.overloaded.displayName == "과부하", "overloaded pulse label")
    try expect(AgentPulse.stalled.displayName == "정체", "stalled pulse label")
    try expect(AgentPulse.unstable.displayName == "불안정", "unstable pulse label")
    try expect(AgentPulse.finishing.displayName == "마무리", "finishing pulse label")
    let stateNow = Date(timeIntervalSince1970: 10_000)
    try expect(
        CodyStatePolicy.visibleState(.complete, updatedAt: stateNow, now: stateNow.addingTimeInterval(2.9)) == .complete,
        "complete state remains visible for three seconds"
    )
    try expect(
        CodyStatePolicy.visibleState(.complete, updatedAt: stateNow, now: stateNow.addingTimeInterval(3)) == .ready,
        "complete state returns to ready"
    )
    try expect(
        CodyStatePolicy.visibleState(.error, updatedAt: stateNow, now: stateNow.addingTimeInterval(30)) == .error,
        "error state stays visible until a new task"
    )

    let pulseNow = Date(timeIntervalSince1970: 20_000)
    try expect(
        AgentPulseAnalyzer.evaluate(events: [], codyState: .ready, contextRemainingPercent: 80, now: pulseNow).pulse == .steady,
        "idle agent pulse is steady"
    )
    try expect(
        AgentPulseAnalyzer.evaluate(events: [], codyState: .thinking, contextRemainingPercent: 80, now: pulseNow).pulse == .active,
        "active reasoning produces an active pulse"
    )
    let stalledEvents = [AgentPulseEvent(kind: .taskStarted, timestamp: pulseNow.addingTimeInterval(-46))]
    try expect(
        AgentPulseAnalyzer.evaluate(events: stalledEvents, codyState: .thinking, contextRemainingPercent: 80, now: pulseNow).pulse == .stalled,
        "active task without progress becomes stalled"
    )
    try expect(
        AgentPulseAnalyzer.evaluate(events: stalledEvents, codyState: .waiting, contextRemainingPercent: 80, now: pulseNow).pulse == .steady,
        "explicit input waiting is not stalled"
    )
    let toolBurst = (0..<8).map {
        AgentPulseEvent(kind: .toolCall, timestamp: pulseNow.addingTimeInterval(Double(-$0)))
    }
    try expect(
        AgentPulseAnalyzer.evaluate(events: toolBurst, codyState: .acting, contextRemainingPercent: 80, now: pulseNow).pulse == .overloaded,
        "tool burst produces overloaded pulse"
    )
    let repeatedErrors = [
        AgentPulseEvent(kind: .error, timestamp: pulseNow.addingTimeInterval(-10)),
        AgentPulseEvent(kind: .error, timestamp: pulseNow.addingTimeInterval(-2)),
    ]
    try expect(
        AgentPulseAnalyzer.evaluate(events: repeatedErrors, codyState: .thinking, contextRemainingPercent: 80, now: pulseNow).pulse == .unstable,
        "repeated errors produce unstable pulse"
    )
    try expect(
        AgentPulseAnalyzer.evaluate(events: [], codyState: .complete, contextRemainingPercent: 80, now: pulseNow).pulse == .finishing,
        "completed task produces finishing pulse"
    )
    let tokenBurn = [
        AgentPulseEvent(kind: .tokenSample(total: 5_000, contextWindow: 100_000), timestamp: pulseNow.addingTimeInterval(-240)),
        AgentPulseEvent(kind: .tokenSample(total: 18_000, contextWindow: 100_000), timestamp: pulseNow),
    ]
    try expect(
        AgentPulseAnalyzer.evaluate(events: tokenBurn, codyState: .thinking, contextRemainingPercent: 82, now: pulseNow).reason == "컨텍스트 소모 빠름",
        "fast context burn is explained"
    )

    let countdownNow = Date(timeIntervalSince1970: 1_000_000)
    let countdown = ResetCountdownFormatter.make(
        fiveHourResetsAt: countdownNow.addingTimeInterval(2 * 3_600 + 18 * 60 + 43),
        weeklyResetsAt: countdownNow.addingTimeInterval(3 * 86_400 + 14 * 3_600 + 22 * 60 + 59),
        now: countdownNow
    )
    try expect(countdown.fiveHourText == "02:18:43", "five-hour countdown formatting")
    try expect(countdown.weeklyText == "3일 14:22", "weekly countdown formatting")
    try expect(!countdown.hasExpiredReset, "future reset must not request a refresh")
    let expiredCountdown = ResetCountdownFormatter.make(
        fiveHourResetsAt: countdownNow.addingTimeInterval(-1),
        weeklyResetsAt: nil,
        now: countdownNow
    )
    try expect(expiredCountdown.fiveHourText == "갱신 중…", "expired reset state")
    try expect(expiredCountdown.weeklyText == "—", "missing reset state")
    try expect(expiredCountdown.hasExpiredReset, "expired reset must request a refresh")

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
    visibility.dismiss()
    try expect(!visibility.update(petIsVisible: true), "dismissed overlay stays hidden while pet remains visible")
    try expect(!visibility.update(petIsVisible: false), "pet detector loss must not change dismissed state")
    visibility.show()
    try expect(visibility.update(petIsVisible: false), "explicit show must work without a detected pet")

    let legacyConfigData = Data("""
    {"launchAtLogin":true,"anchorMode":"petWindow","offsetX":4,"offsetY":12,"clickThrough":false,"warningThreshold":30,"criticalThreshold":10}
    """.utf8)
    let migratedConfig = try JSONDecoder().decode(OverlayConfig.self, from: legacyConfigData)
    try expect(migratedConfig.overlayVisible, "legacy config must default overlay visibility to visible")
    try expect(migratedConfig.manualPositionX == nil, "legacy config must decode without manual position")
    try expect(!migratedConfig.clickThrough, "legacy click-through preference must be preserved")

    let legacyPetWindow = OverlayWindowSnapshot(
        id: 1,
        rect: CGRect(x: 100, y: 100, width: 192, height: 208),
        layer: 0,
        alpha: 1,
        name: "Pet Mascot Effect"
    )
    let nativePetWindow = OverlayWindowSnapshot(
        id: 2,
        rect: CGRect(x: 200, y: 200, width: 84, height: 77),
        layer: 3,
        alpha: 1,
        name: ""
    )
    let pointerHitArea = OverlayWindowSnapshot(
        id: 3,
        rect: CGRect(x: 210, y: 210, width: 59, height: 19),
        layer: 103,
        alpha: 0.1,
        name: ""
    )
    try expect(
        PetWindowSelector.select(from: [pointerHitArea, nativePetWindow])?.id == nativePetWindow.id,
        "native composition mascot panel must beat the transient pointer hit area"
    )
    try expect(
        PetWindowSelector.select(from: [nativePetWindow, legacyPetWindow])?.id == legacyPetWindow.id,
        "explicit legacy mascot title must remain supported"
    )
    try expect(
        PetWindowSelector.select(from: [legacyPetWindow, nativePetWindow], trackedWindowID: nativePetWindow.id)?.id == nativePetWindow.id,
        "tracked mascot panel must stay stable while dragging"
    )

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

    let clampedPoint = OverlayGeometry.clampedOrigin(
        x: 990,
        y: -20,
        panelWidth: 242,
        panelHeight: 62,
        visibleScreenFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
    )
    try expect(clampedPoint.x == 754 && clampedPoint.y == 4, "manual offsets must remain reachable on screen")

    let draggedPoint = OverlayGeometry.draggedOrigin(
        windowOrigin: CGPoint(x: 200, y: 300),
        dragStart: CGPoint(x: 400, y: 500),
        currentPointer: CGPoint(x: 475, y: 460)
    )
    try expect(draggedPoint.x == 275 && draggedPoint.y == 260, "custom panel drag must preserve pointer delta")

    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }
    try writeRollout(file: tempRoot.appendingPathComponent("rollout-root-thread.jsonl"), source: "vscode", total: 25_000, weeklyUsed: 18)
    try writeRollout(file: tempRoot.appendingPathComponent("rollout-cli-thread.jsonl"), source: "cli", total: 100_000)
    let rolloutReader = RolloutReader(sessionsRoot: tempRoot)
    let usage = rolloutReader.refresh()
    try expect(usage?.usedTokens == 25_000, "root rollout selection")
    try expect(usage?.rateLimits?.weekly?.remainingPercent == 82, "rollout rate-limit fallback")

    let rootFile = tempRoot.appendingPathComponent("rollout-root-thread.jsonl")
    try appendRolloutLine(["type": "event_msg", "payload": ["type": "task_started"]], to: rootFile)
    try expect(rolloutReader.refresh(changedPaths: [rootFile.path])?.codyState == .thinking, "task start maps to thinking")
    try appendRolloutLine([
        "type": "response_item",
        "payload": ["type": "custom_tool_call", "name": "exec", "call_id": "call-1", "status": "completed"],
    ], to: rootFile)
    let actingUsage = rolloutReader.refresh(changedPaths: [rootFile.path])
    try expect(actingUsage?.codyState == .acting, "tool call maps to acting")
    try expect(actingUsage?.agentPulse == .active, "tool activity maps to active agent pulse")
    try appendRolloutLine([
        "type": "response_item",
        "payload": ["type": "custom_tool_call_output", "call_id": "call-1", "output": "ok"],
    ], to: rootFile)
    try expect(rolloutReader.refresh(changedPaths: [rootFile.path])?.codyState == .acting, "tool result remains acting until reasoning resumes")
    try appendRolloutLine([
        "type": "event_msg",
        "payload": ["type": "item_completed", "item": ["type": "Reasoning"]],
    ], to: rootFile)
    try expect(rolloutReader.refresh(changedPaths: [rootFile.path])?.codyState == .thinking, "reasoning event restores thinking")
    try appendRolloutLine([
        "type": "response_item",
        "payload": ["type": "custom_tool_call", "name": "request_user_input", "call_id": "call-2", "status": "completed"],
    ], to: rootFile)
    try expect(rolloutReader.refresh(changedPaths: [rootFile.path])?.codyState == .waiting, "input request maps to waiting")
    try appendRolloutLine([
        "type": "event_msg",
        "payload": ["type": "item_completed", "item": ["type": "CommandExecution", "status": "failed"]],
    ], to: rootFile)
    try expect(rolloutReader.refresh(changedPaths: [rootFile.path])?.codyState == .error, "failed work item maps to error")
    try appendRolloutLine(["type": "event_msg", "payload": ["type": "task_started"]], to: rootFile)
    try expect(rolloutReader.refresh(changedPaths: [rootFile.path])?.codyState == .thinking, "new task clears error state")
    try appendRolloutLine(["type": "event_msg", "payload": ["type": "task_complete"]], to: rootFile)
    let completedUsage = rolloutReader.refreshActive()
    try expect(completedUsage?.codyState == .complete, "active rollout polling captures task completion")
    try expect(completedUsage?.agentPulse == .finishing, "task completion maps to finishing agent pulse")

    let timestampRoot = tempRoot.appendingPathComponent("timestamps")
    try FileManager.default.createDirectory(at: timestampRoot, withIntermediateDirectories: true)
    let timestampFile = timestampRoot.appendingPathComponent("rollout-timestamp-thread.jsonl")
    try writeRollout(file: timestampFile, source: "vscode", total: 10_000)
    try appendRolloutLine([
        "timestamp": "2020-01-01T00:00:00.123Z",
        "type": "event_msg",
        "payload": ["type": "error"],
    ], to: timestampFile)
    try appendRolloutLine([
        "timestamp": "2020-01-01T00:00:01.456Z",
        "type": "event_msg",
        "payload": ["type": "error"],
    ], to: timestampFile)
    try appendRolloutLine([
        "type": "event_msg",
        "payload": ["type": "task_started"],
    ], to: timestampFile)
    let timestampReader = RolloutReader(sessionsRoot: timestampRoot)
    try expect(
        timestampReader.refresh()?.agentPulse != .unstable,
        "fractional ISO timestamps keep historical errors outside the pulse window"
    )

    let incrementalRoot = tempRoot.appendingPathComponent("incremental")
    try FileManager.default.createDirectory(at: incrementalRoot, withIntermediateDirectories: true)
    let incrementalFile = incrementalRoot.appendingPathComponent("rollout-incremental-thread.jsonl")
    let incrementalData = try rolloutData(source: "vscode", total: 30_000)
    let finalLineStart = incrementalData.dropLast().lastIndex(of: 0x0A).map { incrementalData.index(after: $0) }
        ?? incrementalData.startIndex
    let splitIndex = incrementalData.index(
        finalLineStart,
        offsetBy: incrementalData.distance(from: finalLineStart, to: incrementalData.endIndex) / 2
    )
    try incrementalData[..<splitIndex].write(to: incrementalFile)
    let incrementalReader = RolloutReader(sessionsRoot: incrementalRoot)
    try expect(incrementalReader.refresh() == nil, "partial rollout record must wait for completion")
    let incrementalHandle = try FileHandle(forWritingTo: incrementalFile)
    try incrementalHandle.seekToEnd()
    try incrementalHandle.write(contentsOf: incrementalData[splitIndex...])
    try incrementalHandle.close()
    try expect(incrementalReader.refresh()?.usedTokens == 30_000, "completed rollout record must be re-read")

    try writeRollout(file: incrementalFile, source: "vscode", total: 5_000)
    try expect(incrementalReader.refresh()?.usedTokens == 5_000, "truncated rollout file must reset its offset")
    print("All CodyUsageCore checks passed.")
} catch {
    fputs("Check failed: \(error)\n", stderr)
    exit(1)
}
