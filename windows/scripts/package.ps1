[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..'))
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$version = ([xml](Get-Content (Join-Path $root 'Directory.Build.props'))).Project.PropertyGroup.Version
$stage = Join-Path $env:TEMP ("CodyUsageOverlay-$version-windows-x64")
$publish = Join-Path $stage 'app'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $publish -Force | Out-Null
dotnet publish (Join-Path $root 'src\CodyUsageOverlay.App\CodyUsageOverlay.App.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $publish
Copy-Item (Join-Path $PSScriptRoot 'install.ps1') $stage
Copy-Item (Join-Path $PSScriptRoot 'uninstall.ps1') $stage
Copy-Item (Join-Path $PSScriptRoot 'doctor.ps1') $stage
$archive = Join-Path $OutputDirectory "CodyUsageOverlay-$version-windows-x64.zip"
if (Test-Path $archive) { Remove-Item $archive -Force }
Compress-Archive (Join-Path $stage '*') $archive -CompressionLevel Optimal
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$archive.sha256", "$hash  $(Split-Path $archive -Leaf)`n", [Text.Encoding]::ASCII)
Write-Host $archive
