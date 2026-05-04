param(
    [string]$ProjectRoot = 'E:/mim_wall',
    [string]$OutputRoot = 'tod/out/stewardship/mim_assist/health',
    [switch]$RunBuild,
    [switch]$RunLint,
    [switch]$RunDeviceSmoke,
    [switch]$RunRegression,
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

function New-CheckRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Summary,
        [string]$Detail = ''
    )

    return [pscustomobject]@{
        name = $Name
        passed = $Passed
        summary = $Summary
        detail = $Detail
    }
}

function Invoke-RepoCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $stdoutPath = Join-Path $env:TEMP (('tod-mim-assist-health-' + [guid]::NewGuid().ToString('N') + '.stdout.log'))
    $stderrPath = Join-Path $env:TEMP (('tod-mim-assist-health-' + [guid]::NewGuid().ToString('N') + '.stderr.log'))
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $resolvedProjectRoot -PassThru -Wait -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $stdout = if (Test-Path -Path $stdoutPath) { [string](Get-Content -Path $stdoutPath -Raw) } else { '' }
        $stderr = if (Test-Path -Path $stderrPath) { [string](Get-Content -Path $stderrPath -Raw) } else { '' }
        return [pscustomobject]@{
            exit_code = [int]$process.ExitCode
            stdout = $stdout
            stderr = $stderr
        }
    }
    finally {
        foreach ($tempPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -Path $tempPath) {
                Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Resolve-AdbPath {
    $candidates = @(
        (Join-Path $resolvedProjectRoot '.android-sdk/platform-tools/adb.exe'),
        (Join-Path $resolvedProjectRoot 'android-sdk/platform-tools/adb.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if ($adbCommand) {
        return [string]$adbCommand.Source
    }

    return ''
}

$resolvedProjectRoot = Resolve-RepoPath -PathValue $ProjectRoot
$resolvedOutputRoot = Resolve-RepoPath -PathValue $OutputRoot

if (-not (Test-Path -Path $resolvedProjectRoot -PathType Container)) {
    throw "Project root not found: $resolvedProjectRoot"
}

$manifestPath = Join-Path $resolvedProjectRoot 'app/src/main/AndroidManifest.xml'
$mainActivityPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/MainActivity.kt'
$callScreeningPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/callscreening/GuardianCallScreeningService.kt'
$inCallPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/callscreening/MimInCallService.kt'
$smsReceiverPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/messaging/IncomingSmsReceiver.kt'
$automationReceiverPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/testing/AutomationSimulationReceiver.kt'
$voiceFactoryPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/voice/VoiceAgentFactory.kt'
$snapshotBuilderPath = Join-Path $resolvedProjectRoot 'app/src/main/java/com/dave/callguardian/workstation/MimWallStateAdapterSnapshotBuilder.kt'
$buildScriptPath = Join-Path $resolvedProjectRoot 'app/build.gradle.kts'
$gradlewPath = Join-Path $resolvedProjectRoot 'gradlew.bat'
$lintScriptPath = Join-Path $resolvedProjectRoot 'scripts/device_smoke_test.ps1'
$regressionScriptPath = Join-Path $resolvedProjectRoot 'scripts/automated_dialog_regression.ps1'
$busyInterceptPath = Join-Path $resolvedProjectRoot 'scripts/verify_busy_intercept.ps1'

$manifestContent = if (Test-Path -Path $manifestPath -PathType Leaf) { [string](Get-Content -Path $manifestPath -Raw) } else { '' }
$adbPath = Resolve-AdbPath

$checks = @(
    (New-CheckRecord -Name 'project_root_present' -Passed (Test-Path -Path $resolvedProjectRoot -PathType Container) -Summary 'Project root is available.' -Detail $resolvedProjectRoot),
    (New-CheckRecord -Name 'gradle_wrapper_present' -Passed (Test-Path -Path $gradlewPath -PathType Leaf) -Summary 'Gradle wrapper is present.' -Detail $gradlewPath),
    (New-CheckRecord -Name 'build_script_present' -Passed (Test-Path -Path $buildScriptPath -PathType Leaf) -Summary 'Android app build script is present.' -Detail $buildScriptPath),
    (New-CheckRecord -Name 'manifest_present' -Passed (Test-Path -Path $manifestPath -PathType Leaf) -Summary 'Android manifest is present.' -Detail $manifestPath),
    (New-CheckRecord -Name 'main_activity_present' -Passed (Test-Path -Path $mainActivityPath -PathType Leaf) -Summary 'Compose shell entry point is present.' -Detail $mainActivityPath),
    (New-CheckRecord -Name 'call_screening_service_declared' -Passed ($manifestContent -match 'GuardianCallScreeningService') -Summary 'Call screening service is declared in the manifest.' -Detail 'GuardianCallScreeningService'),
    (New-CheckRecord -Name 'in_call_service_declared' -Passed ($manifestContent -match 'MimInCallService') -Summary 'In-call service is declared in the manifest.' -Detail 'MimInCallService'),
    (New-CheckRecord -Name 'sms_receiver_declared' -Passed ($manifestContent -match 'IncomingSmsReceiver') -Summary 'SMS receiver is declared in the manifest.' -Detail 'IncomingSmsReceiver'),
    (New-CheckRecord -Name 'automation_receiver_declared' -Passed ($manifestContent -match 'AutomationSimulationReceiver') -Summary 'Automation simulation receiver is declared in the manifest.' -Detail 'AutomationSimulationReceiver'),
    (New-CheckRecord -Name 'call_screening_runtime_present' -Passed (Test-Path -Path $callScreeningPath -PathType Leaf) -Summary 'Call screening runtime source exists.' -Detail $callScreeningPath),
    (New-CheckRecord -Name 'in_call_runtime_present' -Passed (Test-Path -Path $inCallPath -PathType Leaf) -Summary 'In-call runtime source exists.' -Detail $inCallPath),
    (New-CheckRecord -Name 'sms_runtime_present' -Passed (Test-Path -Path $smsReceiverPath -PathType Leaf) -Summary 'SMS runtime source exists.' -Detail $smsReceiverPath),
    (New-CheckRecord -Name 'voice_factory_present' -Passed (Test-Path -Path $voiceFactoryPath -PathType Leaf) -Summary 'Voice provider factory exists.' -Detail $voiceFactoryPath),
    (New-CheckRecord -Name 'workstation_snapshot_present' -Passed (Test-Path -Path $snapshotBuilderPath -PathType Leaf) -Summary 'Read-only workstation snapshot builder exists.' -Detail $snapshotBuilderPath),
    (New-CheckRecord -Name 'device_smoke_script_present' -Passed (Test-Path -Path $lintScriptPath -PathType Leaf) -Summary 'Device smoke script exists.' -Detail $lintScriptPath),
    (New-CheckRecord -Name 'dialog_regression_script_present' -Passed (Test-Path -Path $regressionScriptPath -PathType Leaf) -Summary 'Automated dialog regression script exists.' -Detail $regressionScriptPath),
    (New-CheckRecord -Name 'busy_intercept_script_present' -Passed (Test-Path -Path $busyInterceptPath -PathType Leaf) -Summary 'Busy-call interception verification script exists.' -Detail $busyInterceptPath),
    (New-CheckRecord -Name 'adb_present' -Passed (-not [string]::IsNullOrWhiteSpace($adbPath)) -Summary 'ADB executable is discoverable.' -Detail $adbPath)
)

$validationRuns = New-Object System.Collections.Generic.List[object]

if ($RunLint) {
    $result = Invoke-RepoCommand -FilePath $gradlewPath -Arguments @('lintDebug', '--console=plain', '--no-daemon')
    $validationRuns.Add([pscustomobject]@{
            name = 'lintDebug'
            executed = $true
            passed = ($result.exit_code -eq 0)
            exit_code = $result.exit_code
            summary = if ($result.exit_code -eq 0) { 'lintDebug passed.' } else { 'lintDebug failed.' }
            detail = (($result.stderr + [Environment]::NewLine + $result.stdout).Trim())
        }) | Out-Null
}
else {
    $validationRuns.Add([pscustomobject]@{
            name = 'lintDebug'
            executed = $false
            passed = $false
            exit_code = -1
            summary = 'lintDebug skipped.'
            detail = ''
        }) | Out-Null
}

if ($RunBuild) {
    $result = Invoke-RepoCommand -FilePath $gradlewPath -Arguments @('assembleDebug', '--console=plain', '--no-daemon')
    $validationRuns.Add([pscustomobject]@{
            name = 'assembleDebug'
            executed = $true
            passed = ($result.exit_code -eq 0)
            exit_code = $result.exit_code
            summary = if ($result.exit_code -eq 0) { 'assembleDebug passed.' } else { 'assembleDebug failed.' }
            detail = (($result.stderr + [Environment]::NewLine + $result.stdout).Trim())
        }) | Out-Null
}
else {
    $validationRuns.Add([pscustomobject]@{
            name = 'assembleDebug'
            executed = $false
            passed = $false
            exit_code = -1
            summary = 'assembleDebug skipped.'
            detail = ''
        }) | Out-Null
}

if ($RunDeviceSmoke) {
    $result = Invoke-RepoCommand -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $lintScriptPath)
    $validationRuns.Add([pscustomobject]@{
            name = 'device_smoke_test'
            executed = $true
            passed = ($result.exit_code -eq 0)
            exit_code = $result.exit_code
            summary = if ($result.exit_code -eq 0) { 'Device smoke passed.' } else { 'Device smoke failed.' }
            detail = (($result.stderr + [Environment]::NewLine + $result.stdout).Trim())
        }) | Out-Null
}
else {
    $validationRuns.Add([pscustomobject]@{
            name = 'device_smoke_test'
            executed = $false
            passed = $false
            exit_code = -1
            summary = 'Device smoke skipped.'
            detail = ''
        }) | Out-Null
}

if ($RunRegression) {
    $result = Invoke-RepoCommand -FilePath 'powershell.exe' -Arguments @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $regressionScriptPath, '-Iterations', '1')
    $validationRuns.Add([pscustomobject]@{
            name = 'automated_dialog_regression'
            executed = $true
            passed = ($result.exit_code -eq 0)
            exit_code = $result.exit_code
            summary = if ($result.exit_code -eq 0) { 'Automated dialog regression passed.' } else { 'Automated dialog regression failed.' }
            detail = (($result.stderr + [Environment]::NewLine + $result.stdout).Trim())
        }) | Out-Null
}
else {
    $validationRuns.Add([pscustomobject]@{
            name = 'automated_dialog_regression'
            executed = $false
            passed = $false
            exit_code = -1
            summary = 'Automated dialog regression skipped.'
            detail = ''
        }) | Out-Null
}

$connectedDevicesCount = 0
if (-not [string]::IsNullOrWhiteSpace($adbPath)) {
    try {
        $adbDevices = & $adbPath devices
        $connectedDevicesCount = @($adbDevices | Where-Object { $_ -match '\tdevice$' }).Count
    }
    catch {
        $connectedDevicesCount = 0
    }
}

$recoveryActions = @(
    [pscustomobject]@{ name = 'soft_restart'; command = 'adb shell am force-stop com.dave.callguardian ; adb shell am start -n com.dave.callguardian/.MainActivity'; use_when = 'UI shell is stale or communicator is not responding.' },
    [pscustomobject]@{ name = 'rebuild_reinstall'; command = './gradlew.bat assembleDebug ; adb install -r ./app/build/outputs/apk/debug/app-debug.apk'; use_when = 'Deployed app build may be stale or inconsistent with source head.' },
    [pscustomobject]@{ name = 'device_smoke'; command = 'powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/device_smoke_test.ps1'; use_when = 'Need a quick launch/build/crash-tail confidence check.' },
    [pscustomobject]@{ name = 'dialog_regression'; command = 'powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1'; use_when = 'Need end-to-end behavior validation across call/text scenarios.' },
    [pscustomobject]@{ name = 'busy_intercept_verify'; command = 'powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/verify_busy_intercept.ps1 -WaitSeconds 90'; use_when = 'Need to validate active-call interception and busy SMS handoff.' }
)

$allQuickChecksPassed = (@($checks | Where-Object { -not [bool]$_.passed }).Count -eq 0)
$allExecutedValidationPassed = (@($validationRuns | Where-Object { [bool]$_.executed -and -not [bool]$_.passed }).Count -eq 0)

$normalizedProjectRoot = ([string]$resolvedProjectRoot) -replace '\\', '/'
$normalizedAdbPath = if ([string]::IsNullOrWhiteSpace([string]$adbPath)) {
    ''
}
else {
    ([string]$adbPath) -replace '\\', '/'
}

$quickChecksArray = @($checks | ForEach-Object { $_ })
$validationRunsArray = @($validationRuns | ForEach-Object { $_ })
$recoveryActionsArray = @($recoveryActions | ForEach-Object { $_ })

$summaryObject = [pscustomobject]@{
    quick_checks_passed = $allQuickChecksPassed
    executed_validation_passed = $allExecutedValidationPassed
    build_requested = [bool]$RunBuild
    lint_requested = [bool]$RunLint
    device_smoke_requested = [bool]$RunDeviceSmoke
    regression_requested = [bool]$RunRegression
}

$report = New-Object psobject
$report | Add-Member -NotePropertyName 'generated_at' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o'))
$report | Add-Member -NotePropertyName 'source' -NotePropertyValue 'tod-mim-assist-health-check-v1'
$report | Add-Member -NotePropertyName 'project_root' -NotePropertyValue $normalizedProjectRoot
$report | Add-Member -NotePropertyName 'adb_path' -NotePropertyValue $normalizedAdbPath
$report | Add-Member -NotePropertyName 'connected_devices_count' -NotePropertyValue ([int]$connectedDevicesCount)
$report | Add-Member -NotePropertyName 'quick_checks' -NotePropertyValue $quickChecksArray
$report | Add-Member -NotePropertyName 'validation_runs' -NotePropertyValue $validationRunsArray
$report | Add-Member -NotePropertyName 'recovery_actions' -NotePropertyValue $recoveryActionsArray
$report | Add-Member -NotePropertyName 'summary' -NotePropertyValue $summaryObject

$jsonPath = Join-Path $resolvedOutputRoot 'mim-assist-health-check.latest.json'
$mdPath = Join-Path $resolvedOutputRoot 'mim-assist-health-check.latest.md'

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add('# MIM Assist Health Check') | Out-Null
$markdown.Add('') | Out-Null
$markdown.Add(('- Generated at: {0}' -f [string]$report.generated_at)) | Out-Null
$markdown.Add(('- Project root: `{0}`' -f [string]$report.project_root)) | Out-Null
$markdown.Add(('- ADB path: `{0}`' -f [string]$report.adb_path)) | Out-Null
$markdown.Add(('- Connected devices: {0}' -f [int]$report.connected_devices_count)) | Out-Null
$markdown.Add('') | Out-Null
$markdown.Add('## Quick Checks') | Out-Null
$markdown.Add('') | Out-Null
foreach ($check in @($checks)) {
    $status = if ([bool]$check.passed) { 'PASS' } else { 'FAIL' }
    $markdown.Add(('- [{0}] {1} - {2}' -f $status, [string]$check.name, [string]$check.summary)) | Out-Null
}
$markdown.Add('') | Out-Null
$markdown.Add('## Validation Runs') | Out-Null
$markdown.Add('') | Out-Null
foreach ($item in $validationRunsArray) {
    $status = if (-not [bool]$item.executed) { 'SKIPPED' } elseif ([bool]$item.passed) { 'PASS' } else { 'FAIL' }
    $markdown.Add(('- [{0}] {1} - {2}' -f $status, [string]$item.name, [string]$item.summary)) | Out-Null
}
$markdown.Add('') | Out-Null
$markdown.Add('## Recovery Actions') | Out-Null
$markdown.Add('') | Out-Null
foreach ($action in $recoveryActionsArray) {
    $markdown.Add(('- `{0}` - {1}' -f [string]$action.name, [string]$action.use_when)) | Out-Null
    $markdown.Add(('  Command: `{0}`' -f [string]$action.command)) | Out-Null
}

Write-JsonNoBom -PathValue $jsonPath -Payload $report -Depth 20
Write-TextNoBom -PathValue $mdPath -Content ($markdown -join [Environment]::NewLine)

$result = [pscustomobject]@{
    ok = $true
    generated_at = $report.generated_at
    source = $report.source
    report_json = $jsonPath
    report_markdown = $mdPath
    quick_checks_passed = $report.summary.quick_checks_passed
    executed_validation_passed = $report.summary.executed_validation_passed
    connected_devices_count = $connectedDevicesCount
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 10 | Write-Output
}
else {
    $result
}