using System.Collections.Concurrent;
using System.Text.Json;

namespace CodyUsageOverlay.Core;

public sealed class RolloutSessionMonitor : ISessionMonitor
{
    private sealed class State { public long Offset; public bool IsDesktopRoot; public string? ThreadId; public ContextUsage? Usage; }
    private readonly string sessionsRoot;
    private readonly ConcurrentDictionary<string, State> states = new(StringComparer.OrdinalIgnoreCase);
    private FileSystemWatcher? watcher;
    private readonly object refreshLock = new();
    public event Action<ContextUsage>? Updated;

    public RolloutSessionMonitor(string? sessionsRoot = null) => this.sessionsRoot = sessionsRoot ??
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "sessions");

    public void Start()
    {
        Refresh();
        if (!Directory.Exists(sessionsRoot)) return;
        watcher = new FileSystemWatcher(sessionsRoot, "*.jsonl") { IncludeSubdirectories = true, NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size };
        watcher.Changed += OnChanged; watcher.Created += OnChanged; watcher.Renamed += (_, e) => RefreshPaths([e.FullPath]);
        watcher.EnableRaisingEvents = true;
    }

    private void OnChanged(object sender, FileSystemEventArgs e) => RefreshPaths([e.FullPath]);

    public ContextUsage? Refresh()
    {
        if (!Directory.Exists(sessionsRoot)) return null;
        return RefreshPaths(Directory.EnumerateFiles(sessionsRoot, "*.jsonl", SearchOption.AllDirectories));
    }

    private ContextUsage? RefreshPaths(IEnumerable<string> paths)
    {
        lock (refreshLock)
        {
            foreach (var path in paths) ReadAppended(path);
            var latest = states.Values.Where(x => x.IsDesktopRoot && x.Usage is not null).Select(x => x.Usage!)
                .OrderByDescending(x => x.UpdatedAt).FirstOrDefault();
            if (latest is not null) Updated?.Invoke(latest);
            return latest;
        }
    }

    private void ReadAppended(string path)
    {
        if (!File.Exists(path)) return;
        var state = states.GetOrAdd(path, _ => new State());
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length < state.Offset) { state.Offset = 0; state.IsDesktopRoot = false; state.Usage = null; }
            stream.Position = state.Offset;
            using var reader = new StreamReader(stream);
            while (reader.ReadLine() is { } line) ParseLine(line, state, File.GetLastWriteTimeUtc(path));
            state.Offset = stream.Position;
        }
        catch (IOException) { }
    }

    private static void ParseLine(string line, State state, DateTime updatedAt)
    {
        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var type)) return;
            if (type.GetString() == "session_meta" && root.TryGetProperty("payload", out var metadata))
            {
                state.ThreadId = String(metadata, "id") ?? String(metadata, "thread_id");
                var originator = String(metadata, "originator");
                var source = metadata.TryGetProperty("source", out var sourceValue) ? sourceValue : default;
                var sourceName = source.ValueKind == JsonValueKind.String ? source.GetString() : String(source, "type");
                var isSubagent = source.ValueKind == JsonValueKind.Object && source.TryGetProperty("subagent", out _);
                state.IsDesktopRoot = originator == "Codex Desktop" && sourceName == "vscode" && !isSubagent;
            }
            if (!state.IsDesktopRoot || type.GetString() != "event_msg" || !root.TryGetProperty("payload", out var payload) ||
                String(payload, "type") != "token_count" || !payload.TryGetProperty("last_token_usage", out var usage)) return;
            var total = Integer(usage, "total_tokens");
            var window = Integer(payload, "model_context_window");
            if (total is null || window is null || state.ThreadId is null) return;
            state.Usage = new ContextUsage(state.ThreadId, total.Value, window.Value, new DateTimeOffset(updatedAt, TimeSpan.Zero));
        }
        catch (JsonException) { }
    }

    private static string? String(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) ? value.GetString() : null;
    private static int? Integer(JsonElement element, string name) => element.TryGetProperty(name, out var value) && value.TryGetInt32(out var number) ? number : null;
    public void Dispose() { if (watcher is not null) watcher.EnableRaisingEvents = false; watcher?.Dispose(); }
}
