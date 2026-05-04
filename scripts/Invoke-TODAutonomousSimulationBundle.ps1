param(
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$OutputDir = 'tod/out/training/autonomous-simulation/latest',
    [double]$SimulationDurationHours = 0.5,
    [int]$InitiativeSelfQuestionCount = 24,
    [int]$InitiativeMaxObjectives = 2,
    [double]$InitiativeLiveGroundingTarget = 0.75,
    [int]$CommunicationIterations = 24,
    [int]$SocialConversationCount = 12000,
    [string[]]$SocialDomains = @('coding', 'python_dev', 'java_dev', 'software_architecture', 'software_planning', 'implementation_delivery', 'quality_engineering', 'technology'),
    [switch]$UseAssist,
    [switch]$SkipSimulationMode,
    [switch]$SkipInitiativeTraining,
    [switch]$SkipExecutionSimulation,
    [switch]$SkipProjectSimulation,
    [switch]$SkipRepoEditRecoverSimulation,
    [switch]$SkipCommunicationSoak,
    [switch]$SkipSocialSimulation,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$simulationModeScript = Join-Path $PSScriptRoot 'Start-TODTrainingSimulationMode.ps1'
$initiativeScript = Join-Path $PSScriptRoot 'Invoke-TODInitiativeTraining.ps1'
$executionSimulationScript = Join-Path $PSScriptRoot 'Invoke-TODMimExecutionSimulation.ps1'
$projectSimulationScript = Join-Path $PSScriptRoot 'Invoke-TODGitHubProjectSimulationDaily.ps1'
$repoEditRecoverSimulationScript = Join-Path $PSScriptRoot 'Invoke-TODRepoEditTestRecoverSimulationDaily.ps1'
$communicationScript = Join-Path $PSScriptRoot 'Invoke-TODMimCommunicationSimulationSoak.ps1'
$socialSimulationScript = Join-Path $PSScriptRoot 'Invoke-TODSocialConversationSimulation.ps1'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-DirectoryIfMissing -PathValue $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function ConvertFrom-JsonLoose {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $trimmed = $Text.Trim()
    try {
        return ($trimmed | ConvertFrom-Json)
    }
    catch {
    }

    $firstBrace = $trimmed.IndexOf('{')
    $firstBracket = $trimmed.IndexOf('[')
    $startIndex = -1
    if ($firstBrace -ge 0 -and $firstBracket -ge 0) {
        $startIndex = [Math]::Min($firstBrace, $firstBracket)
    }
    elseif ($firstBrace -ge 0) {
        $startIndex = $firstBrace
    }
    elseif ($firstBracket -ge 0) {
        $startIndex = $firstBracket
    }

    if ($startIndex -lt 0) {
        return $null
    }

    try {
        return ($trimmed.Substring($startIndex) | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Invoke-JsonPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $invocationArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    foreach ($entry in ($Arguments.GetEnumerator() | Sort-Object Key)) {
        $name = [string]$entry.Key
        $value = $entry.Value

        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ([bool]$value.IsPresent) {
                $invocationArgs += ('-' + $name)
            }
            continue
        }

        if ($value -is [bool]) {
            if ([bool]$value) {
                $invocationArgs += ('-' + $name)
            }
            continue
        }

        if ($null -eq $value) {
            continue
        }

        if ($value -is [System.Array] -and -not ($value -is [string])) {
            $invocationArgs += ('-' + $name)
            foreach ($item in @($value)) {
                $invocationArgs += [string]$item
            }
            continue
        }

        $invocationArgs += ('-' + $name)
        $invocationArgs += [string]$value
    }

    $rawOutput = & $powershellExe @invocationArgs 2>&1 | Out-String
    $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) {
        throw ("Script failed with exit code {0}: {1}`n{2}" -f $exitCode, $ScriptPath, $rawOutput.Trim())
    }

    return (ConvertFrom-JsonLoose -Text $rawOutput)
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $stepStart = (Get-Date).ToUniversalTime()
    try {
        $payload = & $Action
        return [pscustomobject]@{
            name = $Name
            ok = $true
            started_at = $stepStart.ToString('o')
            completed_at = (Get-Date).ToUniversalTime().ToString('o')
            payload = $payload
            error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            name = $Name
            ok = $false
            started_at = $stepStart.ToString('o')
            completed_at = (Get-Date).ToUniversalTime().ToString('o')
            payload = $null
            error = [string]$_.Exception.Message
        }
    }
}

$resolvedConfigPath = Resolve-RepoPath -PathValue $ConfigPath
$resolvedOutputDir = Resolve-RepoPath -PathValue $OutputDir
New-DirectoryIfMissing -PathValue $resolvedOutputDir

$reportPath = Join-Path $resolvedOutputDir 'autonomous-simulation-bundle.report.json'
$summaryPath = Join-Path $resolvedOutputDir 'autonomous-simulation-bundle.summary.md'
$steps = @()

if (-not $SkipInitiativeTraining) {
    $steps += Invoke-Step -Name 'initiative_training' -Action {
        Invoke-JsonPowerShellScript -ScriptPath $initiativeScript -Arguments @{
            ConfigPath = $resolvedConfigPath
            OutputRoot = (Join-Path $resolvedOutputDir 'initiative-training')
            SelfQuestionCount = $InitiativeSelfQuestionCount
            MaxObjectivesToExecute = $InitiativeMaxObjectives
            LiveGroundingTarget = $InitiativeLiveGroundingTarget
            EmitJson = $true
        }
    }
}

if (-not $SkipSimulationMode) {
    $steps += Invoke-Step -Name 'simulation_mode' -Action {
        Invoke-JsonPowerShellScript -ScriptPath $simulationModeScript -Arguments @{
            ConfigPath = $resolvedConfigPath
            DurationHours = $SimulationDurationHours
            CycleDelaySeconds = 90
            ValidationCadence = 12
        }
    }
}

if (-not $SkipExecutionSimulation) {
    $steps += Invoke-Step -Name 'mim_execution_simulation' -Action {
        Invoke-JsonPowerShellScript -ScriptPath $executionSimulationScript -Arguments @{
            Scenario = 'all'
            OutputRoot = (Join-Path $resolvedOutputDir 'execution-simulation')
        }
    }
}

if (-not $SkipProjectSimulation) {
    $steps += Invoke-Step -Name 'github_project_simulation' -Action {
        $arguments = @{
            OutputRoot = (Join-Path $resolvedOutputDir 'github-project-simulation')
            EmitJson = $true
        }
        if ($UseAssist) {
            $arguments.UseAssist = $true
        }
        Invoke-JsonPowerShellScript -ScriptPath $projectSimulationScript -Arguments $arguments
    }
}

if (-not $SkipRepoEditRecoverSimulation) {
    $steps += Invoke-Step -Name 'repo_edit_test_recover_simulation' -Action {
        $arguments = @{
            OutputRoot = (Join-Path $resolvedOutputDir 'repo-edit-test-recover')
            EmitJson = $true
        }
        if ($UseAssist) {
            $arguments.UseAssist = $true
        }
        Invoke-JsonPowerShellScript -ScriptPath $repoEditRecoverSimulationScript -Arguments $arguments
    }
}

if (-not $SkipCommunicationSoak) {
    $steps += Invoke-Step -Name 'mim_communication_soak' -Action {
        Invoke-JsonPowerShellScript -ScriptPath $communicationScript -Arguments @{
            Iterations = $CommunicationIterations
            Scenario = 'all'
            OutputRoot = (Join-Path $resolvedOutputDir 'communication-soak')
            EmitJson = $true
        }
    }
}

if (-not $SkipSocialSimulation) {
    $steps += Invoke-Step -Name 'social_conversation_simulation' -Action {
        Invoke-JsonPowerShellScript -ScriptPath $socialSimulationScript -Arguments @{
            ConversationCount = $SocialConversationCount
            OutputRoot = (Join-Path $resolvedOutputDir 'social-simulation')
            IncludeDomains = $SocialDomains
            EnableLiveFetch = $true
            LiveFetchSamplesPerCheckpoint = 2
            EmitJson = $true
        }
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-autonomous-simulation-bundle-v1'
    config_path = $resolvedConfigPath
    output_dir = $resolvedOutputDir
    ok = (-not (@($steps | Where-Object { -not [bool]$_.ok }).Count -gt 0))
    step_count = @($steps).Count
    failed_step_count = @($steps | Where-Object { -not [bool]$_.ok }).Count
    steps = @($steps)
    summary = [pscustomobject]@{
        initiative_ok = [bool](@($steps | Where-Object { $_.name -eq 'initiative_training' -and [bool]$_.ok }).Count -gt 0)
        simulation_mode_ok = [bool](@($steps | Where-Object { $_.name -eq 'simulation_mode' -and [bool]$_.ok }).Count -gt 0)
        execution_simulation_ok = [bool](@($steps | Where-Object { $_.name -eq 'mim_execution_simulation' -and [bool]$_.ok }).Count -gt 0)
        project_simulation_ok = [bool](@($steps | Where-Object { $_.name -eq 'github_project_simulation' -and [bool]$_.ok }).Count -gt 0)
        repo_edit_recover_simulation_ok = [bool](@($steps | Where-Object { $_.name -eq 'repo_edit_test_recover_simulation' -and [bool]$_.ok }).Count -gt 0)
        communication_ok = [bool](@($steps | Where-Object { $_.name -eq 'mim_communication_soak' -and [bool]$_.ok }).Count -gt 0)
        social_ok = [bool](@($steps | Where-Object { $_.name -eq 'social_conversation_simulation' -and [bool]$_.ok }).Count -gt 0)
    }
}

$summaryLines = @(
    '# TOD Autonomous Simulation Bundle',
    '',
    ('Generated: {0}' -f [string]$report.generated_at),
    ('Output Dir: {0}' -f [string]$report.output_dir),
    ('Overall OK: {0}' -f [string]$report.ok),
    ('Failed Steps: {0}' -f [string]$report.failed_step_count),
    '',
    '## Steps'
)
foreach ($step in @($steps)) {
    $summaryLines += ('- {0}: ok={1}; error={2}' -f [string]$step.name, [string]$step.ok, $(if ([string]::IsNullOrWhiteSpace([string]$step.error)) { 'none' } else { [string]$step.error }))
}

Write-Utf8NoBomJson -PathValue $reportPath -Payload $report -Depth 24
[System.IO.File]::WriteAllLines($summaryPath, $summaryLines, (New-Object System.Text.UTF8Encoding($false)))

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 24 | Write-Output
}
else {
    $report
}