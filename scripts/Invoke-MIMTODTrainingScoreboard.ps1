param(
  [double]$OperatorEstimatedHours = 0,
  [string]$BaseUrl = "http://192.168.1.120:18001",
  [switch]$SkipPublish
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvPath = Join-Path $Root ".env"
$ScoreboardScript = Join-Path $Root "scripts\generate_mim_tod_training_scoreboard.py"
$OutDir = Join-Path $Root "runtime_remote_training"
$LatestScoreboard = Join-Path $OutDir "MIM_TOD_TRAINING_SCOREBOARD.latest.json"
$LogDir = Join-Path $Root "runtime\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Get-DotEnvValue {
  param([string]$Name)
  if (-not (Test-Path $EnvPath)) { return "" }
  $line = Get-Content $EnvPath | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
  if (-not $line) { return "" }
  return (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
}

$hostName = Get-DotEnvValue "MIM_SSH_HOST"
$userName = Get-DotEnvValue "MIM_SSH_USER"
$password = Get-DotEnvValue "MIM_SSH_PASSWORD"

if ($hostName -and $userName -and $password) {
  try {
    $sec = ConvertTo-SecureString $password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($userName, $sec)
    $tmpPull = Join-Path $LogDir "mim_tod_reflection_pull"
    New-Item -ItemType Directory -Force -Path $tmpPull | Out-Null
    Get-SCPItem -ComputerName $hostName -Credential $cred -AcceptKey -ConnectionTimeout 30 -Path "/home/testpilot/mim/runtime/shared/MIM_TOD_HOURLY_REFLECTION.latest.json" -PathType File -Destination $tmpPull -Force | Out-Null
    $pulled = Join-Path $tmpPull "MIM_TOD_HOURLY_REFLECTION.latest.json"
    if (Test-Path $pulled) {
      Copy-Item -LiteralPath $pulled -Destination (Join-Path $OutDir "MIM_TOD_HOURLY_REFLECTION.latest.json") -Force
    }
  } catch {
    "Reflection pull failed: $([string]::Join(' ', @($_.Exception.Message -split '\s+')))" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.reflection_pull_failed.log") -Append | Out-Null
  }
}

if ($OperatorEstimatedHours -le 0 -and (Test-Path $LatestScoreboard)) {
  try {
    $prior = Get-Content $LatestScoreboard -Raw | ConvertFrom-Json
    $priorGenerated = [datetime]::Parse($prior.generated_at).ToUniversalTime()
    $priorHours = [double]$prior.training_hours.today.value
    if ($priorGenerated.Date -eq [datetime]::UtcNow.Date -and $priorHours -gt 0) {
      $elapsed = ([datetime]::UtcNow - $priorGenerated).TotalHours
      $OperatorEstimatedHours = [math]::Round(($priorHours + [math]::Max(0, $elapsed)), 2)
    }
  } catch {
    $OperatorEstimatedHours = 0
  }
}

$argsList = @(
  $ScoreboardScript,
  "--base-url", $BaseUrl,
  "--write-snapshots",
  "--out-dir", $OutDir
)
if ($OperatorEstimatedHours -gt 0) {
  $argsList += @("--operator-estimated-hours", [string]$OperatorEstimatedHours)
}

$pythonOutput = & python @argsList 2>&1
$pythonOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Scoreboard generation failed: $pythonOutput"
}

if ($SkipPublish) {
  return
}

if (-not $hostName -or -not $userName -or -not $password) {
  throw "Missing MIM_SSH_HOST, MIM_SSH_USER, or MIM_SSH_PASSWORD in .env"
}

$sec = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($userName, $sec)
$files = @(
  (Join-Path $OutDir "MIM_TOD_TRAINING_SCOREBOARD.latest.json"),
  (Join-Path $OutDir "MIM_TOD_TRAINING_SCOREBOARD.latest.md")
)
foreach ($file in $files) {
  $published = $false
  $lastPublishError = ""
  for ($attempt = 1; $attempt -le 3 -and -not $published; $attempt++) {
    try {
      Set-SCPItem -ComputerName $hostName -Credential $cred -AcceptKey -ConnectionTimeout 30 -Path $file -Destination "/home/testpilot/mim/runtime/shared" -Force | Out-Null
      $published = $true
    } catch {
      $lastPublishError = [string]::Join(" ", @($_.Exception.Message -split "\s+"))
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
  if (-not $published) {
    "Publish failed for ${file}: $lastPublishError" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.publish_failed.log") -Append | Out-Null
  }
}
