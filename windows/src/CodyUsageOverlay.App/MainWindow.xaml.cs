using CodyUsageOverlay.Core;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
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
    private UsageSnapshot snapshot = new(LastUpdatedAt: DateTimeOffset.Now);
    private IntPtr hwnd;
    private bool anchored;
    private bool dismissed;
    private bool waitingForPetToAppear;
    private bool lastPetVisible;

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
        LimitsText.Text = value.FiveHourRemainingPercent is int five ? $"5h {five}% · Week {Percent(value.WeeklyRemainingPercent)}" : $"Week {Percent(value.WeeklyRemainingPercent)}";
        var suffix = value.Freshness == Freshness.Fresh ? "" : value.Freshness == Freshness.Incompatible ? "  호환성 확인 필요" : "  지연됨";
        ContextText.Text = $"Context {Percent(value.ContextRemainingPercent)}{suffix}";
        var limitValues = new[] { value.FiveHourRemainingPercent, value.WeeklyRemainingPercent }.Where(x => x is not null).Select(x => x!.Value).ToArray();
        LimitsText.Foreground = BrushFor(limitValues.Length == 0 ? null : limitValues.Min());
        ToolTip = $"마지막 갱신: {value.LastUpdatedAt?.LocalDateTime:T}\n태스크: {value.ActiveThreadId ?? "확인 중"}";
    }

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
        if (e.OriginalSource == CloseButton || anchored || e.LeftButton != MouseButtonState.Pressed) return;
        DragMove();
        config.ManualLeft = Left; config.ManualTop = Top; SaveConfig();
    }

    private void CloseOverlay(object sender, RoutedEventArgs e)
    {
        dismissed = true;
        waitingForPetToAppear = !lastPetVisible;
        Hide();
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

    private string Diagnostics() => $"Cody Usage Overlay Windows 0.2.1\nOS: {Environment.OSVersion}\nArchitecture: {RuntimeInformation.OSArchitecture}\nCodex: {locator.Locate() ?? "not found"}\nCandidates:\n{string.Join("\n", locator.Candidates)}\nFreshness: {snapshot.Freshness}\n{anchors.Diagnostics}";
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
    private async void OnClosed(object? sender, EventArgs e) { correctionTimer.Stop(); anchors.Dispose(); await coordinator.DisposeAsync(); }

    private const int GWL_EXSTYLE = -20; private const long WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
    private const uint SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040;
    private static readonly IntPtr HWND_TOPMOST = new(-1), HWND_NOTOPMOST = new(-2);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
}
