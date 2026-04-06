# MIM-TOD Dialog Channel v1

Date: 2026-03-31

Purpose: add a bounded coordination channel between MIM and TOD for diagnostic and status-turn exchange without abusing execution artifacts.

## Scope

This channel is for:

- diagnostic questions
- diagnostic replies
- status requests
- status replies
- blocker notices
- resolution notices
- handoff reasoning

This channel is not for:

- executing actions
- bypassing approval or governance
- replacing request, ACK, result, review, or command-status artifacts
- open-ended conversation without correlation to a task or bridge issue

## Files

- Aggregate append-only log:
  - `shared_state/dialog/MIM_TOD_DIALOG.latest.jsonl`
- Session append-only logs:
  - `shared_state/dialog/MIM_TOD_DIALOG.session-<session_id>.jsonl`
- Session state snapshots:
  - `shared_state/dialog/MIM_TOD_DIALOG.session-<session_id>.latest.json`
- Session index snapshot:
  - `shared_state/dialog/MIM_TOD_DIALOG.sessions.latest.json`

## Contract

Each line in a session log and the aggregate log is one JSON object.

Required fields:

```json
{
  "session_id": "mim-tod-bridge-001",
  "turn_id": 14,
  "timestamp": "2026-03-31T10:05:00Z",
  "from": "MIM",
  "to": "TOD",
  "message_type": "diagnostic_query",
  "intent": "listener_state_clarification",
  "correlation_id": "obj97-task207749",
  "task_id": "objective-97-task-mim-arm-safe-home-207749",
  "summary": "Your ACK/result are still pinned to 3422. Can you confirm current_processing source?",
  "payload": {
    "observed_ack_task_id": "objective-97-task-3422",
    "observed_result_task_id": "objective-97-task-3422"
  },
  "requires_reply": true,
  "schema_version": "mim-tod-dialog-v1"
}
```

Supported `message_type` values:

- `diagnostic_query`
- `diagnostic_reply`
- `status_request`
- `status_reply`
- `blocker_notice`
- `resolution_notice`
- `handoff_request`
- `handoff_response`

## Rules

- One append-only line per message.
- One open reply expectation at a time per session.
- `requires_reply = true` marks the current turn as waiting on the recipient.
- A reply closes the open expectation when it comes from the expected recipient to the original sender on a later turn.
- Messages must stay bounded in size.
- Sessions close by explicit `resolution_notice` or inactivity timeout in the session-state snapshot.
- Execution must still flow through request, ACK, result, review, and command-status artifacts.

## Session State

The `.latest.json` session-state snapshot records:

- current session status
- whether a reply is open
- last message summary
- path to the session transcript
- timeout classification if a session has been left open too long

Session status values:

- `idle`
- `awaiting_reply`
- `timed_out`
- `resolved`
- `closed`

## First TOD Baseline Tool

Use [scripts/Invoke-TODMimDialog.ps1](../scripts/Invoke-TODMimDialog.ps1) to operate on the channel.

Supported actions:

- `send`
- `read-session`
- `read-inbox`
- `get-session-status`
- `close-session`

## Examples

Send a diagnostic query from MIM to TOD:

```powershell
./scripts/Invoke-TODMimDialog.ps1 \
  -Action send \
  -SessionId mim-tod-bridge-001 \
  -Actor MIM \
  -PeerActor TOD \
  -MessageType diagnostic_query \
  -Intent listener_state_clarification \
  -TaskId objective-97-task-mim-arm-safe-home-207749 \
  -CorrelationId obj97-task207749 \
  -Summary "Your ACK/result are still pinned to 3422. Can you confirm current_processing source?" \
  -PayloadJson '{"observed_ack_task_id":"objective-97-task-3422","observed_result_task_id":"objective-97-task-3422"}' \
  -RequiresReply
```

Reply from TOD:

```powershell
./scripts/Invoke-TODMimDialog.ps1 \
  -Action send \
  -SessionId mim-tod-bridge-001 \
  -Actor TOD \
  -PeerActor MIM \
  -MessageType diagnostic_reply \
  -Intent listener_state_clarification \
  -TaskId objective-97-task-mim-arm-safe-home-207749 \
  -CorrelationId obj97-task207749 \
  -Summary "Current ACK writer is still sourcing from stale listener journal path. Patching now." \
  -PayloadJson '{"root_cause":"stale_writer_source","next_action":"patch_ack_writer"}'
```

Read TOD inbox:

```powershell
./scripts/Invoke-TODMimDialog.ps1 -Action read-inbox -Actor TOD
```

Close the session:

```powershell
./scripts/Invoke-TODMimDialog.ps1 \
  -Action close-session \
  -SessionId mim-tod-bridge-001 \
  -Actor TOD \
  -PeerActor MIM \
  -TaskId objective-97-task-mim-arm-safe-home-207749 \
  -CorrelationId obj97-task207749 \
  -Summary "Root cause isolated and execution artifacts are rotating correctly again." \
  -PayloadJson '{"resolution":"listener_source_corrected"}'
```

## Adoption Guidance

- Keep dialog tied to a concrete task or bridge incident.
- Keep execution decisions in the execution contract.
- Use dialog to explain, ask, and confirm.
- Persist every turn so the transcript is durable and inspectable.