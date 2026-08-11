import Foundation

public enum RateLimitParserError: Error { case invalidPayload }

public enum RateLimitParser {
    public static func parse(data: Data) throws -> RateLimitResult {
        try parse(JSONSerialization.jsonObject(with: data))
    }

    public static func parse(_ value: Any) throws -> RateLimitResult {
        guard let root = value as? [String: Any] else { throw RateLimitParserError.invalidPayload }
        var snapshots: [[String: Any]] = []
        if let buckets = root["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            snapshots.append(codex)
        } else if let single = root["rateLimits"] as? [String: Any] {
            snapshots.append(single)
        } else if let buckets = root["rateLimitsByLimitId"] as? [String: Any] {
            snapshots.append(contentsOf: buckets.values.compactMap { $0 as? [String: Any] })
        }

        var windows: [RateLimitWindow] = []
        for snapshot in snapshots {
            for key in ["primary", "secondary"] {
                guard let raw = snapshot[key] as? [String: Any],
                      let used = integer(raw["usedPercent"] ?? raw["used_percent"]) else { continue }
                let duration = integer(raw["windowDurationMins"] ?? raw["window_minutes"])
                let resetSeconds = integer(raw["resetsAt"] ?? raw["resets_at"])
                windows.append(RateLimitWindow(
                    usedPercent: used,
                    windowDurationMinutes: duration,
                    resetsAt: resetSeconds.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                ))
            }
        }

        let unique = Array(Set(windows.map(WindowKey.init))).map(\.window)
        return RateLimitResult(
            fiveHour: closest(in: unique, target: 300, tolerance: 180),
            weekly: closest(in: unique, target: 10_080, tolerance: 2_880)
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func closest(in windows: [RateLimitWindow], target: Int, tolerance: Int) -> RateLimitWindow? {
        windows
            .filter { $0.windowDurationMinutes != nil && abs($0.windowDurationMinutes! - target) <= tolerance }
            .min { abs($0.windowDurationMinutes! - target) < abs($1.windowDurationMinutes! - target) }
    }

    private struct WindowKey: Hashable {
        let used: Int
        let duration: Int?
        let reset: Int?
        let window: RateLimitWindow
        init(_ window: RateLimitWindow) {
            used = window.usedPercent
            duration = window.windowDurationMinutes
            reset = window.resetsAt.map { Int($0.timeIntervalSince1970) }
            self.window = window
        }
        static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
            lhs.used == rhs.used && lhs.duration == rhs.duration && lhs.reset == rhs.reset
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(used); hasher.combine(duration); hasher.combine(reset)
        }
    }
}
