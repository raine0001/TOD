param(
    [int]$IntervalSeconds = 180,
    [int]$MaxIterations = 0,
    [int]$PreferredPort = 8844,
    [int]$MaxPortSearch = 30,
    [int]$Top = 10,
    [switch]$VerboseOutput,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($IntervalSeconds -lt 1) {
    throw "IntervalSeconds must be >= 1"
}

if ($MaxIterations -lt 0) {
    throw "MaxIterations must be >= 0"
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$smokeScript = Join-Path $PSScriptRoot "Invoke-TODSmoke.ps1"
if (-not (Test-Path -Path $smokeScript)) {
    throw "Missing smoke script: $smokeScript"
}

function ConvertTo-ComparableJson {
    param([Parameter(Mandatory = $true)]$Object)
    return ($Object | ConvertTo-Json -Depth 20 -Compress)
}

function Get-SmokeSnapshot {
    param(
        [int]$Preferred,
        [int]$Search,
        [int]$TopValue,
        [switch]$FailFast
    )

    $args = @{
        PreferredPort = $Preferred
        MaxPortSearch = $Search
        Top = $TopValue
    }
    if ($FailFast) {
        $args.FailOnError = $true
    }

    $raw = & $smokeScript @args

    return ($raw | ConvertFrom-Json)
}

$iteration = 0
$lastChecksHash = ""
$lastFactsHash = ""

Write-Host "Starting TOD smoke watch. Interval=${IntervalSeconds}s MaxIterations=$MaxIterations (0 means infinite)."

while ($true) {
    $iteration += 1
    $now = Get-Date
    $label = $now.ToString("yyyy-MM-dd HH:mm:ss")

    try {
        $snap = Get-SmokeSnapshot -Preferred $PreferredPort -Search $MaxPortSearch -TopValue $Top -FailFast:$FailOnError

        $checksHash = ConvertTo-ComparableJson -Object $snap.checks
        $factsHash = ConvertTo-ComparableJson -Object $snap.facts
        $delta = ($checksHash -ne $lastChecksHash -or $factsHash -ne $lastFactsHash)
        $failed = (-not [bool]$snap.passed_all)

        $shouldPrint = $VerboseOutput -or $delta -or $failed -or ($iteration -eq 1)
        if ($shouldPrint) {
            $summary = [pscustomobject]@{
                timestamp = $label
                iteration = $iteration
                passed_all = [bool]$snap.passed_all
                checks = $snap.checks
                facts = $snap.facts
                reason = if ($failed) { "failure" } elseif ($delta) { "delta" } else { "initial" }
            }
            $summary | ConvertTo-Json -Depth 8
        }

        $lastChecksHash = $checksHash
        $lastFactsHash = $factsHash
    }
    catch {
        $err = [pscustomobject]@{
            timestamp = $label
            iteration = $iteration
            passed_all = $false
            error = $_.Exception.Message
            reason = "exception"
        }
        $err | ConvertTo-Json -Depth 8

        if ($FailOnError) {
            throw
        }
    }

    if ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
