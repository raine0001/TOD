# TOD-MIM Conversation Simulation Scenarios

Date: 2026-04-01
Status: Active synthetic integration harness spec

Purpose: define the bounded scenario set used to rehearse TOD↔MIM communication against synthetic roots so policy and transport behavior can be verified without touching live shared roots.

## Scope

These scenarios validate:

- dialog session routing
- reply expectation handling
- next-step consensus request and response flow
- reminder behavior
- supersede and reissue semantics
- inbox/index semantics for actionable sessions

These scenarios do not validate:

- live arm motion
- production runtime safety gates
- promotion decisions
- direct writes into live shared roots

## Synthetic Root Rule

All scenarios must run against a synthetic dialog root under a test output directory.

Required policy:

- never point the harness at `/home/testpilot/mim/runtime/shared`
- never point the harness at production-like `shared_state/dialog`
- never let simulation writers compete with live canonical artifacts

## Scenario Catalog

### 1. Diagnostic Roundtrip

Goal:

- prove the basic dialog lane works end to end

Flow:

1. TOD sends `diagnostic_query`
2. MIM reads actionable inbox
3. MIM replies with `diagnostic_reply`
4. TOD closes with `resolution_notice`

Pass criteria:

- the session opens with one reply expectation
- MIM inbox surfaces the session while it is actionable
- the reply clears the open expectation
- the close step marks the session `closed`

### 2. Next-Step Consensus Roundtrip

Goal:

- prove structured next-step adjudication works end to end

Flow:

1. TOD creates a synthetic findings artifact
2. TOD runs `Resolve-TODNextStepConsensus.ps1` against a synthetic dialog root
3. TOD publishes `handoff_request`
4. MIM replies with same-session `handoff_response`
5. TOD reruns consensus resolution

Pass criteria:

- the synthetic session index shows `awaiting_reply`
- the active request is a `handoff_request` with `intent = next_step_consensus`
- MIM replies on the same session
- consensus becomes `consensus_ready`
- the selected finding is deterministic

### 3. Supersede And Reissue Roundtrip

Goal:

- prove a stale or wrong request can be explicitly closed and replaced without corrupting session state

Flow:

1. TOD sends an initial `handoff_request`
2. TOD sends `resolution_notice` with supersede intent
3. TOD sends a new `handoff_request` on the same session
4. MIM replies to the reissued request

Pass criteria:

- the supersede notice clears the original open reply expectation
- the reissued request becomes the new actionable open reply
- MIM can answer the reissued request without creating a new session

## Required Assertions

Each scenario must assert:

- session index semantics
- session transcript correctness
- message ordering by turn
- expected `message_type`
- expected `intent`
- expected open reply state
- expected terminal session status

The next-step consensus scenario must additionally assert:

- `summary`
- `finding_positions`
- decision values per finding
- deterministic consensus output

## Output Artifacts

The harness should emit:

- synthetic session logs
- synthetic session index
- scenario summary JSON
- human-readable summary markdown

Recommended output root:

- `tod/out/tests/tod-mim-conversation-simulations/<run-id>/`

## Acceptance Link

This scenario spec feeds the cross-workspace signoff checklist in:

- `docs/tod-mim-communication-acceptance-checklist-2026-04-01.md`