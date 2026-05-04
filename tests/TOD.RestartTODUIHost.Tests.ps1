Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Restart-TODUIHost.ps1'

function Import-RestartFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw 'Failed to parse ' + $scriptPath
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $scriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ('function\s+{0}\b' -f [regex]::Escape($Name)), ('function global:{0}' -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD UI restart readiness' {
    BeforeAll {
        Import-RestartFunction -Name 'Test-TodUiStartupDiagnosticReady'
    }

    It 'accepts a fresh startup diagnostic from the TOD proxy as ready state' {
        $diagnostic = [pscustomobject]@{
            ok = $true
            status = 'started'
            port = 8844
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            port_owner = [pscustomobject]@{
                in_use = $true
                is_tod_ui_process = $false
                is_tod_ui_proxy_process = $true
            }
        }

        $ready = Test-TodUiStartupDiagnosticReady -Diagnostic $diagnostic -ExpectedPort 8844 -NotBefore ((Get-Date).ToUniversalTime().AddMinutes(-1))

        $ready | Should Be $true
    }

    It 'rejects stale startup diagnostics' {
        $diagnostic = [pscustomobject]@{
            ok = $true
            status = 'started'
            port = 8844
            generated_at = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')
            port_owner = [pscustomobject]@{
                in_use = $true
                is_tod_ui_process = $false
                is_tod_ui_proxy_process = $true
            }
        }

        $ready = Test-TodUiStartupDiagnosticReady -Diagnostic $diagnostic -ExpectedPort 8844 -NotBefore ((Get-Date).ToUniversalTime().AddMinutes(-1))

        $ready | Should Be $false
    }
}