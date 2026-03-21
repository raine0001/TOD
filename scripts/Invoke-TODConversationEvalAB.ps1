param(
    [ValidateSet("smoke", "expanded", "stress", "regression")]
    [string]$Stage = "expanded",
    [string]$OutputRoot = "shared_state/conversation_eval",
    [string[]]$FocusTags = @("low_relevance", "response_loop_risk", "missing_safety_boundary"),
    [int]$Seed = 9201,
    [ValidateSet("auto", "early", "mid", "late")]
    [string]$CyclePosition = "auto",
    [int]$CycleIndex = 0,
    [int]$CycleCount = 0,
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

$runner = Join-Path $PSScriptRoot "Invoke-TODConversationEvalRunner.ps1"
if (-not (Test-Path -Path $runner)) {
    throw "Runner script not found: $runner"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$focusSlug = (@($FocusTags) -join "_")
$baselinePath = Join-Path $outputRootAbs ("conversation_score_report.ab.baseline.{0}.latest.json" -f $focusSlug)
$tightenedPath = Join-Path $outputRootAbs ("conversation_score_report.ab.tightened.{0}.latest.json" -f $focusSlug)
$comparePath = Join-Path $outputRootAbs ("conversation_score_report.ab.compare.{0}.latest.json" -f $focusSlug)

$baseline = & $runner -Stage $Stage -PolicyProfile baseline -IncludeTags $FocusTags -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -OutputPath $baselinePath -Seed $Seed -EmitJson | ConvertFrom-Json
$tightened = & $runner -Stage $Stage -PolicyProfile tightened -IncludeTags $FocusTags -CyclePosition $CyclePosition -CycleIndex $CycleIndex -CycleCount $CycleCount -OutputPath $tightenedPath -Seed $Seed -EmitJson | ConvertFrom-Json

$delta = [math]::Round(([double]$tightened.summary.overall_score - [double]$baseline.summary.overall_score), 4)

$compare = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-eval-ab-v1"
    stage = $Stage
    focus_tags = @($FocusTags)
    summary = [pscustomobject]@{
        baseline_overall = [double]$baseline.summary.overall_score
        tightened_overall = [double]$tightened.summary.overall_score
        delta_overall = $delta
        baseline_failures = [int]$baseline.summary.failure_count
        tightened_failures = [int]$tightened.summary.failure_count
        improved = [bool]($delta -gt 0)
    }
    artifacts = [pscustomobject]@{
        baseline = $baselinePath
        tightened = $tightenedPath
    }
}

$compare | ConvertTo-Json -Depth 12 | Set-Content -Path $comparePath

if ($EmitJson) {
    $compare | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $compare
}