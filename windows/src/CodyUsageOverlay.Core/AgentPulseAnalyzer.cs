namespace CodyUsageOverlay.Core;

public enum AgentPulse { Steady, Active, Overloaded, Stalled, Unstable, Finishing }
public enum AgentPulseEventKind { TaskStarted, Reasoning, ToolCall, ToolResult, Waiting, Error, Complete, TokenSample }

public sealed record AgentPulseEvent(
    AgentPulseEventKind Kind,
    DateTimeOffset Timestamp,
    int? TotalTokens = null,
    int? ContextWindow = null);

public sealed record AgentPulseEvaluation(AgentPulse Pulse, string Reason);

public static class AgentPulseAnalyzer
{
    public static AgentPulseEvaluation Evaluate(
        IEnumerable<AgentPulseEvent> events,
        CodyState codyState,
        int? contextRemainingPercent,
        DateTimeOffset now)
    {
        var recent = events
            .Where(x => x.Timestamp >= now.AddMinutes(-5) && x.Timestamp <= now.AddSeconds(2))
            .OrderBy(x => x.Timestamp)
            .ToArray();
        var errorCount = recent.Count(x => x.Kind == AgentPulseEventKind.Error);
        if (codyState == CodyState.Error || errorCount >= 2)
            return new AgentPulseEvaluation(AgentPulse.Unstable, errorCount >= 2 ? "오류 반복" : "오류 발생");
        if (codyState == CodyState.Complete)
            return new AgentPulseEvaluation(AgentPulse.Finishing, "작업 완료");

        var latestTaskStarted = recent.LastOrDefault(x => x.Kind == AgentPulseEventKind.TaskStarted)?.Timestamp;
        var latestTaskCompleted = recent.LastOrDefault(x => x.Kind == AgentPulseEventKind.Complete)?.Timestamp;
        var taskIsActive = latestTaskStarted is not null
            ? latestTaskCompleted is null || latestTaskCompleted < latestTaskStarted
            : codyState is CodyState.Thinking or CodyState.Acting;
        static bool IsProgress(AgentPulseEvent value) => value.Kind is
            AgentPulseEventKind.TaskStarted or AgentPulseEventKind.Reasoning or AgentPulseEventKind.ToolCall or AgentPulseEventKind.ToolResult;
        var latestProgress = recent.LastOrDefault(IsProgress)?.Timestamp ?? latestTaskStarted;
        if (taskIsActive && codyState != CodyState.Waiting && latestProgress is not null && now - latestProgress >= TimeSpan.FromSeconds(45))
            return new AgentPulseEvaluation(AgentPulse.Stalled, "진행 이벤트 없음");

        if (contextRemainingPercent is <= 15)
            return new AgentPulseEvaluation(AgentPulse.Overloaded, "컨텍스트 소모 큼");

        var burst = recent.Where(x => x.Timestamp >= now.AddMinutes(-1)).ToArray();
        if (burst.Count(x => x.Kind == AgentPulseEventKind.ToolCall) >= 8)
            return new AgentPulseEvaluation(AgentPulse.Overloaded, "도구 호출 급증");
        var progressCount = burst.Count(IsProgress);
        if (progressCount >= 18)
            return new AgentPulseEvaluation(AgentPulse.Overloaded, "이벤트 밀도 높음");

        var samples = recent.Where(x => x.Kind == AgentPulseEventKind.TokenSample && x.TotalTokens is not null && x.ContextWindow is not null).ToArray();
        if (samples.Length >= 2)
        {
            var first = samples[0];
            var last = samples[^1];
            var threshold = Math.Max(12_000, last.ContextWindow!.Value * 8 / 100);
            if (last.Timestamp > first.Timestamp && last.TotalTokens!.Value - first.TotalTokens!.Value >= threshold)
                return new AgentPulseEvaluation(AgentPulse.Overloaded, "컨텍스트 소모 빠름");
        }

        if (codyState is CodyState.Thinking or CodyState.Acting || progressCount >= 3)
            return new AgentPulseEvaluation(AgentPulse.Active, "안정적인 진행");
        if (codyState == CodyState.Waiting)
            return new AgentPulseEvaluation(AgentPulse.Steady, "입력 대기 · 정상");
        return new AgentPulseEvaluation(AgentPulse.Steady, "흐름 안정");
    }
}
