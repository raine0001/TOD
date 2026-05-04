param(
    [string]$ConfigPath,
    [string]$OutputDir,
    [string]$UiBaseUrl = 'http://127.0.0.1:8844',
    [double]$DurationHours = 3,
    [int]$WindowOneBoundedRuns = 1,
    [int]$WindowTwoBoundedRuns = 1,
    [switch]$SkipProjectDiscovery,
    [switch]$NoWait,
    [switch]$FailOnStopCondition
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$delegateScript = Join-Path $PSScriptRoot 'Invoke-TODTrainingRunbook6h.ps1'
if (-not (Test-Path -Path $delegateScript)) {
    throw 'Missing runbook delegate script: ' + $delegateScript
}

$delegateArgs = @{
    DurationHours = $DurationHours
    WindowOneBoundedRuns = $WindowOneBoundedRuns
    WindowTwoBoundedRuns = $WindowTwoBoundedRuns
    UiBaseUrl = $UiBaseUrl
}

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $delegateArgs.ConfigPath = $ConfigPath
}
if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    $delegateArgs.OutputDir = $OutputDir
}
if ($SkipProjectDiscovery) {
    $delegateArgs.SkipProjectDiscovery = $true
}
if ($NoWait) {
    $delegateArgs.NoWait = $true
}
if ($FailOnStopCondition) {
    $delegateArgs.FailOnStopCondition = $true
}

& $delegateScript @delegateArgs