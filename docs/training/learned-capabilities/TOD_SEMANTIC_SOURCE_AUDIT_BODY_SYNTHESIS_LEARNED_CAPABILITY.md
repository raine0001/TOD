# TOD Semantic Source-Audit Body Synthesis Learned Capability

## Capability Name

Semantic source-audit body synthesis from source anchors.

## Trigger

TOD has source-anchor evidence and a required audit-body contract, but the produced artifact is generic or missing semantic root-cause fields.

## Reality

The inspected MIM response-contract source can be observed through exact source anchors, but those anchors do not themselves contain the final requested audit fields.

## Observation

TOD first produced a generic read-only audit artifact that did not include `observed_blocker`, `suspected_root_cause`, `evidence_checked`, `evidence_missing`, `why_forward_motion_is_blocked`, `smallest_diagnostic_step`, `confidence`, or `no_phrase_patch_rule`.

## Root Cause

The existing read-only audit lane could publish an artifact, but it could not synthesize a semantic body from source-anchor evidence. TOD needed an intermediate source-audit lane that reads anchor artifacts, extracts what those anchors prove, and writes the required audit fields without mutating product code or adding phrase patches.

## Blocker Class

- `capability_blocker`
- `data_blocker`
- `coordination_blocker` until MIM acknowledges final proof

## Decomposition Ladder

1. Publish a precise blocker instead of claiming generic audit success.
2. Capture the first source anchor for `_derive_capability_model_status`.
3. Capture the second source anchor for `_collect_contract_output_fields` and `_contract_candidate_sources`.
4. Rerun the original semantic audit body task.
5. Publish a field-complete semantic source-audit artifact.
6. Validate required field readback, `no_code_changes=true`, and `no_phrase_patch_rule=true`.
7. Send final proof to MIM through the dialog lane for decision-quality acknowledgement.

## Smallest Successful Rung

`TOD-SEMANTIC-SOURCE-ANCHOR-CONTRACT-FIELDS-001B` captured the contract-field source anchor with enough exact source text to prove what the collector does and does not produce.

## Implementation Summary

`scripts/engines/LocalExecutionEngine.ps1` gained a bounded semantic source-audit lane. The lane recognizes semantic source-anchor audit tasks, reads one or more source-anchor artifacts, writes a structured semantic audit artifact, and fails closed if required fields or safety assertions are missing.

## Validation

- `TOD-SEMANTIC-AUDIT-BODY-FROM-SOURCE-ANCHORS-001` rerun completed through `Invoke-LocalExecutionSemanticSourceAudit`.
- `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT.latest.json` has no missing required fields.
- Final artifact has `artifact_type=tod_semantic_source_audit_artifact`.
- Final artifact has `classification=semantic_audit_body_synthesis_from_source_anchors`.
- Final artifact has `no_phrase_patch_rule=true`.
- Final artifact has `no_code_changes=true`.
- Focused Pester coverage was added in `tests/TOD.LocalFallbackExecutor.Tests.ps1`.

## General Rule Learned

When a required artifact body is missing, TOD must not treat artifact publication as success. TOD must synthesize the requested body from bounded evidence and validate the required field contract.

## Prevention Rule

Before closing any audit-body task, read back every required field and assert the safety boundary fields. If the body is missing, back up to source-anchor observation and semantic body synthesis before dispatching or closing.

## Reuse Trigger

- `artifact_body_synthesis_missing`
- `semantic_audit_body_synthesis_missing`
- `missing required fields`
- source-anchor artifacts exist but final audit body is generic
- source inspection proves behavior but no root-cause audit body has been written

## Dependent Capabilities

- Source-anchor observation
- Required-field extraction
- Read-only audit artifact publication
- Semantic body synthesis
- MIM/TOD acknowledgement closure

## Capability Confidence

High for scaffolded source-anchor to semantic-audit synthesis. Not yet high for unseen independent TOD selection.

## Independent Pass Rate

`0/1` independent unseen demonstrations. Current pass is scaffolded after Codex escalation.

## Date Frozen

2026-07-13

## Separate Debt

MIM response-contract acknowledgement remains open. MIM replied with an approve decision but did not provide all requested ACK fields.

## Generalized Principle

Evidence preservation and conclusion synthesis are separate capabilities. Source anchors prove what was inspected; audit bodies explain what the inspection means. TOD must learn both.
