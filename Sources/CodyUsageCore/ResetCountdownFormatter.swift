import Foundation

public struct ResetCountdownDisplay: Equatable, Sendable {
    public let fiveHourText: String
    public let weeklyText: String
    public let hasExpiredReset: Bool

    public init(fiveHourText: String, weeklyText: String, hasExpiredReset: Bool) {
        self.fiveHourText = fiveHourText
        self.weeklyText = weeklyText
        self.hasExpiredReset = hasExpiredReset
    }
}

public enum ResetCountdownFormatter {
    public static func make(
        fiveHourResetsAt: Date?,
        weeklyResetsAt: Date?,
        now: Date = Date()
    ) -> ResetCountdownDisplay {
        let fiveHour = countdown(to: fiveHourResetsAt, now: now)
        let weekly = countdown(to: weeklyResetsAt, now: now)
        return ResetCountdownDisplay(
            fiveHourText: formatFiveHour(fiveHour.seconds, state: fiveHour.state),
            weeklyText: formatWeekly(weekly.seconds, state: weekly.state),
            hasExpiredReset: fiveHour.state == .expired || weekly.state == .expired
        )
    }

    private enum CountdownState { case available, missing, expired }

    private static func countdown(to reset: Date?, now: Date) -> (seconds: Int, state: CountdownState) {
        guard let reset else { return (0, .missing) }
        let interval = reset.timeIntervalSince(now)
        guard interval > 0 else { return (0, .expired) }
        return (Int(interval.rounded(.down)), .available)
    }

    private static func formatFiveHour(_ seconds: Int, state: CountdownState) -> String {
        guard state == .available else { return state == .expired ? "갱신 중…" : "—" }
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    private static func formatWeekly(_ seconds: Int, state: CountdownState) -> String {
        guard state == .available else { return state == .expired ? "갱신 중…" : "—" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        return days > 0
            ? String(format: "%d일 %02d:%02d", days, hours, minutes)
            : String(format: "%02d:%02d:%02d", hours, minutes, seconds % 60)
    }
}
