Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$baseUrl = 'http://localhost:8844'
$sweepArtifactScript = Join-Path $repoRoot 'scripts/Test-TODOperatorChatSweepArtifact.ps1'

function Test-TodUiReachable {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/project-status" -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-FileLengthOrZero {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return 0L
    }

    return [int64](Get-Item -Path $Path).Length
}

Describe 'Operator chat ArtifactOnly sweep' {
    It 'stays bounded and emits the expected artifact contract' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $outputDir = Join-Path $repoRoot 'tod/out/tests/operator-chat-artifact-only'
        if (-not (Test-Path -Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $rawArtifactPath = Join-Path $outputDir 'artifact-only-raw.latest.json'
        $summaryArtifactPath = Join-Path $outputDir 'artifact-only-summary.latest.json'
        $reportPath = Join-Path $outputDir 'artifact-only-report.latest.json'

        foreach ($path in @($rawArtifactPath, $summaryArtifactPath, $reportPath)) {
            if (Test-Path -Path $path -PathType Leaf) {
                Remove-Item -Path $path -Force
            }
        }

        $auditLogPath = Join-Path $repoRoot 'shared_state/tod_operator_chat_action_audit.log.jsonl'
        $commitmentLogPath = Join-Path $repoRoot 'shared_state/tod_operator_chat_commitment.log.jsonl'
        $reasoningLogPath = Join-Path $repoRoot 'shared_state/tod_operator_chat_reasoning.log.jsonl'
        $feedbackLogPath = Join-Path $repoRoot 'shared_state/tod_operator_chat_feedback.log.jsonl'

        $auditLengthBefore = Get-FileLengthOrZero -Path $auditLogPath
        $commitmentLengthBefore = Get-FileLengthOrZero -Path $commitmentLogPath
        $reasoningLengthBefore = Get-FileLengthOrZero -Path $reasoningLogPath
        $feedbackLengthBefore = Get-FileLengthOrZero -Path $feedbackLogPath

        $result = & $sweepArtifactScript -RawArtifactPath $rawArtifactPath -IneffectiveSummaryPath $summaryArtifactPath -OutputPath $reportPath -WaitTimeoutSeconds 120 -ArtifactFreshnessSeconds 120 -EmitJson | ConvertFrom-Json

        $auditLengthAfter = Get-FileLengthOrZero -Path $auditLogPath
        $commitmentLengthAfter = Get-FileLengthOrZero -Path $commitmentLogPath
        $reasoningLengthAfter = Get-FileLengthOrZero -Path $reasoningLogPath
        $feedbackLengthAfter = Get-FileLengthOrZero -Path $feedbackLogPath

        $result.summary.passed_all | Should Be $true
        [int]$result.summary.failed | Should Be 0
        [string]$result.summary.exit_code | Should Be '0'
        [bool](Test-Path -Path $rawArtifactPath -PathType Leaf) | Should Be $true
        [bool](Test-Path -Path $summaryArtifactPath -PathType Leaf) | Should Be $true
        [bool](Test-Path -Path $reportPath -PathType Leaf) | Should Be $true
        [string]$result.sweep_process.timed_out | Should Be 'False'
        [double]$result.sweep_process.elapsed_seconds | Should BeLessThan 120

        $rawPayload = Get-Content -Path $rawArtifactPath -Raw | ConvertFrom-Json
        $summaryPayload = Get-Content -Path $summaryArtifactPath -Raw | ConvertFrom-Json

        [string]$rawPayload.source | Should Be 'tod-operator-chat-sweep-early-artifact-v1'
        [bool]$rawPayload.stable_contract.operator_chat_queries_ok | Should Be $true
        [bool]$rawPayload.stable_contract.governed_actions_ok | Should Be $true
        [bool]$rawPayload.stable_contract.audit_ok | Should Be $true
        [bool]$rawPayload.stable_contract.reasoning_ok | Should Be $true
        [bool]$rawPayload.stable_contract.commitments_ok | Should Be $true
        [bool]$summaryPayload.stable_contract_ok | Should Be $true
        [string]$summaryPayload.ineffective_terminal_state | Should Be 'ineffective'
        [string]$summaryPayload.ineffective_lifecycle_status | Should Be 'ineffective'
        [string]$summaryPayload.ineffective_followup_action | Should Be 'refresh-governance-snapshot'

        $auditLengthAfter | Should Be $auditLengthBefore
        $commitmentLengthAfter | Should Be $commitmentLengthBefore
        $reasoningLengthAfter | Should Be $reasoningLengthBefore
        $feedbackLengthAfter | Should Be $feedbackLengthBefore
    }
}