# Batch 20 Autonomous Debugging

Status: passed
Generated: 2026-05-21T02:40:33Z

Goal: Move first-pass diagnosis away from Codex dependency and into MIM/TOD's own symptom to hypothesis to probe to evidence to rollback-safe repair loop.
Primary failure target: Codex must not be first-pass diagnosis.

What TOD packaged:
- mim_symptom_to_hypothesis: Turn an observed failure symptom into ranked local hypotheses before escalation.
- tod_bounded_diagnostic_probe: Run one safe bounded probe that can confirm or falsify the leading hypothesis.
- mim_evidence_based_root_cause_selection: Select likely root cause from probe evidence and uncertainty, not stale templates.
- tod_rollback_safe_repair_plan: Prepare a reversible repair plan before any patch attempt.
- mim_failed_first_pass_self_correction: Detect a wrong first route and generate a corrective local route automatically.
- tod_repair_probe_validation: Validate the repair hypothesis with a focused behavior/static/artifact check.
- mim_codex_last_resort_escalation: Allow Codex only after local hypothesis, bounded probe, insufficient/conflicting evidence, and no rollback-safe local repair.
- tod_debugging_evidence_packet: Publish symptom, hypothesis, probe, evidence, repair plan, rollback plan, and validation fields.
- mim_autonomous_repair_confidence_scoring: Score repair confidence from evidence quality and rollback safety.
- mim_tod_end_to_end_autonomous_debugging: Complete the full loop without Codex unless local diagnosis fails.

Validation: 3/3 passed.
Errors: none
TOD errors: none
Next batch allowed: true

Why this helps:
This gives MIM/TOD a reusable absorption-training packet for batch 20 autonomous debugging with concrete goals, expectations, success metrics, behavior probes, and next-action gating.
