using CodyUsageOverlay.Core;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace CodyUsageOverlay.App;

internal sealed class Win32WindowAnchorProvider : IWindowAnchorProvider
{
    private readonly WinEventDelegate callback;
    private readonly IntPtr hook;
    private IntPtr trackedPet;
    public event Action? Changed;
    public string Diagnostics { get; private set; } = "Window discovery has not run yet.";

    public Win32WindowAnchorProvider()
    {
        callback = (_, _, hwnd, _, _, _, _) => { if (hwnd != IntPtr.Zero && IsCodexWindow(hwnd)) Changed?.Invoke(); };
        hook = SetWinEventHook(EVENT_MIN, EVENT_MAX, IntPtr.Zero, callback, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
    }

    public AnchorLayout? FindAnchor()
    {
        var codexPids = Process.GetProcesses().Where(p => p.ProcessName.Equals("Codex", StringComparison.OrdinalIgnoreCase) || p.ProcessName.Equals("ChatGPT", StringComparison.OrdinalIgnoreCase))
            .Select(p => p.Id).ToHashSet();
        var windows = new List<WindowInfo>();
        EnumWindows((hwnd, _) =>
        {
            if (!IsWindowVisible(hwnd)) return true;
            GetWindowThreadProcessId(hwnd, out var pid);
            if (!codexPids.Contains((int)pid)) return true;
            if (!TryRect(hwnd, out var rect) || rect.Width < 2 || rect.Height < 2) return true;
            windows.Add(new WindowInfo(hwnd, rect, Text(hwnd), ClassName(hwnd)));
            return true;
        }, IntPtr.Zero);

        WindowInfo? pet = trackedPet != IntPtr.Zero ? windows.FirstOrDefault(x => x.Handle == trackedPet) : null;
        pet ??= windows.FirstOrDefault(x => ContainsPetName(x.Title) || ContainsPetName(x.ClassName));
        pet ??= windows.Where(x => x.Rect.Width is >= 70 and <= 400 && x.Rect.Height is >= 100 and <= 500)
            .OrderByDescending(x => x.Rect.Bottom).ThenByDescending(x => x.Rect.Width * x.Rect.Height).FirstOrDefault();
        if (pet is null)
        {
            trackedPet = IntPtr.Zero;
            Diagnostics = $"Codex PIDs: {string.Join(",", codexPids)}\nMatched windows: {windows.Count}\nPet: not found\n" + Describe(windows);
            return null;
        }
        trackedPet = pet.Handle;
        var activities = windows.Where(x => x.Handle != pet.Handle && x.Rect.Width is >= 180 and <= 700 && x.Rect.Height is >= 30 and <= 140 &&
            Math.Abs(x.Rect.CenterX - pet.Rect.CenterX) <= 400 && Math.Abs(x.Rect.CenterY - pet.Rect.CenterY) <= 600).ToList();
        var named = activities.Where(x => x.Title.Contains("activity", StringComparison.OrdinalIgnoreCase) || x.Title.Contains("작업", StringComparison.OrdinalIgnoreCase)).ToList();
        var activity = (named.Count > 0 ? named : activities).OrderBy(x => Math.Abs(x.Rect.CenterX - pet.Rect.CenterX) + Math.Abs(x.Rect.CenterY - pet.Rect.CenterY)).FirstOrDefault();
        var workArea = WorkArea(pet.Rect);
        Diagnostics = $"Codex PIDs: {string.Join(",", codexPids)}\nMatched windows: {windows.Count}\nPet HWND: 0x{pet.Handle.ToInt64():X} {pet.Title} [{pet.ClassName}]\nActivity: {(activity is null ? "fallback" : $"0x{activity.Handle.ToInt64():X}")}\n" + Describe(windows);
        return new AnchorLayout(pet.Rect, activity?.Rect, workArea);
    }

    private static bool ContainsPetName(string value) => value.Contains("Pet Mascot Effect", StringComparison.OrdinalIgnoreCase) || value.Contains("pet mascot", StringComparison.OrdinalIgnoreCase);
    private static bool IsCodexWindow(IntPtr hwnd)
    {
        GetWindowThreadProcessId(hwnd, out var pid);
        try { var name = Process.GetProcessById((int)pid).ProcessName; return name.Equals("Codex", StringComparison.OrdinalIgnoreCase) || name.Equals("ChatGPT", StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }
    private static string Describe(IEnumerable<WindowInfo> windows) => string.Join("\n", windows.Select(x => $"0x{x.Handle.ToInt64():X} {x.Rect.Width}x{x.Rect.Height} '{x.Title}' [{x.ClassName}]"));
    private static string Text(IntPtr hwnd) { var value = new StringBuilder(512); GetWindowText(hwnd, value, value.Capacity); return value.ToString(); }
    private static string ClassName(IntPtr hwnd) { var value = new StringBuilder(256); GetClassName(hwnd, value, value.Capacity); return value.ToString(); }
    private static bool TryRect(IntPtr hwnd, out NativeRect rect)
    {
        if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out var native, Marshal.SizeOf<RECT>()) != 0 && !GetWindowRect(hwnd, out native)) { rect = default; return false; }
        rect = new NativeRect(native.Left, native.Top, native.Right, native.Bottom); return true;
    }
    private static NativeRect WorkArea(NativeRect rect)
    {
        var pointRect = new RECT { Left = rect.Left, Top = rect.Top, Right = rect.Right, Bottom = rect.Bottom };
        var monitor = MonitorFromRect(ref pointRect, MONITOR_DEFAULTTONEAREST);
        var info = new MONITORINFO { Size = Marshal.SizeOf<MONITORINFO>() };
        return GetMonitorInfo(monitor, ref info) ? new NativeRect(info.Work.Left, info.Work.Top, info.Work.Right, info.Work.Bottom) : rect;
    }

    public void Dispose() { if (hook != IntPtr.Zero) UnhookWinEvent(hook); }
    private sealed record WindowInfo(IntPtr Handle, NativeRect Rect, string Title, string ClassName);
    private delegate bool EnumWindowsDelegate(IntPtr hwnd, IntPtr parameter);
    private delegate void WinEventDelegate(IntPtr hook, uint eventType, IntPtr hwnd, int objectId, int childId, uint threadId, uint time);
    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MONITORINFO { public int Size; public RECT Monitor, Work; public uint Flags; }
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9, MONITOR_DEFAULTTONEAREST = 2;
    private const uint EVENT_MIN = 0x0003, EVENT_MAX = 0x800B, WINEVENT_OUTOFCONTEXT = 0, WINEVENT_SKIPOWNPROCESS = 2;
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsDelegate callback, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hwnd, StringBuilder text, int maximum);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT value, int size);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromRect(ref RECT rect, int flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] private static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr module, WinEventDelegate callback, uint process, uint thread, uint flags);
    [DllImport("user32.dll")] private static extern bool UnhookWinEvent(IntPtr hook);
}
