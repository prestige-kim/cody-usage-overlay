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
    ("Cody state completion policy", () =>
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(10_000);
        Equal(CodyState.Complete, CodyStatePolicy.VisibleState(CodyState.Complete, now, now.AddSeconds(2.9)));
        Equal(CodyState.Ready, CodyStatePolicy.VisibleState(CodyState.Complete, now, now.AddSeconds(3)));
        Equal(CodyState.Error, CodyStatePolicy.VisibleState(CodyState.Error, now, now.AddSeconds(30)));
    }),
    ("Agent Pulse classification", () =>
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(20_000);
        Equal(AgentPulse.Steady, AgentPulseAnalyzer.Evaluate([], CodyState.Ready, 80, now).Pulse);
        Equal(AgentPulse.Active, AgentPulseAnalyzer.Evaluate([], CodyState.Thinking, 80, now).Pulse);
        Equal(AgentPulse.Stalled, AgentPulseAnalyzer.Evaluate(
            [new AgentPulseEvent(AgentPulseEventKind.TaskStarted, now.AddSeconds(-46))], CodyState.Thinking, 80, now).Pulse);
        Equal(AgentPulse.Steady, AgentPulseAnalyzer.Evaluate(
            [new AgentPulseEvent(AgentPulseEventKind.TaskStarted, now.AddSeconds(-46))], CodyState.Waiting, 80, now).Pulse);
        Equal(AgentPulse.Overloaded, AgentPulseAnalyzer.Evaluate(
            Enumerable.Range(0, 8).Select(x => new AgentPulseEvent(AgentPulseEventKind.ToolCall, now.AddSeconds(-x))),
            CodyState.Acting, 80, now).Pulse);
        Equal(AgentPulse.Unstable, AgentPulseAnalyzer.Evaluate(
            [new AgentPulseEvent(AgentPulseEventKind.Error, now.AddSeconds(-10)), new AgentPulseEvent(AgentPulseEventKind.Error, now.AddSeconds(-2))],
            CodyState.Thinking, 80, now).Pulse);
        Equal(AgentPulse.Finishing, AgentPulseAnalyzer.Evaluate([], CodyState.Complete, 80, now).Pulse);
    }),
    ("reset countdown formats compactly", () =>
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_000_000);
        var display = ResetCountdownFormatter.Create(
            now.AddSeconds(2 * 3600 + 18 * 60 + 43),
            now.AddSeconds(3 * 86400 + 14 * 3600 + 22 * 60 + 59),
            now);
        Equal("02:18:43", display.FiveHourText);
        Equal("3일 14:22", display.WeeklyText);
        Equal(false, display.HasExpiredReset);
        var expired = ResetCountdownFormatter.Create(now.AddSeconds(-1), null, now);
        Equal("갱신 중…", expired.FiveHourText);
        Equal("—", expired.WeeklyText);
        Equal(true, expired.HasExpiredReset);
    }),
    ("Store ChatGPT process resolves bundled Codex", () =>
    {
        var root = Path.Combine(Path.GetTempPath(), "cody-store-check-" + Guid.NewGuid());
        var app = Path.Combine(root, "app");
        var bundledCodex = Path.Combine(app, "resources", "codex.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(bundledCodex)!);
        File.WriteAllText(bundledCodex, "fixture");
        var locator = new CodexExecutableLocator(
            processExecutablePaths: () => [Path.Combine(app, "ChatGPT.exe")],
            storePackageRoots: () => []);
        Equal(Path.GetFullPath(bundledCodex), locator.Locate());
        Directory.Delete(root, true);
    }),
    ("Store package fallback searches unknown layout", () =>
    {
        var root = Path.Combine(Path.GetTempPath(), "cody-store-check-" + Guid.NewGuid());
        var bundledCodex = Path.Combine(root, "app", "runtime", "tools", "codex.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(bundledCodex)!);
        File.WriteAllText(bundledCodex, "fixture");
        var locator = new CodexExecutableLocator(
            processExecutablePaths: () => [],
            storePackageRoots: () => [root]);
        Equal(Path.GetFullPath(bundledCodex), locator.Locate());
        Directory.Delete(root, true);
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
        File.AppendAllText(rollout, "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}" + Environment.NewLine);
        Equal(CodyState.Thinking, monitor.Refresh()?.CodyState);
        File.AppendAllText(rollout, "{\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call\",\"name\":\"exec\",\"call_id\":\"call-1\",\"status\":\"completed\"}}" + Environment.NewLine);
        var acting = monitor.Refresh();
        Equal(CodyState.Acting, acting?.CodyState);
        Equal(AgentPulse.Active, acting?.AgentPulse);
        File.AppendAllText(rollout, "{\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call_output\",\"call_id\":\"call-1\",\"output\":\"ok\"}}" + Environment.NewLine);
        Equal(CodyState.Acting, monitor.Refresh()?.CodyState);
        File.AppendAllText(rollout, "{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"item\":{\"type\":\"Reasoning\"}}}" + Environment.NewLine);
        Equal(CodyState.Thinking, monitor.Refresh()?.CodyState);
        File.AppendAllText(rollout, "{\"type\":\"response_item\",\"payload\":{\"type\":\"custom_tool_call\",\"name\":\"request_user_input\",\"call_id\":\"call-2\",\"status\":\"completed\"}}" + Environment.NewLine);
        Equal(CodyState.Waiting, monitor.Refresh()?.CodyState);
        File.AppendAllText(rollout, "{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"item\":{\"type\":\"CommandExecution\",\"status\":\"failed\"}}}" + Environment.NewLine);
        Equal(CodyState.Error, monitor.Refresh()?.CodyState);
        File.AppendAllText(rollout, "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}" + Environment.NewLine);
        Equal(CodyState.Thinking, monitor.Refresh()?.CodyState);
        File.AppendAllText(rollout, "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}" + Environment.NewLine);
        var completed = monitor.Refresh();
        Equal(CodyState.Complete, completed?.CodyState);
        Equal(AgentPulse.Finishing, completed?.AgentPulse);
        var next = "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"last_token_usage\":{\"total_tokens\":30},\"model_context_window\":100}}";
        File.AppendAllText(rollout, Environment.NewLine + next[..40]);
        Equal(80, monitor.Refresh()?.RemainingPercent);
        File.AppendAllText(rollout, next[40..] + Environment.NewLine);
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
