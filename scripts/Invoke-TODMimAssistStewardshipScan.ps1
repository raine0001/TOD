param(
    [string]$ProjectRoot = 'E:/mim_wall',
    [string]$OutputRoot = 'tod/out/stewardship/mim_assist',
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Write-TextNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $Content, $utf8NoBom)
}

function New-ModuleRecord {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$Responsibility,
        [Parameter(Mandatory = $true)][string]$Risk,
        [string]$Validation = ''
    )

    $absolutePath = Join-Path $resolvedProjectRoot $RelativePath

    return [pscustomobject]@{
        relative_path = $RelativePath -replace '\\', '/'
        absolute_path = $absolutePath -replace '\\', '/'
        exists = (Test-Path -Path $absolutePath -PathType Leaf)
        surface = $Surface
        responsibility = $Responsibility
        risk = $Risk
        validation = $Validation
    }
}

$resolvedProjectRoot = Resolve-RepoPath -PathValue $ProjectRoot
$resolvedOutputRoot = Resolve-RepoPath -PathValue $OutputRoot

if (-not (Test-Path -Path $resolvedProjectRoot -PathType Container)) {
    throw "Project root not found: $resolvedProjectRoot"
}

$records = @(
    (New-ModuleRecord -RelativePath 'app/src/main/AndroidManifest.xml' -Surface 'frontend_entry_points' -Responsibility 'Application manifest, permissions, and runtime component declarations.' -Risk 'approval_required' -Validation 'build + lint'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/MainActivity.kt' -Surface 'frontend_entry_points' -Responsibility 'Compose operator shell, communicator UI, dashboard, configuration, operations, and workstation controls.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/ui/theme/Theme.kt' -Surface 'frontend_entry_points' -Responsibility 'Theme and visual shell primitives.' -Risk 'safe' -Validation 'build'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/callscreening/GuardianCallScreeningService.kt' -Surface 'runtime_routes' -Responsibility 'Primary call screening entry and call interception logic.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/callscreening/MimInCallService.kt' -Surface 'runtime_routes' -Responsibility 'In-call lifecycle entry for live call runtime.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/messaging/IncomingSmsReceiver.kt' -Surface 'runtime_routes' -Responsibility 'Inbound SMS runtime entry point.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/testing/AutomationSimulationReceiver.kt' -Surface 'runtime_routes' -Responsibility 'ADB-driven simulation entry point for automation regression.' -Risk 'guarded' -Validation 'regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/CallDecisionEngine.kt' -Surface 'initiative_autonomy_modules' -Responsibility 'Call classification and screening decision engine.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/MultiChannelHandoffPlanner.kt' -Surface 'initiative_autonomy_modules' -Responsibility 'Owner handoff planning across channels.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/messaging/CallerInteractionPolicyEngine.kt' -Surface 'initiative_autonomy_modules' -Responsibility 'High-level policy routing for caller interaction behavior.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/messaging/MimConversationEngine.kt' -Surface 'initiative_autonomy_modules' -Responsibility 'Local dialog fallback engine.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/messaging/MimAiOrchestrator.kt' -Surface 'initiative_autonomy_modules' -Responsibility 'AI-assisted message orchestration path.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/messaging/TextMessageManager.kt' -Surface 'initiative_autonomy_modules' -Responsibility 'Primary SMS classification, policy, queue, and owner handoff hub.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/session/CallSessionStore.kt' -Surface 'runtime_state_modules' -Responsibility 'Queue, timeline, and feedback state persistence.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/AssistantPolicyStore.kt' -Surface 'runtime_state_modules' -Responsibility 'Conversation policy persistence.' -Risk 'guarded' -Validation 'build + lint'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/ScreeningBehaviorStore.kt' -Surface 'runtime_state_modules' -Responsibility 'Screening mode and operator control persistence.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/ScreeningRulesStore.kt' -Surface 'runtime_state_modules' -Responsibility 'Thresholds and blocklist persistence.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/DeviceActionGuardrailStore.kt' -Surface 'runtime_state_modules' -Responsibility 'Safe-mode and confirmation guardrails.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/LiveCallRolloutStore.kt' -Surface 'runtime_state_modules' -Responsibility 'Live-call rollout governance and gating.' -Risk 'approval_required' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/domain/MimMasterControlStore.kt' -Surface 'health_recovery_modules' -Responsibility 'Emergency master control and automation stop/resume state.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/callscreening/LiveCallAudioSessionController.kt' -Surface 'media_voice_modules' -Responsibility 'Audio session control for live call runtime.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/callscreening/LiveCallSpeechController.kt' -Surface 'media_voice_modules' -Responsibility 'Speech runtime behavior during active calls.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/callscreening/LiveCallTurnCaptureController.kt' -Surface 'media_voice_modules' -Responsibility 'Turn capture state for live-call voice interaction.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/callscreening/LiveCallTurnCoordinator.kt' -Surface 'media_voice_modules' -Responsibility 'High-level live-call turn coordination.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/voice/VoiceAgentFactory.kt' -Surface 'media_voice_modules' -Responsibility 'Runtime selection between local, MIM, and OpenAI voice/provider modes.' -Risk 'guarded' -Validation 'build + lint + regression'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/voice/ProviderConnectivityTester.kt' -Surface 'health_recovery_modules' -Responsibility 'Provider connectivity verification.' -Risk 'guarded' -Validation 'build + lint'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/workstation/MimWallStateAdapterSnapshotBuilder.kt' -Surface 'shared_state_bridge_modules' -Responsibility 'Read-only snapshot export for TOD/MIM orchestration.' -Risk 'guarded' -Validation 'build + lint + stewardship scan'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/workstation/MimWorkstationPlaceholderClient.kt' -Surface 'shared_state_bridge_modules' -Responsibility 'Remote workstation transport placeholder for future sync.' -Risk 'guarded' -Validation 'build + lint'),
    (New-ModuleRecord -RelativePath 'app/src/main/java/com/dave/callguardian/workstation/MimWorkstationStore.kt' -Surface 'shared_state_bridge_modules' -Responsibility 'Persistence for workstation sync configuration.' -Risk 'guarded' -Validation 'build + lint'),
    (New-ModuleRecord -RelativePath 'scripts/device_smoke_test.ps1' -Surface 'health_recovery_modules' -Responsibility 'Build, lint, install, launch, and crash-tail smoke check.' -Risk 'safe' -Validation 'script execution'),
    (New-ModuleRecord -RelativePath 'scripts/automated_dialog_regression.ps1' -Surface 'health_recovery_modules' -Responsibility 'Primary device regression gate for automation scenarios and capability preflight.' -Risk 'safe' -Validation 'script execution'),
    (New-ModuleRecord -RelativePath 'scripts/verify_busy_intercept.ps1' -Surface 'health_recovery_modules' -Responsibility 'Targeted busy-call interception verification helper.' -Risk 'safe' -Validation 'script execution')
)

$safeEditZones = @(
    'README.md',
    'MIM_ASSIST_SPEC.md',
    'DEVELOPMENT_PLAN.md',
    'SPRINT_1_PLAN.md',
    'scripts/*.ps1',
    'app/src/main/java/com/dave/callguardian/ui/theme/*'
)

$guardedEditZones = @(
    'app/src/main/java/com/dave/callguardian/MainActivity.kt',
    'app/src/main/java/com/dave/callguardian/callscreening/*',
    'app/src/main/java/com/dave/callguardian/messaging/*',
    'app/src/main/java/com/dave/callguardian/domain/*',
    'app/src/main/java/com/dave/callguardian/session/*',
    'app/src/main/java/com/dave/callguardian/voice/*',
    'app/src/main/java/com/dave/callguardian/workstation/*'
)

$validationRequiredZones = @(
    'app/src/main/**',
    'app/build.gradle.kts',
    'build.gradle.kts',
    'scripts/automated_dialog_regression.ps1',
    'scripts/device_smoke_test.ps1',
    'app/src/main/AndroidManifest.xml'
)

$operatorApprovalZones = @(
    'app/src/main/AndroidManifest.xml',
    'app/build.gradle.kts',
    'build.gradle.kts',
    'app/src/main/java/com/dave/callguardian/domain/LiveCallRolloutStore.kt',
    'app/src/main/java/com/dave/callguardian/domain/MimMasterControlStore.kt'
)

$riskyCouplings = @(
    'MainActivity couples UI shell, workstation sync, capability state, and communicator behavior into one large orchestration file.',
    'TextMessageManager combines policy, spam heuristics, queue state, scheduling, and owner handoff behavior.',
    'Telephony runtime behavior depends on Android roles and permissions that can drift independently from code state.',
    'Provider mode selection changes both runtime semantics and validation expectations.',
    'Snapshot export is safe and read-only, but stale export timing can mislead TOD and downstream MIM orchestration.'
)

$staleStateZones = @(
    'capability_drift',
    'live_call_interrupt_and_resume',
    'queue_vs_handoff_divergence',
    'provider_mode_mismatch',
    'workstation_snapshot_lag'
)

$backlog = @(
    [pscustomobject]@{ category = 'stale-state prevention'; title = 'Export capability drift artifact'; priority = 'high'; rationale = 'Role and permission drift currently requires manual diagnosis or regression output inspection.' },
    [pscustomobject]@{ category = 'execution continuity'; title = 'Harden live-call interruption transitions'; priority = 'high'; rationale = 'Audio and speech turnover remains one of the most fragile runtime surfaces.' },
    [pscustomobject]@{ category = 'ui formatting/rendering'; title = 'Split MainActivity into focused shell modules'; priority = 'high'; rationale = 'Large single-file UI orchestration raises blast radius for routine changes.' },
    [pscustomobject]@{ category = 'multimodal/image support'; title = 'Reserve snapshot fields for richer media context'; priority = 'medium'; rationale = 'Stewardship should preserve a forward path for richer MIM context surfaces.' },
    [pscustomobject]@{ category = 'voice usability'; title = 'Add operator-visible voice degradation indicator'; priority = 'high'; rationale = 'Provider mode and voice fallback state should be explicit during operator use.' },
    [pscustomobject]@{ category = 'shell/shared truth integration'; title = 'Add snapshot freshness and queue-age metadata'; priority = 'high'; rationale = 'TOD needs deterministic evidence that exported MIM state is fresh enough to trust.' },
    [pscustomobject]@{ category = 'recovery/resume behavior'; title = 'Create one-step rebuild-reinstall-regression recovery path'; priority = 'medium'; rationale = 'Recovery is scriptable today but not yet packaged as one stewardship action.' }
)

$surfaceGroups = $records |
    Group-Object -Property surface |
    Sort-Object -Property Name |
    ForEach-Object {
        [pscustomobject]@{
            surface = $_.Name
            files = @($_.Group)
        }
    }

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-assist-stewardship-scan-v1'
    project_root = $resolvedProjectRoot -replace '\\', '/'
    output_root = $resolvedOutputRoot -replace '\\', '/'
    project = [pscustomobject]@{
        id = 'mim_wall'
        name = 'MIM Assist'
        type = 'android-app'
        platform = 'android'
        package_name = 'com.dave.callguardian'
    }
    validation_gate = @(
        './gradlew.bat assembleDebug',
        './gradlew.bat lintDebug',
        'powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1'
    )
    architecture = [pscustomobject]@{
        surfaces = $surfaceGroups
        risky_couplings = $riskyCouplings
        stale_state_zones = $staleStateZones
    }
    ownership = [pscustomobject]@{
        safe_edit_zones = $safeEditZones
        guarded_edit_zones = $guardedEditZones
        validation_required_zones = $validationRequiredZones
        operator_approval_zones = $operatorApprovalZones
    }
    backlog = $backlog
}

$jsonPath = Join-Path $resolvedOutputRoot 'mim-assist-stewardship-map.latest.json'
$mdPath = Join-Path $resolvedOutputRoot 'mim-assist-stewardship-map.latest.md'

$markdownLines = New-Object System.Collections.Generic.List[string]
$markdownLines.Add('# MIM Assist Stewardship Map') | Out-Null
$markdownLines.Add('') | Out-Null
$markdownLines.Add(('- Generated at: {0}' -f $report.generated_at)) | Out-Null
$markdownLines.Add(('- Project root: `{0}`' -f $report.project_root)) | Out-Null
$markdownLines.Add('') | Out-Null
$markdownLines.Add('## Validation Gate') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($gate in $report.validation_gate) {
    $markdownLines.Add(('- `{0}`' -f [string]$gate)) | Out-Null
}
$markdownLines.Add('') | Out-Null
$markdownLines.Add('## Surfaces') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($surface in $surfaceGroups) {
    $markdownLines.Add(('### {0}' -f [string]$surface.surface)) | Out-Null
    $markdownLines.Add('') | Out-Null
    foreach ($file in @($surface.files)) {
        $markdownLines.Add(('- `{0}` - {1}' -f [string]$file.relative_path, [string]$file.responsibility)) | Out-Null
    }
    $markdownLines.Add('') | Out-Null
}
$markdownLines.Add('## Risky Couplings') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($item in $riskyCouplings) {
    $markdownLines.Add(('- {0}' -f [string]$item)) | Out-Null
}
$markdownLines.Add('') | Out-Null
$markdownLines.Add('## Ownership') | Out-Null
$markdownLines.Add('') | Out-Null
$markdownLines.Add('### Safe Edit Zones') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($item in $safeEditZones) {
    $markdownLines.Add(('- `{0}`' -f [string]$item)) | Out-Null
}
$markdownLines.Add('') | Out-Null
$markdownLines.Add('### Guarded Edit Zones') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($item in $guardedEditZones) {
    $markdownLines.Add(('- `{0}`' -f [string]$item)) | Out-Null
}
$markdownLines.Add('') | Out-Null
$markdownLines.Add('### Validation Required Zones') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($item in $validationRequiredZones) {
    $markdownLines.Add(('- `{0}`' -f [string]$item)) | Out-Null
}
$markdownLines.Add('') | Out-Null
$markdownLines.Add('### Operator Approval Zones') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($item in $operatorApprovalZones) {
    $markdownLines.Add(('- `{0}`' -f [string]$item)) | Out-Null
}
$markdownLines.Add('') | Out-Null
$markdownLines.Add('## Prioritized Backlog') | Out-Null
$markdownLines.Add('') | Out-Null
foreach ($item in $backlog) {
    $markdownLines.Add(('- [{0}] {1} - {2}' -f [string]$item.priority, [string]$item.category, [string]$item.title)) | Out-Null
    $markdownLines.Add(('  Rationale: {0}' -f [string]$item.rationale)) | Out-Null
}

Write-JsonNoBom -PathValue $jsonPath -Payload $report -Depth 20
Write-TextNoBom -PathValue $mdPath -Content ($markdownLines -join [Environment]::NewLine)

$result = [pscustomobject]@{
    ok = $true
    generated_at = $report.generated_at
    source = $report.source
    project_root = $report.project_root
    report_json = $jsonPath
    report_markdown = $mdPath
    surface_count = @($surfaceGroups).Count
    record_count = @($records).Count
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 10 | Write-Output
}
else {
    $result
}