param(
  [double]$OperatorEstimatedHours = 0,
  [string]$BaseUrl = "http://192.168.1.120:18001",
  [string]$StudioBaseUrl = "https://mimtod.com",
  [string]$MimTodBaseUrl = "https://mimtod.com",
  [string]$AgentMimBaseUrl = "https://www.agentmim.com",
  [string]$AgentMimEnvPath = "",
  [switch]$SkipPublish
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EnvPath = Join-Path $Root ".env"
$ScoreboardScript = Join-Path $Root "scripts\generate_mim_tod_training_scoreboard.py"
$JudgmentSmokeScript = Join-Path $Root "scripts\run_mim_durability_smoke_v2.py"
$TypoSmokeScript = Join-Path $Root "scripts\run_mim_typo_tolerant_intent_smoke.py"
$InitiativeGateScript = Join-Path $Root "scripts\generate_mim_tod_training_initiative_gate.py"
$OperatorImpactLiveScript = Join-Path $Root "tools\score_mim_operator_impact_live_10.py"
$OperatorImpactScorecardScript = Join-Path $Root "tools\build_mim_operator_impact_scorecard.py"
$StructuralDiversityScript = Join-Path $Root "tools\score_mim_structural_reasoning_diversity.py"
$CrossSurfaceScript = Join-Path $Root "tools\score_mim_structural_reasoning_cross_surface.py"
$ContextGroundingScript = Join-Path $Root "tools\score_mim_context_grounding.py"
$RealMovementScript = Join-Path $Root "tools\build_mim_tod_real_movement_scorecard.py"
$OutDir = Join-Path $Root "runtime_remote_training"
$LatestScoreboard = Join-Path $OutDir "MIM_TOD_TRAINING_SCOREBOARD.latest.json"
$LogDir = Join-Path $Root "runtime\logs"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Invoke-PythonCapture {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & python @Arguments 2>&1
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
}

function Get-DotEnvValue {
  param([string]$Name)
  if (-not (Test-Path $EnvPath)) { return "" }
  $line = Get-Content $EnvPath | Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*=" } | Select-Object -First 1
  if (-not $line) { return "" }
  return (($line -split "=", 2)[1]).Trim().Trim('"').Trim("'")
}

function Ensure-PoshSshModulePath {
  $candidateRoots = @(
    (Join-Path $HOME 'OneDrive\Documents\WindowsPowerShell\Modules'),
    (Join-Path $HOME 'Documents\WindowsPowerShell\Modules'),
    (Join-Path $HOME 'OneDrive\Documents\PowerShell\Modules'),
    (Join-Path $HOME 'Documents\PowerShell\Modules')
  )

  $pathParts = @([string]$env:PSModulePath -split [regex]::Escape([System.IO.Path]::PathSeparator) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  foreach ($candidateRoot in $candidateRoots) {
    if ((Test-Path -Path (Join-Path $candidateRoot 'Posh-SSH')) -and -not ($pathParts -contains $candidateRoot)) {
      $pathParts = @($candidateRoot) + $pathParts
    }
  }
  $env:PSModulePath = ($pathParts | Select-Object -Unique) -join [System.IO.Path]::PathSeparator
}

function New-MimSftpSession {
  param(
    [Parameter(Mandatory = $true)][string]$HostName,
    [Parameter(Mandatory = $true)][string]$UserName,
    [Parameter(Mandatory = $true)][int]$Port,
    [Parameter(Mandatory = $true)]$Credential
  )

  Ensure-PoshSshModulePath
  Import-Module Posh-SSH -ErrorAction Stop | Out-Null
  return New-SFTPSession -ComputerName $HostName -Port $Port -Credential $Credential -AcceptKey -ConnectionTimeout 30000
}

function Close-MimSftpSession {
  param($Session)
  if ($null -eq $Session) { return }
  try {
    Remove-SFTPSession -SessionId ([int]$Session.SessionId) | Out-Null
  } catch {
  }
}

function Copy-RemoteSharedFileToLocal {
  param(
    [Parameter(Mandatory = $true)]$Session,
    [Parameter(Mandatory = $true)][string]$RemotePath,
    [Parameter(Mandatory = $true)][string]$DestinationDir
  )

  Get-SFTPItem -SessionId ([int]$Session.SessionId) -Path $RemotePath -Destination $DestinationDir -Force -ErrorAction Stop | Out-Null
}

function Copy-LocalFileToRemoteShared {
  param(
    [Parameter(Mandatory = $true)]$Session,
    [Parameter(Mandatory = $true)][string]$LocalPath,
    [Parameter(Mandatory = $true)][string]$RemoteDir
  )

  Set-SFTPItem -SessionId ([int]$Session.SessionId) -Path $LocalPath -Destination $RemoteDir -Force -ErrorAction Stop | Out-Null
}

$hostName = Get-DotEnvValue "MIM_SSH_HOST"
$userName = Get-DotEnvValue "MIM_SSH_USER"
$password = Get-DotEnvValue "MIM_SSH_PASSWORD"
$portValue = Get-DotEnvValue "MIM_SSH_PORT"
if (-not $portValue) { $portValue = "22" }
if (-not $AgentMimEnvPath) {
  $candidateAgentMimEnv = "E:\comm_app\app\.env"
  if (Test-Path $candidateAgentMimEnv) {
    $AgentMimEnvPath = $candidateAgentMimEnv
  }
}

if ($hostName -and $userName -and $password) {
  $sftpSession = $null
  try {
    $sec = ConvertTo-SecureString $password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($userName, $sec)
    $sftpSession = New-MimSftpSession -HostName $hostName -UserName $userName -Port ([int]$portValue) -Credential $cred
    $tmpPull = Join-Path $LogDir "mim_tod_reflection_pull"
    New-Item -ItemType Directory -Force -Path $tmpPull | Out-Null
    $remoteArtifacts = @(
      "MIM_TOD_HOURLY_REFLECTION.latest.json",
      "TOD_MIM_TASK_RESULT.latest.json",
      "TOD_MIM_COMMAND_STATUS.latest.json",
      "TOD_EXECUTION_TRUTH.latest.json",
      "TOD_EXECUTION_RESULT.latest.json",
      "TOD_VALIDATION_RESULT.latest.json",
      "MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
      "TOD_IDLE_TRAINING_STATUS.latest.json",
      "TOD_PROACTIVE_TASK.latest.json",
      "TOD_PROACTIVE_AUTONOMY.latest.json"
    )
    foreach ($artifactName in $remoteArtifacts) {
      try {
        Copy-RemoteSharedFileToLocal -Session $sftpSession -RemotePath "/home/testpilot/mim/runtime/shared/$artifactName" -DestinationDir $tmpPull
        $pulled = Join-Path $tmpPull $artifactName
        if (Test-Path $pulled) {
          Copy-Item -LiteralPath $pulled -Destination (Join-Path $OutDir $artifactName) -Force
          if ($artifactName -in @("MIM_READY_TASK_DISPATCHER_STATUS.latest.json", "TOD_IDLE_TRAINING_STATUS.latest.json")) {
            $contextSyncTarget = Join-Path $Root ("tod\out\context-sync\{0}" -f $artifactName)
            $contextSyncDir = Split-Path -Parent $contextSyncTarget
            if (-not (Test-Path $contextSyncDir)) {
              New-Item -ItemType Directory -Force -Path $contextSyncDir | Out-Null
            }
            Copy-Item -LiteralPath $pulled -Destination $contextSyncTarget -Force
          }
        }
      } catch {
        "Artifact pull failed for ${artifactName}: $([string]::Join(' ', @($_.Exception.Message -split '\s+')))" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.artifact_pull_failed.log") -Append | Out-Null
      }
    }
    try {
      $dialogDir = Join-Path $Root "shared_state\dialog"
      New-Item -ItemType Directory -Force -Path $dialogDir | Out-Null
      $dialogIndexName = "MIM_TOD_DIALOG.sessions.latest.json"
      Copy-RemoteSharedFileToLocal -Session $sftpSession -RemotePath "/home/testpilot/mim/runtime/shared/dialog/$dialogIndexName" -DestinationDir $dialogDir

      $dialogIndexPath = Join-Path $dialogDir $dialogIndexName
      if (Test-Path $dialogIndexPath) {
        $dialogIndex = Get-Content $dialogIndexPath -Raw | ConvertFrom-Json
        $dialogCandidates = @()
        foreach ($dialogSession in @($dialogIndex.sessions)) {
          $sessionPath = [string]$dialogSession.session_path
          if ([string]::IsNullOrWhiteSpace($sessionPath)) {
            continue
          }
          $status = ([string]$dialogSession.status).Trim().ToLowerInvariant()
          $updatedAtRaw = [string]$dialogSession.updated_at
          $updatedAt = $null
          if (-not [string]::IsNullOrWhiteSpace($updatedAtRaw)) {
            try {
              $updatedAt = [datetime]::Parse($updatedAtRaw).ToUniversalTime()
            } catch {
              $updatedAt = $null
            }
          }
          $dialogCandidates += [pscustomobject]@{
            SessionPath = $sessionPath
            IsOpen = ($status -in @("awaiting_reply", "timed_out"))
            UpdatedAt = $updatedAt
          }
        }
        $openSessionPaths = @($dialogCandidates | Where-Object { $_.IsOpen } | Select-Object -ExpandProperty SessionPath)
        $recentSessionPaths = @(
          $dialogCandidates |
            Where-Object { -not $_.IsOpen -and $null -ne $_.UpdatedAt } |
            Sort-Object -Property UpdatedAt -Descending |
            Select-Object -First 20 -ExpandProperty SessionPath
        )
        foreach ($sessionPath in @(($openSessionPaths + $recentSessionPaths) | Select-Object -Unique)) {
          $sessionFileName = Split-Path -Leaf $sessionPath
          if ([string]::IsNullOrWhiteSpace($sessionFileName)) {
            continue
          }
          $remoteJsonl = "/home/testpilot/mim/runtime/shared/dialog/$sessionFileName"
          $remoteLatest = $remoteJsonl -replace "\.jsonl$", ".latest.json"
          foreach ($remoteDialogFile in @($remoteLatest, $remoteJsonl)) {
            try {
              Copy-RemoteSharedFileToLocal -Session $sftpSession -RemotePath $remoteDialogFile -DestinationDir $dialogDir
            } catch {
              "Dialog pull failed for ${remoteDialogFile}: $([string]::Join(' ', @($_.Exception.Message -split '\s+')))" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.dialog_pull_failed.log") -Append | Out-Null
            }
          }
        }
      }
    } catch {
      "Dialog index pull failed: $([string]::Join(' ', @($_.Exception.Message -split '\s+')))" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.dialog_pull_failed.log") -Append | Out-Null
    }
  } catch {
    "Reflection pull failed: $([string]::Join(' ', @($_.Exception.Message -split '\s+')))" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.reflection_pull_failed.log") -Append | Out-Null
  } finally {
    Close-MimSftpSession -Session $sftpSession
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

$smokeArgsList = @(
  $JudgmentSmokeScript,
  "--transport", "studio",
  "--base-url", $StudioBaseUrl,
  "--out-dir", $OutDir
)
$smokeOutput = Invoke-PythonCapture -Arguments $smokeArgsList
$smokeOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_durability_smoke_v2.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Judgment smoke failed; continuing scoreboard with failed smoke evidence: $smokeOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_durability_smoke_v2.failed.log") -Append | Out-Null
}

$typoArgsList = @(
  $TypoSmokeScript,
  "--base-url", $BaseUrl,
  "--out-dir", $OutDir
)
$typoOutput = Invoke-PythonCapture -Arguments $typoArgsList
$typoOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_typo_tolerant_intent_smoke.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Typo tolerance smoke failed; continuing scoreboard with failed smoke evidence: $typoOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_typo_tolerant_intent_smoke.failed.log") -Append | Out-Null
}

$operatorLiveArgsList = @(
  $OperatorImpactLiveScript,
  "--studio-base-url", $StudioBaseUrl
)
$operatorLiveOutput = Invoke-PythonCapture -Arguments $operatorLiveArgsList
$operatorLiveOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_live_10.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Operator impact live-10 scoring failed; continuing with failed evidence: $operatorLiveOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_live_10.failed.log") -Append | Out-Null
}
else {
  $operatorLiveExpectedArtifacts = @(
    (Join-Path $OutDir "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"),
    (Join-Path $OutDir "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.md")
  )
  $missingOperatorLiveArtifacts = @($operatorLiveExpectedArtifacts | Where-Object { -not (Test-Path $_) })
  if (@($missingOperatorLiveArtifacts).Count -gt 0) {
    throw "Operator impact live-10 scoring exited successfully but did not write expected artifacts: $($missingOperatorLiveArtifacts -join ', ')"
  }
}

$structuralArgsList = @(
  $StructuralDiversityScript,
  "--live-base-url", $MimTodBaseUrl,
  "--timeout", "60"
)
$structuralOutput = Invoke-PythonCapture -Arguments $structuralArgsList
$structuralOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_structural_reasoning_diversity.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Structural reasoning diversity scoring failed; continuing with failed evidence: $structuralOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_structural_reasoning_diversity.failed.log") -Append | Out-Null
}

$contextArgsList = @(
  $ContextGroundingScript,
  "--live-base-url", $MimTodBaseUrl,
  "--timeout", "60"
)
$contextOutput = Invoke-PythonCapture -Arguments $contextArgsList
$contextOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_context_grounding.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Context-grounding scoring failed; continuing with failed evidence: $contextOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_context_grounding.failed.log") -Append | Out-Null
}

$crossSurfaceArgsList = @(
  $CrossSurfaceScript,
  "--mimtod-base-url", $MimTodBaseUrl,
  "--agentmim-base-url", $AgentMimBaseUrl,
  "--studio-base-url", $StudioBaseUrl,
  "--timeout", "60"
)
if ($AgentMimEnvPath) {
  $crossSurfaceArgsList += @("--agentmim-env", $AgentMimEnvPath)
}
$crossSurfaceOutput = Invoke-PythonCapture -Arguments $crossSurfaceArgsList
$crossSurfaceOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_structural_reasoning_cross_surface.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Cross-surface structural reasoning scoring failed; continuing with failed evidence: $crossSurfaceOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_structural_reasoning_cross_surface.failed.log") -Append | Out-Null
}

$operatorScorecardOutput = Invoke-PythonCapture -Arguments @($OperatorImpactScorecardScript)
$operatorScorecardOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_scorecard.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Operator impact scorecard build failed; continuing with failed evidence: $operatorScorecardOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_scorecard.failed.log") -Append | Out-Null
}

if ($OperatorEstimatedHours -gt 0) {
  $argsList += @("--operator-estimated-hours", [string]$OperatorEstimatedHours)
}

$pythonOutput = Invoke-PythonCapture -Arguments $argsList
$pythonOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Scoreboard generation failed: $pythonOutput"
}

$operatorLiveOutput = Invoke-PythonCapture -Arguments $operatorLiveArgsList
$operatorLiveOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_live_10.after_scoreboard.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Operator impact live-10 scoring after scoreboard failed; publishing with failed evidence: $operatorLiveOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_live_10.failed.log") -Append | Out-Null
}
else {
  $missingOperatorLiveArtifacts = @($operatorLiveExpectedArtifacts | Where-Object { -not (Test-Path $_) })
  if (@($missingOperatorLiveArtifacts).Count -gt 0) {
    "Operator impact live-10 scoring after scoreboard exited successfully but did not write expected artifacts: $($missingOperatorLiveArtifacts -join ', ')" | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_live_10.failed.log") -Append | Out-Null
  }
}

$operatorScorecardOutput = Invoke-PythonCapture -Arguments @($OperatorImpactScorecardScript)
$operatorScorecardOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_scorecard.after_scoreboard.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Operator impact scorecard rebuild after scoreboard failed; continuing with failed evidence: $operatorScorecardOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_scorecard.failed.log") -Append | Out-Null
}
else {
  $operatorImpactScorecardPath = Join-Path $OutDir "MIM_OPERATOR_IMPACT_SCORECARD.latest.json"
  if (-not (Test-Path $operatorImpactScorecardPath)) {
    throw "Operator impact scorecard rebuild after scoreboard did not write $operatorImpactScorecardPath"
  }
  $operatorImpactScorecard = Get-Content $operatorImpactScorecardPath -Raw | ConvertFrom-Json
  $operatorImpactScore = [double]$operatorImpactScorecard.operator_impact_score
  $operatorImpactSamples = [int]$operatorImpactScorecard.sample_count
  if ($operatorImpactScore -lt 8 -or $operatorImpactSamples -lt 10) {
    "Operator impact scorecard after scoreboard is below publish target; publishing truthful action-required evidence: score=$operatorImpactScore samples=$operatorImpactSamples" | Tee-Object -FilePath (Join-Path $LogDir "mim_operator_impact_scorecard.failed.log") -Append | Out-Null
  }
}

$pythonOutput = Invoke-PythonCapture -Arguments $argsList
$pythonOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.after_operator_refresh.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Scoreboard regeneration after operator-impact refresh failed: $pythonOutput"
}

$dispositionSource = Join-Path $Root "runtime\shared\MIM_TOD_STALE_ARTIFACT_DISPOSITION.latest.json"
$dispositionTarget = Join-Path $OutDir "MIM_TOD_STALE_ARTIFACT_DISPOSITION.latest.json"
if ((-not (Test-Path $dispositionTarget)) -and (Test-Path $dispositionSource)) {
  Copy-Item -LiteralPath $dispositionSource -Destination $dispositionTarget -Force
}

$pulledReflectionDir = Join-Path $LogDir "mim_tod_reflection_pull"
foreach ($optionalPulledArtifact in @("TOD_PROACTIVE_TASK.latest.json", "TOD_PROACTIVE_AUTONOMY.latest.json")) {
  $pulledArtifactPath = Join-Path $pulledReflectionDir $optionalPulledArtifact
  $trainingArtifactPath = Join-Path $OutDir $optionalPulledArtifact
  if ((Test-Path $pulledArtifactPath) -and (-not (Test-Path $trainingArtifactPath))) {
    Copy-Item -LiteralPath $pulledArtifactPath -Destination $trainingArtifactPath -Force
  }
}

$realMovementOutput = Invoke-PythonCapture -Arguments @($RealMovementScript)
$realMovementOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_real_movement_scorecard.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  "Real movement scorecard build failed; continuing with failed evidence: $realMovementOutput" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_real_movement_scorecard.failed.log") -Append | Out-Null
}

$gateOutput = Invoke-PythonCapture -Arguments @($InitiativeGateScript, "--out-dir", $OutDir)
$gateOutput | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_initiative_gate.last.log") | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Training initiative gate generation failed: $gateOutput"
}

if ($SkipPublish) {
  return
}

if (-not $hostName -or -not $userName -or -not $password) {
  throw "Missing MIM_SSH_HOST, MIM_SSH_USER, or MIM_SSH_PASSWORD in .env"
}

$sec = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($userName, $sec)
$publishSftpSession = $null
$files = @(
  @{ Path = (Join-Path $OutDir "MIM_TOD_TRAINING_SCOREBOARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TOD_TRAINING_SCOREBOARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TOD_TRAINING_INITIATIVE_GATE.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TOD_TRAINING_INITIATIVE_GATE.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_DURABILITY_SMOKE_V2.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_DURABILITY_SMOKE_V2.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_OPERATOR_IMPACT_SCORECARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_OPERATOR_IMPACT_SCORECARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_OBJECTIVE.latest.json"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_OBJECTIVE.latest.md"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_SCORECARD.latest.json"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_SCORECARD.latest.md"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_NEXT_TASK.latest.json"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_INDEPENDENT_RESOLUTION_LADDER_V1_NEXT_TASK.latest.md"); Required = $false },
  @{ Path = (Join-Path $OutDir "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.md"); Required = $true },
  @{ Path = (Join-Path $OutDir "MIM_TOD_STALE_ARTIFACT_DISPOSITION.latest.json"); Required = $false },
  @{ Path = (Join-Path $Root "tod\out\context-sync\MIM_READY_TASK_DISPATCHER_STATUS.latest.json"); Required = $false },
  @{ Path = (Join-Path $Root "tod\out\context-sync\TOD_IDLE_TRAINING_STATUS.latest.json"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_PROACTIVE_TASK.latest.json"); Required = $false },
  @{ Path = (Join-Path $OutDir "TOD_PROACTIVE_AUTONOMY.latest.json"); Required = $false }
)
foreach ($fileSpec in $files) {
  $file = [string]$fileSpec.Path
  $required = [bool]$fileSpec.Required
  if (-not (Test-Path $file)) {
    $message = "Publish skipped for missing optional artifact ${file}"
    if ($required) {
      $message = "Publish failed for required artifact ${file}: local file missing"
    }
    $message | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.publish_failed.log") -Append | Out-Null
    continue
  }
  $published = $false
  $lastPublishError = ""
  for ($attempt = 1; $attempt -le 3 -and -not $published; $attempt++) {
    try {
      if ($null -eq $publishSftpSession) {
        $publishSftpSession = New-MimSftpSession -HostName $hostName -UserName $userName -Port ([int]$portValue) -Credential $cred
      }
      Copy-LocalFileToRemoteShared -Session $publishSftpSession -LocalPath $file -RemoteDir "/home/testpilot/mim/runtime/shared"
      $published = $true
    } catch {
      $lastPublishError = [string]::Join(" ", @($_.Exception.Message -split "\s+"))
      Close-MimSftpSession -Session $publishSftpSession
      $publishSftpSession = $null
      Start-Sleep -Seconds (3 * $attempt)
    }
  }
  if (-not $published) {
    "Publish failed for ${file}: $lastPublishError" | Tee-Object -FilePath (Join-Path $LogDir "mim_tod_training_scoreboard.publish_failed.log") -Append | Out-Null
  }
}
Close-MimSftpSession -Session $publishSftpSession
