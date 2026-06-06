# MIM-TOD-NEEDS-REVIEW-DRAIN-V1

Status: completed with evidence

Goal: convert Needs Review projects into real successor states.

Acceptance:
- Needs Review drops from 15 to under 5.
- Every reviewed project gets a successor action and evidence requirement.
- No project remains Needs Review without an age and reason.
- Each reviewed project is classified as closed, split, dispatched to TOD, waiting on evidence, waiting on Dave, or archived.
- Public TOD route repair stays separate.

First driving task: review the highest-priority Needs Review project and convert it into a successor state with an evidence requirement.

Baseline:
- Review entered: 15
- Review resolved: 0
- Still review: 15
- Reopened: 0
- Review resolution rate: 0%

Latest:
- Review entered: 15
- Review resolved: 15
- Still review: 0
- Reopened: 0
- Review resolution rate: 100%
- Stale: 0
- First resolved project: `22` / MIM TOD Automatic Reality Response V1
- Successor state: waiting on evidence

Verified success: Needs Review drained to zero, stale remained zero, and reviewed projects now have recorded successor states and evidence requirements.

Successor Quality baseline:
- Total successors: 15
- Terminal success: 0
- Active follow-through: 15
- Pending outcome: 15
- Failed or reopened: 0
- Terminal success rate: 0%
- Follow-through rate: 100%
- By path: dispatched to TOD 12, waiting on evidence 2, escalated to Codex 1.

Successor Aging:
- Dispatched to TOD pending > 24h: watch.
- Waiting on evidence pending > 48h: escalate.
- Escalated to Codex pending > 72h: Dave visibility.
- Current aging: OK 15, watch 0, escalate 0, Dave visibility 0.
- Current stale: 0.
- Current needs review: 0.

Repair note: the generic P0/P1 stale clock briefly overrode successor SLAs. That is repaired so successor states use the 24/48/72 hour aging policy.

Metric: Review Resolution Rate measures whether Needs Review projects become real successor states instead of notes. Successor Quality measures whether those successor states later become terminal success, active follow-through, pending outcomes, or failed/reopened work.

Policy: Needs Review is not a resting state. MIM/TOD must decide and record the next execution, evidence, or closure path.
