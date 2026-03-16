# TOD Recovery Plan

## Purpose

Formalize automatic freeze detection and recovery between TOD and MIM so stalled work is detected, surfaced, corrected, and resumed with evidence.

## Scope

- Listener freeze or process exit.
- UI console API unresponsive.
- Pending request not advancing beyond timeout threshold.

## Recovery Loop

1. Check status every 2 minutes.
2. Detect freeze/error conditions:
- Listener process missing.
- Pending request id differs from last processed id for longer than freeze threshold.
- UI health endpoint fails.
3. Surface error in command console via watchdog state payload.
4. Auto-initiate reset:
- Restart listener.
- Restart UI if unhealthy.
5. Log evidence locally.
6. Emit MIM recovery alert packet.
7. Write self-heal order artifact with expected actions.
8. Test recovery (listener + UI health checks).
9. Resume processing.

## Artifacts

- Watchdog status: shared_state/tod_recovery_watchdog.latest.json
- Watchdog log: shared_state/tod_recovery_watchdog.log.jsonl
- Self-heal order: shared_state/TOD_SELF_HEAL_ORDER.latest.json
- MIM alert packet: tod/out/context-sync/listener/TOD_MIM_RECOVERY_ALERT.latest.json

## Runbook

Start watchdog:

powershell
./scripts/Start-TODRecoveryWatchdog.ps1 -CheckEverySeconds 120 -FreezeAfterMinutes 5 -RestartUiOnFailure

Start in one-shot diagnostic mode:

powershell
./scripts/Start-TODRecoveryWatchdog.ps1 -RunOnce

## Verification

- Console /api/project-status contains recovery_watchdog state.
- Action Output panel shows watchdog status and timeline.
- Recovery log grows when injected failures occur.
- MIM alert packet appears after a simulated freeze.

## Notes

- A stable plateau in progress percentage is not itself an error; watchdog only triggers when a pending request is not advancing or health checks fail.
