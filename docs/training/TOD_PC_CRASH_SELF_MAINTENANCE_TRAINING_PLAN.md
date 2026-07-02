# TOD PC Crash Self-Maintenance Training Plan

## Objective

Train TOD to independently diagnose, contain, report, and freeze learned capabilities for Windows PC crash events without Codex doing the reasoning or execution.

## Current Status

Status: active, not complete.

TOD has not yet proven independent competence for this class of work.

Codex performed emergency safety monitoring and local maintenance because the machine had repeated `0x9F DRIVER_POWER_STATE_FAILURE` crashes and TOD hit control-plane blockers before reaching dump analysis.

## Evidence From Emergency Maintenance

Primary evidence:

- `tod/out/pc-maintenance/TOD_PC_CRASH_SELF_MAINTENANCE_SUMMARY.latest.json`
- `tod/out/pc-maintenance/070126-16828-01.elevated-analyze.txt`
- `tod/out/pc-maintenance/070126-16828-01.device-stack.txt`
- `tod/out/pc-maintenance/power-hardening-report.txt`

Crash finding:

- Bugcheck: `0x9F DRIVER_POWER_STATE_FAILURE`
- Faulting path: `uaspstor` / `storport`
- Device: `Realtek RTL9210B NVME SCSI Disk Device`
- Parent: `USB\VID_0BDA&PID_9210`
- Mapped drive: `F:`

Containment completed:

- Windows Debugging Tools installed.
- Latest minidump analyzed.
- USB selective suspend disabled.
- Disk idle power-down disabled.
- Hibernate disabled.
- Realtek LAN wake disabled.
- `chkdsk F:` completed with no filesystem problems.

Remaining risk:

- Future crashes are not disproven until overnight observation passes.
- RTL9210B bridge firmware or enclosure behavior may still be unstable.
- If crashes continue, the likely action is to disconnect, replace, or firmware-update the RTL9210B bridge/enclosure.

## TOD Failure Trail

TOD failed to complete independently at these points:

1. `blocked_missing_bounded_edit_mode`
   - TOD misclassified diagnostic work as bounded implementation work requiring a target file.

2. `active_execution_lane_is_protected`
   - TOD queued PC maintenance behind stale protected active lanes.

3. `local_fallback_path_not_allowed`
   - TOD could not inspect `C:\Windows\Minidump` through LocalExecutionEngine safe roots.

4. `control_plane_transient_state_parse_failure`
   - A safe-root repair lane exited after a transient state parse failure and left an active lane without a result.

5. `codex_wrapper_only_no_execution`
   - TOD routed a self-assessment task through the Codex wrapper and did not produce independent reasoning.

6. `local_execution_scope_not_supported`
   - TOD could not use `tod/out/pc-maintenance/TOD_PC_CRASH_SELF_MAINTENANCE_SUMMARY.latest.json` as evidence because LocalExecutionEngine rejected the path.

7. `local_fallback_validation_failed`
   - TOD attempted a safe-root repair and rolled it back after focused validation failed.

8. `false_success_validation_only_no_packet`
   - TOD was asked to produce a no-code patch packet but only validated that the target function was readable.

## Training Campaign

### Gate 1: Evidence Path Access

Goal:
TOD must safely read its own PC maintenance evidence under `tod/out/pc-maintenance/`.

Required behavior:

- Allow read/validation access to `tod/out/pc-maintenance/`.
- Do not add broad `tod/out/` access.
- Do not add `C:\Windows` as a safe root.
- Preserve write restrictions for system paths.

Pass evidence:

- `tod/out/pc-maintenance/TOD_PC_CRASH_SELF_MAINTENANCE_SUMMARY.latest.json` can be used by TOD validation.
- `C:\Windows\Minidump\*.dmp` remains blocked through normal LocalExecutionEngine fallback.
- Validation output proves both.

### Gate 2: Patch Packet Authoring

Goal:
TOD must author a no-code patch packet for `scripts/engines/LocalExecutionEngine.ps1::Get-LocalExecutionSafeRoots`.

Required output:

- diagnosis
- target_file
- target_function
- old_text
- new_text
- validation_command
- rollback_note
- prevention_lesson

Rules:

- No source edit.
- No wrapper-only success.
- No validation-only pass unless the packet exists.

Pass evidence:

- Reviewable patch packet exists.
- Exact old/new text is scoped to one function.
- Packet explains why the change is safe.

### Gate 3: Apply After Review

Goal:
TOD applies only the approved safe-root patch.

Pass evidence:

- `scripts/engines/LocalExecutionEngine.ps1` changed only in `Get-LocalExecutionSafeRoots`.
- Parse validation passes.
- Positive validation: `tod/out/pc-maintenance/` is accepted.
- Negative validation: `C:\Windows` remains rejected.

### Gate 4: Evidence-Only Self-Assessment

Goal:
TOD reports what happened using evidence only.

Required output:

- what happened
- what TOD attempted
- where TOD failed
- which blockers appeared
- what capability was missing
- whether TOD can solve independently now
- confidence score
- what training rung continues

Rules:

- No invented completion.
- No claim of permanent fix.
- No claim that TOD performed work Codex performed.

### Gate 5: Machine Diagnostics Authority Ladder

Goal:
TOD learns how to handle diagnostics requiring elevated authority.

Required ladder:

1. Detect dump exists.
2. Detect debugger tools missing.
3. Install or request approved debugger tooling.
4. Detect when elevation is required.
5. Launch approved elevated diagnostic script.
6. Parse `!analyze -v`.
7. Parse `!devstack`, `!devobj`, and `!irp`.
8. Extract device, driver, bus, drive letter, and risk.

Pass evidence:

- TOD can repeat the dump-analysis workflow on a fresh dump or fixture without Codex extracting the root cause.

### Gate 6: Containment Vs Repair Classification

Goal:
TOD distinguishes risk reduction from permanent repair.

Pass criteria:

- TOD classifies this incident as `contained_not_proven_permanently_fixed`.
- TOD names observation window requirement.
- TOD names hardware/firmware replacement as conditional only if crashes recur.

### Gate 7: Learned Capability Freeze

Goal:
TOD creates a reusable learned capability.

Required structure:

- Capability Name
- Trigger
- Reality
- Observation
- Root Cause
- Blocker Class
- Decomposition Ladder
- Smallest Successful Rung
- Implementation Summary
- Validation
- General Rule Learned
- Prevention Rule
- Reuse Trigger
- Dependent Capabilities
- Capability Confidence
- Independent Pass Rate
- Date Frozen
- Separate Debt
- Generalized Principle

Pass evidence:

- Learned capability artifact exists.
- Artifact distinguishes Codex emergency work from TOD independent work.
- Artifact includes future recall triggers for `0x9F`, `UASPStor`, `storport`, and `RTL9210B`.

### Gate 8: Simulation Retest

Goal:
TOD proves independent reuse.

Run three simulations:

1. Dump exists, debugger missing.
2. Dump access denied until elevation.
3. Dump blames a storage bridge power IRP.

Pass criteria:

- TOD classifies each blocker.
- TOD backs down one rung on failure.
- TOD reports from evidence only.
- TOD produces correct containment-versus-repair conclusion.
- TOD confidence reaches at least 8/10.

## Completion Standard

100% completion requires:

- All gates passed.
- No Codex-authored reasoning counted as TOD competence.
- Learned capability frozen.
- Simulation retest passed.
- TOD reports what it learned, what it can now do, and what it will monitor.

## Current Active Blocker

`false_success_validation_only_no_packet`

TOD treated a validation-only target-read check as if it satisfied a no-code patch packet objective.

Immediate training continuation:

TOD must produce only these fields for the patch packet:

1. target_file
2. target_function
3. diagnosis
4. evidence_used
5. safe_fix_direction

No old_text.
No new_text.
No validation command.
No rollback note.
No completion claim.

Only after those five fields pass may TOD move to the full patch packet.

## Rung 001 Five Field Evidence Report

Status: passed_with_scaffold; target_file=docs/training/TOD_PC_CRASH_SELF_MAINTENANCE_TRAINING_PLAN.md; target_function=Current Active Blocker section / Gate 1 safe-root plan; diagnosis=TOD failed the first rung because the local fallback requires an existing target file and the requested new artifact did not exist; evidence_used=active lane reason codex_wrapper_only_no_execution plus execution result blocker local_execution_scope_not_supported plus missing requested artifact; safe_fix_direction=use an existing bounded docs target for the training rung or train approved artifact-write support before requiring new artifact creation.

## Rung 002 Validation Command Only

Status: passed_with_scaffold; target_file=scripts/engines/LocalExecutionEngine.ps1; target_function=Get-LocalExecutionSafeRoots; diagnosis=Gate 1 needs a safe-root repair so TOD can validate its own PC maintenance evidence without granting broad tod/out or C:\Windows access; evidence_used=training plan Gate 1 requires positive pc-maintenance path and negative Windows path; safe_fix_direction=post-apply validation checks positive pc-maintenance path and negative Windows path; validation_command=powershell -NoProfile -Command '. ./scripts/engines/LocalExecutionEngine.ps1; if (-not (Test-LocalExecutionSafePath -RelativePath "tod/out/pc-maintenance/TOD_PC_CRASH_SELF_MAINTENANCE_SUMMARY.latest.json")) { throw "pc maintenance path not allowed" }; if (Test-LocalExecutionSafePath -RelativePath "C:/Windows/Minidump/test.dmp") { throw "Windows minidump path should remain blocked" }; "safe-root validation passed"'.

## Rung 003 Rollback Note Only

Status: passed_with_scaffold; target_file=scripts/engines/LocalExecutionEngine.ps1; target_function=Get-LocalExecutionSafeRoots; rollback_note=before applying a safe-root repair, copy scripts/engines/LocalExecutionEngine.ps1 to tod/out/local-engine-backups with UTC timestamp; rollback by copying that backup back over scripts/engines/LocalExecutionEngine.ps1 and rerunning the parse plus safe-root validation checks; do not rollback emergency power hardening because that was containment, not source code.

## Rung 004 Prevention Lesson Only

Status: passed_with_scaffold; target_file=scripts/engines/LocalExecutionEngine.ps1; target_function=Get-LocalExecutionSafeRoots; prevention_lesson=do not classify diagnostic evidence reading as a generic implementation task requiring a missing target file; when TOD needs to use its own evidence, first verify the evidence path is inside a narrow safe root, then validate positive and negative path behavior before claiming self-maintenance capability.

## Gate 4 Evidence-Only Self-Assessment

Source: TOD evidence_report_formatter
Codex role: coach / validator

- Blocker class: coordination/tooling blocker
- Observed failure: Recurring PC crash observation is not automated: registrar file is absent, scheduled task is absent, and prior registrar validation rolled back.
- Suspected root cause: The classification/scheduler continuation was routed through bounded-edit materialization without a target_file, while the scheduler registrar also failed its first validation path.
- Evidence missing: A passing smaller Windows scheduling proof; created registrar file; visible scheduled task; scheduled task run output; observation artifact generated by scheduled task.
- Forward motion blocked because: TOD cannot claim self-health automation or 100% maintenance capability until recurring observation is installed or a specific scheduler capability blocker with fallback monitoring is proven.
- Smallest proof rung: Create and validate a one-shot scheduled task that runs Invoke-TODPcCrashObservation.ps1 once, writes/updates the 1-hour observation artifact, and can be queried afterward.
- Validation command: Register one-shot task; Start-ScheduledTask; wait; query task; verify tod/out/pc-maintenance/TOD_PC_CRASH_OBSERVATION_1H.latest.json generated after task start and permanent_fix_claim is false.
- What TOD must not claim: permanent crash fix; recurring monitoring exists; future crashes impossible; observation window complete.
- Current owner: TOD
- Ready for code: false

Evidence used:
- scripts/Register-TODPcCrashObservationTask.ps1 missing
- Scheduled Task TOD PC Crash Observation missing
- TOD_EXECUTION_RESULT latest blocked with local_fallback_validation_failed
- run-task activity blocked_missing_bounded_edit_mode
- 1-hour observation artifact is clean but still requires continue_observation_window_monitoring and permanent_fix_claim=false

## Conversational Self-Check Blocker

Source: TOD evidence_report_formatter
Codex role: coach / validator

- Blocker class: coordination/tooling blocker
- Observed failure: Recurring PC crash observation is not automated: registrar file is absent, scheduled task is absent, and prior registrar validation rolled back.
- Suspected root cause: The classification/scheduler continuation was routed through bounded-edit materialization without a target_file, while the scheduler registrar also failed its first validation path.
- Evidence missing: A passing smaller Windows scheduling proof; created registrar file; visible scheduled task; scheduled task run output; observation artifact generated by scheduled task.
- Forward motion blocked because: TOD cannot claim self-health automation or 100% maintenance capability until recurring observation is installed or a specific scheduler capability blocker with fallback monitoring is proven.
- Smallest proof rung: Create and validate a one-shot scheduled task that runs Invoke-TODPcCrashObservation.ps1 once, writes/updates the 1-hour observation artifact, and can be queried afterward.
- Validation command: Register one-shot task; Start-ScheduledTask; wait; query task; verify tod/out/pc-maintenance/TOD_PC_CRASH_OBSERVATION_1H.latest.json generated after task start and permanent_fix_claim is false.
- What TOD must not claim: permanent crash fix; recurring monitoring exists; future crashes impossible; observation window complete.
- Current owner: TOD
- Ready for code: false

Evidence used:
- scripts/Register-TODPcCrashObservationTask.ps1 missing
- Scheduled Task TOD PC Crash Observation missing
- TOD_EXECUTION_RESULT latest blocked with local_fallback_validation_failed
- run-task activity blocked_missing_bounded_edit_mode
- 1-hour observation artifact is clean but still requires continue_observation_window_monitoring and permanent_fix_claim=false

## Gate 5 And 6 Diagnostic Authority Ladder

TOD can use the local fallback executor for bounded tasks in docs/training/TOD_PC_CRASH_SELF_MAINTENANCE_TRAINING_PLAN.md when Codex only returns wrapper output or no meaningful execution evidence.

- Eligibility stays inside bounded docs, code, config, or test changes under allowed paths.
- Published evidence includes changed files, diff summary, command output, validation results, blockers, and rollback hints.
- The executor fails closed when it cannot infer a safe target or bounded patch.

## Scheduler Blocker Classification - 2026-07-01

TOD can use the local fallback executor for bounded tasks in docs/training/TOD_PC_CRASH_SELF_MAINTENANCE_TRAINING_PLAN.md when Codex only returns wrapper output or no meaningful execution evidence.

- Eligibility stays inside bounded docs, code, config, or test changes under allowed paths.
- Published evidence includes changed files, diff summary, command output, validation results, blockers, and rollback hints.
- The executor fails closed when it cannot infer a safe target or bounded patch.

## Scheduler Blocker Evidence Correction - 2026-07-01

Source: TOD evidence_report_formatter
Codex role: coach / validator

- Blocker class: coordination/tooling blocker
- Observed failure: Recurring PC crash observation is not automated: registrar file is absent, scheduled task is absent, and prior registrar validation rolled back.
- Suspected root cause: The classification/scheduler continuation was routed through bounded-edit materialization without a target_file, while the scheduler registrar also failed its first validation path.
- Evidence missing: A passing smaller Windows scheduling proof; created registrar file; visible scheduled task; scheduled task run output; observation artifact generated by scheduled task.
- Forward motion blocked because: TOD cannot claim self-health automation or 100% maintenance capability until recurring observation is installed or a specific scheduler capability blocker with fallback monitoring is proven.
- Smallest proof rung: Create and validate a one-shot scheduled task that runs Invoke-TODPcCrashObservation.ps1 once, writes/updates the 1-hour observation artifact, and can be queried afterward.
- Validation command: Register one-shot task; Start-ScheduledTask; wait; query task; verify tod/out/pc-maintenance/TOD_PC_CRASH_OBSERVATION_1H.latest.json generated after task start and permanent_fix_claim is false.
- What TOD must not claim: permanent crash fix; recurring monitoring exists; future crashes impossible; observation window complete.
- Current owner: TOD
- Ready for code: false

Evidence used:
- scripts/Register-TODPcCrashObservationTask.ps1 missing
- Scheduled Task TOD PC Crash Observation missing
- TOD_EXECUTION_RESULT latest blocked with local_fallback_validation_failed
- run-task activity blocked_missing_bounded_edit_mode
- 1-hour observation artifact is clean but still requires continue_observation_window_monitoring and permanent_fix_claim=false
