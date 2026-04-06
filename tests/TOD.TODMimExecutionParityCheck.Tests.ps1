Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODMimExecutionParityCheck.ps1'

function New-ParityFixture {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ('tod/out/tests/tod-mim-execution-parity-' + $id)
    $docs = Join-Path $base 'docs'
    $listener = Join-Path $base 'listener'
    $results = Join-Path $base 'results'
    New-Item -ItemType Directory -Path $docs -Force | Out-Null
    New-Item -ItemType Directory -Path $listener -Force | Out-Null
    New-Item -ItemType Directory -Path $results -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        Docs = $docs
        Listener = $listener
        Results = $results
        Policy = (Join-Path $docs 'policy.md')
        Audit = (Join-Path $docs 'audit.md')
        Feedback = (Join-Path $docs 'feedback.md')
        Gate = (Join-Path $results 'gate.json')
        Output = (Join-Path $results 'parity.json')
    }
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Initialize-GoodParityFixture {
    param([Parameter(Mandatory = $true)]$Fixture)

    @'
## Listener-Stage Execution Contract
- MIM_TOD_TASK_REQUEST.latest.json
- MIM_TO_TOD_TRIGGER.latest.json
- MIM_TOD_GO_ORDER.latest.json
- MIM_TOD_REVIEW_DECISION.latest.json
- TOD_TO_MIM_TRIGGER_ACK.latest.json
- TOD_MIM_TASK_ACK.latest.json
- TOD_MIM_TASK_RESULT.latest.json
- ACK does not prove terminal completion.
- TOD must emit one terminal result per bounded attempt.
- Deduplicate duplicate semantic requests.
'@ | Set-Content -Path $Fixture.Policy

    @'
listener-stage execution contract
Canonical Communication Method
TOD_TO_MIM_TRIGGER_ACK.latest.json
TOD_MIM_TASK_ACK.latest.json
TOD_MIM_TASK_RESULT.latest.json
'@ | Set-Content -Path $Fixture.Audit

    @'
ACK must echo the same live request identity
Result must reference that same request identity
If MIM wants a real retry after a failed terminal result, it must issue a new request identity.
'@ | Set-Content -Path $Fixture.Feedback

    Write-JsonNoBom -PathValue $Fixture.Gate -Payload ([pscustomobject]@{
        scope = [pscustomobject]@{
            contract_lane = 'listener_execution_only'
        }
        coverage = [pscustomobject]@{
            included = @(
                'request accepted once',
                'trigger ACK emitted once',
                'task ACK emitted once',
                'terminal RESULT emitted once',
                'duplicate semantic request deduplication',
                'stale backfill rejection',
                'superseded request handling',
                'wrong-target rejection'
            )
        }
        summary = [pscustomobject]@{
            gate_passed = $true
        }
    })

    Write-JsonNoBom -PathValue (Join-Path $Fixture.Listener 'MIM_TOD_TASK_REQUEST.latest.json') -Payload ([pscustomobject]@{
        request_id = 'objective-400-task-001'
        task_id = 'objective-400-task-001'
        objective_id = 'objective-400'
        target = 'TOD'
        tod_action = 'get-state-bus'
    })

    Write-JsonNoBom -PathValue (Join-Path $Fixture.Listener 'TOD_TO_MIM_TRIGGER_ACK.latest.json') -Payload ([pscustomobject]@{
        source = 'shared-trigger-ack-v1'
        status = 'acknowledged'
        acknowledges = 'objective-400-task-001'
        ack_sequence = 10
        acknowledged_trigger_sequence = 9
    })

    Write-JsonNoBom -PathValue (Join-Path $Fixture.Listener 'TOD_MIM_TASK_ACK.latest.json') -Payload ([pscustomobject]@{
        source = 'tod-mim-task-ack-v1'
        request_id = 'objective-400-task-001'
        task_id = 'objective-400-task-001'
        status = 'accepted'
        ack_sequence = 10
        acknowledged_trigger_sequence = 9
    })

    Write-JsonNoBom -PathValue (Join-Path $Fixture.Listener 'TOD_MIM_TASK_RESULT.latest.json') -Payload ([pscustomobject]@{
        source = 'tod-mim-task-result-v1'
        request_id = 'objective-400-task-001'
        task_id = 'objective-400-task-001'
        status = 'completed'
        action = 'get-state-bus'
        ack_sequence = 11
        acknowledged_trigger_sequence = 9
    })
}

Describe 'TOD MIM execution parity check' {
    It 'reports compatible expectations for a good fixture' {
        $fixture = New-ParityFixture
        Initialize-GoodParityFixture -Fixture $fixture

        $payload = (& $scriptPath -PolicyDocPath $fixture.Policy -AuditDocPath $fixture.Audit -FeedbackContractPath $fixture.Feedback -ExecutionGateArtifactPath $fixture.Gate -ListenerStageDir $fixture.Listener -OutputPath $fixture.Output -SkipExecutionGateRefresh -EmitJson) | ConvertFrom-Json

        [bool]$payload.compatible | Should Be $true
        [int]$payload.mismatch_count | Should Be 0
        (Test-Path -Path $fixture.Output) | Should Be $true
    }

    It 'accepts descriptive request intent when explicit action fields are absent' {
        $fixture = New-ParityFixture
        Initialize-GoodParityFixture -Fixture $fixture

        Write-JsonNoBom -PathValue (Join-Path $fixture.Listener 'MIM_TOD_TASK_REQUEST.latest.json') -Payload ([pscustomobject]@{
            task_id = 'objective-401-task-001'
            objective_id = 'objective-401'
            target = 'TOD'
            title = 'Restore bounded lane status snapshot'
            scope = 'Refresh the listener-stage completion snapshot after replay cleanup.'
            acceptance_criteria = @(
                'Listener stage reflects the authoritative completion snapshot.'
            )
        })

        $payload = (& $scriptPath -PolicyDocPath $fixture.Policy -AuditDocPath $fixture.Audit -FeedbackContractPath $fixture.Feedback -ExecutionGateArtifactPath $fixture.Gate -ListenerStageDir $fixture.Listener -OutputPath $fixture.Output -SkipExecutionGateRefresh -EmitJson) | ConvertFrom-Json

        [bool]$payload.compatible | Should Be $true
        @($payload.checks | Where-Object { [string]$_.code -eq 'live_request_surface_shape' -and -not [bool]$_.passed }).Count | Should Be 0
    }

    It 'reports drift when gate coverage or feedback semantics fall out of sync' {
        $fixture = New-ParityFixture
        Initialize-GoodParityFixture -Fixture $fixture

        @'
ACK must echo the same live request identity
Result is optional for drifted fixture
'@ | Set-Content -Path $fixture.Feedback

        Write-JsonNoBom -PathValue $fixture.Gate -Payload ([pscustomobject]@{
            scope = [pscustomobject]@{
                contract_lane = 'listener_execution_only'
            }
            coverage = [pscustomobject]@{
                included = @(
                    'request accepted once',
                    'trigger ACK emitted once',
                    'task ACK emitted once'
                )
            }
            summary = [pscustomobject]@{
                gate_passed = $true
            }
        })

        $payload = (& $scriptPath -PolicyDocPath $fixture.Policy -AuditDocPath $fixture.Audit -FeedbackContractPath $fixture.Feedback -ExecutionGateArtifactPath $fixture.Gate -ListenerStageDir $fixture.Listener -OutputPath $fixture.Output -SkipExecutionGateRefresh -EmitJson) | ConvertFrom-Json

        [bool]$payload.compatible | Should Be $false
        [int]$payload.mismatch_count | Should BeGreaterThan 0
        @($payload.checks | Where-Object { [string]$_.code -eq 'feedback_contract_semantics' -and -not [bool]$_.passed }).Count | Should BeGreaterThan 0
        @($payload.checks | Where-Object { [string]$_.code -eq 'execution_gate_coverage' -and -not [bool]$_.passed }).Count | Should BeGreaterThan 0
    }
}