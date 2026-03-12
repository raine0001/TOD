# TOD Training Automation v1

## Purpose

Automate evidence-driven training for TOD using existing repository signals, contracts, and runtime telemetry.

This is not model pretraining. It is operational training via structured drills and objective evidence.

## Script

Run:

```powershell
.\scripts\Invoke-TODTrainingLoop.ps1
```

Optional flags:

```powershell
.\scripts\Invoke-TODTrainingLoop.ps1 -Top 25 -SkipSmoke
.\scripts\Invoke-TODTrainingLoop.ps1 -SkipTests
.\scripts\Invoke-TODTrainingLoop.ps1 -OutputDir tod/out/training
.\scripts\Invoke-TODTrainingLoop.ps1 -LibraryRoot "E:\\"
.\scripts\Invoke-TODTrainingLoop.ps1 -SkipProjectDiscovery
.\scripts\Invoke-TODTrainingLoop.ps1 -FailOnError
```

Outputs:

- `tod/out/training/training-report.json`
- `tod/out/training/training-report.md`
- `tod/out/training/test-summary.json` (when tests are enabled)
- `tod/out/training/smoke-summary.json` (when smoke checks are enabled)
- `tod/data/project-library-index.json` (when project discovery is enabled)

## Project Registry and Discovery

The project registry defines each managed domain, boundaries, risk tier, and default interaction commands.

- Registry: `tod/config/project-registry.json`
- Discovery script: `scripts/Update-TODProjectLibrary.ps1`
- Index output: `tod/data/project-library-index.json`

Manual refresh command:

```powershell
.\scripts\Update-TODProjectLibrary.ps1 -RootPath "E:\\"
```

Discovery is read-only. It samples file structure, entrypoint hints, test artifacts, and extension summaries to support phase-1 understanding before advisory or implementation modes.

## Existing Resources TOD Can Consume

The training loop already ingests repository-native resources:

- Runtime state and memory:
  - `tod/data/engineering-memory.json`
  - `tod/data/repo-index.json`
  - `tod/data/module-summaries.json`
  - `tod/config/project-registry.json`
  - `tod/data/project-library-index.json`
- Contract and protocol docs:
  - `docs/tod-command-reference.md`
  - `docs/tod-state-bus-contract-v1.md`
  - `docs/tod-mim-shared-contract-v1.md`
  - `docs/mim-tod-execution-feedback-contract-v1.md`
  - `docs/codex-result-format-v1.md`
- Live operational evidence (queried through `TOD.ps1` actions):
  - `get-state-bus`
  - `get-reliability`
  - `show-reliability-dashboard`
  - `show-failure-taxonomy`
  - `get-engineering-loop-summary`
  - `get-engineering-signal`
  - `get-engineering-loop-history`
- Validation evidence:
  - `scripts/Invoke-TODTests.ps1`
  - `scripts/Invoke-TODSmoke.ps1`

## Competency Snapshot Rubric

The report emits a simple 0-5 snapshot in four dimensions:

- Governance and control
- Reliability awareness
- Workflow structure
- Runtime interaction

Use this as a gate signal, not a vanity metric.

## Suggested Operating Cadence

1. Run training loop daily or per major objective.
2. Promote autonomy only on sustained competency trends.
3. Use `next_drills` as mandatory assignment queue.
4. Archive historical reports outside Git if you need long-term trend analytics.
