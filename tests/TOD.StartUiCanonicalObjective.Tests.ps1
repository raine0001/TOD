Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

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

Describe 'TOD UI canonical objective source' {
    BeforeAll {
        Import-UiFunction -Name 'Read-JsonFileIfExists'
        Import-UiFunction -Name 'Normalize-ObjectiveIdValue'
        Import-UiFunction -Name 'Get-CanonicalMimObjective'
    }

    It 'prefers integration status alignment over stale handshake export fields' {
        $testRoot = Join-Path $repoRoot ('tod/out/tests/ui-canonical-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        $script:integrationStatusPath = Join-Path $testRoot 'integration_status.json'
        $script:mimExportCanonicalPath = Join-Path $testRoot 'MIM_CONTEXT_EXPORT.latest.json'
        $script:mimExportFallbackPath = Join-Path $testRoot 'MIM_CONTEXT_EXPORT.fallback.json'
        $script:mimHandshakeCanonicalPath = Join-Path $testRoot 'MIM_TOD_HANDSHAKE_PACKET.latest.json'
        $script:mimHandshakeFallbackPath = Join-Path $testRoot 'MIM_TOD_HANDSHAKE_PACKET.fallback.json'

        [pscustomobject]@{
            objective_alignment = [pscustomobject]@{
                mim_objective_active = '152'
            }
            objective_authority_reset = [pscustomobject]@{
                active = $true
                authoritative_current_objective = '152'
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:integrationStatusPath

        [pscustomobject]@{
            objective_active = '153'
            current_next_objective = '153'
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:mimExportCanonicalPath

        [pscustomobject]@{
            objective_active = '153'
            current_next_objective = '153'
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:mimHandshakeCanonicalPath

        $canonical = Get-CanonicalMimObjective

        [bool]$canonical.available | Should Be $true
        [string]$canonical.objective_id | Should Be '152'
        [string]$canonical.source | Should Be 'integration_status'
    }

    It 'falls back to authority reset when alignment is missing' {
        $testRoot = Join-Path $repoRoot ('tod/out/tests/ui-canonical-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        $script:integrationStatusPath = Join-Path $testRoot 'integration_status.json'
        $script:mimExportCanonicalPath = Join-Path $testRoot 'MIM_CONTEXT_EXPORT.latest.json'
        $script:mimExportFallbackPath = Join-Path $testRoot 'MIM_CONTEXT_EXPORT.fallback.json'
        $script:mimHandshakeCanonicalPath = Join-Path $testRoot 'MIM_TOD_HANDSHAKE_PACKET.latest.json'
        $script:mimHandshakeFallbackPath = Join-Path $testRoot 'MIM_TOD_HANDSHAKE_PACKET.fallback.json'

        [pscustomobject]@{
            objective_authority_reset = [pscustomobject]@{
                active = $true
                authoritative_current_objective = '152'
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:integrationStatusPath

        $canonical = Get-CanonicalMimObjective

        [bool]$canonical.available | Should Be $true
        [string]$canonical.objective_id | Should Be '152'
        [string]$canonical.source | Should Be 'integration_status_authority_reset'
    }
}