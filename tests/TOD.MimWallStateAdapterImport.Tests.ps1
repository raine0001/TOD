Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$importScript = Join-Path $repoRoot 'scripts/Import-TODMimWallStateSnapshot.ps1'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-MimWallImportFixture {
    $base = Join-Path $repoRoot ('tod/out/tests/mim-wall-import-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        PayloadPath = Join-Path $base 'payload.json'
        SnapshotPath = Join-Path $base 'MIM_WALL_STATE_ADAPTER.latest.json'
        EnvelopePath = Join-Path $base 'MIM_WALL_STATE_ADAPTER_ENVELOPE.latest.json'
        EventProjectionPath = Join-Path $base 'mim_wall_event_projection.latest.json'
        SummaryPath = Join-Path $base 'mim_wall_state.latest.json'
        ReceiptPath = Join-Path $base 'mim_wall_state_import.latest.json'
    }
}

Describe 'TOD mim_wall state adapter import' {
    It 'imports a structured mim_wall adapter snapshot and projects canonical events' {
        (Test-Path -Path $importScript) | Should Be $true

        $fixture = New-MimWallImportFixture
        try {
            $payload = [pscustomobject]@{
                namespace = 'mim_wall'
                source = 'mim-assist-mobile'
                createdAt = 1770000000000
                snapshot = [pscustomobject]@{
                    project_id = 'mim_wall'
                    adapter_id = 'mim_wall_state_adapter_v1'
                    generated_at = '2026-04-14T01:02:03.0000000Z'
                    device = [pscustomobject]@{
                        device_id = 'android-test-device'
                        platform = 'android'
                        app_package = 'com.dave.callguardian'
                    }
                    control_state = [pscustomobject]@{
                        mim_enabled = $true
                        mode = 'read_only_phase'
                    }
                    queue = @(
                        [pscustomobject]@{
                            item_id = 'queue-1'
                            thread_key = '+15551234567'
                            timestamp_ms = 1770000001000
                            status = 'pending'
                            summary = 'Call back when available'
                            source = 'missed_call'
                        }
                    )
                    timeline = @(
                        [pscustomobject]@{
                            timestamp_ms = 1770000002000
                            category = 'screening'
                            detail = 'busy-call interception active'
                        }
                    )
                    feedback = @(
                        [pscustomobject]@{
                            timestamp_ms = 1770000003000
                            label = 'correct'
                            note = 'Captured the right busy-call branch.'
                        }
                    )
                    export_meta = [pscustomobject]@{
                        source_of_truth = 'mim_wall_call_session_store'
                    }
                }
            }
            Write-JsonNoBom -PathValue $fixture.PayloadPath -Payload $payload

            $result = (& $importScript -PayloadPath $fixture.PayloadPath -SnapshotPath $fixture.SnapshotPath -EnvelopePath $fixture.EnvelopePath -EventProjectionPath $fixture.EventProjectionPath -SummaryPath $fixture.SummaryPath -ReceiptPath $fixture.ReceiptPath | Out-String | ConvertFrom-Json)

            [bool]$result.ok | Should Be $true
            [string]$result.project_id | Should Be 'mim_wall'
            [int]$result.projected_event_count | Should Be 3

            $snapshot = Get-Content -Path $fixture.SnapshotPath -Raw | ConvertFrom-Json
            [string]$snapshot.adapter_id | Should Be 'mim_wall_state_adapter_v1'

            $projection = Get-Content -Path $fixture.EventProjectionPath -Raw | ConvertFrom-Json
            [int]$projection.event_count | Should Be 3
            (@($projection.events.event_type) -contains 'queue.item.discovered') | Should Be $true
            (@($projection.events.event_type) -contains 'communication.call.busy_intercepted') | Should Be $true
            (@($projection.events.event_type) -contains 'feedback.user.labeled') | Should Be $true

            $summary = Get-Content -Path $fixture.SummaryPath -Raw | ConvertFrom-Json
            [bool]$summary.mim_enabled | Should Be $true
            [int]$summary.queue_count | Should Be 1
            [int]$summary.timeline_count | Should Be 1
            [int]$summary.feedback_count | Should Be 1
        }
        finally {
            if ($fixture -and (Test-Path -Path $fixture.Base)) {
                Remove-Item -Path $fixture.Base -Recurse -Force
            }
        }
    }
}