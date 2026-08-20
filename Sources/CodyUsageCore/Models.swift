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
    public enum State: Sendable { case visible, hidden }
    public private(set) var state: State

    public init(isVisible: Bool = true) {
        state = isVisible ? .visible : .hidden
    }

    public mutating func dismiss() {
        state = .hidden
    }

    public mutating func show() {
        state = .visible
    }

    @discardableResult
    public mutating func update(petIsVisible: Bool) -> Bool {
        state == .visible
    }
}

public struct OverlayConfig: Codable, Equatable, Sendable {
    public var launchAtLogin = true
    public var anchorMode = AnchorMode.petWindow
    public var offsetX: Double = 0
    public var offsetY: Double = 12
    public var clickThrough = false
    public var warningThreshold = 30
    public var criticalThreshold = 10
    public var overlayVisible = true
    public var manualPositionX: Double?
    public var manualPositionY: Double?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, anchorMode, offsetX, offsetY, clickThrough
        case warningThreshold, criticalThreshold, overlayVisible
        case manualPositionX, manualPositionY
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        anchorMode = try values.decodeIfPresent(AnchorMode.self, forKey: .anchorMode) ?? .petWindow
        offsetX = try values.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0
        offsetY = try values.decodeIfPresent(Double.self, forKey: .offsetY) ?? 12
        clickThrough = try values.decodeIfPresent(Bool.self, forKey: .clickThrough) ?? false
        warningThreshold = try values.decodeIfPresent(Int.self, forKey: .warningThreshold) ?? 30
        criticalThreshold = try values.decodeIfPresent(Int.self, forKey: .criticalThreshold) ?? 10
        overlayVisible = try values.decodeIfPresent(Bool.self, forKey: .overlayVisible) ?? true
        manualPositionX = try values.decodeIfPresent(Double.self, forKey: .manualPositionX)
        manualPositionY = try values.decodeIfPresent(Double.self, forKey: .manualPositionY)
    }
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
