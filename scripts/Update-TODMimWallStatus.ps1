param(
    [string]$ProjectPath = "E:\mim_wall",
    [string]$FileName = "TOD.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $Content, $utf8NoBom)
}

function Set-MarkedBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$BeginMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][string]$Block,
        [string]$AnchorPattern
    )

    $normalizedBlock = ($Block -replace "`r?`n", "`r`n").TrimEnd()
    $replacement = $BeginMarker + "`r`n" + $normalizedBlock + "`r`n" + $EndMarker
    $beginIndex = $Content.IndexOf($BeginMarker, [System.StringComparison]::Ordinal)
    if ($beginIndex -ge 0) {
        $endIndex = $Content.IndexOf($EndMarker, $beginIndex, [System.StringComparison]::Ordinal)
        if ($endIndex -ge 0) {
            $afterEnd = $endIndex + $EndMarker.Length
            return $Content.Substring(0, $beginIndex) + $replacement + $Content.Substring($afterEnd)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($AnchorPattern)) {
        $anchor = [regex]::Match($Content, $AnchorPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if ($anchor.Success) {
            return $Content.Insert($anchor.Index + $anchor.Length, "`r`n`r`n" + $replacement)
        }
    }

    return ($Content.TrimEnd() + "`r`n`r`n" + $replacement + "`r`n")
}

function Get-GitBranch {
    param([string]$Root)
    return [string](& git -C $Root rev-parse --abbrev-ref HEAD 2>$null)
}

function Get-GitRemote {
    param([string]$Root)
    return [string](& git -C $Root remote get-url origin 2>$null)
}

function Get-RecentCommits {
    param(
        [string]$Root,
        [int]$Count = 7
    )

    return @(& git -C $Root log --oneline -n $Count 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

function Set-LineValue {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    return [regex]::Replace($Content, $Pattern, $Replacement, [System.Text.RegularExpressions.RegexOptions]::Multiline)
}

if (-not (Test-Path -Path $ProjectPath)) {
    throw "Project path not found: $ProjectPath"
}

$todPath = Join-Path $ProjectPath $FileName
$readmePath = Join-Path $ProjectPath "README.md"
$planPath = Join-Path $ProjectPath "DEVELOPMENT_PLAN.md"

foreach ($requiredPath in @($todPath, $readmePath, $planPath)) {
    if (-not (Test-Path -Path $requiredPath)) {
        throw "Required file not found: $requiredPath"
    }
}

$now = (Get-Date).ToUniversalTime()
$nowIso = $now.ToString("o")
$nowDate = $now.ToString("yyyy-MM-dd")
$branch = Get-GitBranch -Root $ProjectPath
$remote = Get-GitRemote -Root $ProjectPath
$recentCommits = Get-RecentCommits -Root $ProjectPath -Count 7

$commitLines = @()
foreach ($commit in $recentCommits) {
    $commitLines += ('- `' + [string]$commit + '`')
}
$commitBlock = ($commitLines -join "`r`n")

$readmeContent = Get-Content -Path $readmePath -Raw
$readmeContent = Set-LineValue -Content $readmeContent -Pattern '^- Last updated: .*$' -Replacement ('- Last updated: ' + $nowDate)
$readmeBlock = @(
    '## Latest Shipped State',
    '',
    ('- Current branch: `' + $branch + '`'),
    ('- Current remote: `' + $remote + '`'),
    ('- Last refreshed by TOD: ' + $nowIso),
    '',
    'Recently shipped work:',
    '',
    $commitBlock,
    '',
    'Current operator handoff summary:',
    '',
    '- Directive and solicitation handling is prioritized ahead of generic fallback narration.',
    '- Communicator UI is reduced to a focused waveform and push-to-talk model with interruption controls.',
    '- Capability readiness preflight remains part of the regression gate before live simulation.',
    '- Automated dialog regression artifacts under `artifacts/dialog-regression/` remain the default publish evidence pack.'
) -join "`r`n"
$readmeContent = Set-MarkedBlock -Content $readmeContent -BeginMarker '<!-- TOD:BEGIN AUTO STATUS -->' -EndMarker '<!-- TOD:END AUTO STATUS -->' -Block $readmeBlock -AnchorPattern 'It helps you decide when to jump into a call, when to ignore it, and when to collect a message instead\.'
Write-Utf8NoBom -PathValue $readmePath -Content $readmeContent

$planContent = Get-Content -Path $planPath -Raw
$planContent = Set-LineValue -Content $planContent -Pattern '^- Last updated: .*$' -Replacement ('- Last updated: ' + $nowDate)
$planContent = Set-LineValue -Content $planContent -Pattern '## Baseline Status \([^\r\n]*\)' -Replacement ('## Baseline Status (' + $nowDate + ')')
$planBlock = @(
    '## Recent Delivered Work',
    '',
    ('- Last refreshed by TOD: ' + $nowIso),
    ('- Current branch: `' + $branch + '`'),
    '',
    'Delivered on current head:',
    '',
    $commitBlock,
    '',
    'Plan consequence:',
    '',
    '- Phase 2 SMS context intelligence has materially advanced through solicitation-first and transactional suppression behavior.',
    '- Phase 3 owner control loop has materially advanced through communicator simplification and interruption handling.',
    '- Platform stability remains the publish gate anchor: build, lint, device smoke, and automated dialog regression evidence.'
) -join "`r`n"
$planReplacement = '<!-- TOD:BEGIN AUTO STATUS -->' + "`r`n" + ($planBlock -replace "`r?`n", "`r`n").TrimEnd() + "`r`n" + '<!-- TOD:END AUTO STATUS -->'
if ($planContent -match '<!-- TOD:BEGIN AUTO STATUS -->') {
    $planContent = Set-MarkedBlock -Content $planContent -BeginMarker '<!-- TOD:BEGIN AUTO STATUS -->' -EndMarker '<!-- TOD:END AUTO STATUS -->' -Block $planBlock -AnchorPattern '## Delivery Model'
}
else {
    $planContent = $planContent.Replace('## Delivery Model', $planReplacement + "`r`n`r`n" + '## Delivery Model')
}
Write-Utf8NoBom -PathValue $planPath -Content $planContent

$todContent = Get-Content -Path $todPath -Raw
$todStatusBlock = @(
    '## TOD Status Refresh',
    '',
    '- Project: MIM Assist (`E:/mim_wall`)',
    '- TOD registry status: registered in `E:/TOD/tod/config/project-registry.json`',
    ('- Git branch: `' + $branch + '`'),
    ('- Git remote: `' + $remote + '`'),
    ('- Last TOD refresh: ' + $nowIso),
    '- Primary handoff docs: `README.md`, `MIM_ASSIST_SPEC.md`, `DEVELOPMENT_PLAN.md`, `SPRINT_1_PLAN.md`',
    '- Recommended validation gate:',
    '  - `./gradlew.bat assembleDebug`',
    '  - `./gradlew.bat lintDebug`',
    '  - `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1`',
    '',
    'Latest validated git head:',
    '',
    $commitBlock
) -join "`r`n"

if ($todContent -match '<!-- TOD:BEGIN AUTO STATUS -->') {
    $todContent = Set-MarkedBlock -Content $todContent -BeginMarker '<!-- TOD:BEGIN AUTO STATUS -->' -EndMarker '<!-- TOD:END AUTO STATUS -->' -Block $todStatusBlock -AnchorPattern '^# TOD Summary'
}
elseif ([regex]::IsMatch($todContent, '## TOD Status Refresh.*?(?=\r?\n## )', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
    $todContent = [regex]::Replace($todContent, '## TOD Status Refresh.*?(?=\r?\n## )', '<!-- TOD:BEGIN AUTO STATUS -->' + "`r`n" + $todStatusBlock + "`r`n" + '<!-- TOD:END AUTO STATUS -->' + "`r`n", [System.Text.RegularExpressions.RegexOptions]::Singleline)
}
else {
    $todContent = Set-MarkedBlock -Content $todContent -BeginMarker '<!-- TOD:BEGIN AUTO STATUS -->' -EndMarker '<!-- TOD:END AUTO STATUS -->' -Block $todStatusBlock -AnchorPattern '^# TOD Summary'
}
Write-Utf8NoBom -PathValue $todPath -Content $todContent

[pscustomobject]@{
    ok = $true
    project_path = $ProjectPath
    refreshed_at = $nowIso
    git_branch = $branch
    git_remote = $remote
    written_files = @($todPath, $readmePath, $planPath)
    recent_commits = @($recentCommits)
}