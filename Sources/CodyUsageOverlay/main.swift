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
    var onToggleResetCountdown: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var snapshot = UsageSnapshot() {
        didSet {
            if oldValue.codyState != snapshot.codyState {
                codyAnimationStartedAt = ProcessInfo.processInfo.systemUptime
            }
            if oldValue.agentPulse != snapshot.agentPulse {
                agentPulseAnimationStartedAt = ProcessInfo.processInfo.systemUptime
            }
            updateCodyAnimationTimer()
            needsDisplay = true
            setAccessibilityHelp(tooltipText)
        }
    }
    var showsResetCountdown = false { didSet { needsDisplay = true } }
    var countdownNow = Date() { didSet { if showsResetCountdown { needsDisplay = true } } }
    var warningThreshold = 30
    var criticalThreshold = 10
    private lazy var codexIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "codex-emoji", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var codyStateTrackingArea: NSTrackingArea?
    private var agentPulseTrackingArea: NSTrackingArea?
    private var showsCodyStateLabel = false { didSet { if oldValue != showsCodyStateLabel { needsDisplay = true } } }
    private var showsAgentPulseLabel = false { didSet { if oldValue != showsAgentPulseLabel { needsDisplay = true } } }
    private var codyStateLabelPinnedUntil: Date?
    private var agentPulseLabelPinnedUntil: Date?
    private var codyAnimationTimer: Timer?
    private var codyAnimationStartedAt = ProcessInfo.processInfo.systemUptime
    private var agentPulseAnimationStartedAt = ProcessInfo.processInfo.systemUptime

    override var isFlipped: Bool { true }

    private var closeButtonRect: NSRect { NSRect(x: 7, y: 7, width: 14, height: 14) }
    private var timerButtonRect: NSRect { NSRect(x: 7, y: 41, width: 14, height: 14) }
    private var textRegion: NSRect { NSRect(x: 38, y: 0, width: 122, height: bounds.height) }
    // Agent Pulse is rendered as a background current. This invisible gutter remains its
    // discoverable hover/click zone without competing with the usage text or Cody icon.
    private var agentPulseHitRect: NSRect { NSRect(x: 145, y: 4, width: 47, height: 52) }
    private var codyStateHitRect: NSRect { NSRect(x: 193, y: 6, width: 43, height: 50) }
    private var codexIconRect: NSRect { NSRect(x: 196, y: 13, width: 36, height: 36) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCodyAnimationTimer()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let codyStateTrackingArea { removeTrackingArea(codyStateTrackingArea) }
        if let agentPulseTrackingArea { removeTrackingArea(agentPulseTrackingArea) }
        let tracking = NSTrackingArea(
            rect: codyStateHitRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        codyStateTrackingArea = tracking
        let pulseTracking = NSTrackingArea(
            rect: agentPulseHitRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(pulseTracking)
        agentPulseTrackingArea = pulseTracking
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(agentPulseHitRect, cursor: .pointingHand)
        addCursorRect(codyStateHitRect, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === codyStateTrackingArea {
            showsAgentPulseLabel = false
            showsCodyStateLabel = true
        } else if event.trackingArea === agentPulseTrackingArea {
            showsCodyStateLabel = false
            showsAgentPulseLabel = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === codyStateTrackingArea,
           codyStateLabelPinnedUntil.map({ Date() < $0 }) != true {
            showsCodyStateLabel = false
        } else if event.trackingArea === agentPulseTrackingArea,
                  agentPulseLabelPinnedUntil.map({ Date() < $0 }) != true {
            showsAgentPulseLabel = false
        }
    }

    func refreshCodyStateHover(at screenPoint: NSPoint = NSEvent.mouseLocation) {
        guard let window else {
            showsCodyStateLabel = false
            showsAgentPulseLabel = false
            return
        }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(windowPoint, from: nil)
        let isPinned = codyStateLabelPinnedUntil.map { Date() < $0 } == true
        let isPulsePinned = agentPulseLabelPinnedUntil.map { Date() < $0 } == true
        if !isPinned { codyStateLabelPinnedUntil = nil }
        if !isPulsePinned { agentPulseLabelPinnedUntil = nil }
        let overCody = codyStateHitRect.contains(localPoint)
        let overPulse = agentPulseHitRect.contains(localPoint)
        showsCodyStateLabel = overCody || isPinned
        showsAgentPulseLabel = !showsCodyStateLabel && (overPulse || isPulsePinned)
    }

    override func mouseDown(with event: NSEvent) {
        if closeButtonRect.insetBy(dx: -3, dy: -3).contains(convert(event.locationInWindow, from: nil)) {
            onClose?()
            return
        }
        if timerButtonRect.insetBy(dx: -3, dy: -3).contains(convert(event.locationInWindow, from: nil)) {
            onToggleResetCountdown?()
            return
        }
        if agentPulseHitRect.contains(convert(event.locationInWindow, from: nil)) {
            agentPulseLabelPinnedUntil = Date().addingTimeInterval(3)
            showsCodyStateLabel = false
            showsAgentPulseLabel = true
            return
        }
        if codyStateHitRect.contains(convert(event.locationInWindow, from: nil)) {
            codyStateLabelPinnedUntil = Date().addingTimeInterval(3)
            showsAgentPulseLabel = false
            showsCodyStateLabel = true
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
        drawCodyFluid()
        drawAgentPulseBackground()
        NSColor(calibratedWhite: 1, alpha: 0.16).setStroke(); path.lineWidth = 1; path.stroke()

        let closeCircle = NSBezierPath(ovalIn: closeButtonRect)
        NSColor(calibratedWhite: 1, alpha: 0.18).setFill(); closeCircle.fill()
        drawText("×", at: NSPoint(x: 9.2, y: 4.8), font: .systemFont(ofSize: 14, weight: .semibold), color: .white.withAlphaComponent(0.8))

        drawTimerButton()

        if showsCodyStateLabel {
            drawCodyStateLabel()
        } else if showsAgentPulseLabel {
            drawAgentPulseLabel()
        } else if showsResetCountdown {
            let countdown = ResetCountdownFormatter.make(
                fiveHourResetsAt: snapshot.fiveHourResetsAt,
                weeklyResetsAt: snapshot.weeklyResetsAt,
                now: countdownNow
            )
            drawCountdownLine(label: "5h", value: countdown.fiveHourText, y: 9, valueSize: 14)
            drawCountdownLine(label: "Week", value: countdown.weeklyText, y: 37, valueSize: 12)
        } else {
            let context = snapshot.contextRemainingPercent.map { "Context \($0)%" } ?? "Context —"
            let limits: String
            if let fiveHour = snapshot.fiveHourRemainingPercent {
                limits = "5h \(fiveHour)% · Week \(percent(snapshot.weeklyRemainingPercent))"
            } else {
                limits = "Week \(percent(snapshot.weeklyRemainingPercent))"
            }
            let delayed = snapshot.freshness == .fresh ? "" : "  \(snapshot.freshness == .incompatible ? "호환성 확인 필요" : "지연됨")"
            let limitValues = [snapshot.fiveHourRemainingPercent, snapshot.weeklyRemainingPercent].compactMap { $0 }
            let limitFontSize: CGFloat = snapshot.fiveHourRemainingPercent == nil ? 16 : 12
            drawCenteredText(limits, y: 9, font: .boldSystemFont(ofSize: limitFontSize), color: color(for: limitValues.min()))
            drawCenteredText(context + delayed, y: 37, font: .systemFont(ofSize: 11, weight: .medium), color: .white.withAlphaComponent(0.78))
        }
        codexIcon?.draw(
            in: codexIconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    private func drawText(_ value: String, at point: NSPoint, font: NSFont, color: NSColor) {
        value.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
    private func drawCenteredText(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = (value as NSString).size(withAttributes: attributes).width
        let x = textRegion.midX - width / 2
        value.draw(at: NSPoint(x: max(textRegion.minX, x), y: y), withAttributes: attributes)
    }
    private func drawCountdownLine(label: String, value: String, y: CGFloat, valueSize: CGFloat) {
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: valueSize, weight: .semibold)
        let labelColor = NSColor.white.withAlphaComponent(0.56)
        let valueColor = NSColor(calibratedRed: 0.66, green: 0.75, blue: 1, alpha: 1)
        let labelWidth = (label as NSString).size(withAttributes: [.font: labelFont]).width
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        let gap: CGFloat = 8
        let contentWidth = labelWidth + gap + valueWidth
        let x = max(textRegion.minX, textRegion.midX - contentWidth / 2)
        drawText(label, at: NSPoint(x: x, y: y + 2), font: labelFont, color: labelColor)
        drawText(value, at: NSPoint(x: x + labelWidth + gap, y: y), font: valueFont, color: valueColor)
    }
    private func drawTimerButton() {
        let circle = NSBezierPath(ovalIn: timerButtonRect)
        (showsResetCountdown
            ? NSColor(calibratedRed: 0.43, green: 0.57, blue: 1, alpha: 0.92)
            : NSColor(calibratedWhite: 1, alpha: 0.14)).setFill()
        circle.fill()

        let center = NSPoint(x: timerButtonRect.midX, y: timerButtonRect.midY)
        let clock = NSBezierPath(ovalIn: timerButtonRect.insetBy(dx: 3.2, dy: 3.2))
        clock.move(to: center)
        clock.line(to: NSPoint(x: center.x, y: center.y - 2.4))
        clock.move(to: center)
        clock.line(to: NSPoint(x: center.x + 2.1, y: center.y + 1.2))
        NSColor.white.withAlphaComponent(showsResetCountdown ? 0.96 : 0.78).setStroke()
        clock.lineWidth = 1
        clock.lineCapStyle = .round
        clock.stroke()
    }
    private func drawAgentPulseBackground() {
        let (_, speed, motion, amplitude, opacity) = agentPulseStyle
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14).addClip()

        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - agentPulseAnimationStartedAt)
        let phase = CGFloat(elapsed) * speed
        let center = NSPoint(x: bounds.midX + 22, y: bounds.midY)
        let breath = 0.88 + 0.12 * sin(phase * 0.43)
        let glow = NSShadow()
        glow.shadowBlurRadius = 15
        glow.shadowColor = NSColor.white.withAlphaComponent(opacity * 0.42)
        glow.shadowOffset = .zero
        glow.set()

        // Pulse deliberately uses luminance only. Cody State owns the hue of the overlay,
        // while Pulse contributes a separate layer of speed, density, and breathing motion.
        for layer in 0..<3 {
            let layerPhase = phase * (0.58 + CGFloat(layer) * 0.17) + CGFloat(layer) * 2.2
            let driftX = motion * sin(layerPhase * 0.79 + CGFloat(layer))
            let driftY = motion * 0.62 * cos(layerPhase * 0.61 + CGFloat(layer) * 0.7)
            let path = organicBlobPath(
                center: NSPoint(
                    x: center.x + (CGFloat(layer) - 1) * 18 + driftX,
                    y: center.y + driftY
                ),
                radiusX: 76 - CGFloat(layer) * 10,
                radiusY: 31 - CGFloat(layer) * 4,
                phase: layerPhase,
                amplitude: amplitude * (1 - CGFloat(layer) * 0.13),
                lobes: 3 + layer
            )
            NSColor.white.withAlphaComponent(opacity * breath * (1 - CGFloat(layer) * 0.24)).setFill()
            path.fill()
        }

        if snapshot.agentPulse == .finishing, elapsed < 1.1 {
            let progress = CGFloat(elapsed / 1.1)
            let bloom = organicBlobPath(
                center: center,
                radiusX: 28 + progress * 92,
                radiusY: 16 + progress * 28,
                phase: progress * 2.2,
                amplitude: 0.035,
                lobes: 4
            )
            NSColor.white.withAlphaComponent((1 - progress) * 0.065).setFill()
            bloom.fill()
        }
        context.restoreGraphicsState()
    }
    private func drawAgentPulseLabel() {
        let (color, _, _, _, _) = agentPulseStyle
        drawCenteredText(
            "Agent Pulse",
            y: 8,
            font: .systemFont(ofSize: 9, weight: .medium),
            color: .white.withAlphaComponent(0.52)
        )
        drawCenteredText(
            "\(snapshot.agentPulse.displayName) · \(snapshot.agentPulseReason)",
            y: 31,
            font: .systemFont(ofSize: 10.5, weight: .bold),
            color: color
        )
    }
    private var agentPulseStyle: (
        color: NSColor,
        speed: CGFloat,
        motion: CGFloat,
        amplitude: CGFloat,
        opacity: CGFloat
    ) {
        switch snapshot.agentPulse {
        case .steady:
            (NSColor(calibratedRed: 0.34, green: 0.68, blue: 1, alpha: 1), 0.12, 0.6, 0.025, 0.018)
        case .active:
            (NSColor(calibratedRed: 0.21, green: 0.92, blue: 1, alpha: 1), 1.35, 3.8, 0.070, 0.052)
        case .overloaded:
            (NSColor(calibratedRed: 1, green: 0.66, blue: 0.12, alpha: 1), 2.65, 6.2, 0.110, 0.075)
        case .stalled:
            (NSColor(calibratedWhite: 0.78, alpha: 1), 0.22, 0.4, 0.018, 0.025)
        case .unstable:
            (NSColor(calibratedRed: 1, green: 0.29, blue: 0.31, alpha: 1), 2.20, 7.4, 0.120, 0.070)
        case .finishing:
            (NSColor(calibratedRed: 0.32, green: 0.92, blue: 0.48, alpha: 1), 0.85, 2.6, 0.050, 0.055)
        }
    }
    private func drawCodyFluid() {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 14, yRadius: 14).addClip()

        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - codyAnimationStartedAt)
        let style = codyFluidStyle
        let phase = CGFloat(elapsed) * style.speed
        let overlayCenter = NSPoint(x: bounds.midX, y: bounds.midY)
        let codyCenter = NSPoint(x: 214, y: 31)
        let shadow = NSShadow()
        shadow.shadowBlurRadius = snapshot.codyState == .ready ? 4 : 13
        shadow.shadowColor = style.primary.withAlphaComponent(snapshot.codyState == .ready ? 0.10 : 0.30)
        shadow.shadowOffset = .zero
        shadow.set()

        // Active states wash almost the entire overlay with slow, low-opacity fluid fields.
        for layer in 0..<3 {
            let layerPhase = phase * (0.54 + CGFloat(layer) * 0.11) + CGFloat(layer) * 2.1
            let driftX = style.motion * 3.4 * sin(layerPhase * 0.71 + CGFloat(layer))
            let driftY = style.motion * 1.9 * cos(layerPhase * 0.57 + CGFloat(layer) * 0.9)
            let globalCenter = NSPoint(
                x: overlayCenter.x + (CGFloat(layer) - 1) * 22 + driftX,
                y: overlayCenter.y + driftY
            )
            let path = organicBlobPath(
                center: globalCenter,
                radiusX: 168 - CGFloat(layer) * 25,
                radiusY: 68 - CGFloat(layer) * 8,
                phase: layerPhase,
                amplitude: max(0.035, style.amplitude * 0.62),
                lobes: 3 + layer
            )
            let color = layer == 1 ? style.secondary : style.primary
            color.withAlphaComponent(style.globalOpacity * (1 - CGFloat(layer) * 0.20)).setFill()
            path.fill()
        }

        // A stronger local current keeps the state visually anchored behind the fixed Cody icon.
        for layer in 0..<3 {
            let layerPhase = phase + CGFloat(layer) * 1.7
            let driftX = style.motion * sin(layerPhase * 0.83 + CGFloat(layer))
            let driftY = style.motion * 0.72 * cos(layerPhase * 0.67 + CGFloat(layer) * 0.8)
            let path = organicBlobPath(
                center: NSPoint(x: codyCenter.x + driftX, y: codyCenter.y + driftY),
                radiusX: 22 - CGFloat(layer) * 3.4,
                radiusY: 20 - CGFloat(layer) * 2.9,
                phase: layerPhase,
                amplitude: style.amplitude * (1 - CGFloat(layer) * 0.12),
                lobes: 3 + layer
            )
            let color = layer == 1 ? style.secondary : style.primary
            color.withAlphaComponent(style.opacity * (1 - CGFloat(layer) * 0.18)).setFill()
            path.fill()
        }

        if snapshot.codyState == .complete, elapsed < 1.05 {
            let progress = CGFloat(elapsed / 1.05)
            let ripple = organicBlobPath(
                center: overlayCenter,
                radiusX: 24 + progress * 170,
                radiusY: 18 + progress * 52,
                phase: progress * 2.4,
                amplitude: 0.08,
                lobes: 4
            )
            style.primary.withAlphaComponent((1 - progress) * 0.18).setFill()
            ripple.fill()
        }
        context.restoreGraphicsState()
    }
    private func organicBlobPath(
        center: NSPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        phase: CGFloat,
        amplitude: CGFloat,
        lobes: Int
    ) -> NSBezierPath {
        let pointCount = 14
        let points: [NSPoint] = (0..<pointCount).map { index in
            let angle = CGFloat(index) * 2 * .pi / CGFloat(pointCount)
            let wave = sin(angle * CGFloat(lobes) + phase) * amplitude
                + cos(angle * CGFloat(lobes + 2) - phase * 0.61) * amplitude * 0.42
            return NSPoint(
                x: center.x + cos(angle) * radiusX * (1 + wave),
                y: center.y + sin(angle) * radiusY * (1 + wave)
            )
        }
        let path = NSBezierPath()
        path.move(to: points[0])
        let tension: CGFloat = 0.72
        for index in 0..<pointCount {
            let previous = points[(index - 1 + pointCount) % pointCount]
            let current = points[index]
            let next = points[(index + 1) % pointCount]
            let afterNext = points[(index + 2) % pointCount]
            let control1 = NSPoint(
                x: current.x + (next.x - previous.x) * tension / 6,
                y: current.y + (next.y - previous.y) * tension / 6
            )
            let control2 = NSPoint(
                x: next.x - (afterNext.x - current.x) * tension / 6,
                y: next.y - (afterNext.y - current.y) * tension / 6
            )
            path.curve(to: next, controlPoint1: control1, controlPoint2: control2)
        }
        path.close()
        return path
    }
    private var codyFluidStyle: (
        primary: NSColor,
        secondary: NSColor,
        speed: CGFloat,
        motion: CGFloat,
        amplitude: CGFloat,
        opacity: CGFloat,
        globalOpacity: CGFloat
    ) {
        switch snapshot.codyState {
        case .ready:
            (
                NSColor(calibratedRed: 0.25, green: 0.32, blue: 0.46, alpha: 1),
                NSColor(calibratedRed: 0.36, green: 0.43, blue: 0.57, alpha: 1),
                0, 0, 0.025, 0.12, 0.025
            )
        case .thinking:
            (
                NSColor(calibratedRed: 0.08, green: 0.48, blue: 1, alpha: 1),
                NSColor(calibratedRed: 0.05, green: 0.84, blue: 0.95, alpha: 1),
                1.05, 1.7, 0.10, 0.26, 0.13
            )
        case .acting:
            (
                NSColor(calibratedRed: 0.47, green: 0.20, blue: 1, alpha: 1),
                NSColor(calibratedRed: 0.18, green: 0.49, blue: 1, alpha: 1),
                2.15, 2.6, 0.14, 0.31, 0.18
            )
        case .waiting:
            (
                NSColor(calibratedRed: 1, green: 0.48, blue: 0.08, alpha: 1),
                NSColor(calibratedRed: 1, green: 0.75, blue: 0.16, alpha: 1),
                0.64, 1.2, 0.08, 0.25, 0.12
            )
        case .complete:
            (
                NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.38, alpha: 1),
                NSColor(calibratedRed: 0.31, green: 0.92, blue: 0.61, alpha: 1),
                0.78, 0.9, 0.06, 0.24, 0.14
            )
        case .error:
            (
                NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.24, alpha: 1),
                NSColor(calibratedRed: 1, green: 0.34, blue: 0.20, alpha: 1),
                1.72, 2.1, 0.13, 0.28, 0.16
            )
        }
    }
    private func updateCodyAnimationTimer() {
        let shouldAnimate = window != nil && (snapshot.codyState != .ready || snapshot.agentPulse != .steady)
        if shouldAnimate, codyAnimationTimer == nil {
            let timer = Timer(
                timeInterval: 1 / 24,
                target: self,
                selector: #selector(advanceCodyAnimation(_:)),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = 0.008
            RunLoop.main.add(timer, forMode: .common)
            codyAnimationTimer = timer
        } else if !shouldAnimate, let timer = codyAnimationTimer {
            timer.invalidate()
            codyAnimationTimer = nil
        }
    }
    @objc private func advanceCodyAnimation(_ timer: Timer) {
        needsDisplay = true
    }
    private func drawCodyStateLabel() {
        let (color, _) = codyStateStyle
        drawCenteredText(
            "Cody State",
            y: 8,
            font: .systemFont(ofSize: 9, weight: .medium),
            color: .white.withAlphaComponent(0.52)
        )
        drawCenteredText(
            snapshot.codyState.displayName,
            y: 30,
            font: .systemFont(ofSize: 14, weight: .bold),
            color: color
        )
    }
    private var codyStateStyle: (color: NSColor, glyph: String) {
        switch snapshot.codyState {
        case .ready:
            (NSColor(calibratedWhite: 1, alpha: 0.72), "•")
        case .thinking:
            (NSColor(calibratedRed: 0.38, green: 0.68, blue: 1, alpha: 1), "…")
        case .acting:
            (NSColor(calibratedRed: 0.58, green: 0.48, blue: 1, alpha: 1), "↗")
        case .waiting:
            (NSColor(calibratedRed: 1, green: 0.68, blue: 0.24, alpha: 1), "?")
        case .complete:
            (NSColor(calibratedRed: 0.29, green: 0.82, blue: 0.53, alpha: 1), "✓")
        case .error:
            (NSColor(calibratedRed: 1, green: 0.34, blue: 0.38, alpha: 1), "!")
        }
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
        return "Cody: \(snapshot.codyState.displayName)\nAgent Pulse: \(snapshot.agentPulse.displayName) · \(snapshot.agentPulseReason)\n마지막 갱신: \(formatter.string(from: snapshot.lastUpdatedAt))\n태스크: \(snapshot.activeThreadId ?? "확인 중")"
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
    private var resetCountdownTimer: Timer?
    private var resetCountdownHideAt: Date?
    private var resetCountdownRefreshRequested = false
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
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = config.clickThrough
        usageView.onClose = { [weak self] in self?.setOverlayVisible(false) }
        usageView.onToggleResetCountdown = { [weak self] in self?.toggleResetCountdown() }
        usageView.onDragBegan = { [weak self] in self?.isUserDragging = true }
        usageView.onDragEnded = { [weak self] in self?.finishUserDrag() }
        installMenus()

        coordinator.onUpdate { [weak self] snapshot in
            DispatchQueue.main.async { self?.usageView.snapshot = snapshot }
        }
        coordinator.start()
        reposition()
        let trackingTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.usageView.refreshCodyStateHover()
                self?.reposition()
            }
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
        resetCountdownTimer?.invalidate()
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
        if let iconURL = Bundle.main.url(forResource: "cody-usage-menubar", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 20, height: 20)
            icon.isTemplate = false
            icon.accessibilityDescription = "Cody 사용량 오버레이"
            item.button?.image = icon
        } else {
            item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Cody 사용량 오버레이")
        }
        item.button?.toolTip = "Cody 사용량 오버레이"
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

    private func toggleResetCountdown() {
        if usageView.showsResetCountdown {
            hideResetCountdown()
            return
        }
        usageView.showsResetCountdown = true
        usageView.countdownNow = Date()
        resetCountdownHideAt = Date().addingTimeInterval(8)
        resetCountdownRefreshRequested = false
        resetCountdownTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickResetCountdown() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        resetCountdownTimer = timer
        refreshExpiredResetIfNeeded(now: usageView.countdownNow)
    }

    private func tickResetCountdown() {
        let now = Date()
        guard resetCountdownHideAt.map({ now < $0 }) == true else {
            hideResetCountdown()
            return
        }
        usageView.countdownNow = now
        refreshExpiredResetIfNeeded(now: now)
    }

    private func refreshExpiredResetIfNeeded(now: Date) {
        guard !resetCountdownRefreshRequested else { return }
        let display = ResetCountdownFormatter.make(
            fiveHourResetsAt: usageView.snapshot.fiveHourResetsAt,
            weeklyResetsAt: usageView.snapshot.weeklyResetsAt,
            now: now
        )
        guard display.hasExpiredReset else { return }
        resetCountdownRefreshRequested = true
        coordinator.forceRefresh()
    }

    private func hideResetCountdown() {
        resetCountdownTimer?.invalidate()
        resetCountdownTimer = nil
        resetCountdownHideAt = nil
        usageView.showsResetCountdown = false
    }

    private func setOverlayVisible(_ isVisible: Bool) {
        config.overlayVisible = isVisible
        if isVisible {
            visibility.show()
            reposition(forceFront: true)
        } else {
            hideResetCountdown()
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
