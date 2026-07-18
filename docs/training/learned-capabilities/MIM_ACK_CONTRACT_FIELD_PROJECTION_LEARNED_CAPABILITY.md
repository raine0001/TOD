# Learned Capability: MIM ACK Contract Field Projection

## Capability Name

MIM ACK Contract Field Projection

## Trigger

TOD sends a dialog request that asks MIM for specific acknowledgement or response-contract fields, and MIM replies with generic status, a finding-position-only decision, or a transport receipt that does not include the requested fields.

## Reality

The dialog transport can be healthy while the response contract is still incomplete. A resolved session is not enough when the caller asked for decision-quality ACK fields.

## Observation

TOD observed that MIM replied to `tod-mim-semantic-audit-body-final-proof-001` with an approval inside `finding_positions`, but omitted requested ACK fields including `received`, `owner`, `expected_evidence`, `blocker_state`, and `continuation_action`.

After repair and restart, TOD sent `tod-mim-ack-contract-projection-proof-001`. MIM replied in the same session with the requested fields at both response envelope and payload scope:

- `received=true`
- `decision=blocked`
- `owner=MIM`
- `expected_evidence`
- `blocker_state=blocked`
- `continuation_action=repair_ack_contract_projection`
- `blocker_class=response_contract_gap`
- `smallest_repair_step`

TOD then observed that `tod-mim-ack-contract-projection-resolution-001` remained `awaiting_reply` because the responder only scanned `handoff_request` and `status_request` messages. After the generic requires-reply repair, the same resolution notice closed with `received`, `decision`, `owner`, `expected_evidence`, `blocker_state`, and `continuation_action` present at envelope and payload scope.

## Root Cause

`core/next_step_dialog_service.py` handled some response-contract fields for handoff finding positions, but `status_response` generation could fall through to generic task/system status without projecting caller-requested ACK fields into the response envelope. The responder loop also only discovered `handoff_request` and `status_request`, so other valid TOD messages with `requires_reply=true` could remain stranded.

## Blocker Class

coordination/protocol blocker

## Decomposition Ladder

Level 1: Prove delivery and session closure.

Level 2: Inspect the same-session MIM reply for requested fields instead of counting any reply as success.

Level 3: Identify whether fields are missing at envelope scope, payload scope, or only per-finding scope.

Level 4: Repair protocol field projection generically from `requested_mim_response_fields` and `response_contract.required_ack_fields`.

Level 5: Restart the consumer that owns the dialog response path.

Level 6: Send a fresh live request and validate field presence from the same session transcript.

Level 7: Send a non-status protocol message with `requires_reply=true` and validate it receives the same ACK-field projection instead of going stale.

## Smallest Successful Rung

A fresh `status_request` with required ACK fields returned a same-session `status_response` containing every requested field at both envelope and payload scope. A previously stranded `resolution_notice` with `requires_reply=true` also closed after the generic fallback repair.

## Implementation Summary

Added generic ACK-field projection helpers to `core/next_step_dialog_service.py` and applied them to both handoff and status responses. Added a generic pending-request fallback for TOD messages that set `requires_reply=true` but are not specialized handoff/status requests. The repair derives fields from the request payload and summary context; it does not hardcode one phrase or one operator request.

## Validation

- Local Python compile passed for `tmp_remote_mim/core/next_step_dialog_service.py` and `tmp_remote_mim/tests/test_next_step_dialog_service.py`.
- Focused local ACK projection smoke passed.
- Remote Python compile passed on `/home/testpilot/mim`.
- `mim-watch-tod-dialog-inbox-consumer.service` restarted and reported active.
- Live dialog session `tod-mim-ack-contract-projection-proof-001` resolved with all requested ACK fields.
- Live dialog session `tod-mim-ack-contract-projection-resolution-001` changed from `awaiting_reply` to `resolved` after the generic requires-reply repair, with no missing top-level or payload ACK fields.

## General Rule Learned

Communication completion requires contract closure, not just message delivery. If a caller requests acknowledgement fields, the responder must project those fields explicitly or report which field cannot be supplied and why.

## Prevention Rule

Do not mark a MIM/TOD dialog resolved solely because MIM sent a reply. Validate the required ACK fields from the same session transcript. Also reject any `requires_reply=true` dialog message that has no responder discovery path.

## Reuse Trigger

Use this capability whenever a MIM/TOD interaction says `resolved`, `approved`, `acknowledged`, or `done`, but the response lacks requested owner, evidence, blocker, continuation, or decision fields. Also use it when a non-status dialog message remains open even though it explicitly requires a reply.

## Dependent Capabilities

- Conversation coordination closure
- Response-contract validation
- Dialog session readback
- Protocol-compatible generic field projection

## Capability Confidence

0.78

## Independent Pass Rate

Scaffolded live pass complete. Independent unseen pass pending.

## Date Frozen

2026-07-13

## Generalized Principle

A protocol responder must preserve the caller's contract across all response modes. Generic status text may be useful context, but it cannot replace requested structured acknowledgement fields.
