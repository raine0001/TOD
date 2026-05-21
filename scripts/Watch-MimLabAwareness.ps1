param(
    [string]$EnvFile = ".env",
    [int]$IntervalSeconds = 60,
    [string]$RemoteSharedDir = "/home/testpilot/mim/runtime/shared",
    [string]$LocalStatusPath = "runtime/shared/MIM_LAB_AWARENESS_MONITOR_STATUS.latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ConnectScript = Join-Path $RepoRoot "scripts/Connect-Mim.ps1"
$RequiredArtifacts = @(
    "MIM_LAB_AWARENESS_STATUS.latest.json",
    "MIM_LAB_SENSOR_INVENTORY.latest.json",
    "MIM_LAB_CAMERA_CYCLE_STATUS.latest.json",
    "MIM_HUMAN_INTERACTION_MEMORY.latest.json",
    "MIM_OBJECT_MEMORY_AND_INQUIRY.latest.json",
    "MIM_LAB_AWARENESS_EXECUTION_EVIDENCE.latest.json"
)

function Get-UtcNow {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Invoke-MimCommand {
    param([Parameter(Mandatory = $true)][string]$Command)
    & $ConnectScript -EnvFile $EnvFile -Command $Command
}

function ConvertFrom-MimJsonOutput {
    param([string[]]$Lines)
    $json = ($Lines | Where-Object { $_ -notmatch "^Connected to " }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($json)) { return $null }
    return $json | ConvertFrom-Json
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload
    )
    $fullPath = Join-Path $RepoRoot $Path
    $dir = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $tmp = "$fullPath.tmp"
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $fullPath -Force
}

function Publish-MonitorPrompt {
    param([Parameter(Mandatory = $true)]$Prompt)
    $json = $Prompt | ConvertTo-Json -Depth 20 -Compress
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $remotePath = "$RemoteSharedDir/MIM_LAB_AWARENESS_MONITOR_PROMPT.latest.json"
    Invoke-MimCommand -Command "printf '%s' '$b64' | base64 -d > $remotePath" | Out-Null
}

while ($true) {
    $now = Get-UtcNow
    try {
        $statusLines = Invoke-MimCommand -Command "cat $RemoteSharedDir/MIM_OPERATOR_STATUS.latest.json 2>/dev/null || printf '{}'"
        $operatorStatus = ConvertFrom-MimJsonOutput -Lines $statusLines
        if ($null -eq $operatorStatus) { $operatorStatus = [pscustomobject]@{} }

        $artifactCheck = ($RequiredArtifacts | ForEach-Object {
            "if [ -s '$RemoteSharedDir/$_' ]; then printf 'present $_\n'; else printf 'missing $_\n'; fi"
        }) -join "; "
        $artifactLines = Invoke-MimCommand -Command $artifactCheck
        $artifactStates = @{}
        foreach ($line in $artifactLines) {
            if ($line -match "^(present|missing)\s+(.+)$") {
                $artifactStates[$Matches[2]] = $Matches[1]
            }
        }
        $missing = @($RequiredArtifacts | Where-Object { $artifactStates[$_] -ne "present" })
        $complete = $missing.Count -eq 0

        $currentObjective = ""
        if ($operatorStatus.PSObject.Properties.Name -contains "current_objective_id") {
            $currentObjective = [string]$operatorStatus.current_objective_id
        }
        $currentPhase = ""
        if ($operatorStatus.PSObject.Properties.Name -contains "current_phase") {
            $currentPhase = [string]$operatorStatus.current_phase
        }
        $driftedToGrowth = $currentObjective -like "MIM-GROWTH-*"
        $falseCompletion = ($currentPhase -eq "completed" -and -not $complete)

        $monitorStatus = [ordered]@{
            packet_type = "mim-lab-awareness-monitor-status-v1"
            generated_at = $now
            objective_id = "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1"
            current_mim_objective = $currentObjective
            current_mim_phase = $currentPhase
            complete = $complete
            missing_required_artifacts = $missing
            drifted_to_growth = $driftedToGrowth
            false_completion = $falseCompletion
            next_monitor_action = "continue_monitoring"
        }
        Write-JsonFile -Path $LocalStatusPath -Payload $monitorStatus

        if (-not $complete -and ($driftedToGrowth -or $falseCompletion)) {
            $prompt = [ordered]@{
                packet_type = "mim-lab-awareness-monitor-prompt-v1"
                generated_at = $now
                owner = "TOD"
                target_owner = "MIM"
                objective_id = "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1"
                current_mim_objective = $currentObjective
                current_mim_phase = $currentPhase
                off_course_signal = if ($driftedToGrowth) { "growth_or_idle_preempted_unfinished_lab_objective" } else { "completion_claim_without_lab_evidence" }
                missing_required_artifacts = $missing
                required_resolution = "Return to the lab-awareness objective and publish MIM_LAB_AWARENESS_STATUS.latest.json plus MIM_LAB_SENSOR_INVENTORY.latest.json or blocked_with_inspection. Do not count growth, bridge health, or state-bus validation as lab success."
                tod_codex_boundary = "Monitor and guide only; do not implement camera, microphone, TTS, human memory, or object recognition work for MIM."
            }
            Publish-MonitorPrompt -Prompt $prompt
        }

        if ($complete) {
            break
        }
    }
    catch {
        $errorStatus = [ordered]@{
            packet_type = "mim-lab-awareness-monitor-status-v1"
            generated_at = $now
            objective_id = "MIM-LAB-AWARENESS-HUMAN-INTERACTION-V1"
            complete = $false
            monitor_error = $_.Exception.Message
            next_monitor_action = "retry"
        }
        Write-JsonFile -Path $LocalStatusPath -Payload $errorStatus
    }
    Start-Sleep -Seconds $IntervalSeconds
}
