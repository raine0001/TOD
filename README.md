# TOD

Development orchestration workspace for the MIM ecosystem.

Primary specification:
- [docs/tod-orchestrator-v1-spec.md](docs/tod-orchestrator-v1-spec.md)
- [docs/tod-command-reference.md](docs/tod-command-reference.md)
- [docs/tod-state-bus-contract-v1.md](docs/tod-state-bus-contract-v1.md)
- [docs/tod-mim-shared-contract-v1.md](docs/tod-mim-shared-contract-v1.md)
- [docs/mim-tod-execution-feedback-contract-v1.md](docs/mim-tod-execution-feedback-contract-v1.md)
- [docs/mim-manifest-contract-v1.md](docs/mim-manifest-contract-v1.md)
- [docs/task24-mim-post-journal-handoff.md](docs/task24-mim-post-journal-handoff.md)
- [docs/execution-engine-interface-v1.md](docs/execution-engine-interface-v1.md)
- [docs/codex-execution-engine-v1.md](docs/codex-execution-engine-v1.md)
- [docs/local-execution-engine-v1.md](docs/local-execution-engine-v1.md)
- [docs/mim-tod-alpha-link.md](docs/mim-tod-alpha-link.md)
- [docs/codex-result-format-v1.md](docs/codex-result-format-v1.md)

## TOD v1 Local Runner

PowerShell orchestration script:
- [scripts/TOD.ps1](scripts/TOD.ps1)
- [scripts/TOD-Engineer.ps1](scripts/TOD-Engineer.ps1)
- [scripts/engines/ExecutionEngine.ps1](scripts/engines/ExecutionEngine.ps1)
- [scripts/engines/CodexExecutionEngine.ps1](scripts/engines/CodexExecutionEngine.ps1)
- [scripts/engines/LocalExecutionEngine.ps1](scripts/engines/LocalExecutionEngine.ps1)

State and templates:
- [tod/data/state.json](tod/data/state.json)
- [tod/config/tod-config.json](tod/config/tod-config.json)
- [tod/config/sync-policy.json](tod/config/sync-policy.json)
- [tod/templates/codex-task-prompt.md](tod/templates/codex-task-prompt.md)
- [tod/data/engineering-memory.json](tod/data/engineering-memory.json)
- [tod/data/repo-index.json](tod/data/repo-index.json)
- [tod/data/sample-manifest.json](tod/data/sample-manifest.json)
- [tod/out/prompts-v2](tod/out/prompts-v2)

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
	"fallback_to_local": true,
	"execution_engine": {
		"active": "codex",
		"fallback": "local",
		"allow_fallback": true
	}
}
```

- local: TOD uses local state files only.
- remote: TOD uses MIM API only.
- hybrid: TOD writes to MIM and caches local state.

Execution engine config behavior:
- `execution_engine.active`: currently `codex` or `local`
- `execution_engine.fallback`: fallback engine when enabled
- `execution_engine.allow_fallback`: allow fallback usage
- `engineering_loop.max_run_history`: max persisted `engineer-run` history entries (10-1000)
- `engineering_loop.max_scorecard_history`: max persisted `engineer-scorecard` trend entries (10-1000)
- `engineering_loop.guardrails.require_confirmation_for_apply`: require explicit `-DangerousApproved $true` for `sandbox-apply-plan`
- `engineering_loop.guardrails.require_confirmation_for_write`: optional confirmation gate for `sandbox-write`
- `engineering_loop.autonomy.max_cycles_per_run`: upper bound for `engineer-cycle`
- `engineering_loop.autonomy.stop_at_score`: stop threshold for cycle automation
- Invalid engine values fail fast with a validation error.

Connectivity check:

```powershell
.\scripts\TOD.ps1 -Action ping-mim
```

### Simple Visual UI (Local)

Run a lightweight local UI to inspect TOD output and trigger basic actions:

```powershell
.\scripts\Start-TOD-UI.ps1
```

Open TOD console in a chromeless app window (no browser controls):

```powershell
.\scripts\Start-TOD-UI.ps1 -OpenAppWindow
```

Native fullscreen app window launcher (works even when Edge/Chrome app mode is unavailable):

```powershell
.\scripts\Start-TOD-UI-AppWindow.ps1
```

Hardcoded PowerShell trigger:

```powershell
goTOD
```

Kiosk trigger (no border/menu bar, Esc to exit):

```powershell
goTOD -Kiosk
```

Kiosk mode (no border/menu bar, Esc to exit):

```powershell
.\scripts\Start-TOD-UI-AppWindow.ps1 -HideMenuBar
```

Safer launcher with automatic free-port selection:

```powershell
.\scripts\Start-TOD-UI-Safe.ps1
```

Safe launcher + app window mode:

```powershell
.\scripts\Start-TOD-UI-Safe.ps1 -OpenAppWindow
```

Then open:

```text
http://localhost:8844/
```

Notes:
- The UI is intentionally minimal for now.
- It exposes a local API endpoint at `POST /api/run` that proxies to `scripts/TOD.ps1`.
- It includes a current project marker and a visual progress ring based on objective/task state.
- It exposes `GET /api/project-status` for the marker and progress payload.
- The action list includes `get-state-bus` for a unified snapshot of objective, agent, execution, reliability, and block/uncertainty state.
- Use `Ctrl+C` in the terminal running `Start-TOD-UI.ps1` to stop the server.

One-command smoke validation for the local UI stack:

```powershell
.\scripts\Invoke-TODSmoke.ps1
```

Fail-fast mode for CI or shell pipelines:

```powershell
.\scripts\Invoke-TODSmoke.ps1 -FailOnError
```

Watch mode (prints only first run, failures, and deltas by default):

```powershell
.\scripts\Invoke-TODSmokeWatch.ps1 -IntervalSeconds 180
```

Voice adapter scaffold (dry-run only, no mic/camera capture):

```powershell
.\scripts\Invoke-TODVoiceAdapter.ps1 -Action status
.\scripts\Invoke-TODVoiceAdapter.ps1 -Action describe-contract
.\scripts\Invoke-TODVoiceAdapter.ps1 -Action simulate-intent -Transcript "tod refresh reliability" -Intent "command.request"
```

Local-first conversational model ramp via `llama.cpp`:

```powershell
.\scripts\Setup-TODLlamaCpp.ps1
.\scripts\Get-TODLocalChatModel.ps1
.\scripts\Start-TODLlamaCppServer.ps1
.\scripts\Invoke-TODConversationProvider.ps1 -Action status
```

Notes:
- `Setup-TODLlamaCpp.ps1` downloads a prebuilt Windows `llama.cpp` release into `tools/llama.cpp`.
- `Get-TODLocalChatModel.ps1` downloads a practical starter model: `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- The default local model path is `models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- TOD voice conversation is already configured for `local_first` and will use `http://localhost:8008/v1/chat/completions` when the local server is up.

Run a short local watch sample:

```powershell
.\scripts\Invoke-TODSmokeWatch.ps1 -IntervalSeconds 15 -MaxIterations 4
```

Execution pipeline self-test (package + run-task + persistence checks):

```powershell
.\scripts\Invoke-TODExecutionSelfTest.ps1 -TaskId 45
```

Fail-fast mode for automation:

```powershell
.\scripts\Invoke-TODExecutionSelfTest.ps1 -TaskId 45 -FailOnError
```

### Conversation Evaluation Harness (TOD)

Current operating standard (promoted 2026-03-18):
- default policy profile: `tightened`
- PR gate runs: `tightened`
- nightly/regression runs: `tightened`
- known-good baseline overall score: `0.7483` *(promoted from 0.7446)*

Promotion criteria met (2026-03-18, run `20260318T001825Z`):
- Gate 1: no late degradation — late_avg_pr=0.7512 ≥ early_avg_pr=0.7471 ✓
- Gate 2: drift-lock clean — 0 violations in last 4 cycles ✓
- Gate 3: no fresh failure cluster — late_fail=10.25 < early_fail=13.75, max_streak=2 ✓

Governed expansion status (2026-03-18):
- drift-lock suite expanded to 18 locked scenarios: replay-lock core + `MESS-001..004` + `BRG-001..004` + `OPR-001..004`
- developer utility is now a first-class drift-lock invariant
- PR, nightly, and drift-lock soak runs emit markdown summaries alongside JSON artifacts
- multi-domain governed baseline frozen after full mixed soak with late drift-lock violations = 0
- family density metrics are now emitted per window (`early`/`mid`/`late`) by scenario family

Canonical baseline artifact:
- `shared_state/conversation_eval/conversation_score_report.baseline.current.json`

Run staged synthetic conversation evaluation for TOD orchestration behavior:

```powershell
.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage smoke -EmitJson
.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage expanded -EmitJson
```

PR-oriented gate (smoke + expanded):

```powershell
.\scripts\Invoke-TODConversationEvalPR.ps1 -EmitJson
.\scripts\Invoke-TODConversationEvalPR.ps1 -FailOnThreshold -MinOverallScore 0.68
```

PR and nightly reports also emit markdown summaries:
- `shared_state/conversation_eval/conversation_score_report.pr.latest.md`
- `shared_state/conversation_eval/conversation_score_report.nightly.latest.md`

Nightly regression (1000 runs) and optional baseline refresh:

```powershell
.\scripts\Invoke-TODConversationEvalNightly.ps1 -EmitJson
.\scripts\Invoke-TODConversationEvalNightly.ps1 -UpdateBaseline -EmitJson
```

Focused A/B comparison for top failure tags:

```powershell
.\scripts\Invoke-TODConversationEvalAB.ps1 -Stage expanded -EmitJson
```

One-command coaching loop (A/B drills + PR gate + optional nightly + optional live provider drills):

```powershell
.\scripts\Invoke-TODConversationCoach.ps1 -Stage expanded -EmitJson
.\scripts\Invoke-TODConversationCoach.ps1 -Stage expanded -RunNightlyRegression -UpdateBaseline -EmitJson
```

One-hour soak runner (snapshots every cycle) and trend analysis:

```powershell
.\scripts\Invoke-TODConversationCoachSoak.ps1 -DurationMinutes 60 -IntervalSeconds 300 -Stage expanded -EmitJson
.\scripts\Get-TODConversationCoachTrend.ps1 -RunId latest -EmitJson
```

Optional regression guard (fail if regressions persist across consecutive cycles):

```powershell
.\scripts\Invoke-TODConversationCoachSoak.ps1 -DurationMinutes 60 -IntervalSeconds 300 -Stage expanded -FailOnRegressingCycles 3 -PrDropTolerance 0.002 -EmitJson
```

Drift lock suite (non-negotiable replay invariants):
- `tod/conversation_eval/drift_lock_suite.json`
- includes replay-lock, messy real-world, and MIM <-> TOD bridge invariants

Early-vs-late drift analysis and replay-pack generation:

```powershell
.\scripts\Get-TODConversationDriftAnalysis.ps1 -RunId latest -WindowCycles 3 -EmitJson
.\scripts\New-TODConversationReplayPack.ps1 -RunId latest -TopScenarios 25 -FocusTags low_relevance,missing_safety_boundary -EmitJson
```

Targeted replay-pack soak (100-200 cycles, drift-lock scenarios only):

```powershell
# Full 18-scenario drift-lock soak (hard-gate profile)
.\scripts\Invoke-TODDriftLockSoak.ps1 -Cycles 120 -FailOnRegressingCycles 5 -PrDropTolerance 0.002 -UtilityDropTolerance 0.002 -MaxLateDriftLockViolations 0 -EmitJson

# Narrowed soak: only the still-failing subset (SAF-002, CON-002, SAF-003, TASK-005)
.\scripts\Invoke-TODDriftLockSoak.ps1 -Cycles 175 -IncludeScenarioIds SAF-002,CON-002,SAF-003,TASK-005 -FailOnRegressingCycles 0 -PrDropTolerance 0.002 -EmitJson

# Exact governed messy + bridge soak with bounded late violations
.\scripts\Invoke-TODDriftLockSoak.ps1 -Cycles 120 -IncludeScenarioIds MESS-001,MESS-002,MESS-003,MESS-004,BRG-001,BRG-002,BRG-003,BRG-004 -FailOnRegressingCycles 0 -PrDropTolerance 0.002 -UtilityDropTolerance 0.002 -MaxLateDriftLockViolations 3 -EmitJson

# Full mixed governed soak: replay-lock + messy + bridge + operator friction (hard gates)
.\scripts\Invoke-TODDriftLockSoak.ps1 -Cycles 120 -IncludeScenarioIds REL-005,CON-002,SAF-002,MEM-003,TASK-005,SAF-003,MESS-001,MESS-002,MESS-003,MESS-004,BRG-001,BRG-002,BRG-003,BRG-004,OPR-001,OPR-002,OPR-003,OPR-004 -FailOnRegressingCycles 5 -PrDropTolerance 0.002 -UtilityDropTolerance 0.002 -MaxLateDriftLockViolations 0 -EmitJson -OutputPath .\shared_state\conversation_eval\drift_lock_soak\full_domain_mixed_soak_report.json
```

Drift-lock soak reports also emit a markdown summary:
- `shared_state/conversation_eval/drift_lock_soak/drift_lock_soak.latest.md`

### Baseline Promotion Gate

Do **not** promote baseline until the guarded replay or mixed soak passes these promotion checks:

| Gate | Required |
|------|----------|
| `final_failures` on governed soak | ≤ 1 |
| Late utility floor | `late_avg_developer_utility >= 0.73` |
| Utility slope | `late_avg_developer_utility >= early_avg_developer_utility` |
| Late consistency | `late_avg_consistency >= early_avg_consistency` |
| Late failure pressure | `late_avg_failures <= early_avg_failures` |
| Late drift-lock pressure | `late_drift_lock_violations <= MaxLateDriftLockViolations` |

When all gates pass, run a guarded 60-minute full soak then promote:

```powershell
.\scripts\Invoke-TODConversationCoachSoak.ps1 -DurationMinutes 60 -IntervalSeconds 300 -Stage expanded -FailOnRegressingCycles 3 -PrDropTolerance 0.002 -UpdateBaselineAtEnd -EmitJson
```

**Current status (2026-03-18):**
- Narrowed 175-cycle replay-pack soak: `final_failures=0`, `late_fail=0`, `late_avg_cons=0.833` ✓
- PR gate: `drift_lock_passed=true`, `drift_lock_failures=0`, `gate_passed=true` ✓
- Full guarded 60-min soak (run `20260318T001825Z`): 12 cycles, `avg_pr=0.750`, `regressed=false` ✓
- Governed exact messy + bridge soak (`mixed_mess_bridge_120_governed_bounded_report.json`, bounded late violations): `avg_overall=0.7816`, `avg_developer_utility=0.7908`, `late_drift_lock_violations=3`, `promotion_gate_passed=true` ✓
- Full mixed governed soak (run `20260318T065414Z`, 18 scenarios): `cycles_completed=120`, `avg_overall=0.7770`, `avg_developer_utility=0.7833`, `final_failures=0`, `late_drift_lock_violations=0`, `promotion_gate_passed=true` ✓
- OPR closure soak (run `20260318T064913Z`): `cycles_completed=60`, `avg_overall=0.7695`, `avg_developer_utility=0.7669`, `late_drift_lock_violations=0`, `promotion_gate_passed=true` ✓
- **Baseline promoted to 0.7483** (from 0.7446, +0.004 lift)
- **Multi-domain governed baseline frozen (`baseline_release_v2.json`)**

Governance freeze artifact:
- `tod/conversation_eval/baseline_release_v1.json`
- `tod/conversation_eval/baseline_release_v2.json`

Seed data files:
- `tod/conversation_eval/scenario_cards.json` — 74 scenarios across 18 buckets (48 conversational + 10 engineering + 8 messy/bridge + 4 operator-friction + 4 real-repo-review)
- `tod/conversation_eval/conversation_profiles.json`
- `tod/conversation_eval/drift_lock_suite.json` — 18 locked invariant scenarios
- `tod/conversation_eval/codex_readiness_suite_v1.json` — single-domain expansion suite for real repo change review

Engineering task scenario buckets (added 2026-03-18):

| Bucket | IDs | Focus |
|--------|-----|-------|
| `implementation_planning` | ENG-001–004 | Concrete structure, circuit breakers, queue/pipe tradeoffs, auto-merge governance |
| `code_review_coaching` | ENG-005–007 | Antipattern detection, priority-ranked review, pattern reuse |
| `debugging_loop` | ENG-008–010 | Targeted diagnosis, NullRef root cause, diff-first isolation |

Messy real-world and cross-domain bridge scenarios:

| Bucket | IDs | Focus |
|--------|-----|-------|
| `debugging_loop` + `implementation_planning` + `code_review_coaching` + `unclear_requests` | MESS-001–004 | Incomplete logs, conflicting requirements, partial code, ambiguous intent |
| `mim_tod_bridge` | BRG-001–004 | MIM plans -> TOD critiques -> TOD executes -> MIM validates |
| `operator_friction` | OPR-001–004 | Incomplete bug reports, urgency pressure, rollback conflict, wrong diagnosis confidence |
| `real_repo_change_review` | RRV-001–004 | Security review, partial diffs, conflicting constraints, incident triage under repo pressure |

Run engineering task coaching drills:

```powershell
# Single-pass smoke across all 10 engineering scenarios
.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage smoke -PolicyProfile tightened -IncludeScenarioIds ENG-001,ENG-002,ENG-003,ENG-004,ENG-005,ENG-006,ENG-007,ENG-008,ENG-009,ENG-010 -ScenarioSweep -RunCountOverride 10 -EmitJson

# Targeted 50-cycle soak on all engineering scenarios
.\scripts\Invoke-TODDriftLockSoak.ps1 -Cycles 50 -IncludeScenarioIds ENG-001,ENG-002,ENG-003,ENG-004,ENG-005,ENG-006,ENG-007,ENG-008,ENG-009,ENG-010 -FailOnRegressingCycles 3 -EmitJson

# Messy real-world pressure sweep
.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage expanded -PolicyProfile tightened -IncludeScenarioIds MESS-001,MESS-002,MESS-003,MESS-004 -ScenarioSweep -RunCountOverride 40 -EmitJson

# Cross-domain MIM <-> TOD interaction cycle
.\scripts\Invoke-TODMimTodBridgeCycle.ps1 -Cycles 20 -EmitJson

# Operator-friction pressure sweep
.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage expanded -PolicyProfile tightened -IncludeScenarioIds OPR-001,OPR-002,OPR-003,OPR-004 -ScenarioSweep -RunCountOverride 40 -EmitJson

# Light real-world usage on actual code (review/debug/fixes)
.\scripts\Invoke-TODRealCodeAssist.ps1 -Mode review -FilePaths scripts\Invoke-TODConversationEvalRunner.ps1,scripts\Invoke-TODConversationEvalPR.ps1 -EmitJson

# Real workflow usage: debugging triage
.\scripts\Invoke-TODRealCodeAssist.ps1 -Mode debug -FilePaths scripts\Invoke-TODDriftLockSoak.ps1,scripts\Invoke-TODConversationEvalRunner.ps1 -EmitJson

# Real workflow usage: implementation planning
.\scripts\Invoke-TODRealCodeAssist.ps1 -Mode plan -FilePaths scripts\Invoke-TODMimTodBridgeCycle.ps1,scripts\Invoke-TODRealCodeAssist.ps1 -EmitJson

# Real workflow usage: operator-facing engineering support
.\scripts\Invoke-TODRealCodeAssist.ps1 -Mode operator -FilePaths scripts\Invoke-TODDriftLockSoak.ps1,scripts\Invoke-TODConversationEvalPR.ps1 -EmitJson

# Single-domain candidate sweep: real repo change review
.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage expanded -PolicyProfile tightened -IncludeScenarioIds RRV-001,RRV-002,RRV-003,RRV-004 -ScenarioSweep -RunCountOverride 40 -EmitJson

# Codex-readiness end-to-end KPI run with hard patch gates
.\scripts\Invoke-TODCodexReadinessRun.ps1 -Mode review -FilePaths scripts\Invoke-TODConversationEvalRunner.ps1,scripts\Invoke-TODDriftLockSoak.ps1 -RequireCleanWorktree -TestCommand ".\scripts\Invoke-TODConversationEvalPR.ps1 -EmitJson" -EmitJson

# Operator-support readiness run (no threshold relaxation)
.\scripts\Invoke-TODCodexReadinessRun.ps1 -Mode operator -FilePaths scripts\Invoke-TODConversationEvalPR.ps1,scripts\Invoke-TODMimTodBridgeCycle.ps1 -RequireCleanWorktree -EmitJson

# Daily codex-readiness run profile (hard gates, practical defaults)
.\scripts\Invoke-TODCodexReadinessDaily.ps1 -Mode review -EmitJson

# Register daily schedule at 09:00 and trigger immediately
.\scripts\Register-TODCodexReadinessDailyTask.ps1 -DailyAt 09:00 -Mode review -RunNow

# Remove daily schedule if needed
.\scripts\Unregister-TODCodexReadinessDailyTask.ps1
```

Single-domain expansion rule (next step):
- add **one** new domain at a time under unchanged hard gates (`MaxLateDriftLockViolations=0`, no threshold relaxation)
- active next family: real repo change review (`RRV-001..004`)
- keep all promotion gates hard; tighten only after stable late-window density

Cross-project GitHub simulation training (real repos, simulation only):

```powershell
# Run cross-project simulation over registered repos using real discovery surfaces
.\scripts\Invoke-TODGitHubProjectSimulation.ps1 -UseAssist -EmitJson

# Daily wrapper with the standard output location
.\scripts\Invoke-TODGitHubProjectSimulationDaily.ps1 -UseAssist -EmitJson

# Register daily schedule at 09:15 and trigger immediately
.\scripts\Register-TODGitHubProjectSimulationDailyTask.ps1 -UseAssist -RunNow

# Remove the daily simulation schedule
.\scripts\Unregister-TODGitHubProjectSimulationDailyTask.ps1

# Same simulation without provider-assisted planning (heuristic discovery only)
.\scripts\Invoke-TODGitHubProjectSimulation.ps1 -EmitJson

# Build a rolling trend report from recent simulation runs
.\scripts\Get-TODGitHubProjectSimulationTrend.ps1 -EmitJson

# Prepare a single project task packet without making edits
.\scripts\Invoke-TODGitHubProjectTask.ps1 -ProjectId tod -Task "review drift-lock scorer" -Mode review -TargetHints runner,drift,score

# Refresh TOD.md project status files across the registered library
.\scripts\Update-TODProjectStatusFiles.ps1 -EmitJson
```

Simulation suite and output:
- `tod/conversation_eval/github_project_simulation_suite_v1.json`
- `shared_state/conversation_eval/github_project_simulation/tod_github_project_simulation.latest.json`
- `shared_state/conversation_eval/github_project_simulation/tod_github_project_simulation.trend.latest.json`

Default operating assumption:
- TOD should treat GitHub-enabled cross-project work as the default mode where credentials and repo permissions allow.
- Simulation mode prepares discovery, solution, commit, and push checklists without making live edits.
- Each registered project now carries a local `TOD.md` status file as the default familiarization and handoff surface for future TOD work.

Reports:
- `shared_state/conversation_eval/conversation_score_report.latest.json`
- `shared_state/conversation_eval/conversation_score_report.pr.latest.json`
- `shared_state/conversation_eval/conversation_score_report.nightly.latest.json`
- `shared_state/conversation_eval/conversation_score_report.pr.latest.md`
- `shared_state/conversation_eval/conversation_score_report.nightly.latest.md`
- `shared_state/conversation_eval/drift_lock_soak/drift_lock_soak.latest.json`
- `shared_state/conversation_eval/drift_lock_soak/drift_lock_soak.latest.md`
- `shared_state/conversation_eval/real_usage/tod_real_code_assist.latest.json`
- `shared_state/conversation_eval/codex_readiness/tod_codex_readiness.latest.json`

### Continuous Training Automation

Generate a structured training report from existing TOD evidence (tests, smoke, state-bus, reliability, engineering loop):

```powershell
.\scripts\Invoke-TODTrainingLoop.ps1
```

Include cross-project discovery/indexing from `E:\` (or another root) as part of training:

```powershell
.\scripts\Invoke-TODTrainingLoop.ps1 -LibraryRoot "E:\\"
```

Refresh project library index only (read-only discovery, no code edits):

```powershell
.\scripts\Update-TODProjectLibrary.ps1 -RootPath "E:\\"
```

Validate whether planned file edits are inside per-project boundaries:

```powershell
.\scripts\Test-TODProjectAccessPolicy.ps1 -ProjectId "comm_app" -RelativePaths "src/core/service.py"
```

Build TOD's prioritized cross-project execution queue:

```powershell
.\scripts\Get-TODProjectExecutionQueue.ps1
```

Run queue execution routing by mode (plan-only for advisory/review modes, optional guarded writes):

```powershell
.\scripts\Invoke-TODProjectQueueRunner.ps1 -Top 10 -DryRun
.\scripts\Invoke-TODProjectQueueRunner.ps1 -Top 5 -ExecuteGuardedWrites
```

By default, the runner auto-selects a policy-compliant relative path per project from registry `allowed_paths`. Override with `-RelativePath` when needed.

Project-scoped sandbox writes are now policy-gated and required to use:

- `projects/<project_id>/<relative_path>`

Example allowed write:

```powershell
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "projects/comm_app/src/core/service.py" -Content "# draft"
```

Example blocked write:

```powershell
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "projects/comm_app/secrets/token.txt" -Content "blocked"
```

Always-on daemon mode (daily full training + idle-time lightweight training):

```powershell
.\scripts\Start-TODTrainingDaemon.ps1
```

Useful daemon options:

```powershell
.\scripts\Start-TODTrainingDaemon.ps1 -IntervalSeconds 300 -IdleCadenceMinutes 30 -FullCadenceHours 24
.\scripts\Start-TODTrainingDaemon.ps1 -RunOnce
```

Daemon artifacts:
- `tod/out/training/training-daemon.log`
- `tod/out/training/training-daemon-state.json`
- `tod/out/training/training-report.json`
- `tod/out/training/training-report.md`

Project library artifacts:
- `tod/config/project-registry.json`
- `tod/config/project-priority.json`
- `tod/config/media-pipeline-profiles.json`
- `tod/config/media-runtime.json`
- `tod/data/project-library-index.json`

Media pipeline orchestration (RTX/local-service controller):

```powershell
.\scripts\Invoke-TODMediaPipeline.ps1 -ProjectId "mim_images" -Capability "image-generation" -Prompt "cyber-green TOD status banner" -DryRun
.\scripts\Invoke-TODMediaPipeline.ps1 -ProjectId "tod" -Capability "diagram-dashboard-rendering" -Prompt "engineering loop state flow" -Execute
```

### Spokesperson / RunPod Workflow

Local spokesperson setup and validation:

```powershell
.\scripts\Setup-TODSpokesperson.ps1
.\scripts\Test-TODSpokesperson.ps1
.\scripts\Invoke-TODSpokesperson.ps1
```

RunPod offload and helper flows:

```powershell
.\scripts\Set-TODRunPodEndpoint.ps1 -RunPodHost "1.2.3.4" -RunPodPort 22 -RunPodUser "root"
.\scripts\Invoke-TODSpokesperson-RunPod.ps1 -Preset "tod/config/media-presets/gloria-cowell.json"
.\scripts\goTODRunPodGloria.ps1
.\scripts\New-TODRunPodJobPack.ps1 -Preset "tod/config/media-presets/gloria-cowell.json"
.\scripts\New-TODRunPodBootstrapPack.ps1
.\scripts\Start-TOD-RunPodStudio.ps1
```

Notes:
- Avatar images are local inputs and are not expected to be committed.
- Preferred local slot: `tod/data/avatars/user-avatar.jpg`.
- If a preset avatar path is missing, the spokesperson scripts fall back to the most recent image under `tod/data/avatars/`.
- RunPod Studio can upload a portrait into `tod/data/avatars/uploads/` and then use that path for renders.

MIM context exchange (shared coordination snapshot + inbound updates):

```powershell
.\scripts\Invoke-TODContextExchange.ps1 -Action export
.\scripts\Invoke-TODContextExchange.ps1 -Action status
.\scripts\Invoke-TODContextExchange.ps1 -Action ingest
```

Context exchange artifacts:
- `tod/config/context-exchange.json`
- `tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.yaml`
- `tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json`
- `tod/inbox/context-sync/updates/*.json`
- `tod/out/context-sync/context-updates-log.jsonl`

Shared state sync layer (canonical machine-readable collaboration state):

```powershell
.\scripts\Invoke-TODSharedStateSync.ps1
```

One-command full share bundle refresh (training + context ingest/export + shared state):

```powershell
.\scripts\Invoke-TODShareBundleRefresh.ps1
```

Formal pass to MIM with terminal activity output + share file paths:

```powershell
.\scripts\Invoke-TODFormalPassToMim.ps1 -Top 10 -SkipProjectDiscovery
```

Fast visible pass (skip long tests/smoke while validating comms and artifacts):

```powershell
.\scripts\Invoke-TODFormalPassToMim.ps1 -Top 10 -SkipProjectDiscovery -SkipTests -SkipSmoke
```

Open the export folder automatically after pass:

```powershell
.\scripts\Invoke-TODFormalPassToMim.ps1 -Top 10 -SkipProjectDiscovery -OpenOutputFolder
```

Example (faster run for iterative updates):

```powershell
.\scripts\Invoke-TODShareBundleRefresh.ps1 -Top 10 -SkipProjectDiscovery
```

Canonical shared state files:
- `shared_state/current_build_state.json`
- `shared_state/objectives.json`
- `shared_state/contracts.json`
- `shared_state/next_actions.json`
- `shared_state/shared_development_log_plan.json`
- `shared_state/dev_journal.jsonl`
- `shared_state/latest_summary.md`
- `shared_state/chatgpt_update.md`
- `shared_state/chatgpt_update.json`

Formal pass receipt artifacts:
- `tod/out/context-sync/exports/TOD_FORMAL_PASS_RECEIPT.latest.json`
- `tod/out/context-sync/exports/TOD_FORMAL_PASS_RECEIPT-*.json`

### MIM Debug Logging

TOD can write per-request debug logs for all MIM HTTP calls.

Config in `tod/config/tod-config.json`:

```json
"mim_debug": {
	"enabled": true,
	"log_path": "e:/TOD/tod/out/mim-http.log"
}
```

When enabled, each line in the log file is JSON containing:
- `timestamp_utc`
- `request.method`, `request.uri`, `request.body`
- `response.status_code`, `response.body`
- `response.error`, `response.error_body` (for failures)
- `elapsed_ms`

Quick tail command:

```powershell
Get-Content .\tod\out\mim-http.log -Tail 20
```

### Execution Feedback Publisher (Objective 22 Task B)

TOD can publish execution lifecycle feedback to MIM:

`POST /gateway/capabilities/executions/{execution_id}/feedback`

Enable in `tod/config/tod-config.json`:

```json
"execution_feedback": {
	"enabled": true,
	"source": "tod",
	"auth_token": ""
}
```

Current `run-task` feedback events (when an execution id is available):
- `accepted`
- `running`
- terminal state: `succeeded` or `failed`
- `blocked` when guardrail prevents execution pre-invocation

Execution id resolution order:
1. Explicit `-ExecutionId` parameter on `run-task`
2. Task field `execution_id`
3. Task field `remote_execution_id`

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
- get-manifest -> GET /manifest

Pre-manifest sync readiness check (offline or live):

```powershell
.\scripts\TOD.ps1 -Action compare-manifest -ManifestPath .\tod\data\sample-manifest.json
```

Full sync decision run:

```powershell
.\scripts\TOD.ps1 -Action sync-mim -ConfigPath .\tod\config\tod-config.json
```

Task 24 verification (after MIM enables POST /journal):

```powershell
. .\client\mim_api_client.ps1
$cfg = Get-Content .\tod\config\tod-config.json -Raw | ConvertFrom-Json
$entry = Get-Content .\tod\data\sample-journal-post.json -Raw | ConvertFrom-Json
New-MimJournalEntry -BaseUrl $cfg.mim_base_url -Entry $entry -TimeoutSeconds 15 | ConvertTo-Json -Depth 8
```

Operational sync behavior:
- repo signature drift marks repo index stale and triggers re-index when recommended
- contract drift (breaking) blocks risky actions unless explicitly overridden with `-AllowContractDrift`
- missing capabilities degrade remote calls to local behavior when possible (hybrid fallback)
- sync outcomes are logged to local TOD state and engineering memory, with optional MIM journal write

Machine-readable sync output fields:
- `decision_code`: `SYNC_DECISION_OK|SYNC_DECISION_WARN|SYNC_DECISION_ESCALATE`
- `escalation_code`: e.g. `SYNC_OK`, `SYNC_REINDEX_REQUIRED`, `SYNC_CAPABILITY_WARN`, `SYNC_SCHEMA_WARN`, `SYNC_CONTRACT_INCOMPATIBLE`
- `reconciliation_plan`: ordered plan steps (`step_id`, `action`, `reason`, `blocking`, `auto_executable`, `recommended_command`)

Execution result metadata behavior:
- `add-result` now includes `engine_metadata` in local and hybrid response payloads.
- TOD local journal payloads for execution results include `engine_metadata`.

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

## TOD Command Reference

Use this as a quick day-to-day command map.

### TOD Runtime (Core)

```powershell
.\scripts\TOD.ps1 -Action init
.\scripts\TOD.ps1 -Action ping-mim
.\scripts\TOD.ps1 -Action compare-manifest
.\scripts\TOD.ps1 -Action sync-mim
```

### Objective and Task Flow

```powershell
.\scripts\TOD.ps1 -Action new-objective -Title "..." -Description "..."
.\scripts\TOD.ps1 -Action list-objectives
.\scripts\TOD.ps1 -Action add-task -ObjectiveId <ID> -Title "..." -Scope "..."
.\scripts\TOD.ps1 -Action list-tasks -ObjectiveId <ID>
.\scripts\TOD.ps1 -Action package-task -TaskId <ID>
.\scripts\TOD.ps1 -Action run-task -TaskId <ID>
.\scripts\TOD.ps1 -Action run-task-report -TaskId <ID>
```

### Results and Review

```powershell
.\scripts\TOD.ps1 -Action add-result -TaskId <ID> -Summary "..."
.\scripts\TOD.ps1 -Action review-task -TaskId <ID> -Decision pass -Rationale "..."
.\scripts\TOD.ps1 -Action show-journal -Top 25
```

### Reliability and Routing Views

```powershell
.\scripts\TOD.ps1 -Action get-reliability
.\scripts\TOD.ps1 -Action show-reliability-dashboard -Top 25
.\scripts\TOD.ps1 -Action show-engine-performance
.\scripts\TOD.ps1 -Action show-routing-decisions
.\scripts\TOD.ps1 -Action show-routing-feedback
.\scripts\TOD.ps1 -Action show-failure-taxonomy
.\scripts\TOD.ps1 -Action get-capabilities
.\scripts\TOD.ps1 -Action get-research -Top 10
.\scripts\TOD.ps1 -Action get-resourcing -ObjectiveId <ID> -Top 10
.\scripts\TOD.ps1 -Action engineer-run -Top 10
.\scripts\TOD.ps1 -Action engineer-run -TaskId <ID> -ApplyPlan -DangerousApproved $true
.\scripts\TOD.ps1 -Action engineer-scorecard -Top 25
.\scripts\TOD.ps1 -Action get-engineering-loop-summary -Top 10
.\scripts\TOD.ps1 -Action get-engineering-loop-history -HistoryKind run_history -Page 1 -PageSize 25
.\scripts\TOD.ps1 -Action engineer-cycle -Cycles 3 -Top 10
.\scripts\TOD.ps1 -Action sandbox-list -Top 25
.\scripts\TOD.ps1 -Action sandbox-plan -SandboxPath "notes/demo.txt" -Content "planned content"
.\scripts\TOD.ps1 -Action sandbox-apply-plan -SandboxPlanPath "tod/sandbox/artifacts/PLAN-XXXXXXXXXX.json" -DangerousApproved $true
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "notes/demo.txt" -Content "hello sandbox"
.\scripts\TOD.ps1 -Action get-version
```

### TOD Command Console (UI)

```powershell
.\scripts\Start-TOD-UI.ps1 -Port 8844
```

Notes:
- If `8844` is busy, `Start-TOD-UI.ps1` auto-falls forward to the next available port.
- Open the printed URL in browser (for example `http://localhost:8845/`).

Optional convenience command:

```powershell
Import-Module TODTools -DisableNameChecking -Force
Start-TOD-UI -Port 8844
```

UI quick guide (build-aware):

- Header chips show the active UI build tag and active localhost port.
- `MIM probe` indicates ping reachability to MIM only.
- `TOD Active` indicates local TOD/API activity seen by the console.
- `Live | comms active/frozen` in Action Output is derived from heartbeat age versus stall threshold.
- Action timeline is newest-first.
- Pending queue under Action Output shows projected upcoming objective tasks and shrinks as completions land.
- `Quick Refresh Reliability` uses safe dashboard refresh (status/log/share reload) instead of running a heavy TOD action.
- `Refresh State Bus` is read-only snapshot loading; it does not dispatch tasks, but can be expensive under active load.
- Share artifact `open` uses inline preview; `download` keeps attachment behavior.

UI Help panel:

- Open from the header `UI Help` button.
- Close with `Esc` or the `Close` button.
- The panel documents System Posture, Engineering Loop, Scorecard Trend, telemetry timestamps, and executive summary semantics.

UI changelog (operator-facing):

- `2026.03.13-b2`
	- Added header chips showing active UI build and runtime port.
	- Added in-app UI Help overlay.
	- Added in-app UI changelog block for quick release delta visibility.
- `2026.03.13-b1`
	- Switched Action Output timeline to newest-first ordering.
	- Added pending queue under Action Output.
	- Converted Quick Refresh Reliability to safe dashboard refresh mode.
	- Added executive summary under Current Project Marker.
	- Added state-bus refresh confirmation guard.
	- Fixed Share Artifact `open` link behavior with inline preview endpoint.

### Debug Logs

```powershell
Get-Content .\tod\out\mim-http.log -Tail 20
```

This log captures MIM request/response telemetry when `mim_debug.enabled` is true in `tod/config/tod-config.json`.

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

### TOD Engineering Orchestrator (vNext)

Initialize engineering memory and repo index:

```powershell
.\scripts\TOD-Engineer.ps1 -Action init-engineering-memory
.\scripts\TOD-Engineer.ps1 -Action index-repo
.\scripts\TOD-Engineer.ps1 -Action show-repo-index
```

Bootstrap the repository-aware upgrade objective/tasks:

```powershell
.\scripts\TOD-Engineer.ps1 -Action bootstrap-upgrade-objective
```

Package V2 for Codex with richer context:

```powershell
.\scripts\TOD-Engineer.ps1 -Action package-task-v2 -TaskId 10 -ConfigPath e:\TOD\tod\config\tod-config.json
```

Review Codex result payload with rule engine V2:

```powershell
.\scripts\TOD-Engineer.ps1 -Action review-result-v2 `
	-TaskId 10 `
	-ResultJsonPath e:\TOD\tod\data\sample-codex-result.json `
	-AllowedFiles "scripts/TOD-Engineer.ps1,tod/data/engineering-memory.json" `
	-ConfigPath e:\TOD\tod\config\tod-config.json
```

Run full TOD -> Codex-result -> MIM loop:

```powershell
.\scripts\TOD-Engineer.ps1 -Action execute-task-loop `
	-TaskId 10 `
	-ResultJsonPath e:\TOD\tod\data\sample-codex-result.json `
	-AllowedFiles "scripts/TOD-Engineer.ps1,tod/data/engineering-memory.json" `
	-ConfigPath e:\TOD\tod\config\tod-config.json
```

## TOD Testing

Run all TOD tests locally:

```powershell
.\scripts\Invoke-TODTests.ps1
```

Run all TOD tests and emit machine-readable summary JSON:

```powershell
.\scripts\Invoke-TODTests.ps1 -JsonOutputPath .\tod\out\results-v2\tod-tests-summary.json
```

CI-friendly wrapper (fails on any test failure and prints only summary-path marker):

```powershell
.\scripts\Invoke-TODTests.CI.ps1
```

Branch protection guidance for CI enforcement:

- [docs/github-branch-protection.md](docs/github-branch-protection.md)

Apply branch protection from Windows with one command:

```powershell
.\scripts\apply_branch_protection.ps1 -Repository raine0001/mim -Branch main
```

Optional override for required check context:

```powershell
.\scripts\apply_branch_protection.ps1 -Repository raine0001/mim -Branch main -RequiredCheck "TOD Tests / test"
```

Linux/macOS equivalent:

```bash
bash ./scripts/apply_branch_protection.sh raine0001/mim main
```

Reliability drift penalty decay:

- Configure `execution_engine.routing_policy.drift_detection.decay_half_life_days` to control how quickly penalties taper as signals age.
- Configure `execution_engine.routing_policy.drift_detection.decay_floor` to keep a small residual penalty floor instead of dropping to zero instantly.

MIM-facing TOD runtime metadata endpoints (action output contracts):

```powershell
.\scripts\TOD.ps1 -Action get-reliability
.\scripts\TOD.ps1 -Action get-capabilities
.\scripts\TOD.ps1 -Action get-version
```

These provide:

- current alert state and drift penalty activity
- engine reliability scores and recovery state
- execution/reliability capability metadata
- TOD runtime/policy version metadata
