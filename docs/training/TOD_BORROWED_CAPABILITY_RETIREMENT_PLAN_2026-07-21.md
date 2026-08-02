# TOD Borrowed Capability Retirement Plan - 2026-07-21

## Mission

Reduce TOD's borrowed-capability ratio by training capability families, not isolated incidents. Each borrowed registry entry remains open until TOD proves the relevant capability on a fresh analogous case with evidence.

Current baseline:

- Registry entries: 36
- Borrowed or unknown: 35
- Independent: 1
- Retired: 0
- Borrowed capability ratio: 97.2%
- Independent ratio: 2.8%
- Registry integrity issue: duplicate apprenticeship IDs exist and must be cleaned before per-entry retirement math can be fully trusted.

## Training Strategy

Many registry entries are symptoms of the same missing skills. Retiring them one at a time would create busywork. The training cycle should group related entries into shared drills where one proof can advance multiple debts, as long as the proof is fresh and the capability truly generalizes.

## Priority Families

## Registry Integrity Training Debt

The current registry contains duplicate IDs with different capability names. This must be treated as evidence hygiene debt, not ignored.

Previously duplicated IDs from current parsing:

- `APP-TOD-011` split from `APP-TOD-035`
- `APP-TOD-012` split from `APP-TOD-036`

Training requirement:

- Preserve every duplicate entry during grouping.
- Assign unique IDs before retiring any affected debt.
- Never allow a scorecard parser to collapse separate debts because they reused an ID.

Proof artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_APPRENTICESHIP_REGISTRY_ID_INTEGRITY_PROOF.latest.json`

### Priority 1: Read-Only Assessment And Authority Classification

Why first:

TOD already has momentum here. `APP-TOD-034` is `independent_demo_passed`, so the fastest way to reduce borrowed debt is to reuse that proven lane against adjacent read-only and authority-classification debts.

Registry entries:

- `APP-TOD-034`: Patch Evidence Ingestion For Read-Only Audits
- `APP-TOD-033`: Direct Chat Read-Only Task Mode Preservation
- `APP-TOD-032`: Route Experiment Authority Classification
- `APP-TOD-036`: Read-Only Audit Extraction For Artifact-Write Blockers

Training proof:

- TOD receives one fresh read-only route/authority/audit target.
- TOD classifies task mode without requiring bounded edit fields.
- TOD inspects the target evidence.
- TOD publishes a structured artifact.
- TOD does not modify product source.
- TOD validates that malformed edit packets are still rejected.

Pass artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_AUTHORITY_CLASSIFICATION_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Move `APP-TOD-033`, `APP-TOD-032`, and `APP-TOD-036` toward `independent_demo_passed`.
- Keep `APP-TOD-034` open until one more future fresh pass proves reliability.

### Priority 2: Current-Code Bounded Packet Materialization

Why second:

This is the largest independence blocker. Until TOD can inspect current code and synthesize a valid old/new or anchor/snippet packet, Codex remains the real implementer for many tasks.

Registry entries:

- `APP-TOD-031`: Fresh Target Packet Loop Materialization
- `APP-TOD-018`: Unique-Anchor Bounded Edit Materialization
- `APP-TOD-021`: Missing Objective Prompt Packaging Recovery
- `APP-TOD-022`: Packet Formation Artifact Materialization Recovery
- `APP-TOD-016`: Existing-Bridge Remediation Materialization

Training proof:

- TOD selects one harmless current-code target.
- TOD inspects the file.
- TOD identifies one unique anchor.
- TOD writes a bounded packet with target file, edit mode, old text or anchor, new text or snippet, validation command, rollback note, and prevention lesson.
- TOD applies the packet.
- TOD validates the exact changed behavior.
- TOD cleans up or leaves the intended change with evidence.

Latest rung:

- 2026-07-23: TOD passed a narrower role-disambiguation proof on the failed r3 source-anchor task. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_ARTIFACT_ROLE_DISAMBIGUATION_V1.r1.latest.json`.
- Proven: TOD can classify Evidence Artifact and Package Path as read-only inputs, Inspect Source File as inspection input, Output as the evidence artifact to write, and Target File as a bounded edit target only when behavior-changing edit authority is explicit.
- 2026-07-23: TOD ran the next held-out engineering-corpus synthesis check and published `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_HELDOUT_CANDIDATE_NEWTEXT_V1.r1.latest.json`.
- Proven: TOD can select a held-out source-anchor episode from the enriched corpus manifest, verify `source_anchor_available=true`, and refuse to fabricate `candidate_new_text`.
- 2026-07-23: TOD backed up from a too-narrow source-anchor capture and published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_ARTIFACT_PRODUCER_GENERIC_FALLBACK_ANCHOR_V1.r3.latest.json`.
- Proven: TOD can widen an inspected source anchor until the meaningful current-code block is captured. The R3 artifact includes the read-only audit generic fallback, artifact construction, required-field/readback validation, and no-code-change evidence from `scripts/engines/LocalExecutionEngine.ps1` lines 6515-6965.
- 2026-07-23: TOD ran the read-only delta proposal rung against the R3 artifact and published `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_FROM_SOURCE_ANCHOR_V1.r1.latest.json`.
- Proven: TOD can carry a verified source-anchor artifact into a delta-proposal shape and name `autonomous_candidate_new_text_missing` without fabricating code or modifying source files.
- Not yet proven: TOD can synthesize meaningful, safe `candidate_new_text` from verified source-anchor evidence, or complete the full fresh-target packet loop without Codex scaffolding.

Pass artifact:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_CURRENT_CODE_PACKET_MATERIALIZATION_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Move packet-materialization debts from borrowed/scaffolded toward independent demonstration.

### Priority 3: Recovery That Produces Executable Retry Shape

Why third:

TOD can often say why it is blocked. It still struggles to turn the diagnosis into the next executable attempt.

Registry entries:

- `APP-TOD-011`: Executor Binding Blocker Self-Recovery
- `APP-TOD-023`: Optional Selection Source Field StrictMode Recovery
- `APP-TOD-004`: Self-Evolution Schema Drift Recovery
- `APP-TOD-020`: Terminal Lane Projection And Supersession Hygiene

Training proof:

- TOD receives or discovers a real blocker.
- TOD classifies the blocker.
- TOD identifies the exact missing requirement.
- TOD produces a corrected retry payload or a smaller diagnostic step.
- TOD validates that the blocker condition changed.
- TOD resumes the original objective or records the remaining external dependency.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_EXECUTABLE_RECOVERY_SHAPE_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Improve recovery quality, blocker honesty, and autonomous recovery rate.

### Priority 4: Response Authority And MIM Cognition Boundary

Why fourth:

These are high-impact but more dangerous. They touch MIM's public behavior, so TOD should not attempt them until read-only classification and bounded packet materialization are stable.

Registry entries:

- `APP-TOD-001`: Cross-Surface Conversation Purpose Routing
- `APP-TOD-006`: Studio Active Context Transition Routing
- `APP-TOD-007`: Self-Evolution Status Reporting Before Generic Exploration
- `APP-TOD-010`: Hardcoded MIM Answer Detection And Replacement
- `APP-TOD-024`: Research Observatory Conversation Evolution Routing
- `APP-TOD-027`: Public Homepage Structured Reply Rendering Boundary
- `APP-TOD-028`: Public Enterprise Product Question Routing
- `APP-TOD-029`: Observatory Service Knowledge Product Context Certification

Training proof:

- TOD audits one response-authority path.
- TOD identifies whether it is process support or prohibited final-answer authority.
- TOD proposes a service-level or instrumentation repair, not a phrase route.
- TOD validates cognitive interpretation, composed response, and final visible response remain aligned.

Pass artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_RESPONSE_AUTHORITY_BOUNDARY_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Reduce MIM hardcoded route debt without making more hardcoded routes.

### Priority 5: Evidence-Derived Research And Product Answers

Why fifth:

MIM must derive answers from inspected evidence instead of static text. This is central to Observatory and Enterprise product mastery.

Registry entries:

- `APP-TOD-002`: Evidence-Derived Numeric Research Answer
- `APP-TOD-013`: Semantic Source-Audit Body Synthesis From Source Anchors
- `APP-TOD-015`: Source-Evidence Artifact Body Synthesis and Closure
- `APP-TOD-029`: Observatory Service Knowledge Product Context Certification

Training proof:

- TOD selects one evidence-backed question.
- TOD locates source evidence.
- TOD extracts the relevant fields.
- TOD distinguishes fact, inference, estimate, and missing evidence.
- TOD publishes a derived answer artifact and validation.

Pass artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_EVIDENCE_DERIVED_ANSWER_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Strengthens Auditor, Observatory, and Enterprise product mastery.

### Priority 6: MIM/TOD Coordination Contract And Status Truth

Why sixth:

TOD and MIM still drift between chat claims, hourly summaries, active lanes, and execution evidence. This family makes the system explain what is actually happening.

Registry entries:

- `APP-TOD-005`: Dialog Response Contract Projection And Focus-Review Derivation
- `APP-TOD-014`: MIM Dialog ACK Contract Field Projection
- `APP-TOD-017`: Blocker Policy Communication From Current Evidence
- `APP-TOD-020`: Terminal Lane Projection And Supersession Hygiene
- `APP-TOD-035`: Response Contract Envelope Scope Repair

Training proof:

- TOD publishes a blocker.
- MIM acknowledges it.
- Ownership, next action, evidence, and wait-state become visible.
- Stale artifacts do not override live execution truth.
- Status surfaces show one coherent plain-language state.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_COORDINATION_STATUS_TRUTH_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Directly improves Dave's ability to work with MIM and TOD.

### Priority 7: Cross-Service Live Verification And Deployment Pattern

Why seventh:

These skills are operationally important but should wait until TOD can classify, materialize, and recover with less Codex support.

Registry entries:

- `APP-TOD-009`: Cross-Service Live Surface Verification And Serving-Lane Restart
- `APP-TOD-025`: Enterprise Foundation Minimal Remote Deployment Pattern

Training proof:

- TOD selects a harmless live surface.
- TOD inspects local and remote anchors.
- TOD applies minimal idempotent change or read-only verification.
- TOD validates local, remote, and user-visible behavior.
- TOD records rollback and deployment evidence.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_DEPLOYMENT_PATTERN_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Moves Enterprise deployment from borrowed toward guided or independent.

### Priority 8: AgentMIM Production Assimilation

Why eighth:

AgentMIM matters, but it has many product-specific moving parts. TOD should first improve general packet, recovery, and evidence skills, then apply those to AgentMIM.

Registry entries:

- `APP-TOD-019`: AgentMIM Production Repair Assimilation
- `APP-TOD-026`: AgentMIM Deterministic App-Data Answer Before LLM Fallback
- `APP-TOD-030`: AgentMIM Visible Page-Context Fast Path Before Generic Chat
- `APP-TOD-012`: AgentMIM Carrier Commission Parser Contract Repair

Training proof:

- TOD inspects one AgentMIM production fix already made by Codex.
- TOD reconstructs the failure class.
- TOD selects a fresh analogous defect.
- TOD fixes it with validation and no Codex patch authorship.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_AGENTMIM_ASSIMILATION_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Converts recent production repair debt into reusable TOD skill.

## 12-Hour Execution Order

1. Run Priority 1 to move adjacent read-only/authority debts toward independent demonstration.
2. Run Priority 2 until TOD passes one current-code bounded packet proof.
3. Run Priority 3 against the next real blocker that appears.
4. If the first three pass, run Priority 6 because communication/status truth affects every later objective.
5. If time remains, begin Priority 4 as read-only audit only.

Do not spend the 12-hour cycle on broad product building until packet materialization and recovery are stronger.

## 2026-07-23 Corpus Foundation Rung

Objective: `OBJ-0171` / `TOD-ENGINEERING-CORPUS-FOUNDATION-V1`

Purpose:

Evaluate whether `TOD Local Engineering Intelligence` should become the next training direction by forcing TOD to classify recent real engineering attempts into reusable episode candidates before any local model work begins.

Evidence produced:

- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EVIDENCE_INTAKE_CLASSIFIER_V1.r2c.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EPISODE_CANDIDATE_MANIFEST_V1.r2c.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_WRITER_FIELD_ALIAS_SOURCE_ANCHOR_V1.r2.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_WRITER_OBJECT_BLOCK_SOURCE_ANCHOR_V1.r1.latest.json`

What TOD demonstrated:

- TOD can route a scorecard-led evidence pool into the corpus evidence-intake classifier when the prompt avoids competing enrichment and held-out wording.
- TOD can produce a single-file episode candidate manifest from classified inputs without source-code mutation.
- TOD can capture a source-anchor observation when task mode and task category are explicitly `source_anchor_observation`.

What remains blocked:

- Only two usable episode candidates were available to the safe evidence lane, so a full five-episode engineering corpus is not yet available.
- The manifest writer emits `source_classifier_artifact`, `rejected_inputs`, and `manifest_gaps`; the requested downstream contract uses `input_classifier_artifact`, `rejected_or_deferred_inputs`, and `manifest_limits`.
- TOD attempted `tod-corpus-manifest-delta-r1`, but local execution selected the corpus source-anchor enrichment path instead of a source-anchor delta proposal. The failed task recorded `read_only_audit_required_artifact_type_unsupported` and `task_specific_artifact_lane`.
- Codex then applied a narrow selector-precedence repair after TOD exposed the wrong-lane blocker. Focused validation added `keeps source-anchor delta proposal ahead of corpus enrichment wording` in `tests/TOD.LocalFallbackExecutor.Tests.ps1`; that focused case passed.
- After the repair, TOD reran `tod-corpus-manifest-delta-r1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_FIELD_CONTRACT_DELTA_PROPOSAL_V1.r1.latest.json` with `artifact_type=tod_source_anchor_delta_proposal`, `source_anchor_valid=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, and `no_source_code_modified=true`.
- The rerun reached the real capability blocker: `autonomous_candidate_new_text_missing`. TOD preserved `candidate_new_text=""` and named `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor` as the missing capability.

Training conclusion:

The local engineering intelligence path is the right strategic direction only after Stage 1 corpus/examiner work. The route-specific lane hijack is now repaired for the delta-proposal case, but this was Codex-authored control-plane repair and remains borrowed capability. The current blocker is TOD's inability to reliably convert current source anchors into safe candidate code deltas.

Next smaller training rung:

`TOD-CORPUS-LANE-SELECTOR-PRECEDENCE-AND-DELTA-SYNTHESIS-V1`

Acceptance:

- Given a source-anchor observation artifact and a requested output artifact type of `tod_source_anchor_delta_proposal`, TOD must not route into corpus enrichment.
- TOD must publish either a non-empty candidate replacement or a precise blocker naming autonomous code-delta synthesis as missing.
- The result must preserve the input source anchor, output artifact path, objective ID, task ID, validation command, prevention lesson, and no-code-change assertion.

Status:

- `selector_precedence`: guided/scaffolded pass after Codex repair.
- `delta_synthesis`: blocked on autonomous meaningful `candidate_new_text` generation from verified source anchor evidence.
- `debt_retirement`: no retirement; this rung clarified the next missing skill.
- `supported_lane_retry`: `tod-autonomous-meaningful-newtext-from-source-anchor-r4` was replanned through the supported `inspection_only` read-only lane after r3 exposed path-role ambiguity. The local executor completed cleanly and wrote `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_SYNTHESIS_FROM_SOURCE_ANCHOR_V1.r4.latest.json`.
- `current truth`: r4 validates source-anchor readback and no-code-change evidence, but still returns `candidate_new_text=""` with blocker `autonomous_candidate_new_text_missing`.
- `implementation clue`: the generic `tod_source_anchor_delta_proposal` artifact path in `scripts/engines/LocalExecutionEngine.ps1` still writes an empty `candidate_new_text`, while the separate PowerShell snippet synthesis lane has previously produced a packet candidate under scaffolding. The missing skill is routing a verified source-anchor delta request into a safe synthesis process without Codex-supplied replacement text.
- `2026-07-23 later proof`: TOD produced `runtime_remote_training/tod_independent_resolution_attempts/TOD_CONTRACT_TAIL_AUTONOMOUS_NEWTEXT_PROOF_R25.latest.json`, which contains non-empty `new_text`. Codex validation rejected independent credit in `runtime_remote_training/read_only_audit_artifacts/TOD_CONTRACT_TAIL_AUTONOMOUS_NEWTEXT_PROOF_R25.codex_validation.json` because the proposed `new_text` does not preserve the selected source anchor's semantic purpose. It replaces a read-only audit artifact construction block with an unrelated bounded edit execution switch block.
- `updated current truth`: TOD has advanced from blank-candidate failure to semantic-boundary failure. The next training rung must require source-anchor purpose preservation before packet readiness can count.
- `semantic-preservation R1`: TOD accepted `TOD-SOURCE-ANCHOR-SEMANTIC-DELTA-PRESERVATION-V1-R1`, but local execution wrote `artifact_type=tod_patch_evidence_authority_classification` from `runtime_remote_training/cleanup_holds/TSK-0100_95361c28beae.patch` into the requested output path instead of reviewing the requested R25 input artifact. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_SEMANTIC_DELTA_PRESERVATION_V1.r1.codex_validation.json`.
- `updated blocker`: before semantic preservation can be tested, TOD must preserve the requested artifact type and input artifact through dispatch. This is a supporting runtime/authority blocker, not engineering credit.
- `contract-preservation R1`: TOD attempted `TOD-REQUESTED-ARTIFACT-TYPE-AND-INPUT-PRESERVATION-V1-R1`, but direct execution blocked with `codex_wrapper_only_no_execution` plus `local_execution_scope_not_supported`. The local fallback reported that it can produce generic `tod_read_only_audit_artifact`, but not the requested `tod_requested_artifact_contract_preservation_review`. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_REQUESTED_ARTIFACT_TYPE_AND_INPUT_PRESERVATION_V1.r1.codex_validation.json`.
- `updated blocker`: the requested artifact/input preservation proof needs a minimal task-specific artifact contract lane or a smaller supported blocker shape before TOD can retry semantic preservation.
- `lane-definition R1`: TOD attempted `TOD-TASK-SPECIFIC-ARTIFACT-CONTRACT-LANE-DEFINITION-V1-R1`, but direct execution again blocked because the local fallback can produce generic `tod_read_only_audit_artifact`, not `tod_task_specific_artifact_contract_lane_definition`. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_TASK_SPECIFIC_ARTIFACT_CONTRACT_LANE_DEFINITION_V1.r1.codex_validation.json`.
- `new current truth`: the next rung must back up one more step and use a supported generic read-only artifact to preserve the missing task-specific contract shape. Asking TOD to invent a new custom artifact type through the current executor is not executable yet.
- `generic-summary R1`: TOD used direct local execution to publish `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_GENERIC_BLOCKER_TO_ARTIFACT_CONTRACT_SUMMARY_V1.r1.latest.json`. Mechanical validation passed, but Codex validation rejected capability credit in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_GENERIC_BLOCKER_TO_ARTIFACT_CONTRACT_SUMMARY_V1.r1.codex_validation.json` because the artifact did not preserve requested input artifact, requested output artifact, requested artifact type, unsupported reason, or next learned lane proposal.
- `updated blocker`: the supported generic read-only audit lane must preserve contract-specific evidence fields before it can teach the missing task-specific lane.
- `field-preservation R1/R2`: TOD attempted `TOD-GENERIC-READONLY-AUDIT-EVIDENCE-FIELD-PRESERVATION-V1` twice. Both attempts accepted the read-only task text but routed into generic target inference instead of the source-anchor observation lane. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_READONLY_AUDIT_EVIDENCE_FIELD_PRESERVATION_V1.r1_r2.codex_validation.json`.
- `updated blocker`: before TOD can inspect the generic audit producer, runtime support must preserve `source_anchor_observation` lane selection and keep source file, input evidence artifact, and output artifact in distinct roles.
- `lane-selection R1`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_LANE_SELECTION_PRESERVATION_V1.r1.latest.json` through the read-only task-context proof lane. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_LANE_SELECTION_PRESERVATION_V1.r1.codex_validation.json` accepted the diagnostic value but rejected debt credit: structured `task_category=inspection_only` reached local execution, while `source_anchor_observation` remained prose-only in the scope.
- `updated blocker`: the next proof must use structured `task_category=source_anchor_observation` or identify the earlier executor branch that intercepts it.
- `structured-category R1`: TOD ran `TOD-SA-STRUCTURED-CATEGORY-CONTEXT-PROOF-V1-R1`. The rendered package preserved `Task Category: source_anchor_observation`, but execution did not create `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_CONTEXT_PROOF_V1.r1.latest.json`. Latest truth recorded `codex_wrapper_only_no_execution` plus local fallback `local_execution_scope_not_supported` because the requested output artifact path did not already exist. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_CONTEXT_PROOF_V1.r1.codex_validation.json`.
- `updated blocker`: package rendering can preserve the category, but the execution bridge still cannot prove a new read-only output artifact write for this shape. The next proof must establish the smallest supported read-only output artifact write shape before retrying source-anchor category survival.
- `read-only output eligibility R1`: TOD ran `TOD-READONLY-OUTPUT-ARTIFACT-ELIGIBILITY-PROOF-V1-R1` through the supported `inspection_only` task-context lane. Local execution created `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_OUTPUT_ARTIFACT_ELIGIBILITY_PROOF_V1.r1.latest.json` as a new artifact, changed no source files, and passed schema readback plus non-edit validation. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_OUTPUT_ARTIFACT_ELIGIBILITY_PROOF_V1.r1.codex_validation.json`.
- `updated truth`: new read-only output writes are proven for the supported `inspection_only` context-proof lane. Source-anchor category survival remains unproven.
- `source-anchor category retry R1`: TOD reran with structured `task_category=source_anchor_observation` in `TOD-SOURCE-ANCHOR-STRUCTURED-CATEGORY-RETRY-V1-R1`. The package preserved the category, but execution again blocked before creating `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_RETRY_V1.r1.latest.json`. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_RETRY_V1.r1.codex_validation.json`.
- `updated truth`: `source_anchor_observation` is not a generic context-proof category. It needs the source-file/anchor contract that the source-anchor executor expects. The next proof must inspect that contract branch from current code.
- `source-anchor contract R2`: TOD reran `TOD-SOURCE-ANCHOR-CONTRACT-BRANCH-INSPECTION-V1-R2` with task type `inspection`, structured category `source_anchor_observation`, explicit `Source File`, `Anchor Pattern`, `Output Artifact`, `Output`, and `Required Artifact Type`.
- `updated truth`: the source-anchor observation lane is executable when TOD supplies the full contract. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_CONTRACT_BRANCH_INSPECTION_V1.r2.latest.json` and Codex validation `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_CONTRACT_BRANCH_INSPECTION_V1.r2.codex_validation.json`.
- `field-preservation retry R1`: TOD used that proven contract shape in `TOD-SOURCE-ANCHOR-FIELD-PRESERVATION-RETRY-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_FIELD_PRESERVATION_RETRY_V1.r1.latest.json`.
- `updated truth`: TOD captured the generic read-only audit producer block around `$evidenceFields = @(` from `scripts/engines/LocalExecutionEngine.ps1` lines 5222-5332. The captured block preserves status/materialization fields but does not include requested input artifact, requested output artifact, requested artifact type, unsupported reason, or next learned lane proposal.
- `field-preservation delta R1`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_READONLY_AUDIT_FIELD_PRESERVATION_DELTA_PROPOSAL_V1.r1.latest.json` as `tod_source_anchor_delta_proposal`.
- `updated truth`: the artifact correctly preserved `source_anchor_valid=true`, no source edits, and blocker `autonomous_candidate_new_text_missing`, but it failed to state the current source-anchor purpose or requested behavior delta. Codex validation rejected pass credit in `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_READONLY_AUDIT_FIELD_PRESERVATION_DELTA_PROPOSAL_V1.r1.codex_validation.json`.
- `local-provider probe`: Codex tested the existing localhost `tod-local-chat` provider against a bounded field-preservation source excerpt. The provider successfully returned a plausible current purpose and requested behavior delta. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_PURPOSE_DELTA_LOCAL_PROVIDER_PROBE_V1.codex_validation.json`.
- `updated truth`: the local model can perform this semantic extraction when given clean context, but TOD has not yet demonstrated provider supervision, context packaging, reply judgment, or durable episode creation.
- `model-utilization supervision R1`: TOD attempted `TOD-MODEL-UTILIZATION-PURPOSE-DELTA-SUPERVISION-V1-R1`.
- `updated truth`: no provider-judgment artifact was created. Latest execution blocked with `codex_wrapper_only_no_execution`; wrapper package-path check passed, wrapper execution handoff failed, and local fallback eligibility failed. Codex validation rejected credit in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PURPOSE_DELTA_SUPERVISION_V1.r1.codex_validation.json`.
- `local-lane materialization R1-R3`: TOD inspected the existing provider script, the local execution allowance gate, and the unsupported artifact-type guard.
- `updated truth`: the local provider script exists and can be inspected; `scripts/TOD.ps1::Test-TaskAllowsLocalExecutionWithoutMaterialization` does not admit `model_utilization`; the generic read-only artifact writer rejects unsupported required artifact types and tells the task to use a task-specific learned capability lane. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_LOCAL_LANE_MATERIALIZATION_V1.r1.codex_validation.json`, `.r2.codex_validation.json`, and `.r3.codex_validation.json`.
- `provider-judgment lane packet R1`: TOD tried to produce the repair packet from R1-R3 evidence, but no packet was created because source, evidence, supporting evidence, and output artifact paths competed as target candidates. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_PACKET_V1.r1.codex_validation.json`.
- `admission-gate packet R1`: TOD retried with a single target, `scripts/TOD.ps1`, and only the R2 source-anchor input. No packet was created because LocalExecutionEngine required explicit `edit_mode` or an inferable markdown section update. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_ADMISSION_GATE_PACKET_V1.r1.codex_validation.json`.
- `packet-formation execution-contract R1`: TOD inspected `scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionGenericBoundedTask` through the source-anchor lane and published `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_EXECUTION_CONTRACT_INSPECTION_V1.r1.generic_bounded_task_source_anchor.latest.json`. Codex validation accepted the inspection in `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_EXECUTION_CONTRACT_INSPECTION_V1.r1.codex_validation.json`. The contract is now known: `artifact_write` requires `New Text`; `replace_text` requires `Old Text` and `New Text`; `insert_after` requires `Anchor` and `Snippet`; targetless `validation_only` requires `Validation Command`.
- `packet-body synthesis R1`: TOD exercised the packet-body synthesis lane with verified source-anchor input and one target source file. Local execution blocked precisely with `packet_body_synthesis_autonomous_new_text_missing`, preserving the true missing capability instead of hallucinating a packet. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_FROM_SOURCE_ANCHOR_V1.r1.codex_validation.json`.
- `local-provider judgment R1`: TOD attempted a model-utilization provider-judgment artifact, but the current execution path blocked before provider invocation. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_PROVIDER_SOURCE_ANCHOR_PURPOSE_DELTA_JUDGMENT_V1.r1.codex_validation.json`.
- `execution-lane support source-anchor R1`: TOD inspected `scripts/TOD.ps1::Test-TaskAllowsLocalExecutionWithoutMaterialization` through the source-anchor lane and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_EXECUTION_LANE_SUPPORT_SOURCE_ANCHOR_V1.r1.latest.json`. Codex validation accepted the inspection in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_EXECUTION_LANE_SUPPORT_SOURCE_ANCHOR_V1.r1.codex_validation.json`. The source anchor proves the current local execution allowance gate admits known read-only/source-anchor/packet paths but not `model_utilization`.
- `updated truth`: model-utilization work is not ready for direct provider invocation yet. The smallest next proof is a provider-judgment lane contract that preserves input artifact, output artifact, required artifact type, provider endpoint/script, provider response summary, TOD accept/reject decision, prompt improvement, no-source-mutation evidence, and non-implementation-credit policy.
- `provider-judgment lane contract R1`: TOD used the supported generic read-only artifact lane and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r1.latest.json`. Mechanical execution passed, but Codex validation rejected capability credit in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r1.codex_validation.json` because the artifact did not preserve `provider_reachable`, `provider_reply_summary`, `acceptance_findings`, `tod_accept_reject_decision`, `next_prompt_improvement`, or `counts_as_engineering_implementation_credit`.
- `updated blocker`: the supported generic read-only artifact lane cannot yet carry arbitrary requested contract fields. Before a provider-judgment lane can be learned, TOD must prove contract-field preservation for model-utilization evidence.
- `contract-field preservation R1`: TOD ran `TOD-READONLY-CONTRACT-FIELD-PRESERVATION-FOR-MODEL-UTILIZATION-V1-R1` through the supported generic read-only lane. Mechanical execution passed and wrote `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r1.latest.json`, but Codex validation rejected capability credit in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r1.codex_validation.json`. The execution result echoed the requested field names from the prompt, but the published artifact omitted every required provider-judgment contract field.
- `updated blocker`: the problem is now narrower than provider invocation. The generic read-only artifact writer appears to preserve a fixed evidence field list and drop arbitrary requested contract fields. TOD must inspect that writer/whitelist before model-utilization provider judgment can resume.
- `field whitelist/evaluator source-anchor proof`: TOD completed `TOD-READONLY-AUDIT-FIELD-WHITELIST-SOURCE-ANCHOR-V1-R1` and `TOD-READONLY-CONTRACT-FIELD-EVALUATOR-SOURCE-ANCHOR-V1-R2`. The first source anchor proved the generic writer starts from a fixed evidence-field set. The second source anchor proved the same writer also has a contract-required-field evaluator, but it only activates for accepted labels such as `Required checks:` and `Required output fields:`. Earlier model-utilization prompts used unsupported labels, so the field evaluator never ran. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_EVALUATOR_SOURCE_ANCHOR_V1.r2.latest.json` and `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_EVALUATOR_SOURCE_ANCHOR_V1.r2.codex_validation.json`.
- `updated blocker`: this is no longer a broad whitelist mystery. TOD must demonstrate contract-field preservation using the actual accepted directive language before adding any provider-judgment lane.
- `contract-field preservation R2`: TOD reran the preservation proof with the accepted `Required output fields:` directive. It published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r2.latest.json`, preserving all six required provider-judgment field names and classifying them as missing with `classification=contract_field_evaluation_failed`, `pass_or_reject=reject`, and `no_code_changes=true`. Codex validation passed this supporting rung in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r2.codex_validation.json`.
- `updated truth`: generic read-only contract-field preservation now works when TOD uses the lane's accepted directive vocabulary. The remaining APP-TOD-037 blocker is provider-judgment materialization: TOD still has not invoked or inspected a provider response and published an accept/reject engineering judgment artifact.
- `provider-judgment lane contract R2`: TOD reran the provider-judgment contract through the now-working required-output-fields shape. It preserved the required provider-judgment field names, but did not populate provider reachability, provider reply summary, accept/reject judgment, prompt improvement, or a missing provider-invocation hook. Codex validation rejected capability credit in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r2.codex_validation.json`.
- `provider invoker source-anchor R1`: TOD inspected `scripts/Invoke-TODConversationProvider.ps1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_INVOKER_SOURCE_ANCHOR_V1.r1.latest.json`. Codex validation rejected a pass in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_INVOKER_SOURCE_ANCHOR_V1.r1.codex_validation.json` because the capture contained only the one-line `Invoke-RestMethod` call. This proves a provider call exists, but does not capture the provider invocation function boundary, prompt-body construction, response extraction, or model-output judgment point.
- `updated blocker`: APP-TOD-037 should not proceed to code or provider execution from a one-line anchor. The next proof must capture the provider invocation and response extraction function boundaries, then name the exact hook where a future provider-judgment artifact could be produced.
- `provider function-boundary source-anchor proof`: TOD reran the source-anchor work with explicit ranges. `TOD_MODEL_UTILIZATION_PROVIDER_INVOCATION_FUNCTION_SOURCE_ANCHOR_V1.r2.latest.json` captured `Invoke-ConversationRequest`; `TOD_MODEL_UTILIZATION_PROVIDER_RESPONSE_EXTRACTION_SOURCE_ANCHOR_V1.r2.latest.json` captured `Get-ReplyTextFromResponse`; and `TOD_MODEL_UTILIZATION_PROVIDER_CHAT_ACTION_PATH_SOURCE_ANCHOR_V1.r1.latest.json` captured the `chat` action path that builds request messages, probes reachability, invokes the provider, extracts `reply_text`, and returns the local payload.
- `updated truth`: Codex validation passed the provider-boundary rung in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_FUNCTION_BOUNDARY_SOURCE_ANCHOR_V1.codex_validation.json`. This is supporting Model Utilization evidence, not APP-TOD-037 retirement. TOD now knows where provider invocation and response extraction happen, but has not yet published a provider-judgment artifact or engineering episode.
- `hook-map materialization R1`: TOD attempted to publish `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_HOOK_MAP_V1.r1.latest.json`. Local execution completed, but the artifact was only `tod_read_only_task_context_proof`; it did not contain semantic hook-map fields. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_HOOK_MAP_V1.r1.codex_validation.json`.
- `bridge runnability classification`: A follow-up source-anchor inspection captured `scripts/TOD.ps1` lines 16386-16456 and proved `run-bridge-request` supports only get-capabilities, get-execution-readiness, get-state-bus, get-version, ping-mim, safe_home, scan_pose, and capture_frame; it does not support `execute-chat-task`. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_EXECUTE_CHAT_TASK_BRIDGE_RUNNABILITY_CLASSIFICATION_V1.r1.codex_validation.json`.
- `direct read-only audit R1`: TOD avoided the bridge dead end and used a `report_only` direct read-only audit path. It wrote `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_HOOK_MAP_DIRECT_READONLY_AUDIT_V1.r1.latest.json` and correctly rejected capability credit, but only preserved the first requested field, `provider_invocation_hook`. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_HOOK_MAP_DIRECT_READONLY_AUDIT_V1.r1.codex_validation.json`.
- `updated blocker`: the next smallest blocker is multi-field contract preservation in the direct read-only audit lane. This is Evidence/Runtime support for Engineering learning, not an Engineering implementation failure.

Next smaller training rung:

`TOD-READONLY-AUDIT-MULTIFIELD-CONTRACT-PRESERVATION-V1`

Acceptance:

- TOD must use a direct local read-only audit path, not the unsupported `execute-chat-task` bridge runner.
- TOD must prove whether multiple `Required output fields:` entries survive into the artifact.
- Required test fields: `provider_invocation_hook`, `response_extraction_hook`, `chat_action_hook`, `missing_provider_judgment_publication_hook`, `engineering_episode_boundary`, and `counts_as_engineering_implementation_credit`.
- TOD may pass by preserving all six fields and classifying them as missing, or by publishing a precise source-anchor blocker naming the parser/evaluator branch that drops fields after the first entry.
- TOD must not modify source code and must not create a bounded edit packet.
- TOD must preserve the distinction between Engineering learning and Runtime plumbing: this rung is support infrastructure for future model supervision, not Engineering independence credit.

R1 result:

- TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_MULTIFIELD_CONTRACT_PRESERVATION_V1.r1.latest.json`.
- Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_MULTIFIELD_CONTRACT_PRESERVATION_V1.r1.codex_validation.json` rejected capability credit.
- The six requested hook-map field names survived in `required_fields`, but all six were still missing as materialized values.
- This shifts the APP-TOD-037 blocker from field-name preservation to semantic field-value materialization.

Follow-up R1 result:

- TOD attempted `TOD-MODEL-UTILIZATION-HOOK-MAP-FIELD-VALUE-MATERIALIZATION-V1-R1`.
- Local execution published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_HOOK_MAP_FIELD_VALUE_MATERIALIZATION_V1.r1.latest.json`, but the artifact was only `tod_read_only_task_context_proof`.
- Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_HOOK_MAP_FIELD_VALUE_MATERIALIZATION_V1.r1.codex_validation.json` rejected capability credit because the semantic hook-map fields were absent even though `validation.required_fields_present=true`.
- Source-anchor follow-up captured the read-only task-context proof lane marker and prevention lesson in `TOD_READONLY_TASK_CONTEXT_REQUIRED_FIELDS_FALSE_POSITIVE_SOURCE_ANCHOR_V1.r1.latest.json` and `TOD_READONLY_TASK_CONTEXT_PROOF_PREVENTION_LESSON_SOURCE_ANCHOR_V1.r1.latest.json`.
- A repair-packet attempt, `TOD-READONLY-TASK-CONTEXT-REQUIRED-FIELDS-FALSE-POSITIVE-REPAIR-PACKET-V1-R1`, was also downgraded into a task-context proof. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_TASK_CONTEXT_REQUIRED_FIELDS_FALSE_POSITIVE_REPAIR_PACKET_V1.r1.codex_validation.json` classifies this as runtime lane-selection blocking engineering packet materialization.

New immediate prerequisite:

`TOD-REPAIR-PACKET-ARTIFACT-LANE-TARGET-DISAMBIGUATION-V1`

Acceptance:

- TOD must distinguish source file, input evidence artifact, requested output artifact, and bounded edit target.
- TOD must not satisfy an implementation-shaped repair-packet task by publishing `tod_read_only_task_context_proof`.
- TOD must prove which local execution lane should own repair-packet artifact synthesis before applying any source patch.
- The proof must name the selected lane, rejected lanes, target_file, output artifact path, validation command, and no-source-mutation status.
- This remains Runtime/Evidence support debt; Engineering credit starts only after TOD publishes a real current-code packet or precise inspected blocker from that proof.

R1 result:

- TOD ran `TOD-REPAIR-PACKET-ARTIFACT-LANE-TARGET-DISAMBIGUATION-V1-R1`.
- The generic read-only audit lane preserved all required disambiguation field names but classified every value as missing in `runtime_remote_training/read_only_audit_artifacts/TOD_REPAIR_PACKET_ARTIFACT_LANE_TARGET_DISAMBIGUATION_V1.r1.latest.json`.
- A packet-formation retry then routed as `codex_required`; the Codex wrapper did not execute and local fallback failed, so no packet candidate was produced.
- TOD captured `scripts/TOD.ps1::Resolve-LocalExecutionSuitability` and the default `$classification = 'codex_required'` assignment in `TOD_PACKET_FORMATION_CODEX_REQUIRED_SELECTOR_SOURCE_ANCHOR_V1.r1.latest.json` and `TOD_PACKET_FORMATION_DEFAULT_CODEX_REQUIRED_ASSIGNMENT_SOURCE_ANCHOR_V1.r1.latest.json`.
- A semantic source-audit attempt from those selector anchors produced schema-valid but generic text. Codex validation rejected it in `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_CODEX_REQUIRED_SELECTOR_SEMANTIC_AUDIT_V1.r1.codex_validation.json`.
- TOD captured the canned semantic audit text source at `scripts/engines/LocalExecutionEngine.ps1:7966` in `TOD_SEMANTIC_SOURCE_AUDIT_CANNED_TEXT_SOURCE_ANCHOR_V1.r1.latest.json`.

New active blocker:

`semantic_audit_content_specificity_failure`

Meaning:

- The lane can publish a schema-complete semantic audit artifact.
- The content can still be generic and unrelated to the inspected source anchors.
- This cannot support Model Utilization or Engineering Corpus quality until the artifact body is evidence-specific.

Next smaller training rung:

`TOD-SEMANTIC-SOURCE-AUDIT-CONTENT-SPECIFICITY-V1`

Acceptance:

- Given source-anchor artifacts for `Resolve-LocalExecutionSuitability` and `$classification = 'codex_required'`, TOD must publish a source-specific analysis that mentions those anchors.
- Generic contract-collector text must be rejected.
- The result must not modify source code.
- The proof must state why this is Runtime/Evidence support debt, not Engineering independence credit.

R1 result:

- TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_SOURCE_AUDIT_CONTENT_SPECIFICITY_V1.r1.latest.json`.
- Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_SOURCE_AUDIT_CONTENT_SPECIFICITY_V1.r1.codex_validation.json` rejected capability credit.
- The artifact mentions the selector source anchors (`Resolve-LocalExecutionSuitability` and `$classification = 'codex_required'`) and the canned semantic-audit text source, but it does not answer `selector_function_seen`, `default_codex_required_seen`, `canned_semantic_text_seen`, `source_specific_analysis_possible`, `generic_output_rejected`, `runtime_evidence_support_debt`, or `counts_as_engineering_implementation_credit` as field values.
- This proves a narrower blocker: evidence references are present, but evidence-derived field-value synthesis is not.

Follow-up R1 result:

- TOD ran `TOD-SEMANTIC-AUDIT-FIELD-VALUE-VS-FIELD-NAME-DISCRIMINATION-V1-R1`.
- The generated artifact `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_AUDIT_FIELD_VALUE_VS_FIELD_NAME_DISCRIMINATION_V1.r1.latest.json` correctly set `pass_or_reject=reject` and `validation.required_fields_present=false`, but the outer `execute-chat-task` summary still reported `decision=pass/status=completed`.
- Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_AUDIT_FIELD_VALUE_VS_FIELD_NAME_DISCRIMINATION_V1.r1.codex_validation.json` classifies this as `execution_summary_passed_rejected_artifact`.
- TOD then ran `TOD-EXECUTION-SUMMARY-MUST-DEFER-TO-ARTIFACT-VALIDATION-V1-R1`; its artifact again rejected while the outer summary reported pass. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_EXECUTION_SUMMARY_MUST_DEFER_TO_ARTIFACT_VALIDATION_V1.r1.codex_validation.json` keeps this as validation-truth precedence debt.
- TOD captured `scripts/TOD.ps1:21044` (`$reviewDecision = "pass"`) in `runtime_remote_training/read_only_audit_artifacts/TOD_EXECUTION_SUMMARY_PASS_DEFAULT_SOURCE_ANCHOR_V1.r1.latest.json`.
- TOD produced a packet candidate at `runtime_remote_training/tod_independent_resolution_attempts/TOD_EXECUTION_SUMMARY_ARTIFACT_VALIDATION_PRECEDENCE_PACKET_V1.latest.json`, but Codex validation in `runtime_remote_training/tod_independent_resolution_attempts/TOD_EXECUTION_SUMMARY_ARTIFACT_VALIDATION_PRECEDENCE_PACKET_V1.codex_validation.json` rejected engineering credit because `new_text` only adds a training marker comment and does not implement artifact-validation precedence.

Updated active blocker:

`engineering_patch_synthesis_from_diagnosis`

Meaning:

- TOD can expose the false-success fault and produce a reversible packet shell.
- TOD cannot yet synthesize the behavior-changing patch from the diagnosis.
- This is the exact line between Runtime/Evidence support and Engineering independence.

Next smaller training rung:

`TOD-ENGINEERING-PATCH-SYNTHESIS-FROM-DIAGNOSIS-V1`

Acceptance:

- Given a source anchor and a diagnosis, TOD must produce a bounded packet whose `new_text` implements the requested behavior, not a marker comment.
- The packet must preserve exact current `old_text`, target the inspected source file, include validation command, rollback note, closure evidence, prevention lesson, and no source mutation during formation.
- The packet must classify itself as not yet engineering implementation credit until applied and validated.
- If TOD cannot synthesize behavior-changing `new_text`, it must publish a precise blocker naming the missing engineering-model/runtime support.

R1 result:

- TOD attempted `TOD-ENGINEERING-PATCH-SYNTHESIS-FROM-DIAGNOSIS-V1-R1`.
- The command timed out after 120 seconds and did not write `runtime_remote_training/tod_independent_resolution_attempts/TOD_ENGINEERING_PATCH_SYNTHESIS_FROM_DIAGNOSIS_V1.r1.latest.json`.
- Codex validation in `runtime_remote_training/tod_independent_resolution_attempts/TOD_ENGINEERING_PATCH_SYNTHESIS_FROM_DIAGNOSIS_V1.r1.codex_validation.json` records `packet_body_synthesis_timeout_no_artifact`.
- This is not a reason to add more packet routing. It is a reason to define the minimal Engineering Runtime contract: source excerpt, diagnosis, requested behavior delta, candidate patch, self-critique, validation plan, and reject/accept judgment.

New immediate objective:

`TOD-ENGINEERING-RUNTIME-MINIMAL-PATCH-SYNTHESIS-CONTRACT-V1`

Acceptance:

- Define the smallest local engineering-runtime episode contract needed to turn source context plus diagnosis into a bounded patch candidate.
- Separate provider/model output from TOD's engineering judgment.
- Require TOD to reject marker-comment packets when the requested behavior is code logic.
- Require an Examiner/Auditor validation hook before any model-generated packet is applied.
- Produce an artifact only; do not patch source code in this contract-definition rung.

Resume target after lane proof:

`TOD-READONLY-CONTRACT-FIELD-PRESERVATION-FOR-MODEL-UTILIZATION-V1`

Immediate sub-rung:

`TOD-SOURCE-ANCHOR-SEMANTIC-DELTA-PRESERVATION-V1`

Acceptance:

- Given a source-anchor observation artifact with current `exact_text`, TOD must state the current purpose of that anchor.
- TOD must state the requested behavior delta separately from the current purpose.
- TOD must reject any candidate `new_text` that comes from a different function, switch branch, contract, or responsibility.
- TOD must publish a candidate only when `old_text` and `new_text` preserve the same source boundary and differ only by the requested behavior.
- The proof must include no source mutation, validation evidence, rollback note, and a prevention lesson.

Blocking prerequisite:

`TOD-REQUESTED-ARTIFACT-TYPE-AND-INPUT-PRESERVATION-V1`

Acceptance:

- Given an explicit input artifact and required artifact type, TOD must not substitute a patch-evidence lane or unrelated fresh route patch.
- TOD must either produce the requested artifact type or publish a precise blocker naming `unsupported_required_artifact_type`, the requested input artifact, requested output artifact, and the wrong lane that would otherwise be selected.
- The result must preserve task mode, objective ID, task ID, no-source-mutation evidence, validation command, and prevention lesson.
- Only after this passes should TOD retry `TOD-SOURCE-ANCHOR-SEMANTIC-DELTA-PRESERVATION-V1`.

New smaller prerequisite after R1:

`TOD-TASK-SPECIFIC-ARTIFACT-CONTRACT-LANE-DEFINITION-V1`

Acceptance:

- TOD must define the minimal learned artifact contract for requested input/artifact preservation without modifying product source files.
- TOD must publish either a supported preservation-review artifact or a precise blocker preserving requested input artifact, requested output artifact, required artifact type, selected lane, and reason for unsupported scope.
- The proof must not use `cleanup_holds` patches or route-patch classification as substitute evidence.
- The proof must keep Codex as validator, not artifact author.

Backed-up supported rung after lane-definition R1:

`TOD-READONLY-GENERIC-BLOCKER-TO-ARTIFACT-CONTRACT-SUMMARY-V1`

Acceptance:

- Use only a supported generic read-only audit artifact type.
- Summarize the unsupported requested artifact type as evidence, without trying to create a new custom artifact type.
- Preserve requested input artifact, requested output artifact, selected lane, unsupported reason, and next learned lane proposal inside the generic artifact body.
- Do not modify product source files.
- Do not classify route patches or `cleanup_holds` patches.

Next inspection rung after generic-summary R1:

`TOD-GENERIC-READONLY-AUDIT-EVIDENCE-FIELD-PRESERVATION-V1`

Acceptance:

- Inspect the current generic read-only audit artifact producer.
- Identify why contract-specific fields are not copied from validation artifacts.
- Publish a source-anchor observation for the responsible current-code block.
- Do not modify product source files in the inspection rung.
- The source-anchor observation must name the field-preservation delta needed for a future bounded patch.

Blocking prerequisite after field-preservation R1/R2:

`TOD-SOURCE-ANCHOR-LANE-SELECTION-PRESERVATION-V1`

Acceptance:

- A read-only `source_anchor_observation` task must reach `Invoke-LocalExecutionSourceAnchorObservation`.
- The source file must be treated as inspected source, not a bounded edit target.
- The input evidence artifact and output artifact must be treated as evidence/output, not competing target files.
- TOD must publish `artifact_type=tod_source_anchor_observation` with `exact_text`, `start_line`, `end_line`, and no source mutation.
- Only after this passes should TOD retry `TOD-GENERIC-READONLY-AUDIT-EVIDENCE-FIELD-PRESERVATION-V1`.

New diagnostic sub-rung after lane-selection R1:

`TOD-SOURCE-ANCHOR-STRUCTURED-CATEGORY-CONTEXT-PROOF-V1`

Acceptance:

- Structured task category must be `source_anchor_observation`.
- The proof must show whether local execution sees that structured category or downgrades/intercepts it before source-anchor dispatch.
- Prose scope text must not be used as the authority for task category.
- The result must publish either a diagnostic context proof or a precise blocker naming the intercepting branch.
- No source files may be modified.

## 2026-07-24 Local Engineering Intelligence Path Decision

Decision artifact:

`runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_INTELLIGENCE_PATH_DECISION_V1.latest.json`

Verdict:

Adopt the TOD Local Engineering Intelligence path with scope control.

Policy:

- Engineering Corpus is the primary product.
- Local Engineering Runtime starts early as a provider-neutral context, contract, sandbox, and episode recorder.
- Model Utilization is a measured support skill, not a substitute for TOD engineering ownership.
- Runtime plumbing is repaired only far enough to unblock engineering demonstrations.
- Borrowed capability must be reported by category: engineering, runtime, governance, evidence, validation, coordination, and model utilization.

Immediate attempted rung:

`TOD-ENGINEERING-RUNTIME-MINIMAL-PATCH-SYNTHESIS-CONTRACT-V1-R1`

Result:

Blocked. TOD generated a correct read-only task package, but no contract artifact was produced. Execution reported the wrapper-only blocker:

`Codex wrapper only accepted the packaged prompt without executing it, and the safe local fallback could not execute this task scope.`

Codex validation:

`runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_RUNTIME_MINIMAL_PATCH_SYNTHESIS_CONTRACT_V1.r1.codex_validation.json`

Current blocker:

`artifact_only_engineering_contract_task_not_executed_by_local_lane`

Next smaller rung:

`TOD-ENGINEERING-CONTRACT-ARTIFACT-LANE-SUPPORT-V1`

Acceptance:

- Identify the current branch that sends this task class to wrapper-only execution.
- Publish a source-anchor observation naming the missing local artifact lane.
- No product source mutation in the inspection rung.
- Preserve the requested output artifact type and task category.
- Name the smallest behavior change needed before retrying the contract-definition task.

## 2026-07-24 APP-TOD-037 Source-Anchor And Detector Continuation

TOD ran the next smaller rungs under `APP-TOD-037`:

- `TOD-READONLY-ARTIFACT-TYPE-LANE-PRECEDENCE-SOURCE-ANCHOR-V1-R3`
- `TOD-READONLY-AUDIT-TASK-DETECTOR-SOURCE-ANCHOR-V1-R1`
- `TOD-READONLY-AUDIT-PATH-EXTRACTOR-SOURCE-ANCHOR-V1-R1`
- `TOD-READONLY-EVIDENCE-COMPARISON-DETECTOR-PACKET-V1-R1`

Validated results:

- Source-anchor observation now works when TOD receives a complete source-file and anchor contract.
- TOD captured `Invoke-LocalExecutionReadOnlyAuditArtifact`, `Test-LocalExecutionReadOnlyAuditArtifactTask`, and `Get-LocalExecutionReadOnlyAuditArtifactPaths` from current source.
- The first-loss point is now concrete: the evidence-comparison implementation can read `Package Path` / `Compare Artifact`, but the lane detector is reached only after `Get-LocalExecutionReadOnlyAuditArtifactPaths` finds a JSON input path and output path.
- The extractor supports `Input`, `Input Artifact`, `Input Evidence`, `Evidence Artifact`, and `Review Artifact` as JSON inputs, but does not support `Package Path` or `Compare Artifact` as detector input aliases.
- TOD attempted a bounded detector repair packet, but no ready packet artifact was published and the local fallback reported rollback after failed validation.

Current classification:

`source-anchor inspection = scaffolded/supporting pass`

`bounded repair packet materialization = still blocked`

Next smaller rung:

`TOD-READONLY-EVIDENCE-COMPARISON-DETECTOR-PACKET-MATERIALIZATION-V2`

Acceptance:

- Use the three source-anchor artifacts as evidence.
- Produce a `tod_packet_formation_artifact` with `packet_candidate_ready=true`, or a precise blocker.
- The packet must target only `scripts/engines/LocalExecutionEngine.ps1`.
- The packet must include exact current `old_text`, different `new_text`, `validation_command`, expected evidence, closure evidence, and prevention lesson.
- No local fallback rollback may count as success.
- A pass requires validation evidence, not wrapper acceptance.

Continuation result:

- `TOD-READONLY-EVIDENCE-COMPARISON-DETECTOR-PACKET-ANCHOR-SUITABILITY-V1-R1` passed as a narrow suitability review. It confirmed the detector anchor is unique in the target file, but not packet-ready without `insert_before_pattern`, `snippet`, and `validation_command`.
- `TOD-READONLY-EVIDENCE-COMPARISON-DETECTOR-PACKET-MATERIALIZATION-V2-R1` reported a completed bounded fallback, but did not publish the requested packet artifact.
- The focused `tests/TOD.ReadOnlyAuditRegression.Tests.ps1` suite passed, but a live retry of the package-comparison shape, `TOD-EVIDENCE-COMPARISON-LANE-PACKAGE-CATEGORY-PROOF-V1-R3`, still produced `artifact_type=tod_read_only_task_context_proof` instead of `tod_readonly_evidence_comparison`.

Updated blocker:

`read_only_evidence_comparison_package_path_regression_missing`

Next smaller rung:

`TOD-READONLY-EVIDENCE-COMPARISON-REGRESSION-TEST-PACKET-V1`

Acceptance:

- TOD must first create or inspect a regression test that asserts `Required Artifact Type: tod_readonly_evidence_comparison` with `Package Path`, `Compare Artifact`, and `Output` produces `artifact_type=tod_readonly_evidence_comparison`.
- The test must fail before the repair and pass after the repair.
- TOD must not count `tod_read_only_task_context_proof` as success for this scenario.
- Only after the failing regression is explicit should TOD attempt the detector/extractor repair.

Continuation result:

- TOD captured a test insertion source anchor and ran a packet-anchor suitability review.
- The suitability artifact correctly reported that packet synthesis still required `insert_before_pattern`, `snippet`, and `validation_command`.
- After those directives were supplied, the packet-synthesis attempt still did not publish the requested packet artifact.
- The resulting source diff did not contain the required `Package Path` / `Compare Artifact` / `tod_readonly_evidence_comparison` regression and appeared to reflect unrelated saved-route authority discovery test content.

Updated blocker:

`regression_test_packet_materialization_drifted_to_unrelated_fallback`

Next smaller rung:

`TOD-READONLY-EVIDENCE-COMPARISON-EXACT-PATCH-SYNTHESIS-DRILL-V1`

Acceptance:

- Use `Validation Pattern: exact_patch_synthesis_drill`.
- Produce `artifact_type=tod_exact_patch_synthesis_drill`.
- Preserve inspected files and current anchor evidence.
- Do not edit product or test source.
- Do not claim implementation credit.
- Block precisely on missing `old_text_new_text` if TOD cannot author the exact regression test patch.

2026-07-26 continuation: `TOD-ANCHOR-SPECIFIC-OLDTEXT-VERDICT-V1`

- R733 and R737 remain valid safety-verdict rejects. TOD correctly rejected blank `new_text` and generic validation-command candidates. No source mutation was allowed and no engineering independence credit was awarded.
- R740 through R740E exposed a routing/materialization weakness: source-anchor observation details supplied only in an attached prompt or package path were lost or overridden by the chat execution wrapper. The task was repeatedly normalized as `chat_execution` or lacked the `Source File`, `Anchor Pattern`, and output artifact directives needed by the local source-anchor lane.
- R740F passed after the source-anchor directives were carried in persisted request fields (`Description`, `Scope`, and `Acceptance Criteria`) instead of only the attached prompt. TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_ANCHOR_SPECIFIC_OLDTEXT_VERDICT_SOURCE_R740.latest.json` with `artifact_type=tod_source_anchor_observation`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `source_function=Invoke-LocalExecutionPacketQualityReview`, `no_code_changes=true`, and exact text containing both `old_text_found_in_source` and `$oldTextFound`.
- Validation: PowerShell parse passed for `scripts/engines/LocalExecutionEngine.ps1`; artifact schema and content checks passed.
- Classification: scaffolded runtime/evidence support pass. This does not reduce borrowed-capability ratio because Codex still shaped the successful persisted request fields and no source repair was attempted.

Updated blocker:

`source_anchor_directives_lost_when_only_package_path_supplied`

Next smaller rung:

`TOD-SOURCE-ANCHOR-DIRECTIVE-PERSISTENCE-INDEPENDENT-DEMO-V1`

Acceptance:

- TOD independently creates a fresh source-anchor observation task on a different safe target.
- The request must persist `Source File`, `Anchor Pattern`, output artifact path, and context sizing in the active request/package without Codex rewriting those fields.
- The local source-anchor lane must publish the requested artifact.
- The artifact must include exact source text, source function, line bounds, and `no_code_changes=true`.
- No source code may be modified.
- Borrowed-capability ratio may reduce only if TOD selects the fresh target, materializes the request shape, executes it, validates the artifact, and records the prevention lesson without Codex supplying the working prompt shape.

R741-R745 continuation:

- `R741`: TOD was asked to independently select a fresh safe source/anchor and publish a source-anchor artifact. It blocked with `blocked_missing_capability`; the task was too broad for the current local executor and TOD did not invent a target.
- `R742`: TOD backed up one rung and published `runtime_remote_training/tod_independent_resolution_attempts/TOD_SOURCE_ANCHOR_TARGET_SELECTION_R742.latest.json` with `status=no_candidate_available`. This is correct blocker honesty, not engineering independence.
- `R743`: TOD selected `scripts/engines/LocalExecutionEngine.ps1` from explicit R740F evidence and published `runtime_remote_training/tod_independent_resolution_attempts/TOD_SOURCE_ANCHOR_TARGET_SELECTION_R743.latest.json` with `status=candidate_selected`. This is scaffolded target-selection evidence because Codex named the evidence artifact.
- `R744C`: TOD selected a unique source anchor from the selected target and published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_ANCHOR_SELECTION_R744C.latest.json`. The selected anchor was `function New-LocalExecutionExactPatchSynthesisDrillArtifact {` at line 364 with `no_code_changes=true`.
- `R745`: TOD used the selected anchor and published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_OBSERVATION_FROM_SELECTED_ANCHOR_R745.latest.json` with `artifact_type=tod_source_anchor_observation`, source file `scripts/engines/LocalExecutionEngine.ps1`, source function `New-LocalExecutionExactPatchSynthesisDrillArtifact`, lines 304-424, exact source text, and `no_code_changes=true`.
- R745 limitation: the source-anchor observation artifact did not preserve the input evidence artifact reference to R744C, even though that reference was included in the request fields.
- Classification: scaffolded runtime/evidence support pass. TOD can now carry a TOD-selected target and anchor into source-anchor observation when Codex shapes the request fields, but full independent source-anchor directive persistence remains unproven.

Next smaller blocker:

`TOD-SOURCE-ANCHOR-OBSERVATION-LINEAGE-PRESERVATION-V1`

Acceptance:

- Given a source-anchor observation request with `Input Evidence Artifact`, TOD must preserve that input lineage in the published observation artifact.
- The proof must not modify source files.
- If the current observation lane does not support lineage preservation, TOD must publish a precise blocker naming the responsible artifact writer and the missing field.
- Borrowed-capability ratio may not decrease until lineage preservation, independent target selection, independent anchor selection, and observation execution pass together on a fresh target.

R746-R747 continuation:

- `R746`: TOD captured the current source-anchor observation writer in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_OBSERVATION_LINEAGE_WRITER_SOURCE_R746.latest.json`. The artifact identifies `Invoke-LocalExecutionSourceAnchorObservation` in `scripts/engines/LocalExecutionEngine.ps1` lines 3392-3572 with `no_code_changes=true`.
- Finding: the writer artifact construction preserves `objective_id`, `task_id`, source file/function, anchor pattern, exact text, line bounds, and validation. It does not include an input lineage field such as `input_evidence_artifact`.
- `R747`: TOD used the R746 source anchor to publish `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_OBSERVATION_LINEAGE_DELTA_R747.latest.json` as `tod_source_anchor_delta_proposal`. It correctly preserved `target_file=scripts/engines/LocalExecutionEngine.ps1`, `validation.source_anchor_valid=true`, and `no_source_code_modified=true`.
- R747 blocker: `autonomous_candidate_new_text_missing`. TOD did not synthesize a source patch and did not fabricate `candidate_new_text`.
- Classification: scaffolded evidence/runtime progress. The source of lineage loss is now concrete, but the behavior change still requires meaningful current-code delta synthesis or model-supervised patch generation.

Next smaller rung:

`TOD-LINEAGE-PRESERVATION-ENGINEERING-CONTEXT-PACKAGE-V1`

Acceptance:

- TOD packages R746/R747 into a `tod_engineering_context_package`.
- The package must include problem summary, source file, source function, observed failure, desired behavior, validation target, source-anchor artifact, and prohibited actions.
- The package must explicitly state that this is an engineering-context handoff, not source mutation.
- No source files may be modified.

R748-R749 continuation:

- `R748`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_ENGINEERING_CONTEXT_PACKAGE_R748.latest.json`, but the artifact missed `source_file` and `source_function`. The packager used the delta artifact as primary evidence and did not carry source-anchor identity forward.
- `R749`: TOD reran with R746 as the primary input and R747 as secondary review evidence. It published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_ENGINEERING_CONTEXT_PACKAGE_R749.latest.json` with `artifact_type=tod_engineering_context_package`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `source_function=Invoke-LocalExecutionSourceAnchorObservation`, observed failure, desired behavior, validation target, `no_code_changes=true`, and `independent_credit_requested=false`.
- Classification: scaffolded model-utilization support pass. TOD can package a source-anchor blocker into an engineering-context handoff when the source-anchor artifact is primary evidence.

Next smaller rung:

`TOD-LINEAGE-PRESERVATION-PROVIDER-REQUEST-V1`

Acceptance:

- TOD converts the R749 engineering context package into a provider request artifact.
- The provider request must preserve source file, source function, source-anchor artifact, desired behavior, validation target, rejection policy, and forbidden outputs.
- No source files may be modified.
- This remains Model Utilization support unless TOD later supervises the provider response, validates a bounded patch candidate, and applies it through the normal guarded path.

R750-R753 continuation:

- `R750`: TOD created a provider request but `provider_request_ready=false` because the model-utilization judgment step had not been supplied.
- `R751`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_MODEL_UTILIZATION_JUDGMENT_R751.latest.json` with `context_quality=provider_prompt_ready`, source file/function, `candidate_request_ready=true`, and no source mutation.
- `R752`: TOD retried the provider request with a human-friendly judgment label, but the provider-request lane did not parse it. The artifact again had `provider_request_ready=false`.
- `R753`: TOD used the lane's actual contract field, `Supporting Artifact: runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_MODEL_UTILIZATION_JUDGMENT_R751.latest.json`, and published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_PROVIDER_REQUEST_R753.latest.json` with `provider_request_ready=true`.
- Classification: model-utilization support pass. TOD preserved context, judgment, source anchor artifact, prompt messages, rejection policy, forbidden outputs, and no-source-mutation boundaries. This still does not count as implementation credit.

Next smaller rung:

`TOD-LINEAGE-PRESERVATION-PROVIDER-CANDIDATE-INVOCATION-V1`

Acceptance:

- TOD attempts provider candidate invocation from R753 through the supported local provider path.
- If a provider is reachable, TOD must publish the raw response and parsed candidate fields without applying source changes.
- If no provider is reachable, TOD must publish a precise provider/runtime blocker and name the next smallest model-utilization step.
- No source files may be modified.

R754-R760 continuation:

- `R754`: TOD attempted provider invocation from R753 and published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_PROVIDER_CANDIDATE_INVOCATION_R754.latest.json`. It correctly avoided source mutation, but `provider_called=false` and no candidate was available.
- Runtime check: the configured provider endpoint `http://127.0.0.1:8008/v1/models` was reachable from this machine, so the blocker was not external availability alone.
- `R755`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_PROVIDER_INVENTORY_R755.latest.json` with `real_provider_reachable=true`, `gpu_available=true`, and `usable_provider_hook=true`.
- `R756`: TOD retried invocation with R755 as `Supporting Artifact` and published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_PROVIDER_CANDIDATE_INVOCATION_R756.latest.json` with `provider_called=true`, `candidate_response_available=true`, and no source mutation.
- Candidate quality: R756's candidate was unsafe. It proposed changing a provider-request contract snippet rather than the current `Invoke-LocalExecutionSourceAnchorObservation` writer block, and retained a generic validation phrase.
- `R757`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_PROVIDER_CANDIDATE_VERDICT_R757.latest.json` with `verdict=reject`, `verdict_reason_code=rejected_old_text_not_found_in_current_source`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- `R758/R759`: TOD attempted replan with incorrect input/supporting roles. Both produced non-ready replans and exposed that the replan lane requires the verdict as primary input and provider request plus candidate invocation as `Supporting Artifact` entries.
- `R760`: TOD used the exact replan contract and published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_PROVIDER_CANDIDATE_REPLAN_R760.latest.json` with `prior_verdict=reject`, `prior_rejection_reason_code=rejected_old_text_not_found_in_current_source`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `source_anchor_artifact=runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_OBSERVATION_LINEAGE_WRITER_SOURCE_R746.latest.json`, and `provider_request_ready_for_retry=true`.
- Classification: meaningful model-utilization support progress. TOD supervised and rejected bad provider output and generated a retry-ready replan. This still does not count as engineering implementation credit until a safe candidate is accepted, applied through the guarded path, and validated.

Next smaller rung:

`TOD-LINEAGE-PRESERVATION-PROVIDER-RETRY-CANDIDATE-V1`

Acceptance:

- TOD turns R760 into a retry provider request.
- TOD invokes the provider using the retry request and provider inventory.
- TOD must reject any candidate whose `old_text` is not exact current source from the R746 source-anchor artifact or whose validation command remains generic.
- No source files may be modified unless a later accepted packet passes the normal source-mutation gate.

R761-R763 continuation:

- `R761`: TOD converted retry-ready R760 into `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_RETRY_PROVIDER_REQUEST_R761.latest.json` with `provider_request_ready=true` and the R746 source-anchor artifact included.
- `R762`: TOD invoked the provider again and published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_RETRY_PROVIDER_INVOCATION_R762.latest.json` with `provider_called=true` and `candidate_response_available=true`.
- Candidate quality: R762 again produced a wrong-boundary candidate. It edited the anchor-selection semantic rejection message and retained a generic validation phrase instead of modifying `Invoke-LocalExecutionSourceAnchorObservation`.
- `R763`: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_LINEAGE_PRESERVATION_RETRY_PROVIDER_VERDICT_R763.latest.json` with `verdict=reject`, `verdict_reason_code=rejected_old_text_not_found_in_current_source`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- Updated blocker: provider requests include the source-anchor artifact path, but not the actual source-anchor exact text inline. The local provider appears unable to reliably use an artifact path as source context.
- Classification: model supervision pass, implementation still blocked. TOD correctly rejected two unsafe provider candidates before mutation.

Next smaller rung:

`TOD-PROVIDER-PROMPT-SOURCE-ANCHOR-INLINE-CONTEXT-V1`

Acceptance:

- TOD must create a provider request or provider-context package that includes the R746 source-anchor `exact_text` inline in the prompt messages or model context.
- The provider prompt must explicitly instruct the model to use that inline exact text as `old_text`.
- The prompt must reject candidates that edit any function other than `Invoke-LocalExecutionSourceAnchorObservation`.
- No source files may be modified.
- Only after this passes should TOD retry provider invocation.

R764-R782 continuation:

- `R764`: TOD attempted a read-only diagnosis of provider source-anchor drift, but the evidence-comparison lane blocked with `comparison_paths_missing`. Lesson: comparison artifacts require explicit `Left Artifact` and `Right Artifact`, not generic input/supporting wording.
- `R765C`: TOD captured the provider invocation builder source in `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_BUILDER_SOURCE_R765C.latest.json`, proving the provider is already given literal source-anchor text but can still drift to the wrong source surface.
- `R766B-R768`: TOD packaged the provider-prompt drift as engineering context, model-utilization judgment, and a retry-ready provider request. This preserved source file, source anchor, observed failure, desired behavior, and no-source-mutation boundaries.
- `R769-R774`: TOD invoked the local provider and rejected two unsafe candidates before mutation. R769 returned blank `new_text` while copying prompt-builder text as `old_text`; R773 returned identical `old_text` and `new_text` plus a generic validation command.
- `R775-R776E`: TOD discovered that its first source-observation retry used the wrong task shape. The successful shape was `Task Type: inspection` and `Task Category: source_anchor_observation`; R776E captured the provider replan lane source in `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REPLAN_SOURCE_ANCHOR_R776E.latest.json`.
- Control-plane repair: after TOD exposed the precise blocker, Codex added rejection-specific replan instructions for `rejected_blank_new_text`, `rejected_no_delta_candidate`, and `rejected_old_text_not_found_in_current_source` in `scripts/engines/LocalExecutionEngine.ps1`.
- `R777/R778/R782`: TOD verified the repair by publishing branch-specific replan artifacts for no-delta, blank-new-text, and wrong-surface/stale-old-text failures. Validation passed with PowerShell parse and JSON readback checks for all three revised instructions.
- `R779-R781`: TOD retried the provider with the no-delta-specific instruction. The provider still produced an unsafe code-fence candidate; TOD rejected it before mutation with `rejected_old_text_not_found_in_current_source`.
- Classification: guided/scaffolded model-utilization supervision progress. TOD can now preserve context, invoke the provider, reject unsafe output, replan with rejection-specific coaching, and repair task-shape routing errors. This does not retire borrowed engineering implementation debt because TOD still cannot independently synthesize safe behavior-changing `new_text` or accept/apply/validate a source patch through the guarded mutation path.

Next smaller rung:

`TOD-PROVIDER-REPLAN-VALIDATION-SPECIFICITY-V1`

Acceptance:

- TOD must repair or demonstrate a request/replan path that carries an executable validation command instead of the generic placeholder phrase.
- TOD must prove the provider request rejects or avoids code-fence-only, prompt-template, no-delta, and wrong-surface old_text candidates.
- TOD must preserve source-anchor exact text and target surface without requiring Codex to author the candidate patch.
- No source mutation credit may be granted until a later candidate passes verdict, applies through the guarded source-mutation path, and validates.

R1-R7 result:

- `R1` blocked correctly with `source_anchor_not_found` after an over-escaped anchor string. Lesson: failed source anchors are blockers, not progress.
- `R2` and `R3` proved that too-narrow source anchors can capture only one line and are insufficient for semantic diagnosis.
- `R4` showed the generic report-only lane could reject missing semantic fields but could not synthesize the multi-artifact validation-specificity diagnosis. This is training debt, not a pass.
- Codex made a narrow control-plane repair in `scripts/engines/LocalExecutionEngine.ps1` after TOD exposed the blocker: inherited generic validation commands are now converted to executable commands for known source file types before the replan artifact is written.
- `R7` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REPLAN_VALIDATION_SPECIFICITY_R7.latest.json`, proving `prior_rejection_reason_code=rejected_old_text_not_found_in_current_source`, `provider_request_ready_for_retry=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, and a non-generic PowerShell parser `validation_command`.
- Codex executed the `R7` artifact's generated validation command successfully: `parse=passed`.

Classification: guided control-plane pass. This retires the validation-specificity sub-rung but does not retire APP-TOD-037 because Codex authored the repair and TOD still has not produced an accepted behavior-changing provider candidate or source mutation.

Next smaller rung:

`TOD-PROVIDER-CANDIDATE-STUB-RETRY-FROM-REPLAN-V1`

Acceptance:

- Build a provider retry request from `TOD_PROVIDER_REPLAN_VALIDATION_SPECIFICITY_R7.latest.json`.
- Invoke the local provider with the concrete validation command carried through.
- Reject unsafe provider output if it is prompt-template, code-fence-only, no-delta, wrong-surface old_text, blank new_text, or generic validation.
- Do not mutate source unless the candidate passes verdict and the generated validation command executes.

R8-R16 result:

- `R8` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_REQUEST_FROM_REPLAN_R8.latest.json`, preserving the target file, source-anchor artifact, prompt messages, and non-generic validation command.
- `R9` and `R10` showed the provider invocation path could preserve evidence roles, but `R10` failed provider execution with an HTTP 500 while still proving `supporting_artifact_read=true` and no source mutation.
- `R12` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_VERDICT_R12.latest.json`, rejecting the failed invocation with `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, and `no_source_code_modified=true`.
- `R13` and `R14` exposed a replan-writer gap: the replan artifact was rejection-aware but did not preserve `prompt_budget_strategy`, `source_excerpt_strategy`, or `strict_json_strategy` as semantic fields.
- Codex made two narrow control-plane repairs after TOD exposed specific blockers: `scripts/engines/LocalExecutionEngine.ps1` now emits prompt-budget/source-excerpt/strict-JSON strategy fields on provider replans, and `scripts/TOD.ps1` admits `tod_engineering_provider_candidate_invocation` as a supported read-only artifact-write type so invocation tasks do not get misclassified as bounded source edits.
- `R14B` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_STRICT_JSON_REPLAN_R14B.latest.json`, proving all three strategy fields are populated, `provider_request_ready_for_retry=true`, and the emitted parser validation command runs with `parse=passed`.
- `R15B` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_INVOCATION_R15B.latest.json`, proving the local provider was actually called (`provider_called=true`) and returned an unsafe fenced/truncated candidate with blank `new_text`; no source code was modified.
- `R16` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_VERDICT_R16.latest.json`, correctly rejecting the real provider output with `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, `counts_as_engineering_implementation_credit=false`, and `no_source_code_modified=true`.

Classification: scaffolded model-utilization supervision pass. TOD can now carry a concrete validation command, invoke the local provider, and reject unsafe provider output before mutation. APP-TOD-037 remains open because Codex authored the control-plane repairs and TOD still has not produced, accepted, applied, and validated a safe behavior-changing provider candidate.

Next smaller rung:

`TOD-PROVIDER-CANDIDATE-SMALL-EXCERPT-STRICT-JSON-RETRY-V1`

Acceptance:

- Build a provider request from `TOD_PROVIDER_PROMPT_BUDGET_STRICT_JSON_REPLAN_R14B.latest.json` that sends only the smallest relevant source excerpt instead of the full source-anchor exact text.
- Require strict JSON without markdown fences or prose wrappers.
- Invoke the local provider.
- Reject malformed, fenced, truncated, blank, no-delta, or wrong-surface output before source mutation.
- Grant no implementation credit unless a later candidate passes verdict, applies through the guarded source-mutation path, and validates.

R17-R18 result:

- Codex made a narrow prompt-budget control-plane repair in `scripts/engines/LocalExecutionEngine.ps1`: provider invocation now keeps full source evidence for validation but sends a smaller prompt excerpt when a replan carries `prompt_budget_strategy`; invocation artifacts record `source_anchor_prompt_was_excerpted`, `source_anchor_prompt_length`, and `source_anchor_full_length`.
- `R17` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SMALL_EXCERPT_INVOCATION_R17.latest.json`, proving the prompt was excerpted from 16,031 characters to 3,600 and the local provider was called. The provider returned parseable JSON content, but still wrapped it in markdown fences and left both `old_text` and `new_text` blank while reporting no safe behavior-changing patch.
- `R18` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SMALL_EXCERPT_VERDICT_R18.latest.json`, rejecting the provider output with `verdict=reject`, `verdict_reason_code=rejected_blank_old_text`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, `counts_as_engineering_implementation_credit=false`, and `no_source_code_modified=true`.

Classification: scaffolded provider-supervision safety pass. TOD can now route a prompt-budgeted local-provider attempt and reject non-source-grounded output. APP-TOD-037 remains open because the local model did not produce a safe behavior-changing candidate and Codex authored the prompt-budget support.

Next smaller rung:

`TOD-PROVIDER-SOURCE-SPECIFIC-CANDIDATE-GENERATION-V1`

Acceptance:

- Select a tiny source excerpt with an obvious, harmless behavior-changing target.
- Ask the local provider for strict JSON using only that excerpt.
- Reject fenced/malformed/blank/no-delta output.
- Accept no source mutation unless `old_text` is exact current source, `new_text` is behavior-changing, and validation executes.

R19-R38B result:

- `R19B` proved source-anchor tasks must use line-start directives; `R19C` captured a real function source anchor from `scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionSourceAnchorObservation`.
- `R20C`, `R21`, and `R22` produced a context package, model-utilization judgment, and provider request. `R23` called the local provider, and `R24` correctly rejected the first source-specific candidate with `rejected_old_text_not_found_in_current_source`.
- Codex made a narrow control-plane repair after TOD exposed a precise blocker: provider retry requests now preserve `source_function` and inline source-anchor body from the source-anchor artifact, and replans preserve task-specific observed-failure/desired-behavior details.
- `R25B` and `R26B` verified that the repaired provider request preserved `source_function=Invoke-LocalExecutionSourceAnchorObservation`, carried an inline authoritative source-anchor body, and kept a concrete parser validation command. `R27B/R28B` still rejected the provider output with `rejected_old_text_not_found_in_current_source`.
- TOD backed up one rung to a smaller one-line source anchor in `R29`. `R30-R34` produced a tiny-line context/request/invocation and correctly rejected the provider output with `rejected_generic_validation_command`.
- `R35-R38` replanned for concrete validation, retried the provider, and initially accepted a candidate. Codex validation caught that acceptance as false-positive because the validation command used `$loaded` instead of a real verifier. Codex then repaired the verdict guard so accepted candidates must use an allowed verifier pattern (`Parser.ParseFile`, `py_compile`, `json.tool`, `pytest`, or `Invoke-Pester`) and reference the target source.
- `R38B` rejudged the same provider candidate and correctly rejected it with `rejected_validation_command_not_allowed_verifier`.

Classification: scaffolded provider-supervision safety progress. TOD is improving at supervising local-model output: it can build smaller source anchors, call the provider, reject unsafe candidates, replan after rejection, and detect a false-accept validation-policy gap. This still does not retire APP-TOD-037 because Codex authored the control-plane repairs and no provider-generated source mutation has passed guarded apply plus validation.

Next smaller rung:

`TOD-PROVIDER-VALIDATION-AWARE-CANDIDATE-RETRY-V1`

Acceptance:

- Build a provider retry request from `TOD_PROVIDER_SOURCE_SPECIFIC_TINY_LINE_RETRY_VERDICT_R38B.latest.json`.
- Require an allowed verifier command that references the target source file.
- Reject any candidate whose validation command is not one of the allowed verifier patterns.
- If a candidate passes verdict, run a dry-run mutation/validation proof before source mutation credit is granted.
- Grant no independent implementation credit unless TOD applies and validates a safe source mutation without Codex authoring the candidate or patch.

R39-R42 result:

- `R39` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_AWARE_REPLAN_R39.latest.json`, preserving the new rejection reason `rejected_validation_command_not_allowed_verifier` and carrying a concrete Parser.ParseFile validation requirement.
- `R40` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_AWARE_REQUEST_R40.latest.json` with `provider_request_ready=true`.
- `R41` called the local provider and published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_AWARE_INVOCATION_R41.latest.json`.
- `R42` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_AWARE_VERDICT_R42.latest.json`, rejecting the provider output again with `verdict_reason_code=rejected_validation_command_not_allowed_verifier`. The shell wrapper timed out at 120 seconds, but the artifact was written and read back successfully.

Classification: safety guard pass, provider quality still insufficient. TOD can now prevent a local provider from advancing a candidate whose validation command is concrete-looking but not an allowed verifier. APP-TOD-037 remains open because no provider candidate has passed verdict, dry-run mutation, and validation.

Next smaller rung:

`TOD-PROVIDER-VALIDATION-COMMAND-PROMPT-CONTRACT-V1`

Acceptance:

- Inspect the provider request prompt and invocation artifact from R40/R41.
- Determine why the provider keeps returning dot-source/loaded validation commands instead of Parser.ParseFile.
- Publish a prompt-contract repair packet or precise blocker.
- Do not mutate source until the prompt contract can produce a candidate whose validation command passes the allowed-verifier verdict gate.

R1-R7B result:

- `R1` attempted the validation-command prompt-contract audit through the generic report-only lane, but the artifact did not answer the requested semantic fields.
- `R2` captured the relevant source area for the provider validation-command prompt contract.
- `R3` attempted a bounded prompt-contract packet and rolled back with `local_fallback_validation_failed`; this was a valid TOD attempt with a precise blocker.
- Codex then made a narrow control-plane repair in `scripts/engines/LocalExecutionEngine.ps1` after TOD exposed the blocker: provider replans now convert inherited validation placeholders and prior `rejected_validation_command_not_allowed_verifier` failures into executable source-file verifier commands, and provider requests state allowed validation verifier patterns instead of teaching dot-source `loaded` smoke checks.
- `R4D` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_REPLAN_R4D.latest.json`, proving the replan preserved `target_file=scripts/engines/LocalExecutionEngine.ps1`, `source_anchor_artifact`, `prior_rejection_reason_code=rejected_validation_command_not_allowed_verifier`, and an executable Parser.ParseFile validation command.
- `R5` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_REQUEST_R5.latest.json`, proving the provider request carried a Parser.ParseFile validation command, required allowed verifier patterns, and explicitly warned against dot-source `loaded` smoke checks.
- `R6` called the local provider and published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_INVOCATION_R6.latest.json`. The provider returned non-empty `old_text` and `new_text`, but its `validation_command` was a list of verifier names rather than one executable command.
- `R7` initially accepted that unsafe validation command, exposing another verdict-policy gap. Codex made a narrow verdict-gate repair in `scripts/engines/LocalExecutionEngine.ps1`: allowed verifier names must appear in an executable command shape, not merely in a string.
- `R7B` published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_VERDICT_R7B.latest.json`, correctly rejecting the provider candidate with `verdict_reason_code=rejected_validation_command_not_executable_shape`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.

Classification: scaffolded provider-supervision safety progress. TOD exposed two specific control-plane gaps and verified the repaired guardrails, but Codex authored the repairs and no provider-generated source mutation has passed apply plus validation. APP-TOD-037 remains open.

Next smaller rung:

`TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1`

Acceptance:

- Replan from `TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_VERDICT_R7B.latest.json`.
- Tell the provider that naming verifier tools is insufficient; the `validation_command` must be a single executable command shape.
- Invoke the local provider.
- Reject malformed, fenced, blank, no-delta, wrong-surface, or non-executable validation-command output before mutation.
- Grant no implementation or independence credit unless a candidate later passes verdict, applies through the guarded mutation path, and validates.

## Proof Rules

Every training proof must include:

- unique objective id
- inspected files or evidence artifacts
- changed files or meaningful artifact write
- validation command
- validation result
- rollback note
- prevention lesson
- borrowed-capability registry entries affected
- whether the pass was independent, guided, scaffolded, or borrowed
- no wrapper-only completion

## Automatic Next Objective

`TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1`

Mission:

TOD reduces borrowed capability ratio by executing the priority families above, starting with read-only assessment and authority classification, then current-code bounded packet materialization.

First task:

`TOD-READONLY-AUTHORITY-CLASSIFICATION-RETIREMENT-PROOF-V1`

Acceptance:

TOD independently performs a fresh read-only authority classification without source-code mutation, publishes evidence, validates the artifact, and identifies which apprenticeship entries can advance.
