Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $repoRoot 'scripts/TOD.ps1'
$configPath = Join-Path $repoRoot 'tod/config/tod-config.json'

function Invoke-TodStatelessActionFailure {
    param(
        [Parameter(Mandatory = $true)][string]$ActionName,
        [Parameter(Mandatory = $true)][string]$StatePath
    )

    try {
        & $todScript -Action $ActionName -ConfigPath $configPath -StatePath $StatePath 2>&1 | Out-String
    }
    catch {
        return [string]$_.Exception.Message
    }

    return ''
}

Describe 'TOD stateless action startup' {
    It 'safe_home does not require loading the operational state file at startup' {
        $missingStatePath = Join-Path $repoRoot ('tod/out/tests/missing-state-' + [guid]::NewGuid().ToString('N') + '.json')
        $message = Invoke-TodStatelessActionFailure -ActionName 'safe_home' -StatePath $missingStatePath

        $message | Should Not Match 'State file not found'
        $message | Should Not Match 'OutOfMemoryException'
    }

    It 'scan_pose does not require loading the operational state file at startup' {
        $missingStatePath = Join-Path $repoRoot ('tod/out/tests/missing-state-' + [guid]::NewGuid().ToString('N') + '.json')
        $message = Invoke-TodStatelessActionFailure -ActionName 'scan_pose' -StatePath $missingStatePath

        $message | Should Not Match 'State file not found'
        $message | Should Not Match 'OutOfMemoryException'
    }

    It 'ping-mim does not require loading the operational state file at startup' {
        $missingStatePath = Join-Path $repoRoot ('tod/out/tests/missing-state-' + [guid]::NewGuid().ToString('N') + '.json')
        $message = Invoke-TodStatelessActionFailure -ActionName 'ping-mim' -StatePath $missingStatePath

        $message | Should Not Match 'State file not found'
        $message | Should Not Match 'OutOfMemoryException'
    }
}