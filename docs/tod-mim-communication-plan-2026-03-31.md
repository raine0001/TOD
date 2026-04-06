# TOD MIM Communication Plan

Date: 2026-03-31

Purpose: prevent stale task identities, duplicate retries, and non-closing bounded executions across the TOD listener, UI summaries, and MIM dispatch layer.

## 1. Live authority chain

- Live task authority is the listener stage, in this order:
  - `tod/out/context-sync/listener/listener_state.json`
  - `tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json`
  - `tod/out/context-sync/listener/TOD_MIM_TASK_ACK.latest.json`
  - `tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json`
- UI summaries and operator-chat may include historical proposal rows, but they must not override the live listener stage when reporting the active task.

## 2. Identity rules

- One bounded execution attempt maps to one semantic request identity.
- TOD deduplicates reissues that only change transport noise fields such as:
  - `generated_at`
  - `emitted_at`
  - `sequence`
  - `source_instance_id`
  - `source_service`
- If MIM needs TOD to retry a failed bounded action, MIM must issue a new semantic request, not just a fresh timestamp.

## 3. Retry contract

- Valid retry signals must change one of the following:
  - `request_id`
  - `task_id`
  - explicit `retry_attempt`
  - explicit `retry_token`
- Retry requests should also include:
  - `retry_of_request_id`
  - `retry_reason`
  - `prior_terminal_status`
- Without one of those semantic changes, TOD should treat the request as a duplicate and report `already_processed` rather than executing it again.

## 4. ACK contract

- TOD must ACK every accepted bounded request with:
  - `request_id`
  - `task_id`
  - `correlation_id`
  - `status`
  - `bridge_runtime.current_processing`
- MIM should treat ACK as proof of listener receipt, not proof of terminal completion.

## 5. Result contract

- TOD must emit one terminal result for each bounded execution attempt.
- Terminal result must include:
  - `request_id`
  - `task_id`
  - `status`
  - `error`
  - `execution_mode`
  - readiness and validation context when available
- If TOD cannot execute the action because the action is unsupported, blocked, or fails preflight, the result should say that directly so MIM can decide between fix, retry, or escalation.

## 6. Failure triage rule

- If ACK and result point at the current live request, the listener is healthy.
- In that case, triage the action implementation or remote runtime rather than restarting the listener repeatedly.
- Restart the listener only when live request observation or ACK/result mutation has actually stalled.

## 7. UI reporting rule

- UI and operator-chat should separate:
  - current live request
  - latest terminal result
  - recent historical proposals
- Historical proposal ids can be shown as context, but `current_processing` and live proposal summaries must follow the active request in listener state.

## 8. Operator wording rule

- When MIM and TOD are aligned on the same objective, communication should say MIM is bounded context for the active TOD objective.
- Recommended next steps should clearly distinguish between:
  - implement the bounded action
  - ask MIM for an explicit retry
  - refresh status only

## 9. Practical application to objective 97

- `objective-97-task-3422` is historical context.
- `objective-97-task-mim-arm-safe-home-207749` is the live bounded request.
- If 207749 fails terminally, MIM must send a new semantic retry request after the failure cause is fixed.
- Replaying 207749 without a semantic retry change should be treated as duplicate traffic, not new work.

## 10. Coordination layer

- The execution contract remains artifact-based:
  - request
  - trigger
  - ACK
  - result
  - review
  - command status
- A separate dialog layer is now the preferred channel for bridge coordination that does not itself execute work.
- Dialog should be used for:
  - clarifying stale evidence
  - asking which source path is authoritative
  - reporting blockers
  - confirming root cause and remediation
- Dialog must not be used to bypass approval or trigger execution.
- Baseline dialog contract lives in [docs/mim-tod-dialog-channel-v1.md](./mim-tod-dialog-channel-v1.md).