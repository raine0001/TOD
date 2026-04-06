param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [string]$ObjectiveId = '',
    [Parameter(Mandatory = $true)][string]$ResultJsonPath,
    [string]$ReviewDecision = '',
    [string]$ReviewRationale = '',
    [string]$LoopDecision = '',
    [string]$Workspace = 'TOD',
    [string]$SourceRun = 'codex_task_loop',
    [string]$RunId = '',
    [string]$OutputPath = 'shared_state/tod_codex_next_steps.latest.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-ParentDirectoryForFile {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    Ensure-ParentDirectoryForFile -FilePath $PathValue
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Convert-ToStringArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @([string]$Value)
    }

    return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-ActionTypeFromText {
    param([string]$Text)

    $value = ([string]$Text).ToLowerInvariant()
    if ($value -match 'validat|smoke|regression|verify|check|test') { return 'validate' }
    if ($value -match 'cleanup|retire|remove|dedup|normalize') { return 'cleanup' }
    if ($value -match 'refresh|rebuild|republish|sync') { return 'refresh' }
    if ($value -match 'repair|fix|resolve|correct') { return 'repair' }
    if ($value -match 'observe|inspect|review|audit') { return 'observe' }
    if ($value -match 'promote|release|deploy') { return 'promote' }
    return 'repair'
}

function Get-OwnerWorkspaceFromText {
    param([string]$Text)

    $value = ([string]$Text).ToLowerInvariant()
    if ($value -match 'mim' -and $value -notmatch 'tod') { return 'MIM' }
    if ($value -match 'shared|cross-system|coordination|consensus') { return 'SHARED' }
    return 'TOD'
}

function Get-RiskFromAction {
    param(
        [string]$ActionType,
        [string]$Text
    )

    $value = ([string]$Text).ToLowerInvariant()
    if ($value -match 'live motion|mim_arm|production|restart|restarts|deploy|promotion') { return 'high' }
    if ($ActionType -in @('cleanup', 'repair', 'promote')) { return 'medium' }
    return 'low'
}

function Test-ApprovalRequired {
    param(
        [string]$ActionType,
        [string]$Text
    )

    $value = ([string]$Text).ToLowerInvariant()
    if ($value -match 'approval|approve') { return $true }
    if ($value -match 'mim_arm|live motion|production|restart|deploy|promotion') { return $true }
    return ($ActionType -eq 'promote')
}

function Test-NeedsRemoteInput {
    param(
        [string]$OwnerWorkspace,
        [string]$Text
    )

    $value = ([string]$Text).ToLowerInvariant()
    if ($OwnerWorkspace -ne 'TOD') { return $true }
    return ($value -match 'mim|shared|remote|bridge|listener|ack|result|cross-system|consensus')
}

function Normalize-Finding {
    param(
        [Parameter(Mandatory = $true)]$Finding,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$TaskIdValue
    )

    $description = if ($Finding.PSObject.Properties['description']) { [string]$Finding.description } else { '' }
    if ([string]::IsNullOrWhiteSpace($description) -and $Finding.PSObject.Properties['summary']) {
        $description = [string]$Finding.summary
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = "Structured finding $Index"
    }

    $actionType = if ($Finding.PSObject.Properties['action_type'] -and -not [string]::IsNullOrWhiteSpace([string]$Finding.action_type)) {
        [string]$Finding.action_type
    }
    else {
        Get-ActionTypeFromText -Text $description
    }

    $ownerWorkspace = if ($Finding.PSObject.Properties['owner_workspace'] -and -not [string]::IsNullOrWhiteSpace([string]$Finding.owner_workspace)) {
        ([string]$Finding.owner_workspace).ToUpperInvariant()
    }
    else {
        Get-OwnerWorkspaceFromText -Text $description
    }

    $risk = if ($Finding.PSObject.Properties['risk'] -and -not [string]::IsNullOrWhiteSpace([string]$Finding.risk)) {
        ([string]$Finding.risk).ToLowerInvariant()
    }
    else {
        Get-RiskFromAction -ActionType $actionType -Text $description
    }

    $confidence = 0.65
    if ($Finding.PSObject.Properties['confidence'] -and $null -ne $Finding.confidence) {
        try {
            $confidence = [double]$Finding.confidence
        }
        catch {
            $confidence = 0.65
        }
    }

    [pscustomobject]@{
        finding_id = if ($Finding.PSObject.Properties['finding_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Finding.finding_id)) {
            [string]$Finding.finding_id
        }
        else {
            "{0}-finding-{1:000}" -f $TaskIdValue, $Index
        }
        type = if ($Finding.PSObject.Properties['type']) { [string]$Finding.type } else { 'implementation_candidate' }
        description = $description
        owner_workspace = $ownerWorkspace
        action_type = $actionType
        needs_remote_input = if ($Finding.PSObject.Properties['needs_remote_input']) { [bool]$Finding.needs_remote_input } else { (Test-NeedsRemoteInput -OwnerWorkspace $ownerWorkspace -Text $description) }
        needs_cross_system_consensus = if ($Finding.PSObject.Properties['needs_cross_system_consensus']) { [bool]$Finding.needs_cross_system_consensus } else { $true }
        approval_required = if ($Finding.PSObject.Properties['approval_required']) { [bool]$Finding.approval_required } else { (Test-ApprovalRequired -ActionType $actionType -Text $description) }
        confidence = [math]::Round([math]::Max(0.0, [math]::Min(1.0, $confidence)), 2)
        risk = $risk
        blocking_dependencies = @(Convert-ToStringArray -Value $(if ($Finding.PSObject.Properties['blocking_dependencies']) { $Finding.blocking_dependencies } else { @() }))
        recommended_executor = if ($Finding.PSObject.Properties['recommended_executor'] -and -not [string]::IsNullOrWhiteSpace([string]$Finding.recommended_executor)) {
            [string]$Finding.recommended_executor
        }
        elseif ($ownerWorkspace -eq 'MIM') {
            'mim.local'
        }
        elseif ($ownerWorkspace -eq 'SHARED') {
            'shared.consensus'
        }
        else {
            'tod.local'
        }
        source = if ($Finding.PSObject.Properties['source']) { [string]$Finding.source } else { 'engine_structured_finding' }
    }
}

function Convert-RecommendationToFinding {
    param(
        [Parameter(Mandatory = $true)][string]$Recommendation,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][string]$TaskIdValue
    )

    $actionType = Get-ActionTypeFromText -Text $Recommendation
    $ownerWorkspace = Get-OwnerWorkspaceFromText -Text $Recommendation
    [pscustomobject]@{
        finding_id = "{0}-finding-{1:000}" -f $TaskIdValue, $Index
        type = 'recommendation_fallback'
        description = $Recommendation
        owner_workspace = $ownerWorkspace
        action_type = $actionType
        needs_remote_input = Test-NeedsRemoteInput -OwnerWorkspace $ownerWorkspace -Text $Recommendation
        needs_cross_system_consensus = $true
        approval_required = Test-ApprovalRequired -ActionType $actionType -Text $Recommendation
        confidence = 0.62
        risk = Get-RiskFromAction -ActionType $actionType -Text $Recommendation
        blocking_dependencies = @()
        recommended_executor = if ($ownerWorkspace -eq 'MIM') { 'mim.local' } elseif ($ownerWorkspace -eq 'SHARED') { 'shared.consensus' } else { 'tod.local' }
        source = 'result_recommendation_fallback'
    }
}

$resolvedResultPath = Get-LocalPath -PathValue $ResultJsonPath
if (-not (Test-Path -Path $resolvedResultPath)) {
    throw "ResultJsonPath not found: $resolvedResultPath"
}

$result = Get-Content -Path $resolvedResultPath -Raw | ConvertFrom-Json
$resolvedOutputPath = Get-LocalPath -PathValue $OutputPath

$effectiveRunId = if ([string]::IsNullOrWhiteSpace($RunId)) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    "tod-codex-run-{0}-{1}" -f $TaskId, $stamp
}
else {
    [string]$RunId
}

$findings = @()
$structuredFindings = if ($result.PSObject.Properties['structured_findings']) { @($result.structured_findings) } else { @() }
if (@($structuredFindings).Count -gt 0) {
    $index = 1
    foreach ($finding in @($structuredFindings)) {
        $findings += (Normalize-Finding -Finding $finding -Index $index -TaskIdValue $TaskId)
        $index += 1
    }
}
else {
    $index = 1
    foreach ($recommendation in @(Convert-ToStringArray -Value $result.recommendations)) {
        $findings += (Convert-RecommendationToFinding -Recommendation ([string]$recommendation) -Index $index -TaskIdValue $TaskId)
        $index += 1
    }
}

if ((@($findings).Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($ReviewDecision) -and ($ReviewDecision -ne 'pass')) {
    $findings += [pscustomobject]@{
        finding_id = "{0}-finding-001" -f $TaskId
        type = 'review_blocker'
        description = if ([string]::IsNullOrWhiteSpace($ReviewRationale)) { 'Review produced unresolved issues that require bounded follow-up.' } else { [string]$ReviewRationale }
        owner_workspace = 'TOD'
        action_type = 'repair'
        needs_remote_input = $false
        needs_cross_system_consensus = $true
        approval_required = $false
        confidence = 0.71
        risk = 'medium'
        blocking_dependencies = @()
        recommended_executor = 'tod.local'
        source = 'review_fallback'
    }
}

$artifact = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-codex-next-steps-v1'
    contract_version = 'tod-codex-next-steps-v1'
    run_id = $effectiveRunId
    source_run = $SourceRun
    workspace = ([string]$Workspace).ToUpperInvariant()
    objective_id = [string]$ObjectiveId
    task_id = [string]$TaskId
    summary = if ($result.PSObject.Properties['summary']) { [string]$result.summary } else { '' }
    review = [pscustomobject]@{
        decision = [string]$ReviewDecision
        rationale = [string]$ReviewRationale
        loop_decision = [string]$LoopDecision
    }
    result_artifact = [pscustomobject]@{
        path = $resolvedResultPath
        engine = if ($result.PSObject.Properties['engine']) { $result.engine } else { $null }
        recommendations_count = [int]@(Convert-ToStringArray -Value $result.recommendations).Count
        failures_count = [int]@(Convert-ToStringArray -Value $result.failures).Count
    }
    findings = @($findings)
}

Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $artifact -Depth 20

[pscustomobject]@{
    ok = $true
    output_path = $resolvedOutputPath
    finding_count = [int]@($findings).Count
    artifact = $artifact
} | ConvertTo-Json -Depth 20