param(
  [string]$Suite = "",
  [string]$Output = "",
  [string]$MarkdownOutput = "",
  [string]$Replies = "",
  [string]$LiveBaseUrl = "",
  [int]$TimeoutSeconds = 45,
  [switch]$NoIdealBaseline,
  [switch]$RefreshTrainingScoreboards
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$tool = Join-Path $repoRoot "tools\score_mim_structural_reasoning_diversity.py"
if (-not (Test-Path -LiteralPath $tool)) {
  throw "Missing structural reasoning scorer: $tool"
}

$argsList = @($tool, "--timeout", [string]$TimeoutSeconds)
if (-not [string]::IsNullOrWhiteSpace($Suite)) { $argsList += @("--suite", $Suite) }
if (-not [string]::IsNullOrWhiteSpace($Output)) { $argsList += @("--output", $Output) }
if (-not [string]::IsNullOrWhiteSpace($MarkdownOutput)) { $argsList += @("--markdown-output", $MarkdownOutput) }
if (-not [string]::IsNullOrWhiteSpace($Replies)) { $argsList += @("--replies", $Replies) }
if (-not [string]::IsNullOrWhiteSpace($LiveBaseUrl)) { $argsList += @("--live-base-url", $LiveBaseUrl) }
if ($NoIdealBaseline) { $argsList += "--no-ideal-baseline" }

python @argsList

if ($RefreshTrainingScoreboards) {
  python (Join-Path $repoRoot "scripts\generate_mim_tod_training_scoreboard.py")
  python (Join-Path $repoRoot "tools\build_mim_operator_impact_scorecard.py")
  python (Join-Path $repoRoot "tools\build_mim_tod_real_movement_scorecard.py")
}
