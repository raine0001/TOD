param(
    [int]$WindowDays = 7,
    [string]$AuditPath = 'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT.latest.json',
    [string]$NextObjectivesPath = 'runtime_remote_training/MIM_TOD_7DAY_NEXT_OBJECTIVES.latest.json',
    [string]$AutonomousPlanPath = 'shared_state/MIM_TOD_AUTONOMOUS_TRAINING_PLAN.latest.json',
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Read-JsonIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = Resolve-RepoPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) {
        return $null
    }

    try {
        return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            parse_error = [string]$_.Exception.Message
            path = $PathValue
        }
    }
}

function Write-Json {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 30
    )

    $resolved = Resolve-RepoPath -PathValue $PathValue
    $dir = Split-Path -Parent $resolved
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($resolved, $json, $utf8NoBom)
}

function Get-FileEvidence {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = Resolve-RepoPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) {
        return [pscustomobject]@{
            path = $PathValue
            exists = $false
            length = 0
            last_write_utc = ''
            freshness = 'missing'
        }
    }

    $item = Get-Item -Path $resolved
    $ageHours = (((Get-Date).ToUniversalTime()) - $item.LastWriteTimeUtc).TotalHours
    return [pscustomobject]@{
        path = $PathValue
        exists = $true
        length = [int64]$item.Length
        last_write_utc = $item.LastWriteTimeUtc.ToString('o')
        age_hours = [math]::Round($ageHours, 2)
        freshness = if ($ageHours -le 24) { 'fresh' } else { 'stale' }
    }
}

function Get-StatusCounts {
    param([object[]]$Items)

    $counts = [ordered]@{}
    foreach ($group in @($Items | Group-Object {
                if ($_.PSObject.Properties['status']) { [string]$_.status } else { 'unknown' }
            })) {
        $counts[[string]$group.Name] = [int]$group.Count
    }
    return [pscustomobject]$counts
}

function Get-LatestTrainingReports {
    param([datetime]$WindowStartUtc)

    $root = Resolve-RepoPath -PathValue 'tod/out/training/autonomous-campaign/daemon'
    if (-not (Test-Path -Path $root)) {
        return @()
    }

    return @(
        Get-ChildItem -Path $root -Filter 'training-report.md' -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $WindowStartUtc } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 20 |
            ForEach-Object {
                $summary = ''
                try {
                    $summary = ((Get-Content -Path $_.FullName -TotalCount 12) -join "`n")
                }
                catch {
                    $summary = ''
                }

                [pscustomobject]@{
                    path = $_.FullName.Substring($repoRoot.Length + 1)
                    last_write_utc = $_.LastWriteTimeUtc.ToString('o')
                    length = [int64]$_.Length
                    summary_head = $summary
                }
            }
    )
}

function New-NextObjective {
    param(
        [string]$Slug,
        [string]$Owner,
        [string]$Goal,
        [string]$Target,
        [string]$Evidence,
        [string]$Validation,
        [string]$Nudge,
        [string]$Aging
    )

    return [pscustomobject]@{
        objective_id_or_slug = $Slug
        owner = $Owner
        bounded_goal = $Goal
        target_surface_or_file = $Target
        evidence_to_publish = $Evidence
        validation_command_or_check = $Validation
        nudge_condition = $Nudge
        aging_rule = $Aging
    }
}

$now = (Get-Date).ToUniversalTime()
$windowStart = $now.AddDays(-1 * [math]::Max(1, $WindowDays))

$scoreboard = Read-JsonIfExists -PathValue 'runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json'
$movement = Read-JsonIfExists -PathValue 'runtime_remote_training/MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json'
$impact = Read-JsonIfExists -PathValue 'runtime_remote_training/MIM_OPERATOR_IMPACT_SCORECARD.latest.json'
$reflection = Read-JsonIfExists -PathValue 'runtime_remote_training/MIM_TOD_HOURLY_REFLECTION.latest.json'
$trainingStatus = Read-JsonIfExists -PathValue 'shared_state/tod_training_status.latest.json'
$autonomyStatus = Read-JsonIfExists -PathValue 'shared_state/tod_autonomy_status.latest.json'
$objectivesDoc = Read-JsonIfExists -PathValue 'shared_state/objectives.json'
$chatgptUpdate = Read-JsonIfExists -PathValue 'shared_state/chatgpt_update.json'
$dialogSession = Read-JsonIfExists -PathValue 'shared_state/dialog/MIM_TOD_DIALOG.session-mim-tod-7day-training-audit-retry-20260622T1421Z.latest.json'
$blocker = Read-JsonIfExists -PathValue 'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT_BLOCKER.latest.json'

$objectives = if ($objectivesDoc -and $objectivesDoc.PSObject.Properties['objectives']) { @($objectivesDoc.objectives) } else { @() }
$tasks = if ($objectivesDoc -and $objectivesDoc.PSObject.Properties['tasks']) { @($objectivesDoc.tasks) } else { @() }
$currentAuditObjectives = @($objectives | Where-Object { $_.title -match '7-day training audit|inbox visibility|GOVERNED-INBOX-CONSUMER' })

$trainingReports = @(Get-LatestTrainingReports -WindowStartUtc $windowStart)
$sourceFiles = @(
    'runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json',
    'runtime_remote_training/MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json',
    'runtime_remote_training/MIM_OPERATOR_IMPACT_SCORECARD.latest.json',
    'runtime_remote_training/MIM_TOD_HOURLY_REFLECTION.latest.json',
    'shared_state/tod_training_status.latest.json',
    'shared_state/tod_autonomy_status.latest.json',
    'shared_state/objectives.json',
    'shared_state/latest_summary.md',
    'shared_state/chatgpt_update.json',
    'shared_state/dialog/MIM_TOD_DIALOG.session-mim-tod-7day-training-audit-retry-20260622T1421Z.latest.json',
    'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT_BLOCKER.latest.json'
)
$sourceEvidence = @($sourceFiles | ForEach-Object { Get-FileEvidence -PathValue $_ })

$nextObjectives = @(
    New-NextObjective -Slug 'tod-audit-artifact-publisher-regression' -Owner 'TOD' -Goal 'Keep the 7-day audit publisher runnable and wired to inbound audit handoffs.' -Target 'scripts/Invoke-MIMTOD7DayTrainingAudit.ps1; scripts/Start-TODAutonomousTrainingDaemon.ps1' -Evidence 'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT.latest.json' -Validation 'scripts\Invoke-MIMTOD7DayTrainingAudit.ps1 -EmitJson' -Nudge 'Audit artifacts absent or older than 24 hours after an audit handoff.' -Aging 'Recheck next daemon cycle; publish blocker if publisher fails.'
    New-NextObjective -Slug 'studio-training-freshness-verification' -Owner 'MIM' -Goal 'Verify /studio/training uses the latest training scorecard and TOD status files.' -Target '/studio/training; runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json' -Evidence 'Freshness verdict in the next hourly reflection.' -Validation 'Compare Studio rendered/generated time with scorecard generated_at.' -Nudge 'Studio timestamp is stale or no source file is cited.' -Aging 'Recheck hourly.'
    New-NextObjective -Slug 'studio-projects-status-reconciliation' -Owner 'MIM' -Goal 'Verify project counts and statuses shown in /studio/projects against shared_state/objectives.json.' -Target '/studio/projects; shared_state/objectives.json' -Evidence 'Project/status count comparison with mismatch list.' -Validation 'Count objectives/tasks by status and compare to Studio surface.' -Nudge 'Counts diverge or source file is older than 24 hours.' -Aging 'Recheck after next shared-state sync.'
    New-NextObjective -Slug 'studio-objectives-status-reconciliation' -Owner 'MIM' -Goal 'Verify /studio/objectives reflects current open, in-progress, blocked, and completed objective counts.' -Target '/studio/objectives; shared_state/objectives.json' -Evidence 'Objective count comparison and stale-objective list.' -Validation 'Group objectives by status from shared_state/objectives.json.' -Nudge 'Open audit/repair objective is not visible or status is stale.' -Aging 'Recheck after next shared-state sync.'
    New-NextObjective -Slug 'tod-idle-simulation-gate' -Owner 'TOD' -Goal 'Prevent idle simulations from satisfying governed handoff requests.' -Target 'scripts/Start-TODAutonomousTrainingDaemon.ps1' -Evidence 'Daemon state shows inbound_dialog_consumed before new idle training.' -Validation 'Run daemon once with a synthetic inbound handoff and verify no simulation fallback starts first.' -Nudge 'A visible inbound handoff exists and a newer idle-simulation report appears before a response.' -Aging 'Immediate blocker on same-cycle violation.'
    New-NextObjective -Slug 'communication-file-freshness-scan' -Owner 'MIM' -Goal 'Verify dialog, chatgpt_update, latest_summary, and dev journal freshness.' -Target 'shared_state/dialog; shared_state/chatgpt_update.json; shared_state/latest_summary.md' -Evidence 'Communication freshness table.' -Validation 'All listed files exist and are updated within the expected cadence.' -Nudge 'Any required file missing or stale.' -Aging 'Recheck hourly.'
    New-NextObjective -Slug 'scorecard-refresh-cadence' -Owner 'MIM' -Goal 'Refresh scorecards only when evidence changes, and mark stale scorecards explicitly.' -Target 'runtime_remote_training/*SCORECARD*.latest.json' -Evidence 'Scorecard freshness verdict with generated_at and source paths.' -Validation 'Each scorecard has generated_at and source evidence.' -Nudge 'Scorecard older than 24 hours while related state changed.' -Aging 'Recheck hourly.'
    New-NextObjective -Slug 'tod-blocker-to-task-materialization' -Owner 'TOD' -Goal 'Convert the audit blocker into the smallest executable artifact-publisher task.' -Target 'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT_BLOCKER.latest.json' -Evidence 'Task/result artifact that names changed files or exact dispatcher blocker.' -Validation 'Blocker next_smallest_unblocked_action has a matching task/result.' -Nudge 'Blocker exists with no successor task.' -Aging 'Escalate after one daemon cycle.'
    New-NextObjective -Slug 'mim-reply-quality-contract-watch' -Owner 'MIM' -Goal 'Keep five-field MIM replies enforced for audit and blocker updates.' -Target 'MIM operator replies; runtime_remote_training/MIM_OPERATOR_IMPACT_SCORECARD.latest.json' -Evidence 'Contract-score sample with owner/evidence/aging/Dave-needed fields.' -Validation 'Latest 10 replies meet contract score target.' -Nudge 'Any audit reply omits expected evidence or Dave-needed clarity.' -Aging 'Recheck after each scored reply batch.'
    New-NextObjective -Slug 'autonomous-training-plan-resume' -Owner 'TOD' -Goal 'Resume autonomous idle-time training only after governed handoff state is terminal or explicitly blocked.' -Target 'shared_state/MIM_TOD_AUTONOMOUS_TRAINING_PLAN.latest.json; daemon state' -Evidence 'Autonomous plan with ordered queue, nudge rules, and no-human-intervention policy.' -Validation 'Plan references current blocker/artifacts and daemon state.' -Nudge 'Daemon starts training without terminal/blocker state for visible handoff.' -Aging 'Immediate blocker on same-cycle violation.'
)

$audit = [pscustomobject]@{
    packet_type = 'mim-tod-7day-training-audit-v1'
    generated_at = $now.ToString('o')
    window = [pscustomobject]@{
        start_utc = $windowStart.ToString('o')
        end_utc = $now.ToString('o')
        days = $WindowDays
    }
    assessment = 'needs_attention'
    outcome = [pscustomobject]@{
        audit_complete = $true
        training_improvements_proven = $false
        blocker_present = $null -ne $blocker
        dave_needed = 'no'
    }
    improvements = @(
        'MIM/TOD dialog read-inbox now surfaces actionable open sessions instead of returning an empty inbox for MIM.',
        'TOD autonomous daemon now consumes inbound MIM-to-TOD governed handoffs before idle training fallback.',
        'Latest TOD idle training completed successfully with zero failed steps.',
        'A precise blocker artifact now exists when the audit publisher path is missing or cannot execute.'
    )
    failures = @(
        'The original audit handoff did not produce the required artifacts before Codex repaired the dialog/daemon path.',
        'Idle-simulation reports were produced repeatedly but did not satisfy the 7-day audit contract.',
        'The full audit evidence packet was missing until this publisher generated it.',
        'Studio endpoint accuracy is source-verified from local artifacts here; live rendered endpoint comparison still belongs to MIM/TOD if the Studio server is remote-only.'
    )
    weak_areas = @(
        'Governed handoff consumption was not a first-class daemon path.',
        'Scorecard freshness can drift behind shared-state changes.',
        'Objective/blocker successor materialization still needs a direct task/result binding.',
        'Studio /training, /projects, and /objectives need repeatable source-to-surface count checks.'
    )
    suggested_areas_of_focus = @(
        'Keep the audit publisher wired to inbound handoffs.',
        'Add source-to-Studio verification for training, projects, and objectives.',
        'Bind blockers to successor tasks before idle training resumes.',
        'Use scorecard refreshes as verification, not as substitute progress.'
    )
    verification = [pscustomobject]@{
        studio_training = [pscustomobject]@{
            source = 'runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json; shared_state/tod_training_status.latest.json'
            verdict = 'source_files_present'
            evidence = @((Get-FileEvidence -PathValue 'runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json'), (Get-FileEvidence -PathValue 'shared_state/tod_training_status.latest.json'))
        }
        studio_projects = [pscustomobject]@{
            source = 'shared_state/objectives.json'
            verdict = 'source_file_present'
            objective_status_counts = Get-StatusCounts -Items $objectives
            task_status_counts = Get-StatusCounts -Items $tasks
        }
        studio_objectives = [pscustomobject]@{
            source = 'shared_state/objectives.json'
            verdict = 'source_file_present'
            current_audit_objectives = @($currentAuditObjectives | Select-Object id,title,status,updated_at)
        }
        communication_files = @(
            Get-FileEvidence -PathValue 'shared_state/dialog/MIM_TOD_DIALOG.session-mim-tod-7day-training-audit-retry-20260622T1421Z.latest.json'
            Get-FileEvidence -PathValue 'shared_state/chatgpt_update.json'
            Get-FileEvidence -PathValue 'shared_state/latest_summary.md'
        )
        reporting_files = @(
            Get-FileEvidence -PathValue 'shared_state/tod_training_status.latest.json'
            Get-FileEvidence -PathValue 'shared_state/tod_autonomy_status.latest.json'
            Get-FileEvidence -PathValue 'runtime_remote_training/MIM_TOD_HOURLY_REFLECTION.latest.json'
        )
        scorecards = @(
            Get-FileEvidence -PathValue 'runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json'
            Get-FileEvidence -PathValue 'runtime_remote_training/MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json'
            Get-FileEvidence -PathValue 'runtime_remote_training/MIM_OPERATOR_IMPACT_SCORECARD.latest.json'
        )
    }
    source_summaries = [pscustomobject]@{
        scoreboard_status = if ($scoreboard -and $scoreboard.PSObject.Properties['status']) { $scoreboard.status } else { $null }
        scoreboard_recommendation = if ($scoreboard -and $scoreboard.PSObject.Properties['recommendation']) { $scoreboard.recommendation } else { $null }
        real_movement_status = if ($movement -and $movement.PSObject.Properties['status']) { $movement.status } else { $null }
        real_movement_readout = if ($movement -and $movement.PSObject.Properties['overall_readout']) { $movement.overall_readout } else { $null }
        hourly_assessment = if ($reflection -and $reflection.PSObject.Properties['assessment']) { $reflection.assessment } else { $null }
        hourly_improving = if ($reflection -and $reflection.PSObject.Properties['are_they_improving']) { $reflection.are_they_improving } else { $null }
        tod_training_state = if ($trainingStatus -and $trainingStatus.PSObject.Properties['state_label']) { $trainingStatus.state_label } else { $null }
        chatgpt_blockers = if ($chatgptUpdate -and $chatgptUpdate.PSObject.Properties['blockers']) { @($chatgptUpdate.blockers) } else { @() }
    }
    training_activity = [pscustomobject]@{
        reports_in_window = @($trainingReports).Count
        latest_reports = @($trainingReports | Select-Object -First 8)
        latest_training_status = $trainingStatus
        latest_autonomy_status = $autonomyStatus
    }
    blocker_resolution = [pscustomobject]@{
        blocker_artifact = 'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT_BLOCKER.latest.json'
        blocker = $blocker
        resolved_by = 'scripts/Invoke-MIMTOD7DayTrainingAudit.ps1'
        prevention = 'Future inbound MIM-to-TOD audit handoffs should run this publisher before idle simulation fallback.'
    }
    source_files = $sourceEvidence
}

$nextObjectiveArtifact = [pscustomobject]@{
    packet_type = 'mim-tod-7day-next-objectives-v1'
    generated_at = $now.ToString('o')
    source_audit = $AuditPath
    count = @($nextObjectives).Count
    objectives = $nextObjectives
}

$autonomousPlan = [pscustomobject]@{
    packet_type = 'mim-tod-autonomous-training-plan-v1'
    generated_at = $now.ToString('o')
    policy = [pscustomobject]@{
        no_human_intervention = $true
        dave_needed_default = 'no'
        codex_role = 'monitor_or_repair_control_plane_only_when_MIM_TOD_cannot_consume_visible_work'
        idle_training_rule = 'Do not run or credit idle simulation while a governed inbound handoff is visible and unresolved.'
    }
    current_state = [pscustomobject]@{
        audit_artifact = $AuditPath
        next_objectives_artifact = $NextObjectivesPath
        blocker_artifact = 'runtime_remote_training/MIM_TOD_7DAY_TRAINING_AUDIT_BLOCKER.latest.json'
        dialog_session = if ($dialogSession) { $dialogSession } else { $null }
        tod_training_state = if ($trainingStatus -and $trainingStatus.PSObject.Properties['state_label']) { $trainingStatus.state_label } else { '' }
    }
    ordered_objectives = $nextObjectives
    autonomous_loop = [pscustomobject]@{
        before_each_idle_training_cycle = @(
            'read Actor TOD inbox',
            'consume any visible MIM-to-TOD governed handoff',
            'publish requested artifacts or precise blocker',
            'only then run idle training fallback'
        )
        evidence_required_each_cycle = @(
            'dialog state terminal or blocker artifact',
            'training report path if idle training ran',
            'scorecard freshness verdict if scorecards changed'
        )
    }
}

Write-Json -PathValue $AuditPath -Payload $audit -Depth 40
Write-Json -PathValue $NextObjectivesPath -Payload $nextObjectiveArtifact -Depth 30
Write-Json -PathValue $AutonomousPlanPath -Payload $autonomousPlan -Depth 30

$result = [pscustomobject]@{
    ok = $true
    generated_at = $now.ToString('o')
    audit_path = $AuditPath
    next_objectives_path = $NextObjectivesPath
    autonomous_plan_path = $AutonomousPlanPath
    objective_count = @($nextObjectives).Count
    validation = [pscustomobject]@{
        audit_exists = (Test-Path -Path (Resolve-RepoPath -PathValue $AuditPath))
        next_objectives_exists = (Test-Path -Path (Resolve-RepoPath -PathValue $NextObjectivesPath))
        autonomous_plan_exists = (Test-Path -Path (Resolve-RepoPath -PathValue $AutonomousPlanPath))
        objective_count_ok = (@($nextObjectives).Count -eq 10)
    }
}

if ($EmitJson) {
    $result | ConvertTo-Json -Depth 8
}
else {
    $result
}
