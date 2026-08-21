import Foundation

public final class RolloutReader: @unchecked Sendable {
    private let sessionsRoot: URL
    private var offsets: [URL: UInt64] = [:]
    private var activeFile: URL?

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
        var latest: ContextUsage?
        for line in completeData.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
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
                rateLimits: rateLimits
            )
        }
        return latest
    }
}
