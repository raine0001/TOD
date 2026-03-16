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
        MimContextYaml = (Join-Path $base "MIM_CONTEXT_EXPORT.latest.yaml")
        MimManifest = (Join-Path $base "MIM_MANIFEST.latest.json")
        MimShared = (Join-Path $base "runtime/shared")
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
        (($integration.mim_refresh.PSObject.Properties.Name) -contains "ssh_attempted") | Should Be $true
        [bool]$integration.mim_refresh.ssh_attempted | Should Be $false
    }

    It "stale MIM status is surfaced as blocker and objective alignment is recorded" {
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

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        (Test-Path -Path $integrationPath) | Should Be $true
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        @(@($chatgpt.blockers) | Where-Object { [string]$_ -match "mim status stale" }).Count | Should BeGreaterThan 0
        (@("mismatch", "unknown") -contains [string]$integration.objective_alignment.status) | Should Be $true
    }

    It "refresh from shared export updates local MIM context before sync" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.MimShared -Force | Out-Null

        $oldContext = [pscustomobject]@{
            source = "mim-old"
            generated_at = (Get-Date).ToUniversalTime().AddHours(-10).ToString("o")
            status = [pscustomobject]@{
                objective_active = 17
                phase = "warming"
                blockers = "pending approvals"
            }
            schema_version = "2026-03-12-57"
        }
        $freshContext = [pscustomobject]@{
            source = "mim-fresh"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 71
                phase = "active"
                blockers = "none"
            }
            schema_version = "2026-03-12-57"
        }
        $manifestDoc = [pscustomobject]@{
            source = "mim-fresh"
            schema_version = "2026-03-12-57"
            contract_version = "tod-mim-shared-contract-v1"
        }

        $sharedJson = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.json"
        $sharedYaml = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.yaml"
        $sharedManifest = Join-Path $paths.MimShared "MIM_MANIFEST.latest.json"

        $oldContext | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        "stale: true`nobjective_active: 17" | Set-Content -Path $paths.MimContextYaml
        $freshContext | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedJson
        "stale: false`nobjective_active: 71" | Set-Content -Path $sharedYaml
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedManifest

        $previousEnvRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
        try {
            $env:MIM_SHARED_EXPORT_ROOT = [string]$paths.MimShared
            $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimContextExportYamlPath $paths.MimContextYaml -MimManifestPath $paths.MimManifest -RefreshMimContextFromShared -ContextSyncInboxPath "tod/inbox/context-sync/updates"
        }
        finally {
            $env:MIM_SHARED_EXPORT_ROOT = $previousEnvRoot
        }

        $copiedContext = Get-Content -Path $paths.MimContext -Raw | ConvertFrom-Json
        [string]$copiedContext.source | Should Be "mim-fresh"
        [string]$copiedContext.status.objective_active | Should Be "71"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json
        [bool]$integration.mim_refresh.attempted | Should Be $true
        [bool]$integration.mim_refresh.copied_json | Should Be $true
        [bool]$integration.mim_refresh.copied_yaml | Should Be $true
        [bool]$integration.mim_refresh.copied_manifest | Should Be $true
        [string]$integration.mim_refresh.resolved_source_root | Should Be ([string]$paths.MimShared)
        @($integration.mim_refresh.candidate_paths_tried).Count | Should BeGreaterThan 0
        [string]$integration.mim_refresh.failure_reason | Should Be ""
        [string]$integration.mim_status.objective_active | Should Be "71"
    }

    It "refresh diagnostics report candidate paths and path-not-found when no source resolves" {
        $paths = New-TestRunPaths

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimContextExportYamlPath $paths.MimContextYaml -MimManifestPath $paths.MimManifest -RefreshMimContextFromShared -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        [bool]$integration.mim_refresh.attempted | Should Be $true
        [bool]$integration.mim_refresh.copied_json | Should Be $false
        [bool]$integration.mim_refresh.copied_yaml | Should Be $false
        [bool]$integration.mim_refresh.copied_manifest | Should Be $false
        [string]$integration.mim_refresh.failure_reason | Should Be "path_not_found"
        @($integration.mim_refresh.candidate_paths_tried).Count | Should BeGreaterThan 0
        [string]$integration.mim_refresh.resolved_source_root | Should Be ""
    }

    It "refresh succeeds with json and yaml when manifest is missing" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.MimShared -Force | Out-Null

        $freshContext = [pscustomobject]@{
            source = "mim-fresh"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 74
                phase = "active"
                blockers = "none"
            }
            schema_version = "2026-03-12-67"
        }

        $sharedJson = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.json"
        $sharedYaml = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.yaml"

        $freshContext | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedJson
        "objective_active: 74`ncurrent_next_objective: 75" | Set-Content -Path $sharedYaml

        $previousEnvRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
        try {
            $env:MIM_SHARED_EXPORT_ROOT = [string]$paths.MimShared
            $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimContextExportYamlPath $paths.MimContextYaml -MimManifestPath $paths.MimManifest -RefreshMimContextFromShared -ContextSyncInboxPath "tod/inbox/context-sync/updates"
        }
        finally {
            $env:MIM_SHARED_EXPORT_ROOT = $previousEnvRoot
        }

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        [bool]$integration.mim_refresh.attempted | Should Be $true
        [bool]$integration.mim_refresh.copied_json | Should Be $true
        [bool]$integration.mim_refresh.copied_yaml | Should Be $true
        [bool]$integration.mim_refresh.copied_manifest | Should Be $false
        [string]$integration.mim_refresh.failure_reason | Should Be ""
    }

    It "top-level MIM export fields populate mim_status when status object is absent" {
        $paths = New-TestRunPaths

        $contextDoc = [pscustomobject]@{
            source = "mim-top-level"
            exported_at = (Get-Date).ToUniversalTime().ToString("o")
            objective_active = 74
            phase = "active"
            blockers = @()
            schema_version = "2026-03-12-67"
            release_tag = "objective-74"
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        [string]$integration.mim_status.objective_active | Should Be "74"
        [string]$integration.mim_status.phase | Should Be "active"
        [string]$integration.mim_status.generated_at | Should Be ([string]$contextDoc.exported_at)
    }

    It "handshake packet truth is persisted and preferred for objective alignment" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.MimShared -Force | Out-Null

        $contextDoc = [pscustomobject]@{
            source = "mim-fresh"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 17
                phase = "active"
                blockers = "none"
            }
            schema_version = "2026-03-12-57"
        }
        $handshakeDoc = [pscustomobject]@{
            handshake_version = "mim-tod-shared-export-v1"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            truth = [pscustomobject]@{
                objective_active = "74"
                latest_completed_objective = "74"
                current_next_objective = "75"
                schema_version = "2026-03-12-67"
                release_tag = "objective-74"
                regression_status = "PASS"
                regression_tests = "66/66"
                prod_promotion_status = "SUCCESS"
                prod_smoke_status = "PASS"
                blockers = @()
            }
        }

        $sharedJson = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.json"
        $sharedYaml = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.yaml"
        $sharedHandshake = Join-Path $paths.MimShared "MIM_TOD_HANDSHAKE_PACKET.latest.json"

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedJson
        "objective_active: 17" | Set-Content -Path $sharedYaml
        $handshakeDoc | ConvertTo-Json -Depth 20 | Set-Content -Path $sharedHandshake

        $previousEnvRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
        try {
            $env:MIM_SHARED_EXPORT_ROOT = [string]$paths.MimShared
            $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimContextExportYamlPath $paths.MimContextYaml -MimManifestPath $paths.MimManifest -RefreshMimContextFromShared -ContextSyncInboxPath "tod/inbox/context-sync/updates"
        }
        finally {
            $env:MIM_SHARED_EXPORT_ROOT = $previousEnvRoot
        }

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        [bool]$integration.mim_handshake.available | Should Be $true
        [string]$integration.mim_handshake.objective_active | Should Be "74"
        [string]$integration.mim_handshake.current_next_objective | Should Be "75"
        [string]$integration.objective_alignment.mim_objective_active | Should Be "74"
        [string]$integration.objective_alignment.mim_objective_source | Should Be "handshake_packet"
    }
}
