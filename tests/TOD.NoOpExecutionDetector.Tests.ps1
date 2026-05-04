Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$global:repoRoot = $repoRoot

function Import-TodFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($todScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $todScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $todScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function New-NoOpTestTask {
    param(
        [string]$Id = 'objective-2913-task-7144',
        [string]$Title = 'Patch token extraction',
        [string]$Scope = 'Patch token extraction so only the identifier value is captured.',
        [string]$Type = 'implementation',
        [string]$TaskCategory = 'code_change',
        [string]$TaskClass = ''
    )

    $task = [pscustomobject]@{
        id = $Id
        objective_id = 'objective-2913'
        title = $Title
        scope = $Scope
        type = $Type
        task_category = $TaskCategory
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskClass)) {
        $task | Add-Member -NotePropertyName task_class -NotePropertyValue $TaskClass -Force
    }

    return $task
}

function New-NoOpResultPayload {
    param(
        [string[]]$FilesChanged = @(),
        [object[]]$StructuredFindings = @(),
        [string]$Summary = 'Wrapper accepted package and prepared normalized result.',
        [string[]]$TestsRun = @('engine contract self-check'),
        [string[]]$TestResults = @('pass')
    )

    return [pscustomobject]@{
        summary = $Summary
        files_changed = @($FilesChanged)
        tests_run = @($TestsRun)
        test_results = @($TestResults)
        failures = @()
        recommendations = @()
        structured_findings = @($StructuredFindings)
        needs_escalation = $false
    }
}

Describe 'TOD no-op execution detector' {
    BeforeAll {
        Import-TodFunction -Name 'Resolve-TaskCategory'
        Import-TodFunction -Name 'Get-LocalExecutionValidationChecks'
        Import-TodFunction -Name 'Get-LocalExecutionCommandCapture'
        Import-TodFunction -Name 'Get-LocalExecutionRollbackState'
        Import-TodFunction -Name 'Get-NormalizedObjectiveToken'
        Import-TodFunction -Name 'Resolve-LocalExecutionTaskClass'
        Import-TodFunction -Name 'Test-LocalExecutionPatchRequired'
        Import-TodFunction -Name 'Get-LocalExecutionNoOpAssessment'
        Import-TodFunction -Name 'Publish-LocalExecutionArtifacts'

        function global:Get-UtcNow {
            return (Get-Date).ToUniversalTime().ToString('o')
        }

        function global:Publish-RemoteTodExecutionArtifacts {
            param([string[]]$LocalArtifactPaths)

            return [pscustomobject]@{ attempted = $true; published = $false; reason = 'stubbed_for_pester' }
        }
    }

    BeforeEach {
        $script:artifactRoot = Join-Path $repoRoot ('tod/out/tests/noop-artifacts-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:artifactRoot -Force | Out-Null
        $global:CapturedArtifacts = @{}

        function global:Get-TodExecutionSharedRoots {
            return ,$script:artifactRoot
        }

        function global:Write-TodExecutionSharedJson {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Payload
            )

            $global:CapturedArtifacts[[System.IO.Path]::GetFileName($Path)] = $Payload
        }
    }

    AfterEach {
        if (Test-Path -Path $script:artifactRoot) {
            Remove-Item -Path $script:artifactRoot -Recurse -Force
        }
        Remove-Item function:\Get-TodExecutionSharedRoots -ErrorAction SilentlyContinue
        Remove-Item function:\Write-TodExecutionSharedJson -ErrorAction SilentlyContinue
    }

    It 'rejects a patch task when files_changed is empty' {
        $task = New-NoOpTestTask
        $result = New-NoOpResultPayload

        $assessment = Get-LocalExecutionNoOpAssessment -Task $task -ResultPayload $result

        [bool]$assessment.detected | Should Be $true
        [string]$assessment.reason_code | Should Be 'no_meaningful_execution_evidence'
        [bool]$assessment.allows_authoritative_completion | Should Be $false
    }

    It 'allows a diagnostic task to complete without changed files' {
        $task = New-NoOpTestTask -Title 'Capture diagnostic state' -Scope 'Produce a diagnostic snapshot only.' -Type 'diagnostic_only' -TaskCategory 'diagnostic_only' -TaskClass 'diagnostic_only'
        $result = New-NoOpResultPayload

        $assessment = Get-LocalExecutionNoOpAssessment -Task $task -ResultPayload $result

        [bool]$assessment.detected | Should Be $false
        [bool]$assessment.exempt | Should Be $true
        [bool]$assessment.allows_authoritative_completion | Should Be $true
    }

    It 'treats patch_writer not_needed as a rejection for patch tasks' {
        $task = New-NoOpTestTask
        $result = New-NoOpResultPayload

        $assessment = Get-LocalExecutionNoOpAssessment -Task $task -ResultPayload $result

        [string]$assessment.patch_writer_status | Should Be 'not_needed'
        [bool]$assessment.patch_writer_rejected | Should Be $true
        [bool]$assessment.detected | Should Be $true
    }

    It 'accepts a patch task when an accepted result artifact proves execution' {
        $task = New-NoOpTestTask
        $result = New-NoOpResultPayload -Summary 'Updated the bounded routing report and published the accepted execution artifact.' -StructuredFindings @(
            [pscustomobject]@{
                type = 'result_contract'
                action_taken = 'Patched the bounded routing report and published the accepted artifact.'
                changed_files = @()
                accepted = $true
            }
        )

        $assessment = Get-LocalExecutionNoOpAssessment -Task $task -ResultPayload $result

        [string]$assessment.patch_writer_status | Should Be 'evidence_only'
        [bool]$assessment.patch_writer_rejected | Should Be $false
        [bool]$assessment.detected | Should Be $false
        ((@($assessment.meaningful_evidence) -contains 'result_artifact')) | Should Be $true
    }

    It 'prevents authoritative completion when a pass result is actually a no-op' {
        $task = New-NoOpTestTask
        $result = New-NoOpResultPayload

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $result -ReviewDecision 'pass' -ExecutionId 'EXEC-001' -PackagePath 'E:\TOD\tod\out\prompts\objective-2913-task-7144.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.active_objective.status | Should Be 'active'
        [string]$published.active_task.status | Should Be 'blocked'
        [string]$published.execution_result.status | Should Be 'blocked'
        [string]$published.execution_result.execution_state | Should Be 'no_op_rejected'
        [string]$published.execution_result.reason_code | Should Be 'no_meaningful_execution_evidence'
    }

    It 'publishes completed artifacts when accepted result evidence supports a patch task' {
        $task = New-NoOpTestTask
        $result = New-NoOpResultPayload -Summary 'Updated the bounded routing report and published the accepted execution artifact.' -StructuredFindings @(
            [pscustomobject]@{
                type = 'result_contract'
                action_taken = 'Patched the bounded routing report and published the accepted artifact.'
                changed_files = @()
                accepted = $true
            },
            [pscustomobject]@{
                type = 'command'
                capture = [pscustomobject]@{
                    command = '.\\scripts\\Validate-Routing.ps1'
                    stderr = 'OK'
                    exit_code = 0
                }
            }
        )

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $result -ReviewDecision 'pass' -ExecutionId 'EXEC-003' -PackagePath 'E:\TOD\tod\out\prompts\objective-2913-task-7144.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.active_task.status | Should Be 'completed'
        [string]$published.execution_result.execution_state | Should Be 'completed'
        [string]$published.active_task.execution_contract.command_runner.status | Should Be 'completed'
        [string]$published.active_task.execution_contract.patch_writer.status | Should Be 'evidence_only'
    }

    It 'signals replay_or_replan_required for rejected no-op executions' {
        $task = New-NoOpTestTask
        $result = New-NoOpResultPayload

        $published = Publish-LocalExecutionArtifacts -Task $task -Objective $null -ResultPayload $result -ReviewDecision 'pass' -ExecutionId 'EXEC-002' -PackagePath 'E:\TOD\tod\out\prompts\objective-2913-task-7144.md' -ExecutionReadiness ([pscustomobject]@{ status = 'valid' })

        [string]$published.no_op_assessment.recovery_state | Should Be 'replay_or_replan_required'
        [string]$published.active_task.recovery_state | Should Be 'replay_or_replan_required'
        [string]$published.execution_result.recovery_state | Should Be 'replay_or_replan_required'
        [string]$published.active_task.next_step | Should Be 'replay_or_replan_required'
    }
}