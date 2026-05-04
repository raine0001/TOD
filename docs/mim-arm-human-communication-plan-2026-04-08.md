# MIM ARM Human Communication Plan

Date: 2026-04-08

## Objective

Make the MIM ARM UI at `192.168.1.90` a reliable human-facing communication surface by tying it directly to MIM communication, instead of allowing the ARM host to behave like an independent weak conversational agent.

## Current Problem

Observed behavior on the MIM ARM web UI shows a local chat surface that responds with low-value fallback language such as “I'm still learning. Could you rephrase that?”

That is the wrong authority model.

- `192.168.1.90` is an arm-side runtime and telemetry host.
- It is not the authoritative communication host.
- Human-facing conversation quality should come from MIM cognition and bounded MIM/TOD coordination, not from a shallow ARM-local fallback responder.

## Architecture Rule

The MIM ARM chat panel should be treated as a thin human interface.

- Human message enters on MIM ARM UI.
- Message is routed to MIM communication logic.
- MIM produces the primary response.
- TOD contributes execution/runtime evidence only when the response needs TOD-grounded status, bounded action posture, or coordination context.
- ARM UI renders the resulting response, confidence, evidence posture, and limitations.

The ARM host may cache, mirror, or render communication state, but it must not become a separate conversational authority.

## Target Interaction Model

### 1. Human asks on ARM UI

The ARM chat box accepts the operator message and creates a bounded conversation request.

Required fields:

- `session_id`
- `message_id`
- `operator_text`
- `intent`
- `objective_id` when known
- `source_surface = mim_arm_ui`
- `requested_response_mode = explain | status | help | bounded_action_guidance`

### 2. ARM routes to MIM

The ARM host forwards the request to MIM rather than answering locally from a weak placeholder.

Preferred routing order:

1. direct MIM dialog or bounded API call on the canonical MIM communication path
2. same-session TOD-MIM coordination when TOD execution/runtime evidence is required
3. explicit bounded fallback explanation if MIM is temporarily unavailable

### 3. MIM composes the response

MIM owns:

- human-readable explanation
- intent interpretation
- response structure
- next-question closure
- decision language for planning or guidance

TOD contributes only when needed:

- runtime state
- bridge status
- objective alignment
- bounded action availability
- execution restrictions or safety posture

### 4. ARM renders a structured answer

The chat UI should render:

- answer summary first
- supporting evidence below
- confidence tag
- limitations tag
- source tag such as `MIM`, `MIM+TOD`, or `fallback`
- optional suggested bounded actions

## Required Changes

### Phase A. Remove ARM-local conversational authority

Replace local placeholder chat behavior on the ARM host with a transport-only or proxy-style request path.

Done when:

- ARM no longer emits generic low-value fallback answers as the default path
- ARM clearly marks when MIM is unavailable instead of pretending to answer

### Phase B. Add direct MIM communication binding

Bind ARM chat requests to MIM through a stable bounded channel.

Preferred contract:

- request envelope from ARM UI to MIM
- response envelope from MIM back to ARM UI
- correlation id preserved end-to-end
- objective id preserved when present
- confidence and limitation fields preserved

### Phase C. Add TOD evidence enrichment

When the operator question depends on runtime truth, MIM should request bounded evidence from TOD rather than guessing.

Examples:

- current active objective
- bridge mismatch state
- listener or watchdog health
- whether a bounded action is available or blocked

### Phase D. Improve human response quality

MIM responses rendered on ARM should follow a simple operator-facing contract.

Required qualities:

- lead with the answer
- explain why briefly
- state uncertainty explicitly
- avoid empty rephrase loops unless the input is actually unparseable
- end with closure, not ambiguity

### Phase E. Add observability and fallback discipline

Track whether the ARM surface is truly using MIM-backed communication.

Required telemetry:

- request count
- response source: `mim`, `mim_tod`, `fallback`
- response latency
- timeout count
- local-placeholder usage count
- operator dissatisfaction markers when available

## Management Procedure

### Ownership

MIM owns:

- conversational reasoning
- human-facing wording
- decision framing
- clarification strategy

TOD owns:

- execution/runtime evidence
- bounded control availability
- coordination and status truth for execution surfaces

MIM ARM owns:

- UI capture and rendering
- session continuity on the ARM screen
- transport to MIM
- transparency about source and fallback mode

### Decision Rules

- If the question is about execution truth, MIM should incorporate TOD evidence.
- If the question is about planning, explanation, or clarification, MIM should answer directly.
- If MIM is unavailable, ARM should say so plainly and avoid pretending to reason locally.
- If TOD evidence is stale or unavailable, the response should say that explicitly.

### Escalation Rules

- If ARM cannot reach MIM, show `MIM unavailable` with retry posture.
- If MIM can answer but TOD evidence is missing, answer with MIM explanation plus a stated TOD evidence gap.
- If the same operator question gets repeated weak fallback answers, treat that as a communication-quality defect, not user error.

## Acceptance Criteria

This plan is complete when all of the following are true:

- ARM chat no longer defaults to local weak placeholder answers.
- ARM chat responses are traceably sourced from `MIM` or `MIM+TOD`.
- Runtime-sensitive questions clearly reflect TOD evidence when relevant.
- Responses include confidence and limitations.
- Operators receive direct, concise, human-usable answers instead of repeated rephrase prompts.
- Telemetry can prove whether ARM is using real MIM-backed communication.

## Immediate Priority

The first implementation slice should be:

1. disable or demote the ARM-local fallback responder
2. route ARM chat requests directly to MIM
3. mark source on every response
4. only use TOD as bounded evidence support, not as the primary conversational brain for ARM chat