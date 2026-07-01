# TOD Command Reference

Quick command cheatsheet for operating TOD and the TOD Command Console.

## Core Runtime

```powershell
.\scripts\TOD.ps1 -Action init
.\scripts\TOD.ps1 -Action ping-mim
.\scripts\TOD.ps1 -Action safe_home
.\scripts\TOD.ps1 -Action compare-manifest
.\scripts\TOD.ps1 -Action sync-mim
```

`safe_home` uses the configured `MIM_ARM_SSH_*` or `MIM_SSH_*` settings from `.env`, opens an SSH session to the active arm host, and invokes the bounded `POST /go_safe` endpoint on the remote Flask runtime.

## Objectives and Tasks

```powershell
.\scripts\TOD.ps1 -Action new-objective -Title "..." -Description "..." -Priority high
.\scripts\TOD.ps1 -Action list-objectives

.\scripts\TOD.ps1 -Action add-task -ObjectiveId <ID> -Title "..." -Type implementation -Scope "..."
.\scripts\TOD.ps1 -Action list-tasks -ObjectiveId <ID>
.\scripts\TOD.ps1 -Action package-task -TaskId <ID>
.\scripts\TOD.ps1 -Action run-task -TaskId <ID>
.\scripts\TOD.ps1 -Action run-task-report -TaskId <ID>
```

Use `run-task` only for resolvable MIM `/tasks` registry IDs. Do not pass listener bridge request IDs to this lane.

## Bridge Requests

```powershell
.\scripts\TOD.ps1 -Action run-bridge-request -RequestId <REQUEST_ID>
```

`run-bridge-request` reads `tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json`, validates that the live `request_id` matches `-RequestId`, and dispatches the packet through the bridge execution lane. It does not use `/tasks` lookup or local task-state resolution.

## Results and Review

```powershell
.\scripts\TOD.ps1 -Action add-result -TaskId <ID> -Summary "..." -TestResults "pass"
.\scripts\TOD.ps1 -Action review-task -TaskId <ID> -Decision pass -Rationale "..."
.\scripts\TOD.ps1 -Action show-journal -Top 25
```

## Reliability and Routing

```powershell
.\scripts\TOD.ps1 -Action get-reliability
.\scripts\TOD.ps1 -Action show-reliability-dashboard -Top 25
.\scripts\TOD.ps1 -Action show-engine-performance
.\scripts\TOD.ps1 -Action show-routing-decisions
.\scripts\TOD.ps1 -Action show-routing-feedback
.\scripts\TOD.ps1 -Action show-failure-taxonomy
.\scripts\TOD.ps1 -Action get-capabilities
.\scripts\TOD.ps1 -Action get-execution-readiness
.\scripts\TOD.ps1 -Action get-research -Top 10
.\scripts\TOD.ps1 -Action get-resourcing -ObjectiveId <ID> -Top 10
.\scripts\TOD.ps1 -Action engineer-run -Top 10
.\scripts\TOD.ps1 -Action engineer-run -TaskId <ID> -ApplyPlan
.\scripts\TOD.ps1 -Action engineer-scorecard -Top 25
.\scripts\TOD.ps1 -Action sandbox-list -Top 25
.\scripts\TOD.ps1 -Action sandbox-plan -SandboxPath "notes/demo.txt" -Content "planned content"
.\scripts\TOD.ps1 -Action sandbox-apply-plan -SandboxPlanPath "tod/sandbox/artifacts/PLAN-XXXXXXXXXX.json"
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "notes/demo.txt" -Content "hello sandbox"
.\scripts\TOD.ps1 -Action get-state-bus
.\scripts\TOD.ps1 -Action get-version
.\scripts\Invoke-TODWatchdogDriftGuard.ps1 -AutoCorrect -RestartUiOnFailure -EmitJson
.\scripts\Register-TODWatchdogDriftGuardTask.ps1 -CheckEveryMinutes 15 -RestartUiOnFailure -TriggerMaintenanceOnUnresolved -IncludeLogonTrigger
.\scripts\Register-TODWatchdogDriftGuardTask.ps1 -TaskName "TOD-Watchdog-DriftGuard-Training" -CheckEveryMinutes 5 -RestartUiOnFailure -TriggerMaintenanceOnUnresolved -ActiveWindows "06:00-23:00" -IncludeLogonTrigger
.\scripts\Register-TODWatchdogDriftGuardTask.ps1 -TaskName "TOD-Watchdog-DriftGuard-Overnight" -CheckEveryMinutes 30 -RestartUiOnFailure -TriggerMaintenanceOnUnresolved -ActiveWindows "23:00-06:00" -IncludeLogonTrigger
.\scripts\Get-TODDriftGuardCoverageHealth.ps1
```

Execution-readiness policy notes:

- `get-execution-readiness` returns the normalized TOD sweep certification signal from `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json`.
- operational certification on this host comes from `scripts/Test-TODOperatorChatSweepArtifact.ps1` writing `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json`.
- extended validation comes from the slower full operator-chat sweep and is not the primary host certification gate.
- wrapper launch surfaces must evaluate readiness before child execution and must use a supplied request `configPath` instead of silently reverting to the host default config.
- direct `/api/operator-chat` must not use generic response caching because commitment and sweep state changes have to remain visible immediately.
- the sweep `-ArtifactOnly` ineffective branch must remain live-derived and self-contained.
- `run-task` can be blocked when the readiness artifact is stale or invalid.
- `engineer-run -ApplyPlan` can be degraded to advisory-only mode when readiness policy is not satisfied.
- readiness states are standardized as `valid`, `degraded`, `stale`, `invalid`, and `unknown`.
- `POST /api/run` with `action = get-execution-readiness` returns the current readiness payload plus recent transition history.

Operator-chat cache rule:

- safe to cache: helper query resolution, harness-isolated query caches, preview reuse when the shared preview state is intentional.
- unsafe to cache: generic direct `/api/operator-chat` responses, commitment-history-sensitive recommendation paths, sweep-sensitive stateful chat branches.

Readiness history notes:

- `shared_state/tod_execution_readiness_history.latest.json` records prior/new status, reason, timestamp, artifact path, and host/session metadata for each transition.

## TOD Command Console (UI)

```powershell
.\scripts\Start-TOD-UI.ps1 -Port 8844
```

Notes:

- If the requested port is busy, TOD auto-falls forward to the next available port.
- Open the printed URL in browser.

Optional command alias module:

```powershell
Import-Module TODTools -DisableNameChecking -Force
Start-TOD-UI -Port 8844
```

## Debug Logging

```powershell
Get-Content .\tod\out\mim-http.log -Tail 20
```

`mim-http.log` is populated when `mim_debug.enabled` is `true` in `tod/config/tod-config.json`.

## TOD Execution Lane Proof

TOD local execution lane proof task TOD-LANE-PROOF-20260604172442 completed through bounded docs append.

## TOD Active Lane Success Proof TOD-LANE-SUCCESS-PROOF-20260604173953

TOD active execution lane success proof task TOD-LANE-SUCCESS-PROOF-20260604173953 completed through bounded docs append.

## TOD Hardened Lane Proof TOD-LANE-HARDENED-PROOF-20260604175325

TOD hardened lane proof task TOD-LANE-HARDENED-PROOF-20260604175325 completed through bounded docs append with source-artifact acceptance text.

## TOD Useful Work Roundtrip Evidence

TOD completed a bounded local docs edit through LocalExecutionEngine as part of the proactive growth lane. Evidence marker: TOD-GROWTH-ROUNDTRIP-001.

## Update docs/tod-command-reference.md. Edit Mode: docs_append_section

TOD can use the local fallback executor for bounded tasks in docs/tod-command-reference.md when Codex only returns wrapper output or no meaningful execution evidence.

- Eligibility stays inside bounded docs, code, config, or test changes under allowed paths.
- Published evidence includes changed files, diff summary, command output, validation results, blockers, and rollback hints.
- The executor fails closed when it cannot infer a safe target or bounded patch.

## TOD Successor Loop Evidence 004A

TOD completed a clean multiline first task after repairing selected task identity and material proof count handling. Evidence marker: TOD-GROWTH-SUCCESSOR-004A.

## TOD Successor Loop Evidence 004B

TOD completed the automatically selected successor task after the first task finished. Evidence marker: TOD-GROWTH-SUCCESSOR-004B.

## TOD Chain Proof A

TOD completed task A and should select task B next. Evidence marker: TOD-CHAIN-A-SUCCESS-001.

## TOD Chain Proof C

TOD selected the safe recovery task after the intentional blocker. Evidence marker: TOD-CHAIN-C-SAFE-001.

## Dave-Away Bounded Dispatch Lessons 2026-06-14

During the Dave-away training loop, quote-heavy direct chat dispatches produced malformed task packets when exact Python replacement text was embedded in command-line arguments. Future TOD code-change nudges should prefer explicit -TargetFile metadata and file-backed or simple bounded directives. If a task lacks exactly one target_file, TOD must block with blocked_missing_bounded_edit_mode instead of claiming wrapper or validation-only progress.
