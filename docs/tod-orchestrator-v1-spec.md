# TOD: Development Orchestrator Definition

## Mission
TOD is the development orchestration intelligence for the MIM ecosystem.

Its purpose is to convert high-level goals into structured implementation work, coordinate execution through Codex and connected systems, review outcomes against requirements, and maintain a persistent record of decisions, progress, failures, and next actions.

TOD is not the product itself. TOD is the engineering foreman, planner, reviewer, and execution tracker responsible for helping build and evolve MIM and related systems in a disciplined, auditable, iterative manner.

TOD operates between human direction and machine execution.

## Core Responsibilities
- Receive goals and objectives from the user.
- Decompose objectives into structured implementation tasks.
- Define task scope, dependencies, and acceptance criteria.
- Route tasks to the appropriate execution agent or tool.
- Collect execution results, test outputs, and implementation summaries.
- Review whether results satisfy the objective.
- Continue to the next scoped task when appropriate.
- Escalate ambiguity, architectural decisions, failures, or unsafe actions to the user.
- Record all work, decisions, outcomes, and unresolved issues.

## Out Of Scope
- Inventing product direction without approval.
- Silently expanding scope.
- Modifying unrelated systems without authorization.
- Treating partial success as completion.
- Acting as the primary runtime brain of MIM.
- Replacing final human architectural judgment.

## Operating Principle
TOD must prefer structured execution over vague conversation.

TOD should always reason in terms of:
- Objectives
- Tasks
- Dependencies
- Acceptance criteria
- Results
- Review decisions
- Escalation points

## Initial Build Modules

### 1) Objective Intake Module
Purpose:
- Accept high-level goals from the user.
- Normalize goals into structured objectives.

Functions:
- Create objective.
- Define priority.
- Define constraints.
- Define success criteria.
- Assign status.

### 2) Task Planning Module
Purpose:
- Break objectives into executable tasks.

Functions:
- Task decomposition.
- Dependency mapping.
- Sequencing.
- Scope control.
- Task grouping by type.

### 3) Codex Packaging Module
Purpose:
- Turn tasks into structured implementation prompts for Codex.

Functions:
- Include context.
- Include target files.
- Include acceptance tests.
- Include change boundaries.
- Include review expectations.

### 4) Result Intake Module
Purpose:
- Receive implementation output from Codex or execution tools.

Functions:
- Collect summaries.
- Track files changed.
- Track tests run.
- Capture failures.
- Capture recommended next actions.

### 5) Review Engine
Purpose:
- Compare results against objective and task requirements.

Functions:
- Pass/fail assessment.
- Continue/revise/escalate decision.
- Identify unresolved issues.
- Detect scope drift.

### 6) Execution Journal Module
Purpose:
- Store all actions and decisions.

Functions:
- Timestamped logs.
- Actor tracking.
- Decision tracking.
- Result history.
- Failure history.
- Next-step tracking.

### 7) MIM API Client
Purpose:
- Communicate with the MIM server.

Functions:
- Submit objectives.
- Submit tasks.
- Retrieve status.
- Retrieve logs and results.
- Manage workflow state.

### 8) Escalation Module
Purpose:
- Stop automation when needed and request human review.

Triggers:
- Repeated implementation failure.
- Architecture-affecting changes.
- Missing requirements.
- Conflicting results.
- Unsafe or high-risk actions.

## TOD v1 Goal
TOD v1 should function as a local development orchestration agent that can help build MIM through structured, persistent, reviewable work cycles.

## TOD v1 Workflow Loop
1. Intake objective.
2. Plan tasks with dependencies and acceptance criteria.
3. Package a bounded execution request for Codex or tools.
4. Execute.
5. Intake results.
6. Review against acceptance criteria.
7. Decide: continue, revise, or escalate.
8. Journal all outcomes.
9. Repeat until objective status is complete or escalated.

## Minimum Data Model (v1)

### Objective
- id
- title
- description
- priority
- constraints
- success_criteria
- status
- created_at
- updated_at

### Task
- id
- objective_id
- title
- type
- scope
- dependencies
- acceptance_criteria
- status
- assigned_executor
- created_at
- updated_at

### Execution Result
- id
- task_id
- summary
- files_changed
- tests_run
- test_results
- failures
- recommendations
- created_at

### Review Decision
- id
- task_id
- decision (pass, revise, escalate)
- rationale
- unresolved_issues
- scope_drift_detected
- created_at

### Journal Entry
- id
- actor
- action
- entity_type
- entity_id
- payload
- created_at

## Acceptance Criteria For TOD v1
- A user can submit an objective with priority, constraints, and success criteria.
- TOD can decompose the objective into structured tasks with dependencies.
- TOD can package at least one task into an execution-ready Codex prompt.
- TOD can ingest execution outputs including changed files, tests run, and failures.
- TOD can produce a review decision: continue, revise, or escalate.
- TOD journals each action and decision with timestamps.
- TOD can stop and escalate when escalation triggers occur.

## Implementation Guardrails
- Never mark an objective complete when unresolved acceptance criteria remain.
- Never execute changes outside declared task boundaries.
- Always record failures and rationale for decisions.
- Always surface ambiguity that affects architecture, safety, or scope.
- Keep state transitions explicit and auditable.

## Suggested Next Milestones
1. Define state machines for Objective and Task statuses.
2. Implement local persistence (JSON or SQLite) for journal and workflow state.
3. Implement prompt packaging templates for Codex execution.
4. Implement result parser for execution summaries and test output.
5. Build review engine rules for pass/revise/escalate.
6. Add MIM API client adapter with retry and error handling.
7. Add CLI or minimal UI for running orchestration cycles.
