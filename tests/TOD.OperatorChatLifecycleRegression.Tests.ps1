Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$baseUrl = 'http://localhost:8844'
$executionReadinessArtifactPath = Join-Path $repoRoot 'shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json'

function Invoke-TodJsonGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TodJsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
}

function Get-TodValidationHarnessName {
    param($Payload)

    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['validation_harness'] -or $null -eq $Payload.validation_harness) {
        return ''
    }

    if ($Payload.validation_harness -is [string]) {
        return [string]$Payload.validation_harness
    }

    if ($Payload.validation_harness.PSObject.Properties['name']) {
        return [string]$Payload.validation_harness.name
    }

    return ''
}

function Get-TodCommittableSuggestedAction {
    param($SuggestedActions)

    foreach ($candidate in @($SuggestedActions)) {
        if ($null -eq $candidate) {
            continue
        }

        $mode = if ($candidate.PSObject.Properties['mode']) { [string]$candidate.mode } else { '' }
        if (-not [string]::Equals($mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }

    return $null
}

function Get-TodIneffectiveValidationAction {
    param($SuggestedActions)

    $committable = @($SuggestedActions | Where-Object {
            $null -ne $_ -and
            -not [string]::Equals([string]$_.mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
        })

    foreach ($candidate in $committable) {
        $sameIntentSatisfiedCount = if ($candidate.PSObject.Properties['history_same_intent_satisfied_count']) { [int]$candidate.history_same_intent_satisfied_count } else { 0 }
        $sameIntentAbandonedCount = if ($candidate.PSObject.Properties['history_same_intent_abandoned_count']) { [int]$candidate.history_same_intent_abandoned_count } else { 0 }
        if ($sameIntentSatisfiedCount -eq 0 -and $sameIntentAbandonedCount -eq 0) {
            return $candidate
        }
    }

    foreach ($candidate in $committable) {
        $sameIntentSatisfiedCount = if ($candidate.PSObject.Properties['history_same_intent_satisfied_count']) { [int]$candidate.history_same_intent_satisfied_count } else { 0 }
        if ($sameIntentSatisfiedCount -eq 0) {
            return $candidate
        }
    }

    return Get-TodCommittableSuggestedAction -SuggestedActions $SuggestedActions
}

function Test-TodUiReachable {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/project-status" -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Get-TodExecutionReadinessArtifactBackup {
    if (-not (Test-Path -Path $executionReadinessArtifactPath -PathType Leaf)) {
        return $null
    }

    return [System.IO.File]::ReadAllText($executionReadinessArtifactPath)
}

function Restore-TodExecutionReadinessArtifact {
    param([AllowNull()][string]$Content)

    if ($null -eq $Content) {
        if (Test-Path -Path $executionReadinessArtifactPath -PathType Leaf) {
            Remove-Item -Path $executionReadinessArtifactPath -Force
        }
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($executionReadinessArtifactPath, $Content, $utf8NoBom)
}

function Set-TodExecutionReadinessArtifactScenario {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('degraded', 'stale', 'invalid', 'unknown')][string]$Scenario,
        [int]$ArtifactAgeMinutes = 45
    )

    if ($Scenario -eq 'unknown') {
        [System.IO.File]::WriteAllText($executionReadinessArtifactPath, '{"generated_at":', (New-Object System.Text.UTF8Encoding($false)))
        return
    }

    $artifact = Get-Content -Path $executionReadinessArtifactPath -Raw | ConvertFrom-Json
    $generatedAt = (Get-Date).ToUniversalTime().AddMinutes(-1 * [Math]::Abs($ArtifactAgeMinutes)).ToString('o')
    $artifact.generated_at = $generatedAt
    if ($artifact.PSObject.Properties['artifact_generated_at']) {
        $artifact.artifact_generated_at = $generatedAt
    }

    if (-not $artifact.PSObject.Properties['summary'] -or $null -eq $artifact.summary) {
        $artifact | Add-Member -NotePropertyName summary -NotePropertyValue ([pscustomobject]@{})
    }

    if ($Scenario -eq 'degraded') {
        $generatedAt = (Get-Date).ToUniversalTime().AddMinutes(-12).ToString('o')
        $artifact.generated_at = $generatedAt
        if ($artifact.PSObject.Properties['artifact_generated_at']) {
            $artifact.artifact_generated_at = $generatedAt
        }
        $artifact.summary.passed_all = $true
        $artifact.summary.exit_code = 0
    }
    elseif ($Scenario -eq 'stale') {
        $artifact.summary.passed_all = $true
        $artifact.summary.exit_code = 0
    }
    elseif ($Scenario -eq 'invalid') {
        $artifact.generated_at = (Get-Date).ToUniversalTime().ToString('o')
        if ($artifact.PSObject.Properties['artifact_generated_at']) {
            $artifact.artifact_generated_at = [string]$artifact.generated_at
        }
        $artifact.summary.passed_all = $false
        $artifact.summary.exit_code = 5
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($executionReadinessArtifactPath, ($artifact | ConvertTo-Json -Depth 20), $utf8NoBom)
}

function New-TodApiRunReadinessFixture {
    $id = [guid]::NewGuid().ToString('N')
    $base = Join-Path $repoRoot ("tod/out/tests/operator-chat-run-readiness-" + $id)
    New-Item -ItemType Directory -Path $base -Force | Out-Null

    $artifactPath = Join-Path $base 'tod_operator_chat_sweep_artifact_smoke.latest.json'
    $historyPath = Join-Path $base 'tod_execution_readiness_history.latest.json'
    $statePath = Join-Path $base 'state.json'
    $configPath = Join-Path $base 'tod-config.json'
    $sourceConfigPath = Join-Path $repoRoot 'tod/config/tod-config.json'

    Set-TodApiRunReadinessArtifact -ArtifactPath $artifactPath -ArtifactAgeMinutes 1 -PassedAll:$true -ExitCode 0

    $state = [pscustomobject]@{
        source = 'tod-state-test-fixture-v1'
        updated_at = ''
        objectives = @(
            [pscustomobject]@{
                id = '75'
                title = 'Lifecycle readiness fixture objective'
                status = 'in_progress'
                constraints = @()
                success_criteria = @()
            }
        )
        tasks = @(
            [pscustomobject]@{ id = '41'; objective_id = '75'; title = 'Blocked fixture task'; scope = 'Exercise blocked pre-invocation report path.'; type = 'implementation'; task_category = 'code_change'; assigned_executor = 'codex'; status = 'blocked'; dependencies = @(); acceptance_criteria = @() },
            [pscustomobject]@{ id = '45'; objective_id = '75'; title = 'Report fixture task'; scope = 'Exercise wrapper readiness path.'; type = 'implementation'; task_category = 'refactor'; assigned_executor = 'codex'; status = 'pending'; dependencies = @(); acceptance_criteria = @() }
        )
        execution_results = @()
        review_decisions = @()
        journal = @()
        sync_state = [pscustomobject]@{ last_comparison = [pscustomobject]@{ status = 'ok' } }
        engine_performance = [pscustomobject]@{ records = @(); updated_at = (Get-Date).ToUniversalTime().ToString('o') }
        routing_decisions = [pscustomobject]@{ records = @(); updated_at = (Get-Date).ToUniversalTime().ToString('o') }
        engineering_loop = [pscustomobject]@{
            run_history = @()
            scorecard_history = @()
            cycle_records = @()
            review_actions = @()
            last_run = $null
            last_scorecard = $null
            updated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    $state | ConvertTo-Json -Depth 30 | Set-Content -Path $statePath

    $cfg = Get-Content -Path $sourceConfigPath -Raw | ConvertFrom-Json
    if (-not $cfg.execution_engine.PSObject.Properties['readiness_policy'] -or $null -eq $cfg.execution_engine.readiness_policy) {
        $cfg.execution_engine | Add-Member -NotePropertyName readiness_policy -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $cfg.execution_engine.readiness_policy = [pscustomobject]@{
        enabled = $true
        signal_path = $artifactPath
        history_path = $historyPath
        history_max_entries = 20
        max_artifact_age_minutes = 30
        display_max_artifact_age_minutes = 10
        block_actions = @('run-task')
        degrade_actions = @('engineer-run')
        block_states = @('stale', 'invalid', 'unknown')
        degrade_states = @('degraded', 'stale', 'invalid', 'unknown')
        degrade_apply_plan = $true
    }
    $cfg | ConvertTo-Json -Depth 40 | Set-Content -Path $configPath

    return [pscustomobject]@{
        Base = $base
        ArtifactPath = $artifactPath
        HistoryPath = $historyPath
        StatePath = $statePath
        ConfigPath = $configPath
    }
}

function Set-TodApiRunReadinessArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [int]$ArtifactAgeMinutes = 0,
        [bool]$PassedAll = $true,
        [int]$ExitCode = 0
    )

    $generatedAt = (Get-Date).ToUniversalTime().AddMinutes(-1 * $ArtifactAgeMinutes).ToString('o')
    $artifact = [pscustomobject]@{
        source = 'tod-operator-chat-sweep-artifact-smoke-v1'
        generated_at = $generatedAt
        summary = [pscustomobject]@{
            total = 13
            passed = if ($PassedAll -and $ExitCode -eq 0) { 13 } else { 12 }
            failed = if ($PassedAll -and $ExitCode -eq 0) { 0 } else { 1 }
            passed_all = $PassedAll
            exit_code = $ExitCode
        }
    }

    $artifact | ConvertTo-Json -Depth 20 | Set-Content -Path $ArtifactPath
}

function Set-TodApiRunReadinessScenario {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [Parameter(Mandatory = $true)][ValidateSet('degraded', 'stale', 'invalid', 'unknown')][string]$Scenario
    )

    switch ($Scenario) {
        'degraded' {
            Set-TodApiRunReadinessArtifact -ArtifactPath $Fixture.ArtifactPath -ArtifactAgeMinutes 12 -PassedAll:$true -ExitCode 0
        }
        'stale' {
            Set-TodApiRunReadinessArtifact -ArtifactPath $Fixture.ArtifactPath -ArtifactAgeMinutes 45 -PassedAll:$true -ExitCode 0
        }
        'invalid' {
            Set-TodApiRunReadinessArtifact -ArtifactPath $Fixture.ArtifactPath -ArtifactAgeMinutes 0 -PassedAll:$false -ExitCode 5
        }
        'unknown' {
            if (Test-Path -Path $Fixture.ArtifactPath) {
                Remove-Item -Path $Fixture.ArtifactPath -Force
            }
        }
    }
}

function Remove-TodApiRunReadinessFixture {
    param($Fixture)

    if ($Fixture -and $Fixture.Base -and (Test-Path -Path $Fixture.Base)) {
        Remove-Item -Path $Fixture.Base -Recurse -Force
    }
}

Describe 'Operator chat lifecycle regression' {
    It 'enforces exact readiness outcomes for governed confirmations across degraded stale invalid and unknown states' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        if (-not (Test-Path -Path $executionReadinessArtifactPath -PathType Leaf)) {
            return
        }

        $artifactBackup = Get-TodExecutionReadinessArtifactBackup
        try {
            $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
            $statusPayload.ok | Should Be $true

            $scenarioExpectations = @(
                @{ name = 'degraded'; expected_action_status = 'succeeded'; expected_policy_outcome = 'allow'; expected_blocked = $false },
                @{ name = 'stale'; expected_action_status = 'blocked'; expected_policy_outcome = 'block'; expected_blocked = $true },
                @{ name = 'invalid'; expected_action_status = 'blocked'; expected_policy_outcome = 'block'; expected_blocked = $true },
                @{ name = 'unknown'; expected_action_status = 'blocked'; expected_policy_outcome = 'block'; expected_blocked = $true }
            )

            foreach ($scenario in $scenarioExpectations) {
                Restore-TodExecutionReadinessArtifact -Content $artifactBackup
                Set-TodExecutionReadinessArtifactScenario -Scenario ([string]$scenario.name)

                $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
                    phase = 'preview'
                    action = 'refresh-project-status'
                    intent = 'summarize_status'
                    objective_id = [string]$statusPayload.selected_objective_id
                    query = 'Summarize dashboard state in operator language.'
                    window_minutes = 10
                    operator_id = 'pester-operator'
                    suggested_reason = 'Regression validation for readiness-gated governed confirmation.'
                    mode = 'read_only'
                }

                $previewPayload.ok | Should Be $true
                [string]$previewPayload.phase | Should Be 'preview'
                [bool]$previewPayload.allowed | Should Be $true
                [string]$previewPayload.preview_id | Should Not BeNullOrEmpty

                $confirmPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
                    phase = 'confirm'
                    preview_id = [string]$previewPayload.preview_id
                    action = 'refresh-project-status'
                    intent = 'summarize_status'
                    objective_id = [string]$statusPayload.selected_objective_id
                    query = 'Summarize dashboard state in operator language.'
                    window_minutes = 10
                    operator_id = 'pester-operator'
                    suggested_reason = 'Regression validation for readiness-gated governed confirmation.'
                    mode = 'read_only'
                }

                $confirmPayload.ok | Should Be $true
                [string]$confirmPayload.phase | Should Be 'confirm'
                [string]$confirmPayload.action_status | Should Be ([string]$scenario.expected_action_status)
                (($confirmPayload.PSObject.Properties.Name) -contains 'execution_readiness') | Should Be $true
                [string]$confirmPayload.execution_readiness.policy_outcome | Should Be ([string]$scenario.expected_policy_outcome)
                [string]$confirmPayload.execution_readiness.status | Should Be ([string]$scenario.name)

                if ([bool]$scenario.expected_blocked) {
                    [string]$confirmPayload.summary | Should Be 'Execution blocked by the authoritative certification gate.'
                    [string]($confirmPayload.flags -join '|') | Should Match 'execution_readiness_blocked'
                }
                else {
                    [string]$confirmPayload.summary | Should Not Be 'Execution blocked by the authoritative certification gate.'
                    [string]($confirmPayload.flags -join '|') | Should Not Match 'execution_readiness_blocked'
                }
            }
        }
        finally {
            Restore-TodExecutionReadinessArtifact -Content $artifactBackup
        }
    }

    It 'keeps repeated operator chat queries isolated by validation harness' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
        $statusPayload.ok | Should Be $true

        $query = 'Cache isolation regression {0}' -f ([guid]::NewGuid().ToString('N'))
        $commonBody = @{
            query = $query
            intent = 'summarize_status'
            objective_id = [string]$statusPayload.selected_objective_id
            window_minutes = 10
        }

        $plainPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body $commonBody
        $plainPayload.ok | Should Be $true
        (Get-TodValidationHarnessName -Payload $plainPayload) | Should Be ''

        $harnessPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body (@{} + $commonBody + @{ validation_harness = 'multi_objective_compare' })
        $harnessPayload.ok | Should Be $true
        (Get-TodValidationHarnessName -Payload $harnessPayload) | Should Be 'multi_objective_compare'
        [string]$harnessPayload.objective_id | Should Be ([string]$plainPayload.objective_id)

        $plainCachedPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body $commonBody
        $plainCachedPayload.ok | Should Be $true
        (Get-TodValidationHarnessName -Payload $plainCachedPayload) | Should Be ''
        [string]$plainCachedPayload.objective_id | Should Be ([string]$plainPayload.objective_id)
        [string]$plainCachedPayload.response.summary | Should Not BeNullOrEmpty

        $harnessCachedPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body (@{} + $commonBody + @{ validation_harness = 'multi_objective_compare' })
        $harnessCachedPayload.ok | Should Be $true
        (Get-TodValidationHarnessName -Payload $harnessCachedPayload) | Should Be 'multi_objective_compare'
        [string]$harnessCachedPayload.objective_id | Should Be ([string]$harnessPayload.objective_id)
        [string]$harnessCachedPayload.response.summary | Should Not BeNullOrEmpty
    }

    It 'applies readiness policy through the /api/run wrapper for run-task and engineer-run -ApplyPlan' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $fixture = New-TodApiRunReadinessFixture
        try {
            foreach ($scenario in @('stale', 'invalid', 'unknown')) {
                Set-TodApiRunReadinessScenario -Fixture $fixture -Scenario $scenario
                $payload = Invoke-TodJsonPost -Path '/api/run' -Body @{
                    action = 'run-task'
                    taskId = '45'
                    statePath = [string]$fixture.StatePath
                    configPath = [string]$fixture.ConfigPath
                }

                $payload.ok | Should Be $true
                [bool]$payload.result.blocked | Should Be $true
                [string]$payload.result.execution_readiness.status | Should Be $scenario
                [string]$payload.result.execution_readiness.policy_outcome | Should Be 'block'
            }

            foreach ($scenario in @('degraded', 'stale', 'invalid', 'unknown')) {
                Set-TodApiRunReadinessScenario -Fixture $fixture -Scenario $scenario
                $payload = Invoke-TodJsonPost -Path '/api/run' -Body @{
                    action = 'engineer-run'
                    top = 5
                    statePath = [string]$fixture.StatePath
                    configPath = [string]$fixture.ConfigPath
                    applyPlan = $true
                }

                $payload.ok | Should Be $true
                [string]$payload.result.execution_readiness.status | Should Be $scenario
                [bool]$payload.result.execution_readiness_degraded | Should Be $true
                [bool]$payload.result.apply_plan_effective | Should Be $false
                [string]$payload.result.execution_trace.execution_readiness.policy_outcome | Should Be 'degrade'
            }
        }
        finally {
            Remove-TodApiRunReadinessFixture -Fixture $fixture
        }
    }

    It 'honors request-scoped configPath instead of host defaults across wrapper surfaces' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $validFixture = New-TodApiRunReadinessFixture
        $blockedFixture = New-TodApiRunReadinessFixture
        try {
            Set-TodApiRunReadinessScenario -Fixture $blockedFixture -Scenario 'stale'

            $blockedRunPayload = Invoke-TodJsonPost -Path '/api/run' -Body @{
                action = 'run-task'
                taskId = '45'
                statePath = [string]$blockedFixture.StatePath
                configPath = [string]$blockedFixture.ConfigPath
            }

            $blockedRunPayload.ok | Should Be $true
            [bool]$blockedRunPayload.result.blocked | Should Be $true
            [string]$blockedRunPayload.result.execution_readiness.status | Should Be 'stale'
            [string]$blockedRunPayload.result.execution_readiness.config_path | Should Be ([string]$blockedFixture.ConfigPath)

            $validRunPayload = Invoke-TodJsonPost -Path '/api/run' -Body @{
                action = 'get-execution-readiness'
                configPath = [string]$validFixture.ConfigPath
            }

            $validRunPayload.ok | Should Be $true
            [string]$validRunPayload.result.readiness.status | Should Be 'valid'
            [string]$validRunPayload.result.readiness.reason | Should Be 'artifact_passed'
            [string]$validRunPayload.result.artifact_path | Should Be ([string]$validFixture.ArtifactPath)
            [string]$validRunPayload.result.history_path | Should Be ([string]$validFixture.HistoryPath)

            $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
            $statusPayload.ok | Should Be $true

            $previewBody = @{
                phase = 'preview'
                action = 'refresh-project-status'
                intent = 'summarize_status'
                objective_id = [string]$statusPayload.selected_objective_id
                query = 'Request scoped config regression for governed action confirms.'
                window_minutes = 10
                operator_id = 'pester-operator'
                suggested_reason = 'Ensure request config overrides host default readiness context.'
                mode = 'read_only'
            }

            $validPreviewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body (@{} + $previewBody + @{ configPath = [string]$validFixture.ConfigPath })
            $validPreviewPayload.ok | Should Be $true
            [bool]$validPreviewPayload.allowed | Should Be $true
            [string]$validPreviewPayload.preview_id | Should Not BeNullOrEmpty

            $validConfirmPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
                phase = 'confirm'
                preview_id = [string]$validPreviewPayload.preview_id
                action = 'refresh-project-status'
                intent = 'summarize_status'
                objective_id = [string]$statusPayload.selected_objective_id
                query = 'Request scoped config regression for governed action confirms.'
                window_minutes = 10
                operator_id = 'pester-operator'
                suggested_reason = 'Ensure request config overrides host default readiness context.'
                mode = 'read_only'
                configPath = [string]$validFixture.ConfigPath
            }

            $validConfirmPayload.ok | Should Be $true
            [string]$validConfirmPayload.action_status | Should Be 'succeeded'
            [string]$validConfirmPayload.execution_readiness.status | Should Be 'valid'
            [string]$validConfirmPayload.execution_readiness.policy_outcome | Should Be 'allow'
            [string]$validConfirmPayload.execution_readiness.config_path | Should Be ([string]$validFixture.ConfigPath)

            $blockedPreviewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body (@{} + $previewBody + @{ configPath = [string]$blockedFixture.ConfigPath })
            $blockedPreviewPayload.ok | Should Be $true
            [bool]$blockedPreviewPayload.allowed | Should Be $true
            [string]$blockedPreviewPayload.preview_id | Should Not BeNullOrEmpty

            $blockedConfirmPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
                phase = 'confirm'
                preview_id = [string]$blockedPreviewPayload.preview_id
                action = 'refresh-project-status'
                intent = 'summarize_status'
                objective_id = [string]$statusPayload.selected_objective_id
                query = 'Request scoped config regression for governed action confirms.'
                window_minutes = 10
                operator_id = 'pester-operator'
                suggested_reason = 'Ensure request config overrides host default readiness context.'
                mode = 'read_only'
                configPath = [string]$blockedFixture.ConfigPath
            }

            $blockedConfirmPayload.ok | Should Be $true
            [string]$blockedConfirmPayload.action_status | Should Be 'blocked'
            [string]$blockedConfirmPayload.summary | Should Be 'Execution blocked by the authoritative certification gate.'
            [string]$blockedConfirmPayload.execution_readiness.status | Should Be 'stale'
            [string]$blockedConfirmPayload.execution_readiness.policy_outcome | Should Be 'block'
            [string]$blockedConfirmPayload.execution_readiness.config_path | Should Be ([string]$blockedFixture.ConfigPath)
        }
        finally {
            Remove-TodApiRunReadinessFixture -Fixture $validFixture
            Remove-TodApiRunReadinessFixture -Fixture $blockedFixture
        }
    }

    It 'does not reuse generic direct operator-chat responses after commitment history changes' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status?validation_harness=multi_objective_compare'
        $statusPayload.ok | Should Be $true

        $query = 'What should I do next? direct-query-cache-regression {0}' -f ([guid]::NewGuid().ToString('N'))
        $chatBody = @{
            query = $query
            intent = 'suggest_next_action'
            objective_id = [string]$statusPayload.selected_objective_id
            window_minutes = 10
            validation_harness = 'multi_objective_compare'
        }

        $initialPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body $chatBody
        $initialPayload.ok | Should Be $true

        $suggestedAction = Get-TodIneffectiveValidationAction -SuggestedActions @($initialPayload.response.suggested_actions)
        if ($null -eq $suggestedAction) {
            return
        }

        $initialSuggestedAction = @($initialPayload.response.suggested_actions | Where-Object { [string]$_.action -eq [string]$suggestedAction.action } | Select-Object -First 1)
        $initialSameIntentAbandonedCount = if (@($initialSuggestedAction).Count -gt 0 -and $initialSuggestedAction[0].PSObject.Properties['history_same_intent_abandoned_count']) { [int]$initialSuggestedAction[0].history_same_intent_abandoned_count } else { 0 }
        $initialHistoryIneffectiveSignal = if (@($initialSuggestedAction).Count -gt 0 -and $initialSuggestedAction[0].PSObject.Properties['history_ineffective_signal']) { [bool]$initialSuggestedAction[0].history_ineffective_signal } else { $false }

        $previewIntent = if ($suggestedAction.PSObject.Properties['intent']) { [string]$suggestedAction.intent } else { 'suggest_next_action' }
        foreach ($cycle in @(1, 2)) {
            $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
                phase = 'preview'
                action = [string]$suggestedAction.action
                intent = $previewIntent
                objective_id = [string]$statusPayload.selected_objective_id
                query = $query
                window_minutes = 10
                operator_id = 'pester-operator'
                suggested_reason = [string]$suggestedAction.reason
                mode = [string]$suggestedAction.mode
            }

            [string]$previewPayload.preview_id | Should Not BeNullOrEmpty

            $committedPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
                preview_id = [string]$previewPayload.preview_id
                objective_id = [string]$statusPayload.selected_objective_id
                operator_id = 'pester-operator'
                state = 'committed'
                duration_minutes = 15
                validation_harness = 'multi_objective_compare'
            }
            $committedPayload.ok | Should Be $true

            $abandonedPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
                preview_id = [string]$previewPayload.preview_id
                objective_id = [string]$statusPayload.selected_objective_id
                operator_id = 'pester-operator'
                state = 'abandoned'
                duration_minutes = 15
                validation_harness = 'multi_objective_compare'
            }
            $abandonedPayload.ok | Should Be $true
        }

        $followupPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body $chatBody
        $followupPayload.ok | Should Be $true
        [string]$followupPayload.generated_at | Should Not Be ([string]$initialPayload.generated_at)

        $followupSuggestedAction = @($followupPayload.response.suggested_actions | Where-Object { [string]$_.action -eq [string]$suggestedAction.action } | Select-Object -First 1)
        $followupFlags = [string]($followupPayload.response.flags -join '|')

        if (@($followupSuggestedAction).Count -gt 0) {
            $followupSameIntentAbandonedCount = if ($followupSuggestedAction[0].PSObject.Properties['history_same_intent_abandoned_count']) { [int]$followupSuggestedAction[0].history_same_intent_abandoned_count } else { 0 }
            $followupHistoryIneffectiveSignal = if ($followupSuggestedAction[0].PSObject.Properties['history_ineffective_signal']) { [bool]$followupSuggestedAction[0].history_ineffective_signal } else { $false }

            [bool]($followupSameIntentAbandonedCount -ge $initialSameIntentAbandonedCount) | Should Be $true
            [bool]($followupHistoryIneffectiveSignal -or $followupFlags -match 'operator_commitment_ineffective') | Should Be $true
            if (-not $initialHistoryIneffectiveSignal) {
                [bool]$followupHistoryIneffectiveSignal | Should Be $true
            }
        }
        else {
            @($followupPayload.response.suggested_actions).Count | Should BeGreaterThan 0
            [string]$followupPayload.response.suggested_actions[0].action | Should Not Be ([string]$suggestedAction.action)
            [bool]($followupFlags -match 'operator_commitment_ineffective') | Should Be $true
        }
    }

    It 'keeps cadence noise suppression aligned with steady-state messaging' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
        $statusPayload.ok | Should Be $true
        $statusPayload.cadence_health | Should Not BeNullOrEmpty
        $statusPayload.steady_state | Should Not BeNullOrEmpty
        (($statusPayload.cadence_health.PSObject.Properties.Name) -contains 'governance') | Should Be $true
        (($statusPayload.steady_state.PSObject.Properties.Name) -contains 'regression_green') | Should Be $true

        $noiseSuppressed = [bool]$statusPayload.cadence_health.governance.noise_suppressed
        if ($noiseSuppressed) {
            [string]$statusPayload.steady_state.status | Should Match 'ok|warning'
            [bool]$statusPayload.steady_state.regression_green | Should Be $true
            [string]$statusPayload.steady_state.summary | Should Be 'Regression is green; cadence noise is present but execution truth remains healthy.'
            [string]($statusPayload.cadence_health.alerts -join '|') | Should Match 'cadence_noise_suppressed'
        }
        else {
            [bool]$statusPayload.cadence_health.governance.noise_suppressed | Should Be $false
        }
    }

    It 'keeps proposal lifecycle and bridge diagnostics consistent across status chat audit trust chain and commitments' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $statusPayload = Invoke-TodJsonGet -Path '/api/project-status'
        $statusPayload.ok | Should Be $true
        $statusPayload.bridge_status | Should Not BeNullOrEmpty
        (($statusPayload.bridge_status.PSObject.Properties.Name) -contains 'status_reason') | Should Be $true
        (($statusPayload.bridge_status.PSObject.Properties.Name) -contains 'listener_freshness_state') | Should Be $true
        (($statusPayload.bridge_status.PSObject.Properties.Name) -contains 'listener_fresh_threshold_seconds') | Should Be $true
        (($statusPayload.bridge_status.PSObject.Properties.Name) -contains 'sequence_state') | Should Be $true
        (($statusPayload.bridge_status.PSObject.Properties.Name) -contains 'artifact_completeness') | Should Be $true
        (($statusPayload.bridge_status.PSObject.Properties.Name) -contains 'missing_artifacts') | Should Be $true
        [string]$statusPayload.bridge_status.status_reason | Should Not BeNullOrEmpty
        [string]$statusPayload.bridge_status.listener_freshness_state | Should Match 'fresh|startup_lag|stale|unknown'
        [string]$statusPayload.bridge_status.sequence_state | Should Match 'sequence_aware|partial|missing'

        if (-not $statusPayload.PSObject.Properties['mim_proposal'] -or -not $statusPayload.mim_proposal -or -not [bool]$statusPayload.mim_proposal.available) {
            return
        }

        $chatPayload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What should I do next?'
            intent = 'suggest_next_action'
            window_minutes = 10
        }

        $chatPayload.ok | Should Be $true
        $proposalAction = @($chatPayload.response.suggested_actions | Where-Object { [string]$_.proposal_source -eq 'mim' } | Select-Object -First 1)
        if (@($proposalAction).Count -eq 0) {
            return
        }

        $refreshedStatusPayload = Invoke-TodJsonGet -Path '/api/project-status'
        $refreshedStatusPayload.ok | Should Be $true

        [bool](@([string]$statusPayload.mim_proposal.task_id, [string]$refreshedStatusPayload.mim_proposal.task_id) -contains [string]$proposalAction[0].proposal_id) | Should Be $true
        [string]$proposalAction[0].proposal_objective_id | Should Be ([string]$statusPayload.selected_objective_id)
        [string]$proposalAction[0].proposal_closure_status | Should Be ([string]$statusPayload.mim_proposal_closure.status)
        [string]$proposalAction[0].proposal_closure_disposition | Should Be ([string]$statusPayload.mim_proposal_closure.disposition)

        $previewPayload = Invoke-TodJsonPost -Path '/api/operator-chat-action' -Body @{
            phase = 'preview'
            action = [string]$proposalAction[0].action
            intent = 'suggest_next_action'
            objective_id = [string]$statusPayload.selected_objective_id
            query = 'What should I do next?'
            window_minutes = 10
            operator_id = 'pester-operator'
            suggested_reason = [string]$proposalAction[0].reason
            mode = [string]$proposalAction[0].mode
        }

        $previewId = [string]$previewPayload.preview_id
        $previewId | Should Not BeNullOrEmpty

        $auditPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-audit?preview_id={0}&limit=1" -f [uri]::EscapeDataString($previewId))
        $auditPayload.ok | Should Be $true
        $auditPayload.entries | Should Not BeNullOrEmpty
        [string]$auditPayload.entries[0].proposal_id | Should Be ([string]$statusPayload.mim_proposal.task_id)
        $auditPayload.proposal_lifecycle | Should Not BeNullOrEmpty
        [string]$auditPayload.proposal_lifecycle.status | Should Be ([string]$statusPayload.mim_proposal_closure.status)
        [string]$auditPayload.proposal_lifecycle.disposition | Should Be ([string]$statusPayload.mim_proposal_closure.disposition)

        $auditId = [string]$auditPayload.entries[0].audit_id
        $auditId | Should Not BeNullOrEmpty

        $trustPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-trust-chain?audit_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($auditId))
        $trustPayload.ok | Should Be $true
        $trustPayload.proposal_closure | Should Not BeNullOrEmpty
        [string]$trustPayload.proposal_closure.status | Should Be ([string]$statusPayload.mim_proposal_closure.status)
        [string]$trustPayload.proposal_closure.disposition | Should Be ([string]$statusPayload.mim_proposal_closure.disposition)

        $commitmentPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId
            objective_id = [string]$statusPayload.selected_objective_id
            operator_id = 'pester-operator'
            state = 'committed'
            duration_minutes = 15
        }

        $commitmentPayload.ok | Should Be $true
        [string]$commitmentPayload.commitment.scope_proposal_id | Should Be ([string]$statusPayload.mim_proposal.task_id)
        [string]$commitmentPayload.commitment.current_scope_proposal_id | Should Be ([string]$statusPayload.mim_proposal.task_id)
        [string]$commitmentPayload.commitment.scope_kind | Should Be 'proposal_specific'
        [string]$commitmentPayload.commitment.current_scope_kind | Should Be 'proposal_specific'
        [string]$commitmentPayload.commitment.scope_conflict_resolution | Should Match 'active|downgrade|block'
        [string]$commitmentPayload.commitment.scope_overlap_status | Should Be 'exact'
        [int]$commitmentPayload.commitment.scope_precedence_rank | Should Be 3
        [string]$commitmentPayload.commitment.scope_influence_summary | Should Not BeNullOrEmpty

        $commitmentId = [string]$commitmentPayload.commitment.commitment_id
        $commitmentId | Should Not BeNullOrEmpty

        $commitmentTrustPayload = Invoke-TodJsonGet -Path ("/api/operator-chat-action-trust-chain?commitment_id={0}&validation_harness=multi_objective_compare" -f [uri]::EscapeDataString($commitmentId))
        $commitmentTrustPayload.ok | Should Be $true
        $commitmentTrustPayload.proposal_closure | Should Not BeNullOrEmpty
        [string]$commitmentTrustPayload.proposal_closure.status | Should Be ([string]$statusPayload.mim_proposal_closure.status)
        $commitmentTrustPayload.commitments | Should Not BeNullOrEmpty
        [string]$commitmentTrustPayload.commitments[0].scope_kind | Should Be 'proposal_specific'
        [string]$commitmentTrustPayload.commitments[0].scope_conflict_resolution | Should Match 'active|downgrade|block'
        [string]$commitmentTrustPayload.commitments[0].scope_influence_summary | Should Not BeNullOrEmpty

        $clearPayload = Invoke-TodJsonPost -Path '/api/operator-chat-commitment' -Body @{
            preview_id = $previewId
            objective_id = [string]$statusPayload.selected_objective_id
            operator_id = 'pester-operator'
            state = 'cleared'
            duration_minutes = 15
        }

        $clearPayload.ok | Should Be $true
    }
}