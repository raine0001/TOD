Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$guardScript = Join-Path $repoRoot 'scripts/Invoke-TODAutonomyGuard.ps1'

function Import-AutonomyGuardFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($guardScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $guardScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $guardScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD autonomy guard task lookup' {
    BeforeAll {
        Import-AutonomyGuardFunction -Name 'Get-TaskInfoSafe'
    }

    BeforeEach {
        Remove-Item function:\Get-ScheduledTask -ErrorAction SilentlyContinue
        Remove-Item function:\Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
    }

    It 'keeps large scheduled task results without treating the task as missing' {
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
                LastRunTime = [datetime]'2026-04-20T04:18:57Z'
                NextRunTime = [datetime]'2026-04-20T04:33:56Z'
                LastTaskResult = 2147946720L
            }
        }

        $summary = Get-TaskInfoSafe -TaskName 'TOD-Autonomy-Guard'

        [bool]$summary.exists | Should Be $true
        [string]$summary.state | Should Be 'Running'
        [long]$summary.last_task_result | Should Be 2147946720
    }

    It 'still returns missing when scheduled task lookup fails' {
        function global:Get-ScheduledTask {
            param([string]$TaskName)

            throw 'task not found'
        }

        $summary = Get-TaskInfoSafe -TaskName 'TOD-Autonomy-Guard'

        [bool]$summary.exists | Should Be $false
        [string]$summary.state | Should Be 'missing'
        $summary.last_task_result | Should Be $null
    }
}