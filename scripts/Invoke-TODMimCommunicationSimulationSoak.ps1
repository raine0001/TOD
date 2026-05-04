param(
    [int]$Iterations = 300,
    [ValidateSet('all', 'diagnostic_roundtrip', 'next_step_consensus_roundtrip', 'supersede_reissue_roundtrip', 'status_exchange_roundtrip', 'help_offer_roundtrip', 'blocker_assistance_roundtrip', 'emergency_assistance_roundtrip')]
    [string]$Scenario = 'all',
    [string]$OutputRoot = 'tod/out/tests/tod-mim-communication-soak',
    [switch]$StopOnFirstFailure,
    [switch]$FailOnFailure,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Iterations -le 0) {
    throw 'Iterations must be > 0'
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$simulationScript = Join-Path $PSScriptRoot 'Invoke-TODMimConversationSimulation.ps1'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
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

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

$outputRootAbs = Resolve-LocalPath -PathValue $OutputRoot
Ensure-Directory -PathValue $outputRootAbs

$runId = 'tod-mim-comm-soak-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runDir = Join-Path $outputRootAbs $runId
Ensure-Directory -PathValue $runDir

$iterationResults = @()
$failures = @()
$scenarioTotals = @{}
$scenarioPasses = @{}
$startedAt = Get-Date

for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
    try {
        $payload = (& $simulationScript -Scenario $Scenario -OutputRoot $runDir) | ConvertFrom-Json
        $scenarioResults = @($payload.scenario_results)

        foreach ($entry in $scenarioResults) {
            $name = [string]$entry.scenario
            if (-not $scenarioTotals.ContainsKey($name)) {
                $scenarioTotals[$name] = 0
                $scenarioPasses[$name] = 0
            }
            $scenarioTotals[$name] = [int]$scenarioTotals[$name] + 1
            if ([bool]$entry.ok) {
                $scenarioPasses[$name] = [int]$scenarioPasses[$name] + 1
            }
        }

        $iterationResults += [pscustomobject]@{
            iteration = $iteration
            ok = [bool]$payload.ok
            root = [string]$payload.root
            scenarios = @($scenarioResults | ForEach-Object {
                [pscustomobject]@{
                    scenario = [string]$_.scenario
                    ok = [bool]$_.ok
                    final_status = if ($_.PSObject.Properties['final_status']) { [string]$_.final_status } else { '' }
                }
            })
        }

        if (-not [bool]$payload.ok) {
            $failures += [pscustomobject]@{
                iteration = $iteration
                reason = 'scenario_failure'
                root = [string]$payload.root
            }
            if ($StopOnFirstFailure) {
                break
            }
        }
    }
    catch {
        $failures += [pscustomobject]@{
            iteration = $iteration
            reason = [string]$_.Exception.Message
            root = ''
        }
        if ($StopOnFirstFailure) {
            break
        }
    }
}

$finishedAt = Get-Date
$scenarioSuccess = @()
foreach ($name in @($scenarioTotals.Keys | Sort-Object)) {
    $total = [int]$scenarioTotals[$name]
    $passed = [int]$scenarioPasses[$name]
    $rate = if ($total -gt 0) { [math]::Round(($passed / $total), 6) } else { 0 }
    $scenarioSuccess += [pscustomobject]@{
        scenario = [string]$name
        passed = $passed
        total = $total
        success_rate = $rate
        perfect = ($passed -eq $total)
    }
}

$completedIterations = @($iterationResults).Count
$passedIterations = @(@($iterationResults | Where-Object { [bool]$_.ok })).Count
$strictPass = ($completedIterations -eq $Iterations) -and (@($failures).Count -eq 0) -and (@($scenarioSuccess | Where-Object { -not [bool]$_.perfect }).Count -eq 0)

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-communication-simulation-soak-v1'
    run_id = $runId
    config = [pscustomobject]@{
        iterations = $Iterations
        scenario = $Scenario
        stop_on_first_failure = [bool]$StopOnFirstFailure
    }
    summary = [pscustomobject]@{
        strict_pass = [bool]$strictPass
        iterations_completed = $completedIterations
        iterations_requested = $Iterations
        iterations_passed = $passedIterations
        iterations_failed = @($failures).Count
        started_at = $startedAt.ToUniversalTime().ToString('o')
        finished_at = $finishedAt.ToUniversalTime().ToString('o')
        duration_seconds = [math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)
    }
    scenario_success = @($scenarioSuccess)
    failures = @($failures)
    artifacts = [pscustomobject]@{
        run_dir = $runDir
        latest_json = (Join-Path $outputRootAbs 'tod-mim-communication-soak.latest.json')
        latest_markdown = (Join-Path $outputRootAbs 'tod-mim-communication-soak.latest.md')
    }
}

$latestJsonPath = Join-Path $outputRootAbs 'tod-mim-communication-soak.latest.json'
$latestMarkdownPath = Join-Path $outputRootAbs 'tod-mim-communication-soak.latest.md'
Write-Utf8NoBomJson -PathValue $latestJsonPath -Payload $report -Depth 20

$markdown = @(
    '# TOD-MIM Communication Simulation Soak',
    '',
    ('- run_id: {0}' -f $runId),
    ('- strict_pass: {0}' -f [string]$report.summary.strict_pass),
    ('- iterations: {0}/{1}' -f [string]$report.summary.iterations_completed, [string]$report.summary.iterations_requested),
    ('- passed_iterations: {0}' -f [string]$report.summary.iterations_passed),
    ('- failed_iterations: {0}' -f [string]$report.summary.iterations_failed),
    '',
    '## Scenario Success',
    ''
)
foreach ($entry in @($scenarioSuccess)) {
    $markdown += ('- {0}: {1}/{2} ({3})' -f [string]$entry.scenario, [string]$entry.passed, [string]$entry.total, [string]$entry.success_rate)
}
[System.IO.File]::WriteAllText($latestMarkdownPath, (($markdown -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 20 | Write-Output
}
else {
    $report
}

if ($FailOnFailure -and -not $strictPass) {
    throw ('TOD-MIM communication simulation soak failed. See artifact: {0}' -f $latestJsonPath)
}