param(
    [string]$PromptSetPath = 'tod/config/tod-stale-recovery-prompts-2026-04-14.json',
    [string]$OutputDir = '',
    [string]$OperatorName = 'Operator',
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$conversationScript = Join-Path $PSScriptRoot 'Invoke-TODConversationalReply.ps1'

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
        [int]$Depth = 30
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Get-ReplySignalCounts {
    param([string]$ReplyText)

    $text = [string]$ReplyText
    return [pscustomobject]@{
        mentions_refresh_governance_snapshot = ($text -match 'refresh-governance-snapshot')
        mentions_warnings_summary = ($text -match 'warnings-summary|warnings summary')
        mentions_objective_152 = ($text -match 'objective-152|objective 152')
        mentions_next_step = ($text -match 'next step|next action')
        short_reply = ($text.Trim().Length -lt 220)
    }
}

if (-not (Test-Path -Path $conversationScript -PathType Leaf)) {
    throw "Missing conversational script: $conversationScript"
}

$resolvedPromptSetPath = Resolve-RepoPath -PathValue $PromptSetPath
if (-not (Test-Path -Path $resolvedPromptSetPath -PathType Leaf)) {
    throw "Prompt set not found: $resolvedPromptSetPath"
}

$resolvedOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    Join-Path $repoRoot ('tod/out/training/stale-recovery-direct-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
}
else {
    Resolve-RepoPath -PathValue $OutputDir
}

New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
$itemsDir = Join-Path $resolvedOutputDir 'items'
New-Item -ItemType Directory -Path $itemsDir -Force | Out-Null

$promptSet = Get-Content -Path $resolvedPromptSetPath -Raw -Encoding UTF8 | ConvertFrom-Json
$prompts = @($promptSet.prompts)

$results = New-Object System.Collections.Generic.List[object]
$runErrors = New-Object System.Collections.Generic.List[object]

foreach ($prompt in $prompts) {
    $query = [string]$prompt.prompt
    $itemId = [string]$prompt.id
    $title = [string]$prompt.title

    try {
        $raw = & $conversationScript -Query $query -OperatorName $OperatorName -AsJson | Out-String
        $response = $raw | ConvertFrom-Json
        $signalCounts = Get-ReplySignalCounts -ReplyText ([string]$response.reply_text)

        $itemResult = [pscustomobject]@{
            id = $itemId
            task_number = [int]$prompt.task_number
            title = $title
            prompt = $query
            ok = [bool]$response.ok
            generated_at = [string]$response.generated_at
            request_kind = [string]$response.request_kind
            source = [string]$response.source
            provider_status = $response.provider_status
            current_objective = [string]$response.current_work.objective_id
            active_task = [string]$response.current_work.active_task
            next_action = [string]$response.current_work.next_action
            blocker = [string]$response.current_work.blocker
            reply_text = [string]$response.reply_text
            limitations = @($response.limitations)
            signals = $signalCounts
            raw_response = $response
        }

        $results.Add($itemResult) | Out-Null
        Write-JsonNoBom -PathValue (Join-Path $itemsDir ($itemId + '.json')) -Payload $itemResult -Depth 40
    }
    catch {
        $errorRecord = [pscustomobject]@{
            id = $itemId
            task_number = [int]$prompt.task_number
            title = $title
            prompt = $query
            ok = $false
            error = [string]$_.Exception.Message
        }

        $runErrors.Add($errorRecord) | Out-Null
        $results.Add($errorRecord) | Out-Null
        Write-JsonNoBom -PathValue (Join-Path $itemsDir ($itemId + '.json')) -Payload $errorRecord -Depth 20

        if ($FailOnError) {
            throw
        }
    }
}

$successful = @($results | Where-Object { $_.PSObject.Properties['source'] })
$boundedFallbackCount = @($successful | Where-Object { [string]$_.source -eq 'bounded_fallback' }).Count
$providerCount = @($successful | Where-Object { [string]$_.source -eq 'local_conversation_provider' }).Count
$requestKinds = @($successful | Group-Object request_kind | ForEach-Object {
    [ordered]@{
        name = [string]$_.Name
        count = [int]$_.Count
    }
})
$signalSummary = [ordered]@{
    refresh_governance_snapshot_mentions = @($successful | Where-Object { $_.signals.mentions_refresh_governance_snapshot }).Count
    warnings_summary_mentions = @($successful | Where-Object { $_.signals.mentions_warnings_summary }).Count
    objective_152_mentions = @($successful | Where-Object { $_.signals.mentions_objective_152 }).Count
    next_step_mentions = @($successful | Where-Object { $_.signals.mentions_next_step }).Count
    short_replies = @($successful | Where-Object { $_.signals.short_reply }).Count
}

$summaryMap = [ordered]@{}
$summaryMap['ok'] = [bool]($runErrors.Count -eq 0)
$summaryMap['generated_at'] = (Get-Date).ToUniversalTime().ToString('o')
$summaryMap['source'] = 'tod-stale-recovery-direct-run-v1'
$summaryMap['prompt_set_path'] = $resolvedPromptSetPath
$summaryMap['output_dir'] = $resolvedOutputDir
$summaryMap['prompt_count'] = [int]@($prompts).Count
$summaryMap['success_count'] = [int]@($successful).Count
$summaryMap['error_count'] = [int]$runErrors.Count
$summaryMap['bounded_fallback_count'] = [int]$boundedFallbackCount
$summaryMap['local_conversation_provider_count'] = [int]$providerCount
$summaryMap['request_kinds'] = [object[]]@($requestKinds)
$summaryMap['signal_summary'] = $signalSummary
$summaryMap['errors'] = if ($runErrors.Count -gt 0) { [object[]]$runErrors.ToArray() } else { @() }
$summary = New-Object PSObject -Property $summaryMap

$summaryPath = Join-Path $resolvedOutputDir 'summary.json'
$transcriptPath = Join-Path $resolvedOutputDir 'transcript.md'

Write-JsonNoBom -PathValue $summaryPath -Payload $summary -Depth 20

$transcriptLines = New-Object System.Collections.Generic.List[string]
$transcriptLines.Add('# TOD Stale Recovery Direct Run') | Out-Null
$transcriptLines.Add('') | Out-Null
$transcriptLines.Add(('Generated at: {0}' -f $summary.generated_at)) | Out-Null
$transcriptLines.Add(('Prompt count: {0}' -f $summary.prompt_count)) | Out-Null
$transcriptLines.Add(('Local conversation provider replies: {0}' -f $summary.local_conversation_provider_count)) | Out-Null
$transcriptLines.Add(('Bounded fallback replies: {0}' -f $summary.bounded_fallback_count)) | Out-Null
$transcriptLines.Add('') | Out-Null

foreach ($result in $results) {
    $resultSource = if ($result.PSObject.Properties['source']) { [string]$result.source } else { 'error' }
    $transcriptLines.Add(('## {0}. {1}' -f [string]$result.task_number, [string]$result.title)) | Out-Null
    $transcriptLines.Add('') | Out-Null
    $transcriptLines.Add(('Source: {0}' -f $resultSource)) | Out-Null
    $transcriptLines.Add('') | Out-Null
    $transcriptLines.Add('Prompt:') | Out-Null
    $transcriptLines.Add([string]$result.prompt) | Out-Null
    $transcriptLines.Add('') | Out-Null
    if ($result.PSObject.Properties['reply_text']) {
        $transcriptLines.Add('Reply:') | Out-Null
        $transcriptLines.Add([string]$result.reply_text) | Out-Null
    }
    else {
        $transcriptLines.Add(('Error: {0}' -f [string]$result.error)) | Out-Null
    }
    $transcriptLines.Add('') | Out-Null
}

[System.IO.File]::WriteAllLines($transcriptPath, $transcriptLines, (New-Object System.Text.UTF8Encoding($false)))

$summary | ConvertTo-Json -Depth 20