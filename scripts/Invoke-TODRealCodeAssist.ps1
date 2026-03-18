param(
    [ValidateSet("review", "debug", "fixes", "plan", "operator")]
    [string]$Mode = "review",
    [string[]]$FilePaths = @(),
    [string]$OutputRoot = "shared_state/conversation_eval/real_usage",
    [int]$MaxFiles = 3,
    [int]$MaxLinesPerFile = 120,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($MaxFiles -lt 1) { throw "MaxFiles must be >= 1" }
if ($MaxLinesPerFile -lt 20) { throw "MaxLinesPerFile must be >= 20" }

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return [System.IO.Path]::GetFullPath($PathValue) }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Get-UtilityScore {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return 0.0 }
    $t = $Text.ToLowerInvariant()
    $score = 0.35
    if ($t -match "fix|patch|change|replace") { $score += 0.20 }
    if ($t -match "line|error|exception|risk|bug") { $score += 0.20 }
    if ($t -match "next step|command|test") { $score += 0.15 }
    if ($Text.Length -lt 2500) { $score += 0.10 }
    if ($score -gt 1.0) { $score = 1.0 }
    return [math]::Round($score, 4)
}

$providerScript = Join-Path $PSScriptRoot "Invoke-TODConversationProvider.ps1"
if (-not (Test-Path -Path $providerScript)) {
    throw "Missing provider script: $providerScript"
}

$status = & $providerScript -Action status -AsJson | ConvertFrom-Json
if (-not [bool]$status.reachable) {
    throw "Local conversation provider is not reachable; start provider before running real-code assist"
}

$resolvedFiles = @()
if (@($FilePaths).Count -gt 0) {
    foreach ($p in @($FilePaths)) {
        $candidate = Resolve-LocalPath -PathValue $p
        if (Test-Path -Path $candidate -PathType Leaf) {
            $resolvedFiles += $candidate
        }
    }
}
else {
    $resolvedFiles = @(
        Get-ChildItem -Path (Join-Path $repoRoot "scripts") -Filter "*.ps1" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $MaxFiles |
        ForEach-Object { $_.FullName }
    )
}

$resolvedFiles = @($resolvedFiles | Select-Object -Unique | Select-Object -First $MaxFiles)
if (@($resolvedFiles).Count -eq 0) {
    throw "No files found for real-code assist"
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
if (-not (Test-Path -Path $outputRootAbs)) {
    New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
}

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$runPath = Join-Path $outputRootAbs ("tod_real_code_assist.{0}.json" -f $runId)
$latestPath = Join-Path $outputRootAbs "tod_real_code_assist.latest.json"

$results = @()

foreach ($f in @($resolvedFiles)) {
    $content = Get-Content -Path $f -TotalCount $MaxLinesPerFile
    $snippet = ($content -join "`n")
    if ($snippet.Length -gt 7000) {
        $snippet = $snippet.Substring(0, 7000)
    }

    $modeInstruction = switch ($Mode) {
        "review" { "Review this code for bugs, risks, regressions, and missing tests. Prioritize highest-severity findings." }
        "debug" { "Debug likely failure points and provide an actionable diagnosis path with concrete checks." }
        "fixes" { "Suggest concrete code fixes and minimal patch-style edits with rationale." }
        "plan" { "Create a concrete implementation plan with sequenced steps, constraints, and explicit verification checkpoints." }
        "operator" { "Provide operator-facing engineering support: triage with limited evidence, define one safe default action, and list only the highest-value follow-up check." }
    }

    $prompt = @"
$modeInstruction

Output format:
1) Top findings (or root cause hypotheses) in priority order
2) Actionable fixes
3) Minimal verification steps

File: $f
Code excerpt:
$snippet
"@

    try {
        $reply = & $providerScript -Action chat -Prompt $prompt -ObjectiveSummary "Real code assist" -TaskState "real-code-$Mode" -ObjectiveId ([System.IO.Path]::GetFileName($f)) -AsJson | ConvertFrom-Json
        $text = [string]$reply.reply_text
        $utility = Get-UtilityScore -Text $text

        $results += [pscustomobject]@{
            file = $f
            mode = $Mode
            utility = $utility
            response = $text
            passed = [bool]($utility -ge 0.72)
        }
    }
    catch {
        $results += [pscustomobject]@{
            file = $f
            mode = $Mode
            utility = 0.0
            response = ""
            passed = $false
            error = $_.Exception.Message
        }
    }
}

$avgUtility = [math]::Round(((@($results | ForEach-Object { [double]$_.utility }) | Measure-Object -Average).Average), 4)
$failed = @($results | Where-Object { -not [bool]$_.passed })

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-real-code-assist-v1"
    run_id = $runId
    config = [pscustomobject]@{
        mode = $Mode
        max_files = $MaxFiles
        max_lines_per_file = $MaxLinesPerFile
        file_count = @($results).Count
    }
    summary = [pscustomobject]@{
        average_utility = $avgUtility
        pass_count = (@($results).Count - @($failed).Count)
        failure_count = @($failed).Count
    }
    results = @($results)
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $runPath
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $latestPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}
