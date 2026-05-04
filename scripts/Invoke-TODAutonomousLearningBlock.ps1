param(
    [double]$DurationHours = 6,
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$BasePromptSetPath = 'tod/config/tod-stale-recovery-prompts-2026-04-14.json',
    [string]$FocusedPromptSetPath = '',
    [string]$OutputRoot = 'tod/out/training/autonomous-learning-block',
    [int]$VariantsPerCriticalPrompt = 8,
    [int]$SocialConversationCount = 2000000,
    [switch]$EnableSocialSimulation,
    [switch]$SkipProjectDiscovery,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$promptGeneratorScript = Join-Path $PSScriptRoot 'New-TODFocusedStaleRecoveryPromptSet.ps1'
$promptRunScript = Join-Path $PSScriptRoot 'Invoke-TODStaleRecoveryPromptRun.ps1'
$promptScoreScript = Join-Path $PSScriptRoot 'Invoke-TODStaleRecoveryPromptScore.ps1'
$trainingLoopScript = Join-Path $PSScriptRoot 'Invoke-TODTrainingLoop.ps1'
$supervisedScript = Join-Path $PSScriptRoot 'Invoke-TODSupervisedExecution.ps1'
$socialSimulationScript = Join-Path $PSScriptRoot 'Invoke-TODSocialConversationSimulation.ps1'

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
        [int]$Depth = 25
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Save-ReportSnapshot {
    param(
        [Parameter(Mandatory = $true)]$ReportObject,
        [Parameter(Mandatory = $true)][string]$PathValue
    )

    Write-JsonNoBom -PathValue $PathValue -Payload ([pscustomobject]$ReportObject) -Depth 30
}

function ConvertFrom-JsonLoose {
    param([Parameter(Mandatory = $true)][string]$Text)

    $trimmed = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    try {
        return ($trimmed | ConvertFrom-Json)
    }
    catch {
    }

    $candidateIndexes = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $trimmed.Length; $index++) {
        $char = $trimmed[$index]
        if ($char -eq '{' -or $char -eq '[') {
            $candidateIndexes.Add($index) | Out-Null
        }
    }

    for ($index = $candidateIndexes.Count - 1; $index -ge 0; $index--) {
        $startIndex = $candidateIndexes[$index]
        $candidate = $trimmed.Substring($startIndex)
        try {
            return ($candidate | ConvertFrom-Json)
        }
        catch {
        }
    }

    throw 'Unable to recover JSON payload from mixed output.'
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

function Add-TraceLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $line = '[{0}] {1}' -f ((Get-Date).ToUniversalTime().ToString('o')), $Message
    Add-Content -Path $Path -Value $line
    Write-Host $line
}

$resolvedConfigPath = Resolve-RepoPath -PathValue $ConfigPath
$resolvedBasePromptSetPath = Resolve-RepoPath -PathValue $BasePromptSetPath
$runStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$resolvedOutputRoot = Resolve-RepoPath -PathValue $OutputRoot
$runDir = Join-Path $resolvedOutputRoot $runStamp

if (-not (Test-Path -Path $runDir)) {
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
}

$tracePath = Join-Path $runDir 'autonomous-learning-trace.log'
$reportPath = Join-Path $runDir 'autonomous-learning-report.json'
$summaryPath = Join-Path $runDir 'autonomous-learning-summary.md'
$focusedPromptSetAbs = if ([string]::IsNullOrWhiteSpace($FocusedPromptSetPath)) {
    Join-Path $runDir 'tod-stale-recovery-prompts-focused.json'
}
else {
    Resolve-RepoPath -PathValue $FocusedPromptSetPath
}

$startUtc = (Get-Date).ToUniversalTime()
$deadlineUtc = $startUtc.AddHours([Math]::Max($DurationHours, 0.1))

$report = [ordered]@{
    generated_at = $startUtc.ToString('o')
    source = 'tod-autonomous-learning-block-v1'
    duration_hours = $DurationHours
    output_root = $runDir
    config_path = $resolvedConfigPath
    base_prompt_set_path = $resolvedBasePromptSetPath
    focused_prompt_set_path = $focusedPromptSetAbs
    cycles = @()
    social_simulation = $null
    errors = @()
}

Save-ReportSnapshot -ReportObject $report -PathValue $reportPath

Add-TraceLine -Path $tracePath -Message 'generating focused stale-recovery prompt set'
$focusedPromptSet = Invoke-JsonPowerShellScript -ScriptPath $promptGeneratorScript -Arguments @{
    BasePromptSetPath = $resolvedBasePromptSetPath
    OutputPath = $focusedPromptSetAbs
    VariantsPerCriticalPrompt = $VariantsPerCriticalPrompt
    EmitJson = $true
}
$report['focused_prompt_set'] = $focusedPromptSet
Save-ReportSnapshot -ReportObject $report -PathValue $reportPath

$cycleIndex = 0
try {
    Add-TraceLine -Path $tracePath -Message 'starting initial supervised checkpoint'
    $supervisedDir = Join-Path $runDir 'supervised-initial'
    if (-not (Test-Path -Path $supervisedDir)) {
        New-Item -ItemType Directory -Path $supervisedDir -Force | Out-Null
    }
    $initialSupervised = Invoke-JsonPowerShellScript -ScriptPath $supervisedScript -Arguments @{
        ImplementationConfigPath = $resolvedConfigPath
        ImplementationOutputDir = $supervisedDir
        RefreshMimContextFromSsh = $true
        RunReportPath = (Join-Path $supervisedDir 'tod_supervised_execution.latest.json')
    }
    $report['initial_supervised'] = $initialSupervised
    Save-ReportSnapshot -ReportObject $report -PathValue $reportPath

    while ((Get-Date).ToUniversalTime() -lt $deadlineUtc) {
        $cycleIndex += 1
        $cycleDir = Join-Path $runDir ('cycle-' + $cycleIndex.ToString('00'))
        if (-not (Test-Path -Path $cycleDir)) {
            New-Item -ItemType Directory -Path $cycleDir -Force | Out-Null
        }

        Add-TraceLine -Path $tracePath -Message ('cycle {0}: running focused stale-recovery prompt batch' -f $cycleIndex)
        $promptRunDir = Join-Path $cycleDir 'prompt-run'
        $promptRun = Invoke-JsonPowerShellScript -ScriptPath $promptRunScript -Arguments @{
            PromptSetPath = $focusedPromptSetAbs
            OutputDir = $promptRunDir
        }

        Add-TraceLine -Path $tracePath -Message ('cycle {0}: scoring focused stale-recovery prompt batch' -f $cycleIndex)
        $score = Invoke-JsonPowerShellScript -ScriptPath $promptScoreScript -Arguments @{
            RunDir = $promptRunDir
        }

        Add-TraceLine -Path $tracePath -Message ('cycle {0}: running bounded training loop' -f $cycleIndex)
        $trainingDir = Join-Path $cycleDir 'bounded-training'
        $trainingArgs = @{
            ConfigPath = $resolvedConfigPath
            OutputDir = $trainingDir
        }
        if ($SkipProjectDiscovery) {
            $trainingArgs.SkipProjectDiscovery = $true
        }
        $trainingLoop = Invoke-JsonPowerShellScript -ScriptPath $trainingLoopScript -Arguments $trainingArgs

        $cycleRecord = [pscustomobject]@{
            cycle_index = $cycleIndex
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
            prompt_run = $promptRun
            score = $score
            bounded_training = $trainingLoop
        }
        $report.cycles += @($cycleRecord)
        Save-ReportSnapshot -ReportObject $report -PathValue $reportPath

        if (($cycleIndex % 2) -eq 0 -and (Get-Date).ToUniversalTime() -lt $deadlineUtc) {
            Add-TraceLine -Path $tracePath -Message ('cycle {0}: running midpoint supervised checkpoint' -f $cycleIndex)
            $supervisedDir = Join-Path $cycleDir 'supervised'
            $supervisedRun = Invoke-JsonPowerShellScript -ScriptPath $supervisedScript -Arguments @{
                ImplementationConfigPath = $resolvedConfigPath
                ImplementationOutputDir = $supervisedDir
                RefreshMimContextFromSsh = $true
                RunReportPath = (Join-Path $supervisedDir 'tod_supervised_execution.latest.json')
            }
            $cycleRecord | Add-Member -NotePropertyName supervised -NotePropertyValue $supervisedRun
            Save-ReportSnapshot -ReportObject $report -PathValue $reportPath
        }

        $remainingMinutes = [int][Math]::Floor(($deadlineUtc - (Get-Date).ToUniversalTime()).TotalMinutes)
        if ($EnableSocialSimulation -and $null -eq $report.social_simulation -and $remainingMinutes -ge 90) {
            Add-TraceLine -Path $tracePath -Message 'starting secondary social conversation simulation lane'
            $socialOutputRoot = Join-Path $cycleDir 'social-simulation'
            $socialRun = Invoke-JsonPowerShellScript -ScriptPath $socialSimulationScript -Arguments @{
                ConversationCount = $SocialConversationCount
                OutputRoot = $socialOutputRoot
                IncludeDomains = @('coding', 'python_dev', 'java_dev', 'databases', 'software_planning', 'software_architecture', 'implementation_delivery', 'quality_engineering', 'technology', 'science', 'math')
                EnableLiveFetch = $true
                LiveFetchSamplesPerCheckpoint = 2
                EmitJson = $true
            }
            $report.social_simulation = $socialRun
            Save-ReportSnapshot -ReportObject $report -PathValue $reportPath
        }
    }
}
catch {
    $errorMessage = [string]$_.Exception.Message
    $report.errors += @($errorMessage)
    Add-TraceLine -Path $tracePath -Message ('error: ' + $errorMessage)
    Save-ReportSnapshot -ReportObject $report -PathValue $reportPath
}

$completedAt = (Get-Date).ToUniversalTime().ToString('o')
$cycleCount = @($report.cycles).Count
$lastScore = if ($cycleCount -gt 0) { $report.cycles[-1].score } else { $null }
$summaryLines = @(
    '# TOD Autonomous Learning Block',
    '',
    ('Generated at: {0}' -f $report.generated_at),
    ('Completed at: {0}' -f $completedAt),
    ('Focused prompt count: {0}' -f [string]$focusedPromptSet.prompt_count),
    ('Completed cycles: {0}' -f $cycleCount),
    ('Last critical count: {0}' -f $(if ($lastScore) { [string]$lastScore.critical_count } else { 'n/a' })),
    ('Last major count: {0}' -f $(if ($lastScore) { [string]$lastScore.major_count } else { 'n/a' })),
    ('Social simulation executed: {0}' -f [string]($null -ne $report.social_simulation)),
    ('Error count: {0}' -f [string]@($report.errors).Count)
)

[System.IO.File]::WriteAllLines($summaryPath, $summaryLines, (New-Object System.Text.UTF8Encoding($false)))
Save-ReportSnapshot -ReportObject $report -PathValue $reportPath

$result = [pscustomobject]@{
    ok = (@($report.errors).Count -eq 0)
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-autonomous-learning-block-v1'
    run_dir = $runDir
    focused_prompt_set = $focusedPromptSet
    cycle_count = $cycleCount
    last_score = $lastScore
    social_simulation_executed = ($null -ne $report.social_simulation)
    report_path = $reportPath
    trace_path = $tracePath
    summary_path = $summaryPath
    errors = @($report.errors)
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 20 | Write-Output
}
else {
    $result
}