# Objective 97 Execution Memory Triage - 2026-04-03

## Incident scope

- Treat Objective 97 as an execution-memory incident, not a communication incident.
- Communication lane truth during incident:
  - `bridge_status = ok`
  - ACK accepted
  - integration alignment = `in_sync`
- Active failed request: `objective-97-task-mim-arm-safe-home-1775231977`
- Secondary stale-backfill noise: `objective-97-task-mim-arm-safe-home-207752`

## Root cause

- `scripts/TOD.ps1` was loading the full `tod/data/state.json` before dispatching `safe_home`.
- `safe_home` does not require TOD operational state.
- The failure occurred in `Load-State` at `Get-Content -Raw` on `tod/data/state.json`, before the action reached the SSH safe-home handler.
- `Start-TODMimPacketListener.ps1` then classified the exception path as `executor_failed` through `Get-ResultReasonCode`.

## Memory evidence

- `tod/data/state.json` size at incident time: `1639957969` bytes (`1563.99 MiB`).
- Pre-fix bounded child execution of `TOD.ps1 -Action safe_home`:
  - exit code: `1`
  - peak working set: `3350.37 MiB`
  - peak private memory: `3341.42 MiB`
  - terminal failure: `System.OutOfMemoryException`
  - exact throw site: `scripts/TOD.ps1:454`
- What caused growth:
  - full-file raw string allocation via `Get-Content -Raw`
  - immediate `ConvertFrom-Json` into a second large in-memory object graph
  - additional normalization work after deserialization
- Conclusion:
  - the executor was loading all of `state.json`
  - it was duplicating the payload in memory as both raw text and parsed object
  - this was unnecessary for `safe_home`

## Fix applied

- Updated `scripts/TOD.ps1` so `safe_home` is treated as a stateless action in `Test-ActionRequiresState`.
- Also marked `ping-mim` stateless because it does not require operational state either.

## Post-fix evidence

- Post-fix bounded child execution of `TOD.ps1 -Action safe_home`:
  - no startup OOM
  - peak working set: `170.77 MiB`
  - peak private memory: `148.16 MiB`
  - reached actual MIM ARM execution path: `mim_arm_ssh_http`
  - returned success payload from `http://127.0.0.1:5000/go_safe`
- Fresh end-to-end listener smoke request:
  - request id: `objective-97-task-smoke-20260403171131`
  - objective id: `objective-97`
  - action: `safe_home`
  - journal outcome: `succeeded`
  - result status: `succeeded`
  - result reason code: `execution_completed`
  - execution mode: `direct_script_success`
  - command status: `succeeded`
  - command detail: `Task RESULT emitted to shared path.`

## State handling recommendations

- `state.json` can and should be partially loaded for stateless remote actions.
- Immediate rule:
  - do not load full state for `safe_home`, `ping-mim`, and other remote control actions that only need config and credentials.
- Near-term reduction options:
  - split operational state into smaller files by concern instead of one monolith
  - page large history collections instead of deserializing them wholesale
  - use lightweight summary payloads for routing/readiness decisions
  - avoid raw-string plus full-object duplication for oversized files

## Outcome

- Success condition met: TOD can now accept one fresh executable Objective 97 `safe_home` request and emit a live RESULT without `System.OutOfMemoryException`.