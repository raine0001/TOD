param(
    [int]$MaxCycles = 36,
    [int]$IntervalMinutes = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$watchdogScript = Join-Path $repoRoot "scripts/Invoke-UserAppBuildTrainingWatchdog.ps1"
$logDir = Join-Path $repoRoot "runtime/shared/logs"
if (-not (Test-Path -Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$stdout = Join-Path $logDir "user_app_deep_training_watchdog.stdout.log"
$stderr = Join-Path $logDir "user_app_deep_training_watchdog.stderr.log"

$safeWatchdogScript = $watchdogScript.Replace("'", "''")
$loopCommand = @"
`$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath '$($repoRoot.Replace("'", "''"))'
for (`$cycle = 1; `$cycle -le $MaxCycles; `$cycle++) {
  & '$safeWatchdogScript' -RunOnce -MaxCycles $MaxCycles -IntervalMinutes $IntervalMinutes
  if (`$cycle -lt $MaxCycles) {
    Start-Sleep -Seconds ([Math]::Max(1, $IntervalMinutes) * 60)
  }
}
"@

$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($loopCommand))
$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-EncodedCommand", $encodedCommand
) -join " "

$process = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WorkingDirectory $repoRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru

$payload = [ordered]@{
    artifact_type = "user_app_deep_training_watchdog_process_v1"
    started_at = (Get-Date).ToUniversalTime().ToString("o")
    process_id = $process.Id
    max_cycles = $MaxCycles
    interval_minutes = $IntervalMinutes
    mode = "persistent_runonce_loop"
    stdout = $stdout
    stderr = $stderr
    status_artifact = "runtime/shared/USER_APP_DEEP_TRAINING_WATCHDOG.latest.json"
    rule = "MIM/TOD own app development; Codex supervises the watchdog and blocker repair only."
}
$statusPath = Join-Path $repoRoot "runtime/shared/USER_APP_DEEP_TRAINING_WATCHDOG_PROCESS.latest.json"
$json = $payload | ConvertTo-Json -Depth 10
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($statusPath, $json, $utf8NoBom)
$payload | ConvertTo-Json -Depth 10
