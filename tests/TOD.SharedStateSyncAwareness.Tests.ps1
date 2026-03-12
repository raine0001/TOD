Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$syncScript = Join-Path $repoRoot "scripts/Invoke-TODSharedStateSync.ps1"

function New-TestRunPaths {
    $id = [guid]::NewGuid().ToString("N")
    $base = Join-Path $repoRoot ("tod/out/tests/shared-state-sync-" + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    return [pscustomobject]@{
        Base = $base
        SharedStateDir = (Join-Path $base "shared_state")
        MimContext = (Join-Path $base "MIM_CONTEXT_EXPORT.latest.json")
        MimManifest = (Join-Path $base "MIM_MANIFEST.latest.json")
    }
}

Describe "TOD Shared State Sync Awareness" {
    It "integration status includes MIM freshness and objective alignment" {
        $paths = New-TestRunPaths

        $contextDoc = [pscustomobject]@{
            source = "mim-test"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 16
                phase = "active"
                blockers = "none"
            }
            schema_version = "2026-03-12-57"
        }
        $manifestDoc = [pscustomobject]@{
            source = "mim-test"
            schema_version = "2026-03-12-57"
            contract_version = "tod-mim-shared-contract-v1"
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimManifest

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        (Test-Path -Path $integrationPath) | Should Be $true
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        (($integration.PSObject.Properties.Name) -contains "mim_status") | Should Be $true
        (($integration.PSObject.Properties.Name) -contains "objective_alignment") | Should Be $true
        [bool]$integration.mim_status.available | Should Be $true
        (($integration.mim_status.PSObject.Properties.Name) -contains "is_stale") | Should Be $true
        (($integration.objective_alignment.PSObject.Properties.Name) -contains "status") | Should Be $true
    }

    It "stale MIM status and objective mismatch are surfaced as blockers" {
        $paths = New-TestRunPaths

        $oldTime = (Get-Date).ToUniversalTime().AddHours(-25).ToString("o")
        $contextDoc = [pscustomobject]@{
            source = "mim-test"
            generated_at = $oldTime
            status = [pscustomobject]@{
                objective_active = 71
                phase = "active"
                blockers = "none"
            }
            schema_version = "2026-03-12-57"
        }
        $manifestDoc = [pscustomobject]@{
            source = "mim-test"
            schema_version = "2026-03-12-57"
            contract_version = "tod-mim-shared-contract-v1"
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimManifest

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -MimStatusStaleAfterHours 1 -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $chatgptUpdatePath = Join-Path $paths.SharedStateDir "chatgpt_update.json"
        (Test-Path -Path $chatgptUpdatePath) | Should Be $true
        $chatgpt = Get-Content -Path $chatgptUpdatePath -Raw | ConvertFrom-Json

        @(@($chatgpt.blockers) | Where-Object { [string]$_ -match "mim status stale" }).Count | Should BeGreaterThan 0
        @(@($chatgpt.blockers) | Where-Object { [string]$_ -match "objective mismatch" }).Count | Should BeGreaterThan 0
    }
}
