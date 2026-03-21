param(
    [string]$SoakRoot = "shared_state/conversation_eval/soak",
    [string]$RunId = "latest",
    [int]$TopScenarios = 25,
    [string[]]$FocusTags = @("low_relevance", "missing_safety_boundary"),
    [string]$ScenarioPath = "tod/conversation_eval/scenario_cards.json",
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
$runDir = Get-RunDirectory -Root $soakRootAbs -Id $RunId

$driftPath = Join-Path $runDir "conversation_coach.drift.latest.json"
if (-not (Test-Path -Path $driftPath)) {
    throw "Drift report missing: $driftPath. Run Get-TODConversationDriftAnalysis.ps1 first."
}

$drift = Get-Content -Path $driftPath -Raw | ConvertFrom-Json
$scenarioAbs = Resolve-LocalPath -PathValue $ScenarioPath
if (-not (Test-Path -Path $scenarioAbs)) {
    throw "Scenario file not found: $scenarioAbs"
}

$scenarioDoc = Get-Content -Path $scenarioAbs -Raw | ConvertFrom-Json
$cards = @($scenarioDoc.scenario_cards)
$byId = @{}
foreach ($c in $cards) {
    $byId[[string]$c.id] = $c
}

$focus = @($FocusTags)
$selected = @()
foreach ($row in @($drift.scenario_drift | Sort-Object delta -Descending | Select-Object -First $TopScenarios)) {
    if ([int]$row.delta -le 0) { continue }
    $sid = [string]$row.scenario_id
    if (-not $byId.ContainsKey($sid)) { continue }

    $card = $byId[$sid]
    $tagMatch = $false
    foreach ($t in @($card.tags)) {
        if ($focus -contains [string]$t) {
            $tagMatch = $true
            break
        }
    }
    if (-not $tagMatch) { continue }

    $selected += [pscustomobject]@{
        scenario_id = $sid
        bucket = [string]$card.bucket
        tags = @($card.tags)
        difficulty = [int]$card.difficulty
        user_turns = @($card.user_turns)
        expected_behavior = @($card.expected_behavior)
        failure_conditions = @($card.failure_conditions)
        drift_delta = [int]$row.delta
        early_count = [int]$row.early_count
        late_count = [int]$row.late_count
    }
}

$pack = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-replay-pack-v1"
    run_dir = $runDir
    focus_tags = @($FocusTags)
    scenario_count = @($selected).Count
    scenarios = @($selected)
}

$outPath = Join-Path $runDir "conversation_replay_pack.focus.latest.json"
$pack | ConvertTo-Json -Depth 20 | Set-Content -Path $outPath

if ($EmitJson) {
    $pack | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $pack
}
