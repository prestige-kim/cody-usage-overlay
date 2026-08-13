using System.Text.Json;

namespace CodyUsageOverlay.Core;

public static class RateLimitParser
{
    public static RateLimitResult Parse(ReadOnlySpan<byte> json)
    {
        using var document = JsonDocument.Parse(json);
        return Parse(document.RootElement);
    }

    public static RateLimitResult Parse(JsonElement root)
    {
        var snapshots = new List<JsonElement>();
        if (root.TryGetProperty("rateLimitsByLimitId", out var buckets) && buckets.ValueKind == JsonValueKind.Object)
        {
            if (buckets.TryGetProperty("codex", out var codex) && codex.ValueKind == JsonValueKind.Object) snapshots.Add(codex);
            else snapshots.AddRange(buckets.EnumerateObject().Where(x => x.Value.ValueKind == JsonValueKind.Object).Select(x => x.Value));
        }
        else if (root.TryGetProperty("rateLimits", out var single) && single.ValueKind == JsonValueKind.Object) snapshots.Add(single);
        else if (root.TryGetProperty("primary", out _)) snapshots.Add(root);

        var windows = new List<RateLimitWindow>();
        foreach (var snapshot in snapshots)
        foreach (var key in new[] { "primary", "secondary" })
        {
            if (!snapshot.TryGetProperty(key, out var raw) || raw.ValueKind != JsonValueKind.Object) continue;
            var used = Integer(raw, "usedPercent", "used_percent");
            if (used is null) continue;
            var duration = Integer(raw, "windowDurationMins", "window_minutes");
            var reset = Integer64(raw, "resetsAt", "resets_at");
            windows.Add(new RateLimitWindow(used.Value, duration, reset is null ? null : DateTimeOffset.FromUnixTimeSeconds(reset.Value)));
        }

        RateLimitWindow? closest(int minutes, int tolerance) => windows
            .Where(x => x.WindowDurationMinutes is not null && Math.Abs(x.WindowDurationMinutes.Value - minutes) <= tolerance)
            .OrderBy(x => Math.Abs(x.WindowDurationMinutes!.Value - minutes)).FirstOrDefault();
        return new RateLimitResult(closest(300, 60), closest(10_080, 1440));
    }

    private static int? Integer(JsonElement element, params string[] names)
    {
        var value = Integer64(element, names);
        return value is >= int.MinValue and <= int.MaxValue ? (int)value.Value : null;
    }

    private static long? Integer64(JsonElement element, params string[] names)
    {
        foreach (var name in names)
            if (element.TryGetProperty(name, out var property))
            {
                if (property.TryGetInt64(out var number)) return number;
                if (property.ValueKind == JsonValueKind.String && long.TryParse(property.GetString(), out number)) return number;
            }
        return null;
    }
}
