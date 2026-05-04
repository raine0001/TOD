# TOD 6-Hour Training Runbook

Superseded by [docs/tod-training-runbook-3h-2026-04-07.md](docs/tod-training-runbook-3h-2026-04-07.md) as the current default operator block.

Date: 2026-04-06
Audience: TOD operators and maintainers
Mode: live-runtime-safe first, full validation only when the host is quiet enough to allow it

## Purpose

Use a six-hour block to improve TOD's operational training posture without forcing heavyweight validation when the runtime is active, the state file is large, or the state file is locked.

This runbook treats bounded-under-lock validation as the default lane and uses supervised execution as the periodic hard checkpoint.

Reference surfaces:

- [docs/tod-training-automation-v1.md](docs/tod-training-automation-v1.md)
- [docs/tod-bounded-under-lock-hardening-checkpoint-2026-03-28.md](docs/tod-bounded-under-lock-hardening-checkpoint-2026-03-28.md)
- [docs/tod-execution-readiness-promotion-note-2026-03-27.md](docs/tod-execution-readiness-promotion-note-2026-03-27.md)
- [scripts/Invoke-TODTrainingRunbook6h.ps1](../scripts/Invoke-TODTrainingRunbook6h.ps1)
- [scripts/Invoke-TODTrainingLoop.ps1](../scripts/Invoke-TODTrainingLoop.ps1)
- [scripts/Invoke-TODSupervisedExecution.ps1](../scripts/Invoke-TODSupervisedExecution.ps1)

Historical executor:

```powershell
.\scripts\Invoke-TODTrainingRunbook6h.ps1
```

Compressed validation path for development and CI-like verification:

```powershell
.\scripts\Invoke-TODTrainingRunbook6h.ps1 -DurationHours 0.05 -WindowOneBoundedRuns 1 -WindowTwoBoundedRuns 1 -NoWait
```

## Operating Assumptions

- TOD is running on the live host and the UI is available on port `8844`.
- Current best-practice lane is bounded runtime-safe validation unless the host is quiet enough for full tests and smoke.
- The training loop may skip full tests or smoke by design when `tod/data/state.json` is large or locked.
- That skip is not a failure when authoritative bounded artifacts are still produced.

## Training Goals For This Block

1. Accumulate multiple fresh bounded-under-lock training artifacts.
2. Repeatedly validate readiness recovery and runtime-safe operator-chat sweep behavior.
3. Use supervised execution as the hard gate every few hours instead of depending only on local loop output.
4. End the block with a clear judgment: stable bounded lane, ready for quiet-window full run, or blocked by a repeatable issue.

## Canonical Artifacts To Watch

Primary bounded artifacts under [tod/out/training](../tod/out/training):

- `training-report.json`
- `training-report.md`
- `readiness-recovery.latest.json`
- `runtime-safe-sweep-raw.latest.json`
- `runtime-safe-sweep-ineffective-summary.latest.json`
- `runtime-safe-sweep-validation.latest.json`
- `runtime-safe-validation-subset.latest.json`

Primary supervised artifacts:

- `shared_state/tod_supervised_execution.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_COORDINATION_ESCALATION_STATE.latest.json`
- `shared_state/TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json`

## Stop Conditions

Pause the runbook and investigate before continuing if any of the following becomes true:

1. `runtime-safe-validation-subset.latest.json` reports `summary.passed_all = false` twice in a row.
2. `readiness-recovery.latest.json` stops showing recovery from blocked or degraded states.
3. `tod-supervised-default` escalates twice in a row for the same root cause.
4. The UI host on `8844` stops serving `GET /api/project-status`.
5. Bridge receipt check stops returning uploaded, executed, and full-access-granted posture.

## Hour 0: Baseline And Host Readiness

Objective: establish a hard baseline before running repeated training loops.

Run:

```powershell
Invoke-RestMethod -Uri 'http://127.0.0.1:8844/api/project-status' -TimeoutSec 20 | ConvertTo-Json -Depth 8
```

Then run the supervised checkpoint task:

```powershell
tod-supervised-default
```

Equivalent direct command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODSupervisedExecution.ps1 -RefreshMimContextFromSsh -FailOnEscalation
```

Accept baseline if all of the following hold:

1. The supervised run does not escalate.
2. Publish, receipt check, and bridge smoke are all OK.
3. The UI still serves project status after the run.

If supervised execution fails here, do not start the six-hour training block. Use the remaining time for root-cause repair instead.

## Hours 1-2: Bounded Runtime-Safe Repetition

Objective: collect repeated bounded-under-lock evidence without stressing the live host with unnecessary heavy validation.

Run one of the existing workspace tasks twice in sequence:

```text
rerun-bounded-training-20260328-14
rerun-bounded-training-20260328-15
```

Equivalent direct command pattern:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODTrainingLoop.ps1 -ConfigPath tod/config/tod-config.json -OutputDir tod/out/training/bounded-under-lock-<timestamp> -SkipProjectDiscovery
```

After each run, inspect:

```powershell
Get-Content tod/out/training/runtime-safe-validation-subset.latest.json -Raw
Get-Content tod/out/training/readiness-recovery.latest.json -Raw
Get-Content tod/out/training/training-report.md -Raw
```

Healthy bounded run criteria:

1. `summary.passed_all = true` in `runtime-safe-validation-subset.latest.json`.
2. `recovered = true` in `readiness-recovery.latest.json`.
3. `training-report.md` shows bounded runtime-safe validation, even if tests and smoke were skipped.
4. Warnings mention skipped heavyweight paths, not fresh runtime-safe failures.

## Hour 2 Review: Decide Whether To Stay Bounded Or Open A Quiet Window

Objective: decide whether to keep training in bounded mode or attempt one stronger full run later.

Stay in bounded mode if any of the following is true:

1. The host is still actively serving live work.
2. The training loop keeps preferring lightweight validation.
3. You expect `tod/data/state.json` contention.

Consider one full-window run later only if:

1. The host is quiet.
2. State contention is absent.
3. Recent bounded runs are clean.

This is a decision checkpoint, not a mandatory mode switch.

## Hours 3-4: Supervised Gate Then Another Bounded Pair

Objective: confirm bounded training is not diverging from the supervised path.

First run another supervised checkpoint:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODSupervisedExecution.ps1 -RefreshMimContextFromSsh -FailOnEscalation
```

If that passes, immediately follow with another bounded training pair:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODTrainingLoop.ps1 -ConfigPath tod/config/tod-config.json -OutputDir tod/out/training/bounded-under-lock-hour3a -SkipProjectDiscovery

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODTrainingLoop.ps1 -ConfigPath tod/config/tod-config.json -OutputDir tod/out/training/bounded-under-lock-hour3b -SkipProjectDiscovery
```

During this phase, compare:

1. Did supervised execution remain green?
2. Did runtime-safe subset remain green?
3. Did readiness recovery remain consistently recovered?
4. Did communication or readiness surfaces regress into true warning or critical states?

## Hour 4 Review: Assign TOD's Training Focus For The Last Two Hours

Use the training loop's built-in `next_drills` as the assignment queue.

Prioritize these in order:

1. `drill-reliability`
2. `drill-root-cause`
3. `drill-multi-file`
4. `drill-project-discovery`

Interpretation:

1. `drill-reliability`: best fit when runtime-safe recovery remains the primary operating seam.
2. `drill-root-cause`: use when failures are repeatable and localized.
3. `drill-multi-file`: use only if the host is stable enough for a coordinated implementation slice.
4. `drill-project-discovery`: use as a low-risk filler if execution should remain mostly read-only.

## Hours 5-6: Finish With One Hard Gate And A Final Evidence Pack

Objective: end the block with a decision-quality result, not just a pile of logs.

Run final supervised checkpoint:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODSupervisedExecution.ps1 -RefreshMimContextFromSsh -FailOnEscalation
```

Then capture the final bounded evidence set:

```powershell
Get-Content tod/out/training/training-report.json -Raw
Get-Content tod/out/training/readiness-recovery.latest.json -Raw
Get-Content tod/out/training/runtime-safe-validation-subset.latest.json -Raw
Get-Content shared_state/tod_supervised_execution.latest.json -Raw
```

Final block outcome should be classified as one of:

### Stable Bounded Lane

Use when:

1. Bounded subset stayed green through the block.
2. Recovery stayed healthy.
3. Supervised runs remained green.

Interpretation:

TOD can keep training productively under live-runtime constraints for extended periods.

### Ready For Quiet-Window Full Run

Use when:

1. Bounded subset stayed green.
2. Supervised runs stayed green.
3. The host became quiet enough to justify a fuller comparison run next.

Interpretation:

The next best investment is one quieter-window full training comparison, not more bounded repetition.

### Root-Cause Investigation Required

Use when:

1. Runtime-safe subset failed repeatedly.
2. Recovery evidence regressed.
3. Supervised execution escalated repeatedly.

Interpretation:

Stop the drill loop and switch into repair mode.

## Optional Quiet-Window Full Comparison

Only run this if the host is calm enough to permit heavier validation.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Invoke-TODTrainingLoop.ps1 -ConfigPath tod/config/tod-config.json -OutputDir tod/out/training/quieter-window-full-<timestamp>
```

What this is for:

1. Compare bounded validation against a stronger full-window pass.
2. Decide whether runtime interaction should remain `4/5` or deserves stronger credit in future rubric changes.

## Minimal Operator Checklist

At the end of the six-hour block, confirm all of the following:

1. Latest supervised run report is present and non-escalated.
2. Latest runtime-safe subset artifact reports `passed_all = true`.
3. Latest readiness recovery artifact reports `recovered = true`.
4. `training-report.md` reflects the current run and not stale output.
5. The final classification is written down as `stable bounded lane`, `ready for quiet-window full run`, or `root-cause investigation required`.

## Recommended Default For This Host Right Now

Given the current host behavior and the existing bounded-under-lock artifact history, the default six-hour operating posture should be:

1. supervised checkpoint at the start
2. repeated bounded runtime-safe loops during live runtime
3. supervised checkpoint in the middle
4. repeated bounded runtime-safe loops
5. supervised checkpoint at the end

That sequence maximizes evidence quality without pretending that live-runtime-safe validation and quiet-window full validation are the same thing.