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
- bounded status, help, blocker, and emergency coordination exchanges

These scenarios do not validate:

- live arm motion
- production runtime safety gates
- promotion decisions
- direct writes into live shared roots

## Synthetic Root Rule

All scenarios must run against a synthetic dialog root under a test output directory.

Required policy:

- never point the harness at `192.168.1.120:/home/testpilot/mim/runtime/shared`
- never point the harness at `192.168.1.90:/home/testpilot/mim/runtime/shared`
- never point the harness at `192.168.1.90:/home/testpilot/mim_arm/runtime/shared`
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

### 4. Status Exchange Roundtrip

Goal:

- prove routine status questions do not hang unanswered

Flow:

1. TOD sends `status_request`
2. The request asks where MIM is, what happened, and what MIM is working on
3. MIM replies with `status_reply`

Pass criteria:

- MIM inbox surfaces the actionable request
- the reply clears the open expectation
- the reply includes current location and active work context

### 5. Help Offer Roundtrip

Goal:

- prove one side can offer help and get an explicit answer

Flow:

1. TOD sends `status_request` with help-offer intent
2. MIM replies with `status_reply`
3. MIM either declines help or names the support it needs

Pass criteria:

- there is no silent pending session
- the reply explicitly states whether help is needed
- requested support is structured when help is needed

### 6. Blocker Assistance Roundtrip

Goal:

- prove “I need help” and “I am stuck” become actionable, not silent

Flow:

1. MIM sends `blocker_notice`
2. TOD reads the actionable inbox
3. TOD replies with `diagnostic_reply`

Pass criteria:

- TOD inbox surfaces the blocker
- TOD acknowledges the blocker with a concrete next step
- the open reply expectation is cleared

### 7. Emergency Assistance Roundtrip

Goal:

- prove emergency coordination receives an immediate explicit response

Flow:

1. MIM sends `blocker_notice` marked as emergency
2. TOD acknowledges immediately
3. The session closes explicitly

Pass criteria:

- TOD inbox surfaces the emergency immediately
- TOD acknowledges the emergency on the same session
- the session does not remain open or ambiguous

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

The status/help/emergency scenarios must additionally assert:

- no silent hanging open reply remains after the response
- the response includes an explicit stance: status, help needed, blocker acknowledged, or emergency acknowledged

## Output Artifacts

The harness should emit:

- synthetic session logs
- synthetic session index
- scenario summary JSON
- human-readable summary markdown

Recommended output root:

- `tod/out/tests/tod-mim-conversation-simulations/<run-id>/`

Recommended soak root:

- `tod/out/tests/tod-mim-communication-soak/<run-id>/`

## Acceptance Link

This scenario spec feeds the cross-workspace signoff checklist in:

- `docs/tod-mim-communication-acceptance-checklist-2026-04-01.md`