param(
    [string]$ProjectRoot = "E:/comm_app",
    [string]$OutputPath = "shared_state/agentmim/comm_app_marketing_smoke.latest.json",
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

function Test-FileContains {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $false
    }

    return $null -ne (Select-String -Path $Path -Pattern $Pattern -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function New-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    return [pscustomobject]@{
        name = $Name
        passed = $Passed
        detail = $Detail
    }
}

$resolvedProjectRoot = Resolve-LocalPath -PathValue $ProjectRoot
$resolvedOutputPath = Resolve-LocalPath -PathValue $OutputPath

$routeFile = Join-Path $resolvedProjectRoot "routes/marketing_routes.py"
$templateFile = Join-Path $resolvedProjectRoot "app/templates/admin/marketing.html"
$providerFile = Join-Path $resolvedProjectRoot "app/services/animation_provider.py"
$workerFile = Join-Path $resolvedProjectRoot "worker/app.py"
$workerHandlerFile = Join-Path $resolvedProjectRoot "worker/handler.py"
$statusFile = Join-Path $resolvedProjectRoot "TOD.md"

$checks = @()

$projectRootExists = Test-Path -Path $resolvedProjectRoot -PathType Container
$checks += New-Check -Name "project_root_exists" -Passed $projectRootExists -Detail $resolvedProjectRoot

$routeExists = Test-Path -Path $routeFile -PathType Leaf
$checks += New-Check -Name "marketing_routes_exists" -Passed $routeExists -Detail $routeFile

$templateExists = Test-Path -Path $templateFile -PathType Leaf
$checks += New-Check -Name "marketing_template_exists" -Passed $templateExists -Detail $templateFile

$providerExists = Test-Path -Path $providerFile -PathType Leaf
$checks += New-Check -Name "animation_provider_exists" -Passed $providerExists -Detail $providerFile

$workerExists = Test-Path -Path $workerFile -PathType Leaf
$checks += New-Check -Name "worker_app_exists" -Passed $workerExists -Detail $workerFile

$workerHandlerExists = Test-Path -Path $workerHandlerFile -PathType Leaf
$checks += New-Check -Name "worker_handler_exists" -Passed $workerHandlerExists -Detail $workerHandlerFile

$statusExists = Test-Path -Path $statusFile -PathType Leaf
$checks += New-Check -Name "project_status_file_exists" -Passed $statusExists -Detail $statusFile

$routeTokens = @(
    '@bp_marketing.route("/", methods=["GET"])',
    'def dashboard():',
    'def upload_avatar():',
    'def generate_animation():',
    'def generate_from_prompt():',
    'def avatar_preflight(avatar_id):',
    'def update_avatar(avatar_id):',
    'def update_avatar_rig(avatar_id):',
    'def avatar_rig_preview_clip(avatar_id):',
    'def avatar_rig_autodetect(avatar_id):'
)

$missingRouteTokens = @()
foreach ($token in $routeTokens) {
    if (-not (Test-FileContains -Path $routeFile -Pattern $token)) {
        $missingRouteTokens += $token
    }
}
$routeContractPassed = @($missingRouteTokens).Count -eq 0
$routeContractDetail = if ($routeContractPassed) {
    "All expected route tokens present."
}
else {
    "Missing route tokens: " + ($missingRouteTokens -join "; ")
}
$checks += New-Check -Name "marketing_route_contract" -Passed $routeContractPassed -Detail $routeContractDetail

$templateTokens = @(
    'href="#video" data-tab="video"',
    'href="#character" data-tab="character"',
    'href="#generate" data-tab="generate"',
    'href="#animations" data-tab="animations"',
    "url_for('marketing.generate_from_prompt')",
    "url_for('marketing.upload_avatar')",
    "url_for('marketing.generate_animation')"
)

$missingTemplateTokens = @()
foreach ($token in $templateTokens) {
    if (-not (Test-FileContains -Path $templateFile -Pattern $token)) {
        $missingTemplateTokens += $token
    }
}
$templateContractPassed = @($missingTemplateTokens).Count -eq 0
$templateContractDetail = if ($templateContractPassed) {
    "All expected template tokens present."
}
else {
    "Missing template tokens: " + ($missingTemplateTokens -join "; ")
}
$checks += New-Check -Name "marketing_template_contract" -Passed $templateContractPassed -Detail $templateContractDetail

$providerTokens = @(
    'resolve_animation_provider_choice',
    'RunPod',
    'SadTalker'
)

$providerHits = @()
foreach ($token in $providerTokens) {
    if (Test-FileContains -Path $providerFile -Pattern $token) {
        $providerHits += $token
    }
}
$providerMarkerPassed = @($providerHits).Count -ge 2
$providerMarkerDetail = if ($providerMarkerPassed) {
    "Matched provider markers: " + ($providerHits -join ", ")
}
else {
    "Expected provider markers not found."
}
$checks += New-Check -Name "animation_provider_markers" -Passed $providerMarkerPassed -Detail $providerMarkerDetail

$workerAppTokens = @(
    'class JobRequest',
    '_run_local_pipeline',
    'pipeline'
)

$missingWorkerAppTokens = @()
foreach ($token in $workerAppTokens) {
    if (-not (Test-FileContains -Path $workerFile -Pattern $token)) {
        $missingWorkerAppTokens += $token
    }
}
$workerHandlerTokens = @(
    'upload_url',
    'callback_url'
)

$missingWorkerHandlerTokens = @()
foreach ($token in $workerHandlerTokens) {
    if (-not (Test-FileContains -Path $workerHandlerFile -Pattern $token)) {
        $missingWorkerHandlerTokens += $token
    }
}

$workerContractPassed = (@($missingWorkerAppTokens).Count -eq 0) -and (@($missingWorkerHandlerTokens).Count -eq 0)
$workerContractDetail = if ($workerContractPassed) {
    "All expected worker tokens present."
}
else {
    $missingParts = @()
    if (@($missingWorkerAppTokens).Count -gt 0) {
        $missingParts += ("worker/app.py: " + ($missingWorkerAppTokens -join "; "))
    }
    if (@($missingWorkerHandlerTokens).Count -gt 0) {
        $missingParts += ("worker/handler.py: " + ($missingWorkerHandlerTokens -join "; "))
    }
    "Missing worker tokens: " + ($missingParts -join " | ")
}
$checks += New-Check -Name "worker_contract_markers" -Passed $workerContractPassed -Detail $workerContractDetail

$statusTokens = @(
    'Avatar/video generation should use the external worker/RunPod path'
)

$missingStatusTokens = @()
foreach ($token in $statusTokens) {
    if (-not (Test-FileContains -Path $statusFile -Pattern $token)) {
        $missingStatusTokens += $token
    }
}

$sadTalkerStatusVariants = @(
    'SadTalker is the stable default avatar profile',
    'SadTalker is the recommended stable production avatar profile',
    'Recommended stable spokesperson stack: SadTalker + GFPGAN + ffmpeg'
)

$hasSadTalkerStatusNote = $false
foreach ($variant in $sadTalkerStatusVariants) {
    if (Test-FileContains -Path $statusFile -Pattern $variant) {
        $hasSadTalkerStatusNote = $true
        break
    }
}

if (-not $hasSadTalkerStatusNote) {
    $missingStatusTokens += 'SadTalker stable/recommended production note'
}

$statusNotesPassed = @($missingStatusTokens).Count -eq 0
$statusNotesDetail = if ($statusNotesPassed) {
    "TOD.md contains expected avatar pipeline notes."
}
else {
    "Missing TOD.md notes: " + ($missingStatusTokens -join "; ")
}
$checks += New-Check -Name "project_status_notes" -Passed $statusNotesPassed -Detail $statusNotesDetail

$passedAll = @($checks | Where-Object { -not [bool]$_.passed }).Count -eq 0

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-comm-app-marketing-smoke-v1"
    project_id = "comm_app"
    project_root = $resolvedProjectRoot
    acceptance_surface = "/admin/marketing/?tab=video#video"
    checks = @($checks)
    summary = [pscustomobject]@{
        total = @($checks).Count
        passed = @(@($checks | Where-Object { [bool]$_.passed })).Count
        failed = @(@($checks | Where-Object { -not [bool]$_.passed })).Count
        passed_all = $passedAll
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 12 | Set-Content -Path $resolvedOutputPath

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 10 | Write-Output
}
else {
    $report
}

if ($FailOnError -and -not $passedAll) {
    throw "comm_app marketing smoke reported one or more failures."
}