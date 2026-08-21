import Foundation

public final class UsageCoordinator: @unchecked Sendable {
    public typealias UpdateHandler = @Sendable (UsageSnapshot) -> Void

    private let client: AppServerClient
    private let rolloutReader: RolloutReader
    private let eventMonitor: SessionEventMonitor
    private let queue = DispatchQueue(label: "CodyUsageOverlay.Coordinator")
    private var timer: DispatchSourceTimer?
    private var snapshot = UsageSnapshot()
    private var updateHandler: UpdateHandler?
    private var retrySeconds: TimeInterval = 2
    private var retryWorkItem: DispatchWorkItem?
    private var rateLimitRefreshInFlight = false
    private var rateLimitRefreshPending = false
    private var lastRateLimitUpdate: Date?
    private var lastContextUpdate: Date?

    public init(client: AppServerClient = AppServerClient(), rolloutReader: RolloutReader = RolloutReader(), eventMonitor: SessionEventMonitor = SessionEventMonitor()) {
        self.client = client
        self.rolloutReader = rolloutReader
        self.eventMonitor = eventMonitor
        client.setNotificationHandler { [weak self] method, params in
            guard method == "account/rateLimits/updated" else { return }
            self?.applyRateLimits(params)
        }
    }

    public func onUpdate(_ handler: @escaping UpdateHandler) { queue.async { self.updateHandler = handler } }

    public func start() {
        queue.async { self.refreshContext() }
        eventMonitor.start { [weak self] paths in
            guard let self else { return }
            self.queue.async { self.refreshContext(changedPaths: paths) }
        }
        queue.async {
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 1)
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
        }
        refreshRateLimits()
    }

    public func stop() {
        eventMonitor.stop()
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.retryWorkItem?.cancel()
            self.retryWorkItem = nil
            self.rateLimitRefreshPending = false
        }
        Task { try? await client.stop() }
    }

    public func forceRefresh() { refreshRateLimits(force: true); queue.async { self.refreshContext() } }

    public func diagnostics() -> String {
        queue.sync {
            let executable = AppServerClient.locateExecutable()?.path ?? "missing"
            return "Codex: \(executable)\nThread: \(snapshot.activeThreadId ?? "unknown")\nFreshness: \(snapshot.freshness.rawValue)\nUpdated: \(snapshot.lastUpdatedAt)"
        }
    }

    private func tick() {
        if lastRateLimitUpdate == nil || Date().timeIntervalSince(lastRateLimitUpdate!) >= 60 { refreshRateLimits() }
        let newest = [lastRateLimitUpdate, lastContextUpdate].compactMap { $0 }.max() ?? .distantPast
        if Date().timeIntervalSince(newest) > 90 && snapshot.freshness == .fresh {
            snapshot.freshness = .delayed; publish()
        }
    }

    private func refreshContext() {
        if let usage = rolloutReader.refresh() {
            applyContext(usage)
        }
    }

    private func refreshContext(changedPaths: [String]) {
        if let usage = rolloutReader.refresh(changedPaths: changedPaths) {
            applyContext(usage)
        }
    }

    private func applyContext(_ usage: ContextUsage) {
            snapshot.contextRemainingPercent = usage.remainingPercent
            snapshot.activeThreadId = usage.threadId
            if let rateLimits = usage.rateLimits { mergeRateLimits(rateLimits) }
            lastContextUpdate = usage.updatedAt
            snapshot.lastUpdatedAt = Date()
            snapshot.freshness = .fresh
            publish()
    }

    private func refreshRateLimits(force: Bool = false) {
        queue.async { self.beginRateLimitRefresh(force: force) }
    }

    private func beginRateLimitRefresh(force: Bool) {
        if force {
            retryWorkItem?.cancel()
            retryWorkItem = nil
        } else if retryWorkItem != nil {
            return
        }
        guard !rateLimitRefreshInFlight else {
            if force { rateLimitRefreshPending = true }
            return
        }
        rateLimitRefreshInFlight = true
        Task {
            do {
                let raw = try await client.readRateLimits()
                queue.async {
                    self.rateLimitRefreshInFlight = false
                    self.retrySeconds = 2
                    self.applyRateLimitsOnQueue(raw)
                    self.runPendingRateLimitRefreshIfNeeded()
                }
            } catch {
                queue.async {
                    self.rateLimitRefreshInFlight = false
                    let hasLimits = self.snapshot.fiveHourRemainingPercent != nil || self.snapshot.weeklyRemainingPercent != nil
                    self.snapshot.freshness = hasLimits ? .delayed : .unavailable
                    self.publish()
                    if self.runPendingRateLimitRefreshIfNeeded() { return }
                    let delay = self.retrySeconds
                    self.retrySeconds = min(60, self.retrySeconds * 2)
                    let retry = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.retryWorkItem = nil
                        self.beginRateLimitRefresh(force: false)
                    }
                    self.retryWorkItem = retry
                    self.queue.asyncAfter(deadline: .now() + delay, execute: retry)
                }
            }
        }
    }

    @discardableResult
    private func runPendingRateLimitRefreshIfNeeded() -> Bool {
        guard rateLimitRefreshPending else { return false }
        rateLimitRefreshPending = false
        beginRateLimitRefresh(force: true)
        return true
    }

    private func applyRateLimits(_ raw: Data) {
        queue.async { self.applyRateLimitsOnQueue(raw) }
    }

    private func applyRateLimitsOnQueue(_ raw: Data) {
        do {
            let result = try RateLimitParser.parse(data: raw)
            mergeRateLimits(result)
            lastRateLimitUpdate = Date()
            snapshot.lastUpdatedAt = Date()
            snapshot.freshness = .fresh
        } catch {
            snapshot.freshness = .incompatible
        }
        publish()
    }

    private func mergeRateLimits(_ result: RateLimitResult) {
        if let five = result.fiveHour {
            snapshot.fiveHourRemainingPercent = mergedRemaining(
                current: snapshot.fiveHourRemainingPercent,
                currentReset: snapshot.fiveHourResetsAt,
                incoming: five
            )
            snapshot.fiveHourResetsAt = five.resetsAt
        }
        if let weekly = result.weekly {
            snapshot.weeklyRemainingPercent = mergedRemaining(
                current: snapshot.weeklyRemainingPercent,
                currentReset: snapshot.weeklyResetsAt,
                incoming: weekly
            )
            snapshot.weeklyResetsAt = weekly.resetsAt
        }
    }

    private func mergedRemaining(current: Int?, currentReset: Date?, incoming: RateLimitWindow) -> Int {
        guard let current,
              let currentReset,
              let incomingReset = incoming.resetsAt,
              abs(currentReset.timeIntervalSince(incomingReset)) < 1 else {
            return incoming.remainingPercent
        }
        return min(current, incoming.remainingPercent)
    }

    private func publish() { updateHandler?(snapshot) }
}
