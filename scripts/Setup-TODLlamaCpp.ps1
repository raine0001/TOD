param(
    [string]$ConfigPath = "tod/config/llama-runtime.json",
    [switch]$Force,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Initialize-ParentDir {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$cfgAbs = Get-LocalPath -PathValue $ConfigPath
if (-not (Test-Path -Path $cfgAbs)) {
    throw "llama runtime config not found: $cfgAbs"
}

$cfg = Get-Content -Path $cfgAbs -Raw | ConvertFrom-Json
$installRoot = Get-LocalPath -PathValue ([string]$cfg.install_root)
$serverExe = Get-LocalPath -PathValue ([string]$cfg.server_exe)
$releaseApi = [string]$cfg.release_api
$assetPatterns = @($cfg.asset_patterns | ForEach-Object { [string]$_ })

if ((Test-Path -Path $serverExe) -and -not $Force) {
    $payload = [pscustomobject]@{
        ok = $true
        action = "setup"
        changed = $false
        server_exe = $serverExe
        note = "llama-server.exe already present"
    }
    if ($AsJson) { $payload | ConvertTo-Json -Depth 8 } else { $payload }
    return
}

Initialize-ParentDir -FilePath (Join-Path $installRoot "placeholder.txt")

$release = Invoke-RestMethod -Uri $releaseApi -Headers @{ "User-Agent" = "TOD-llama-setup" } -TimeoutSec 30
if ($null -eq $release -or -not $release.assets) {
    throw "Unable to read llama.cpp release assets from $releaseApi"
}

$selectedAsset = $null
foreach ($pattern in $assetPatterns) {
    $selectedAsset = @($release.assets | Where-Object { [string]$_.name -like "*$pattern*" } | Select-Object -First 1)
    if ($selectedAsset.Count -gt 0) {
        $selectedAsset = $selectedAsset[0]
        break
    }
}

if ($null -eq $selectedAsset) {
    $assetNames = @($release.assets | ForEach-Object { [string]$_.name }) -join ", "
    throw "No matching Windows llama.cpp asset found. Available assets: $assetNames"
}

$zipPath = Join-Path $installRoot ([string]$selectedAsset.name)
Invoke-WebRequest -Uri ([string]$selectedAsset.browser_download_url) -OutFile $zipPath -UseBasicParsing -TimeoutSec 0

if (Test-Path -Path $installRoot) {
    Get-ChildItem -Path $installRoot -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne [System.IO.Path]::GetFileName($zipPath) } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Expand-Archive -Path $zipPath -DestinationPath $installRoot -Force

$llamaServer = Get-ChildItem -Path $installRoot -Recurse -Filter "llama-server.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $llamaServer) {
    throw "llama-server.exe not found after extraction to $installRoot"
}

$payload = [pscustomobject]@{
    ok = $true
    action = "setup"
    changed = $true
    asset = [string]$selectedAsset.name
    server_exe = [string]$llamaServer.FullName
    install_root = $installRoot
    note = "Download complete. Place a GGUF model at the configured model path before starting the server."
}
if ($AsJson) { $payload | ConvertTo-Json -Depth 8 } else { $payload }
