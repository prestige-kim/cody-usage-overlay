import AppKit
import CodyUsageCore
import Darwin

final class SingleInstanceLock {
    private let descriptor: Int32

    init?() {
        let identifier = Bundle.main.bundleIdentifier ?? "com.proudchris.cody-usage-overlay"
        let path = "/tmp/\(identifier).\(getuid()).lock"
        descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if descriptor >= 0 { Darwin.close(descriptor) }
            return nil
        }
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

final class UsageView: NSView {
    var snapshot = UsageSnapshot() { didSet { needsDisplay = true; toolTip = tooltipText } }
    var warningThreshold = 30
    var criticalThreshold = 10
    private lazy var codexIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "codex-emoji", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 15, yRadius: 15)
        NSColor(calibratedWhite: 0.08, alpha: 0.88).setFill(); path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke(); path.lineWidth = 1; path.stroke()

        let context = snapshot.contextRemainingPercent.map { "Context \($0)%" } ?? "Context —"
        let limits: String
        if let fiveHour = snapshot.fiveHourRemainingPercent {
            limits = "5h \(fiveHour)% · Week \(percent(snapshot.weeklyRemainingPercent))"
        } else {
            limits = "Week \(percent(snapshot.weeklyRemainingPercent))"
        }
        let delayed = snapshot.freshness == .fresh ? "" : "  \(snapshot.freshness == .incompatible ? "호환성 확인 필요" : "지연됨")"
        let limitValues = [snapshot.fiveHourRemainingPercent, snapshot.weeklyRemainingPercent].compactMap { $0 }
        let limitFontSize: CGFloat = snapshot.fiveHourRemainingPercent == nil ? 16 : 14
        drawText(limits, at: NSPoint(x: 16, y: 9), font: .boldSystemFont(ofSize: limitFontSize), color: color(for: limitValues.min()))
        drawText(context + delayed, at: NSPoint(x: 16, y: 37), font: .systemFont(ofSize: 11, weight: .medium), color: .white.withAlphaComponent(0.78))
        codexIcon?.draw(
            in: NSRect(x: 164, y: 13, width: 36, height: 36),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        let emojiFont = NSFont(name: "AppleColorEmoji", size: 31) ?? .systemFont(ofSize: 31)
        drawText("🧑🏻‍💻", at: NSPoint(x: 202, y: 8), font: emojiFont, color: .white)
    }

    private func drawText(_ value: String, at point: NSPoint, font: NSFont, color: NSColor) {
        value.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
    private func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" }
    private func color(for value: Int?) -> NSColor {
        guard let value else { return .white }
        if value <= criticalThreshold { return NSColor(calibratedRed: 1, green: 0.35, blue: 0.35, alpha: 1) }
        if value <= warningThreshold { return NSColor(calibratedRed: 1, green: 0.67, blue: 0.26, alpha: 1) }
        return NSColor(calibratedRed: 0.49, green: 0.64, blue: 1, alpha: 1)
    }
    private var tooltipText: String {
        let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .medium
        return "마지막 갱신: \(formatter.string(from: snapshot.lastUpdatedAt))\n태스크: \(snapshot.activeThreadId ?? "확인 중")"
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class WindowLocator {
    struct AnchorLayout {
        let pet: CGRect
    }
    private var petWindowID: CGWindowID?

    func chatGPTRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.openai.codex" }
    }

    func anchorLayout() -> AnchorLayout? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let windows: [(rect: CGRect, layer: Int, id: CGWindowID)] = info.compactMap { row in
            guard row[kCGWindowOwnerName as String] as? String == "ChatGPT",
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let number = row[kCGWindowNumber as String] as? NSNumber else { return nil }
            return (rect, row[kCGWindowLayer as String] as? Int ?? 0, CGWindowID(number.uint32Value))
        }
        // Keep following the same Cody window while dragging. Codex creates a
        // temporary hit-area window during a drag, which must not replace it.
        if let petWindowID, let tracked = windows.first(where: { $0.id == petWindowID }) {
            return AnchorLayout(pet: cocoaCoordinates(tracked.rect))
        }
        let pet = windows
            .filter {
                $0.rect.width >= 70 && $0.rect.width <= 320 &&
                $0.rect.height >= 100 && $0.rect.height <= 400
            }
            // The pet is the lowest substantial ChatGPT overlay. Layer order also
            // contains transient controls, so using the highest layer can anchor
            // to a control above Cody instead of Cody's own window.
            .max {
                if abs($0.rect.maxY - $1.rect.maxY) > 2 { return $0.rect.maxY < $1.rect.maxY }
                return $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height
            }
        if let pet {
            petWindowID = pet.id
            let petFrame = cocoaCoordinates(pet.rect)
            return AnchorLayout(pet: petFrame)
        }
        petWindowID = nil
        return nil
    }

    private func cocoaCoordinates(_ quartz: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first else { return quartz }
        return CGRect(x: quartz.minX, y: screen.frame.maxY - quartz.maxY, width: quartz.width, height: quartz.height)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let coordinator = UsageCoordinator()
    private let locator = WindowLocator()
    private var panel: OverlayPanel!
    private var usageView: UsageView!
    private var positionTimer: Timer?
    private var alwaysOnTop = true
    private var config = OverlayConfig()
    private var manualPositionInitialized = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        config = loadConfig()
        usageView = UsageView(frame: NSRect(x: 0, y: 0, width: 242, height: 62))
        usageView.warningThreshold = config.warningThreshold
        usageView.criticalThreshold = config.criticalThreshold
        panel = OverlayPanel(
            contentRect: usageView.bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = usageView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = config.clickThrough
        installMenu()

        coordinator.onUpdate { [weak self] snapshot in
            DispatchQueue.main.async { self?.usageView.snapshot = snapshot }
        }
        coordinator.start()
        reposition()
        let trackingTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        trackingTimer.tolerance = 0.002
        RunLoop.main.add(trackingTimer, forMode: .common)
        positionTimer = trackingTimer
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) { coordinator.stop(); positionTimer?.invalidate() }

    private func reposition() {
        guard locator.chatGPTRunning() else { panel.orderOut(nil); return }
        guard let layout = locator.anchorLayout() else {
            panel.isMovableByWindowBackground = true
            panel.ignoresMouseEvents = false
            if !manualPositionInitialized {
                placeManualWindowInitially()
                manualPositionInitialized = true
            }
            panel.level = alwaysOnTop ? .floating : .normal
            if !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        manualPositionInitialized = true
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = config.clickThrough
        let anchor = layout.pet
        let x = anchor.midX - panel.frame.width / 2 + config.offsetX
        let screenMinY = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame.minY ?? 0
        let y = OverlayGeometry.panelOriginY(
            petWindowMinY: anchor.minY,
            petWindowHeight: anchor.height,
            panelHeight: panel.frame.height,
            visibleScreenMinY: screenMinY
        )
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.level = alwaysOnTop ? .floating : .normal
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func placeManualWindowInitially() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.minY + 24
        ))
    }

    private func installMenu() {
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(withTitle: "새로고침", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(withTitle: "위치 재탐색", action: #selector(repositionNow), keyEquivalent: "")
        let top = NSMenuItem(title: "항상 위에 표시", action: #selector(toggleTop(_:)), keyEquivalent: "")
        top.state = .on; menu.addItem(top)
        menu.addItem(.separator())
        menu.addItem(withTitle: "진단 정보 복사", action: #selector(copyDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        usageView.menu = menu
    }

    @objc private func refresh() { coordinator.forceRefresh() }
    @objc private func repositionNow() { reposition() }
    @objc private func spaceChanged() { reposition() }
    @objc private func toggleTop(_ sender: NSMenuItem) { alwaysOnTop.toggle(); sender.state = alwaysOnTop ? .on : .off; reposition() }
    @objc private func copyDiagnostics() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(coordinator.diagnostics(), forType: .string) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func loadConfig() -> OverlayConfig {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodyUsageOverlay/config.json")
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(OverlayConfig.self, from: data) else {
            return OverlayConfig()
        }
        return decoded
    }
}

guard let singleInstanceLock = SingleInstanceLock() else { exit(0) }
for running in NSRunningApplication.runningApplications(withBundleIdentifier: "com.proudchris.cody-usage-overlay")
where running.processIdentifier != getpid() {
    running.terminate()
}
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
withExtendedLifetime(singleInstanceLock) {}
