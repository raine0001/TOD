param(
    [string]$ProjectRoot = "E:/comm_app",
    [string]$OutputPath = "shared_state/agentmim/comm_app_managed_work.latest.json",
    [switch]$FailOnError,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Get-GitChangeEntries {
    param([Parameter(Mandatory = $true)][string]$Root)

    $entries = @()
    $gitAvailable = $false
    try {
        $null = Get-Command git -ErrorAction Stop
        $gitAvailable = $true
    }
    catch {
        return [pscustomobject]@{
            available = $false
            entries = @()
        }
    }

    $statusLines = @()
    try {
        $statusLines = @(git -C $Root status --porcelain=1 --untracked-files=all 2>&1)
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{
                available = $gitAvailable
                entries = @()
            }
        }
    }
    catch {
        return [pscustomobject]@{
            available = $gitAvailable
            entries = @()
        }
    }

    foreach ($line in $statusLines) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.Length -lt 4) { continue }

        $statusCode = $text.Substring(0, 2)
        $pathText = $text.Substring(3).Trim()
        if ($pathText -match ' -> ') {
            $pathText = ($pathText -split ' -> ')[-1]
        }

        $normalizedPath = ($pathText -replace '\\', '/').Trim('"')
        $statusName = if ($statusCode -eq '??') { 'untracked' } else { 'modified' }

        $entries += [pscustomobject]@{
            status = $statusName
            status_code = $statusCode
            path = $normalizedPath
        }
    }

    return [pscustomobject]@{
        available = $gitAvailable
        entries = @($entries)
    }
}

function Classify-ChangeEntry {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Status
    )

    $normalized = ($RelativePath -replace '\\', '/').Trim()
    $classification = 'manual_review'
    $reason = 'Path does not match a known comm_app managed scope rule.'
    $recommendedAction = 'Review manually before including in a TOD-managed patch.'

    if ($normalized -match '^scripts/qa_') {
        $classification = 'qa_support_artifact'
        $reason = 'QA helper scripts support validation but are not part of the primary product runtime surface.'
        $recommendedAction = 'Keep separate from the product patch unless TOD is explicitly promoting QA automation.'
    }
    elseif ($normalized -match '^static/images/' -and $Status -eq 'untracked') {
        $classification = 'asset_candidate'
        $reason = 'Untracked media asset should be confirmed as shipped product content before inclusion.'
        $recommendedAction = 'Separate from the product patch unless the avatar/admin feature explicitly needs this asset.'
    }
    elseif (
        $normalized -eq 'README.md' -or
        $normalized -eq 'TOD.md' -or
        $normalized -match '^(app|routes|worker|tests|docs)/'
    ) {
        $classification = 'managed_product_patch'
        $reason = 'File is inside the current comm_app avatar/admin managed surface or its immediate docs/tests.'
        $recommendedAction = 'Keep inside the TOD-managed product patch scope.'
    }

    return [pscustomobject]@{
        path = $normalized
        status = $Status
        classification = $classification
        reason = $reason
        recommended_action = $recommendedAction
    }
}

$resolvedProjectRoot = Resolve-LocalPath -PathValue $ProjectRoot
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

$verificationScript = Join-Path $PSScriptRoot 'Invoke-TODCommAppVerification.ps1'
$verificationOutputPath = Join-Path (Split-Path -Parent $resolvedOutputPath) 'comm_app_verification.latest.json'

$verificationReport = $null
try {
    $verificationJson = & $verificationScript -ProjectRoot $resolvedProjectRoot -OutputPath $verificationOutputPath -EmitJson
    $verificationReport = ($verificationJson | ConvertFrom-Json)
}
catch {
    throw "Unable to build comm_app managed work report because verification failed to execute: $($_.Exception.Message)"
}

$gitState = Get-GitChangeEntries -Root $resolvedProjectRoot
$classifiedChanges = @()
foreach ($entry in @($gitState.entries)) {
    $classifiedChanges += Classify-ChangeEntry -RelativePath ([string]$entry.path) -Status ([string]$entry.status
    )
}

$managedPatchFiles = @($classifiedChanges | Where-Object { [string]$_.classification -eq 'managed_product_patch' })
$supportArtifacts = @($classifiedChanges | Where-Object {
    ([string]$_.classification -eq 'qa_support_artifact') -or
    ([string]$_.classification -eq 'asset_candidate')
})
$manualReviewFiles = @($classifiedChanges | Where-Object { [string]$_.classification -eq 'manual_review' })

$controlState = 'verification_blocked'
if ($verificationReport.summary.passed_required_gate) {
    if (@($manualReviewFiles).Count -gt 0) {
        $controlState = 'review_needed'
    }
    elseif (@($managedPatchFiles).Count -gt 0 -and @($supportArtifacts).Count -gt 0) {
        $controlState = 'ready_with_artifact_separation'
    }
    elseif (@($managedPatchFiles).Count -gt 0) {
        $controlState = 'ready_for_managed_patch'
    }
    elseif (@($supportArtifacts).Count -gt 0) {
        $controlState = 'qa_only_pending'
    }
    else {
        $controlState = 'clean_or_no_pending_changes'
    }
}

$recommendedActions = @()
if (-not $verificationReport.summary.passed_required_gate) {
    $recommendedActions += 'Fix required comm_app verification failures before TOD attempts live feature work.'
}
elseif (@($managedPatchFiles).Count -gt 0) {
    $recommendedActions += 'Use the managed product patch file set as the active TOD edit scope for the next comm_app task.'
}

if (@($supportArtifacts).Count -gt 0) {
    $recommendedActions += 'Keep QA/support artifacts separated from the product patch unless the task explicitly promotes them into the managed workflow.'
}

if (@($manualReviewFiles).Count -gt 0) {
    $recommendedActions += 'Resolve manually classified files before treating the repo state as a clean TOD-managed patch set.'
}

if (@($recommendedActions).Count -eq 0) {
    $recommendedActions += 'No pending managed work was identified; the comm_app working tree is ready for the next TOD-directed task.'
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-comm-app-managed-work-v1'
    project_id = 'comm_app'
    project_root = $resolvedProjectRoot
    acceptance_surface = '/admin/marketing/?tab=video#video'
    control_state = $controlState
    verification = $verificationReport
    patch_scope = [pscustomobject]@{
        managed_product_patch = @($managedPatchFiles)
        support_or_reference_artifacts = @($supportArtifacts)
        manual_review = @($manualReviewFiles)
    }
    facts = [pscustomobject]@{
        pending_changes = @($classifiedChanges).Count
        managed_product_patch_count = @($managedPatchFiles).Count
        support_or_reference_artifact_count = @($supportArtifacts).Count
        manual_review_count = @($manualReviewFiles).Count
    }
    recommended_actions = @($recommendedActions)
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $resolvedOutputPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 12 | Write-Output
}
else {
    $report
}

if ($FailOnError -and -not $verificationReport.summary.passed_required_gate) {
    throw 'comm_app managed work reported required verification failures.'
}