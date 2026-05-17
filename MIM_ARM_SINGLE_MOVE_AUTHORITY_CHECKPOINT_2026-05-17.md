# MIM Arm Single-Move Authority Checkpoint (2026-05-17)

## Objective

Stabilize MIM arm movement authority so one operator input maps to one intentional movement flow, eliminate ghost/reversal behavior, and restore safe speed control.

## What Was Fixed

1. Unified backend movement path through `_execute_servo_move(...)` for authoritative command handling.
2. Preserved request metadata (`source`, `request_id`, `page`, `timestamp`) from UI to backend for root-cause tracing.
3. Disabled retry-like behavior on manual movement paths by default to reduce ghost corrections.
4. Replaced blind serial input clearing with explicit discard handling and logging.
5. Changed Safe button behavior to a single browser POST to `/go_safe`.
6. Restored manual move duration behavior (nudge/slider now honor configured Move Duration via animation path).
7. Added backend move forensic trace endpoint:
   - `GET /move_trace?limit=N`
   - Event ring buffer records `move_sent`, `move_ack`, `move_timeout`.
8. Fixed runtime telemetry regression by allowing metadata kwargs in `update_serial_runtime(...)`.

## Canonical Evidence Captured

1. Single base nudge click on `/routines` produced exactly one browser POST `/move`.
2. Matching backend trace showed exactly one send+ack pair for same request id.
3. Large base slider change produced paced, same-direction step sequence (not one high-speed jump).
4. Safe button produced one browser POST `/go_safe`; backend handled staged servo moves under `safe_position` source.

## Live Runtime Surfaces

1. UI route validated: `http://192.168.1.90:5000/routines`
2. Trace endpoint validated: `http://192.168.1.90:5000/move_trace?limit=...`
3. App process pattern to match during restart operations:
   - `/home/testpilot/mim_arm/mimenv/bin/python3 /home/testpilot/mim_arm/app.py`

## Files Of Record

1. `tmp_remote_mim/routes.py`
   - move authority execution path
   - trace buffer + `/move_trace`
   - metadata-safe serial runtime update
2. `tmp_remote_mim/control.js`
   - manual movement duration honored for nudge and slider flows

## Operational Verification Playbook

1. Baseline trace:
   - `curl -s http://127.0.0.1:5000/move_trace?limit=10`
2. Trigger one manual input (single base arrow click).
3. Re-pull trace with higher limit.
4. Confirm expected pattern:
   - one `move_sent` + one `move_ack` for same `request_id`
   - no immediate opposite-angle command from a different source
5. If duplicate/reversal occurs, isolate by `source`, `request_id`, `page`, and timestamp proximity.

## Current Status

Checkpoint state is stable and suitable as the go-forward baseline for future movement diagnostics and tuning.
