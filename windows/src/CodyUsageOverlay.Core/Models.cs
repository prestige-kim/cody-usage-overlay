namespace CodyUsageOverlay.Core;

public enum Freshness { Fresh, Delayed, Unavailable, Incompatible }
public enum CodyState { Ready, Thinking, Acting, Waiting, Complete, Error }

public static class CodyStatePolicy
{
    public static CodyState VisibleState(CodyState state, DateTimeOffset updatedAt, DateTimeOffset now, TimeSpan? completedDisplayDuration = null) =>
        state == CodyState.Complete && now - updatedAt >= (completedDisplayDuration ?? TimeSpan.FromSeconds(3))
            ? CodyState.Ready
            : state;
}

public sealed record UsageSnapshot(
    int? ContextRemainingPercent = null,
    int? FiveHourRemainingPercent = null,
    int? WeeklyRemainingPercent = null,
    DateTimeOffset? FiveHourResetsAt = null,
    DateTimeOffset? WeeklyResetsAt = null,
    string? ActiveThreadId = null,
    CodyState CodyState = CodyUsageOverlay.Core.CodyState.Ready,
    DateTimeOffset? CodyStateUpdatedAt = null,
    AgentPulse AgentPulse = CodyUsageOverlay.Core.AgentPulse.Steady,
    string AgentPulseReason = "흐름 안정",
    DateTimeOffset? LastUpdatedAt = null,
    Freshness Freshness = Freshness.Unavailable);

public sealed record RateLimitWindow(int UsedPercent, int? WindowDurationMinutes, DateTimeOffset? ResetsAt)
{
    public int RemainingPercent => Math.Clamp(100 - UsedPercent, 0, 100);
}

public sealed record RateLimitResult(RateLimitWindow? FiveHour = null, RateLimitWindow? Weekly = null);

public sealed record ContextUsage(
    string ThreadId,
    int UsedTokens,
    int ModelContextWindow,
    DateTimeOffset UpdatedAt,
    RateLimitResult? RateLimits = null,
    CodyState CodyState = CodyUsageOverlay.Core.CodyState.Ready,
    DateTimeOffset? CodyStateUpdatedAt = null,
    AgentPulse AgentPulse = CodyUsageOverlay.Core.AgentPulse.Steady,
    string AgentPulseReason = "흐름 안정")
{
    public int RemainingPercent => ModelContextWindow <= 0
        ? 0
        : Math.Clamp((int)Math.Round((1d - (double)UsedTokens / ModelContextWindow) * 100d), 0, 100);
}

public sealed class OverlayConfig
{
    public bool LaunchAtLogin { get; set; } = true;
    public double ManualLeft { get; set; } = double.NaN;
    public double ManualTop { get; set; } = double.NaN;
    public bool AlwaysOnTop { get; set; } = true;
    public int WarningThreshold { get; set; } = 30;
    public int CriticalThreshold { get; set; } = 10;
    public string? CodexExecutablePath { get; set; }
}

public readonly record struct NativeRect(int Left, int Top, int Right, int Bottom)
{
    public int Width => Right - Left;
    public int Height => Bottom - Top;
    public int CenterX => Left + Width / 2;
    public int CenterY => Top + Height / 2;
}

public sealed record AnchorLayout(NativeRect Pet, NativeRect? Activity, NativeRect WorkArea);

public interface ICodexExecutableLocator { string? Locate(); IReadOnlyList<string> Candidates { get; } }
public interface IAppServerClient : IAsyncDisposable
{
    event Action<string, byte[]>? Notification;
    Task StartAsync(CancellationToken cancellationToken = default);
    Task<byte[]> ReadRateLimitsAsync(CancellationToken cancellationToken = default);
}
public interface ISessionMonitor : IDisposable
{
    event Action<ContextUsage>? Updated;
    ContextUsage? Refresh();
    ContextUsage? RefreshActive();
    void Start();
}
public interface IWindowAnchorProvider : IDisposable
{
    event Action? Changed;
    AnchorLayout? FindAnchor();
    string Diagnostics { get; }
}
public interface IAutoStartManager
{
    bool IsEnabled { get; }
    void SetEnabled(bool enabled);
}
