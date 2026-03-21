param(
    [ValidateSet("smoke", "expanded", "stress", "regression")]
    [string]$Stage = "expanded",
    [string]$OutputRoot = "shared_state/conversation_eval",
    [string[]]$FocusTags = @("low_relevance", "response_loop_risk", "missing_safety_boundary", "messy_real_world", "mim_tod_bridge"),
    [int]$Seed = 9301,
    [ValidateSet("auto", "early", "mid", "late")]
    [string]$CyclePosition = "auto",
    [int]$CycleIndex = 0,
    [int]$CycleCount = 0,
    [int]$LiveDrillCount = 6,
    [switch]$RunNightlyRegression,
    [switch]$UpdateBaseline,
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

function Get-TopFailureTags {
    param([Parameter(Mandatory = $true)][object]$Runs)
    $map = @{}
    foreach ($r in @($Runs)) {
        foreach ($tag in @($r.failure_tags)) {
            if (-not $map.ContainsKey([string]$tag)) {
                $map[[string]$tag] = 0
            }
            $map[[string]$tag] += 1
        }
    }

    return @($map.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
            [pscustomobject]@{
                tag = [string]$_.Key
                count = [int]$_.Value
            }
        })
}

$abScript = Join-Path $PSScriptRoot "Invoke-TODConversationEvalAB.ps1"
$prScript = Join-Path $PSScriptRoot "Invoke-TODConversationEvalPR.ps1"
$nightlyScript = Join-Path $PSScriptRoot "Invoke-TODConversationEvalNightly.ps1"
$providerScript = Join-Path $PSScriptRoot "Invoke-TODConversationProvider.ps1"

if (-not (Test-Path -Path $abScript)) { throw "Missing script: $abScript" }
if (-not (Test-Path -Path $prScript)) { throw "Missing script: $prScript" }
if (-not (Test-Path -Path $nightlyScript)) { throw "Missing script: $nightlyScript" }
if (-not (Test-Path -Path $providerScript)) { throw "Missing script: $providerScript" }

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$ab = & $abScript -Stage $Stage -OutputRoot $OutputRoot -FocusTags $FocusTags -Seed $Seed -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -EmitJson | ConvertFrom-Json
$pr = & $prScript -OutputRoot $OutputRoot -Seed ($Seed + 101) -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -EmitJson | ConvertFrom-Json

$nightly = $null
if ($RunNightlyRegression) {
    $nightlyParams = @{
        OutputRoot = $OutputRoot
        Seed = ($Seed + 202)
        EmitJson = $true
    }
    if ($UpdateBaseline) {
        $nightlyParams["UpdateBaseline"] = $true
    }
    $nightly = & $nightlyScript @nightlyParams | ConvertFrom-Json
}

$tightenedRuns = @()
if ($ab.artifacts -and $ab.artifacts.tightened -and (Test-Path -Path ([string]$ab.artifacts.tightened))) {
    $tightenedDoc = Get-Content -Path ([string]$ab.artifacts.tightened) -Raw | ConvertFrom-Json
    $tightenedRuns = @($tightenedDoc.runs)
}

$providerStatus = $null
$liveDrills = @()
$providerError = ""

try {
    $providerStatus = & $providerScript -Action status -AsJson | ConvertFrom-Json
}
catch {
    $providerError = $_.Exception.Message
}

if ($LiveDrillCount -gt 0 -and $providerStatus -and [bool]$providerStatus.reachable) {
    $scenarioPath = Resolve-LocalPath -PathValue "tod/conversation_eval/scenario_cards.json"
    if (Test-Path -Path $scenarioPath) {
        $scenarioDoc = Get-Content -Path $scenarioPath -Raw | ConvertFrom-Json
        $cards = @($scenarioDoc.scenario_cards)
        if (@($FocusTags).Count -gt 0) {
            $cards = @($cards | Where-Object {
                    foreach ($tag in @($FocusTags)) {
                        if (@($_.tags) -contains [string]$tag) { return $true }
                    }
                    return $false
                })
        }

        if (@($cards).Count -gt 0) {
            $rng = New-Object System.Random($Seed)
            $maxDrills = [Math]::Min($LiveDrillCount, @($cards).Count)
            for ($i = 0; $i -lt $maxDrills; $i += 1) {
                $card = $cards[$rng.Next(0, @($cards).Count)]
                $prompt = [string]($card.user_turns | Select-Object -First 1)
                if ([string]::IsNullOrWhiteSpace($prompt)) {
                    continue
                }

                try {
                    $reply = & $providerScript -Action chat -Prompt $prompt -ObjectiveSummary "Conversation coaching drill" -TaskState "coach-drill" -ObjectiveId ([string]$card.id) -AsJson | ConvertFrom-Json
                    $liveDrills += [pscustomobject]@{
                        scenario_id = [string]$card.id
                        bucket = [string]$card.bucket
                        prompt = $prompt
                        reply_text = [string]$reply.reply_text
                        ok = $true
                    }
                }
                catch {
                    $liveDrills += [pscustomobject]@{
                        scenario_id = [string]$card.id
                        bucket = [string]$card.bucket
                        prompt = $prompt
                        reply_text = ""
                        ok = $false
                        error = $_.Exception.Message
                    }
                }
            }
        }
    }
}

$actions = @()
$delta = [double]$ab.summary.delta_overall
$remainingFailures = [int]$ab.summary.tightened_failures

if ($delta -gt 0) {
    $actions += "Keep tightened as default and avoid policy rollback while delta remains positive."
}
if ($remainingFailures -gt 0) {
    $actions += "Prioritize replay drills for remaining failures in focus tags before broad policy edits."
}
if ($pr.summary.PSObject.Properties['drift_lock_passed'] -and -not [bool]$pr.summary.drift_lock_passed) {
    $actions += "Drift lock suite failed; replay pack scenarios are now hard blockers until cleared."
}
if ($pr.summary.PSObject.Properties['developer_utility_passed'] -and -not [bool]$pr.summary.developer_utility_passed) {
    $actions += "Developer utility dropped below threshold; prioritize actionable, concise output over purely correct but unusable responses."
}
if ([double]$pr.summary.overall_score -lt 0.74) {
    $actions += "Raise PR threshold after replay pass stabilizes above 0.74 for two consecutive runs."
}
if ($RunNightlyRegression -and $nightly -and $nightly.summary.delta_vs_baseline -ne $null -and [double]$nightly.summary.delta_vs_baseline -lt 0) {
    $actions += "Nightly regression is below baseline; block policy promotion until recovered."
}
if (@($liveDrills).Count -eq 0) {
    $actions += "Start local provider and run live drills to validate simulated gains against real responses."
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-coach-v1"
    stage = $Stage
    focus_tags = @($FocusTags)
    summary = [pscustomobject]@{
        ab_delta_overall = $delta
        tightened_failures = $remainingFailures
        pr_overall = [double]$pr.summary.overall_score
        pr_developer_utility = if ($pr.summary.PSObject.Properties['developer_utility']) { [double]$pr.summary.developer_utility } else { $null }
        pr_developer_utility_passed = if ($pr.summary.PSObject.Properties['developer_utility_passed']) { [bool]$pr.summary.developer_utility_passed } else { $null }
        pr_gate_passed = [bool]$pr.summary.gate_passed
        drift_lock_passed = if ($pr.summary.PSObject.Properties['drift_lock_passed']) { [bool]$pr.summary.drift_lock_passed } else { $null }
        drift_lock_failures = if ($pr.summary.PSObject.Properties['drift_lock_failures']) { [int]$pr.summary.drift_lock_failures } else { $null }
        drift_lock_consistency = if ($pr.summary.PSObject.Properties['drift_lock_consistency']) { [double]$pr.summary.drift_lock_consistency } else { $null }
        cycle_position = $CyclePosition
        cycle_index = $CycleIndex
        cycle_count = $CycleCount
        nightly_overall = if ($nightly) { [double]$nightly.summary.overall_score } else { $null }
        nightly_delta_vs_baseline = if ($nightly) { $nightly.summary.delta_vs_baseline } else { $null }
        provider_reachable = if ($providerStatus) { [bool]$providerStatus.reachable } else { $false }
        live_drill_count = @($liveDrills).Count
    }
    top_failure_tags = @(Get-TopFailureTags -Runs $tightenedRuns)
    recommended_actions = @($actions)
    artifacts = [pscustomobject]@{
        ab_compare = [string](Join-Path $outputRootAbs ("conversation_score_report.ab.compare.{0}.latest.json" -f (@($FocusTags) -join "_")))
        pr = [string](Join-Path $outputRootAbs "conversation_score_report.pr.latest.json")
        nightly = if ($nightly) { [string](Join-Path $outputRootAbs "conversation_score_report.nightly.latest.json") } else { "" }
        coach_report = [string](Join-Path $outputRootAbs "conversation_coach.latest.json")
    }
    live_drills = @($liveDrills)
    provider_status = if ($providerStatus) { $providerStatus } else { [pscustomobject]@{ ok = $false; error = $providerError } }
}

$coachPath = Join-Path $outputRootAbs "conversation_coach.latest.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $coachPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}