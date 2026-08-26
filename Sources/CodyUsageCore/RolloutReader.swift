import Foundation

public final class RolloutReader: @unchecked Sendable {
    private let sessionsRoot: URL
    private var offsets: [URL: UInt64] = [:]
    private var activeFile: URL?
    private var latestUsageByFile: [URL: ContextUsage] = [:]
    private var codyStateByFile: [URL: (state: CodyState, updatedAt: Date)] = [:]
    private var pulseEventsByFile: [URL: [AgentPulseEvent]] = [:]
    private let timestampFormatter = ISO8601DateFormatter()
    private let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")) {
        self.sessionsRoot = sessionsRoot
    }

    public func refresh() -> ContextUsage? {
        guard let file = newestDesktopRootRollout() else { return nil }
        if activeFile != file { activeFile = file; offsets[file] = 0 }
        return readLatestUsage(from: file)
    }

    public func refresh(changedPaths: [String]) -> ContextUsage? {
        var selected = activeFile
        var selectedDate = selected.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate } ?? .distantPast
        for path in changedPaths where path.hasSuffix(".jsonl") {
            let candidate = URL(fileURLWithPath: path)
            guard isDesktopRoot(candidate),
                  let date = try? candidate.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date >= selectedDate else { continue }
            selected = candidate; selectedDate = date
        }
        guard let file = selected else { return refresh() }
        if activeFile != file { activeFile = file; offsets[file] = 0 }
        return readLatestUsage(from: file)
    }

    public func refreshActive() -> ContextUsage? {
        guard let activeFile else { return refresh() }
        return readLatestUsage(from: activeFile) ?? refreshPulseIfNeeded(for: activeFile)
    }

    public func newestDesktopRootRollout() -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var candidates: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard isDesktopRoot(url),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate else { continue }
            candidates.append((url, modified))
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    private func isDesktopRoot(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 128 * 1024),
              let firstLine = data.split(separator: 0x0A).first,
              let object = try? JSONSerialization.jsonObject(with: Data(firstLine)) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return false }
        return payload["originator"] as? String == "Codex Desktop" && payload["source"] as? String == "vscode"
    }

    private func readLatestUsage(from url: URL) -> ContextUsage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let recordedOffset = offsets[url] ?? 0
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let start = recordedOffset <= fileSize ? recordedOffset : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        // FSEvents can arrive between two writes that make up one JSONL record.
        // Advance only through the last complete line so the unfinished suffix
        // is read again when the writer appends the rest of the record.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return nil }
        let completeEnd = data.index(after: lastNewline)
        let completeByteCount = data.distance(from: data.startIndex, to: completeEnd)
        offsets[url] = start + UInt64(completeByteCount)
        let completeData = data.prefix(completeByteCount)

        let threadId = url.deletingPathExtension().lastPathComponent.split(separator: "-").suffix(5).joined(separator: "-")
        var latest = latestUsageByFile[url]
        var activity = codyStateByFile[url] ?? (latest?.codyState ?? .ready, latest?.codyStateUpdatedAt ?? Date())
        var activityChanged = false
        var pulseEvents = pulseEventsByFile[url] ?? []
        var pulseEventsChanged = false
        for line in completeData.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let eventDate = eventTimestamp(from: object) ?? Date()
            if let pulseEvent = agentPulseEvent(from: object, timestamp: eventDate) {
                pulseEvents.append(pulseEvent)
                pulseEventsChanged = true
            }
            if let nextState = codyState(from: object, current: activity.state), nextState != activity.state {
                activity = (nextState, eventDate)
                activityChanged = true
            }
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let total = (last["total_tokens"] as? NSNumber)?.intValue,
                  let window = (info["model_context_window"] as? NSNumber)?.intValue else { continue }
            let rawLimits = payload["rate_limits"] as? [String: Any] ?? info["rate_limits"] as? [String: Any]
            let rateLimits = rawLimits.flatMap { try? RateLimitParser.parse(["rateLimits": $0]) }
            latest = ContextUsage(
                threadId: threadId,
                usedTokens: total,
                modelContextWindow: window,
                updatedAt: Date(),
                rateLimits: rateLimits,
                codyState: activity.state,
                codyStateUpdatedAt: activity.updatedAt
            )
        }
        let cutoff = Date().addingTimeInterval(-600)
        pulseEvents.removeAll { $0.timestamp < cutoff }
        pulseEventsByFile[url] = pulseEvents
        if (activityChanged || pulseEventsChanged), let existing = latest {
            latest = ContextUsage(
                threadId: existing.threadId,
                usedTokens: existing.usedTokens,
                modelContextWindow: existing.modelContextWindow,
                updatedAt: Date(),
                rateLimits: existing.rateLimits,
                codyState: activity.state,
                codyStateUpdatedAt: activity.updatedAt,
                agentPulse: existing.agentPulse,
                agentPulseReason: existing.agentPulseReason
            )
        }
        if let existing = latest {
            let evaluation = AgentPulseAnalyzer.evaluate(
                events: pulseEvents,
                codyState: activity.state,
                contextRemainingPercent: existing.remainingPercent
            )
            latest = ContextUsage(
                threadId: existing.threadId,
                usedTokens: existing.usedTokens,
                modelContextWindow: existing.modelContextWindow,
                updatedAt: existing.updatedAt,
                rateLimits: existing.rateLimits,
                codyState: activity.state,
                codyStateUpdatedAt: activity.updatedAt,
                agentPulse: evaluation.pulse,
                agentPulseReason: evaluation.reason
            )
        }
        codyStateByFile[url] = activity
        if let latest { latestUsageByFile[url] = latest }
        return latest
    }

    private func refreshPulseIfNeeded(for url: URL) -> ContextUsage? {
        guard let existing = latestUsageByFile[url] else { return nil }
        let evaluation = AgentPulseAnalyzer.evaluate(
            events: pulseEventsByFile[url] ?? [],
            codyState: existing.codyState,
            contextRemainingPercent: existing.remainingPercent
        )
        guard evaluation.pulse != existing.agentPulse || evaluation.reason != existing.agentPulseReason else { return nil }
        let updated = ContextUsage(
            threadId: existing.threadId,
            usedTokens: existing.usedTokens,
            modelContextWindow: existing.modelContextWindow,
            updatedAt: Date(),
            rateLimits: existing.rateLimits,
            codyState: existing.codyState,
            codyStateUpdatedAt: existing.codyStateUpdatedAt,
            agentPulse: evaluation.pulse,
            agentPulseReason: evaluation.reason
        )
        latestUsageByFile[url] = updated
        return updated
    }

    private func eventTimestamp(from object: [String: Any]) -> Date? {
        guard let raw = object["timestamp"] as? String else { return nil }
        return fractionalTimestampFormatter.date(from: raw) ?? timestampFormatter.date(from: raw)
    }

    private func agentPulseEvent(from object: [String: Any], timestamp: Date) -> AgentPulseEvent? {
        guard let recordType = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return nil }
        let payloadType = payload["type"] as? String

        if recordType == "response_item" {
            switch payloadType {
            case "custom_tool_call", "function_call":
                let name = (payload["name"] as? String ?? "").lowercased()
                let kind: AgentPulseEventKind = name.contains("request_user_input") || name.contains("request_permissions")
                    ? .waiting : .toolCall
                return AgentPulseEvent(kind: kind, timestamp: timestamp)
            case "custom_tool_call_output", "function_call_output":
                return AgentPulseEvent(kind: .toolResult, timestamp: timestamp)
            default:
                return nil
            }
        }

        guard recordType == "event_msg" else { return nil }
        switch payloadType {
        case "task_started":
            return AgentPulseEvent(kind: .taskStarted, timestamp: timestamp)
        case "task_complete":
            return AgentPulseEvent(kind: .complete, timestamp: timestamp)
        case "error", "turn_aborted", "task_failed":
            return AgentPulseEvent(kind: .error, timestamp: timestamp)
        case "item_completed":
            guard let item = payload["item"] as? [String: Any] else { return nil }
            if (item["status"] as? String)?.lowercased() == "failed" {
                return AgentPulseEvent(kind: .error, timestamp: timestamp)
            }
            let itemType = (item["type"] as? String ?? "").lowercased()
            if itemType == "reasoning" { return AgentPulseEvent(kind: .reasoning, timestamp: timestamp) }
            let workItems = ["commandexecution", "filechange", "mcptoolcall", "dynamictoolcall", "extension", "imageview"]
            return workItems.contains(itemType) ? AgentPulseEvent(kind: .toolResult, timestamp: timestamp) : nil
        case "token_count":
            guard let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let total = (last["total_tokens"] as? NSNumber)?.intValue,
                  let window = (info["model_context_window"] as? NSNumber)?.intValue else { return nil }
            return AgentPulseEvent(kind: .tokenSample(total: total, contextWindow: window), timestamp: timestamp)
        default:
            return nil
        }
    }

    private func codyState(from object: [String: Any], current: CodyState) -> CodyState? {
        guard let recordType = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return nil }
        let payloadType = payload["type"] as? String

        if recordType == "response_item" {
            switch payloadType {
            case "custom_tool_call", "function_call":
                let name = (payload["name"] as? String ?? "").lowercased()
                return name.contains("request_user_input") || name.contains("request_permissions") ? .waiting : .acting
            case "custom_tool_call_output", "function_call_output":
                return current == .waiting ? .thinking : .acting
            default:
                return nil
            }
        }

        guard recordType == "event_msg" else { return nil }
        switch payloadType {
        case "task_started":
            return .thinking
        case "task_complete":
            return .complete
        case "error", "turn_aborted", "task_failed":
            return .error
        case "item_completed":
            guard let item = payload["item"] as? [String: Any] else { return nil }
            if (item["status"] as? String)?.lowercased() == "failed" { return .error }
            let itemType = (item["type"] as? String ?? "").lowercased()
            if itemType == "reasoning" { return .thinking }
            let workItems = ["commandexecution", "filechange", "mcptoolcall", "dynamictoolcall", "extension", "imageview"]
            return workItems.contains(itemType) ? .acting : nil
        default:
            return nil
        }
    }
}
