param(
    [int]$Top = 10,
    [switch]$SkipProjectDiscovery,
    [switch]$SkipTests,
    [switch]$SkipSmoke,
    [switch]$OpenOutputFolder,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$shareBundleScript = Join-Path $PSScriptRoot "Invoke-TODShareBundleRefresh.ps1"
$contextScript = Join-Path $PSScriptRoot "Invoke-TODContextExchange.ps1"

if (-not (Test-Path -Path $shareBundleScript)) { throw "Missing script: $shareBundleScript" }
if (-not (Test-Path -Path $contextScript)) { throw "Missing script: $contextScript" }

function Convert-ToFileUri {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = [System.IO.Path]::GetFullPath($PathValue)
    $uriPath = $resolved -replace "\\", "/"
    return ("file:///{0}" -f $uriPath)
}

$contextExportsDir = Join-Path $repoRoot "tod/out/context-sync/exports"
if (-not (Test-Path -Path $contextExportsDir)) {
    New-Item -ItemType Directory -Path $contextExportsDir -Force | Out-Null
}

$passId = "FORMALPASS-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant())
$startedAt = (Get-Date).ToUniversalTime().ToString("o")

Write-Host "[TOD] Starting formal pass to MIM: $passId" -ForegroundColor Cyan

$bundleArgs = @{
    Top = $Top
}
if ($SkipProjectDiscovery) {
    $bundleArgs.SkipProjectDiscovery = $true
}
if ($SkipTests) {
    $bundleArgs.SkipTests = $true
}
if ($SkipSmoke) {
    $bundleArgs.SkipSmoke = $true
}

Write-Host "[TOD] Running share bundle refresh (training + context + shared state)..." -ForegroundColor Cyan
$bundleRaw = & $shareBundleScript @bundleArgs
$bundle = $bundleRaw | ConvertFrom-Json

Write-Host "[TOD] Running explicit context export for formal handoff..." -ForegroundColor Cyan
$exportRaw = & $contextScript -Action "export"
$exportPayload = $exportRaw | ConvertFrom-Json

Write-Host "[TOD] Checking context channel status..." -ForegroundColor Cyan
$statusRaw = & $contextScript -Action "status"
$statusPayload = $statusRaw | ConvertFrom-Json

$sharedStateChatgptMd = Join-Path $repoRoot "shared_state/chatgpt_update.md"
$sharedStateChatgptJson = Join-Path $repoRoot "shared_state/chatgpt_update.json"
$sharedStateLogPlan = Join-Path $repoRoot "shared_state/shared_development_log_plan.json"

$receipt = [pscustomobject]@{
    id = $passId
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-formal-pass-to-mim-v1"
    started_at = $startedAt
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    ok = ([bool]$bundle.ok -and [bool]$exportPayload.ok -and [bool]$statusPayload.ok)
    summary = [pscustomobject]@{
        bundle_ok = [bool]$bundle.ok
        context_export_ok = [bool]$exportPayload.ok
        context_status_ok = [bool]$statusPayload.ok
        pending_context_updates = if ($statusPayload.PSObject.Properties["pending_update_count"]) { [int]$statusPayload.pending_update_count } else { -1 }
    }
    artifacts = [pscustomobject]@{
        context_latest_yaml = [string]$exportPayload.latest_yaml
        context_latest_json = [string]$exportPayload.latest_json
        context_versioned_yaml = [string]$exportPayload.versioned_yaml
        context_versioned_json = [string]$exportPayload.versioned_json
        shared_state_chatgpt_md = $sharedStateChatgptMd
        shared_state_chatgpt_json = $sharedStateChatgptJson
        shared_state_log_plan = $sharedStateLogPlan
    }
}

$slug = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$receiptVersionedPath = Join-Path $contextExportsDir ("TOD_FORMAL_PASS_RECEIPT-{0}.json" -f $slug)
$receiptLatestPath = Join-Path $contextExportsDir "TOD_FORMAL_PASS_RECEIPT.latest.json"

$receipt | ConvertTo-Json -Depth 20 | Set-Content -Path $receiptVersionedPath
$receipt | ConvertTo-Json -Depth 20 | Set-Content -Path $receiptLatestPath

Write-Host "[TOD] Formal pass complete." -ForegroundColor Green
Write-Host "[TOD] Share/download these files:" -ForegroundColor Green
Write-Host "  $receiptLatestPath"
Write-Host "  $($receipt.artifacts.context_latest_yaml)"
Write-Host "  $($receipt.artifacts.context_latest_json)"
Write-Host "  $($receipt.artifacts.shared_state_chatgpt_md)"
Write-Host "  $($receipt.artifacts.shared_state_chatgpt_json)"
Write-Host "  $($receipt.artifacts.shared_state_log_plan)"
Write-Host "[TOD] File URIs (for copy/share):" -ForegroundColor Green
Write-Host "  $(Convert-ToFileUri -PathValue $receiptLatestPath)"
Write-Host "  $(Convert-ToFileUri -PathValue ([string]$receipt.artifacts.context_latest_yaml))"
Write-Host "  $(Convert-ToFileUri -PathValue ([string]$receipt.artifacts.context_latest_json))"
Write-Host "  $(Convert-ToFileUri -PathValue ([string]$receipt.artifacts.shared_state_chatgpt_md))"
Write-Host "  $(Convert-ToFileUri -PathValue ([string]$receipt.artifacts.shared_state_chatgpt_json))"
Write-Host "  $(Convert-ToFileUri -PathValue ([string]$receipt.artifacts.shared_state_log_plan))"

if ($OpenOutputFolder) {
    Start-Process explorer.exe $contextExportsDir | Out-Null
    Write-Host "[TOD] Opened output folder: $contextExportsDir" -ForegroundColor DarkGray
}

$receipt | ConvertTo-Json -Depth 20 | Write-Output

if ($FailOnError -and -not [bool]$receipt.ok) {
    exit 2
}
