Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

function Import-UiDriveFunction {
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

Describe 'TOD UI drive access helpers' {
    BeforeAll {
        Import-UiDriveFunction -Name 'Test-DriveAccessPathAllowed'
        Import-UiDriveFunction -Name 'Resolve-DriveAccessPath'
        Import-UiDriveFunction -Name 'Get-DriveAccessListingPayload'
    }

    It 'rejects paths outside the approved drive roots' {
        $testRoot = Join-Path $repoRoot ('tod/out/tests/drive-access-' + [guid]::NewGuid().ToString('N'))
        $allowedRoot = Join-Path $testRoot 'allowed'
        $blockedRoot = Join-Path $testRoot 'blocked'
        New-Item -ItemType Directory -Path $allowedRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $blockedRoot -Force | Out-Null

        $script:driveAccessRoots = @(
            [pscustomobject]@{ key = 'allowed'; label = 'Allowed'; path = $allowedRoot }
        )

        { Resolve-DriveAccessPath -RequestedPath $blockedRoot } | Should Throw 'outside the allowed drive-access roots'
    }

    It 'returns a directory listing for an approved root' {
        $testRoot = Join-Path $repoRoot ('tod/out/tests/drive-access-' + [guid]::NewGuid().ToString('N'))
        $allowedRoot = Join-Path $testRoot 'allowed'
        New-Item -ItemType Directory -Path $allowedRoot -Force | Out-Null
        Set-Content -Path (Join-Path $allowedRoot 'alpha.txt') -Value 'alpha'
        New-Item -ItemType Directory -Path (Join-Path $allowedRoot 'nested') -Force | Out-Null

        $script:driveAccessRoots = @(
            [pscustomobject]@{ key = 'allowed'; label = 'Allowed'; path = $allowedRoot }
        )

        $payload = Get-DriveAccessListingPayload -RequestedPath $allowedRoot -ActivePort 8844

        [bool]$payload.ok | Should Be $true
        [string]$payload.requested_path | Should Be ([System.IO.Path]::GetFullPath($allowedRoot))
        (@($payload.entries | Where-Object { $_.name -eq 'alpha.txt' })).Count | Should Be 1
        (@($payload.entries | Where-Object { $_.name -eq 'nested' -and $_.kind -eq 'directory' })).Count | Should Be 1
    }
}