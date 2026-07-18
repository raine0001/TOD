# TOD Source-Evidence Artifact Body Synthesis and Closure Learned Capability

## Capability Name

Source-evidence artifact body synthesis and closure.

## Trigger

TOD has a bounded artifact-write target and source evidence, but no supplied `New Text` body. The task must produce a proof artifact from evidence rather than a generic blocker or wrapper-only success.

## Reality

`runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION.latest.json` already contained structured SolAir power-curve evidence. The source had two evidence lanes: chart/workbook output values and physics-limit calculated values.

## Observation

TOD first produced `blocked_missing_artifact_content` because it could bind the output artifact but could not synthesize the required body from the source evidence. After the source-evidence lane was reachable, TOD published a valid proof artifact, but the outer execution gate still rejected completion as `wrapper_only_success_rejected+material_diff_missing`.

## Root Cause

Two capabilities were missing:

1. TOD needed a source-evidence artifact-body lane that reads structured evidence and writes the required proof fields.
2. TOD's closure gate needed to recognize validated artifact-write output as material proof when the artifact itself is the bounded target.

## Blocker Class

- `capability_blocker`
- `validation_contract_blocker`

## Decomposition Ladder

1. Bind exactly one output target.
2. Detect and publish `blocked_missing_artifact_content` instead of false success.
3. Read the source evidence artifact.
4. Extract the 10 mph chart and physics-limit rows.
5. Preserve the authority boundary between source-observed chart values and calculated physics-limit values.
6. Write the proof artifact with all required fields.
7. Read back the proof artifact and validate required fields.
8. Repair closure validation so a validated artifact write can complete when the artifact is the target.
9. Rerun the same task and prove the execution contract closes.

## Smallest Successful Rung

`TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002E` published `runtime/shared/TOD_INDEPENDENT_UNSEEN_APPRENTICESHIP_DEMONSTRATION_002.latest.json` with no missing required fields and validation status `pass`.

## Implementation Summary

`scripts/engines/LocalExecutionEngine.ps1` gained a bounded source-evidence demonstration lane for the SolAir power-output proof. The lane reads the SolAir power-curve observation artifact, extracts chart and physics-limit evidence, writes an authority-boundary answer model, and validates required fields.

`scripts/TOD.ps1` now recognizes explicit `artifact_write` mode from task metadata and materialization metadata during material-implementation proof assessment, so a validated artifact target is not rejected as wrapper-only output.

## Validation

- Pester: `tests/TOD.LocalFallbackExecutor.Tests.ps1` now passes the new SolAir source-evidence artifact-body test.
- Suite baseline after repair: `51 passed, 2 failed`; the 2 failures are pre-existing consumed-materialization selector tests.
- Live TOD task: `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002E`.
- Live execution result: `status=completed`, `reason_code=""`.
- Artifact readback: no missing required fields.
- Extracted 10 mph values:
  - chart one unit: `175 W`
  - chart two units parallel: `350 W`
  - chart two units series: `350 W`
  - physics raw wind power: `98.8 W`
  - physics Betz limit: `58.6 W`
  - physics after generator efficiency: `52.7 W`
- `source_conflict=true` was preserved.
- Follow-up guard validation: `TOD-INDEPENDENT-SOURCE-EVIDENCE-ARTIFACT-BODY-DEMONSTRATION-003B` proved that a `local_execution_artifact_write_blocker` must not be accepted as completion.

## General Rule Learned

Artifact-body synthesis is not text generation from nothing. It is evidence selection, field extraction, boundary preservation, and required-field validation.

## Prevention Rule

If a task asks for an artifact body and source evidence exists, TOD must not stop at `new_text_missing`. TOD must first try a smaller source-evidence synthesis rung, then validate that the outer execution contract accepts the artifact as material proof.

If the written artifact is itself a blocker, TOD must preserve the blocked state. A blocker artifact is useful evidence, but it is not completion evidence.

## Reuse Trigger

- `blocked_missing_artifact_content`
- `new_text_artifact_body_missing`
- source evidence artifact exists
- proof artifact required
- wrapper-only rejection after artifact write
- artifact-write blocker accidentally treated as completion
- task has `artifact_write` mode in metadata but `validation_only` category

## Dependent Capabilities

- Single-target materialization
- Structured JSON evidence reading
- Required-field extraction
- Authority-boundary reasoning
- Artifact-write validation
- Material proof classification

## Capability Confidence

Medium-high for the scaffolded SolAir source-evidence case. Low-to-medium for unseen independent source selection until TOD repeats on a different source artifact without Codex adding a new lane.

## Independent Pass Rate

`0/2` fully independent demonstrations. `1/1` scaffolded source-evidence demonstrations passed after Codex escalation. The follow-up BOM attempt correctly remained blocked after the blocker-artifact guard.

## Date Frozen

2026-07-13

## Generalized Principle

Validated artifact writes are material implementation evidence when the artifact itself is the bounded target. Closure gates must evaluate the requested work product, not only source-code diffs.
