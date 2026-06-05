# TOD Trust And Recovery Chain - 2026-06-04

Status: completed_with_new_followups

Goal: keep TOD moving toward autonomous project execution by hardening trust mechanics, then proving a three-task chain with one intentional blocker.

## Trust Repairs Completed

- Task ID collision prevention:
  - Added `New-StateUniqueId`.
  - Added a named state mutation mutex.
  - `add-task` now reloads state and allocates the final local task id inside the mutation lock.
  - Regression: `TOD.Tests.ps1` includes concurrent local writers and verifies two persisted tasks receive two unique ids.

- Validation marker specificity:
  - Append/insert/replace/json/validation-only local checks now use a validation command that throws when the pattern is absent.
  - `Validation Pattern` is authoritative when supplied.
  - Regression: append-section with a missing explicit marker rolls back and fails instead of passing on the heading.

- Recoverable blocker continuation:
  - `failed_recoverable` tasks now select a ready same-objective recovery task before unrelated backlog work.
  - Regression: `TOD.SelfDrivingTaskSelection.Tests.ps1` verifies same-objective recovery beats higher-priority unrelated backlog.

## Three-Task Chain Proof

- Task A: `TSK-3128`
  - Result: completed.
  - Evidence marker: `TOD-CHAIN-A-SUCCESS-001`.
  - TOD selected B next.

- Task B: `TSK-3130`
  - Result: blocked with evidence.
  - Reason: `local_fallback_validation_failed`.
  - Expected marker `TOD-CHAIN-B-MISSING-001` was intentionally absent.
  - LocalExecutionEngine rolled back the attempted edit.

- Task C: `TSK-3127`
  - Result: completed.
  - Selection kind: `same_objective_recovery_after_blocker`.
  - Evidence marker: `TOD-CHAIN-C-SAFE-001`.

## Validation

- `tests/TOD.Tests.ps1`: 43 passed, 0 failed.
- `tests/TOD.LocalFallbackExecutor.Tests.ps1`: 15 passed, 0 failed.
- `tests/TOD.SelfDrivingTaskSelection.Tests.ps1`: 9 passed, 0 failed.

## Followups

- The latest-artifact gate still writes fresh successful local execution payloads into a blocked/superseded lane when the canonical lane differs.
- The add-task batch shell pattern used during this run lost an intermediate task; one-command-at-a-time and the new lock worked, but batch orchestration should avoid nested external process chains for state mutation.
- One-line bounded edit grammar still needs a dedicated parser-hardening pass.

