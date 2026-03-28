param(
    [int]$Port = 8844,
    [string]$ValidationHarness = 'multi_objective_compare',
    [string]$RawArtifactPath = 'tmp_live_sweep_raw.json',
    [string]$IneffectiveSummaryPath = 'tmp_ineffective_sweep_summary.json',
    [string]$OutputPath = 'shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json',
    [int]$WaitTimeoutSeconds = 300,
    [int]$PollMilliseconds = 500,
    [int]$ArtifactFreshnessSeconds = 300,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sweepScript = Join-Path $PSScriptRoot 'Invoke-TODOperatorChatSweep.ps1'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $resolvedDetail = if ([string]::IsNullOrWhiteSpace($Detail)) { '(empty)' } else { $Detail }

    return [pscustomobject]@{
        name = $Name
        passed = $Passed
        detail = $resolvedDetail
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Payload | ConvertTo-Json -Depth $Depth
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Read-JsonIfAvailable {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return [pscustomobject]@{
            exists = $false
            parsed = $false
            payload = $null
            error = 'missing'
        }
    }

    try {
        return [pscustomobject]@{
            exists = $true
            parsed = $true
            payload = (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
            error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            exists = $true
            parsed = $false
            payload = $null
            error = [string]$_.Exception.Message
        }
    }
}

$resolvedRawArtifactPath = Resolve-LocalPath -PathValue $RawArtifactPath
$resolvedSummaryArtifactPath = Resolve-LocalPath -PathValue $IneffectiveSummaryPath
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath
$outputDirectory = Split-Path -Parent $resolvedOutputPath
$outputLeaf = [System.IO.Path]::GetFileNameWithoutExtension($resolvedOutputPath)
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$stdoutLogPath = Join-Path $outputDirectory ($outputLeaf + '.' + $runId + '.stdout.log')
$stderrLogPath = Join-Path $outputDirectory ($outputLeaf + '.' + $runId + '.stderr.log')

if (-not (Test-Path -Path $sweepScript -PathType Leaf)) {
    throw "Sweep script not found: $sweepScript"
}

foreach ($artifactPath in @($resolvedRawArtifactPath, $resolvedSummaryArtifactPath)) {
    if (Test-Path -Path $artifactPath -PathType Leaf) {
        Remove-Item -Path $artifactPath -Force
    }
}

$startedAt = (Get-Date).ToUniversalTime()
$transportError = ''
$summaryRead = $null
$rawRead = $null
$rawGeneratedAt = $null
$timedOut = $false
$sweepExitCode = $null
$sweepPid = $PID
$sweepElapsedSeconds = 0

try {
    $stdoutContent = ''
    $stderrContent = ''

    try {
        $global:LASTEXITCODE = 0
        $sweepOutput = & $sweepScript -ArtifactOnly -Port $Port -ValidationHarness $ValidationHarness -RawArtifactPath $resolvedRawArtifactPath -IneffectiveSummaryPath $resolvedSummaryArtifactPath 2>&1
        $lastExitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
        $sweepExitCode = if ($null -ne $lastExitCodeVar) { [int]$lastExitCodeVar.Value } else { 0 }
        if ($null -ne $sweepOutput) {
            $stdoutContent = [string]($sweepOutput | Out-String)
        }
    }
    catch {
        $transportError = [string]$_.Exception.Message
        $sweepExitCode = 1
        $stderrContent = [string]($_ | Out-String)
    }

    $sweepElapsedSeconds = [Math]::Round((((Get-Date).ToUniversalTime()) - $startedAt).TotalSeconds, 3)
    $timedOut = ($sweepElapsedSeconds -gt [Math]::Max(5, $WaitTimeoutSeconds))

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($stdoutLogPath, $stdoutContent, $utf8NoBom)
    [System.IO.File]::WriteAllText($stderrLogPath, $stderrContent, $utf8NoBom)

    $summaryRead = Read-JsonIfAvailable -PathValue $resolvedSummaryArtifactPath
    $rawRead = Read-JsonIfAvailable -PathValue $resolvedRawArtifactPath

    if ($rawRead.parsed -and $rawRead.payload -and $rawRead.payload.PSObject.Properties['generated_at']) {
        try {
            $rawGeneratedAt = ([DateTime]::Parse([string]$rawRead.payload.generated_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
        }
        catch {
            $rawGeneratedAt = $null
        }
    }

    $artifactFresh = ($null -ne $rawGeneratedAt -and $rawGeneratedAt -ge $startedAt.AddSeconds(-5) -and $rawGeneratedAt -ge ((Get-Date).ToUniversalTime().AddSeconds(-1 * [Math]::Abs($ArtifactFreshnessSeconds))))
    $summaryValid = ($summaryRead.parsed -and $summaryRead.payload -and
        [bool]$summaryRead.payload.ineffective_smoke_ok -and
        [bool]$summaryRead.payload.stable_contract_ok -and
        [string]$summaryRead.payload.ineffective_terminal_state -eq 'ineffective' -and
        [string]$summaryRead.payload.ineffective_lifecycle_status -eq 'ineffective' -and
        [bool]$summaryRead.payload.ineffective_signal_seen -and
        [string]$summaryRead.payload.ineffective_followup_action -eq 'refresh-governance-snapshot' -and
        [string]$summaryRead.payload.ineffective_commitment_terminal_state -eq 'ineffective')

}
catch {
    $transportError = [string]$_.Exception.Message
}

$summaryRead = if ($null -eq $summaryRead) { Read-JsonIfAvailable -PathValue $resolvedSummaryArtifactPath } else { $summaryRead }
$rawRead = if ($null -eq $rawRead) { Read-JsonIfAvailable -PathValue $resolvedRawArtifactPath } else { $rawRead }

if ($null -eq $rawGeneratedAt -and $rawRead.parsed -and $rawRead.payload -and $rawRead.payload.PSObject.Properties['generated_at']) {
    try {
        $rawGeneratedAt = ([DateTime]::Parse([string]$rawRead.payload.generated_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
    }
    catch {
        $rawGeneratedAt = $null
    }
}

$artifactFreshFinal = ($null -ne $rawGeneratedAt -and $rawGeneratedAt -ge $startedAt.AddSeconds(-5) -and $rawGeneratedAt -ge ((Get-Date).ToUniversalTime().AddSeconds(-1 * [Math]::Abs($ArtifactFreshnessSeconds))))
$summaryPayload = if ($summaryRead.parsed) { $summaryRead.payload } else { $null }
$rawPayload = if ($rawRead.parsed) { $rawRead.payload } else { $null }
$checks = @(
    (New-Check -Name 'sweep_transport_started' -Passed ([string]::IsNullOrWhiteSpace($transportError)) -Detail $(if ([string]::IsNullOrWhiteSpace($transportError)) { 'Sweep process launched.' } else { $transportError })),
    (New-Check -Name 'raw_artifact_exists' -Passed ([bool]$rawRead.exists) -Detail $resolvedRawArtifactPath),
    (New-Check -Name 'summary_artifact_exists' -Passed ([bool]$summaryRead.exists) -Detail $resolvedSummaryArtifactPath),
    (New-Check -Name 'raw_artifact_parses' -Passed ([bool]$rawRead.parsed) -Detail $(if ($rawRead.parsed) { 'Raw artifact parsed.' } else { [string]$rawRead.error })),
    (New-Check -Name 'summary_artifact_parses' -Passed ([bool]$summaryRead.parsed) -Detail $(if ($summaryRead.parsed) { 'Summary artifact parsed.' } else { [string]$summaryRead.error })),
    (New-Check -Name 'raw_artifact_contract_source' -Passed ($rawPayload -and [string]$rawPayload.source -eq 'tod-operator-chat-sweep-early-artifact-v1') -Detail $(if ($rawPayload) { [string]$rawPayload.source } else { 'raw artifact unavailable' })),
    (New-Check -Name 'artifact_timestamp_fresh' -Passed ([bool]$artifactFreshFinal) -Detail $(if ($artifactFreshFinal) { [string]$rawGeneratedAt.ToString('o') } else { 'Raw artifact timestamp is missing or stale.' })),
    (New-Check -Name 'ineffective_smoke_ok' -Passed ($summaryPayload -and [bool]$summaryPayload.ineffective_smoke_ok) -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_smoke_ok } else { 'summary unavailable' })),
    (New-Check -Name 'stable_contract_ok' -Passed ($summaryPayload -and [bool]$summaryPayload.stable_contract_ok) -Detail $(if ($summaryPayload) { [string]$summaryPayload.stable_contract_ok } else { 'summary unavailable' })),
    (New-Check -Name 'ineffective_terminal_state' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_terminal_state -eq 'ineffective') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_terminal_state } else { 'summary unavailable' })),
    (New-Check -Name 'ineffective_lifecycle_status' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_lifecycle_status -eq 'ineffective') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_lifecycle_status } else { 'summary unavailable' })),
    (New-Check -Name 'ineffective_signal_seen' -Passed ($summaryPayload -and [bool]$summaryPayload.ineffective_signal_seen) -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_signal_seen } else { 'summary unavailable' })),
    (New-Check -Name 'ineffective_followup_action' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_followup_action -eq 'refresh-governance-snapshot') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_followup_action } else { 'summary unavailable' })),
    (New-Check -Name 'ineffective_commitment_terminal_state' -Passed ($summaryPayload -and [string]$summaryPayload.ineffective_commitment_terminal_state -eq 'ineffective') -Detail $(if ($summaryPayload) { [string]$summaryPayload.ineffective_commitment_terminal_state } else { 'summary unavailable' }))
)

$passedAll = @($checks | Where-Object { -not [bool]$_.passed }).Count -eq 0
$exitCode = if ($passedAll) { 0 } elseif (-not [string]::IsNullOrWhiteSpace($transportError)) { 2 } elseif (-not $summaryRead.exists -or -not $rawRead.exists) { 3 } elseif (-not $summaryRead.parsed -or -not $rawRead.parsed) { 4 } else { 5 }

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-operator-chat-sweep-artifact-smoke-v1'
    port = $Port
    validation_harness = $ValidationHarness
    wait_timeout_seconds = $WaitTimeoutSeconds
    poll_milliseconds = $PollMilliseconds
    artifact_freshness_seconds = $ArtifactFreshnessSeconds
    started_at = $startedAt.ToString('o')
    raw_artifact_path = $resolvedRawArtifactPath
    ineffective_summary_path = $resolvedSummaryArtifactPath
    output_path = $resolvedOutputPath
    stdout_log_path = $stdoutLogPath
    stderr_log_path = $stderrLogPath
    sweep_process = [pscustomobject]@{
        started = $true
        pid = $sweepPid
        exited = $true
        exit_code = $sweepExitCode
        elapsed_seconds = $sweepElapsedSeconds
        timed_out = $timedOut
    }
    artifact_generated_at = if ($null -ne $rawGeneratedAt) { $rawGeneratedAt.ToString('o') } else { '' }
    checks = @($checks)
    summary = [pscustomobject]@{
        total = @($checks).Count
        passed = @(@($checks | Where-Object { [bool]$_.passed })).Count
        failed = @(@($checks | Where-Object { -not [bool]$_.passed })).Count
        passed_all = $passedAll
        exit_code = $exitCode
    }
}

Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $report -Depth 12

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 10 | Write-Output
}
else {
    $report
}

exit $exitCode