param(
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$CampaignRoot = 'tod/out/training/autonomous-campaign',
    [int]$TotalDays = 12,
    [string]$TaskName = '',
    [switch]$AutoDisableTask,
    [double]$RunbookDurationHours = 6,
    [double]$BundleSimulationDurationHours = 0.75,
    [int]$DefaultCommunicationIterations = 36,
    [int]$DefaultSocialConversationCount = 18000,
    [bool]$DefaultUseAssist = $true,
    [switch]$SkipStartupHealth,
    [switch]$SkipRunbook,
    [switch]$SkipSimulationBundle,
    [switch]$SkipProjectDiscovery,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
$runbookScript = Join-Path $PSScriptRoot 'Invoke-TODTrainingRunbook6h.ps1'
$supervisedScript = Join-Path $PSScriptRoot 'Invoke-TODSupervisedExecution.ps1'
$bundleScript = Join-Path $PSScriptRoot 'Invoke-TODAutonomousSimulationBundle.ps1'

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-TrainingDirectory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 30
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-TrainingDirectory -PathValue $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
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

function Get-DefaultPlan {
    return [ordered]@{
        runbook_duration_hours = $RunbookDurationHours
        bundle_simulation_duration_hours = $BundleSimulationDurationHours
        initiative_self_questions = 28
        initiative_max_objectives = 3
        initiative_live_grounding_target = 0.77
        communication_iterations = $DefaultCommunicationIterations
        social_conversation_count = $DefaultSocialConversationCount
        use_assist = [bool]$DefaultUseAssist
        social_domains = @('coding', 'python_dev', 'java_dev', 'software_architecture', 'software_planning', 'implementation_delivery', 'quality_engineering', 'technology', 'science', 'math')
    }
}

function Get-CampaignState {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$CampaignRootPath
    )

    $existing = Read-JsonFileIfExists -PathValue $StatePath
    if ($null -ne $existing) {
        return $existing
    }

    $defaultPlan = Get-DefaultPlan
    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        source = 'tod-autonomous-training-campaign-v1'
        campaign_root = $CampaignRootPath
        total_days = $TotalDays
        completed_days = 0
        status = 'active'
        last_run_utc = ''
        latest_report_path = ''
        next_day_plan = [pscustomobject]$defaultPlan
        days = @()
    }
}

function Save-CampaignState {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)]$State
    )

    $State.total_days = $TotalDays
    Write-Utf8NoBomJson -PathValue $StatePath -Payload $State -Depth 40
}

function Get-OptimizedPlan {
    param(
        [Parameter(Mandatory = $true)]$CurrentPlan,
        [Parameter(Mandatory = $true)]$DailyReport
    )

    $plan = [ordered]@{
        runbook_duration_hours = [double]$CurrentPlan.runbook_duration_hours
        bundle_simulation_duration_hours = [double]$CurrentPlan.bundle_simulation_duration_hours
        initiative_self_questions = [int]$CurrentPlan.initiative_self_questions
        initiative_max_objectives = [int]$CurrentPlan.initiative_max_objectives
        initiative_live_grounding_target = [double]$CurrentPlan.initiative_live_grounding_target
        communication_iterations = [int]$CurrentPlan.communication_iterations
        social_conversation_count = [int]$CurrentPlan.social_conversation_count
        use_assist = [bool]$CurrentPlan.use_assist
        social_domains = @($CurrentPlan.social_domains)
    }

    if ($DailyReport.runbook -and @($DailyReport.runbook.stop_conditions).Count -gt 0) {
        $plan.bundle_simulation_duration_hours = [math]::Min(1.5, [double]$plan.bundle_simulation_duration_hours + 0.25)
        $plan.initiative_self_questions = [math]::Min(80, [int]$plan.initiative_self_questions + 8)
        $plan.communication_iterations = [math]::Min(120, [int]$plan.communication_iterations + 8)
    }

    $bundle = $DailyReport.simulation_bundle
    if ($bundle -and $bundle.steps) {
        $communicationStep = @($bundle.steps | Where-Object { $_.name -eq 'mim_communication_soak' } | Select-Object -First 1)
        if (@($communicationStep).Count -gt 0 -and -not [bool]$communicationStep[0].ok) {
            $plan.communication_iterations = [math]::Min(120, [int]$plan.communication_iterations + 12)
        }

        $projectStep = @($bundle.steps | Where-Object { $_.name -eq 'github_project_simulation' } | Select-Object -First 1)
        if (@($projectStep).Count -gt 0 -and $projectStep[0].payload -and $projectStep[0].payload.PSObject.Properties['publish_ready_count']) {
            $publishReady = [int]$projectStep[0].payload.publish_ready_count
            $scenarioCount = if ($projectStep[0].payload.PSObject.Properties['scenario_count']) { [int]$projectStep[0].payload.scenario_count } else { 0 }
            if ($scenarioCount -gt 0 -and $publishReady -lt $scenarioCount) {
                $plan.use_assist = $true
                $plan.initiative_max_objectives = [math]::Min(5, [int]$plan.initiative_max_objectives + 1)
            }
        }

        $socialStep = @($bundle.steps | Where-Object { $_.name -eq 'social_conversation_simulation' } | Select-Object -First 1)
        if (@($socialStep).Count -gt 0) {
            if (-not [bool]$socialStep[0].ok) {
                $plan.social_conversation_count = [math]::Min(120000, [int]$plan.social_conversation_count + 12000)
                $plan.initiative_live_grounding_target = [math]::Min(0.9, [double]$plan.initiative_live_grounding_target + 0.02)
            }
        }

        $executionStep = @($bundle.steps | Where-Object { $_.name -eq 'mim_execution_simulation' } | Select-Object -First 1)
        if (@($executionStep).Count -gt 0 -and -not [bool]$executionStep[0].ok) {
            $plan.bundle_simulation_duration_hours = [math]::Min(1.5, [double]$plan.bundle_simulation_duration_hours + 0.25)
        }
    }

    return [pscustomobject]$plan
}

$resolvedConfigPath = Resolve-RepoPath -PathValue $ConfigPath
$resolvedCampaignRoot = Resolve-RepoPath -PathValue $CampaignRoot
New-TrainingDirectory -PathValue $resolvedCampaignRoot
$campaignStatePath = Join-Path $resolvedCampaignRoot 'campaign-state.json'
$campaignIndexPath = Join-Path $resolvedCampaignRoot 'campaign-summary.latest.md'

$campaignState = Get-CampaignState -StatePath $campaignStatePath -CampaignRootPath $resolvedCampaignRoot
if ([int]$campaignState.completed_days -ge $TotalDays) {
    $campaignState.status = 'completed'
    Save-CampaignState -StatePath $campaignStatePath -State $campaignState
    if ($AutoDisableTask -and -not [string]::IsNullOrWhiteSpace($TaskName)) {
        try {
            Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
        }
    }

    $noOp = [pscustomobject]@{
        ok = $true
        action = 'no_op_campaign_completed'
        completed_days = [int]$campaignState.completed_days
        total_days = [int]$campaignState.total_days
        campaign_state_path = $campaignStatePath
    }

    if ($EmitJson) {
        $noOp | ConvertTo-Json -Depth 12 | Write-Output
    }
    else {
        $noOp
    }
    return
}

$dayNumber = [int]$campaignState.completed_days + 1
$dayDir = Join-Path $resolvedCampaignRoot ('day-' + $dayNumber.ToString('00'))
New-TrainingDirectory -PathValue $dayDir
$dailyReportPath = Join-Path $dayDir 'daily-report.json'
$dailySummaryPath = Join-Path $dayDir 'daily-summary.md'
$activePlan = if ($campaignState.PSObject.Properties['next_day_plan'] -and $null -ne $campaignState.next_day_plan) { $campaignState.next_day_plan } else { [pscustomobject](Get-DefaultPlan) }

$dailyReport = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-autonomous-training-campaign-daily-v1'
    campaign_root = $resolvedCampaignRoot
    campaign_state_path = $campaignStatePath
    day_number = $dayNumber
    total_days = $TotalDays
    plan = $activePlan
    startup_health = $null
    runbook = $null
    simulation_bundle = $null
    ok = $false
    errors = @()
    next_day_plan = $null
}

if (-not $SkipStartupHealth) {
    try {
        $startupHealth = Invoke-JsonPowerShellScript -ScriptPath $supervisedScript -Arguments @{
            ImplementationConfigPath = $resolvedConfigPath
            ImplementationOutputDir = (Join-Path $dayDir 'startup-health')
            RefreshMimContextFromSsh = $true
            SkipTests = $true
            RunReportPath = (Join-Path $dayDir 'startup-health/tod_supervised_execution.latest.json')
        }
        $dailyReport.startup_health = $startupHealth
    }
    catch {
        $dailyReport.errors += @('startup_health: ' + [string]$_.Exception.Message)
    }
}

if (-not $SkipRunbook) {
    try {
        $runbookArgs = @{
            ConfigPath = $resolvedConfigPath
            OutputDir = (Join-Path $dayDir 'runbook')
            DurationHours = [double]$activePlan.runbook_duration_hours
        }
        if ($SkipProjectDiscovery) {
            $runbookArgs.SkipProjectDiscovery = $true
        }
        $dailyReport.runbook = Invoke-JsonPowerShellScript -ScriptPath $runbookScript -Arguments $runbookArgs
    }
    catch {
        $dailyReport.errors += @('runbook: ' + [string]$_.Exception.Message)
    }
}

if (-not $SkipSimulationBundle) {
    try {
        $bundleArgs = @{
            ConfigPath = $resolvedConfigPath
            OutputDir = (Join-Path $dayDir 'simulation-bundle')
            SimulationDurationHours = [double]$activePlan.bundle_simulation_duration_hours
            InitiativeSelfQuestionCount = [int]$activePlan.initiative_self_questions
            InitiativeMaxObjectives = [int]$activePlan.initiative_max_objectives
            InitiativeLiveGroundingTarget = [double]$activePlan.initiative_live_grounding_target
            CommunicationIterations = [int]$activePlan.communication_iterations
            SocialConversationCount = [int]$activePlan.social_conversation_count
            SocialDomains = @($activePlan.social_domains)
            EmitJson = $true
        }
        if ($true -eq [bool]$activePlan.use_assist) {
            $bundleArgs.UseAssist = $true
        }
        $dailyReport.simulation_bundle = Invoke-JsonPowerShellScript -ScriptPath $bundleScript -Arguments $bundleArgs
    }
    catch {
        $dailyReport.errors += @('simulation_bundle: ' + [string]$_.Exception.Message)
    }
}

$hasRunbook = $SkipRunbook -or ($null -ne $dailyReport.runbook)
$hasSimulationBundle = $SkipSimulationBundle -or ($null -ne $dailyReport.simulation_bundle)
$dailyReport.ok = (@($dailyReport.errors).Count -eq 0) -and $hasRunbook -and $hasSimulationBundle
$dailyReport.next_day_plan = Get-OptimizedPlan -CurrentPlan $activePlan -DailyReport ([pscustomobject]$dailyReport)
$dailyReport.completed_at = (Get-Date).ToUniversalTime().ToString('o')

$startupHealthStatus = if ($SkipStartupHealth) { 'skipped' } elseif ($null -ne $dailyReport.startup_health) { 'completed' } else { 'failed_or_not_captured' }
$runbookStatus = if ($SkipRunbook) { 'skipped' } elseif ($null -ne $dailyReport.runbook) { 'completed' } else { 'failed_or_not_captured' }
$simulationBundleStatus = if ($SkipSimulationBundle) { 'skipped' } elseif ($null -ne $dailyReport.simulation_bundle) { 'completed' } else { 'failed_or_not_captured' }

$summaryLines = @(
    '# TOD Autonomous Daily Training Report',
    '',
    ('Day: {0}/{1}' -f [string]$dayNumber, [string]$TotalDays),
    ('Generated: {0}' -f [string]$dailyReport.generated_at),
    ('Completed: {0}' -f [string]$dailyReport.completed_at),
    ('Overall OK: {0}' -f [string]$dailyReport.ok),
    ('Errors: {0}' -f [string]@($dailyReport.errors).Count),
    '',
    '## Daily Results',
    ('- Startup health: {0}' -f [string]$startupHealthStatus),
    ('- Runbook: {0}' -f [string]$runbookStatus),
    ('- Runbook outcome: {0}' -f $(if ($dailyReport.runbook) { [string]$dailyReport.runbook.outcome } else { 'n/a' })),
    ('- Simulation bundle: {0}' -f [string]$simulationBundleStatus),
    ('- Simulation bundle ok: {0}' -f $(if ($dailyReport.simulation_bundle) { [string]$dailyReport.simulation_bundle.ok } else { 'n/a' }))
)

if (@($dailyReport.errors).Count -gt 0) {
    $summaryLines += ''
    $summaryLines += '## Errors'
    foreach ($entry in @($dailyReport.errors)) {
        $summaryLines += ('- ' + [string]$entry)
    }
}

$summaryLines += ''
$summaryLines += '## Next-Day Tuning'
$summaryLines += ('- Communication iterations: {0}' -f [string]$dailyReport.next_day_plan.communication_iterations)
$summaryLines += ('- Social conversation count: {0}' -f [string]$dailyReport.next_day_plan.social_conversation_count)
$summaryLines += ('- Bundle simulation duration hours: {0}' -f [string]$dailyReport.next_day_plan.bundle_simulation_duration_hours)
$summaryLines += ('- Use assist: {0}' -f [string]$dailyReport.next_day_plan.use_assist)

Write-Utf8NoBomJson -PathValue $dailyReportPath -Payload ([pscustomobject]$dailyReport) -Depth 40
[System.IO.File]::WriteAllLines($dailySummaryPath, $summaryLines, (New-Object System.Text.UTF8Encoding($false)))

$dayEntry = [pscustomobject]@{
    day_number = $dayNumber
    generated_at = [string]$dailyReport.generated_at
    completed_at = [string]$dailyReport.completed_at
    ok = [bool]$dailyReport.ok
    report_path = $dailyReportPath
    summary_path = $dailySummaryPath
    runbook_outcome = if ($dailyReport.runbook) { [string]$dailyReport.runbook.outcome } else { '' }
    error_count = @($dailyReport.errors).Count
}

$campaignState.completed_days = $dayNumber
$campaignState.last_run_utc = [string]$dailyReport.completed_at
$campaignState.latest_report_path = $dailyReportPath
$campaignState.status = if ($dayNumber -ge $TotalDays) { 'completed' } else { 'active' }
$campaignState.next_day_plan = $dailyReport.next_day_plan
$campaignState.days = @($campaignState.days) + @($dayEntry)

Save-CampaignState -StatePath $campaignStatePath -State $campaignState

$indexLines = @(
    '# TOD Autonomous Campaign Summary',
    '',
    ('Campaign Root: {0}' -f $resolvedCampaignRoot),
    ('Status: {0}' -f [string]$campaignState.status),
    ('Completed Days: {0}/{1}' -f [string]$campaignState.completed_days, [string]$TotalDays),
    ('Latest Report: {0}' -f $dailyReportPath),
    '',
    '## Days'
)
foreach ($entry in @($campaignState.days)) {
    $indexLines += ('- day {0}: ok={1}; runbook_outcome={2}; errors={3}; report={4}' -f [string]$entry.day_number, [string]$entry.ok, [string]$entry.runbook_outcome, [string]$entry.error_count, [string]$entry.report_path)
}
[System.IO.File]::WriteAllLines($campaignIndexPath, $indexLines, (New-Object System.Text.UTF8Encoding($false)))

if ($AutoDisableTask -and -not [string]::IsNullOrWhiteSpace($TaskName) -and $dayNumber -ge $TotalDays) {
    try {
        Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
    }
}

if ($EmitJson) {
    ([pscustomobject]$dailyReport) | ConvertTo-Json -Depth 40 | Write-Output
}
else {
    [pscustomobject]$dailyReport
}