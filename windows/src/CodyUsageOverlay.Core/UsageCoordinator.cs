namespace CodyUsageOverlay.Core;

public sealed class UsageCoordinator(IAppServerClient client, ISessionMonitor sessionMonitor) : IAsyncDisposable
{
    private readonly object gate = new();
    private CancellationTokenSource? lifetime;
    private UsageSnapshot snapshot = new(LastUpdatedAt: DateTimeOffset.Now);
    private DateTimeOffset? lastRateLimitUpdate;
    private DateTimeOffset? lastContextUpdate;
    public event Action<UsageSnapshot>? Updated;
    public UsageSnapshot Snapshot { get { lock (gate) return snapshot; } }

    public void Start()
    {
        if (lifetime is not null) return;
        lifetime = new CancellationTokenSource();
        client.Notification += OnNotification;
        sessionMonitor.Updated += OnContext;
        sessionMonitor.Start();
        _ = RefreshLoopAsync(lifetime.Token);
        _ = FreshnessLoopAsync(lifetime.Token);
    }

    public Task ForceRefreshAsync(CancellationToken cancellationToken = default) => RefreshRateLimitsAsync(cancellationToken);

    private async Task RefreshLoopAsync(CancellationToken cancellationToken)
    {
        var retry = TimeSpan.FromSeconds(2);
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await RefreshRateLimitsAsync(cancellationToken);
                retry = TimeSpan.FromSeconds(60);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { break; }
            catch
            {
                lock (gate) snapshot = snapshot with { Freshness = HasAnyValue(snapshot) ? Freshness.Delayed : Freshness.Unavailable };
                Publish();
                retry = TimeSpan.FromSeconds(Math.Min(60, Math.Max(2, retry.TotalSeconds * 2)));
            }
            try { await Task.Delay(retry, cancellationToken); } catch (OperationCanceledException) { break; }
        }
    }

    private async Task RefreshRateLimitsAsync(CancellationToken cancellationToken)
    {
        var raw = await client.ReadRateLimitsAsync(cancellationToken);
        Merge(RateLimitParser.Parse(raw));
    }

    private void OnNotification(string method, byte[] payload)
    {
        if (!method.Equals("account/rateLimits/updated", StringComparison.OrdinalIgnoreCase)) return;
        try { Merge(RateLimitParser.Parse(payload)); }
        catch { lock (gate) snapshot = snapshot with { Freshness = Freshness.Incompatible }; Publish(); }
    }

    private void Merge(RateLimitResult result)
    {
        lock (gate)
        {
            var five = result.FiveHour;
            var weekly = result.Weekly;
            snapshot = snapshot with
            {
                FiveHourRemainingPercent = five is null ? snapshot.FiveHourRemainingPercent : MergeRemaining(snapshot.FiveHourRemainingPercent, snapshot.FiveHourResetsAt, five),
                FiveHourResetsAt = five?.ResetsAt ?? snapshot.FiveHourResetsAt,
                WeeklyRemainingPercent = weekly is null ? snapshot.WeeklyRemainingPercent : MergeRemaining(snapshot.WeeklyRemainingPercent, snapshot.WeeklyResetsAt, weekly),
                WeeklyResetsAt = weekly?.ResetsAt ?? snapshot.WeeklyResetsAt,
                LastUpdatedAt = DateTimeOffset.Now,
                Freshness = Freshness.Fresh
            };
            lastRateLimitUpdate = DateTimeOffset.Now;
        }
        Publish();
    }

    private void OnContext(ContextUsage usage)
    {
        lock (gate)
        {
            snapshot = snapshot with
            {
                ContextRemainingPercent = usage.RemainingPercent,
                ActiveThreadId = usage.ThreadId,
                CodyState = usage.CodyState,
                CodyStateUpdatedAt = usage.CodyStateUpdatedAt,
                AgentPulse = usage.AgentPulse,
                AgentPulseReason = usage.AgentPulseReason,
                LastUpdatedAt = DateTimeOffset.Now,
                Freshness = Freshness.Fresh
            };
            lastContextUpdate = usage.UpdatedAt;
        }
        if (usage.RateLimits is not null) Merge(usage.RateLimits); else Publish();
    }

    private async Task FreshnessLoopAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
            try { sessionMonitor.RefreshActive(); } catch { }
            lock (gate)
            {
                if (snapshot.CodyStateUpdatedAt is DateTimeOffset stateUpdatedAt)
                {
                    var visibleState = CodyStatePolicy.VisibleState(snapshot.CodyState, stateUpdatedAt, DateTimeOffset.Now);
                    if (visibleState != snapshot.CodyState)
                        snapshot = snapshot with { CodyState = visibleState, CodyStateUpdatedAt = DateTimeOffset.Now };
                }
                var newest = new[] { lastRateLimitUpdate, lastContextUpdate }.Where(x => x is not null).Max();
                if (newest is not null && DateTimeOffset.Now - newest > TimeSpan.FromSeconds(90) && snapshot.Freshness == Freshness.Fresh)
                    snapshot = snapshot with { Freshness = Freshness.Delayed };
            }
            Publish();
        }
    }

    private static int MergeRemaining(int? current, DateTimeOffset? currentReset, RateLimitWindow incoming) =>
        current is not null && currentReset is not null && incoming.ResetsAt is not null && Math.Abs((currentReset.Value - incoming.ResetsAt.Value).TotalSeconds) < 1
            ? Math.Min(current.Value, incoming.RemainingPercent) : incoming.RemainingPercent;
    private static bool HasAnyValue(UsageSnapshot value) => value.ContextRemainingPercent is not null || value.FiveHourRemainingPercent is not null || value.WeeklyRemainingPercent is not null;
    private void Publish() { UsageSnapshot value; lock (gate) value = snapshot; Updated?.Invoke(value); }

    public async ValueTask DisposeAsync()
    {
        lifetime?.Cancel(); lifetime?.Dispose(); lifetime = null;
        sessionMonitor.Dispose();
        await client.DisposeAsync();
    }
}
