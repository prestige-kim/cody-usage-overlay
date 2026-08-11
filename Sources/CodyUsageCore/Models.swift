import Foundation

public enum Freshness: String, Codable, Sendable {
    case fresh, delayed, unavailable, incompatible
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var contextRemainingPercent: Int?
    public var fiveHourRemainingPercent: Int?
    public var weeklyRemainingPercent: Int?
    public var fiveHourResetsAt: Date?
    public var weeklyResetsAt: Date?
    public var activeThreadId: String?
    public var lastUpdatedAt: Date
    public var freshness: Freshness

    public init(
        contextRemainingPercent: Int? = nil,
        fiveHourRemainingPercent: Int? = nil,
        weeklyRemainingPercent: Int? = nil,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil,
        activeThreadId: String? = nil,
        lastUpdatedAt: Date = Date(),
        freshness: Freshness = .unavailable
    ) {
        self.contextRemainingPercent = contextRemainingPercent
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyResetsAt = weeklyResetsAt
        self.activeThreadId = activeThreadId
        self.lastUpdatedAt = lastUpdatedAt
        self.freshness = freshness
    }
}

public enum AnchorMode: String, Codable, Sendable { case petWindow, mainWindow, manual }

public struct OverlayVisibilityController: Sendable {
    public enum State: Sendable { case visible, waitingForPetToDisappear, waitingForPetToAppear }
    public private(set) var state: State = .visible

    public init() {}

    public mutating func dismiss(petIsVisible: Bool) {
        state = petIsVisible ? .waitingForPetToDisappear : .waitingForPetToAppear
    }

    @discardableResult
    public mutating func update(petIsVisible: Bool) -> Bool {
        switch state {
        case .visible:
            return true
        case .waitingForPetToDisappear:
            if !petIsVisible { state = .waitingForPetToAppear }
            return false
        case .waitingForPetToAppear:
            if petIsVisible {
                state = .visible
                return true
            }
            return false
        }
    }
}

public struct OverlayConfig: Codable, Equatable, Sendable {
    public var launchAtLogin = true
    public var anchorMode = AnchorMode.petWindow
    public var offsetX: Double = 0
    public var offsetY: Double = 12
    public var clickThrough = true
    public var warningThreshold = 30
    public var criticalThreshold = 10

    public init() {}
}

public struct RateLimitWindow: Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public var remainingPercent: Int { max(0, min(100, 100 - usedPercent)) }
}

public struct RateLimitResult: Equatable, Sendable {
    public var fiveHour: RateLimitWindow?
    public var weekly: RateLimitWindow?
}

public struct ContextUsage: Equatable, Sendable {
    public let threadId: String
    public let usedTokens: Int
    public let modelContextWindow: Int
    public let updatedAt: Date
    public let rateLimits: RateLimitResult?
    public init(threadId: String, usedTokens: Int, modelContextWindow: Int, updatedAt: Date, rateLimits: RateLimitResult? = nil) {
        self.threadId = threadId
        self.usedTokens = usedTokens
        self.modelContextWindow = modelContextWindow
        self.updatedAt = updatedAt
        self.rateLimits = rateLimits
    }
    public var remainingPercent: Int {
        guard modelContextWindow > 0 else { return 0 }
        let ratio = 1 - Double(usedTokens) / Double(modelContextWindow)
        return max(0, min(100, Int((ratio * 100).rounded())))
    }
}
