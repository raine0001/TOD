# MIM ARM Human Communication Tasking

Date: 2026-04-08

## Answer

Yes, there is already a task and scheduler foundation in this repo.

- Structured implementation work can be tracked through `scripts/TOD.ps1` objective and task actions.
- Long-running or recurring automation can be installed through the existing `Register-*.ps1` scheduled-task scripts.

What was missing was a dedicated tasking list for the new MIM ARM communication plan. This document fills that gap.

## Next Implementation Step

The next implementation step is not a scheduler.

It is Phase A from the plan:

1. identify the ARM-local fallback responder that currently emits weak local chat replies
2. replace that default reply path with a transport path that forwards the message to MIM
3. render source on every response so the UI shows `MIM`, `MIM+TOD`, or `fallback`

That is the correct first slice because until the ARM UI stops pretending to reason locally, any later scheduling only automates the wrong behavior.

## Existing Repo Foundations

### Objective and task lane

Available through `scripts/TOD.ps1`:

- `new-objective`
- `add-task`
- `list-objectives`
- `list-tasks`
- `package-task`
- `run-task`
- `run-task-report`

### Existing scheduled-task lane

Already present in the repo:

- `scripts/Register-TODConversationProviderTask.ps1`
- `scripts/Register-TODListenerTask.ps1`
- `scripts/Register-TODCatchupGateWatcherTask.ps1`
- `scripts/Register-TODWatchdogDriftGuardTask.ps1`
- `scripts/Register-TODTrainingDaemonTask.ps1`
- `scripts/Register-TODVoiceListenerTask.ps1`

These show the intended pattern: one-time engineering work is tracked as objectives and tasks; persistent recurring behavior is installed as a scheduled task only after the logic is correct.

## Tasking List

## Objective

`MIM ARM human communication uses MIM as the conversational authority and TOD only as bounded evidence support.`

### Task 1. Trace and remove ARM-local fallback authority

Owner: MIM ARM

Goal:

- find the code path that generates the current weak local chat fallback
- demote it from primary reply logic to transport-failure-only behavior

Acceptance:

- normal ARM chat requests do not terminate in the local placeholder responder
- local fallback is only used when MIM is unreachable or times out

Scheduler posture:

- not a scheduled task
- one-time engineering implementation task

### Task 2. Define the ARM-to-MIM request envelope

Owner: MIM + MIM ARM

Goal:

- define the request payload for ARM chat requests sent to MIM

Required fields:

- `session_id`
- `message_id`
- `operator_text`
- `intent`
- `objective_id`
- `source_surface = mim_arm_ui`
- `requested_response_mode`

Acceptance:

- envelope format is documented and stable
- MIM can parse and answer the envelope deterministically

Scheduler posture:

- not a scheduled task
- one-time contract implementation task

### Task 3. Define the MIM-to-ARM response envelope

Owner: MIM

Goal:

- standardize the human-facing response object returned to ARM

Required fields:

- `answer_text`
- `source`
- `confidence`
- `limitations`
- `objective_id` when relevant
- `evidence_summary`
- optional `bounded_actions`

Acceptance:

- ARM can render the response without guessing field meanings
- source and confidence are always available

Scheduler posture:

- not a scheduled task
- one-time contract implementation task

### Task 4. Add TOD evidence enrichment path

Owner: TOD

Goal:

- provide a bounded evidence lookup path for MIM when runtime truth is needed

Evidence examples:

- active objective
- bridge health
- listener and watchdog status
- execution-readiness posture
- bounded action availability

Acceptance:

- MIM can request bounded evidence without turning TOD into the primary chat brain
- runtime-sensitive questions are grounded in real TOD evidence

Scheduler posture:

- core logic is not a scheduled task
- recurring freshness checks may later be attached to existing listener or watchdog scheduled tasks

### Task 5. Update the ARM UI renderer

Owner: MIM ARM

Goal:

- render structured answers clearly to the operator

Required UI fields:

- primary answer
- source badge
- confidence badge
- limitations
- optional evidence summary
- optional bounded actions

Acceptance:

- the operator can tell whether the answer came from `MIM`, `MIM+TOD`, or `fallback`
- the UI no longer looks like an ungrounded toy chat box

Scheduler posture:

- not a scheduled task
- one-time UI implementation task

### Task 6. Add communication telemetry and health reporting

Owner: TOD + MIM ARM

Goal:

- track whether ARM is using real MIM-backed communication

Required telemetry:

- request count
- response source
- latency
- timeout count
- fallback count
- placeholder count

Acceptance:

- health or audit surfaces can prove whether ARM is talking to MIM or falling back locally

Scheduler posture:

- yes, this should build into recurring checks
- best attached to watchdog-style scheduled execution after implementation

### Task 7. Add recurring health automation

Owner: TOD

Goal:

- turn communication health validation into a scheduled operational lane

Recommended recurring checks:

- verify ARM-to-MIM route is reachable
- verify source labels remain correct
- verify fallback usage stays below threshold
- verify TOD evidence enrichment still resolves when requested

Acceptance:

- scheduled run emits machine-readable health output
- drift or fallback regression becomes visible without manual inspection

Scheduler posture:

- yes, scheduled task
- likely implemented as a new purpose-built registration script after Tasks 1 through 6 are complete

## Scheduled Task Mapping

### Use existing scheduled tasks now

These existing tasks already support adjacent operational stability:

- `Register-TODListenerTask.ps1` for listener continuity
- `Register-TODCatchupGateWatcherTask.ps1` for single-writer catch-up and gate posture
- `Register-TODWatchdogDriftGuardTask.ps1` for recurring drift detection and correction
- `Register-TODConversationProviderTask.ps1` only if the local TOD conversation provider remains part of bounded evidence or fallback support

### Add a new scheduled task later

After the direct MIM path is implemented, add a dedicated scheduled task for this plan.

Recommended future script:

- `scripts/Register-TODMimArmCommunicationHealthTask.ps1`

Recommended future daemon:

- `scripts/Start-TODMimArmCommunicationHealth.ps1`

Recommended checks:

- poll recent ARM chat telemetry
- verify `source != fallback` for normal requests
- verify MIM response latency stays inside threshold
- verify TOD evidence calls succeed when invoked
- write a latest health artifact under `shared_state/`

## Suggested Objective and Task Breakdown For TOD

If this is entered into the TOD objective lane, use this structure.

Objective title:

- `MIM ARM communication authority realignment`

Suggested task titles:

1. `Trace ARM fallback responder`
2. `Implement ARM to MIM request envelope`
3. `Implement MIM response envelope`
4. `Add TOD bounded evidence path`
5. `Upgrade ARM chat renderer`
6. `Emit ARM communication telemetry`
7. `Add scheduled communication health watcher`

## Build Order

Use this order.

1. Task 1
2. Task 2
3. Task 3
4. Task 5
5. Task 4
6. Task 6
7. Task 7

Reason:

- first remove the wrong local authority
- then establish the MIM contract
- then render the real response
- then enrich with TOD evidence
- finally automate health checking through scheduled tasks

## Practical Conclusion

There is now a tasking list for MIM and TOD.

The immediate next step is:

- implement Task 1 and Task 2, not scheduling

The scheduled-task endpoint of this plan is:

- Task 7, after the direct ARM-to-MIM communication path is real and measurable