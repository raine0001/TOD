param(
    [string]$SoakRoot = "shared_state/conversation_eval/soak",
    [string]$RunId = "latest",
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Convert-ToScalarDouble {
    param($Value)

    if ($null -eq $Value) { return 0.0 }
    while ($Value -is [System.Array]) {
        if (@($Value).Count -eq 0) { return 0.0 }
        $Value = $Value[0]
    }
    return [double]$Value
}

function Get-PerCycleSlope {
    param([object[]]$Y)
    if ($null -eq $Y -or $Y.Count -lt 2) { return 0.0 }
    $first = Convert-ToScalarDouble -Value $Y[0]
    $last = Convert-ToScalarDouble -Value $Y[-1]
    $steps = [double]([Math]::Max(1, ($Y.Count - 1)))
    return [math]::Round((($last - $first) / $steps), 6)
}

function Get-RunDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id
    )

    if ($Id -ne "latest") {
        $explicit = Join-Path $Root $Id
        if (-not (Test-Path -Path $explicit)) {
            throw "Soak run directory not found: $explicit"
        }
        return $explicit
    }

    $dirs = @(Get-ChildItem -Path $Root -Directory | Sort-Object Name -Descending)
    if (@($dirs).Count -eq 0) {
        throw "No soak runs found under $Root"
    }
    return $dirs[0].FullName
}

$soakRootAbs = Resolve-LocalPath -PathValue $SoakRoot
if (-not (Test-Path -Path $soakRootAbs)) {
    throw "Soak root not found: $soakRootAbs"
}

$runDir = Get-RunDirectory -Root $soakRootAbs -Id $RunId
$snapPaths = @(Get-ChildItem -Path $runDir -Filter "conversation_coach.cycle.*.json" | Sort-Object Name)
if (@($snapPaths).Count -eq 0) {
    throw "No cycle snapshots found in $runDir"
}

$snapshots = @($snapPaths | ForEach-Object { Get-Content -Path $_.FullName -Raw | ConvertFrom-Json })

$prSeries = @($snapshots | ForEach-Object { Convert-ToScalarDouble -Value $_.summary.pr_overall })
$deltaSeries = @($snapshots | ForEach-Object { Convert-ToScalarDouble -Value $_.summary.ab_delta_overall })
$failSeries = @($snapshots | ForEach-Object { Convert-ToScalarDouble -Value $_.summary.tightened_failures })
$utilitySeries = @($snapshots | ForEach-Object {
        if ($_.summary.PSObject.Properties['pr_developer_utility']) {
            Convert-ToScalarDouble -Value $_.summary.pr_developer_utility
        }
        else {
            0.0
        }
    })

$prSlope = Get-PerCycleSlope -Y $prSeries
$deltaSlope = Get-PerCycleSlope -Y $deltaSeries
$failSlope = Get-PerCycleSlope -Y $failSeries
$utilitySlope = Get-PerCycleSlope -Y $utilitySeries

$prDrift = [math]::Round(($prSeries[-1] - $prSeries[0]), 4)
$deltaDrift = [math]::Round(($deltaSeries[-1] - $deltaSeries[0]), 4)
$failDrift = [math]::Round(($failSeries[-1] - $failSeries[0]), 4)
$utilityDrift = [math]::Round(($utilitySeries[-1] - $utilitySeries[0]), 4)

$health = "stable"
if ($prDrift -gt 0.01 -and $failDrift -lt 0) {
    $health = "improving"
}
elseif ($prDrift -lt -0.01 -or $failDrift -gt 0) {
    $health = "regressing"
}
if ($utilityDrift -lt -0.01) {
    $health = "regressing"
}

$recommendations = @()
if ($health -eq "improving") {
    $recommendations += "Continue tightened policy and expand live drill coverage."
}
if ($health -eq "stable") {
    $recommendations += "Increase scenario pressure on low_relevance and missing_safety_boundary to force movement."
}
if ($health -eq "regressing") {
    $recommendations += "Pause policy changes and replay top failure tags before next baseline update."
}
if ($failSeries[-1] -gt 0) {
    $recommendations += "Prioritize targeted replay until tightened_failures trends toward zero."
}
if ($utilitySeries[-1] -lt 0.70) {
    $recommendations += "Developer utility is below threshold; focus on concise, directly actionable guidance."
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-coach-trend-v1"
    run_dir = $runDir
    cycles = @($snapshots).Count
    trend = [pscustomobject]@{
        health = $health
        pr_overall = [pscustomobject]@{
            first = [math]::Round($prSeries[0], 4)
            last = [math]::Round($prSeries[-1], 4)
            drift = $prDrift
            slope = $prSlope
        }
        ab_delta_overall = [pscustomobject]@{
            first = [math]::Round($deltaSeries[0], 4)
            last = [math]::Round($deltaSeries[-1], 4)
            drift = $deltaDrift
            slope = $deltaSlope
        }
        tightened_failures = [pscustomobject]@{
            first = [int]$failSeries[0]
            last = [int]$failSeries[-1]
            drift = $failDrift
            slope = $failSlope
        }
        developer_utility = [pscustomobject]@{
            first = [math]::Round($utilitySeries[0], 4)
            last = [math]::Round($utilitySeries[-1], 4)
            drift = $utilityDrift
            slope = $utilitySlope
        }
    }
    recommended_actions = @($recommendations)
}

$trendPath = Join-Path $runDir "conversation_coach.trend.latest.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -Path $trendPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}