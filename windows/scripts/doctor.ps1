[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class CodyWindowProbe {
  public delegate bool Callback(IntPtr h, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback c, IntPtr p);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rect r);
  public static string[] Enumerate(int[] processIds) {
    var ids = new HashSet<int>(processIds); var rows = new List<string>();
    EnumWindows((h,p) => { uint id; GetWindowThreadProcessId(h,out id); Rect r;
      if (!ids.Contains((int)id) || !IsWindowVisible(h) || !GetWindowRect(h,out r)) return true;
      var title=new StringBuilder(512); var cls=new StringBuilder(256); GetWindowText(h,title,512); GetClassName(h,cls,256);
      rows.Add(String.Format("0x{0:X} pid={1} rect={2},{3},{4},{5} title='{6}' class='{7}'",h.ToInt64(),id,r.Left,r.Top,r.Right,r.Bottom,title,cls)); return true;
    },IntPtr.Zero); return rows.ToArray();
  }
}
'@
$homeDir = [Environment]::GetFolderPath('UserProfile')
$candidateList = [Collections.Generic.List[string]]::new()
function Add-CodexCandidate([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)) } catch { return }
    if (-not $candidateList.Contains($fullPath)) { $candidateList.Add($fullPath) }
}
function Add-AppDirectoryCandidates([string]$Directory) {
    if ([string]::IsNullOrWhiteSpace($Directory)) { return }
    Add-CodexCandidate (Join-Path $Directory 'codex.exe')
    Add-CodexCandidate (Join-Path $Directory 'resources\codex.exe')
    Add-CodexCandidate (Join-Path $Directory 'resources\app\codex.exe')
    Add-CodexCandidate (Join-Path $Directory 'resources\bin\codex.exe')
    Add-CodexCandidate (Join-Path $Directory 'bin\codex.exe')
}
function Add-StorePackageCandidates([string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Root)) { return }
    Add-AppDirectoryCandidates $Root
    Add-AppDirectoryCandidates (Join-Path $Root 'app')
    Get-ChildItem $Root -Filter codex.exe -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 16 -ExpandProperty FullName | ForEach-Object { Add-CodexCandidate $_ }
}

$desktopProcesses = @(Get-Process Codex,ChatGPT -ErrorAction SilentlyContinue)
$processPaths = @($desktopProcesses | ForEach-Object { try { $_.Path } catch {} } | Where-Object { $_ })
try {
    $processPaths += @(Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object { $_.Name -in @('codex.exe', 'ChatGPT.exe') } |
        Select-Object -ExpandProperty ExecutablePath | Where-Object { $_ })
} catch {}
$processPaths = @($processPaths | Select-Object -Unique)
foreach ($processPath in $processPaths) {
    if ([IO.Path]::GetFileName($processPath) -ieq 'codex.exe') { Add-CodexCandidate $processPath; continue }
    if ([IO.Path]::GetFileName($processPath) -ine 'ChatGPT.exe') { continue }
    $appDirectory = Split-Path $processPath -Parent
    Add-AppDirectoryCandidates $appDirectory
    if ((Split-Path $appDirectory -Leaf) -ieq 'app') { Add-StorePackageCandidates (Split-Path $appDirectory -Parent) }
}

$storePackages = @()
foreach ($packageName in @('OpenAI.Codex', 'OpenAI.ChatGPT')) {
    try { $storePackages += @(Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue) } catch {}
}
foreach ($package in $storePackages) { Add-StorePackageCandidates $package.InstallLocation }

Add-CodexCandidate (Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
@(
    "$homeDir\.local\bin\codex.exe", "$homeDir\.codex\bin\codex.exe"
) | ForEach-Object { Add-CodexCandidate $_ }
$candidates = @($candidateList)
$foundCodex = $candidates | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
$codex = if ($foundCodex) { [string]$foundCodex } else { $null }
$sessions = Join-Path $homeDir '.codex\sessions'
$rollout = if (Test-Path $sessions) { Get-ChildItem $sessions -Filter '*.jsonl' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1 -ExpandProperty FullName }
$processes = $desktopProcesses
$windowRows = if ($processes.Count) { [CodyWindowProbe]::Enumerate([int[]]@($processes.Id)) } else { @() }
$result = [ordered]@{
    ok = [bool]$codex
    os = [Environment]::OSVersion.VersionString
    architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    codex = $codex
    searchedCodexPaths = @($candidates)
    desktopProcessPaths = @($processPaths)
    storePackages = @($storePackages | ForEach-Object { @{ name = $_.Name; version = $_.Version.ToString(); installLocation = $_.InstallLocation } })
    codexVersion = $null
    appServer = $false
    rateLimitFields = @()
    rollout = $rollout
    codexProcesses = @($processes | ForEach-Object { @{ id = $_.Id; name = $_.ProcessName; mainWindow = ('0x{0:X}' -f $_.MainWindowHandle.ToInt64()) } })
    windows = @($windowRows)
    autoStart = [bool](Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name CodyUsageOverlay -ErrorAction SilentlyContinue)
}
if ($codex) {
    try { $result.codexVersion = (& $codex --version 2>&1 | Select-Object -First 1) -join '' } catch {}
    $psi = [Diagnostics.ProcessStartInfo]::new($codex, 'app-server --stdio')
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $server = [Diagnostics.Process]::new(); $server.StartInfo = $psi
    try {
        [void]$server.Start()
        $server.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"cody-usage-overlay-doctor","title":"Cody Usage Overlay Doctor","version":"0.2.2"},"capabilities":{"experimentalApi":true}}}')
        $server.StandardInput.Flush(); $initialize = $server.StandardOutput.ReadLineAsync()
        if ($initialize.Wait(15000) -and $initialize.Result) {
            $server.StandardInput.WriteLine('{"method":"initialized","params":{}}')
            $server.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read","params":{}}'); $server.StandardInput.Flush()
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while ([DateTime]::UtcNow -lt $deadline) {
                $lineTask = $server.StandardOutput.ReadLineAsync()
                $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
                if (-not $lineTask.Wait($remaining)) { break }
                if (-not $lineTask.Result) { break }
                $message = $lineTask.Result | ConvertFrom-Json
                if ($message.id -eq 2 -and $message.result) {
                    $result.appServer = $true
                    $result.rateLimitFields = @($message.result.PSObject.Properties.Name)
                    break
                }
            }
        }
    } catch { $result.appServerError = $_.Exception.Message }
    finally { if ($server -and -not $server.HasExited) { $server.Kill($true) }; if ($server) { $server.Dispose() } }
}
$result.ok = $result.ok -and $result.appServer -and [bool]$result.rollout
$result | ConvertTo-Json -Depth 8
if (-not $result.ok) { exit 1 }
