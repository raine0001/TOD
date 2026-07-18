# Learned Capability: Research Evidence Boundary Reasoning And Owner Contract Closure

## Capability Name
Research evidence-boundary reasoning and MIM owner-field response-contract closure.

## Trigger
A research/manufacturing/specification prompt asks MIM or TOD to classify what can be safely said from supplied evidence, while explicitly forbidding code changes, task creation, and status reporting.

## Reality
The broad reasoning prompt was not an implementation request. It was a research-boundary classification request.

The MIM response-contract closure request required an `owner` field. MIM responded, but originally omitted that field.

## Observation
TOD initially routed the less-scaffolded reasoning prompt as `implementation_request` and returned stale Current Work / Initiative / Durable Memory / Communication Skills scaffold.

After the first repair, TOD stopped dispatching implementation work but still overclaimed the evidence through the local conversation provider.

MIM originally returned `decision`, `reason`, `confidence`, and `local_blockers`, but omitted `owner` even when the response contract required it.

## Root Cause
TOD did not have a distinct research evidence-boundary request lane. The classifier treated negated phrases such as "no code changes" and "no task creation" as implementation signals because they contained action words.

MIM response-contract propagation only handled selected fields such as `implementation_allowed`, `required_changes`, and `expected_evidence`; it did not handle owner fields.

## Blocker Class
- TOD: capability_blocker
- MIM: coordination_blocker

## Decomposition Ladder
1. Prove scaffolded evidence-boundary field reporting.
2. Test the same skill through a less-scaffolded reasoning prompt.
3. Classify the scaffold leakage as a capability blocker.
4. Identify the target routing surface.
5. Add a general research-boundary request lane.
6. Add a source-evidence formatter that uses the supplied evidence and claim sections.
7. Validate no implementation dispatch, no stale scaffold, and no final unsupported claim.
8. Identify MIM owner-field response-contract gap.
9. Add owner/current_owner/next_owner propagation from requested contract fields.
10. Validate unit and live dialog behavior.

## Smallest Successful Rung
The same broad research-boundary prompt returned:

- `request_kind=research_boundary_request`
- `source=research_boundary_formatter`
- no implementation dispatch
- no stale Current Work scaffold in the reply
- `Classification: not_yet_claimable`
- missing evidence named before promoting the claim

## Implementation Summary
TOD `scripts/Invoke-TODConversationalReply.ps1` now recognizes bounded reasoning drills that include evidence, a claim to classify, and explicit no-code/no-task/no-status boundaries.

TOD emits a research-boundary answer from supplied evidence and claim sections instead of asking the local conversation provider to improvise.

MIM `core/next_step_dialog_service.py` now includes `owner`, `current_owner`, or `next_owner` in finding positions when requested by `response_contract.required_fields`, deriving the value from explicit fields or `owner_workspace`.

## Validation
TOD validation:

```powershell
./scripts/Invoke-TODConversationalReply.ps1 -Query $researchBoundaryPrompt -ObjectiveId OBJ-0264 -OperatorName Dave -AsJson
```

Observed:

- `request_kind=research_boundary_request`
- `source=research_boundary_formatter`
- reply contained `Classification: not_yet_claimable`
- reply named missing bend-radius drawing, fixture drawing, supplier quote, current supplier price, labor routing, overhead, tooling amortization, and production validation record

MIM validation:

```bash
cd /home/testpilot/mim && .venv/bin/pytest -q tests/test_next_step_dialog_service.py
```

Observed:

- `4 passed`

Live dialog validation:

- session: `research-boundary-owner-field-live-probe-001`
- finding: `TOD-OWNER-FIELD-LIVE-PROBE-001`
- owner returned: `tod`
- result: owner-field live probe passed

## General Rule Learned
Routing must respect negation and intent. A prompt that says "no code changes" is not asking for code just because it contains the word "changes."

Research answers should classify what evidence supports, what remains provisional, and what cannot be claimed until source evidence is promoted.

Response contracts must include every required field, not only fields the responder already knows how to emit.

## Prevention Rule
Before treating a research prompt as implementation, check whether it is actually asking for classification, evidence boundaries, or source-promotion reasoning.

Before closing a MIM/TOD dialog transaction, verify all `response_contract.required_fields` are present in the response.

## Reuse Trigger
Use this learned capability when:

- MIM or TOD sees a research/spec/manufacturing/chart/cost prompt asking what can safely be said.
- A prompt includes action words only inside negated constraints such as "no code changes."
- MIM replies to a response contract but omits required ownership or closure fields.

## Dependent Capabilities
- research document assimilation
- evidence/source promotion
- MIM/TOD dialog response contracts
- TOD conversational request classification
- operator-facing research answer safety

## Capability Confidence
7/10.

The tested rungs pass, but broader unstructured research prompts still need more varied regression examples.

## Independent Pass Rate
2/2 focused runtime probes passed after repair:

- TOD research-boundary formatter smoke
- MIM owner-field live dialog probe

## Date Frozen
2026-07-07
