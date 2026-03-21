param(
    [int]$Cycles = 20,
    [string]$ScenarioPath = "tod/conversation_eval/scenario_cards.json",
    [string]$OutputRoot = "shared_state/conversation_eval",
    [string[]]$IncludeScenarioIds = @(),
    [int]$Seed = 9901,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Cycles -lt 1) { throw "Cycles must be >= 1" }

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Get-Reply {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string]$Objective,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [int]$TimeoutSeedOffset = 0
    )

    $providerScript = Join-Path $PSScriptRoot "Invoke-TODConversationProvider.ps1"
    $res = & $providerScript -Action chat -Prompt $Prompt -ObjectiveSummary $Objective -TaskState "mim-tod-bridge" -ObjectiveId $ObjectiveId -AsJson | ConvertFrom-Json
    return [string]$res.reply_text
}

function Get-BridgeUtility {
    param(
        [string]$Plan,
        [string]$Critique,
        [string]$Execution,
        [string]$Validation
    )

    $score = 0.0
    if (-not [string]::IsNullOrWhiteSpace($Plan)) { $score += 0.25 }
    if (-not [string]::IsNullOrWhiteSpace($Critique)) { $score += 0.25 }
    if (-not [string]::IsNullOrWhiteSpace($Execution)) { $score += 0.25 }
    if (-not [string]::IsNullOrWhiteSpace($Validation)) { $score += 0.25 }

    $all = (([string]$Plan + "\n" + [string]$Critique + "\n" + [string]$Execution + "\n" + [string]$Validation).ToLowerInvariant())
    if ($all -match "risk|guard|rollback|validate") { $score += 0.10 }
    if ($all -match "step|checklist|gate|criteria") { $score += 0.10 }

    if ($score -gt 1.0) { $score = 1.0 }
    return [math]::Round($score, 4)
}

function Get-BridgeStageScore {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return 0.0 }

    $score = 0.45
    $t = $Text.ToLowerInvariant()
    switch ($Stage) {
        'plan' {
            if ($t -match 'assumption|scope') { $score += 0.2 }
            if ($t -match 'step|plan') { $score += 0.2 }
            if ($t -match 'risk|guard') { $score += 0.15 }
        }
        'execution' {
            if ($t -match 'checklist|step') { $score += 0.2 }
            if ($t -match 'gate|rollback') { $score += 0.2 }
            if ($t -match 'validate|verify|check') { $score += 0.15 }
        }
        'summary' {
            if ($t -match 'pass|needs_changes|block') { $score += 0.2 }
            if ($t -match 'required|next step|change') { $score += 0.2 }
            if ($t -match 'why|because|reason') { $score += 0.15 }
        }
    }

    if ($score -gt 1.0) { $score = 1.0 }
    return [math]::Round($score, 4)
}

$providerScript = Join-Path $PSScriptRoot "Invoke-TODConversationProvider.ps1"
if (-not (Test-Path -Path $providerScript)) {
    throw "Missing provider script: $providerScript"
}

$status = & $providerScript -Action status -AsJson | ConvertFrom-Json
if (-not [bool]$status.reachable) {
    throw "Local conversation provider is not reachable; start provider before running bridge cycle"
}

$scenarioAbs = Resolve-LocalPath -PathValue $ScenarioPath
if (-not (Test-Path -Path $scenarioAbs)) {
    throw "Scenario file not found: $scenarioAbs"
}
$doc = Get-Content -Path $scenarioAbs -Raw | ConvertFrom-Json
$cards = @($doc.scenario_cards | Where-Object { @($_.tags) -contains "mim_tod_bridge" })
if (@($IncludeScenarioIds).Count -gt 0) {
    $cards = @($cards | Where-Object { @($IncludeScenarioIds) -contains [string]$_.id })
}
if (@($cards).Count -eq 0) {
    throw "No MIM-TOD bridge scenarios found"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}
$bridgeRoot = Join-Path $outputRootAbs "bridge"
if (-not (Test-Path -Path $bridgeRoot)) {
    New-Item -ItemType Directory -Path $bridgeRoot -Force | Out-Null
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runPath = Join-Path $bridgeRoot ("mim_tod_bridge.{0}.json" -f $runId)
$latestPath = Join-Path $bridgeRoot "mim_tod_bridge.latest.json"

$runs = @()

for ($i = 1; $i -le $Cycles; $i += 1) {
    $card = $cards[($i - 1) % @($cards).Count]
    $ask = [string]((@($card.user_turns) -join " | "))

    $planPrompt = @"
You are MIM planner.
User ask:
$ask

Return concise sections:
1) Assumptions
2) Plan Steps
3) Risks
"@

    $plan = ""
    $critique = ""
    $execution = ""
    $validation = ""
    $runError = ""

    try {
        $plan = Get-Reply -Prompt $planPrompt -Objective "MIM plan for TOD bridge" -ObjectiveId ([string]$card.id)

    $critiquePrompt = @"
You are TOD critic reviewing a MIM plan.
Original ask:
$ask

MIM Plan:
$plan

Return concise sections:
1) Top Risks
2) Missing Guards
3) Recommended Edits
"@

        $critique = Get-Reply -Prompt $critiquePrompt -Objective "TOD critique of MIM plan" -ObjectiveId ([string]$card.id)

    $executePrompt = @"
You are TOD executor.
Original ask:
$ask

MIM Plan:
$plan

TOD Critique:
$critique

Return:
1) Execution Checklist
2) Safety Gates
3) Rollback Trigger
"@

        $execution = Get-Reply -Prompt $executePrompt -Objective "TOD execution plan" -ObjectiveId ([string]$card.id)

    $validatePrompt = @"
You are MIM validator.
Original ask:
$ask

Execution checklist from TOD:
$execution

Return:
1) Validation Result (pass/needs_changes)
2) Why
3) Required changes if any
"@

        $validation = Get-Reply -Prompt $validatePrompt -Objective "MIM validation of TOD execution" -ObjectiveId ([string]$card.id)
    }
    catch {
        $runError = $_.Exception.Message
    }

    $utility = Get-BridgeUtility -Plan $plan -Critique $critique -Execution $execution -Validation $validation
    $planQuality = Get-BridgeStageScore -Stage plan -Text ($plan + "`n" + $critique)
    $executionInterpretationQuality = Get-BridgeStageScore -Stage execution -Text $execution
    $returnSummaryQuality = Get-BridgeStageScore -Stage summary -Text $validation

    $runs += [pscustomobject]@{
        cycle = $i
        scenario_id = [string]$card.id
        bucket = [string]$card.bucket
        utility = $utility
        bridge_chain = [pscustomobject]@{
            mim_plan_quality = $planQuality
            tod_execution_interpretation_quality = $executionInterpretationQuality
            return_to_operator_summary_quality = $returnSummaryQuality
        }
        passed = [bool]($utility -ge 0.72)
        error = $runError
        transcript = [pscustomobject]@{
            ask = $ask
            mim_plan = $plan
            tod_critique = $critique
            tod_execution = $execution
            mim_validation = $validation
        }
    }
}

$runArray = @($runs)
$avgUtility = if ($runArray.Count -gt 0) {
    [math]::Round(((@($runArray | ForEach-Object { [double]$_.utility }) | Measure-Object -Average).Average), 4)
}
else { 0 }

$avgPlanQuality = if ($runArray.Count -gt 0) {
    [math]::Round(((@($runArray | ForEach-Object { [double]$_.bridge_chain.mim_plan_quality }) | Measure-Object -Average).Average), 4)
}
else { 0 }

$avgExecutionQuality = if ($runArray.Count -gt 0) {
    [math]::Round(((@($runArray | ForEach-Object { [double]$_.bridge_chain.tod_execution_interpretation_quality }) | Measure-Object -Average).Average), 4)
}
else { 0 }

$avgSummaryQuality = if ($runArray.Count -gt 0) {
    [math]::Round(((@($runArray | ForEach-Object { [double]$_.bridge_chain.return_to_operator_summary_quality }) | Measure-Object -Average).Average), 4)
}
else { 0 }

$failed = @($runArray | Where-Object { -not [bool]$_.passed })
$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-mim-bridge-cycle-v1"
    run_id = $runId
    config = [pscustomobject]@{
        cycles = $Cycles
        scenario_path = $ScenarioPath
        include_scenario_ids = @($IncludeScenarioIds)
        seed = $Seed
    }
    summary = [pscustomobject]@{
        avg_bridge_utility = $avgUtility
        avg_mim_plan_quality = $avgPlanQuality
        avg_tod_execution_interpretation_quality = $avgExecutionQuality
        avg_return_to_operator_summary_quality = $avgSummaryQuality
        failure_count = @($failed).Count
        pass_count = ($runArray.Count - @($failed).Count)
    }
    runs = $runArray
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $runPath
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $latestPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}
