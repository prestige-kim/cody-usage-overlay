using Microsoft.Win32;
using System.Diagnostics;

namespace CodyUsageOverlay.Core;

public sealed class CodexExecutableLocator : ICodexExecutableLocator
{
    private readonly OverlayConfig config;
    private readonly List<string> candidates = [];
    public CodexExecutableLocator(OverlayConfig? config = null) => this.config = config ?? new OverlayConfig();
    public IReadOnlyList<string> Candidates => candidates;

    public string? Locate()
    {
        candidates.Clear();
        Add(config.CodexExecutablePath);
        foreach (var process in Process.GetProcessesByName("codex"))
            try { Add(process.MainModule?.FileName); } catch { }
        AddFromAppPathsRegistry();
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ChatGPT", "resources", "codex.exe"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Codex", "resources", "codex.exe"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Codex", "codex.exe"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex", "codex.exe"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Codex", "codex.exe"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin", "codex.exe"));
        Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "bin", "codex.exe"));
        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            Add(Path.Combine(directory.Trim('"'), "codex.exe"));
        return candidates.FirstOrDefault(File.Exists);
    }

    private void Add(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        var full = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path));
        if (!candidates.Contains(full, StringComparer.OrdinalIgnoreCase)) candidates.Add(full);
    }

    private void AddFromAppPathsRegistry()
    {
        foreach (var root in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            using var key = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\codex.exe");
            Add(key?.GetValue(null) as string);
        }
    }
}
