# MIM TOD Automatic Reality Response V1

Status: active
Owner: MIM + TOD
Priority: P0

## Goal

MIM/TOD should act on project-board reality automatically instead of waiting for Dave or Codex to notice drift.

## Rules

- Missing acceptance: write an intervention and define acceptance as the driving task.
- Scope expanded: write an intervention and split expanded work into a follow-on project.
- Close or split: force completion or follow-on project decision.
- Blocked: require resolve, reclassify, escalate, or archive.
- Stale momentum: promote, block, archive, or assign a bounded driving task.

## Guardrail

At most one automatic intervention per rule per project per UTC day.

## Acceptance

- Projects API exposes `auto_intervention_count`.
- Interventions create `mim_auto_intervention` project events.
- Interventions update next action and current driving task.
- Completed projects are skipped.
