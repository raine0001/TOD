# TOD Autonomy Continuity v1

## Purpose

Keep TOD moving during operator absence by enforcing no-stall execution, bounded idle time, and automatic fallback into training.

## Authority Model

- MIM provides direction when responsive.
- TOD executes without waiting for human approval.
- If MIM does not respond in time, TOD proceeds under documented assumptions.

## Enforcement Rules

1. No next step may stall awaiting human intervention.
2. TOD must never be idle for more than 30 minutes.
3. If no higher-priority MIM work exists, TOD resumes training.
4. If scheduled 20:00 training is missed, TOD starts it immediately when detected.
5. If drift, readiness degradation, or stale daemon state is detected, TOD runs reconciliation automatically.

## Runtime Components

- Daily training task: `TOD-AutonomousTraining-Daily`
- Idle daemon task: `TOD-AutonomousTraining-IdleDaemon`
- Autonomy guard task: `TOD-Autonomy-Guard`
- Completion status artifact: `shared_state/tod_autonomy_status.latest.json`

## Operating Flow

1. Run the daily 6-hour campaign at 20:00.
2. Keep the idle daemon active with a 30-minute idle threshold.
3. Run the autonomy guard every 15 minutes.
4. If the daily run is missed after 20:00, the guard starts it.
5. If daemon state is stale, the guard runs a reconciliation pass immediately.
6. Emit a completion-status artifact after each guard cycle.

## No-Stall Behavior

- TOD may notify MIM that it is proceeding.
- TOD does not pause while waiting for MIM.
- Training and recovery are valid default actions when no better work exists.

## Verification

Use these commands:

```powershell
.\scripts\Register-TODAutonomousTrainingCampaignTasks.ps1 -RunDaemonNow
.\scripts\Register-TODAutonomyGuardTask.ps1 -RunNow
.\scripts\Write-TODCompletionStatus.ps1 -EmitJson
```
