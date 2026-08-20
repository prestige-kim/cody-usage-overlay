import Foundation
import CoreGraphics

public struct OverlayWindowSnapshot: Sendable {
    public let id: UInt32
    public let rect: CGRect
    public let layer: Int
    public let alpha: Double
    public let name: String
    public let isOnscreen: Bool?

    public init(
        id: UInt32,
        rect: CGRect,
        layer: Int,
        alpha: Double,
        name: String,
        isOnscreen: Bool? = nil
    ) {
        self.id = id
        self.rect = rect
        self.layer = layer
        self.alpha = alpha
        self.name = name
        self.isOnscreen = isOnscreen
    }
}

public enum PetWindowSelector {
    public static func select(
        from windows: [OverlayWindowSnapshot],
        trackedWindowID: UInt32? = nil,
        lastKnownRect: CGRect? = nil
    ) -> OverlayWindowSnapshot? {
        let candidates = windows.filter(isPetCandidate)
        if let trackedWindowID,
           let tracked = candidates.first(where: { $0.id == trackedWindowID }) {
            return tracked
        }
        return candidates.max { score($0, lastKnownRect: lastKnownRect) < score($1, lastKnownRect: lastKnownRect) }
    }

    public static func isPetCandidate(_ window: OverlayWindowSnapshot) -> Bool {
        let name = window.name.lowercased()
        if name.contains("pet mascot effect") ||
            (name.contains("pet surface") && name.contains("mascot")) {
            return true
        }

        // Recent ChatGPT builds render the mascot through a native composition
        // panel. CGWindowList exposes the panel without a title or on-screen bit,
        // while its tiny translucent pointer surface appears on a much higher
        // layer. Keep the anonymous fallback deliberately narrow.
        guard name.isEmpty,
              window.alpha >= 0.5,
              window.layer > 0,
              window.layer < 32,
              window.rect.width >= 48,
              window.rect.width <= 420,
              window.rect.height >= 48,
              window.rect.height <= 420,
              window.rect.width * window.rect.height >= 2_500 else {
            return false
        }
        let aspectRatio = window.rect.width / window.rect.height
        return aspectRatio >= 0.45 && aspectRatio <= 3.2
    }

    private static func score(_ window: OverlayWindowSnapshot, lastKnownRect: CGRect?) -> Double {
        let name = window.name.lowercased()
        var result = 0.0
        if name.contains("pet mascot effect") { result += 20_000 }
        if name.contains("pet surface") && name.contains("mascot") { result += 18_000 }
        if window.layer == 3 { result += 1_000 }
        if window.isOnscreen == true { result += 500 }

        // Prefer the compact mascot-sized surface over larger auxiliary panels.
        let targetArea = 96.0 * 96.0
        result -= abs(Double(window.rect.width * window.rect.height) - targetArea) / 100
        if let lastKnownRect {
            result -= hypot(
                Double(window.rect.midX - lastKnownRect.midX),
                Double(window.rect.midY - lastKnownRect.midY)
            )
        }
        return result
    }
}

public enum OverlayGeometry {
    public static func draggedOrigin(
        windowOrigin: CGPoint,
        dragStart: CGPoint,
        currentPointer: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: windowOrigin.x + currentPointer.x - dragStart.x,
            y: windowOrigin.y + currentPointer.y - dragStart.y
        )
    }

    public static func oppositeActivityOriginY(
        petCenterY: Double,
        activityCenterY: Double?,
        lastActivityDistance: Double?,
        panelHeight: Double,
        visibleScreenMinY: Double,
        visibleScreenMaxY: Double
    ) -> Double {
        let targetCenterY: Double
        if let activityCenterY {
            targetCenterY = 2 * petCenterY - activityCenterY
        } else {
            let distance = lastActivityDistance ?? panelHeight * 1.8
            let screenCenterY = (visibleScreenMinY + visibleScreenMaxY) / 2
            targetCenterY = petCenterY >= screenCenterY
                ? petCenterY + distance
                : petCenterY - distance
        }
        let unclamped = targetCenterY - panelHeight / 2
        return min(
            visibleScreenMaxY - panelHeight - 4,
            max(visibleScreenMinY + 4, unclamped)
        )
    }

    public static func clampedOrigin(
        x: Double,
        y: Double,
        panelWidth: Double,
        panelHeight: Double,
        visibleScreenFrame: CGRect,
        margin: Double = 4
    ) -> CGPoint {
        CGPoint(
            x: min(
                visibleScreenFrame.maxX - panelWidth - margin,
                max(visibleScreenFrame.minX + margin, x)
            ),
            y: min(
                visibleScreenFrame.maxY - panelHeight - margin,
                max(visibleScreenFrame.minY + margin, y)
            )
        )
    }
}
