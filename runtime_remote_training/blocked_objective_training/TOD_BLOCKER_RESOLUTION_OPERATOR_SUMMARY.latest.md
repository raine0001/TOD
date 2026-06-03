# TOD Blocker Resolution Autonomy

Updated: 2026-06-01T18:14:01Z

Status: active

TOD already has blocker clearing in place and proved the first safe cleanup. The next training improvement is stronger blocker resolution autonomy: every blocker must move to a resolved, parked, superseded, narrowed, repair-task, Codex-escalated, or human-decision state.

## Current Proof

- Drill 001: grouped 33 blocked objectives into 5 repair classes.
- Drill 002: completed with evidence; parked 2 non-current voice follow-ups; active blocked count moved from 33 to 31.
- Drill 003: active; linked-task blockers are being inspected for real evidence quality.

## New Finding

Sampled linked tasks 7972-7976 have task rows and task result rows, but the result content is empty/null. TOD must not treat empty task result rows as evidence.

## Rule

All blockers must be resolved or transformed into an accountable next state. No vague `blocked_with_evidence` state is acceptable unless the evidence has been inspected and has substance.

## Next Drill

DRILL-004 should repair the empty-evidence blocker class for one linked-task objective, then validate objective/task/artifact/dispatcher/operator status agree.
