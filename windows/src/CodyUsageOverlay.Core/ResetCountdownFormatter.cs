namespace CodyUsageOverlay.Core;

public sealed record ResetCountdownDisplay(string FiveHourText, string WeeklyText, bool HasExpiredReset);

public static class ResetCountdownFormatter
{
    public static ResetCountdownDisplay Create(
        DateTimeOffset? fiveHourResetsAt,
        DateTimeOffset? weeklyResetsAt,
        DateTimeOffset? now = null)
    {
        var reference = now ?? DateTimeOffset.Now;
        var fiveHour = CountdownTo(fiveHourResetsAt, reference);
        var weekly = CountdownTo(weeklyResetsAt, reference);
        return new ResetCountdownDisplay(
            FormatFiveHour(fiveHour.Seconds, fiveHour.State),
            FormatWeekly(weekly.Seconds, weekly.State),
            fiveHour.State == CountdownState.Expired || weekly.State == CountdownState.Expired);
    }

    private enum CountdownState { Available, Missing, Expired }

    private static (int Seconds, CountdownState State) CountdownTo(DateTimeOffset? reset, DateTimeOffset now)
    {
        if (reset is null) return (0, CountdownState.Missing);
        var interval = reset.Value - now;
        if (interval <= TimeSpan.Zero) return (0, CountdownState.Expired);
        return ((int)Math.Floor(interval.TotalSeconds), CountdownState.Available);
    }

    private static string FormatFiveHour(int seconds, CountdownState state)
    {
        if (state != CountdownState.Available) return state == CountdownState.Expired ? "갱신 중…" : "—";
        return $"{seconds / 3600:00}:{seconds % 3600 / 60:00}:{seconds % 60:00}";
    }

    private static string FormatWeekly(int seconds, CountdownState state)
    {
        if (state != CountdownState.Available) return state == CountdownState.Expired ? "갱신 중…" : "—";
        var days = seconds / 86400;
        var hours = seconds % 86400 / 3600;
        var minutes = seconds % 3600 / 60;
        return days > 0
            ? $"{days}일 {hours:00}:{minutes:00}"
            : $"{hours:00}:{minutes:00}:{seconds % 60:00}";
    }
}
