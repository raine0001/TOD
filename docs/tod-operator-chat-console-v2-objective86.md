# TOD Operator Chat Console v2

## Objective 86

Objective 86 adds governed action confirmation and audit on top of the read-only operator console delivered by Objective 85.

The design goal is to keep the operator experience conversational while ensuring every mutating action stays bounded, explainable, and auditable.

Status after closure pass: trusted layer candidate. Objective 86 now includes prod-like restart validation, explicit failure-mode documentation, and durable reasoning linkage for every governed audit event.

## Scope

- Preserve Objective 85 as the default mode: explanation first, execution never implicit.
- Introduce a small allow-list of governed actions that reuse existing safe TOD control paths.
- Require explicit operator confirmation before any mutating action is dispatched.
- Record an auditable action trail with actor, time, intent, rationale, and outcome.
- Explain why an action is allowed, deferred, or blocked.
- Link every audit entry to the reasoning bundle that justified it.

## Non-Goals

- No arbitrary shell execution.
- No free-form command construction.
- No bypass of existing `/api/run` or UI-safe control paths.
- No automatic restart loops triggered only by chat text.

## Current Governed Allowlist

- `get-reliability`
- `get-state-bus`
- `get-engineering-loop-summary`
- `get-engineering-signal`
- `show-reliability-dashboard`
- `refresh-share-links`
- `quick-refresh-reliability`
- `refresh-project-status`
- `recheck-bridge-diagnostics`
- `refresh-governance-snapshot`
- `refresh-bridge-alignment-bundle`

Observe-only recommendations such as `wait` remain intentionally blocked from confirmation.

## Required UX

- Action suggestion remains separate from action confirmation.
- Confirmation prompt must state:
  - exact action name
  - why TOD is recommending it
  - evidence posture and staleness flags
  - expected impact
  - rollback or follow-up expectation when applicable
- Blocked actions must return a structured explanation instead of silent failure.

## Initial Endpoint

- `POST /api/operator-chat-action`
- phases:
  - `preview`
  - `confirm`

The endpoint must:

- validate the action against the governed allowlist
- explain allow or block reasoning
- require confirmation before execution
- reuse only bounded existing control paths or read-only server composites
- return structured outcome details for chat rendering

## Preview Lifecycle Hardening

- `preview_id` is now server-tracked, not only client-held.
- Previews expire after a bounded TTL.
- Confirm requests must match the original preview on:
  - action
  - intent
  - objective scope
  - query
  - mode
  - operator identity
- Confirmed previews are single-use and replay attempts return structured `invalid_preview` responses.
- Unsupported phases return structured `invalid_request` responses.

## Response Additions

Potential additions for Objective 86:

- `response.allowed_actions[]`
- `response.blocked_actions[]`
- `response.confirmation_required`
- `response.action_reasoning`
- `response.audit_reference`

## Audit Trail

Each governed action should capture:

- operator-visible action label
- canonical action id
- triggering intent
- objective id in scope
- evidence posture flags
- confirmation timestamp
- execution timestamp
- outcome status
- outcome summary

Current Objective 86 audit artifacts:

- `shared_state/tod_operator_chat_action_audit.log.jsonl`
- `shared_state/tod_operator_chat_action_audit.latest.json`
- `shared_state/tod_operator_chat_reasoning.log.jsonl`
- `shared_state/tod_operator_chat_reasoning.latest.json`

Audit inspection endpoint:

- `GET /api/operator-chat-action-audit?limit=N`
- Optional filter: `preview_id`

Reasoning inspection endpoint:

- `GET /api/operator-chat-action-reasoning?bundle_id=<id>&limit=N`

Each audit entry now includes:

- `reasoning_bundle_id`
- optional `commitment_id` when the operator committed before execution

Each reasoning bundle captures:

- policy allow or block rationale
- suggested reason shown to the operator
- confirmation rationale
- expected impact
- linked structured evidence
- linked dashboard citations
- safe alternatives when the action is blocked or deferred

Trust-chain inspection endpoint:

- `GET /api/operator-chat-action-trust-chain`

The trust-chain endpoint resolves:

- selected audit entry
- linked reasoning bundle
- linked commitment records
- linked structured evidence count and citations

The dashboard now exposes the latest governed audit entries inline so operators can correlate preview IDs, audit IDs, phase, and outcome without opening raw files.

The audit endpoint now also supports bounded operator filtering by:

- `action`
- `outcome_status`
- `phase`
- `preview_id`
- `search`

## Policy Table

| Action | Mode | Confirmation | Expected Impact | UI Refresh Target |
| --- | --- | --- | --- | --- |
| `get-reliability` | `read_only` | required | Refresh reliability snapshot | action workspace + audit |
| `get-state-bus` | `read_only` | required | Refresh state bus snapshot | state bus + audit |
| `get-engineering-loop-summary` | `read_only` | required | Refresh engineering loop summary | action workspace + audit |
| `get-engineering-signal` | `read_only` | required | Refresh engineering signal | action workspace + audit |
| `show-reliability-dashboard` | `read_only` | required | Refresh reliability dashboard payload | action workspace + audit |
| `refresh-share-links` | `ui_refresh_only` | required | Refresh share artifact availability | share artifacts + audit |
| `quick-refresh-reliability` | `ui_refresh_only` | required | Refresh status, logs, and share artifacts | status + logs + share artifacts + audit |
| `refresh-project-status` | `read_only` | required | Re-read project status payload | project status + audit |
| `recheck-bridge-diagnostics` | `read_only` | required | Recompute bridge explanation | project status + audit |
| `refresh-governance-snapshot` | `read_only` | required | Refresh governance evidence bundle | project status + share artifacts + state bus + audit |
| `refresh-bridge-alignment-bundle` | `read_only` | required | Refresh bridge evidence, artifacts, and state bus posture | project status + share artifacts + state bus + audit |

## Safety Gates

- Listener or bridge fallback must be surfaced before confirmation.
- High-staleness evidence should bias toward observe-first actions.
- If no bounded control path exists, the console must stay read-only and explain why.

## Failure Modes

The trusted-layer closure explicitly documents the failure modes Objective 86 must preserve:

1. `invalid_preview`

- confirm request references an expired, missing, mismatched, or already-consumed preview
- required operator response: request a new preview instead of retrying execution blindly

1. `invalid_request`

- request phase or contract fields are unsupported
- required operator response: stay within the preview or confirm contract

1. `blocked`

- action is outside the allowlist or observe-only posture prevents confirmation
- required operator response: inspect policy reasoning and use safe alternatives

1. `failed`

- policy check passed but the bounded control path threw during execution
- required operator response: inspect the failure summary, refresh evidence, then request a fresh preview if retry is still justified

1. stale host during promotion

- UI HTML can reflect a newer build while the PowerShell backend still serves older in-memory routes
- required mitigation: recycle the live `Start-TOD-UI.ps1` host before trusting validation output

## Readiness Note

Objective 86 is ready for promotion when all of the following are true in a restarted prod-like host:

- all allowlisted actions preview and confirm successfully
- `wait` remains blocked with explicit policy reasoning
- preview expiry, replay protection, mismatched confirmation, and invalid phase all return structured contract responses
- audit filtering remains correct
- every audited event links to a durable reasoning bundle with structured evidence
- operator commitment records can be captured and inspected without bypassing preview or confirm

## Validation Status

Live validation on 2026-03-24 against `http://localhost:8844/` confirmed:

- build `2026.03.24-b20`
- audit panel filters for action, outcome, phase, and search query against the live audit endpoint
- trust-chain inspector panel resolves audit, reasoning, commitment, and evidence together from a governed action row
- all allowlisted governed actions preview and confirm successfully
- blocked `wait` previews return explicit allow/block reasoning plus safe alternatives
- invalid preview, replay, and invalid phase cases return structured contract responses
- audit inspection endpoint returns the latest governed action events
- reasoning inspection endpoint returns the linked bundle for the latest audit event and that bundle contains structured evidence
- operator commitment capture returns durable committed, timeboxed, and evidence-bound records linked to the same preview and reasoning bundle

## Implementation Order

1. Add action confirmation schema and UI scaffold.
2. Add blocked-vs-allowed reasoning contract.
3. Add audit persistence for governed actions.
4. Enable the smallest safe action set first.
5. Validate every allowed action against live operator-chat evidence posture.

## Objective 86.1

Objective 86.1 is a refinement, not a new execution surface.

It adds audit to reasoning linkage so the trusted chain is:

`action execution -> audit entry -> reasoning bundle -> evidence`

That allows TOD to explain not only what happened, but why it was allowed.
