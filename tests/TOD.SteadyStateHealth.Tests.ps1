Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

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
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

function Remove-TestFixturePath {
    param([string]$PathValue)

    if (-not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -Path $PathValue)) {
        Remove-Item -Path $PathValue -Recurse -Force
    }
}

function Import-UiFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($uiScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $uiScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $uiScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Read-JsonFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Get-IsoAgeSeconds {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return -1
    }

    try {
        $timestamp = [DateTime]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return [int][Math]::Floor(((Get-Date).ToUniversalTime() - $timestamp.ToUniversalTime()).TotalSeconds)
    }
    catch {
        return -1
    }
}

$script:BridgeStatusStubResult = [pscustomobject]@{ available = $false; status = 'unknown' }
function Get-BridgeStatus {
    return $script:BridgeStatusStubResult
}

Describe 'TOD steady-state health hardening' {
    BeforeAll {
        Import-UiFunction -Name 'Get-RecoveryWatchdogStatus'
        Import-UiFunction -Name 'Get-SteadyStateHealth'
    }

    It 'preserves bridge_smoke when adapting recovery watchdog state' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/ui-health-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:recoveryWatchdogStatePath = Join-Path $fixture 'watchdog.json'
            $script:listenerStatePath = Join-Path $fixture 'listener_state.json'
            $script:listenerRequestPath = Join-Path $fixture 'task_request.json'
            $script:listenerResultPath = Join-Path $fixture 'task_result.json'

            $now = (Get-Date).ToUniversalTime()
            Write-JsonNoBom -PathValue $script:recoveryWatchdogStatePath -Payload ([pscustomobject]@{
                state = 'healthy'
                task_state = 'idle'
                progress_classification = 'no_progress_but_heartbeats_present'
                bridge_smoke = [pscustomobject]@{
                    passed = $true
                    classification = 'pass'
                }
            })
            Write-JsonNoBom -PathValue $script:listenerStatePath -Payload ([pscustomobject]@{ last_cycle_at = $now.AddSeconds(-10).ToString('o') })
            Write-JsonNoBom -PathValue $script:listenerRequestPath -Payload ([pscustomobject]@{ generated_at = $now.AddSeconds(-8).ToString('o') })
            Write-JsonNoBom -PathValue $script:listenerResultPath -Payload ([pscustomobject]@{ generated_at = $now.AddSeconds(-6).ToString('o') })

            $status = Get-RecoveryWatchdogStatus

            [bool]$status.available | Should Be $true
            [string]$status.state | Should Be 'healthy'
            $status.bridge_smoke | Should Not BeNullOrEmpty
            [bool]$status.bridge_smoke.passed | Should Be $true
            [string]$status.bridge_smoke.classification | Should Be 'pass'
        }
        finally {
            Remove-TestFixturePath -PathValue $fixture
        }
    }

    It 'supersedes stale regression failures when watchdog bridge_smoke is healthy even if transient bridge diagnostics are noisy' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/ui-health-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:currentBuildStatePath = Join-Path $fixture 'current_build.json'
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:regressionStallStatePath = Join-Path $fixture 'stall.json'
            $script:BridgeStatusStubResult = [pscustomobject]@{ available = $true; status = 'warning' }

            Write-JsonNoBom -PathValue $script:currentBuildStatePath -Payload ([pscustomobject]@{
                last_regression_result = [pscustomobject]@{
                    passed = 12
                    failed = 1
                    total = 13
                    generated_at = (Get-Date).ToUniversalTime().AddHours(-2).ToString('o')
                }
            })

            $recoveryWatchdog = [pscustomobject]@{
                state = 'healthy'
                effective_state = 'healthy'
                heartbeat_age_seconds = 12
                bridge_smoke = [pscustomobject]@{
                    passed = $true
                    classification = 'pass'
                }
            }
            $cadenceHealth = [pscustomobject]@{
                governance = [pscustomobject]@{
                    adjusted_severity = 'ok'
                    noise_suppressed = $false
                }
                stream = [pscustomobject]@{
                    loop_idle_sec = 12
                }
            }

            $result = Get-SteadyStateHealth -ListenerActivity $null -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -StateWarning '' -UsingListenerOnly $false

            [string]$result.status | Should Be 'ok'
            [bool]$result.regression_report_stale | Should Be $true
            [string]$result.summary | Should Match 'current bridge, cadence, and watchdog telemetry are healthy'
        }
        finally {
            Remove-TestFixturePath -PathValue $fixture
        }
    }

    It 'does not supersede stale regression failures when watchdog bridge_smoke is failed even if fallback bridge diagnostics are ok' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/ui-health-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:currentBuildStatePath = Join-Path $fixture 'current_build.json'
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:regressionStallStatePath = Join-Path $fixture 'stall.json'
            $script:BridgeStatusStubResult = [pscustomobject]@{ available = $true; status = 'ok' }

            Write-JsonNoBom -PathValue $script:currentBuildStatePath -Payload ([pscustomobject]@{
                last_regression_result = [pscustomobject]@{
                    passed = 12
                    failed = 1
                    total = 13
                    generated_at = (Get-Date).ToUniversalTime().AddHours(-2).ToString('o')
                }
            })

            $recoveryWatchdog = [pscustomobject]@{
                state = 'healthy'
                effective_state = 'healthy'
                heartbeat_age_seconds = 12
                bridge_smoke = [pscustomobject]@{
                    passed = $false
                    classification = 'listener_contract_stalled'
                }
            }
            $cadenceHealth = [pscustomobject]@{
                governance = [pscustomobject]@{
                    adjusted_severity = 'ok'
                    noise_suppressed = $false
                }
                stream = [pscustomobject]@{
                    loop_idle_sec = 12
                }
            }

            $result = Get-SteadyStateHealth -ListenerActivity $null -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -StateWarning '' -UsingListenerOnly $false

            [string]$result.status | Should Be 'critical'
            [bool]$result.regression_report_stale | Should Be $false
            [string]$result.summary | Should Be 'Regression failures remain; system is not in steady state.'
        }
        finally {
            Remove-TestFixturePath -PathValue $fixture
        }
    }

    It 'clears stale coordination and stall residue after a newer listener request completes successfully' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/ui-health-' + [guid]::NewGuid().ToString('N'))
        try {
            $script:currentBuildStatePath = Join-Path $fixture 'current_build.json'
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:regressionStallStatePath = Join-Path $fixture 'stall.json'
            $script:BridgeStatusStubResult = [pscustomobject]@{ available = $true; status = 'warning' }

            Write-JsonNoBom -PathValue $script:currentBuildStatePath -Payload ([pscustomobject]@{
                last_regression_result = [pscustomobject]@{
                    passed = 148
                    failed = 1
                    total = 149
                    generated_at = (Get-Date).ToUniversalTime().AddHours(-3).ToString('o')
                }
            })
            Write-JsonNoBom -PathValue $script:coordinationEscalationPath -Payload ([pscustomobject]@{
                pending_request_id = 'objective-109-task-mim-arm-scan-pose-20260406190341'
                last_ack_status = 'pending'
            })
            Write-JsonNoBom -PathValue $script:regressionStallStatePath -Payload ([pscustomobject]@{
                last_request_id = 'objective-109-task-mim-arm-safe-home-20260406191850'
                unchanged_cycles = 2
            })

            $listenerActivity = [pscustomobject]@{
                latest_request_id = 'objective-109-task-mim-arm-safe-home-20260406191850'
                latest_execution_status = 'already_processed'
                latest_cycle_classification = 'duplicate_seen'
                result_status = 'succeeded'
            }
            $recoveryWatchdog = [pscustomobject]@{
                state = 'healthy'
                effective_state = 'healthy'
                heartbeat_age_seconds = 18
                bridge_smoke = [pscustomobject]@{
                    passed = $true
                    classification = 'pass'
                }
            }
            $cadenceHealth = [pscustomobject]@{
                governance = [pscustomobject]@{
                    adjusted_severity = 'ok'
                    noise_suppressed = $false
                }
                stream = [pscustomobject]@{
                    loop_idle_sec = 45
                }
            }

            $result = Get-SteadyStateHealth -ListenerActivity $listenerActivity -RecoveryWatchdog $recoveryWatchdog -CadenceHealth $cadenceHealth -StateWarning 'state.json too large; using listener telemetry' -UsingListenerOnly $true

            [string]$result.status | Should Be 'ok'
            [bool]$result.regression_report_stale | Should Be $true
            [bool]$result.pending_coordination | Should Be $false
            [int]$result.unchanged_cycles | Should Be 0
            [bool]$result.listener_terminal | Should Be $true
        }
        finally {
            Remove-TestFixturePath -PathValue $fixture
        }
    }
}