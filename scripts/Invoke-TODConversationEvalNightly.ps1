param(
    [string]$OutputRoot = "shared_state/conversation_eval",
    [int]$Seed = 8501,
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

$runner = Join-Path $PSScriptRoot "Invoke-TODConversationEvalRunner.ps1"
if (-not (Test-Path -Path $runner)) {
    throw "Runner script not found: $runner"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$regressionPath = Join-Path $outputRootAbs "conversation_score_report.regression.latest.json"
$baselinePath = Join-Path $outputRootAbs "conversation_score_report.baseline.current.json"
$nightlyPath = Join-Path $outputRootAbs "conversation_score_report.nightly.latest.json"
$markdownScript = Join-Path $PSScriptRoot "New-TODConversationMarkdownSummary.ps1"

$regression = & $runner -Stage regression -PolicyProfile tightened -OutputPath $regressionPath -Seed $Seed -EmitJson | ConvertFrom-Json

$baseline = $null
if (Test-Path -Path $baselinePath) {
    $baseline = Get-Content -Path $baselinePath -Raw | ConvertFrom-Json
}

$delta = $null
if ($baseline -and $baseline.summary -and $baseline.summary.PSObject.Properties["overall_score"]) {
    $delta = [math]::Round(([double]$regression.summary.overall_score - [double]$baseline.summary.overall_score), 4)
}

$nightly = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-conversation-eval-nightly-v1"
    run_id = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    summary = [pscustomobject]@{
        overall_score = [double]$regression.summary.overall_score
        developer_utility = if ($regression.summary.PSObject.Properties['developer_utility_score']) { [double]$regression.summary.developer_utility_score } else { $null }
        failure_count = [int]$regression.summary.failure_count
        baseline_present = [bool]($null -ne $baseline)
        delta_vs_baseline = $delta
    }
    artifacts = [pscustomobject]@{
        regression = $regressionPath
        baseline = $baselinePath
        report_markdown = ""
    }
}

if ($UpdateBaseline -or -not (Test-Path -Path $baselinePath)) {
    $regression | ConvertTo-Json -Depth 20 | Set-Content -Path $baselinePath
}

$nightly | ConvertTo-Json -Depth 12 | Set-Content -Path $nightlyPath

if (Test-Path -Path $markdownScript) {
    try {
        $markdown = & $markdownScript -Kind nightly -InputPath $nightlyPath -EmitJson | ConvertFrom-Json
        $nightly.artifacts.report_markdown = [string]$markdown.output_path
        $nightly | ConvertTo-Json -Depth 12 | Set-Content -Path $nightlyPath
    }
    catch {
    }
}

if ($EmitJson) {
    $nightly | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $nightly
}