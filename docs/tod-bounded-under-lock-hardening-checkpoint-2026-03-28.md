# Bounded-Under-Lock Hardening Checkpoint - 2026-03-28

## Status

The bounded training loop now completes end to end under lock-sensitive runtime conditions.

## What Changed

- `Invoke-TODTrainingLoop.ps1` now isolates child script execution in a separate PowerShell process.
- Training-loop recovery and subset stages now load artifacts from disk first instead of trusting inline stdout alone.
- `Invoke-TODOperatorChatSweep.ps1 -ArtifactOnly` now exits before commitment, trust-chain, and other mutation-heavy flows.
- The runtime-safe subset now produces a complete bounded artifact set that can be consumed reliably during lightweight validation.

## Interpretation

- The runtime-safe subset artifacts are authoritative for lightweight validation under lock.
- This hardening pass resolves the bounded-under-lock execution blocker.
- `runtime_interaction` remains `4/5` under the current rubric because full-test-equivalent scoring is still reserved for the stronger path.
- The flat score should not be interpreted as a broken bounded path. It reflects scoring design, not a failed implementation.

## Authoritative Artifacts

For bounded-under-lock validation, use these artifacts in the training output directory:

- `readiness-recovery.latest.json`
- `runtime-safe-sweep-raw.latest.json`
- `runtime-safe-sweep-ineffective-summary.latest.json`
- `runtime-safe-sweep-validation.latest.json`
- `runtime-safe-validation-subset.latest.json`
- `training-report.json`
- `training-report.md`

## Next Measurement

The next comparison point remains a quieter-window full retraining pass. That run should decide whether bounded-under-lock validation is only a fallback or is operationally equivalent enough to justify future rubric changes.
