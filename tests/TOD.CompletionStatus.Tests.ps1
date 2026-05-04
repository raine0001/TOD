Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$statusScript = Join-Path $repoRoot 'scripts/Write-TODCompletionStatus.ps1'

function Import-CompletionStatusFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($statusScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $statusScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $statusScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD completion status task summary' {
    BeforeAll {
        Import-CompletionStatusFunction -Name 'Get-TaskSummary'
        Import-CompletionStatusFunction -Name 'Get-EffectiveBlockers'
    }

    BeforeEach {
        Remove-Item function:\Get-ScheduledTask -ErrorAction SilentlyContinue
        Remove-Item function:\Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    }

    It 'keeps daemon tasks with large last task results instead of classifying them as missing' {
        function global:Get-ScheduledTask {
            param([string]$TaskName)

            return [pscustomobject]@{
                TaskName = $TaskName
                State = 'Running'
            }
        }

        function global:Get-ScheduledTaskInfo {
            param($Task)

            return [pscustomobject]@{
                LastRunTime = [datetime]'2026-04-20T03:47:25Z'
                NextRunTime = $null
                LastTaskResult = 2147946720L
            }
        }

        $summary = Get-TaskSummary -TaskName 'TOD-AutonomousTraining-IdleDaemon'

        [bool]$summary.exists | Should Be $true
        [string]$summary.state | Should Be 'Running'
        [long]$summary.last_task_result | Should Be 2147946720
    }

    It 'still reports missing when the scheduled task lookup fails' {
        function global:Get-ScheduledTask {
            param([string]$TaskName)

            throw 'task not found'
        }

        $summary = Get-TaskSummary -TaskName 'TOD-AutonomousTraining-IdleDaemon'

        [bool]$summary.exists | Should Be $false
        [string]$summary.state | Should Be 'missing'
        $summary.last_task_result | Should Be $null
    }

    It 'merges public route health blockers into the emitted blocker list' {
        $effective = Get-EffectiveBlockers -ExplicitBlockers @('daemon_ok') -PublicRouteHealth ([pscustomobject]@{ blockers = @('public_tod_wrong_surface:authority_console', 'public_tod_quick_facts_mismatch:153->152') })

        ((@($effective) -contains 'daemon_ok')) | Should Be $true
        ((@($effective) -contains 'public_tod_wrong_surface:authority_console')) | Should Be $true
        ((@($effective) -contains 'public_tod_quick_facts_mismatch:153->152')) | Should Be $true
    }

    It 'embeds live training status and derives current_tod_state as training when a run is active' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/completion-status-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null

            $daemonStatePath = Join-Path $fixture 'daemon-state.json'
            $trainingStatusPath = Join-Path $fixture 'training-status.json'
            $outputPath = Join-Path $fixture 'tod-autonomy-status.json'
            $publicRouteHealthPath = Join-Path $fixture 'public-route-health.json'

            [pscustomobject]@{
                updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
                last_status = 'critical_recovery_ok'
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $daemonStatePath

            [pscustomobject]@{
                source = 'tod-training-status-v1'
                state = 'running'
                state_label = 'TRAINING ACTIVE'
                active = $true
                percent_complete = 42
                phase = 'runtime_safe_subset'
                runtime_seconds = 600
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $trainingStatusPath

            [pscustomobject]@{ blockers = @() } | ConvertTo-Json -Depth 4 | Set-Content -Path $publicRouteHealthPath

            $result = & $statusScript -DaemonStatePath $daemonStatePath -TrainingStatusPath $trainingStatusPath -OutputPath $outputPath -PublicRouteHealthPath $publicRouteHealthPath -EmitJson | ConvertFrom-Json

            [string]$result.current_tod_state | Should Be 'training'
            $result.training_status | Should Not BeNullOrEmpty
            [bool]$result.training_status.active | Should Be $true
            [int]$result.training_status.percent_complete | Should Be 42
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}