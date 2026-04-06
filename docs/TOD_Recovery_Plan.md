# TOD Recovery Plan

## Purpose

Formalize automatic freeze detection and recovery between TOD and MIM so stalled work is detected, surfaced, corrected, and resumed with evidence.

## Scope

- Listener freeze or process exit.
- UI console API unresponsive.
- Pending request not advancing beyond timeout threshold.

## Recovery Loop

1. Check status every 2 minutes.
1. Detect freeze/error conditions:

- Listener process missing.
- Pending request id differs from last processed id for longer than freeze threshold.
- UI health endpoint fails.

1. Surface error in command console via watchdog state payload.
1. Auto-initiate reset:

- Restart listener.
- Restart UI if unhealthy.

1. Log evidence locally.
1. Emit MIM recovery alert packet.
1. Write self-heal order artifact with expected actions.
1. Test recovery (listener + UI health checks).
1. Resume processing.

## Maintenance Layer

The watchdog handles acute failures, but it should not be the only protection against slow drift.

Recommended operating model:

1. Continuous watchdog every 1 to 2 minutes for process exits, stalled pending work, and UI failures.
2. Scheduled self-health maintenance 2 to 3 times per day to refresh canonical MIM state, run one-shot recovery, and emit a consolidated maintenance report.
3. Optional deep maintenance once per day to include readiness and local verification gates.

Maintenance status model:

- `healthy`: no unresolved degradation detected.
- `healthy_with_fallback`: bounded fallback is active, but the run is still operationally non-failing.
- `warning`: residual degradation or risk remains and should be inspected if it persists.
- `needs_attention`: active critical condition or failed maintenance step requires intervention.

Maintenance severity model:

- `info`: healthy run with no residual concern.
- `notice`: expected, bounded fallback such as oversized-state listener telemetry fallback.
- `warning`: fallback scope/risk grows or other warning-level degradation remains.
- `critical`: failing health signal or maintenance action failure.

Fallback persistence threshold:

- Scheduled maintenance runs are marked separately from manual validation runs.
- Expected bounded fallback stays at `healthy_with_fallback + notice` by default.
- If expected bounded fallback persists across 6 scheduled runs inside 48 hours, maintenance promotes severity to `warning` while keeping status at `healthy_with_fallback`.
- Manual runs do not count toward that threshold so ad hoc validation does not create false escalation.

Maintenance runner:

powershell
./scripts/Invoke-TODSelfHealthMaintenance.ps1 -Profile standard -RestartUiOnFailure

Deep maintenance runner:

powershell
./scripts/Invoke-TODSelfHealthMaintenance.ps1 -Profile deep -RestartUiOnFailure -RefreshAgentMimReadiness

Register a scheduled maintenance task with three daily runs:

powershell
./scripts/Register-TODSelfHealthMaintenanceTask.ps1 -Profile standard -DailyAt 08:00,14:00,20:00 -IncludeLogonTrigger -RestartUiOnFailure

Maintenance artifacts:

- Latest report: shared_state/TOD_SELF_HEALTH_RUN.latest.json
- Historical log: shared_state/TOD_SELF_HEALTH_RUN.log.jsonl
- Drift guard latest: shared_state/tod_watchdog_drift_guard.latest.json
- Drift guard log: shared_state/tod_watchdog_drift_guard.log.jsonl

## Artifacts

- Watchdog status: shared_state/tod_recovery_watchdog.latest.json
- Watchdog log: shared_state/tod_recovery_watchdog.log.jsonl
- Self-heal order: shared_state/TOD_SELF_HEAL_ORDER.latest.json
- MIM alert packet: tod/out/context-sync/listener/TOD_MIM_RECOVERY_ALERT.latest.json
- Self-health report: shared_state/TOD_SELF_HEALTH_RUN.latest.json
- Self-health log: shared_state/TOD_SELF_HEALTH_RUN.log.jsonl

## Runbook

Start watchdog:

powershell
./scripts/Start-TODRecoveryWatchdog.ps1 -CheckEverySeconds 120 -FreezeAfterMinutes 5 -RestartUiOnFailure

Start in one-shot diagnostic mode:

powershell
./scripts/Start-TODRecoveryWatchdog.ps1 -RunOnce

Run watchdog drift guard in detect-and-correct mode:

powershell
./scripts/Invoke-TODWatchdogDriftGuard.ps1 -AutoCorrect -RestartUiOnFailure -EmitJson

Register scheduled drift alerts with resolution triggers:

powershell
./scripts/Register-TODWatchdogDriftGuardTask.ps1 -CheckEveryMinutes 15 -RestartUiOnFailure -TriggerMaintenanceOnUnresolved -IncludeLogonTrigger

High-frequency training profile (every 5 minutes, auto-standdown outside training hours):

powershell
./scripts/Register-TODWatchdogDriftGuardTask.ps1 -TaskName "TOD-Watchdog-DriftGuard-Training" -CheckEveryMinutes 5 -RestartUiOnFailure -TriggerMaintenanceOnUnresolved -ActiveWindows "06:00-23:00" -IncludeLogonTrigger

Overnight fallback profile (every 30 minutes, active outside training hours):

powershell
./scripts/Register-TODWatchdogDriftGuardTask.ps1 -TaskName "TOD-Watchdog-DriftGuard-Overnight" -CheckEveryMinutes 30 -RestartUiOnFailure -TriggerMaintenanceOnUnresolved -ActiveWindows "23:00-06:00" -IncludeLogonTrigger

Resolution trigger modes:

- `-TriggerMaintenanceOnUnresolved`: run self-health maintenance only when drift is detected and immediate correction is not successful.
- `-TriggerMaintenanceOnDetection`: run self-health maintenance for every detected drift event.

## Drift-Guard Training Drill

Goal: teach operators to identify stale watchdog telemetry that conflicts with fresher listener/request/result artifacts.

1. Execute the drift guard and capture the output payload.
2. Confirm `detected=true` and reason `watchdog_older_than_listener_truth` when watchdog artifact is behind.
3. Verify correction outcome (`correction.succeeded=true`) after one-shot watchdog refresh.
4. Re-check state bus (`./scripts/Get-TODLightweightStateBus.ps1 -AsJson`) and confirm `recovery_watchdog.stale=false`.
5. Archive artifacts for the incident timeline:

- shared_state/tod_watchdog_drift_guard.latest.json
- shared_state/tod_recovery_watchdog.latest.json
- tod/out/context-sync/listener/listener_state.json

Expected pass condition:

- No stale watchdog mismatch remains after correction.

## Verification

- Console /api/project-status contains recovery_watchdog state.
- Action Output panel shows watchdog status and timeline.
- Recovery log grows when injected failures occur.
- MIM alert packet appears after a simulated freeze.

## Notes

- A stable plateau in progress percentage is not itself an error; watchdog only triggers when a pending request is not advancing or health checks fail.

## Recoupling Closure Snapshot 2026-03-25

Verified closure after rerunning TOD shared-state sync against the refreshed MIM exporter:

- Canonical export objective: `88.2`
- Handshake packet objective: `88.2`
- Live task request: `objective-88.2-task-3310`
- TOD selected objective: `88.2`
- Objective alignment status: `in_sync`
- Objective alignment source: `handshake_packet`
- Live-request promotion: `false`
- Promotion reason: empty
- Final bridge status: `ok`

Authoritative host model:

- Canonical export and handshake originate on the MIM host at `/home/testpilot/mim/runtime/shared`.
- TOD is the consumer/mirror host; it stages those artifacts locally, derives `shared_state/integration_status.json`, and serves the live operator status surfaces.

Operational takeaway:

- If TOD shows a higher live-request objective than canonical export, treat that as stale upstream publisher state first.
- If canonical export, handshake, live task request, and TOD selected objective all converge, recoupling is complete and bridge compensation should no longer be active.
