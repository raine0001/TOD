param(
    [string]$PolicyDocPath = 'docs/tod-mim-communication-policy-authority-2026-04-01.md',
    [string]$AuditDocPath = 'docs/tod-mim-communication-audit-2026-04-01.md',
    [string]$FeedbackContractPath = 'docs/mim-tod-execution-feedback-contract-v1.md',
    [string]$ExecutionGateArtifactPath = 'tod/out/results-v2/tod-mim-execution-contract.latest.json',
    [string]$ListenerStageDir = 'tod/out/context-sync/listener',
    [string]$OutputPath = 'tod/out/results-v2/tod-mim-execution-parity.latest.json',
    [switch]$SkipExecutionGateRefresh,
    [switch]$FailOnMismatch,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Read-TextFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return $null
    }

    return [string](Get-Content -Path $PathValue -Raw)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function New-CheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Message,
        [AllowNull()]$Detail = $null
    )

    return [pscustomobject]@{
        code = $Code
        area = $Area
        passed = $Passed
        severity = $Severity
        message = $Message
        detail = $Detail
    }
}

function Test-TextContainsAll {
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory = $true)][string[]]$RequiredSnippets
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @($RequiredSnippets)
    }

    $missing = @()
    foreach ($snippet in $RequiredSnippets) {
        if (-not $Text.Contains($snippet)) {
            $missing += $snippet
        }
    }
    return @($missing)
}

function Test-ObjectHasProperties {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$RequiredProperties
    )

    $missing = @()
    if ($null -eq $InputObject) {
        return @($RequiredProperties)
    }

    foreach ($property in $RequiredProperties) {
        if (-not $InputObject.PSObject.Properties[$property]) {
            $missing += $property
        }
    }

    return @($missing)
}

function Get-ObjectFieldText {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return ''
    }

    return [string]$InputObject.$FieldName
}

function Get-ObjectFieldLong {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$FieldName]) {
        return $null
    }

    try {
        return [long]$InputObject.$FieldName
    }
    catch {
        return $null
    }
}

$resolvedPolicyDocPath = Resolve-LocalPath -PathValue $PolicyDocPath
$resolvedAuditDocPath = Resolve-LocalPath -PathValue $AuditDocPath
$resolvedFeedbackContractPath = Resolve-LocalPath -PathValue $FeedbackContractPath
$resolvedExecutionGateArtifactPath = Resolve-LocalPath -PathValue $ExecutionGateArtifactPath
$resolvedListenerStageDir = Resolve-LocalPath -PathValue $ListenerStageDir
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

$executionGateScriptPath = Join-Path $PSScriptRoot 'Invoke-TODMimExecutionContractGate.ps1'
if ((-not $SkipExecutionGateRefresh) -and -not (Test-Path -Path $resolvedExecutionGateArtifactPath -PathType Leaf) -and (Test-Path -Path $executionGateScriptPath -PathType Leaf)) {
    try {
        $null = & $executionGateScriptPath -OutputPath $ExecutionGateArtifactPath -FailOnFailure -EmitJson
    }
    catch {
    }
}

$canonicalInboundArtifacts = @(
    'MIM_TOD_TASK_REQUEST.latest.json',
    'MIM_TO_TOD_TRIGGER.latest.json',
    'MIM_TOD_GO_ORDER.latest.json',
    'MIM_TOD_REVIEW_DECISION.latest.json'
)

$canonicalOutboundArtifacts = @(
    'TOD_TO_MIM_TRIGGER_ACK.latest.json',
    'TOD_MIM_TASK_ACK.latest.json',
    'TOD_MIM_TASK_RESULT.latest.json'
)

$requiredGateCoverage = @(
    'request accepted once',
    'trigger ACK emitted once',
    'task ACK emitted once',
    'terminal RESULT emitted once',
    'duplicate semantic request deduplication',
    'stale backfill rejection',
    'superseded request handling',
    'wrong-target rejection'
)

$checks = @()

$policyDocText = Read-TextFile -PathValue $resolvedPolicyDocPath
if ($null -eq $policyDocText) {
    $checks += New-CheckResult -Code 'policy_doc_missing' -Area 'documents' -Passed $false -Severity 'error' -Message 'Policy authority document is missing.' -Detail $resolvedPolicyDocPath
}
else {
    $policyMissingArtifacts = Test-TextContainsAll -Text $policyDocText -RequiredSnippets ($canonicalInboundArtifacts + $canonicalOutboundArtifacts)
    $checks += New-CheckResult -Code 'policy_doc_artifacts' -Area 'documents' -Passed (@($policyMissingArtifacts).Count -eq 0) -Severity 'error' -Message 'Policy authority document lists the canonical listener-stage execution artifacts.' -Detail ([pscustomobject]@{ missing = @($policyMissingArtifacts) })

    $policySemanticMissing = Test-TextContainsAll -Text $policyDocText -RequiredSnippets @(
        'ACK does not prove terminal completion.',
        'TOD must emit one terminal result per bounded attempt.',
        'Deduplicate duplicate semantic requests.'
    )
    $checks += New-CheckResult -Code 'policy_doc_semantics' -Area 'documents' -Passed (@($policySemanticMissing).Count -eq 0) -Severity 'error' -Message 'Policy authority document still encodes ACK/result and duplicate-request semantics.' -Detail ([pscustomobject]@{ missing = @($policySemanticMissing) })
}

$auditDocText = Read-TextFile -PathValue $resolvedAuditDocPath
if ($null -eq $auditDocText) {
    $checks += New-CheckResult -Code 'audit_doc_missing' -Area 'documents' -Passed $false -Severity 'error' -Message 'Communication audit document is missing.' -Detail $resolvedAuditDocPath
}
else {
    $auditMissing = Test-TextContainsAll -Text $auditDocText -RequiredSnippets @(
        'listener-stage execution contract',
        'Canonical Communication Method',
        'TOD_MIM_TASK_ACK.latest.json',
        'TOD_MIM_TASK_RESULT.latest.json',
        'TOD_TO_MIM_TRIGGER_ACK.latest.json'
    )
    $checks += New-CheckResult -Code 'audit_doc_matrix' -Area 'documents' -Passed (@($auditMissing).Count -eq 0) -Severity 'error' -Message 'Audit/matrix document still describes the same listener execution lane.' -Detail ([pscustomobject]@{ missing = @($auditMissing) })
}

$feedbackContractText = Read-TextFile -PathValue $resolvedFeedbackContractPath
if ($null -eq $feedbackContractText) {
    $checks += New-CheckResult -Code 'feedback_contract_missing' -Area 'documents' -Passed $false -Severity 'error' -Message 'Execution feedback contract document is missing.' -Detail $resolvedFeedbackContractPath
}
else {
    $feedbackMissing = Test-TextContainsAll -Text $feedbackContractText -RequiredSnippets @(
        'ACK must echo the same live request identity',
        'Result must reference that same request identity',
        'If MIM wants a real retry after a failed terminal result, it must issue a new request identity.'
    )
    $checks += New-CheckResult -Code 'feedback_contract_semantics' -Area 'documents' -Passed (@($feedbackMissing).Count -eq 0) -Severity 'error' -Message 'Execution feedback contract still matches live request-identity and retry expectations.' -Detail ([pscustomobject]@{ missing = @($feedbackMissing) })
}

$executionGateArtifact = Read-JsonFile -PathValue $resolvedExecutionGateArtifactPath
if ($null -eq $executionGateArtifact) {
    $checks += New-CheckResult -Code 'execution_gate_artifact_missing' -Area 'gate_artifact' -Passed $false -Severity 'error' -Message 'Execution contract gate artifact is missing or unreadable.' -Detail $resolvedExecutionGateArtifactPath
}
else {
    $gatePassed = $false
    if ($executionGateArtifact.PSObject.Properties['summary'] -and $executionGateArtifact.summary -and $executionGateArtifact.summary.PSObject.Properties['gate_passed']) {
        $gatePassed = [bool]$executionGateArtifact.summary.gate_passed
    }
    $checks += New-CheckResult -Code 'execution_gate_green' -Area 'gate_artifact' -Passed $gatePassed -Severity 'error' -Message 'Execution contract gate artifact reports a green baseline.' -Detail ([pscustomobject]@{ artifact = $resolvedExecutionGateArtifactPath })

    $contractLane = if ($executionGateArtifact.PSObject.Properties['scope'] -and $executionGateArtifact.scope -and $executionGateArtifact.scope.PSObject.Properties['contract_lane']) { [string]$executionGateArtifact.scope.contract_lane } else { '' }
    $checks += New-CheckResult -Code 'execution_gate_scope' -Area 'gate_artifact' -Passed ([string]::Equals($contractLane, 'listener_execution_only', [System.StringComparison]::OrdinalIgnoreCase)) -Severity 'error' -Message 'Execution contract gate artifact is still scoped only to the listener execution lane.' -Detail ([pscustomobject]@{ actual = $contractLane })

    $includedCoverage = @()
    if ($executionGateArtifact.PSObject.Properties['coverage'] -and $executionGateArtifact.coverage -and $executionGateArtifact.coverage.PSObject.Properties['included']) {
        $includedCoverage = @($executionGateArtifact.coverage.included | ForEach-Object { [string]$_ })
    }
    $coverageMissing = @($requiredGateCoverage | Where-Object { @($includedCoverage) -notcontains [string]$_ })
    $checks += New-CheckResult -Code 'execution_gate_coverage' -Area 'gate_artifact' -Passed (@($coverageMissing).Count -eq 0) -Severity 'error' -Message 'Execution contract gate coverage still matches the expected drift-sensitive semantics.' -Detail ([pscustomobject]@{ missing = @($coverageMissing) })
}

$requestPacket = Read-JsonFile -PathValue (Join-Path $resolvedListenerStageDir 'MIM_TOD_TASK_REQUEST.latest.json')
if ($null -eq $requestPacket) {
    $checks += New-CheckResult -Code 'live_request_surface_missing' -Area 'live_surfaces' -Passed $false -Severity 'warning' -Message 'Live request surface is not present; request-shape parity was skipped.' -Detail (Join-Path $resolvedListenerStageDir 'MIM_TOD_TASK_REQUEST.latest.json')
}
else {
    $requestMissing = Test-ObjectHasProperties -InputObject $requestPacket -RequiredProperties @('objective_id', 'target')
    $hasRequestIdentity = (-not [string]::IsNullOrWhiteSpace((Get-ObjectFieldText -InputObject $requestPacket -FieldName 'request_id'))) -or (-not [string]::IsNullOrWhiteSpace((Get-ObjectFieldText -InputObject $requestPacket -FieldName 'task_id')))
    $hasActionField = (-not [string]::IsNullOrWhiteSpace((Get-ObjectFieldText -InputObject $requestPacket -FieldName 'tod_action'))) -or (-not [string]::IsNullOrWhiteSpace((Get-ObjectFieldText -InputObject $requestPacket -FieldName 'action')))
    $hasDescriptiveIntent = (-not [string]::IsNullOrWhiteSpace((Get-ObjectFieldText -InputObject $requestPacket -FieldName 'title'))) -or (-not [string]::IsNullOrWhiteSpace((Get-ObjectFieldText -InputObject $requestPacket -FieldName 'scope'))) -or ($requestPacket.PSObject.Properties['acceptance_criteria'] -and @($requestPacket.acceptance_criteria).Count -gt 0)
    $checks += New-CheckResult -Code 'live_request_surface_shape' -Area 'live_surfaces' -Passed ((@($requestMissing).Count -eq 0) -and $hasRequestIdentity -and ($hasActionField -or $hasDescriptiveIntent)) -Severity 'warning' -Message 'Live request packet still exposes identity, target, objective, and executable intent fields.' -Detail ([pscustomobject]@{ missing = @($requestMissing); has_identity = $hasRequestIdentity; has_action = $hasActionField; has_descriptive_intent = $hasDescriptiveIntent })
}

$triggerAckPacket = Read-JsonFile -PathValue (Join-Path $resolvedListenerStageDir 'TOD_TO_MIM_TRIGGER_ACK.latest.json')
if ($null -eq $triggerAckPacket) {
    $checks += New-CheckResult -Code 'live_trigger_ack_surface_missing' -Area 'live_surfaces' -Passed $false -Severity 'warning' -Message 'Live trigger ACK surface is not present; trigger-ACK parity was skipped.' -Detail (Join-Path $resolvedListenerStageDir 'TOD_TO_MIM_TRIGGER_ACK.latest.json')
}
else {
    $triggerAckMissing = Test-ObjectHasProperties -InputObject $triggerAckPacket -RequiredProperties @('source', 'status', 'acknowledges', 'ack_sequence', 'acknowledged_trigger_sequence')
    $triggerAckStatus = Get-ObjectFieldText -InputObject $triggerAckPacket -FieldName 'status'
    $triggerAckSource = Get-ObjectFieldText -InputObject $triggerAckPacket -FieldName 'source'
    $checks += New-CheckResult -Code 'live_trigger_ack_surface_shape' -Area 'live_surfaces' -Passed ((@($triggerAckMissing).Count -eq 0) -and [string]::Equals($triggerAckStatus, 'acknowledged', [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($triggerAckSource, 'shared-trigger-ack-v1', [System.StringComparison]::OrdinalIgnoreCase)) -Severity 'warning' -Message 'Live trigger ACK surface still advertises receipt semantics and trigger linkage.' -Detail ([pscustomobject]@{ missing = @($triggerAckMissing); status = $triggerAckStatus; source = $triggerAckSource })
}

$taskAckPacket = Read-JsonFile -PathValue (Join-Path $resolvedListenerStageDir 'TOD_MIM_TASK_ACK.latest.json')
if ($null -eq $taskAckPacket) {
    $checks += New-CheckResult -Code 'live_task_ack_surface_missing' -Area 'live_surfaces' -Passed $false -Severity 'warning' -Message 'Live task ACK surface is not present; task-ACK parity was skipped.' -Detail (Join-Path $resolvedListenerStageDir 'TOD_MIM_TASK_ACK.latest.json')
}
else {
    $taskAckMissing = Test-ObjectHasProperties -InputObject $taskAckPacket -RequiredProperties @('source', 'request_id', 'task_id', 'status', 'ack_sequence', 'acknowledged_trigger_sequence')
    $taskAckStatus = Get-ObjectFieldText -InputObject $taskAckPacket -FieldName 'status'
    $taskAckSource = Get-ObjectFieldText -InputObject $taskAckPacket -FieldName 'source'
    $taskAckStatusOk = @('accepted', 'deferred_waiting_go_order') -contains $taskAckStatus.ToLowerInvariant()
    $checks += New-CheckResult -Code 'live_task_ack_surface_shape' -Area 'live_surfaces' -Passed ((@($taskAckMissing).Count -eq 0) -and $taskAckStatusOk -and [string]::Equals($taskAckSource, 'tod-mim-task-ack-v1', [System.StringComparison]::OrdinalIgnoreCase)) -Severity 'warning' -Message 'Live task ACK surface still exposes execution-acceptance semantics.' -Detail ([pscustomobject]@{ missing = @($taskAckMissing); status = $taskAckStatus; source = $taskAckSource })
}

$resultPacket = Read-JsonFile -PathValue (Join-Path $resolvedListenerStageDir 'TOD_MIM_TASK_RESULT.latest.json')
if ($null -eq $resultPacket) {
    $checks += New-CheckResult -Code 'live_result_surface_missing' -Area 'live_surfaces' -Passed $false -Severity 'warning' -Message 'Live result surface is not present; result-shape parity was skipped.' -Detail (Join-Path $resolvedListenerStageDir 'TOD_MIM_TASK_RESULT.latest.json')
}
else {
    $resultMissing = Test-ObjectHasProperties -InputObject $resultPacket -RequiredProperties @('source', 'request_id', 'task_id', 'status', 'action', 'ack_sequence', 'acknowledged_trigger_sequence')
    $resultStatus = Get-ObjectFieldText -InputObject $resultPacket -FieldName 'status'
    $resultSource = Get-ObjectFieldText -InputObject $resultPacket -FieldName 'source'
    $resultStatusOk = @('completed', 'failed', 'blocked', 'stale_request_ignored', 'already_processed') -contains $resultStatus.ToLowerInvariant()
    $checks += New-CheckResult -Code 'live_result_surface_shape' -Area 'live_surfaces' -Passed ((@($resultMissing).Count -eq 0) -and $resultStatusOk -and [string]::Equals($resultSource, 'tod-mim-task-result-v1', [System.StringComparison]::OrdinalIgnoreCase)) -Severity 'warning' -Message 'Live result surface still exposes terminal bounded-execution semantics.' -Detail ([pscustomobject]@{ missing = @($resultMissing); status = $resultStatus; source = $resultSource })
}

$errorChecks = @($checks | Where-Object { -not [bool]$_.passed -and [string]::Equals([string]$_.severity, 'error', [System.StringComparison]::OrdinalIgnoreCase) })
$warningChecks = @($checks | Where-Object { -not [bool]$_.passed -and [string]::Equals([string]$_.severity, 'warning', [System.StringComparison]::OrdinalIgnoreCase) })

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-execution-parity-check-v1'
    compatible = (@($errorChecks).Count -eq 0)
    mismatch_count = @($errorChecks).Count
    warning_count = @($warningChecks).Count
    summary = [pscustomobject]@{
        compatibility_reason = if (@($errorChecks).Count -eq 0) { 'execution_contract_expectations_in_sync' } else { 'semantic_drift_detected' }
        checked_documents = @($checks | Where-Object { [string]$_.area -eq 'documents' }).Count
        checked_live_surfaces = @($checks | Where-Object { [string]$_.area -eq 'live_surfaces' -and [bool]$_.passed }).Count
        checked_gate_artifact = @($checks | Where-Object { [string]$_.area -eq 'gate_artifact' }).Count
    }
    paths = [pscustomobject]@{
        policy_doc = $resolvedPolicyDocPath
        audit_doc = $resolvedAuditDocPath
        feedback_contract = $resolvedFeedbackContractPath
        execution_gate_artifact = $resolvedExecutionGateArtifactPath
        listener_stage_dir = $resolvedListenerStageDir
    }
    checks = @($checks)
}

Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $result -Depth 20

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 20
}
else {
    $result
}

if ($FailOnMismatch -and -not [bool]$result.compatible) {
    throw ('TOD/MIM execution parity drift detected. See artifact: {0}' -f $resolvedOutputPath)
}