# MIM Console Task Rule Card

Date: 2026-04-08

## Task Rules

1. Every task must belong to an objective.
2. Every task must have a plan before execution.
3. Tasks must stay visible in the queue until resolved.
4. Blocked or escalated tasks must show a reason.
5. Idle time means review the queue and start the best ready task.
6. Emergency tasks go first.
7. Dependencies and task order must be reviewed before execution.
8. Every task must be applied, tested, verified, and reviewed.
9. Completed work should be committed and pushed when it passes review.
10. No prompt is required unless security, public exposure, OS damage, or human harm risk is involved.

## Task Flow

1. Task identified by human, TOD, or MIM.
2. Objective created or selected.
3. Task added to the queue.
4. Plan written with dependencies, goals, outcomes, testing, and verification.
5. Queue re-ordered against current open work.
6. Best ready task starts.
7. Implementation runs.
8. Tests and verification run.
9. Review decides pass, revise, or escalate.
10. Passed work is logged complete and pushed.

## What Must Not Happen

- tasks getting lost after creation
- partial work left in open loops
- escalations being ignored
- work stalling because TOD or MIM cannot decide
- prompts blocking normal implementation work

## Console Questions This Card Supports

- What is the current active task?
- Why is this task first?
- What is blocked?
- What completed recently?
- What is the status of a specific task or objective?

## Prompt Boundary

Prompt the human only if the action may affect:

- security posture
- public-facing access or data exposure
- TOD operating system safety
- MIM operating system safety
- human safety

If none of those apply, continue without prompting.