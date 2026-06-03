# TOD-BLOCKED-OBJECTIVE-CLEARING-COMPETENCY-V1

Goal: teach TOD to clear blocked objectives, not merely report them.

Current blocker map:
- 33 blocked objectives
- 24 completed objectives
- 1 running objective
- 28 blocker follow-on objectives

Primary blocker groups:
- linked task already blocked_with_evidence: 21
- no executor bound: 7
- stale heartbeat/overnight lane: 1
- graphics executor missing: 1
- streaming STT parked/follow-up not executing: 1
- voice debug artifact missing: 1
- objective orchestration follow-up remaining: 1

TOD training loop:
Inspect -> Classify -> Group -> Choose repair -> Act -> Validate -> Immunize.

First drill is read-only: classify every blocked objective and rank the safest cleanup candidates.

Second drill clears one safe blocker group with evidence.
