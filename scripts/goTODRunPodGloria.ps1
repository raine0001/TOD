<#
.SYNOPSIS
    One-command launcher for Gloria Cowell spokesperson render on RunPod.

.DESCRIPTION
    Wrapper around Invoke-TODSpokesperson-RunPod.ps1 with the Gloria preset preselected.
    RunPod connection values can be passed directly or sourced from .env by the underlying script.

.EXAMPLE
    .\scripts\goTODRunPodGloria.ps1 -RunPodHost "1.2.3.4" -RunPodKeyPath "C:/Users/dave/.ssh/runpod"

.EXAMPLE
    .\scripts\goTODRunPodGloria.ps1
#>
[CmdletBinding()]
param(
    [string]$RunPodHost = "",
    [string]$RunPodUser = "root",
    [int]$RunPodPort = 22,
    [string]$RunPodKeyPath = "",
    [string]$RemoteRepoPath = "",
    [string]$RemoteSadTalkerPath = "",
    [string]$RemotePythonExe = "",
    [string]$OutputPath = "",
    [switch]$SkipSmoothing,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runner = Join-Path $PSScriptRoot "Invoke-TODSpokesperson-RunPod.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing runner script: $runner"
}

$invokeParams = @{
    Preset = "tod/config/media-presets/gloria-cowell.json"
}

if (-not [string]::IsNullOrWhiteSpace($RunPodHost)) { $invokeParams.RunPodHost = $RunPodHost }
if (-not [string]::IsNullOrWhiteSpace($RunPodUser)) { $invokeParams.RunPodUser = $RunPodUser }
if ($RunPodPort -gt 0) { $invokeParams.RunPodPort = $RunPodPort }
if (-not [string]::IsNullOrWhiteSpace($RunPodKeyPath)) { $invokeParams.RunPodKeyPath = $RunPodKeyPath }
if (-not [string]::IsNullOrWhiteSpace($RemoteRepoPath)) { $invokeParams.RemoteRepoPath = $RemoteRepoPath }
if (-not [string]::IsNullOrWhiteSpace($RemoteSadTalkerPath)) { $invokeParams.RemoteSadTalkerPath = $RemoteSadTalkerPath }
if (-not [string]::IsNullOrWhiteSpace($RemotePythonExe)) { $invokeParams.RemotePythonExe = $RemotePythonExe }
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { $invokeParams.OutputPath = $OutputPath }
if ($SkipSmoothing) { $invokeParams.SkipSmoothing = $true }
if ($DryRun) { $invokeParams.DryRun = $true }

Write-Host "Launching RunPod render for Gloria preset..." -ForegroundColor Green
Write-Host "  Runner: $runner" -ForegroundColor DarkGray
Write-Host "  Preset: tod/config/media-presets/gloria-cowell.json" -ForegroundColor DarkGray

& $runner @invokeParams
$exitCode = if (Test-Path variable:LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
exit $exitCode
