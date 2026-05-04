param(
    [string]$EnvFile = ".env",
    [string]$ObjectiveId = "objective-90",
    [string]$TodAction = "get-state-bus",
    [int]$TimeoutSeconds = 180,
    [int]$PollSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$authoritativeCommunicationHost = '192.168.1.120'
$authoritativeCommunicationRoot = '/home/testpilot/mim/runtime/shared'

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match "^\s*$([regex]::Escape($Name))\s*="
    } | Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return ($line -replace "^\s*$([regex]::Escape($Name))\s*=\s*", "").Trim()
}

function Resolve-PreferredSshHost {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName
    )

    try {
        $v4 = @(Resolve-DnsName -Name $HostName -Type A -ErrorAction Stop | Select-Object -ExpandProperty IPAddress)
        if (@($v4).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$v4[0])) {
            return [string]$v4[0]
        }
    }
    catch {
    }

    return $HostName
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot $EnvFile
if (-not (Test-Path -Path $envPath)) {
    throw "Missing $EnvFile. Copy .env.example to .env and set MIM_SSH_PASSWORD."
}

$hostName = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_HOST"
$userName = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_USER"
$port = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_PORT"
$password = Get-DotEnvValue -Path $envPath -Name "MIM_SSH_PASSWORD"

if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = "mim" }
if ([string]::IsNullOrWhiteSpace($userName)) { $userName = "testpilot" }
if ([string]::IsNullOrWhiteSpace($port)) { $port = "22" }

if ([string]::IsNullOrWhiteSpace($password) -or $password -eq "CHANGE_ME") {
    throw "Set MIM_SSH_PASSWORD in $EnvFile before running the listener smoke."
}

if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    throw "Posh-SSH is not installed. Run: Install-Module -Name Posh-SSH -Scope CurrentUser"
}

Import-Module Posh-SSH -ErrorAction Stop | Out-Null

$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($userName, $securePassword)
$connectHost = Resolve-PreferredSshHost -HostName $hostName
$remoteRoot = "/home/testpilot/mim/runtime/shared"

if (-not [string]::Equals([string]$connectHost, $authoritativeCommunicationHost, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("Listener smoke refuses to use non-authoritative communication host '{0}'. Expected {1}:{2}. Arm-side hosts such as 192.168.1.90 are runtime/telemetry only." -f [string]$connectHost, $authoritativeCommunicationHost, $authoritativeCommunicationRoot)
}

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")
$requestId = "{0}-task-smoke-{1}" -f $ObjectiveId, $stamp
$correlationId = "obj{0}-smoke-{1}" -f ($ObjectiveId -replace "^objective-", ""), $stamp
$goCorrelationId = "$correlationId-go"
$now = (Get-Date).ToUniversalTime().ToString("o")
$sequenceBase = [long]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

$request = [pscustomobject]@{
    version = "1.0"
    source = "MIM"
    target = "TOD"
    generated_at = $now
    emitted_at = $now
    sequence = $sequenceBase
    source_host = "MIM"
    source_service = "copilot-smoke"
    source_instance_id = "copilot-smoke:$stamp"
    correlation_id = $correlationId
    task_id = $requestId
    objective_id = $ObjectiveId
    title = "Execution readiness live smoke"
    scope = "Validate readiness metadata propagation through ACK, RESULT, and loop journal."
    priority = "high"
    tod_action = $TodAction
    acceptance_criteria = @(
        "Fresh result emitted for smoke request",
        "Result includes execution_readiness",
        "Command status advances beyond ACK"
    )
    constraints = @(
        "Keep objective alignment true",
        "Use lightweight action only"
    )
    notes = "Synthetic smoke request for readiness metadata validation."
}

$goOrder = [pscustomobject]@{
    version = "1.0"
    source = "MIM"
    target = "TOD"
    generated_at = $now
    emitted_at = $now
    sequence = $sequenceBase + 1
    source_host = "MIM"
    source_service = "copilot-smoke"
    source_instance_id = "copilot-smoke:$stamp"
    task_id = $requestId
    correlation_id = $goCorrelationId
    order = [pscustomobject]@{
        correlation_id = $goCorrelationId
        task_id = $requestId
        objective_id = $ObjectiveId
        type = "execute_now"
        instructions = @(
            "Acknowledge current task packet",
            "Execute lightweight action",
            "Emit readiness-enriched result artifacts"
        )
    }
}

$review = [pscustomobject]@{
    version = "1.0"
    source = "MIM"
    target = "TOD"
    generated_at = $now
    emitted_at = $now
    sequence = $sequenceBase + 2
    source_host = "MIM"
    source_service = "copilot-smoke"
    source_instance_id = "copilot-smoke:$stamp"
    objective_id = $ObjectiveId
    correlation_id = $correlationId
    task_id = $requestId
    decision = "accepted"
    decision_rationale = "Synthetic smoke approval for readiness metadata validation."
    required_followups = @(
        "Verify emitted artifacts"
    )
    closeout_notes = "Copilot smoke request"
}

$tempDir = Join-Path $env:TEMP ("tod-listener-smoke-" + $stamp)
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$requestPath = Join-Path $tempDir "MIM_TOD_TASK_REQUEST.latest.json"
$goPath = Join-Path $tempDir "MIM_TOD_GO_ORDER.latest.json"
$reviewPath = Join-Path $tempDir "MIM_TOD_REVIEW_DECISION.latest.json"

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($requestPath, (($request | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"), $utf8)
[System.IO.File]::WriteAllText($goPath, (($goOrder | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"), $utf8)
[System.IO.File]::WriteAllText($reviewPath, (($review | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"), $utf8)

$sftp = New-SFTPSession -ComputerName $connectHost -Port ([int]$port) -Credential $credential -AcceptKey -Force -ConnectionTimeout 30000
try {
    Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $requestPath -Destination $remoteRoot -Force -ErrorAction Stop | Out-Null
    Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $goPath -Destination $remoteRoot -Force -ErrorAction Stop | Out-Null
    Set-SFTPItem -SessionId ([int]$sftp.SessionId) -Path $reviewPath -Destination $remoteRoot -Force -ErrorAction Stop | Out-Null
}
finally {
    if ($sftp) {
        Remove-SFTPSession -SessionId ([int]$sftp.SessionId) | Out-Null
    }

    if (Test-Path -Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
}

$listenerRoot = Join-Path $repoRoot "tod/out/context-sync/listener"
$resultPath = Join-Path $listenerRoot "TOD_MIM_TASK_RESULT.latest.json"
$commandStatusPath = Join-Path $listenerRoot "TOD_MIM_COMMAND_STATUS.latest.json"
$journalPath = Join-Path $listenerRoot "TOD_LOOP_JOURNAL.latest.json"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$resultPacket = $null
do {
    if (Test-Path -Path $resultPath) {
        try {
            $candidate = Get-Content -Path $resultPath -Raw | ConvertFrom-Json
            if ($candidate -and [string]::Equals([string]$candidate.request_id, $requestId, [System.StringComparison]::OrdinalIgnoreCase)) {
                $resultPacket = $candidate
                break
            }
        }
        catch {
        }
    }

    Start-Sleep -Seconds $PollSeconds
} while ((Get-Date) -lt $deadline)

$commandStatus = $null
$journal = $null
if (Test-Path -Path $commandStatusPath) {
    try {
        $commandStatus = Get-Content -Path $commandStatusPath -Raw | ConvertFrom-Json
    }
    catch {
    }
}

if (Test-Path -Path $journalPath) {
    try {
        $journal = Get-Content -Path $journalPath -Raw | ConvertFrom-Json
    }
    catch {
    }
}

$latestJournalEntry = $null
if ($journal -and $journal.PSObject.Properties["entries"]) {
    $entries = @($journal.entries)
    if ($entries.Count -gt 0) {
        $latestJournalEntry = $entries[-1]
    }
}

[pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    request_id = $requestId
    objective_id = $ObjectiveId
    tod_action = $TodAction
    communication_authority = [pscustomobject]@{
        host = $authoritativeCommunicationHost
        path = $authoritativeCommunicationRoot
        role = 'communication_authority'
        configured_host = $hostName
        resolved_host = $connectHost
        resolved_host_matches_policy = [string]::Equals([string]$connectHost, $authoritativeCommunicationHost, [System.StringComparison]::OrdinalIgnoreCase)
        non_authoritative_surfaces = @(
            [pscustomobject]@{ host = '192.168.1.90'; path = '/home/testpilot/mim/runtime/shared'; role = 'arm-side runtime/telemetry'; authoritative_for_communication = $false },
            [pscustomobject]@{ host = '192.168.1.90'; path = '/home/testpilot/mim_arm/runtime/shared'; role = 'arm-side runtime/telemetry'; authoritative_for_communication = $false },
            [pscustomobject]@{ host = 'local'; path = 'tod/out/context-sync/*'; role = 'local mirrors'; authoritative_for_communication = $false }
        )
    }
    result_emitted = ($null -ne $resultPacket)
    result_request_id = if ($resultPacket) { [string]$resultPacket.request_id } else { "" }
    result_status = if ($resultPacket) { [string]$resultPacket.status } else { "" }
    result_execution_readiness_status = if ($resultPacket -and $resultPacket.PSObject.Properties["execution_readiness"] -and $resultPacket.execution_readiness) { [string]$resultPacket.execution_readiness.status } else { "" }
    result_execution_readiness_policy = if ($resultPacket -and $resultPacket.PSObject.Properties["execution_readiness"] -and $resultPacket.execution_readiness) { [string]$resultPacket.execution_readiness.policy_outcome } else { "" }
    command_status_request_id = if ($commandStatus) { [string]$commandStatus.request_id } else { "" }
    command_status_status = if ($commandStatus) { [string]$commandStatus.status } else { "" }
    command_status_execution_readiness_status = if ($commandStatus -and $commandStatus.PSObject.Properties["execution_readiness"] -and $commandStatus.execution_readiness) { [string]$commandStatus.execution_readiness.status } else { "" }
    journal_latest_request_id = if ($latestJournalEntry) { [string]$latestJournalEntry.request_id } else { "" }
    journal_latest_execution_status = if ($latestJournalEntry) { [string]$latestJournalEntry.execution_status } else { "" }
    journal_latest_execution_readiness_status = if ($latestJournalEntry) { [string]$latestJournalEntry.execution_readiness_status } else { "" }
} | ConvertTo-Json -Depth 6