param(
    [int]$SinceHours = 24,
    [string]$OutputPath = "tod/out/pc-maintenance/TOD_PC_CRASH_OBSERVATION.latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repoRoot $OutputPath
}

$since = (Get-Date).AddHours(-1 * [Math]::Max(1, $SinceHours))
$os = Get-CimInstance Win32_OperatingSystem
$lastBoot = $os.LastBootUpTime

function Get-SystemEventsSafe {
    param(
        [int[]]$Ids,
        [datetime]$StartTime
    )

    try {
        return @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = $Ids; StartTime = $StartTime } -ErrorAction Stop |
            Select-Object -First 20 TimeCreated, Id, ProviderName, Message)
    }
    catch {
        return @()
    }
}

$bugchecks = @(Get-SystemEventsSafe -Ids @(1001) -StartTime $since | Where-Object {
    [string]$_.ProviderName -match 'BugCheck|Microsoft-Windows-WER-SystemErrorReporting'
})
$kernelPower = @(Get-SystemEventsSafe -Ids @(41) -StartTime $since)
$unexpectedShutdown = @(Get-SystemEventsSafe -Ids @(6008) -StartTime $since)

$minidumpDir = Join-Path $env:SystemRoot 'Minidump'
$recentMinidumps = @()
if (Test-Path -Path $minidumpDir -PathType Container) {
    $recentMinidumps = @(Get-ChildItem -Path $minidumpDir -Filter '*.dmp' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since } |
        Select-Object -First 20 FullName, LastWriteTime, Length)
}

$crashSignals = @($bugchecks).Count + @($kernelPower).Count + @($unexpectedShutdown).Count + @($recentMinidumps).Count
$status = if ($crashSignals -gt 0) { 'crash_signal_detected' } else { 'no_new_crash_signal_detected' }

$payload = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    status = $status
    since_hours = $SinceHours
    since_local = $since.ToString('o')
    last_boot = $lastBoot.ToString('o')
    permanent_fix_claim = $false
    stability_claim = if ($crashSignals -gt 0) { 'not_stable_new_crash_signal_requires_diagnostic_ladder' } else { 'observation_window_clean_so_far_not_permanent_proof' }
    bugcheck_event_count = @($bugchecks).Count
    kernel_power_event_count = @($kernelPower).Count
    unexpected_shutdown_event_count = @($unexpectedShutdown).Count
    recent_minidump_count = @($recentMinidumps).Count
    recent_minidumps = @($recentMinidumps)
    required_continuation = if ($crashSignals -gt 0) { 'collect_fresh_dump_and_rerun_pc_crash_diagnostic_ladder' } else { 'continue_observation_window_monitoring' }
}

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -Path $outDir -PathType Container)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8
$payload | ConvertTo-Json -Depth 8