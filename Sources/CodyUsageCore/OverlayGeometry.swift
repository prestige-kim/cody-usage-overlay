import Foundation

public enum OverlayGeometry {
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
}
