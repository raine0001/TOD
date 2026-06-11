# MIM TOD Real Movement Training V1

Generated: 2026-06-11T15:40:57Z
Status: action_required
Overall: Real movement is not proven yet. Operator Impact, stale artifact retirement, and TOD execution evidence must all improve.

## Required Movement Loop

- MIM replies include action, owner, evidence, aging, and Dave-needed yes/no.
- TOD produces changed files plus validation, or blocks with inspected evidence, every active cycle.
- Stale artifacts are retired, refreshed, or mapped to current project state.
- Projects older than 24 hours without movement are forced to completed, split, dispatched, waiting-with-evidence, blocked-with-owner, or archived.
- Every action records whether it moved the project closer to completion.

## Metrics

- MIM Operator Impact: 4.5/10 from 4 scored replies (8/10+)
- Dave Needed Clarity: 0% / 0 of 4 (90%+)
- Stale Artifact Count: 5 (decrease every cycle until 0 or source-labeled historical)
- Validated TOD Edits: 1 (fresh real execution/blocker evidence each cycle)
- Dispatcher State: idle_training_running (no idle state without successor action)
- Idle Training State: running (training produces real movement or a narrower blocker)

## Cycle 001

- Score the next 10 live MIM operational replies against the five-field contract.
  Owner: MIM
  Evidence: Updated MIM_OPERATOR_IMPACT_SCORECARD with 10 scored replies and per-field pass rates.
  Aging: Review after 10 replies or 24 hours, whichever comes first.
  Dave needed: no
- Dispatch one bounded TOD task that must inspect, edit or block with evidence, validate, and publish truth.
  Owner: TOD
  Evidence: Fresh TOD result artifact with changed files or inspected blocker, validation output, and successor state.
  Aging: Escalate if no fresh result appears in the next active cycle.
  Dave needed: no
- Retire, refresh, or map one stale training artifact to a current project state.
  Owner: MIM + TOD
  Evidence: Stale artifact retirement record naming the artifact, current state, owner, and reason.
  Aging: One stale artifact must move per cycle until the stale count is 0 or source-labeled historical.
  Dave needed: no
- Select one vague working project and force it into completed, split, dispatched, waiting-with-evidence, blocked-with-owner, or archived.
  Owner: MIM
  Evidence: Project event showing successor or terminal state and expected evidence.
  Aging: Any project with 24 hours of no movement must be reviewed.
  Dave needed: no unless policy, credential, or external-account approval is required.
- Record whether the cycle moved a project closer to completion.
  Owner: MIM + TOD
  Evidence: Movement outcome label: moved, did_not_move, blocked_with_evidence, split, closed, or archived.
  Aging: Record before the next cycle starts.
  Dave needed: no
