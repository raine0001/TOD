Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$syncScript = Join-Path $repoRoot "scripts/Invoke-TODSharedStateSync.ps1"

function Import-SyncFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($syncScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $syncScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $syncScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

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
    BeforeAll {
        Import-SyncFunction -Name 'Get-LocalPath'
        Import-SyncFunction -Name 'Get-JsonFileIfExists'
        Import-SyncFunction -Name 'Normalize-ObjectiveIdText'
        Import-SyncFunction -Name 'Get-BridgeCanonicalEvidence'
    }

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

        # Pass a non-existent listener request path so the live-task freshness
        # override does not suppress the stale detection we are testing here.
        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -MimStatusStaleAfterHours 1 -ContextSyncInboxPath "tod/inbox/context-sync/updates" -ListenerRequestPath (Join-Path $paths.Base "no_live_request.json")

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

    It "bridge evidence rejects same-objective live task when canonical task id differs" {
        $paths = New-TestRunPaths
        $runtimeShared = Join-Path $paths.Base 'runtime/shared'
        New-Item -ItemType Directory -Path $runtimeShared -Force | Out-Null

        $sharedTruthPath = Join-Path $runtimeShared 'TOD_MIM_SHARED_TRUTH.latest.json'
        [pscustomobject]@{
            objective_id = '2913'
            task_id = 'objective-2913-task-7144'
            request_id = 'objective-2913-task-7144'
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $sharedTruthPath

        $previousRepoRoot = $script:repoRoot
        try {
            $script:repoRoot = $paths.Base
            $evidence = Get-BridgeCanonicalEvidence -MimRefresh $null -MimHandshake $null -LiveTaskRequest ([pscustomobject]@{
                    available = $true
                    request_id = 'objective-2913-task-1777951503'
                    task_id = 'objective-2913-task-1777951503'
                    normalized_objective_id = '2913'
                    promotion_applied = $true
                }) -ObjectiveAlignment ([pscustomobject]@{
                    status = 'in_sync'
                    mim_objective_active = '2913'
                }) -TodStatusPublish ([pscustomobject]@{
                    status = 'uploaded'
                    mim_mirror_status = 'mirrored'
                    remote_access_status = 'full_access_granted'
                    consumer_status = 'executed'
                })
        }
        finally {
            $script:repoRoot = $previousRepoRoot
        }

        [bool]$evidence.canonical_refresh_satisfied | Should Be $false
        [bool]$evidence.live_bridge_publish_satisfied | Should Be $false
        [string]$evidence.canonical_task_id | Should Be 'objective-2913-task-7144'
        [string]$evidence.live_task_task_id | Should Be 'objective-2913-task-1777951503'
        @($evidence.failure_signals) | Should Contain 'live_task_request_task_mismatch'
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

    It "prefers fresher shared live task request over stale listener copy" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.MimShared -Force | Out-Null

        $contextDoc = [pscustomobject]@{
            source = 'mim-fresh'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            status = [pscustomobject]@{
                objective_active = 2504
                phase = 'execution'
                blockers = 'none'
            }
            schema_version = '2026-03-12-57'
        }
        $listenerRequest = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('o')
            request_id = 'objective-2489-task-6295-old'
            task_id = 'objective-2489-task-6295'
            objective_id = 'objective-2489'
            correlation_id = 'objective-2489-task-6295'
        }
        $sharedRequest = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            request_id = 'objective-2504-task-6325-new'
            task_id = 'objective-2504-task-6325'
            objective_id = 'objective-2504'
            correlation_id = 'objective-2504-task-6325'
        }

        $listenerRequestPath = Join-Path $paths.Base 'listener-request.json'
        $sharedJson = Join-Path $paths.MimShared 'MIM_CONTEXT_EXPORT.latest.json'
        $sharedRequestPath = Join-Path $paths.MimShared 'MIM_TOD_TASK_REQUEST.latest.json'

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedJson
        $listenerRequest | ConvertTo-Json -Depth 12 | Set-Content -Path $listenerRequestPath
        $sharedRequest | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedRequestPath

        $previousEnvRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
        try {
            $env:MIM_SHARED_EXPORT_ROOT = [string]$paths.MimShared
            $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -RefreshMimContextFromShared -ListenerRequestPath $listenerRequestPath -ContextSyncInboxPath 'tod/inbox/context-sync/updates'
        }
        finally {
            $env:MIM_SHARED_EXPORT_ROOT = $previousEnvRoot
        }

        $integrationPath = Join-Path $paths.SharedStateDir 'integration_status.json'
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        [string]$integration.live_task_request.source_path | Should Be ([string]$sharedRequestPath)
        [string]$integration.live_task_request.request_id | Should Be 'objective-2504-task-6325-new'
        [string]$integration.live_task_request.normalized_objective_id | Should Be '2504'
    }

    It "authority reset overrides invalidated handshake objective for alignment" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.MimShared -Force | Out-Null
        New-Item -ItemType Directory -Path $paths.SharedStateDir -Force | Out-Null

        $contextDoc = [pscustomobject]@{
            source = "mim-fresh"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 153
                phase = "active"
                blockers = "none"
            }
            schema_version = "2026-03-12-57"
        }
        $handshakeDoc = [pscustomobject]@{
            handshake_version = "mim-tod-shared-export-v1"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            truth = [pscustomobject]@{
                objective_active = "153"
                latest_completed_objective = "152"
                current_next_objective = "153"
                schema_version = "2026-03-12-67"
                release_tag = "objective-153"
                regression_status = "PASS"
                regression_tests = "66/66"
                prod_promotion_status = "SUCCESS"
                prod_smoke_status = "PASS"
                blockers = @()
            }
        }
        $authorityResetDoc = [pscustomobject]@{
            active = $true
            authoritative_current_objective = '152'
            max_valid_objective = '152'
            invalidated_objectives = @('153')
            reason = 'rollback'
        }

        $sharedJson = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.json"
        $sharedYaml = Join-Path $paths.MimShared "MIM_CONTEXT_EXPORT.latest.yaml"
        $sharedHandshake = Join-Path $paths.MimShared "MIM_TOD_HANDSHAKE_PACKET.latest.json"
        $authorityResetPath = Join-Path $paths.SharedStateDir 'objective_authority_reset.json'

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedJson
        "objective_active: 153" | Set-Content -Path $sharedYaml
        $handshakeDoc | ConvertTo-Json -Depth 20 | Set-Content -Path $sharedHandshake
        $authorityResetDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $authorityResetPath

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

        [string]$integration.objective_alignment.tod_current_objective | Should Be '152'
        [string]$integration.objective_alignment.mim_objective_active | Should Be '152'
        [string]$integration.objective_alignment.mim_objective_source | Should Be 'objective_authority_reset'
    }

    It "publish metadata records missing ssh password without attempting network" {
        $paths = New-TestRunPaths

        $contextDoc = [pscustomobject]@{
            source = "mim-test"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 17
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

        $missingDotEnv = Join-Path $paths.Base ".env.missing"
        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -PublishTodStatusToMimArm -MimArmSshHost "192.168.1.90" -MimArmSshUser "testpilot" -MimArmSshPort 22 -MimArmSshRemoteRoot "/home/testpilot/mim_arm/runtime/shared" -DotEnvPath $missingDotEnv -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $receiptPath = Join-Path $paths.SharedStateDir "TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json
        $receipt = Get-Content -Path $receiptPath -Raw | ConvertFrom-Json

        [string]$integration.tod_status_publish.status | Should Be "missing_ssh_password"
        [string]$integration.tod_status_publish.remote_primary_path | Should Be "/home/testpilot/mim_arm/runtime/shared/TOD_INTEGRATION_STATUS.latest.json"
        [string]$integration.tod_status_publish.remote_summary_path | Should Be "/home/testpilot/mim_arm/runtime/shared/TOD_AUTHORITY_SUMMARY.latest.json"
        [string]$receipt.status | Should Be "missing_ssh_password"
    }

    It "persists listener decision artifacts into integration status" {
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
        $decisionPath = Join-Path $paths.Base "TOD_MIM_EXECUTION_DECISION.latest.json"
        $decisionDoc = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            request_id = "objective-307-task-soft-boundary-001"
            task_id = "objective-307-task-soft-boundary-001"
            correlation_id = "objective-307-task-soft-boundary-001-corr"
            requested_objective_id = "objective-307"
            decision_outcome = "execute"
            reason_code = "authorized_routine_request"
            summary = "Synthetic listener executed authorized soft-boundary work without waiting on human start confirmation."
            boundary_class = "soft_boundary"
            ack_state = "accepted"
            execution_state = "completed"
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimManifest
        $decisionDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $decisionPath

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -ListenerDecisionPath $decisionPath -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json

        [bool]$integration.listener_decision.available | Should Be $true
        [string]$integration.listener_decision.request_id | Should Be "objective-307-task-soft-boundary-001"
        [string]$integration.listener_decision.normalized_objective_id | Should Be "307"
        [string]$integration.listener_decision.decision_outcome | Should Be "execute"
        [string]$integration.listener_decision.execution_state | Should Be "completed"
    }

    It "suppresses stale authority reset listener rejection when reset is inactive" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.SharedStateDir -Force | Out-Null

        $contextDoc = [pscustomobject]@{
            source = "mim-test"
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            status = [pscustomobject]@{
                objective_active = 720
                phase = "execution"
                blockers = "none"
            }
            schema_version = "2026-03-12-57"
        }
        $manifestDoc = [pscustomobject]@{
            source = "mim-test"
            schema_version = "2026-03-12-57"
            contract_version = "tod-mim-shared-contract-v1"
        }
        $decisionPath = Join-Path $paths.Base "TOD_MIM_EXECUTION_DECISION.latest.json"
        $authorityResetPath = Join-Path $paths.SharedStateDir 'objective_authority_reset.json'
        $decisionDoc = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            request_id = "objective-720-task-008"
            task_id = "objective-720-task-008"
            requested_objective_id = "objective-720"
            decision_outcome = "reject_with_specific_policy_reason"
            reason_code = "authority_reset_ceiling_exceeded"
            summary = "Request objective is invalidated by the current authority ceiling."
            boundary_class = "soft_boundary"
            ack_state = "not_acked"
            execution_state = "rejected"
            blocker_classification = "policy_rejection"
            next_step_recommendation = "refresh_authoritative_objective_then_reissue"
        }
        $authorityResetDoc = [pscustomobject]@{
            active = $false
            authoritative_current_objective = '216'
            max_valid_objective = '216'
            invalidated_objectives = @('720')
            reason = 'superseded'
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimManifest
        $decisionDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $decisionPath
        $authorityResetDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $authorityResetPath

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -ListenerDecisionPath $decisionPath -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $integrationPath = Join-Path $paths.SharedStateDir "integration_status.json"
        $nextActionsPath = Join-Path $paths.SharedStateDir "next_actions.json"
        $integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json
        $nextActions = Get-Content -Path $nextActionsPath -Raw | ConvertFrom-Json

        [string]$integration.listener_decision.decision_outcome | Should Be 'ignored_stale_listener_decision'
        [string]$integration.listener_decision.execution_state | Should Be 'ignored'
        [string]$integration.listener_decision.suppressed_reason | Should Be 'inactive_authority_reset'
        @($nextActions.blockers) | Should Not Contain 'listener rejected request (authority_reset_ceiling_exceeded)'
        @($nextActions.recommended_recovery_actions) | Should Not Contain 'Listener recommendation: refresh_authoritative_objective_then_reissue'
    }

    It "surfaces non-execute listener decisions as blockers and recovery guidance" {
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
        $decisionPath = Join-Path $paths.Base "TOD_MIM_EXECUTION_DECISION.latest.json"
        $decisionDoc = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString("o")
            request_id = "objective-401-task-dependency-001"
            task_id = "objective-401-task-dependency-001"
            correlation_id = "objective-401-task-dependency-001-corr"
            requested_objective_id = "objective-401"
            decision_outcome = "acknowledge_and_wait_on_dependency"
            reason_code = "await_external_dependency"
            summary = "Waiting on a prerequisite owned outside the active execution lane."
            boundary_class = "soft_boundary"
            ack_state = "acknowledged_waiting_dependency"
            execution_state = "waiting_on_dependency"
            blocker_classification = "external_coordination_blocker"
            next_step_recommendation = "Wait for dependency confirmation from MIM before retrying execution."
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimManifest
        $decisionDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $decisionPath

        $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -ListenerDecisionPath $decisionPath -ContextSyncInboxPath "tod/inbox/context-sync/updates"

        $nextActionsPath = Join-Path $paths.SharedStateDir "next_actions.json"
        $nextActions = Get-Content -Path $nextActionsPath -Raw | ConvertFrom-Json

        @(@($nextActions.blockers) | Where-Object { [string]$_ -match "listener waiting on dependency \(await_external_dependency\)" }).Count | Should Be 1
        @(@($nextActions.recommended_recovery_actions) | Where-Object { [string]$_ -eq "Listener recommendation: Wait for dependency confirmation from MIM before retrying execution." }).Count | Should Be 1
    }

    It "promotes the canonical MIM objective when listener objective_mismatch only reflects a stale local pin" {
        $paths = New-TestRunPaths
        New-Item -ItemType Directory -Path $paths.MimShared -Force | Out-Null

        $contextDoc = [pscustomobject]@{
            source = 'mim-test'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            status = [pscustomobject]@{
                objective_active = 2913
                phase = 'execution'
                blockers = 'none'
            }
            schema_version = '2026-03-12-57'
        }
        $manifestDoc = [pscustomobject]@{
            source = 'mim-test'
            schema_version = '2026-03-12-57'
            contract_version = 'tod-mim-shared-contract-v1'
        }
        $handshakeDoc = [pscustomobject]@{
            handshake_version = 'mim-tod-shared-export-v1'
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            truth = [pscustomobject]@{
                objective_active = '2913'
                latest_completed_objective = '2912'
                current_next_objective = '2913'
                schema_version = '2026-03-24-70'
                release_tag = 'objective-2913'
                regression_status = 'PASS'
                regression_tests = '66/66'
                prod_promotion_status = 'EXECUTED'
                prod_smoke_status = 'PASSED'
                blockers = @()
            }
        }
        $listenerRequest = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            request_id = 'objective-2913-task-7144'
            task_id = 'objective-2913-task-7144'
            objective_id = 'objective-2913'
            correlation_id = 'objective-2913-task-7144'
        }
        $decisionPath = Join-Path $paths.Base 'TOD_MIM_EXECUTION_DECISION.latest.json'
        $listenerRequestPath = Join-Path $paths.Base 'MIM_TOD_TASK_REQUEST.latest.json'
        $sharedHandshake = Join-Path $paths.MimShared 'MIM_TOD_HANDSHAKE_PACKET.latest.json'
        $decisionDoc = [pscustomobject]@{
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            request_id = 'objective-2913-task-7144'
            task_id = 'objective-2913-task-7144'
            correlation_id = 'objective-2913-task-7144'
            requested_objective_id = 'objective-2913'
            objective_id = '2913'
            normalized_objective_id = '2913'
            decision_outcome = 'reject_with_specific_policy_reason'
            reason_code = 'objective_mismatch'
            summary = 'Request objective does not match the current authoritative objective.'
            boundary_class = 'soft_boundary'
            ack_state = 'not_acked'
            execution_state = 'rejected'
            next_step_recommendation = 'publish_request_for_authoritative_objective'
        }

        $contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimContext
        $manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $paths.MimManifest
        $handshakeDoc | ConvertTo-Json -Depth 20 | Set-Content -Path $sharedHandshake
        $listenerRequest | ConvertTo-Json -Depth 12 | Set-Content -Path $listenerRequestPath
        $decisionDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $decisionPath

        $previousEnvRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
        try {
            $env:MIM_SHARED_EXPORT_ROOT = [string]$paths.MimShared
            $null = & $syncScript -SharedStateDir $paths.SharedStateDir -MimContextExportPath $paths.MimContext -MimManifestPath $paths.MimManifest -RefreshMimContextFromShared -ListenerRequestPath $listenerRequestPath -ListenerDecisionPath $decisionPath -ContextSyncInboxPath 'tod/inbox/context-sync/updates'
        }
        finally {
            $env:MIM_SHARED_EXPORT_ROOT = $previousEnvRoot
        }

        $integration = Get-Content -Path (Join-Path $paths.SharedStateDir 'integration_status.json') -Raw | ConvertFrom-Json
        $nextActions = Get-Content -Path (Join-Path $paths.SharedStateDir 'next_actions.json') -Raw | ConvertFrom-Json

        [string]$integration.objective_alignment.tod_current_objective | Should Be '2913'
        [string]$integration.objective_alignment.mim_objective_active | Should Be '2913'
        [string]$nextActions.current_objective_in_progress | Should Be '2913'
    }
}
