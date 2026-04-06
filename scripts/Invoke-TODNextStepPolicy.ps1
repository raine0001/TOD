param(
    [string]$ConsensusPath = 'shared_state/NEXT_STEP_CONSENSUS.latest.json',
    [string]$OutputPath = 'shared_state/NEXT_STEP_POLICY.latest.json'
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

$policy = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-next-step-policy-v1'
    contract_version = 'tod-next-step-policy-v1'
    consensus_path = $resolvedConsensusPath
    status = $status
    selected_finding_id = if ($selectedFinding) { [string]$selectedFinding.finding.finding_id } else { '' }
    recommended_action = $recommendation
    execution_policy = if ($consensus.PSObject.Properties['consensus']) { $consensus.consensus.execution_policy } else { [pscustomobject]@{ class = 'none'; applied = $false; applied_reason = 'missing_consensus_execution_policy' } }
    applied = $false
    applied_reason = 'phase1_recommendation_only'
}

$resolvedOutputPath = Get-LocalPath -PathValue $OutputPath
Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $policy -Depth 20

[pscustomobject]@{
    ok = $true
    output_path = $resolvedOutputPath
    policy = $policy
} | ConvertTo-Json -Depth 20