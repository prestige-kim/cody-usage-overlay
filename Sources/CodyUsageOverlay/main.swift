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
    var onClose: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var snapshot = UsageSnapshot() { didSet { needsDisplay = true; toolTip = tooltipText } }
    var warningThreshold = 30
    var criticalThreshold = 10
    private lazy var codexIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "codex-emoji", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override var isFlipped: Bool { true }

    private var closeButtonRect: NSRect { NSRect(x: 7, y: 7, width: 14, height: 14) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if closeButtonRect.insetBy(dx: -3, dy: -3).contains(convert(event.locationInWindow, from: nil)) {
            onClose?()
            return
        }
        if window?.isMovableByWindowBackground == true {
            dragStartMouseLocation = NSEvent.mouseLocation
            dragStartWindowOrigin = window?.frame.origin
            onDragBegan?()
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let dragStartMouseLocation,
              let dragStartWindowOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(OverlayGeometry.draggedOrigin(
            windowOrigin: dragStartWindowOrigin,
            dragStart: dragStartMouseLocation,
            currentPointer: current
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStartMouseLocation != nil else {
            super.mouseUp(with: event)
            return
        }
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        onDragEnded?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 15, yRadius: 15)
        NSColor(calibratedWhite: 0.08, alpha: 0.88).setFill(); path.fill()
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke(); path.lineWidth = 1; path.stroke()

        let closeCircle = NSBezierPath(ovalIn: closeButtonRect)
        NSColor(calibratedWhite: 1, alpha: 0.18).setFill(); closeCircle.fill()
        drawText("×", at: NSPoint(x: 9.2, y: 4.8), font: .systemFont(ofSize: 14, weight: .semibold), color: .white.withAlphaComponent(0.8))

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
        drawText(limits, at: NSPoint(x: 27, y: 9), font: .boldSystemFont(ofSize: limitFontSize), color: color(for: limitValues.min()))
        drawText(context + delayed, at: NSPoint(x: 27, y: 37), font: .systemFont(ofSize: 11, weight: .medium), color: .white.withAlphaComponent(0.78))
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
        let activity: CGRect?
        let activityDistance: CGFloat?
    }
    private var petWindowID: CGWindowID?
    private var pendingPetWindowID: CGWindowID?
    private var pendingPetWindowSamples = 0
    private var missingPetSamples = 0
    private var lastPetQuartzRect: CGRect?
    private var lastLayout: AnchorLayout?
    private var lastActivityDistance: CGFloat?
    private(set) var diagnosticsText = "Window discovery has not run yet."

    func chatGPTRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.openai.codex" }
    }

    func anchorLayout() -> AnchorLayout? {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            diagnosticsText = "CGWindowList: unavailable"
            return lastLayout
        }
        let codexPIDs = Set(NSWorkspace.shared.runningApplications.compactMap { app -> pid_t? in
            guard ["com.openai.codex", "com.openai.chat"].contains(app.bundleIdentifier ?? "") else { return nil }
            return app.processIdentifier
        })
        let windows: [OverlayWindowSnapshot] = info.compactMap { row in
            let ownerName = (row[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let ownerPID = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            guard (ownerPID.map { codexPIDs.contains($0) } == true || ["chatgpt", "codex"].contains(ownerName)),
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let number = row[kCGWindowNumber as String] as? NSNumber else { return nil }
            return OverlayWindowSnapshot(
                id: number.uint32Value,
                rect: rect,
                layer: row[kCGWindowLayer as String] as? Int ?? 0,
                alpha: (row[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                name: row[kCGWindowName as String] as? String ?? "",
                isOnscreen: (row[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
            )
        }

        guard let selected = PetWindowSelector.select(
            from: windows,
            trackedWindowID: petWindowID,
            lastKnownRect: lastPetQuartzRect
        ) else {
            missingPetSamples += 1
            if missingPetSamples <= 15, let lastLayout {
                diagnosticsText = "Codex PIDs: \(codexPIDs.sorted())\nMatched windows: \(windows.count)\nPet: temporarily unavailable (using last position)"
                return lastLayout
            }
            petWindowID = nil
            pendingPetWindowID = nil
            pendingPetWindowSamples = 0
            lastPetQuartzRect = nil
            lastLayout = nil
            diagnosticsText = "Codex PIDs: \(codexPIDs.sorted())\nMatched windows: \(windows.count)\nPet: not found"
            return nil
        }

        if selected.id != petWindowID {
            if pendingPetWindowID == selected.id {
                pendingPetWindowSamples += 1
            } else {
                pendingPetWindowID = selected.id
                pendingPetWindowSamples = 1
            }
            guard pendingPetWindowSamples >= 3 else {
                diagnosticsText = "Codex PIDs: \(codexPIDs.sorted())\nMatched windows: \(windows.count)\nPet: candidate \(selected.id) (\(pendingPetWindowSamples)/3)"
                return lastLayout
            }
            petWindowID = selected.id
        }
        pendingPetWindowID = nil
        pendingPetWindowSamples = 0
        missingPetSamples = 0
        lastPetQuartzRect = selected.rect

        let petFrame = cocoaCoordinates(selected.rect)
        let activity = windows
            .filter {
                let name = $0.name.lowercased()
                return $0.id != selected.id && name.contains("pet") && name.contains("activity")
            }
            .min {
                abs($0.rect.midX - selected.rect.midX) + abs($0.rect.midY - selected.rect.midY)
                < abs($1.rect.midX - selected.rect.midX) + abs($1.rect.midY - selected.rect.midY)
            }
            .map { cocoaCoordinates($0.rect) }
        if let activity {
            lastActivityDistance = abs(activity.midY - petFrame.midY)
        }
        let layout = AnchorLayout(pet: petFrame, activity: activity, activityDistance: lastActivityDistance)
        lastLayout = layout
        diagnosticsText = "Codex PIDs: \(codexPIDs.sorted())\nMatched windows: \(windows.count)\nPet: \(selected.name.isEmpty ? "native anonymous panel" : selected.name) #\(selected.id), layer \(selected.layer), \(Int(selected.rect.width))x\(Int(selected.rect.height))\nActivity: \(activity == nil ? "integrated/fallback" : "matched")"
        return layout
    }

    private func cocoaCoordinates(_ quartz: CGRect) -> CGRect {
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(x: quartz.minX, y: mainDisplayHeight - quartz.maxY, width: quartz.width, height: quartz.height)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum MenuTag {
        static let overlayVisible = 1
        static let followPet = 2
        static let clickThrough = 3
        static let alwaysOnTop = 4
    }

    private let coordinator = UsageCoordinator()
    private let locator = WindowLocator()
    private var panel: OverlayPanel!
    private var usageView: UsageView!
    private var statusItem: NSStatusItem?
    private var positionTimer: Timer?
    private var alwaysOnTop = true
    private var config = OverlayConfig()
    private var manualPositionInitialized = false
    private var visibility = OverlayVisibilityController()
    private var isUserDragging = false
    private var lastAutomaticBaseOrigin: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        config = loadConfig()
        visibility = OverlayVisibilityController(isVisible: config.overlayVisible)
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
        usageView.onClose = { [weak self] in self?.setOverlayVisible(false) }
        usageView.onDragBegan = { [weak self] in self?.isUserDragging = true }
        usageView.onDragEnded = { [weak self] in self?.finishUserDrag() }
        installMenus()

        coordinator.onUpdate { [weak self] snapshot in
            DispatchQueue.main.async { self?.usageView.snapshot = snapshot }
        }
        coordinator.start()
        reposition()
        let trackingTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
        trackingTimer.tolerance = 0.03
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

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
        positionTimer?.invalidate()
        if config.anchorMode != .petWindow { saveManualPosition() }
        saveConfig()
    }

    private func reposition(forceFront: Bool = false) {
        let followsPet = config.anchorMode == .petWindow
        let layout = followsPet ? locator.anchorLayout() : nil
        guard visibility.update(petIsVisible: layout != nil) else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = config.clickThrough
        panel.level = alwaysOnTop ? .floating : .normal

        if !followsPet || layout == nil {
            ensureManualPosition()
            lastAutomaticBaseOrigin = nil
            if forceFront || !panel.isVisible { panel.orderFrontRegardless() }
            return
        }
        guard let layout, !isUserDragging else {
            if forceFront || !panel.isVisible { panel.orderFrontRegardless() }
            return
        }

        let anchor = layout.pet
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        let baseX = (layout.activity?.midX ?? anchor.midX) - panel.frame.width / 2
        let baseY = OverlayGeometry.oppositeActivityOriginY(
            petCenterY: anchor.midY,
            activityCenterY: layout.activity.map { Double($0.midY) },
            lastActivityDistance: layout.activityDistance.map(Double.init),
            panelHeight: panel.frame.height,
            visibleScreenMinY: visibleFrame.minY,
            visibleScreenMaxY: visibleFrame.maxY
        )
        lastAutomaticBaseOrigin = NSPoint(x: baseX, y: baseY)
        let target = OverlayGeometry.clampedOrigin(
            x: baseX + config.offsetX,
            y: baseY + config.offsetY,
            panelWidth: panel.frame.width,
            panelHeight: panel.frame.height,
            visibleScreenFrame: visibleFrame
        )
        if hypot(panel.frame.minX - target.x, panel.frame.minY - target.y) > 0.5 {
            panel.setFrameOrigin(target)
        }
        if forceFront || !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func ensureManualPosition() {
        guard !manualPositionInitialized else { return }
        if let x = config.manualPositionX, let y = config.manualPositionY {
            let proposed = CGRect(x: x, y: y, width: panel.frame.width, height: panel.frame.height)
            let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(proposed) }) ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                let origin = OverlayGeometry.clampedOrigin(
                    x: x,
                    y: y,
                    panelWidth: panel.frame.width,
                    panelHeight: panel.frame.height,
                    visibleScreenFrame: visibleFrame
                )
                panel.setFrameOrigin(origin)
            }
        } else {
            placeManualWindowInitially()
        }
        manualPositionInitialized = true
    }

    private func placeManualWindowInitially() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - panel.frame.width - 24,
            y: visible.minY + 24
        ))
    }

    private func installMenus() {
        usageView.menu = makeMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Cody Usage Overlay")
        item.button?.toolTip = "Cody Usage Overlay"
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        let visible = NSMenuItem(title: "오버레이 표시", action: #selector(toggleOverlayVisible(_:)), keyEquivalent: "")
        visible.tag = MenuTag.overlayVisible
        menu.addItem(visible)
        let follow = NSMenuItem(title: "Cody 따라가기", action: #selector(toggleFollowPet(_:)), keyEquivalent: "")
        follow.tag = MenuTag.followPet
        menu.addItem(follow)
        let clickThrough = NSMenuItem(title: "클릭 통과", action: #selector(toggleClickThrough(_:)), keyEquivalent: "")
        clickThrough.tag = MenuTag.clickThrough
        menu.addItem(clickThrough)
        let top = NSMenuItem(title: "항상 위에 표시", action: #selector(toggleTop(_:)), keyEquivalent: "")
        top.tag = MenuTag.alwaysOnTop
        menu.addItem(top)
        menu.addItem(.separator())
        menu.addItem(withTitle: "새로고침", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(withTitle: "위치 초기화", action: #selector(resetPosition), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "진단 정보 복사", action: #selector(copyDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q")
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            switch item.tag {
            case MenuTag.overlayVisible:
                item.state = config.overlayVisible ? .on : .off
            case MenuTag.followPet:
                item.state = config.anchorMode == .petWindow ? .on : .off
            case MenuTag.clickThrough:
                item.state = config.clickThrough ? .on : .off
            case MenuTag.alwaysOnTop:
                item.state = alwaysOnTop ? .on : .off
            default:
                break
            }
        }
    }

    @objc private func refresh() { coordinator.forceRefresh() }
    @objc private func spaceChanged() { reposition(forceFront: true) }
    @objc private func toggleOverlayVisible(_ sender: NSMenuItem) { setOverlayVisible(!config.overlayVisible) }
    @objc private func toggleFollowPet(_ sender: NSMenuItem) {
        if config.anchorMode == .petWindow {
            config.anchorMode = .manual
            saveManualPosition()
            manualPositionInitialized = true
        } else {
            config.anchorMode = .petWindow
        }
        saveConfig()
        reposition(forceFront: true)
    }
    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        config.clickThrough.toggle()
        panel.ignoresMouseEvents = config.clickThrough
        saveConfig()
    }
    @objc private func toggleTop(_ sender: NSMenuItem) {
        alwaysOnTop.toggle()
        reposition()
    }
    @objc private func resetPosition() {
        let defaults = OverlayConfig()
        config.offsetX = defaults.offsetX
        config.offsetY = defaults.offsetY
        config.manualPositionX = nil
        config.manualPositionY = nil
        manualPositionInitialized = false
        saveConfig()
        reposition(forceFront: true)
    }
    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        let mode = config.anchorMode == .petWindow ? "follow-pet" : "manual"
        NSPasteboard.general.setString(
            coordinator.diagnostics() + "\nMode: \(mode)\nVisible: \(config.overlayVisible)\n" + locator.diagnosticsText,
            forType: .string
        )
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func setOverlayVisible(_ isVisible: Bool) {
        config.overlayVisible = isVisible
        if isVisible {
            visibility.show()
            reposition(forceFront: true)
        } else {
            visibility.dismiss()
            panel.orderOut(nil)
        }
        saveConfig()
    }

    private func finishUserDrag() {
        defer {
            isUserDragging = false
            reposition()
        }
        if config.anchorMode == .petWindow, let base = lastAutomaticBaseOrigin {
            config.offsetX = panel.frame.minX - base.x
            config.offsetY = panel.frame.minY - base.y
        } else {
            saveManualPosition()
        }
        saveConfig()
    }

    private func saveManualPosition() {
        guard panel != nil else { return }
        config.manualPositionX = panel.frame.minX
        config.manualPositionY = panel.frame.minY
    }

    private func loadConfig() -> OverlayConfig {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? JSONDecoder().decode(OverlayConfig.self, from: data) else {
            return OverlayConfig()
        }
        return decoded
    }

    private func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: configURL, options: .atomic)
    }

    private var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodyUsageOverlay/config.json")
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
