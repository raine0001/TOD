# MIM/TOD Training Scoreboard

Generated: 2026-06-03T04:51:43Z
Status: needs_attention_with_training_active

## Outcome Reflection

- Reflection generated: 2026-06-03T04:04:23Z
- Assessment: needs_attention
- Are outcomes improving: False
- Creating new objectives: True
- Truth integrity: healthy
- Fresh artifacts: 4
- Stale artifacts: 12

Outcome summary:

> MIM/TOD assessment: needs_attention. Objectives: 24 complete, 1 running, 32 blocked, 28 blocker follow-on objective(s). Next: MIM-TOD-OBJECTIVE-LIFECYCLE-REGRESSION-SUITE-V1. Top blocker: overnight_lane_stale_without_current_heartbeat; Restart as a fresh bounded overnight run only after the current repair stack is clean.

Reflection recommendations:

- Run blocker-to-objective synthesis because at least one blocker does not have a follow-on objective.
- Refresh stale reflection inputs: TOD_EXECUTION_RESULT.latest.json, TOD_VALIDATION_RESULT.latest.json, MIM_TOD_NEXT_OBJECTIVE.latest.json, MIM_TOD_CANONICAL_AUTHORITY_REGISTRY.latest.json, TOD_MATERIAL_IMPLEMENTATION_PROOF_POLICY.latest.json, MIM_TOD_CONTINUITY_MEMORY.latest.json, MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json, TOD_MATERIAL_IMPLEMENTATION_PROOF_STATUS.latest.json, MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json, MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json, MIM_TOD_FRESHNESS_PROVENANCE_POLICY.latest.json, MIM_TOD_MORNING_OPERATOR_SUMMARY.latest.json

## Training Hours

| Window | Value | Status |
|---|---:|---|
| Last 7 Days | baseline needed | baseline_needed |
| Yesterday | baseline needed | baseline_needed |
| Today | baseline needed | baseline_needed |

## MIM Score

| Metric | Yesterday | Today | Source |
|---|---:|---:|---|
| Intent Understood | baseline needed | 100 | live_gateway_eval |
| Answered Question | baseline needed | 100 | live_gateway_eval |
| Internal Jargon | baseline needed | 0 | live_gateway_eval |
| Recommendation Quality | baseline needed | 100 | live_gateway_eval |

## MIM Judgment Mode Score

- Objective: MIM-DURABILITY-SMOKE-V2
- Status: failed_needs_judgment_training
- Cases: 20
- Passed: 4
- Failed: 16
- Pass rate: 20%
- Current weakness: MIM defaults to status reporting instead of selecting recommendation, explanation, demonstration, consultative discovery, or problem-analysis mode.
- Target: Reach at least 80% on the focused V2 judgment suite before expanding to larger prompt sets.

| Group | Passed | Failed |
|---|---:|---:|
| Consultative Discovery | 0 | 3 |
| Demonstration Mode | 3 | 1 |
| Explanation Mode | 1 | 5 |
| Problem Analysis | 0 | 4 |
| Recommendation Mode | 0 | 3 |

## TOD Score

| Metric | Yesterday | Today | Source |
|---|---:|---:|---|
| Blockers Cleared | baseline needed | 3 | blocker_drill_artifacts |
| False Completions Prevented | baseline needed | 1 | drill_004_meaningful_evidence_self_correction |
| Validated Edits | baseline needed | baseline needed | baseline_needed |
| No Op Rejections | baseline needed | baseline needed | baseline_needed |

## Latest Evidence

- Latest TOD drill: TOD-BLOCKER-CLEARING-DRILL-004 (completed_with_evidence)
- Finding: Initial empty-evidence hypothesis was wrong. the inspected task result contains meaningful deferred-lane evidence, so TOD narrowed the blocker instead of treating it as empty evidence.
- Continue training: True
- Next required improvement: Resolve the reflection outcome gap before claiming training is going great.

## Notes

- Baseline-needed fields are not guessed. They become real numbers after scoreboard snapshots exist.
- Internal jargon is a lower-is-better percentage from live MIM evaluation prompts.
