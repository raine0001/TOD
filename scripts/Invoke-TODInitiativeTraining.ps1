param(
    [string]$ConfigPath = 'tod/config/tod-config.json',
    [string]$OutputRoot = 'tod/out/training/initiative-training',
    [int]$SelfQuestionCount = 50,
    [int]$MaxObjectivesToExecute = 2,
    [double]$LiveGroundingTarget = 0.75,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot 'TOD.ps1'
$conversationProviderScript = Join-Path $PSScriptRoot 'Invoke-TODConversationProvider.ps1'
$readinessArtifactScript = Join-Path $PSScriptRoot 'Test-TODOperatorChatSweepArtifact.ps1'
$selfHealthScript = Join-Path $PSScriptRoot 'Invoke-TODSelfHealthMaintenance.ps1'
$nextStepPolicyScript = Join-Path $PSScriptRoot 'Invoke-TODNextStepPolicy.ps1'
$codexReadinessScript = Join-Path $PSScriptRoot 'Invoke-TODCodexReadinessRun.ps1'
$pythonSimulationScript = Join-Path $PSScriptRoot 'tod_social_conversation_simulation.py'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-ParentDirectory {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    Ensure-ParentDirectory -PathValue $PathValue
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Content
    )

    Ensure-ParentDirectory -PathValue $PathValue
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $Content, $utf8NoBom)
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

function Get-JsonFromText {
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
    $start = -1
    if ($firstBrace -ge 0 -and $firstBracket -ge 0) {
        $start = [Math]::Min($firstBrace, $firstBracket)
    }
    elseif ($firstBrace -ge 0) {
        $start = $firstBrace
    }
    elseif ($firstBracket -ge 0) {
        $start = $firstBracket
    }

    if ($start -lt 0) {
        return $null
    }

    $candidate = $trimmed.Substring($start)
    try {
        return ($candidate | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$WorkingDirectory = $repoRoot
    )

    $stdoutPath = Join-Path $env:TEMP ("tod-init-train-" + [guid]::NewGuid().ToString('N') + '.stdout.log')
    $stderrPath = Join-Path $env:TEMP ("tod-init-train-" + [guid]::NewGuid().ToString('N') + '.stderr.log')

    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -Wait -NoNewWindow -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
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

function Invoke-JsonPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    $powershellExe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -Path $powershellExe)) {
        $powershellExe = 'powershell.exe'
    }

    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
    foreach ($entry in $Arguments.GetEnumerator() | Sort-Object Key) {
        $name = [string]$entry.Key
        $value = $entry.Value

        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ([bool]$value.IsPresent) {
                $args += ('-' + $name)
            }
            continue
        }

        if ($value -is [bool]) {
            if ([bool]$value) {
                $args += ('-' + $name)
            }
            continue
        }

        if ($null -eq $value) {
            continue
        }

        if ($value -is [System.Array] -and -not ($value -is [string])) {
            $args += ('-' + $name)
            foreach ($item in @($value)) {
                $args += [string]$item
            }
            continue
        }

        $args += ('-' + $name)
        $args += [string]$value
    }

    $rawOutput = & $powershellExe @args 2>&1 | Out-String
    $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
    $json = Get-JsonFromText -Text $rawOutput
    return [pscustomobject]@{
        ok = ($exitCode -eq 0)
        exit_code = $exitCode
        stdout = $rawOutput
        stderr = ''
        json = $json
    }
}

function Invoke-TodJsonAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$ExtraArgs = @{}
    )

    $arguments = @{
        Action = $Action
        ConfigPath = $effectiveConfigPath
        Top = 25
    }
    foreach ($key in $ExtraArgs.Keys) {
        $arguments[$key] = $ExtraArgs[$key]
    }

    $result = Invoke-JsonPowerShellScript -ScriptPath $todScript -Arguments $arguments
    if (-not $result.ok) {
        $detail = if (-not [string]::IsNullOrWhiteSpace($result.stderr)) { $result.stderr.Trim() } else { $result.stdout.Trim() }
        throw "TOD action '$Action' failed: $detail"
    }
    if ($null -eq $result.json) {
        throw "TOD action '$Action' did not return JSON output."
    }
    return $result.json
}

function Get-PythonCommand {
    $venvPython = Join-Path $repoRoot '.venv/Scripts/python.exe'
    if (Test-Path -Path $venvPython) {
        return $venvPython
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return $pythonCmd.Source
    }

    return ''
}

function Get-ConversationProviderStatus {
    if (-not (Test-Path -Path $conversationProviderScript)) {
        return [pscustomobject]@{
            available = $false
            reachable = $false
            source = 'missing'
            endpoint = ''
            model = ''
            error = 'conversation_provider_script_missing'
        }
    }

    $result = Invoke-JsonPowerShellScript -ScriptPath $conversationProviderScript -Arguments @{ Action = 'status'; AsJson = $true }
    if (-not $result.ok -or $null -eq $result.json) {
        return [pscustomobject]@{
            available = $true
            reachable = $false
            source = 'status_failed'
            endpoint = ''
            model = ''
            error = if (-not [string]::IsNullOrWhiteSpace($result.stderr)) { $result.stderr.Trim() } else { 'provider_status_failed' }
        }
    }

    $payload = $result.json
    return [pscustomobject]@{
        available = $true
        reachable = [bool]$payload.reachable
        source = 'local_conversation_provider'
        endpoint = if ($payload.PSObject.Properties['endpoint']) { [string]$payload.endpoint } else { '' }
        model = if ($payload.PSObject.Properties['model']) { [string]$payload.model } else { '' }
        error = if ($payload.PSObject.Properties['error']) { [string]$payload.error } else { '' }
    }
}

function Get-LatestSocialSimulationReports {
    $root = Join-Path $repoRoot 'shared_state/conversation_eval/social-million'
    if (-not (Test-Path -Path $root)) {
        return @()
    }

    $reports = @()
    foreach ($directory in @(Get-ChildItem -Path $root -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 8)) {
        $reportPath = Join-Path $directory.FullName 'social-simulation-report.json'
        $report = Read-JsonFileIfExists -PathValue $reportPath
        if ($null -eq $report) {
            continue
        }
        $reports += [pscustomobject]@{
            path = $reportPath
            run_id = if ($report.PSObject.Properties['run_id']) { [string]$report.run_id } else { $directory.Name }
            generated_at = if ($report.PSObject.Properties['generated_at']) { [string]$report.generated_at } else { '' }
            include_domains = if ($report.config -and $report.config.PSObject.Properties['include_domains']) { @($report.config.include_domains | ForEach-Object { [string]$_ }) } else { @() }
            live_grounding_score = if ($report.summary -and $report.summary.PSObject.Properties['live_grounding_score'] -and $null -ne $report.summary.live_grounding_score) { [double]$report.summary.live_grounding_score } elseif ($report.live_fetch -and $report.live_fetch.PSObject.Properties['average_grounding_score'] -and $null -ne $report.live_fetch.average_grounding_score) { [double]$report.live_fetch.average_grounding_score } else { -1.0 }
            live_fetch_success_rate = if ($report.summary -and $report.summary.PSObject.Properties['live_fetch_success_rate'] -and $null -ne $report.summary.live_fetch_success_rate) { [double]$report.summary.live_fetch_success_rate } elseif ($report.live_fetch -and $report.live_fetch.PSObject.Properties['success_rate'] -and $null -ne $report.live_fetch.success_rate) { [double]$report.live_fetch.success_rate } else { -1.0 }
            live_fetch_attempted = if ($report.live_fetch -and $report.live_fetch.PSObject.Properties['attempted']) { [int]$report.live_fetch.attempted } else { 0 }
            resource_average = if ($report.summary -and $report.summary.PSObject.Properties['resource_average']) { [double]$report.summary.resource_average } else { 0.0 }
            pass = if ($report.summary -and $report.summary.PSObject.Properties['pass']) { [bool]$report.summary.pass } else { $false }
            payload = $report
        }
    }

    return @($reports)
}

function Get-SeverityRank {
    param([string]$Severity)

    switch (([string]$Severity).ToLowerInvariant()) {
        'critical' { return 4 }
        'high' { return 3 }
        'medium' { return 2 }
        'low' { return 1 }
        default { return 0 }
    }
}

function New-Deficiency {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][double]$PriorityScore,
        [Parameter(Mandatory = $true)][string]$Reason,
        [Parameter(Mandatory = $true)][string]$ObjectiveTitle,
        [Parameter(Mandatory = $true)][string]$ObjectiveDescription,
        [Parameter(Mandatory = $true)][string[]]$SuccessCriteria,
        [Parameter(Mandatory = $true)]$PlanSteps,
        [Parameter(Mandatory = $true)][pscustomobject]$Metric
    )

    return [pscustomobject]@{
        id = $Id
        title = $Title
        severity = $Severity
        priority_score = [math]::Round($PriorityScore, 4)
        reason = $Reason
        objective_title = $ObjectiveTitle
        objective_description = $ObjectiveDescription
        success_criteria = @($SuccessCriteria)
        plan_steps = @($PlanSteps)
        metric = $Metric
    }
}

function Get-ActionPlanGuidance {
    param(
        [Parameter(Mandatory = $true)]$Deficiency,
        [Parameter(Mandatory = $true)]$ProviderStatus,
        [Parameter(Mandatory = $true)]$Baseline
    )

    if (-not [bool]$ProviderStatus.reachable) {
        return [pscustomobject]@{
            used = $false
            source = 'deterministic_fallback'
            guidance = 'Resource guidance fallback active. Use local evidence first, and only use external guidance when the next safe step is unclear.'
        }
    }

    $prompt = @"
You are coaching TOD during initiative training.

Current deficiency: $($Deficiency.title)
Reason: $($Deficiency.reason)
Current execution readiness: $($Baseline.execution_readiness.status)
Current self-health severity: $($Baseline.self_health.overall_severity)
Current live grounding score: $([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.000}', [double]$Baseline.live_grounding.score))

Give TOD a short plan with exactly three bullets:
1. diagnose the deficiency using local evidence
2. execute one safe improvement step
3. verify and decide whether to continue without asking the operator

Keep it under 120 words.
"@

    $result = Invoke-JsonPowerShellScript -ScriptPath $conversationProviderScript -Arguments @{
        Action = 'chat'
        Prompt = $prompt
        ObjectiveSummary = 'Initiative training guidance'
        TaskState = $Deficiency.id
        ObjectiveId = 'initiative-training'
        AsJson = $true
    }

    $replyText = ''
    if ($result.ok -and $result.json -and $result.json.PSObject.Properties['reply_text']) {
        $replyText = [string]$result.json.reply_text
    }

    return [pscustomobject]@{
        used = (-not [string]::IsNullOrWhiteSpace($replyText))
        source = if (-not [string]::IsNullOrWhiteSpace($replyText)) { 'local_conversation_provider' } else { 'deterministic_fallback' }
        guidance = if (-not [string]::IsNullOrWhiteSpace($replyText)) { $replyText.Trim() } else { 'Use local evidence first, execute a bounded safe step, verify, log, and continue if the operator queue is empty.' }
    }
}

function Get-BaselineSignals {
    param([Parameter(Mandatory = $true)]$ProviderStatus)

    $currentBuildState = Read-JsonFileIfExists -PathValue (Join-Path $repoRoot 'shared_state/current_build_state.json')
    $selfHealth = Read-JsonFileIfExists -PathValue (Join-Path $repoRoot 'shared_state/TOD_SELF_HEALTH_RUN.latest.json')
    $codexReadiness = Read-JsonFileIfExists -PathValue (Join-Path $repoRoot 'shared_state/conversation_eval/codex_readiness/tod_codex_readiness.latest.json')
    $nextStepPolicy = Read-JsonFileIfExists -PathValue (Join-Path $repoRoot 'shared_state/NEXT_STEP_POLICY.latest.json')
    $socialReports = @(Get-LatestSocialSimulationReports)
    $weakestGroundingReport = $null
    $groundingReports = @($socialReports | Where-Object { [int]$_.live_fetch_attempted -gt 0 -and [double]$_.live_grounding_score -ge 0 })
    if (@($groundingReports).Count -gt 0) {
        $weakestGroundingReport = @($groundingReports | Sort-Object live_grounding_score, generated_at | Select-Object -First 1)[0]
    }

    $executionReadiness = if ($currentBuildState -and $currentBuildState.PSObject.Properties['execution_readiness']) { $currentBuildState.execution_readiness } else { $null }
    $pendingRequestCount = if ($selfHealth -and $selfHealth.preflight -and $selfHealth.preflight.PSObject.Properties['pending_request_count']) { [int]$selfHealth.preflight.pending_request_count } else { 0 }
    $liveGroundingScore = if ($weakestGroundingReport) { [double]$weakestGroundingReport.live_grounding_score } else { 1.0 }
    $liveGroundingDomains = if ($weakestGroundingReport) { @($weakestGroundingReport.include_domains) } else { @() }
    $codexAverageUtility = if ($codexReadiness -and $codexReadiness.summary -and $codexReadiness.summary.PSObject.Properties['average_utility']) { [double]$codexReadiness.summary.average_utility } else { 0.0 }

    return [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString('o')
        current_build_state = $currentBuildState
        execution_readiness = [pscustomobject]@{
            status = if ($executionReadiness) { [string]$executionReadiness.status } else { 'unknown' }
            execution_allowed = if ($executionReadiness) { [bool]$executionReadiness.execution_allowed } else { $false }
            reason = if ($executionReadiness) { [string]$executionReadiness.reason } else { '' }
            detail = if ($executionReadiness) { [string]$executionReadiness.detail } else { '' }
            artifact_age_minutes = if ($executionReadiness -and $executionReadiness.PSObject.Properties['artifact_age_minutes']) { [double]$executionReadiness.artifact_age_minutes } else { 0.0 }
        }
        self_health = [pscustomobject]@{
            overall_status = if ($selfHealth) { [string]$selfHealth.overall_status } else { 'unknown' }
            overall_severity = if ($selfHealth) { [string]$selfHealth.overall_severity } else { 'unknown' }
            summary = if ($selfHealth) { [string]$selfHealth.summary } else { '' }
            pending_request_count = $pendingRequestCount
            watchdog_state = if ($selfHealth -and $selfHealth.postflight -and $selfHealth.postflight.PSObject.Properties['watchdog_state']) { [string]$selfHealth.postflight.watchdog_state } else { '' }
        }
        codex_readiness = [pscustomobject]@{
            gate_passed = if ($codexReadiness -and $codexReadiness.summary) { [bool]$codexReadiness.summary.gate_passed } else { $false }
            average_utility = $codexAverageUtility
            changed_files_delta_count = if ($codexReadiness -and $codexReadiness.summary -and $codexReadiness.summary.PSObject.Properties['changed_files_delta_count']) { [int]$codexReadiness.summary.changed_files_delta_count } else { 0 }
        }
        live_grounding = [pscustomobject]@{
            score = $liveGroundingScore
            target = $LiveGroundingTarget
            weakest_run_id = if ($weakestGroundingReport) { [string]$weakestGroundingReport.run_id } else { '' }
            weakest_domains = @($liveGroundingDomains)
            source_path = if ($weakestGroundingReport) { [string]$weakestGroundingReport.path } else { '' }
        }
        next_step_policy = [pscustomobject]@{
            decision = if ($nextStepPolicy -and $nextStepPolicy.continuation) { [string]$nextStepPolicy.continuation.decision } else { '' }
            route = if ($nextStepPolicy -and $nextStepPolicy.continuation) { [string]$nextStepPolicy.continuation.route } else { '' }
            provisional = if ($nextStepPolicy -and $nextStepPolicy.PSObject.Properties['provisional']) { [bool]$nextStepPolicy.provisional } else { $false }
        }
        resource_status = [pscustomobject]@{
            local_conversation_provider = $ProviderStatus
            codex_configured = $true
            external_guidance_policy = 'backup_only'
        }
    }
}

function Get-Deficiencies {
    param([Parameter(Mandatory = $true)]$Baseline)

    $deficiencies = New-Object System.Collections.Generic.List[object]

    if (-not [bool]$Baseline.execution_readiness.execution_allowed) {
        $artifactAge = [double]$Baseline.execution_readiness.artifact_age_minutes
        $priorityScore = 100 + [math]::Min($artifactAge / 10.0, 50.0)
        $steps = @(
            [pscustomobject]@{ title = 'Assess guidance and safe execution resources'; acceptance = 'Resource status is captured before TOD acts.'; action = [pscustomobject]@{ kind = 'resource_status' } },
            [pscustomobject]@{ title = 'Refresh the operator-chat readiness artifact'; acceptance = 'A fresh readiness artifact smoke result exists.'; action = [pscustomobject]@{ kind = 'script'; script = $readinessArtifactScript; arguments = @{ EmitJson = $true } } },
            [pscustomobject]@{ title = 'Re-check execution readiness'; acceptance = 'TOD can state whether execution is allowed and why.'; action = [pscustomobject]@{ kind = 'tod_action'; action = 'get-execution-readiness' } }
        )

        $deficiencies.Add((New-Deficiency -Id 'execution_readiness_stale' -Title 'Execution readiness is blocking independent work' -Severity 'critical' -PriorityScore $priorityScore -Reason ([string]$Baseline.execution_readiness.detail) -ObjectiveTitle 'TOD initiative training: restore execution readiness' -ObjectiveDescription 'TOD identified stale execution readiness as the highest-value blocker to independent progress. During training, TOD should refresh readiness evidence, verify the result, and continue safely instead of waiting idle.' -SuccessCriteria @('A fresh readiness artifact exists', 'Execution readiness is re-evaluated after refresh', 'TOD records the next safe continuation decision') -PlanSteps $steps -Metric ([pscustomobject]@{ name = 'execution_readiness'; current = [string]$Baseline.execution_readiness.status; target = 'valid'; gap = if ([string]$Baseline.execution_readiness.status -eq 'valid') { 0 } else { 1 } })))
    }

    if ([string]$Baseline.self_health.overall_severity -eq 'critical') {
        $steps = @(
            [pscustomobject]@{ title = 'Run self-health maintenance once'; acceptance = 'A fresh self-health artifact exists for this run.'; action = [pscustomobject]@{ kind = 'script'; script = $selfHealthScript; arguments = @{ Profile = 'standard'; InvocationMode = 'manual'; RefreshAgentMimReadiness = $true; EmitJson = $true } } },
            [pscustomobject]@{ title = 'Refresh next-step continuation policy'; acceptance = 'Continuation policy is published after maintenance.'; action = [pscustomobject]@{ kind = 'script'; script = $nextStepPolicyScript; arguments = @{} } },
            [pscustomobject]@{ title = 'Reassess self-health severity'; acceptance = 'TOD records whether the critical condition eased or still needs follow-up.'; action = [pscustomobject]@{ kind = 'file_snapshot'; target = 'self_health' } }
        )

        $deficiencies.Add((New-Deficiency -Id 'self_health_critical' -Title 'Self-health remains in a critical condition' -Severity 'high' -PriorityScore 92 -Reason ([string]$Baseline.self_health.summary) -ObjectiveTitle 'TOD initiative training: reduce self-health critical blockers' -ObjectiveDescription 'TOD identified persistent self-health critical severity as a blocker to reliable autonomy. During training, TOD should run the maintenance loop, publish a fresh continuation policy, and decide whether it can keep moving without prompts.' -SuccessCriteria @('A fresh self-health report is generated', 'Continuation policy is refreshed after maintenance', 'TOD logs whether the critical condition improved or requires another bounded pass') -PlanSteps $steps -Metric ([pscustomobject]@{ name = 'self_health'; current = [string]$Baseline.self_health.overall_severity; target = 'warning'; gap = 1 })))
    }

    if ([double]$Baseline.live_grounding.score -lt [double]$Baseline.live_grounding.target) {
        $groundingGap = [double]$Baseline.live_grounding.target - [double]$Baseline.live_grounding.score
        $weakDomains = @($Baseline.live_grounding.weakest_domains)
        if (@($weakDomains).Count -eq 0) {
            $weakDomains = @('technology', 'coding')
        }
        $steps = @(
            [pscustomobject]@{ title = 'Re-run a bounded live-grounding validation pass'; acceptance = 'A fresh live-grounding report exists for the weakest domains.'; action = [pscustomobject]@{ kind = 'python_simulation'; include_domains = $weakDomains; conversation_count = 300000; checkpoint_interval = 50000; human_count = 15000; live_fetch_samples_per_checkpoint = 4 } },
            [pscustomobject]@{ title = 'Record the new live-grounding score'; acceptance = 'TOD compares the new score against the prior weakest run.'; action = [pscustomobject]@{ kind = 'file_snapshot'; target = 'live_grounding' } }
        )

        $deficiencies.Add((New-Deficiency -Id 'live_grounding_gap' -Title 'Live grounding is below the target floor' -Severity 'medium' -PriorityScore (70 + ($groundingGap * 100)) -Reason ("Lowest recent live-grounding score is {0:0.000} across {1}." -f [double]$Baseline.live_grounding.score, (@($weakDomains) -join ', ')) -ObjectiveTitle 'TOD initiative training: lift live grounding on weak domains' -ObjectiveDescription 'TOD identified live grounding as an improvement objective because the weakest recent score is below the desired floor. During training, TOD should run a bounded validation pass and compare the new score before deciding on the next grounding task.' -SuccessCriteria @('A bounded grounding run completes successfully', 'TOD records the delta between the prior and current grounding scores', 'TOD decides whether another grounding task is required') -PlanSteps $steps -Metric ([pscustomobject]@{ name = 'live_grounding'; current = [double]$Baseline.live_grounding.score; target = [double]$Baseline.live_grounding.target; gap = [math]::Round($groundingGap, 4) })))
    }

    if (-not [bool]$Baseline.codex_readiness.gate_passed -or [double]$Baseline.codex_readiness.average_utility -lt 0.9) {
        $steps = @(
            [pscustomobject]@{ title = 'Run a codex-readiness operator profile check'; acceptance = 'A fresh codex-readiness report is produced.'; action = [pscustomobject]@{ kind = 'script'; script = $codexReadinessScript; arguments = @{ Mode = 'operator'; EmitJson = $true } } },
            [pscustomobject]@{ title = 'Record readiness utility trend'; acceptance = 'TOD can explain whether coding assistance remains a weakness.'; action = [pscustomobject]@{ kind = 'file_snapshot'; target = 'codex_readiness' } }
        )

        $deficiencies.Add((New-Deficiency -Id 'codex_readiness_gap' -Title 'Codex/operator readiness can still improve' -Severity 'medium' -PriorityScore 55 -Reason ("Codex-readiness average utility is {0:0.000}." -f [double]$Baseline.codex_readiness.average_utility) -ObjectiveTitle 'TOD initiative training: verify codex/operator readiness' -ObjectiveDescription 'TOD identified operator-support readiness as a secondary improvement objective. During training, TOD should refresh the readiness run and decide whether a follow-on engineering task is needed.' -SuccessCriteria @('A fresh codex-readiness artifact exists', 'TOD records the average utility score', 'TOD decides whether to continue improving operator-support readiness') -PlanSteps $steps -Metric ([pscustomobject]@{ name = 'codex_readiness'; current = [double]$Baseline.codex_readiness.average_utility; target = 0.9; gap = [math]::Round((0.9 - [double]$Baseline.codex_readiness.average_utility), 4) })))
    }

    return @($deficiencies | Sort-Object @{ Expression = { Get-SeverityRank -Severity $_.severity }; Descending = $true }, @{ Expression = { [double]$_.priority_score }; Descending = $true })
}

function New-SelfInquiryQuestions {
    param(
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$Deficiencies,
        [int]$Count = 50
    )

    $deficiencyList = @($Deficiencies)
    if (@($deficiencyList).Count -eq 0) {
        $deficiencyList = @([pscustomobject]@{ title = 'No active deficiency detected'; reason = 'All tracked signals are currently healthy.'; severity = 'low' })
    }

    $templates = @(
        [pscustomobject]@{ q = 'What is my current skill for this task?'; a = "My current skill is bounded operational improvement using readiness, self-health, and grounding evidence. The top active weakness is {0}." },
        [pscustomobject]@{ q = 'What metric shows the strongest need for improvement right now?'; a = "The strongest improvement signal is {0} because {1}." },
        [pscustomobject]@{ q = 'Can I identify an objective without waiting for the operator?'; a = "Yes. I can derive an objective from local evidence. The highest-value candidate is {0}." },
        [pscustomobject]@{ q = 'What safe action can I take first?'; a = "The first safe action is to run a bounded diagnostic or maintenance step for {0} before attempting larger changes." },
        [pscustomobject]@{ q = 'What tells me I should not stay idle?'; a = "There is no pending operator or MIM work in the current snapshot, so I should continue the improvement loop for {0}." },
        [pscustomobject]@{ q = 'Do I need outside guidance for the next step?'; a = "Only as a backup. I should use local evidence first for {0}, and consult available guidance only if the next safe step is unclear." },
        [pscustomobject]@{ q = 'How do I know this objective is safe to execute?'; a = "It is safe because the plan for {0} uses small steps, reassessment after each step, and no destructive state changes." },
        [pscustomobject]@{ q = 'What result would prove improvement?'; a = "Improvement means the metric behind {0} moves toward target and I can name the next action without prompting." },
        [pscustomobject]@{ q = 'If the first attempt does not fix it, what do I do next?'; a = "I log the result, choose the next bounded corrective step for {0}, and test again instead of stopping." },
        [pscustomobject]@{ q = 'How do I show initiative when stuck?'; a = "When stuck on {0}, I should publish the blocker, pick the smallest corrective step, execute it, and reassess." }
    )

    $entries = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $template = $templates[$i % $templates.Count]
        $deficiency = $deficiencyList[$i % $deficiencyList.Count]
        $answer = ([string]$template.a).Replace('{0}', [string]$deficiency.title).Replace('{1}', [string]$deficiency.reason)
        $entries += [pscustomobject]@{
            index = $i + 1
            question = [string]$template.q
            answer = $answer
            deficiency = [string]$deficiency.title
            severity = [string]$deficiency.severity
        }
    }

    return @($entries)
}

function Test-ObjectiveCompletion {
    param(
        [Parameter(Mandatory = $true)][string]$DeficiencyId,
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$AfterSnapshot
    )

    switch ($DeficiencyId) {
        'execution_readiness_stale' {
            return ([string]$AfterSnapshot.execution_readiness.status -eq 'valid' -or [bool]$AfterSnapshot.execution_readiness.execution_allowed)
        }
        'self_health_critical' {
            return ([string]$AfterSnapshot.self_health.overall_severity -ne 'critical')
        }
        'live_grounding_gap' {
            return ([double]$AfterSnapshot.live_grounding.score -ge [double]$Baseline.live_grounding.target)
        }
        'codex_readiness_gap' {
            return ([double]$AfterSnapshot.codex_readiness.average_utility -ge 0.9 -and [bool]$AfterSnapshot.codex_readiness.gate_passed)
        }
        default {
            return $false
        }
    }
}

function Get-ImprovementSummary {
    param(
        [Parameter(Mandatory = $true)][string]$DeficiencyId,
        [Parameter(Mandatory = $true)]$BeforeSnapshot,
        [Parameter(Mandatory = $true)]$AfterSnapshot
    )

    switch ($DeficiencyId) {
        'execution_readiness_stale' {
            return [pscustomobject]@{
                metric = 'execution_readiness'
                before = [string]$BeforeSnapshot.execution_readiness.status
                after = [string]$AfterSnapshot.execution_readiness.status
                improved = ([string]$BeforeSnapshot.execution_readiness.status -ne [string]$AfterSnapshot.execution_readiness.status)
            }
        }
        'self_health_critical' {
            return [pscustomobject]@{
                metric = 'self_health'
                before = [string]$BeforeSnapshot.self_health.overall_severity
                after = [string]$AfterSnapshot.self_health.overall_severity
                improved = ([string]$BeforeSnapshot.self_health.overall_severity -ne [string]$AfterSnapshot.self_health.overall_severity)
            }
        }
        'live_grounding_gap' {
            return [pscustomobject]@{
                metric = 'live_grounding'
                before = [double]$BeforeSnapshot.live_grounding.score
                after = [double]$AfterSnapshot.live_grounding.score
                delta = [math]::Round(([double]$AfterSnapshot.live_grounding.score - [double]$BeforeSnapshot.live_grounding.score), 4)
                improved = ([double]$AfterSnapshot.live_grounding.score -gt [double]$BeforeSnapshot.live_grounding.score)
            }
        }
        'codex_readiness_gap' {
            return [pscustomobject]@{
                metric = 'codex_readiness'
                before = [double]$BeforeSnapshot.codex_readiness.average_utility
                after = [double]$AfterSnapshot.codex_readiness.average_utility
                delta = [math]::Round(([double]$AfterSnapshot.codex_readiness.average_utility - [double]$BeforeSnapshot.codex_readiness.average_utility), 4)
                improved = ([double]$AfterSnapshot.codex_readiness.average_utility -gt [double]$BeforeSnapshot.codex_readiness.average_utility)
            }
        }
        default {
            return [pscustomobject]@{ metric = $DeficiencyId; improved = $false }
        }
    }
}

function Invoke-PlanStepAction {
    param(
        [Parameter(Mandatory = $true)]$ActionSpec,
        [Parameter(Mandatory = $true)][string]$ObjectiveOutputDir,
        [Parameter(Mandatory = $true)]$Baseline
    )

    $kind = [string]$ActionSpec.kind
    switch ($kind) {
        'resource_status' {
            return [pscustomobject]@{
                ok = $true
                summary = 'Resource status captured.'
                payload = $Baseline.resource_status
            }
        }
        'tod_action' {
            $payload = Invoke-TodJsonAction -Action ([string]$ActionSpec.action)
            return [pscustomobject]@{
                ok = $true
                summary = "TOD action '$([string]$ActionSpec.action)' completed."
                payload = $payload
            }
        }
        'script' {
            $result = Invoke-JsonPowerShellScript -ScriptPath ([string]$ActionSpec.script) -Arguments $ActionSpec.arguments
            return [pscustomobject]@{
                ok = [bool]$result.ok
                summary = if ($result.ok) { "Script '$([System.IO.Path]::GetFileName([string]$ActionSpec.script))' completed." } else { "Script '$([System.IO.Path]::GetFileName([string]$ActionSpec.script))' failed." }
                payload = if ($result.json) { $result.json } else { [pscustomobject]@{ stdout = $result.stdout; stderr = $result.stderr; exit_code = $result.exit_code } }
            }
        }
        'python_simulation' {
            $pythonExe = Get-PythonCommand
            if ([string]::IsNullOrWhiteSpace($pythonExe)) {
                return [pscustomobject]@{
                    ok = $false
                    summary = 'Python runtime is unavailable for bounded live-grounding validation.'
                    payload = [pscustomobject]@{ error = 'python_unavailable' }
                }
            }

            $args = @(
                $pythonSimulationScript,
                '--conversation-count', [string]$ActionSpec.conversation_count,
                '--checkpoint-interval', [string]$ActionSpec.checkpoint_interval,
                '--human-count', [string]$ActionSpec.human_count,
                '--enable-live-fetch',
                '--live-fetch-samples-per-checkpoint', [string]$ActionSpec.live_fetch_samples_per_checkpoint,
                '--min-live-grounding-score', [string]$LiveGroundingTarget,
                '--emit-json'
            )
            if ($ActionSpec.PSObject.Properties['include_domains']) {
                $args += '--include-domains'
                foreach ($domain in @($ActionSpec.include_domains)) {
                    $args += [string]$domain
                }
            }

            $capture = Invoke-ProcessCapture -FilePath $pythonExe -ArgumentList $args -WorkingDirectory $repoRoot
            $json = Get-JsonFromText -Text $capture.stdout
            return [pscustomobject]@{
                ok = ($capture.exit_code -eq 0 -and $null -ne $json)
                summary = if ($capture.exit_code -eq 0) { 'Bounded live-grounding validation completed.' } else { 'Bounded live-grounding validation failed.' }
                payload = if ($null -ne $json) { $json } else { [pscustomobject]@{ stdout = $capture.stdout; stderr = $capture.stderr; exit_code = $capture.exit_code } }
            }
        }
        'file_snapshot' {
            $snapshot = Get-BaselineSignals -ProviderStatus $Baseline.resource_status.local_conversation_provider
            return [pscustomobject]@{
                ok = $true
                summary = "Snapshot '$([string]$ActionSpec.target)' captured."
                payload = $snapshot
            }
        }
        default {
            return [pscustomobject]@{
                ok = $false
                summary = "Unsupported action kind '$kind'."
                payload = [pscustomobject]@{ error = 'unsupported_action_kind'; kind = $kind }
            }
        }
    }
}

$effectiveConfigPath = Resolve-LocalPath -PathValue $ConfigPath
$effectiveOutputRoot = Resolve-LocalPath -PathValue $OutputRoot
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$runOutputDir = Join-Path $effectiveOutputRoot $runId
$latestJsonPath = Join-Path $effectiveOutputRoot 'tod_initiative_training.latest.json'
$latestMarkdownPath = Join-Path $effectiveOutputRoot 'tod_initiative_training.latest.md'
$runJsonPath = Join-Path $runOutputDir 'tod_initiative_training.json'
$runMarkdownPath = Join-Path $runOutputDir 'tod_initiative_training.md'

if (-not (Test-Path -Path $effectiveOutputRoot)) {
    New-Item -ItemType Directory -Path $effectiveOutputRoot -Force | Out-Null
}
if (-not (Test-Path -Path $runOutputDir)) {
    New-Item -ItemType Directory -Path $runOutputDir -Force | Out-Null
}

if (-not (Test-Path -Path $effectiveConfigPath)) {
    throw "Missing config path: $effectiveConfigPath"
}

$providerStatus = Get-ConversationProviderStatus
$baseline = Get-BaselineSignals -ProviderStatus $providerStatus
$initialBaseline = $baseline
$deficiencies = @(Get-Deficiencies -Baseline $baseline)
$selfQuestions = @(New-SelfInquiryQuestions -Baseline $baseline -Deficiencies $deficiencies -Count $SelfQuestionCount)

$trainingNudge = 'Prefer independent improvement objectives that unlock TOD execution first. Use local evidence first, external guidance only as a backup, and continue the loop automatically when no operator or MIM work is pending.'

$objectiveRuns = @()
$createdContinuation = $null
$pendingDeficiencies = @($deficiencies)

for ($objectiveIndex = 0; $objectiveIndex -lt [Math]::Min($MaxObjectivesToExecute, @($pendingDeficiencies).Count); $objectiveIndex++) {
    $selected = $pendingDeficiencies[$objectiveIndex]
    $objectiveOutputDir = Join-Path $runOutputDir ("objective-" + ($objectiveIndex + 1).ToString('00') + '-' + $selected.id)
    if (-not (Test-Path -Path $objectiveOutputDir)) {
        New-Item -ItemType Directory -Path $objectiveOutputDir -Force | Out-Null
    }

    $guidance = Get-ActionPlanGuidance -Deficiency $selected -ProviderStatus $providerStatus -Baseline $baseline
    $objectiveRecord = Invoke-TodJsonAction -Action 'new-objective' -ExtraArgs @{
        Title = $selected.objective_title
        Description = $selected.objective_description
        Priority = $(if ($selected.severity -eq 'critical') { 'critical' } elseif ($selected.severity -eq 'high') { 'high' } else { 'medium' })
        SuccessCriteria = ($selected.success_criteria -join ',')
    }

    $objectiveId = if ($objectiveRecord.PSObject.Properties['id']) { [string]$objectiveRecord.id } elseif ($objectiveRecord.PSObject.Properties['local']) { [string]$objectiveRecord.local.id } else { '' }
    $taskRecords = @()
    $stepResults = @()

    foreach ($step in @($selected.plan_steps)) {
        $taskRecord = Invoke-TodJsonAction -Action 'add-task' -ExtraArgs @{
            ObjectiveId = $objectiveId
            Title = [string]$step.title
            Scope = [string]$selected.reason
            AcceptanceCriteria = [string]$step.acceptance
            AssignedExecutor = 'codex'
            TaskCategory = 'initiative_training'
        }
        $taskRecords += $taskRecord

        try {
            $actionResult = Invoke-PlanStepAction -ActionSpec $step.action -ObjectiveOutputDir $objectiveOutputDir -Baseline $baseline
        }
        catch {
            $actionResult = [pscustomobject]@{
                ok = $false
                summary = [string]$_.Exception.Message
                payload = [pscustomobject]@{ error = [string]$_.Exception.Message }
            }
        }
        $stepResults += [pscustomobject]@{
            title = [string]$step.title
            acceptance = [string]$step.acceptance
            ok = [bool]$actionResult.ok
            summary = [string]$actionResult.summary
            payload = $actionResult.payload
        }
    }

    $afterSnapshot = Get-BaselineSignals -ProviderStatus $providerStatus
    $completed = Test-ObjectiveCompletion -DeficiencyId $selected.id -Baseline $baseline -AfterSnapshot $afterSnapshot
    $improvement = Get-ImprovementSummary -DeficiencyId $selected.id -BeforeSnapshot $baseline -AfterSnapshot $afterSnapshot

    $objectiveRuns += [pscustomobject]@{
        objective_index = $objectiveIndex + 1
        selected_deficiency = $selected
        objective = $objectiveRecord
        guidance = $guidance
        tasks = @($taskRecords)
        step_results = @($stepResults)
        before_snapshot = $baseline
        after_snapshot = $afterSnapshot
        improvement = $improvement
        completed = $completed
        status = if ($completed) { 'completed' } elseif (@($stepResults | Where-Object { [bool]$_.ok }).Count -gt 0) { 'partial' } else { 'blocked' }
    }

    $baseline = $afterSnapshot
}

$remainingDeficiencies = @(Get-Deficiencies -Baseline $baseline)
$currentObjectiveIds = @($objectiveRuns | ForEach-Object { if ($_.selected_deficiency) { [string]$_.selected_deficiency.id } })
$remainingCandidate = @($remainingDeficiencies | Where-Object { $currentObjectiveIds -notcontains [string]$_.id } | Select-Object -First 1)
$isIdleForTraining = ([int]$baseline.self_health.pending_request_count -eq 0)
$unresolvedRun = @($objectiveRuns | Where-Object { -not [bool]$_.completed } | Select-Object -First 1)

if ($isIdleForTraining -and @($remainingCandidate).Count -gt 0) {
    $nextDeficiency = $remainingCandidate[0]
    $nextObjective = Invoke-TodJsonAction -Action 'new-objective' -ExtraArgs @{
        Title = ($nextDeficiency.objective_title + ' (auto-continued)')
        Description = ($nextDeficiency.objective_description + ' This follow-on objective was created automatically because TOD was idle and still had improvement work available.')
        Priority = $(if ($nextDeficiency.severity -eq 'critical') { 'critical' } elseif ($nextDeficiency.severity -eq 'high') { 'high' } else { 'medium' })
        SuccessCriteria = ($nextDeficiency.success_criteria -join ',')
    }
    $nextObjectiveId = if ($nextObjective.PSObject.Properties['id']) { [string]$nextObjective.id } elseif ($nextObjective.PSObject.Properties['local']) { [string]$nextObjective.local.id } else { '' }
    $nextTask = Invoke-TodJsonAction -Action 'add-task' -ExtraArgs @{
        ObjectiveId = $nextObjectiveId
        Title = [string]$nextDeficiency.plan_steps[0].title
        Scope = [string]$nextDeficiency.reason
        AcceptanceCriteria = [string]$nextDeficiency.plan_steps[0].acceptance
        AssignedExecutor = 'codex'
        TaskCategory = 'initiative_training'
    }
    $createdContinuation = [pscustomobject]@{
        created = $true
        reason = 'TOD was idle and identified another improvement objective without needing an operator prompt.'
        objective = $nextObjective
        first_task = $nextTask
        deficiency = $nextDeficiency
    }
}
elseif ($isIdleForTraining -and @($unresolvedRun).Count -gt 0) {
    $followOnTask = Invoke-TodJsonAction -Action 'add-task' -ExtraArgs @{
        ObjectiveId = [string]$unresolvedRun[0].objective.id
        Title = ('Continue bounded follow-through for ' + [string]$unresolvedRun[0].selected_deficiency.title)
        Scope = ('Follow-on loop after partial progress: ' + [string]$unresolvedRun[0].selected_deficiency.reason)
        AcceptanceCriteria = 'TOD records the next corrective step, executes it safely, and reassesses whether the deficiency improved.'
        AssignedExecutor = 'codex'
        TaskCategory = 'initiative_training'
    }
    $createdContinuation = [pscustomobject]@{
        created = $true
        reason = 'TOD was idle, the current improvement objective was still unresolved, and TOD created a follow-on task automatically.'
        objective = $unresolvedRun[0].objective
        first_task = $followOnTask
        deficiency = $unresolvedRun[0].selected_deficiency
    }
}
else {
    $createdContinuation = [pscustomobject]@{
        created = $false
        reason = if (-not $isIdleForTraining) { 'External work was still pending, so TOD did not auto-seed another improvement objective.' } else { 'No remaining tracked deficiency required another objective.' }
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-initiative-training-v1'
    run_id = $runId
    training_goal = 'Teach TOD to identify its own deficiencies, create bounded improvement objectives, act safely without idling, and continue with a follow-on task when no external work is pending.'
    training_nudge = $trainingNudge
    self_inquiry_questions = @($selfQuestions)
    baseline = $initialBaseline
    final_signals = $baseline
    initial_deficiencies = @($deficiencies)
    objective_runs = @($objectiveRuns)
    continuation = $createdContinuation
    summary = [pscustomobject]@{
        objective_count_executed = @($objectiveRuns).Count
        objective_count_completed = @(@($objectiveRuns | Where-Object { [bool]$_.completed })).Count
        can_continue_without_prompts = [bool]$createdContinuation.created
        idle_during_follow_on_decision = $isIdleForTraining
        selected_focus = if (@($objectiveRuns).Count -gt 0) { [string]$objectiveRuns[0].selected_deficiency.title } else { 'none' }
    }
}

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add('# TOD Initiative Training Report')
$markdown.Add('')
$markdown.Add(('Generated: {0}' -f [string]$report.generated_at))
$markdown.Add(('Run ID: {0}' -f [string]$report.run_id))
$markdown.Add('')
$markdown.Add('## Training Goal')
$markdown.Add($report.training_goal)
$markdown.Add('')
$markdown.Add('## Training Nudge')
$markdown.Add($report.training_nudge)
$markdown.Add('')
$markdown.Add('## Initial Deficiencies')
foreach ($deficiency in @($deficiencies)) {
    $markdown.Add(('- {0} [{1}] - {2}' -f [string]$deficiency.title, [string]$deficiency.severity, [string]$deficiency.reason))
}
$markdown.Add('')
$markdown.Add('## Objective Runs')
foreach ($run in @($objectiveRuns)) {
    $markdown.Add(('### {0}' -f [string]$run.selected_deficiency.objective_title))
    $markdown.Add(('Status: {0}' -f [string]$run.status))
    $markdown.Add(('Guidance source: {0}' -f [string]$run.guidance.source))
    $markdown.Add(('Improvement: {0}' -f (($run.improvement | ConvertTo-Json -Compress))))
    foreach ($step in @($run.step_results)) {
        $markdown.Add(('- {0}: {1}' -f [string]$step.title, [string]$step.summary))
    }
    $markdown.Add('')
}
$markdown.Add('## Continuation')
$markdown.Add(('Can continue without prompts: {0}' -f [bool]$report.summary.can_continue_without_prompts))
$markdown.Add(('Reason: {0}' -f [string]$createdContinuation.reason))
if ($createdContinuation.created) {
    $continuationObjectiveTitle = if ($createdContinuation.objective.PSObject.Properties['title']) { [string]$createdContinuation.objective.title } elseif ($createdContinuation.objective.PSObject.Properties['local']) { [string]$createdContinuation.objective.local.title } else { '' }
    $continuationTaskTitle = if ($createdContinuation.first_task.PSObject.Properties['title']) { [string]$createdContinuation.first_task.title } elseif ($createdContinuation.first_task.PSObject.Properties['local']) { [string]$createdContinuation.first_task.local.title } else { '' }
    $markdown.Add(('Next objective: {0}' -f $continuationObjectiveTitle))
    $markdown.Add(('Next task: {0}' -f $continuationTaskTitle))
}
$markdown.Add('')
$markdown.Add('## Self-Inquiry Sample')
foreach ($entry in @($selfQuestions | Select-Object -First 10)) {
    $markdown.Add(('- Q{0}: {1}' -f [int]$entry.index, [string]$entry.question))
    $markdown.Add(('  A: {0}' -f [string]$entry.answer))
}

Write-Utf8NoBomJson -PathValue $runJsonPath -Payload $report -Depth 30
Write-Utf8NoBomJson -PathValue $latestJsonPath -Payload $report -Depth 30
Write-Utf8NoBomText -PathValue $runMarkdownPath -Content ($markdown -join "`n")
Write-Utf8NoBomText -PathValue $latestMarkdownPath -Content ($markdown -join "`n")

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 18 | Write-Output
}
else {
    $report
}