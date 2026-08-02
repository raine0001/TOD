Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$localEngineScript = Join-Path $repoRoot 'scripts/engines/LocalExecutionEngine.ps1'
$executionEngineScript = Join-Path $repoRoot 'scripts/engines/ExecutionEngine.ps1'

function Import-ScriptFunction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $ScriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $ScriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Import-ScriptFunctionWithLiteralRoot {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$LiteralRoot
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $ScriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $ScriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    $definition = $definition.Replace('$PSScriptRoot', ('''' + ($LiteralRoot -replace '''', '''''') + ''''))
    . ([scriptblock]::Create($definition))
}

function New-LocalFallbackPromptFile {
    param([Parameter(Mandatory = $true)][string]$Content)

    $dir = Join-Path $repoRoot ('tod/out/tests/local-fallback-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'task.md'
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function Set-LocalFallbackTestFileText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    if (Test-Path -Path $Path -PathType Leaf) {
        $item = Get-Item -Path $Path -Force
        if ($item.IsReadOnly) {
            $item.IsReadOnly = $false
        }
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function New-LocalFallbackContext {
    param(
        [Parameter(Mandatory = $true)][string]$TaskId,
        [Parameter(Mandatory = $true)][string]$ObjectiveId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Scope,
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [hashtable]$Metadata = @{}
    )

    return [pscustomobject]@{
        task_id = $TaskId
        objective_id = $ObjectiveId
        title = $Title
        scope = $Scope
        prompt_path = $PromptPath
        allowed_files = @()
        validation_commands = @()
        metadata = $Metadata
    }
}

Describe 'TOD local fallback executor' {
    BeforeAll {
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Get-ExecutionEngineInterfaceSpec'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineTaskContext'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Complete-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Test-EngineContract'

        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-UtcNow'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-NormalizedObjectiveToken'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingText'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingFileHints'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-TaskCategory'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Convert-EngineResultToNormalizedEnvelope'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Normalize-EngineResultPayload'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-EngineResultPrecheck'
        Import-ScriptFunction -ScriptPath $todScript -Name 'New-ExecutionEngineBlockedResult'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionValidationChecks'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRequiredValidationFailures'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionCommandCapture'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRollbackState'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-LocalExecutionTaskClass'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-LocalExecutionPatchRequired'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionNoOpAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-TodWrapperOnlyChangedPath'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TodMaterialImplementationProofAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TodTaskIdentity'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Publish-LocalExecutionArtifacts'
        Import-ScriptFunctionWithLiteralRoot -ScriptPath $todScript -Name 'Invoke-ExecutionEngine' -LiteralRoot (Join-Path $repoRoot 'scripts')

        . $localEngineScript
    }

    It 'stops validation command directives before packaged prompt metadata bullets' {
        $promptText = @'
## Task

Validation Command: powershell -NoProfile -Command "Write-Output 'ok'"
- Dependencies:
- Acceptance Criteria: command should not include this line

## Change Boundaries
- Do not modify unrelated systems.
'@

        $command = Get-LocalExecutionDirectiveValue -PromptText $promptText -FieldName 'Validation Command'

        [string]$command | Should Be 'powershell -NoProfile -Command "Write-Output ''ok''"'
        [string]$command | Should Not Match 'Dependencies'
        [string]$command | Should Not Match 'Change Boundaries'
    }

    It 'rejects packet quality review when explicit semantic constraints fail' {
        $suffix = [guid]::NewGuid().ToString('N')
        $sourceRel = "scripts/local-packet-quality-source-$suffix.ps1"
        $packetRel = "runtime_remote_training/tod_independent_resolution_attempts/local-packet-quality-packet-$suffix.json"
        $reviewRel = "runtime_remote_training/tod_independent_resolution_attempts/local-packet-quality-review-$suffix.json"
        $sourceAbs = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $packetAbs = Join-Path $repoRoot ($packetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $reviewAbs = Join-Path $repoRoot ($reviewRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $packetAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($sourceAbs, "function Test-DirectiveParser {`n    'Prevention Lesson',`n}`n", (New-Object System.Text.UTF8Encoding($false)))
        $packet = [ordered]@{
            artifact_type = 'tod_packet_formation_artifact'
            packet = [ordered]@{
                selected_candidate = 'tod_materialization_proof_directive_parser'
                target_file = $sourceRel
                intended_edit_mode = 'replace_text'
                old_text = "    'Prevention Lesson',"
                new_text = "    'Prevention Lesson',`n    'Dave Needed',"
                validation_command = 'powershell -NoProfile -Command "Write-Output ok"'
                validation_pattern = 'Dave Needed'
                closure_evidence = 'test packet'
                prevention_lesson = 'test packet'
                dave_needed = 'no'
            }
        }
        [System.IO.File]::WriteAllText($packetAbs, ($packet | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
        $promptText = @"
Packet quality review.
Target File: $reviewRel
Review Artifact: $packetRel
Source File: $sourceRel
Expected Decision: reject_packet
Required Old Text Pattern: target_selection
Required New Text Pattern: target_selection
Forbidden Selected Candidate: tod_materialization_proof_directive_parser
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-PACKET-QUALITY-SEMANTIC-REJECT' `
            -ObjectiveId 'TOD-PACKET-QUALITY-SEMANTIC-RELEVANCE-V1' `
            -Title 'Reject semantically off-target packet' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            if ([string]$result.status -ne 'completed') {
                throw ($result | ConvertTo-Json -Depth 8)
            }
            [string]$result.status | Should Be 'completed'
            [string]@($result.files_changed)[0] | Should Be $reviewRel
            Test-Path -Path $reviewAbs | Should Be $true
            $review = Get-Content $reviewAbs -Raw | ConvertFrom-Json
            [string]$review.decision | Should Be 'reject_packet'
            @($review.evidence_checked | Where-Object { [string]$_.check -eq 'forbidden_selected_candidate' -and [bool]$_.passed -eq $false }).Count | Should Be 1
            @($review.evidence_checked | Where-Object { [string]$_.check -eq 'expected_decision_matches_intrinsic_review' -and [bool]$_.passed }).Count | Should Be 1
        }
        finally {
            foreach ($path in @($sourceAbs, $packetAbs, $reviewAbs)) {
                if (Test-Path -Path $path) {
                    Remove-Item -Path $path -Force
                }
            }
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'keeps packet quality review ahead of generic read-only audit artifact routing' {
        $suffix = [guid]::NewGuid().ToString('N')
        $sourceRel = "scripts/local-packet-quality-precedence-source-$suffix.ps1"
        $packetRel = "runtime_remote_training/tod_independent_resolution_attempts/local-packet-quality-precedence-packet-$suffix.json"
        $reviewRel = "runtime_remote_training/tod_independent_resolution_attempts/local-packet-quality-precedence-review-$suffix.json"
        $sourceAbs = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $packetAbs = Join-Path $repoRoot ($packetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $reviewAbs = Join-Path $repoRoot ($reviewRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $packetAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($sourceAbs, "function Test-PacketQualityPrecedence {`n    return 'old-anchor'`n}`n", (New-Object System.Text.UTF8Encoding($false)))
        $packet = [ordered]@{
            artifact_type = 'tod_packet_body_synthesis_artifact'
            packet_candidate_ready = $true
            packet = [ordered]@{
                target_file = $sourceRel
                intended_edit_mode = 'replace_exact_text'
                old_text = "    return 'old-anchor'"
                new_text = "    return 'new-anchor'"
                validation_command = 'powershell -NoProfile -Command "Write-Output ok"'
                validation_pattern = 'new-anchor'
                closure_evidence = 'test packet'
                prevention_lesson = 'test packet'
                dave_needed = 'no'
            }
        }
        [System.IO.File]::WriteAllText($packetAbs, ($packet | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))
        $promptText = @"
Packet quality review.
This is a read-only audit artifact review, but the packet-quality lane has explicit authority.
Output: $reviewRel
Review Artifact: $packetRel
Source File: $sourceRel
Expected Decision: accept_packet
Required Old Text Pattern: old-anchor
Required New Text Pattern: new-anchor
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-PACKET-QUALITY-REVIEW-PRECEDENCE' `
            -ObjectiveId 'TOD-SOURCE-ANCHOR-PACKET-TARGET-DISAMBIGUATION-V1' `
            -Title 'Packet quality review precedence' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            if ([string]$result.status -ne 'completed') {
                throw ($result | ConvertTo-Json -Depth 8)
            }
            [string]$result.status | Should Be 'completed'
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionPacketQualityReview'
            Test-Path -Path $reviewAbs | Should Be $true
            $review = Get-Content $reviewAbs -Raw | ConvertFrom-Json
            [string]$review.artifact_type | Should Be 'tod_packet_quality_review_artifact'
            [string]$review.decision | Should Be 'accept_packet'
            @($review.evidence_checked | Where-Object { [string]$_.check -eq 'old_text_found_in_source' -and [bool]$_.passed }).Count | Should Be 1
        }
        finally {
            foreach ($path in @($sourceAbs, $packetAbs, $reviewAbs)) {
                if (Test-Path -Path $path) {
                    Remove-Item -Path $path -Force
                }
            }
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'publishes a read-only task context proof without requiring an input artifact or target file' {
        $suffix = [guid]::NewGuid().ToString('N')
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTEXT_PROOF_TEST_$suffix.json"
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $promptText = @"
Read-only assessment via direct chat intake.
Output Artifact: $outputRel
Mission: verify task_mode=read_only_assessment survives execute-chat-task, intake, and run-task without source-code mutation or bounded edit requirements.
Required fields: task_mode_preserved, bounded_edit_required=false, target_file_required=false, no_code_changes=true, evidence_checked, validation, prevention_lesson, dave_needed=no.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-READONLY-CONTEXT-PROOF-TEST' `
            -ObjectiveId 'TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1' `
            -Title 'Read-only context proof test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @($result.files_changed) -contains $outputRel | Should Be $true
            [string]$artifact.artifact_type | Should Be 'tod_read_only_task_context_proof'
            [string]$artifact.task_mode | Should Be 'read_only_assessment'
            [bool]$artifact.task_mode_preserved | Should Be $true
            [bool]$artifact.bounded_edit_required | Should Be $false
            [bool]$artifact.target_file_required | Should Be $false
            [bool]$artifact.no_code_changes | Should Be $true
            [string]$artifact.dave_needed | Should Be 'no'
            @($result.validation_results | Where-Object { [string]$_.name -eq 'non-edit assertion' -and [bool]$_.passed }).Count | Should Be 1
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'routes Input Evidence read-only assessments to the audit lane instead of context-only proof' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_INPUT_EVIDENCE_AUDIT_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_INPUT_EVIDENCE_AUDIT_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_patch_evidence_authority_classification'
            task_id = 'TOD-INPUT-EVIDENCE-AUDIT-INPUT'
            classification_counts = [ordered]@{
                reusable_service_candidate = 2
                hardcoded_response_authority_risk = 1
                operator_contract_authority_risk = 1
            }
            signals = @(
                [ordered]@{ signal = 'active_conversation_state'; bucket = 'reusable_service_candidate'; match_count = 3 },
                [ordered]@{ signal = 'visible_reply_authority'; bucket = 'hardcoded_response_authority_risk'; match_count = 1 }
            )
            continuation_action = 'Select one reusable service candidate and define generalized tests.'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only assessment.
Input Evidence: $inputRel
Output Artifact: $outputRel
Mission: inspect the classification evidence and produce a read-only audit artifact.
Do not modify source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-INPUT-EVIDENCE-AUDIT-TEST' `
            -ObjectiveId 'TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1' `
            -Title 'Input Evidence read-only audit test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @($result.files_changed) -contains $outputRel | Should Be $true
            [string]$artifact.artifact_type | Should Be 'tod_read_only_audit_artifact'
            [string]$artifact.source | Should Be 'local_execution_read_only_audit_artifact_lane'
            @($artifact.inspected_files) -contains $inputRel | Should Be $true
            [string]$artifact.classification | Should Be 'patch_authority_classification_review_required'
            @($artifact.evidence_used[0].fields) -contains 'classification_counts' | Should Be $true
            @($artifact.evidence_used[0].fields) -contains 'signals' | Should Be $true
            @($artifact.findings | Where-Object { [string]$_.finding -eq 'patch_authority_classification_counts' -and [string]$_.evidence -match 'reusable_service_candidate=2' }).Count | Should Be 1
            @($artifact.findings | Where-Object { [string]$_.finding -eq 'patch_authority_signals' -and [string]$_.evidence -match 'active_conversation_state:reusable_service_candidate:3' }).Count | Should Be 1
            @($artifact.findings | Where-Object { [string]$_.finding -eq 'patch_authority_continuation_action' -and [string]$_.evidence -match 'Select one reusable service candidate' }).Count | Should Be 1
            @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'route_response_authority_risk_present' }).Count | Should Be 1
            [bool]$artifact.no_code_changes | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves requested source-anchor classifier shape for mixed evidence pools' {
        $suffix = [guid]::NewGuid().ToString('N')
        $blockerRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_BLOCKER_$suffix.json"
        $reviewRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_REVIEW_$suffix.json"
        $anchorRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_SOURCE_ANCHOR_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_OUTPUT_$suffix.json"
        $blockerAbs = Join-Path $repoRoot ($blockerRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $reviewAbs = Join-Path $repoRoot ($reviewRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $anchorAbs = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $blockerAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_training_blocker_evidence'
            status = 'blocked'
            blocker = [ordered]@{ reason_code = 'packet_body_missing'; reason = 'Diagnostic blocker only.' }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $blockerAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_packet_quality_review_artifact'
            decision = 'reject_packet'
            credit_decision = [ordered]@{ independent_tod_resolution = $false }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $reviewAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            exact_text = 'function Invoke-Example { return $true }'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $anchorAbs -Encoding utf8

        $promptText = @"
Read-only audit artifact:
Input: $blockerRel
Output: $outputRel

Evidence pool:
- $blockerRel
- $reviewRel
- $anchorRel

Required output shape:
{
  "classification_decision": "passed|blocked",
  "selected_source_anchor_artifact": "",
  "classified_artifacts": [],
  "packet_materialization_allowed": true,
  "tod_independent_capability_acquired": false
}

Mission: classify the evidence pool and identify the usable source-anchor observation with exact_text. Do not edit source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-EVIDENCE-POOL-SOURCE-ANCHOR-CLASSIFIER-TEST' `
            -ObjectiveId 'TOD-EVIDENCE-POOL-SOURCE-ANCHOR-CLASSIFIER-V1' `
            -Title 'Evidence pool source-anchor classifier test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection'; task_mode = 'inspection'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_evidence_pool_source_anchor_classifier'
            [string]$artifact.classification_decision | Should Be 'passed'
            [string]$artifact.selected_source_anchor_artifact | Should Be $anchorRel
            [bool]$artifact.packet_materialization_allowed | Should Be $true
            [bool]$artifact.tod_independent_capability_acquired | Should Be $false
            [bool]$artifact.no_code_changes | Should Be $true
            @($artifact.classified_artifacts).Count | Should Be 3
            @($artifact.classified_artifacts | Where-Object { [string]$_.path -eq $blockerRel -and [string]$_.artifact_shape -eq 'blocker_artifact' -and -not [bool]$_.usable_as_old_text_source }).Count | Should Be 1
            @($artifact.classified_artifacts | Where-Object { [string]$_.path -eq $reviewRel -and [string]$_.artifact_shape -eq 'review_artifact' -and -not [bool]$_.usable_as_old_text_source }).Count | Should Be 1
            @($artifact.classified_artifacts | Where-Object { [string]$_.path -eq $anchorRel -and [string]$_.artifact_shape -eq 'source_anchor_observation' -and [bool]$_.usable_as_old_text_source }).Count | Should Be 1
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $blockerAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $reviewAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'dereferences source-anchor classifier output before packet body synthesis' {
        $suffix = [guid]::NewGuid().ToString('N')
        $anchorRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_PACKET_ANCHOR_$suffix.json"
        $classifierRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_PACKET_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/tod_independent_resolution_attempts/TOD_CLASSIFIER_PACKET_OUTPUT_$suffix.json"
        $anchorAbs = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $classifierAbs = Join-Path $repoRoot ($classifierRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $anchorAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            exact_text = 'function Invoke-Example { return $true }'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $anchorAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_evidence_pool_source_anchor_classifier'
            classification_decision = 'passed'
            selected_source_anchor_artifact = $anchorRel
            packet_materialization_allowed = $true
            tod_independent_capability_acquired = $false
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $classifierAbs -Encoding utf8

        $promptText = @"
Packet-body synthesis task:
Input Artifact: $classifierRel
Output: $outputRel

Use the selected_source_anchor_artifact from the classifier result as the source-anchor old_text input.
No source edits are allowed.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-CLASSIFIER-SELECTED-SOURCE-ANCHOR-DEREFERENCE-TEST' `
            -ObjectiveId 'TOD-CLASSIFIER-SELECTED-SOURCE-ANCHOR-DEREFERENCE-V1' `
            -Title 'Classifier selected source-anchor dereference test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'packet_formation'; task_mode = 'packet_formation'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'blocked'
            [string]$result.reason_code | Should Be 'packet_body_synthesis_autonomous_new_text_missing'
            [string]@($result.blockers)[0].missing_variable | Should Be 'autonomous_meaningful_new_text_materialization_from_source_anchor'
            Test-Path -Path $outputAbs | Should Be $false
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $classifierAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'derives packet body target file from direct source-anchor input' {
        $suffix = [guid]::NewGuid().ToString('N')
        $anchorRel = "runtime_remote_training/read_only_audit_artifacts/TOD_DIRECT_PACKET_ANCHOR_$suffix.json"
        $outputRel = "runtime_remote_training/tod_independent_resolution_attempts/TOD_DIRECT_PACKET_OUTPUT_$suffix.json"
        $anchorAbs = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $anchorAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            exact_text = 'function Invoke-Example { return $true }'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $anchorAbs -Encoding utf8

        $promptText = @"
Packet-body synthesis task:
Input Artifact: $anchorRel
Output: $outputRel

Use the source-anchor exact_text as old_text.
No source edits are allowed.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-DIRECT-SOURCE-ANCHOR-TARGET-DERIVATION-TEST' `
            -ObjectiveId 'TOD-DIRECT-SOURCE-ANCHOR-TARGET-DERIVATION-V1' `
            -Title 'Direct source-anchor target derivation test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'packet_formation'; task_mode = 'packet_formation'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'blocked'
            [string]$result.reason_code | Should Be 'packet_body_synthesis_autonomous_new_text_missing'
            [string]@($result.blockers)[0].missing_variable | Should Be 'autonomous_meaningful_new_text_materialization_from_source_anchor'
            Test-Path -Path $outputAbs | Should Be $false
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves source-anchor delta proposal schema in read-only lane' {
        $suffix = [guid]::NewGuid().ToString('N')
        $anchorRel = "runtime_remote_training/read_only_audit_artifacts/TOD_DELTA_PROPOSAL_ANCHOR_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_DELTA_PROPOSAL_OUTPUT_$suffix.json"
        $anchorAbs = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $anchorAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            exact_text = 'function Invoke-Example { return $true }'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $anchorAbs -Encoding utf8

        $promptText = @"
Read-only source-anchor delta proposal:
Input Artifact: $anchorRel
Output Artifact: $outputRel
Required Output Fields: artifact_type, objective_id, task_id, status, old_text_source, target_file, intended_behavior_delta, candidate_new_text, safety_constraints, validation_plan, confidence, no_source_code_modified, blocker, validation

Required output artifact shape:
{
  "artifact_type": "tod_source_anchor_delta_proposal",
  "status": "proposed|blocked",
  "old_text_source": "$anchorRel",
  "target_file": "",
  "intended_behavior_delta": "",
  "candidate_new_text": "",
  "safety_constraints": [],
  "validation_plan": [],
  "confidence": "low|medium|high",
  "no_source_code_modified": true,
  "blocker": null
}

Mission: preserve the requested delta-proposal schema before packet materialization. Do not edit source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-READONLY-DELTA-PROPOSAL-SCHEMA-PRESERVATION-TEST' `
            -ObjectiveId 'TOD-READONLY-DELTA-PROPOSAL-SCHEMA-PRESERVATION-V1' `
            -Title 'Read-only source-anchor delta proposal schema preservation test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_source_anchor_delta_proposal'
            [string]$artifact.status | Should Be 'blocked'
            [string]$artifact.old_text_source | Should Be $anchorRel
            [string]$artifact.target_file | Should Be 'scripts/engines/LocalExecutionEngine.ps1'
            [string]$artifact.blocker.reason_code | Should Be 'autonomous_candidate_new_text_missing'
            [bool]$artifact.no_source_code_modified | Should Be $true
            [bool]$artifact.validation.required_fields_present | Should Be $true
            [string]$artifact.pass_or_reject | Should Be 'pass'
            @($artifact.missing_fields).Count | Should Be 0
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps source-anchor delta proposal ahead of corpus enrichment wording' {
        $suffix = [guid]::NewGuid().ToString('N')
        $anchorRel = "runtime_remote_training/read_only_audit_artifacts/TOD_DELTA_CORPUS_PRECEDENCE_ANCHOR_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_DELTA_CORPUS_PRECEDENCE_OUTPUT_$suffix.json"
        $anchorAbs = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $anchorAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            exact_text = 'function Invoke-Example { return $true }'
            no_code_changes = $true
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $anchorAbs -Encoding utf8

        $promptText = @"
Read-only source-anchor delta proposal for a corpus-related selector.
Input Artifact: $anchorRel
Output Artifact: $outputRel

Required Artifact Type: tod_source_anchor_delta_proposal

Mission: propose whether source-anchor exact_text can become candidate_new_text. The surrounding objective mentions corpus, source-anchor episode enrichment, and tod_engineering_corpus_source_anchor_episode_enrichment, but this task must preserve the requested delta-proposal artifact type.
Do not edit source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-DELTA-CORPUS-PRECEDENCE-TEST' `
            -ObjectiveId 'TOD-CORPUS-LANE-SELECTOR-PRECEDENCE-AND-DELTA-SYNTHESIS-V1' `
            -Title 'Source-anchor delta proposal outranks corpus enrichment wording' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_source_anchor_delta_proposal'
            [string]$artifact.old_text_source | Should Be $anchorRel
            [string]$artifact.target_file | Should Be 'scripts/engines/LocalExecutionEngine.ps1'
            [string]$artifact.blocker.reason_code | Should Be 'autonomous_candidate_new_text_missing'
            [bool]$artifact.no_source_code_modified | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'dereferences held-out selected source-anchor episodes for delta proposal' {
        $suffix = [guid]::NewGuid().ToString('N')
        $sourceRel = "runtime_remote_training/read_only_audit_artifacts/TOD_HELDOUT_DELTA_SOURCE_$suffix.json"
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_HELDOUT_DELTA_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_HELDOUT_DELTA_OUTPUT_$suffix.json"
        $sourceAbs = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            exact_text = 'function Invoke-Example { return $true }'
            no_code_changes = $true
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $sourceAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_heldout_candidate_newtext_from_corpus_manifest'
            status = 'blocked'
            selected_episode = [ordered]@{
                episode_id = 'episode-005'
                source_artifact = $sourceRel
                source_artifact_type = 'tod_source_anchor_observation'
                source_file = 'scripts/engines/LocalExecutionEngine.ps1'
                exact_text_available = $true
            }
            source_anchor_available = $true
            candidate_new_text = ''
            blocker = @{ reason_code = 'autonomous_candidate_new_text_missing' }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only source-anchor delta proposal from held-out selected episode.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $inputRel
Output Artifact: $outputRel

Required Artifact Type: tod_source_anchor_delta_proposal
Required Output Fields: artifact_type, objective_id, task_id, status, old_text_source, target_file, intended_behavior_delta, candidate_new_text, safety_constraints, validation_plan, confidence, no_source_code_modified, blocker, validation

Mission: dereference the selected held-out source-anchor episode and report whether autonomous candidate_new_text can be synthesized.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-HELDOUT-DELTA-PROPOSAL-TEST' `
            -ObjectiveId 'TOD-AUTONOMOUS-CANDIDATE-NEWTEXT-FROM-ENRICHED-HELDOUT-V1' `
            -Title 'Held-out selected source-anchor delta proposal test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_source_anchor_delta_proposal'
            [string]$artifact.old_text_source | Should Be $sourceRel
            [string]$artifact.target_file | Should Be 'scripts/engines/LocalExecutionEngine.ps1'
            [string]$artifact.candidate_new_text | Should Be ''
            [string]$artifact.blocker.reason_code | Should Be 'autonomous_candidate_new_text_missing'
            [bool]$artifact.no_source_code_modified | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $sourceAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'routes corpus evidence intake classification before semantic source audit' {
        $suffix = [guid]::NewGuid().ToString('N')
        $semanticRel = "runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_PACKET_MODE_SOURCE_AUDIT_$suffix.json"
        $scorecardRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_SCORECARD_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_EVIDENCE_INTAKE_OUTPUT_$suffix.json"
        $semanticAbs = Join-Path $repoRoot ($semanticRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $scorecardAbs = Join-Path $repoRoot ($scorecardRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $semanticAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_semantic_source_audit_artifact'
            objective_id = 'TOD-SEMANTIC-PACKET-MODE-SOURCE-AUDIT-V1'
            codex_role = 'validation_only'
            validation = @{ passed = $true }
            final_outcome = @{ status = 'completed'; lesson = 'semantic evidence can guide future corpus classification' }
            next_training_rung = 'TOD-ENGINEERING-CORPUS-FOUNDATION-V1'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $semanticAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'mim_tod_organizational_maintenance_scorecard_v1'
            objective_id = 'TOD-ORGANIZATIONAL-MAINTENANCE-CYCLE-V1'
            borrowed_capability_ratio = @{ current = @{ borrowed_percent = 77.8; independent_percent = 22.2 } }
            validation = @{ passed = $true }
            next_training_rung = 'TOD-ENGINEERING-CORPUS-FOUNDATION-V1'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $scorecardAbs -Encoding utf8

        $promptText = @"
Read-only corpus evidence intake classifier.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $semanticRel
Input Evidence Pool:
- $semanticRel
- $scorecardRel
Output Artifact: $outputRel

Required Artifact Type: tod_engineering_corpus_evidence_intake_classifier
Required Output Fields: artifact_type, objective_id, task_id, status, codex_role, source_artifacts, candidate_inputs, rejected_inputs, missing_fields_for_episode_manifest, smallest_next_executable_shape, validation, prevention_lesson, independent_credit_requested, dave_needed

Mission: classify these existing training artifacts into candidate engineering-corpus episode inputs. This is corpus intake classification, not semantic source-anchor auditing.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-CORPUS-EVIDENCE-INTAKE-CLASSIFIER-TEST' `
            -ObjectiveId 'TOD-ENGINEERING-CORPUS-EVIDENCE-INTAKE-CLASSIFIER-V1' `
            -Title 'Corpus evidence intake classifier routing precedence test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_corpus_evidence_intake_classifier'
            @($artifact.source_artifacts).Count | Should Be 2
            @($artifact.candidate_inputs).Count | Should BeGreaterThan 0
            [bool]$artifact.independent_credit_requested | Should Be $false
            [bool]$artifact.validation.no_source_code_modified | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $semanticAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $scorecardAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'publishes read-only evidence comparison from two prompt packages' {
        $suffix = [guid]::NewGuid().ToString('N')
        $leftRel = "tod/out/prompts/TOD_READONLY_COMPARISON_FAILED_$suffix.md"
        $rightRel = "tod/out/prompts/TOD_READONLY_COMPARISON_PASSED_$suffix.md"
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_COMPARISON_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_COMPARISON_OUTPUT_$suffix.json"
        $leftAbs = Join-Path $repoRoot ($leftRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $rightAbs = Join-Path $repoRoot ($rightRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $leftAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        @"
Read-only comparison source.
Task Mode: read_only_assessment
Task Category: read_only_role_classification
Input Artifact: $inputRel
Output Artifact: $outputRel
Required Artifact Type: tod_readonly_evidence_comparison
"@ | Set-Content -Path $leftAbs -Encoding utf8
        @"
Read-only comparison source.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $inputRel
Output Artifact: $outputRel
Required Artifact Type: tod_readonly_evidence_comparison
"@ | Set-Content -Path $rightAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_read_only_recovery_attempt'
            objective_id = 'TOD-READONLY-RECOVERY-CONTRACT-DIFFERENCE-DETECTION-V1'
            task_id = 'comparison-input'
            status = 'failed'
            validation = @{ no_code_changes = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only evidence comparison.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $inputRel
Package Path: $leftRel
Inspect Source File: $rightRel
Output Artifact: $outputRel

Required Artifact Type: tod_readonly_evidence_comparison
Required Output Fields: artifact_type, objective_id, task_id, status, input_evidence_artifact, left_artifact, right_artifact, first_material_difference, failed_contract_value, passed_contract_value, detector_eligibility_effect, smallest_reusable_rule, validation, prevention_lesson, independent_credit_requested, dave_needed

Mission: compare the failed and passing evidence packages and publish the first material contract difference.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-READONLY-EVIDENCE-COMPARISON-TEST' `
            -ObjectiveId 'TOD-READONLY-RECOVERY-CONTRACT-DIFFERENCE-DETECTION-V1' `
            -Title 'Read-only evidence comparison lane test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_readonly_evidence_comparison'
            [string]$artifact.first_material_difference | Should Be 'Task Category'
            [string]$artifact.failed_contract_value | Should Be 'read_only_role_classification'
            [string]$artifact.passed_contract_value | Should Be 'inspection_only'
            [string]$artifact.detector_eligibility_effect | Should Be 'affects_executor_lane_or_artifact_contract'
            [bool]$artifact.validation.no_code_changes | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $leftAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $rightAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'publishes read-only evidence comparison from left and right artifact roles' {
        $suffix = [guid]::NewGuid().ToString('N')
        $leftRel = "runtime_remote_training/engineering_corpus/TOD_LEFT_COMPARISON_$suffix.json"
        $rightRel = "tod/out/prompts/TOD_RIGHT_COMPARISON_$suffix.md"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_EVIDENCE_COMPARISON_$suffix.json"
        $leftAbs = Join-Path $repoRoot ($leftRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $rightAbs = Join-Path $repoRoot ($rightRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $leftAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $rightAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_episode_quality_examiner_verdict'
            status = 'completed'
            validation = @{ no_code_changes = $true }
            prompt_excerpt = @"
Task Category: artifact_write
Output Artifact: $outputRel
Required Artifact Type: tod_engineering_episode_quality_examiner_verdict
"@
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $leftAbs -Encoding utf8
        @"
Read-only comparison source.
Task Category: artifact_write
Output Artifact: $outputRel
Required Artifact Type: tod_source_anchor_delta_proposal
"@ | Set-Content -Path $rightAbs -Encoding utf8

        $promptText = @"
Read-only evidence comparison.
Left Artifact: $leftRel
Right Artifact: $rightRel
Output Artifact: $outputRel
Required Artifact Type: tod_read_only_evidence_comparison
Do not modify source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-READONLY-EVIDENCE-COMPARISON-LEFT-RIGHT-TEST' `
            -ObjectiveId 'TOD-READONLY-RECOVERY-CONTRACT-DIFFERENCE-DETECTION-V1' `
            -Title 'Read-only evidence comparison left/right artifact lane test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_read_only_evidence_comparison'
            [string]$artifact.first_material_difference | Should Be 'Task Category'
            [string]$artifact.detector_eligibility_effect | Should Be 'affects_executor_lane_or_artifact_contract'
            [bool]$artifact.validation.no_code_changes | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $leftAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $rightAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'publishes provider-candidate replan from primary input sentence role' {
        $suffix = [guid]::NewGuid().ToString('N')
        $verdictRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_VERDICT_$suffix.json"
        $requestRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_$suffix.json"
        $candidateRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REPLAN_$suffix.json"
        $verdictAbs = Join-Path $repoRoot ($verdictRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $requestAbs = Join-Path $repoRoot ($requestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $candidateAbs = Join-Path $repoRoot ($candidateRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $verdictAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_verdict'
            verdict = 'reject'
            verdict_reason_code = 'rejected_no_delta_candidate'
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $verdictAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_engineering_provider_request'
            source_files_to_include = @('scripts/engines/LocalExecutionEngine.ps1')
            artifacts_to_include = @('runtime_remote_training/read_only_audit_artifacts/TOD_EXAMPLE_SOURCE_ANCHOR.latest.json')
            validation_command = 'Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1'
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $requestAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_stub'
            target_file = 'scripts/engines/LocalExecutionEngine.ps1'
            old_text = 'same text'
            new_text = 'same text'
            validation_command = ''
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $candidateAbs -Encoding utf8

        $promptText = @"
Provider candidate rejection replan.
Primary input is $verdictRel.
Supporting Artifact: $requestRel
Supporting Artifact: $candidateRel
Output Artifact: $outputRel
Required Artifact Type: tod_engineering_provider_candidate_replan
No source edits.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-PROVIDER-CANDIDATE-REPLAN-PRIMARY-INPUT-TEST' `
            -ObjectiveId 'TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1' `
            -Title 'Provider candidate replan primary input sentence lane test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_provider_candidate_replan'
            [string]$artifact.input_candidate_verdict | Should Be $verdictRel
            [string]$artifact.prior_rejection_reason_code | Should Be 'rejected_no_delta_candidate'
            [bool]$artifact.provider_request_ready_for_retry | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $verdictAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $requestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $candidateAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'downgrades model provider readiness when supporting evidence proves already-applied source' {
        $suffix = [guid]::NewGuid().ToString('N')
        $contextRel = "runtime_remote_training/engineering_corpus/TOD_CONTEXT_ALREADY_APPLIED_$suffix.json"
        $supportRel = "runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_VALIDATION_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_JUDGMENT_$suffix.json"
        $contextAbs = Join-Path $repoRoot ($contextRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $supportAbs = Join-Path $repoRoot ($supportRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $contextAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_context_package'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            source_function = 'Invoke-LocalExecutionReadOnlyAuditArtifact'
            source_anchor_artifact = 'runtime_remote_training/read_only_audit_artifacts/TOD_VALIDATION_SPECIFICITY_CURRENT_SOURCE_R277.latest.json'
            required_output_contract = @{ validation_command = 'Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1' }
            rejected_outputs = @('marker-only packet')
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $contextAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'codex_validation_tod_model_utilization_already_applied_readiness_v1'
            verdict = 'fail_model_retry_readiness'
            training_classification = 'model_utilization_defect'
            findings = @{ source_anchor_contains_truth_table_repair = $true }
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $supportAbs -Encoding utf8

        $promptText = @"
Model utilization judgment.
Input Artifact: $contextRel
Supporting Artifact: $supportRel
Output Artifact: $outputRel
Required Artifact Type: tod_model_utilization_engineering_judgment
No source edits.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-MODEL-JUDGMENT-ALREADY-APPLIED-TEST' `
            -ObjectiveId 'TOD-ALREADY-APPLIED-CONTEXT-READINESS-REJECTION-V1B' `
            -Title 'Model judgment already-applied readiness downgrade test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_model_utilization_engineering_judgment'
            [string]$artifact.context_quality | Should Be 'already_applied_no_provider_retry'
            [bool]$artifact.candidate_request_ready | Should Be $false
            [bool]$artifact.provider_readiness_downgraded_by_supporting_evidence | Should Be $true
            [string]$artifact.blocker_or_next_action.reason_code | Should Be 'already_applied_source_evidence'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $contextAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $supportAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves task-scope problem fields in engineering context packages' {
        $suffix = [guid]::NewGuid().ToString('N')
        $sourceRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_FIELD_SELECTION_SOURCE_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_CONTEXT_FIELD_SELECTION_OUTPUT_$suffix.json"
        $sourceAbs = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            source_function = 'Invoke-LocalExecutionReadOnlyAuditArtifact'
            validation = @{ anchor_found = $true; no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $sourceAbs -Encoding utf8

        $promptText = @"
Required Artifact Type: tod_engineering_context_package
Input Artifact: $sourceRel
Output Artifact: $outputRel
Problem Summary: supporting_artifacts_read emits duplicate supporting artifact paths.
Observed Failure: R284 listed each supporting evidence path more than once.
Desired Behavior: supporting_artifacts_read should contain each supporting artifact path once while preserving first observed order.
Validation Target: focused regression proves unique supporting_artifacts_read paths and PowerShell parse passes.
No source edits.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-CONTEXT-FIELD-PRESERVATION-TEST' `
            -ObjectiveId 'TOD-PROVIDER-CONTEXT-SEMANTIC-QUALITY-GATE-V1' `
            -Title 'Context package task-scope problem preservation test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'engineering_context_package'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_context_package'
            [string]$artifact.problem_summary | Should Match 'supporting_artifacts_read emits duplicate'
            [string]$artifact.observed_failure | Should Match 'R284 listed each supporting evidence path'
            [string]$artifact.desired_behavior | Should Match 'each supporting artifact path once'
            [string]$artifact.validation_target | Should Match 'unique supporting_artifacts_read paths'
            [string]$artifact.problem_summary | Should Not Match 'marker-only packet'
            [string]$artifact.desired_behavior | Should Not Match 'marker-only'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $sourceAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects unsafe provider candidate with blank new_text before source mutation' {
        $suffix = [guid]::NewGuid().ToString('N')
        $requestRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_BLANK_NEW_$suffix.json"
        $candidateRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_BLANK_NEW_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_VERDICT_BLANK_NEW_$suffix.json"
        $requestAbs = Join-Path $repoRoot ($requestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $candidateAbs = Join-Path $repoRoot ($candidateRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $requestAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_provider_request'
            source_files_to_include = @('scripts/engines/LocalExecutionEngine.ps1')
            validation_command = "Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1 -FullName 'rejects unsafe provider candidate with blank new_text before source mutation'"
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $requestAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_stub'
            target_file = 'scripts/engines/LocalExecutionEngine.ps1'
            old_text = 'function Invoke-LocalExecutionEngine {'
            new_text = ''
            validation_command = "Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1 -FullName 'rejects unsafe provider candidate with blank new_text before source mutation'"
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $candidateAbs -Encoding utf8

        $promptText = @"
Provider candidate verdict.
Input Artifact: $candidateRel
Supporting Artifact: $requestRel
Output Artifact: $outputRel
Required Artifact Type: tod_engineering_provider_candidate_verdict
No source edits.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-PROVIDER-CANDIDATE-BLANK-NEWTEXT-REJECT-TEST' `
            -ObjectiveId 'TOD-PROVIDER-CANDIDATE-VERDICT-SAFETY-POLICY-V1' `
            -Title 'Provider candidate blank new_text safety rejection test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_provider_candidate_verdict'
            [string]$artifact.verdict | Should Be 'reject'
            [string]$artifact.verdict_reason_code | Should Be 'rejected_blank_new_text'
            [bool]$artifact.accepted_for_source_mutation | Should Be $false
            [bool]$artifact.rejected_before_source_mutation | Should Be $true
            @($artifact.policy_checks | Where-Object { [string]$_.check -eq 'old_text_found_in_current_source' -and [bool]$_.passed }).Count | Should Be 1
            @($artifact.policy_checks | Where-Object { [string]$_.check -eq 'new_text_nonblank' -and -not [bool]$_.passed }).Count | Should Be 1
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $requestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $candidateAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects provider candidate with blank validation command as not specific' {
        $suffix = [guid]::NewGuid().ToString('N')
        $requestRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_BLANK_VALIDATION_$suffix.json"
        $candidateRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_BLANK_VALIDATION_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_VERDICT_BLANK_VALIDATION_$suffix.json"
        $requestAbs = Join-Path $repoRoot ($requestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $candidateAbs = Join-Path $repoRoot ($candidateRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $requestAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_provider_request'
            source_files_to_include = @('scripts/engines/LocalExecutionEngine.ps1')
            validation_command = "Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1 -FullName 'rejects provider candidate with blank validation command as not specific'"
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $requestAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_stub'
            target_file = 'scripts/engines/LocalExecutionEngine.ps1'
            old_text = 'function Invoke-LocalExecutionEngine {'
            new_text = 'function Invoke-LocalExecutionEngine { # candidate change requiring validation'
            validation_command = ''
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $candidateAbs -Encoding utf8

        $promptText = @"
Provider candidate verdict.
Input Artifact: $candidateRel
Supporting Artifact: $requestRel
Output Artifact: $outputRel
Required Artifact Type: tod_engineering_provider_candidate_verdict
No source edits.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-PROVIDER-CANDIDATE-BLANK-VALIDATION-REJECT-TEST' `
            -ObjectiveId 'TOD-VALIDATION-COMMAND-SPECIFICITY-TRUTH-TABLE-V1' `
            -Title 'Provider candidate blank validation command specificity test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_provider_candidate_verdict'
            [string]$artifact.verdict | Should Be 'reject'
            [string]$artifact.verdict_reason_code | Should Be 'rejected_missing_validation_command'
            [bool]$artifact.accepted_for_source_mutation | Should Be $false
            @($artifact.policy_checks | Where-Object { [string]$_.check -eq 'validation_command_present' -and -not [bool]$_.passed }).Count | Should Be 1
            @($artifact.policy_checks | Where-Object { [string]$_.check -eq 'validation_command_specific' -and -not [bool]$_.passed -and [string]$_.evidence -eq 'validation command is blank' }).Count | Should Be 1
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $requestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $candidateAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects unsafe script-block validation before mutation authority' {
        $fixtureRel = 'tod/out/tests/semantic-gate-unsafe-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        Set-LocalFallbackTestFileText -Path $fixtureAbs -Content "Write-Output 'before'`n"

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "Write-Output 'before'" `
                -NewText "Write-Output 'after'" `
                -ValidationCommand "Invoke-Pester -Script { Write-Output 'not allowlisted' }"

            [string]$semantic.semantic_verdict | Should Be 'reject'
            [bool]$semantic.mutation_authority_allowed | Should Be $false
            (@($semantic.reason_codes) -contains 'unsupported_or_unsafe_validation_command') | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be "Write-Output 'before'`n"
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a parseable literal single-anchor candidate only in temporary workspace' {
        $fixtureRel = 'tod/out/tests/semantic-gate-valid-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        Set-LocalFallbackTestFileText -Path $fixtureAbs -Content "Write-Output 'before'`n"
        $validation = 'powershell -NoProfile -Command ''$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "{0}"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}}''' -f $fixtureRel

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "Write-Output 'before'" `
                -NewText "Write-Output 'after'" `
                -ValidationCommand $validation `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'text_invariants'
                    required_contains = @("Write-Output 'after'")
                    forbidden_contains = @("Write-Output 'before'")
                })

            [string]$semantic.semantic_verdict | Should Be 'accept'
            [bool]$semantic.mutation_authority_allowed | Should Be $true
            [int]$semantic.anchor_match_count | Should Be 1
            [bool]$semantic.patch_applied | Should Be $true
            [bool]$semantic.behavior_test_passed | Should Be $true
            @($semantic.changed_files).Count | Should Be 1
            @($semantic.unexpected_files).Count | Should Be 0
            [int]$semantic.parser_exit_code | Should Be 0
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be "Write-Output 'before'`n"
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'adapts LF candidate text to a CRLF source without mutating production' {
        $fixtureRel = 'tod/out/tests/semantic-gate-crlf-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "function Test-One {`r`n    Write-Output 'before'`r`n}`r`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        $validation = 'powershell -NoProfile -Command ''$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "{0}"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}}''' -f $fixtureRel

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "function Test-One {`n    Write-Output 'before'`n}" `
                -NewText "function Test-One {`n    Write-Output 'after'`n}" `
                -ValidationCommand $validation `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'text_invariants'
                    required_contains = @("Write-Output 'after'")
                    forbidden_contains = @("Write-Output 'before'")
                })

            [string]$semantic.semantic_verdict | Should Be 'accept'
            [bool]$semantic.mutation_authority_allowed | Should Be $true
            [int]$semantic.anchor_match_count | Should Be 1
            [bool]$semantic.behavior_test_passed | Should Be $true
            [string]$semantic.resulting_diff.old_text | Should Match "`r`n"
            [string]$semantic.resulting_diff.new_text | Should Match "`r`n"
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a focused Pester validation as behavioral evidence without a text assertion' {
        $fixtureRel = 'tod/out/tests/semantic-gate-focused-' + [guid]::NewGuid().ToString('N') + '.Tests.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "function Get-SemanticGateValue {`r`n    'before'`r`n}`r`n`r`nDescribe 'semantic gate fixture' {`r`n    It 'returns before' {`r`n        Get-SemanticGateValue | Should Be 'before'`r`n    }`r`n}`r`n"
        $replacement = "function Get-SemanticGateValue {`n    'after'`n}`n`nDescribe 'semantic gate fixture' {`n    It 'returns after' {`n        Get-SemanticGateValue | Should Be 'after'`n    }`n}"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        $validation = 'Invoke-Pester -Path "{0}"' -f $fixtureRel

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText ($original -replace "`r`n", "`n") `
                -NewText $replacement `
                -ValidationCommand $validation

            [string]$semantic.semantic_verdict | Should Be 'accept'
            [string]$semantic.behavior_test | Should Be 'focused_validation_command'
            [bool]$semantic.behavior_test_passed | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps provider-candidate replan artifact-write tasks out of generic bounded execution' {
        $suffix = [guid]::NewGuid().ToString('N')
        $verdictRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_VERDICT_ARTIFACT_WRITE_$suffix.json"
        $requestRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_ARTIFACT_WRITE_$suffix.json"
        $candidateRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_ARTIFACT_WRITE_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REPLAN_ARTIFACT_WRITE_$suffix.json"
        $verdictAbs = Join-Path $repoRoot ($verdictRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $requestAbs = Join-Path $repoRoot ($requestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $candidateAbs = Join-Path $repoRoot ($candidateRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $verdictAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_verdict'
            verdict = 'reject'
            verdict_reason_code = 'rejected_no_delta_candidate'
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $verdictAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_engineering_provider_request'
            source_files_to_include = @('scripts/engines/LocalExecutionEngine.ps1')
            artifacts_to_include = @('runtime_remote_training/read_only_audit_artifacts/TOD_EXAMPLE_SOURCE_ANCHOR.latest.json')
            validation_command = 'Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1'
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $requestAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_engineering_provider_candidate_stub'
            target_file = 'scripts/engines/LocalExecutionEngine.ps1'
            old_text = 'same text'
            new_text = 'same text'
            validation_command = ''
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $candidateAbs -Encoding utf8

        $promptText = @"
Provider candidate rejection replan.
Input Artifact: $verdictRel. Supporting Artifact: $requestRel. Supporting Artifact: $candidateRel. Output Artifact: $outputRel. Required Artifact Type: tod_engineering_provider_candidate_replan. No source edits.
No source edits.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-PROVIDER-CANDIDATE-REPLAN-ARTIFACT-WRITE-TEST' `
            -ObjectiveId 'TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1' `
            -Title 'Provider candidate replan artifact-write lane test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write'; task_mode = 'implementation'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_provider_candidate_replan'
            [string]$artifact.input_candidate_verdict | Should Be $verdictRel
            [string]$artifact.input_provider_request | Should Be $requestRel
            [string]$artifact.input_candidate_stub | Should Be $candidateRel
            [bool]$artifact.provider_request_ready_for_retry | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
            [string]$result.summary | Should Match 'provider candidate replan'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $verdictAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $requestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $candidateAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'materializes corpus episode manifest from classifier artifact' {
        $suffix = [guid]::NewGuid().ToString('N')
        $classifierRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_CLASSIFIER_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_EPISODE_MANIFEST_OUTPUT_$suffix.json"
        $classifierAbs = Join-Path $repoRoot ($classifierRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $classifierAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_corpus_evidence_intake_classifier'
            objective_id = 'TOD-ENGINEERING-CORPUS-EVIDENCE-INTAKE-CLASSIFIER-V1'
            task_id = 'classifier-input'
            status = 'completed'
            candidate_inputs = @(
                [ordered]@{ path='runtime_remote_training/read_only_audit_artifacts/A.json'; artifact_type='tod_read_only_audit_artifact'; objective_id='A'; episode_candidate_quality='candidate'; likely_capability_classification='guided_scaffolded'; actual_author_signal='TOD'; borrowed_capability_signal='borrowed_present'; usable_for_corpus=$true; missing_episode_fields=@('final_outcome') },
                [ordered]@{ path='runtime_remote_training/read_only_audit_artifacts/B.json'; artifact_type='tod_semantic_source_audit_artifact'; objective_id='B'; episode_candidate_quality='candidate'; likely_capability_classification='blocked_or_failed'; actual_author_signal='Codex_or_mixed'; borrowed_capability_signal='borrowed_present'; usable_for_corpus=$true; missing_episode_fields=@() },
                [ordered]@{ path='runtime_remote_training/read_only_audit_artifacts/C.json'; artifact_type='tod_guided_capability_proof'; objective_id='C'; episode_candidate_quality='candidate'; likely_capability_classification='independent_or_claimed_independent'; actual_author_signal='TOD'; borrowed_capability_signal='no_credit_or_borrowed_not_reduced'; usable_for_corpus=$true; missing_episode_fields=@('next_training_rung') }
            )
            rejected_inputs = @()
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $classifierAbs -Encoding utf8

        $promptText = @"
Read-only corpus episode candidate manifest.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $classifierRel
Output Artifact: $outputRel

Required Artifact Type: tod_engineering_corpus_episode_candidate_manifest
Required Output Fields: artifact_type, objective_id, task_id, status, codex_role, source_classifier_artifact, episode_candidates, rejected_inputs, manifest_gaps, smallest_next_executable_shape, validation, prevention_lesson, independent_credit_requested, dave_needed

Mission: convert classified candidate_inputs into one reusable episode-candidate manifest. Do not run evidence-intake classification again.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-CORPUS-EPISODE-MANIFEST-TEST' `
            -ObjectiveId 'TOD-ENGINEERING-CORPUS-EPISODE-CANDIDATE-MANIFEST-V1B' `
            -Title 'Corpus episode candidate manifest routing test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_corpus_episode_candidate_manifest'
            @($artifact.episode_candidates).Count | Should Be 3
            [bool]$artifact.independent_credit_requested | Should Be $false
            [bool]$artifact.validation.no_source_code_modified | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $classifierAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'enriches corpus manifest with source-anchor episode' {
        $suffix = [guid]::NewGuid().ToString('N')
        $manifestRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_ENRICH_INPUT_$suffix.json"
        $anchorRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_SOURCE_ANCHOR_ENRICH_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_SOURCE_ANCHOR_ENRICH_OUTPUT_$suffix.json"
        $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $anchorAbs = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $manifestAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_corpus_episode_candidate_manifest'
            objective_id = 'TOD-ENGINEERING-CORPUS-EPISODE-CANDIDATE-MANIFEST-V1B'
            task_id = 'manifest-input'
            status = 'completed'
            episode_candidates = @(
                [ordered]@{ episode_id='episode-001'; source_artifact='runtime_remote_training/read_only_audit_artifacts/A.json'; source_artifact_type='tod_read_only_audit_artifact'; source_objective_id='A'; usable_for_training=$true }
            )
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestAbs -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            objective_id = 'TOD-MEANINGFUL-SAFE-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1'
            task_id = 'source-anchor-input'
            source_file = 'scripts/engines/LocalExecutionEngine.ps1'
            start_line = 10
            end_line = 12
            exact_text = 'candidate_ready = $false'
            no_code_changes = $true
            validation = @{ no_code_changes = $true }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $anchorAbs -Encoding utf8

        $promptText = @"
Read-only corpus source-anchor episode enrichment.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $manifestRel
Source Anchor Artifact: $anchorRel
Output Artifact: $outputRel

Required Artifact Type: tod_engineering_corpus_source_anchor_episode_enrichment
Required Output Fields: artifact_type, objective_id, task_id, status, codex_role, input_manifest_artifact, source_anchor_artifact, enriched_episode, updated_episode_count, source_anchor_episode_count, validation, prevention_lesson, independent_credit_requested, dave_needed

Mission: enrich this existing corpus episode manifest with one source-anchor observation episode. Do not rebuild the manifest from classifier inputs.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-CORPUS-SOURCE-ANCHOR-ENRICHMENT-TEST' `
            -ObjectiveId 'TOD-ENGINEERING-CORPUS-SOURCE-ANCHOR-EPISODE-ENRICHMENT-V1' `
            -Title 'Corpus source-anchor episode enrichment routing test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_corpus_source_anchor_episode_enrichment'
            [string]$artifact.status | Should Be 'completed'
            [int]$artifact.updated_episode_count | Should Be 2
            [int]$artifact.source_anchor_episode_count | Should Be 1
            [string]$artifact.enriched_episode.source_artifact_type | Should Be 'tod_source_anchor_observation'
            [string]$artifact.enriched_episode.source_file | Should Be 'scripts/engines/LocalExecutionEngine.ps1'
            [bool]$artifact.enriched_episode.exact_text_available | Should Be $true
            [bool]$artifact.validation.no_source_code_modified | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $manifestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'recognizes configured local engineering provider assets outside PATH' {
        $suffix = [guid]::NewGuid().ToString('N')
        $requestRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/engineering_corpus/TOD_PROVIDER_INVENTORY_OUTPUT_$suffix.json"
        $requestAbs = Join-Path $repoRoot ($requestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $serverRel = 'tools/llama.cpp/llama-server.exe'
        $modelRel = 'models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf'
        $serverAbs = Join-Path $repoRoot ($serverRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $modelAbs = Join-Path $repoRoot ($modelRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $createdServer = $false
        $createdModel = $false
        New-Item -ItemType Directory -Path (Split-Path -Parent $requestAbs) -Force | Out-Null
        if (-not (Test-Path -Path $serverAbs -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $serverAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($serverAbs, 'test llama server placeholder', (New-Object System.Text.UTF8Encoding($false)))
            $createdServer = $true
        }
        if (-not (Test-Path -Path $modelAbs -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $modelAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($modelAbs, 'test model placeholder', (New-Object System.Text.UTF8Encoding($false)))
            $createdModel = $true
        }
        [ordered]@{
            artifact_type = 'tod_engineering_provider_request'
            provider_request_ready = $true
            target_file = 'scripts/engines/LocalExecutionEngine.ps1'
            validation_command = 'focused provider inventory regression'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $requestAbs -Encoding utf8

        $promptText = @"
Read-only local engineering provider inventory artifact.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $requestRel
Output Artifact: $outputRel

Required Artifact Type: tod_local_engineering_provider_inventory
Required Output Fields: artifact_type, provider_request_ready, detected_tools, configured_provider_assets, running_provider_endpoint, real_provider_reachable, usable_provider_hook

Mission: inspect both PATH-visible tools and configured repo-local provider assets before deciding whether a provider hook is usable.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-PROVIDER-CONFIGURED-ASSETS-TEST' `
            -ObjectiveId 'TOD-LOCAL-PROVIDER-CONFIGURED-PATH-DISCOVERY-V1' `
            -Title 'Provider configured assets discovery test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_local_engineering_provider_inventory'
            [bool]$artifact.provider_request_ready | Should Be $true
            [bool]$artifact.configured_provider_assets.llama_server_exists | Should Be $true
            [bool]$artifact.configured_provider_assets.model_exists | Should Be $true
            [bool]$artifact.configured_provider_assets.configured_provider_available | Should Be $true
            [bool]$artifact.real_provider_reachable | Should Be $true
            [bool]$artifact.usable_provider_hook | Should Be $true
            [string]$artifact.next_smallest_rung | Should Be 'TOD-LOCAL-ENGINEERING-PROVIDER-CANDIDATE-INVOCATION-V1'
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $requestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
            if ($createdServer) {
                Remove-Item -Path $serverAbs -Force -ErrorAction SilentlyContinue
            }
            if ($createdModel) {
                Remove-Item -Path $modelAbs -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'blocks held-out candidate new text when manifest lacks source-anchor episode evidence' {
        $suffix = [guid]::NewGuid().ToString('N')
        $manifestRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_HELDOUT_NEWTEXT_OUTPUT_$suffix.json"
        $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $manifestAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_corpus_episode_candidate_manifest'
            objective_id = 'TOD-ENGINEERING-CORPUS-EPISODE-CANDIDATE-MANIFEST-V1B'
            task_id = 'manifest-input'
            status = 'completed'
            episode_candidates = @(
                [ordered]@{ episode_id='episode-001'; source_artifact='runtime_remote_training/read_only_audit_artifacts/A.json'; source_artifact_type='tod_read_only_audit_artifact'; source_objective_id='A'; usable_for_training=$true }
            )
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestAbs -Encoding utf8

        $promptText = @"
Read-only held-out candidate_new_text evaluation.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $manifestRel
Output Artifact: $outputRel

Required Artifact Type: tod_heldout_candidate_newtext_from_corpus_manifest
Required Output Fields: artifact_type, objective_id, task_id, status, codex_role, input_manifest_artifact, selected_episode, source_anchor_available, candidate_new_text, blocker, validation, prevention_lesson, independent_credit_requested, dave_needed

Mission: select a held-out episode and propose candidate_new_text only if source-anchor exact_text and source_file evidence exists.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-HELDOUT-NEWTEXT-TEST' `
            -ObjectiveId 'TOD-HELDOUT-CANDIDATE-NEWTEXT-FROM-CORPUS-MANIFEST-V1' `
            -Title 'Held-out candidate new text source-anchor boundary test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_heldout_candidate_newtext_from_corpus_manifest'
            [bool]$artifact.source_anchor_available | Should Be $false
            [string]$artifact.candidate_new_text | Should Be ''
            [string]$artifact.blocker.reason_code | Should Be 'heldout_episode_source_anchor_missing'
            [bool]$artifact.validation.no_source_code_modified | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $manifestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'evaluates held-out candidate new text from enriched corpus without rerunning enrichment' {
        $suffix = [guid]::NewGuid().ToString('N')
        $manifestRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_ENRICHED_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_HELDOUT_ENRICHED_OUTPUT_$suffix.json"
        $manifestAbs = Join-Path $repoRoot ($manifestRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $manifestAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_corpus_source_anchor_episode_enrichment'
            objective_id = 'TOD-ENGINEERING-CORPUS-SOURCE-ANCHOR-EPISODE-ENRICHMENT-V1'
            task_id = 'enriched-input'
            status = 'completed'
            episode_candidates = @(
                [ordered]@{
                    episode_id = 'episode-005'
                    source_artifact = 'runtime_remote_training/read_only_audit_artifacts/source-anchor.json'
                    source_artifact_type = 'tod_source_anchor_observation'
                    source_objective_id = 'TOD-MEANINGFUL-SAFE-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1'
                    source_file = 'scripts/engines/LocalExecutionEngine.ps1'
                    exact_text_available = $true
                    usable_for_training = $true
                }
            )
            validation = @{ no_source_code_modified = $true }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $manifestAbs -Encoding utf8

        $promptText = @"
Read-only held-out candidate_new_text evaluation from enriched corpus.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $manifestRel
Output Artifact: $outputRel

Required Artifact Type: tod_heldout_candidate_newtext_from_corpus_manifest
Required Output Fields: artifact_type, objective_id, task_id, status, codex_role, input_manifest_artifact, selected_episode, source_anchor_available, candidate_new_text, blocker, validation, prevention_lesson, independent_credit_requested, dave_needed

Mission: select a held-out episode from the enriched corpus and propose candidate_new_text only if source-anchor exact_text and source_file evidence exists.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-HELDOUT-ENRICHED-NEWTEXT-TEST' `
            -ObjectiveId 'TOD-HELDOUT-CANDIDATE-NEWTEXT-FROM-ENRICHED-CORPUS-MANIFEST-V1' `
            -Title 'Held-out candidate new text enriched corpus selector test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_heldout_candidate_newtext_from_corpus_manifest'
            [string]$artifact.selected_episode.episode_id | Should Be 'episode-005'
            [bool]$artifact.source_anchor_available | Should Be $true
            [string]$artifact.candidate_new_text | Should Be ''
            [string]$artifact.blocker.reason_code | Should Be 'autonomous_candidate_new_text_missing'
            [bool]$artifact.validation.no_source_code_modified | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $manifestAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'publishes durable engineering episode card into corpus safe root' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_EPISODE_CARD_INPUT_$suffix.json"
        $outputRel = "runtime/tod_engineering_corpus/TOD_ENGINEERING_EPISODE_CARD_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_read_only_audit_artifact'
            objective_id = 'TOD-ENGINEERING-CORPUS-FOUNDATION-V1'
            task_id = 'episode-card-input'
            status = 'blocked'
            problem_statement = 'TOD generated useful validation evidence but did not publish a durable engineering episode.'
            attempted_actions = @('classified evidence', 'validated output absence')
            diagnosis = 'episode_card_not_written'
            debt_category = 'runtime_plumbing'
            prevention_lesson = 'Engineering evidence must be preserved as reusable corpus episodes.'
            next_training_rung = 'TOD-ENGINEERING-EPISODE-WRITER-LANE-V1'
            validation = @{ passed = $false; reason = 'episode card missing' }
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only engineering episode card publication.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $inputRel
Output Artifact: $outputRel

Required Artifact Type: tod_engineering_episode_card
Required Output Fields: artifact_type, episode_id, objective_id, task_id, problem_statement, attempted_actions, evidence_artifacts, diagnosis, debt_category, borrowed_vs_independent, lesson, smallest_next_repair, validation_summary, no_source_edits, independent_credit_requested, dave_needed

Mission: write a durable TOD engineering episode card from the supplied validation evidence. Do not modify source code and do not publish a generic audit wrapper.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-ENGINEERING-EPISODE-CARD-TEST' `
            -ObjectiveId 'TOD-ENGINEERING-EPISODE-WRITER-LANE-V1' `
            -Title 'Engineering episode card writer lane test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_episode_card'
            [string]$artifact.source_artifact | Should Be $inputRel
            [string]$artifact.problem_statement | Should Be 'TOD generated useful validation evidence but did not publish a durable engineering episode.'
            [string]$artifact.debt_category | Should Be 'runtime_plumbing'
            [bool]$artifact.no_source_edits | Should Be $true
            [bool]$artifact.independent_credit_requested | Should Be $false
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'selects an engineering episode source from evidence root without treating exclusions as target files' {
        $suffix = [guid]::NewGuid().ToString('N')
        $rootRel = "runtime_remote_training/read_only_audit_artifacts/episode_selection_$suffix"
        $outputRootRel = "runtime/tod_engineering_corpus/episode_selection_$suffix"
        $rootAbs = Join-Path $repoRoot ($rootRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputRootAbs = Join-Path $repoRoot ($outputRootRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path $rootAbs -Force | Out-Null
        New-Item -ItemType Directory -Path $outputRootAbs -Force | Out-Null
        [ordered]@{
            artifact_type = 'codex_validation'
            objective_id = 'EXCLUDED'
            task_id = 'excluded'
            verdict = 'excluded_example'
        } | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $rootAbs 'excluded_one.codex_validation.json') -Encoding utf8
        [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            objective_id = 'TOD-FRESH-SOURCE-SELECTION'
            task_id = 'fresh-source'
            problem_statement = 'TOD needs to select the fresh evidence source instead of treating exclusions as targets.'
            validation = @{ source_read = $true; anchor_found = $true; source_edits = @() }
            lesson = 'Evidence-root source selection must choose usable source evidence and ignore explicit exclusions.'
        } | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $rootAbs 'fresh_source.latest.json') -Encoding utf8

        $promptText = @"
Read-only engineering episode selection and publication.
Task Mode: read_only_assessment
Task Category: inspection_only
Evidence Root: $rootRel
Output Root: $outputRootRel
Required Artifact Type: tod_engineering_episode_card.
Mission: choose one fresh engineering-relevant validation or blocker artifact that is not excluded_one.codex_validation.json and not missing_example.latest.json, then publish one durable engineering episode card under the output root.
Required Output Fields: artifact_type, episode_id, objective_id, task_id, source_artifact, problem_statement, attempted_actions, evidence_artifacts, diagnosis, debt_category, borrowed_vs_independent, lesson, smallest_next_repair, validation_summary, no_source_edits, independent_credit_requested, dave_needed
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-ENGINEERING-EPISODE-SELECTION-TEST' `
            -ObjectiveId 'TOD-ENGINEERING-EPISODE-WRITER-INDEPENDENT-SELECTION-V1' `
            -Title 'Engineering episode source selection test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = ''; local_fallback_target_files = @('excluded_one.codex_validation.json', 'missing_example.latest.json') }
        $context.allowed_files = @('excluded_one.codex_validation.json', 'missing_example.latest.json')

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $expectedOutputRel = "$outputRootRel/fresh_source.latest.episode.json"
            $expectedOutputAbs = Join-Path $repoRoot ($expectedOutputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $artifact = Get-Content -Path $expectedOutputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_episode_card'
            [string]$artifact.source_artifact | Should Be "$rootRel/fresh_source.latest.json"
            [string]$artifact.selected_source_reason | Should Match 'selected_from_evidence_root'
            [string]$artifact.selected_source_reason | Should Match 'excluded:2'
            [bool]$artifact.no_source_edits | Should Be $true
            [bool]$artifact.independent_credit_requested | Should Be $false
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $rootAbs -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputRootAbs -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'quality-gates runtime-support episode cards without reducing borrowed capability' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime/tod_engineering_corpus/TOD_ENGINEERING_EPISODE_QUALITY_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_EPISODE_QUALITY_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_engineering_episode_card'
            generated_at = '2026-07-24T08:06:05Z'
            source = 'local_execution_read_only_audit_artifact_lane'
            episode_id = 'runtime-support-episode'
            objective_id = 'TOD-ENGINEERING-CORPUS-FOUNDATION-V1'
            task_id = 'runtime-support-task'
            status = 'recorded'
            source_artifact = 'runtime_remote_training/read_only_audit_artifacts/source.json'
            source_artifact_type = 'tod_source_anchor_observation'
            problem_statement = 'TOD learned how to select evidence-root input for a corpus episode.'
            attempted_actions = @('read source evidence', 'publish episode card')
            evidence_artifacts = @('runtime_remote_training/read_only_audit_artifacts/source.json')
            diagnosis = 'evidence root source selection worked after runtime support was added'
            debt_category = 'runtime_plumbing'
            borrowed_vs_independent = 'borrowed_or_codex_involved'
            lesson = 'Runtime support episodes are useful but do not prove independent engineering.'
            smallest_next_repair = 'Run Examiner review before granting progress credit.'
            validation_summary = @{ source_read = $true; artifact_written = $true }
            blocker = @{}
            no_source_edits = $true
            independent_credit_requested = $false
            dave_needed = 'no'
        } | ConvertTo-Json -Depth 12 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only engineering episode quality examination.
Task Mode: read_only_assessment
Task Category: inspection_only
Input Artifact: $inputRel
Output Artifact: $outputRel
Required Artifact Type: tod_engineering_episode_quality_examiner_verdict
Mission: evaluate whether this episode card should reduce borrowed engineering capability. Do not modify source code.
Required Output Fields: artifact_type, input_episode_artifact, episode_id, episode_debt_category, training_usefulness, engineering_credit_allowed, runtime_support_credit_allowed, borrowed_capability_ratio_effect, verdict_reason, smallest_next_training_rung, prevention_lesson, independent_credit_requested, dave_needed
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-ENGINEERING-EPISODE-QUALITY-EXAMINER-TEST' `
            -ObjectiveId 'TOD-ENGINEERING-EPISODE-QUALITY-EXAMINER-V1' `
            -Title 'Engineering episode quality examiner test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'inspection_only'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_engineering_episode_quality_examiner_verdict'
            [string]$artifact.training_usefulness | Should Be 'accept_runtime_support_only'
            [bool]$artifact.engineering_credit_allowed | Should Be $false
            [bool]$artifact.runtime_support_credit_allowed | Should Be $true
            [string]$artifact.borrowed_capability_ratio_effect | Should Be 'no_reduction'
            [string]$artifact.smallest_next_training_rung | Should Match 'fresh engineering episode'
            [string]$artifact.pass_or_reject | Should Be 'pass'
            @($artifact.missing_fields).Count | Should Be 0
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves credit decisions when auditing packet-quality review artifacts' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_QUALITY_CREDIT_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_QUALITY_CREDIT_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_packet_quality_review_artifact'
            generated_at = '2026-07-22T23:59:00Z'
            source = 'packet_quality_review'
            decision = 'reject_packet'
            failure_reason_or_acceptance_reason = @(
                'new_text does not contain required semantic pattern: New-LocalExecutionPacketCandidateArtifact',
                'new_text contains forbidden semantic pattern: TOD training marker'
            )
            next_smaller_repair_step = 'Return to packet materialization requiring non-duplicative behavior-changing new_text.'
            credit_decision = [ordered]@{
                independent_tod_resolution = $false
                meaningful_tod_implementation = $false
                validated_tod_edit = $false
                reason = 'Quality review artifact only; no product code changed.'
            }
            evidence_checked = @('target file', 'semantic new text', 'validation command')
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only assessment.
Input Evidence: $inputRel
Output Artifact: $outputRel
Audit Subject: packet quality credit decision.
Use the read-only audit artifact lane.
No code changes.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-PACKET-QUALITY-CREDIT-AUDIT-TEST' `
            -ObjectiveId 'TOD-ARTIFACT-WRITE-MODE-EXECUTION-GAP-V1' `
            -Title 'Packet quality credit audit test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @($result.files_changed) -contains $outputRel | Should Be $true
            [string]$artifact.artifact_type | Should Be 'tod_read_only_audit_artifact'
            [string]$artifact.source | Should Be 'local_execution_read_only_audit_artifact_lane'
            @($artifact.inspected_files) -contains $inputRel | Should Be $true
            [string]$artifact.classification | Should Be 'credit_decision_review_required'
            @($artifact.evidence_used[0].fields) -contains 'credit_decision' | Should Be $true
            @($artifact.findings | Where-Object { [string]$_.finding -eq 'visible_credit_decision' -and [string]$_.evidence -match 'independent_tod_resolution=False' }).Count | Should Be 1
            @($artifact.findings | Where-Object { [string]$_.finding -eq 'packet_rejection_or_acceptance_reason' -and [string]$_.evidence -match 'TOD training marker' }).Count | Should Be 1
            @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'credit_decision_blocks_independent_progress' }).Count | Should Be 1
            [bool]$artifact.no_code_changes | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionReadOnlyAuditArtifact'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects read-only artifacts that miss requested contract fields' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CONTRACT_FIELD_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_CONTRACT_FIELD_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_read_only_audit_artifact'
            objective_id = 'TOD-ARTIFACT-WRITE-MODE-EXECUTION-GAP-V1'
            task_id = 'tod-artifact-write-mode-next-executable-shape-r1'
            blockers = @(
                [ordered]@{
                    reason_code = 'credit_decision_blocks_independent_progress'
                    reason = 'Quality review artifact only; no product code changed.'
                }
            )
            no_code_changes = $true
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only assessment.
Input Evidence: $inputRel
Output Artifact: $outputRel
Mission: review whether the prior artifact satisfied its requested output contract. Required checks: objective_id present, task_id present, evidence_read present, credit_decision_seen present, blocker_seen present, next_training_rung present, required_task_mode present, required_target_selection_rule present, required_packet_fields present, validation_command present, expected_evidence present, dave_needed present. If fields are missing, reject the prior artifact and name the smallest next repair.
Acceptance: publish pass_or_reject, missing_fields, reason, and next_smaller_repair_step.
Do not modify source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-CONTRACT-FIELD-EVALUATION-TEST' `
            -ObjectiveId 'TOD-READONLY-CONTRACT-FIELD-EVALUATION-V1' `
            -Title 'Contract field evaluation test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @($result.files_changed) -contains $outputRel | Should Be $true
            [string]$artifact.classification | Should Be 'contract_field_evaluation_failed'
            [string]$artifact.pass_or_reject | Should Be 'reject'
            @($artifact.required_fields) -contains 'credit_decision_seen' | Should Be $true
            @($artifact.missing_fields) -contains 'credit_decision_seen' | Should Be $true
            @($artifact.missing_fields) -contains 'required_packet_fields' | Should Be $true
            [string]$artifact.reason | Should Match 'missing required contract fields'
            [string]$artifact.next_smaller_repair_step | Should Match 'contract-field evaluation'
            @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'contract_required_fields_missing' }).Count | Should Be 1
            [bool]$artifact.validation.required_fields_present | Should Be $false
            [string]$artifact.dave_needed | Should Be 'no'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'publishes autonomous new_text synthesis blocker for source-anchor synthesis tasks' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_REQUIRED_TYPE_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_REQUIRED_TYPE_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_source_anchor_delta_proposal'
            status = 'blocked'
            blocker = [ordered]@{ reason_code = 'autonomous_candidate_new_text_missing' }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only assessment.
Input Artifact: $inputRel
Output Artifact: $outputRel
Required Artifact Type: tod_autonomous_meaningful_newtext_synthesis
Mission: produce the requested artifact type or block precisely.
Do not modify source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-REQUIRED-ARTIFACT-TYPE-GUARD-TEST' `
            -ObjectiveId 'TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1' `
            -Title 'Required artifact type guard test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            Test-Path -Path $outputAbs | Should Be $true
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
            [string]$artifact.artifact_type | Should Be 'tod_autonomous_meaningful_newtext_synthesis'
            [string]$artifact.status | Should Be 'blocked'
            [string]$artifact.blocker.reason_code | Should Be 'source_anchor_input_invalid'
            [bool]$artifact.independent_credit_requested | Should Be $false
            [bool]$artifact.no_source_code_modified | Should Be $true
            [bool]$artifact.validation.new_text_nonempty | Should Be $false
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'routes explicit Input Patch read-only assessments to the patch-evidence lane' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/cleanup_holds/TOD_INPUT_PATCH_AUTHORITY_TEST_$suffix.patch"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_INPUT_PATCH_AUTHORITY_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        @"
diff --git a/tmp_remote_mim/core/routers/studio.py b/tmp_remote_mim/core/routers/studio.py
--- a/tmp_remote_mim/core/routers/studio.py
+++ b/tmp_remote_mim/core/routers/studio.py
@@
+Recommended action: append an operator contract.
+relationship_type = 'facility_location'
+final_authority = 'route_template'
"@ | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only assessment.
Input Patch: $inputRel
Output Artifact: $outputRel
Mission: classify patch evidence for route-level hardcoded response authority, operator-contract authority, reusable service candidates, process support, and learned-capability return paths.
Do not modify source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-INPUT-PATCH-AUTHORITY-TEST' `
            -ObjectiveId 'TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1' `
            -Title 'Input Patch authority classification test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @($result.files_changed) -contains $outputRel | Should Be $true
            [string]$artifact.artifact_type | Should Be 'tod_patch_evidence_authority_classification'
            [string]$artifact.source | Should Be 'local_execution_patch_evidence_artifact_lane'
            [string]$artifact.input_patch | Should Be $inputRel
            [int]$artifact.classification_counts.operator_contract_authority_risk | Should Be 1
            [int]$artifact.classification_counts.reusable_service_candidate | Should Be 1
            @($artifact.signals | Where-Object { [string]$_.signal -eq 'operator_contract_injection' }).Count | Should Be 1
            @($artifact.signals | Where-Object { [string]$_.signal -eq 'observational_relationship_memory' }).Count | Should Be 1
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionPatchEvidenceArtifact'
            [bool]$artifact.no_code_changes | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'synthesizes a service-extraction plan from patch authority classification evidence' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_SERVICE_EXTRACTION_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_SERVICE_EXTRACTION_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
        [ordered]@{
            artifact_type = 'tod_patch_evidence_authority_classification'
            classification_counts = [ordered]@{
                reusable_service_candidate = 2
                hardcoded_response_authority_risk = 1
                operator_contract_authority_risk = 1
            }
            signals = @(
                [ordered]@{ signal = 'active_conversation_state'; bucket = 'reusable_service_candidate'; match_count = 12 },
                [ordered]@{ signal = 'observational_relationship_memory'; bucket = 'reusable_service_candidate'; match_count = 44 },
                [ordered]@{ signal = 'operator_contract_injection'; bucket = 'operator_contract_authority_risk'; match_count = 3 }
            )
            continuation_action = 'Select one reusable service candidate and define generalized tests.'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only assessment.
Input Evidence: $inputRel
Output Artifact: $outputRel
Mission: select one reusable_service_candidate and produce a service-extraction plan with service boundary and generalized tests.
Do not modify source code.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-SERVICE-EXTRACTION-TEST' `
            -ObjectiveId 'TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1' `
            -Title 'Service extraction plan test' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_route_service_extraction_plan'
            [string]$artifact.classification | Should Be 'patch_authority_service_extraction_plan'
            [string]$artifact.selected_service_candidate.signal | Should Be 'observational_relationship_memory'
            [string]$artifact.service_boundary | Should Match 'observational_relationship_memory'
            @($artifact.forbidden_route_response_authority | Where-Object { [string]$_ -match 'route-level fixed visible replies' }).Count | Should Be 1
            @($artifact.generalized_tests | Where-Object { [string]$_ -match 'highest-evidence candidate' }).Count | Should Be 1
            [string]$artifact.prevention_lesson | Should Match 'service boundary'
            [string]$artifact.dave_needed | Should Be 'no'
            [bool]$artifact.no_code_changes | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'patches a bounded docs file and records execution evidence' {
        $relativePath = ('docs/local-fallback-docs-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Temp`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Local Fallback Executor section." -f $relativePath)
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-DOCS' -ObjectiveId 'OBJ-LF' -Title 'Update fallback docs' -Scope ("Update {0} with a short Local Fallback Executor section." -f $relativePath) -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        @($result.files_changed).Count | Should Be 1
        [string]@($result.files_changed)[0] | Should Be $relativePath
        [string]$result.diff_summary | Should Match 'markdown section'
        @($result.validation_results).Count | Should BeGreaterThan 0
        @($result.commands_run).Count | Should Be 1
        [string]$result.confidence | Should Be 'medium-high'
        [string]$result.rollback_hint | Should Match 'Copy-Item'
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match '## Local Fallback Executor'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'patches a bounded allowed source file for code_change tasks' {
        $relativePath = ('scripts/local-fallback-code-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'OLD_SENTINEL'`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
Validation Pattern: NEW_SENTINEL
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-CODE' -ObjectiveId 'OBJ-LF' -Title 'Patch allowed source file' -Scope ("Patch $relativePath with a bounded replace_text change.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        [string]@($result.files_changed)[0] | Should Be $relativePath
        [string]$result.diff_summary | Should Match 'Replaced bounded text'
        @($result.validation_results | Where-Object { [string]$_.name -eq 'focused_validation_exit_zero' -and [bool]$_.passed }).Count | Should Be 1
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'NEW_SENTINEL'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'blocks replace_text writeback when the bounded edit would unexpectedly inflate the file' {
        $relativePath = ('scripts/local-fallback-size-guard-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $sourceRelativePath = ('tests/local-fallback-size-guard-new-text-{0}.txt' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $sourcePath = Join-Path $repoRoot ($sourceRelativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'OLD_SENTINEL'`n", (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($sourcePath, ("Write-Output '" + ("X" * 1200000) + "'`n"), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text Source File: $sourceRelativePath
Validation Pattern: X
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-SIZE-GUARD' -ObjectiveId 'OBJ-LF' -Title 'Block oversized bounded write' -Scope ("Patch $relativePath with a bounded replace_text change.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }
        $context.allowed_files = @($relativePath)

        $result = Invoke-LocalExecutionEngine -Context $context
        $current = [string](Get-Content -Path $absolutePath -Raw)

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_write_size_guard'
        [string]$result.blockers[0].missing_variable | Should Be 'bounded_write_size'
        $current | Should Match 'OLD_SENTINEL'
        $current | Should Not Match 'XXXXXXXXXX'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
        Remove-Item -Path $sourcePath -Force
    }

    It 'honors replace_text Occurrence last for self-editing prompt text' {
        $relativePath = ('scripts/local-fallback-occurrence-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'TARGET'`nWrite-Output 'TARGET'`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: replace_text
Occurrence: last
Minimum Occurrences: 2
Old Text: Write-Output 'TARGET'
New Text: Write-Output 'TARGET_LAST_REPLACED'
Validation Pattern: TARGET_LAST_REPLACED
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-OCCURRENCE-LAST' -ObjectiveId 'OBJ-LF' -Title 'Patch last occurrence' -Scope ("Patch $relativePath with a bounded replace_text change against the last occurrence.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

        $result = Invoke-LocalExecutionEngine -Context $context
        $updated = [string](Get-Content -Path $absolutePath -Raw)

        [string]$result.status | Should Be 'completed'
        [string]@($result.files_changed)[0] | Should Be $relativePath
        ($updated.IndexOf("Write-Output 'TARGET'") -lt $updated.IndexOf("Write-Output 'TARGET_LAST_REPLACED'")) | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'parks stale recovery replace_text when validation pattern is already present' {
        $relativePath = ('scripts/local-fallback-stale-recovery-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "Write-Output 'REQUESTED_STATE_PRESENT'`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Target File: $relativePath
Recovery Mode: failed_material_patch
Required behavior: when a failed recovery task's old replace_text snippet is absent but its validation pattern is already present, park it as already_satisfied_with_evidence.
Edit Mode: replace_text
Old Text: OLD_STATE_THAT_IS_GONE
New Text: Write-Output 'REQUESTED_STATE_PRESENT'
Validation Pattern: REQUESTED_STATE_PRESENT
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-STALE-RECOVERY' -ObjectiveId 'OBJ-LF' -Title 'Park stale recovery' -Scope ("Recover stale failed-patch task for $relativePath.") -PromptPath $promptPath -Metadata @{ task_category = 'code_change'; local_fallback_target_file = $relativePath }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        [bool]$result.no_change_required | Should Be $true
        @($result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count | Should Be 0
        [string]$result.diff_summary | Should Match 'Parked stale recovery'
        @($result.validation_results | Where-Object { [string]$_.name -eq 'stale_recovery_already_satisfied_no_file_change_expected' -and [bool]$_.passed }).Count | Should Be 1
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'REQUESTED_STATE_PRESENT'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'writes corrected patch synthesis practice evidence with inspected current-code anchors' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-practice-' + [guid]::NewGuid().ToString('N'))
        $target = Join-Path $tempRoot 'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json'
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $inspectedTarget = Join-Path $tempRoot 'scripts/generate_mim_tod_training_scoreboard.py'
            New-Item -ItemType Directory -Path (Split-Path -Parent $inspectedTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($inspectedTarget, 'print("scoreboard")', (New-Object System.Text.UTF8Encoding($false)))

            $seed = [pscustomobject]@{
                status = 'ready_for_tod_attempt'
                exercise_id = 'practice-test'
                required_outputs = @('inspected_target_file', 'current_anchor_line_or_hash', 'credit_decision')
            } | ConvertTo-Json -Depth 5
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, $seed, (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json
Edit Mode: artifact_write
Practice-only task for TOD-CORRECTED-PATCH-SYNTHESIS-PRACTICE-V1.
Produce a result artifact that fills these required_output fields: inspected_target_file, current_anchor_line_or_hash, why_inherited_old_text_is_stale_or_safe, proposed_edit_mode, proposed_old_text_or_exact_blocker, proposed_new_text_or_exact_blocker, validation_command, expected_validation_pattern, credit_decision.
'@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PRACTICE-ARTIFACT' -ObjectiveId 'OBJ-LF' -Title 'Practice artifact write' -Scope 'Produce corrected patch synthesis practice evidence.' -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains 'runtime_remote_training/TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json') | Should Be $true
            [string]$updated.status | Should Be 'practice_blocked_with_current_code_inspection'
            [bool]$updated.required_outputs_filled | Should Be $true
            [string]$updated.target.inspected_target_file | Should Be 'scripts/generate_mim_tod_training_scoreboard.py'
            [string]$updated.target.credit_decision | Should Be 'no_credit_practice_blocker_only'
            [string]$updated.target.current_anchor_line_or_hash | Should Match 'sha256:'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'writes different-target discovery evidence even when scope names forbidden paths' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tools/score_mim_operator_impact_live_10.py',
                'tools/build_mim_operator_impact_scorecard.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: scripts/run_mim_durability_smoke_v2.py, tmp_remote_mim/core/routers/gateway.py, core/routers/gateway.py
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Inspect at least three current-code files, but do not patch scripts/run_mim_durability_smoke_v2.py, tmp_remote_mim/core/routers/gateway.py, or core/routers/gateway.py.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-DISCOVERY' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery drill' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$result.summary | Should Match 'selected tmp_remote_mim/core/routers/studio.py'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'candidate_selected'
            @($updated.inspected_files).Count | Should BeGreaterThan 2
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            @($updated.selected_candidate_or_none.expected_changed_files) -contains 'tmp_remote_mim/tests/test_studio_training_chat.py' | Should Be $true
            [string]$updated.credit_decision.reason | Should Match 'Discovery artifact only'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'publishes no-candidate target-selection evidence instead of using stale fallback targets' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-target-selection-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tools/score_mim_operator_impact_live_10.py',
                'tools/build_mim_operator_impact_scorecard.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @'
Objective: TOD-INDEPENDENT-STATUS-TRUTH-REPRODUCTION-V1B
Task mode: target_selection
Select one fresh target for a later bounded edit packet.
Do not modify source code during target selection.
Required output fields: inspected_candidates, selected_target, rejected_candidates, selection_reason, validation_plan, next_bounded_packet_requirements
'@
            $scope = 'Select one fresh target for a later bounded edit packet, but do not modify source code during target selection.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-TARGET-SELECTION' -ObjectiveId 'OBJ-LF' -Title 'Target selection before bounded packet materialization' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'target_selection' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'blocked'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            @($result.failures) -contains 'target_selection_no_candidate_available' | Should Be $true
            @($result.test_results) -contains 'fail' | Should Be $true
            [string]$updated.artifact_type | Should Be 'tod_target_selection_artifact'
            [string]$updated.status | Should Be 'no_candidate_available'
            [string]$updated.selected_target | Should Be ''
            $updated.selected_candidate_or_none | Should Be $null
            [string]$updated.selection_reason | Should Match 'Target-selection tasks require input evidence'
            @($updated.inspected_candidates).Count | Should Be 0
            @($updated.next_bounded_packet_requirements) -contains 'target_file' | Should Be $true
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'selects a semantic source anchor and keeps anchor evidence bounded' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-anchor-selection-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/AnchorSelectionFixture.ps1'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_ANCHOR_SELECTION_TEST.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            $fixtureLines = [System.Collections.Generic.List[string]]::new()
            [void]$fixtureLines.Add('$ErrorActionPreference = "Stop"')
            [void]$fixtureLines.Add('')
            [void]$fixtureLines.Add('function Invoke-MeaningfulAnchorSelection {')
            [void]$fixtureLines.Add('    return "selected"')
            [void]$fixtureLines.Add('}')
            for ($i = 1; $i -le 80; $i++) {
                [void]$fixtureLines.Add(('function Invoke-FixtureCandidate{0} {{ return {0} }}' -f $i))
            }
            [System.IO.File]::WriteAllText($sourceAbs, ($fixtureLines -join [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Objective: TOD-ANCHOR-SELECTION-QUALITY-V1
Task mode: anchor_selection
Select one fresh current-code anchor for a later bounded packet.
Source File: $sourceRel
Output: $outputRel
Mission: Select a unique semantic source anchor. Do not select boilerplate assignments.
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-ANCHOR-SELECTION-QUALITY' -ObjectiveId 'OBJ-LF' -Title 'Anchor selection quality drill' -Scope 'Select a unique semantic source anchor from current code without source edits.' -PromptPath $promptPath -Metadata @{ task_category = 'anchor_selection' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.selected_anchor_pattern | Should Be 'function Invoke-MeaningfulAnchorSelection {'
            [bool]$updated.source_read | Should Be $true
            [bool]$updated.selected_anchor_nonempty | Should Be $true
            [bool]$updated.selected_anchor_unique | Should Be $true
            [int]$updated.selected_line | Should Be 3
            [int]$updated.candidate_count | Should BeGreaterThan 50
            @($updated.inspected_candidates).Count | Should BeLessThan 51
            @($updated.inspected_candidates | Where-Object { [string]$_.anchor_pattern -eq '$ErrorActionPreference = "Stop"' }).Count | Should Be 1
            @($updated.inspected_candidates | Where-Object { [string]$_.anchor_pattern -eq 'function Invoke-MeaningfulAnchorSelection {' }).Count | Should Be 1

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'keeps explicit anchor_selection ahead of broad route patch evidence classification' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-anchor-selection-precedence-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'tmp_remote_mim/core/routers/tod_ui.py'
        $patchRel = 'runtime_remote_training/cleanup_holds/TOD_TEST_ROUTE_AUTHORITY.patch'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_ANCHOR_SELECTION_PRECEDENCE.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $patchAbs = Join-Path $tempRoot ($patchRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @"
def helper():
    return "fixture"

def build_tod_live_context_panel():
    return {"status": "live"}
"@, (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $patchAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($patchAbs, @"
diff --git a/tmp_remote_mim/core/routers/studio.py b/tmp_remote_mim/core/routers/studio.py
--- a/tmp_remote_mim/core/routers/studio.py
+++ b/tmp_remote_mim/core/routers/studio.py
@@
-old route authority
+new route authority
"@, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: anchor_selection
Select one unique current-code anchor for a later bounded packet.
Source File: $sourceRel
Input Patch: $patchRel
Output: $outputRel
Mission: Route patch evidence is only input context. The explicit task is anchor selection against the Source File. Do not classify the patch.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-ANCHOR-SELECTION-PRECEDENCE' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Anchor selection outranks route patch evidence' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'anchor_selection' }

            $result = Invoke-LocalExecutionEngine -Context $context

            if ([string]$result.status -ne 'completed') {
                throw ($result | ConvertTo-Json -Depth 8)
            }
            [string]$result.status | Should Be 'completed'
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
            [string]$artifact.artifact_type | Should Be 'tod_anchor_selection_artifact'
            [string]$artifact.source_file | Should Be $sourceRel
            [string]$artifact.selected_anchor_pattern | Should Not BeNullOrEmpty
            [string]$result.summary | Should Match 'anchor selection'
            [string]$result.summary | Should Not Match 'route patch evidence'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'preserves package task category when runtime metadata is missing' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-anchor-selection-package-category-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'tmp_remote_mim/core/routers/tod_ui.py'
        $patchRel = 'runtime_remote_training/cleanup_holds/TOD_TEST_ROUTE_AUTHORITY.patch'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_ANCHOR_SELECTION_PACKAGE_CATEGORY.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $patchAbs = Join-Path $tempRoot ($patchRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @"
def helper():
    return "fixture"

def build_tod_live_context_panel():
    return {"status": "live"}
"@, (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $patchAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($patchAbs, @"
diff --git a/tmp_remote_mim/core/routers/studio.py b/tmp_remote_mim/core/routers/studio.py
--- a/tmp_remote_mim/core/routers/studio.py
+++ b/tmp_remote_mim/core/routers/studio.py
@@
-old route authority
+new route authority
"@, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
- Task Type: read_only_assessment
- Task Category: anchor_selection
Select one unique current-code anchor for a later bounded packet.
Source File: $sourceRel
Input Patch: $patchRel
Output: $outputRel
Mission: Route patch evidence is only input context. The explicit task is anchor selection against the Source File. Do not classify the patch.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-ANCHOR-SELECTION-PACKAGE-CATEGORY' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Anchor selection package category fallback' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{}

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
            [string]$artifact.artifact_type | Should Be 'tod_anchor_selection_artifact'
            [string]$artifact.source_file | Should Be $sourceRel
            [string]$artifact.selected_anchor_pattern | Should Not BeNullOrEmpty
            [string]$result.summary | Should Match 'anchor selection'
            [string]$result.summary | Should Not Match 'route patch evidence'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'resolves anchor selection source file from combined task scope when package metadata wraps it' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-anchor-selection-combined-scope-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'tmp_remote_mim/core/routers/tod_ui.py'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_ANCHOR_SELECTION_COMBINED_SCOPE.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @"
def helper():
    return "fixture"

def build_tod_live_context_panel():
    return {"status": "live"}
"@, (New-Object System.Text.UTF8Encoding($false)))

            $scopeText = @"
Source File: $sourceRel
Output: $outputRel
Mission: Select one unique current-code anchor from the source file and write the evidence artifact.
Required evidence: source_read=true, selected_anchor_nonempty=true, selected_anchor_unique=true, no_code_changes=true, continuation_action present for source-anchor observation.
"@
            $promptText = @"
- Task Type: read_only_assessment
- Task Category: anchor_selection
- Scope: $scopeText
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-ANCHOR-SELECTION-COMBINED-SCOPE' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Anchor selection source role from combined scope' `
                -Scope $scopeText `
                -PromptPath $promptPath `
                -Metadata @{}

            $detectedCategory = Get-LocalExecutionTaskCategory -Context $context
            $detectedSpec = Get-LocalExecutionAnchorSelectionSpec -Context $context
            $detectedAsAnchor = Test-LocalExecutionAnchorSelectionTask -Context $context
            [string]$detectedCategory | Should Be 'anchor_selection'
            [string]$detectedSpec.source_file | Should Be $sourceRel
            [string]$detectedSpec.output_path | Should Be $outputRel
            [bool]$detectedAsAnchor | Should Be $true
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
            [string]$artifact.artifact_type | Should Be 'tod_anchor_selection_artifact'
            [string]$artifact.source_file | Should Be $sourceRel
            [bool]$artifact.source_read | Should Be $true
            [string]$artifact.selected_anchor_pattern | Should Not BeNullOrEmpty
            [bool]$artifact.selected_anchor_nonempty | Should Be $true
            [bool]$artifact.selected_anchor_unique | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'rejects a unique but semantically wrong anchor-selection artifact before source-anchor observation' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-anchor-selection-semantic-rejection-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/LocalExecutionEngine.ps1'
        $inputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_BAD_ANCHOR_SELECTION.latest.json'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_BAD_ANCHOR_SELECTION_REJECTION.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputAbs = Join-Path $tempRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @'
function Get-LocalExecutionModeSectionLines {
    return @()
}

function Invoke-LocalExecutionGenericBoundedTask {
    $editMode = "artifact_write"
    return $editMode
}
'@, (New-Object System.Text.UTF8Encoding($false)))

            New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
            $inputArtifact = [ordered]@{
                artifact_type = 'tod_anchor_selection_artifact'
                objective_id = 'TOD-SAFE-SOURCE-ANCHOR-SELECTION-FOR-PACKET-MATERIALIZATION-V1'
                task_id = 'tod-bad-anchor-selection'
                source_file = $sourceRel
                selected_anchor_pattern = 'function Get-LocalExecutionModeSectionLines {'
                selected_line = 1
                inspected_candidates = @(
                    [ordered]@{ anchor_pattern = 'function Get-LocalExecutionModeSectionLines {'; occurrence_count = 1; line_number = 1 },
                    [ordered]@{ anchor_pattern = 'function Invoke-LocalExecutionGenericBoundedTask {'; occurrence_count = 1; line_number = 5 }
                )
                rationale = 'Selected first unique function.'
                continuation_action = 'Run source-anchor observation using selected_anchor_pattern as Anchor Pattern.'
            }
            [System.IO.File]::WriteAllText($inputAbs, ($inputArtifact | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: read_only_assessment
Task Category: inspection_only
Anchor-selection artifact semantic rejection.
Input Artifact: $inputRel
Output: $outputRel
Mission: Decide whether the selected anchor is acceptable for artifact_write/edit-mode packet materialization before source-anchor observation. If the selected anchor is a mode-section helper rather than packet/edit-mode behavior, reject it.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-ANCHOR-SELECTION-SEMANTIC-REJECTION' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Anchor selection semantic rejection artifact' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'inspection_only' }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
            [string]$artifact.artifact_type | Should Be 'tod_anchor_selection_semantic_rejection'
            [string]$artifact.decision | Should Be 'reject_anchor'
            [string]$artifact.selected_anchor_pattern | Should Be 'function Get-LocalExecutionModeSectionLines {'
            [string]$artifact.missing_capability | Should Not BeNullOrEmpty
            [bool]$artifact.no_code_changes | Should Be $true
            [string]$result.summary | Should Match 'anchor-selection semantic rejection'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'resolves a named source task prompt into the target-selection source file' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-target-selection-source-task-' + [guid]::NewGuid().ToString('N'))
        $sourceTaskId = 'tod-source-anchor-packet-quality-test'
        $targetRel = 'tmp_remote_mim/core/routers/studio.py'
        $promptRel = "tod/out/prompts/$sourceTaskId.md"
        $outputRel = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json'
        $targetAbs = Join-Path $tempRoot ($targetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $sourcePromptAbs = Join-Path $tempRoot ($promptRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($targetAbs, '# studio route fixture', (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourcePromptAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourcePromptAbs, @"
# TOD Task Execution Package

Task mode: inspection
Review Artifact: runtime_remote_training/tod_independent_resolution_attempts/TOD_SELECTOR_AUTHORITY_PACKET.latest.json
Source File: $targetRel
Output: runtime_remote_training/tod_independent_resolution_attempts/TOD_SELECTOR_AUTHORITY_PACKET_REVIEW.latest.json
"@, (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Objective: TOD-INDEPENDENT-RESOLUTION-LADDER-V1
Task mode: target_selection
Use the current source task $sourceTaskId as the training target.
TOD must inspect current artifacts and source surfaces itself.
Do not use static fallback candidates.
"@
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-TARGET-SELECTION-SOURCE-TASK' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Target selection resolves source task prompt' `
                -Scope 'Use the current source task tod-source-anchor-packet-quality-test as the training target.' `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'target_selection' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_target_selection_artifact'
            [string]$artifact.status | Should Be 'candidate_selected'
            [string]$artifact.selected_target | Should Be $targetRel
            [string]$artifact.selected_candidate_or_none.candidate_key | Should Be 'source_task_named_target'
            @($artifact.selected_candidate_or_none.evidence_fields) -contains 'source_task_source_file' | Should Be $true
            @($artifact.inspected_files) -contains $promptRel | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'keeps explicit target_selection ahead of broad route patch evidence registration' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-target-selection-precedence-' + [guid]::NewGuid().ToString('N'))
        $evidenceRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SELECTOR_AUTHORITY_BLOCKER.latest.json'
        $targetRel = 'scripts/engines/LocalExecutionEngine.ps1'
        $outputRel = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json'
        $evidenceAbs = Join-Path $tempRoot ($evidenceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $targetAbs = Join-Path $tempRoot ($targetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($targetAbs, '# local executor fixture', (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $evidenceAbs) -Force | Out-Null
            $evidence = [ordered]@{
                artifact_type = 'tod_training_blocker_evidence'
                observed_request = [ordered]@{
                    task_mode = 'inspection'
                    source_file = $targetRel
                }
                summary = 'Selector authority evidence mentions route patch history, but target selection must choose from evidence.'
            } | ConvertTo-Json -Depth 8
            [System.IO.File]::WriteAllText($evidenceAbs, $evidence, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: target_selection
Select one fresh target for the next bounded repair packet using only supplied evidence.

Evidence Artifact: $evidenceRel

Mission:
Choose the smallest source target after the read-only role-classification proof. This text mentions fresh route patch evidence, but the explicit task mode is target_selection.
Do not patch anything in this task.
Do not use static fallback candidates.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-TARGET-SELECTION-PRECEDENCE' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Target selection outranks route patch evidence' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'target_selection' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_target_selection_artifact'
            [string]$artifact.status | Should Be 'candidate_selected'
            [string]$artifact.selected_target | Should Be $targetRel
            [string]$artifact.selected_candidate_or_none.candidate_key | Should Be 'evidence_named_target'
            [string]$result.summary | Should Match 'target-selection'
            [string]$result.summary | Should Not Match 'route patch evidence'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'selects patch-summary changed source paths from supplied evidence' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-target-selection-patch-summary-' + [guid]::NewGuid().ToString('N'))
        $evidenceRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SELECTOR_PATCH_SUMMARY.latest.json'
        $targetRel = 'tmp_remote_mim/core/routers/studio.py'
        $outputRel = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json'
        $evidenceAbs = Join-Path $tempRoot ($evidenceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $targetAbs = Join-Path $tempRoot ($targetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($targetAbs, '# studio route fixture', (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $evidenceAbs) -Force | Out-Null
            $evidence = [ordered]@{
                artifact_type = 'tod_patch_evidence_authority_classification'
                input_patch = 'runtime_remote_training/cleanup_holds/example.patch'
                patch_summary = [ordered]@{
                    files_changed = @(
                        [ordered]@{
                            old_path = $targetRel
                            new_path = $targetRel
                        }
                    )
                }
            } | ConvertTo-Json -Depth 8
            [System.IO.File]::WriteAllText($evidenceAbs, $evidence, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: target_selection
Select one fresh target for the next bounded repair packet using only supplied evidence.

Evidence Artifact: $evidenceRel

Mission:
Choose the smallest source target after the read-only role-classification proof.
Do not patch anything in this task.
Do not use static fallback candidates.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-TARGET-SELECTION-PATCH-SUMMARY' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Target selection reads patch summary paths' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'target_selection' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_target_selection_artifact'
            [string]$artifact.status | Should Be 'candidate_selected'
            [string]$artifact.selected_target | Should Be $targetRel
            @($artifact.selected_candidate_or_none.evidence_fields) -contains 'new_path' | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'pivots different-target discovery away from forbidden Studio candidates' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-pivot-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tmp_remote_mim/core/routers/public_chat.py',
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py',
                'tools/run_public_mim_general_conversation_smoke.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, studio_training_live_mode_selection_response_guard
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Do not reuse Studio recommendation packet candidates. Inspect a different current-code live path and publish a candidate or blocker.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-PIVOT' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/public_chat.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'public_chat_context_followup_direct_answer_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/public_chat.py' | Should Be $true
            [string]$updated.why_selected | Should Match 'not forbidden'
            [string]$updated.credit_decision.reason | Should Match 'Discovery artifact only'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'uses latest drill forbidden paths when choosing a different-target discovery candidate' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-current-drill-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tmp_remote_mim/core/routers/public_chat.py',
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py',
                'tmp_remote_mim/core/routers/tod_ui.py',
                'tmp_remote_mim/tests/integration/test_tod_ui_console.py',
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            $interventionPath = Join-Path $tempRoot 'runtime_remote_training/codex_training_interventions/CODEX_TOD_DIFFERENT_TARGET_DISCOVERY_DRILL_20260616T2010Z.latest.json'
            New-Item -ItemType Directory -Path (Split-Path -Parent $interventionPath) -Force | Out-Null
            [pscustomobject]@{
                artifact_version = 'codex-training-intervention-v1'
                generated_at = '2026-06-16T20:10:00Z'
                status = 'training_instruction_issued'
                tod_training_instruction = [pscustomobject]@{
                    forbidden_paths = @(
                        'tmp_remote_mim/core/routers/public_chat.py'
                    )
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $interventionPath -Encoding UTF8

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, studio_training_live_mode_selection_response_guard
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Do not reuse Studio candidates. Also honor current drill forbidden paths from codex_training_interventions before choosing a discovery target.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-CURRENT-DRILL' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery current drill pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/tod_ui.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'tod_ui_chat_payload_latest_execution_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/tod_ui.py' | Should Be $true
            [string]$updated.why_selected | Should Match 'not forbidden'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'broadens different-target discovery to inquiry router when prior router candidates are exhausted' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-composer-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @(
                'tmp_remote_mim/core/routers/studio.py',
                'tmp_remote_mim/tests/test_studio_training_chat.py',
                'tmp_remote_mim/core/routers/public_chat.py',
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py',
                'tmp_remote_mim/core/routers/tod_ui.py',
                'tmp_remote_mim/tests/integration/test_tod_ui_console.py',
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json',
                'tmp_remote_mim/core/routers/gateway.py',
                'tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py',
                'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json',
                'tmp_remote_mim/core/routers/tasks.py',
                'tmp_remote_mim/core/schemas.py',
                'tmp_remote_mim/core/objective_lifecycle.py',
                'tmp_remote_mim/core/routers/operator.py',
                'tmp_remote_mim/core/operator_resolution_service.py',
                'tmp_remote_mim/core/operator_commitment_monitoring_service.py',
                'tmp_remote_mim/core/routers/inquiry.py',
                'tmp_remote_mim/core/inquiry_service.py',
                'tmp_remote_mim/core/schemas.py',
                'tmp_remote_mim/core/communication_composer.py',
                'tools/score_mim_operator_impact_live_10.py'
            )) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, tmp_remote_mim/core/routers/public_chat.py, tmp_remote_mim/core/routers/tod_ui.py, tmp_remote_mim/core/routers/gateway.py, tmp_remote_mim/core/routers/tasks.py, tmp_remote_mim/core/routers/operator.py, tmp_remote_mim/core/interaction_quality_dashboard.py
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Router discovery candidates are consumed or already applied. Inspect a different current-code live conversation surface.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-COMPOSER' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery composer pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/inquiry.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'inquiry_router_answer_context_evidence_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/inquiry.py' | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'skips different-target discovery candidates whose applied marker already exists' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-discovery-fresh-marker-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $fixtures = @{
                'tmp_remote_mim/core/routers/studio.py' = '# forbidden studio fixture'
                'tmp_remote_mim/tests/test_studio_training_chat.py' = '# fixture'
                'tmp_remote_mim/core/routers/public_chat.py' = '# forbidden public chat fixture'
                'tmp_remote_mim/tests/test_public_chat_direct_answers.py' = '# fixture'
                'tmp_remote_mim/core/routers/tod_ui.py' = '# forbidden tod ui fixture'
                'tmp_remote_mim/tests/integration/test_tod_ui_console.py' = '# fixture'
                'runtime/shared/TOD_EXECUTION_RESULT.latest.json' = '{}'
                'tmp_remote_mim/core/routers/gateway.py' = '# forbidden gateway fixture'
                'tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py' = '# fixture'
                'runtime/shared/MIM_TOD_TASK_REQUEST.latest.json' = '{}'
                'tmp_remote_mim/core/routers/tasks.py' = '# forbidden tasks fixture'
                'tmp_remote_mim/core/schemas.py' = '# fixture'
                'tmp_remote_mim/core/objective_lifecycle.py' = '# fixture'
                'tmp_remote_mim/core/routers/inquiry.py' = 'answer_context_evidence = True'
                'tmp_remote_mim/core/inquiry_service.py' = '# fixture'
                'tmp_remote_mim/core/routers/results.py' = '# fresh results target'
                'tmp_remote_mim/core/autonomy_driver_service.py' = '# fixture'
                'tmp_remote_mim/core/routers/operator.py' = 'operator_action_required = True'
                'tmp_remote_mim/core/operator_resolution_service.py' = '# fixture'
                'tmp_remote_mim/core/operator_commitment_monitoring_service.py' = '# fixture'
                'tmp_remote_mim/core/communication_composer.py' = 'message = "clear answer or next useful action"'
                'tools/score_mim_operator_impact_live_10.py' = '# fixture'
                'tmp_remote_mim/core/interaction_quality_dashboard.py' = '# fresh dashboard target'
            }
            foreach ($fixturePath in $fixtures.Keys) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, [string]$fixtures[$fixturePath], (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json
Edit Mode: artifact_write
Validation Pattern: selected_candidate_or_none
Forbidden repeated targets: tmp_remote_mim/core/routers/studio.py, tmp_remote_mim/core/routers/public_chat.py, tmp_remote_mim/core/routers/tod_ui.py, tmp_remote_mim/core/routers/gateway.py, tmp_remote_mim/core/routers/tasks.py
Required output fields: inspected_files, candidate_count, selected_candidate_or_none, why_selected, validation_command, rollback_note, prevention_lesson, dave_needed
'@
            $scope = 'Operator and communication composer candidates are already applied. Discovery should select the next fresh live-path target instead of repeating no-op packet candidates.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DIFFERENT-TARGET-FRESH-MARKER' -ObjectiveId 'OBJ-LF' -Title 'Different target discovery applied marker skip' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'candidate_selected'
            [string]$updated.selected_candidate_or_none.target_file | Should Be 'tmp_remote_mim/core/routers/results.py'
            [string]$updated.selected_candidate_or_none.candidate_key | Should Be 'results_router_objective_recompute_evidence_guard'
            @($updated.inspected_files) -contains 'tmp_remote_mim/core/routers/results.py' | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks generic packet formation when the current-code anchor is unavailable' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_EXPLICIT_ARTIFACT_WRITE_2026_06_14.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $durabilityPath = Join-Path $tempRoot 'scripts/run_mim_durability_smoke_v2.py'
        $durabilityFixture = @'
def no_status_report_leakage(reply):
    status_boilerplate = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    return True
'@
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $durabilityPath) -Force | Out-Null
            Set-LocalFallbackTestFileText -Path $durabilityPath -Content $durabilityFixture

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Packet formation task for the next independent TOD resolution attempt.
"@
            $scope = 'Publish packet_candidate_ready evidence for a later independent runtime-code task. Dave-needed no unless credentials/external service are required.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PACKET-ARTIFACT' -ObjectiveId 'OBJ-LF' -Title 'Packet formation artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'blocked_current_code_anchor_missing'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'old_text'
            [string]$updated.blocker.required_next_action | Should Match 'exact old_text/new_text from the current code'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'forms an operator router packet candidate from the discovery-selected target' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-operator-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_OPERATOR_PACKET_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $operatorRelativePath = 'tmp_remote_mim/core/routers/operator.py'
            $operatorPath = Join-Path $tempRoot ($operatorRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $operatorFixture = @'
def _to_operator_execution(execution, resolution, event):
    feedback = execution.feedback_json if isinstance(execution.feedback_json, dict) else {}
    return {
        "execution_id": execution.id,
        "input_event_id": execution.input_event_id,
        "resolution_id": execution.resolution_id,
        "goal_id": execution.goal_id,
        "capability_name": execution.capability_name,
        "status": execution.status,
        "dispatch_decision": execution.dispatch_decision,
        "reason": execution.reason,
        "exception_reason": _normalize_exception_reason(execution, resolution, event),
        "requested_executor": execution.requested_executor,
        "safety_mode": execution.safety_mode,
        "trace_id": execution.trace_id,
        "managed_scope": execution.managed_scope,
        "arguments_json": execution.arguments_json,
        "feedback_json": feedback,
        "replan_required": bool(feedback.get("replan_required", False)),
        "latest_replan_outcome": str(feedback.get("latest_replan_outcome", "")),
    }
'@
            Set-LocalFallbackTestFileText -Path $operatorPath -Content $operatorFixture
            $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
            Set-LocalFallbackTestFileText -Path $todPath -Content @'
function Write-PacketProofParserFixture {
    $fields = @(
        'Validation Command',
        'Closure Evidence',
        'Prevention Lesson',
        'Dave Needed',
        'Required Packet Fields',
        'Inspect Target File',
        'Anchor'
    )
}
'@

            $attemptsDir = Join-Path $tempRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -ItemType Directory -Path $attemptsDir -Force | Out-Null
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery_drill'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'operator_router_exception_reason_actionability_guard'
                    target_file = $operatorRelativePath
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'),
                ($discoveryArtifact | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
Use the fresh operator router discovery target and publish exact old_text/new_text. No implementation credit.
"@
            $scope = 'Publish inspected packet candidate for operator router execution evidence. No implementation credit. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-OPERATOR-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Operator router packet candidate artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'operator_router_action_required_execution_payload'
            [string]$updated.packet.target_file | Should Be $operatorRelativePath
            [string]$updated.packet.old_text | Should Match '_normalize_exception_reason'
            [string]$updated.packet.new_text | Should Match 'operator_action_required'
            [string]$updated.packet.validation_command | Should Match 'operator.py'
            [string]$updated.packet.validation_pattern | Should Be '"operator_action_required"'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'synthesizes a packet body from explicit new text without marker-only scaffolding' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-explicit-packet-body-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/LocalExecutionEngine.ps1'
        $inputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_EXPLICIT_PACKET_BODY_SOURCE_ANCHOR_TEST.latest.json'
        $outputRel = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_EXPLICIT_PACKET_BODY_SYNTHESIS_TEST.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputAbs = Join-Path $tempRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $oldText = @'
    switch ($mode) {
        'validation_only' {
            $actionSummary = 'Validated bounded target.'
        }
        default {
            return 'blocked'
        }
    }
'@
        $newText = @'
    switch ($mode) {
        'artifact_write' {
            $actionSummary = 'Wrote bounded artifact.'
        }
        'validation_only' {
            $actionSummary = 'Validated bounded target.'
        }
        default {
            return 'blocked'
        }
    }
'@
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, $oldText, (New-Object System.Text.UTF8Encoding($false)))
            $anchor = [ordered]@{
                artifact_type = 'tod_source_anchor_observation'
                source_file = $sourceRel
                exact_text = $oldText
                start_line = 1
                end_line = 8
            }
            [System.IO.File]::WriteAllText($inputAbs, ($anchor | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Packet body synthesis from source anchor.
Input Artifact: $inputRel
Target File: $sourceRel
New Text:
$newText
Output Artifact: $outputRel
Validation Pattern: artifact_write
Validation Command: powershell -NoProfile -Command "`$null = [System.Management.Automation.Language.Parser]::ParseFile('$sourceRel', [ref]`$null, [ref]`$null); 'parse ok'"
Closure Evidence: explicit new_text packet candidate ready
Prevention Lesson: TOD must use explicit semantic new_text for behavior-changing code packets instead of marker-only scaffolding.
Dave Needed: no
"@
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-EXPLICIT-PACKET-BODY' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Explicit packet body synthesis' `
                -Scope 'Packet body synthesis should preserve current old_text and use explicit semantic New Text.' `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @($result.files_changed) -contains $outputRel | Should Be $true
            [bool]$artifact.packet_candidate_ready | Should Be $true
            [string]$artifact.packet.target_file | Should Be $sourceRel
            [string]$artifact.packet.old_text | Should Match 'validation_only'
            [string]$artifact.packet.new_text | Should Match 'artifact_write'
            [string]$artifact.packet.new_text | Should Not Match 'TOD training marker'
            [string]$artifact.synthesis.synthesis_mode | Should Be 'explicit_new_text'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'keeps no-snippet packet-body synthesis in the packet lane with a precise autonomous new_text blocker' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-packet-body-autonomous-newtext-blocker-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/PacketBodyAutonomousTarget.ps1'
        $inputRel = 'runtime_remote_training/read_only_audit_artifacts/PACKET_BODY_AUTONOMOUS_SOURCE_ANCHOR.latest.json'
        $outputRel = 'runtime_remote_training/tod_independent_resolution_attempts/PACKET_BODY_AUTONOMOUS_PACKET.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputAbs = Join-Path $tempRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $oldText = @'
    $artifact = [ordered]@{
        candidate_ready = $false
        codex_patch_supplied = $false
    }
'@
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, "function Test-AutonomousPacketBody {`n$oldText`n}`n", (New-Object System.Text.UTF8Encoding($false)))
            $anchor = [ordered]@{
                artifact_type = 'tod_source_anchor_observation'
                source_file = $sourceRel
                exact_text = $oldText
                start_line = 2
                end_line = 5
            }
            [System.IO.File]::WriteAllText($inputAbs, ($anchor | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Packet body synthesis independent probe.
Input Artifact: $inputRel
Target File: $sourceRel
Output Artifact: $outputRel
Validation Pattern: meaningful_safe_delta
"@
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-PACKET-BODY-AUTONOMOUS-BLOCKER' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'No-snippet packet body synthesis blocker' `
                -Scope 'Packet body synthesis should not fall through to generic target ambiguity when autonomous new_text is missing.' `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'blocked'
            [string]$result.reason_code | Should Be 'packet_body_synthesis_autonomous_new_text_missing'
            [string]$result.structured_findings[0].missing_variable | Should Be 'autonomous_meaningful_new_text_materialization_from_source_anchor'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks packet-body synthesis when the input artifact is not a source-anchor observation' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-packet-body-input-shape-blocker-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/PacketBodyInputShapeTarget.ps1'
        $inputRel = 'runtime_remote_training/read_only_audit_artifacts/PACKET_BODY_REVIEW_NOT_SOURCE_ANCHOR.latest.json'
        $outputRel = 'runtime_remote_training/tod_independent_resolution_attempts/PACKET_BODY_INPUT_SHAPE_PACKET.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputAbs = Join-Path $tempRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, "function Test-PacketBodyInputShape {`n    return `$true`n}`n", (New-Object System.Text.UTF8Encoding($false)))
            $reviewArtifact = [ordered]@{
                artifact_type = 'tod_autonomous_newtext_materialization_blocker_lane_rerun_v1'
                observed_result = @{ reason_code = 'packet_body_synthesis_autonomous_new_text_missing' }
            }
            [System.IO.File]::WriteAllText($inputAbs, ($reviewArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Packet body synthesis evidence-shape probe.
Input Artifact: $inputRel
Target File: $sourceRel
Output Artifact: $outputRel
Validation Pattern: source_anchor_exact_text
"@
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-PACKET-BODY-INPUT-SHAPE-BLOCKER' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Packet body synthesis input shape blocker' `
                -Scope 'Packet body synthesis must reject non-source-anchor input artifacts without crashing.' `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'blocked'
            [string]$result.reason_code | Should Be 'packet_body_synthesis_input_not_source_anchor'
            [string]$result.structured_findings[0].missing_variable | Should Be 'source_anchor_exact_text'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'forms an inquiry router packet candidate from the discovery-selected target' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-inquiry-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INQUIRY_PACKET_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $inquiryRelativePath = 'tmp_remote_mim/core/routers/inquiry.py'
            $inquiryPath = Join-Path $tempRoot ($inquiryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            $inquiryFixture = @'
async def answer_inquiry_question_endpoint():
    return {
        "answered": True,
        "applied_effect": applied_effect,
        "question": to_inquiry_question_out(updated),
    }
'@
            Set-LocalFallbackTestFileText -Path $inquiryPath -Content $inquiryFixture

            $attemptsDir = Join-Path $tempRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -ItemType Directory -Path $attemptsDir -Force | Out-Null
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery_drill'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'inquiry_router_answer_context_evidence_guard'
                    target_file = $inquiryRelativePath
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'),
                ($discoveryArtifact | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: different_target_discovery_candidate
Use the fresh inquiry router discovery target and publish exact old_text/new_text. No implementation credit.
"@
            $scope = 'Publish inspected packet candidate for inquiry answer response evidence. No implementation credit. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-INQUIRY-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Inquiry router packet candidate artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'inquiry_router_answer_context_evidence_payload'
            [string]$updated.packet.target_file | Should Be $inquiryRelativePath
            [string]$updated.packet.old_text | Should Match 'applied_effect'
            [string]$updated.packet.new_text | Should Match 'answer_context_evidence'
            [string]$updated.packet.validation_command | Should Match 'inquiry.py'
            [string]$updated.packet.validation_pattern | Should Be '"answer_context_evidence"'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks packet formation as already applied before reporting a stale old_text anchor' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-already-applied-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_ALREADY_APPLIED_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $durabilityPath = Join-Path $tempRoot 'scripts/run_mim_durability_smoke_v2.py'
        $durabilityOriginalContent = if (Test-Path -Path $durabilityPath) { Get-Content -Path $durabilityPath -Raw } else { $null }
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $tempRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryOriginalContent = if (Test-Path -Path $discoveryTarget) { Get-Content -Path $discoveryTarget -Raw } else { $null }
        $studioPath = Join-Path $tempRoot 'tmp_remote_mim/core/routers/studio.py'
        $studioOriginalContent = if (Test-Path -Path $studioPath) { Get-Content -Path $studioPath -Raw } else { $null }
        $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
        $todOriginalContent = if (Test-Path -Path $todPath) { Get-Content -Path $todPath -Raw } else { $null }

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    expected_changed_files = @('tmp_remote_mim/core/routers/studio.py')
                }
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $discoveryTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($studioPath, "# TOD current-code packet materialization`n", (New-Object System.Text.UTF8Encoding($false)))
            New-Item -ItemType Directory -Path (Split-Path -Parent $todPath) -Force | Out-Null
            if ($null -ne $todOriginalContent -and -not $todOriginalContent.Contains("'Prevention Lesson',")) {
                [System.IO.File]::WriteAllText($todPath, ($todOriginalContent.TrimEnd() + "`n        'Prevention Lesson',`n"), (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $studioOriginalContent -and -not $studioOriginalContent.Contains('TOD current-code packet materialization')) {
                [System.IO.File]::WriteAllText($studioPath, ($studioOriginalContent.TrimEnd() + "`n# TOD current-code packet materialization`n"), (New-Object System.Text.UTF8Encoding($false)))
            }

            $seededContent = @'
def no_status_report_leakage(reply):
    status_boilerplate = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "here are the current scorecard numbers",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    return True
'@
            Set-LocalFallbackTestFileText -Path $durabilityPath -Content $seededContent

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Packet formation task for the next independent TOD resolution attempt.
"@
            $scope = 'Publish packet_candidate_ready evidence for a later independent runtime-code task. Dave-needed no unless credentials/external service are required.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PACKET-ALREADY-APPLIED' -ObjectiveId 'OBJ-LF' -Title 'Packet formation already applied' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'blocked_candidate_already_applied'
            [bool]$updated.packet_candidate_ready | Should Be $false
            (@($updated.blocker.inspected_files).Count -gt 0) | Should Be $true
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'fresh_old_text'
            [string]$updated.blocker.required_next_action | Should Match 'different current-code behavior gap'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $durabilityOriginalContent) {
                Set-LocalFallbackTestFileText -Path $durabilityPath -Content $durabilityOriginalContent
            }
            if ([string]::IsNullOrWhiteSpace($discoveryOriginalContent)) {
                if (Test-Path -Path $discoveryTarget) { Remove-Item -Path $discoveryTarget -Force }
            }
            else {
                [System.IO.File]::WriteAllText($discoveryTarget, $discoveryOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $studioOriginalContent) {
                [System.IO.File]::WriteAllText($studioPath, $studioOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $todOriginalContent) {
                [System.IO.File]::WriteAllText($todPath, $todOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'blocks stale synthesis packet formation with inspected current-code evidence' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_SYNTHESIS_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Use stale_synthesis_reason_specificity evidence to form the next bounded runtime-code packet from current repository code.
Required output: publish one tod_independent_resolution_attempts packet candidate artifact with packet_candidate_ready=true.
"@
            $scope = 'Repair synthesis candidate materialization from current code; include candidate_key in the next current-code packet fields.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PACKET-SYNTHESIS' -ObjectiveId 'OBJ-LF' -Title 'Packet formation synthesis target' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'blocked_current_code_anchor_missing'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.blocker.reason | Should Match 'could not find the exact current summary block'
            [string]$updated.blocker.required_next_action | Should Match 'Inspect the current target file'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'old_text'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'uses latest materialization blocker target for exact patch synthesis drills' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-exact-drill-latest-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_EXACT_PATCH_SYNTHESIS_DRILL_OPERATOR_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $operatorRelativePath = 'tmp_remote_mim/core/routers/operator.py'
            $operatorPath = Join-Path $tempRoot ($operatorRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
            New-Item -ItemType Directory -Path (Split-Path -Parent $operatorPath) -Force | Out-Null
            [System.IO.File]::WriteAllText(
                $operatorPath,
                "def _to_operator_execution(execution, resolution, event):`n    feedback = execution.feedback_json if isinstance(execution.feedback_json, dict) else {}`n    return {`n        `"exception_reason`": _normalize_exception_reason(execution, resolution, event),`n        `"replan_required`": bool(feedback.get(`"replan_required`", False)),`n    }`n",
                (New-Object System.Text.UTF8Encoding($false))
            )

            $attemptsDir = Join-Path $tempRoot 'runtime_remote_training/tod_independent_resolution_attempts'
            New-Item -ItemType Directory -Path $attemptsDir -Force | Out-Null
            $stalePacket = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'packet_candidate_ready'
                packet_candidate_ready = $true
                packet = [ordered]@{
                    selected_candidate = 'stale_tasks_packet'
                    target_file = 'tmp_remote_mim/core/routers/tasks.py'
                    old_text = 'old stale tasks text'
                    new_text = 'new stale tasks text'
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json'),
                ($stalePacket | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            $freshBlocker = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                status = 'blocked_requires_tod_synthesized_old_new'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = $operatorRelativePath
                    reason = 'TOD must synthesize exact current old_text/new_text for operator.py.'
                    required_next_action = 'Inspect operator.py and publish exact old_text/new_text.'
                }
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $attemptsDir 'TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY.latest.json'),
                ($freshBlocker | ConvertTo-Json -Depth 8),
                (New-Object System.Text.UTF8Encoding($false))
            )
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: exact_patch_synthesis_drill
Run exact patch synthesis drill from the latest materialization blocker.
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-EXACT-DRILL-LATEST' -ObjectiveId 'OBJ-LF' -Title 'Exact patch latest blocker drill' -Scope 'Use latest materialization blocker target.' -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.artifact_type | Should Be 'tod_exact_patch_synthesis_drill'
            [string]$updated.target_file | Should Be $operatorRelativePath
            [string]$updated.current_anchor.text | Should Match 'exception_reason'
            @($updated.bounded_slice.slice).Count | Should BeGreaterThan 0
            [string]($updated.bounded_slice.slice -join "`n") | Should Match 'replan_required'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'uses live Studio conversation anchors when packet formation cannot find current old_text' {
        $patterns = Get-LocalExecutionPacketAnchorPatterns `
            -TargetFile 'tmp_remote_mim/core/routers/studio.py' `
            -CandidateName 'studio_recommendation_prioritizes_exact_old_new_packet_materialization' `
            -ValidationPattern "TOD's next meaningful implementation loop" `
            -OldText 'stale Studio recommendation text that is no longer present'

        $slice = Get-LocalExecutionBoundedSliceEvidence -RelativePath 'tmp_remote_mim/core/routers/studio.py' -Patterns $patterns

        [string]$slice.matched_pattern | Should Not Be 'file_start'
        [int]$slice.start_line | Should BeGreaterThan 100
        [string]($slice.slice -join "`n") | Should Match '_studio_conversation_mode_guard_reply|what are you working on|response_mode|recommendation_mode'
    }

    It 'forms materialization recovery packets for TOD proof directives' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_MATERIALIZATION_RECOVERY_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $todPath = Join-Path $repoRoot 'scripts/TOD.ps1'
        $todOriginalContent = if (Test-Path -Path $todPath) { Get-Content -Path $todPath -Raw } else { $null }
        $newDirectiveBlock = @'
        'Validation Command',
        'Closure Evidence',
        'Prevention Lesson',
        'Dave Needed',
        'Required Packet Fields',
        'Inspect Target File',
        'Anchor',
'@
        $oldDirectiveBlock = @'
        'Validation Command',
        'Closure Evidence',
        'Anchor',
'@

        try {
            if ($null -ne $todOriginalContent -and $todOriginalContent.Contains($newDirectiveBlock)) {
                [System.IO.File]::WriteAllText($todPath, $todOriginalContent.Replace($newDirectiveBlock, $oldDirectiveBlock), (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: same_objective_recovery_not_materialized_before_dispatch
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Publish packet_candidate_ready evidence for materialized bounded edit proof. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MATERIALIZATION-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Materialization recovery packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'tod_materialization_proof_directive_parser'
            [string]$updated.packet.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.packet.validation_pattern | Should Be "'Prevention Lesson',"
            [string]$updated.packet.new_text | Should Match 'Required Packet Fields'
            [string]$updated.packet.prevention_lesson | Should Match 'bounded directive parser'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $todOriginalContent) {
                [System.IO.File]::WriteAllText($todPath, $todOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'blocks consumed materialization recovery packets when the discovery-selected Studio target is already applied' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_MATERIALIZATION_PIVOT_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $durabilityPath = Join-Path $repoRoot 'scripts/run_mim_durability_smoke_v2.py'
        $durabilityOriginalContent = if (Test-Path -Path $durabilityPath) { Get-Content -Path $durabilityPath -Raw } else { $null }
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $repoRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryOriginalContent = if (Test-Path -Path $discoveryTarget) { Get-Content -Path $discoveryTarget -Raw } else { $null }

        try {
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    expected_changed_files = @('tmp_remote_mim/core/routers/studio.py')
                }
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $discoveryTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $seededContent = @'
def no_status_report_leakage(reply):
    status_boilerplate = (
        "training is active, but outcome improvement is not proven yet",
        "training is active, but the useful question is whether it is changing behavior",
        "my current weakness is:",
        "my mode-selection score",
        "the outcome verdict is",
        "i default to status reporting",
        "not whether the scoreboard looks busy",
        "here are the current scorecard numbers",
        "mim communication:",
        "mim/tod real movement:",
        "mim operator impact:",
    )
    return True
'@
            Set-LocalFallbackTestFileText -Path $durabilityPath -Content $seededContent

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Publish packet_candidate_ready evidence for materialized bounded edit proof. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MATERIALIZATION-PIVOT-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Materialization recovery packet formation pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @('blocked_candidate_already_applied', 'blocked_current_code_anchor_missing') -contains [string]$updated.status | Should Be $true
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.blocker.target_file | Should Not Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.blocker.required_next_action | Should Match 'current-code behavior gap|old_text/new_text'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $durabilityOriginalContent) {
                Set-LocalFallbackTestFileText -Path $durabilityPath -Content $durabilityOriginalContent
            }
            if ([string]::IsNullOrWhiteSpace($discoveryOriginalContent)) {
                if (Test-Path -Path $discoveryTarget) { Remove-Item -Path $discoveryTarget -Force }
            }
            else {
                [System.IO.File]::WriteAllText($discoveryTarget, $discoveryOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'uses discovery-selected target instead of durability fallback after proof directive packet is consumed' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_DISCOVERY_TARGET_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $repoRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryOriginalContent = if (Test-Path -Path $discoveryTarget) { Get-Content -Path $discoveryTarget -Raw } else { $null }

        try {
            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    target_file = 'tmp_remote_mim/core/routers/studio.py'
                    validation_command = 'python -m unittest tmp_remote_mim.tests.test_studio_training_chat'
                    expected_changed_files = @('tmp_remote_mim/core/routers/studio.py')
                }
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $discoveryTarget) -Force | Out-Null
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Use the fresh discovery-selected target and do not fall back to scripts/run_mim_durability_smoke_v2.py.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MATERIALIZATION-DISCOVERY-TARGET' -ObjectiveId 'OBJ-LF' -Title 'Materialization recovery discovery target' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            @('blocked_candidate_already_applied', 'blocked_current_code_anchor_missing') -contains [string]$updated.status | Should Be $true
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.blocker.target_file | Should Not Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.blocker.required_next_action | Should Match 'current-code behavior gap|old_text/new_text'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ([string]::IsNullOrWhiteSpace($discoveryOriginalContent)) {
                if (Test-Path -Path $discoveryTarget) { Remove-Item -Path $discoveryTarget -Force }
            }
            else {
                [System.IO.File]::WriteAllText($discoveryTarget, $discoveryOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'materializes a Studio mode guard packet for explicit inspect targets' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-studio-mode-guard-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_STUDIO_MODE_GUARD_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $studioRelativePath = 'tmp_remote_mim/core/routers/studio.py'
        $studioPath = Join-Path $tempRoot ($studioRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($studioPath, @'
def _studio_conversation_mode_guard_reply(prompt, page_context):
    recommendation_terms = (
        "smartest next move",
        "work should be paused",
    )
'@, (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Inspect Target File: $studioRelativePath
Required output: publish a current-code packet candidate with exact old_text/new_text.
"@
            $scope = 'Materialize a Studio packet for the explicit inspect target.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-STUDIO-MODE-GUARD-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Studio mode guard packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.target_file | Should Be $studioRelativePath
            [string]$updated.packet.old_text | Should Match 'smartest next move'
            [string]$updated.packet.new_text | Should Match 'what should we work on'
            [string]$updated.packet.validation_pattern | Should Be '"what should we work on"'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force
            }
        }
    }

    It 'materializes public chat discovery packets from exact current code' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-public-chat-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_PUBLIC_CHAT_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $tempRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
        $publicChatPath = Join-Path $tempRoot 'tmp_remote_mim/core/routers/public_chat.py'
        $publicChatOldBlock = @'
        if any(token in recent_text for token in ("day", "date", "today", "time", "thursday", "friday", "saturday")):
            return (
                f"This could mean several things, but if you mean the day/date from the prior question, in France it is {temporal['current_date']} at about {temporal['current_time']} {temporal['timezone']}. "
                "The evidence is the prior turn plus the France timezone source. If you meant laws, travel, pricing, or something else about France, that is a different path. Next action: I will use the prior-turn date context unless you choose another France topic."
            )
'@

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $todPath) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $publicChatPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($todPath, "        'Prevention Lesson',`n", (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($publicChatPath, $publicChatOldBlock, (New-Object System.Text.UTF8Encoding($false)))

            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'public_chat_context_followup_direct_answer_guard'
                    target_file = 'tmp_remote_mim/core/routers/public_chat.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/routers/public_chat.py'
                    expected_changed_files = @('tmp_remote_mim/core/routers/public_chat.py')
                }
            }
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Use the fresh public-chat discovery-selected target and publish exact old_text/new_text. No implementation credit.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-PUBLIC-CHAT-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Public chat packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'public_chat_france_followup_prior_context_direct_answer'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/public_chat.py'
            [string]$updated.packet.old_text | Should Match 'This could mean several things'
            [string]$updated.packet.new_text | Should Match 'I am carrying forward the prior date/time question'
            [string]$updated.packet.validation_command | Should Match 'public_chat.py'
            [string]$updated.packet.validation_pattern | Should Be 'I am carrying forward the prior date/time question'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'materializes interaction quality dashboard discovery packets from exact current code' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-dashboard-packet-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_DASHBOARD_TEST.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $discoveryRelativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json'
        $discoveryTarget = Join-Path $tempRoot ($discoveryRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $todPath = Join-Path $tempRoot 'scripts/TOD.ps1'
        $dashboardPath = Join-Path $tempRoot 'tmp_remote_mim/core/interaction_quality_dashboard.py'
        $dashboardOldBlock = @'
        "headline": {
            "available_artifacts": sum(1 for item in artifacts if item.get("available")),
            "best_weighted_pass_rate": max(best_weighted) if best_weighted else None,
            "total_failure_examples": len(failure_analysis.get("examples") or []),
            "internal_jargon_failure_count": sum(
                int(item.get("internal_jargon_failure_count") or 0) for item in artifacts
            ),
        },
'@

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $todPath) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $dashboardPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($todPath, "        'Prevention Lesson',`n", (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($dashboardPath, $dashboardOldBlock, (New-Object System.Text.UTF8Encoding($false)))

            $discoveryArtifact = [ordered]@{
                artifact_type = 'tod_different_target_discovery'
                status = 'candidate_selected'
                selected_candidate_or_none = [ordered]@{
                    candidate_key = 'interaction_quality_dashboard_stale_artifact_context_guard'
                    target_file = 'tmp_remote_mim/core/interaction_quality_dashboard.py'
                    validation_command = 'python -m py_compile tmp_remote_mim/core/interaction_quality_dashboard.py'
                    expected_changed_files = @('tmp_remote_mim/core/interaction_quality_dashboard.py')
                }
            }
            [System.IO.File]::WriteAllText($discoveryTarget, ($discoveryArtifact | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Recovery Materialization Source: consumed_packet_anchor_requires_different_candidate
Focus: materialized bounded edit proof for TOD recovery. Include Prevention Lesson, Dave Needed, Required Packet Fields, and Inspect Target File parsing.
"@
            $scope = 'Use the fresh dashboard discovery-selected target and publish exact old_text/new_text. No implementation credit.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-DASHBOARD-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Dashboard packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'interaction_quality_dashboard_stale_artifact_headline_count'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/interaction_quality_dashboard.py'
            [string]$updated.packet.old_text | Should Match 'available_artifacts'
            [string]$updated.packet.new_text | Should Match 'stale_artifacts'
            [string]$updated.packet.validation_command | Should Match 'interaction_quality_dashboard.py'
            [string]$updated.packet.validation_pattern | Should Be '"stale_artifacts"'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'keeps selector preference packet recovery on TOD selector code instead of durability smoke fallback' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_SELECTOR_PREFERENCE_RECOVERY.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Behavior Delta: materialize a current-code selector preference packet so recovery backlog packet formation cannot outrank the active Studio old_text/new_text blocker.
Required output: publish one current-code packet candidate for scripts/TOD.ps1 selector preference, or publish blocked_candidate_already_applied/current_code_anchor_missing.
"@
            $scope = 'Selector preference recovery must stay on scripts/TOD.ps1 and must not pivot to the durability smoke packet.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-SELECTOR-PREFERENCE-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Selector preference packet recovery' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.blocker.target_file | Should Not Be 'scripts/run_mim_durability_smoke_v2.py'
            [string]$updated.credit_decision.independent_tod_resolution | Should Be 'False'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'validates blocked packet artifacts as blockers instead of ready string matches' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_BLOCKED_VALIDATION_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $blockedPacket = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'blocked_current_code_anchor_missing'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = 'scripts/run_mim_durability_smoke_v2.py'
                    reason = 'Packet formation could not find the exact current summary block.'
                    required_next_action = 'Inspect the current target file and form a packet with exact old_text/new_text from the current code.'
                }
            }
            [System.IO.File]::WriteAllText($target, ($blockedPacket | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $command = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $relativePath
            $capture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $repoRoot

            [int]$capture.exit_code | Should Be 0
            [string]$capture.stdout | Should Match 'Packet candidate blocked with inspected evidence'
            [string]$capture.stdout | Should Match 'Next action'
            [string]$capture.stdout | Should Not Match 'Packet candidate ready'
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'rejects thin blocked packet artifacts without a required next action' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_THIN_BLOCKER_VALIDATION_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $blockedPacket = [ordered]@{
                artifact_type = 'tod_packet_formation_artifact'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
                status = 'blocked_current_code_anchor_missing'
                packet_candidate_ready = $false
                blocker = [ordered]@{
                    target_file = 'scripts/run_mim_durability_smoke_v2.py'
                    reason = 'Packet formation could not find the exact current summary block.'
                }
            }
            [System.IO.File]::WriteAllText($target, ($blockedPacket | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

            $command = New-LocalExecutionPacketCandidateValidationCommand -TargetFile $relativePath
            $capture = Invoke-LocalShellCapture -Command $command -WorkingDirectory $repoRoot

            [int]$capture.exit_code | Should Not Be 0
            [string]$capture.stderr | Should Match 'missing required blocker evidence'
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'writes exact patch synthesis drill blockers without implementation credit' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_EXACT_PATCH_SYNTHESIS_DRILL_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: exact_patch_synthesis_drill
Produce exact bounded-edit synthesis evidence before any code execution.
"@
            $scope = 'Training drill: produce exact bounded-edit synthesis evidence before any code execution. Credit rule: this drill is not a validated TOD edit, not a meaningful implementation, and not an independent resolution.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-EXACT-PATCH-DRILL' -ObjectiveId 'OBJ-LF' -Title 'Exact patch synthesis drill' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.artifact_type | Should Be 'tod_exact_patch_synthesis_drill'
            [string]$updated.status | Should Be 'blocked_with_precise_reason'
            [bool]$updated.required_outputs_filled | Should Be $true
            [bool]$updated.candidate_ready | Should Be $false
            @($updated.inspected_files).Count | Should BeGreaterThan 3
            [string]$updated.validation_pattern | Should Be 'exact_patch_synthesis_drill'
            [string]$updated.dave_needed | Should Be 'no'
            [bool]$updated.codex_patch_supplied | Should Be $false
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false
            [bool]$updated.credit_decision.validated_tod_edit | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'forms gateway packets from multi-target handoff blocker evidence' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_GATEWAY_SPLIT_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $gatewayRelativePath = 'tmp_remote_mim/core/routers/gateway.py'
        $gatewayPath = Join-Path $repoRoot ($gatewayRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $gatewayOriginalContent = if (Test-Path -Path $gatewayPath) { Get-Content -Path $gatewayPath -Raw } else { $null }
        $gatewayOldBlock = @'
    expected_evidence = [
        "fresh changed_files for the target gateway/test files or blocked_with_inspection",
        "focused validation command output",
    ]
'@
        $gatewayNewBlock = @'
    expected_evidence = [
        "fresh changed_files for the selected one-file target or blocked_with_inspection naming target_file_exactly_one",
        "focused validation command output",
    ]
'@

        try {
            if (-not [string]::IsNullOrWhiteSpace($gatewayOriginalContent) -and -not $gatewayOriginalContent.Contains($gatewayOldBlock)) {
                $seededGatewayContent = if ($gatewayOriginalContent.Contains($gatewayNewBlock)) {
                    $gatewayOriginalContent.Replace($gatewayNewBlock, $gatewayOldBlock)
                }
                else {
                    $gatewayOriginalContent.TrimEnd() + "`n" + $gatewayOldBlock + "`n"
                }
                $seededGatewayContent = $seededGatewayContent.Replace('selected one-file target', 'target gateway/test files')
                [System.IO.File]::WriteAllText($gatewayPath, $seededGatewayContent, (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Previous blocker: blocked_missing_bounded_edit_mode because the handoff named both the gateway implementation file and its test file.
Required behavior: create a packet for exactly one gateway target_file after target_file_exactly_one blocked the broad MIM synced handoff.
"@
            $scope = 'Publish packet_candidate_ready evidence for the MIM synced gateway multi-target split. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-GATEWAY-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Gateway packet formation artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.selected_candidate | Should Be 'gateway_multi_target_split_evidence'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/gateway.py'
            [string]$updated.packet.new_text | Should Match 'selected one-file target'
            [string]$updated.packet.validation_command | Should Match 'tmp_remote_mim/core/routers/gateway.py'
            [string]$updated.packet.validation_pattern | Should Be 'selected one-file target'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $gatewayOriginalContent) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 100
                [System.IO.File]::WriteAllText($gatewayPath, $gatewayOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'blocks packet formation when the selected target is forbidden by the prompt' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_FORBIDDEN_GATEWAY_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $gatewayRelativePath = 'tmp_remote_mim/core/routers/gateway.py'
        $gatewayPath = Join-Path $repoRoot ($gatewayRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $gatewayOriginalContent = if (Test-Path -Path $gatewayPath) { Get-Content -Path $gatewayPath -Raw } else { $null }
        $gatewayOldBlock = @'
    expected_evidence = [
        "fresh changed_files for the target gateway/test files or blocked_with_inspection",
        "focused validation command output",
    ]
'@
        $gatewayNewBlock = @'
    expected_evidence = [
        "fresh changed_files for the selected one-file target or blocked_with_inspection naming target_file_exactly_one",
        "focused validation command output",
    ]
'@

        try {
            if (-not [string]::IsNullOrWhiteSpace($gatewayOriginalContent) -and -not $gatewayOriginalContent.Contains($gatewayOldBlock)) {
                $seededGatewayContent = if ($gatewayOriginalContent.Contains($gatewayNewBlock)) {
                    $gatewayOriginalContent.Replace($gatewayNewBlock, $gatewayOldBlock)
                }
                else {
                    $gatewayOriginalContent.TrimEnd() + "`n" + $gatewayOldBlock + "`n"
                }
                [System.IO.File]::WriteAllText($gatewayPath, $seededGatewayContent, (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Inspect Target File: tmp_remote_mim/core/routers/gateway.py
Previous blocker: blocked_missing_bounded_edit_mode because the handoff named both the gateway implementation file and its test file.
Required behavior: create a packet for exactly one gateway target_file after target_file_exactly_one blocked the broad MIM synced handoff.
Forbidden target paths for this packet: tmp_remote_mim/core/routers/gateway.py, scripts/run_mim_durability_smoke_v2.py
"@
            $scope = 'Publish packet_candidate_ready evidence for the MIM synced gateway multi-target split. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-FORBIDDEN-GATEWAY-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Forbidden gateway packet formation artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'blocked_forbidden_target'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'tmp_remote_mim/core/routers/gateway.py'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'allowed_target_file'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $gatewayOriginalContent) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 100
                [System.IO.File]::WriteAllText($gatewayPath, $gatewayOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'pivots inferred forbidden gateway packet formation to an allowed governance target' {
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_FORBIDDEN_GATEWAY_PIVOT_TEST.latest.json'
        $target = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $improvementRelativePath = 'tmp_remote_mim/core/routers/improvement.py'
        $improvementPath = Join-Path $repoRoot ($improvementRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $improvementOriginalContent = if (Test-Path -Path $improvementPath) { Get-Content -Path $improvementPath -Raw } else { $null }
        $improvementOldBlock = @'
    return {
        "updated": True,
        "proposal": to_improvement_proposal_out(proposal, latest_artifact=artifact),
        "artifact": to_improvement_artifact_out(artifact),
    }
'@
        $improvementNewBlock = @'
    return {
        "updated": True,
        "proposal": to_improvement_proposal_out(proposal, latest_artifact=artifact),
        "artifact": to_improvement_artifact_out(artifact),
        "review_decision_evidence": {
            "decision": "accepted",
            "journal_action": "improvement_proposal_accepted",
            "artifact_id": artifact.id,
            "reason_recorded": bool(payload.reason),
        },
    }
'@

        try {
            if (-not [string]::IsNullOrWhiteSpace($improvementOriginalContent) -and -not $improvementOriginalContent.Contains($improvementOldBlock)) {
                $seededImprovementContent = if ($improvementOriginalContent.Contains($improvementNewBlock)) {
                    $improvementOriginalContent.Replace($improvementNewBlock, $improvementOldBlock)
                }
                else {
                    $improvementOriginalContent
                }
                [System.IO.File]::WriteAllText($improvementPath, $seededImprovementContent, (New-Object System.Text.UTF8Encoding($false)))
            }

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Previous blocker: blocked_missing_bounded_edit_mode because the handoff named both the gateway implementation file and its test file.
Required behavior: create a packet for exactly one gateway target_file after target_file_exactly_one blocked the broad MIM synced handoff.
Forbidden target paths for this packet: tmp_remote_mim/core/routers/gateway.py, scripts/run_mim_durability_smoke_v2.py, tmp_remote_mim/core/routers/studio.py, scripts/TOD.ps1
"@
            $scope = 'Publish packet_candidate_ready evidence for the MIM synced gateway multi-target split. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-FORBIDDEN-GATEWAY-PIVOT-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Forbidden gateway packet formation pivot' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/improvement.py'
            [string]$updated.packet.selected_candidate | Should Be 'improvement_router_accept_review_decision_evidence'
            [string]$updated.packet.new_text | Should Match 'review_decision_evidence'
            [string]$updated.packet.validation_command | Should Match 'tmp_remote_mim/core/routers/improvement.py'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $improvementOriginalContent) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                Start-Sleep -Milliseconds 100
                [System.IO.File]::WriteAllText($improvementPath, $improvementOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
        }
    }

    It 'does not pivot a forbidden TOD fallback target just because gateway appears in rejected evidence' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-noisy-gateway-pivot-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_NOISY_GATEWAY_REJECTED_EVIDENCE.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Validation Command: if (-not (Get-Content -Path '.\$($relativePath -replace '/', '\')' | Select-String -SimpleMatch 'packet_candidate_ready')) { throw 'Validation pattern not found: packet_candidate_ready' } else { 'Validation pattern found: packet_candidate_ready' }
Required output: inspect current repository code and publish one current-code packet candidate with packet_candidate_ready=true.
Focus: materialized bounded edit proof for TOD recovery/autonomy backlog.
Forbidden target paths for this packet: tmp_remote_mim/core/routers/gateway.py, scripts/engines/LocalExecutionEngine.ps1, scripts/run_mim_durability_smoke_v2.py, scripts/TOD.ps1
Rejected candidate evidence to inspect before choosing the next target:
- packet_candidate:TOD_PACKET_FORMATION_GATEWAY_SPLIT_TEST.latest.json: packet_candidate_forbidden_by_current_discovery_drill
- synthesized_independent_resolution_candidate:fresh_current_code_candidate_packet_requirement: synthesized_candidate_not_materialized_as_behavior_changing_edit
"@
            $scope = 'Publish packet_candidate_ready evidence for materialized bounded edit proof. Do not use rejected gateway evidence as a fresh target.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-NOISY-GATEWAY-PIVOT' -ObjectiveId 'OBJ-LF' -Title 'Noisy gateway rejected evidence packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'blocked_forbidden_target'
            [bool]$updated.packet_candidate_ready | Should Be $false
            [string]$updated.blocker.target_file | Should Be 'scripts/TOD.ps1'
            [string]$updated.blocker.missing_anchor_or_field | Should Be 'allowed_target_file'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            @($result.commands_run | Where-Object { [string]$_ -match 'Select-String.+packet_candidate_ready' }).Count | Should Be 0
            @($result.commands_run | Where-Object { [string]$_ -match 'ConvertFrom-Json' }).Count | Should BeGreaterThan 0
            $pythonChecks = @($result.validation_results | Where-Object { [string]$_.name -match '^python_unittest' })
            $pythonChecks.Count | Should Be 2
            @($pythonChecks | Where-Object { $_.PSObject.Properties['required'] -and -not [bool]$_.required }).Count | Should Be 2

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'pivots from a forbidden stale fallback target to an allowed current-code packet candidate' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-forbidden-target-pivot-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_ALLOWED_PIVOT.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $studioRelative = 'tmp_remote_mim/core/routers/studio.py'
        $studioPath = Join-Path $tempRoot ($studioRelative -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($target, '{}', (New-Object System.Text.UTF8Encoding($false)))
            [System.IO.File]::WriteAllText($studioPath, 'I recommend working on MIM conversation mode selection next.', (New-Object System.Text.UTF8Encoding($false)))

            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Required output: inspect current repository code and publish one current-code packet candidate with packet_candidate_ready=true.
Focus: materialized bounded edit proof for TOD recovery/autonomy backlog.
Forbidden target paths for this packet: tmp_remote_mim/core/routers/gateway.py, scripts/engines/LocalExecutionEngine.ps1, scripts/run_mim_durability_smoke_v2.py, scripts/TOD.ps1
Rejected candidate evidence to inspect before choosing the next target:
- packet_candidate:TOD_PACKET_FORMATION_GATEWAY_SPLIT_TEST.latest.json: packet_candidate_forbidden_by_current_discovery_drill
- synthesized_independent_resolution_candidate:fresh_current_code_candidate_packet_requirement: synthesized_candidate_not_materialized_as_behavior_changing_edit
"@
            $scope = 'Publish packet_candidate_ready evidence for materialized bounded edit proof. Do not reuse any forbidden target path; choose a different current-code target.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-FORBIDDEN-TARGET-ALLOWED-PIVOT' -ObjectiveId 'OBJ-LF' -Title 'Forbidden target allowed pivot packet formation' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.target_file | Should Be $studioRelative
            [string]$updated.packet.target_file | Should Be $studioRelative
            [string]$updated.packet.selected_candidate | Should Be 'studio_recommendation_prioritizes_tod_materialization'
            [string]$updated.packet.old_text | Should Match 'MIM conversation mode selection'
            [string]$updated.packet.new_text | Should Match 'TOD self-authored bounded edit materialization'
            @($result.commands_run | Where-Object { [string]$_ -match 'Select-String.+packet_candidate_ready' }).Count | Should Be 0

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'writes Studio mode-selection packet candidates without changing the target yet' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-studio-mode-' + [guid]::NewGuid().ToString('N'))
        $relativePath = 'runtime_remote_training/tod_independent_resolution_attempts/TOD_STUDIO_MODE_SELECTION_BOUNDED_PACKET.latest.json'
        $target = Join-Path $tempRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $originalContent = if (Test-Path -Path $target) { Get-Content -Path $target -Raw } else { $null }
        $studioRelativePath = 'tmp_remote_mim/core/routers/studio.py'
        $studioPath = Join-Path $tempRoot ($studioRelativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $studioOriginalContent = if (Test-Path -Path $studioPath -PathType Leaf) { Get-Content -Path $studioPath -Raw } else { $null }
        $studioOldText = 'I recommend working on MIM conversation mode selection next.'
        $studioNewText = 'I recommend working on TOD self-authored bounded edit materialization next.'

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $studioPath) -Force | Out-Null
            if ($null -eq $studioOriginalContent) {
                [System.IO.File]::WriteAllText($studioPath, ($studioOldText + "`n"), (New-Object System.Text.UTF8Encoding($false)))
                $studioOriginalContent = $studioOldText + "`n"
            }
            if ($null -ne $studioOriginalContent -and -not $studioOriginalContent.Contains($studioOldText)) {
                $seededStudioContent = if ($studioOriginalContent.Contains($studioNewText)) {
                    $studioOriginalContent.Replace($studioNewText, $studioOldText)
                }
                else {
                    $studioOriginalContent.TrimEnd() + "`n" + $studioOldText + "`n"
                }
                [System.IO.File]::WriteAllText($studioPath, $seededStudioContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            $promptPath = New-LocalFallbackPromptFile -Content @"
Target File: $relativePath
Edit Mode: artifact_write
Validation Pattern: packet_candidate_ready
Packet Source Target: tmp_remote_mim/core/routers/studio.py
Observed blocker: blocked_missing_bounded_edit_mode because TOD did not provide edit_mode plus exact current old_text_or_anchor and new_text_or_snippet.
Required behavior: inspect the Studio mode-selection target and publish packet_candidate_ready with exact current old_text/new_text, or publish a precise blocker. Do not change the Studio target in this packet-formation step.
"@
            $scope = 'Publish inspected packet candidate for Studio mode-selection bounded edit. No implementation credit. Dave-needed no.'
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-STUDIO-MODE-PACKET' -ObjectiveId 'OBJ-LF' -Title 'Studio mode packet candidate artifact write' -Scope $scope -PromptPath $promptPath -Metadata @{ task_category = 'packet_formation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $updated = Get-Content -Path $target -Raw | ConvertFrom-Json
            $studioAfterContent = if (Test-Path -Path $studioPath -PathType Leaf) { Get-Content -Path $studioPath -Raw } else { '' }

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $relativePath) | Should Be $true
            [string]$updated.artifact_type | Should Be 'tod_packet_formation_artifact'
            [string]$updated.status | Should Be 'packet_candidate_ready'
            [bool]$updated.packet_candidate_ready | Should Be $true
            [string]$updated.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.packet.selected_candidate | Should Be 'studio_recommendation_prioritizes_tod_materialization'
            [string]$updated.packet.target_file | Should Be 'tmp_remote_mim/core/routers/studio.py'
            [string]$updated.packet.intended_edit_mode | Should Be 'replace_text'
            [string]$updated.packet.old_text | Should Match 'MIM conversation mode selection'
            [string]$updated.packet.new_text | Should Match 'TOD self-authored bounded edit materialization'
            [string]$updated.packet.validation_pattern | Should Match 'TOD self-authored bounded edit materialization'
            [string]$updated.validation_command | Should Match '_studio_conversation_mode_reply'
            [string]$updated.packet.validation_command | Should Match 'TOD self-authored bounded edit materialization'
            [string]$updated.dave_needed | Should Be 'no'
            [bool]$updated.credit_decision.independent_tod_resolution | Should Be $false
            [bool]$updated.credit_decision.meaningful_tod_implementation | Should Be $false
            [bool]$updated.credit_decision.validated_tod_edit | Should Be $false
            [string]$studioAfterContent | Should Match ([regex]::Escape($studioOldText))

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if ([string]::IsNullOrWhiteSpace($originalContent)) {
                if (Test-Path -Path $target) { Remove-Item -Path $target -Force }
            }
            else {
                [System.IO.File]::WriteAllText($target, $originalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if ($null -ne $studioOriginalContent) {
                [System.IO.File]::WriteAllText($studioPath, $studioOriginalContent, (New-Object System.Text.UTF8Encoding($false)))
            }
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'requires explicit validation pattern for append_section when supplied' {
        $relativePath = ('docs/local-fallback-validation-marker-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        [System.IO.File]::WriteAllText($absolutePath, "# Marker validation fixture`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Update $relativePath.
Edit Mode: append_section
Section Title: Marker Validation Section
Section Body: This body intentionally omits the required proof marker.
Validation Pattern: REQUIRED_PROOF_MARKER_123
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-MARKER-STRICT' -ObjectiveId 'OBJ-LF' -Title 'Require explicit marker' -Scope ("Patch $relativePath with an append_section change.") -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_validation_failed'
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Not Match 'Marker Validation Section'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'maps simple MIM workspace filenames into the tmp_remote_mim mirror safely' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/routes.py'
        $createdMirror = $false
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $mirrorPath) -Force | Out-Null
            [System.IO.File]::WriteAllText($mirrorPath, "# temporary MIM routes mirror`n", (New-Object System.Text.UTF8Encoding($false)))
            $createdMirror = $true
        }

        try {
            [string](Convert-ToLocalExecutionRepoRelativePath -PathValue 'routes.py') | Should Be 'tmp_remote_mim/routes.py'
            [bool](Test-LocalExecutionSafePath -RelativePath 'routes.py') | Should Be $true

            $promptPath = New-LocalFallbackPromptFile -Content @"
Update routes.py.
Edit Mode: validation_only
Validation Pattern: workspace
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-ROUTES' -ObjectiveId 'OBJ-LF' -Title 'Validate MIM routes mirror' -Scope 'Validate routes.py through the local MIM workspace mirror.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'routes.py' }
            [string]@(Get-LocalExecutionTargetFiles -Context $context)[0] | Should Be 'tmp_remote_mim/routes.py'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        } finally {
            if ($createdMirror -and (Test-Path -Path $mirrorPath -PathType Leaf)) {
                Remove-Item -Path $mirrorPath -Force
            }
        }
    }

    It 'maps MIM app-relative core paths into the tmp_remote_mim mirror safely' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/core/routers/gateway.py'
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            throw "Expected MIM gateway mirror at $mirrorPath"
        }

        [string](Convert-ToLocalExecutionRepoRelativePath -PathValue 'core/routers/gateway.py') | Should Be 'tmp_remote_mim/core/routers/gateway.py'
        [bool](Test-LocalExecutionSafePath -RelativePath 'core/routers/gateway.py') | Should Be $true

        $promptPath = New-LocalFallbackPromptFile -Content @"
Update gateway.py.
Target File: core/routers/gateway.py
Edit Mode: validation_only
Validation Pattern: gateway
"@
        try {
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-CORE-GATEWAY' -ObjectiveId 'OBJ-LF' -Title 'Validate MIM gateway mirror path mapping' -Scope 'Validate core/routers/gateway.py through the local MIM workspace mirror.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'core/routers/gateway.py' }
            [string]@(Get-LocalExecutionTargetFiles -Context $context)[0] | Should Be 'tmp_remote_mim/core/routers/gateway.py'
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'canonicalizes MIM app-relative validation commands into the tmp_remote_mim mirror' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/core/routers/gateway.py'
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            throw "Expected MIM gateway mirror at $mirrorPath"
        }

        [string](Convert-LocalExecutionValidationCommandPaths -Command 'python -m py_compile .\core\routers\gateway.py' -TargetFile 'tmp_remote_mim/core/routers/gateway.py') | Should Be 'python -m py_compile .\tmp_remote_mim\core\routers\gateway.py'
        [string](Convert-LocalExecutionValidationCommandPaths -Command 'python -m py_compile tmp_remote_mim/core/routers/gateway.py' -TargetFile 'tmp_remote_mim/core/routers/gateway.py') | Should Be 'python -m py_compile tmp_remote_mim/core/routers/gateway.py'

        $promptPath = New-LocalFallbackPromptFile -Content @'
Target File: core/routers/gateway.py
Edit Mode: validation_only
Validation Command: python -m py_compile .\core\routers\gateway.py
'@
        try {
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-CORE-GATEWAY-VALIDATION' -ObjectiveId 'OBJ-LF' -Title 'Validate MIM gateway mirror command mapping' -Scope 'Validate core/routers/gateway.py through the local MIM workspace mirror.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'core/routers/gateway.py' }
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            [bool]$result.no_change_required | Should Be $true
            @($result.validation_results | Where-Object { [string]$_.name -eq 'validation_only_no_file_change_expected' -and [bool]$_.passed }).Count | Should Be 1
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'validates the MIM ARM workspace safety calibration slice without moving hardware' {
        $mirrorPath = Join-Path $repoRoot 'tmp_remote_mim/routes.py'
        $createdMirror = $false
        if (-not (Test-Path -Path $mirrorPath -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $mirrorPath) -Force | Out-Null
            $content = @"
from flask import jsonify, request

def _workspace_servo_limit_for(servo_index):
    return {"configured": False, "min": 0, "max": 180, "source": "default"}

def _workspace_clamp_servo_angle(servo_index, requested_angle):
    limit = _workspace_servo_limit_for(servo_index)
    clamped_angle = max(int(limit["min"]), min(int(limit["max"]), int(requested_angle)))
    return clamped_angle, {"table_edge_guard": "servo_limit_clamp"}

def move_servo():
    data = request.get_json()
    servo = int(data['servo'])
    angle = int(data['angle'])
    requested_angle = angle
    angle, safety = _workspace_clamp_servo_angle(servo, requested_angle)
    dry_run = bool(data.get("dry_run") or data.get("no_motion") or data.get("validate_only"))
    if dry_run:
        update_serial_runtime("move_dry_run_validated")
        return jsonify({"status": "ok", "safety": safety}), 200
"@
            [System.IO.File]::WriteAllText($mirrorPath, $content, (New-Object System.Text.UTF8Encoding($false)))
            $createdMirror = $true
        }

        try {
            $promptPath = New-LocalFallbackPromptFile -Content @"
OBJECTIVE: MIM-ARM-WORKSPACE-SAFETY-CALIBRATION-V1
TARGET FILE: routes.py
Validate the workspace safety calibration route, servo limit clamp, dry_run no-motion path, and table edge guard.
"@
            $context = New-LocalFallbackContext -TaskId 'TSK-LF-MIM-ARM-SAFETY' -ObjectiveId 'mim-arm-workspace-safety-calibration-v1' -Title 'MIM ARM workspace safety calibration' -Scope 'Validate workspace safety calibration for routes.py without moving hardware.' -PromptPath $promptPath -Metadata @{ task_category = 'implementation_repair'; local_fallback_target_file = 'routes.py' }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            [bool]$result.no_change_required | Should Be $true
            @($result.files_changed).Count | Should Be 0
            [string]$result.diff_summary | Should Match 'without invoking hardware'
            @($result.validation_results | Where-Object { [string]$_.name -eq 'python_compile_passed' -and [bool]$_.passed }).Count | Should Be 1

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        } finally {
            if ($createdMirror -and (Test-Path -Path $mirrorPath -PathType Leaf)) {
                Remove-Item -Path $mirrorPath -Force
            }
        }
    }

    It 'rejects blocked traversal paths' {
        $promptText = @"
Update scripts/../../danger.ps1.
Edit Mode: replace_text
Old Text: OLD_SENTINEL
New Text: NEW_SENTINEL
Validation Pattern: NEW_SENTINEL
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-BLOCKED' -ObjectiveId 'OBJ-LF' -Title 'Patch blocked path' -Scope 'Patch scripts/../../danger.ps1 with a bounded replace_text change.' -PromptPath $promptPath -Metadata @{ task_category = 'code_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_path_not_allowed'
        [string]$result.blockers[0].missing_variable | Should Be 'allowed_path'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'allows learned capability artifact writes inside the bounded training artifact root' {
        $relativePath = 'runtime_remote_training/learned_capabilities/TOD_BOUNDED_PACKET_FIELD_PRESERVATION_TEST.latest.json'
        $targetPath = Join-Path $repoRoot ($relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -Path $targetPath -PathType Leaf) {
            Remove-Item -Path $targetPath -Force
        }
        $promptText = @"
Target File: $relativePath
Edit Mode: artifact_write
New Text: {"capability_name":"Bounded Packet Field Preservation Test","validation":"safe-root write allowed"}
Validation Command: if (-not (Select-String -Path $relativePath -Pattern 'Bounded Packet Field Preservation Test' -SimpleMatch -Quiet)) { throw 'learned capability test artifact missing' }
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-LEARNED-CAPABILITY' -ObjectiveId 'OBJ-LF' -Title 'Freeze learned capability' -Scope 'Write a learned capability artifact under the bounded training artifact root.' -PromptPath $promptPath -Metadata @{ task_category = 'artifact_write'; local_fallback_target_file = $relativePath }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        (@($result.files_changed) -contains $relativePath) | Should Be $true
        (Test-Path -Path $targetPath -PathType Leaf) | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        if (Test-Path -Path $targetPath -PathType Leaf) {
            Remove-Item -Path $targetPath -Force
        }
    }

    It 'publishes regression snapshot counts and failure families from read-only audit input' {
        $inputRel = ('tod/out/tests/regression-summary-{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_REGRESSION_AUDIT_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $summary = [ordered]@{
            generated_at = '2026-07-10T01:00:00Z'
            passed_all = $false
            passed = 410
            failed = 3
            total = 413
            failed_tests = @(
                [ordered]@{ describe = 'TOD local fallback executor'; name = 'first'; message = 'failed'; classification = 'deterministic' },
                [ordered]@{ describe = 'TOD local fallback executor'; name = 'second'; message = 'failed'; classification = 'deterministic' },
                [ordered]@{ describe = 'TOD self-driving next task selection'; name = 'third'; message = 'failed'; classification = 'deterministic' }
            )
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, ($summary | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input: $inputRel
Output artifact: $outputRel
Audit Subject: TOD operations regression snapshot.
Use the read-only audit artifact lane.
No code changes.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-REGRESSION-AUDIT' -ObjectiveId 'OBJ-LF' -Title 'Regression snapshot read-only audit artifact' -Scope $promptText -PromptPath $promptPath -Metadata @{ task_category = 'report_only' }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.classification | Should Be 'regression_snapshot_review_required'
        @($artifact.evidence_used[0].fields) -contains 'failed_tests' | Should Be $true
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'regression_snapshot_counts' -and [string]$_.evidence -match 'passed=410; failed=3; total=413' }).Count | Should Be 1
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'regression_failure_families' -and [string]$_.evidence -match 'TOD local fallback executor' }).Count | Should Be 1
        @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'regression_failures' }).Count | Should Be 1
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        if (Test-Path -Path $inputPath -PathType Leaf) {
            Remove-Item -Path $inputPath -Force
        }
        if (Test-Path -Path $outputPath -PathType Leaf) {
            Remove-Item -Path $outputPath -Force
        }
    }

    It 'publishes semantic source audit fields from source-anchor artifacts' {
        $inputOneRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SEMANTIC_ANCHOR_ONE_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputTwoRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SEMANTIC_ANCHOR_TWO_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SEMANTIC_AUDIT_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputOnePath = Join-Path $repoRoot ($inputOneRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $inputTwoPath = Join-Path $repoRoot ($inputTwoRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $anchorOne = [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'tmp_remote_mim/core/next_step_dialog_service.py'
            anchor_pattern = 'def _derive_capability_model_status('
            start_line = 1
            end_line = 20
            exact_text = @'
def _derive_capability_model_status(*, item, metadata, shared_root):
    return {
        "artifact_type": "mim_capability_model_v1",
        "capability_name": "requested capability",
        "confidence": "medium",
    }
'@
        }
        $anchorTwo = [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            source_file = 'tmp_remote_mim/core/next_step_dialog_service.py'
            anchor_pattern = 'def _collect_contract_output_fields('
            start_line = 21
            end_line = 80
            exact_text = @'
def _collect_contract_output_fields(*, item, metadata, required_fields, shared_root):
    candidate_sources = _contract_candidate_sources(item=item, metadata=metadata, shared_root=shared_root)
    for raw_field in required_fields:
        field = str(raw_field or "").strip()
        value = _first_present_source_value(candidate_sources, field)
        if value is None:
            missing_fields.append(field)

def _contract_candidate_sources(*, item, metadata, shared_root):
    capability_model_status = _derive_capability_model_status(item=item, metadata=metadata, shared_root=shared_root)
    if capability_model_status:
        candidate_sources.append(capability_model_status)
'@
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputOnePath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputOnePath, ($anchorOne | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText($inputTwoPath, ($anchorTwo | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Semantic read-only audit-body synthesis from source-anchor evidence.
Input: $inputOneRel
Additional Evidence: $inputTwoRel
Output: $outputRel

Required output fields: observed_blocker, suspected_root_cause, evidence_checked, evidence_missing, why_forward_motion_is_blocked, smallest_diagnostic_step, confidence, no_phrase_patch_rule=true.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-SEMANTIC-SOURCE-AUDIT' -ObjectiveId 'OBJ-LF' -Title 'Semantic source audit artifact' -Scope $promptText -PromptPath $promptPath -Metadata @{ task_category = 'inspection_only' }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.artifact_type | Should Be 'tod_semantic_source_audit_artifact'
        [string]$artifact.classification | Should Be 'semantic_audit_body_synthesis_from_source_anchors'
        [string]$artifact.observed_blocker | Should Not BeNullOrEmpty
        [string]$artifact.suspected_root_cause | Should Match 'contract collector'
        @($artifact.evidence_checked).Count -ge 2 | Should Be $true
        [string]$artifact.why_forward_motion_is_blocked | Should Not BeNullOrEmpty
        [string]$artifact.smallest_diagnostic_step | Should Not BeNullOrEmpty
        [bool]$artifact.no_phrase_patch_rule | Should Be $true
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        foreach ($path in @($inputOnePath, $inputTwoPath, $outputPath)) {
            if (Test-Path -Path $path -PathType Leaf) {
                Remove-Item -Path $path -Force
            }
        }
    }

    It 'keeps source-anchor observation ahead of contaminated route patch evidence wording' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-source-anchor-precedence-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/LocalExecutionEngine.ps1'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SOURCE_ANCHOR_PRECEDENCE.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @'
function Invoke-LocalExecutionEngine {
elseif (Test-LocalExecutionReadOnlyAuditArtifactTask -Context $Context) {
    $result = Invoke-LocalExecutionReadOnlyAuditArtifact -Context $Context -Result $result -Spec $spec
}
elseif (Test-LocalExecutionFreshRoutePatchEvidenceRegistrationTask -Context $Context) {
    $result = Invoke-LocalExecutionFreshRoutePatchEvidenceRegistration -Context $Context -Result $result -Spec $spec
}
elseif (Test-LocalExecutionPatchEvidenceArtifactTask -Context $Context) {
    $result = Invoke-LocalExecutionPatchEvidenceArtifact -Context $Context -Result $result -Spec $spec
}
}
'@, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: source_anchor_observation
Read-only source-anchor observation for selector precedence.

Source File: $sourceRel
Output: $outputRel
Anchor Pattern: elseif (Test-LocalExecutionFreshRoutePatchEvidenceRegistrationTask
Lines Before: 1
Lines After: 4

Mission:
Capture the exact source-anchor observation. The surrounding objective mentions fresh route patch evidence, authority classification, cleanup_holds patch history, and route-level experiments, but this task must not become patch evidence classification.
Do not modify source code.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-SOURCE-ANCHOR-PRECEDENCE' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Source anchor outranks route patch evidence wording' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'source_anchor_observation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]@($result.files_changed)[0] | Should Be $outputRel
            [string]$artifact.artifact_type | Should Be 'tod_source_anchor_observation'
            [string]$artifact.source_file | Should Be $sourceRel
            [string]$artifact.anchor_pattern | Should Be 'elseif (Test-LocalExecutionFreshRoutePatchEvidenceRegistrationTask'
            [bool]$artifact.source_read | Should Be $true
            [bool]$artifact.anchor_found | Should Be $true
            [bool]$artifact.exact_text_nonempty | Should Be $true
            [string]$artifact.source_function | Should Be 'Invoke-LocalExecutionEngine'
            [string]$artifact.function_surface | Should Be 'Invoke-LocalExecutionEngine'
            [bool]$artifact.validation.source_function_inferred | Should Be $true
            [int]$artifact.context_start_line | Should Be 4
            [int]$artifact.context_end_line | Should Be 9
            [bool]$artifact.no_code_changes | Should Be $true
            [string]$result.summary | Should Match 'Published source anchor observation'
            [string]$result.summary | Should Not Match 'route patch evidence'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'infers the nearest Python function instead of an earlier JavaScript function' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-source-anchor-python-function-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/source_anchor_sample.py'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_SOURCE_ANCHOR_PYTHON_FUNCTION.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @'
function closeBatPhoneModal() {
    return true;
}

def _run_studio_auditor_observatory_certification():
    certification_id = "observatory-certification"
    return certification_id
'@, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: source_anchor_observation
Task Category: source_anchor_observation
Source File: $sourceRel
Output: $outputRel
Anchor Pattern: certification_id =
Lines Before: 1
Lines After: 1

Mission:
Capture the Python function containing the selected source anchor without inheriting an unrelated earlier JavaScript function name.
Do not modify source code.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-SOURCE-ANCHOR-PYTHON-FUNCTION' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Infer Python source function' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'source_anchor_observation'; task_mode = 'source_anchor_observation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.source_function | Should Be '_run_studio_auditor_observatory_certification'
            [string]$artifact.function_surface | Should Be '_run_studio_auditor_observatory_certification'
            [bool]$artifact.validation.source_function_inferred | Should Be $true
            [bool]$artifact.no_code_changes | Should Be $true

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'keeps packaged source-anchor observation ahead of generic audit when role evidence is present' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-source-anchor-role-evidence-' + [guid]::NewGuid().ToString('N'))
        $sourceRel = 'scripts/engines/LocalExecutionEngine.ps1'
        $roleRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_ROLE_EVIDENCE.latest.json'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_WITH_ROLE_EVIDENCE.latest.json'
        $sourceAbs = Join-Path $tempRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $roleAbs = Join-Path $tempRoot ($roleRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            New-Item -ItemType Directory -Path (Split-Path -Parent $sourceAbs) -Force | Out-Null
            New-Item -ItemType Directory -Path (Split-Path -Parent $roleAbs) -Force | Out-Null
            [System.IO.File]::WriteAllText($sourceAbs, @'
elseif (Test-LocalExecutionReadOnlyAuditArtifactTask -Context $Context) {
    $result = Invoke-LocalExecutionReadOnlyAuditArtifact -Context $Context -Result $result -Spec $spec
}
elseif (Test-LocalExecutionSourceAnchorObservationTask -Context $Context) {
    $result = Invoke-LocalExecutionSourceAnchorObservation -Context $Context -Result $result -Spec $spec
}
'@, (New-Object System.Text.UTF8Encoding($false)))
            [ordered]@{
                artifact_type = 'tod_read_only_role_classification_artifact'
                communication_role_map = [ordered]@{
                    'Source File' = 'source_to_inspect_read_only'
                    'Output' = 'evidence_artifact_to_write'
                    'Target File' = 'bounded_edit_target_only_when_edit_mode_or_behavior_change_is_authorized'
                }
                no_code_changes = $true
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $roleAbs -Encoding utf8

            $promptText = @"
Task mode: source_anchor_observation
Task Category: source_anchor_observation
Role Evidence: $roleRel
Source File: $sourceRel
Output: $outputRel
Anchor Pattern: elseif (Test-LocalExecutionSourceAnchorObservationTask
Lines Before: 1
Lines After: 3

Mission:
Capture the exact source-anchor observation. Source File is read-only input. Output is the artifact destination. Role Evidence is input evidence, not a bounded edit target.
Do not modify source code.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-SOURCE-ANCHOR-ROLE-EVIDENCE' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Source anchor with role evidence' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'source_anchor_observation'; task_mode = 'source_anchor_observation' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]@($result.files_changed)[0] | Should Be $outputRel
            [string]$artifact.artifact_type | Should Be 'tod_source_anchor_observation'
            [string]$artifact.source_file | Should Be $sourceRel
            [bool]$artifact.source_read | Should Be $true
            [bool]$artifact.anchor_found | Should Be $true
            [bool]$artifact.exact_text_nonempty | Should Be $true
            [bool]$artifact.no_code_changes | Should Be $true
            [string]@($result.commands_run)[0] | Should Be 'Invoke-LocalExecutionSourceAnchorObservation'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'publishes read-only role classification when source and artifact paths are not edit targets' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-role-classification-' + [guid]::NewGuid().ToString('N'))
        $inputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_ROLE_CLASSIFICATION_INPUT.latest.json'
        $outputRel = 'runtime_remote_training/read_only_audit_artifacts/TOD_TEST_ROLE_CLASSIFICATION_OUTPUT.latest.json'
        $sourceRel = 'scripts/engines/LocalExecutionEngine.ps1'
        $todRel = 'scripts/TOD.ps1'
        $inputAbs = Join-Path $tempRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $tempRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            foreach ($fixturePath in @($sourceRel, $todRel)) {
                $absoluteFixture = Join-Path $tempRoot ($fixturePath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
                New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteFixture) -Force | Out-Null
                [System.IO.File]::WriteAllText($absoluteFixture, ('# fixture: ' + $fixturePath), (New-Object System.Text.UTF8Encoding($false)))
            }

            New-Item -ItemType Directory -Path (Split-Path -Parent $inputAbs) -Force | Out-Null
            $inputArtifact = [ordered]@{
                blocker_class = 'authority_blocker'
                summary = 'Read-only inspection prompt was misread as having multiple bounded edit target files.'
                observed_candidates = @($inputRel, $todRel, $sourceRel, $outputRel)
            } | ConvertTo-Json -Depth 8
            [System.IO.File]::WriteAllText($inputAbs, $inputArtifact, (New-Object System.Text.UTF8Encoding($false)))

            $promptText = @"
Task mode: inspection
Read-only selector authority role classification.

Evidence Artifact: $inputRel
Package Path: tod/out/prompts/TOD-TEST-ROLE-CLASSIFICATION.md
Inspect Source File: $todRel
Inspect Source File: $sourceRel
Output: $outputRel

Mission:
Classify communication_role_map for Source File, Output, Evidence Artifact, Package Path, and Target File.
Do not modify source code.
Do not create a bounded edit packet.
"@
            $promptPath = New-LocalFallbackPromptFile -Content $promptText
            $context = New-LocalFallbackContext `
                -TaskId 'TSK-LF-ROLE-CLASSIFICATION' `
                -ObjectiveId 'OBJ-LF' `
                -Title 'Read-only role classification' `
                -Scope $promptText `
                -PromptPath $promptPath `
                -Metadata @{ task_category = 'inspection_only' }

            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed) -contains $outputRel) | Should Be $true
            [string]$artifact.artifact_type | Should Be 'tod_read_only_role_classification_artifact'
            [string]$artifact.communication_role_map.'Evidence Artifact' | Should Be 'input_evidence_read_only'
            [string]$artifact.communication_role_map.'Source File' | Should Be 'source_to_inspect_read_only'
            [string]$artifact.communication_role_map.'Output' | Should Be 'evidence_artifact_to_write'
            [string]$artifact.communication_role_map.'Target File' | Should Be 'bounded_edit_target_only_when_edit_mode_or_behavior_change_is_authorized'
            [string]$artifact.blocker_class | Should Be 'authority_blocker'
            [bool]$artifact.no_code_changes | Should Be $true
            @($artifact.observed_paths.source_files).Count | Should Be 2

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) { Remove-Item -Path $tempRoot -Recurse -Force }
        }
    }

    It 'publishes SolAir research evidence demonstration from source evidence without new text' {
        $sourceRel = 'runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION.latest.json'
        $outputRel = ('runtime/shared/TOD_TEST_INDEPENDENT_UNSEEN_DEMO_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $sourcePath = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -Path $sourcePath -PathType Leaf)) {
            Set-ItResult -Skipped -Because 'SolAir power curve source artifact is not present in this checkout.'
            return
        }

        $promptText = @"
OBJECTIVE: TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-TEST

Goal: TOD independently demonstrates borrowed artifact-body synthesis on a fresh analogous case without Codex-provided final artifact body text.

Fresh case: SolAir power-output question. Read-only source evidence is the SolAir power curve observation artifact in the runtime shared folder.

Source evidence: $sourceRel
Target File: $outputRel
Edit Mode: artifact_write
Task Category: validation_only

Required proof fields:
- objective_id
- selected_unseen_case
- source_evidence_discovered
- diagnosis
- authority_boundary
- answer_model
- validation_plan
- validation_result
- what_TOD_did_without_Codex
- what_TOD_still_cannot_do
- registry_update_recommendation

Rules:
- No source code edits.
- No hardcoded answer snippets from Codex.
- No final completion claim unless the JSON artifact exists and all required fields are populated from source evidence.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-SOLAIR-UNSEEN-DEMO' -ObjectiveId 'OBJ-LF' -Title 'SolAir unseen apprenticeship demonstration' -Scope $promptText -PromptPath $promptPath -Metadata @{ task_category = 'validation_only'; local_fallback_target_file = $outputRel }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.artifact_type | Should Be 'tod_independent_unseen_apprenticeship_demonstration'
        [string]$artifact.selected_unseen_case | Should Match 'SolAir'
        @($artifact.source_evidence_discovered).Count | Should Be 1
        [int]$artifact.source_evidence_discovered[0].physics_limit_rows | Should BeGreaterThan 0
        [int]$artifact.source_evidence_discovered[0].chart_rows | Should BeGreaterThan 0
        [double]$artifact.answer_model.ten_mph.physics_after_generator_efficiency_watts | Should Be 52.7
        [double]$artifact.answer_model.ten_mph.chart_one_unit_watts | Should Be 175
        [bool]$artifact.answer_model.ten_mph.source_conflict | Should Be $true
        [string]$artifact.authority_boundary.answer_rule | Should Match 'Report both lanes'
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        if (Test-Path -Path $outputPath -PathType Leaf) {
            Remove-Item -Path $outputPath -Force
        }
    }

    It 'completes validation_only tasks without changing the target file' {
        $promptText = @"
Inspect scripts/TOD.ps1.
Edit Mode: validation_only
Validation Pattern: function Invoke-ExecuteChatTaskRequest
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-VALIDATE' -ObjectiveId 'OBJ-LF' -Title 'Validate TOD task route' -Scope 'Inspect scripts/TOD.ps1 and publish validation only.' -PromptPath $promptPath -Metadata @{ task_category = 'validation'; local_fallback_target_file = 'scripts/TOD.ps1' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        [bool]$result.no_change_required | Should Be $true
        [string]$result.diff_summary | Should Match 'Validated bounded target'
        @($result.commands_run).Count | Should Be 1

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'blocks validation_only when failed-patch recovery requires a behavior-changing edit' {
        $promptText = @"
Target File: scripts/TOD.ps1
Recovery Mode: failed_material_patch
Required behavior: inspect the failed target file and repair the smallest behavior-changing patch.
Closure Evidence: changed target file, passing validation command, prevention lesson, and no independent-resolution credit unless TOD performs the full fix/validate/close loop.
Edit Mode: validation_only
Validation Pattern: function Invoke-ExecuteChatTaskRequest
No validation-only completion.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-RECOVERY-VALIDATION-ONLY' -ObjectiveId 'OBJ-LF' -Title 'Reject validation-only recovery' -Scope 'Recover failed material patch; no validation-only completion.' -PromptPath $promptPath -Metadata @{ task_category = 'code_change'; local_fallback_target_file = 'scripts/TOD.ps1' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_validation_only_forbidden'
        [string]$result.blockers[0].missing_variable | Should Be 'behavior_changing_edit'
        @($result.files_changed).Count | Should Be 0

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'blocks missing target files with the exact missing variable' {
        $relativePath = ('docs/local-fallback-missing-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $promptText = @"
Update $relativePath.
Edit Mode: append_section
Section Title: Missing Target
Section Body: This section should not be written.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-MISSING' -ObjectiveId 'OBJ-LF' -Title 'Patch missing target' -Scope ("Update $relativePath with a Missing Target section.") -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'failed'
        [string]$result.reason_code | Should Be 'local_fallback_needs_target_or_scope'
        [string]$result.blockers[0].missing_variable | Should Be 'existing_target_file'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'triggers local fallback when codex only returns wrapper output' {
        $relativePath = ('docs/local-fallback-wrapper-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Wrapper Fallback`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Wrapper Evidence section." -f $relativePath)
        $task = [pscustomobject]@{
            id = 'TSK-LF-WRAPPER'
            objective_id = 'OBJ-LF'
            title = 'Update wrapper fallback docs'
            scope = ("Update {0} with a short Wrapper Evidence section." -f $relativePath)
            type = 'implementation'
            task_category = 'docs_change'
        }
        $engineConfig = [pscustomobject]@{
            active = 'codex'
            fallback = 'local'
            allow_fallback = $true
            retry_policy = [pscustomobject]@{
                enabled = $false
                max_attempts_per_engine = 1
                retry_on_status = @('failed', 'error', 'not_implemented')
            }
        }

        $invocation = Invoke-ExecutionEngine -Task $task -TaskId 'TSK-LF-WRAPPER' -PackagePath $promptPath -EngineConfig $engineConfig

        [bool]$invocation.fallback_applied | Should Be $true
        [string]$invocation.active_engine | Should Be 'local'
        [string]$invocation.result.status | Should Be 'completed'
        [string]@($invocation.result.files_changed)[0] | Should Be $relativePath
        [string]$invocation.result.command_output | Should Match 'Wrapper Evidence'
        [string]$invocation.result.diff_summary | Should Match $relativePath
        [string]@($invocation.result.commands_run)[0] | Should Match 'Select-String'
        @($invocation.result.validation_results).Count | Should BeGreaterThan 0
        [string]$invocation.result.confidence | Should Be 'medium-high'
        [string]$invocation.result.rollback_hint | Should Match 'Copy-Item'
        ([string](Get-Content -Path $absolutePath -Raw)) | Should Match '## Wrapper Evidence'

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'patches prompt token extraction with bounded local fallback evidence' {
        $originalRoot = $script:LocalEngineRepoRoot
        $tempRoot = Join-Path $repoRoot ('tod/out/tests/local-fallback-token-' + [guid]::NewGuid().ToString('N'))
        $targetRelativePath = 'tmp_remote_mim/core/routers/tod_ui.py'
        $targetAbsolutePath = Join-Path $tempRoot ($targetRelativePath -replace '/', '\\')
        $targetDir = Split-Path -Parent $targetAbsolutePath
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Copy-Item -Path (Join-Path $repoRoot ($targetRelativePath -replace '/', '\\')) -Destination $targetAbsolutePath -Force

        $currentSnippet = @'
def _extract_identifier_token(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    match = re.search(r"[A-Za-z0-9][A-Za-z0-9._:-]*", text)
    if not match:
        return _compact_text(text, 220)
    return match.group(0).rstrip(".,;:)]}>")


def _extract_labeled_prompt_value(message: str, label: str) -> str:
    text = str(message or "")
    lines = text.splitlines()
    normalized_label = re.sub(r"[_\s-]+", r"[_\\s-]+", str(label or "").strip())
    label_pattern = re.compile(rf"^\s*(?:(?:[-*]|#{{1,6}})\s*)?{normalized_label}\s*:\s*(.*)$", re.IGNORECASE)
    next_label_pattern = re.compile(r"^\s*(?:(?:[-*]|#{1,6})\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:\s*(.*)$")
    identifier_labels = {"initiative_id", "objective_id", "task_id", "request_id"}
    normalized_label_key = re.sub(r"[^a-z0-9]+", "_", str(label or "").strip().lower()).strip("_")
    for index, line in enumerate(lines):
        match = label_pattern.match(line)
        if not match:
            continue
        if normalized_label_key in identifier_labels:
            return _extract_identifier_token(match.group(1))
        collected = [str(match.group(1) or "").strip()]
        for next_line in lines[index + 1 :]:
            if next_label_pattern.match(next_line):
                break
            stripped = str(next_line or "").strip()
            if stripped:
                collected.append(stripped)
        return _compact_text(" ".join(item for item in collected if item), 220)
    pattern = re.compile(
        rf"(?:^|\b){normalized_label}\s*:\s*(.+?)(?=\s+(?:(?:[-*]|#{{1,6}})\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:|$)",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        return ""
    value = match.group(1)
    if normalized_label_key in identifier_labels:
        return _extract_identifier_token(value)
    return _compact_text(value, 220)
'@
        $oldSnippet = @'
def _extract_labeled_prompt_value(message: str, label: str) -> str:
    text = str(message or "")
    lines = text.splitlines()
    normalized_label = re.sub(r"[_\s-]+", r"[_\\s-]+", str(label or "").strip())
    label_pattern = re.compile(rf"^\s*(?:[-*]\s*)?{normalized_label}\s*:\s*(.*)$", re.IGNORECASE)
    next_label_pattern = re.compile(r"^\s*(?:[-*]\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:\s*(.*)$")
    for index, line in enumerate(lines):
        match = label_pattern.match(line)
        if not match:
            continue
        collected = [str(match.group(1) or "").strip()]
        for next_line in lines[index + 1 :]:
            if next_label_pattern.match(next_line):
                break
            stripped = str(next_line or "").strip()
            if stripped:
                collected.append(stripped)
        return _compact_text(" ".join(item for item in collected if item), 220)
    pattern = re.compile(
        rf"(?:^|\b){normalized_label}\s*:\s*(.+?)(?=\s+(?:[-*]\s*)?[A-Z][A-Za-z0-9_]*(?:[ _-][A-Z][A-Za-z0-9_]*)*\s*:|$)",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        return ""
    return _compact_text(match.group(1), 220)
'@
        $seededContent = [string](Get-Content -Path $targetAbsolutePath -Raw)
        [System.IO.File]::WriteAllText($targetAbsolutePath, $seededContent.Replace($currentSnippet, $oldSnippet), (New-Object System.Text.UTF8Encoding($false)))

        try {
            $script:LocalEngineRepoRoot = $tempRoot
            $promptPath = New-LocalFallbackPromptFile -Content '# TOD Task Execution Package`n- Objective Description: Patch token extraction so only the identifier value is captured.'
            $context = New-LocalFallbackContext -TaskId 'objective-2913-task-7144' -ObjectiveId 'objective-2913' -Title 'Patch token extraction' -Scope 'Patch token extraction so only the identifier value is captured.' -PromptPath $promptPath -Metadata @{
                task_category = 'code_change'
                local_fallback_target_file = $targetRelativePath
                local_fallback_validation_command = "Get-Content -Path '.\\tmp_remote_mim\\core\\routers\\tod_ui.py' | Select-String -SimpleMatch 'def _extract_identifier_token(value: str) -> str:','return _extract_identifier_token(match.group(1))'"
            }

            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            $nonEmptyFiles = @($result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if (@($nonEmptyFiles).Count -gt 0) {
                [string]@($nonEmptyFiles)[0] | Should Be $targetRelativePath
            }
            [string]$result.diff_summary | Should Match 'identifier values'
            @($result.validation_results | Where-Object { [string]$_.name -eq 'focused_validation_exit_zero' -and [bool]$_.passed }).Count | Should Be 1
            ([string](Get-Content -Path $targetAbsolutePath -Raw)) | Should Match 'def _extract_identifier_token'
            ([string](Get-Content -Path $targetAbsolutePath -Raw)) | Should Match 'return _extract_identifier_token\(match.group\(1\)\)'

            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
        finally {
            $script:LocalEngineRepoRoot = $originalRoot
            if (Test-Path -Path $tempRoot) {
                Remove-Item -Path $tempRoot -Recurse -Force
            }
        }
    }

    It 'ignores an empty local_fallback_target_file and still infers the bounded docs target from prompt text' {
        $relativePath = ('docs/local-fallback-empty-target-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Empty Target Override`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Async Dispatch section." -f $relativePath)
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-EMPTY-TARGET' -ObjectiveId 'OBJ-LF' -Title 'Ignore empty target override' -Scope ("Update {0} with a short Async Dispatch section." -f $relativePath) -PromptPath $promptPath -Metadata @{
            task_category = 'docs_change'
            local_fallback_target_file = ''
        }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            (@($result.files_changed | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -contains $relativePath) | Should Be $true
            ([string](Get-Content -Path $absolutePath -Raw)) | Should Match 'Async Dispatch'
        }
        finally {
            if (Test-Path -Path $promptPath) {
                Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
            }
            if (Test-Path -Path $absolutePath) {
                Remove-Item -Path $absolutePath -Force
            }
        }
    }

    It 'publishes diff summary, commands, validation results, confidence, and rollback hints in shared artifacts' {
        function global:Get-TodExecutionSharedRoots {
            return ,(Join-Path $repoRoot ('tod/out/tests/local-fallback-artifacts-' + [guid]::NewGuid().ToString('N')))
        }

        function global:Write-TodExecutionSharedJson {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Payload
            )

            $dir = Split-Path -Parent $Path
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            ($Payload | ConvertTo-Json -Depth 20) | Set-Content -Path $Path -Encoding utf8
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $false; published = $false; reason = 'stubbed' }
        }

        $relativePath = ('docs/local-fallback-publish-{0}.md' -f [guid]::NewGuid().ToString('N'))
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\\')
        $absoluteDir = Split-Path -Parent $absolutePath
        New-Item -ItemType Directory -Path $absoluteDir -Force | Out-Null
        [System.IO.File]::WriteAllText($absolutePath, "# Publish Test`n", (New-Object System.Text.UTF8Encoding($false)))

        $promptPath = New-LocalFallbackPromptFile -Content ("Update {0} with a short Published Evidence section." -f $relativePath)
        $context = New-LocalFallbackContext -TaskId 'TSK-LF-PUBLISH' -ObjectiveId 'OBJ-LF' -Title 'Publish fallback evidence' -Scope ("Update {0} with a short Published Evidence section." -f $relativePath) -PromptPath $promptPath -Metadata @{ task_category = 'docs_change' }
        $result = Invoke-LocalExecutionEngine -Context $context
        $task = [pscustomobject]@{
            id = 'TSK-LF-PUBLISH'
            objective_id = 'OBJ-LF'
            title = 'Publish fallback evidence'
            scope = ("Update {0} with a short Published Evidence section." -f $relativePath)
            type = 'implementation'
            task_category = 'docs_change'
        }

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $result -ReviewDecision 'pass' -ExecutionId ([string]$result.execution_id) -PackagePath $promptPath -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.execution_result.execution_evidence.diff_summary | Should Match $relativePath
        [string]@($published.execution_result.execution_evidence.commands_run)[0] | Should Match 'Select-String'
        @($published.execution_result.execution_evidence.validation_results).Count | Should BeGreaterThan 0
        [string]$published.execution_result.execution_evidence.confidence | Should Be 'medium-high'
        [string]$published.execution_result.execution_evidence.rollback_hint | Should Match 'Copy-Item'

        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Write-TodExecutionSharedJson -ErrorAction SilentlyContinue
        Remove-Item function:\Publish-RemoteTodExecutionArtifacts -ErrorAction SilentlyContinue
        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        Remove-Item -Path $absolutePath -Force
    }

    It 'blocks publication when a required validation check failed even if review decision says pass' {
        function global:Get-TodExecutionSharedRoots {
            return ,(Join-Path $repoRoot ('tod/out/tests/local-fallback-required-validation-' + [guid]::NewGuid().ToString('N')))
        }

        function global:Write-TodExecutionSharedJson {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Payload
            )

            $dir = Split-Path -Parent $Path
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            ($Payload | ConvertTo-Json -Depth 20) | Set-Content -Path $Path -Encoding utf8
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $false; published = $false; reason = 'stubbed' }
        }

        $task = [pscustomobject]@{
            id = 'TSK-VALIDATION-TRUTH'
            objective_id = 'OBJ-VALIDATION-TRUTH'
            title = 'Reject false validation success'
            scope = 'Read-only authority classification proof with failed required validation.'
            type = 'read_only_assessment'
            task_category = 'read_only_assessment'
        }
        $resultPayload = [pscustomobject]@{
            status = 'completed'
            summary = 'Artifact was written but signal extraction did not pass.'
            files_changed = @('runtime_remote_training/read_only_audit_artifacts/TOD_VALIDATION_TRUTH.latest.json')
            tests_run = @('artifact write', 'signal extraction')
            test_results = @('pass', 'fail')
            commands_run = @('Invoke-LocalExecutionPatchEvidenceArtifact')
            structured_findings = @()
            validation_results = @(
                [pscustomobject]@{ name = 'artifact write'; passed = $true; required = $true },
                [pscustomobject]@{ name = 'signal extraction'; passed = $false; required = $true }
            )
            no_change_required = $false
        }

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $resultPayload -ReviewDecision 'pass' -ExecutionId 'truth-test' -PackagePath 'tod/out/prompts/TSK-VALIDATION-TRUTH.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.active_task.status | Should Be 'blocked'
        [string]$published.active_task.reason_code | Should Be 'required_validation_failed'
        [bool]$published.execution_result.execution_evidence.validation_passed | Should Be $false
        [string]$published.execution_result.execution_evidence.recovery_state | Should Be 'validation_repair_required'

        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Write-TodExecutionSharedJson -ErrorAction SilentlyContinue
        Remove-Item function:\Publish-RemoteTodExecutionArtifacts -ErrorAction SilentlyContinue
    }

    It 'does not fail material proof on optional diagnostic validation checks' {
        function global:Get-TodExecutionSharedRoots {
            return ,(Join-Path $repoRoot ('tod/out/tests/local-fallback-optional-validation-' + [guid]::NewGuid().ToString('N')))
        }

        function global:Write-TodExecutionSharedJson {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Payload
            )

            $dir = Split-Path -Parent $Path
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            ($Payload | ConvertTo-Json -Depth 20) | Set-Content -Path $Path -Encoding utf8
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)
            return [pscustomobject]@{ attempted = $false; published = $false; reason = 'stubbed' }
        }

        $task = [pscustomobject]@{
            id = 'TSK-OPTIONAL-VALIDATION-TRUTH'
            objective_id = 'OBJ-OPTIONAL-VALIDATION-TRUTH'
            title = 'Accept optional diagnostic failure'
            scope = 'Apply a bounded implementation with optional diagnostic validation checks.'
            type = 'implementation'
            task_category = 'code_change'
        }
        $resultPayload = [pscustomobject]@{
            status = 'completed'
            summary = 'Bounded implementation completed with optional diagnostics.'
            files_changed = @('scripts/engines/LocalExecutionEngine.ps1')
            tests_run = @('focused_validation_exit_zero', 'python_unittest_ok')
            test_results = @('pass', 'fail')
            commands_run = @('Invoke-LocalExecutionEngine')
            structured_findings = @()
            validation_results = @(
                [pscustomobject]@{ name = 'focused_validation_exit_zero'; passed = $true; required = $true },
                [pscustomobject]@{ name = 'python_unittest_ok'; passed = $false; required = $false }
            )
            no_change_required = $false
            diff_summary = 'updated scripts/engines/LocalExecutionEngine.ps1'
        }

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $resultPayload -ReviewDecision 'pass' -ExecutionId 'optional-validation-test' -PackagePath 'tod/out/prompts/TSK-OPTIONAL-VALIDATION-TRUTH.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.active_task.status | Should Be 'completed'
        [bool]$published.execution_result.execution_evidence.validation_passed | Should Be $true
        [string]$published.execution_result.execution_evidence.reason_code | Should Be ''

        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Write-TodExecutionSharedJson -ErrorAction SilentlyContinue
        Remove-Item function:\Publish-RemoteTodExecutionArtifacts -ErrorAction SilentlyContinue
    }
}
Describe 'TOD local ledger coverage handler' {
    BeforeAll {
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Get-ExecutionEngineInterfaceSpec'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineTaskContext'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'New-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Complete-EngineExecutionResult'
        Import-ScriptFunction -ScriptPath $executionEngineScript -Name 'Test-EngineContract'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-UtcNow'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-NormalizedObjectiveToken'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingText'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TaskRoutingFileHints'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-TaskCategory'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Convert-EngineResultToNormalizedEnvelope'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Normalize-EngineResultPayload'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-EngineResultPrecheck'
        Import-ScriptFunction -ScriptPath $todScript -Name 'New-ExecutionEngineBlockedResult'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionValidationChecks'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRequiredValidationFailures'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionCommandCapture'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionRollbackState'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Resolve-LocalExecutionTaskClass'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-LocalExecutionPatchRequired'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-LocalExecutionNoOpAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Test-TodWrapperOnlyChangedPath'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Get-TodMaterialImplementationProofAssessment'
        Import-ScriptFunction -ScriptPath $todScript -Name 'Publish-LocalExecutionArtifacts'
        Import-ScriptFunctionWithLiteralRoot -ScriptPath $todScript -Name 'Invoke-ExecutionEngine' -LiteralRoot (Join-Path $repoRoot 'scripts')

        . $localEngineScript
    }

    It 'Test-LocalExecutionLedgerCoverageTask matches a message-ledger coverage report objective' {
        $promptPath = New-LocalFallbackPromptFile -Content 'Measure Phase A observe-only message-ledger coverage across TOD/MIM communication paths.'
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-LEDGER-COVERAGE' `
            -ObjectiveId 'TOD-MESSAGE-LEDGER-COVERAGE-REPORT' `
            -Title 'Measure Phase A observe-only message-ledger coverage' `
            -Scope 'Perform a non-mutating ledger coverage measurement and write the Phase A coverage report.' `
            -PromptPath $promptPath
        Test-LocalExecutionLedgerCoverageTask -Context $context | Should Be $true
        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'Test-LocalExecutionLedgerCoverageTask does not match an unrelated code_change task' {
        $promptPath = New-LocalFallbackPromptFile -Content 'Update scripts/TOD.ps1 to fix the boundary check.'
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-UNRELATED' `
            -ObjectiveId 'OBJ-CODE-CHANGE' `
            -Title 'Fix boundary check in TOD.ps1' `
            -Scope 'Apply bounded patch to scripts/TOD.ps1.' `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'code_change' }
        Test-LocalExecutionLedgerCoverageTask -Context $context | Should Be $false
        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }

    It 'does not let coverage wording override an explicit artifact_write target' {
        $targetRel = 'runtime_remote_training/tod_result_artifacts/TOD_SELECTOR_PRECEDENCE_TEST.latest.json'
        $targetAbs = Join-Path $repoRoot ($targetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-Path -Path $targetAbs) {
            Remove-Item -Path $targetAbs -Force
        }
        $prompt = @"
Edit Mode: artifact_write
Target File: $targetRel
New Text:
{
  "artifact_type": "selector_precedence_test",
  "status": "passed"
}
Validation Command: powershell -NoProfile -Command "`$p='$targetRel'; if(-not (Test-Path `$p)){exit 1}; `$j=Get-Content `$p -Raw | ConvertFrom-Json; if(`$j.artifact_type -ne 'selector_precedence_test'){exit 2}"
Prevention Lesson: Evidence text that mentions message-ledger coverage must not override explicit bounded target authority.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $prompt
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-ARTIFACT-WRITE-PRECEDENCE' `
            -ObjectiveId 'TOD-CURRENT-MIM-OBJECTIVE-MONITOR-AND-COACH-V1' `
            -Title 'Write artifact despite coverage evidence wording' `
            -Scope $prompt `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'artifact_write' }

        try {
            Test-LocalExecutionLedgerCoverageTask -Context $context | Should Be $false
            $result = Invoke-LocalExecutionEngine -Context $context

            [string]$result.status | Should Be 'completed'
            [string]@($result.files_changed)[0] | Should Be $targetRel
            Test-Path -Path $targetAbs | Should Be $true
            $parsed = Get-Content $targetAbs -Raw | ConvertFrom-Json
            [string]$parsed.artifact_type | Should Be 'selector_precedence_test'
        }
        finally {
            if (Test-Path -Path $targetAbs) {
                Remove-Item -Path $targetAbs -Force
            }
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
        }
    }

    It 'uses canonical current caveats instead of historical apprenticeship prose for retirement eligibility' {
        $suffix = [guid]::NewGuid().ToString('N')
        $inputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_RETIREMENT_CAVEAT_INPUT_$suffix.json"
        $outputRel = "runtime_remote_training/read_only_audit_artifacts/TOD_RETIREMENT_CAVEAT_OUTPUT_$suffix.json"
        $inputAbs = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputAbs = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $registryPath = Join-Path $repoRoot 'docs/training/TOD_APPRENTICESHIP_REGISTRY.md'
        $registryBytes = [System.IO.File]::ReadAllBytes($registryPath)
        $registryText = [System.Text.Encoding]::UTF8.GetString($registryBytes)
        $fixture = @'

### APP-TOD-997: Historical prose does not block current truth

Progress: independent_demo_passed
Proficiency: independent
Independent Demonstration: passed
Freeze: frozen
Retirement: open
Current Caveats: none
Evidence: docs/training/TOD_APPRENTICESHIP_REGISTRY.md
History: an old wrapper-only attempt and an old source mutation failure remain preserved as evidence.

### APP-TOD-998: Current wrapper caveat remains blocking

Progress: independent_demo_passed
Proficiency: independent
Independent Demonstration: passed
Freeze: frozen
Retirement: open
Current Caveats: wrapper-only evidence remains unresolved
Evidence: docs/training/TOD_APPRENTICESHIP_REGISTRY.md

### APP-TOD-999: Current mutation caveat remains blocking

Progress: independent_demo_passed
Proficiency: independent
Independent Demonstration: passed
Freeze: frozen
Retirement: open
Current Caveats: source mutation boundary remains unresolved
Evidence: docs/training/TOD_APPRENTICESHIP_REGISTRY.md
'@
        [System.IO.File]::WriteAllText($registryPath, ($registryText + $fixture), (New-Object System.Text.UTF8Encoding($false)))
        [ordered]@{
            artifact_type = 'tod_borrowed_capability_training_plan'
            baseline_ratio = [ordered]@{ current = [ordered]@{ total_entries = 3; borrowed_count = 3 } }
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $inputAbs -Encoding utf8

        $promptText = @"
Read-only retirement eligibility review.
Input Artifact: $inputRel
Output Artifact: $outputRel
Required Artifact Type: tod_readonly_retirement_eligibility_proof
Review APP-TOD-997, APP-TOD-998, and APP-TOD-999 from current canonical registry fields. Do not modify source.
"@
        $promptPath = New-LocalFallbackPromptFile -Content $promptText
        $context = New-LocalFallbackContext `
            -TaskId 'TOD-RETIREMENT-CURRENT-CAVEAT-TEST' `
            -ObjectiveId 'TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1' `
            -Title 'Test current caveat authority' `
            -Scope $promptText `
            -PromptPath $promptPath `
            -Metadata @{ task_category = 'read_only_assessment'; task_mode = 'read_only_assessment'; bounded_edit_mode = $false; target_file = '' }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputAbs -Raw | ConvertFrom-Json
            $clean = @($artifact.retirement_decisions | Where-Object { [string]$_.entry_id -eq 'APP-TOD-997' })[0]
            $wrapper = @($artifact.retirement_decisions | Where-Object { [string]$_.entry_id -eq 'APP-TOD-998' })[0]
            $mutation = @($artifact.retirement_decisions | Where-Object { [string]$_.entry_id -eq 'APP-TOD-999' })[0]

            [string]$result.status | Should Be 'completed'
            [bool]$clean.eligible | Should Be $true
            [string]$clean.decision | Should Be 'eligible_to_retire'
            [bool]$wrapper.eligible | Should Be $false
            [string]@($wrapper.reasons) | Should Match 'wrapper-only or queue-only caveat is present'
            [bool]$mutation.eligible | Should Be $false
            [string]@($mutation.reasons) | Should Match 'read-only boundary is not cleanly proven'
        }
        finally {
            [System.IO.File]::WriteAllBytes($registryPath, $registryBytes)
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Invoke-LocalExecutionEngine executes ledger coverage and writes coverage report' {
        $promptPath = New-LocalFallbackPromptFile -Content 'Measure Phase A observe-only message-ledger coverage across TOD/MIM communication paths.'
        $context = New-LocalFallbackContext `
            -TaskId 'TSK-LEDGER-COVERAGE' `
            -ObjectiveId 'TOD-MESSAGE-LEDGER-COVERAGE-REPORT' `
            -Title 'Measure Phase A observe-only message-ledger coverage' `
            -Scope 'Perform a non-mutating ledger coverage measurement and write the Phase A coverage report.' `
            -PromptPath $promptPath

        $result = Invoke-LocalExecutionEngine -Context $context

        [string]$result.status | Should Be 'completed'
        @($result.files_changed).Count | Should BeGreaterThan 0
        [string]@($result.files_changed)[0] | Should Match 'TOD_MIM_LEDGER_PHASE_A_COVERAGE'
        [string]$result.summary | Should Match 'coverage'
        @($result.failures).Count | Should Be 0
        [bool]$result.needs_escalation | Should Be $false

        $coverageFile = Join-Path $repoRoot 'runtime\shared\TOD_MIM_LEDGER_PHASE_A_COVERAGE.latest.json'
        Test-Path $coverageFile | Should Be $true
        $parsed = Get-Content $coverageFile -Raw | ConvertFrom-Json
        $parsed.observe_only | Should Be $true
        $parsed.coverage_percent | Should BeGreaterThan 0

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force
    }
}
