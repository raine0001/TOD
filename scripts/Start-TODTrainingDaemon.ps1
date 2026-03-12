param(
    [string]$ConfigPath,
    [int]$Top = 20,
    [int]$IntervalSeconds = 300,
    [int]$IdleCadenceMinutes = 30,
    [int]$FullCadenceHours = 24,
    [switch]$NoIdleGate,
    [switch]$RunOnce
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$trainingScript = Join-Path $PSScriptRoot "Invoke-TODTrainingLoop.ps1"
$outDir = Join-Path $repoRoot "tod/out/training"
$statePath = Join-Path $outDir "training-daemon-state.json"
$lockPath = Join-Path $outDir "training-daemon.lock"
$logPath = Join-Path $outDir "training-daemon.log"

if (-not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$effectiveConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    if ([System.IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath } else { Join-Path $repoRoot $ConfigPath }
}

if (-not (Test-Path -Path $todScript)) {
    throw "Missing TOD script: $todScript"
}
if (-not (Test-Path -Path $trainingScript)) {
    throw "Missing training script: $trainingScript"
}
if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw "Missing config file: $effectiveConfigPath"
}

function Write-DaemonLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = "[{0}] {1}" -f ((Get-Date).ToUniversalTime().ToString("o")), $Message
    Add-Content -Path $logPath -Value $line
    Write-Host $line
}

function Get-DaemonState {
    if (-not (Test-Path -Path $statePath)) {
        return [pscustomobject]@{
            last_full_run_utc = ""
            last_idle_run_utc = ""
            last_status = "never"
            updated_at_utc = ""
        }
    }

    try {
        return (Get-Content -Path $statePath -Raw | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            last_full_run_utc = ""
            last_idle_run_utc = ""
            last_status = "corrupt_state"
            updated_at_utc = ""
        }
    }
}

function Save-DaemonState {
    param([Parameter(Mandatory = $true)]$State)

    $State.updated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    $State | ConvertTo-Json -Depth 8 | Set-Content -Path $statePath
}

function Acquire-Lock {
    if (Test-Path -Path $lockPath) {
        return $false
    }

    Set-Content -Path $lockPath -Value ((Get-Date).ToUniversalTime().ToString("o"))
    return $true
}

function Release-Lock {
    if (Test-Path -Path $lockPath) {
        Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-StateBus {
    try {
        $raw = & $todScript -Action "get-state-bus" -ConfigPath $effectiveConfigPath -Top $Top
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-DaemonLog "state-bus query failed: $($_.Exception.Message)"
        return $null
    }
}

function Test-IsIdle {
    param($Bus)

    if ($NoIdleGate) {
        return $true
    }

    if ($null -eq $Bus -or -not $Bus.PSObject.Properties["system_posture"]) {
        return $false
    }

    $posture = $Bus.system_posture
    $activeExecutions = if ($posture.PSObject.Properties["active_execution_count"]) { [int]$posture.active_execution_count } else { 1 }
    $pendingConfirmations = if ($posture.PSObject.Properties["pending_confirmations"]) { [int]$posture.pending_confirmations } else { 1 }
    $agentState = if ($posture.PSObject.Properties["agent_state"]) { [string]$posture.agent_state } else { "busy" }

    return ($activeExecutions -eq 0 -and $pendingConfirmations -eq 0 -and $agentState -ne "busy")
}

function Invoke-Training {
    param([Parameter(Mandatory = $true)][ValidateSet("full", "idle")][string]$Mode)

    $params = @{
        ConfigPath = $effectiveConfigPath
        Top = $Top
    }

    if ($Mode -eq "idle") {
        $params.SkipTests = $true
        $params.SkipSmoke = $true
    }

    $raw = & $trainingScript @params
    return ($raw | ConvertFrom-Json)
}

function Get-ElapsedHours {
    param([string]$WhenUtc)
    if ([string]::IsNullOrWhiteSpace($WhenUtc)) { return [double]::PositiveInfinity }
    try {
        $then = [datetime]::Parse($WhenUtc).ToUniversalTime()
        return ((Get-Date).ToUniversalTime() - $then).TotalHours
    }
    catch {
        return [double]::PositiveInfinity
    }
}

function Get-ElapsedMinutes {
    param([string]$WhenUtc)
    if ([string]::IsNullOrWhiteSpace($WhenUtc)) { return [double]::PositiveInfinity }
    try {
        $then = [datetime]::Parse($WhenUtc).ToUniversalTime()
        return ((Get-Date).ToUniversalTime() - $then).TotalMinutes
    }
    catch {
        return [double]::PositiveInfinity
    }
}

Write-DaemonLog "training daemon started (interval=${IntervalSeconds}s idle_cadence=${IdleCadenceMinutes}m full_cadence=${FullCadenceHours}h)"

try {
    while ($true) {
        $state = Get-DaemonState
        $bus = Get-StateBus
        $isIdle = Test-IsIdle -Bus $bus

        $hoursSinceFull = Get-ElapsedHours -WhenUtc $state.last_full_run_utc
        $minutesSinceIdle = Get-ElapsedMinutes -WhenUtc $state.last_idle_run_utc

        $shouldRunFull = ($hoursSinceFull -ge $FullCadenceHours)
        $shouldRunIdle = ($isIdle -and $minutesSinceIdle -ge $IdleCadenceMinutes)

        if ($shouldRunFull -or $shouldRunIdle) {
            if (-not (Acquire-Lock)) {
                Write-DaemonLog "skipping run (lock held)"
            }
            else {
                try {
                    if ($shouldRunFull) {
                        Write-DaemonLog "running FULL training cycle"
                        $result = Invoke-Training -Mode "full"
                        $state.last_full_run_utc = (Get-Date).ToUniversalTime().ToString("o")
                        $state.last_status = if ($result.ok) { "full_ok" } else { "full_error" }
                        Write-DaemonLog ("full training complete ok={0} resources={1}" -f [bool]$result.ok, [int]$result.resources_count)
                    }
                    elseif ($shouldRunIdle) {
                        Write-DaemonLog "running IDLE training cycle"
                        $result = Invoke-Training -Mode "idle"
                        $state.last_idle_run_utc = (Get-Date).ToUniversalTime().ToString("o")
                        $state.last_status = if ($result.ok) { "idle_ok" } else { "idle_error" }
                        Write-DaemonLog ("idle training complete ok={0} resources={1}" -f [bool]$result.ok, [int]$result.resources_count)
                    }
                }
                catch {
                    $state.last_status = "run_exception"
                    Write-DaemonLog "training run failed: $($_.Exception.Message)"
                }
                finally {
                    Save-DaemonState -State $state
                    Release-Lock
                }
            }
        }
        else {
            $fullIn = if ([double]::IsInfinity($hoursSinceFull)) { 0.0 } else { [math]::Max(0.0, ([double]$FullCadenceHours - $hoursSinceFull)) }
            $idleIn = if ([double]::IsInfinity($minutesSinceIdle)) { 0.0 } else { [math]::Max(0.0, ([double]$IdleCadenceMinutes - $minutesSinceIdle)) }
            Write-DaemonLog ("no run (idle={0} full_in={1:n1}h idle_in={2:n1}m)" -f $isIdle, $fullIn, $idleIn)
        }

        if ($RunOnce) {
            break
        }

        Start-Sleep -Seconds $IntervalSeconds
    }
}
finally {
    Release-Lock
    Write-DaemonLog "training daemon stopped"
}
