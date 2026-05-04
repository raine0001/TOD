# TOD 3-Hour Training Runbook

Date: 2026-04-07
Audience: TOD operators and maintainers
Mode: live-runtime-safe first, full validation only when the host is quiet enough to allow it

This is the current operator-ready block for the host.

Primary executor:

```powershell
.\scripts\Invoke-TODTrainingRunbook3h.ps1
```

Compressed validation path for development and repo-side verification:

```powershell
.\scripts\Invoke-TODTrainingRunbook3h.ps1 -DurationHours 0.05 -NoWait
```

Reference surfaces:

- [docs/tod-training-automation-v1.md](docs/tod-training-automation-v1.md)
- [docs/tod-bounded-under-lock-hardening-checkpoint-2026-03-28.md](docs/tod-bounded-under-lock-hardening-checkpoint-2026-03-28.md)
- [docs/tod-execution-readiness-promotion-note-2026-03-27.md](docs/tod-execution-readiness-promotion-note-2026-03-27.md)
- [scripts/Invoke-TODTrainingRunbook3h.ps1](../scripts/Invoke-TODTrainingRunbook3h.ps1)
- [scripts/Invoke-TODTrainingRunbook6h.ps1](../scripts/Invoke-TODTrainingRunbook6h.ps1)

## Block Shape

The 3-hour block is intentionally shorter and simpler than the previous 6-hour cadence:

1. Baseline supervised checkpoint.
2. One bounded runtime-safe training loop.
3. Midpoint supervised checkpoint.
4. One more bounded runtime-safe training loop.
5. Final supervised checkpoint.

## Why This Is The Default Now

The current host is still sensitive to full-suite and UI health regressions. A 3-hour block gives enough time to validate supervised integrity and bounded runtime-safe posture without committing to a longer window before the baseline is proven clean again.

## Success Criteria

1. All three supervised checkpoints complete without escalation.
2. Both bounded runs show runtime-safe subset `passed_all = true`.
3. Recovery remains healthy in the readiness-recovery artifact.
4. The block ends as `stable_bounded_lane` or `ready_for_quiet_window_full_run`.

## Failure Criteria

Pause and repair before retrying if any of the following occurs:

1. Supervised checkpoint escalates.
2. The UI host fails to serve `GET /api/project-status`.
3. Receipt check or bridge smoke fails.
4. Runtime-safe subset fails twice in a row.

## Canonical Artifacts

Watch these paths during the block:

- `tod/out/training/runbook-3h-*/runbook-report.json`
- `tod/out/training/runbook-3h-*/runbook-report.md`
- `tod/out/training/readiness-recovery.latest.json`
- `tod/out/training/runtime-safe-validation-subset.latest.json`
- `shared_state/tod_supervised_execution.latest.json`

## Current Recommendation

Use the 3-hour block as the default operator path until the supervised baseline stops failing for deterministic reasons on this host. Only then should the longer window become the normal route again.