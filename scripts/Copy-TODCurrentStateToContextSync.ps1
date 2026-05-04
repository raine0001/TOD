param(
    [string]$DestinationRoot = "tod/out/context-sync"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path $repoRoot $PathValue)
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Get-FileHashSafe {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    try {
        return [string](Get-FileHash -Path $PathValue -Algorithm SHA256).Hash
    }
    catch {
        return ''
    }
}

$resolvedDestinationRoot = Resolve-RepoPath -PathValue $DestinationRoot
Ensure-Directory -PathValue $resolvedDestinationRoot

$entries = @(
    [pscustomobject]@{ source = 'shared_state/integration_status.json'; target = 'TOD_MIM_INTEGRATION_STATUS.latest.json'; category = 'state'; summary = 'Current unified integration state.' },
    [pscustomobject]@{ source = 'shared_state/next_actions.json'; target = 'TOD_MIM_NEXT_ACTIONS.latest.json'; category = 'state'; summary = 'Current objective, next objective, and required verification.' },
    [pscustomobject]@{ source = 'shared_state/current_build_state.json'; target = 'TOD_MIM_CURRENT_BUILD_STATE.latest.json'; category = 'state'; summary = 'Current build and execution summary.' },
    [pscustomobject]@{ source = 'shared_state/objectives.json'; target = 'TOD_MIM_OBJECTIVES.latest.json'; category = 'state'; summary = 'Current objective ledger snapshot.' },
    [pscustomobject]@{ source = 'shared_state/latest_summary.md'; target = 'TOD_MIM_LATEST_SUMMARY.latest.md'; category = 'state'; summary = 'Latest human-readable summary.' },
    [pscustomobject]@{ source = 'docs/mim-console-task-rule-card-v1.md'; target = 'MIM_CONSOLE_TASK_RULE_CARD.latest.md'; category = 'operator'; summary = 'Short operator-facing task rule card for the MIM Console.' },
    [pscustomobject]@{ source = 'shared_state/TOD_MIM_CONTRACT_ACCEPTANCE.latest.json'; target = 'TOD_MIM_CONTRACT_ACCEPTANCE.latest.json'; category = 'contract'; summary = 'TOD-side contract acceptance status.' },
    [pscustomobject]@{ source = 'shared_state/TOD_MIM_CONTRACT_FORMAL_AGREEMENT.latest.json'; target = 'TOD_MIM_CONTRACT_FORMAL_AGREEMENT.latest.json'; category = 'contract'; summary = 'Formal contract agreement state across TOD and MIM.' },
    [pscustomobject]@{ source = 'shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json'; target = 'TOD_MIM_BRIDGE_SMOKE.latest.json'; category = 'bridge'; summary = 'Latest bridge smoke evidence.' },
    [pscustomobject]@{ source = 'shared_state/TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json'; target = 'TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json'; category = 'bridge'; summary = 'Remote boundary and authority diagnostics.' },
    [pscustomobject]@{ source = 'shared_state/TOD_MIM_ARM_AUTHORITY_SMOKE.latest.json'; target = 'TOD_MIM_ARM_AUTHORITY_SMOKE.latest.json'; category = 'arm'; summary = 'MIM ARM authority smoke state.' },
    [pscustomobject]@{ source = 'shared_state/TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json'; target = 'TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json'; category = 'arm'; summary = 'Latest TOD status upload receipt on MIM ARM.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/mim_wall/MIM_WALL_STATE_ADAPTER.latest.json'; target = 'MIM_WALL_STATE_ADAPTER.latest.json'; category = 'ecosystem'; summary = 'Latest imported mim_wall shared integration adapter snapshot.' },
    [pscustomobject]@{ source = 'shared_state/mim_wall_event_projection.latest.json'; target = 'MIM_WALL_EVENT_PROJECTION.latest.json'; category = 'ecosystem'; summary = 'Canonical event projection derived from the latest mim_wall adapter snapshot.' },
    [pscustomobject]@{ source = 'shared_state/mim_wall_state.latest.json'; target = 'MIM_WALL_STATE.latest.json'; category = 'ecosystem'; summary = 'Latest mim_wall adapter ingestion summary for TOD/MIM orchestration.' },
    [pscustomobject]@{ source = 'shared_state/tod_supervised_execution.latest.json'; target = 'TOD_MIM_SUPERVISED_EXECUTION.latest.json'; category = 'runtime'; summary = 'Latest supervised execution state.' },
    [pscustomobject]@{ source = 'shared_state/tod_recovery_watchdog.latest.json'; target = 'TOD_MIM_RECOVERY_WATCHDOG.latest.json'; category = 'runtime'; summary = 'Latest recovery watchdog state.' },
    [pscustomobject]@{ source = 'shared_state/tod_watchdog_drift_guard.latest.json'; target = 'TOD_MIM_WATCHDOG_DRIFT_GUARD.latest.json'; category = 'runtime'; summary = 'Latest drift guard state.' },
    [pscustomobject]@{ source = 'shared_state/TOD_SELF_HEALTH_RUN.latest.json'; target = 'TOD_SELF_HEALTH_RUN.latest.json'; category = 'runtime'; summary = 'Latest TOD self-health run.' },
    [pscustomobject]@{ source = 'shared_state/NEXT_STEP_CONSENSUS.latest.json'; target = 'TOD_MIM_NEXT_STEP_CONSENSUS.latest.json'; category = 'planning'; summary = 'Latest TOD/MIM next-step consensus state.' },
    [pscustomobject]@{ source = 'shared_state/NEXT_STEP_POLICY.latest.json'; target = 'TOD_MIM_NEXT_STEP_POLICY.latest.json'; category = 'planning'; summary = 'Latest applied next-step policy state.' },
    [pscustomobject]@{ source = 'shared_state/tod_codex_next_steps.latest.json'; target = 'TOD_MIM_CODEX_NEXT_STEPS.latest.json'; category = 'planning'; summary = 'Latest TOD codex next-step recommendations.' },
    [pscustomobject]@{ source = 'shared_state/agentmim/tod_managed_work.latest.json'; target = 'TOD_MIM_MANAGED_WORK.latest.json'; category = 'managed-work'; summary = 'Latest managed-work posture.' },
    [pscustomobject]@{ source = 'shared_state/agentmim/tod_managed_work_cleanup.latest.json'; target = 'TOD_MIM_MANAGED_WORK_CLEANUP.latest.json'; category = 'managed-work'; summary = 'Latest managed-work cleanup record.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/ssh-shared/MIM_TOD_HANDSHAKE_PACKET.latest.json'; target = 'MIM_TOD_HANDSHAKE_PACKET.latest.json'; category = 'mim'; summary = 'Latest MIM handshake packet copied up from ssh-shared.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json'; target = 'MIM_TOD_TASK_REQUEST.latest.json'; category = 'mim'; summary = 'Latest live task request copied up from listener.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json'; target = 'MIM_CONTEXT_EXPORT.latest.json'; category = 'mim'; summary = 'Latest MIM context export JSON.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.yaml'; target = 'MIM_CONTEXT_EXPORT.latest.yaml'; category = 'mim'; summary = 'Latest MIM context export YAML.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/MIM_MANIFEST.latest.json'; target = 'MIM_MANIFEST.latest.json'; category = 'mim'; summary = 'Latest MIM manifest.' },
    [pscustomobject]@{ source = 'tod/out/context-sync/TOD_integration_status.latest.json'; target = 'TOD_integration_status.latest.json'; category = 'mim'; summary = 'Latest TOD integration status mirrored on context-sync root.' }
)

$copied = @()
$missing = @()

foreach ($entry in $entries) {
    $sourcePath = Resolve-RepoPath -PathValue ([string]$entry.source)
    $targetPath = Join-Path $resolvedDestinationRoot ([string]$entry.target)

    if (-not (Test-Path -Path $sourcePath)) {
        $missing += [pscustomobject]@{
            source = [string]$entry.source
            target = [string]$entry.target
            category = [string]$entry.category
            summary = [string]$entry.summary
        }
        continue
    }

    if ($sourcePath -ne $targetPath) {
        Copy-Item -Path $sourcePath -Destination $targetPath -Force
    }

    $item = Get-Item -Path $targetPath
    $copied += [pscustomobject]@{
        file_name = [string]$entry.target
        category = [string]$entry.category
        summary = [string]$entry.summary
        source = [string]$entry.source
        destination = $targetPath
        size_bytes = [int64]$item.Length
        last_write_time_utc = $item.LastWriteTimeUtc.ToString('o')
        sha256 = Get-FileHashSafe -PathValue $targetPath
    }
}

$generatedAt = (Get-Date).ToUniversalTime().ToString('o')
$indexObject = [pscustomobject]@{
    generated_at = $generatedAt
    source = 'tod-current-state-copy-v1'
    destination_root = $resolvedDestinationRoot
    copied_count = @($copied).Count
    missing_count = @($missing).Count
    copied_files = $copied
    missing_files = $missing
}

$jsonPath = Join-Path $resolvedDestinationRoot 'CURRENT_TOD_MIM_STATE_INDEX.latest.json'
$mdPath = Join-Path $resolvedDestinationRoot 'CURRENT_TOD_MIM_STATE_INDEX.latest.md'

$indexObject | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding utf8

$markdownLines = @(
    '# Current TOD MIM State Index',
    '',
    ('Generated at: {0}' -f $generatedAt),
    '',
    ('Copied files: {0}' -f @($copied).Count),
    ('Missing files: {0}' -f @($missing).Count),
    '',
    '## Available Files',
    ''
)

foreach ($file in $copied | Sort-Object category, file_name) {
    $markdownLines += ('- {0} [{1}] :: {2}' -f [string]$file.file_name, [string]$file.category, [string]$file.summary)
}

if (@($missing).Count -gt 0) {
    $markdownLines += ''
    $markdownLines += '## Missing Files'
    $markdownLines += ''
    foreach ($file in $missing | Sort-Object category, target) {
        $markdownLines += ('- {0} [{1}] :: missing source {2}' -f [string]$file.target, [string]$file.category, [string]$file.source)
    }
}

$markdownLines | Set-Content -Path $mdPath -Encoding utf8

$indexObject | ConvertTo-Json -Depth 8 | Write-Output