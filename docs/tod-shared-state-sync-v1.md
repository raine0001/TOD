# TOD Shared State Sync v1

Purpose: provide a canonical synchronization layer for TOD, MIM, and parallel collaborator sessions.

## Output Folder

- `shared_state/`

Generated files:

- `shared_state/current_build_state.json`
- `shared_state/objectives.json`
- `shared_state/contracts.json`
- `shared_state/next_actions.json`
- `shared_state/shared_development_log_plan.json`
- `shared_state/dev_journal.jsonl`
- `shared_state/latest_summary.md`
- `shared_state/chatgpt_update.md`
- `shared_state/chatgpt_update.json`

Related contract doc:

- `docs/tod-shared-development-log-contract-v1.md`

## Command

```powershell
.\scripts\Invoke-TODSharedStateSync.ps1
```

Optional overrides:

```powershell
.\scripts\Invoke-TODSharedStateSync.ps1 -NextProposedObjective "OBJ-0022"
.\scripts\Invoke-TODSharedStateSync.ps1 -ReleaseTagOverride "candidate-2026-03-12"
```

## Data Sources

- git metadata: branch, commit SHA, release tag
- TOD runtime endpoints: `get-capabilities`, `get-engineering-signal`, `get-reliability`
- TOD state and reports:
  - `tod/data/state.json`
  - `tod/out/training/test-summary.json`
  - `tod/out/training/smoke-summary.json`
  - `tod/out/training/quality-gate-summary.json`

## Update Cadence

Run this sync at minimum:

- after focused gate
- after full regression
- after promotion decision
- after prod verification
- after major architecture changes
- when switching objectives

## Design Constraints

- Keep snapshots machine-readable and small.
- Keep journal append-only (`dev_journal.jsonl`).
- Record decisions/outcomes/current truth, not raw scratchpad reasoning.
