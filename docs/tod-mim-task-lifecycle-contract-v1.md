# TOD-MIM Task Lifecycle Contract v1

Date: 2026-04-08

## Purpose

This contract defines how objectives and tasks are created, planned, ordered, executed, reviewed, completed, reported, and escalated across TOD, MIM, and human-originated requests.

This is the formal answer to five questions:

1. how tasks get added
2. how tasks get managed
3. when tasks get worked on
4. when human prompts are allowed
5. how task status becomes visible in the console and operator reports

## Core Rules

- Every task must belong to an objective.
- Every task must have a durable plan before execution.
- Every task must be visible in a durable queue and status log.
- Every executed task must produce result, review, and verification evidence.
- Open tasks must not be lost because the system is idle, blocked, or undecided.
- If no active task is running, TOD and MIM must immediately review the open queue and start the best eligible task.
- No prompt is required for normal implementation, planning, testing, verification, commit, push, or follow-up improvement selection.
- A prompt is required only if the action risks security exposure, opening ports or public surfaces, damage to TOD or MIM operating systems, or damage or harm to a human.

## Sources Of Work

Tasks may originate from three sources.

### 1. Human-originated work

The human may create:

- an objective directly
- a task under an existing objective
- an emergency task
- a review or status inquiry about an existing task

Human-originated work must be normalized into the same objective and task lifecycle used for autonomous work.

### 2. TOD-originated work

TOD may create tasks when:

- an objective implies missing implementation steps
- review discovers a gap
- test or verification failure requires follow-up
- a completed task naturally suggests a bounded quality or reliability improvement

### 3. MIM-originated work

MIM may create tasks when:

- execution evidence reveals a missing prerequisite
- communication or synchronization failure requires corrective work
- a completed implementation needs a bounded follow-up for quality, clarity, or reliability

## Canonical Flow

## Phase 1. Objective Intake

All work starts with an objective.

Minimum objective fields:

- `objective_id`
- `title`
- `description`
- `priority`
- `constraints`
- `success_criteria`
- `origin` = `human` | `tod` | `mim`
- `status`

Rules:

- A free-floating task without an objective is invalid.
- If a human asks for a task without an objective, TOD or MIM must create or attach the correct objective first.
- Emergency work may use a short-lived incident objective, but it still requires an objective container.

## Phase 2. Task Intake

Once the objective exists, one or more tasks are created.

Minimum task fields:

- `task_id`
- `objective_id`
- `title`
- `type`
- `scope`
- `dependencies`
- `acceptance_criteria`
- `origin`
- `status`
- `priority`
- `emergency`
- `autonomous_approval`

Rules:

- New tasks must enter the queue in `proposed` state.
- A task may not go directly from `proposed` to `completed`.
- Every task must declare acceptance criteria before execution.

## Phase 3. Planning

Before execution, every task must be expanded into a formal plan.

Required plan fields:

- `task_id`
- `objective_id`
- `goal`
- `implementation_strategy`
- `dependencies`
- `ordering_reason`
- `risks`
- `expected_outcomes`
- `test_plan`
- `verification_plan`
- `completion_definition`
- `prompt_required`
- `prompt_reason`

Rules:

- No task enters execution until a plan exists.
- The plan must say whether execution is autonomous or prompt-gated.
- Prompt-gated is allowed only for the explicit safety and security boundaries in this contract.

## Phase 4. Prioritization And Sequencing

All open tasks must be ordered against the full queue.

Order is determined by the following precedence:

1. emergency tasks
2. blocking dependencies needed by active objectives
3. tasks that unlock multiple downstream tasks
4. tasks with the strongest objective leverage
5. tasks that reduce reliability or verification risk early
6. normal quality or improvement tasks

The ordering engine must consider:

- dependency readiness
- objective priority
- whether one task benefits a later task
- implementation efficiency from grouping adjacent work
- risk of leaving the task incomplete
- whether the task is stale or repeatedly deferred

Rules:

- The queue must be re-ranked after every completion, major failure, or new emergency.
- A blocked task remains visible and cannot silently disappear.
- If multiple tasks are eligible, TOD and MIM should choose the one with the best unlock or leverage value.

## Phase 5. Readiness Gate

Before execution starts, the system must verify:

- dependencies satisfied
- plan present
- acceptance criteria present
- test and verification path defined
- no prompt-required boundary is being crossed without review

If the readiness gate fails, the task becomes `blocked` with a durable reason.

## Phase 6. Idle-Time Execution Rule

When TOD and MIM are not actively working on a task, they must immediately:

1. review the open queue
2. select the best eligible ready task
3. begin execution without prompting the human

Rules:

- Idle time is execution time.
- Waiting without checking the queue is invalid.
- Freeze-ups caused by indecision are invalid; if ordering is ambiguous, choose the highest-leverage ready task and journal the rationale.

## Phase 7. Execution Loop

The standard execution loop is:

1. apply implementation
2. run tests
3. verify outcomes
4. record result
5. review pass or fail
6. continue, revise, or escalate

Rules:

- Partial implementation without recorded status is invalid.
- Open-ended loops are invalid.
- Every iteration must update the task status and journal.

## Phase 8. Review And Verification

Each executed task must produce:

- implementation result
- tests run
- verification evidence
- review decision
- unresolved issues when present

Allowed review outcomes:

- `pass`
- `revise`
- `escalate`

Completion requires:

- acceptance criteria satisfied
- tests pass or justified bounded exceptions recorded
- verification evidence recorded
- review decision = `pass`

## Phase 9. Commit And Push

Once a task is reviewed as passed and the working state is valid:

- TOD and MIM should commit the resulting implementation
- TOD and MIM should push the resulting build
- no prompt is required for commit and push when the task stayed inside approved boundaries

Commit and push are blocked only when:

- the task failed verification
- unresolved critical issues remain
- the task crossed a prompt-required safety boundary

## Phase 10. Follow-Up Objective Derivation

When a completed task reveals a meaningful bounded improvement, TOD and MIM should decide whether to add follow-up work without human intervention.

Allowed autonomous follow-up types:

- reliability hardening
- verification coverage expansion
- explanation or reporting improvements
- cleanup needed to finish the original goal properly
- quality improvements that materially benefit the just-completed work

Rules:

- follow-up tasks must still be tied to an objective
- follow-up tasks must still enter the same queue and planning lifecycle
- speculative scope growth without measurable benefit is not allowed

## Prompt Policy

Human prompts are not required for:

- planning
- sequencing
- implementation
- testing
- verification
- review
- follow-up task creation
- commit
- push
- next-step continuation

Rule:

- If the next-step policy is `pending_mim` or an open TOD-MIM consensus session exists, TOD must continue through that dialog lane and must not ask the operator to choose the next step.

Human prompts are required only when the action may impact:

- security posture
- opening ports
- public-facing data exposure
- damage to TOD operating system
- damage to MIM operating system
- damage or harm to a human

If none of those are in play, no prompt is allowed to block execution.

## Anti-Loss Rules

To prevent tasks from being lost:

- every task must exist in the queue artifact
- every transition must exist in the status log
- every blocked or escalated task must have a visible reason
- every stale task must appear in periodic queue review

## Anti-Partial Rules

To prevent partial implementation loops:

- no task may remain `in_progress` without fresh status updates beyond its execution timeout window
- tasks that fail mid-way must move to `revise`, `blocked`, or `escalate`
- completed means fully reviewed and verified, not partially coded

## Anti-Ignore Rules

To prevent escalated or emergency tasks from being ignored:

- emergency tasks move to the top of the queue immediately
- escalated tasks remain visible until resolved
- watchdog-style scheduled review must flag stale blocked or escalated work

## Anti-Freeze Rules

To prevent indecision stalls:

- queue review must always emit a selected next task when at least one eligible task exists
- if multiple tasks tie, choose the one that unlocks more downstream work
- if still tied, choose the older task and journal the tie-break decision

## Canonical Artifacts

The following artifacts should be treated as the durable lifecycle surfaces for the task system.

### 1. Queue snapshot

Path:

- `shared_state/TOD_MIM_TASK_QUEUE.latest.json`

Purpose:

- current ordered task list for console rendering and autonomous selection

Recommended shape:

```json
{
  "generated_at": "string",
  "source": "tod-mim-task-lifecycle-v1",
  "active_task_id": "string",
  "selection_reason": "string",
  "tasks": [
    {
      "task_id": "string",
      "objective_id": "string",
      "title": "string",
      "status": "string",
      "priority": "string",
      "emergency": false,
      "dependencies_satisfied": true,
      "queue_rank": 1,
      "origin": "human|tod|mim",
      "next_action": "string"
    }
  ]
}
```

### 2. Task status log

Path:

- `shared_state/TOD_MIM_TASK_STATUS.log.jsonl`

Purpose:

- append-only lifecycle and accountability log

Recommended shape:

```json
{
  "timestamp": "string",
  "task_id": "string",
  "objective_id": "string",
  "actor": "TOD|MIM|human",
  "from_status": "string",
  "to_status": "string",
  "summary": "string",
  "evidence": {},
  "schema_version": "tod-mim-task-lifecycle-v1"
}
```

### 3. Per-task latest snapshot

Path:

- `shared_state/tasks/<task_id>.latest.json`

Purpose:

- full current state for a single task

Recommended sections:

- task metadata
- plan
- latest result
- latest review
- latest verification
- follow-up recommendations

### 4. Console summary table

Path:

- `shared_state/TOD_MIM_TASK_STATUS.latest.json`

Purpose:

- compact data for MIM Console task list and task status table

Recommended columns:

- task id
- objective id
- title
- owner
- status
- priority
- queue rank
- blocked reason
- last updated
- next action

## MIM Console Requirements

The MIM Console task table should show:

- active task
- queued tasks in order
- blocked tasks
- escalated tasks
- recently completed tasks
- latest review result

The console should support status questions such as:

- current task
- why this task is first
- what is blocked
- what completed recently
- status of a named task or objective

## Status Inquiry Contract

TOD and MIM should be able to answer task status questions from the queue and per-task artifacts without inventing status from chat memory.

Required answer elements:

- current status
- objective linkage
- last meaningful progress
- current blocker if any
- next planned action
- confidence based on freshness of the task artifact

## Operational Commands

Human or automation can add work through the existing TOD lane:

```powershell
.\scripts\TOD.ps1 -Action new-objective -Title "..." -Description "..." -Priority high -Constraints "..." -SuccessCriteria "..."
.\scripts\TOD.ps1 -Action add-task -ObjectiveId <ID> -Title "..." -Type implementation -Scope "..." -Dependencies "..." -AcceptanceCriteria "..."
.\scripts\TOD.ps1 -Action list-objectives
.\scripts\TOD.ps1 -Action list-tasks -ObjectiveId <ID>
.\scripts\TOD.ps1 -Action add-result -TaskId <ID> -Summary "..." -TestsRun "..." -TestResults "pass"
.\scripts\TOD.ps1 -Action review-task -TaskId <ID> -Decision pass -Rationale "..."
.\scripts\TOD.ps1 -Action show-journal -Top 25
```

## Scheduled Execution Model

Recurring scheduled tasks should support this lifecycle in three lanes.

### Lane 1. Queue review

Purpose:

- rank work and pick the next eligible task during idle time

### Lane 2. Execution

Purpose:

- run the selected task autonomously when safe and ready

### Lane 3. Health and stale-work review

Purpose:

- detect ignored escalations, stale blocked tasks, long-running partial tasks, or queue freeze-ups

## Completion Standard

The lifecycle is functioning correctly only when:

- tasks are never lost after creation
- tasks are never worked without accountability and reporting
- partial tasks do not remain in open-ended loops
- escalated tasks stay visible and actionable
- TOD and MIM do not freeze while eligible work exists
- completed work is tested, verified, committed, and pushed without unnecessary prompts
