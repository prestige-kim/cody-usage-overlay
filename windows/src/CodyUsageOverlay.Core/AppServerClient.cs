using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;

namespace CodyUsageOverlay.Core;

public sealed class AppServerClient(ICodexExecutableLocator locator) : IAppServerClient
{
    private readonly SemaphoreSlim lifecycle = new(1, 1);
    private readonly ConcurrentDictionary<int, TaskCompletionSource<byte[]>> pending = new();
    private Process? process;
    private StreamWriter? input;
    private int nextId;
    private bool initialized;
    public event Action<string, byte[]>? Notification;

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        await lifecycle.WaitAsync(cancellationToken);
        try
        {
            if (initialized && process is { HasExited: false }) return;
            await StopInternalAsync();
            var executable = locator.Locate() ?? throw new FileNotFoundException("Codex 실행 파일을 찾지 못했습니다.");
            var newProcess = new Process
            {
                StartInfo = new ProcessStartInfo(executable, "app-server --stdio")
                {
                    UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true,
                    RedirectStandardError = true, CreateNoWindow = true, WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                }, EnableRaisingEvents = true
            };
            newProcess.Exited += (_, _) => FailPending(new IOException("Codex app-server가 종료되었습니다."));
            if (!newProcess.Start()) throw new IOException("Codex app-server를 시작하지 못했습니다.");
            process = newProcess;
            input = newProcess.StandardInput;
            _ = Task.Run(() => ReadLoopAsync(newProcess.StandardOutput, CancellationToken.None));
            _ = Task.Run(async () => { while (await newProcess.StandardError.ReadLineAsync() is not null) { } });
            await CallAsync("initialize", new
            {
                clientInfo = new { name = "cody-usage-overlay-windows", title = "Cody Usage Overlay", version = "0.2.0" },
                capabilities = new { experimentalApi = true }
            }, true, cancellationToken);
            await WriteAsync(new { method = "initialized", @params = new { } }, cancellationToken);
            initialized = true;
        }
        finally { lifecycle.Release(); }
    }

    public async Task<byte[]> ReadRateLimitsAsync(CancellationToken cancellationToken = default)
    {
        await StartAsync(cancellationToken);
        return await CallAsync("account/rateLimits/read", new { }, false, cancellationToken);
    }

    private async Task<byte[]> CallAsync(string method, object parameters, bool allowUninitialized, CancellationToken cancellationToken)
    {
        if (!allowUninitialized && !initialized) throw new IOException("app-server가 초기화되지 않았습니다.");
        var id = Interlocked.Increment(ref nextId);
        var completion = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        pending[id] = completion;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        using var registration = timeout.Token.Register(() => completion.TrySetCanceled(timeout.Token));
        try
        {
            await WriteAsync(new { id, method, @params = parameters }, cancellationToken);
            return await completion.Task;
        }
        finally { pending.TryRemove(id, out _); }
    }

    private async Task WriteAsync(object message, CancellationToken cancellationToken)
    {
        var writer = input ?? throw new IOException("app-server 입력 스트림이 없습니다.");
        await writer.WriteLineAsync(JsonSerializer.Serialize(message).AsMemory(), cancellationToken);
        await writer.FlushAsync(cancellationToken);
    }

    private async Task ReadLoopAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        try
        {
            while (await reader.ReadLineAsync(cancellationToken) is { } line)
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.TryGetProperty("id", out var idElement) && idElement.TryGetInt32(out var id) && pending.TryRemove(id, out var completion))
                {
                    if (root.TryGetProperty("error", out var error)) completion.TrySetException(new IOException(error.ToString()));
                    else if (root.TryGetProperty("result", out var result)) completion.TrySetResult(JsonSerializer.SerializeToUtf8Bytes(result));
                    else completion.TrySetException(new InvalidDataException("app-server 응답에 result가 없습니다."));
                }
                else if (root.TryGetProperty("method", out var method))
                {
                    var payload = root.TryGetProperty("params", out var parameters) ? JsonSerializer.SerializeToUtf8Bytes(parameters) : "{}"u8.ToArray();
                    Notification?.Invoke(method.GetString() ?? "", payload);
                }
            }
        }
        catch (Exception error) { FailPending(error); }
    }

    private void FailPending(Exception error)
    {
        initialized = false;
        foreach (var item in pending.ToArray()) if (pending.TryRemove(item.Key, out var completion)) completion.TrySetException(error);
    }

    private Task StopInternalAsync()
    {
        initialized = false;
        input?.Dispose(); input = null;
        if (process is { HasExited: false }) { process.Kill(true); process.WaitForExit(2000); }
        process?.Dispose(); process = null;
        FailPending(new IOException("app-server가 중지되었습니다."));
        return Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        await lifecycle.WaitAsync();
        try { await StopInternalAsync(); }
        finally { lifecycle.Release(); lifecycle.Dispose(); }
    }
}
