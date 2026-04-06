# TOD Live Smoke Cycle - 2026-03-24

## Scope

Validated the live restart and smoke cycle for the updated listener cadence changes in:

- `scripts/Start-TODMimPacketListener.ps1`
- `scripts/Start-TOD-UI.ps1`

The goal was to confirm that:

1. the updated listener and UI could be restarted cleanly,
2. live cadence classification and backoff state were written to listener artifacts,
3. the UI API reflected the new cadence scoring and governance-noise suppression behavior.

## Runtime Used

- Listener process: `powershell.exe` running `Start-TODMimPacketListener.ps1`
- UI process: `powershell.exe` running `Start-TOD-UI.ps1 -Port 8844 -NoAutoOpen`
- Verification path: direct local API query via `.NET HttpClient` plus artifact inspection from `tod/out/context-sync/listener`

## Smoke Result

Status: partial pass

What passed:

- Updated listener process started successfully and held the mutex.
- Updated UI started successfully on `http://localhost:8844/`.
- Listener wrote new cadence fields into `listener_state.json`.
- Listener appended new cadence-classified journal entries into `TOD_LOOP_JOURNAL.latest.json`.
- UI API reflected the new cadence fields and governance-adjusted severity during the first post-restart smoke check.

What follow-on issue was discovered:

- A later live request rolled to objective `81`, but shared-state/UI selection remained pinned to objective `80`.
- That produced a real failed result packet for `objective-81-task-3297` due `tod_current_objective = 80` and `mim_objective_active = 80` while the request expected `81`.

## First Verified Live Check

Observed after fresh restart and initial duplicate-seen cycles:

- `selected_objective_id = 80`
- `progress.summary = Objective 80: 76% (listener journal)`
- `listener_activity.latest_objective_id = 80`
- `listener_activity.latest_request_id = objective-80-task-3297`
- `listener_activity.latest_execution_status = completed`
- `listener_activity.latest_cycle_classification = duplicate_seen`
- `listener_activity.latest_retry_reason = duplicate_seen`
- `cadence_health.severity = ok`
- `cadence_health.governance.adjusted_severity = ok`
- `cadence_health.governance.noise_suppressed = true`
- `cadence_health.governance.dominant_retry_reason = duplicate_seen`
- `cadence_health.cadence.score = 89.2`
- `steady_state.status = ok`
- `steady_state.summary = Regression is green; cadence noise is present but execution truth remains healthy.`

## Listener Artifact Evidence

### `listener_state.json`

Verified new cadence runtime fields were persisted during a duplicate-seen cycle:

- `last_cycle_classification = duplicate_seen`
- `last_retry_reason = duplicate_seen`
- `cadence_retry_streak = 1`
- `cadence_backoff_seconds = 1`
- `cadence_minimum_cycle_seconds = 3`
- `cadence_planned_sleep_seconds = 3`

### `TOD_LOOP_JOURNAL.latest.json`

Verified appended cadence-classified entry:

- `execution_status = already_processed`
- `cycle_classification = duplicate_seen`
- `retry_due_to_duplicate_seen = true`
- `cadence_noise = true`
- `retry_weight = 0.35`
- `planned_sleep_seconds = 3`
- `minimum_cycle_seconds = 3`
- `backoff_seconds = 1`
- `retry_streak = 1`

## Second Spot-Check

Observed later in the same live run:

- `selected_objective_id = 80`
- `marker_status = completed`
- `listener_latest_execution_status = failed`
- `result_status = failed`
- `result_objective_id = 81`
- `result_tod_current_objective = 80`
- `result_mim_objective_active = 80`
- `progress_summary = Objective 80: 76% (listener journal)`

Listener runtime state at that point:

- `last_processed_request_id = objective-81-task-3297`
- `last_result_status = failed`
- `last_cycle_classification = duplicate_seen`
- `cadence_retry_streak = 28`
- `cadence_backoff_seconds = 18`
- `cadence_planned_sleep_seconds = 20`

Journal tail at that point showed repeated objective-81 duplicate-seen cycles with increasing retry streak and capped backoff:

- `retry_streak = 27`, `planned_sleep_seconds = 20`
- `retry_streak = 28`, `planned_sleep_seconds = 20`

## Root Cause Of Follow-On Failure

Latest result packet `TOD_MIM_TASK_RESULT.latest.json` showed:

- `request_id = objective-81-task-3297`
- `status = failed`
- `review_gate.passed = false`
- `validator.passed = false`
- expected objective context: `81`
- actual integration context: `tod_current_objective = 80`, `mim_objective_active = 80`

This means the cadence work is functioning, but objective rollover handling has a fresh mismatch path for objective `81`.

## Assessment

The smoke cycle validated the new cadence implementation itself:

- retry classification is live,
- backoff is live,
- cadence scoring is live,
- governance-noise suppression is live.

The same live cycle also surfaced a new operational issue:

- objective rollover to `81` is not fully propagated through shared-state/UI selection and review/validation inputs.

## Follow-Up Remediation

TOD-side remediation was applied after the issue was identified:

- `scripts/Invoke-TODSharedStateSync.ps1` was updated to promote the live request objective when it matches the handshake's `current_next_objective`.
- `scripts/Start-TOD-UI.ps1` was updated so listener-only mode also prefers the live request objective during rollover instead of staying pinned to stale journal/objective-state data.
- Shared-state sync was rerun live.
- UI was restarted on `8844` with the patched logic.

Verified follow-up state:

- `shared_state/integration_status.json` now reports `tod_current_objective = 81` and `mim_objective_active = 81` with `mim_objective_source = live_task_request`.
- `shared_state/next_actions.json` now reports `current_objective_in_progress = 81`.
- Live UI API now reports `selected_objective_id = 81`.
- Live UI marker now points at objective `81`.

Remaining upstream lag after TOD-side remediation:

- canonical MIM export and handshake still advertise active objective `80` and next objective `81`.
- latest result packet is still the older failed `objective-81-task-3297` packet generated before the TOD-side remediation ran.
- bridge status correctly still reports a canonical/live mismatch until upstream export truth advances or a fresh objective-81 execution packet is emitted.

## Recommended Next Step

Trace and fix the objective-81 rollover path so that:

- `shared_state/next_actions.json`
- `shared_state/integration_status.json`
- UI selected objective
- listener review/validator expected-vs-actual objective inputs

all converge on objective `81` once the live request stream advances.

## Final Confirmation Smoke - 2026-03-26

After the listener runtime fix for inline expression handling, a final live confirmation smoke was rerun against the real shared path with the reusable smoke driver in `scripts/Invoke-TODMimListenerSmoke.ps1`.

Confirmed request:

- `request_id = objective-90-task-smoke-20260326215121`
- `objective_id = objective-90`
- `tod_action = get-state-bus`

Confirmed live outcome:

- listener terminal output recorded `Executing request objective-90-task-smoke-20260326215121...`
- listener terminal output recorded `Processed request objective-90-task-smoke-20260326215121 status=completed`
- smoke runner returned `result_emitted = true`
- smoke runner returned `result_status = completed`
- smoke runner returned `command_status_status = completed`
- smoke runner returned `journal_latest_execution_status = completed`

Confirmed execution-readiness propagation:

- result artifact reported `execution_readiness.status = stale`
- result artifact reported `execution_readiness.policy_outcome = allow`
- command-status artifact reported `execution_readiness.status = stale`
- journal entry reported `execution_readiness_status = stale`
- journal entry reported `execution_readiness_policy_outcome = allow`

Assessment:

- the live MIM listener path is once again completing end to end,
- readiness metadata is now present in result, command-status, and journal artifacts for a fresh live smoke request,
- the execution-readiness signal is therefore verified in real listener traffic, not only in focused tests or standalone certification.