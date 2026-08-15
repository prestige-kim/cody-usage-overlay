using Microsoft.Win32;
using System.Diagnostics;

namespace CodyUsageOverlay.Core;

public sealed class CodexExecutableLocator : ICodexExecutableLocator
{
    private static readonly string[] StorePackagePrefixes = ["OpenAI.Codex_", "OpenAI.ChatGPT_"];
    private readonly OverlayConfig config;
    private readonly Func<IEnumerable<string>> processExecutablePaths;
    private readonly Func<IEnumerable<string>> storePackageRoots;
    private readonly List<string> candidates = [];

    public CodexExecutableLocator(
        OverlayConfig? config = null,
        Func<IEnumerable<string>>? processExecutablePaths = null,
        Func<IEnumerable<string>>? storePackageRoots = null)
    {
        this.config = config ?? new OverlayConfig();
        this.processExecutablePaths = processExecutablePaths ?? ReadDesktopProcessPaths;
        this.storePackageRoots = storePackageRoots ?? ReadStorePackageRoots;
    }

    public IReadOnlyList<string> Candidates => candidates;

    public string? Locate()
    {
        candidates.Clear();
        Add(config.CodexExecutablePath);

        foreach (var processPath in SafeRead(processExecutablePaths))
            AddDesktopExecutableCandidates(processPath);

        AddFromAppPathsRegistry();

        foreach (var packageRoot in SafeRead(storePackageRoots))
            AddStorePackageCandidates(packageRoot);

        // Keep the separately supported Codex CLI as a fallback. Legacy
        // standalone Codex desktop installation paths are intentionally omitted.
        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        Add(Path.Combine(userProfile, ".local", "bin", "codex.exe"));
        Add(Path.Combine(userProfile, ".codex", "bin", "codex.exe"));
        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            Add(Path.Combine(directory.Trim('"'), "codex.exe"));

        return candidates.FirstOrDefault(File.Exists);
    }

    private void AddDesktopExecutableCandidates(string path)
    {
        if (string.Equals(Path.GetFileName(path), "codex.exe", StringComparison.OrdinalIgnoreCase))
        {
            Add(path);
            return;
        }

        if (!string.Equals(Path.GetFileName(path), "ChatGPT.exe", StringComparison.OrdinalIgnoreCase)) return;
        var appDirectory = Path.GetDirectoryName(path);
        if (appDirectory is null) return;
        AddApplicationDirectoryCandidates(appDirectory);
        if (string.Equals(Path.GetFileName(appDirectory), "app", StringComparison.OrdinalIgnoreCase) && Directory.GetParent(appDirectory) is { } packageRoot)
            AddStorePackageCandidates(packageRoot.FullName);
    }

    private void AddStorePackageCandidates(string packageRoot)
    {
        AddApplicationDirectoryCandidates(packageRoot);
        AddApplicationDirectoryCandidates(Path.Combine(packageRoot, "app"));

        // Package layouts are not a public Codex contract. Search the small app
        // package as a final compatibility fallback after probing known layouts.
        try
        {
            foreach (var executable in Directory.EnumerateFiles(packageRoot, "codex.exe", SearchOption.AllDirectories).Take(16))
                Add(executable);
        }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or System.Security.SecurityException) { }
    }

    private void AddApplicationDirectoryCandidates(string directory)
    {
        Add(Path.Combine(directory, "codex.exe"));
        Add(Path.Combine(directory, "resources", "codex.exe"));
        Add(Path.Combine(directory, "resources", "app", "codex.exe"));
        Add(Path.Combine(directory, "resources", "bin", "codex.exe"));
        Add(Path.Combine(directory, "bin", "codex.exe"));
    }

    private void Add(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            var full = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path));
            if (!candidates.Contains(full, StringComparer.OrdinalIgnoreCase)) candidates.Add(full);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or PathTooLongException) { }
    }

    private void AddFromAppPathsRegistry()
    {
        foreach (var root in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            try
            {
                using var key = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\codex.exe");
                Add(key?.GetValue(null) as string);
            }
            catch (System.Security.SecurityException) { }
        }
    }

    private static IEnumerable<string> ReadDesktopProcessPaths()
    {
        foreach (var processName in new[] { "codex", "ChatGPT" })
        {
            foreach (var process in Process.GetProcessesByName(processName))
            {
                using (process)
                {
                    string? path = null;
                    try { path = process.MainModule?.FileName; } catch { }
                    if (!string.IsNullOrWhiteSpace(path)) yield return path;
                }
            }
        }
    }

    private static IEnumerable<string> ReadStorePackageRoots()
    {
        var result = new List<string>();
        const string repositoryPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";
        try
        {
            using var packages = Registry.CurrentUser.OpenSubKey(repositoryPath);
            foreach (var packageName in packages?.GetSubKeyNames() ?? [])
            {
                if (!StorePackagePrefixes.Any(prefix => packageName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))) continue;
                using var package = packages!.OpenSubKey(packageName);
                if (package?.GetValue("PackageRootFolder") is string root && !string.IsNullOrWhiteSpace(root)) result.Add(root);
            }
        }
        catch (Exception error) when (error is System.Security.SecurityException or UnauthorizedAccessException or IOException) { }

        var windowsApps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsApps");
        foreach (var prefix in StorePackagePrefixes)
        {
            IEnumerable<string> roots;
            try { roots = Directory.EnumerateDirectories(windowsApps, prefix + "*").ToArray(); }
            catch (Exception error) when (error is UnauthorizedAccessException or IOException or System.Security.SecurityException) { continue; }
            result.AddRange(roots);
        }
        return result.Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static IEnumerable<string> SafeRead(Func<IEnumerable<string>> provider)
    {
        try { return provider().ToArray(); }
        catch { return []; }
    }
}
