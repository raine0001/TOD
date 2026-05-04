Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $repoRoot '.venv/Scripts/python.exe'
$validatorScript = Join-Path $repoRoot 'scripts/validate_tod_mim_runtime_packet.py'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-RuntimeBindingFixture {
    param([switch]$InvalidAck)

    $base = Join-Path $repoRoot ('tod/out/tests/runtime-binding-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    $contractPath = Join-Path $base 'TOD_MIM_COMMUNICATION_CONTRACT.v1.yaml'
    $receiptPath = Join-Path $base 'TOD_MIM_COMMUNICATION_CONTRACT_RECEIPT.v1.json'
    $ackPath = Join-Path $base 'ack.json'
    $resultPath = Join-Path $base 'result.json'

    $contractYaml = @'
contract_name: TOD_MIM_COMMUNICATION_CONTRACT
contract_version: v1
schema_version: 2026-04-02-communication-contract-v1
transport_layer:
  primary_transport:
    authority_surface: /home/testpilot/mim/runtime/shared
message_envelope:
  required_fields:
    - packet_type
    - schema_version
    - contract_version
    - generated_at
    - source_identity
    - transport
    - objective_id
    - task_id
    - request_id
    - correlation_id
    - message_kind
    - sequence
message_kinds:
  ack:
    packet_type: tod-mim-task-ack-v1
    status_values:
      - accepted
      - rejected
      - superseded_ignored
      - stale_ignored
  result:
    packet_type: tod-mim-task-result-v1
    status_values:
      - succeeded
      - failed
      - timed_out
      - aborted
      - blocked
'@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($contractPath, $contractYaml, $utf8NoBom)

    Write-JsonNoBom -PathValue $receiptPath -Payload ([pscustomobject]@{
            acceptance_status = 'accepted'
            checksum_match = $true
            no_reinterpretation_confirmed = $true
            contract_version = 'v1'
            schema_version = '2026-04-02-communication-contract-v1'
            checksum_sha256 = '204d078a8cc28ba6b9c2765326c4ad73169db804da46553f059b61931a91979a'
        })

    $ackPayload = [ordered]@{
        packet_type = 'tod-mim-task-ack-v1'
        schema_version = '2026-04-02-communication-contract-v1'
        contract_version = 'v1'
        generated_at = '2026-04-02T10:00:00Z'
        source_identity = [ordered]@{
            actor = 'TOD'
            host = 'DR_HOME_II'
            service = 'tod-mim-listener'
            instance_id = 'DR_HOME_II:100'
        }
        transport = [ordered]@{
            transport_id = 'mim_server_shared_artifact_boundary'
            surface = '/home/testpilot/mim/runtime/shared'
        }
        authoritative_surface = '/home/testpilot/mim/runtime/shared'
        checksum_sha256 = '204d078a8cc28ba6b9c2765326c4ad73169db804da46553f059b61931a91979a'
        objective_id = 'objective-97'
        task_id = 'objective-97-task-3422'
        request_id = 'objective-97-task-3422'
        correlation_id = 'corr-3422'
        message_kind = 'ack'
        sequence = 7
        acknowledged_trigger_sequence = 5
        status = 'accepted'
        ack_status = 'accepted'
        ack_reason_code = 'request_accepted_for_execution'
    }
    if ($InvalidAck) {
        $ackPayload.Remove('source_identity')
    }
    Write-JsonNoBom -PathValue $ackPath -Payload ([pscustomobject]$ackPayload)

    Write-JsonNoBom -PathValue $resultPath -Payload ([pscustomobject]@{
            packet_type = 'tod-mim-task-result-v1'
            schema_version = '2026-04-02-communication-contract-v1'
            contract_version = 'v1'
            generated_at = '2026-04-02T10:00:05Z'
            source_identity = [pscustomobject]@{
                actor = 'TOD'
                host = 'DR_HOME_II'
                service = 'tod-mim-listener'
                instance_id = 'DR_HOME_II:100'
            }
            transport = [pscustomobject]@{
                transport_id = 'mim_server_shared_artifact_boundary'
                surface = '/home/testpilot/mim/runtime/shared'
            }
            authoritative_surface = '/home/testpilot/mim/runtime/shared'
            checksum_sha256 = '204d078a8cc28ba6b9c2765326c4ad73169db804da46553f059b61931a91979a'
            objective_id = 'objective-97'
            task_id = 'objective-97-task-3422'
            request_id = 'objective-97-task-3422'
            correlation_id = 'corr-3422'
            message_kind = 'result'
            sequence = 8
            status = 'succeeded'
            result_status = 'succeeded'
            terminal = $true
            result_reason_code = 'execution_completed'
            execution_outcome = [pscustomobject]@{ ok = $true; blocked = $false }
        })

    return [pscustomobject]@{
        Base = $base
        ContractPath = $contractPath
        ReceiptPath = $receiptPath
        AckPath = $ackPath
        ResultPath = $resultPath
    }
}

function Get-JsonFile {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
}

function Remove-FixturePath {
    param([string]$PathValue)
    if (-not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -Path $PathValue)) {
        Remove-Item -Path $PathValue -Recurse -Force
    }
}

Describe 'TOD MIM runtime contract packet validator' {
    It 'accepts a contract-compliant ACK packet against an accepted receipt' {
        $fixture = New-RuntimeBindingFixture
        try {
            $raw = & $pythonPath $validatorScript --contract $fixture.ContractPath --receipt $fixture.ReceiptPath --packet $fixture.AckPath --kind ack
            $result = $raw | ConvertFrom-Json
            [bool]$result.passed | Should Be $true
            [bool]$result.binding_active | Should Be $true
        }
        finally {
            Remove-FixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'rejects an ACK packet missing required contract envelope fields' {
        $fixture = New-RuntimeBindingFixture -InvalidAck
        try {
            $raw = & $pythonPath $validatorScript --contract $fixture.ContractPath --receipt $fixture.ReceiptPath --packet $fixture.AckPath --kind ack
            $result = $raw | ConvertFrom-Json
            [bool]$result.passed | Should Be $false
            [string]($result.errors | ConvertTo-Json -Depth 10) | Should Match 'source_identity'
        }
        finally {
            Remove-FixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'accepts a contract-compliant RESULT packet against an accepted receipt' {
        $fixture = New-RuntimeBindingFixture
        try {
            $raw = & $pythonPath $validatorScript --contract $fixture.ContractPath --receipt $fixture.ReceiptPath --packet $fixture.ResultPath --kind result
            $result = $raw | ConvertFrom-Json
            [bool]$result.passed | Should Be $true
            [bool]$result.binding_active | Should Be $true
        }
        finally {
            Remove-FixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'rejects an ACK packet whose bridge runtime current_processing still points to an older task' {
        $fixture = New-RuntimeBindingFixture
        try {
            $ack = Get-JsonFile -PathValue $fixture.AckPath
            $ack | Add-Member -NotePropertyName bridge_runtime -NotePropertyValue ([pscustomobject]@{
                    current_processing = [pscustomobject]@{
                        task_id = 'objective-152-task-008'
                        correlation_id = 'obj152-task008'
                    }
                }) -Force
            Write-JsonNoBom -PathValue $fixture.AckPath -Payload $ack

            $raw = & $pythonPath $validatorScript --contract $fixture.ContractPath --receipt $fixture.ReceiptPath --packet $fixture.AckPath --kind ack
            $result = $raw | ConvertFrom-Json
            [bool]$result.passed | Should Be $false
            [string]($result.errors | ConvertTo-Json -Depth 10) | Should Match 'bridge_runtime.current_processing.task_id'
        }
        finally {
            Remove-FixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'rejects a RESULT packet whose embedded validator and integration snapshots are stale' {
        $fixture = New-RuntimeBindingFixture
        try {
            $resultPacket = Get-JsonFile -PathValue $fixture.ResultPath
            $resultPacket | Add-Member -NotePropertyName bridge_runtime -NotePropertyValue ([pscustomobject]@{
                    current_processing = [pscustomobject]@{
                        task_id = 'objective-152-task-008'
                        correlation_id = 'obj152-task008'
                    }
                }) -Force
            $resultPacket | Add-Member -NotePropertyName validator -NotePropertyValue ([pscustomobject]@{
                    attempted = $true
                    passed = $true
                    request_id = 'objective-152-task-008'
                    task_id = 'objective-152-task-008'
                    objective_id = 'objective-152'
                    correlation_id = 'obj152-task008'
                }) -Force
            $resultPacket | Add-Member -NotePropertyName integration -NotePropertyValue ([pscustomobject]@{
                    compatible = $true
                    tod_current_objective = '152'
                    mim_objective_active = 'objective-152'
                    request_id = 'objective-152-task-008'
                }) -Force
            Write-JsonNoBom -PathValue $fixture.ResultPath -Payload $resultPacket

            $raw = & $pythonPath $validatorScript --contract $fixture.ContractPath --receipt $fixture.ReceiptPath --packet $fixture.ResultPath --kind result
            $result = $raw | ConvertFrom-Json
            [bool]$result.passed | Should Be $false
            [string]($result.errors | ConvertTo-Json -Depth 10) | Should Match 'validator.request_id'
            [string]($result.errors | ConvertTo-Json -Depth 10) | Should Match 'integration.tod_current_objective'
            [string]($result.errors | ConvertTo-Json -Depth 10) | Should Match 'bridge_runtime.current_processing.task_id'
        }
        finally {
            Remove-FixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }
}