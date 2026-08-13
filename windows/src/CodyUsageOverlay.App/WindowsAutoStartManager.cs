using CodyUsageOverlay.Core;
using Microsoft.Win32;

namespace CodyUsageOverlay.App;

internal sealed class WindowsAutoStartManager : IAutoStartManager
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "CodyUsageOverlay";
    public bool IsEnabled { get { using var key = Registry.CurrentUser.OpenSubKey(KeyPath); return key?.GetValue(ValueName) is string; } }
    public void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
        if (enabled) key.SetValue(ValueName, $"\"{Environment.ProcessPath}\""); else key.DeleteValue(ValueName, false);
    }
}
