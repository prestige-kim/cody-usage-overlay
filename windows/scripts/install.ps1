[CmdletBinding()]
param([switch]$NoLaunch, [string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$appName = 'CodyUsageOverlay'
$installDir = Join-Path $env:LOCALAPPDATA $appName
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

if (-not $PackageRoot) { $PackageRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { $PWD.Path } }
$payload = Join-Path $PackageRoot 'app'
$downloadRoot = $null
if (-not (Test-Path (Join-Path $payload "$appName.exe"))) {
    Write-Host 'Release payload not found; downloading the latest Windows prerelease...'
    $headers = @{ 'User-Agent' = 'CodyUsageOverlay-Installer' }
    $releases = Invoke-RestMethod 'https://api.github.com/repos/prestige-kim/cody-usage-overlay/releases?per_page=20' -Headers $headers
    $release = $releases | Where-Object { $_.assets.name -match '^CodyUsageOverlay-.*-windows-x64\.zip$' } | Select-Object -First 1
    $asset = $release.assets | Where-Object { $_.name -match '^CodyUsageOverlay-.*-windows-x64\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'A Windows x64 release asset was not found.' }
    $checksumAsset = $release.assets | Where-Object { $_.name -eq "$($asset.name).sha256" } | Select-Object -First 1
    if (-not $checksumAsset) { throw 'The Windows release checksum was not found.' }
    $downloadRoot = Join-Path $env:TEMP ("CodyUsageOverlay-install-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $downloadRoot | Out-Null
    $archive = Join-Path $downloadRoot $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $archive -Headers $headers
    $checksumPath = "$archive.sha256"
    Invoke-WebRequest $checksumAsset.browser_download_url -OutFile $checksumPath -Headers $headers
    $expectedHash = ((Get-Content $checksumPath -Raw) -split '\s+')[0].ToLowerInvariant()
    $actualHash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw 'Downloaded release checksum does not match.' }
    Expand-Archive $archive -DestinationPath $downloadRoot
    $payload = Get-ChildItem $downloadRoot -Recurse -Directory | Where-Object { Test-Path (Join-Path $_.FullName "$appName.exe") } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $payload) { throw 'Downloaded release does not contain CodyUsageOverlay.exe.' }
}

Get-Process $appName -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item (Join-Path $payload '*') $installDir -Recurse -Force
$executable = Join-Path $installDir "$appName.exe"
New-Item -Path $runKey -Force | Out-Null
Set-ItemProperty -Path $runKey -Name $appName -Value ('"' + $executable + '"')
if (-not $NoLaunch) { Start-Process $executable }
if ($downloadRoot) { Remove-Item $downloadRoot -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "Installed and started: $executable"
