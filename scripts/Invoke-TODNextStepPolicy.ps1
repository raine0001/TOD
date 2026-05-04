param(
    [string]$ConsensusPath = 'shared_state/NEXT_STEP_CONSENSUS.latest.json',
    [string]$OutputPath = 'shared_state/NEXT_STEP_POLICY.latest.json',
    [int]$PendingConsensusTimeoutMinutes = 5
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

$resolvedConsensusPath = Get-LocalPath -PathValue $ConsensusPath
if (-not (Test-Path -Path $resolvedConsensusPath)) {
    throw "ConsensusPath not found: $resolvedConsensusPath"
}

$consensus = Get-Content -Path $resolvedConsensusPath -Raw | ConvertFrom-Json
$selectedFinding = @($consensus.findings | Where-Object { [string]$_.finding.finding_id -eq [string]$consensus.consensus.selected_finding_id } | Select-Object -First 1)[0]

$status = [string]$consensus.status
$recommendation = 'No action selected.'
if ($selectedFinding) {
    $recommendation = [string]$selectedFinding.finding.description
}

$consensusGeneratedAtRaw = if ($consensus.PSObject.Properties['generated_at']) { [string]$consensus.generated_at } else { '' }
$consensusGeneratedAt = $null
if (-not [string]::IsNullOrWhiteSpace($consensusGeneratedAtRaw)) {
    try {
        $consensusGeneratedAt = [datetime]::Parse($consensusGeneratedAtRaw, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        $consensusGeneratedAt = $null
    }
}

$pendingConsensusTimedOut = $false
$pendingConsensusAgeMinutes = 0.0
if ($consensusGeneratedAt) {
    $pendingConsensusAgeMinutes = [math]::Round(((Get-Date).ToUniversalTime() - $consensusGeneratedAt.ToUniversalTime()).TotalMinutes, 2)
}
if ([string]::Equals($status, 'pending_mim', [System.StringComparison]::OrdinalIgnoreCase) -and $consensusGeneratedAt -and $pendingConsensusAgeMinutes -ge $PendingConsensusTimeoutMinutes) {
    $pendingConsensusTimedOut = $true
}

$continuationRoute = 'tod_local_follow_through'
$operatorPromptAllowed = $false
$continuationDecision = 'continue'
$continuationReason = 'TOD may continue with the selected bounded next step without asking the operator.'
if ([string]::Equals($status, 'pending_mim', [System.StringComparison]::OrdinalIgnoreCase)) {
    if ($pendingConsensusTimedOut) {
        $continuationRoute = 'tod_local_provisional_follow_through'
        $continuationDecision = 'proceed_with_local_decision'
        $continuationReason = 'TOD/MIM consensus exceeded the timeout threshold, so TOD should proceed with a provisional local decision instead of preserving deadlock.'
    }
    else {
        $continuationRoute = 'tod_executes_under_open_mim_dialog'
        $continuationDecision = 'proceed_while_mim_dialog_open'
        $continuationReason = 'TOD published its position and continues under the best supported next step while the TOD-MIM dialog remains open; operator prompts stay disabled.'
    }
}

$policy = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-next-step-policy-v2'
    contract_version = 'tod-next-step-policy-v2'
    consensus_path = $resolvedConsensusPath
    status = $status
    selected_finding_id = if ($selectedFinding) { [string]$selectedFinding.finding.finding_id } else { '' }
    recommended_action = $recommendation
    execution_policy = if ($consensus.PSObject.Properties['consensus']) { $consensus.consensus.execution_policy } else { [pscustomobject]@{ class = 'none'; applied = $false; applied_reason = 'missing_consensus_execution_policy' } }
    applied = $true
    applied_reason = if ($pendingConsensusTimedOut) { 'pending_consensus_timeout_provisional_local_decision' } else { 'continue_execution_while_mim_dialog_open' }
    provisional = $pendingConsensusTimedOut
    pending_consensus_timeout_minutes = $PendingConsensusTimeoutMinutes
    pending_consensus_age_minutes = $pendingConsensusAgeMinutes
    continuation = [pscustomobject]@{
        decision = $continuationDecision
        route = $continuationRoute
        operator_prompt_allowed = $operatorPromptAllowed
        reason = $continuationReason
        mim_session_id = if ($consensus.PSObject.Properties['mim_position'] -and $consensus.mim_position -and $consensus.mim_position.PSObject.Properties['session_id']) { [string]$consensus.mim_position.session_id } else { '' }
    }
}

$resolvedOutputPath = Get-LocalPath -PathValue $OutputPath
Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $policy -Depth 20

[pscustomobject]@{
    ok = $true
    output_path = $resolvedOutputPath
    policy = $policy
} | ConvertTo-Json -Depth 20