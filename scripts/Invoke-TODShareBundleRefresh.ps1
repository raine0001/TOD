param(
    [string]$ConfigPath = "tod/config/tod-config.json",
    [int]$Top = 25,
    [switch]$SkipTests,
    [switch]$SkipSmoke,
    [switch]$SkipProjectDiscovery,
    [switch]$SkipContextIngest,
    [switch]$SkipContextExport,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$trainingScript = Join-Path $PSScriptRoot "Invoke-TODTrainingLoop.ps1"
$contextScript = Join-Path $PSScriptRoot "Invoke-TODContextExchange.ps1"
$sharedSyncScript = Join-Path $PSScriptRoot "Invoke-TODSharedStateSync.ps1"

if (-not (Test-Path -Path $trainingScript)) { throw "Missing training script: $trainingScript" }
if (-not (Test-Path -Path $contextScript)) { throw "Missing context exchange script: $contextScript" }
if (-not (Test-Path -Path $sharedSyncScript)) { throw "Missing shared state script: $sharedSyncScript" }

function Invoke-JsonScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][hashtable]$Params,
        [Parameter(Mandatory = $true)][string]$StepName
    )

    try {
        $raw = & $ScriptPath @Params
        return [pscustomobject]@{
            ok = $true
            step = $StepName
            payload = ($raw | ConvertFrom-Json)
            error = ""
        }
    }
    catch {
        return [pscustomobject]@{
            ok = $false
            step = $StepName
            payload = $null
            error = $_.Exception.Message
        }
    }
}

$startedAt = (Get-Date).ToUniversalTime().ToString("o")
$steps = @()

$trainingParams = @{
    ConfigPath = $ConfigPath
    Top = $Top
}
if ($SkipTests) { $trainingParams.SkipTests = $true }
if ($SkipSmoke) { $trainingParams.SkipSmoke = $true }
if ($SkipProjectDiscovery) { $trainingParams.SkipProjectDiscovery = $true }

$steps += Invoke-JsonScript -ScriptPath $trainingScript -Params $trainingParams -StepName "training"

$contextStatus = Invoke-JsonScript -ScriptPath $contextScript -Params @{ Action = "status" } -StepName "context_status_before"
$steps += $contextStatus

if (-not $SkipContextIngest) {
    $steps += Invoke-JsonScript -ScriptPath $contextScript -Params @{ Action = "ingest" } -StepName "context_ingest"
}

if (-not $SkipContextExport) {
    $steps += Invoke-JsonScript -ScriptPath $contextScript -Params @{ Action = "export" } -StepName "context_export"
}

$steps += Invoke-JsonScript -ScriptPath $contextScript -Params @{ Action = "status" } -StepName "context_status_after"
$steps += Invoke-JsonScript -ScriptPath $sharedSyncScript -Params @{} -StepName "shared_state_sync"

$failedSteps = @($steps | Where-Object { -not [bool]$_.ok })
$sharedStateStep = @($steps | Where-Object { [string]$_.step -eq "shared_state_sync" } | Select-Object -First 1)
$trainingStep = @($steps | Where-Object { [string]$_.step -eq "training" } | Select-Object -First 1)
$contextAfterStep = @($steps | Where-Object { [string]$_.step -eq "context_status_after" } | Select-Object -First 1)

$result = [pscustomobject]@{
    ok = (@($failedSteps).Count -eq 0)
    source = "tod-share-bundle-refresh-v1"
    started_at = $startedAt
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    steps_total = @($steps).Count
    steps_failed = @($failedSteps).Count
    steps = @($steps)
    quick = [pscustomobject]@{
        training_ok = if ($trainingStep) { [bool]$trainingStep.ok } else { $false }
        shared_state_ok = if ($sharedStateStep) { [bool]$sharedStateStep.ok } else { $false }
        pending_context_updates_after = if ($contextAfterStep -and $contextAfterStep.payload -and $contextAfterStep.payload.PSObject.Properties["pending_update_count"]) { [int]$contextAfterStep.payload.pending_update_count } else { -1 }
    }
}

$result | ConvertTo-Json -Depth 40 | Write-Output

if ($FailOnError -and @($failedSteps).Count -gt 0) {
    exit 2
}
