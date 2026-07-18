# Learned Capability: Response-Contract Closure And Evidence-Derived Manufacturing Answers

## Capability Name
MIM response-contract field propagation and SolAir manufacturing equipment answer from evidence.

## Trigger
TOD sends a review or blocker packet to MIM that requires decision-quality fields, or a user asks a research/manufacturing question that should be answered from observed project evidence.

## Reality
MIM could consume TOD handoff requests and return `decision` and `reason`, but it did not propagate requested `response_contract` fields such as `required_changes`, `implementation_allowed`, and `expected_evidence`.

The SolAir manufacturing-equipment answer was falling back to a generic frame/tooling statement instead of synthesizing a provisional facility equipment map from observed BOM lanes.

## Observation
- MIM returned generic or incomplete review responses for multiple TOD review-contract requests.
- MIM response payloads omitted required fields even when `response_contract.required_fields` requested them.
- Existing tests accepted placeholder `blocked_missing_data` behavior.
- The SolAir live answer did not provide useful manufacturing equipment categories.

## Root Cause
`core/next_step_dialog_service.py::_build_response_finding_positions` emitted only `finding_id`, `decision`, `reason`, `confidence`, and `local_blockers`.

It did not merge raw candidate-finding metadata with adjudication output or propagate required response-contract fields.

The SolAir equipment branch in `core/public_research_context.py::_manufacturing_discovery_reply` used a generic tooling sentence instead of grouping observed BOM evidence into manufacturing equipment categories.

## Blocker Class
- `authority_blocker`: incomplete MIM review-contract response blocked TOD implementation authority.
- `capability_blocker`: research answer synthesis from source evidence was too weak.

## Decomposition Ladder
1. Prove MIM receives TOD review packets.
2. Prove MIM consumes item-shaped `candidate_findings`.
3. Prove MIM response lacks requested fields.
4. Repair generic response-contract field propagation.
5. Validate with unit tests and live dialog probe.
6. Resume SolAir answer repair.
7. Replace generic answer branch with evidence-derived manufacturing equipment map.
8. Validate with tests and live HTTP probe.

## Smallest Successful Rung
Live dialog probe `mim-response-contract-field-propagation-live-probe-001` returned:

- `decision`
- `reason`
- `required_changes`
- `implementation_allowed`
- `expected_evidence`

with no missing required fields.

## Implementation Summary
Emergency/control-plane repair:

- Added generic response-contract field propagation in `tmp_remote_mim/core/next_step_dialog_service.py`.
- Added coverage in `tmp_remote_mim/tests/test_next_step_dialog_service.py`.

Escalation after TOD attempt:

- Updated SolAir equipment/facility answer branch in `tmp_remote_mim/core/public_research_context.py`.
- Strengthened `tmp_remote_mim/tests/test_public_research_context.py`.

## Validation
- Remote MIM pytest: `37 passed, 12 subtests passed`.
- MIM user service restarted and active.
- Live `/public/chat/message` probe for `what equipment do I need to manufacture the solair turbine?` returned an evidence-derived provisional equipment map with source-observed BOM rows, source link, and uncertainty boundary.

## General Rule Learned
Acknowledgement is not review closure.

Research/manufacturing answers must synthesize from observed evidence and explicitly preserve uncertainty boundaries.

## Prevention Rule
When `response_contract.required_fields` is present, MIM must include those fields in the response or publish a field-complete blocker.

For research questions, MIM must not answer from generic domain knowledge when project evidence exists. It should cite observed evidence, state what remains unverified, and avoid final claims unless source review supports them.

## Reuse Trigger
Use this capability when:

- MIM says `approve` but omits `implementation_allowed` or `expected_evidence`.
- TOD cannot tell whether a review packet is actually approved.
- A research answer says only that files exist instead of synthesizing observed evidence.
- Manufacturing questions require a provisional evidence-derived answer without claiming final production readiness.

## Dependent Capabilities
- TOD evidence-only reporting.
- MIM/TOD dialog response contracts.
- Research source observation and document-library indexing.
- Evidence-derived numeric and manufacturing answers.

## Capability Confidence
7/10.

## Independent Pass Rate
Not yet established. Codex performed emergency/control-plane repair and escalation after TOD attempt. TOD/MIM must repeat similar repairs independently before this can be raised.

## Date Frozen
2026-07-07
