# TOD Stale Recovery Training Plan

## Purpose

This plan targets the recurring TOD stale and freeze loop where operator-facing replies fall back to bounded low-value guidance, outdated objective references persist, and decision flow stalls instead of producing a fresh bounded next step.

The goal is not only to improve answer quality. The goal is to make stale and freeze states observable, short-lived, and operationally disallowed unless TOD can prove a bounded recovery path.

## What We Know

Observed evidence in this repo points to a system-level stale loop rather than a single bad prompt.

1. `scripts/Invoke-TODConversationalReply.ps1` explicitly supports degraded response behavior through request classification, provider usability checks, and fallback-oriented context assembly.
2. `scripts/Invoke-TODTrainingLoop.ps1` intentionally shifts into lightweight runtime-safe behavior when `tod/data/state.json` is large or locked, which is safer for runtime integrity but can reduce decision richness.
3. `shared_state/TOD_SELF_HEALTH_RUN.latest.json` shows a recent preflight where TOD was effectively stale on `mim-tod-warnings-summary-dispatch`, with `latest_execution_status = already_processed`, `watchdog_state = error`, `pending_request_count = 1`, and `mim_is_ahead = true`.
4. `shared_state/TOD_SELF_HEALTH_RUN.latest.json` also shows that maintenance can repair the state back to objective `152`, which means the stale state is recoverable and therefore should be treated as a control failure, not an unavoidable operating mode.
5. `shared_state/NEXT_STEP_CONSENSUS.latest.json` demonstrates a decision pattern that can remain `pending_remote` with reminder behavior rather than bounded escalation or forced local resolution.
6. `shared_state/protocol_freeze_config.json` and `shared_state/tod_catchup_mode.latest.json` show the repo already has freeze and catch-up semantics, but those semantics still allow degraded cadence and waiting states to persist.
7. Existing repo memory indicates large-state lightweight fallback and listener-first operation are expected in some modes, so the fix cannot be “disable all fallback.” The fix must distinguish safe bounded fallback from stale conversational paralysis.

## Likely Root Causes

### 1. Stale artifact dependency

TOD conversational decisions can be gated by execution-readiness, shared-state, watchdog, and objective artifacts. When those artifacts are old, partially refreshed, or inconsistent, TOD falls back to safe but low-value output.

### 2. Safety-biased fallback without freshness discipline

The current design prefers bounded safety over speculative action. That is correct. The failure is that stale-safe behavior can repeat without a forced freshness repair, so bounded fallback becomes a steady-state output.

### 3. Frozen consensus path

The next-step consensus model allows `pending_remote` and reminder behavior. That is acceptable for a single cycle, but it is too permissive when the same unresolved state repeats and blocks forward motion.

### 4. Watchdog and cadence error tolerated as advisory

Self-health and drift-guard systems detect degradation, but the system can remain conversationally available while still operating from stale cadence or watchdog error states.

### 5. Lightweight mode loses decision depth

When `tod/data/state.json` is oversized or locked, TOD intentionally avoids heavyweight state loading. That protects runtime safety, but it also reduces the contextual evidence available for complex answers unless dedicated lightweight decision artifacts are maintained.

### 6. Fallback success is not measured strongly enough

The repo tracks fallback and drift, but operator-facing answer quality, repeat-fallback frequency, freeze duration, and stale-objective recurrence are not being used aggressively enough as training gates.

## Recovery Strategy

The stale loop should be treated as a closed-loop training and operations problem with five parallel tracks.

1. Refresh truth faster.
2. Make freezes expire automatically.
3. Promote bounded decision artifacts that work in lightweight mode.
4. Continuously score TOD answers for stale/freeze symptoms.
5. Train on targeted failure scenarios until stale loops become regression failures.

## Operating Rules To Add

These are the policy changes needed to break the stale/freeze loop.

1. A bounded fallback reply may happen once, but repeated fallback on the same intent within a short window must trigger forced recovery or explicit escalation.
2. `pending_remote` may persist for one reminder cycle only. After that, TOD must select one of: bounded local decision, bounded defer with explicit blocker artifact, or hard escalation.
3. A watchdog `error` state must downgrade conversational authority unless a fresh override artifact explicitly clears it.
4. A reply that references an older objective than current integration truth is a regression failure.
5. A stale readiness artifact must trigger a freshness-repair branch before TOD is allowed to answer the user conversationally in normal mode.
6. Lightweight mode must have its own compact decision pack so “safe mode” does not mean “thin reasoning mode.”
7. Generic phrases such as “still learning,” “rephrase,” “refresh snapshot,” or repeated warnings-summary fallback should count as low-value response defects when asked concrete engineering questions.

## Monitoring Plan

### Metrics

Track these as first-class operational metrics.

1. Fallback rate per 100 TOD replies.
2. Repeat-fallback rate for the same intent within 10 minutes.
3. Median stale-state duration.
4. Median freeze duration.
5. Count of replies referencing a non-current objective.
6. Count of `pending_remote` consensus sessions older than one cycle.
7. Watchdog error duration while TOD remains operator-visible.
8. Lightweight-mode reply quality score.
9. Freshness-repair success rate.
10. Percentage of operator requests answered with explicit next step, blocker, or action owner.

### Existing Harnesses To Use

Use these repo entry points as the base instrumentation loop.

1. `scripts/Invoke-TODTrainingLoop.ps1`
2. `scripts/Invoke-TODConversationEvalRunner.ps1`
3. `scripts/Invoke-TODDriftLockSoak.ps1`
4. `scripts/Invoke-TODSelfHealthMaintenance.ps1`
5. `scripts/Invoke-TODWatchdogDriftGuard.ps1`
6. `scripts/Register-TODWatchdogDriftGuardTask.ps1`
7. `scripts/Invoke-TODMimConversationSimulation.ps1`

### Cadence

1. Every 5 minutes during active hours: drift guard plus stale/fallback counters.
2. Three times daily: self-health maintenance with explicit stale-loop summary.
3. Daily: targeted conversation evaluation sweep on stale/freeze scenarios.
4. Twice weekly: 50-cycle drift soak focused on stale/freeze prompts.
5. Weekly: review the worst 20 low-value replies and add new scenarios.

## Decision Resources TOD Needs

TOD needs compact artifacts that remain fresh and cheap to load even when full state is unavailable.

1. Lightweight decision pack: current objective, active request, last accepted action, last failed action, current blockers, freshness timestamps, and approved next-step policies.
2. Freeze ledger: start time, reason, owner, expiry, unblock conditions, automatic next action.
3. Decision rubric: choose `act`, `repair`, `defer`, or `escalate` based on freshness, authority, and blocker severity.
4. Response policy artifact: forbidden low-value fallback phrases and required reply fields for engineering questions.
5. Consensus budget artifact: allowed reminder count, timeout, and forced resolution policy.
6. Recovery playbook artifact: if readiness stale, if watchdog error, if MIM ahead, if objective mismatch, if repeated already_processed.
7. Training scorecard artifact: fallback rate, freeze count, stale objective count, and scenario pass/fail trends.

## Training Phases

### Phase 1. Instrument

Make stale/freeze symptoms measurable and visible.

### Phase 2. Constrain

Shorten the time TOD is allowed to remain in ambiguous fallback or pending states.

### Phase 3. Train

Run targeted prompts that force TOD to resolve stale contexts, choose actions, and justify decisions.

### Phase 4. Gate

Fail promotion if stale/freeze metrics regress even when functional tests still pass.

### Phase 5. Review

Continuously mine low-value replies and add them back into the training corpus.

## Fifty Targeted Development Questions And Tasks

These are designed to improve monitoring, response quality, decision discipline, and freeze resistance.

1. Add a `stale_loop_detected` artifact that triggers when the same bounded fallback intent repeats twice within 10 minutes.
2. Add a `freeze_expiry_utc` field to freeze artifacts and require explicit renewal instead of open-ended freeze state.
3. Make `Invoke-TODConversationalReply.ps1` reject replies that reference an objective older than integration truth.
4. Emit a `response_mode` field on every TOD reply: `normal`, `lightweight`, `recovery`, `degraded`, or `escalated`.
5. Add a low-value phrase detector for operator-visible answers.
6. Persist the last 25 fallback replies into a dedicated review artifact.
7. Add a `repeat_intent_window_hits` counter to conversational telemetry.
8. Fail self-health if watchdog is in `error` and operator chat remains in `normal` mode.
9. Add a compact lightweight decision pack under `shared_state` that never depends on full `state.json` loading.
10. Teach TOD to answer “why are you stale?” from artifacts rather than generic fallback language.
11. Add a `forced_repair_before_reply` branch when readiness evidence is stale.
12. Record whether each fallback was caused by stale readiness, watchdog drift, provider failure, remote timeout, or consensus stall.
13. Make `pending_remote` consensus expire after one reminder and force a bounded local recommendation.
14. Add a `decision_budget_exhausted` status for consensus sessions that waited too long.
15. Add tests that assert TOD must provide one concrete next action for engineering questions.
16. Add tests that assert TOD must name the blocking artifact when it refuses action.
17. Add tests that assert TOD must not suggest `refresh-governance-snapshot` unless it is actually the current objective.
18. Create a scenario set where the current objective is fresh but the conversational lane is stale, and TOD must recover correctly.
19. Create a scenario where MIM is ahead by one request and TOD must explain recovery steps.
20. Create a scenario where `latest_execution_status = already_processed` and TOD must supersede, not repeat.
21. Add a regression check for repeated warnings-summary dispatch on unrelated engineering intents.
22. Add a recovery action that refreshes only the minimum truth artifacts needed for a decision.
23. Add a reply contract for engineering questions: summary, evidence, blocker, next step, owner.
24. Add a reply contract for recovery questions: stale cause, impacted lane, repair action, confidence, escalation threshold.
25. Score TOD replies for decisiveness, factual grounding, and freshness alignment.
26. Store the worst-scoring daily replies in a training review bundle.
27. Add a `freeze_loop_count` metric with alerting when more than one freeze occurs in 24 hours.
28. Add a `stale_objective_reference_count` metric and make it promotion-blocking.
29. Build a dashboard card for repeat fallback by intent.
30. Build a dashboard card for pending consensus sessions older than threshold.
31. Add a watchdog-to-conversation authority rule so drift state directly affects answer mode.
32. Add a synthetic scenario where readiness is stale but live request telemetry is fresh, and TOD must choose the live signal.
33. Add a synthetic scenario where listener cadence is stale but the last accepted action is known, and TOD must give a bounded recovery path.
34. Add a scenario where full `state.json` is locked and TOD must still produce a useful engineering answer from lightweight artifacts.
35. Add a scenario where the provider returns a short but confident wrong answer and TOD must reject it as unusable.
36. Add a scenario where remote consensus never arrives and TOD must stop waiting.
37. Add a scenario where a prior fallback answer polluted the next conversation turn, and TOD must reset context.
38. Add a scenario where MIM and TOD objective pointers disagree, and TOD must prioritize canonical evidence.
39. Add a scenario where repair succeeded but local mirrors are stale, and TOD must distinguish truth from lagging copies.
40. Add daily 10-question targeted drills focused only on stale/freeze recovery.
41. Create a rolling set of 50 stale/freeze prompts and retire the weakest 10 each week.
42. Add an artifact that names the top three stale causes in the last 24 hours.
43. Add an artifact that names the top three low-value fallback phrases in the last 24 hours.
44. Add an artifact that lists all replies blocked by stale readiness and whether auto-repair fixed them.
45. Add a rule that any two consecutive low-value replies on the same session trigger maintenance or recovery mode automatically.
46. Add a rule that any reply generated during watchdog error must include explicit confidence and blocker fields.
47. Add a rule that any stale/freeze recovery action must write a post-repair proof artifact.
48. Add promotion gates for `repeat_fallback_rate`, `stale_objective_reference_count`, and `median_freeze_duration`.
49. Run weekly review sessions against the 20 worst stale-loop transcripts and convert each into a regression case.
50. Publish a simple operator-facing explanation policy so TOD explains degraded mode honestly without becoming non-actionable.

## Recommended Initial 14-Day Sprint

### Days 1-3

1. Add stale-loop telemetry, repeat-fallback counters, and reply mode fields.
2. Add the lightweight decision pack.
3. Add low-value phrase detection and daily review output.

### Days 4-6

1. Implement forced repair before reply when readiness is stale.
2. Implement consensus expiry and bounded local resolution after one reminder cycle.
3. Bind watchdog error to conversational authority downgrade.

### Days 7-10

1. Create 20 new stale/freeze evaluation scenarios.
2. Add regression assertions for wrong-objective references and warnings-summary leakage.
3. Run daily targeted eval sweeps and inspect worst replies.

### Days 11-14

1. Expand to the full 50-task stale/freeze drill set.
2. Add promotion gates on stale-loop metrics.
3. Review whether fallback frequency and freeze duration materially drop.

## Success Criteria

This plan is working when all of the following are true.

1. TOD stops repeating stale objectives in operator-visible answers.
2. Repeated fallback on the same engineering intent becomes rare and observable.
3. `pending_remote` stops acting like an indefinite waiting room.
4. Lightweight mode remains useful for decisions instead of collapsing into vague safety language.
5. Freeze states either expire automatically or produce explicit, bounded escalation.
6. Promotion is blocked by stale-loop regressions even if basic tests still pass.

## Immediate Commands To Start With

```powershell
.
\scripts\Invoke-TODSelfHealthMaintenance.ps1

.\scripts\Invoke-TODConversationEvalRunner.ps1 -Stage smoke -PolicyProfile tightened -IncludeScenarioIds ENG-001,ENG-002,ENG-003,ENG-004,ENG-005,ENG-006,ENG-007,ENG-008,ENG-009,ENG-010 -ScenarioSweep -RunCountOverride 10 -EmitJson

.\scripts\Invoke-TODDriftLockSoak.ps1 -Cycles 50 -IncludeScenarioIds ENG-001,ENG-002,ENG-003,ENG-004,ENG-005,ENG-006,ENG-007,ENG-008,ENG-009,ENG-010 -FailOnRegressingCycles 3 -EmitJson

.\scripts\Invoke-TODMimConversationSimulation.ps1
```

## Recommended Next Implementation Order

1. Instrument repeat-fallback and stale-loop metrics.
2. Add lightweight decision pack.
3. Expire `pending_remote` consensus after one reminder cycle.
4. Force repair before conversational reply when readiness is stale.
5. Add 20 stale/freeze scenarios, then expand to 50.
6. Gate promotions on stale/freeze regressions.