# TOD Blocked Objective Clearing Training

Updated: 2026-06-01T11:13:20Z

TOD now has a concrete blocker-clearing drill instead of a generic instruction to keep training.

## Current Blocked Objective Picture

- Blocked objectives: 33
- Repair classes found: 5
- First drill status: completed_with_read_only_evidence
- Mode: read_only

## Repair Classes

- artifact_missing_or_superseded: 1
- linked_task_blocked_needs_evidence_inspection: 21
- missing_executor: 8
- parked_followup_not_currently_executing: 2
- stale_heartbeat_or_recovery: 1

## Safest Next Cleanup Candidates

- MIM-STREAMING-STT-MIGRATION-V1: mark parked_until_needed or materialize one specific follow-up task
- MIM-VOICE-RESPONSIVENESS-AUDIBLE-ROUTING-REPAIR-20260528: mark parked_until_needed or materialize one specific follow-up task
- MIM-VOICE-DEBUG-PANEL-V1: verify whether artifact is still needed; recreate or mark superseded with replacement evidence

## What TOD Must Learn

TOD should clear blockers using this loop:

1. Inspect objective, linked task, dispatcher status, and evidence artifact.
2. Classify the blocker into one primary class.
3. Group shared root causes.
4. Pick the smallest safe repair action.
5. Act only with evidence.
6. Validate objective/task/artifact/operator status agree.
7. Record the prevention rule so this blocker class is easier next time.

## Current Next Drill

`TOD-BLOCKER-CLEARING-DRILL-002`

Clear one safe blocker group end-to-end with evidence. Start with parked follow-up or artifact-missing/superseded items before executor-binding work.

Hard rule: no objective is complete until it is tested done, with linked evidence and matching operator-facing state.
