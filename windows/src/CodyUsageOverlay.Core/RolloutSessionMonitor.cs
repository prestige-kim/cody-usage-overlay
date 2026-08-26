using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;

namespace CodyUsageOverlay.Core;

public sealed class RolloutSessionMonitor : ISessionMonitor
{
    private sealed class State
    {
        public long Offset;
        public byte[] Pending = [];
        public bool IsDesktopRoot;
        public string? ThreadId;
        public ContextUsage? Usage;
        public CodyState CodyState = CodyState.Ready;
        public DateTimeOffset CodyStateUpdatedAt = DateTimeOffset.Now;
        public List<AgentPulseEvent> PulseEvents = [];
    }
    private readonly string sessionsRoot;
    private readonly ConcurrentDictionary<string, State> states = new(StringComparer.OrdinalIgnoreCase);
    private FileSystemWatcher? watcher;
    private readonly object refreshLock = new();
    private string? activePath;
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

    public ContextUsage? RefreshActive()
    {
        var path = activePath;
        return path is null ? Refresh() : RefreshPaths([path]);
    }

    private ContextUsage? RefreshPaths(IEnumerable<string> paths)
    {
        lock (refreshLock)
        {
            foreach (var path in paths) ReadAppended(path);
            var latest = states.Where(x => x.Value.IsDesktopRoot && x.Value.Usage is not null)
                .OrderByDescending(x => x.Value.Usage!.UpdatedAt).FirstOrDefault();
            var latestUsage = latest.Value?.Usage;
            if (latestUsage is not null)
            {
                activePath = latest.Key;
                Updated?.Invoke(latestUsage);
                return latestUsage;
            }
            return null;
        }
    }

    private void ReadAppended(string path)
    {
        if (!File.Exists(path)) return;
        var state = states.GetOrAdd(path, _ => new State());
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length < state.Offset)
            {
                state.Offset = 0;
                state.Pending = [];
                state.IsDesktopRoot = false;
                state.Usage = null;
                state.CodyState = CodyState.Ready;
                state.CodyStateUpdatedAt = DateTimeOffset.Now;
                state.PulseEvents.Clear();
            }
            stream.Position = state.Offset;
            using var memory = new MemoryStream();
            stream.CopyTo(memory);
            state.Offset = stream.Length;
            var appended = memory.ToArray();
            var bytes = new byte[state.Pending.Length + appended.Length];
            state.Pending.CopyTo(bytes, 0); appended.CopyTo(bytes, state.Pending.Length);
            var lineStart = 0;
            for (var index = 0; index < bytes.Length; index++)
            {
                if (bytes[index] != (byte)'\n') continue;
                var length = index - lineStart;
                if (length > 0 && bytes[index - 1] == (byte)'\r') length--;
                if (length > 0) ParseLine(Encoding.UTF8.GetString(bytes, lineStart, length), state, File.GetLastWriteTimeUtc(path));
                lineStart = index + 1;
            }
            state.Pending = lineStart < bytes.Length ? bytes[lineStart..] : [];
            UpdatePulse(state, DateTimeOffset.Now);
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
            var eventTime = DateTimeOffset.TryParse(String(root, "timestamp"), out var parsedTimestamp)
                ? parsedTimestamp
                : new DateTimeOffset(updatedAt, TimeSpan.Zero);
            if (type.GetString() == "session_meta" && root.TryGetProperty("payload", out var metadata))
            {
                state.ThreadId = String(metadata, "id") ?? String(metadata, "thread_id");
                var originator = String(metadata, "originator");
                var source = metadata.TryGetProperty("source", out var sourceValue) ? sourceValue : default;
                var sourceName = source.ValueKind == JsonValueKind.String ? source.GetString() : String(source, "type");
                var isSubagent = source.ValueKind == JsonValueKind.Object && source.TryGetProperty("subagent", out _);
                state.IsDesktopRoot = originator == "Codex Desktop" && sourceName == "vscode" && !isSubagent;
            }
            if (!state.IsDesktopRoot || !root.TryGetProperty("payload", out var payload)) return;
            var pulseEvent = ParseAgentPulseEvent(type.GetString(), payload, eventTime);
            if (pulseEvent is not null) state.PulseEvents.Add(pulseEvent);
            var nextState = ParseCodyState(type.GetString(), payload, state.CodyState);
            if (nextState is not null && nextState != state.CodyState)
            {
                state.CodyState = nextState.Value;
                state.CodyStateUpdatedAt = eventTime;
                if (state.Usage is not null)
                    state.Usage = state.Usage with
                    {
                        CodyState = state.CodyState,
                        CodyStateUpdatedAt = state.CodyStateUpdatedAt,
                        UpdatedAt = state.CodyStateUpdatedAt
                    };
            }
            if (type.GetString() == "event_msg" && String(payload, "type") == "token_count")
            {
                var info = payload.TryGetProperty("info", out var nestedInfo) ? nestedInfo : payload;
                var hasUsage = info.TryGetProperty("last_token_usage", out var usage);
                var total = hasUsage ? Integer(usage, "total_tokens") : null;
                var window = Integer(info, "model_context_window");
                if (total is not null && window is not null && state.ThreadId is not null)
                    state.Usage = new ContextUsage(
                        state.ThreadId,
                        total.Value,
                        window.Value,
                        eventTime,
                        CodyState: state.CodyState,
                        CodyStateUpdatedAt: state.CodyStateUpdatedAt);
            }
            UpdatePulse(state, eventTime);
        }
        catch (JsonException) { }
    }

    private static void UpdatePulse(State state, DateTimeOffset now)
    {
        state.PulseEvents.RemoveAll(x => x.Timestamp < now.AddMinutes(-10));
        if (state.Usage is null) return;
        var evaluation = AgentPulseAnalyzer.Evaluate(state.PulseEvents, state.CodyState, state.Usage.RemainingPercent, now);
        if (evaluation.Pulse == state.Usage.AgentPulse && evaluation.Reason == state.Usage.AgentPulseReason) return;
        state.Usage = state.Usage with
        {
            AgentPulse = evaluation.Pulse,
            AgentPulseReason = evaluation.Reason,
            UpdatedAt = now
        };
    }

    private static AgentPulseEvent? ParseAgentPulseEvent(string? recordType, JsonElement payload, DateTimeOffset timestamp)
    {
        var payloadType = String(payload, "type");
        if (recordType == "response_item")
        {
            if (payloadType is "custom_tool_call" or "function_call")
            {
                var name = String(payload, "name")?.ToLowerInvariant() ?? "";
                var kind = name.Contains("request_user_input") || name.Contains("request_permissions")
                    ? AgentPulseEventKind.Waiting : AgentPulseEventKind.ToolCall;
                return new AgentPulseEvent(kind, timestamp);
            }
            if (payloadType is "custom_tool_call_output" or "function_call_output")
                return new AgentPulseEvent(AgentPulseEventKind.ToolResult, timestamp);
            return null;
        }
        if (recordType != "event_msg") return null;
        if (payloadType == "task_started") return new AgentPulseEvent(AgentPulseEventKind.TaskStarted, timestamp);
        if (payloadType == "task_complete") return new AgentPulseEvent(AgentPulseEventKind.Complete, timestamp);
        if (payloadType is "error" or "turn_aborted" or "task_failed") return new AgentPulseEvent(AgentPulseEventKind.Error, timestamp);
        if (payloadType == "item_completed" && payload.TryGetProperty("item", out var item))
        {
            if (String(item, "status")?.Equals("failed", StringComparison.OrdinalIgnoreCase) == true)
                return new AgentPulseEvent(AgentPulseEventKind.Error, timestamp);
            var itemType = String(item, "type")?.ToLowerInvariant();
            if (itemType == "reasoning") return new AgentPulseEvent(AgentPulseEventKind.Reasoning, timestamp);
            if (itemType is "commandexecution" or "filechange" or "mcptoolcall" or "dynamictoolcall" or "extension" or "imageview")
                return new AgentPulseEvent(AgentPulseEventKind.ToolResult, timestamp);
        }
        if (payloadType == "token_count")
        {
            var info = payload.TryGetProperty("info", out var nestedInfo) ? nestedInfo : payload;
            if (info.TryGetProperty("last_token_usage", out var usage))
            {
                var total = Integer(usage, "total_tokens");
                var window = Integer(info, "model_context_window");
                if (total is not null && window is not null)
                    return new AgentPulseEvent(AgentPulseEventKind.TokenSample, timestamp, total, window);
            }
        }
        return null;
    }

    private static CodyState? ParseCodyState(string? recordType, JsonElement payload, CodyState current)
    {
        var payloadType = String(payload, "type");
        if (recordType == "response_item")
        {
            if (payloadType is "custom_tool_call" or "function_call")
            {
                var name = String(payload, "name")?.ToLowerInvariant() ?? "";
                return name.Contains("request_user_input") || name.Contains("request_permissions") ? CodyState.Waiting : CodyState.Acting;
            }
            if (payloadType is "custom_tool_call_output" or "function_call_output")
                return current == CodyState.Waiting ? CodyState.Thinking : CodyState.Acting;
            return null;
        }
        if (recordType != "event_msg") return null;
        if (payloadType == "task_started") return CodyState.Thinking;
        if (payloadType == "task_complete") return CodyState.Complete;
        if (payloadType is "error" or "turn_aborted" or "task_failed") return CodyState.Error;
        if (payloadType != "item_completed" || !payload.TryGetProperty("item", out var item)) return null;
        if (String(item, "status")?.Equals("failed", StringComparison.OrdinalIgnoreCase) == true) return CodyState.Error;
        var itemType = String(item, "type")?.ToLowerInvariant();
        if (itemType == "reasoning") return CodyState.Thinking;
        return itemType is "commandexecution" or "filechange" or "mcptoolcall" or "dynamictoolcall" or "extension" or "imageview"
            ? CodyState.Acting
            : null;
    }

    private static string? String(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) ? value.GetString() : null;
    private static int? Integer(JsonElement element, string name) => element.TryGetProperty(name, out var value) && value.TryGetInt32(out var number) ? number : null;
    public void Dispose() { if (watcher is not null) watcher.EnableRaisingEvents = false; watcher?.Dispose(); }
}
