Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = 'e:\TOD'
$syncScript = Join-Path $repoRoot 'scripts/Invoke-TODSharedStateSync.ps1'
$id = [guid]::NewGuid().ToString('N')
$base = Join-Path $repoRoot ("tod/out/tests/shared-live-request-" + $id)
$sharedStateDir = Join-Path $base 'shared_state'
$mimContext = Join-Path $base 'MIM_CONTEXT_EXPORT.latest.json'
$mimManifest = Join-Path $base 'MIM_MANIFEST.latest.json'
$mimShared = Join-Path $base 'runtime/shared'
$listenerRequestPath = Join-Path $base 'listener-request.json'
$sharedRequestPath = Join-Path $mimShared 'MIM_TOD_TASK_REQUEST.latest.json'
$sharedJson = Join-Path $mimShared 'MIM_CONTEXT_EXPORT.latest.json'

New-Item -ItemType Directory -Path $mimShared -Force | Out-Null

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
$manifestDoc = [pscustomobject]@{
    source = 'mim-fresh'
    schema_version = '2026-03-12-57'
    contract_version = 'tod-mim-shared-contract-v1'
}

$contextDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedJson
$manifestDoc | ConvertTo-Json -Depth 12 | Set-Content -Path $mimManifest
$listenerRequest | ConvertTo-Json -Depth 12 | Set-Content -Path $listenerRequestPath
$sharedRequest | ConvertTo-Json -Depth 12 | Set-Content -Path $sharedRequestPath

$previousEnvRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
try {
    $env:MIM_SHARED_EXPORT_ROOT = [string]$mimShared
    $null = & $syncScript -SharedStateDir $sharedStateDir -MimContextExportPath $mimContext -MimManifestPath $mimManifest -RefreshMimContextFromShared -ListenerRequestPath $listenerRequestPath -ContextSyncInboxPath 'tod/inbox/context-sync/updates'
}
finally {
    $env:MIM_SHARED_EXPORT_ROOT = $previousEnvRoot
}

$integrationPath = Join-Path $sharedStateDir 'integration_status.json'
$integration = Get-Content -Path $integrationPath -Raw | ConvertFrom-Json
$result = [pscustomobject]@{
    source_path = [string]$integration.live_task_request.source_path
    request_id = [string]$integration.live_task_request.request_id
    normalized_objective_id = [string]$integration.live_task_request.normalized_objective_id
}
$result | ConvertTo-Json -Depth 8

if ([string]$result.source_path -ne [string]$sharedRequestPath) { throw 'Expected shared live task request path to win over stale listener copy.' }
if ([string]$result.request_id -ne 'objective-2504-task-6325-new') { throw 'Expected fresher shared request id to be selected.' }
if ([string]$result.normalized_objective_id -ne '2504') { throw 'Expected normalized objective id 2504.' }
