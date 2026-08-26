import Foundation

public enum AgentPulse: String, Codable, Sendable {
    case steady, active, overloaded, stalled, unstable, finishing

    public var displayName: String {
        switch self {
        case .steady: "원활"
        case .active: "활발"
        case .overloaded: "과부하"
        case .stalled: "정체"
        case .unstable: "불안정"
        case .finishing: "마무리"
        }
    }
}

public enum AgentPulseEventKind: Sendable {
    case taskStarted
    case reasoning
    case toolCall
    case toolResult
    case waiting
    case error
    case complete
    case tokenSample(total: Int, contextWindow: Int)
}

public struct AgentPulseEvent: Sendable {
    public let kind: AgentPulseEventKind
    public let timestamp: Date

    public init(kind: AgentPulseEventKind, timestamp: Date) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

public struct AgentPulseEvaluation: Equatable, Sendable {
    public let pulse: AgentPulse
    public let reason: String

    public init(pulse: AgentPulse, reason: String) {
        self.pulse = pulse
        self.reason = reason
    }
}

public enum AgentPulseAnalyzer {
    public static func evaluate(
        events: [AgentPulseEvent],
        codyState: CodyState,
        contextRemainingPercent: Int?,
        now: Date = Date()
    ) -> AgentPulseEvaluation {
        let windowStart = now.addingTimeInterval(-300)
        let recent = events
            .filter { $0.timestamp >= windowStart && $0.timestamp <= now.addingTimeInterval(2) }
            .sorted { $0.timestamp < $1.timestamp }
        let errorCount = recent.filter { if case .error = $0.kind { true } else { false } }.count

        if codyState == .error || errorCount >= 2 {
            return AgentPulseEvaluation(
                pulse: .unstable,
                reason: errorCount >= 2 ? "오류 반복" : "오류 발생"
            )
        }
        if codyState == .complete {
            return AgentPulseEvaluation(pulse: .finishing, reason: "작업 완료")
        }

        let latestTaskStarted = recent.last { if case .taskStarted = $0.kind { true } else { false } }?.timestamp
        let latestTaskCompleted = recent.last { if case .complete = $0.kind { true } else { false } }?.timestamp
        let taskIsActive = latestTaskStarted.map { started in
            latestTaskCompleted.map { $0 < started } ?? true
        } ?? (codyState == .thinking || codyState == .acting)
        let progressKinds: (AgentPulseEventKind) -> Bool = { kind in
            switch kind {
            case .taskStarted, .reasoning, .toolCall, .toolResult: true
            default: false
            }
        }
        let latestProgress = recent.last { progressKinds($0.kind) }?.timestamp ?? latestTaskStarted
        if taskIsActive,
           codyState != .waiting,
           let latestProgress,
           now.timeIntervalSince(latestProgress) >= 45 {
            return AgentPulseEvaluation(pulse: .stalled, reason: "진행 이벤트 없음")
        }

        if let remaining = contextRemainingPercent, remaining <= 15 {
            return AgentPulseEvaluation(pulse: .overloaded, reason: "컨텍스트 소모 큼")
        }

        let burstStart = now.addingTimeInterval(-60)
        let burst = recent.filter { $0.timestamp >= burstStart }
        let toolCalls = burst.filter { if case .toolCall = $0.kind { true } else { false } }.count
        if toolCalls >= 8 {
            return AgentPulseEvaluation(pulse: .overloaded, reason: "도구 호출 급증")
        }
        let progressCount = burst.filter { progressKinds($0.kind) }.count
        if progressCount >= 18 {
            return AgentPulseEvaluation(pulse: .overloaded, reason: "이벤트 밀도 높음")
        }

        let samples: [(date: Date, total: Int, window: Int)] = recent.compactMap { event in
            guard case let .tokenSample(total, contextWindow) = event.kind else { return nil }
            return (event.timestamp, total, contextWindow)
        }
        if let first = samples.first, let last = samples.last, last.date > first.date {
            let burn = last.total - first.total
            let threshold = max(12_000, last.window * 8 / 100)
            if burn >= threshold {
                return AgentPulseEvaluation(pulse: .overloaded, reason: "컨텍스트 소모 빠름")
            }
        }

        if codyState == .thinking || codyState == .acting || progressCount >= 3 {
            return AgentPulseEvaluation(pulse: .active, reason: "안정적인 진행")
        }
        if codyState == .waiting {
            return AgentPulseEvaluation(pulse: .steady, reason: "입력 대기 · 정상")
        }
        return AgentPulseEvaluation(pulse: .steady, reason: "흐름 안정")
    }
}
