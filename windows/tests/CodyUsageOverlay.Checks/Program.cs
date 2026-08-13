using CodyUsageOverlay.Core;
using System.Text;

var checks = new List<(string Name, Action Run)>
{
    ("rate limits classify by duration", () =>
    {
        var value = RateLimitParser.Parse(Encoding.UTF8.GetBytes("""
          {"rateLimits":{"primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1800000000},"secondary":{"usedPercent":9,"windowDurationMins":300,"resetsAt":1700000000}}}
          """));
        Equal(91, value.FiveHour?.RemainingPercent); Equal(83, value.Weekly?.RemainingPercent);
    }),
    ("limit bucket order is irrelevant", () =>
    {
        var value = RateLimitParser.Parse(Encoding.UTF8.GetBytes("""
          {"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":99,"windowDurationMins":60}},"codex":{"primary":{"used_percent":40,"window_minutes":10080},"secondary":{"used_percent":25,"window_minutes":300}}}}
          """));
        Equal(75, value.FiveHour?.RemainingPercent); Equal(60, value.Weekly?.RemainingPercent);
    }),
    ("five-hour is optional", () =>
    {
        var value = RateLimitParser.Parse(Encoding.UTF8.GetBytes("""{"rateLimits":{"primary":{"usedPercent":2,"windowDurationMins":10080}}}"""));
        Equal(null, value.FiveHour); Equal(98, value.Weekly?.RemainingPercent);
    }),
    ("context remaining is bounded", () =>
    {
        Equal(75, new ContextUsage("a", 25, 100, DateTimeOffset.Now).RemainingPercent);
        Equal(0, new ContextUsage("a", 200, 100, DateTimeOffset.Now).RemainingPercent);
    }),
    ("overlay mirrors activity", () =>
    {
        var below = OverlayGeometry.OppositeActivity(new AnchorLayout(new NativeRect(400, 300, 600, 500), new NativeRect(300, 100, 700, 200), new NativeRect(0, 0, 1920, 1040)), 242, 62);
        True(below.Top > 500);
        var above = OverlayGeometry.OppositeActivity(new AnchorLayout(new NativeRect(400, 300, 600, 500), new NativeRect(300, 600, 700, 680), new NativeRect(0, 0, 1920, 1040)), 242, 62);
        True(above.Top < 300);
    }),
    ("desktop root rollout is selected incrementally", () =>
    {
        var root = Path.Combine(Path.GetTempPath(), "cody-usage-check-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        var rollout = Path.Combine(root, "rollout.jsonl");
        File.WriteAllLines(rollout,
        [
            "{\"type\":\"session_meta\",\"payload\":{\"id\":\"thread-1\",\"originator\":\"Codex Desktop\",\"source\":\"vscode\"}}",
            "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"last_token_usage\":{\"total_tokens\":20},\"model_context_window\":100}}"
        ]);
        using var monitor = new RolloutSessionMonitor(root);
        Equal(80, monitor.Refresh()?.RemainingPercent);
        File.AppendAllText(rollout, Environment.NewLine + "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"last_token_usage\":{\"total_tokens\":30},\"model_context_window\":100}}");
        Equal(70, monitor.Refresh()?.RemainingPercent);
        Directory.Delete(root, true);
    })
};

foreach (var check in checks)
{
    try { check.Run(); Console.WriteLine($"PASS {check.Name}"); }
    catch (Exception error) { Console.Error.WriteLine($"FAIL {check.Name}: {error.Message}"); Environment.ExitCode = 1; }
}
if (Environment.ExitCode == 0) Console.WriteLine("All Windows core checks passed.");

static void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException($"expected {expected}, got {actual}"); }
static void True(bool value) { if (!value) throw new InvalidOperationException("condition was false"); }
