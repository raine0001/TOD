# MIM/TOD Training Initiative Gate

Generated: 2026-06-03T06:21:50Z
Status: peer_recovery_triggered
Escalation target: MIM_TOD_peer_recovery
Dave needed: False

## Trigger Reasons

- scoreboard_needs_attention
- stale_reflection_artifacts:12
- reflection_not_improving

## Recovery Ladder

- 1. MIM+TOD: MIM names the training gap in plain language; TOD refreshes or repairs the evidence lane with validation. (active)
- 2. Codex: Implement or debug the failing gate with exact files, commands, failing checks, and acceptance criteria. (next_if_peer_recovery_does_not_clear)
- 3. Dave: Decide priority, provide credentials/physical-world confirmation, or override safety/product direction. (only_if_machine_lanes_blocked)

## Auto Initiative

- Objective: MIM-TOD-TRAINING-AUTO-RECOVERY-GATE-V1
- Owner: MIM_TOD_peer_recovery
- Action: Refresh stale TOD evidence artifacts and rerun scoreboard/reflection until needs_attention clears.
- Acceptance: Next scoreboard has no below-threshold MIM metrics, judgment smoke remains >=80%, and reflection stale artifacts are reduced or converted into owned follow-on actions.

## TOD Codex Training

- Status: training_active
- Topic: Codex-level software implementation proficiency
- Goal: TOD progresses from task router to implementation-capable agent: inspect code, plan bounded changes, edit safely, validate, report evidence, and learn from failures.

## Next Check

- Run after every scoreboard refresh and publish this gate beside the scoreboard so drops cannot remain passive findings.
