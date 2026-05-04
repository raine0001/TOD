# TOD-MIM Communication Policy Authority

Date: 2026-04-01
Status: Active consolidation reference
Audience: TOD, MIM, operator, future maintenance chats

Purpose: define one shareable authority for all TOD to MIM communication policies, ownership boundaries, transport rules, and artifact semantics.

This document consolidates the currently active policy from the listener-stage execution contract, dialog channel, shared-state sync, operator-chat routing, state-bus boundary rules, and next-step consensus flow.

## 1. Authority Model

There is not one flat communication lane. There are multiple lanes with different authority levels.

Authority order:

1. Listener-stage execution contract
2. Explicit governance inputs to the listener
3. Dialog coordination channel
4. Shared-state projections
5. UI and operator-facing summaries
6. Synthetic/manual test writers

Policy:

- Only the listener-stage execution contract is authoritative for live bounded execution.
- Dialog is authoritative for coordination only, not execution truth.
- Shared-state is derivative and must never override live execution artifacts.
- UI is explanatory and operator-facing, not authoritative.
- Synthetic/test writers must never compete with production-like roots.

## 2. Ownership Boundary

TOD owns:

- bounded execution runtime
- ACK and terminal result emission
- execution telemetry
- local readiness and runtime health
- local guardrails, retries, and recovery behavior

MIM owns:

- cognition
- planning
- strategy meaning
- governance interpretation
- proposal generation
- adjudication intent

Cross-domain rule:

- TOD executes approved bounded actions and reports runtime facts.
- MIM interprets meaning, priority, planning, and governance.
- Neither side should silently overwrite the other's ownership boundary.

## 3. Canonical Shared Root

Canonical shared root consumed by TOD:

- `192.168.1.120:/home/testpilot/mim/runtime/shared`

Role:

- communication authority

Canonical dialog root mirrored between TOD and MIM:

- `192.168.1.120:/home/testpilot/mim/runtime/shared/dialog`

Local TOD mirrored roots:

- `tod/out/context-sync/listener`
- `tod/out/context-sync/ssh-shared`
- `shared_state/dialog`

Non-authoritative for communication truth:

- `192.168.1.90:/home/testpilot/mim/runtime/shared`
- `192.168.1.90:/home/testpilot/mim_arm/runtime/shared`
- local mirrors under `tod/out/context-sync/*`

Policy:

- If TOD and MIM disagree about current work, first verify both are reading and writing the same shared root.
- For communication truth, that shared root is only `192.168.1.120:/home/testpilot/mim/runtime/shared`.
- The Raspberry Pi at `192.168.1.90` is arm-side runtime and telemetry only; it is not a communication-authority surface.
- SSH alias or export-root drift is an upstream communication fault, not a policy exception.
- Any chat or human-facing communication surface on `192.168.1.90` must act as a thin client of MIM communication, not as an independent conversational authority. ARM-local fallback responses may only report bounded unavailability or transport failure; they must not replace MIM reasoning.

## 4. Listener-Stage Execution Contract

These are the canonical live execution artifacts.

MIM to TOD:

- `MIM_TOD_TASK_REQUEST.latest.json`
- `MIM_TO_TOD_TRIGGER.latest.json`
- `MIM_TOD_GO_ORDER.latest.json`
- `MIM_TOD_REVIEW_DECISION.latest.json`

TOD to MIM:

- `TOD_TO_MIM_TRIGGER_ACK.latest.json`
- `TOD_MIM_TASK_ACK.latest.json`
- `TOD_MIM_TASK_RESULT.latest.json`

TOD local runtime state:

- `listener_state.json`

Policy:

- One current request packet represents one bounded execution attempt.
- One current trigger packet wakes that request.
- TOD must publish acceptance and one terminal result for that same request identity.
- `listener_state.json` is local listener truth only; it is not a cross-system substitute for the request/ACK/result contract.

## 5. Request Identity And Retry Policy

Policy:

- One semantic bounded attempt maps to one stable request identity.
- Transport-noise-only changes do not create a new request.
- If MIM wants a real retry, it must issue a new semantic identity.

Valid retry changes include:

- new `request_id`
- new `task_id`
- explicit `retry_attempt`
- explicit `retry_token`

Recommended retry metadata:

- `retry_of_request_id`
- `retry_reason`
- `prior_terminal_status`

TOD behavior:

- Deduplicate duplicate semantic requests.
- Return `already_processed` for a duplicate instead of re-executing.
- Publish explicit failure or blocked status when preflight or runtime prevents execution.

## 6. ACK And Result Semantics

Policy:

- ACK proves listener receipt or accepted execution.
- ACK does not prove terminal completion.
- Result is the canonical terminal outcome.

Expected semantics:

- `TOD_TO_MIM_TRIGGER_ACK.latest.json` means transport receipt.
- `TOD_MIM_TASK_ACK.latest.json` means execution accepted.
- `TOD_MIM_TASK_RESULT.latest.json` means terminal outcome.

Consumer rule:

- MIM must not treat ACK as completion.
- TOD must emit one terminal result per bounded attempt.

## 7. Legacy And Non-Authoritative Artifacts

Legacy aliases not allowed as canonical live truth:

- `MIM_TOD_TASK_REQUEST.json`
- `MIM-TO_TOD_TRIGGER.latest.json`

Artifacts explicitly not authoritative for live execution:

- `task.json`
- `tasks.json`
- `shared_state/integration_status.json`
- `shared_state/next_actions.json`
- `TOD_MIM_COMMAND_STATUS.latest.json`
- `TOD_LOOP_JOURNAL.latest.json`
- `shared_state/dialog/*`

Policy:

- These artifacts may explain or project state.
- They must not replace canonical request, ACK, or result truth.
- Derived files must not pin the current live objective or current live request.

## 8. Dialog Channel Policy

The dialog channel is the bounded coordination lane between TOD and MIM.

Canonical files:

- `shared_state/dialog/MIM_TOD_DIALOG.latest.jsonl`
- `shared_state/dialog/MIM_TOD_DIALOG.session-<session_id>.jsonl`
- `shared_state/dialog/MIM_TOD_DIALOG.session-<session_id>.latest.json`
- `shared_state/dialog/MIM_TOD_DIALOG.sessions.latest.json`

Supported message types:

- `diagnostic_query`
- `diagnostic_reply`
- `status_request`
- `status_reply`
- `blocker_notice`
- `resolution_notice`
- `handoff_request`
- `handoff_response`

Policy:

- Dialog is for asking, explaining, blocking, resolving, or handing off reasoning.
- Dialog is not for executing work or bypassing listener-stage execution governance.
- One open reply expectation is allowed at a time per session.
- A `resolution_notice` can explicitly close or supersede a session.
- `MIM_TOD_DIALOG.latest.jsonl` is append-only history, not the authoritative actionable inbox.
- The authoritative actionable view is `MIM_TOD_DIALOG.sessions.latest.json` plus the referenced session log.

Read order for a recipient:

1. `MIM_TOD_DIALOG.sessions.latest.json`
2. target `session-<session_id>.jsonl`
3. only then consult `MIM_TOD_DIALOG.latest.jsonl` for history if needed

## 9. TOD Next-Step Consensus Policy

TOD now routes post-run next-step adjudication through the dialog lane.

Canonical TOD-side artifacts:

- `shared_state/tod_codex_next_steps.latest.json`
- `shared_state/NEXT_STEP_CONSENSUS.latest.json`
- `shared_state/NEXT_STEP_POLICY.latest.json`

Policy:

- Chat prose is not authority for next actions.
- Candidate next actions become structured findings.
- TOD publishes its local positions.
- MIM must answer through dialog with `handoff_response` on the same session.
- Consensus stays `pending_mim` until MIM publishes `finding_positions`.
- Phase 1 remains recommendation-only even when a low-risk class is eligible for `auto_execute`.

Required MIM reply payload fields:

- `summary`
- `finding_positions[].finding_id`
- `finding_positions[].decision`
- `finding_positions[].reason`
- `finding_positions[].confidence`
- `finding_positions[].local_blockers`

Reminder policy:

- If MIM does not answer in time, TOD sends a same-session `status_request` reminder.
- Reminder does not replace the original handoff request.
- Reminder is coordination only; it does not reopen or reinterpret execution truth.

## 10. Operator-Chat And Proposal Policy

Operator-chat is a governed explanatory surface, not a second execution plane.

Policy:

- TOD routes operator-chat questions to MIM first when MIM is the primary source for updates or next-step guidance.
- MIM proposals can be shown, compared, arbitrated, merged, acknowledged, and closed within existing governed TOD surfaces.
- Proposal handling must not create a parallel execution control plane.
- Suggested actions may include MIM-tagged or proposal-aware metadata, but execution still flows through the authoritative listener or adjudication contracts.

Operational rule:

- Operator-chat can explain proposal conflict, arbitration, merge posture, acknowledgment, and closure.
- Operator-chat must not override listener-stage or adjudication artifacts.

## 11. Standing Synthetic Communication Gate

The synthetic TOD to MIM conversation harness is promoted as a standing regression gate for communication-contract integrity.

Canonical TOD gate command:

- `.\scripts\Invoke-TODMimCommunicationContractGate.ps1 -EmitJson`

Gate scope:

- synthetic-only
- dialog and adjudication contract coverage only
- same-session reply expectation handling
- actionable inbox and session-index semantics
- next-step consensus, reminder, and supersede/reissue behavior

Explicit non-scope:

- live listener execution validation
- request, trigger, ACK, and result execution-lane certification
- production-like shared root mutation

Policy:

- This gate is required as a regular regression and CI lane for communication-contract integrity.
- This gate must remain small, deterministic, and cheap to run.
- This gate must report as TOD<->MIM communication contract pass or fail.
- This gate must not be described as live runtime validation.
- Execution-lane validation remains a separate contract and must be promoted separately.

## 12. Standing Synthetic Execution Gate

The synthetic TOD to MIM execution harness is promoted as a standing regression gate for listener-stage execution-contract integrity.

Canonical TOD gate command:

- `.\scripts\Invoke-TODMimExecutionContractGate.ps1 -EmitJson`

Gate scope:

- synthetic-only
- listener-stage execution lane only
- canonical request, trigger ACK, task ACK, and task result semantics
- request accepted once, ACK once, RESULT once
- duplicate semantic request deduplication
- stale backfill rejection
- superseded request handling
- wrong-target rejection

Explicit non-scope:

- live SSH listener validation
- dialog routing, actionable inbox, and adjudication semantics
- production-like shared root mutation

Policy:

- This gate is required as a regular regression and CI lane for execution-contract integrity.
- This gate must remain small, deterministic, and cheap to run.
- This gate must report as TOD<->MIM execution contract pass or fail.
- This gate must not be described as live runtime validation.
- Dialog and adjudication validation remains a separate contract and must stay promoted separately.

## 13. Shared-State Projection Policy

Shared-state exists to provide durable cross-session handoff projections.

Examples:

- `shared_state/integration_status.json`
- `shared_state/next_actions.json`
- `shared_state/current_build_state.json`
- `shared_state/contracts.json`
- `shared_state/execution_evidence.json`

Policy:

- Shared-state is machine-readable and durable.
- Shared-state is a projection, not live execution authority.
- Shared-state should summarize and hand off, not pin or mutate the live task lane.
- MIM may consume shared-state as coordination context, but not as a substitute for canonical listener-stage or dialog session truth.

## 14. Unified State Bus And Event Boundary

State-bus and execution-event artifacts are runtime telemetry and handoff boundaries.

Policy:

- TOD publishes execution/runtime reliability signals only.
- MIM remains owner of cognition, strategy, meaning, planning, memory, and governance.
- Bus events are append-only transient execution telemetry.
- `shared_state/*` remains the durable coordination and handoff surface.

Bus/event rule:

- TOD event streams report runtime facts.
- They must not infer strategy or governance semantics that belong to MIM.

## 15. Recovery And Watchdog Policy

Supervisory scripts can inspect freshness, health, and bridge progression.

Policy:

- Recovery and watchdog lanes are supervisory only.
- They may restart writers or emit notices.
- They are not the source of truth for active task identity.
- If ACK and result match the live request, diagnose action/runtime failure before restarting the listener again.

## 16. Synthetic And Manual Writer Policy

Synthetic tools include smoke tools, result pushers, and tmp helper scripts.

Policy:

- Synthetic or manual tools must be isolated from production-like roots.
- They must not share the same canonical namespace as the live listener unless explicitly running in a test root.
- If synthetic writers share the live namespace, they become competing authorities and invalidate trust in the channel.

## 17. What MIM Should Look At First

When MIM needs current actionable TOD communication, read in this order:

1. `MIM_TOD_DIALOG.sessions.latest.json` for actionable dialog sessions
2. the referenced `session-<session_id>.jsonl` for the active request and current turn
3. canonical listener-stage artifacts for live execution truth
4. shared-state projections for operator-facing or cross-session context
5. append-only aggregate logs only for history or audits

For the next-step consensus lane specifically, MIM should look for:

- a session with `status = awaiting_reply`
- `open_reply.to = MIM`
- `message_type = handoff_request`
- `intent = next_step_consensus`

## 16. What TOD Should Look At First

When TOD needs current MIM-origin live execution truth, read in this order:

1. `MIM_TOD_TASK_REQUEST.latest.json`
2. `MIM_TO_TOD_TRIGGER.latest.json`
3. explicit governance inputs like go-order and review-decision
4. dialog session files for coordination, explanation, and adjudication only
5. shared-state projections for operator summary only

## 17. Operational Do And Do Not Rules

Do:

- treat listener-stage request/ACK/result as live execution authority
- treat dialog session index plus session log as the actionable coordination inbox
- treat shared-state as derivative coordination context
- publish explicit terminal results
- publish dialog replies on the same session when a reply is requested
- use a new semantic request identity for true retries

Do not:

- use append-only aggregate dialog history as the primary inbox
- let `next_actions.json` or other projections pin live task identity
- use operator-chat as an execution bypass
- treat ACK as completion
- create a new session to answer an existing request unless policy explicitly requires it
- let synthetic writers share the canonical live namespace

## 18. Current Canonical Source Files Behind This Consolidation

- `docs/tod-mim-communication-audit-2026-04-01.md`
- `docs/tod-mim-communication-plan-2026-03-31.md`
- `docs/mim-tod-dialog-channel-v1.md`
- `docs/mim-tod-execution-feedback-contract-v1.md`
- `docs/tod-shared-state-sync-v1.md`
- `docs/tod-state-bus-contract-v1.md`
- `docs/tod-unified-state-bus-execution-events-v1.md`
- `docs/tod-operator-chat-console-v3-objective87.md`
- `scripts/Start-TODMimPacketListener.ps1`
- `scripts/Invoke-TODMimDialog.ps1`
- `scripts/Invoke-TODSharedStateSync.ps1`
- `scripts/Resolve-TODNextStepConsensus.ps1`

## 19. Shareable Short Version For MIM

Use this verbatim if needed:

"For TOD↔MIM communication, live bounded execution authority is only the listener-stage contract: request, trigger, ACK, and terminal result artifacts. Dialog sessions are the bounded coordination and adjudication channel and must be read from the session index plus the referenced session log, not from the aggregate history log. Shared-state and UI are derivative context only. MIM owns cognition, planning, and governance; TOD owns execution runtime, ACK/result emission, and runtime telemetry. For next-step consensus, answer the open `handoff_request` on the same dialog session with a `handoff_response` containing `summary` and `finding_positions`. Do not ask the operator for next steps when TOD and MIM can decide through the open session; continue based on the TOD-MIM decision." 