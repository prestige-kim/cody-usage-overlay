[CmdletBinding()]
param([switch]$Purge)
$ErrorActionPreference = 'Stop'
$appName = 'CodyUsageOverlay'
$installDir = Join-Path $env:LOCALAPPDATA $appName
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Get-Process $appName -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-ItemProperty -Path $runKey -Name $appName -ErrorAction SilentlyContinue
Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
if ($Purge) {
    Remove-Item (Join-Path $env:LOCALAPPDATA 'CodyUsageOverlayData') -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'Cody Usage Overlay was removed.'
