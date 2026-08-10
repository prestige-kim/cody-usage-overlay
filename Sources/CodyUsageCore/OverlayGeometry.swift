import Foundation

public enum OverlayGeometry {
    /// Calibrated from two same-scale Cody captures: 166 px of initial gap and
    /// 70 px of overlap at a 40% correction yield a 28.1% foot position.
    public static let spaceBelowFeetRatio = 0.282

    public static func panelOriginY(
        petWindowMinY: Double,
        petWindowHeight: Double,
        panelHeight: Double,
        visibleScreenMinY: Double
    ) -> Double {
        let feetY = petWindowMinY + petWindowHeight * spaceBelowFeetRatio
        let touchingFeetY = feetY - panelHeight + 2
        return max(visibleScreenMinY + 4, touchingFeetY)
    }
}
