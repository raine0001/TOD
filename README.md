# TOD

Development orchestration workspace for the MIM ecosystem.

Primary specification:
- [docs/tod-orchestrator-v1-spec.md](docs/tod-orchestrator-v1-spec.md)
- [docs/tod-mim-shared-contract-v1.md](docs/tod-mim-shared-contract-v1.md)
- [docs/mim-tod-alpha-link.md](docs/mim-tod-alpha-link.md)
- [docs/codex-result-format-v1.md](docs/codex-result-format-v1.md)

## TOD v1 Local Runner

PowerShell orchestration script:
- [scripts/TOD.ps1](scripts/TOD.ps1)

State and templates:
- [tod/data/state.json](tod/data/state.json)
- [tod/config/tod-config.json](tod/config/tod-config.json)
- [tod/templates/codex-task-prompt.md](tod/templates/codex-task-prompt.md)

MIM client modules:
- [client/mim_api_client.ps1](client/mim_api_client.ps1)
- [client/mim_api_helpers.ps1](client/mim_api_helpers.ps1)

### TOD-MIM Modes

Configure [tod/config/tod-config.json](tod/config/tod-config.json):

```json
{
	"mim_base_url": "http://192.168.1.120:8000",
	"mode": "hybrid",
	"timeout_seconds": 15,
	"fallback_to_local": true
}
```

- local: TOD uses local state files only.
- remote: TOD uses MIM API only.
- hybrid: TOD writes to MIM and caches local state.

Connectivity check:

```powershell
.\scripts\TOD.ps1 -Action ping-mim
```

Ping output includes:
- reachable
- health payload
- status payload
- elapsed_ms

Mapped actions:
- new-objective -> POST /objectives
- list-objectives -> GET /objectives
- add-task -> POST /tasks
- list-tasks -> GET /tasks
- add-result -> POST /results
- review-task -> POST /reviews
- show-journal -> GET /journal

Durable record rule:
- In remote and hybrid modes, MIM is the source of truth for workflow state.
- Objective IDs, task IDs, statuses, review outcomes, and journal history should come from MIM.

### Quickstart

1. Initialize (safe to run multiple times):

```powershell
.\scripts\TOD.ps1 -Action init
```

2. Create an objective:

```powershell
.\scripts\TOD.ps1 -Action new-objective `
	-Title "Build TOD v1" `
	-Description "Local orchestration loop and journal" `
	-Priority high `
	-Constraints "Do not modify unrelated systems" `
	-SuccessCriteria "Objective intake works,Task planning works,Review decisions are logged"
```

3. Add a task:

```powershell
.\scripts\TOD.ps1 -Action add-task `
	-ObjectiveId OBJ-0001 `
	-Title "Implement state persistence" `
	-Type implementation `
	-Scope "Add local JSON state store and save/load helpers" `
	-Dependencies "" `
	-AcceptanceCriteria "State file created,Load/save commands work"
```

4. Package task for Codex execution:

```powershell
.\scripts\TOD.ps1 -Action package-task -TaskId TSK-0001
```

5. Add execution result:

```powershell
.\scripts\TOD.ps1 -Action add-result `
	-TaskId TSK-0001 `
	-Summary "Implemented state persistence" `
	-FilesChanged "scripts/TOD.ps1,tod/data/state.json" `
	-TestsRun "manual smoke test" `
	-TestResults "pass" `
	-Failures "" `
	-Recommendations "Proceed to review"
```

6. Review task:

```powershell
.\scripts\TOD.ps1 -Action review-task `
	-TaskId TSK-0001 `
	-Decision pass `
	-Rationale "Acceptance criteria satisfied" `
	-UnresolvedIssues ""
```

7. Inspect state:

```powershell
.\scripts\TOD.ps1 -Action list-objectives
.\scripts\TOD.ps1 -Action list-tasks
.\scripts\TOD.ps1 -Action show-journal -Top 20
```

### Validated Bridge Run (Real Command Path)

The following flow was executed successfully against MIM at `http://192.168.1.120:8000`.

```powershell
$cfg='e:\TOD\tod\config\tod-config.json'

& .\scripts\TOD.ps1 -Action ping-mim -ConfigPath $cfg

$obj = (& .\scripts\TOD.ps1 -Action new-objective -ConfigPath $cfg -Title 'Bridge Step Test Objective' -Description 'Stepwise bridge validation' -SuccessCriteria 'loop works') | ConvertFrom-Json
$objectiveId = if($obj.objective_id){$obj.objective_id}elseif($obj.local){$obj.local.id}else{$obj.id}

$task = (& .\scripts\TOD.ps1 -Action add-task -ConfigPath $cfg -ObjectiveId $objectiveId -Title 'Bridge Step Test Task' -Scope 'Validate task/result/review flow' -AcceptanceCriteria 'journal has entries') | ConvertFrom-Json
$taskId = if($task.task_id){$task.task_id}elseif($task.local){$task.local.id}else{$task.id}

& .\scripts\TOD.ps1 -Action package-task -ConfigPath $cfg -TaskId $taskId

& .\scripts\TOD.ps1 -Action add-result -ConfigPath $cfg -TaskId $taskId -Summary 'Step test result' -FilesChanged 'scripts/TOD.ps1' -TestsRun 'step test' -TestResults 'pass' -Recommendations 'continue'

& .\scripts\TOD.ps1 -Action review-task -ConfigPath $cfg -TaskId $taskId -Decision pass -Rationale 'Step test succeeded'

& .\scripts\TOD.ps1 -Action show-journal -ConfigPath $cfg -Top 6
```

Observed from the validated run:
- Objective ID: 10
- Task ID: 8
- Result ID: 7
- Review ID: 7
- Latest journal action: create_review
