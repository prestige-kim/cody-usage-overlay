using CodyUsageOverlay.Core;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace CodyUsageOverlay.App;

public partial class MainWindow : Window
{
    private readonly string configPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodyUsageOverlayData", "config.json");
    private readonly OverlayConfig config;
    private readonly CodexExecutableLocator locator;
    private readonly Win32WindowAnchorProvider anchors = new();
    private readonly WindowsAutoStartManager autoStart = new();
    private readonly UsageCoordinator coordinator;
    private readonly DispatcherTimer correctionTimer;
    private readonly DispatcherTimer resetCountdownTimer;
    private readonly DispatcherTimer codyFluidTimer;
    private UsageSnapshot snapshot = new(LastUpdatedAt: DateTimeOffset.Now);
    private CodyState renderedCodyState = CodyState.Ready;
    private AgentPulse renderedAgentPulse = AgentPulse.Steady;
    private DateTimeOffset codyFluidStartedAt = DateTimeOffset.Now;
    private DateTimeOffset agentPulseStartedAt = DateTimeOffset.Now;
    private IntPtr hwnd;
    private bool anchored;
    private bool dismissed;
    private bool waitingForPetToAppear;
    private bool lastPetVisible;
    private bool showsResetCountdown;
    private bool resetCountdownRefreshRequested;
    private DateTimeOffset? resetCountdownHideAt;
    private static readonly Brush TimerInactiveBrush = new SolidColorBrush(Color.FromArgb(0x23, 0xFF, 0xFF, 0xFF));
    private static readonly Brush TimerActiveBrush = new SolidColorBrush(Color.FromArgb(0xEB, 0x6F, 0x92, 0xFF));
    private static readonly Brush CountdownLabelBrush = new SolidColorBrush(Color.FromArgb(0x8F, 0xFF, 0xFF, 0xFF));
    private static readonly Brush CountdownValueBrush = new SolidColorBrush(Color.FromRgb(0xA9, 0xC0, 0xFF));

    public MainWindow()
    {
        config = LoadConfig();
        locator = new CodexExecutableLocator(config);
        var client = new AppServerClient(locator);
        var sessions = new RolloutSessionMonitor();
        coordinator = new UsageCoordinator(client, sessions);
        InitializeComponent();
        Topmost = config.AlwaysOnTop;
        SourceInitialized += OnSourceInitialized;
        Loaded += OnLoaded;
        Closed += OnClosed;
        MouseLeftButtonDown += OnDrag;
        anchors.Changed += () => Dispatcher.BeginInvoke(Reposition);
        coordinator.Updated += value => Dispatcher.BeginInvoke(() => Render(value));
        correctionTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(100), DispatcherPriority.Render, (_, _) => Reposition(), Dispatcher);
        resetCountdownTimer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, (_, _) => TickResetCountdown(), Dispatcher);
        codyFluidTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(1000d / 24d), DispatcherPriority.Render, (_, _) => AnimateCodyFluid(), Dispatcher);
        ContextMenu = BuildContextMenu();
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        hwnd = new WindowInteropHelper(this).Handle;
        var style = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(style | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE));
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        PlaceManualInitially();
        coordinator.Start();
        correctionTimer.Start();
        Reposition();
    }

    private void Render(UsageSnapshot value)
    {
        snapshot = value;
        RenderContent(DateTimeOffset.Now);
        RenderCodyState(value.CodyState);
        RenderAgentPulse(value.AgentPulse, value.AgentPulseReason);
        ToolTip = $"Cody: {CodyStateLabel(value.CodyState)}\nAgent Pulse: {AgentPulseLabel(value.AgentPulse)} · {value.AgentPulseReason}\n마지막 갱신: {value.LastUpdatedAt?.LocalDateTime:T}\n태스크: {value.ActiveThreadId ?? "확인 중"}";
    }

    private void RenderContent(DateTimeOffset now)
    {
        if (showsResetCountdown)
        {
            var countdown = ResetCountdownFormatter.Create(snapshot.FiveHourResetsAt, snapshot.WeeklyResetsAt, now);
            RenderCountdownLine(LimitsText, "5h", countdown.FiveHourText, 14);
            RenderCountdownLine(ContextText, "Week", countdown.WeeklyText, 12);
            RefreshExpiredResetIfNeeded(countdown);
            return;
        }

        LimitsText.Inlines.Clear();
        ContextText.Inlines.Clear();
        LimitsText.FontFamily = new FontFamily("Segoe UI");
        ContextText.FontFamily = new FontFamily("Segoe UI");
        LimitsText.FontSize = snapshot.FiveHourRemainingPercent is null ? 16 : 12;
        LimitsText.FontWeight = FontWeights.Bold;
        ContextText.FontSize = 11;
        ContextText.FontWeight = FontWeights.Medium;
        LimitsText.Text = snapshot.FiveHourRemainingPercent is int five ? $"5h {five}% · Week {Percent(snapshot.WeeklyRemainingPercent)}" : $"Week {Percent(snapshot.WeeklyRemainingPercent)}";
        var suffix = snapshot.Freshness == Freshness.Fresh ? "" : snapshot.Freshness == Freshness.Incompatible ? "  호환성 확인 필요" : "  지연됨";
        ContextText.Text = $"Context {Percent(snapshot.ContextRemainingPercent)}{suffix}";
        var limitValues = new[] { snapshot.FiveHourRemainingPercent, snapshot.WeeklyRemainingPercent }.Where(x => x is not null).Select(x => x!.Value).ToArray();
        LimitsText.Foreground = BrushFor(limitValues.Length == 0 ? null : limitValues.Min());
        ContextText.Foreground = new SolidColorBrush(Color.FromArgb(0xC7, 0xFF, 0xFF, 0xFF));
    }

    private static void RenderCountdownLine(System.Windows.Controls.TextBlock block, string label, string value, double valueSize)
    {
        block.Text = "";
        block.Inlines.Clear();
        block.FontFamily = new FontFamily("Segoe UI");
        block.Inlines.Add(new Run(label) { FontSize = 10, FontWeight = FontWeights.Medium, Foreground = CountdownLabelBrush });
        block.Inlines.Add(new Run($"   {value}") { FontFamily = new FontFamily("Consolas"), FontSize = valueSize, FontWeight = FontWeights.SemiBold, Foreground = CountdownValueBrush });
    }

    private void RenderCodyState(CodyState state)
    {
        var (color, secondary) = state switch
        {
            CodyState.Thinking => (Color.FromRgb(0x14, 0x7A, 0xFF), Color.FromRgb(0x0D, 0xD6, 0xF2)),
            CodyState.Acting => (Color.FromRgb(0x78, 0x33, 0xFF), Color.FromRgb(0x2E, 0x7D, 0xFF)),
            CodyState.Waiting => (Color.FromRgb(0xFF, 0x7A, 0x14), Color.FromRgb(0xFF, 0xBF, 0x29)),
            CodyState.Complete => (Color.FromRgb(0x0F, 0xB8, 0x61), Color.FromRgb(0x4F, 0xEB, 0x9C)),
            CodyState.Error => (Color.FromRgb(0xF0, 0x1F, 0x3D), Color.FromRgb(0xFF, 0x57, 0x33)),
            _ => (Color.FromRgb(0x40, 0x52, 0x75), Color.FromRgb(0x5C, 0x6E, 0x91))
        };
        var brush = new SolidColorBrush(color);
        CodyFluidBlobOne.Fill = brush;
        CodyFluidBlobTwo.Fill = new SolidColorBrush(secondary);
        CodyFluidBlobThree.Fill = brush;
        CodyFluidRipple.Fill = brush;
        CodyGlobalBlobOne.Fill = brush;
        CodyGlobalBlobTwo.Fill = new SolidColorBrush(secondary);
        CodyGlobalBlobThree.Fill = brush;
        CodyGlobalRipple.Fill = brush;
        CodyStateLabelText.Text = CodyStateLabel(state);
        CodyStateLabelText.Foreground = brush;
        CodyStateIndicator.ToolTip = $"Cody 상태 · {CodyStateLabel(state)}";

        if (renderedCodyState != state)
        {
            renderedCodyState = state;
            codyFluidStartedAt = DateTimeOffset.Now;
        }
        UpdateAnimationTimer();
        AnimateCodyFluid();
    }

    private void RenderAgentPulse(AgentPulse pulse, string reason)
    {
        var color = AgentPulseColor(pulse);
        var brush = new SolidColorBrush(color);
        AgentPulseLabelText.Text = $"{AgentPulseLabel(pulse)} · {reason}";
        AgentPulseLabelText.Foreground = brush;
        AgentPulseIndicator.ToolTip = $"Agent Pulse · {AgentPulseLabel(pulse)} · {reason}";
        if (renderedAgentPulse != pulse)
        {
            renderedAgentPulse = pulse;
            agentPulseStartedAt = DateTimeOffset.Now;
        }
        UpdateAnimationTimer();
        AnimateAgentPulse();
    }

    private void UpdateAnimationTimer()
    {
        if (renderedCodyState == CodyState.Ready && renderedAgentPulse == AgentPulse.Steady) codyFluidTimer.Stop();
        else if (!codyFluidTimer.IsEnabled) codyFluidTimer.Start();
    }

    private void AnimateCodyFluid()
    {
        var elapsed = Math.Max(0, (DateTimeOffset.Now - codyFluidStartedAt).TotalSeconds);
        var (speed, motion, opacity, globalOpacity) = renderedCodyState switch
        {
            CodyState.Thinking => (1.05, 1.7, 0.26, 0.13),
            CodyState.Acting => (2.15, 2.6, 0.31, 0.18),
            CodyState.Waiting => (0.64, 1.2, 0.25, 0.12),
            CodyState.Complete => (0.78, 0.9, 0.24, 0.14),
            CodyState.Error => (1.72, 2.1, 0.28, 0.16),
            _ => (0.0, 0.0, 0.12, 0.025)
        };
        var phase = elapsed * speed;
        PositionFluid(CodyFluidBlobOne, 3, 6, motion, phase, opacity);
        PositionFluid(CodyFluidBlobTwo, 8, 3, motion * 0.78, phase + 1.7, opacity * 0.82);
        PositionFluid(CodyFluidBlobThree, 5, 9, motion * 0.58, phase + 3.4, opacity * 0.66);
        PositionFluid(CodyGlobalBlobOne, 10, -11, motion * 3.4, phase * 0.54, globalOpacity);
        PositionFluid(CodyGlobalBlobTwo, 33, -18, motion * 2.7, phase * 0.65 + 2.1, globalOpacity * 0.8);
        PositionFluid(CodyGlobalBlobThree, 18, -3, motion * 2.2, phase * 0.76 + 4.2, globalOpacity * 0.62);

        if (renderedCodyState == CodyState.Complete && elapsed < 1.05)
        {
            var progress = elapsed / 1.05;
            var width = 24 + progress * 26;
            var height = 22 + progress * 22;
            CodyFluidRipple.Width = width;
            CodyFluidRipple.Height = height;
            Canvas.SetLeft(CodyFluidRipple, 25 - width / 2);
            Canvas.SetTop(CodyFluidRipple, 24 - height / 2);
            CodyFluidRipple.Opacity = (1 - progress) * 0.28;
            var globalWidth = 48 + progress * 320;
            var globalHeight = 34 + progress * 104;
            CodyGlobalRipple.Width = globalWidth;
            CodyGlobalRipple.Height = globalHeight;
            Canvas.SetLeft(CodyGlobalRipple, 120 - globalWidth / 2);
            Canvas.SetTop(CodyGlobalRipple, 30 - globalHeight / 2);
            CodyGlobalRipple.Opacity = (1 - progress) * 0.18;
        }
        else
        {
            CodyFluidRipple.Opacity = 0;
            CodyGlobalRipple.Opacity = 0;
        }
        AnimateAgentPulse();
    }

    private void AnimateAgentPulse()
    {
        var elapsed = Math.Max(0, (DateTimeOffset.Now - agentPulseStartedAt).TotalSeconds);
        var (speed, motion, opacity) = renderedAgentPulse switch
        {
            AgentPulse.Active => (1.35, 3.8, 0.052),
            AgentPulse.Overloaded => (2.65, 6.2, 0.075),
            AgentPulse.Stalled => (0.22, 0.4, 0.025),
            AgentPulse.Unstable => (2.20, 7.4, 0.070),
            AgentPulse.Finishing => (0.85, 2.6, 0.055),
            _ => (0.12, 0.6, 0.018)
        };
        var phase = elapsed * speed;
        var breath = 0.88 + 0.12 * Math.Sin(phase * 0.43);
        PositionPulseBackground(AgentPulseBackgroundBlobOne, 66, -1, motion, phase * 0.58, opacity * breath);
        PositionPulseBackground(AgentPulseBackgroundBlobTwo, 80, -5, motion * 0.82, phase * 0.75 + 2.2, opacity * breath * 0.76);
        PositionPulseBackground(AgentPulseBackgroundBlobThree, 91, 3, motion * 0.65, phase * 0.92 + 4.4, opacity * breath * 0.52);

        if (renderedAgentPulse == AgentPulse.Finishing && elapsed < 1.1)
        {
            var progress = elapsed / 1.1;
            AgentPulseBackgroundBloom.Width = 56 + progress * 184;
            AgentPulseBackgroundBloom.Height = 32 + progress * 56;
            Canvas.SetLeft(AgentPulseBackgroundBloom, 142 - AgentPulseBackgroundBloom.Width / 2);
            Canvas.SetTop(AgentPulseBackgroundBloom, 30 - AgentPulseBackgroundBloom.Height / 2);
            AgentPulseBackgroundBloom.Opacity = (1 - progress) * 0.065;
        }
        else AgentPulseBackgroundBloom.Opacity = 0;
    }

    private static void PositionPulseBackground(System.Windows.Shapes.Ellipse blob, double left, double top, double motion, double phase, double opacity)
    {
        Canvas.SetLeft(blob, left + Math.Sin(phase * 0.79) * motion);
        Canvas.SetTop(blob, top + Math.Cos(phase * 0.61) * motion * 0.62);
        blob.Opacity = opacity;
        blob.RenderTransformOrigin = new Point(0.5, 0.5);
        blob.RenderTransform = new ScaleTransform(
            1 + Math.Sin(phase * 0.67) * motion * 0.012,
            1 + Math.Cos(phase * 0.53) * motion * 0.012
        );
    }

    private static Color AgentPulseColor(AgentPulse pulse) => pulse switch
    {
        AgentPulse.Active => Color.FromRgb(0x35, 0xEB, 0xFF),
        AgentPulse.Overloaded => Color.FromRgb(0xFF, 0xA8, 0x1F),
        AgentPulse.Stalled => Color.FromRgb(0xC7, 0xC7, 0xC7),
        AgentPulse.Unstable => Color.FromRgb(0xFF, 0x4A, 0x4F),
        AgentPulse.Finishing => Color.FromRgb(0x52, 0xEB, 0x7A),
        _ => Color.FromRgb(0x57, 0xAD, 0xFF)
    };

    private static string AgentPulseLabel(AgentPulse pulse) => pulse switch
    {
        AgentPulse.Active => "활발",
        AgentPulse.Overloaded => "과부하",
        AgentPulse.Stalled => "정체",
        AgentPulse.Unstable => "불안정",
        AgentPulse.Finishing => "마무리",
        _ => "원활"
    };

    private static void PositionFluid(System.Windows.Shapes.Ellipse blob, double left, double top, double motion, double phase, double opacity)
    {
        Canvas.SetLeft(blob, left + Math.Sin(phase * 0.83) * motion);
        Canvas.SetTop(blob, top + Math.Cos(phase * 0.67) * motion * 0.72);
        blob.Opacity = opacity * (0.88 + Math.Sin(phase * 0.51) * 0.12);
        blob.RenderTransformOrigin = new Point(0.5, 0.5);
        blob.RenderTransform = new ScaleTransform(
            1 + Math.Sin(phase * 0.71) * motion * 0.018,
            1 + Math.Cos(phase * 0.59) * motion * 0.018
        );
    }

    private void ShowCodyStateLabel(object sender, MouseEventArgs e)
    {
        UsageReadout.Visibility = Visibility.Collapsed;
        AgentPulseReadout.Visibility = Visibility.Collapsed;
        CodyStateReadout.Visibility = Visibility.Visible;
    }

    private void HideCodyStateLabel(object sender, MouseEventArgs e)
    {
        CodyStateReadout.Visibility = Visibility.Collapsed;
        if (!AgentPulseIndicator.IsMouseOver) UsageReadout.Visibility = Visibility.Visible;
    }

    private void ShowAgentPulseLabel(object sender, MouseEventArgs e)
    {
        UsageReadout.Visibility = Visibility.Collapsed;
        CodyStateReadout.Visibility = Visibility.Collapsed;
        AgentPulseReadout.Visibility = Visibility.Visible;
    }

    private void HideAgentPulseLabel(object sender, MouseEventArgs e)
    {
        AgentPulseReadout.Visibility = Visibility.Collapsed;
        if (!CodyStateIndicator.IsMouseOver) UsageReadout.Visibility = Visibility.Visible;
    }

    private static string CodyStateLabel(CodyState state) => state switch
    {
        CodyState.Thinking => "생각 중",
        CodyState.Acting => "도구 실행 중",
        CodyState.Waiting => "입력 대기",
        CodyState.Complete => "완료",
        CodyState.Error => "확인 필요",
        _ => "준비됨"
    };

    private void Reposition()
    {
        var layout = anchors.FindAnchor();
        var petVisible = layout is not null;
        if (dismissed)
        {
            if (lastPetVisible && !petVisible) waitingForPetToAppear = true;
            if (waitingForPetToAppear && petVisible) { dismissed = false; waitingForPetToAppear = false; Show(); }
            else { if (IsVisible) Hide(); lastPetVisible = petVisible; return; }
        }
        lastPetVisible = petVisible;
        if (layout is null)
        {
            anchored = false;
            if (!IsVisible) Show();
            return;
        }
        anchored = true;
        var dpi = GetDpiForWindow(hwnd) / 96d;
        var pixelWidth = Width * dpi;
        var pixelHeight = Height * dpi;
        var position = OverlayGeometry.OppositeActivity(layout, pixelWidth, pixelHeight);
        SetWindowPos(hwnd, Topmost ? HWND_TOPMOST : HWND_NOTOPMOST, (int)Math.Round(position.Left), (int)Math.Round(position.Top),
            (int)Math.Round(pixelWidth), (int)Math.Round(pixelHeight), SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    private void OnDrag(object sender, MouseButtonEventArgs e)
    {
        if (CloseButton.IsMouseOver || TimerButton.IsMouseOver || anchored || e.LeftButton != MouseButtonState.Pressed) return;
        DragMove();
        config.ManualLeft = Left; config.ManualTop = Top; SaveConfig();
    }

    private void CloseOverlay(object sender, RoutedEventArgs e)
    {
        HideResetCountdown();
        dismissed = true;
        waitingForPetToAppear = !lastPetVisible;
        Hide();
    }

    private void ToggleResetCountdown(object sender, RoutedEventArgs e)
    {
        if (showsResetCountdown)
        {
            HideResetCountdown();
            return;
        }
        showsResetCountdown = true;
        resetCountdownRefreshRequested = false;
        resetCountdownHideAt = DateTimeOffset.Now.AddSeconds(8);
        TimerButton.Background = TimerActiveBrush;
        TimerButton.ToolTip = "리셋 타이머 숨기기";
        RenderContent(DateTimeOffset.Now);
        resetCountdownTimer.Start();
    }

    private void TickResetCountdown()
    {
        var now = DateTimeOffset.Now;
        if (resetCountdownHideAt is null || now >= resetCountdownHideAt)
        {
            HideResetCountdown();
            return;
        }
        RenderContent(now);
    }

    private void HideResetCountdown()
    {
        resetCountdownTimer.Stop();
        resetCountdownHideAt = null;
        showsResetCountdown = false;
        TimerButton.Background = TimerInactiveBrush;
        TimerButton.ToolTip = "리셋 타이머 보기";
        RenderContent(DateTimeOffset.Now);
    }

    private void RefreshExpiredResetIfNeeded(ResetCountdownDisplay display)
    {
        if (!display.HasExpiredReset || resetCountdownRefreshRequested) return;
        resetCountdownRefreshRequested = true;
        _ = RefreshExpiredResetAsync();
    }

    private async Task RefreshExpiredResetAsync()
    {
        try { await coordinator.ForceRefreshAsync(); }
        catch { }
    }

    private System.Windows.Controls.ContextMenu BuildContextMenu()
    {
        var menu = new System.Windows.Controls.ContextMenu();
        Add("새로고침", async () => { try { await coordinator.ForceRefreshAsync(); } catch { } });
        Add("위치 재탐색", Reposition);
        Add("항상 위에 표시", () => { config.AlwaysOnTop = !config.AlwaysOnTop; Topmost = config.AlwaysOnTop; SaveConfig(); Reposition(); }, true, () => Topmost);
        Add("로그인 시 자동 시작", () => { autoStart.SetEnabled(!autoStart.IsEnabled); config.LaunchAtLogin = autoStart.IsEnabled; SaveConfig(); }, true, () => autoStart.IsEnabled);
        menu.Items.Add(new System.Windows.Controls.Separator());
        Add("진단 정보 복사", () => Clipboard.SetText(Diagnostics()));
        Add("종료", () => Application.Current.Shutdown());
        menu.Opened += (_, _) => { foreach (var item in menu.Items.OfType<System.Windows.Controls.MenuItem>()) if (item.Tag is Func<bool> state) item.IsChecked = state(); };
        return menu;
        void Add(string title, Action action, bool checkable = false, Func<bool>? state = null)
        {
            var item = new System.Windows.Controls.MenuItem { Header = title, IsCheckable = checkable, Tag = state };
            item.Click += (_, _) => action(); menu.Items.Add(item);
        }
    }

    private string Diagnostics() => $"Cody Usage Overlay Windows 0.3.0\nOS: {Environment.OSVersion}\nArchitecture: {RuntimeInformation.OSArchitecture}\nCodex: {locator.Locate() ?? "not found"}\nCandidates:\n{string.Join("\n", locator.Candidates)}\nFreshness: {snapshot.Freshness}\n{anchors.Diagnostics}";
    private static string Percent(int? value) => value is null ? "—" : $"{value}%";
    private Brush BrushFor(int? value) => value is null ? Brushes.White : value <= config.CriticalThreshold ? new SolidColorBrush(Color.FromRgb(255, 89, 89)) : value <= config.WarningThreshold ? new SolidColorBrush(Color.FromRgb(255, 171, 66)) : new SolidColorBrush(Color.FromRgb(125, 164, 255));

    private OverlayConfig LoadConfig()
    {
        try { return File.Exists(configPath) ? JsonSerializer.Deserialize<OverlayConfig>(File.ReadAllBytes(configPath)) ?? new OverlayConfig() : new OverlayConfig(); }
        catch { return new OverlayConfig(); }
    }
    private void SaveConfig() { Directory.CreateDirectory(Path.GetDirectoryName(configPath)!); File.WriteAllBytes(configPath, JsonSerializer.SerializeToUtf8Bytes(config, new JsonSerializerOptions { WriteIndented = true })); }
    private void PlaceManualInitially()
    {
        if (!double.IsNaN(config.ManualLeft) && !double.IsNaN(config.ManualTop)) { Left = config.ManualLeft; Top = config.ManualTop; }
        else { Left = SystemParameters.WorkArea.Right - Width - 24; Top = SystemParameters.WorkArea.Bottom - Height - 24; }
    }
    private async void OnClosed(object? sender, EventArgs e) { correctionTimer.Stop(); resetCountdownTimer.Stop(); codyFluidTimer.Stop(); anchors.Dispose(); await coordinator.DisposeAsync(); }

    private const int GWL_EXSTYLE = -20; private const long WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
    private const uint SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040;
    private static readonly IntPtr HWND_TOPMOST = new(-1), HWND_NOTOPMOST = new(-2);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
}
