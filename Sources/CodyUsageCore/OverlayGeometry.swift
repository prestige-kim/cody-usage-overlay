import Foundation

public enum OverlayGeometry {
    /// The Codex pet window includes the built-in controls below the pet.
    /// Keep the usage panel just below that complete interactive area.
    public static let gapBelowPetControls = 4.0

    public static func panelOriginY(
        petWindowMinY: Double,
        petWindowHeight: Double,
        panelHeight: Double,
        visibleScreenMinY: Double
    ) -> Double {
        let belowControlsY = petWindowMinY - panelHeight - gapBelowPetControls
        return max(visibleScreenMinY + 4, belowControlsY)
    }
}
