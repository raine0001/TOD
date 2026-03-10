# MIM-TOD Alpha Link

## Objective
Establish the first unified workflow where TOD drives planning and execution flow while MIM is the durable system of record.

Rule:
- TOD plans.
- MIM remembers.

## Success Criteria
- TOD reads and writes workflow state through MIM endpoints.
- MIM persists objectives, tasks, results, reviews, and journal entries.
- Journal reflects the full lifecycle for a build task.
- One end-to-end workflow completes through the bridge.

## Required Integration Test Loop
1. ping-mim
2. create objective in MIM
3. create task in MIM
4. package task locally
5. record result in MIM
6. review task in MIM
7. fetch journal from MIM

## Example Commands
```powershell
.\scripts\TOD.ps1 -Action ping-mim

$obj = (.\scripts\TOD.ps1 -Action new-objective -Title "Alpha Link Objective" -Description "Bridge test" -SuccessCriteria "loop complete") | ConvertFrom-Json
$objectiveId = if ($obj.objective_id) { [string]$obj.objective_id } elseif ($obj.local) { [string]$obj.local.id } else { [string]$obj.id }

$task = (.\scripts\TOD.ps1 -Action add-task -ObjectiveId $objectiveId -Title "Alpha Link Task" -Scope "Run full loop" -AcceptanceCriteria "loop complete") | ConvertFrom-Json
$taskId = if ($task.task_id) { [string]$task.task_id } elseif ($task.local) { [string]$task.local.id } else { [string]$task.id }

.\scripts\TOD.ps1 -Action package-task -TaskId $taskId

.\scripts\TOD.ps1 -Action add-result -TaskId $taskId -Summary "Result recorded" -FilesChanged "scripts/TOD.ps1" -TestsRun "integration" -TestResults "pass" -Recommendations "continue"

.\scripts\TOD.ps1 -Action review-task -TaskId $taskId -Decision pass -Rationale "Loop succeeded"

.\scripts\TOD.ps1 -Action show-journal -Top 10
```

## Notes
- In remote and hybrid modes, objective and task identity should come from MIM.
- Hybrid mode can cache locally for resilience and inspection.
- If MIM is unavailable in hybrid mode and fallback is enabled, TOD can continue locally.
