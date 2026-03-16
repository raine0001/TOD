param(
    [string]$ConfigPath = "tod/config/llama-runtime.json",
    [string]$ModelPath,
    [int]$Port,
    [switch]$Launch,
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

$cfgAbs = Get-LocalPath -PathValue $ConfigPath
if (-not (Test-Path -Path $cfgAbs)) {
    throw "llama runtime config not found: $cfgAbs"
}

$cfg = Get-Content -Path $cfgAbs -Raw | ConvertFrom-Json
$serverExe = Get-LocalPath -PathValue ([string]$cfg.server_exe)
$effectiveModel = if (-not [string]::IsNullOrWhiteSpace($ModelPath)) { $ModelPath } else { [string]$cfg.default_model_path }
$modelAbs = Get-LocalPath -PathValue $effectiveModel
$bindHost = if ($cfg.PSObject.Properties["host"]) { [string]$cfg.host } else { "127.0.0.1" }
$effectivePort = if ($PSBoundParameters.ContainsKey('Port')) { $Port } elseif ($cfg.PSObject.Properties["port"]) { [int]$cfg.port } else { 8008 }
$contextSize = if ($cfg.PSObject.Properties["context_size"]) { [int]$cfg.context_size } else { 4096 }
$gpuLayers = if ($cfg.PSObject.Properties["gpu_layers"]) { [int]$cfg.gpu_layers } else { 32 }
$threads = if ($cfg.PSObject.Properties["threads"]) { [int]$cfg.threads } else { 8 }
$chatFormat = if ($cfg.PSObject.Properties["chat_format"]) { [string]$cfg.chat_format } else { "chatml" }
$extraArgs = if ($cfg.PSObject.Properties["extra_args"]) { @($cfg.extra_args | ForEach-Object { [string]$_ }) } else { @() }

if (-not (Test-Path -Path $serverExe)) {
    throw "llama-server.exe not found: $serverExe. Run .\\scripts\\Setup-TODLlamaCpp.ps1 first."
}
if (-not (Test-Path -Path $modelAbs)) {
    throw "GGUF model not found: $modelAbs"
}

$argList = @(
    "--host", $bindHost,
    "--port", [string]$effectivePort,
    "-m", $modelAbs,
    "-c", [string]$contextSize,
    "-ngl", [string]$gpuLayers,
    "-t", [string]$threads,
    "--chat-template", $chatFormat
)
$argList += $extraArgs

$payload = [pscustomobject]@{
    ok = $true
    action = "start"
    server_exe = $serverExe
    model = $modelAbs
    endpoint = "http://${bindHost}:${effectivePort}/v1/chat/completions"
    args = @($argList)
    note = if ($Launch) { "Launching llama-server now" } else { "Launch this command in a dedicated terminal or background task." }
}

if ($Launch) {
    & $serverExe @argList
    exit $LASTEXITCODE
}

if ($AsJson) {
    $payload | ConvertTo-Json -Depth 10
}
else {
    $payload
}
