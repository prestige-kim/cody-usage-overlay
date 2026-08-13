namespace CodyUsageOverlay.Core;

public static class OverlayGeometry
{
    public static (double Left, double Top) OppositeActivity(AnchorLayout layout, double width, double height)
    {
        var centerX = layout.Activity?.CenterX ?? layout.Pet.CenterX;
        var activityCenterY = layout.Activity?.CenterY;
        var distance = activityCenterY is null ? Math.Max(height * 1.8, layout.Pet.Height * 0.8) : Math.Abs(activityCenterY.Value - layout.Pet.CenterY);
        var targetCenterY = activityCenterY is null
            ? (layout.Pet.CenterY <= (layout.WorkArea.Top + layout.WorkArea.Bottom) / 2d
                ? layout.Pet.CenterY + distance : layout.Pet.CenterY - distance)
            : 2d * layout.Pet.CenterY - activityCenterY.Value;
        var left = Math.Clamp(centerX - width / 2d, layout.WorkArea.Left + 4d, layout.WorkArea.Right - width - 4d);
        var top = Math.Clamp(targetCenterY - height / 2d, layout.WorkArea.Top + 4d, layout.WorkArea.Bottom - height - 4d);
        return (left, top);
    }
}
