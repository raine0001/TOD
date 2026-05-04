param(
    [string]$BasePromptSetPath = 'tod/config/tod-stale-recovery-prompts-2026-04-14.json',
    [string]$OutputPath = '',
    [int]$VariantsPerCriticalPrompt = 8,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-PromptEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][int]$TaskNumber,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    return [pscustomobject]@{
        id = $Id
        task_number = $TaskNumber
        title = $Title
        prompt = $Prompt
    }
}

$resolvedBasePromptSetPath = Resolve-RepoPath -PathValue $BasePromptSetPath
if (-not (Test-Path -Path $resolvedBasePromptSetPath -PathType Leaf)) {
    throw "Base prompt set not found: $resolvedBasePromptSetPath"
}

$resolvedOutputPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Resolve-RepoPath -PathValue 'tod/config/tod-stale-recovery-prompts-focused-2026-04-15.json'
}
else {
    Resolve-RepoPath -PathValue $OutputPath
}

$basePromptSet = Get-Content -Path $resolvedBasePromptSetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$basePrompts = @($basePromptSet.prompts)

$criticalPromptIds = @(
    'stale-recovery-001',
    'stale-recovery-009',
    'stale-recovery-012',
    'stale-recovery-013',
    'stale-recovery-035',
    'stale-recovery-039'
)

$variantSuffixes = @(
    'Use canonical objective 152 if any local memory still points at 170.',
    'Treat stale local mirrors as lower priority than integration truth and name the specific artifact you trust first.',
    'If the model answer is short, confident, and wrong, reject it and continue with a bounded repair step.',
    'Assume watchdog drift is warning but the live task request is fresh; prefer the live task and explain why.',
    'If pending_remote has already reminded once, stop waiting and choose a bounded local recommendation.',
    'If readiness is stale, force the minimum truth refresh before answering in normal mode.',
    'Name the blocker artifact, the repair artifact, and the next bounded action in the same answer.',
    'Avoid low-value memory repetition and keep the answer anchored to the current active task.'
)

$promptList = New-Object System.Collections.Generic.List[object]
$taskNumber = 1

foreach ($prompt in $basePrompts) {
    $promptList.Add((New-PromptEntry -Id ([string]$prompt.id) -TaskNumber $taskNumber -Title ([string]$prompt.title) -Prompt ([string]$prompt.prompt))) | Out-Null
    $taskNumber += 1
}

foreach ($prompt in $basePrompts | Where-Object { $criticalPromptIds -contains [string]$_.id }) {
    $variantCount = [Math]::Min($VariantsPerCriticalPrompt, @($variantSuffixes).Count)
    for ($index = 0; $index -lt $variantCount; $index++) {
        $variantId = ('{0}-focus-{1:d2}' -f [string]$prompt.id, ($index + 1))
        $variantTitle = ('{0} Focus Variant {1}' -f [string]$prompt.title, ($index + 1))
        $variantPrompt = ('{0} {1}' -f ([string]$prompt.prompt).Trim(), $variantSuffixes[$index]).Trim()
        $promptList.Add((New-PromptEntry -Id $variantId -TaskNumber $taskNumber -Title $variantTitle -Prompt $variantPrompt)) | Out-Null
        $taskNumber += 1
    }
}

$materializedPrompts = @($promptList.ToArray())
$materializedCriticalPromptIds = @($criticalPromptIds)

$generatedPromptSet = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-focused-stale-recovery-prompt-set-v1'
    base_prompt_set_path = $resolvedBasePromptSetPath
    base_prompt_count = @($basePrompts).Count
    critical_prompt_ids = $materializedCriticalPromptIds
    variants_per_critical_prompt = $VariantsPerCriticalPrompt
    prompts = $materializedPrompts
}

Write-JsonNoBom -PathValue $resolvedOutputPath -Payload $generatedPromptSet -Depth 10

$result = [pscustomobject]@{
    ok = $true
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-focused-stale-recovery-prompt-set-v1'
    output_path = $resolvedOutputPath
    prompt_count = @($materializedPrompts).Count
    base_prompt_count = @($basePrompts).Count
    generated_variant_count = (@($materializedPrompts).Count - @($basePrompts).Count)
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 10 | Write-Output
}
else {
    $result
}