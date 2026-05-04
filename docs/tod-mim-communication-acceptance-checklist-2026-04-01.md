# TOD-MIM Communication Acceptance Checklist

Date: 2026-04-01
Status: Active cross-workspace signoff checklist

Purpose: provide one bounded checklist TOD and MIM can use to confirm the communication method is implemented, aligned, and stable.

## Shared Root

- TOD and MIM agree on the canonical shared root.
- TOD and MIM agree on the canonical dialog root.
- Both sides can prove they are reading the same actionable session index.

## Listener-Stage Execution

- MIM publishes only canonical live request and trigger artifacts.
- TOD emits canonical trigger ACK, task ACK, and task result artifacts.
- ACK is not treated as completion.
- Duplicate semantic requests are deduplicated.
- Real retries use a new semantic request identity.

## Dialog Channel

- Both sides use the session index as the actionable inbox.
- Both sides use the referenced session log as the active transcript.
- Neither side uses the aggregate dialog log as the primary inbox.
- Same-session replies clear open reply expectations correctly.
- Resolution notices can supersede stale requests correctly.

## Next-Step Consensus

- TOD publishes structured findings.
- TOD opens `handoff_request` with `intent = next_step_consensus`.
- MIM replies with same-session `handoff_response`.
- MIM reply includes `summary` and `finding_positions`.
- TOD resolves consensus deterministically after the reply.
- Recommendation-only policy remains bounded unless a later phase explicitly changes it.

## Synthetic Harness

- Diagnostic roundtrip passes.
- Next-step consensus roundtrip passes.
- Supersede and reissue roundtrip passes.
- Status exchange roundtrip passes.
- Help offer roundtrip passes.
- Blocker assistance roundtrip passes.
- Emergency assistance roundtrip passes.
- Harness runs only against synthetic roots.
- Harness does not write into live shared roots.
- Communication soak reaches the target iteration count with zero failed iterations.

## Operator And Projection Boundaries

- Shared-state remains derivative only.
- Operator-chat remains explanatory/governed only.
- Proposal handling does not create a second execution plane.

## Signoff

- TOD side signed off.
- MIM side signed off.
- Cross-workspace simulation artifacts archived.
- Current single-source policy reference acknowledged:
  - `docs/tod-mim-communication-policy-authority-2026-04-01.md`