param(
    [ValidateSet('initialize', 'append_message', 'append_event', 'append_claim', 'append_result', 'append_heartbeat', 'append_delivery_attempt', 'append_dead_letter')]
    [string]$Operation,
    [string]$PayloadFile,
    [string]$EnvFile = '.env',
    [string]$RemoteAppRoot = '/home/testpilot/mim',
    [string]$RemoteTempRoot = '/home/testpilot/mim/runtime/shared/.ledger_observe',
    [string]$StatusPath = 'runtime/shared/TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json',
    [string]$PostgresMigrationPath = 'db/migrations/20260506_tod_mim_message_ledger_phase_a_observe_only.postgres.sql',
    [string]$Mode = 'observe_only',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ('^' + [regex]::Escape($Name) + '=')
    } | Select-Object -First 1

    if (-not $line) {
        return ''
    }

    return ($line -replace ('^' + [regex]::Escape($Name) + '='), '').Trim()
}

function Resolve-PreferredSshHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    try {
        $v4 = @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop | Select-Object -ExpandProperty IPAddress)
        if ($v4.Length -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$v4[0])) {
            return [string]$v4[0]
        }
    }
    catch {
    }

    return $HostName
}

function Format-RemoteSingleQuotedValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return "'" + ($Value -replace "'", "'\''") + "'"
}

function New-ParentDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Write-StatusFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [hashtable]$Status
    )

    New-ParentDirectory -Path $Path
    ($Status | ConvertTo-Json -Depth 8) + "`n" | Set-Content -Path $Path -Encoding UTF8
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $EnvFile))
if (-not (Test-Path -Path $envFullPath -PathType Leaf)) {
    throw "Missing env file: $envFullPath"
}

$payloadFullPath = ''
if ($Operation -ne 'initialize') {
    if ([string]::IsNullOrWhiteSpace($PayloadFile)) {
        throw 'PayloadFile is required for append operations.'
    }
    $payloadFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PayloadFile))
    if (-not (Test-Path -Path $payloadFullPath -PathType Leaf)) {
        throw "Missing payload file: $payloadFullPath"
    }
}

$migrationFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PostgresMigrationPath))
if (-not (Test-Path -Path $migrationFullPath -PathType Leaf)) {
    throw "Missing PostgreSQL migration file: $migrationFullPath"
}

$statusFullPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $StatusPath))
$hostName = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_HOST'
$userName = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_USER'
$portText = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_PORT'
$password = Get-DotEnvValue -Path $envFullPath -Name 'MIM_SSH_PASSWORD'

if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = 'mim' }
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'testpilot' }
if ([string]::IsNullOrWhiteSpace($portText)) { $portText = '22' }
if ([string]::IsNullOrWhiteSpace($password) -or $password -eq 'CHANGE_ME') {
    throw "Set MIM_SSH_PASSWORD in $envFullPath before using the remote ledger writer."
}

[int]$port = $portText
$connectHost = Resolve-PreferredSshHost -HostName $hostName
$timestamp = (Get-Date).ToUniversalTime().ToString('o')
$remoteRunId = [guid]::NewGuid().ToString('N')
$remoteSqlPath = "$RemoteTempRoot/ledger-schema-$remoteRunId.sql"
$remotePayloadPath = "$RemoteTempRoot/ledger-payload-$remoteRunId.json"

$status = [ordered]@{
    generated_at = $timestamp
    mode = $Mode
    enabled = ($Mode -eq 'observe_only')
    operation = $Operation
    dry_run = [bool]$DryRun.IsPresent
    ssh = [ordered]@{
        host = $hostName
        resolved_host = $connectHost
        user = $userName
        port = $port
    }
    remote = [ordered]@{
        app_root = $RemoteAppRoot
        temp_root = $RemoteTempRoot
        schema_path = $remoteSqlPath
        payload_path = $(if ($Operation -eq 'initialize') { $null } else { $remotePayloadPath })
    }
    local = [ordered]@{
        env_file = $envFullPath
        migration_path = $migrationFullPath
        payload_file = $(if ($Operation -eq 'initialize') { $null } else { $payloadFullPath })
    }
}

if ($DryRun.IsPresent) {
    $status.ok = $true
    $status.note = 'dry_run_only'
    Write-StatusFile -Path $statusFullPath -Status $status
    $status | ConvertTo-Json -Depth 8
    return
}

if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    throw 'Posh-SSH is not installed. Run: Install-Module -Name Posh-SSH -Scope CurrentUser'
}

Import-Module Posh-SSH -ErrorAction Stop
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)

$ssh = $null
$sftp = $null
try {
    $ssh = New-SSHSession -ComputerName $connectHost -Port $port -Credential $credential -AcceptKey -ConnectionTimeout 30000
    $sftp = New-SFTPSession -ComputerName $connectHost -Port $port -Credential $credential -AcceptKey -ConnectionTimeout 30000

    $mkdirCommand = 'mkdir -p ' + (Format-RemoteSingleQuotedValue -Value $RemoteTempRoot)
    $mkdirResult = Invoke-SSHCommand -SessionId ([int]$ssh.SessionId) -Command $mkdirCommand -TimeOut 30
    if ($mkdirResult.ExitStatus -ne 0) {
        throw "Remote directory create failed: $RemoteTempRoot"
    }

    if ($Operation -eq 'initialize') {
        Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $migrationFullPath -Destination $remoteSqlPath -Force -ErrorAction Stop | Out-Null
        $remoteCommand = @"
set -euo pipefail
DB_URL=$(grep '^DATABASE_URL=' '$RemoteAppRoot/.env' | cut -d= -f2- | sed 's#postgresql+asyncpg://#postgresql://#')
psql "\$DB_URL" -v ON_ERROR_STOP=1 -f '$remoteSqlPath'
rm -f '$remoteSqlPath'
"@
        $remoteCommand = $remoteCommand -replace "", '$'
    }
    else {
        Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $payloadFullPath -Destination $remotePayloadPath -Force -ErrorAction Stop | Out-Null
        $remoteCommand = @"
set -euo pipefail
export LEDGER_APP_ROOT='$RemoteAppRoot'
export LEDGER_OPERATION='$Operation'
export LEDGER_PAYLOAD_PATH='$remotePayloadPath'
'$RemoteAppRoot/.venv/bin/python' - <<'PY'
import asyncio
import json
import os
from pathlib import Path

import asyncpg

APP_ROOT = Path(os.environ['LEDGER_APP_ROOT'])
PAYLOAD_PATH = Path(os.environ['LEDGER_PAYLOAD_PATH'])
OPERATION = os.environ['LEDGER_OPERATION']


def env_value(path: Path, name: str) -> str:
    for raw_line in path.read_text(encoding='utf-8').splitlines():
        if raw_line.startswith(name + '='):
            return raw_line.split('=', 1)[1].strip()
    return ''


def json_text(value):
    return json.dumps(value, ensure_ascii=True, separators=(',', ':'), sort_keys=True)


def text_value(payload, name, fallback=''):
    value = payload.get(name)
    if value is None:
        return fallback
    return str(value)


async def ensure_thread(conn, payload):
    thread_id = text_value(payload, 'thread_id')
    if not thread_id:
        return
    await conn.execute(
        '''
        INSERT INTO agent_ledger_conversation_threads (
            thread_id, thread_type, root_message_id, created_by_agent, created_at, closed_at, thread_state
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (thread_id) DO NOTHING
        ''',
        thread_id,
        text_value(payload, 'thread_type'),
        text_value(payload, 'root_message_id') or None,
        text_value(payload, 'created_by_agent'),
        text_value(payload, 'created_at'),
        text_value(payload, 'closed_at') or None,
        text_value(payload, 'thread_state'),
    )


async def append_message(conn, payload):
    await ensure_thread(conn, payload)
    message_id = text_value(payload, 'message_id')
    if not message_id:
        raise ValueError('message_id is required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_messages (
            message_id, thread_id, from_agent, to_agent, task_id, correlation_id, message_type,
            payload_json, status, created_at, acknowledged_at, completed_at, expires_at,
            superseded_by_message_id, source_surface, observed_at
        ) VALUES (
            $1, $2, $3, $4, $5, $6, $7,
            $8::jsonb, $9, $10::timestamptz, $11::timestamptz, $12::timestamptz, $13::timestamptz,
            $14, $15, $16::timestamptz
        )
        ON CONFLICT (message_id) DO NOTHING
        ''',
        message_id,
        text_value(payload, 'thread_id') or None,
        text_value(payload, 'from_agent'),
        text_value(payload, 'to_agent'),
        text_value(payload, 'task_id') or None,
        text_value(payload, 'correlation_id') or None,
        text_value(payload, 'message_type'),
        json_text(payload.get('payload', payload)),
        text_value(payload, 'status'),
        text_value(payload, 'created_at'),
        text_value(payload, 'acknowledged_at') or None,
        text_value(payload, 'completed_at') or None,
        text_value(payload, 'expires_at') or None,
        text_value(payload, 'superseded_by_message_id') or None,
        text_value(payload, 'source_surface'),
        text_value(payload, 'observed_at'),
    )
    return {'table': 'agent_ledger_messages', 'id': message_id, 'result': result}


async def append_event(conn, payload):
    event_id = text_value(payload, 'event_id')
    message_id = text_value(payload, 'message_id')
    if not event_id or not message_id:
        raise ValueError('event_id and message_id are required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_message_events (
            event_id, message_id, event_type, event_status, event_payload_json, created_at, actor_agent, source_surface
        ) VALUES ($1, $2, $3, $4, $5::jsonb, $6::timestamptz, $7, $8)
        ON CONFLICT (event_id) DO NOTHING
        ''',
        event_id,
        message_id,
        text_value(payload, 'event_type'),
        text_value(payload, 'event_status'),
        json_text(payload.get('payload', payload)),
        text_value(payload, 'created_at'),
        text_value(payload, 'actor_agent'),
        text_value(payload, 'source_surface'),
    )
    return {'table': 'agent_ledger_message_events', 'id': event_id, 'result': result}


async def append_claim(conn, payload):
    claim_id = text_value(payload, 'claim_id')
    if not claim_id:
        raise ValueError('claim_id is required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_task_claims (
            claim_id, task_id, message_id, claimed_by_agent, claim_status, created_at, released_at, payload_json
        ) VALUES ($1, $2, $3, $4, $5, $6::timestamptz, $7::timestamptz, $8::jsonb)
        ON CONFLICT (claim_id) DO NOTHING
        ''',
        claim_id,
        text_value(payload, 'task_id'),
        text_value(payload, 'message_id') or None,
        text_value(payload, 'claimed_by_agent'),
        text_value(payload, 'claim_status'),
        text_value(payload, 'created_at'),
        text_value(payload, 'released_at') or None,
        json_text(payload.get('payload', payload)),
    )
    return {'table': 'agent_ledger_task_claims', 'id': claim_id, 'result': result}


async def append_result(conn, payload):
    result_id = text_value(payload, 'result_id')
    if not result_id:
        raise ValueError('result_id is required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_task_results (
            result_id, task_id, message_id, correlation_id, result_status, result_payload_json, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7::timestamptz)
        ON CONFLICT (result_id) DO NOTHING
        ''',
        result_id,
        text_value(payload, 'task_id'),
        text_value(payload, 'message_id') or None,
        text_value(payload, 'correlation_id') or None,
        text_value(payload, 'result_status'),
        json_text(payload.get('payload', payload)),
        text_value(payload, 'created_at'),
    )
    return {'table': 'agent_ledger_task_results', 'id': result_id, 'result': result}


async def append_heartbeat(conn, payload):
    heartbeat_id = text_value(payload, 'heartbeat_id')
    if not heartbeat_id:
        raise ValueError('heartbeat_id is required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_heartbeats (
            heartbeat_id, agent_id, status, heartbeat_payload_json, created_at, expires_at, source_surface
        ) VALUES ($1, $2, $3, $4::jsonb, $5::timestamptz, $6::timestamptz, $7)
        ON CONFLICT (heartbeat_id) DO NOTHING
        ''',
        heartbeat_id,
        text_value(payload, 'agent_id'),
        text_value(payload, 'status'),
        json_text(payload.get('payload', payload)),
        text_value(payload, 'created_at'),
        text_value(payload, 'expires_at') or None,
        text_value(payload, 'source_surface'),
    )
    return {'table': 'agent_ledger_heartbeats', 'id': heartbeat_id, 'result': result}


async def append_delivery_attempt(conn, payload):
    attempt_id = text_value(payload, 'attempt_id')
    if not attempt_id:
        raise ValueError('attempt_id is required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_delivery_attempts (
            attempt_id, message_id, attempt_number, delivery_target, attempt_status,
            error_code, error_detail, attempted_at, payload_json
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::timestamptz, $9::jsonb)
        ON CONFLICT (attempt_id) DO NOTHING
        ''',
        attempt_id,
        text_value(payload, 'message_id'),
        int(payload.get('attempt_number', 1)),
        text_value(payload, 'delivery_target'),
        text_value(payload, 'attempt_status'),
        text_value(payload, 'error_code') or None,
        text_value(payload, 'error_detail') or None,
        text_value(payload, 'attempted_at'),
        json_text(payload.get('payload', payload)),
    )
    return {'table': 'agent_ledger_delivery_attempts', 'id': attempt_id, 'result': result}


async def append_dead_letter(conn, payload):
    dead_letter_id = text_value(payload, 'dead_letter_id')
    if not dead_letter_id:
        raise ValueError('dead_letter_id is required')
    result = await conn.execute(
        '''
        INSERT INTO agent_ledger_dead_letters (
            dead_letter_id, message_id, dead_letter_reason, final_status, moved_at, recovery_hint_json, payload_json
        ) VALUES ($1, $2, $3, $4, $5::timestamptz, $6::jsonb, $7::jsonb)
        ON CONFLICT (dead_letter_id) DO NOTHING
        ''',
        dead_letter_id,
        text_value(payload, 'message_id'),
        text_value(payload, 'dead_letter_reason'),
        text_value(payload, 'final_status'),
        text_value(payload, 'moved_at'),
        json_text(payload.get('recovery_hint', {})),
        json_text(payload.get('payload', payload)),
    )
    return {'table': 'agent_ledger_dead_letters', 'id': dead_letter_id, 'result': result}


OPERATIONS = {
    'append_message': append_message,
    'append_event': append_event,
    'append_claim': append_claim,
    'append_result': append_result,
    'append_heartbeat': append_heartbeat,
    'append_delivery_attempt': append_delivery_attempt,
    'append_dead_letter': append_dead_letter,
}


async def main():
    payload = json.loads(PAYLOAD_PATH.read_text(encoding='utf-8'))
    dsn = env_value(APP_ROOT / '.env', 'DATABASE_URL')
    if not dsn:
        raise SystemExit('DATABASE_URL not found in remote .env')
    conn = await asyncpg.connect(dsn)
    try:
        operation_result = await OPERATIONS[OPERATION](conn, payload)
        print(json.dumps(operation_result, ensure_ascii=True, separators=(',', ':'), sort_keys=True))
    finally:
        await conn.close()


asyncio.run(main())
PY
rm -f '$remotePayloadPath'
"@
    }

    $result = Invoke-SSHCommand -SessionId ([int]$ssh.SessionId) -Command $remoteCommand -TimeOut 180
    $outputText = @($result.Output) -join "`n"
    if ($result.ExitStatus -ne 0) {
        throw "Remote ledger operation failed with exit status $($result.ExitStatus): $outputText"
    }

    $status.ok = $true
    $status.remote_exit_status = $result.ExitStatus
    $status.remote_output = $outputText
    Write-StatusFile -Path $statusFullPath -Status $status
    $status | ConvertTo-Json -Depth 8
}
catch {
    $status.ok = $false
    $status.error = [string]$_.Exception.Message
    Write-StatusFile -Path $statusFullPath -Status $status
    throw
}
finally {
    if ($sftp) {
        Remove-SFTPSession -SessionId ([int]$sftp.SessionId) | Out-Null
    }
    if ($ssh) {
        Remove-SSHSession -SessionId ([int]$ssh.SessionId) | Out-Null
    }
}
