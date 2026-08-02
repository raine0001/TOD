# TOD Local Engineering Intelligence Program V2

Generated: 2026-07-24T04:21:17Z

## Decision

The Local Engineering Intelligence path should move forward now, but with a corrected emphasis:

1. Engineering Corpus starts immediately.
2. Local Engineering Runtime starts immediately.
3. Small local model integration starts early as an episode generator, not as implementation authority.
4. Larger models come later without changing TOD's workflow.

This is not a diversion from TOD training. It is the training platform TOD needs so engineering work, failures, recoveries, validations, examiner results, and auditor results become durable learning material.

## Core Distinction

TOD should not spend the next training cycle becoming mostly better at packet administration.

TOD should become better at supervising engineering:

- building the right context,
- choosing relevant files,
- diagnosing from evidence,
- judging model output,
- rejecting weak patches,
- improving prompts,
- validating behavior,
- recording reusable episodes.

Runtime plumbing is necessary, but it is a support track. It only outranks engineering when it directly blocks engineering episodes.

## Training Tracks

### Engineering

Primary track.

Measures whether TOD can inspect, diagnose, plan, patch, validate, recover, and explain engineering work.

### Runtime

Support track.

Measures whether packets, selectors, lineage, artifact routing, service bridges, and local execution lanes allow engineering work to happen.

### Governance

Support track.

Measures authority boundaries, ownership, escalation, safe action selection, and honest completion rules.

### Evidence

Support track.

Measures whether TOD records proof that is specific, durable, reproducible, and useful to Examiner/Auditor.

### Model Utilization

New explicit track.

Measures whether TOD can use an engineering model effectively without surrendering engineering ownership.

Required capabilities:

- construct a focused context package,
- choose the right provider and task type,
- detect model hallucination or weak output,
- reject unsafe or vague patches,
- improve prompts after failure,
- summarize model contribution honestly,
- record the episode as training data,
- mark model output as non-credit unless TOD validates it.

## Revised Program Order

### Phase A: Engineering Corpus Foundation

Start now.

Create immutable engineering episodes from existing repairs, failures, borrowed capabilities, Examiner results, and Auditor results.

Success means every meaningful engineering attempt improves the corpus.

### Phase B: Local Engineering Runtime

Start now.

Build the provider-neutral interface, context packaging, episode recording, evaluation hooks, and safe execution boundaries before relying on model quality.

Success means TOD can ask any current or future engineering model for bounded help through the same controlled path.

### Phase C: Small Local Model

Start early.

Use a small local coding model as a supervised engineering assistant and episode generator.

Success does not mean the model is good enough to own work. Success means TOD learns to supervise model output.

### Phase D: Larger Model Migration

Later.

When stronger hardware arrives, swap the model behind the same runtime and rerun the same baselines, examiner checks, and episode pipeline.

## Updated Scorecard Shape

Borrowed capability should be split by track:

| Track | Current Interpretation |
| --- | --- |
| Engineering | Primary training value; should receive most fresh demonstrations. |
| Runtime | Necessary support; should not dominate unless blocking engineering. |
| Governance | Mostly mature but still needs live authority proof. |
| Evidence | Important because corpus quality depends on it. |
| Model Utilization | New and currently borrowed; must be trained explicitly. |

## Near-Term Objective

`TOD-ENGINEERING-CORPUS-FOUNDATION-V1`

Mission:

Create the first durable engineering corpus slice from recent TOD/MIM work.

Acceptance:

- Define the episode schema.
- Import at least three successful repairs and two failed/blocked repairs.
- Preserve repository state, problem, evidence, attempted action, validation, Examiner/Codex validation, and outcome.
- Mark Codex-authored implementation as borrowed capability.
- Produce index files that can be used by later context-building tasks.
- Do not use rotating `.latest.json` artifacts as the only source of truth.

## Next Supporting Objective

`TOD-ENGINEERING-CONTEXT-BUILDER-V1`

Mission:

Teach TOD to prepare the smallest sufficient context package for an engineering provider.

This should begin before or alongside the first local model service. A weak model with excellent context is more useful than a stronger model fed stale runtime noise.

## Local Model Policy

The local model is not TOD.

The model may propose, inspect, summarize, or critique.

TOD must:

- supervise it,
- constrain it,
- validate it,
- reject it when weak,
- record its contribution,
- remain responsible for the engineering episode.

No model-generated patch counts as TOD independence until TOD proves the full inspect -> supervise -> apply -> validate -> evidence loop.

## Codex Role

Codex remains coach and validator.

Codex may define contracts and evaluate results.

Codex-authored production implementation remains borrowed capability and must enter the Apprenticeship Registry.

## Prevention Lesson

Do not confuse local inference with local engineering intelligence.

The durable product is the engineering episode system: context, attempt, judgment, validation, recovery, and learning. Model horsepower matters only after the organization can capture and evaluate the work.

## 2026-07-24 Strategy Adjustment

The program should not wait for a larger model before building TOD's engineering runtime.

The corrected sequence is:

1. Engineering Corpus.
2. Local Engineering Runtime.
3. Engineering Episodes.
4. TOD learns engineering supervision.
5. Larger models later.

The runtime is moved earlier, but its purpose is narrowed. Runtime work exists to let TOD practice engineering, not to turn TOD into a packet administrator.

TOD should be scored in separate capability families:

| Capability family | Purpose |
| --- | --- |
| Engineering | Inspect code, diagnose faults, choose repair surfaces, patch, validate, recover, and explain. |
| Runtime | Route packets, preserve lineage, write artifacts, bind selectors, and keep execution lanes healthy. |
| Governance | Preserve authority boundaries, ownership, escalation, and honest completion. |
| Evidence | Produce durable proof that Examiner and Auditor can verify. |
| Model Utilization | Build context, choose providers, supervise model output, reject bad proposals, and record episodes. |

The primary learning target is Engineering. Runtime and governance remain important, but they should not dominate the curriculum unless they directly block engineering episodes.

The local model should begin early as a supervised episode generator. It may help propose, inspect, or critique, but it does not receive implementation authority and does not count as TOD independence unless TOD owns the full loop:

objective -> context -> model supervision -> bounded attempt -> validation -> evidence -> Examiner/Auditor review.

This prevents a false tradeoff between "make TOD a better engineer" and "give TOD more horsepower." The practical path is to build the engineering organization now, use a small model to generate supervised learning episodes now, and swap in larger models later without changing TOD's workflow.

## 2026-07-24 Fresh Episode Status

Current evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_SCORECARD_POLICY_SOURCE_ANCHOR_R2.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_SCORECARD_POLICY_DELTA_PROPOSAL_R3.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_RUNTIME_TRAINING_STATUS_20260724_CONTINUATION_R2.latest.json`

TOD completed a fresh source-anchor inspection against `tools/build_organizational_maintenance_scorecard.py` and preserved exact current source evidence. The follow-up delta-proposal rung blocked honestly on `autonomous_candidate_new_text_missing`.

Training conclusion:

- Source-anchor inspection is improving.
- Engineering episode capture is useful runtime support.
- Borrowed-capability ratio did not improve.
- Engineering credit remains blocked until TOD can synthesize safe, meaningful `candidate_new_text` from inspected source evidence without Codex supplying the patch.

Next smallest rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

This rung must teach TOD to preserve source-anchor purpose, state the requested behavior delta separately, reject marker-only or unrelated replacement text, and produce candidate code only when the candidate preserves the same source boundary and responsibility.

## 2026-07-24 Training Priority Correction

The Engineering Corpus is now the primary product.

Every meaningful engineering attempt should improve the corpus, including:

- successful repairs,
- failed attempts,
- blocked attempts,
- borrowed Codex interventions,
- Examiner findings,
- Auditor findings,
- recovery attempts,
- false completions.

The local engineering runtime should start now, but its purpose is not to make TOD better at administration. Its purpose is to generate, supervise, validate, and store engineering episodes.

The local model should start as a supervised episode generator. It should help TOD practice model utilization:

- building focused context,
- selecting relevant files,
- asking for bounded proposals,
- rejecting weak patches,
- interpreting validation output,
- retrying intelligently,
- recording what happened honestly.

Current classification:

| Area | Status |
| --- | --- |
| Engineering Corpus | primary next product |
| Local Engineering Runtime | start now as support for episodes |
| Small local model | start early as supervised assistant, not authority |
| Runtime plumbing | supporting track only unless directly blocking episode creation |
| Borrowed capability ratio | no reduction from recent R6/R8/R3 proofs because Codex repaired runtime support |

Fresh evidence:

- `runtime_remote_training/training_debt/TOD_LITERAL_SOURCE_TOKEN_EXTRACTION_R6_VALIDATION_20260724.latest.json`
- `runtime_remote_training/training_debt/TOD_SOURCE_SPECIFIC_ROOT_CAUSE_READING_R3_VALIDATION_20260724.latest.json`
- `runtime_remote_training/training_debt/TOD_LITERAL_SOURCE_TOKEN_EXTRACTION_R8_VALIDATION_20260724.latest.json`

Lesson:

TOD should be trained as an engineering supervisor first. Runtime skills are necessary only insofar as they let TOD create, validate, and learn from engineering episodes. More packet proficiency without more engineering judgment does not reduce the real apprenticeship debt.

## 2026-07-24 R9 Update

TOD advanced one support rung after the source-anchor proof.

Evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_CARD_WRITER_SELECTOR_PRECEDENCE_SOURCE_ANCHOR_V1_R1.latest.json`
- `runtime_remote_training/tod_independent_resolution_attempts/TOD_EPISODE_CARD_WRITER_SELECTOR_PRECEDENCE_PACKET_SYNTHESIS_V1_R2.latest.json`
- `runtime_remote_training/training_debt/TOD_EPISODE_CARD_WRITER_SELECTOR_PRECEDENCE_PACKET_SYNTHESIS_R2_CODEX_VALIDATION_20260724.latest.json`

Observed result:

- TOD consumed a current-source anchor artifact.
- TOD produced a bounded packet candidate for `scripts/engines/LocalExecutionEngine.ps1`.
- The candidate included distinct current `old_text` and proposed `new_text`.
- TOD did not mutate the source file during packet formation.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | Partial support only |
| Runtime | Yes |
| Governance | No new movement |
| Evidence | Yes |
| Model Utilization | No |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains approximately 78.4% until TOD applies, validates, examines, and freezes fresh engineering repairs without Codex-authored patch content.

Next smallest rung:

`TOD-EPISODE-CARD-WRITER-PACKET-QUALITY-REVIEW-V1`

Mission:

TOD must review its own packet candidate before execution. The review must decide whether the packet preserves the source anchor, is minimal, targets the correct behavior, has an executable validation command, and should be approved, revised, or rejected.

Reason:

Engineering supervision begins when TOD can reject its own weak engineering packet instead of treating packet creation as completion.

## 2026-07-25 R138/R140 Update

The Engineering Intelligence path is confirmed as the better curriculum direction, but the latest evidence also shows why it must be measured in separate tracks.

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_DIRECTIVE_FIELD_ROUTING_DELTA_PROPOSAL_R138.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_R136_PASS_VS_R138_BLOCKED_EVIDENCE_COMPARISON_R140.latest.json`

Observed result:

- TOD reached the correct source-anchor delta proposal lane for R138.
- TOD preserved the exact target source file: `scripts/engines/LocalExecutionEngine.ps1`.
- TOD did not modify source code during the read-only delta-proposal task.
- TOD blocked honestly on `autonomous_candidate_new_text_missing`.
- R140 compared the successful and failed evidence paths without Codex fallback and identified the first material difference at the `Output Artifact` contract.

Training conclusion:

TOD is no longer merely failing on route plumbing for this slice. The remaining blocker is the engineering skill itself: synthesizing safe, meaningful `candidate_new_text` from a current source anchor.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | Not yet; candidate behavior-changing text was not produced. |
| Runtime | Yes; read-only evidence comparison and source-anchor artifact roles now route correctly. |
| Governance | Partial; TOD blocked honestly instead of fabricating a patch. |
| Evidence | Yes; durable artifacts exist for R138 and R140. |
| Model Utilization | Not yet; no engineering provider was supervised. |

Borrowed-capability impact:

- No borrowed capability ratio reduction.
- This remains a support milestone, not an independent engineering milestone.

Next smallest engineering rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

Teach TOD to use a current source anchor, identify the intended behavior delta, and synthesize a minimal safe candidate replacement only when the new text preserves the same responsibility boundary. If it cannot produce meaningful code, it must block with an exact missing capability rather than inventing marker text.

Program implication:

Runtime plumbing should now recede unless it directly blocks this engineering rung. The corpus and local engineering runtime are valuable because they let TOD practice engineering supervision, not because artifact routing itself is the final skill.

## 2026-07-25 R126/R127 Provider-Replan Lane Update

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_REPLAN_AFTER_REJECTION_R126.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_REPLAN_INPUT_ROLE_CHECK_R127.latest.json`

Observed result:

- R126 now reaches the `tod_engineering_provider_candidate_replan` lane instead of falling back to generic read-only task context proof.
- R127 now reaches the same provider-replan lane even when the package uses inline `Input Artifact`, `Supporting Artifact`, `Output Artifact`, and `Required Artifact Type` fields.
- Both runs correctly refuse to mark retry readiness because the supporting artifacts are not a normalized `tod_engineering_provider_request` plus `tod_engineering_provider_candidate_stub`.
- The current blocker is precise: `TOD-PROVIDER-CANDIDATE-REPLAN-INPUT-ROLE-REPAIR-V1`.

Validation:

- `Invoke-Pester -Path tests/TOD.LocalFallbackExecutor.Tests.ps1`
- Result: 66 passed, 34 failed.
- The new provider-replan lane tests passed.
- The remaining failures are pre-existing local fallback/packet-formation failures and do not prove this provider-replan support slice failed.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source candidate was produced. |
| Runtime | Yes. The provider-replan artifact lane now wins over generic bounded execution for supported read-only artifact-write contracts. |
| Governance | Partial. TOD blocks on missing normalized inputs instead of claiming retry readiness. |
| Evidence | Yes. R126/R127 produce durable, specific blocker artifacts. |
| Model Utilization | Not yet. TOD still cannot complete the model-supervision loop from rejected raw candidate to ready retry request. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4% until TOD independently completes an engineering/model-utilization loop that produces a validated, meaningful candidate or an Examiner-accepted rejection/retry cycle without Codex-authored runtime repair.

Next smallest rung:

`TOD-PROVIDER-CANDIDATE-REPLAN-INPUT-ROLE-REPAIR-V1`

Mission:

Teach TOD to distinguish provider request, provider inventory, raw provider output, candidate stub, Examiner verdict, and replan artifact roles. A raw provider output may be evidence, but it is not automatically a candidate stub. A replan may proceed only when the prior request and candidate are normalized enough to preserve target file, source anchor, desired behavior, and validation command.

Prevention lesson:

Do not let artifact-write packaging drift into generic bounded patch execution. Supported read-only evidence contracts must reach their task-specific lane first, then expose the real training blocker.

## 2026-07-25 R133 Engineering Corpus Foundation Index

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_CORPUS_FOUNDATION_R133.latest.json`

Observed result:

- R133 now reaches the `tod_engineering_corpus_foundation_index` lane.
- The corpus index read 5 unique input artifacts and found 0 missing inputs.
- Input paths are deduplicated before counting, so repeated packaged prompt sections do not inflate evidence.
- The index separates evidence and model-utilization tracks instead of treating every artifact as engineering independence.
- The index correctly reports `borrowed_capability_reduction_now = false`.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R133-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R133-20260725 -PackagePath "tod\out\prompts\R133-20260725.md" -SkipNextTaskSelectionLoop`
- Readback confirmed: `artifact_type = tod_engineering_corpus_foundation_index`, `input_count = 5`, `missing_input_count = 0`, `borrowed_capability_reduction_now = false`.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. The index organizes engineering memory, but no behavior-changing source candidate was produced. |
| Runtime | Yes. The read-only artifact lane now supports corpus foundation indexing. |
| Governance | Partial. The artifact refuses to lower borrowed ratio without independent proof. |
| Evidence | Yes. The corpus now has a durable index over current engineering and model-utilization episodes. |
| Model Utilization | Partial evidence only. Provider-replan artifacts are indexed, but no retry-ready provider request exists yet. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The corpus foundation is useful because it points at the next engineering demonstration instead of pretending indexing is engineering.

Next smallest engineering rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

TOD must inspect a current source anchor, infer the intended behavioral delta, synthesize one minimal meaningful replacement or insertion, and provide validation evidence. If TOD cannot produce meaningful new text without Codex patching, it must publish a precise engineering blocker rather than producing marker-only text or another wrapper artifact.

Prevention lesson:

The corpus is the memory system, not the skill. Engineering debt only falls when TOD uses that memory to perform or reject a real engineering move with validated evidence.

## 2026-07-25 R166 State Durability Blocker

Fresh evidence:

- `.\scripts\TOD.ps1 -Action add-task -ObjectiveId OBJ-0002 -TaskId R166-20260725 ...`
- Immediate readback from `tod/data/state.json` showed `R166-20260725` as `planned`.
- `.\scripts\TOD.ps1 -Action package-task -TaskId R166-20260725`
- Follow-up readback from `tod/data/state.json` showed `has_R166 = 0`.

Observed result:

- TOD accepted the read-only authority classification retirement task under the registered objective `OBJ-0002`.
- The task vanished before packaging.
- No package file or runtime artifact was created.
- This repeats the R165 pattern where a returned task object was not durably available to the next TOD command.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD never received a runnable training packet. |
| Runtime | Blocked. Local task-state durability is preventing the training rung from entering execution. |
| Governance | Partial. The failure is being recorded honestly instead of reissued as fake progress. |
| Evidence | Partial. The blocker has command/readback evidence but not an Examiner artifact yet. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`TOD-TASK-STATE-DURABILITY-READBACK-CLASSIFICATION-V1`

Mission:

TOD must classify why a task that is returned by `add-task` and visible in immediate readback is absent by `package-task`. The task should inspect the state transition evidence, identify the smallest suspected owner/surface, and publish a read-only blocker artifact. No source code changes are allowed in this rung.

Prevention lesson:

Do not keep issuing higher-level engineering retirement tasks through a state lane that cannot preserve the task long enough to package it. A disappearing task is a runtime-support blocker, not an engineering failure.

## 2026-07-25 R167B Read-Only Context Proof Limitation

Fresh evidence:

- `tod/out/prompts/R167B-20260725.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TASK_STATE_DURABILITY_READBACK_CLASSIFICATION_R167B.latest.json`

Observed result:

- TOD successfully packaged and ran a read-only inspection task after R166 disappeared.
- TOD produced `artifact_type = tod_read_only_task_context_proof`.
- The artifact proved:
  - `task_mode = inspection`
  - `bounded_edit_required = false`
  - `target_file_required = false`
  - `no_code_changes = true`
- The artifact did not inspect the R166 add-task/readback/package-task/follow-up-readback sequence.
- The artifact did not identify the suspected state durability owner or surface.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No source diagnosis or behavior-changing proposal was produced. |
| Runtime | Partial. The read-only lane can preserve non-edit mode but cannot yet diagnose evidence-specific state loss. |
| Governance | Partial. TOD avoided false source mutation. |
| Evidence | Partial. Durable artifact exists, but evidence specificity is insufficient. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`TOD-EVIDENCE-SPECIFIC-READONLY-DIAGNOSIS-V1`

Mission:

TOD must go beyond generic task-context proof. Given a named evidence sequence, TOD must inspect the concrete evidence, preserve the observed facts, identify the first failing transition, name the smallest suspected owner/surface, and publish a diagnosis artifact. The task remains read-only and must not require bounded edit fields.

Prevention lesson:

Read-only mode preservation is not the same as read-only diagnosis. A proof that a task did not require `target_file` is useful, but it does not answer why the task disappeared or how to resume the borrowed-capability retirement cycle.

## 2026-07-25 R168 State Subject Audit

Fresh evidence:

- `tod/out/prompts/R168-20260725.md`
- TOD run-task result for `R168-20260725`
- `tod/data/state.json` readback after R166 disappearance

Observed result:

- TOD packaged `R168-20260725`.
- Routing selected the Codex wrapper first because the task category was `read_only_assessment`.
- Codex wrapper did not execute the prompt.
- Safe local fallback inspected `tod/data/state.json` and failed with the precise reason:
  - `Audit subject was not found in input state: R166-20260725`
- No requested audit artifact was written because the missing subject produced a blocker before artifact publication.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No code diagnosis or patch proposal was produced. |
| Runtime | Yes, as blocker evidence. The state audit proved R166 is absent from the authoritative local state by the time the audit runs. |
| Governance | Partial. TOD returned an explicit blocker instead of counting wrapper acceptance as progress. |
| Evidence | Partial. The evidence is in the run-task result, not a durable task-specific artifact. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`TOD-READONLY-ASSESSMENT-LOCAL-FIRST-ROUTING-OR-INSPECTION-REROUTE-V1`

Mission:

TOD must route evidence-specific read-only diagnosis to an executor that can inspect JSON state without Codex wrapper involvement. Either `read_only_assessment` must become local-first for supported read-only audit contracts, or MIM/TOD must reframe these tasks as `inspection` when no external reasoning engine is required.

Prevention lesson:

The task-state disappearance is now proven; the next blocker is not evidence discovery. The next blocker is choosing a supported local route for evidence-specific read-only diagnosis and preserving the blocker in a durable artifact when the subject is missing.

## 2026-07-25 R169 Inspection Reroute Proof

Fresh evidence:

- `tod/out/prompts/R169-20260725.md`
- TOD run-task result for `R169-20260725`

Observed result:

- TOD reran the R166 state-subject audit as `task_category = inspection`.
- Routing selected local execution directly:
  - `selected_engine = local-placeholder`
  - `attempted_engines = local`
  - `fallback_applied = false`
- Local execution inspected `tod/data/state.json` and returned the precise blocker:
  - `reason_code = read_only_audit_subject_not_found`
  - `reason = Audit subject was not found in input state: R166-20260725`
- No durable audit artifact was written because the read-only audit lane returns a blocker before output publication when the requested subject is missing.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. This is still diagnosis/routing support. |
| Runtime | Yes. TOD proved the local inspection route avoids Codex wrapper involvement for this class. |
| Governance | Partial. The task blocked honestly and did not count missing-subject proof as completion. |
| Evidence | Partial. The blocker is persisted in task result state, but not in the requested durable artifact. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest engineering rung:

`TOD-READONLY-AUDIT-MISSING-SUBJECT-BLOCKER-ARTIFACT-SOURCE-ANCHOR-V1`

Mission:

TOD must inspect the current `read_only_audit_subject_not_found` branch in `scripts/engines/LocalExecutionEngine.ps1`, capture the exact source anchor, and decide whether the smallest repair should publish a blocker artifact before returning or preserve the current no-artifact blocker behavior. This is a source-anchor inspection only; no source code changes yet.

Prevention lesson:

The engineering target is now specific: missing-subject audits need durable evidence if they are going to support apprenticeship retirement decisions. The next step is current-code inspection, not another generic read-only context proof.

## 2026-07-25 R170 Source-Anchor Wrong-Lane Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_MISSING_SUBJECT_BLOCKER_ARTIFACT_SOURCE_ANCHOR_R170.latest.json`

Observed result:

- TOD accepted a source-anchor observation request for `scripts/engines/LocalExecutionEngine.ps1`.
- Local execution completed and wrote an artifact.
- The artifact was not a source-anchor observation:
  - `artifact_type = tod_read_only_task_context_proof`
  - `source = local_execution_read_only_task_context_artifact_lane`
  - `inspected_files = tod/out/prompts/R170-20260725.md`
  - `exact_text_exists = false`
  - no `start_line` or `end_line`
- The source file was not inspected.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not inspect the target source branch. |
| Runtime | Blocked. Prose `source_anchor_observation` in scope was not enough to select the source-anchor lane. |
| Governance | Partial. No source code was modified. |
| Evidence | Partial. The wrong-lane artifact is useful evidence of selector drift. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`TOD-STRUCTURED-SOURCE-ANCHOR-CATEGORY-SELECTION-V1`

Mission:

TOD must issue the same source-anchor task with structured task category `source_anchor_observation`, not only prose scope text. The pass condition is `artifact_type = tod_source_anchor_observation` with exact source text and line numbers from `scripts/engines/LocalExecutionEngine.ps1`.

Prevention lesson:

For source-anchor work, prose intent is not enough. The structured task category must match the intended learned lane, otherwise the local executor can satisfy the wrong schema and produce a false pass.

## 2026-07-25 R89 Autonomous Meaningful New Text Synthesis Lane

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_SYNTHESIS_FROM_SOURCE_ANCHOR_R89.latest.json`

Observed result:

- R89 now reaches the explicit `tod_autonomous_meaningful_newtext_synthesis` lane instead of being swallowed by generic read-only context proof.
- The artifact preserves the source-anchor role:
  - `source_anchor_artifact = runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_STUB_SOURCE_ANCHOR_SELECTOR_AUDIT_R85.latest.json`
  - `prior_delta_artifact = runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_STUB_SELECTOR_MEANINGFUL_DELTA_PROPOSAL_R86.latest.json`
  - `target_file = scripts/engines/LocalExecutionEngine.ps1`
  - `old_text` is non-empty.
- The artifact keeps `new_text` blank and blocks honestly with `autonomous_meaningful_new_text_synthesis_missing`.
- `independent_credit_requested = false`.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R89-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R89-20260725 -PackagePath "tod\out\prompts\R89-20260725.md" -SkipNextTaskSelectionLoop`
- Readback confirmed: `artifact_type = tod_autonomous_meaningful_newtext_synthesis`, `source_anchor_valid = true`, `prior_delta_available = true`, `old_text_nonempty = true`, `new_text_nonempty = false`, `no_source_code_modified = true`.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD still did not synthesize behavior-changing source text. |
| Runtime | Yes. The explicit synthesis task no longer gets hidden by generic context proof. |
| Governance | Yes. The artifact refuses independent credit while the engineering move is absent. |
| Evidence | Yes. The exact blocker and source-anchor context are durable. |
| Model Utilization | Blocked. The missing capability is now named directly as safe autonomous code-delta synthesis. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is the clearest current blocker for Engineering Independence: TOD can preserve the source anchor and explain the missing move, but cannot yet produce the move.

Next smallest engineering/model-utilization rung:

`TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`

Mission:

Provide TOD with a real engineering-provider loop that can receive the source anchor, target file, desired behavior, validation command, and rejection policy, then return a candidate that TOD can accept or reject. The first pass may use a small local model or deterministic stub only if the output is explicitly labeled as non-credit training data.

Prevention lesson:

Do not grade TOD on packet shape when the missing skill is code-delta synthesis. The next training loop must test whether TOD can supervise an engineering candidate, not whether it can produce another administrative artifact.

## 2026-07-25 R141/R142 Local Engineering Provider Probe

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_LOCAL_ENGINEERING_MODEL_RAW_CANDIDATE_R141.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_ENGINEERING_MODEL_CANDIDATE_VERDICT_R142.latest.json`

Observed result:

- The local engineering provider is real on this workstation:
  - `tools/llama.cpp/llama-server.exe` exists.
  - `models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf` exists.
  - `http://127.0.0.1:8008/health` returned `{"status":"ok"}`.
  - `http://127.0.0.1:8008/v1/models` listed `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- A provider probe generated a code-shaped candidate for the R89 source-anchor blocker.
- The candidate was rejected because it changed the wrong semantic guard, still relied on weak path matching, and supplied an invalid/incomplete validation command.
- This was a Codex-invoked validation probe, so it is training evidence, not TOD independence.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No accepted behavior-changing source candidate exists. |
| Runtime | Partial. A real local model service exists and answered, but TOD did not initiate the loop. |
| Governance | Yes. The weak candidate was rejected instead of converted into false progress. |
| Evidence | Yes. Raw provider output and rejection rationale are now durable. |
| Model Utilization | Progress. The next missing skill is TOD-supervised provider rejection and replan. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This changes the training focus: TOD no longer needs to wait for a future model to begin model-utilization training. TOD now needs to learn how to supervise the available local engineering model.

Next smallest model-utilization rung:

`TOD-LOCAL-ENGINEERING-MODEL-SUPERVISION-REJECTION-AND-REPLAN-V1`

Mission:

TOD must initiate the local provider loop from an existing source-anchor blocker, build the context bundle, reject weak model output with exact reasons, and replan a narrower retry without Codex authoring the replacement code.

Prevention lesson:

A local coding model is engineering horsepower, not engineering judgment. TOD earns credit when it constrains, rejects, replans, and validates model output instead of treating any model response as a patch.

## 2026-07-25 R143 Model Supervision Task Materialization Blocker

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_MODEL_SUPERVISION_TASK_MATERIALIZATION_BLOCKER_R143.latest.json`

Observed result:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R142-20260725` failed with `Task not found: R142-20260725`.
- This is correct: R142 is an evidence artifact, not a TOD task.
- The next missing capability is not local model availability. It is canonical task materialization for a model-supervision loop.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No source change candidate was accepted or validated. |
| Runtime | No new credit. The existing task runner correctly refused an unknown task ID. |
| Governance | Yes. The failed packaging attempt was recorded as a blocker instead of silently editing TOD state. |
| Evidence | Yes. The boundary between evidence artifact and executable task is now explicit. |
| Model Utilization | Blocked at task materialization. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`MIM-TOD-MODEL-SUPERVISION-TASK-MATERIALIZATION-V1`

Mission:

MIM must create or update the canonical objective, and TOD must materialize a resolvable task that references the raw provider candidate, the rejection verdict, the source anchor, and the validation command. Codex must not write the task record directly into state.

Prevention lesson:

Evidence artifacts are not executable work. TOD independence requires converting evidence into a resolvable task through the canonical task materializer, not relying on Codex to write task records by hand.

## 2026-07-25 R144-R148 Provider Replan Control Loop

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_REPLAN_NORMALIZED_ROLE_PROOF_R144.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_FROM_REPLAN_R145.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_INVENTORY_FROM_R145_R146.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_STUB_CANDIDATE_FROM_REPLAN_R147.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_STUB_VERDICT_FROM_REPLAN_R148.latest.json`

Observed result:

- R144 completed through the official TOD task path and produced `tod_engineering_provider_candidate_replan` with `provider_request_ready_for_retry = true`.
- R145 converted the retry-ready replan into `tod_engineering_provider_request` with `provider_request_ready = true`.
- R146 inspected local provider availability from the request and correctly preserved `provider_request_ready = true`, but reported `usable_provider_hook = false`.
- R147 produced a deterministic provider candidate stub from the provider request and inventory.
- R148 rejected that stub before source mutation with `verdict = reject` and `verdict_reason_code = rejected_marker_only_candidate`.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R144-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R144-20260725 -PackagePath "tod\out\prompts\R144-20260725.md" -SkipNextTaskSelectionLoop`
- Same package/run pattern for R145, R146, R147, and R148.
- Readback confirmed no source code mutation in all five artifacts.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No accepted behavior-changing source candidate was produced. |
| Runtime | Yes. TOD can now move normalized provider artifacts through replan -> request -> inventory -> stub -> verdict. |
| Governance | Yes. TOD rejected the marker-only candidate before source mutation. |
| Evidence | Yes. The full control loop is durable and individually readable. |
| Model Utilization | Partial support. TOD can supervise a deterministic stub, but did not yet invoke the running local model through its own lane. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is a model-supervision safety proof, not an independent engineering proof.

New precise blocker:

`TOD-LOCAL-PROVIDER-CONFIG-AND-HEALTH-DISCOVERY-V1`

Mission:

TOD must discover the local engineering provider from configured runtime metadata and HTTP health/model endpoints, not only from `Get-Command` checks. The current workstation has a live provider at `http://127.0.0.1:8008` with model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`, but the R146 inventory reports `usable_provider_hook = false` because `llama-server` is not on PATH.

Prevention lesson:

Provider discovery is not the same as command discovery. A running configured provider should be recognized through config, process, health endpoint, and model endpoint evidence before TOD falls back to deterministic stubs.

## 2026-07-25 R149-R151 Provider Discovery Source-Anchor Training

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_DISCOVERY_SOURCE_ANCHOR_R149.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_DISCOVERY_SOURCE_ANCHOR_R151.latest.json`

Observed result:

- R149 asked for a source-anchor observation but used `task_category = read_only_assessment`, so the generic read-only task-context proof lane won.
- R150 corrected the task category to `source_anchor_observation`, but the task wording used `Target File` plus an output artifact and the local executor refused to guess which path was the target.
- R151 used the source-anchor lane's native contract:
  - `Source File`
  - `Anchor Pattern`
  - `Lines Before`
  - `Lines After`
  - `Output Artifact`
  - `Required Artifact Type`
- R151 passed and captured exact source from `scripts/engines/LocalExecutionEngine.ps1` lines 7158-7283.

Training lesson:

The same operator intent can reach the wrong runtime lane if TOD chooses the wrong task shape. For source-anchor work, TOD must express the source path as `Source File`, the search term as `Anchor Pattern`, and the output as `Output Artifact`. It must not use ambiguous `Target File` wording for read-only source-anchor observation.

Engineering finding from R151:

The current provider inventory lane checks only command availability:

- `ollama`
- `llama-cli`
- `llama-server`
- `python`
- `node`
- `nvidia-smi`

It derives `realProviderReachable` from command availability only. It does not yet read `tod/config/llama-runtime.json`, check configured server paths, inspect running processes, call `http://127.0.0.1:8008/health`, or call `/v1/models`.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No source change was proposed or validated. |
| Runtime | Yes. TOD learned the task-shape distinction needed to reach the source-anchor lane. |
| Governance | Partial. R150 blocked instead of guessing when path roles were ambiguous. |
| Evidence | Yes. R151 is a durable source anchor for the next repair. |
| Model Utilization | Blocked until provider discovery recognizes the configured/running local model. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`TOD-LOCAL-PROVIDER-CONFIG-AND-HEALTH-DISCOVERY-PACKET-V1`

Mission:

Using R151 as the exact current source anchor, TOD must synthesize a bounded packet that teaches the provider inventory lane to recognize configured and running local providers in addition to PATH-discovered commands. The packet must preserve command discovery while adding config/process/HTTP health evidence. If TOD cannot synthesize safe new text, it must block with `provider_discovery_new_text_missing`.

Prevention lesson:

Do not mistake "no provider command found" for "no provider exists." Provider availability may be proven by configuration, process path, health endpoint, or model endpoint even when the executable is not globally discoverable.

## 2026-07-25 R152 Provider Discovery New Text Synthesis Attempt

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_DISCOVERY_NEWTEXT_SYNTHESIS_R152.latest.json`

Observed result:

- R152 was created, packaged, and executed through the official TOD task path.
- TOD consumed the R151 source-anchor observation and produced a `tod_source_anchor_delta_proposal`.
- TOD correctly preserved `target_file = scripts/engines/LocalExecutionEngine.ps1`.
- TOD did not edit source code.
- TOD did not fabricate marker-only or comment-only success.
- TOD blocked with `autonomous_candidate_new_text_missing`.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R152-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R152-20260725 -PackagePath "tod\out\prompts\R152-20260725.md" -SkipNextTaskSelectionLoop`
- Readback confirmed the artifact schema, source-anchor validity, empty source edits, and required fields.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD still did not produce behavior-changing replacement text. |
| Runtime | Yes. TOD routed the source-anchor delta proposal correctly. |
| Governance | Yes. TOD rejected fake progress instead of claiming a marker-only repair. |
| Evidence | Yes. R152 is a precise blocker artifact. |
| Model Utilization | Blocked. The next rung must convert source-anchor evidence into a model-ready engineering context or provider invocation. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

New precise blocker:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Reality:

TOD has exact source evidence and a correct target file, but the current local execution lane cannot synthesize safe behavior-changing `candidate_new_text` from that source anchor.

Prevention lesson:

A source anchor is evidence, not a repair. TOD must either turn it into a behavior-changing patch candidate through an engineering model/context lane or publish the missing synthesis capability before source mutation.

Next smallest rung:

`TOD-PROVIDER-DISCOVERY-ENGINEERING-CONTEXT-PACKAGE-V1`

Mission:

Create a model-ready engineering context package from R151/R152 that clearly separates source file, source anchor, desired behavior, rejected outputs, validation target, and acceptance policy. The context package must not edit source code and must not claim engineering implementation credit.

## 2026-07-25 R153-R154 Context Package Quality Gate

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_DISCOVERY_CONTEXT_PACKAGE_R153.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_DISCOVERY_CONTEXT_QUALITY_R154.latest.json`

Observed result:

- R153 produced a `tod_engineering_context_package`, but it collapsed the provider-specific problem into generic packet-materialization language.
- R153 preserved the source file and source anchor, but left `source_function` empty.
- R153 did not preserve the task-specific facts about `tod/config/llama-runtime.json`, `http://127.0.0.1:8008/health`, `/v1/models`, or provider inventory expected behavior.
- R154 correctly judged the package as `context_quality = insufficient_context_package`.
- R154 set `candidate_request_ready = false` and blocked on `context_package_missing_required_prompt_fields`.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R153-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R153-20260725 -PackagePath "tod\out\prompts\R153-20260725.md" -SkipNextTaskSelectionLoop`
- `.\scripts\TOD.ps1 -Action package-task -TaskId R154-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R154-20260725 -PackagePath "tod\out\prompts\R154-20260725.md" -SkipNextTaskSelectionLoop`
- Readback confirmed R153/R154 artifacts and no source code mutation.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. Still no behavior-changing patch candidate. |
| Runtime | Partial. Context package and judgment lanes work mechanically. |
| Governance | Yes. TOD rejected an insufficient context package before provider invocation. |
| Evidence | Yes. The quality failure is explicit and reusable. |
| Model Utilization | Partial negative proof. TOD can identify that the model prompt is not ready. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

New precise blocker:

`TOD-CONTEXT-PACKAGE-TASK-FACT-PRESERVATION-V1`

Reality:

The context-package lane can write a valid schema, but it currently fails to preserve task-specific problem facts when the input source-anchor artifact lacks those fields directly.

Prevention lesson:

A schema-valid context package is not automatically model-ready. Before invoking a model, TOD must verify that the context preserves the actual engineering problem, source function/surface, desired behavior, validation target, and rejected output classes.

Next smallest rung:

`TOD-CONTEXT-PACKAGE-BUILDER-SOURCE-ANCHOR-V1`

Mission:

Observe the current context-package builder source and identify where task-scope facts are ignored or replaced by generic defaults. This is runtime-support debt, not engineering implementation credit.

## 2026-07-25 R155 Context Package Builder Source Anchor

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_TASK_FACT_PRESERVATION_SOURCE_ANCHOR_R155.latest.json`

Observed result:

- R155 completed through the official TOD task path with local execution.
- TOD captured `scripts/engines/LocalExecutionEngine.ps1` lines 6894-7041 around `$wantsEngineeringContextPackage`.
- The source confirms that context packages are built primarily from fields already present in the input artifact:
  - `evidence`
  - `problem`
  - `intended_repair_delta`
  - `lesson`
  - top-level source fields
- When those fields are missing, the lane falls back to generic packet-materialization defaults.
- This explains R153: the source-anchor artifact had source text but not provider-specific context fields, so the context package became schema-valid but semantically generic.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R155-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R155-20260725 -PackagePath "tod\out\prompts\R155-20260725.md" -SkipNextTaskSelectionLoop`
- Readback confirmed source file, anchor match, nonempty source text, and no source code mutation.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. This was source observation, not source repair. |
| Runtime | Yes. TOD identified the runtime-support lane that loses task-specific context. |
| Governance | Yes. TOD separated context-quality failure from provider/model failure. |
| Evidence | Yes. R155 is exact source evidence. |
| Model Utilization | Indirect. Model use is blocked until context packages become prompt-ready. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Current ladder state:

1. Provider exists and is healthy outside TOD's inventory lane.
2. R151 proved the provider inventory source only uses command discovery.
3. R152 proved TOD cannot synthesize behavior-changing replacement text from source anchor alone.
4. R153 proved the context-package lane can write a valid schema but loses provider-specific facts.
5. R154 correctly rejected that context as not model-ready.
6. R155 found the source reason for that context loss.

Strategic conclusion:

The Engineering Corpus and Local Engineering Runtime should move earlier in the roadmap, but they must be separated from runtime plumbing. TOD should be trained on:

- Engineering episodes: inspect, diagnose, propose, validate, reject bad patches.
- Model utilization: build context, call a provider, judge candidate output.
- Runtime support: packet routing, source anchors, context packages, evidence integrity.

Runtime support is necessary, but it must not become the whole apprenticeship.

Next smallest rung:

`TOD-CONTEXT-PACKAGE-TASK-FACT-PRESERVATION-DELTA-V1`

Mission:

Using R155 as source evidence, TOD must produce a bounded delta proposal for preserving task-scope problem facts in context packages when the input source-anchor artifact lacks direct problem fields. If TOD cannot synthesize safe behavior-changing new text, it must publish `context_package_task_fact_new_text_missing` and preserve the blocker as runtime-support debt.

## 2026-07-25 R156 Context Package Task-Fact Preservation Delta Attempt

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_CONTEXT_PACKAGE_TASK_FACT_PRESERVATION_DELTA_R156.latest.json`

Observed result:

- R156 completed through the official TOD task path with local execution.
- TOD produced a `tod_source_anchor_delta_proposal` artifact for `scripts/engines/LocalExecutionEngine.ps1`.
- TOD linked the R155 source evidence through `old_text_source`.
- TOD did not edit source code.
- TOD did not produce behavior-changing `candidate_new_text`.
- TOD published an honest capability blocker:
  - `reason_code`: `autonomous_candidate_new_text_missing`
  - `missing_capability`: `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor`

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R156-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R156-20260725 -PackagePath "tod\out\prompts\R156-20260725.md" -SkipNextTaskSelectionLoop`
- Artifact readback confirmed:
  - `artifact_type=tod_source_anchor_delta_proposal`
  - `status=blocked`
  - `target_file=scripts/engines/LocalExecutionEngine.ps1`
  - source evidence linked to R155
  - `candidate_new_text` blank
  - no source code mutation

Acceptance review:

- Pass: correct bounded edit target.
- Pass: no source mutation.
- Pass: honest blocker instead of fake progress.
- Partial: the requested `input_artifact` field was represented as `old_text_source`, so the artifact is useful but not perfectly schema-clean.
- Fail for independence: TOD still cannot synthesize safe behavior-changing replacement text from source-anchor evidence.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing patch candidate was produced. |
| Runtime | Yes. TOD confirmed the exact runtime-support blocker. |
| Governance | Yes. TOD did not count blocked synthesis as progress. |
| Evidence | Yes, with schema caveat. The source link exists under `old_text_source`, not `input_artifact`. |
| Model Utilization | Blocked. This context path still cannot reach a model-ready engineering prompt. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is a repeatable negative proof across R152 and R156: TOD can preserve anchors and publish honest blockers, but cannot yet write safe behavior-changing code deltas from inspected source.

Training classification:

This is not an engineering failure alone. It is a mixed Runtime + Model Utilization blocker:

- Runtime support must preserve task facts into context packages.
- Model utilization must turn rich context into candidate code.
- Engineering independence remains blocked until TOD can reject or accept such candidates with validation evidence.

Next smallest rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

Teach TOD to transform one inspected source anchor and one explicit behavior delta into a safe candidate replacement text without Codex-authored patch content. If TOD cannot write the replacement, it must produce a model-ready engineering prompt and route it to the local provider for a candidate, then judge the returned candidate before any source mutation.

## 2026-07-25 R157 Autonomous Meaningful New Text Synthesis Proof

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_SYNTHESIS_R157.latest.json`

Observed result:

- R157 completed through the official TOD task path with local execution.
- TOD produced a `tod_autonomous_meaningful_newtext_synthesis` artifact.
- TOD preserved nonempty `old_text` from R155.
- TOD did not produce `new_text`.
- TOD did not edit source code.
- TOD did not request independent credit.
- TOD published the blocker:
  - `reason_code`: `autonomous_meaningful_new_text_synthesis_missing`
  - `smallest_next_rung`: `TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`

Important runtime finding:

R157 was instructed to consume both:

- `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_TASK_FACT_PRESERVATION_SOURCE_ANCHOR_R155.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_CONTEXT_PACKAGE_TASK_FACT_PRESERVATION_DELTA_R156.latest.json`

The output shows:

- `source_anchor_artifact` was captured from R155.
- `prior_delta_artifact` is blank.
- `validation.prior_delta_available=false`.
- `validation.listed_input_count=1`.

The synthesis lane only recognized the read-only-audit source-anchor path and did not ingest the engineering-corpus delta artifact. This is now a precise runtime-support blocker: the new-text synthesis path cannot consume its own prior delta evidence when that evidence lives under `runtime_remote_training/engineering_corpus/`.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R157-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R157-20260725 -PackagePath "tod\out\prompts\R157-20260725.md" -SkipNextTaskSelectionLoop`
- Artifact readback confirmed:
  - `artifact_type=tod_autonomous_meaningful_newtext_synthesis`
  - `status=blocked`
  - R155 source anchor captured
  - `old_text_nonempty=true`
  - `new_text_nonempty=false`
  - `prior_delta_available=false`
  - no source code mutation

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No candidate patch was produced. |
| Runtime | Yes. The missing evidence-root support is now isolated. |
| Governance | Yes. TOD did not claim progress from blank `new_text`. |
| Evidence | Yes. The artifact records exactly which input was seen and which input was lost. |
| Model Utilization | Blocked. The model-utilization lane cannot proceed until synthesis receives both source anchor and prior delta context. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- TOD remains at scaffolded/guided proof for this class.

Next smallest rung:

`TOD-SYNTHESIS-EVIDENCE-ROOT-PRESERVATION-V1`

Mission:

Teach or repair TOD's synthesis lane so it can consume both read-only source-anchor artifacts and engineering-corpus delta artifacts as named inputs. The goal is not to synthesize code yet; it is to preserve the full evidence set needed for the next model-utilization attempt.

## 2026-07-25 R158/R159 Synthesis Evidence Root Preservation Source Anchors

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SYNTHESIS_EVIDENCE_ROOT_PRESERVATION_SOURCE_ANCHOR_R158.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SYNTHESIS_BRANCH_EVIDENCE_ROOT_SOURCE_ANCHOR_R159.latest.json`

Observed result:

- R158 completed through the official TOD task path with local execution.
- R158 captured the upstream input pre-selector around lines 2227-2280.
- R158 showed the pre-selector special-cases `tod_autonomous_meaningful_newtext_synthesis` and captures only the first listed path matching:
  - `runtime_remote_training/read_only_audit_artifacts/...json`
- R159 completed through the official TOD task path after Codex returned `not_implemented` and local fallback succeeded.
- R159 captured the autonomous synthesis branch around lines 6650-6730.
- R159 showed the branch itself also matches only:
  - `runtime_remote_training/read_only_audit_artifacts/...json`
- R159 exact text does not include `runtime_remote_training/engineering_corpus`.

Why this matters:

R157 did not lose the prior delta because TOD forgot it conceptually. The runtime input-discovery code does not admit engineering-corpus delta artifacts into the synthesis input list. Once an artifact enters the list, the branch can classify `tod_source_anchor_delta_proposal`; the problem is that the delta artifact never reaches that loop.

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R158-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R158-20260725 -PackagePath "tod\out\prompts\R158-20260725.md" -SkipNextTaskSelectionLoop`
- `.\scripts\TOD.ps1 -Action package-task -TaskId R159-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R159-20260725 -PackagePath "tod\out\prompts\R159-20260725.md" -SkipNextTaskSelectionLoop`
- R159 readback confirmed:
  - `start_line=6650`
  - `end_line=6730`
  - exact text includes `wantsAutonomousMeaningfulNewTextSynthesis`
  - exact text includes `listedSynthesisInputMatches`
  - exact text includes `runtime_remote_training/read_only_audit_artifacts`
  - exact text does not include `runtime_remote_training/engineering_corpus`

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. This is runtime source observation. |
| Runtime | Yes. TOD isolated a precise evidence-root preservation defect. |
| Governance | Partial. R159 required fallback after Codex `not_implemented`, so independence is degraded. |
| Evidence | Yes. R158 and R159 separate pre-selector and branch-level causes. |
| Model Utilization | Blocked until this runtime path accepts both source-anchor and delta artifacts. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is runtime-support debt that blocks model-utilization training.

Next smallest rung:

`TOD-SYNTHESIS-EVIDENCE-ROOT-PRESERVATION-DELTA-V1`

Mission:

Using R158 and R159 source anchors, TOD must produce a bounded delta proposal to allow autonomous synthesis tasks to ingest both read-only source anchors and engineering-corpus delta artifacts. The proposal must preserve safety path checks and must not broaden input intake to arbitrary filesystem paths.

## 2026-07-25 R160 Synthesis Evidence Root Preservation Delta Attempt

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SYNTHESIS_EVIDENCE_ROOT_PRESERVATION_DELTA_R160.latest.json`

Observed result:

- R160 completed through the official TOD task path with local execution.
- TOD produced a `tod_source_anchor_delta_proposal` artifact.
- TOD used R159 as `old_text_source`.
- TOD selected the correct target file: `scripts/engines/LocalExecutionEngine.ps1`.
- TOD did not edit source code.
- TOD did not produce behavior-changing `candidate_new_text`.
- TOD preserved the blocker:
  - `reason_code`: `autonomous_candidate_new_text_missing`
  - `missing_capability`: `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor`

Validation:

- `.\scripts\TOD.ps1 -Action package-task -TaskId R160-20260725`
- `.\scripts\TOD.ps1 -Action run-task -TaskId R160-20260725 -PackagePath "tod\out\prompts\R160-20260725.md" -SkipNextTaskSelectionLoop`
- Artifact readback confirmed:
  - `artifact_type=tod_source_anchor_delta_proposal`
  - `status=blocked`
  - `old_text_source` points to R159
  - `target_file=scripts/engines/LocalExecutionEngine.ps1`
  - `candidate_new_text` is blank
  - `no_source_code_modified=true`
  - `validation.input_read=true`
  - `validation.source_anchor_valid=true`

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing patch candidate was produced. |
| Runtime | Yes. The precise runtime repair target is now known. |
| Governance | Yes. TOD stayed honest and did not claim debt retirement. |
| Evidence | Yes. R159 -> R160 forms a clean observation-to-blocked-delta chain. |
| Model Utilization | Still blocked inside TOD's own lane. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- Repeated proof now exists across R152, R156, and R160: TOD cannot yet independently synthesize meaningful source replacement text from inspected source anchors.

Decision:

Do not keep rerunning source-anchor delta tasks expecting a different result. The next useful training step is model utilization: supply R159 exact source and R160 behavior target to the configured local model, capture the candidate, and make TOD judge the candidate before any source mutation.

Next smallest rung:

`TOD-LOCAL-MODEL-CANDIDATE-JUDGMENT-FROM-SOURCE-ANCHOR-V1`

Mission:

Create one borrowed-but-explicit model-utilization episode: the local engineering model proposes a candidate from R159/R160 context, then TOD evaluates whether the candidate is safe, behavior-changing, source-grounded, and validation-ready. Credit belongs to Model Utilization and Evidence only unless TOD independently drives the provider invocation and verdict path.

## 2026-07-25 R161/R162 Local Model Candidate Judgment

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_LOCAL_MODEL_CANDIDATE_FROM_R159_R160_R161.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_MODEL_CANDIDATE_VERDICT_R162.latest.json`

Observed result:

- R161 was a borrowed local-model invocation performed for TOD training.
- The configured local provider was reachable through `llama.cpp` with `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- The model produced a malformed/truncated markdown-wrapped JSON candidate.
- TOD evaluated the candidate through the official task path in R162.
- TOD rejected the candidate before source mutation.
- No source code was modified.

R162 verdict:

- `artifact_type`: `tod_engineering_provider_candidate_verdict`
- `verdict`: `reject`
- `verdict_reason_code`: `rejected_wrong_target_file`
- `accepted_for_source_mutation`: `false`
- `rejected_before_source_mutation`: `true`
- `counts_as_engineering_implementation_credit`: `false`
- `no_source_code_modified`: `true`

Policy checks:

| Check | Result | Evidence |
| --- | --- | --- |
| Candidate artifact type | Failed | Candidate was `tod_local_model_candidate_from_source_anchor`, not the expected provider candidate contract. |
| Target matches provider request | Failed | Target was not extracted into the expected verdict field. |
| Not marker-only | Passed | No marker-only token detected. |
| Has delta | Failed | Verdict classified candidate as no usable delta. |
| Validation command present | Failed | No validation command was present. |

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not produce or safely apply a behavior-changing source patch. |
| Runtime | Partial. The local model service was reachable, but invocation remains Codex-borrowed. |
| Governance | Yes. TOD prevented a bad model candidate from becoming source mutation. |
| Evidence | Yes. The model attempt and rejection verdict are preserved as corpus evidence. |
| Model Utilization | Partial. TOD can judge and reject an unsafe candidate, but cannot yet independently invoke, constrain, normalize, and retry the model. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is not a failure of the local-model idea. It proves the first required supervision skill: TOD must be able to reject weak model output before patching.

Roadmap correction:

The Engineering Corpus and Local Engineering Runtime should advance together. Runtime plumbing should support engineering learning, not become the curriculum. The operating split is now:

| Track | Purpose | Current Evidence |
| --- | --- | --- |
| Engineering | Diagnose, patch, validate, recover. | Still weak; meaningful source delta synthesis remains blocked. |
| Runtime | Provider access, safe execution, isolation. | Service reachable; TOD invocation path not independent. |
| Governance | Scope, authority, honesty, rejection. | Stronger; R162 rejected unsafe output. |
| Evidence | Durable episodes and proof. | Improving; R141-R162 form a usable corpus chain. |
| Model Utilization | Build context, constrain provider, judge candidates, retry. | New track; R162 is the first partial pass. |

Next smallest rung:

`TOD-LOCAL-MODEL-PROMPT-CONSTRAINT-AND-RETRY-V1`

Mission:

TOD must learn to create a smaller provider request that asks the local model for one narrow, schema-valid candidate instead of a large pasted code block. The model output must then be judged again before any source mutation. This remains model-utilization training until TOD independently drives provider invocation and candidate review.

## 2026-07-25 R163 Prompt-Constraint Retry Contract Attempt

Fresh evidence:

- Official TOD task `R163-20260725`
- Requested output: `runtime_remote_training/engineering_corpus/TOD_LOCAL_MODEL_PROMPT_CONSTRAINT_RETRY_R163.latest.json`

Observed result:

- The task was accepted after the scope field was made explicit.
- Packaging succeeded.
- Local execution failed before producing the requested artifact.
- Failure reason:
  - `LocalExecutionEngine requires an existing target file, but runtime_remote_training/engineering_corpus/TOD_LOCAL_MODEL_PROMPT_CONSTRAINT_RETRY_R163.latest.json was not found.`
- No source code was modified.

Classification:

This is runtime-support debt, not an engineering-synthesis result. TOD was asked to create a new model-utilization evidence artifact under `runtime_remote_training/engineering_corpus/`, but the current local executor routed the work into the generic bounded task path, where missing target files are treated as blockers.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No engineering patch or diagnosis was produced. |
| Runtime | Yes, as blocker evidence. The executor lacks a supported lane for this artifact class/path. |
| Governance | Yes. The task failed instead of fabricating a missing artifact. |
| Evidence | Partial. The run output clearly identifies the missing executor capability. |
| Model Utilization | Blocked. TOD cannot yet create its own provider retry contract through the current lane. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Decision:

Do not let this become the main curriculum. This blocker belongs to the runtime-support track. The engineering track should continue with corpus construction, candidate judgment, and context quality. Runtime work should only supply the minimum lane needed for TOD to record and judge engineering-model episodes.

Next smallest runtime-support rung:

`TOD-MODEL-UTILIZATION-ARTIFACT-LANE-CLASSIFICATION-V1`

Mission:

TOD should classify which existing artifact publication lane can safely record model-utilization evidence without requiring Codex to create files by hand. If none exists, TOD should publish a precise blocker naming the smallest lane extension needed, without claiming engineering progress.

## 2026-07-25 R164/R165 Artifact-Lane Classification Attempts

Fresh evidence:

- `R164-20260725`: add-task returned an object, but package-task could not find the task.
- `R164B-20260725`: persisted, packaged, and ran successfully.
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_ARTIFACT_LANE_CLASSIFICATION_R164B.latest.json`
- `R165-20260725`: add-task returned an object and immediate state readback saw it, but a later package-task could not find it and the task disappeared from `tod/data/state.json`.

Observed result:

- R164B proved the existing read-only task-context artifact lane can publish a no-code-change proof.
- R164B did not inspect the R163 blocker itself; it published generic task-context proof because the detailed input directive was not present in the packaged prompt.
- R165 was shaped to force a true read-only audit from `tod/data/state.json`, but the task record did not survive long enough to package.

R164B artifact facts:

- `artifact_type`: `tod_read_only_task_context_proof`
- `task_mode`: `inspection`
- `task_mode_preserved`: `true`
- `bounded_edit_required`: `false`
- `target_file_required`: `false`
- `no_code_changes`: `true`
- `prevention_lesson`: `Read-only task context proofs may be generated from the task context itself; they must not be forced into bounded-edit target_file materialization.`

Classification:

R164B is useful but insufficient. It proves the generic read-only context lane, not the requested model-utilization blocker audit. R165 adds a separate runtime concern: task creation/readback can momentarily appear successful and then disappear before packaging.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. |
| Runtime | Partial. R164B proves one supported non-edit artifact lane; R165 exposes task-state durability risk. |
| Governance | Yes. Neither run claimed source implementation credit. |
| Evidence | Partial. The system now has proof of the supported lane and the disappearing-task behavior. |
| Model Utilization | Still blocked for independent retry-contract production. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Decision:

The better long-term path remains Engineering Corpus + Local Engineering Runtime + Model Utilization, but runtime debt must be split from engineering debt. The next runtime fix should be scoped narrowly to durable task-state persistence for model-utilization evidence tasks, while the engineering curriculum continues to build candidate judgment and context-quality episodes.

## 2026-07-25 R171-R173 Source-Anchor Lane Disambiguation

Fresh evidence:

- `R171-20260725`: source-anchor observation request preserved `TaskCategory=source_anchor_observation`, but used prose `Anchor` wording and fell through Codex/generic fallback. No source-anchor artifact was produced.
- `R172-20260725`: added `Anchor Pattern` but kept the directive fields in a semicolon-delimited scope sentence. Normal `run-task` still routed Codex-first and direct local fallback still treated multiple paths as target candidates.
- `runtime_remote_training/read_only_audit_artifacts/TOD_DIRECTIVE_LINE_SOURCE_ANCHOR_MISSING_SUBJECT_BRANCH_R173.latest.json`

Observed result:

- R173 used newline-separated directive fields:
  - `Source File`
  - `Anchor Pattern`
  - `Lines Before`
  - `Lines After`
  - `Output`
  - `Required Artifact Type`
- Direct local engine invocation produced a valid `tod_source_anchor_observation` artifact.
- The artifact was produced by `local_execution_source_anchor_observation_lane`.
- The artifact matched `read_only_audit_subject_not_found`.
- The artifact captured `scripts/engines/LocalExecutionEngine.ps1` lines 5348-5364.
- `exact_text` was nonempty.
- `no_code_changes=true`.
- Source code was not modified.

Classification:

R173 proves the source-anchor lane already exists and can work when TOD receives directive-line fields. The failure in R171/R172 was not a missing local capability. It was task-shape and routing ambiguity: source file, output artifact, and supporting artifact paths were being mixed into one prose field, allowing generic target-file logic or Codex-first routing to win.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. This was source evidence capture, not diagnosis-to-patch implementation. |
| Runtime | Yes. TOD now has proof that directive-line packet shape unlocks the existing source-anchor lane. |
| Governance | Partial. No source mutation occurred, but Codex shaped the packet and forced local execution. |
| Evidence | Yes. R173 produced exact source evidence suitable for a future bounded packet. |
| Model Utilization | No. No engineering provider was used or judged. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is a scaffolded/guided runtime-support pass, not an independent engineering pass.

Training lesson:

Source-anchor packet tasks may contain several paths, but only `Source File` is the bounded inspection target. `Output` is the destination artifact. Supporting artifacts are evidence inputs. TOD must not collapse those roles into generic prose or allow a selector to reinterpret the output artifact as the edit target.

Next smallest rung:

`TOD-SOURCE-ANCHOR-PACKET-SELF-MATERIALIZATION-V1`

Mission:

TOD must inspect the existing source-anchor local execution contract, then independently materialize a fresh source-anchor packet with newline-separated directive fields, package it, run it through the normal official path where possible, and publish exact source evidence without Codex shaping the directive fields. If the normal path still routes Codex-first, TOD must publish the precise selector/eligibility blocker instead of counting forced local execution as independence.

## 2026-07-25 R174 Source-Anchor Packet Self-Materialization Attempt

Fresh evidence:

- Official TOD task: `R174-20260725`
- Requested artifact: `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_PACKET_SELF_MATERIALIZATION_R174.latest.json`
- Packaged prompt: `tod/out/prompts/R174-20260725.md`
- State readback: `tod/data/state.json`

Observed result:

- R174 was created, persisted, packaged, and run through the official TOD task path.
- TOD materialization correctly classified the task as read-only:
  - `materialization.status=not_required`
  - `reason_code=canonical_read_only_task_mode_valid`
  - `target_file_required=false`
  - `edit_mode=read_only`
- The task then blocked during execution.
- No requested packet artifact was produced.
- No source code was modified.

Terminal blocker:

- `reason_code`: `codex_wrapper_only_no_execution`
- Codex wrapper accepted the package but did not execute the task.
- Local fallback then failed because `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_PACKET_SELF_MATERIALIZATION_R174.latest.json` did not already exist.

Why this matters:

R174 proves a narrower gap than earlier attempts. The pre-active materialization gate is no longer the blocker for this task class. It understood that no bounded edit target was required. The remaining issue is execution-lane support: TOD does not yet have a local lane that can create a new source-anchor packet materialization artifact from inspected contract knowledge and prior evidence.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No diagnosis-to-patch implementation occurred. |
| Runtime | Partial. The read-only materialization gate behaved correctly, but the execution lane is missing. |
| Governance | Yes. TOD blocked instead of fabricating the packet artifact. |
| Evidence | Yes. The state record preserves the materialization decision and terminal blocker. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- R174 is not a TOD independent pass. It is a clean blocker that identifies the next support lane needed for independence.

Training classification:

This is Runtime support debt, not Engineering debt. The correct priority is to add only enough execution support for TOD to create packet-materialization evidence, then return to engineering corpus/model-utilization work. Do not let this become another long packet-administration curriculum.

Next smallest rung:

`TOD-SOURCE-ANCHOR-PACKET-MATERIALIZER-LANE-V1`

Mission:

Provide or select a safe local evidence lane for `source_anchor_packet_materialization` tasks that can write a no-source-change artifact containing `chosen_source_file`, `chosen_anchor_pattern`, `output_artifact`, `directive_lines`, `reason_for_choice`, `validation_command`, and `no_code_changes=true`. The lane must not mutate source files and must not count as engineering implementation credit.

## 2026-07-25 R175 Guided Source-Anchor Packet Directive Lane Proof

Fresh evidence:

- Official TOD task: `R175-20260725`
- Input artifact: `runtime_remote_training/read_only_audit_artifacts/TOD_DIRECTIVE_LINE_SOURCE_ANCHOR_MISSING_SUBJECT_BRANCH_R173.latest.json`
- Output artifact: `runtime_remote_training/tod_independent_resolution_attempts/TOD_SOURCE_ANCHOR_PACKET_DIRECTIVE_FROM_R173_R175.latest.json`
- Packaged prompt: `tod/out/prompts/R175-20260725.md`

Observed result:

- R175 completed through the official TOD `run-task` path.
- The active route attempted Codex first, then fell back to local.
- Local execution produced a valid `tod_source_anchor_packet_directive_materialization_artifact`.
- The artifact was produced by `local_execution_source_anchor_packet_directive_lane`.
- `packet_candidate_ready=true`.
- The packet includes nonempty `old_text`, nonempty `new_text`, and the texts differ.
- The packet target is `scripts/engines/LocalExecutionEngine.ps1`.
- The packet includes a validation command.
- The artifact records `validation.no_source_edits=true`.
- This run wrote the packet artifact only; it did not apply the generated packet to source.

Validation:

- `input source-anchor artifact read=pass`
- `current-source old_text match=pass`
- `packet directive materialization=pass`
- `packet candidate schema validation=pass`
- `no source edit assertion=pass`

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. The generated packet is a harmless marker directive, not a meaningful behavior-changing repair. |
| Runtime | Yes. The existing packet directive lane can turn source-anchor evidence into a reversible packet candidate artifact. |
| Governance | Partial. The run preserved source safety, but Codex still shaped the directive contract. |
| Evidence | Yes. The packet artifact is durable and validated. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- R175 is a guided runtime-support pass. It proves the lane is usable, not that TOD can independently choose it or synthesize meaningful code.

Remaining blocker:

Even with a local-supported packet directive, the official route attempted Codex first and only succeeded through local fallback. The routing decision still reported `local_suitability_codex_required`. That is useful evidence but cannot count as independent execution.

Next smallest rung:

`TOD-EXECUTOR-SELECTOR-AUTHORITY-PRECEDENCE-INDEPENDENT-DEMO-V1`

Mission:

TOD must inspect the current selector evidence from R175, identify why a local-supported source-anchor packet directive still routes Codex-first, and publish a bounded, evidence-backed selector-authority diagnosis. If TOD proposes a repair, it must produce a bounded packet from current source anchors and validation evidence before any source mutation.

## 2026-07-25 R176/R177 Selector-Precedence Evidence Split

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SELECTOR_PRECEDENCE_LOCAL_SUITABILITY_REASON_R176.latest.json`
- Official TOD task: `R177-20260725`

Observed result:

- R176 produced a valid `tod_source_anchor_observation` artifact.
- R176 captured `scripts/TOD.ps1` lines 9630-9660 with `no_code_changes=true`.
- The captured source shows the `codex_required` branch promoting Codex to the active executor and leaving the prior local executor only as fallback.
- Direct source inspection also shows `packet_formation` is classified as `local_supported` at `scripts/TOD.ps1` lines 8702-8705.
- R177 routed local-first, but failed before publishing the requested diagnosis artifact.
- R177 blocker: `read_only_audit_required_artifact_type_unsupported`.
- The local executor can publish generic read-only audit artifacts, but it cannot yet publish the task-specific `tod_selector_precedence_diagnosis` artifact.

Classification:

This is runtime-support debt, not engineering debt. The important learning is not "TOD needs more packet practice." The important learning is that engineering episodes need a small number of reliable evidence lanes, and missing task-specific artifact lanes should be added or avoided only when they directly block engineering learning.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No diagnosis-to-repair implementation occurred. |
| Runtime | Yes for R176 source evidence; blocked for R177 task-specific diagnosis publication. |
| Governance | Yes. TOD did not claim the missing diagnosis artifact existed. |
| Evidence | Partial. Source evidence exists; the synthesized selector diagnosis is not yet published. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- R177 confirms that the next useful support rung is not broad dispatcher retraining. It is either a smaller generic diagnosis artifact accepted by the existing lane or a deliberately scoped task-specific artifact lane.

Program implication:

The user direction is correct: Engineering Corpus and Local Engineering Runtime should advance now. The split must be explicit:

1. Engineering is the primary curriculum.
2. Runtime is support infrastructure.
3. Governance keeps TOD honest.
4. Evidence feeds Examiner/Auditor and the corpus.
5. Model Utilization begins early with small local models as supervised episode generators, not autonomous implementers.

Next smallest rung:

`TOD-SELECTOR-PRECEDENCE-GENERIC-DIAGNOSIS-USING-EXISTING-LANE-V1`

Mission:

Use the existing generic read-only audit lane to publish a selector-precedence diagnosis without requiring a new artifact type. The artifact must cite R176 source evidence, R175 route behavior, and the local-supported `packet_formation` branch. If the generic lane cannot preserve the needed fields, then the missing task-specific diagnosis lane becomes a runtime support objective.

## 2026-07-25 R178 Generic Diagnosis Lane Result

Fresh evidence:

- Official TOD task: `R178-20260725`
- Output artifact: `runtime_remote_training/read_only_audit_artifacts/TOD_SELECTOR_PRECEDENCE_GENERIC_DIAGNOSIS_R178.latest.json`

Observed result:

- R178 completed through the existing read-only task context proof lane.
- The task stayed read-only:
  - `bounded_edit_required=false`
  - `target_file_required=false`
  - `no_code_changes=true`
- The output artifact was created under the expected read-only artifact root.
- The artifact type was `tod_read_only_task_context_proof`, not a selector-precedence diagnosis artifact.
- The artifact preserved task mode and task context, but did not preserve selector-diagnosis fields such as `observed_route`, `first_decision_loss`, `smallest_repair_target`, `debt_track`, or `borrowed_capability_impact`.

Classification:

R178 proves the generic read-only lane is safe but insufficient for selector-precedence diagnosis. This is a clean runtime-support finding. TOD can publish generic context proof without source mutation, but the lane cannot yet carry the structured evidence needed to explain selector authority drift.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing diagnosis-to-repair work occurred. |
| Runtime | Yes. Generic read-only lane availability is proven, and its limitation is now identified. |
| Governance | Yes. TOD did not claim selector diagnosis fields that were not preserved. |
| Evidence | Partial. The artifact proves read-only task context, but not the required selector-precedence diagnosis. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The lesson supports the user's corrected roadmap: runtime work should supply minimum viable engineering evidence lanes, not become the primary apprenticeship curriculum.

Next smallest runtime-support rung:

`TOD-SELECTOR-PRECEDENCE-DIAGNOSIS-ARTIFACT-LANE-V1`

Mission:

Add or select the smallest safe local evidence lane that can write a no-source-change selector-precedence diagnosis artifact. The lane must preserve `observed_route`, `local_support_evidence`, `codex_primary_evidence`, `first_decision_loss`, `smallest_repair_target`, `debt_track`, and `borrowed_capability_impact`. It must not mutate source code and must not count as engineering implementation credit.

## 2026-07-25 R179 Read-Only Context Lane Source Anchor

Fresh evidence:

- Official TOD task: `R179-20260725`
- Output artifact: `runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_CONTEXT_LANE_SOURCE_ANCHOR_R179.latest.json`

Observed result:

- TOD published a valid `tod_source_anchor_observation` artifact.
- The artifact was produced by `local_execution_source_anchor_observation_lane`.
- The artifact captured `scripts/engines/LocalExecutionEngine.ps1` lines 8478-8528.
- The captured source includes the generic `tod_read_only_task_context_proof` writer.
- `exact_text` is nonempty.
- `no_code_changes=true`.
- Validation passed:
  - source file read
  - anchor pattern match
  - source anchor artifact write
  - required schema readback
  - no-code-change assertion

Routing caveat:

The official route still attempted Codex first and completed through local fallback. This is useful evidence but not independent TOD execution credit. The same selector-precedence concern remains: a local-supported source-anchor observation can still route Codex-first before fallback recovers.

Credit:

| Track | Credit |
| --- | --- |
| Engineering | No. This is source evidence capture, not engineering repair. |
| Runtime | Yes. The exact generic read-only writer is now anchored for a bounded support repair. |
| Governance | Partial. No source mutation occurred, but route authority still preferred Codex first. |
| Evidence | Yes. The current source evidence is durable and exact. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest rung:

`TOD-READONLY-DIAGNOSIS-LANE-PACKET-SYNTHESIS-V1`

Mission:

Using R179 as the source anchor, TOD must synthesize a bounded packet candidate that extends the existing read-only context proof writer or adjacent safe branch to preserve selector-precedence diagnosis fields. The packet must target only `scripts/engines/LocalExecutionEngine.ps1`, include exact `old_text` from R179/current source, proposed `new_text`, validation command, and no source mutation. The packet must be reviewed before any apply step and must be classified as runtime-support credit only.

## 2026-07-25 R180-R184 Fresh Evidence And Curriculum Correction

User correction:

TOD should not spend another long cycle becoming a better packet administrator before it becomes a better engineer. The better sequence is:

1. Engineering Corpus.
2. Local Engineering Runtime.
3. Engineering Episodes.
4. TOD learns engineering supervision.
5. Larger model later.

The training split is now explicit:

| Track | Purpose |
| --- | --- |
| Engineering | Inspect code, diagnose behavior, propose bounded changes, validate, recover. |
| Runtime | Provide only the routing, artifact, selector, and execution support needed for engineering episodes. |
| Governance | Keep authority, blocker honesty, and no-wrapper-only rules intact. |
| Evidence | Preserve exact source, validation, decisions, and lessons. |
| Model Utilization | Build context, supervise provider output, reject bad patches, retry intelligently, and record episodes. |

R180 result:

- Task: `R180-20260725`
- Outcome: rejected for retirement credit.
- Reason: TOD classified a saved patch, but the selected patch contained no useful authority signals.
- Borrowed-capability impact: none.

R181 result:

- Task: `R181-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUTHORITY_SIGNAL_PATCH_RELIABILITY_R181.latest.json`
- Outcome: valid repeatability evidence for saved route-authority patch classification.
- Signals found: 6.
- Classification buckets:
  - `hardcoded_response_authority_risk`
  - `operator_contract_authority_risk`
  - `reusable_service_candidate`
  - `process_support_candidate`
  - `phrase_patch_rejected`
- Borrowed-capability impact: none, because this reused the known saved patch.

R182 result:

- Task: `R182-20260725`
- Intended proof: fresh git-history route patch registration and classification.
- Actual result: TOD selected the existing saved route-authority patch instead of registering a fresh git-history patch.
- Output: `runtime_remote_training/read_only_audit_artifacts/R182-20260725_20260721_remaining_dirty_mim_tod_route_experimen.latest.json`
- Diagnosis: selector precedence drift. `Test-LocalExecutionSavedRoutePatchEvidenceDiscoveryTask` wins before `Test-LocalExecutionFreshRoutePatchEvidenceRegistrationTask`, so a request that asks to find/select fresh route evidence can be captured by the saved-evidence lane.
- Borrowed-capability impact: none.

R183 result:

- Task: `R183-20260725`
- Output: `runtime/tod_engineering_corpus/TOD_SELECTOR_PRECEDENCE_FRESH_REGISTRATION_DRIFT_R183.latest.json`
- Outcome: TOD converted the R182 selector drift into a durable corpus episode card.
- Caveat: the episode card preserved the broad runtime debt classification but did not preserve the specific R182 problem statement as strongly as requested.

R184 result:

- Task: `R184-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_SELECTOR_PRECEDENCE_R183_EPISODE_QUALITY_R184.latest.json`
- Examiner verdict:
  - `training_usefulness`: `accept_runtime_support_only`
  - `engineering_credit_allowed`: `false`
  - `runtime_support_credit_allowed`: `true`
  - `borrowed_capability_ratio_effect`: `no_reduction`
- Verdict reason: the episode is useful runtime-support memory, but it documents routing/selector/artifact-lane work rather than independent engineering diagnosis, patch, and validation.

Current borrowed-capability ratio:

- Baseline remains 78.4%.
- No R180-R184 item reduces the ratio.

Current lesson:

The Engineering Corpus is the primary learning product. Runtime plumbing should be repaired only far enough to let TOD create and evaluate real engineering episodes. A useful runtime episode is still valuable, but it must not masquerade as engineering independence.

Next smallest training rung:

`TOD-FRESH-ENGINEERING-EPISODE-INDEPENDENT-DEMO-V1`

Mission:

TOD selects a fresh, harmless source-level engineering target, inspects current code, diagnoses a real behavior or maintainability issue, proposes a bounded change, validates it, writes an engineering episode, and runs an Examiner verdict. Codex may coach and validate, but Codex must not author the patch or the engineering judgment.

## 2026-07-25 R185-R189 Fresh Engineering Episode Ladder

R185 target selection:

- Task: `R185-20260725`
- Outcome: blocked.
- Reason: no evidence-derived source target was available for the target-selection lane.
- Useful lesson: TOD must not invent static fallback targets when no current evidence names a viable source target.

R186 source-anchor attempt:

- Task: `R186-20260725`
- Outcome: blocked.
- Reason: the anchor pattern was too literal and did not match current source text.
- Useful lesson: source-anchor tasks should use stable current-source anchors, not brittle copied fragments.

R186B source-anchor success:

- Task: `R186B-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_CARD_PROBLEM_STATEMENT_SOURCE_ANCHOR_R186B.latest.json`
- Outcome: completed.
- Source file: `scripts/engines/LocalExecutionEngine.ps1`
- Source line: 7805
- Captured behavior: the engineering episode card writer can fall back to a generic `problem_statement`.
- Credit:
  - Engineering: inspection only.
  - Runtime: support evidence.
  - Evidence: source anchor captured.
  - Model Utilization: no.

R187 delta proposal:

- Task: `R187-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_CARD_PROBLEM_STATEMENT_DELTA_R187.latest.json`
- Outcome: blocked honestly.
- Blocker: `autonomous_candidate_new_text_missing`
- Meaning: TOD has source-anchor exact text and target file, but cannot yet synthesize meaningful candidate `new_text` from source evidence without model-utilization support.

R188 engineering context package:

- Task: `R188-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_EPISODE_CARD_PROBLEM_STATEMENT_CONTEXT_PACKAGE_R188.latest.json`
- Outcome: completed mechanically, but context quality was weak.
- Missing: `source_file` and `source_function`.
- Meaning: the context builder did not preserve source-anchor role strongly enough from R186B/R187.

R189 model-utilization judgment:

- Task: `R189-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_EPISODE_CARD_PROBLEM_STATEMENT_MODEL_JUDGMENT_R189.latest.json`
- Outcome: completed.
- Verdict:
  - `context_quality`: `insufficient_context_package`
  - `candidate_request_ready`: `false`
  - `counts_as_model_utilization_credit`: `no`
  - `blocker_reason_code`: `context_package_missing_required_prompt_fields`
- Correct behavior: TOD rejected weak context before provider/model invocation.

Borrowed-capability impact:

- No ratio reduction yet.
- Current borrowed ratio remains 78.4%.

Development significance:

This is the first clean pass through the corrected roadmap shape:

1. Capture source evidence.
2. Attempt source-delta reasoning.
3. Identify autonomous `new_text` synthesis as blocked.
4. Build context package.
5. Reject insufficient provider context before model use.

The result is not engineering independence yet, but it is better model-supervision behavior than blindly escalating to Codex or treating a generic package as provider-ready.

Next smallest training rung:

`TOD-CONTEXT-PACKAGE-SOURCE-ROLE-PRESERVATION-V1`

Mission:

Repair the context-package training path so source-anchor-derived context preserves `source_file`, `source_function` or function surface, and the original source-anchor artifact when the input artifact is a delta proposal. This is Runtime + Model Utilization support only. Engineering credit starts only after TOD can use that preserved context to supervise a provider candidate and reject or accept a behavior-changing patch.

## 2026-07-25 R190-R193 Context Package Source-Role Preservation

R190 direct-chat attempt:

- Task: `R190-20260725`
- Outcome: blocked.
- Reason: the direct-chat materializer forced read-only source-anchor work into malformed bounded-edit shape.
- Useful lesson: task-mode classification still leaks into implementation-mode packet requirements.
- Borrowed-capability impact: none.

R190B source-anchor observation:

- Task: `R190B-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_SOURCE_ROLE_SOURCE_ANCHOR_R190B.latest.json`
- Outcome: completed.
- Source file: `scripts/engines/LocalExecutionEngine.ps1`
- Source lines: 6909-6921.
- Validation: artifact type `tod_source_anchor_observation`, matched source, captured `source_file`, `source_function`, and `source_anchor_artifact` selection block, no source edits.

R191 first delta attempt:

- Task: `R191-20260725`
- Outcome: blocked by stale objective-context contamination.
- Reason: the packaged prompt included the earlier R190 objective text and the brittle R190 anchor, causing the source-anchor detector to win before the delta proposal lane.
- Useful lesson: objective context can poison later task routing when the same objective record carries stale detector-triggering language.

R191C clean delta proposal:

- Task: `R191C-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_SOURCE_ROLE_DELTA_R191C.latest.json`
- Outcome: completed with honest blocker.
- Preserved:
  - `target_file`: `scripts/engines/LocalExecutionEngine.ps1`
  - `old_text_source`: `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_SOURCE_ROLE_SOURCE_ANCHOR_R190B.latest.json`
- Blocker: `autonomous_candidate_new_text_missing`.
- Meaning: TOD can preserve the source role in a clean delta artifact, but still cannot synthesize behavior-changing `candidate_new_text` independently in this lane.

R192 context-package proof:

- Task: `R192-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_CONTEXT_PACKAGE_SOURCE_ROLE_CONTEXT_R192.latest.json`
- Outcome: completed mechanically, but proved the preservation defect remains.
- Observed failure:
  - `source_file`: empty
  - `source_function`: empty
  - `source_anchor_artifact`: incorrectly set to the R191C delta artifact rather than the original R190B source-anchor artifact.
- Meaning: the context-package builder does not yet preserve source-role fields from delta proposal inputs.

R193 model-utilization judgment:

- Task: `R193-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_CONTEXT_PACKAGE_SOURCE_ROLE_MODEL_JUDGMENT_R193.latest.json`
- Outcome: completed.
- Verdict:
  - `context_quality`: `insufficient_context_package`
  - `candidate_request_ready`: `false`
  - `counts_as_model_utilization_credit`: `no`
  - `blocker_reason_code`: `context_package_missing_required_prompt_fields`
- Correct behavior: TOD rejected weak model context instead of asking a provider or Codex to generate a candidate patch from empty source-role fields.

Borrowed-capability impact:

- No ratio reduction yet.
- Current borrowed ratio remains 78.4%.

Development significance:

TOD is beginning to supervise the engineering pipeline instead of blindly escalating. It captured source evidence, preserved source role in a clean delta artifact, proved context-package field loss, and rejected weak model context. This is runtime/model-utilization support progress, not engineering independence.

Next smallest training rung:

`TOD-CONTEXT-PACKAGE-SOURCE-ROLE-REPAIR-PACKET-V1`

Mission:

Using R190B, R191C, R192, and R193 as evidence, TOD must produce a bounded repair packet for `scripts/engines/LocalExecutionEngine.ps1` that updates only the engineering context package source-role selection block. The packet must preserve `target_file` as `source_file` when the input artifact is a delta proposal, preserve `old_text_source` as the original `source_anchor_artifact`, provide a useful source function or function surface, and include a focused validation command. The packet must be reviewed before any source apply step.

## 2026-07-25 Engineering-First Curriculum Correction

Operator correction:

The program should not wait for the October-class model, but it also should not spend the next months training TOD primarily as a packet administrator. The right sequence is:

1. Engineering Corpus.
2. Local Engineering Runtime.
3. Engineering Episodes.
4. TOD learns engineering supervision.
5. Larger model later.

The runtime moves earlier, but not as the primary educational objective. Its job is to let TOD create, supervise, validate, and learn from engineering episodes. Runtime plumbing is necessary only when it directly unblocks engineering practice.

Primary product:

The Engineering Corpus is now the primary product. Every engineering attempt, failed attempt, borrowed Codex repair, Examiner result, Auditor result, recovery, and rejection should improve the corpus.

Added track:

`Model Utilization`

Measures whether TOD can effectively use whichever engineering model is available without surrendering ownership.

Required proof:

- builds focused context,
- chooses relevant source and test files,
- asks for the right provider task,
- rejects weak or unsafe model output,
- retries with a better request,
- records the model contribution honestly,
- validates before credit,
- marks provider output as non-credit unless TOD owns the full loop.

Split scorecard:

| Track | Current evidence snapshot | Current interpretation |
| --- | --- | --- |
| Engineering | 17 borrowed / 25 tracked | Primary debt. TOD can inspect and preserve evidence, but meaningful patch synthesis remains weak. |
| Runtime | 3 borrowed / 4 tracked | Support debt. Fix only when blocking engineering episodes. |
| Governance | 1 borrowed / 1 tracked | Needs proof, but should not dominate daily engineering training. |
| Evidence | 2 borrowed / 2 tracked | Corpus quality depends on this; train through real episodes. |
| Coordination | 4 borrowed / 4 tracked | Important for MIM/TOD operation, but separate from engineering independence. |
| Model Utilization | emerging, not yet registry-scored | Add as first-class debt category immediately. |

Policy:

Do not treat packet routing, lineage reconciliation, selector binding, or artifact plumbing as engineering independence. Those can earn runtime-support credit. Engineering independence requires TOD to inspect source, identify a repair surface, supervise or synthesize a bounded change, validate behavior, reject failures, and publish an episode that Examiner/Auditor can verify.

Next training implication:

Continue `TOD-CONTEXT-PACKAGE-SOURCE-ROLE-REPAIR-PACKET-V1` because it directly unblocks provider-ready engineering context. The goal is not to admire the context builder. The goal is to get TOD to the point where a small local model can be supervised on real bounded engineering work without Codex authoring the patch.

## 2026-07-25 R194-R198 Source-Role Repair Packet Recovery Ladder

Objective:

`TOD-CONTEXT-PACKAGE-SOURCE-ROLE-REPAIR-PACKET-V1`

R194 repair-packet attempt:

- Task: `R194-20260725`
- Outcome: blocked.
- First blocker: multiple candidate target files because evidence artifacts and the source file all appeared in the package.
- Recovery attempt: retry with explicit `TargetFile=scripts/engines/LocalExecutionEngine.ps1`.
- Second blocker: `missing_variable=edit_mode`.
- Lesson: target binding resolves path ambiguity, but the local executor still treats repair-packet proposal work as bounded source-edit execution.

R195 artifact-only packet proposal attempt:

- Task: `R195-20260725`
- Outcome: blocked.
- First blocker: multiple candidate target files when evidence paths were included in task text.
- Recovery attempt: retry with explicit `TargetFile=scripts/engines/LocalExecutionEngine.ps1`.
- Second blocker: `missing_variable=edit_mode`.
- Lesson: marking the work as artifact-only is not enough when the task shape still falls through to `Invoke-LocalExecutionGenericBoundedTask`.

R196 read-only training-debt extraction attempt:

- Task: `R196-20260725`
- Outcome: blocked.
- Blocker: `missing_variable=edit_mode`.
- Lesson: even training-debt extraction can be misrouted when the prompt does not match an existing read-only artifact lane.

R197 source-anchor diagnostic attempt:

- Task: `R197-20260725`
- Outcome: blocked.
- Blocker: `missing_variable=edit_mode`.
- Diagnosis: the task asked for a source-anchor observation but did not provide the explicit output artifact path required by `Get-LocalExecutionSourceAnchorObservationSpec`.

R198 source-anchor diagnostic pass:

- Task: `R198-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_ARTIFACT_ONLY_PACKET_EDIT_MODE_GATE_SOURCE_ANCHOR_R198.latest.json`
- Outcome: completed.
- Captured source: `scripts/engines/LocalExecutionEngine.ps1` lines 10612-10636.
- Captured blocker text: `LocalExecutionEngine requires an explicit bounded edit mode or an inferable markdown section update for this task.`
- Validation:
  - source file read: pass
  - anchor pattern match: pass
  - source anchor artifact write: pass
  - required schema readback: pass
  - no-code-change assertion: pass

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing packet was synthesized. |
| Runtime | Yes. TOD proved the generic edit-mode gate with exact source evidence. |
| Evidence | Yes. Durable source-anchor artifact exists. |
| Model Utilization | No. No provider-ready context or candidate supervision occurred. |
| Governance | Partial. TOD stopped rather than fabricating packet success. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Current finding:

TOD can now recover from the blocker by backing down to a valid source-anchor observation when the directive shape is explicit. TOD still cannot independently produce the source-role repair packet. The next training work should use R198 as the source anchor for a bounded packet-body synthesis rung, and should not count as engineering independence unless TOD produces meaningful `new_text` and validation evidence without Codex-authored patch content.

Next smallest training rung:

`TOD-ARTIFACT-ONLY-PACKET-LANE-DISPATCH-REPAIR-PACKET-V1`

Mission:

Using R198 as source evidence, TOD must produce a packet-body synthesis artifact that proposes the smallest dispatch/materializer repair allowing artifact-only packet proposal and training-debt extraction tasks to select a read-only artifact lane instead of falling through to generic bounded edit mode. The output must name exact `target_file`, exact `old_text` from R198/current source, meaningful `new_text`, validation command, rollback note, prevention lesson, and no source mutation before review.

## 2026-07-25 R199-R203 Context-Quality And Model-Utilization Check

Objective:

`TOD-CONTEXT-PACKAGE-SOURCE-ROLE-REPAIR-PACKET-V1`

R199 selector drift:

- Task: `R199-20260725`
- Outcome: completed with wrong-lane evidence, then failed validation.
- Evidence:
  - `runtime_remote_training/cleanup_holds/R199-20260725_95361c28beae.patch`
  - `runtime_remote_training/read_only_audit_artifacts/R199-20260725_95361c28beae.latest.json`
- Problem: the saved route/authority patch classifier won the lane and produced route-experiment evidence instead of a source-role repair packet.
- Additional damage: the earlier R198 source-anchor path was later found to contain unrelated patch-evidence content, so R198 can no longer be treated as a trustworthy source anchor for this rung.
- Lesson: selector drift is runtime-support debt. It is not engineering progress, and it can contaminate evidence if output paths are reused too broadly.

R200 context package from contaminated evidence:

- Task: `R200-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_ARTIFACT_ONLY_PACKET_LANE_CONTEXT_R200.latest.json`
- Outcome: local task reported pass, but manual validation rejected provider readiness.
- Evidence quality:
  - `source_file`: blank
  - `source_function`: blank
  - provider-ready: false
- Lesson: a context package can be schema-shaped and still useless for engineering. Model Utilization requires source facts strong enough for a provider or candidate generator to act on.

R201 fresh source-anchor recovery:

- Task: `R201-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_SOURCE_FIELD_SELECTION_R201.latest.json`
- Outcome: completed.
- Captured source: `scripts/engines/LocalExecutionEngine.ps1` lines 6883-6943.
- Key source surface: engineering context package source-field selection logic.
- Validation:
  - source file read: pass
  - anchor found: pass
  - exact text nonempty: pass
  - no source mutation: pass

R202 context package from R201:

- Task: `R202-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_CONTEXT_SOURCE_FIELD_SELECTION_CONTEXT_R202.latest.json`
- Outcome: completed after first engine path was not implemented and safe local fallback produced an artifact.
- Evidence quality:
  - `source_file`: `scripts/engines/LocalExecutionEngine.ps1`
  - `source_function`: blank
  - `source_anchor_artifact`: `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_SOURCE_FIELD_SELECTION_R201.latest.json`
  - provider-ready: false
- Lesson: R202 recovered the source file but still lacks a function or surface label. That is enough for corpus evidence, but not enough for a provider-ready engineering prompt.

R203 model-utilization judgment:

- Task: `R203-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_CONTEXT_SOURCE_FIELD_SELECTION_MODEL_JUDGMENT_R203.latest.json`
- Outcome: completed.
- Judgment: `context_quality=insufficient_context_package`.
- Provider invoked: no.
- Correct behavior: TOD rejected the incomplete context before sending a weak prompt to a model.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source delta or bounded repair packet exists. |
| Runtime | Partial. TOD exposed selector drift and recovered a clean source-anchor path. |
| Evidence | Yes. R201-R203 preserve the source-field selection blocker and context-quality verdict. |
| Model Utilization | Partial negative proof. TOD can reject a non-provider-ready context package before wasting a model call. |
| Governance | Yes. TOD did not claim engineering independence from schema-shaped artifacts. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Current finding:

The engineering-first correction is still right. TOD should not keep practicing packet administration as if it were software engineering. The next useful rung is to make context packages provider-ready by preserving a source surface/function label from source-anchor evidence. After that, TOD can supervise a small local engineering model on a real bounded candidate instead of sending blank-context prompts or drifting into route-patch evidence lanes.

Next smallest training rung:

`TOD-CONTEXT-PACKAGE-SOURCE-SURFACE-FALLBACK-V1`

Mission:

Using R201 and R203 as evidence, TOD must propose the smallest repair that makes engineering context packages provider-ready when the source-anchor artifact has `source_file`, `start_line`, `end_line`, and `anchor_pattern` but no explicit `source_function`. The proposal must preserve `source_file`, derive a meaningful source surface label, preserve the original source-anchor artifact, and define a validation command that proves R202 would become provider-ready without editing the input or output artifacts.

## 2026-07-25 R204 False Materialization

Objective:

`TOD-CONTEXT-PACKAGE-SOURCE-SURFACE-FALLBACK-V1`

R204 attempt:

- Task: `R204-20260725`
- Intended output: `runtime_remote_training/tod_independent_resolution_attempts/TOD_CONTEXT_PACKAGE_SOURCE_SURFACE_FALLBACK_R204.packet.json`
- Outcome: task state says completed, but validation rejects it.
- Actual artifact: missing.
- Source mutation: none. The pre/post source hash was unchanged.
- Misroute evidence: the packaged prompt auto-materialized `Edit Mode: replace_text` plus a huge `Old Text`/`New Text` block from `LocalExecutionEngine.ps1` internals instead of selecting the packet-body synthesis artifact lane.
- Review result: not a pass. No provider-ready context repair packet exists.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. |
| Runtime | Partial negative proof. The materializer still prefers generic bounded replace when packet-body intent is underspecified. |
| Evidence | Yes. The missing artifact and bad package directives are inspectable. |
| Model Utilization | No. |
| Governance | Yes. The result is rejected despite a local completed status. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-PACKET-BODY-SYNTHESIS-DIRECTIVE-ROUTING-V1`

Mission:

Prove TOD can route an explicit packet-body synthesis task into the artifact-writing lane without falling through to generic `replace_text`. Use R201 as input, write a packet-body artifact only, and then reject or accept the artifact quality separately. This is Runtime + Evidence proof first; Engineering credit requires a later artifact whose `new_text` is source-valid and behavior-changing.

## 2026-07-25 R205-R206 Packet-Body Lane Routing Proof

R205 paragraph-directive attempt:

- Task: `R205-20260725`
- Outcome: blocked.
- Blocker: `packet_body_synthesis_autonomous_new_text_missing`.
- Actual cause: the required `Field Name`, `Field Value`, and `Insert Before Pattern` directives were embedded inside paragraph text and did not survive as parseable line directives.
- Secondary materializer finding: the task still showed multiple target candidates because input artifact, output artifact, and source file were all present in the prompt.
- Lesson: packet-body synthesis directives must be line-based. Prose instructions are not enough for this executor.

R206 line-directive attempt:

- Task: `R206-20260725`
- Output: `runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_BODY_SYNTHESIS_LINE_DIRECTIVE_R206.packet.json`
- Outcome: completed.
- What passed:
  - packet-body synthesis lane selected
  - source-anchor input artifact read
  - output artifact written
  - source file not mutated
  - packet candidate schema validated
- What failed quality review:
  - `new_text` inserted JSON-style `"source_surface": "engineering_context_package_source_field_selection",` into PowerShell source.
  - Candidate parse check failed with `Missing '=' operator after key in hash literal`.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. Candidate is not source-valid. |
| Runtime | Yes. R206 proved the packet-body synthesis lane can be reached when directives are line-based. |
| Evidence | Yes. R206 artifact and parse failure are durable. |
| Model Utilization | Partial. TOD now has a concrete bad candidate to reject before provider/source mutation. |
| Governance | Yes. Do not apply R206; treat it as a rejected candidate. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Current finding:

TOD has climbed one rung: lane routing and directive parsing can work. It has not yet learned engineering-quality synthesis. The next useful step is candidate quality judgment: reject R206 for language/syntax mismatch and produce a provider-ready critique that asks for PowerShell-valid `new_text` rather than JSON-shaped field insertion.

Next smallest training rung:

`TOD-PACKET-CANDIDATE-SOURCE-LANGUAGE-REJECTION-V1`

Mission:

Use the R206 packet artifact as a candidate and produce a judgment artifact that rejects it because the candidate `new_text` is not valid PowerShell for `scripts/engines/LocalExecutionEngine.ps1`. The judgment must preserve the exact parse failure, name the required repair shape, and produce a retry prompt for a model or TOD synthesis step without modifying source.

## 2026-07-25 R207 Candidate Verdict Limitation Proof

Task:

- `R207-20260725`

Inputs:

- Candidate artifact: `runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_BODY_SYNTHESIS_LINE_DIRECTIVE_R206.packet.json`
- Supporting context: `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_CONTEXT_SOURCE_FIELD_SELECTION_CONTEXT_R202.latest.json`

Output:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_CANDIDATE_SOURCE_LANGUAGE_REJECTION_R207.latest.json`

What passed:

- TOD used the read-only audit artifact lane.
- TOD wrote a candidate verdict artifact.
- TOD rejected the candidate before source mutation.
- No source code was modified.

What did not pass:

- The verdict reason was `rejected_no_delta_candidate`, not a source-language or parse-failure reason.
- The verdict inspected root-level fields and did not inspect nested `packet.new_text` from the R206 packet-body artifact.
- The verdict artifact did not preserve the actual PowerShell parse failure.
- The supporting artifact was not a true provider request, but the current verdict lane only recorded it as read, not semantically mismatched.

Independent parse evidence:

```text
candidate_parse=failed
Missing '=' operator after key in hash literal.
```

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not produce or repair valid source text. |
| Runtime | Partial. The candidate-verdict lane can reject unsafe candidates before mutation, but only by shallow checks. |
| Evidence | Yes. R207 created a durable verdict and the independent parse failure is reproducible. |
| Model Utilization | Partial negative proof. TOD has not yet learned to reject provider candidates by target-language validity. |
| Governance | Yes. The bad candidate was not applied or credited. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Current finding:

TOD is making progress as a supervising engineer, but the current verifier is still too administrative. It rejects the R206 candidate because the artifact shape does not match the expected provider-candidate schema, not because it understands that the proposed `new_text` is invalid PowerShell for the target file.

Next smallest training rung:

`TOD-PACKET-CANDIDATE-SOURCE-LANGUAGE-REJECTION-LANE-V1`

Mission:

Teach TOD's candidate-verdict path to inspect the actual proposed source text, including nested packet-body candidate fields, select the parser based on the target file extension, preserve parse errors, and reject source-invalid candidates with a precise reason before source mutation. This remains Model Utilization + Governance training until TOD can use the rejection to request or synthesize a corrected PowerShell-valid candidate.

## 2026-07-25 R208 False Source-Inspection Pass

Task:

- `R208-20260725`

Intended mission:

- Inspect `scripts/engines/LocalExecutionEngine.ps1`.
- Capture the exact source block that creates `tod_engineering_provider_candidate_verdict`.
- Preserve the current candidate-verdict authority before proposing any repair.

Actual output:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_CANDIDATE_VERDICT_SOURCE_ANCHOR_R208.latest.json`

What actually happened:

- TOD reported completion through the read-only task context lane.
- The artifact type was `tod_read_only_task_context_proof`, not `tod_source_anchor_observation`.
- The only inspected file was `E:\TOD\tod\out\prompts\R208-20260725.md`.
- TOD did not inspect `scripts/engines/LocalExecutionEngine.ps1`.
- No source mutation occurred.

Why this matters:

This is a useful false pass. TOD produced administrative proof that the task context was read-only, but it did not perform the engineering inspection requested by the objective. This demonstrates the difference between runtime administration and engineering work.

Root cause:

- The task category was `read_only_audit`.
- The source-anchor observation lane currently accepts categories such as `inspection` and `source_anchor_observation`, but not `read_only_audit`.
- Because the category did not match the source-anchor lane, the executor selected the generic read-only context artifact path.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. The source file was not inspected. |
| Runtime | Partial negative proof. The lane selector obeyed its current category rules, but those rules allow false completion for engineering-inspection intent. |
| Evidence | Yes. The wrong-lane artifact proves the failure mode. |
| Model Utilization | No. No candidate or provider context was improved. |
| Governance | Yes. The false pass is rejected and not counted as engineering progress. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

A read-only proof is not automatically an engineering inspection. TOD must distinguish:

- prompt/context inspection,
- artifact inspection,
- source-anchor inspection,
- source patch planning.

The requested target determines the evidence standard. If the task says to inspect a source file, the proof must name that source file, line range, anchor, and exact source text.

Next smallest rung:

`TOD-PACKET-CANDIDATE-VERDICT-SOURCE-ANCHOR-RERUN-V1`

Mission:

Rerun the candidate-verdict source inspection with an explicit source-anchor category and source-anchor wording. The required output must be a `tod_source_anchor_observation` artifact against `scripts/engines/LocalExecutionEngine.ps1`, not a prompt-context proof. This is still Runtime + Evidence training until TOD uses the source anchor to produce a candidate-verdict repair packet.

## 2026-07-25 R209-R210 Source-Anchor Recovery

R209:

- Task: `R209-20260725`
- Outcome: blocked.
- Blocker: `source_anchor_not_found`.
- Cause: the anchor text was too exact. It attempted to match the full assignment line for `$wantsEngineeringProviderCandidateVerdict`, but source-formatting and prompt escaping made the full-line anchor brittle.
- Source mutation: none. Source hash remained `CE69D48667C03E38B72BAA7129D6ED0854EFCA9F12DF24B97B26B472EC50FFD1`.

R210:

- Task: `R210-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_CANDIDATE_VERDICT_SOURCE_ANCHOR_R210.latest.json`
- Outcome: completed.
- Artifact type: `tod_source_anchor_observation`.
- Source file: `scripts/engines/LocalExecutionEngine.ps1`.
- Captured lines: 7317-7417.
- Exact text includes:
  - root-level `$candidate.PSObject.Properties['old_text']`
  - root-level `$candidate.PSObject.Properties['new_text']`
  - `verdict_reason_code` selection.
- Source mutation: none. Source hash remained `CE69D48667C03E38B72BAA7129D6ED0854EFCA9F12DF24B97B26B472EC50FFD1`.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Inspection credit only. TOD read the real source authority but did not produce a repair. |
| Runtime | Yes. TOD recovered from a brittle source anchor by backing down to a stable source token. |
| Evidence | Yes. The source-anchor artifact is durable and specific. |
| Model Utilization | Partial support. The captured block explains why R206/R207 cannot be judged by source language yet. |
| Governance | Yes. R209 was blocked honestly; R210 passed with source evidence rather than prompt-context evidence. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

Source anchors should be stable enough to survive formatting while still pointing at the precise source authority. Over-specific anchors create false blockers; under-specific anchors create wrong-source risk. TOD must choose the smallest stable source token that uniquely identifies the source authority under inspection.

Next smallest training rung:

`TOD-CANDIDATE-VERDICT-NESTED-PACKET-REPAIR-PACKET-V1`

Mission:

Using R210 as exact source evidence, TOD must produce a bounded repair packet artifact that teaches the candidate-verdict lane to inspect actual proposed source text from both provider-candidate stubs and nested packet-body artifacts. The packet must preserve root-level candidate support, add nested `packet.target_file`, `packet.old_text`, `packet.new_text`, and `packet.validation_command` fallback reads, preserve parse errors for target-language rejection, and include a validation command proving R206 is rejected for PowerShell syntax rather than shallow missing-delta shape. No source mutation before packet review.

## 2026-07-25 R211 Package-Context Contamination Proof

Task:

- `R211-20260725`

Intended mission:

- Use R210 source evidence.
- Attempt a PowerShell-valid candidate packet for the candidate-verdict nested-packet repair.
- Do not let Codex supply the snippet body.
- Either produce the packet or block precisely on autonomous PowerShell snippet synthesis.

Expected output:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_CANDIDATE_VERDICT_NESTED_PACKET_REPAIR_R211.packet.json`

Actual output:

- No R211 packet artifact was written.
- The generated prompt package `tod/out/prompts/R211-20260725.md` included an unrelated `Bounded Edit Materialization` block targeting a broad `replace_text` region around `Invoke-LocalExecutionGenericBoundedTask`, not the R210 candidate-verdict block.
- The R211 task state shows `status: blocked`.
- The source file was not mutated.

What this proves:

- TOD did not reach autonomous PowerShell snippet synthesis.
- The immediate blocker is earlier: package/materialization context contamination.
- A task intended as artifact-only packet formation inherited stale bounded-edit materialization from the active objective state.
- This creates a false engineering target before TOD can practice the actual engineering skill.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not synthesize or validate a PowerShell repair candidate. |
| Runtime | Negative proof. The packaging/materialization layer can inject stale bounded-edit context into a new packet-formation task. |
| Evidence | Yes. R211 prompt and state preserve the contaminated materialization block and missing output artifact. |
| Model Utilization | No. TOD never reached a provider or candidate-supervision loop. |
| Governance | Yes. The missing packet is not counted as progress or borrowed-capability retirement. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

Engineering training tasks must carry exactly one bounded target context. Input artifacts, output artifacts, source files, and previous active objective materialization must not merge into a stale edit packet. Before TOD can supervise engineering candidates, its packet-generation lane must isolate the current task contract from prior bounded-edit materialization state.

Next smallest training rung:

`TOD-PACKET-FORMATION-CONTEXT-ISOLATION-V1`

Mission:

Teach TOD to inspect the task package/materialization path and prove why R211 inherited stale bounded-edit materialization. The required output is a source-anchor observation naming the function or state field that contributes the unrelated `Bounded Edit Materialization` block. This is Runtime + Evidence training only. Do not patch source yet; first prove the source authority and exact contamination mechanism.

## 2026-07-25 R212-R213 Packet-Formation Context Isolation

R212:

- Task: `R212-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_CONTEXT_ISOLATION_R212.latest.json`
- Outcome: completed.
- Artifact type: `tod_source_anchor_observation`.
- Source file: `scripts/TOD.ps1`.
- Captured lines: 7280-7530.
- Exact text includes:
  - `$existingMaterialization`
  - `return $existingMaterialization`
  - `packet_body_synthesis_materialization_valid`
- Source mutation: none.

What R212 proved:

The package/materialization path can reuse an existing materialized `replace_text` block from `task.materialization`. That reuse is only refreshed when fresh `Old Text` and `New Text` directives exist and differ. For packet-formation or artifact-only work, that means a prior active objective can leak stale bounded-edit materialization into a new prompt package before TOD reaches the intended engineering task.

R213:

- Task: `R213-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_PACKET_FORMATION_CONTEXT_ISOLATION_CONTEXT_R213.latest.json`
- Outcome: completed.
- Artifact type: `tod_engineering_context_package`.
- Source mutation: none.

R213 pass:

- The local executor wrote the requested context-package artifact.
- The artifact kept `source_file: scripts/TOD.ps1`.
- The artifact preserved a no-source-mutation validation result.

R213 failure:

- The artifact did not preserve the prompt-supplied `Source Function: Resolve-TaskBoundedEditMaterialization`.
- The artifact collapsed the actual R211 contamination problem into a generic source-anchor packet lesson.
- It did not preserve the exact desired behavior: ignore or refresh stale materialized directives unless they match the current task target, mode, and explicit directives.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not produce or validate a source repair candidate. |
| Runtime | Yes for source-authority discovery; no for repair. |
| Evidence | Yes. R212 and R213 provide durable proof of the contamination mechanism and context-packaging gap. |
| Model Utilization | Partial. TOD created a context package, but the package is not provider-ready because it dropped the most important engineering facts. |
| Governance | Yes. R213 is not counted as independent engineering progress. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

Engineering context packages are not just administrative wrappers. They must preserve the problem, the source authority, the desired behavior, rejected outputs, and validation target exactly enough for a model or human engineer to reason from the current code rather than from stale training patterns.

Next smallest training rung:

`TOD-CONTEXT-PACKAGE-PROMPT-FIELD-PRESERVATION-V1`

Mission:

Teach TOD to preserve prompt-supplied engineering facts in a context package. The next context artifact must carry `problem_summary`, `desired_behavior`, `source_function`, `validation_target`, and `rejected_outputs` from the current task scope when those fields are explicitly provided, while still linking to the inspected source-anchor artifact. No source mutation. This is Model Utilization + Evidence training, not engineering independence.

## 2026-07-25 R214 Prompt-Field Preservation False Pass

Task:

- `R214-20260725`

Intended mission:

- Generate a corrected context package from R212.
- Preserve explicit prompt facts:
  - `Problem Summary`
  - `Desired Behavior`
  - `Source Function: Resolve-TaskBoundedEditMaterialization`
  - `Validation Target`
  - `Rejected Outputs`

Observed prompt evidence:

- `tod/out/prompts/R214-20260725.md` contains the required prompt facts twice.
- The package correctly marks `Bounded Edit Materialization` as `not_required`.
- No source mutation occurred.

Actual output:

- `runtime_remote_training/engineering_corpus/TOD_PACKET_FORMATION_CONTEXT_ISOLATION_CONTEXT_R214.latest.json`

Actual artifact failure:

- `source_function` is still empty.
- `problem_summary` reverted to a generic packet-materialization phrase.
- `desired_behavior` reverted to the generic source-file/old-text/new-text packet phrase.
- `validation_target` reverted to the generic source-anchor packet phrase.
- `rejected_outputs` reverted to marker/comment/whitespace generic outputs.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No source repair candidate was produced. |
| Runtime | Negative proof. The read-only artifact writer can ignore prompt-supplied engineering fields. |
| Evidence | Yes. Prompt and artifact comparison proves the field loss. |
| Model Utilization | No. The produced context package is still not provider-ready. |
| Governance | Yes. The local success banner was rejected as a false pass. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

Success banners are not evidence. The artifact must be compared against the task's required semantic fields. A context package that drops the exact problem is not a model-utilization pass, even if it writes a valid JSON file.

Next smallest training rung:

`TOD-CONTEXT-PACKAGE-WRITER-SOURCE-AUTHORITY-V1`

Mission:

Inspect the context-package writer in `scripts/engines/LocalExecutionEngine.ps1` and publish a `tod_source_anchor_observation` showing where `tod_engineering_context_package` is built, how it reads source fields, and why prompt-supplied fields are not preserved. No source mutation. This remains Runtime + Evidence training until TOD produces a bounded repair packet from the inspected source.

## 2026-07-25 R215-R215B Context-Package Writer Source Authority

R215:

- Task: `R215-20260725`
- Outcome: blocked.
- Blocker: `source_anchor_not_found`.
- Cause: over-specific source anchor. The actual source line exists, but the prompt anchor used a brittle partial function-call string.
- Source mutation: none.

R215B:

- Task: `R215B-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_WRITER_SOURCE_AUTHORITY_R215B.latest.json`
- Outcome: completed.
- Artifact type: `tod_source_anchor_observation`.
- Source file: `scripts/engines/LocalExecutionEngine.ps1`.
- Captured lines: 6906-6977.
- Source mutation: none.

What R215B proved:

- The context package writer builds `tod_engineering_context_package` from `$auditSource`, `$sourceEvidence`, and `$sourceRepairDelta`.
- It does not read prompt/task-focus fields such as `Problem Summary`, `Desired Behavior`, `Source Function`, `Validation Target`, or `Rejected Outputs` when those are provided only in the task scope.
- That explains why R214's prompt contained the correct facts while the generated artifact reverted to generic defaults.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Inspection credit only. TOD found the source authority but did not produce a repair. |
| Runtime | Yes. TOD recovered from an over-specific anchor by rerunning with a stable token. |
| Evidence | Yes. The source-anchor artifact names the exact writer block and line range. |
| Model Utilization | Support only. The source proof now explains why the context package is not provider-ready. |
| Governance | Yes. The blocked R215 attempt was not counted as completion. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

Stable source-anchor selection is now becoming a repeatable TOD skill. The engineering lesson is one step deeper: context packages cannot be useful to an engineering model if the writer ignores the task's explicit engineering facts.

Next smallest training rung:

`TOD-CONTEXT-PACKAGE-PROMPT-FIELD-REPAIR-PACKET-V1`

Mission:

Using R215B as exact source evidence, TOD must produce a bounded repair packet artifact for `scripts/engines/LocalExecutionEngine.ps1`. The packet should add a source of prompt-supplied engineering fields, preserve existing audit-source behavior, and use exact current source text as `old_text`. It must not mutate source before review. If TOD cannot synthesize the PowerShell replacement safely, it must publish a precise blocker naming the missing capability.

## 2026-07-25 R216-R220 Context Package Repair Training Truth

R216:

- Task: `R216-20260725`
- Intended output: `runtime_remote_training/tod_independent_resolution_attempts/TOD_CONTEXT_PACKAGE_PROMPT_FIELD_REPAIR_R216.packet.json`
- Outcome: blocked.
- No packet artifact was written.
- Blocker: `codex_wrapper_only_no_execution` plus `local_execution_scope_not_supported`.
- Local fallback refused to guess between the input artifact, output artifact, `scripts/engines/LocalExecutionEngine.ps1`, and `LocalExecutionEngine.ps1`.

What R216 proved:

- TOD has source-authority evidence from R215B.
- TOD still cannot synthesize a meaningful PowerShell repair packet from that evidence.
- The immediate missing capability is target disambiguation plus provider-ready context/model-utilization support, not engineering implementation success.

R217:

- Task: `R217-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_CONTEXT_PACKAGE_PROMPT_FIELD_REPAIR_R216_BLOCKER_EPISODE_R217.latest.json`
- Outcome: completed.
- Artifact type: `tod_engineering_episode_card`.
- R217 preserved the R216 blocker facts well enough for evidence memory.
- R217 did not request independent credit.

R217 limitation:

- The package still carried stale `OBJ-0026` objective context for an older context-package source-role repair.
- The episode cited `runtime/shared/TOD_EXECUTION_RESULT.latest.json` as the only evidence artifact instead of explicitly carrying R215B, R214, and R216 as separate named evidence objects.
- The debt category was too generic: `engineering_episode_capture` instead of the more useful `model_utilization + runtime_plumbing`.

R218:

- Task: `R218-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_CONTEXT_PACKAGE_PROMPT_FIELD_REPAIR_R216_BLOCKER_EPISODE_R217.examiner_R218.latest.json`
- Outcome: false pass.
- Artifact type: `tod_engineering_episode_quality_examiner_verdict`.
- The artifact correctly refused engineering credit and borrowed-ratio reduction.
- It did not perform the required semantic checks:
  - R215B/R214/R216 evidence coverage.
  - Objective-context contamination in `tod/out/prompts/R217-20260725.md`.
  - Specific debt classification quality.
  - Whether the smallest next repair was actually sufficient.

R219:

- Task: `R219-20260725`
- Intended output: `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_EPISODE_EXAMINER_SEMANTIC_CHECK_SOURCE_AUTHORITY_R219.latest.json`
- Outcome: runner failure before TOD could publish a blocker.
- Observed error: `The property 'id' cannot be found on this object. Verify that the property exists.`
- R219 output artifact was not written.
- Task state remained `planned`.

R220:

- Task: `R220-20260725`
- Intended mission: diagnose the R219 runner failure.
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_R219_RUNNER_FAILURE_DIAGNOSTIC_R220.latest.json`
- Outcome: false pass.
- The artifact type was `tod_read_only_task_context_proof`, not `tod_runner_failure_diagnostic`.
- It inspected only `tod/out/prompts/R220-20260725.md`.
- It did not preserve the observed R219 error, output-artifact absence, runner stage, suspected blocker class, or smallest next diagnostic.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD still has not produced meaningful PowerShell `new_text` or a repair packet for the context-package writer. |
| Runtime | Partial. TOD can capture some blocker episodes, but source-anchor and diagnostic lanes still degrade into generic context proofs or runner crashes. |
| Evidence | Partial. R217 is useful evidence memory; R218 and R220 are false passes that must be quality-gated. |
| Model Utilization | No. TOD still cannot build a provider-ready context from R215B that preserves prompt-supplied engineering fields. |
| Governance | Yes. No source mutation occurred and no independent credit was granted. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Training lesson:

TOD must not treat schema-valid artifacts as examiner-quality evidence. Examiner and diagnostic artifacts must compare the required semantic facts against the produced artifact. If the requested artifact type is not produced, the task is not a pass, even when a generic read-only proof file exists.

Next smallest training rung:

`TOD-SEMANTIC-EXAMINER-AND-DIAGNOSTIC-LANE-DISAMBIGUATION-V1`

Mission:

Teach TOD to distinguish read-only context proof, semantic examiner verdict, runner failure diagnostic, and source-anchor observation as separate evidence products. A generic context proof must not satisfy an examiner or diagnostic task. The next proof should either produce the requested semantic artifact type or block with an exact reason before claiming completion.

Codex validation note:

- `scripts/engines/LocalExecutionEngine.ps1:2353-2412` decides when the read-only audit artifact lane is eligible.
- `scripts/engines/LocalExecutionEngine.ps1:6905` selects `tod_engineering_episode_quality_examiner_verdict`.
- `scripts/engines/LocalExecutionEngine.ps1:7686-7756` writes the current episode-quality examiner artifact.
- `scripts/engines/LocalExecutionEngine.ps1:8486-8526` writes the generic `tod_read_only_task_context_proof` artifact.
- The current examiner source records schema, debt category, borrowed signal, validation summary, lesson, next rung, and no-source-edit fields.
- The current examiner source does not compare requested semantic checks such as R215B/R214/R216 evidence coverage or objective-context contamination.

This validation is borrowed Codex evidence, not a TOD independent pass. TOD still needs to reproduce the source-authority finding through a valid source-anchor or provider-ready context path without the generic read-only proof lane masking the requested artifact.

## 2026-07-25 R221-R224 Engineering Roadmap Selector Lesson

Dave's strategic correction:

- The Engineering Corpus should become the primary product.
- Local Engineering Runtime should start immediately as an engineering-episode platform, not as another months-long runtime-plumbing curriculum.
- Model Utilization should become its own score family: context building, file selection, follow-up question quality, patch rejection, retry judgment, and supervised model use.
- Runtime plumbing is support work. It should not dominate TOD's engineering apprenticeship unless it directly blocks engineering episodes.

R221:

- Task: `R221-20260725`
- Intended output: `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_RUNTIME_MODEL_UTILIZATION_SEPARATION_R221.latest.json`
- Required artifact type: `tod_model_utilization_engineering_judgment`
- Actual output: `runtime_remote_training/read_only_audit_artifacts/R221-20260725_20260721_remaining_dirty_mim_tod_route_experimen.latest.json`
- Actual artifact type: `tod_patch_evidence_authority_classification`
- Outcome: false pass.

What R221 proved:

- TOD accepted the strategic training task but did not answer it.
- The executor selected an older route-authority patch evidence lane instead of the requested model-utilization judgment lane.
- The requested output artifact was not written.
- No borrowed capability should be retired.

R222:

- Task: `R222-20260725`
- Intended mission: source-anchor observation for the selector precedence failure.
- Outcome: blocked.
- First blocker: transient `state.journal-history.json` file lock during task execution.
- Retry blocker: source-anchor observation did not win; generic bounded fallback reported multiple target files.

What R222 taught:

- The source-anchor lane requires exact protocol labels, not near-English equivalents.
- `Source Anchor:` was not enough; the lane expects `Anchor Pattern:`.

R223:

- Task: `R223-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_LANE_PRECEDENCE_R223.latest.json`
- Outcome: partial pass.
- The artifact captured `Test-LocalExecutionSavedRoutePatchEvidenceDiscoveryTask` but only one line, which was not enough evidence to explain the selector failure.

R224:

- Task: `R224-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_LANE_PRECEDENCE_R224.latest.json`
- Outcome: useful source evidence pass.
- The artifact captured the saved-route evidence predicate body from `scripts/engines/LocalExecutionEngine.ps1`.
- The captured source shows the broad trigger:
  - read-only evidence task,
  - route/router/studio/MIM/TOD/authority text,
  - saved/existing/training evidence text,
  - classify/inspect/audit/proof text.

Training conclusion:

- The Local Engineering Intelligence path is the better forward solution.
- The current executor cannot yet cleanly express a program-level engineering/runtime/model-utilization strategy artifact.
- `tod_model_utilization_engineering_judgment` is currently shaped around judging an engineering context package JSON, not a free-form program roadmap markdown file.
- Broad route-authority language can still hijack adjacent read-only training tasks.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No source repair or engineering candidate was produced. |
| Runtime | Yes, but support-only. TOD identified a selector-lane failure that blocks engineering/model-utilization training. |
| Evidence | Yes. R224 is durable source evidence. R221 is a false-pass artifact useful as negative evidence. |
| Model Utilization | No. TOD still did not produce the requested strategy judgment or provider-ready context. |
| Governance | Yes. Borrowed ratio was not reduced. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-ENGINEERING-PROGRAM-JUDGMENT-ARTIFACT-LANE-V1`

Mission:

Teach TOD to produce a program-level engineering judgment artifact from strategy documents and borrowed-capability evidence without falling into route-patch classification, generic context proof, or provider-candidate judgment lanes.

Acceptance:

- Input can be markdown plus JSON evidence.
- Output is a durable JSON artifact under `runtime_remote_training/engineering_corpus/`.
- Artifact separates Engineering, Runtime, Governance, Evidence, Coordination, and Model Utilization.
- Artifact names the next engineering rung and support-only runtime rungs.
- Artifact explicitly states no borrowed-capability ratio reduction.
- Existing provider-context judgment remains reserved for concrete engineering context packages.

Prevention lesson:

Do not force program strategy, source repair packets, provider candidate judgments, and route-authority patch classification through the same artifact lane. TOD needs separate evidence products for separate kinds of engineering intelligence, otherwise runtime selectors keep turning strategic engineering work back into packet administration.

R225:

- Task: `R225-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROGRAM_JUDGMENT_ARTIFACT_LANE_SOURCE_R225.latest.json`
- Outcome: source-anchor pass.
- TOD inspected the current `tod_model_utilization_engineering_judgment` source branch in `scripts/engines/LocalExecutionEngine.ps1`.
- The captured source shows that model-utilization judgment is a concrete provider/context-package readiness artifact, not a general engineering-program strategy artifact.

R226:

- Task: `R226-20260725`
- Intended output: `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_PROGRAM_JUDGMENT_ARTIFACT_LANE_PACKET_R226.latest.json`
- Outcome: revise / failed.
- The intended engineering-corpus packet was not written.
- The executor drifted back into route-patch evidence handling and created a cleanup-hold patch copy instead of the requested program-judgment packet proposal.
- No borrowed-capability ratio reduction is allowed from this run.

Updated conclusion:

TOD now has enough evidence to say the next blocker is not engineering knowledge. It is a runtime support blocker: there is no clean program-level engineering judgment artifact lane. Until that exists, strategic engineering-corpus work can be misrouted into route-authority patch classification.

Next smallest repair:

`TOD-ENGINEERING-PROGRAM-JUDGMENT-ARTIFACT-LANE-V1B`

Mission:

Expose or add a read-only artifact lane that can produce a durable program-level engineering judgment artifact from strategy documents and borrowed-capability evidence, without route-patch classifier hijack and without claiming engineering independence from runtime support work.

## 2026-07-25 R237/R238 Episode-Corpus Continuation

Dave's correction stands:

- Engineering Corpus is the primary product.
- Local Engineering Runtime should begin now as the episode/corpus platform.
- Small local models should start early as supervised episode generators, not as implementation authority.
- Runtime plumbing is a support track, not the main apprenticeship.
- Add `Model Utilization` as its own score family.

R237:

- Task: `R237-20260725`
- Intended output: `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R237.latest.json`
- Outcome: blocked.
- The package said local artifact writing could proceed, but the task was assigned to the Codex wrapper and local fallback rejected the scope.
- No episode artifact was written.

R237B:

- Task: `R237B-20260725`
- Intended output: `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R237B.latest.json`
- Outcome: blocked.
- Even with `AssignedExecutor local`, `run-task` attempted the Codex wrapper first and then local fallback treated all evidence paths as candidate edit targets.
- Blocker: multi-evidence corpus packaging lacks path-role separation for input evidence, output artifact, registry/document evidence, and source file.

R238:

- Task: `R238-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R238.latest.json`
- Outcome: scaffolded pass.
- TOD wrote a basic `tod_engineering_episode_card` from a single input artifact.
- Source health validation still passed: `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.

Codex validation:

- `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R238.codex_validation.json`

Validation verdict:

- Accepted: TOD can write a basic engineering episode card from one clean evidence artifact.
- Rejected: full corpus quality, engineering independence, and borrowed-capability retirement.
- Missing from R238: R231B, R232, R236, explicit source target, and borrowed-ratio preservation language.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source repair or independently synthesized packet was produced. |
| Runtime | Partial. Single-source episode writing works; multi-evidence episode packaging still misroutes. |
| Governance | Yes. The episode does not request independent credit. |
| Evidence | Partial. A durable episode exists, but it is incomplete. |
| Model Utilization | No. No engineering provider was used or judged. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-ENGINEERING-EPISODE-QUALITY-CONTROL-V1`

Mission:

TOD must compare a produced episode card against the required evidence fields and reject or revise incomplete corpus episodes before they are treated as training data.

Why this matters:

The Engineering Corpus only becomes useful if each episode preserves concrete attempts, authorship, validation, recovery, source targets, and borrowed/independent status. A schema-valid but vague episode is not engineering memory; it is runtime paperwork.

## 2026-07-25 R239-R242B Episode Quality-Control Continuation

R239:

- Task: `R239-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R238.quality_R239.latest.json`
- Outcome: partial pass.
- TOD correctly refused engineering credit and kept `borrowed_capability_ratio_effect = no_reduction`.
- TOD did not preserve the task-specific required checks for R231B, R232, R236, source target, or borrowed-ratio language.

R240:

- Task: `R240-20260725`
- Output: `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R238.required_checks_R240.latest.json`
- Outcome: failed specific-check preservation.
- The artifact repeated the generic quality verdict instead of producing the requested `required_checks`, `missing_required_facts`, `accepted_for_training`, and named-attempt checks.
- Codex validation: `runtime_remote_training/engineering_corpus/TOD_PACKET_APPLY_VALIDATION_CONTRACT_EPISODE_R238_REQUIRED_CHECKS_R240.codex_validation.json`

R241:

- Task: `R241-20260725`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_QUALITY_WRITER_SOURCE_AUTHORITY_R241.latest.json`
- Outcome: source-anchor pass after direct local run.
- It captured the read-only artifact selector around `tod_engineering_episode_quality_examiner_verdict`, but not the writer body.
- The bridge runner could not execute the task because `run-bridge-request` does not support `execute-chat-task`. This is runtime support debt, not an engineering pass/fail.

R242/R242B:

- `R242-20260725` blocked on a brittle exact anchor.
- `R242B-20260725` passed with a stable anchor and published `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_QUALITY_WRITER_BODY_SOURCE_AUTHORITY_R242B.latest.json`.
- Codex validation: `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_QUALITY_WRITER_BODY_SOURCE_AUTHORITY_R242B.codex_validation.json`

What R242B proved:

- The quality writer block lives in `scripts/engines/LocalExecutionEngine.ps1` lines 7699-7889.
- The writer emits fixed fields such as `required_episode_fields`, `missing_episode_fields`, `evidence_checked`, and `borrowed_capability_ratio_effect`.
- The captured writer block does not read task-supplied `Required checks`, `Required output fields`, or similar prompt directives.
- This explains why R239/R240 produced broad schema quality verdicts instead of the exact Examiner checks.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No repair packet or source change was produced. |
| Runtime | Yes. TOD found the source authority after one brittle-anchor miss. |
| Governance | Yes. Borrowed capability ratio stayed unchanged. |
| Evidence | Yes. R242B is a durable source-authority proof. |
| Model Utilization | No. No provider/model path was exercised. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-EPISODE-QUALITY-CHECK-LIST-MATERIALIZATION-PACKET-V1`

Mission:

Using R242B source evidence, TOD must produce a bounded repair packet candidate that lets the quality writer preserve and evaluate task-supplied required checks without losing the existing canonical episode schema checks. The packet must be artifact-only until reviewed; no source mutation before packet quality review.

## 2026-07-25 R243 Packet Materialization Result

R243:

- Task: `R243-20260725`
- Objective: `TOD-EPISODE-QUALITY-CHECK-LIST-MATERIALIZATION-PACKET-V1`
- Expected output: `runtime_remote_training/tod_independent_resolution_attempts/TOD_EPISODE_QUALITY_CHECK_LIST_MATERIALIZATION_PACKET_R243.packet.json`
- Outcome: blocked honestly.
- TOD preserved the source-anchor evidence, target file, and output path, but did not synthesize safe behavior-changing `new_text`.
- TOD reported that autonomous `new_text` synthesis was unavailable without an explicit New Text or field-insertion directive.
- No packet artifact was written.
- Source health still passed with `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.

Codex validation:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_EPISODE_QUALITY_CHECK_LIST_MATERIALIZATION_PACKET_R243.codex_validation.json`

Validation verdict:

- Accepted: TOD refused to fabricate a packet when it lacked safe source-to-new-text synthesis.
- Rejected: packet candidate, source repair, engineering independence, and borrowed-capability retirement.
- The blocker moved from artifact routing into engineering synthesis: TOD can inspect the source and name the missing behavior, but cannot yet transform that source evidence into a minimal safe code change.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No meaningful behavior-changing edit text was synthesized. |
| Runtime | Yes. The task preserved source, target, and output roles. |
| Governance | Yes. TOD did not claim completion or retirement. |
| Evidence | Partial. The blocker is durable, but no repair packet exists. |
| Model Utilization | No. No engineering model/provider path was used to assist synthesis. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

TOD must learn to synthesize safe, behavior-changing `new_text` from a current source anchor while preserving the same responsibility boundary and rejecting marker-only, schema-only, or artifact-only changes. This is an Engineering track skill, supported by Evidence and Model Utilization. Runtime plumbing should not dominate this rung unless it directly blocks the engineering episode.

## 2026-07-25 R244-R244C Source Anchor To New Text Attempt

R244:

- Task: `R244-20260725`
- Category used: `engineering_synthesis`
- Outcome: blocked before local execution.
- No candidate artifact was written.
- Cause: `engineering_synthesis` is not an active supported local category; the task produced a wrapper-only blocker and no engine path.

R244A:

- Task: `R244A-20260725`
- Category used: `packet_formation`
- Outcome: blocked before the intended read-only artifact lane.
- Cause: the task type was shaped as `read_only_assessment`; the local fallback did not enter the source-anchor delta artifact writer.

R244B:

- Task: `R244B-20260725`
- Category used: `artifact_write`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_QUALITY_WRITER_REQUIRED_CHECK_DELTA_R244B.latest.json`
- Outcome: pass.
- TOD published the required `tod_source_anchor_delta_proposal`.
- The artifact preserved the source anchor, target file, intended behavior delta, no-source-edit boundary, and an honest blocker: `autonomous_candidate_new_text_missing`.

R244C:

- Task: `R244C-20260725`
- Category used: `artifact_write`
- Inputs:
  - `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_QUALITY_WRITER_BODY_SOURCE_AUTHORITY_R242B.latest.json`
  - `runtime_remote_training/read_only_audit_artifacts/TOD_EPISODE_QUALITY_WRITER_REQUIRED_CHECK_DELTA_R244B.latest.json`
- Output: `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_SYNTHESIS_R244C.latest.json`
- Outcome: pass as honest blocker.
- TOD published `tod_autonomous_meaningful_newtext_synthesis` with source anchor, prior delta artifact, target file, nonempty old text, blank new text, and the precise blocker `autonomous_meaningful_new_text_synthesis_missing`.

Validation:

- `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"` passed.
- `python tools\build_tod_borrowed_capability_training_plan.py` regenerated the borrowed capability plan.
- No source code was modified for R244B/R244C.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD still cannot synthesize safe behavior-changing `new_text` independently. |
| Runtime | Yes. Correct task shape is now proven: `artifact_write` + required artifact type reaches the existing local artifact lane. |
| Governance | Yes. TOD did not request independent credit. |
| Evidence | Yes. Source anchor, prior delta, and synthesis blocker are durable and linked. |
| Model Utilization | Partial diagnostic credit only. R244C proves the next missing resource is a learned code-delta model/provider path, not more packet routing. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Updated training interpretation:

The current blocker is no longer “TOD cannot make packets.” The blocker is “TOD does not yet have an engineering synthesis resource capable of turning source evidence and desired behavior into safe new text.” Runtime support should now serve the Engineering Corpus and Model Utilization track instead of becoming the main curriculum.
## 2026-07-25 R253-R260 Engineering-First Runtime Pivot

Dave's updated correction:

- The Engineering Corpus is the primary product.
- Local Engineering Runtime should begin immediately as an engineering-episode platform.
- Small local models should be used now as supervised candidate generators, not implementation authority.
- Runtime plumbing is necessary, but it should not dominate TOD's apprenticeship.
- Add Model Utilization as a first-class score family.

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_CORPUS_FOUNDATION_ENGINEERING_FIRST_R253.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_FROM_R145_R254.codex_bridge.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_STUB_FROM_R145_R254.codex_bridge.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_VERDICT_R255.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_VERDICT_R255.codex_validation.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_VERDICT_SAFETY_POLICY_SOURCE_R256.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_VERDICT_DELTA_PROPOSAL_R259.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_VERDICT_MEANINGFUL_NEWTEXT_SYNTHESIS_R260.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_ENGINEERING_FIRST_RUNTIME_PIVOT_R253_R260.codex_validation.md`

Observed result:

- R253 produced an engineering-first corpus index and correctly refused borrowed-ratio reduction.
- The local Qwen server was reachable and produced a candidate from current provider-request evidence.
- The candidate was unsafe: blank `new_text`, weak target/anchor grounding, and generic validation.
- R255 incorrectly accepted that unsafe candidate, proving TOD's model-utilization supervision is not mature.
- R256 captured current source evidence for the provider-candidate verdict policy in `scripts/engines/LocalExecutionEngine.ps1`.
- R257/R257B failed to produce a repair packet because TOD still needs explicit `Old Text` and `New Text` instead of synthesizing them from source evidence.
- R259 produced the source-anchor delta proposal rung.
- R260 produced the meaningful-new-text synthesis artifact and honestly blocked with `new_text_nonempty=false`.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not synthesize safe behavior-changing source text. |
| Runtime | Partial. The existing source-anchor/delta/synthesis ladder can record the episode. |
| Governance | Yes. TOD did not request implementation credit for blocker artifacts. |
| Evidence | Yes. Current artifacts preserve source, candidate failure, and synthesis blocker. |
| Model Utilization | No. TOD accepted an unsafe model candidate and needs supervision training. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This is valuable current evidence, not proof of independence.

Next smallest training rung:

`TOD-PROVIDER-CANDIDATE-VERDICT-SAFETY-POLICY-V1`

Mission:

TOD must learn to reject unsafe local-model candidate patches before source mutation. The verdict policy must reject blank `old_text`, blank `new_text`, candidates whose `old_text` is not proven against current source, and generic validation commands that do not exercise the changed path.

Program implication:

TOD should now be trained as an engineering supervisor. A weak local model is useful only if TOD can build context, reject bad output, request a better attempt, and record the episode. The model does not become authority; TOD does.

## 2026-07-25 R261-R272 Engineering Supervision Track

Dave's correction:

- Do not let runtime plumbing dominate TOD's apprenticeship.
- Split TOD development into distinct tracks: Engineering, Runtime, Governance, Evidence, and Model Utilization.
- Start the Engineering Corpus and local engineering runtime now.
- Use the small local model now as a supervised candidate generator, not as source-edit authority.
- TOD's durable skill is supervising engineering: choose context, reject bad patches, request better attempts, validate, recover, and record the episode.

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_VERDICT_R261.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_REPLAN_AFTER_SAFETY_REJECTION_R262.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_REPLAN_GROUNDING_CHECK_R263.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CONTEXT_FROM_VERDICT_SAFETY_R264.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CONTEXT_FROM_VERDICT_SOURCE_ANCHOR_R265.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_FUNCTION_SURFACE_R266C.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_VERDICT_SAFETY_POLICY_SOURCE_R267.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CONTEXT_FROM_VERDICT_FUNCTION_ANCHOR_R268.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CONTEXT_READINESS_JUDGMENT_R269.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_REQUEST_FROM_VERDICT_FUNCTION_ANCHOR_R270.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_FROM_R270_R271.codex_bridge.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_STUB_FROM_R270_R271.codex_bridge.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_QWEN_CANDIDATE_VERDICT_R272.latest.json`

Observed result:

- R261 proved the new candidate-verdict policy rejects unsafe local-model output before source mutation.
- R262 attempted replan after rejection, but reused stale grounding and a generic validation command.
- R263 detected only a shallow artifact-type difference and did not catch the deeper source-anchor mismatch.
- R264 created a provider context package from the R260 blocker but failed to preserve the exact source file.
- R265 corrected the source-file grounding by using the R256 source-anchor artifact directly.
- R266/R266B were wrapper-only attempts because the task was not shaped into the supported read-only assessment lane.
- R266C published a semantic audit, but the function surface remained blank because the source-anchor evidence did not record the enclosing function.
- Codex added borrowed runtime support so source-anchor observations can infer the enclosing PowerShell function from current source context.
- R267 proved the source anchor now records `source_function` and `function_surface`.
- R268 and R269 built a function-aware context package and judged it provider-prompt ready.
- R270 generated a grounded provider request, but the top-level provider-request fields still did not preserve `source_function`, and the validation command remained generic.
- R271 used the local Qwen service as a supervised candidate generator. The model returned unusable bounded-edit output: placeholder target semantics, no normalized target, no valid old/new text, and no validation command.
- R272 required TOD to judge that model output before source mutation. TOD correctly rejected it and published failed policy checks for target mismatch, blank `old_text`, blank `new_text`, absent validation command, and no behavior delta.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD still has not produced a safe, meaningful, behavior-changing source patch independently. |
| Runtime | Partial, borrowed. Codex repaired source-anchor function inference after TOD surfaced the missing evidence field. |
| Governance | Yes. TOD rejected unsafe model output before source mutation and did not count model output as implementation progress. |
| Evidence | Yes. The episode now links source anchor, context package, provider request, local model output, and TOD verdict. |
| Model Utilization | Partial. TOD can now supervise and reject a bad local-model candidate, but it has not yet produced or requested a successful corrected candidate. |

Known scoring defect:

- `TOD_LOCAL_QWEN_CANDIDATE_VERDICT_R272.latest.json` marks `validation_command_specific=true` even when `validation_command_present=false`.
- This did not create source risk because the verdict was still `reject`, but the policy should learn that specificity cannot pass when the command is absent.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The result is valuable model-utilization evidence, not TOD engineering independence.

Next smallest training rung:

`TOD-VALIDATION-COMMAND-SPECIFICITY-TRUTH-TABLE-V1`

Mission:

TOD must learn that validation specificity is conditional on validation presence. A blank validation command must fail both `validation_command_present` and `validation_command_specific`, and the verdict evidence must expose that failure clearly.

Next engineering rung after that:

`TOD-LOCAL-MODEL-CANDIDATE-RETRY-SUPERVISION-V1`

Mission:

TOD must use the rejected candidate, the function-aware source anchor, and the provider request to request or produce a corrected candidate with exact `target_file`, exact current `old_text`, meaningful `new_text`, and a focused validation command. The corrected candidate still may not mutate source until TOD's verdict accepts it.

## 2026-07-25 R273-R274 Validation Specificity Repair

Trigger:

- R272 correctly rejected the local-model candidate, but its policy evidence exposed a scoring defect: `validation_command_specific` could pass when `validation_command_present` failed.

TOD attempt:

- R273 packaged a read-only source-anchor observation for `scripts/engines/LocalExecutionEngine.ps1`.
- The package was valid and classified as `read_only_assessment` with `source_anchor_observation`.
- The local dispatch failed before execution with `Task not found in local state cache or remote task registry: R273-20260725`.

Codex intervention class:

- `escalation_after_TOD_attempt`
- Reason: TOD produced the failing R272 evidence and attempted the next source-anchor rung, but local task-state dispatch blocked the read-only observation before the engine lane could run.

Borrowed repair:

- `scripts/engines/LocalExecutionEngine.ps1`
- The verdict policy now calculates `validation_command_specific` as true only when the command is present and not generic.
- Blank validation evidence is now reported as `validation command is blank`.

Regression test:

- `tests/TOD.LocalFallbackExecutor.Tests.ps1`
- Added `rejects provider candidate with blank validation command as not specific`.
- The test builds a candidate with valid target, nonblank old/new text, and blank `validation_command`; expected verdict is `reject` with `rejected_missing_validation_command`, and both `validation_command_present` and `validation_command_specific` must fail.

Validation:

- Parse check passed: `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.
- Focused regression passed inside the broader Pester run.
- Broad file status remained 69 passed / 33 failed. Those failures are pre-existing broader local-fallback packet/materialization issues and were not resolved by this narrow truth-table repair.

Replay blocker:

- R274/R274B attempted to re-run the real R271 candidate through TOD after the repair.
- Both attempts failed before verdict publication because `tod/data/state.reliability-history.json` was locked by another process.
- This is a runtime hygiene blocker, not an engineering policy failure.
- R275 attempted to publish a custom runtime-hygiene blocker artifact, but the unsupported artifact type fell into the wrong local path and required a pre-existing target file.
- R275B backed up one rung and used the existing `tod_read_only_task_context_proof` lane. It passed, proving the lock issue is a read-only runtime hygiene blocker and not a source-edit objective.
- R276 successfully replayed the real local-model candidate verdict after the lock cleared.
- R276 proved the truth-table repair: blank validation now fails both `validation_command_present` and `validation_command_specific`.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Borrowed. Codex authored the policy patch after TOD attempt. |
| Runtime | Partial. TOD backed up to an existing context-proof lane; the dispatch/file-lock blocker remains hygiene debt. |
| Governance | Yes. The repair is classified as borrowed and not counted as TOD independence. |
| Evidence | Yes. R272 evidence, R273 package, focused regression, R275B context proof, and R276 replay verdict are linked. |
| Model Utilization | Partial. TOD rejected unsafe model output, but corrected-candidate retry remains open. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest blocker-training rung:

`TOD-STATE-RELIABILITY-HISTORY-FILE-LOCK-HYGIENE-V1`

Mission:

TOD must classify and safely handle `state.reliability-history.json` write locks during local execution without corrupting state, killing unrelated processes, or pretending the requested task ran.

Next model-utilization rung after lock hygiene:

`TOD-LOCAL-MODEL-CANDIDATE-RETRY-SUPERVISION-V1`

Mission:

Use the rejected R271/R272 candidate and the repaired verdict policy to request a corrected local-model candidate, then require TOD to accept or reject it from exact source evidence before any source mutation.

## 2026-07-25 R277-R280 Already-Applied Readiness Defect

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_VALIDATION_SPECIFICITY_CURRENT_SOURCE_R277.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CONTEXT_FROM_VALIDATION_SPECIFICITY_R278.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_VALIDATION_SPECIFICITY_CONTEXT_READINESS_R279.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ALREADY_APPLIED_CONTEXT_READINESS_COMPARISON_R280.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_MODEL_UTILIZATION_ALREADY_APPLIED_READINESS_R277_R280.codex_validation.json`

Observed result:

- R277 passed and captured current source after the validation specificity truth-table repair.
- The source anchor proves the current source already contains `$validationSpecific = (-not $missingValidation -and -not $genericValidation)`.
- R278 built a context package from that current source, but still used a generic behavior-changing output contract and a generic validation command.
- R279 judged that package `provider_prompt_ready`, even though the current source already contained the requested repair.
- R280 attempted a read-only evidence comparison, but only reported the artifact-type/header difference and missed the semantic problem.
- Codex validation classified this as `fail_model_retry_readiness`.

Capability finding:

TOD can reject bad model output after a candidate exists, but it cannot yet reliably decide whether a model retry should be requested at all.

The missing skill is not another packet route. It is engineering supervision:

- compare desired behavior against current source;
- recognize already-applied/no-change states;
- downgrade provider readiness when the next step should be validation or closure instead of new `new_text`;
- avoid asking a model to patch code that is already correct.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No TOD-authored source change or independent closure. |
| Runtime | Partial. TOD used source-anchor, context-package, judgment, and comparison lanes. |
| Governance | Yes. No source mutation occurred and no independent credit was claimed. |
| Evidence | Yes. The failure is now evidence-backed across R277-R280. |
| Model Utilization | Failed readiness judgment. TOD over-trusted context readiness instead of detecting already-applied source. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-ALREADY-APPLIED-CONTEXT-READINESS-REJECTION-V1B`

Mission:

Before asking a model for `new_text`, TOD must compare the desired behavior with current source evidence. If the requested behavior already exists, TOD must reject or downgrade provider readiness and route to validation/closure instead of model patch generation.

## 2026-07-25 R281-R284 Supporting-Evidence Readiness Repair

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_PROVIDER_READINESS_REJECTION_R281.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_JUDGMENT_SUPPORTING_EVIDENCE_GAP_R282B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_JUDGMENT_SUPPORTING_EVIDENCE_DELTA_R283.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_PROVIDER_READINESS_REJECTION_R284.latest.json`

Observed result:

- R281 re-ran the already-applied readiness judgment with supporting artifacts, but still returned `context_quality=provider_prompt_ready` and `candidate_request_ready=true`.
- R282 first failed because the source anchor was too exact for the current file.
- R282B backed up one rung and passed a source-anchor observation for the model-utilization judgment branch in `scripts/engines/LocalExecutionEngine.ps1`.
- R283 produced a source-delta proposal but blocked on `autonomous_candidate_new_text_missing`, proving TOD still could not synthesize the safe control-plane repair independently.
- Codex then made a borrowed support repair after TOD's bounded attempts: the model-utilization judgment branch now reads named supporting artifacts and can downgrade provider/model retry readiness when evidence proves the requested source behavior is already applied.
- R284 re-ran the judgment and passed: `context_quality=already_applied_no_provider_retry`, `candidate_request_ready=false`, `provider_readiness_downgraded_by_supporting_evidence=true`, and `blocker_or_next_action.reason_code=already_applied_source_evidence`.

Validation:

- Parse check passed: `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.
- Focused regression passed inside `tests/TOD.LocalFallbackExecutor.Tests.ps1`: `downgrades model provider readiness when supporting evidence proves already-applied source`.
- Broad Pester file result: 70 passed / 33 failed. The 33 failures are pre-existing wider local-fallback/materialization failures and were not resolved by this narrow repair.
- Live TOD task replay passed: `TOD-ALREADY-APPLIED-CONTEXT-READINESS-REJECTION-V1B` task `R284-20260725` published the expected artifact.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not author the source repair or independently synthesize safe `new_text`. |
| Runtime | Borrowed support. Codex added supporting-artifact awareness after TOD surfaced the blocker. |
| Governance | Yes. The repair is recorded as borrowed, and R284 did not request source mutation or independent completion credit. |
| Evidence | Yes. R281, R282B, R283, and R284 preserve the failed judgment, source surface, proposed delta blocker, and successful replay. |
| Model Utilization | Partial. TOD can now route already-applied source evidence to validation/closure instead of asking a model for redundant patch text. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-ALREADY-APPLIED-CLOSURE-VALIDATION-V1`

Mission:

TOD must take an already-applied/no-provider-retry judgment and complete the next valid engineering-supervision step: cite or run focused validation, produce a closure artifact, and avoid requesting model patch text when the desired source behavior is already present.

## 2026-07-25 R285-R287 Closure Validation Attempt

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_CLOSURE_VALIDATION_R285.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_CLOSURE_EPISODE_CARD_R286.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_ALREADY_APPLIED_CLOSURE_EPISODE_EXAMINER_R287.latest.json`

Observed result:

- R285 completed, but used the generic read-only evidence-comparison lane and compared artifact header lines.
- This did not prove the requested semantic closure claim: already-applied source behavior should route to validation/closure instead of provider `new_text` generation.
- R286 preserved the attempt as an engineering corpus episode.
- R287 Examiner verdict accepted the episode only as runtime-support memory, with `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can now preserve weak/failed closure attempts as corpus episodes and run an Examiner gate without inflating progress. TOD still cannot independently produce a semantic closure artifact that answers the requested engineering-supervision question.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No independent source diagnosis, patch, validation, or closure proof. |
| Runtime | Partial. TOD routed the artifacts, produced an episode card, and ran Examiner. |
| Governance | Yes. Examiner denied borrowed-ratio reduction and no independent credit was requested. |
| Evidence | Yes. The failed semantic closure attempt is durable and quality-gated. |
| Model Utilization | Partial only. TOD avoided provider retry after R284, but did not yet complete semantic closure validation. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next training direction:

Return to a fresh engineering episode where TOD must inspect current source, diagnose a behavior, propose a bounded change or explicit no-change closure from evidence, validate, publish evidence, and pass Examiner without Codex authoring the solution.

Runtime plumbing should not be the main curriculum unless it blocks that engineering episode.

## 2026-07-25 R288-R290B Fresh Engineering Episode: Supporting Artifact Dedupe

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SUPPORTING_ARTIFACT_DEDUPE_SOURCE_R288D.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SUPPORTING_ARTIFACT_DEDUPE_DELTA_R289.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_NEWTEXT_SYNTHESIS_R290.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_NEWTEXT_SYNTHESIS_R290B.latest.json`

Observed issue:

- The model-utilization judgment branch can read supporting artifacts, but `supporting_artifacts_read` may emit the same supporting artifact path multiple times when repeated `Supporting Artifact:` directives appear in prompt, scope, package metadata, or combined text.
- This is a real behavior issue in `scripts/engines/LocalExecutionEngine.ps1`, not a scoreboard or wrapper artifact.

Observed result:

- R288 and R288B failed because the requested source anchor was too exact.
- R288C backed up to a whole-line style anchor but still failed on quoting/escaping fragility.
- R288D passed after TOD used the stable source token `supportingArtifactMatches`, identified the source file, and inferred the enclosing function `Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R289 produced a bounded source-delta proposal but blocked on `autonomous_candidate_new_text_missing`.
- R290 attempted autonomous new-text synthesis but failed to read the prior delta artifact because the synthesis lane did not treat labeled `Supporting Artifact:` lines as listed inputs.
- R290B retried with explicit listed inputs. It read both the source-anchor artifact and prior delta artifact, confirmed `old_text_nonempty=true`, and still produced `new_text_nonempty=false`.

Capability finding:

TOD has now separated three rungs:

1. Source-anchor discovery can pass with a stable token.
2. Prior delta evidence can be supplied correctly when listed as an input artifact.
3. Autonomous meaningful `new_text` synthesis from source-anchor evidence is still not demonstrated.

This is the desired failure class for the engineering-first curriculum. The next blocker is not generic packet routing. It is engineering model utilization: TOD needs a supervised way to ask an engineering model or local provider for a candidate patch, then judge that candidate from current source and validation evidence.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not synthesize or apply a safe behavior-changing patch. |
| Runtime | Partial. TOD found the source function, preserved input artifacts, and exposed a precise missing synthesis capability. |
| Governance | Yes. No source mutation occurred and no independent credit was claimed. |
| Evidence | Yes. R288D, R289, R290, and R290B preserve the source-anchor, delta blocker, input-role correction, and true synthesis blocker. |
| Model Utilization | Open. The next task is to route the source-anchor problem into a provider/request/verdict loop and require TOD to supervise the result. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`

Mission:

TOD must turn the R288D/R289/R290B evidence into a model-provider context request, capture a candidate patch without directly mutating source, and then accept or reject that candidate using current source evidence plus a focused validation plan.

Success requires TOD to supervise the engineering model. It does not require TOD to become the code generator yet.

## 2026-07-25 R291-R292B Provider Context Preservation Failure

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CONTEXT_R291.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SUPPORTING_ARTIFACT_DEDUPE_CONTEXT_PRESERVATION_R292B.latest.json`

Observed result:

- R291 mechanically published a `tod_engineering_context_package` for the supporting-artifact dedupe defect.
- The output did not preserve the task's actual problem statement, observed failure, desired behavior, or validation target.
- Instead, R291 reverted to the generic older provider-context language about marker-only packet materialization.
- R292 attempted a direct read-only evidence comparison but did not enter the intended artifact-comparison lane.
- R292B backed up to the read-only task context proof lane and passed, but only proved that the task was read-only. It did not evaluate whether the R291 artifact preserved semantic problem context.

Capability finding:

TOD can route a source-anchor artifact into a provider-context artifact, but it cannot yet verify that the context artifact preserved the specific engineering problem being handed to the provider.

This is now a quality-gate problem:

- A provider request that preserves path roles but drops the actual problem is not useful engineering supervision.
- A read-only proof that only checks task mode is not sufficient validation evidence for provider-context quality.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No source patch, no candidate patch, and no semantic provider-context validation. |
| Runtime | Partial. TOD produced the context artifact and backed up to a read-only proof lane when the first comparison path failed. |
| Governance | Yes. The failed semantic preservation is recorded without inflating progress. |
| Evidence | Partial. R291 and R292B preserve enough evidence to identify the quality gap, but not enough for a pass verdict. |
| Model Utilization | Blocked. TOD cannot safely ask a provider for a candidate until provider context preserves the real problem. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-PROVIDER-CONTEXT-SEMANTIC-QUALITY-GATE-V1`

Mission:

TOD must compare the original task prompt against the generated provider-context artifact and produce an explicit pass/fail verdict for semantic preservation:

- problem statement preserved;
- observed failure preserved;
- desired behavior preserved;
- validation target preserved;
- no fallback to unrelated generic provider-context language.

This gate must not count a task-mode proof as semantic evidence.

## 2026-07-25 R293-R300 Provider Context Repair and Model-Utilization Chain

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_FIELD_SELECTION_SOURCE_R293B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_FIELD_SELECTION_DELTA_R294.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CONTEXT_R295.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_CONTEXT_READINESS_R296.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_REQUEST_R297.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_INVENTORY_R298.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_CANDIDATE_STUB_R299.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_CANDIDATE_VERDICT_R300.latest.json`

Observed result:

- R293 first failed because it used the wrong source-anchor task shape.
- R293B used the previously proven source-anchor observation shape and passed, capturing `scripts/engines/LocalExecutionEngine.ps1` lines 6919-6974 around the engineering-context package builder.
- R294 produced a source-anchor delta proposal but again blocked on `autonomous_candidate_new_text_missing`.
- Codex then made a narrow borrowed support repair after TOD attempts: the context-package builder now preserves explicit task-scope `Problem Summary`, `Observed Failure`, `Desired Behavior`, and `Validation Target` directives when present, before falling back to input-artifact defaults.
- The new focused regression `preserves task-scope problem fields in engineering context packages` passed.
- R295 replayed the dedupe provider-context task and passed with the real dedupe problem preserved.
- R296 judged the context `provider_prompt_ready`, with provider reachability still false.
- R297 materialized a provider request that preserved `supporting_artifacts_read` dedupe in the provider prompt.
- R298 inventoried the local provider environment: `python`, `node`, and `nvidia-smi` are present; `ollama`, `llama-cli`, and `llama-server` are not; `gpu_available=true`; `usable_provider_hook=false`.
- R299 created a provider candidate stub with no real candidate response, old text, or new text.
- R300 correctly rejected the stub before source mutation with `verdict=reject` and `accepted_for_source_mutation=false`.

Validation:

- Parse check passed: `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.
- Focused regression passed inside the broader Pester run: `preserves task-scope problem fields in engineering context packages`.
- Broad `tests/TOD.LocalFallbackExecutor.Tests.ps1` still reports 71 passed / 33 failed. The 33 failures are pre-existing wider fallback/materialization failures and are not resolved by this context-preservation support repair.

Capability finding:

TOD now has a cleaner model-utilization supervision chain for this fresh issue:

1. inspect source;
2. preserve engineering problem context;
3. judge provider readiness;
4. materialize provider request;
5. inventory local provider availability;
6. reject no-candidate stub before source mutation.

The remaining blocker is concrete: no usable local engineering provider hook exists yet for producing a real candidate patch. TOD can supervise a stub, but cannot obtain an actual model-generated candidate in this lane.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No real candidate patch or TOD-authored source mutation. |
| Runtime | Borrowed support. Codex repaired task-scope directive preservation after TOD isolated the failure. |
| Governance | Yes. R300 rejected the no-candidate stub and did not inflate progress. |
| Evidence | Yes. R293B-R300 preserve source inspection, failed synthesis, support repair replay, provider request, inventory, stub, and verdict. |
| Model Utilization | Partial. TOD can prepare and police the provider workflow, but cannot yet invoke a real local engineering provider. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-LOCAL-ENGINEERING-PROVIDER-HOOK-ACTIVATION-V1`

Mission:

TOD must identify the smallest safe local provider hook that can produce a candidate patch from an existing provider request without installing new models, downloading dependencies, editing source directly, or treating the stub as a real candidate. If no provider exists, TOD must publish a precise provider-hook blocker and recommend the smallest environment/configuration step needed.

## 2026-07-25 R301-R302 Provider-Hook Blocker Episode

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_LOCAL_PROVIDER_HOOK_BLOCKER_EPISODE_R301.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_LOCAL_PROVIDER_HOOK_BLOCKER_EXAMINER_R302.latest.json`

Observed result:

- R301 converted the R298 provider inventory and R300 stub rejection into a durable engineering-corpus episode.
- The episode classified the current blocker as `runtime_plumbing`, not independent engineering.
- R302 Examiner accepted the episode as `accept_runtime_support_only`.
- R302 explicitly set `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can now preserve and quality-gate the local-provider-hook blocker without inflating engineering capability. That is useful governance, but it does not yet create the local engineering provider needed for real candidate generation.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No real provider candidate and no source patch. |
| Runtime | Partial. Provider availability and blocker evidence are durable and Examiner-gated. |
| Governance | Yes. Examiner prevented false borrowed-ratio reduction. |
| Evidence | Yes. R301/R302 connect inventory, stub rejection, and no-credit classification. |
| Model Utilization | Blocked on local provider hook activation. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-LOCAL-ENGINEERING-PROVIDER-HOOK-ACTIVATION-V1B`

Mission:

Identify an approved local provider path already available on this machine or publish the exact missing setup requirement. The next action must not install or download anything automatically. It should determine whether a configured local model service exists outside the simple `ollama`/`llama-cli`/`llama-server` checks, then record the smallest safe activation path for Dave/Codex review.

## 2026-07-25 R303-R311 Local Provider Invocation And Replan Episode

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVENTORY_PATH_ONLY_SOURCE_R303.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_INVENTORY_R304.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CANDIDATE_R306.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_VERDICT_R307.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_REPLAN_R311.latest.json`

Observed result:

- R303 inspected the provider inventory source path and found the shallow detector only checked PATH tools: `ollama`, `llama-cli`, `llama-server`, `python`, `node`, and `nvidia-smi`.
- The actual local provider was already available outside that shallow check: `tools/llama.cpp/llama-server.exe`, `models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf`, and `http://127.0.0.1:8008/v1/models`.
- Codex added borrowed runtime support so the inventory lane can inspect configured repo-local assets and a running local provider endpoint.
- R304 replayed the inventory and correctly reported `real_provider_reachable=true`, `usable_provider_hook=true`, and the live model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- Codex added a borrowed provider-invocation lane so TOD can call the local provider, capture a candidate, and route it through a verdict gate.
- R306 invoked the local provider and captured a real candidate response.
- R307 rejected the candidate before source mutation because the parsed candidate had blank `new_text`.
- R309 proved the read-only task-mode gate could accept a replan request, but also exposed that artifact writes require an explicit `Output Artifact`.
- R310 completed the replan artifact write with an explicit output path.
- Codex then tightened borrowed replan support so it can consume real provider invocation artifacts and locate source-anchor artifacts by content, not only by filename.
- R311 completed the corrected replan and preserved the real provider invocation plus source-anchor lineage.

Validation:

- Parse check passed: `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.
- R304 result: `provider_request_ready=true`, `configured_provider_available=true`, `running_provider_endpoint.reachable=true`, `real_provider_reachable=true`, `usable_provider_hook=true`.
- R306 result: `provider_called=true`, `candidate_response_available=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R307 result: `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`.
- R311 result: `provider_request_ready_for_retry=true`, `input_candidate_invocation=runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CANDIDATE_R306.latest.json`, `source_anchor_artifact=runtime_remote_training/read_only_audit_artifacts/TOD_SUPPORTING_ARTIFACT_DEDUPE_SOURCE_R288D.latest.json`, `no_source_code_modified=true`.

Capability finding:

TOD can now supervise a local engineering provider through a safer loop:

1. inspect provider-hook source logic;
2. inventory configured local provider assets and running endpoint;
3. invoke the local provider against a preserved engineering context;
4. reject a weak candidate before source mutation;
5. produce a retry replan that preserves provider invocation and source-anchor lineage.

This is progress in runtime support, evidence integrity, governance, and model utilization. It is not yet independent engineering implementation because TOD has not accepted a valid behavior-changing patch or modified source from a provider-generated candidate.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No accepted behavior-changing candidate and no TOD-authored source mutation. |
| Runtime | Borrowed support. Codex repaired configured provider discovery, provider invocation, and replan lineage handling after TOD exposed each gap. |
| Governance | Yes. R307 rejected the blank candidate instead of inflating progress. |
| Evidence | Yes. R303-R311 preserve source inspection, provider inventory, provider invocation, rejection, and corrected replan lineage. |
| Model Utilization | Partial. TOD can call and police the local provider, but it cannot yet drive the provider to an acceptable patch. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New measurable progress: local provider hook activation and candidate-supervision loop are no longer purely theoretical.

Next smallest training rung:

`TOD-PROVIDER-CANDIDATE-RETRY-FROM-REPLAN-V1`

Mission:

Use the R311 replan to produce a second local-provider candidate. The retry must preserve the source anchor, include nonblank `new_text`, and still pass through the same verdict gate before any source mutation. If the second provider candidate is weak, TOD must classify the provider prompt/context deficiency and create a smaller model-utilization improvement rung rather than mutating source.

## 2026-07-25 R312-R320 Provider Retry And Verdict Safety Episode

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CANDIDATE_R313.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_VERDICT_R316.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_REPLAN_R318.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CANDIDATE_R319.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_VERDICT_R320.latest.json`

Observed result:

- R312 tried to retry from the R311 replan but exposed that the candidate invocation lane did not dereference replan inputs.
- Codex added borrowed support so provider-candidate invocation can read a replan artifact, recover the underlying provider request, apply the revised provider instruction, and preserve `input_replan`.
- R313 used the repaired path to call the local provider and produced a nonblank candidate with target, old text, new text, and risk notes.
- R316 rejected the R313 candidate before source mutation because the validation command was still a generic placeholder rather than an executable proof command.
- Codex tightened verdict evidence so rejections preserve candidate type, provider request lineage, target file, old/new text lengths, and validation command.
- Codex tightened replan wording for `rejected_generic_validation_command` so the next retry explicitly requires a concrete executable command.
- R318 produced a reason-aware replan that instructs the provider not to return phrases like `PowerShell parse or focused regression`.
- R319 retried the provider from R318. The provider was called, but the result regressed to blank `new_text` and the same generic validation placeholder.
- R320 rejected the R319 candidate before source mutation because `new_text` was blank and validation remained generic.

Validation:

- R313 result: `provider_called=true`, `candidate_response_available=true`, `replan_instruction_applied=true`, `old_len=463`, `new_len=743`, `required_fields_present=true`.
- R316 result: `verdict=reject`, `verdict_reason_code=rejected_generic_validation_command`, `input_provider_request=runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_REQUEST_R297.latest.json`, `accepted_for_source_mutation=false`.
- R318 result: `provider_request_ready_for_retry=true`, `prior_rejection_reason_code=rejected_generic_validation_command`, and a revised instruction requiring a concrete executable validation command.
- R319 result: `provider_called=true`, `candidate_response_available=true`, but `new_len=0` and validation remained generic.
- R320 result: `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, failed checks `new_text_nonblank` and `validation_command_specific`, `accepted_for_source_mutation=false`, `no_source_code_modified=true`.

Capability finding:

TOD now has a safer model-utilization supervision loop:

1. call a configured local provider;
2. capture raw and parsed candidate output;
3. reject weak candidates before source mutation;
4. preserve rejection lineage;
5. generate reason-aware retry instructions;
6. reject repeated bad provider output rather than counting it as progress.

This is a meaningful safety and supervision capability, but it is still not independent engineering implementation. The local provider has not yet produced an acceptable bounded patch, and Codex repaired the invocation/replan evidence lanes during the episode.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No accepted behavior-changing candidate and no source mutation. |
| Runtime | Borrowed support. Codex repaired replan-aware invocation and verdict/replan evidence fidelity. |
| Governance | Yes. R316 and R320 rejected unsafe candidates before mutation. |
| Evidence | Yes. R313-R320 preserve provider retry, verdict, replan, second retry, and final rejection. |
| Model Utilization | Partial. TOD can supervise and reject provider output, but cannot yet obtain an acceptable patch. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The new measurable capability is bad-patch rejection and reason-aware model retry, not independent source repair.

Next smallest training rung:

`TOD-PROVIDER-PROMPT-CONTRACT-TIGHTENING-V1`

Mission:

Improve the provider request/output contract so the local model receives one smaller source anchor, a concrete validation-command requirement, and an explicit rejectable JSON schema. The next attempt must not mutate source. It should prove whether a tighter prompt contract can produce a candidate with nonblank `new_text` and an executable `validation_command`; if not, classify this as a model capability limit rather than a TOD engineering pass.

## 2026-07-25 R321-R324 Provider Prompt Contract Tightening Episode

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_REQUEST_R322.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_CANDIDATE_R323.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SUPPORTING_ARTIFACT_DEDUPE_PROVIDER_VERDICT_R324.latest.json`

Observed result:

- R321 proved the provider request contract could carry a stricter nested output contract, but the top-level `validation_command` still used the old generic placeholder.
- Codex added borrowed support so replan-derived provider requests also set the top-level validation command to a concrete executable-command requirement.
- R322 produced a provider request with a strict JSON instruction, the source target, a preserved source anchor, and an explicit requirement for an executable validation command instead of placeholder phrases.
- R323 called the local provider using the tighter contract. The provider responded, but the response was still not acceptable: it was fenced or malformed JSON, carried a blank `new_text`, and produced a parse-failure risk.
- R324 rejected the R323 candidate before source mutation because `new_text` was blank.

Validation:

- Parse check passed after the borrowed request-contract changes: `powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\scripts\engines\LocalExecutionEngine.ps1; 'loaded'"`.
- R322 result: `provider_request_ready=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, strict JSON output requested, and validation-command placeholders explicitly rejected.
- R323 result: `provider_called=true`, `candidate_response_available=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `old_len=3293`, `new_len=0`, and `risk` includes `candidate_json_parse_failed`.
- R324 result: `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, `new_text_length=0`, and `no_source_code_modified=true`.

Capability finding:

TOD's local provider supervision loop can now tighten prompt contracts and reject invalid model output before mutation. That is useful model-utilization governance. It is still not independent engineering implementation because the local provider did not produce an acceptable bounded patch, and Codex repaired the request-contract path.

The failure class changed:

1. Earlier failures included missing provider hooks, replan dereferencing, evidence lineage, and generic validation placeholders.
2. R322 repaired the prompt contract enough to remove the old generic-validation placeholder as the primary blocker.
3. R323-R324 now show the remaining blocker as candidate materialization quality: malformed/fenced JSON plus blank `new_text`.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No accepted behavior-changing candidate and no source mutation. |
| Runtime | Borrowed support. Codex repaired provider request-contract propagation after TOD exposed the top-level placeholder leak. |
| Governance | Yes. R324 rejected the bad candidate before source mutation. |
| Evidence | Yes. R322-R324 preserve request, provider invocation, candidate quality, and verdict lineage. |
| Model Utilization | Partial. Prompt-contract quality improved, but the model still failed to produce a usable bounded patch. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The new measurable capability is safer provider-contract tightening and rejection, not independent source repair.

Next smallest training rung:

`TOD-PROVIDER-SMALL-ANCHOR-CONTRACT-V1`

Mission:

Back up from the broad 3,293-character source anchor to a much smaller source-anchor target and ask the local provider for a non-mutating bounded patch candidate. The attempt must use strict JSON, a concrete executable validation command, and the same verdict gate. If the provider still returns blank or malformed output, classify the limit as model/output-materialization debt instead of continuing to inflate TOD engineering progress.

## 2026-07-25 R325-R327 Small Anchor Dispatch And Active-Lane Blocker

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_CONTRACT_R327.prompt.txt`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SMALL_ANCHOR_CONTRACT_SOURCE_R327.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_CONTRACT_BLOCKER_R327.latest.json`

Observed result:

- R325 submitted the small source-anchor request through TOD chat execution. No requested source-anchor artifact was published.
- R326 retried with `AssignedExecutor local` and `Engine local`. The request was still queued behind a protected active lane and no requested source-anchor artifact was published.
- Direct local-engine diagnostic R327 proved the source-anchor extraction lane itself can publish the requested smaller source anchor when supplied with a real prompt artifact.
- R327 produced a 41-line source anchor from `scripts/engines/LocalExecutionEngine.ps1` around `validation_command_must_be_executable`, with `exact_text_length=2805` and `no_code_changes=true`.
- The direct local-engine diagnostic then failed interface validation after writing the artifact. That is a wrapper/contract issue, not a source-anchor extraction failure.

Validation:

- R325/R326 artifact readback: `TOD_PROVIDER_SMALL_ANCHOR_CONTRACT_SOURCE_R325.latest.json` and `TOD_PROVIDER_SMALL_ANCHOR_CONTRACT_SOURCE_R326.latest.json` were missing.
- R327 artifact readback: `artifact_type=tod_source_anchor_observation`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`, `line_count=41`, `exact_text_nonempty=true`, `no_code_changes=true`.
- R327 blocker artifact records `source_anchor_lane_direct_artifact_write=passed` and `direct_engine_wrapper_validation=failed`.

Capability finding:

The next blocker is not provider quality yet. TOD first has to prove read-only training tasks can move from chat/request intake into local execution while a protected active lane exists, or it must publish a precise active-lane authority blocker. Without that proof, another provider retry would test the wrong thing.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No provider candidate accepted and no source mutation. |
| Runtime | Partial diagnostic only. Source-anchor extraction works directly, but the TOD chat/active-lane path did not execute it. |
| Governance | Yes. The missing R325/R326 artifacts were not counted as progress. |
| Evidence | Yes. R327 records the successful direct source-anchor extraction and the wrapper/active-lane blockers. |
| Model Utilization | Not tested in this rung. Provider invocation should wait until read-only execution promotion is proven. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New measurable blocker: read-only source-anchor tasks can be accepted by chat intake without producing the requested artifact when active-lane protection is in force.

Next smallest training rung:

`TOD-READONLY-ACTIVE-LANE-PROMOTION-DIAGNOSTIC-V1`

Mission:

Prove whether a read-only source-anchor task can be promoted or safely executed while an active lane is protected. TOD must either publish the requested artifact through its owned execution path or publish a precise blocker naming the active-lane authority, queue state, selected task, and smallest allowed continuation. Do not continue to provider invocation until this execution-path proof is complete.

## 2026-07-25 R328-R336 Small Anchor Provider Supervision Loop

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_READONLY_ACTIVE_LANE_PROMOTION_DIAGNOSTIC_R328.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_CONTEXT_PACKAGE_R329.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_MODEL_JUDGMENT_R330.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_PROVIDER_REQUEST_R331.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_PROVIDER_CANDIDATE_R332.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_PROVIDER_VERDICT_R333.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_PROVIDER_REPLAN_R334.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_PROVIDER_CANDIDATE_RETRY_R335.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_SMALL_ANCHOR_PROVIDER_VERDICT_RETRY_R336.latest.json`

Observed result:

- R328 proved the local executor can run read-only work, but it selected the generic read-only context proof producer instead of the active-lane promotion diagnostic requested by the prompt.
- R329 successfully produced a real `tod_engineering_context_package` from the R327 source-anchor artifact. It preserved the path roles: input artifact, output artifact, and source file are distinct, and only the source file is a valid bounded edit target.
- R330 produced a `tod_model_utilization_engineering_judgment` that classified the context as `provider_prompt_ready` and `candidate_request_ready=true`.
- R331 produced a provider request with `provider_request_ready=true`, source file `scripts/engines/LocalExecutionEngine.ps1`, and the R327 source-anchor artifact as required context.
- The first R332 invocation did not call the provider because no usable provider inventory was supplied. After adding the existing R304 provider inventory as supporting evidence, R332 called the local provider at `http://127.0.0.1:8008/v1/chat/completions`.
- R332 returned a provider candidate with the correct target file and source-grounded old text, but `new_text` was blank and the validation command remained generic.
- R333 correctly rejected the candidate with `verdict_reason_code=rejected_blank_new_text` and also flagged `validation_command_specific=false`.
- R334 produced a replan artifact that preserved the rejection reason and required nonblank behavior-changing `new_text`, exact source old text, and a concrete executable validation command.
- R335 invoked the provider again with the replan instruction applied. The provider still returned blank `new_text`.
- R336 correctly rejected the retry for the same reason before any source mutation.

Validation:

- Local provider reachable: `http://127.0.0.1:8008/v1/models` returned `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- R332 and R335 both recorded `provider_called=true` and `candidate_response_available=true`.
- R333 and R336 both recorded `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, `new_text_length=0`, and `no_source_code_modified=true`.
- No source files were edited by the provider candidate flow.

Capability finding:

TOD now has a scaffolded model-supervision loop for this class:

1. Build a small source-anchor context package.
2. Judge provider readiness.
3. Create a provider request.
4. Invoke the local provider.
5. Reject blank or generic candidates before source mutation.
6. Replan after rejection.
7. Retry and reject again when the provider repeats the same failure.

The remaining blocker is model/output-materialization quality on this target, not safety. TOD correctly prevented a bad provider output from becoming source code.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No accepted behavior-changing candidate and no source mutation. |
| Runtime | Partial. Direct local-engine artifact producers worked; chat/active-lane promotion remains unresolved. |
| Governance | Yes. Bad provider candidates were rejected twice before source mutation. |
| Evidence | Yes. The artifacts preserve context, judgment, request, candidate, verdict, replan, retry, and second verdict lineage. |
| Model Utilization | Scaffolded pass. TOD used the local provider and supervised its output, but the provider did not produce a usable patch. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New measurable progress: TOD can supervise a local provider attempt and reject unsafe or empty candidates with evidence.

Next smallest training rung:

`TOD-PROVIDER-ANCHOR-SELECTION-QUALITY-V1`

Mission:

Select a better source anchor that contains an obvious, bounded behavior change opportunity before invoking the provider. The anchor must be smaller than the original broad source chunk, include enough surrounding logic for a safe patch, and name a concrete executable validation command before provider invocation. Do not ask the provider to invent a behavior change from a weak anchor.

## 2026-07-25 R337 Anchor-Selection Blocked By Protected Active Lane

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_ANCHOR_SELECTION_QUALITY_BLOCKER_R337.latest.json`

Observed result:

- R337 was sent through the normal TOD chat execution lane as a read-only source-anchor task.
- TOD materialization correctly classified it as a canonical read-only task that does not require bounded edit materialization.
- Intake arbitration still queued the request because `TOD_ACTIVE_EXECUTION_LANE.latest.json` is protected and active.
- The requested artifact `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_ANCHOR_SELECTION_QUALITY_SOURCE_R337.latest.json` was not produced.

Validation:

- `Test-Path runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_ANCHOR_SELECTION_QUALITY_SOURCE_R337.latest.json` returned false.
- Current active lane remains `TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1` / `TOD-AUTHORITY-EVIDENCE-SUITABILITY-SELECTION-V1`, generated `2026-07-23T13:29:36.5385407Z`, status `active`.

Capability finding:

The next blocker is not anchor-selection reasoning yet. TOD must first resolve active-lane ownership: a read-only task can be valid and still fail to execute if the protected active lane never reaches terminal, paused, or sidecar-permitted state.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No fresh source anchor and no behavior-changing candidate. |
| Runtime | Blocked. Active-lane protection prevented the fresh read-only task from producing its requested artifact. |
| Governance | Yes. Missing requested artifact was rejected as progress. |
| Evidence | Yes. R337 blocker names the queue decision, active lane, missing artifact, and retry condition. |
| Model Utilization | No new model work. Provider invocation is intentionally blocked until fresh source-anchor evidence exists. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New measurable debt: active-lane protection blocks read-only sidecar training tasks even when materialization classifies them as valid.

Next smallest training rung:

`TOD-ACTIVE-LANE-READONLY-SIDECAR-OR-PAUSE-V1`

Mission:

TOD must resolve the stale protected active lane before further provider training. It must either complete/pause the current active lane with evidence or demonstrate a safe read-only sidecar execution policy that allows artifact-only training tasks without mutating the active implementation lane. After that, replay R337 and require requested artifact readback before continuing provider invocation.

## 2026-07-25 R338-R339 Active-Lane Diagnostic Contract Lesson

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_ACTIVE_LANE_READONLY_SIDECAR_OR_PAUSE_R338.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_ACTIVE_LANE_READONLY_SIDECAR_OR_PAUSE_BLOCKER_R338.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_ACTIVE_LANE_READONLY_SIDECAR_OR_PAUSE_COMPARISON_R339.latest.json`
- `runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json`

Observed result:

- R338 was sent as a diagnostic/read-only task with a scope path and required output artifact, but it did not expose `Input Artifact:`, `Output Artifact:`, or `Required Artifact Type:` directives.
- TOD produced `tod_read_only_task_context_proof`, which only proved the read-only mode was preserved.
- The R338 artifact inspected the prompt file and did not inspect `runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json`.
- Codex classified the result as blocked because it did not answer the requested active-lane question.
- R339 replayed the smallest diagnostic with explicit evidence-lane directives:
  - `Task Category: artifact_write`
  - `Required Artifact Type: tod_read_only_evidence_comparison`
  - `Input Artifact: runtime_remote_training/engineering_corpus/TOD_ACTIVE_LANE_READONLY_SIDECAR_OR_PAUSE_BLOCKER_R338.latest.json`
  - `Left Artifact: runtime_remote_training/engineering_corpus/TOD_ACTIVE_LANE_READONLY_SIDECAR_OR_PAUSE_R338.latest.json`
  - `Right Artifact: runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json`
  - `Output Artifact: runtime_remote_training/engineering_corpus/TOD_ACTIVE_LANE_READONLY_SIDECAR_OR_PAUSE_COMPARISON_R339.latest.json`
- R339 produced the required `tod_read_only_evidence_comparison` artifact with `validation.no_code_changes=true`.

Validation:

- R338 requested artifact existed, but `artifact_type=tod_read_only_task_context_proof`.
- R338 `inspected_files` only contained `E:/TOD/tod/out/prompts/R338-20260725.md`.
- R338 blocker recorded `active_lane_was_not_inspected_by_artifact=true` and `requested_decision_missing=true`.
- R339 requested artifact exists and records:
  - `artifact_type=tod_read_only_evidence_comparison`
  - `status=completed`
  - `input_read=true`
  - `left_artifact_read=true`
  - `right_artifact_read=true`
  - `no_code_changes=true`

Capability finding:

TOD has not yet learned the independent diagnostic-materialization rule. The system can execute the correct evidence lane, but only when Codex supplies exact artifact-contract directives. The missing TOD skill is recognizing that a requested evidence-specific diagnostic cannot be expressed as loose scope text; it must be materialized as a named input/output/artifact-type contract before execution.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No source inspection or behavior-changing patch occurred. |
| Runtime | Scaffolded pass. The evidence-comparison lane works when exact directives are supplied. |
| Governance | Yes. Generic context proof was rejected as insufficient. |
| Evidence | Yes. R338 and R339 preserve the failed shape, corrected shape, and validation readback. |
| Model Utilization | No. This was runtime/evidence routing, not provider supervision. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New training lesson: evidence-specific diagnostic requests need explicit `Input Artifact`, `Output Artifact`, and `Required Artifact Type` fields before generic read-only context proof fallback is eligible.

Next smallest training rung:

`TOD-DIAGNOSTIC-PACKET-MATERIALIZATION-INDEPENDENT-DEMO-V1`

Mission:

TOD must receive a fresh diagnostic request that contains only natural task language plus source/evidence paths, independently infer the correct evidence-lane packet shape, materialize the exact `Input Artifact`, `Output Artifact`, and `Required Artifact Type` directives, execute the artifact write, and validate readback without Codex supplying the corrected directives.

## 2026-07-25 R340 Independent Diagnostic Materialization Attempt

Fresh evidence:

- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_BLOCKER_R340.latest.json`

Observed result:

- R340 asked TOD, in natural language, to compare the R338 failed diagnostic with the R339 corrected diagnostic and publish one read-only artifact.
- Codex did not supply `Input Artifact`, `Output Artifact`, or `Required Artifact Type` directives.
- TOD did not infer the evidence-specific packet shape.
- The requested artifact `runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_INDEPENDENT_DEMO_R340.latest.json` was not produced.
- The local executor blocked with `reason_code=local_fallback_needs_target_or_scope`.
- The blocker stated that multiple artifact paths were interpreted as candidate target files and the engine would not guess which one to patch.

Validation:

- `Test-Path runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_INDEPENDENT_DEMO_R340.latest.json` returned false.
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json` recorded the blocker function as `scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionGenericBoundedTask`.
- No source files were intentionally edited.

Capability finding:

TOD still cannot independently turn natural diagnostic language into a specific artifact-write packet. The missing skill is not evidence comparison itself; R339 proved that lane works. The missing skill is role materialization: identifying which paths are evidence inputs, which path is the output artifact, and whether any path is a source edit target.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No code inspection or behavior-changing patch. |
| Runtime | No independent credit. TOD fell back to target-file guessing. |
| Governance | Yes. The missing artifact was rejected as progress. |
| Evidence | Yes. The failure was captured as a precise blocker. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New precise debt: diagnostic packet materialization from natural request is not demonstrated.

Next smallest training rung:

`TOD-PRODUCER-SELECTION-SOURCE-ANCHOR-OBSERVATION-V1`

Mission:

TOD should inspect the local executor producer-selection rules and publish a source-anchor observation explaining why R340 fell through to generic bounded target guessing instead of read-only artifact writing. This is read-only source inspection. It must name the exact source file, function, anchor, and validation evidence before any retry.

## 2026-07-25 R341 Producer-Selection Source Anchor Observation

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PRODUCER_SELECTION_SOURCE_ANCHOR_OBSERVATION_R341.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R341 asked TOD to inspect `scripts/engines/LocalExecutionEngine.ps1`.
- TOD produced `tod_source_anchor_observation`.
- The source function was correctly inferred as `Test-LocalExecutionReadOnlyAuditArtifactTask`.
- The artifact captured lines 2333-2438, including:
  - required artifact type extraction
  - artifact-write type eligibility
  - input/output path requirement
  - fallback-adjacent `Test-LocalExecutionReadOnlyTaskContextArtifactTask`
- No source code was modified.

Validation:

- Artifact exists at `runtime_remote_training/read_only_audit_artifacts/TOD_PRODUCER_SELECTION_SOURCE_ANCHOR_OBSERVATION_R341.latest.json`.
- Artifact records `artifact_type=tod_source_anchor_observation`.
- Artifact records `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- Artifact records `source_function=Test-LocalExecutionReadOnlyAuditArtifactTask`.
- Artifact records `exact_text_nonempty=true`.
- Artifact records `validation.no_code_changes=true`.
- Latest execution result records five passed checks: source read, anchor match, artifact write, schema readback, and no-code-change assertion.

Capability finding:

TOD can perform a source-anchor observation on the producer-selection surface when given the target file and anchor. This is useful but still guided. The remaining independent skill is to use this source evidence to re-materialize a natural diagnostic request into the correct artifact-write contract without Codex providing the final field labels.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Read-only inspection credit only. No behavior-changing implementation. |
| Runtime | Scaffolded pass. TOD used the correct source-anchor producer. |
| Governance | Yes. It stayed read-only and did not mutate the active lane. |
| Evidence | Yes. Exact source evidence and validation are present. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New available evidence: TOD can now point at the source rule that made R339 pass and R340 fail.

Next smallest training rung:

`TOD-DIAGNOSTIC-PACKET-MATERIALIZATION-RETRY-FROM-SOURCE-EVIDENCE-V1`

Mission:

TOD must use the R341 source-anchor observation plus the R340 failure evidence to retry diagnostic packet materialization. It should publish a non-generic diagnostic artifact or a smaller blocker that explicitly names which directive cannot be inferred. Codex may provide the evidence artifacts, but not the final corrected `Input Artifact` / `Output Artifact` / `Required Artifact Type` packet.

## 2026-07-25 R342 Retry From Source Evidence Failure

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_BLOCKER_R342.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PRODUCER_SELECTION_SOURCE_ANCHOR_OBSERVATION_R341.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R342 was asked to use R340 blocker evidence and R341 source-anchor evidence to retry diagnostic materialization.
- The requested diagnostic output artifact was not produced.
- The local executor wrote a generic `tod_read_only_task_context_proof`.
- Worse, it wrote that generic proof into the R341 source-anchor artifact path, overwriting prior evidence.
- The overwritten R341 file now records task `R342-20260725`, not the original source-anchor observation.

Validation:

- The expected R342 diagnostic artifact was absent.
- The R341 artifact path no longer contained `artifact_type=tod_source_anchor_observation`.
- The replacement artifact only inspected the R342 prompt file.
- No source code was intentionally changed.

Capability finding:

TOD has a path-role classification gap. It can be given evidence paths, source paths, package paths, and output paths, but it does not yet reliably distinguish which path is safe to write. Evidence artifacts must be treated as immutable inputs unless explicitly named as the output artifact.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. |
| Runtime | No independent credit. The executor selected the generic context proof lane and overwrote evidence. |
| Governance | Yes. The overwritten evidence was detected and rejected instead of counted as success. |
| Evidence | Partial. The failure itself is useful evidence; the prior R341 evidence must be restored under a new path. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- New precise debt: TOD must classify path roles before diagnostic writes.

## 2026-07-25 R343 Path-Role Classification Before Diagnostic Write

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PATH_ROLE_CLASSIFICATION_BEFORE_DIAGNOSTIC_WRITE_R343.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R343 asked TOD to classify the roles of the R342 blocker path, the R342 package path, the source file, and the output path.
- TOD produced `tod_read_only_role_classification_artifact`.
- The artifact correctly classified:
  - `Input Artifact` and `Evidence Artifact` as `input_evidence_read_only`
  - `Package Path` as `package_evidence_read_only`
  - `Source File` as `source_to_inspect_read_only`
  - `Output` / `Output Artifact` as `evidence_artifact_to_write`
  - `Target File` as a bounded edit target only when edit mode or behavior change is authorized.
- The artifact named `Get-LocalExecutionTargetFiles / Invoke-LocalExecutionGenericBoundedTask` as the suspected path-role failure area.

Validation:

- Artifact exists at `runtime_remote_training/read_only_audit_artifacts/TOD_PATH_ROLE_CLASSIFICATION_BEFORE_DIAGNOSTIC_WRITE_R343.latest.json`.
- Artifact records `artifact_type=tod_read_only_role_classification_artifact`.
- Latest execution result records passed checks for input role mapping, artifact write, required field readback, and no-code-change assertion.
- No source code was changed.

Capability finding:

TOD can now produce a role map when explicitly asked. This is a useful scaffolding rung, but it does not yet prove TOD independently uses the role map before attempting diagnostic materialization.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Read-only diagnostic credit only. |
| Runtime | Guided pass. |
| Governance | Yes. It preserved no-code-change boundaries. |
| Evidence | Yes. The role map is reusable evidence for the next attempt. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-PRODUCER-SELECTION-SOURCE-ANCHOR-RESTORE-V1`

Mission:

Restore the lost producer-selection source-anchor observation under a fresh artifact path, then retry diagnostic materialization using the R343 role map as input evidence. The next retry must not write to any input evidence path.

## 2026-07-25 R344-R345 Source Evidence Restore

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PRODUCER_SELECTION_SOURCE_ANCHOR_OBSERVATION_RESTORED_R344.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PRODUCER_SELECTION_SOURCE_SPAN_RESTORED_R345.latest.json`

Observed result:

- R344 restored a source-anchor artifact at a fresh path without overwriting R341 again.
- R344 only captured the function signature line, which was valid but too thin for learning.
- R345 repeated the restore with an end pattern and captured the full source span from `Test-LocalExecutionReadOnlyAuditArtifactTask` through the read-only context fallback boundary.
- R345 captured 63 lines, including required artifact type extraction, allowed read-only artifact types, input/output artifact path requirements, and fallback boundaries.

Validation:

- R344 artifact exists and records `artifact_type=tod_source_anchor_observation`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, and `no_code_changes=true`.
- R345 artifact exists and records `artifact_type=tod_source_anchor_observation`, `start_line=2353`, `end_line=2415`, `line_count=63`, and `no_code_changes=true`.
- R345 exact text includes `Required Artifact Type`, `Get-LocalExecutionReadOnlyAuditArtifactPaths`, `input_path`, and `output_path`.

Capability finding:

TOD can restore source evidence to a fresh path when explicitly given source file, anchor, end pattern, and output path. It can also improve thin source evidence when coached to capture a useful span. This remains guided, not independent.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Guided source-inspection credit. |
| Runtime | Guided pass. |
| Governance | Yes. The new artifacts avoided the corrupted R341 path. |
| Evidence | Yes. R345 is usable source evidence. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R346 Role-Map Retry Failure

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_BLOCKER_R346.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R346 gave TOD the R343 role map, R345 source span, R340 blocker, R342 blocker, and a single expected output path.
- Codex did not provide a final `Required Artifact Type` or corrected `Input Artifact` / `Output Artifact` packet.
- TOD did not create `runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_WITH_ROLE_MAP_R346.latest.json`.
- The generic context-proof fallback wrote into the R343 role-map path.
- R343 role-map evidence was overwritten with `artifact_type=tod_read_only_task_context_proof`.

Validation:

- `Test-Path runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_WITH_ROLE_MAP_R346.latest.json` returned false.
- Latest execution result records `commands_run=Invoke-LocalExecutionReadOnlyTaskContextArtifact`.
- Latest execution result summary says it published a context proof to the R343 path.

Capability finding:

TOD can create a path role map but cannot yet enforce it as an immutable input boundary on the next task. The context-proof writer can still treat the scoped input evidence path as a writable artifact path.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. |
| Runtime | No independent credit. |
| Governance | Yes. The evidence corruption was caught and recorded. |
| Evidence | Failure evidence only. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-IMMUTABLE-EVIDENCE-INPUT-GUARD-SOURCE-ANCHOR-V1`

Mission:

TOD must inspect the context-proof writer and identify the exact rule that allows scoped input evidence paths to become write targets. It must publish a source-anchor observation and either produce a bounded repair packet or a precise blocker naming the missing output-selection rule. No source mutation should happen before the source evidence is published.

## 2026-07-25 R347-R349 Output-Directive Repair Training

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_DIAGNOSTIC_PACKET_MATERIALIZATION_BLOCKER_R346.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_DELTA_R349.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R347 attempted to inspect `Invoke-LocalExecutionReadOnlyTaskContextArtifact`, but the source-anchor writer again wrote to the R343 evidence path instead of the requested R347 output path.
- Codex source inspection identified the likely implementation surfaces:
  - `Get-LocalExecutionSourceAnchorObservationSpec` lines 2946-3004
  - `Get-LocalExecutionReadOnlyAuditArtifactPaths` lines 2204-2335
  - `Get-LocalExecutionDirectiveValue` lines 10179+
- R348 asked TOD to produce a bounded repair packet, but TOD correctly blocked instead of guessing because multiple candidate paths were present and the local fallback could not safely select a target.
- R349 constrained the task to one input source-anchor artifact, one target file, one output artifact, and a supported `tod_source_anchor_delta_proposal` artifact type.
- R349 produced the requested delta-proposal artifact, but it was blocked with `autonomous_candidate_new_text_missing`.

Validation:

- R349 artifact exists at `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_DELTA_R349.latest.json`.
- R349 artifact records `artifact_type=tod_source_anchor_delta_proposal`.
- R349 artifact records `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R349 artifact records `candidate_new_text=""`.
- R349 blocker names `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor` as the missing capability.
- No source code was changed by these tasks.

Capability finding:

TOD can now package a precise source-anchor delta proposal and refuse false completion when it lacks meaningful new text. The largest remaining engineering gap is current-code new-text synthesis from a source anchor.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Partial. TOD identified the repair target but did not synthesize the code change. |
| Runtime | Guided pass for delta-proposal artifact creation. |
| Governance | Strong. TOD blocked rather than emitting fake new text. |
| Evidence | Yes. R349 is a clean blocker artifact. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

TOD must use the current source-anchor evidence and the repair intent to synthesize non-empty, meaningful, safe `candidate_new_text` without Codex writing the text. If it cannot, it must publish a blocker that explains whether the missing piece is model assistance, source-span size, directive schema, or patch-writer support.

## 2026-07-25 R350-R360 Model-Utilization Ladder

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_NEWTEXT_R350.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_CONTEXT_R352.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_MODEL_JUDGMENT_R353.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_PROVIDER_REQUEST_R354.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_PROVIDER_INVENTORY_R355.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_PROVIDER_CANDIDATE_R356.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_PROVIDER_VERDICT_R357.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_PROVIDER_REPLAN_R358.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_PROVIDER_STUB_RETRY_R359.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_STUB_VERDICT_R360.latest.json`

Observed result:

- R350 used the restored source span and target file, but blocked with `autonomous_meaningful_new_text_synthesis_missing`.
- R351 attempted a richer synthesis retry but did not publish the requested artifact.
- R352 successfully built a provider-ready engineering context package from the source-anchor evidence.
- R353 produced a model-utilization judgment and correctly stated that the next step needed a provider request or local-model stub before source mutation.
- R354 published a provider request with path-role warnings, candidate schema, and rejection rules.
- R355 inventoried the local engineering provider and found the configured endpoint/model reachable with a usable provider hook.
- R356 produced a provider-candidate invocation artifact, but `provider_called=false` and the candidate fields were blank.
- R357 rejected the blank provider candidate before source mutation.
- R358 replanned from the rejection and named a stub retry as the next smallest rung.
- R359 produced a stub retry artifact, but the candidate fields were still blank.
- R360 rejected the blank stub retry before source mutation.

Validation:

- R352-R360 artifacts exist and were read back.
- R352-R360 latest execution results report artifact-write-only changes.
- R357 and R360 both record `accepted_for_source_mutation=false` and `rejected_before_source_mutation=true`.
- No source code was changed by this ladder.

Capability finding:

TOD can now run the supervision ladder around model utilization: context package, judgment, request, provider inventory, candidate artifact, verdict, and replan. TOD still cannot independently produce a valid behavior-changing source patch candidate from the provider/stub lane. The provider endpoint is reachable, but the local execution candidate invocation path did not actually call it in R356.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No implementation credit. TOD did not synthesize a source patch. |
| Runtime | Guided pass for read-only model-utilization artifact lanes. |
| Governance | Strong. TOD rejected blank candidates before mutation. |
| Evidence | Yes. The ladder is well evidenced through R360. |
| Model Utilization | Scaffolded/guided progress. Provider inventory and request are good; candidate invocation remains incomplete. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-LOCAL-ENGINEERING-PROVIDER-CALL-MATERIALIZATION-V1`

Mission:

TOD must inspect the local execution provider-candidate invocation path and determine why R356 recorded `usable_provider_hook=true` but `provider_called=false`. It must publish a source-anchor observation naming the exact function or branch responsible, then either produce a bounded repair packet or a precise blocker. No source mutation should happen until the source evidence and repair packet are both present.

## 2026-07-25 R361 Provider-Call Source-Anchor Attempt

Fresh evidence:

- `tod/out/prompts/R361-20260725.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CALL_MATERIALIZATION_SOURCE_ANCHOR_R361.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R361 was packaged correctly as a provider-call source-anchor observation task.
- The chat wrapper blocked with `codex_wrapper_only_no_execution`.
- A direct `run-task` attempt selected unrelated `TSK-0102`, proving the task-store selector can still substitute backlog work for the explicit task id.
- Direct local-engine execution with `task_category=artifact_write` blocked with `local_fallback_needs_target_or_scope`.
- Direct local-engine execution with `task_category=inspection` published a read-only task context proof, not a source-anchor observation.
- Inspection of `scripts/engines/LocalExecutionEngine.ps1` shows `tod_source_anchor_observation` is not present in the `Test-LocalExecutionReadOnlyAuditArtifactTask` read-only artifact-write allowlist.

Validation:

- Requested source-anchor artifact path exists, but `artifact_type=tod_read_only_task_context_proof`.
- The artifact inspected the prompt package, not the target source span.
- No source code was changed.

Capability finding:

TOD preserved read-only safety and avoided false source mutation, but it did not publish the requested source-anchor observation. The local executor has a lane-selection gap: `tod_source_anchor_observation` can be requested in prompt text, but this artifact type is not accepted by the read-only artifact-write allowlist used for the model-utilization ladder.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. Source branch evidence was not captured. |
| Runtime | Failure evidence only. Explicit task execution still drifted to `TSK-0102` through `run-task`. |
| Governance | Yes. The failed lane selection was detected and not counted as progress. |
| Evidence | Partial. R361 proves the allowlist/lane mismatch. |
| Model Utilization | No additional credit. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-SOURCE-ANCHOR-ARTIFACT-LANE-ALLOWLIST-V1`

Mission:

TOD must inspect the read-only artifact-write classifier and source-anchor observation writer, then produce a bounded repair packet or a precise blocker explaining how `tod_source_anchor_observation` should enter the intended source-anchor artifact lane without falling back to generic context proof or bounded edit materialization. No source mutation should happen before the packet is complete.

## 2026-07-25 R362-R363 Source-Anchor Lane Allowlist Attempts

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_ARTIFACT_LANE_ALLOWLIST_R362.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SOURCE_ANCHOR_ARTIFACT_LANE_ALLOWLIST_R363.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R362 used the R361 context-proof artifact as input and correctly blocked with `source_anchor_input_invalid`.
- R363 retried with valid R345 source-anchor evidence and produced the requested `tod_source_anchor_delta_proposal`.
- R363 still blocked with `autonomous_candidate_new_text_missing`.
- R363 correctly preserved `target_file=scripts/engines/LocalExecutionEngine.ps1` and did not mutate source.

Additional source inspection:

- The provider-candidate invocation branch is around `scripts/engines/LocalExecutionEngine.ps1` lines 7468-7679.
- That branch first selects an artifact path if the path string matches `SOURCE_ANCHOR.*\.json$`.
- The R354 provider request lists `TOD_SOURCE_ANCHOR_OUTPUT_DIRECTIVE_CONTEXT_R352.latest.json` before the real R345 source-anchor artifact.
- R352 has `SOURCE_ANCHOR` in its filename but `artifact_type=tod_engineering_context_package` and no `exact_text`.
- Because the path-name heuristic selects R352 first, `sourceAnchorText` remains blank, `invocationReady=false`, and R356 records `provider_called=false` even though R355 found the provider endpoint and hook usable.

Capability finding:

TOD has now isolated a real provider-invocation root cause: artifact role selection is path-name based before it is type/evidence based. The next repair should prefer artifacts whose JSON has `artifact_type=tod_source_anchor_observation` or non-empty `exact_text`, and should not treat `SOURCE_ANCHOR` in a filename as sufficient proof that the artifact is source-anchor evidence.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | Diagnostic credit only. TOD still did not synthesize a code patch. |
| Runtime | Guided evidence-routing pass. |
| Governance | Strong. Invalid source-anchor input was rejected. |
| Evidence | Yes. R362/R363 plus source inspection identify the selection fault. |
| Model Utilization | No additional credit. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-PROVIDER-SOURCE-ANCHOR-EVIDENCE-SELECTION-V1`

Mission:

TOD must produce a bounded repair packet for provider-candidate invocation source-anchor selection. The packet should change selection from filename-first matching to evidence-first matching: inspect artifact JSON, prefer `tod_source_anchor_observation` or non-empty `exact_text`, and only fall back to filename heuristics after artifact-type validation fails. The packet must include exact old text, candidate new text, a focused validation command, closure evidence, and prevention lesson before any source mutation.

## 2026-07-25 R364 Provider Evidence-Selection Context Attempt

Fresh evidence:

- `tod/out/prompts/R364-20260725.md`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R364 attempted to create a provider-ready context package whose filename avoided `SOURCE_ANCHOR`.
- The chat execution path blocked with `local_fallback_needs_target_or_scope`.
- Direct local-engine retry also blocked with `local_fallback_needs_target_or_scope`.
- No R364 context artifact was produced.

Capability finding:

The model-utilization context-package lane is still sensitive to path-role ambiguity. When the task mentions input evidence, output artifact, and source target in the same prompt, TOD/local execution may fall into generic bounded fallback rather than the supported read-only artifact writer.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. |
| Runtime | Failure evidence only. |
| Governance | Yes. The task blocked instead of guessing. |
| Evidence | Partial blocker evidence. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R365 Recovery-Shape Retirement Eligibility Proof

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_EXECUTABLE_RECOVERY_SHAPE_RETIREMENT_PROOF_R365.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R365 inspected the Recovery That Produces Executable Retry Shape family:
  - APP-TOD-011
  - APP-TOD-023
  - APP-TOD-004
  - APP-TOD-020
- TOD published a read-only retirement eligibility proof.
- TOD found zero entries eligible for retirement.
- The projected borrowed-capability ratio remains 78.4%.

Validation:

- R365 artifact exists.
- R365 reviewed four requested entries.
- R365 wrote no source code.
- R365 latest execution result reports artifact-write-only evidence and passed readback/no-code-change checks.

Capability finding:

TOD can now produce an honest retirement eligibility proof for a debt family and refuse to reduce borrowed-capability ratio when proficiency/evidence quality is insufficient. That is governance progress, not engineering debt retirement.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No implementation credit. |
| Runtime | Read-only retirement proof pass. |
| Governance | Strong. No inflated retirements. |
| Evidence | Yes. R365 is usable scorecard evidence. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-RECOVERY-SHAPE-FRESH-INDEPENDENT-DEMO-V1`

Mission:

TOD must pick one recovery-shape entry from R365, run a fresh independent demonstration against a harmless target, publish evidence with validation and prevention lesson, and then rerun eligibility proof. The first target should be the entry with the smallest missing proof gap, not the most interesting one.

## 2026-07-25 R366-R368 Recovery-Shape Selection Contract Proof

Fresh evidence:

- `tod/out/prompts/R366-20260725.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_RECOVERY_SHAPE_FRESH_DEMO_SELECTION_R366.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_RECOVERY_SHAPE_CONTRACT_MISMATCH_PROOF_R368.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R366 was asked to choose exactly one recovery-shape entry for a fresh independent demo.
- TOD produced `tod_readonly_retirement_eligibility_proof` again instead of the requested selection fields.
- R367 correctly exposed that a new unsupported artifact shape falls through to generic target-file fallback when the executor cannot recognize it.
- R368 used a supported evidence-comparison lane to prove the contract mismatch without modifying source code.

Validation:

- R368 artifact exists.
- R368 status is `completed`.
- R368 first material difference is `Task Mode`.
- R368 validation reports both compared artifacts were read and `no_code_changes=true`.

Capability finding:

TOD can now prove a requested/delivered evidence-contract mismatch through a supported read-only artifact lane. TOD still cannot independently materialize an unsupported selection artifact shape or choose the next recovery-shape demo target in the requested custom schema.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No implementation credit. |
| Runtime | Evidence-contract comparison pass. |
| Governance | Strong. Wrong artifact shape was not accepted as debt retirement. |
| Evidence | Yes. R368 is usable proof for the next training rung. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-RECOVERY-SHAPE-CONTRACT-MISMATCH-EPISODE-V1`

Mission:

Convert the R366/R368 mismatch into a durable engineering episode card, then run Examiner quality review on that episode. The episode should classify the failure as runtime support debt, not independent engineering progress.

## 2026-07-25 R369-R370 Recovery-Shape Episode Quality Gate

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_RECOVERY_SHAPE_CONTRACT_MISMATCH_EPISODE_R369.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_RECOVERY_SHAPE_CONTRACT_MISMATCH_EPISODE_EXAMINER_R370.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`

Observed result:

- R369 converted the R368 contract mismatch proof into an engineering episode card.
- The episode correctly preserved the source artifact and no-code-change boundary, but its `borrowed_vs_independent` value was still muddy: `independent_or_claimed_independent`.
- R370 Examiner reviewed the episode and prevented it from reducing borrowed-capability debt.

Validation:

- R370 status is `completed`.
- R370 `training_usefulness` is `accept_runtime_support_only`.
- R370 `engineering_credit_allowed=false`.
- R370 `runtime_support_credit_allowed=true`.
- R370 `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can now create an episode from a runtime-support proof, and Examiner can prevent runtime plumbing from masquerading as independent engineering progress. This is useful organizational memory, but it is not engineering independence.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. Examiner explicitly denied engineering credit. |
| Runtime | Yes. Runtime-support memory accepted. |
| Governance | Strong. Quality gate rejected inflated independence. |
| Evidence | Yes. R369/R370 are usable corpus evidence. |
| Model Utilization | No. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-FRESH-ENGINEERING-EPISODE-SELECTION-V1`

Mission:

Select a fresh engineering episode where TOD inspects source code, diagnoses behavior, proposes a bounded change, validates it, and publishes evidence. Avoid routing, selector, packet, and artifact-lane plumbing unless they are only supporting evidence. The target must be an engineering task, not another proof that the runtime can classify its own paperwork.

## 2026-07-25 R371-R375B Fresh Engineering Episode Selection And Provider-Path Repair

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_FRESH_ENGINEERING_EPISODE_SELECTION_INDEX_R372.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_INVOCATION_SOURCE_ANCHOR_R374.latest.json`
- Failed task attempts: `R371-20260725`, `R373-20260725`, `R375-20260725`, `R375B-20260725`

Observed result:

- `R371-20260725` failed before artifact publication because the task shape exposed multiple candidate paths and the local executor would not guess the target.
- `R372-20260725` passed after the task was reshaped as an explicit `artifact_write` with `Required Artifact Type: tod_engineering_corpus_foundation_index`.
- R372 separated evidence/model-utilization support candidates from true engineering candidates and named the next true engineering bottleneck: `TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`.
- `R373-20260725` attempted to create a provider request directly from raw source-anchor/delta/newtext artifacts. It failed because the provider-request lane expects a `tod_engineering_context_package` plus a ready `tod_model_utilization_engineering_judgment`, not raw source-anchor inputs.
- Direct readiness replay showed the R354/R355 provider path was blocked because provider invocation selected a context package without `exact_text` before reaching the real source-anchor evidence. The concrete symptom was `provider_called=false` and `old_text` length `0`.
- `R374-20260725` passed and created a repaired source-anchor artifact with `artifact_type=tod_source_anchor_observation`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`, nonempty `exact_text`, and no source-code changes.
- `R375-20260725` disappeared between `add-task` and `package-task`, proving the recurring task-state durability blocker is still present under live sync pressure.
- `R375B-20260725` preserved the task long enough to package, but failed before context publication because the context-package task included source-anchor `exact_text` and the local executor fell into generic multi-target handling instead of the read-only context package writer.

Current blocker:

`model_utilization_context_shape_blocked`

TOD can now:

- classify the fresh episode track,
- preserve a source anchor through a corrected source-anchor artifact,
- identify why the provider invocation did not call the local model,
- avoid claiming engineering credit from support artifacts.

TOD still cannot yet:

- independently transform source-anchor evidence into a provider-ready context package when `exact_text` appears in the source input,
- independently synthesize meaningful `new_text`,
- retire the borrowed source-anchor patch-authoring capability.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source patch or safe `new_text` was produced. |
| Runtime | Yes. R374 repaired the evidence shape enough to expose the next lane-admission blocker. |
| Governance | Yes. TOD did not count failed provider requests, blank `new_text`, or wrapper-only output as progress. |
| Evidence | Yes. R372 and R374 are durable proof artifacts; R373/R375B are precise blocker evidence. |
| Model Utilization | Partial. Provider assets and endpoint are reachable, but TOD has not yet completed provider invocation and verdict on this episode. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Model-utilization training must distinguish four path roles before execution:

- source file: the only possible future bounded edit target;
- source-anchor artifact: read-only input containing exact source text;
- context/judgment artifacts: provider-preparation inputs;
- output artifact: evidence to write.

If those roles are collapsed, TOD either selects a context artifact as old text, loses `exact_text`, or falls into generic bounded-task target ambiguity.

Next smallest training rung:

`TOD-MODEL-UTILIZATION-CONTEXT-SHAPE-ADMISSION-V1`

Mission:

TOD must publish a context-package or equivalent provider-ready evidence object from a source-anchor artifact without source mutation and without falling into generic multi-target handling. The pass condition is not provider output yet. The pass condition is a provider-ready context object that preserves the repaired R374 source anchor and can be consumed by the existing judgment/provider-request lanes.

## 2026-07-25 R376-R385 Provider Invocation, Rejection, And Episode Quality Gate

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_JUDGMENT_R376.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_PROVIDER_REQUEST_R377B.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_PROVIDER_INVENTORY_R378.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_CANDIDATE_R379.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_VERDICT_R380.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_REPLAN_R381.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_CANDIDATE_R382.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_VERDICT_R383.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_REJECTION_EPISODE_R384.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_INVOCATION_REJECTION_EXAMINER_R385.latest.json`

Observed result:

- R376 produced a provider-ready model-utilization judgment from the repaired context.
- R377 failed when the task disappeared between readback and package, preserving the live task-state durability blocker.
- R377B used a fast-package recovery and produced a provider request without source mutation.
- R378 proved the local provider assets and endpoint were reachable: `tools/llama.cpp/llama-server.exe`, `models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf`, and `http://127.0.0.1:8008/v1/models`.
- R379 called the local model and received a candidate, but the candidate was not usable.
- R380 rejected the first candidate before source mutation because `old_text` was not a byte-exact substring of the current source and the validation command was generic.
- R381 replanned the retry with stricter instructions: exact current old text, no marker/comment/no-op change, and concrete validation.
- R382 called the provider again, but the retry still returned non-exact `old_text`, bogus replacement content, and a generic validation command.
- R383 rejected the retry before source mutation for the same grounded reasons.
- R384 preserved the failed provider-candidate loop as a durable engineering episode card.
- R385 Examiner accepted the episode as runtime/model-utilization support only and explicitly denied engineering credit.

Validation:

- R385 status is `completed`.
- R385 `training_usefulness=accept_runtime_support_only`.
- R385 `engineering_credit_allowed=false`.
- R385 `runtime_support_credit_allowed=true`.
- R385 `borrowed_capability_ratio_effect=no_reduction`.
- R385 validation confirms input read, required fields present, and no code changes.

Capability finding:

TOD can now drive a real local-provider loop far enough to:

- build provider context,
- produce a model-utilization judgment,
- publish a provider request,
- verify provider availability,
- invoke the provider,
- reject bad candidates before mutation,
- replan a retry,
- preserve the failure as an episode,
- and submit that episode to Examiner.

TOD still cannot yet get the local provider to produce a safe, byte-exact, validation-ready bounded edit candidate. The model saw the source anchor, but stripped or altered the exact old text and returned generic validation. That is a model-utilization grounding problem, not engineering implementation proof.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source patch was accepted, applied, or validated. |
| Runtime | Yes. The provider loop reached real model invocation and safe rejection. |
| Governance | Strong. TOD rejected two weak candidates before source mutation and Examiner blocked false independence credit. |
| Evidence | Yes. The full request, inventory, candidate, verdict, replan, episode, and examiner chain is durable. |
| Model Utilization | Partial. TOD supervised provider output and rejection, but candidate quality remains below the bounded-edit gate. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Provider output is not engineering progress until it passes exact source grounding and executable validation checks. A candidate must supply `old_text` that is a contiguous byte-exact substring of the target source and a concrete validation command. If either fails, TOD must reject before mutation and replan instead of asking Codex to patch the source.

Next smallest training rung:

`TOD-LOCAL-PROVIDER-CANDIDATE-EXACT-OLDTEXT-GROUNDING-V1`

Mission:

TOD must run a provider-candidate retry where the model is constrained to either return `old_text` copied exactly from the source anchor or declare itself unable to patch. The acceptance gate is a candidate whose `old_text` is verified as a current-source substring and whose validation command is executable and specific. Source mutation remains forbidden until that gate passes.

## 2026-07-25 R386-R394 Exact Old Text Grounding Retry

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_REQUEST_R386B.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_INVENTORY_R387.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_CANDIDATE_R388.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_VERDICT_R389.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_REPLAN_R390.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_CANDIDATE_R391.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_VERDICT_R392.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_REJECTION_EPISODE_R393.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_CANDIDATE_EXACT_OLDTEXT_REJECTION_EXAMINER_R394.latest.json`

Observed result:

- R386 failed before artifact creation because the task shape mixed too many candidate paths and fell into generic target ambiguity.
- R386B backed up to the canonical provider-request lane and produced a provider request artifact without source mutation.
- R387 confirmed the local provider remained reachable through the llama.cpp server and `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- R388 invoked the provider, but the candidate again used non-current `old_text` and a generic validation command.
- R389 rejected R388 before source mutation because `old_text` was not found in the current source. It also recorded that the validation command was generic.
- R390 replanned after rejection, but because the primary rejection reason was `rejected_old_text_not_found_in_current_source`, the replan did not switch to the stricter generic-validation repair branch.
- R391 invoked the provider from the R390 replan. The provider repeated the same failure: non-current `old_text`, invented replacement variables, and the generic validation placeholder.
- R392 rejected R391 before source mutation for stale/non-current `old_text` and generic validation.
- R393 preserved the R390-R392 loop as a corpus episode.
- R394 Examiner accepted the episode as runtime-support memory only and denied engineering credit.

Validation:

- R391 `provider_called=true`.
- R392 `verdict=reject`.
- R392 `accepted_for_source_mutation=false`.
- R392 `rejected_before_source_mutation=true`.
- R394 `status=completed`.
- R394 `training_usefulness=accept_runtime_support_only`.
- R394 `engineering_credit_allowed=false`.
- R394 `runtime_support_credit_allowed=true`.
- R394 `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can now execute a complete safe provider-supervision loop:

- publish a provider request,
- confirm provider availability,
- invoke the local provider,
- apply the verdict gate,
- reject unsafe candidates before source mutation,
- preserve the rejection as a corpus episode,
- and submit the episode to Examiner.

TOD still cannot yet convert source-anchor evidence into an accepted engineering implementation. The local provider repeatedly fails to copy a byte-exact current source anchor and repeatedly returns a generic validation placeholder.

The exact blocker is now narrower than before:

- the provider request/replan path treats the first rejection reason as the only repair driver,
- candidate rejection can observe multiple failed checks,
- but replan does not yet preserve multi-defect repair priorities,
- so the validation-command defect is recorded but not promoted when stale `old_text` is also present.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source patch was accepted, applied, or validated. |
| Runtime | Yes. TOD supervised the provider loop and stopped unsafe mutation. |
| Governance | Strong. TOD rejected repeated bad candidates and Examiner prevented false independence credit. |
| Evidence | Yes. Request, inventory, candidate, verdict, replan, second candidate, second verdict, episode, and Examiner evidence exist. |
| Model Utilization | Partial. TOD can invoke and judge the local model, but cannot yet elicit an acceptable bounded edit candidate. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Provider retry loops must preserve every failed gate, not just the first rejection reason. If `old_text` is stale and `validation_command` is generic, the next replan must constrain both. A single primary reason is useful for summary, but insufficient for repair planning.

Next smallest training rung:

`TOD-PROVIDER-VERDICT-MULTI-DEFECT-REPLAN-V1`

Mission:

TOD must produce a replan from a provider verdict that carries all failed policy checks into the next provider request. The retry should require both exact current `old_text` and an executable, non-placeholder validation command before another provider candidate invocation. Source mutation remains forbidden until the verdict gate accepts both fields.

## 2026-07-25 R395 Multi-Defect Replan Probe

Fresh evidence:

- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_VERDICT_MULTIDEFECT_REPLAN_R395.latest.json`

Observed result:

- R395 consumed the R392 verdict, R386B provider request, and R391 candidate invocation.
- R395 produced a `tod_engineering_provider_candidate_replan` artifact without modifying source code.
- The artifact correctly preserved the primary rejection reason: `rejected_old_text_not_found_in_current_source`.
- The artifact still emitted the generic placeholder validation command: `PowerShell parse or focused regression covering the changed source behavior`.
- The artifact's checklist says the next candidate must include a concrete executable validation command, but the replan's top-level `validation_command` does not enforce that constraint.

Validation:

- `artifact_type=tod_engineering_provider_candidate_replan`.
- `provider_request_ready_for_retry=true`.
- `no_source_code_modified=true`.
- `candidate_invocation_read=true`.
- `required_fields_present=true`.
- `counts_as_engineering_implementation_credit=false`.

Capability finding:

R395 proves the current blocker precisely: the replan lane carries the first rejection reason forward, but it does not promote every failed policy check into the next executable retry contract. R392 observed both stale `old_text` and a generic validation command. R395 repaired neither at the contract level; it only summarized the need in acceptance-check prose.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No behavior-changing source patch was accepted, applied, or validated. |
| Runtime | Yes. TOD produced a safe replan probe and preserved the blocker. |
| Governance | Yes. The lane remained mutation-safe and did not inflate the retry as implementation progress. |
| Evidence | Yes. R395 is a durable proof of the multi-defect replan gap. |
| Model Utilization | No additional credit. The provider was not improved by this replan. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

A replan artifact must not rely on prose-only acceptance checks when a failed policy check can be converted into an executable retry field. If a candidate verdict records `validation_command_specific=false`, the next replan must replace any generic validation placeholder with a concrete validation requirement before another provider invocation.

Next smallest training rung:

`TOD-PROVIDER-VERDICT-MULTI-DEFECT-SOURCE-ANCHOR-V1`

Mission:

TOD must publish a source-anchor observation of the replan code path that chooses the primary rejection reason and builds the retry validation command. The observation must identify the exact source span where multi-defect verdict evidence is collapsed into a single replan driver. Source mutation remains forbidden until TOD uses that anchor to synthesize a bounded packet.

## 2026-07-25 R396-R399 Multi-Defect Source Anchor Recovery

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_MULTIDEFECT_SOURCE_ANCHOR_R396.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_MULTIDEFECT_SOURCE_ANCHOR_R399.latest.json`

Observed result:

- R396 was submitted as a read-only source-anchor task but used the broad `read_only_assessment` task type. TOD wrote `tod_read_only_task_context_proof` instead of the requested `tod_source_anchor_observation`.
- R397 corrected the task category to `source_anchor_observation`, but no source-anchor artifact was produced.
- R398 used the known-good source-anchor directive shape. TOD still blocked because the anchor pattern was too long and was not found as a contiguous current-source string.
- R399 backed up to a shorter unique current-source anchor: `Retry the same target source file and exact current old_text`.
- R399 passed and published `tod_source_anchor_observation` from `scripts/engines/LocalExecutionEngine.ps1` lines 7932-7947.

Validation:

- R399 `artifact_type=tod_source_anchor_observation`.
- R399 `matched=true`.
- R399 `source_read=true`.
- R399 `anchor_found=true`.
- R399 `exact_text_nonempty=true`.
- R399 `no_code_changes=true`.
- R399 terminal state `completed`.
- R399 tests: source file read, anchor pattern match, source anchor artifact write, schema readback, no-code-change assertion.

Capability finding:

TOD successfully recovered by backing up one rung after two selector/anchor failures. The recovery path matters more than the final artifact alone: TOD learned that task mode and anchor granularity both affect evidence-lane selection.

The extracted source proves the current replan behavior:

- `validationCommand` is copied from the provider request or defaults to the generic placeholder.
- the stricter concrete-validation retry instruction is only selected when `priorReasonCode` equals `rejected_generic_validation_command`.
- when the primary reason is stale `old_text`, a simultaneous generic-validation failure remains checklist prose rather than executable retry state.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. This was source evidence only. |
| Runtime | Yes. TOD recovered from lane/anchor mismatch and published the correct artifact. |
| Governance | Yes. TOD kept source mutation forbidden. |
| Evidence | Yes. R399 supplies exact source text for the next packet-synthesis rung. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Read-only evidence tasks must choose the most specific artifact lane, not merely any read-only lane. Source-anchor tasks also need a short, unique current-source anchor; long lines containing quoting and formatting can fail even when the intended source surface exists.

Next smallest training rung:

`TOD-PROVIDER-VERDICT-MULTI-DEFECT-PACKET-SYNTHESIS-V1`

Mission:

Using R399 as the source anchor, TOD must produce a bounded repair packet artifact only. The packet should update the provider-candidate replan path so all failed verdict policy checks are promoted into the next retry contract. If TOD cannot synthesize safe same-purpose `new_text`, it must publish a precise blocker naming the missing requirement. Source mutation remains forbidden in this rung.

## 2026-07-25 R400 Packet-Synthesis False Success

Fresh evidence:

- `tod/out/prompts/R400-20260725.md`
- `tod/data/state.json` task `R400-20260725`
- missing requested artifact: `runtime_remote_training/tod_independent_resolution_attempts/TOD_PROVIDER_VERDICT_MULTIDEFECT_PACKET_SYNTHESIS_R400.latest.json`

Observed result:

- R400 was submitted as `TaskCategory=packet_formation`.
- The prompt clearly requested a packet artifact only and explicitly forbade source edits.
- TOD materialized the request as a `replace_text` bounded edit against `scripts/engines/LocalExecutionEngine.ps1`.
- The materialized `Old Text` was a large unrelated executor mode block, not the R399 source-anchor span.
- The materialized validation command only syntax-checked `LocalExecutionEngine.ps1`.
- TOD terminal state reported `completed` with `local_executor_completed`.
- The required packet output artifact was not created.
- No source files were changed.

Validation:

- `Test-Path runtime_remote_training/tod_independent_resolution_attempts/TOD_PROVIDER_VERDICT_MULTIDEFECT_PACKET_SYNTHESIS_R400.latest.json` returned `False`.
- R400 terminal `tests_run` included `target_file_exists`, `focused_validation_exit_zero`, and `change_or_requested_state_present`, but none verified the requested packet artifact.
- R400 therefore failed the acceptance contract despite a completed executor state.

Capability finding:

TOD still treats `packet_formation` as if it were a source-edit task when a target source file is present. The materializer is over-weighting `Target File` and `Edit Mode` while under-weighting the requested `Output Artifact` and `packet artifact only` contract. This produces a dangerous false success: the executor validates the source file instead of the required packet artifact.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No bounded repair packet was produced, applied, or validated. |
| Runtime | No. The materializer selected the wrong execution shape. |
| Governance | Partial. Source remained unchanged, but TOD falsely reported completion. |
| Evidence | Yes. R400 exposes the packet-formation materialization defect. |
| Model Utilization | No. No provider/model improvement occurred. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

A packet-formation task has a different truth condition from a source-edit task. If an `Output Artifact` is required, successful completion must prove that artifact exists, has the requested artifact type, and contains either a ready bounded packet or a precise blocked result. Syntax-checking the target source file is not packet-formation validation.

Next smallest training rung:

`TOD-PACKET-FORMATION-OUTPUT-ARTIFACT-ASSERTION-V1`

Mission:

TOD must inspect the packet-formation materialization path and publish a source-anchor observation showing where `Output Artifact` and artifact-type requirements are lost or subordinated to source-edit materialization. Source mutation remains forbidden. The next pass condition is not a repair packet; it is an exact source anchor for the materializer branch that must eventually learn packet-output validation.

## 2026-07-25 R401 Packet-Formation Output-Artifact Eligibility Anchor

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_OUTPUT_ARTIFACT_ASSERTION_R401.latest.json`

Observed result:

- R401 was submitted as `source_anchor_observation`.
- TOD published the requested `tod_source_anchor_observation`.
- The source anchor was `hasSourceAnchorPacketOutput`.
- The observed source is `scripts/TOD.ps1` lines 8260-8280.
- The observed branch belongs to `Test-TaskAllowsLocalExecutionWithoutMaterialization`.

Validation:

- R401 `artifact_type=tod_source_anchor_observation`.
- R401 `matched=true`.
- R401 `source_read=true`.
- R401 `anchor_found=true`.
- R401 `exact_text_nonempty=true`.
- R401 `no_code_changes=true`.
- The artifact validation object recorded `source_edits=[]`.

Capability finding:

TOD recovered from R400 by backing up to a read-only source-anchor task and produced a precise artifact. The source confirms one half of the packet-formation defect: the runtime can return `true` for packet-formation local execution eligibility when the task text mentions a source-anchor packet directive plus input/output artifacts. That is not enough to prove packet completion. It only proves the task may proceed without ordinary bounded edit materialization.

Remaining gap:

R401 did not yet identify why R400 materialized as a `replace_text` source edit instead of the packet artifact lane. The likely earlier branch is in `Resolve-TaskBoundedEditMaterialization`, where target-file hints and explicit packet file filtering influence whether `$sourceAnchorPacketDirectiveTask` becomes true.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. This was source evidence only. |
| Runtime | Yes. TOD selected the correct source-anchor lane after a false-success packet attempt. |
| Governance | Yes. Source mutation remained forbidden. |
| Evidence | Yes. R401 anchors the local-execution eligibility half of the defect. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Eligibility and completion are different contracts. A `packet_formation` task may be eligible for local execution because it has input/output artifacts, but completion must still prove the requested output artifact exists and satisfies its schema.

Next smallest training rung:

`TOD-PACKET-FORMATION-TARGET-FILE-DISAMBIGUATION-SOURCE-ANCHOR-V1`

Mission:

TOD must publish a second source-anchor observation from `Resolve-TaskBoundedEditMaterialization` showing how `Target File`, `Input Artifact`, and `Output Artifact` are disambiguated for source-anchor packet tasks. The observation must explain why R400's explicit `Target File: scripts/engines/LocalExecutionEngine.ps1` caused ordinary source-edit materialization instead of packet-output materialization. Source mutation remains forbidden.

## 2026-07-25 R402 Packet-Formation Target-File Disambiguation Anchor

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_TARGET_FILE_DISAMBIGUATION_R402.latest.json`

Observed result:

- R402 was submitted as `source_anchor_observation`.
- TOD published `tod_source_anchor_observation`.
- The observed function is `Resolve-TaskBoundedEditMaterialization`.
- The source anchor was `sourceAnchorPacketDirectiveTask`.
- The observed source is `scripts/TOD.ps1` lines 7417-7449.

Validation:

- R402 `artifact_type=tod_source_anchor_observation`.
- R402 `matched=true`.
- R402 `source_read=true`.
- R402 `anchor_found=true`.
- R402 `exact_text_nonempty=true`.
- R402 `no_code_changes=true`.

Capability finding:

R402 explains R400's false-success path. The source-anchor packet directive branch requires all of these:

- `task_category=packet_formation`,
- source-anchor packet directive wording,
- a read-only input artifact,
- an independent-resolution output artifact,
- and zero non-evidence explicit source-anchor packet files.

R400 included `Target File: scripts/engines/LocalExecutionEngine.ps1`. That non-evidence file hint made `@($explicitSourceAnchorPacketFiles | Select-Object -Unique).Count -eq 0` false, so TOD did not enter the packet-directive materialization branch. It fell through into ordinary bounded source-edit materialization and then falsely passed source syntax validation.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. This was still source evidence only. |
| Runtime | Yes. TOD identified the exact target/source/artifact disambiguation branch. |
| Governance | Yes. Source mutation remained forbidden. |
| Evidence | Yes. R402 gives the exact source condition that explains R400. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

For source-anchor packet tasks, `Target File` can accidentally become an edit-target hint instead of a derived packet target. The packet lane should derive the source target from the input artifact, while the requested output path remains the artifact that must be produced and validated.

Next smallest training rung:

`TOD-PACKET-BODY-SYNTHESIS-LANE-DEMO-V1`

Mission:

TOD must use the existing `packet_body_synthesis` lane to produce a packet-body artifact from a source-anchor observation without editing source. The prompt must avoid `Target File:` as a top-level bounded edit directive and instead let the packet-body lane use the input artifact plus explicit synthesis fields. The pass condition is creation and schema validation of a `tod_packet_body_synthesis_artifact`, not a source syntax check.

## 2026-07-25 R403 Source-Anchor Packet Directive Lane Demo

Fresh evidence:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_SOURCE_ANCHOR_PACKET_DIRECTIVE_LANE_DEMO_R403.latest.json`

Observed result:

- R403 was submitted as `packet_formation`.
- The prompt intentionally avoided a top-level `Target File:` directive.
- TOD entered the `source_anchor_packet_directive` materialization lane.
- TOD produced the requested output artifact.
- The packet target was derived from the R402 input artifact's `source_file`.
- No source files were edited.

Validation:

- R403 `artifact_type=tod_source_anchor_packet_directive_materialization_artifact`.
- R403 `source=local_execution_source_anchor_packet_directive_lane`.
- R403 `packet_candidate_ready=true`.
- R403 `packet.target_file=scripts/TOD.ps1`.
- R403 `packet.intended_edit_mode=replace_exact_text`.
- R403 validation recorded `input_artifact_read=true`.
- R403 validation recorded `old_text_found_in_current_source=true`.
- R403 validation recorded `new_text_differs=true`.
- R403 validation recorded `packet_candidate_schema=ready`.
- R403 validation recorded `no_source_edits=true`.
- R403 materialization reason was `source_anchor_packet_directive_materialization_valid`.

Capability finding:

R403 proves the correct shape for this class of runtime support work:

1. first create source-anchor evidence,
2. then run packet formation without a top-level `Target File:` directive,
3. derive the target from the input artifact,
4. and validate the output artifact itself.

This directly contrasts with R400, where a top-level `Target File:` hint caused ordinary source-edit materialization and false completion.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. The packet is a harmless directive artifact, not a meaningful repair patch. |
| Runtime | Yes. TOD used the correct packet-directive materialization lane after R400's false success. |
| Governance | Yes. TOD proved no source edits occurred and validated the artifact contract. |
| Evidence | Yes. R403 is durable evidence of the correct packet-formation shape. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The artifact itself marks `borrowed_capability=true`; this is guided lane mastery, not independent engineering capability.

Prevention lesson:

Packet-formation tasks must validate the artifact they were asked to create. A completed executor result is only credible when the requested output exists, has the expected artifact type, and records no unintended source mutation.

Next smallest training rung:

`TOD-SOURCE-ANCHOR-PACKET-FRESH-TARGET-INDEPENDENCE-V1`

Mission:

TOD must repeat the source-anchor to packet-artifact loop on a fresh target selected from current runtime evidence, without Codex naming the source file or anchor. Success requires: TOD selects the target, publishes source-anchor evidence, produces a packet artifact, validates no source edits, and records why the target was selected. This can reduce borrowed capability only if TOD owns target selection and artifact validation without a Codex-specified source file or anchor.

## 2026-07-25 R404 Fresh Target Selection Blocker

Fresh evidence:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json`
- `tod/data/state.json` task `R404-20260725`

Observed result:

- R404 asked TOD to select a fresh target without Codex naming a source file or anchor.
- TOD accepted the task as `target_selection`.
- TOD did not create the requested output artifact `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_PACKET_FRESH_TARGET_SELECTION_R404.latest.json`.
- TOD instead wrote the generic target-selection artifact `runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json`.
- The generic artifact reported `status=no_candidate_available`.
- `candidate_count=0`.
- `inspected_files=[]`.
- `inspected_candidates=[]`.
- The only rejected candidate was the missing requested output artifact itself.

Validation:

- R404 terminal state `status=blocked`.
- R404 reason code `required_validation_failed`.
- R404 failures:
  - `target_selection_no_candidate_available`
  - `Required validation failed: different-target discovery artifact written`
- R404 recommendation: `Provide a current evidence artifact naming one viable source target before packet materialization.`

Capability finding:

TOD cannot yet perform fresh target selection from an unstructured evidence field. It can execute a selected source-anchor path when Codex names the target and anchor, and it can use the source-anchor packet lane when Codex provides the input artifact. It cannot independently discover a viable fresh target from the available training evidence without a pre-built evidence pool.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No target was selected and no packet was produced. |
| Runtime | Partial. TOD rejected stale/static fallback candidates instead of inventing progress. |
| Governance | Yes. TOD did not mutate source or claim independent resolution. |
| Evidence | Yes. R404 precisely identifies the missing evidence-pool requirement. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Fresh-target independence requires an evidence pool, not merely a generic target-selection request. TOD must inspect current artifacts, classify candidate source anchors, and select from that pool before packet materialization can be independent.

Next smallest training rung:

`TOD-FRESH-TARGET-EVIDENCE-POOL-CLASSIFIER-V1`

Mission:

TOD must build or use a current evidence-pool classifier artifact from existing read-only source-anchor artifacts. The classifier must list candidate source-anchor artifacts, reject stale or repeated targets, choose one viable fresh source-anchor artifact, and explain why it can be used for the next source-anchor packet loop. Source mutation remains forbidden.

## 2026-07-25 R405/R406 Evidence-Pool Classifier Selector Miss

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_TARGET_EVIDENCE_POOL_CLASSIFIER_R405.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_TARGET_EVIDENCE_POOL_CLASSIFIER_R406.latest.json`

Observed result:

- R405 and R406 attempted to invoke the evidence-pool source-anchor classifier.
- Both attempts produced generic `tod_read_only_task_context_proof` artifacts instead of the requested evidence-pool classifier artifact.
- No source files were edited.
- The requested classifier behavior did not run.

Capability finding:

TOD has a classifier-like runtime capability available, but it did not select that capability from the prompt shape used in R405/R406. The failure is selector/intake shaped, not source-edit shaped.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No fresh target was selected. |
| Runtime | Partial. The generic read-only lane avoided source mutation, but selected the wrong artifact lane. |
| Governance | Yes. The attempts did not claim source edits or independent engineering progress. |
| Evidence | Yes. The wrong artifact type is itself useful evidence of selector drift. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Runtime support tasks must validate the requested artifact type, not merely any read-only proof artifact. A generic context proof is not a pass when the objective requires a classifier output.

## 2026-07-25 R407 Evidence-Pool Classifier Trigger Source Anchor

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_EVIDENCE_POOL_CLASSIFIER_TRIGGER_R407.latest.json`

Observed result:

- R407 published read-only source-anchor evidence for the classifier trigger.
- The trigger is located in `scripts/engines/LocalExecutionEngine.ps1`.
- The trigger requires the combined prompt text to include:
  - `evidence pool`,
  - `source-anchor` or `source anchor`,
  - and one of `classified_artifacts`, `classification_decision`, or `classify`.
- No source files were edited.

Validation:

- R407 `artifact_type=tod_source_anchor_observation`.
- R407 `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R407 `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R407 `anchor_found=true`.
- R407 `exact_text_nonempty=true`.
- R407 `no_code_changes=true`.

Capability finding:

The specific classifier trigger exists. R405/R406 failed before or around lane selection, not because the classifier concept is absent.

## 2026-07-25 R408 Read-Only Audit Parent Detector Source Anchor

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_PARENT_DETECTOR_R408.latest.json`

Observed result:

- R408 published read-only source-anchor evidence for `Test-LocalExecutionReadOnlyAuditArtifactTask`.
- The detector runs before the generic read-only task context artifact detector.
- The detector rejects read-only audit artifact tasks when either `input_path` or `output_path` is missing.
- The detector also rejects non-allowlisted source-anchor-like text containing `exact_text`, `extracted_tokens`, `branch_excerpt`, `regex_terms_excerpt`, or `literal source token`.
- No source files were edited.

Validation:

- R408 `artifact_type=tod_source_anchor_observation`.
- R408 `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R408 `source_function=Test-LocalExecutionReadOnlyAuditArtifactTask`.
- R408 `anchor_found=true`.
- R408 `exact_text_nonempty=true`.
- R408 `no_code_changes=true`.

Capability finding:

The R405/R406 selector miss is now explained. The evidence-pool classifier lives inside the read-only audit artifact path, and the parent detector requires a single accepted input artifact plus a requested output artifact. Listing an evidence pool in ordinary prompt prose is not sufficient to enter the classifier lane.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. This is runtime path diagnosis. |
| Runtime | Yes. TOD surfaced the parent detector and its gating condition. |
| Governance | Yes. The result clarifies why generic context proof must not be counted as classifier success. |
| Evidence | Yes. R407 and R408 together explain the selector miss with source evidence. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Evidence-pool classifier training must use the runtime's accepted audit-artifact shape: provide an explicit `Input Artifact:` that the parent detector can parse and an explicit `Output:` path. If the task needs a pool of candidates, the pool must be represented by or reachable from the input artifact rather than only described in free text.

Next smallest training rung:

`TOD-EVIDENCE-POOL-CLASSIFIER-CANONICAL-INPUT-V1`

Mission:

TOD must retry the classifier lane using a canonical input artifact and requested output artifact, then prove the output artifact type is the evidence-pool classifier rather than generic read-only context proof. Source mutation remains forbidden. The pass condition is the requested classifier artifact existing with candidate classification, selected candidate, rejected candidates, and no source edits.

## 2026-07-25 R409 Evidence-Pool Classifier Canonical Input Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_EVIDENCE_POOL_CLASSIFIER_CANONICAL_INPUT_R409.latest.json`

Observed result:

- R409 retried the classifier with an explicit `Input Artifact:` and `Output:` path.
- TOD produced the requested `tod_evidence_pool_source_anchor_classifier` artifact.
- The classifier inspected five artifacts.
- It selected `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_OUTPUT_ARTIFACT_ASSERTION_R401.latest.json` as a usable source-anchor artifact.
- It classified R401, R402, and R399 as usable source-anchor observations.
- It classified R403 as context and `TOD_TARGET_SELECTION.latest.json` as review evidence.
- No source files were edited.

Validation:

- R409 `artifact_type=tod_evidence_pool_source_anchor_classifier`.
- R409 `classification_decision=passed`.
- R409 `packet_materialization_allowed=true`.
- R409 `selected_source_anchor_artifact` is nonempty.
- R409 `classified_artifacts` count is 5.
- R409 `no_code_changes=true`.

Capability finding:

The classifier works when TOD receives the runtime's accepted audit-artifact shape. This clears the R405/R406 selector blocker but remains scaffolded because Codex supplied the evidence pool and canonical input shape.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. This is evidence classification, not code repair. |
| Runtime | Yes. TOD entered the intended classifier lane and produced the correct artifact. |
| Governance | Yes. The artifact distinguishes usable source-anchor evidence from context/review evidence. |
| Evidence | Yes. R409 is durable proof that the classifier lane can work. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

For this runtime lane, "evidence pool" in prose is insufficient. TOD must provide one canonical input artifact and explicit output path, while additional pool members can be listed for classification.

## 2026-07-25 R410 Classifier-To-Packet Body Partial Pass

Fresh evidence:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_CLASSIFIER_TO_PACKET_BODY_SYNTHESIS_R410.latest.json`

Observed result:

- R410 used the R409 classifier as input.
- The packet-body synthesis lane followed the classifier's selected source-anchor artifact.
- The packet body targeted `scripts/TOD.ps1`, derived from the selected source-anchor evidence.
- TOD produced `tod_packet_body_synthesis_artifact`.
- No source files were edited.

Validation:

- R410 `artifact_type=tod_packet_body_synthesis_artifact`.
- R410 `source=local_execution_packet_body_synthesis_lane`.
- R410 `packet_candidate_ready=true`.
- R410 `packet.target_file=scripts/TOD.ps1`.
- R410 validation recorded `input_artifact_read=true`.
- R410 validation recorded `old_text_present=true`.
- R410 validation recorded `new_text_differs=true`.
- R410 validation recorded `packet_candidate_schema=ready`.
- R410 validation recorded `no_source_edits=true`.

Capability finding:

R410 proves classifier output can drive packet-body synthesis without Codex naming the source file as a top-level target. It does not prove engineering readiness because the synthesized new text was malformed for PowerShell and must not be applied.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. The generated packet body is not safe to apply. |
| Runtime | Yes. TOD chained classifier output into packet-body materialization. |
| Governance | Partial. TOD created the artifact without source mutation, but quality review was still required. |
| Evidence | Yes. The artifact records the selected source anchor and packet candidate. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Artifact schema readiness is not patch readiness. A packet body must pass semantic and syntax-aware quality review before it can be eligible for apply.

## 2026-07-25 R411 Packet Quality Review Rejection Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_CLASSIFIER_TO_PACKET_BODY_QUALITY_REVIEW_R411.latest.json`

Observed result:

- R411 reviewed the R410 packet-body artifact before apply.
- TOD produced `tod_packet_quality_review_artifact`.
- The packet was rejected.
- The decisive failure was that the new text contained malformed/forbidden content: `"# TOD training note":`.
- No source files were edited.

Validation:

- R411 `artifact_type=tod_packet_quality_review_artifact`.
- R411 `decision=reject_packet`.
- R411 `review_artifact=runtime_remote_training/tod_independent_resolution_attempts/TOD_CLASSIFIER_TO_PACKET_BODY_SYNTHESIS_R410.latest.json`.
- R411 `source_file=scripts/TOD.ps1`.
- R411 `expected_decision_matches_intrinsic_review=true`.

Capability finding:

TOD successfully stopped an unsafe packet candidate before apply. This is an important governance and recovery behavior: the training lane must reject bad materialization instead of counting it as implementation progress.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No safe implementation patch was produced. |
| Runtime | Yes. TOD used packet quality review after packet-body synthesis. |
| Governance | Yes. TOD rejected unsafe output instead of applying it. |
| Evidence | Yes. R411 records checked evidence and rejection reasons. |
| Model Utilization | No. No provider/model candidate was invoked. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

The recovery ladder for source-anchor packet work is now: classify evidence pool, synthesize packet body, review packet quality, then apply only if review accepts. The current chain is working through review, but still lacks autonomous safe new-text generation.

Next smallest training rung:

`TOD-AUTONOMOUS-SAFE-NEWTEXT-FROM-SOURCE-ANCHOR-V1`

Mission:

TOD must produce a safe, behavior-preserving or behavior-changing new-text candidate from source-anchor evidence without Codex writing the replacement text. The pass condition is not apply. The pass condition is a reviewed packet candidate where quality review either accepts a safe bounded delta or rejects it with precise evidence and a smaller next repair step.

## 2026-07-25 R412 Autonomous Safe New-Text Capability Blocker Proof

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_SAFE_NEWTEXT_SOURCE_ANCHOR_R412.latest.json`

Observed result:

- R412 attempted the next smallest read-only delta-proposal rung from source-anchor evidence.
- TOD produced `tod_source_anchor_delta_proposal`.
- The source anchor was valid.
- The target file was identified as `scripts/TOD.ps1`.
- TOD did not invent replacement text.
- The artifact explicitly blocked on missing autonomous safe new-text synthesis.
- No source files were edited.

Validation:

- R412 `artifact_type=tod_source_anchor_delta_proposal`.
- R412 `status=blocked`.
- R412 `old_text_source=runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_OUTPUT_ARTIFACT_ASSERTION_R401.latest.json`.
- R412 `target_file=scripts/TOD.ps1`.
- R412 `candidate_new_text=''`.
- R412 `no_source_code_modified=true`.
- R412 validation recorded `input_read=true`.
- R412 validation recorded `source_anchor_valid=true`.
- R412 validation recorded no source edits.
- R412 blocker `reason_code=autonomous_candidate_new_text_missing`.
- R412 blocker `missing_capability=autonomous_meaningful_safe_new_text_synthesis_from_source_anchor`.

Capability finding:

TOD can now classify source-anchor evidence, carry it into packet-body synthesis, reject unsafe packet output, and publish a precise missing-capability blocker. TOD still cannot independently synthesize safe meaningful `new_text` from source-anchor evidence.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. The core engineering synthesis capability remains missing. |
| Runtime | Yes. TOD reached the correct smallest blocker rung. |
| Governance | Yes. TOD refused to invent progress and preserved source safety. |
| Evidence | Yes. R412 is explicit proof of the current independence boundary. |
| Model Utilization | No. TOD did not yet invoke or supervise an engineering model/provider. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

The training debt is now narrower and more useful: TOD does not need more selector plumbing for this rung; it needs model-utilization or engineering-corpus support to generate and critique a meaningful bounded `new_text` candidate from source evidence.

Next smallest training rung:

`TOD-MODEL-UTILIZATION-FOR-SAFE-NEWTEXT-V1`

Mission:

TOD must prepare a model/provider request from R412 evidence that contains the source anchor, target file, intended behavior delta, safety constraints, validation command, and required reviewer checks. TOD should not apply or accept the result blindly. Success requires a provider request artifact that a model could use to propose candidate new text, plus a planned review gate before any apply step.

## 2026-07-25 R413 Engineering Context Package Partial Failure

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_ENGINEERING_CONTEXT_R413.latest.json`

Observed result:

- R413 attempted to build an engineering context package from the R412 blocker artifact.
- TOD produced `tod_engineering_context_package`.
- The package preserved the problem summary, observed failure, desired behavior, validation target, and rejected-output rules.
- The package failed to populate `source_file`.
- The package set `source_anchor_artifact` to R412, which is a blocker wrapper rather than the original source-anchor observation.
- No source files were edited.

Validation:

- R413 `artifact_type=tod_engineering_context_package`.
- R413 `problem_summary` is present.
- R413 `observed_failure` is present.
- R413 `desired_behavior` is present.
- R413 `rejected_outputs` includes marker-only/comment-only/no-delta and wrong-target outputs.
- R413 `source_file=''`.
- R413 `no_code_changes=true`.

Capability finding:

TOD can package the coaching problem, but it selected the wrong evidence layer as source context. A blocker artifact can explain the debt; it cannot substitute for direct source-anchor evidence when building a provider-ready context package.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. Provider-ready source context was incomplete. |
| Runtime | Partial. The context package lane ran, but from the wrong input layer. |
| Governance | Yes. The package did not claim readiness or mutate source. |
| Evidence | Yes. R413 proves the evidence-layer mismatch. |
| Model Utilization | No. Missing `source_file` prevents provider request readiness. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Model-utilization context packages must be built from direct source-anchor evidence, not from downstream blocker wrappers. Blocker artifacts should be supporting evidence, not the primary context source.

Next smallest training rung:

`TOD-SOURCE-ANCHOR-ENGINEERING-CONTEXT-PACKAGE-V1`

Mission:

Retry engineering context packaging using the selected source-anchor observation as the primary input artifact and the R412/R411 artifacts as supporting context. The context package must populate `source_file`, `source_function`, `source_anchor_artifact`, desired behavior, rejected outputs, and validation target before any provider request is attempted.

## 2026-07-25 R414 Direct Source-Anchor Engineering Context Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_ENGINEERING_CONTEXT_R414.latest.json`

Observed result:

- R414 retried context packaging with the direct source-anchor observation as primary input.
- TOD produced `tod_engineering_context_package`.
- The package populated `source_file=scripts/TOD.ps1`.
- The package populated `source_function=Test-TaskAllowsLocalExecutionWithoutMaterialization`.
- The package pointed `source_anchor_artifact` to R401.
- The package preserved observed failure, desired behavior, validation target, and rejected-output policy.
- No source files were edited.

Validation:

- R414 `artifact_type=tod_engineering_context_package`.
- R414 `source_file=scripts/TOD.ps1`.
- R414 `source_function=Test-TaskAllowsLocalExecutionWithoutMaterialization`.
- R414 `source_anchor_artifact=runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_OUTPUT_ARTIFACT_ASSERTION_R401.latest.json`.
- R414 `rejected_outputs` includes marker-only, comment-only, whitespace-only, input-artifact target, and output-artifact target.
- R414 `no_code_changes=true`.

Capability finding:

TOD can now build the correct engineering context package when the direct source-anchor artifact is primary and blocker/review artifacts are supporting context. This repairs the R413 evidence-layer mistake.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. Context package only. |
| Runtime | Yes. TOD used the correct input layer and populated source role fields. |
| Governance | Yes. The package keeps rejected-output rules before provider invocation. |
| Evidence | Yes. R414 is provider-context evidence. |
| Model Utilization | Partial. It prepares model utilization but does not yet request or evaluate a candidate. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R415 Model-Utilization Judgment Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_MODEL_UTILIZATION_JUDGMENT_R415.latest.json`

Observed result:

- R415 evaluated R414 for provider/model readiness.
- TOD produced `tod_model_utilization_engineering_judgment`.
- The context was classified as `provider_prompt_ready`.
- `candidate_request_ready=true`.
- `provider_reachable=false`.
- The missing provider hook was named: `no_engineering_provider_hook_available_in_local_execution_lane`.
- TOD accept/reject policy was preserved.
- No source files were edited.

Validation:

- R415 `artifact_type=tod_model_utilization_engineering_judgment`.
- R415 `context_quality=provider_prompt_ready`.
- R415 `candidate_request_ready=true`.
- R415 `provider_or_runtime_hook=no_engineering_provider_hook_available_in_local_execution_lane`.
- R415 `counts_as_model_utilization_credit=partial_context_and_judgment_credit_only`.
- R415 `no_source_code_modified=true`.

Capability finding:

TOD can now distinguish provider-ready context from actual provider availability. This is progress in supervising engineering: TOD is not claiming a model exists locally; it is preparing the request and preserving the review gate.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No candidate patch was generated. |
| Runtime | Partial. This is orchestration support. |
| Governance | Yes. The artifact names the provider hook blocker honestly. |
| Evidence | Yes. R415 records readiness and blocker state. |
| Model Utilization | Partial. Context/judgment credit only. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R416 Engineering Provider Request Partial Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_ENGINEERING_PROVIDER_REQUEST_R416.latest.json`

Observed result:

- R416 produced `tod_engineering_provider_request`.
- `provider_request_ready=true`.
- `target_file=scripts/TOD.ps1`.
- `source_files_to_include` includes `scripts/TOD.ps1`.
- `artifacts_to_include` includes R414, R415, and R401.
- The request preserves the accept/reject review gate.
- The request explicitly says the next step is provider invocation followed by TOD accept/reject before any source edit.
- No source files were edited.

Validation:

- R416 `artifact_type=tod_engineering_provider_request`.
- R416 `provider_request_ready=true`.
- R416 `provider_role=local_engineering_model_or_provider_candidate_patch_generator`.
- R416 `counts_as_model_utilization_credit=provider_request_artifact_only`.
- R416 rejection policy includes source-target, exact old-text, and validation-command requirements.

Remaining defect:

R416 still carries `validation_command=PowerShell parse or focused regression covering the changed source behavior`, which is a placeholder phrase. The request is structurally provider-ready, but not quality-ready for invocation under the same standard we applied to earlier provider candidates. This must be corrected before invoking any provider or claiming model-utilization independence.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No candidate patch was generated or reviewed. |
| Runtime | Yes. Provider-request packaging worked. |
| Governance | Partial. Review policy is present, but validation command is still a placeholder. |
| Evidence | Yes. R416 is durable request evidence. |
| Model Utilization | Partial. Provider request artifact only; no invocation. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Prevention lesson:

Provider request readiness must include an executable validation command, not only correct target/source/artifact routing. Otherwise TOD will recreate the earlier provider-candidate defect where placeholder validation made a candidate unusable.

Next smallest training rung:

`TOD-PROVIDER-REQUEST-VALIDATION-COMMAND-REPLAN-V1`

Mission:

TOD must replan or repair the provider-request artifact so the validation command is executable and appropriate for the target source. The output should remain an artifact, not a source edit. Success requires provider request readiness plus a non-placeholder validation command and preserved accept/reject gate.

## 2026-07-25 Current Boundary After R416

Current proven chain:

1. R409: evidence-pool classifier can select usable source-anchor evidence.
2. R410: classifier output can drive packet-body synthesis.
3. R411: packet-quality review can reject unsafe synthesized packet bodies before apply.
4. R412: TOD can publish an honest blocker when autonomous safe new-text synthesis is unavailable.
5. R414: direct source-anchor evidence can become a provider-ready engineering context package.
6. R415: TOD can judge model-utilization readiness and name the missing provider hook.
7. R416: TOD can publish a provider request artifact with target/source/artifact roles and accept/reject policy.

Still unproven:

- TOD cannot independently generate safe meaningful `new_text` from source-anchor evidence.
- TOD cannot yet invoke a real local engineering provider/model from this lane.
- TOD cannot yet repair a provider request whose validation command remains a placeholder phrase.
- TOD has not produced a provider candidate, accepted or rejected that candidate from source evidence, applied a safe patch, or validated a source behavior change.

Current blocker:

`provider_request_validation_command_placeholder`

Evidence:

- R416 `validation_command=PowerShell parse or focused regression covering the changed source behavior`.
- R416 system prompt correctly says validation must be executable, but the request-level validation command is still a placeholder.
- No dedicated provider-request quality/replan lane was found for this defect. Existing replan support is aimed at rejected provider candidates, not provider request quality before invocation.

Next smallest training rung:

`TOD-PROVIDER-REQUEST-QUALITY-REVIEW-LANE-V1`

Mission:

TOD needs a read-only review capability for provider request artifacts before provider invocation. It should inspect `tod_engineering_provider_request`, reject placeholder validation commands, confirm source/artifact roles, preserve accept/reject policy, and produce a smaller executable replan target. This is runtime support debt, not engineering independence credit.

## 2026-07-25 R417 Provider Request Source-Anchor Observation Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_QUALITY_REVIEW_LANE_SOURCE_ANCHOR_R417.latest.json`

Observed result:

- TOD inspected `scripts/engines/LocalExecutionEngine.ps1`.
- TOD found the provider-request branch in `Invoke-LocalExecutionReadOnlyAuditArtifact`.
- The captured source shows how `validation_command` falls back to `PowerShell parse or focused regression covering the changed source behavior`.
- No source files were edited.

Validation:

- R417 `artifact_type=tod_source_anchor_observation`.
- R417 `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R417 `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R417 `anchor_pattern=$wantsEngineeringProviderRequest`.
- R417 `anchor_found=true`.
- R417 `exact_text_nonempty=true`.
- R417 `no_code_changes=true`.

Capability finding:

TOD can now source-anchor the provider-request quality defect. The weakness is no longer vague "provider request bad"; the source branch that produces the placeholder validation command is visible.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R418 Local Engineering Provider Inventory Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_PROVIDER_INVENTORY_R418.latest.json`

Observed result:

- TOD produced `tod_local_engineering_provider_inventory`.
- The inventory found `python`, `node`, and `nvidia-smi`.
- The configured local provider assets exist:
  - `tools/llama.cpp/llama-server.exe`
  - `models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf`
- The local endpoint `http://127.0.0.1:8008/v1/models` was reachable.
- The endpoint reported model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- `usable_provider_hook=true`.
- No source files were edited.

Validation:

- R418 `artifact_type=tod_local_engineering_provider_inventory`.
- R418 `provider_request_ready=true`.
- R418 `real_provider_reachable=true`.
- R418 `usable_provider_hook=true`.
- R418 `gpu_available=true`.
- R418 `next_smallest_rung=TOD-LOCAL-ENGINEERING-PROVIDER-CANDIDATE-INVOCATION-V1`.

Capability finding:

The immediate blocker is not missing hardware or a missing provider endpoint. TOD has a reachable local engineering provider hook. The next risk is whether TOD can invoke the provider with correct source-anchor evidence and reject unusable candidates.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. Inventory is not a code repair. |
| Runtime | Yes. TOD identified a usable provider hook from local evidence. |
| Governance | Yes. It preserved the no-source-edit boundary. |
| Evidence | Yes. Tool, asset, endpoint, model, and GPU facts are recorded. |
| Model Utilization | Partial. Provider hook inventory only. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R419 Provider Candidate Invocation Attempt Rejected By Evidence

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_PROVIDER_CANDIDATE_INVOCATION_R419.latest.json`

Observed result:

- TOD attempted the provider-candidate invocation lane.
- `provider_called=false`.
- `candidate_response_available=false`.
- `old_text` was blank.
- `new_text` was blank.
- `validation_command` remained the generic placeholder.
- No source files were edited.

Root cause observed:

The provider request's `artifacts_to_include` listed `TOD_SOURCE_ANCHOR_ENGINEERING_CONTEXT_R414.latest.json` before the real source-anchor observation R401. The provider invocation branch selected the first path whose filename matched `SOURCE_ANCHOR.*.json`. R414 is an engineering context package and does not contain `exact_text`, so the invocation had no old text and did not call the provider.

Validation:

- R419 `artifact_type=tod_engineering_provider_candidate_invocation`.
- R419 `input_provider_request=...R416.latest.json`.
- R419 `input_provider_inventory=...R418.latest.json`.
- R419 `provider_called=false`.
- R419 `validation.required_fields_present=false`.
- R419 `no_source_code_modified=true`.

Capability finding:

TOD reached a live provider hook, but the invocation path still has source-anchor role confusion. A filename that contains `SOURCE_ANCHOR` is not sufficient proof that the artifact is source-anchor evidence.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R420 Provider Candidate Verdict Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_PROVIDER_CANDIDATE_VERDICT_R420.latest.json`

Observed result:

- TOD ran the accept/reject verdict gate on R419.
- Verdict: `reject`.
- Reason: `rejected_blank_old_text`.
- The verdict also rejected blank `new_text`, missing old text in current source, no delta, and generic validation command.
- `accepted_for_source_mutation=false`.
- `rejected_before_source_mutation=true`.
- No source files were edited.

Validation:

- R420 `artifact_type=tod_engineering_provider_candidate_verdict`.
- R420 includes policy checks for:
  - `old_text_nonblank=false`
  - `new_text_nonblank=false`
  - `old_text_found_in_current_source=false`
  - `has_delta=false`
  - `validation_command_specific=false`
- R420 `next_smallest_rung=TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1`.

Capability finding:

This is a meaningful guardrail pass. TOD did not treat provider invocation machinery as progress. It rejected an unusable candidate before mutation.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. No source repair exists. |
| Runtime | Partial. Verdict gate worked. |
| Governance | Yes. Bad candidate was rejected before mutation. |
| Evidence | Yes. Failure checks are explicit. |
| Model Utilization | Partial. Candidate-policy judgment only. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R421 / R421B Replan Materialization Partial Pass

Fresh evidence:

- R421 expected output missing: `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_PROVIDER_CANDIDATE_REPLAN_R421.latest.json`
- R421B materialized output: `runtime_remote_training/read_only_audit_artifacts/TOD_SAFE_NEWTEXT_PROVIDER_CANDIDATE_REPLAN_R421B.latest.json`

Observed result:

- R421 failed to materialize a replan artifact.
- R421B succeeded only after the task was restated as an explicit read-only assessment artifact write.
- R421B produced `tod_engineering_provider_candidate_replan`.
- R421B preserved the prior rejection reason `rejected_blank_old_text`.
- R421B set `provider_request_ready_for_retry=true`.
- R421B still pointed `source_anchor_artifact` at `TOD_SOURCE_ANCHOR_ENGINEERING_CONTEXT_R414.latest.json`, which is not the actual source-anchor evidence.
- No source files were edited.

Validation:

- R421B `artifact_type=tod_engineering_provider_candidate_replan`.
- R421B `input_provider_request=...R416.latest.json`.
- R421B `input_candidate_invocation=...R419.latest.json`.
- R421B `prior_verdict=reject`.
- R421B `prior_rejection_reason_code=rejected_blank_old_text`.
- R421B `source_anchor_artifact=...R414.latest.json`.

Remaining defect:

R421B is structurally materialized but semantically false-ready. It accepts a context package as the source-anchor artifact because the selection logic still prefers a path-name match before verifying artifact type or `exact_text`.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R422 Replan Source-Anchor Selection Observation Pass

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REPLAN_MATERIALIZATION_SOURCE_ANCHOR_R422.latest.json`

Observed result:

- TOD inspected the `tod_engineering_provider_candidate_replan` branch.
- TOD captured the exact source around `$wantsEngineeringProviderCandidateReplan`.
- The source shows the same source-anchor selection pattern:
  1. first accept any artifact path matching `SOURCE_ANCHOR.*.json`;
  2. only if no filename match exists, inspect JSON for `artifact_type=tod_source_anchor_observation` or `exact_text`.
- No source files were edited.

Validation:

- R422 `artifact_type=tod_source_anchor_observation`.
- R422 `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R422 `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R422 `anchor_pattern=$wantsEngineeringProviderCandidateReplan`.
- R422 `anchor_found=true`.
- R422 `exact_text_nonempty=true`.
- R422 `no_code_changes=true`.

Capability finding:

TOD has identified the exact source pattern causing false source-anchor selection. The fix should not be broad; it should teach the selector to verify artifact semantics before filename hints.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 R423 Autonomous Delta Proposal Honest Blocker

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_REPLAN_SOURCE_ANCHOR_SELECTION_DELTA_R423.latest.json`

Observed result:

- TOD attempted to produce a source-anchor delta proposal from R422 and R421B.
- TOD did not edit source code.
- TOD did not fake candidate text.
- Status: `blocked`.
- Blocker class: `capability_blocker`.
- Reason code: `autonomous_candidate_new_text_missing`.
- Missing capability: `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor`.

Validation:

- R423 `artifact_type=tod_source_anchor_delta_proposal`.
- R423 `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R423 `candidate_new_text=""`.
- R423 `source_anchor_valid=true`.
- R423 `source_edits=[]`.

Capability finding:

TOD can now run the provider-inventory, invocation, verdict, replan, and source-anchor diagnosis loop, but still cannot independently synthesize safe behavior-changing source text from inspected code. This is the central current-code engineering blocker, not a runtime availability blocker.

Credit classification:

| Track | Credit |
| --- | --- |
| Engineering | No. TOD did not produce a source change. |
| Runtime | Yes. It completed a multi-step provider/review/replan diagnostic loop. |
| Governance | Yes. It rejected bad candidates and refused to fake a patch. |
| Evidence | Yes. R418-R423 preserve the chain. |
| Model Utilization | Partial. Provider hook exists, but no valid provider candidate was produced because source-anchor selection failed before invocation. |

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

## 2026-07-25 Current Boundary After R423

Current proven chain:

1. R417: TOD source-anchored the provider-request validation placeholder source.
2. R418: TOD inventoried a reachable local engineering provider hook.
3. R419: TOD attempted provider invocation and exposed blank old-text due source-anchor role confusion.
4. R420: TOD rejected the bad candidate before mutation.
5. R421B: TOD materialized a replan after explicit read-only contract clarification.
6. R422: TOD source-anchored the replan source-anchor selection bug.
7. R423: TOD honestly blocked on autonomous safe new-text synthesis instead of fabricating a patch.

Still unproven:

- TOD cannot independently create a safe behavior-changing patch from source-anchor evidence.
- TOD cannot yet invoke the provider with correct old text for this R416/R418/R419 chain because source-anchor selection picks a context package first.
- TOD cannot yet repair the selector itself.
- No source behavior change has been applied or validated.

Current blocker:

`autonomous_meaningful_safe_new_text_synthesis_from_source_anchor`

Immediate next smallest training rung:

`TOD-SOURCE-ANCHOR-SELECTION-OLDTEXT-PROVIDER-RETRY-V1`

Mission:

Back up one rung. TOD should create a provider request or replan retry that uses the real source-anchor observation R401 directly as source-anchor evidence, bypassing the false filename-selected context package. The goal is not to patch source yet; the goal is to prove the local provider can be called with nonblank exact `old_text`, then require the verdict gate to accept or reject the candidate.

## 2026-07-25 R424 Recovery Family Retirement Gate Recheck

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_RECOVERY_FAMILY_RETIREMENT_GATE_RECHECK_R424.latest.json`

Observed result:

- TOD reviewed APP-TOD-011, APP-TOD-020, and APP-TOD-023 against the current apprenticeship registry and named evidence.
- TOD inspected existing evidence paths for each entry.
- TOD proposed zero registry changes.
- No source files were edited.

Validation:

- R424 `artifact_type=tod_readonly_retirement_eligibility_proof`.
- R424 reviewed:
  - `APP-TOD-011`
  - `APP-TOD-020`
  - `APP-TOD-023`
- R424 `eligible_retirements=0`.
- R424 `projected_borrowed_percent=78.4`.
- R424 `no_source_code_modified=true`.

Retirement decisions:

| Entry | Decision | Reason |
| --- | --- | --- |
| APP-TOD-011 | not_yet_eligible | Proficiency is not independent or reliable in the registry. |
| APP-TOD-020 | not_yet_eligible | Proficiency is not independent or reliable in the registry. |
| APP-TOD-023 | not_yet_eligible | Proficiency is not independent or reliable, and freeze/prevention lesson is not strong enough. |

Capability finding:

TOD can produce an honest retirement-gate proof and avoid inflating the borrowed-capability ratio. The next blocker is not missing evidence files; it is registry materialization quality. Entries with focused independent demonstrations still need explicit proficiency/freeze fields before retirement math can move.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Next smallest training rung:

`TOD-REGISTRY-PROFICIENCY-FIELD-MATERIALIZATION-V1`

Mission:

TOD should inspect one registry entry with independent evidence, synthesize a bounded documentation update that adds or corrects proficiency/freeze text from existing evidence, validate the markdown, then rerun the read-only retirement gate. This is governance debt, not engineering implementation credit, and it must not change retirement status unless the evidence gates are satisfied.

## 2026-07-25 R425/R425E Registry Proficiency Materialization Dispatch Failure

Fresh evidence:

- Expected artifact missing: `runtime_remote_training/read_only_audit_artifacts/TOD_APP_TOD_011_REGISTRY_PROFICIENCY_DELTA_R425.latest.json`
- R425D task state: `TOD-R425-MISSING-ARTIFACT-SELF-DIAGNOSIS-V1`, `R425D-20260725`
- R425E task state: `TOD-R425-MISSING-ARTIFACT-SELF-DIAGNOSIS-V1`, `R425E-20260725`
- Fallback selected task: `TSK-0102`
- Fallback artifact: `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CALL_MATERIALIZATION_SOURCE_ANCHOR_R361.latest.json`
- Fallback patch hold: `runtime_remote_training/cleanup_holds/TSK-0102_95361c28beae.patch`

Observed result:

- R425 did not produce the requested APP-TOD-011 registry proficiency delta artifact.
- R425D proved the first dispatch was accepted into task state but routed to the Codex wrapper.
- R425E set `assigned_executor=local`, but `run-task` still attempted `codex` first, then local fallback reported `local_execution_scope_not_supported`.
- The automatic fallback selected an unrelated backlog task (`TSK-0102`) under `TOD-LOCAL-ENGINEERING-PROVIDER-CALL-MATERIALIZATION-V1`.
- `TSK-0102` produced a route-patch classification artifact and patch-hold evidence instead of the requested R425 diagnostic or APP-TOD-011 registry delta.

Validation:

- `R425D-20260725` exists in `tod/data/state.json`.
- `R425E-20260725` exists in `tod/data/state.json`.
- Both R425D and R425E terminal states report `codex_wrapper_only_no_execution`.
- R425E local fallback reports `local_execution_scope_not_supported`.
- No R425, R425D, or R425E requested output artifact exists under `runtime_remote_training/read_only_audit_artifacts`.
- `TSK-0102` status is `blocked` with `required_validation_failed`.
- `TSK-0102` is not the same objective, not the same task, and not a valid substitute for R425.

Capability finding:

TOD has two distinct blockers at this rung:

1. Read-only diagnostic artifact work submitted through `execute-chat-task` can still route into the Codex wrapper instead of an eligible local artifact writer.
2. After that failure, TOD's next-task selector can drift into stale backlog work instead of preserving the current objective family.

This is not a registry-writing failure yet. It is a selector and execution-lane authority failure before the registry update can be honestly attempted.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Immediate next smallest training rung:

`TOD-CURRENT-OBJECTIVE-SELECTOR-PRESERVATION-V1`

Mission:

TOD must classify why the current R425 registry objective was displaced by `TSK-0102`, then produce a read-only selector-preservation proof that names the active objective, the stale selected objective, the divergence point, and the smallest rule required to keep retries inside the current objective family unless a human or MIM explicitly changes priorities.

## 2026-07-25 R426-R432B Selector Preservation Reduction

Fresh evidence:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_TARGET_SELECTION.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_APP_TOD_011_REGISTRY_SOURCE_ANCHOR_R430.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_EVIDENCE_PATH_PREFIX_SOURCE_ANCHOR_R432B.latest.json`

Observed result:

- R426 asked TOD to preserve the current R425 registry objective family and reject stale `TSK-0102`.
- R426 wrote a target-selection artifact, but selected no candidate.
- R427 supplied a registry target in conversational text; TOD still selected no candidate.
- R428 moved the target into parser-visible description/scope, but `Target File:` caused bounded-edit materialization pressure instead of read-only target selection.
- R429 used `Source File:` vocabulary, but TOD still selected no candidate because no separate evidence artifact was available.
- R430 successfully produced a source-anchor observation for the APP-TOD-011 registry heading.
- R431 consumed R430 but still selected no candidate.
- R432B successfully source-anchored the selector implementation line that explains R431: source-anchor artifacts can name `docs/...`, but the target-selection evidence regex only accepts paths beginning with `scripts`, `tmp_remote_mim`, or `core`.

Validation:

- R430 `artifact_type=tod_source_anchor_observation`.
- R430 `source_file=docs/training/TOD_APPRENTICESHIP_REGISTRY.md`.
- R430 `anchor_found=true`.
- R430 `exact_text_nonempty=true`.
- R432B `artifact_type=tod_source_anchor_observation`.
- R432B `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R432B `source_function=New-LocalExecutionDifferentTargetDiscoveryArtifact`.
- R432B exact text contains the restrictive path prefix group `(?:scripts|tmp_remote_mim|core)`.
- No source code was modified by these steps.

Capability finding:

TOD can now reduce the selector-preservation blocker to a precise implementation surface:

`New-LocalExecutionDifferentTargetDiscoveryArtifact` does not allow documentation targets from evidence artifacts, so registry proficiency materialization cannot be selected through the current target-selection evidence path.

This is an authority/selector capability blocker, not an APP-TOD-011 registry-content blocker.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.

Immediate next smallest training rung:

`TOD-TARGET-SELECTION-DOCS-PATH-PREFIX-DELTA-PROPOSAL-V1`

Mission:

TOD should use R432B as the source anchor and attempt to produce a bounded delta proposal that generalizes the evidence-target path regex enough to include `docs/...` training registry files. This step is proposal-only unless TOD can also provide exact old text, exact new text, a focused validation command, and no stale selector fallback.

## 2026-07-25 R435C-R444 Local Provider Supervision Ladder

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_CONTEXT_R435C.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_MODEL_JUDGMENT_R436.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_REQUEST_R437.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_INVENTORY_R438.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_INVOCATION_R439.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_VERDICT_R440.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_REPLAN_R441.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_INVOCATION_RETRY_R442.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TARGET_SELECTION_DOCS_PATH_PREFIX_PROVIDER_VERDICT_RETRY_R443.latest.json`
- `runtime/tod_engineering_corpus/TOD_DOCS_PATH_SELECTOR_PROVIDER_SUPERVISION_R444.latest.json`

Observed result:

- R435 and R435B failed before useful provider supervision because the local artifact writer is strict about task shape.
- R435 failed when `TargetFile` pushed the request toward bounded-edit materialization.
- R435B used `Input Path:` and `Output Path:` labels; preflight recognized artifact-write intent, but direct execution fell back to the generic bounded path and rejected multiple candidate files.
- R435C corrected the task shape by using exact `Input:` and `Output:` labels and produced a valid engineering context package from the R432B source-anchor artifact.
- R436 produced a provider-ready model-utilization judgment from the context package.
- R437 produced a provider request with target file, exact source anchor, and bounded candidate requirements.
- R438 proved a local engineering provider was reachable at `http://127.0.0.1:8008/v1/models` with model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- R439 called the local provider, but the response failed JSON parsing and produced no non-empty `new_text`.
- R440 rejected the provider candidate before source mutation because `new_text` was blank and the validation command was generic.
- R441 replanned the provider request from the rejection evidence without changing source files.
- R442 retried the provider invocation; the provider again returned malformed or unusable JSON and no safe `new_text`.
- R443 rejected the retry before source mutation for the same safety reasons.
- R444 recorded the episode in the engineering corpus as supervision training, not as independent implementation credit.

Validation:

- R435C task state completed with `local_executor_completed`.
- R436, R437, R438, R440, R443, and R444 have completed task states or passed readback evidence.
- R438 reports `usable_provider_hook=true` and a reachable local model endpoint.
- R440 and R443 both set `accepted_for_source_mutation=false` and `rejected_before_source_mutation=true`.
- R444 `artifact_type=tod_engineering_episode_card`.
- R444 `status=recorded`.
- R444 `no_source_edits=true`.
- R444 `independent_credit_requested=false`.
- No source code changed during this ladder.

Capability finding:

TOD can now supervise a local engineering provider through a full read-only ladder:

context package -> model judgment -> provider request -> provider inventory -> provider invocation -> candidate verdict -> replan -> retry -> verdict -> engineering episode.

That is real model-utilization and evidence-integrity progress. It is not yet engineering independence because TOD did not obtain a safe bounded implementation candidate from the provider and did not apply a source edit.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This rung reduces ambiguity around the blocker: the current gap is provider candidate quality and JSON-safe patch materialization, not provider availability.

Immediate next smallest training rung:

`TOD-LOCAL-PROVIDER-CANDIDATE-QUALITY-V1`

Mission:

TOD should use R439 and R442 as failure evidence, classify why the local provider returned unusable patch candidates, and produce a stricter provider-request pattern that separates source-anchor references from JSON-escaped patch text. The pass condition is not source mutation. The pass condition is a candidate response with non-empty old text, non-empty behavior-changing new text, a specific validation command, and a verdict artifact that can accept or reject it without parse ambiguity.

## 2026-07-25 R445-R458 Provider Supervision And Discovery-Lane Preemption

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_DOCS_PATH_SELECTOR_PROVIDER_SUPERVISION_QUALITY_R445.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_TARGET_DISCOVERY_R446.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DIFFERENT_TARGET_DISCOVERY_DRILL.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTED_BY_READONLY_CONTEXT_SOURCE_ANCHOR_R447.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_LANE_SOURCE_ANCHOR_R448.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_DISCOVERY_LANE_SOURCE_ANCHOR_R448B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_COMPARISON_R449B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_BRANCH_SPAN_R450.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_CONTEXT_R451.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_MODEL_JUDGMENT_R452.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_PROVIDER_REQUEST_R453.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_PROVIDER_INVENTORY_R454.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_PROVIDER_STUB_R456.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_PROVIDER_STUB_VERDICT_R457.latest.json`
- `runtime/tod_engineering_corpus/TOD_DISCOVERY_PREEMPTION_PROVIDER_FALLBACK_R458.latest.json`

Observed result:

- R445 quality-gated the R444 episode and correctly classified it as `accept_runtime_support_only`.
- R446/R446B attempted fresh target discovery but produced `tod_read_only_task_context_proof`, not a discovery artifact.
- R447 anchored the read-only task context detector at line 13051.
- R448 anchored the target-selection-specific discovery detector at line 13033.
- R448B anchored the generic different-target discovery detector at line 13066.
- R449/R449B showed the comparison lane can compare artifacts, but JSON timestamp comparison is not enough to prove semantic branch order.
- R450 solved that by creating one branch-span source anchor from lines 13031-13071. The span shows the generic discovery branch appears after read-only task context.
- R451 packaged the branch-order failure into an engineering context package.
- R452 judged the context provider-ready, with no source edits.
- R453 produced a provider request for a bounded repair candidate.
- R454 proved the local provider endpoint was reachable.
- R455 live provider invocation did not publish the requested artifact and left task state in progress.
- R456 backed up to the deterministic provider stub lane.
- R457 rejected that stub before source mutation because old text and new text were blank and validation was generic.
- R458 recorded the fallback episode in the engineering corpus without requesting independent credit.

Validation:

- R445 `borrowed_capability_ratio_effect=no_reduction`.
- R450 `artifact_type=tod_source_anchor_observation`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `start_line=13031`, `end_line=13071`, `line_count=41`.
- R451 `artifact_type=tod_engineering_context_package`, source function `Invoke-LocalExecutionEngine`, and desired behavior names discovery-lane preservation.
- R454 `real_provider_reachable=true` and `usable_provider_hook=true`.
- R457 `verdict=reject`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- R458 `artifact_type=tod_engineering_episode_card`, `debt_category=runtime_plumbing`, `no_source_edits=true`, and `independent_credit_requested=false`.

Capability finding:

TOD learned two things in this branch:

1. The fresh-target selection blocker was not lack of candidates; it was lane precedence. Generic different-target discovery runs after read-only task context proof, so inspection-shaped discovery can be preempted.
2. When live provider invocation fails to materialize an artifact, TOD can back up to a deterministic stub and verdict gate instead of mutating source or claiming progress.

This is useful engineering supervision discipline, but it is still runtime plumbing. It does not reduce the borrowed-capability ratio.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- Provider availability is proven; safe live provider candidate materialization remains unproven.

Immediate next smallest training rung:

`TOD-DISCOVERY-PREEMPTION-EPISODE-QUALITY-GATE-V1`

Mission:

TOD should run the episode-quality Examiner on R458. If the episode is accepted only as runtime support, TOD should select the next fresh engineering target from a source-anchor path that does not depend on the preempted discovery lane. If the episode is rejected, TOD should publish the missing evidence and back up to the smallest missing proof.

## 2026-07-25 R459 Discovery-Preemption Episode Quality Gate

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_DISCOVERY_PREEMPTION_PROVIDER_FALLBACK_QUALITY_R459.latest.json`

Observed result:

- TOD quality-gated the R458 provider-fallback episode.
- The verdict accepted the episode as useful runtime-support memory only.
- The verdict did not allow engineering credit and did not reduce the borrowed-capability ratio.

Validation:

- R459 `artifact_type=tod_engineering_episode_quality_examiner_verdict`.
- R459 `status=completed`.
- R459 `training_usefulness=accept_runtime_support_only`.
- R459 `engineering_credit_allowed=false`.
- R459 `runtime_support_credit_allowed=true`.
- R459 `borrowed_capability_ratio_effect=no_reduction`.
- R459 task state completed with `local_executor_completed`.

Capability finding:

TOD can now quality-gate a runtime-plumbing episode without inflating engineering progress. This is useful because it prevents selector, artifact-lane, and provider-fallback work from being counted as independent engineering implementation.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- The current branch improved evidence honesty, not engineering independence.

Immediate next smallest training rung:

`TOD-DIRECT-SOURCE-ANCHOR-ENGINEERING-EPISODE-V1`

Mission:

TOD should avoid the preempted broad discovery lane and run one direct source-anchor engineering episode against an already identified source file. The episode must inspect one exact source anchor, diagnose one behavior gap, propose a bounded change candidate with non-empty old text, non-empty new text, and a specific validation command, then verdict the candidate before any source mutation. Passing this rung does not require applying the change; it requires proving TOD can produce a real engineering candidate rather than another runtime-plumbing artifact.

## 2026-07-25 R460-R461B Direct Source-Anchor Engineering Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_DIRECT_SOURCE_ANCHOR_DELTA_PROPOSAL_R460.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DIRECT_SOURCE_ANCHOR_NEWTEXT_SYNTHESIS_R461.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_DIRECT_SOURCE_ANCHOR_NEWTEXT_SYNTHESIS_R461B.latest.json`

Observed result:

- R460 consumed the R450 branch-span source anchor and produced a `tod_source_anchor_delta_proposal`.
- R460 correctly identified `scripts/engines/LocalExecutionEngine.ps1` as the bounded source target and preserved the source anchor without mutating source.
- R460 blocked because `candidate_new_text` was empty.
- R461 attempted the synthesis rung but only consumed one input artifact because the source anchor path was attached to an `Input:` label instead of listed as a bare evidence path.
- R461B corrected the input-list shape. It consumed both the source-anchor observation and prior delta blocker, preserved non-empty `old_text`, and still blocked because `new_text` remained empty.

Validation:

- R460 `source_anchor_valid=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, and `blocker.reason_code=autonomous_candidate_new_text_missing`.
- R461 `listed_input_count=1`, `source_anchor_valid=false`, and `prior_delta_available=true`.
- R461B `listed_input_count=2`, `source_anchor_valid=true`, `old_text_nonempty=true`, `new_text_nonempty=false`.
- R461B `blocker.reason_code=autonomous_meaningful_new_text_synthesis_missing`.
- All three rungs preserved `no_source_code_modified=true`.

Capability finding:

TOD can now carry a source-anchor target and old text into a direct engineering synthesis attempt. The remaining capability gap is not target selection, source anchoring, or input evidence shape. The gap is meaningful safe code-delta synthesis from source-anchor evidence.

Borrowed-capability impact:

- No borrowed capability retired.
- Borrowed ratio remains 78.4%.
- This branch narrows the blocker from "TOD cannot find an engineering task" to "TOD cannot yet synthesize behavior-changing new text from a valid source anchor."

Immediate next smallest training rung:

`TOD-MODEL-ASSISTED-CODE-DELTA-SYNTHESIS-V1`

Mission:

TOD should use the valid R461B source-anchor synthesis blocker as a context package for model-assisted code-delta synthesis. The pass condition is a provider candidate with non-empty old text, non-empty new text, a specific validation command, and a verdict artifact that rejects unsafe or malformed output before any source mutation.

## 2026-07-25 R462-R467 Model-Assisted Code-Delta Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_CONTEXT_R462.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_MODEL_JUDGMENT_R463B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_REQUEST_R464.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_INVENTORY_R465.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_INVOCATION_R466.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_VERDICT_R467.latest.json`

Observed result:

- R462 created a new context package from R461B, but it omitted `source_file` and `source_function`.
- R463 initially used the wrong artifact type name and was rejected by the local fallback as ambiguous target materialization.
- R463B reused the complete R451 context package and correctly judged it provider-prompt-ready.
- R464 generated a strict provider request targeting `scripts/engines/LocalExecutionEngine.ps1`.
- R465 verified the local provider endpoint was reachable, GPU was available, and the provider hook was usable.
- R466 invoked the local Qwen provider and received a parsed candidate response.
- R467 rejected the candidate before source mutation because `new_text` was blank, `old_text` did not match current source exactly, and the validation command was generic.

Validation:

- R463B `context_quality=provider_prompt_ready`, `candidate_request_ready=true`.
- R464 `provider_request_ready=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R465 `real_provider_reachable=true`, `gpu_available=true`, `usable_provider_hook=true`.
- R466 `provider_called=true`, `candidate_response_available=true`, and `counts_as_model_utilization_credit=local_provider_candidate_generated_pending_verdict`.
- R467 `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `old_text_length=2564`, `new_text_length=0`, and `rejected_before_source_mutation=true`.

Capability finding:

TOD has now demonstrated meaningful model-utilization supervision on this branch: it can build a provider request, confirm local provider availability, invoke the provider, parse a candidate, and reject the candidate without mutating source. It has not demonstrated independent engineering implementation because the candidate had no behavior-changing `new_text`, did not preserve exact current-source anchoring, and carried only a generic validation command.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization support improved; engineering implementation remains borrowed.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1`

Mission:

TOD should convert the R467 rejection into a stricter retry instruction that explicitly requires exact current-source old text copied from the source-anchor artifact, non-empty behavior-changing new text, and a concrete validation command. The retry instruction must also tell the provider that refusing to propose a change is acceptable only if it names the smallest required source-anchor or diagnosis evidence needed next.

## 2026-07-25 R468-R470 Provider Retry And Malformed Candidate Verdict

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_REPLAN_R468.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_RETRY_INVOCATION_R469B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_ASSISTED_CODE_DELTA_PROVIDER_RETRY_VERDICT_R470.latest.json`

Observed result:

- R468 converted the R467 rejection into a stricter provider retry instruction.
- R469 async retry was queued behind the protected active lane and did not publish an artifact.
- R469B synchronous retry published the provider invocation artifact.
- R469B called the provider and captured raw response text that attempted to include a `new_text` patch, but the JSON was malformed and parsed `new_text` remained blank.
- R470 correctly rejected the retry candidate before source mutation.

Validation:

- R468 `provider_request_ready_for_retry=true`.
- R469B `provider_called=true`, `candidate_response_available=true`, and `counts_as_model_utilization_credit=local_provider_candidate_generated_pending_verdict`.
- R469B `old_text` was non-empty, but parsed `new_text` was blank because `candidate_json_parse_failed`.
- R470 `old_text_found_in_current_source=true`, `new_text_nonblank=false`, `verdict=reject`, and `rejected_before_source_mutation=true`.

Capability finding:

TOD has now demonstrated the complete supervision loop around a failed provider retry: replan, synchronous invocation, malformed-output capture, and safe rejection. This still does not produce independent engineering implementation. The next blocker is provider-output materialization quality, likely worsened by a large 41-line source anchor that makes strict JSON patch output fragile.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization and rejection discipline improved; behavior-changing code-delta synthesis remains unproven.

Immediate next smallest training rung:

`TOD-SMALL-SOURCE-ANCHOR-PROVIDER-CANDIDATE-V1`

Mission:

TOD should select or create a smaller source anchor around the exact branch-order behavior gap, then rerun the provider request/invocation/verdict loop against that smaller old text. The pass condition is not applying source. The pass condition is a JSON-parseable candidate with exact-current old text, non-empty behavior-changing new text, and a concrete validation command, followed by an accept/reject verdict before mutation.

## 2026-07-25 R471-R477C Small Anchor And Context-Package Blocker

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DISCOVERY_PREEMPTION_SOURCE_ANCHOR_R471.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_SOURCE_ANCHOR_MODEL_JUDGMENT_R473.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_EMISSION_R472_BLOCKER.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_SOURCE_ANCHOR_PROVIDER_REPLAN_R474.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_SOURCE_ANCHOR_ROLE_REPAIR_PROOF_R475.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_SOURCE_ANCHOR_PROVIDER_REQUEST_R476.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_MATERIALIZER_SOURCE_ANCHOR_R477C.latest.json`

Observed result:

- R471 successfully captured a smaller source anchor around the read-only context branch and the generic different-target discovery branch.
- The R471 anchor is 16 lines instead of the earlier 41-line R450 anchor.
- R472, R472B, and R472C were accepted as read-only/context-package tasks but did not emit the requested `tod_engineering_context_package` artifact.
- R473 correctly judged direct provider use of R471 as not provider-ready because the source anchor is not a full engineering context package.
- R474 replanned from the provider-readiness failure and refused to mark the retry provider-ready.
- R475 produced a comparison artifact, but the comparison was too generic to answer the requested provider-field question, so it does not count as role-repair proof.
- R476 produced a provider-request artifact but marked `provider_request_ready=false` because the input still lacked structured context fields.
- R477C captured the current context-package materializer source surface for diagnosis.
- R478 attempted to diagnose the blocker through the model-utilization judgment lane, but it repeated the generic `context_package_missing_required_prompt_fields` verdict instead of identifying the selector/write condition that prevented R472 from emitting.
- R479 captured the selector eligibility source for `Test-LocalExecutionReadOnlyAuditArtifactTask`.
- The superseded request evidence showed R472C was overwritten by R473 before it could publish, so R472C alone was not valid proof of a context-package writer failure.
- R480 retried the same context-package emission without an immediate follow-on task. It remained `in_progress` with a valid `supported_read_only_artifact_write_contract_valid` materialization record, but no output artifact appeared after the wait window.

Validation:

- R471 `artifact_type=tod_source_anchor_observation`.
- R471 `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R471 `source_function=Invoke-LocalExecutionEngine`.
- R471 `exact_text_nonempty=true`.
- R471 `line_count=16`.
- R473 `context_quality=insufficient_context_package`.
- R473 `candidate_request_ready=false`.
- R473 `blocker_or_next_action.reason_code=context_package_missing_required_prompt_fields`.
- R476 `provider_request_ready=false`.
- R476 `validation.required_fields_present=false`.
- R477C `artifact_type=tod_source_anchor_observation`.
- R477C `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R477C captured the builder beginning at `$wantsEngineeringContextPackage`.
- R478 `artifact_type=tod_model_utilization_engineering_judgment`.
- R478 `candidate_request_ready=false`.
- R478 `blocker_or_next_action.reason_code=context_package_missing_required_prompt_fields`.
- R479 `artifact_type=tod_source_anchor_observation`.
- R479 `source_function=Test-LocalExecutionReadOnlyAuditArtifactTask`.
- R479 confirms `tod_engineering_context_package` is an accepted artifact type for the read-only audit artifact selector.
- R480 task state remained `in_progress`.
- R480 `materialization.reason_code=supported_read_only_artifact_write_contract_valid`.

Capability finding:

TOD improved the target quality by shrinking the source anchor and correctly refused to invoke the provider from insufficient context. The live blocker is narrower than before: TOD needs to materialize a provider-ready `tod_engineering_context_package` from a valid source-anchor observation. Generic model-utilization judgment is not enough to diagnose this because it repeats the missing-field verdict without tracing selector/write behavior. The current evidence points to a dispatch/execution-lane issue for accepted read-only artifact-write tasks: R480 has a valid materialization contract but no emitted artifact. This is not yet engineering implementation. It is the bridge between source inspection and model-assisted code-delta generation.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Source-anchor targeting improved.
- Provider-readiness honesty improved.
- Context-package emission from a fresh source anchor remains unproven.

Immediate next smallest training rung:

`TOD-READONLY-ARTIFACT-WRITE-DISPATCH-TRACE-V1`

Mission:

TOD should trace why R480 is accepted as `supported_read_only_artifact_write_contract_valid` but remains `in_progress` without publishing `TOD_SMALL_SOURCE_ANCHOR_CONTEXT_R480.latest.json`. The next attempt should inspect dispatch/heartbeat evidence, active-lane selection, local executor invocation, write/readback behavior, and stale/superseded task handling. The pass condition is either a valid context package from R471 with required provider prompt fields, or a precise blocker that names the exact dispatch/executor/write condition that prevented the artifact. Do not apply a source patch until the diagnosis is evidence-backed.

## 2026-07-25 R482-R493 Read-Only Artifact Role Collapse And Provider Boundary

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_R480_PROMPT_INPUT_OUTPUT_ROLE_TRACE_R482.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_BOUNDED_TARGET_AMBIGUITY_SOURCE_ANCHOR_R483.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_ARTIFACT_ROLE_COLLAPSE_CONTEXT_R484.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_ARTIFACT_ROLE_COLLAPSE_MODEL_JUDGMENT_R485.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_CONTEXT_R486.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_MODEL_JUDGMENT_R487.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_REQUEST_R488.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_CANDIDATE_STUB_R489.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_CANDIDATE_VERDICT_R490.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_CANDIDATE_REPLAN_R491.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_CANDIDATE_STUB_RETRY_R492.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_CANDIDATE_RETRY_VERDICT_R493.latest.json`

Observed result:

- R482 proved the R480 prompt had distinct artifact roles: `Input` was the R471 source-anchor artifact and `Output` was the requested context package.
- R483 captured the generic bounded fallback branch in `Invoke-LocalExecutionGenericBoundedTask` that calls `Get-LocalExecutionTargetFiles` and blocks when more than one candidate path is inferred.
- R484 produced a context package, but it used the prompt file as `source_file`; R485 correctly rejected that package as insufficient.
- R486 rebuilt the context package from the executor source anchor and preserved the real source file/function: `scripts/engines/LocalExecutionEngine.ps1` / `Invoke-LocalExecutionGenericBoundedTask`.
- R487 judged R486 provider-prompt ready but blocked on the missing engineering provider hook.
- R488 created a provider request with the correct source target and rejection policy.
- R489 produced a local deterministic provider stub, but no real provider response was available; the stub had blank `new_text` and did not count as implementation.
- R490 correctly rejected R489 before source mutation because `new_text` was blank, `old_text` was not found in current source, and the validation command was generic.
- R491 produced a corrected retry plan after the rejection.
- R492 retried the local stub and preserved honesty by not fabricating a behavior-changing patch, but it lost `target_file`, `old_text`, and `new_text`.
- R493 correctly rejected R492 before source mutation.

Validation:

- R482 `artifact_type=tod_readonly_evidence_comparison` with R480 prompt role evidence.
- R483 `artifact_type=tod_source_anchor_observation` and `source_function=Invoke-LocalExecutionGenericBoundedTask`.
- R485 `context_quality=insufficient_context_package` and `candidate_request_ready=false`.
- R486 `artifact_type=tod_engineering_context_package`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, and `source_function=Invoke-LocalExecutionGenericBoundedTask`.
- R487 `context_quality=provider_prompt_ready`, `candidate_request_ready=true`, and `provider_reachable=false`.
- R488 `artifact_type=tod_engineering_provider_request` and `provider_request_ready=true`.
- R490 `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- R491 `provider_request_ready_for_retry=true`.
- R493 `verdict=reject`, `verdict_reason_code=rejected_blank_old_text`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- All R482-R493 steps preserved `no_source_code_modified=true`.

Capability finding:

TOD traced the role-collapse failure from prompt roles to the generic bounded fallback source branch, rebuilt a provider-ready context package from real source evidence, produced a provider request, and safely rejected invalid provider candidates before mutation. This is meaningful progress in engineering supervision, evidence integrity, and recovery shape.

The capability is not yet independent engineering implementation. The remaining blocker is a real engineering provider/model invocation path that can produce parseable, exact-current, behavior-changing source candidates. Local deterministic stubs are useful for rejection training, but they cannot retire the borrowed code-delta synthesis capability.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Provider-readiness, candidate rejection, and recovery-shape discipline improved.
- Behavior-changing code-delta synthesis remains unproven.

Immediate next smallest training rung:

`TOD-LOCAL-ENGINEERING-PROVIDER-HOOK-V1`

Mission:

Build or connect a harmless local engineering provider interface that can consume a `tod_engineering_provider_request` and return a strict JSON candidate response without editing source. The first pass must run on a harmless training target and prove only provider invocation, schema validity, exact-current old text, non-empty behavior-changing new text, and a concrete validation command. Source mutation remains gated behind a separate TOD verdict.

## 2026-07-25 R494-R499 Local Provider Hook And Replan Input Roles

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_INVENTORY_R494.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_INVOCATION_R495.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_INVOCATION_VERDICT_R496.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_TIMEOUT_REPLAN_R497.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_REPLAN_INPUT_ROLE_REPAIR_R498.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_REPLAN_DIRECTIVE_REPAIR_R499.latest.json`

Observed result:

- R494 proved a configured local engineering provider hook exists: `tools/llama.cpp/llama-server.exe`, `models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf`, reachable endpoint `http://127.0.0.1:8008/v1/models`, and GPU availability. This was inventory only, not candidate generation.
- R495 executed the provider-candidate-invocation artifact lane and preserved source safety, but did not produce a usable model candidate. It recorded `provider_called=false`, `candidate_response_available=false`, blank `new_text`, and a timeout risk note.
- R496 correctly rejected R495 before source mutation with `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- R497 attempted a replan from the verdict alone but failed to read the provider request or candidate invocation, leaving `target_file`, `source_anchor_artifact`, and retry-readiness evidence empty.
- R498 repeated the failure because the prompt used custom labels instead of the local artifact-writer's canonical directive vocabulary.
- R499 repaired the input-role loss by using the supported directive form: `Input Artifact`, repeated `Supporting Artifact`, `Output Artifact`, and `Required Artifact Type`.

Validation:

- R494 `artifact_type=tod_local_engineering_provider_inventory`, `usable_provider_hook=true`, `real_provider_reachable=true`, `gpu_available=true`, and `no_source_code_modified=true`.
- R495 `artifact_type=tod_engineering_provider_candidate_invocation`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `old_text` captured, `new_text` blank, and `no_source_code_modified=true`.
- R496 rejected the invalid candidate before mutation.
- R497 and R498 honestly showed incomplete replan inputs instead of pretending retry readiness.
- R499 `artifact_type=tod_engineering_provider_candidate_replan`, `input_provider_request` preserved R488, `input_candidate_invocation` preserved R495, `provider_request_ready_for_retry=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `source_anchor_artifact` preserved R483, `required_fields_present=true`, `provider_request_read=true`, `candidate_invocation_read=true`, and `no_source_code_modified=true`.

Capability finding:

TOD can now inventory a local engineering provider hook, run the candidate invocation lane, reject unusable provider output before mutation, and repair provider-replan input roles when the canonical artifact directive vocabulary is used. The important learned distinction is that "provider reachable" is not the same as "candidate generated." TOD must preserve that distinction in future engineering loops.

The remaining blocker is still real provider candidate generation. The current local hook reached the model endpoint but did not return a usable candidate before timeout. This is model-utilization/runtime capability debt, not source-patch capability acquisition.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Provider inventory, candidate rejection, and replan input-role handling moved from borrowed/unclear to scaffolded pass.
- Behavior-changing model-assisted code-delta synthesis remains borrowed.

Immediate next smallest training rung:

`TOD-LOCAL-PROVIDER-RAW-RESPONSE-PROBE-V1`

Mission:

Before asking the provider for a behavior-changing source patch, TOD should run a tiny read-only raw-response probe against the configured local provider. The probe must ask for a short strict JSON response unrelated to source editing, capture request parameters, timeout, raw response, parse result, model name, and latency, and publish an artifact. Only after raw response reliability is proven should TOD retry code-candidate generation.

## 2026-07-25 R500-R506 Provider Health Versus Engineering Candidate Failure

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_PROVIDER_RAW_RESPONSE_PROBE_EVIDENCE_R500.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_PROVIDER_HEALTH_VS_CANDIDATE_FAILURE_COMPARISON_R501.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_TIMEOUT_SOURCE_ANCHOR_R503.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_REPLAN_INVOCATION_R505.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_FALLBACK_ROLE_COLLAPSE_PROVIDER_REPLAN_INVOCATION_VERDICT_R506.latest.json`

Observed result:

- Direct validation with `scripts/Invoke-TODConversationProvider.ps1 -Action status -AsJson` proved the local provider was reachable at `http://localhost:8008/v1/chat/completions` with model `tod-local-chat`.
- Direct validation with `scripts/Invoke-TODConversationProvider.ps1 -Action chat` proved the provider could return the tiny strict JSON response `{"probe":"ok"}`.
- R500 failed as an evidence comparison because the comparison artifact lane requires explicit left/right roles, not generic input/supporting evidence alone.
- R501 used the correct comparison directives and completed, but it only found the first mechanical artifact-type difference. This is useful contract proof but not sufficient semantic diagnosis.
- R502 failed to enter the source-anchor lane because the prompt used `Inspect Source File` instead of the supported `Source File` / `Anchor Pattern` contract.
- R503 used the source-anchor contract correctly and captured the `tod_engineering_provider_candidate_invocation` branch in `Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R504 attempted the replan invocation with the wrong task category and was blocked by bounded-edit target ambiguity.
- R505 retried in read-only inspection mode and produced a provider invocation artifact. It still failed to generate a candidate: `provider_called=false`, `candidate_response_available=false`, blank `new_text`, `old_text_length=8666`, and risk note `(500) Internal Server Error`.
- R506 correctly rejected R505 before source mutation.

Validation:

- Provider status probe returned `reachable=true`.
- Provider chat probe returned `reply_text={"probe":"ok"}`.
- R501 `status=completed` and `validation.no_code_changes=true`.
- R503 `artifact_type=tod_source_anchor_observation`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`, `anchor_found=true`, and `exact_text_nonempty=true`.
- R505 `artifact_type=tod_engineering_provider_candidate_invocation`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `old_text_length=8666`, `new_text_length=0`, `risk_notes=(500) Internal Server Error`, and `no_source_code_modified=true`.
- R506 `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, and `no_source_code_modified=true`.

Capability finding:

TOD can distinguish local provider availability from engineering-candidate generation success. A live provider endpoint and a successful tiny JSON chat response do not prove that a long source-anchor code-candidate request will succeed. TOD also learned two more lane-contract details: evidence comparison needs explicit left/right roles, and source-anchor observation needs `Source File` plus `Anchor Pattern`.

The current blocker is no longer "missing provider." It is provider prompt/source-anchor suitability for code-candidate generation. The candidate prompt is carrying an 8,666-character source anchor into a 900-token, 60-second local provider call and receiving HTTP 500 or blank output.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Local provider health validation moved to scaffolded pass.
- Candidate verdict safety remains scaffolded pass.
- Model-assisted behavior-changing code-delta synthesis remains borrowed.

Immediate next smallest training rung:

`TOD-PROVIDER-PROMPT-BUDGET-MINIMIZATION-V1`

Mission:

TOD should learn to reduce provider candidate prompts before retrying code synthesis. The next pass should create a small source-anchor fixture or identify a compact current-code anchor under 1,500 characters, build a provider request from that compact anchor, prove the provider can return strict JSON with non-empty `old_text`, non-empty behavior-changing `new_text`, and a concrete validation command, and still require a separate verdict before mutation. No source mutation should occur during the prompt-budget exercise.

## 2026-07-25 R507-R518B Provider Prompt Budget And Verdict Boundary

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_COMPACT_SOURCE_ANCHOR_R507.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_COMPACT_CONTEXT_R508.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_COMPACT_MODEL_JUDGMENT_R509.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_COMPACT_PROVIDER_REQUEST_R510.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_COMPACT_PROVIDER_INVOCATION_R511B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_COMPACT_PROVIDER_VERDICT_R512B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_EXACT_ANCHOR_REPLAN_R513B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_EXACT_ANCHOR_INVOCATION_R514.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_BUDGET_EXACT_ANCHOR_VERDICT_R515.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_SOURCE_ANCHOR_R516.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_DELTA_PROPOSAL_R517B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_NEWTEXT_SYNTHESIS_R518B.latest.json`

Observed result:

- R507 captured a compact provider utility source anchor in `scripts/Invoke-TODConversationProvider.ps1` for `Get-ReplyTextFromResponse`.
- R508 built a provider context package around that compact anchor.
- R509 judged the compact context provider-ready for candidate generation.
- R510 produced a provider request for `scripts/Invoke-TODConversationProvider.ps1`.
- R511 initially drifted into stale source-anchor objective context, so it produced the wrong artifact type. R511B fixed this by using a fresh objective ID and reached the provider invocation lane.
- R511B called the local provider and received a parsed candidate response, but the provider returned no behavior delta: `old_text` and `new_text` were both 893 characters.
- R512B correctly rejected R511B before mutation.
- R513 initially failed because a recovery task was materialized as implementation and the bounded-edit gate treated all artifact paths as target candidates. R513B corrected the task mode to read-only and produced a valid provider replan.
- R514 applied the replan and produced the first useful compact local-provider candidate: `provider_called=true`, `candidate_response_available=true`, `old_text_length=893`, and `new_text_length=961`.
- R515 rejected R514 before mutation because `old_text` was not found in current source.
- Direct validation showed this was a line-ending boundary, not semantic mismatch: raw CRLF containment failed, while LF-normalized containment passed for both the source-anchor artifact and the provider candidate.
- R516 captured the provider verdict source branch that performs the raw containment check.
- R517 drifted back to stale source-anchor context; R517B used a fresh objective ID and reached the source-anchor delta proposal lane.
- R517B correctly blocked with `autonomous_candidate_new_text_missing` instead of fabricating a patch.
- R518 initially failed to read the supporting source-anchor path because the synthesis lane only discovers standalone artifact paths. R518B used standalone artifact-path lines and produced a clean synthesis blocker with `source_anchor_valid=true`, `prior_delta_available=true`, `old_text_length=1671`, `new_text_length=0`, and `independent_credit_requested=false`.

Validation:

- R511B `artifact_type=tod_engineering_provider_candidate_invocation`, `provider_called=true`, `candidate_response_available=true`, `raw_provider_response_len=2187`, `target_file=scripts/Invoke-TODConversationProvider.ps1`, and `no_source_code_modified=true`.
- R512B `artifact_type=tod_engineering_provider_candidate_verdict`, `verdict=reject`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- R513B `artifact_type=tod_engineering_provider_candidate_replan`, preserved verdict/request/invocation lineage, `provider_request_ready_for_retry=true`, `target_file=scripts/Invoke-TODConversationProvider.ps1`, and `source_anchor_artifact` preserved R507.
- R514 `artifact_type=tod_engineering_provider_candidate_invocation`, `replan_instruction_applied=true`, `provider_called=true`, `candidate_response_available=true`, `new_text_length=961`, and `no_source_code_modified=true`.
- R515 rejected the candidate before mutation.
- Normalized containment check: source contains R507/R514 old text after CRLF-to-LF normalization, but not with raw CRLF containment.
- R516 `artifact_type=tod_source_anchor_observation`, `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`, `anchor_found=true`.
- R517B `artifact_type=tod_source_anchor_delta_proposal`, `status=blocked`, `reason_code=autonomous_candidate_new_text_missing`, and `no_source_code_modified=true`.
- R518B `artifact_type=tod_autonomous_meaningful_newtext_synthesis`, `status=blocked`, `listed_input_count=2`, `source_anchor_valid=true`, `prior_delta_available=true`, `new_text_nonempty=false`, and `no_source_code_modified=true`.

Capability finding:

TOD can now drive a compact local-provider candidate loop far enough to call the local model, capture real candidate output, reject unsafe candidates before mutation, replan from a rejection, retry with a revised instruction, and identify a verdict-boundary defect without modifying source code. This is meaningful model-utilization and engineering-supervision progress.

TOD still cannot independently synthesize safe, behavior-changing `new_text` from a source anchor. When asked for a source-anchor delta proposal, the lane correctly blocks rather than inventing a patch. That is honest, but it means code-delta synthesis remains borrowed.

New process lessons:

- Use fresh objective IDs when changing artifact lanes; stale objective context can override the current task's required artifact type.
- Read-only recovery artifacts must stay in read-only task mode, or bounded-edit materialization will treat evidence paths as target-file candidates.
- The autonomous synthesis lane discovers evidence only when artifact paths appear alone on their own lines.
- Provider verdict checks need line-ending-aware source containment evidence before exact-source-preservation can be judged fairly.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Local provider invocation moved from "hook exists" to scaffolded real provider call.
- Provider-candidate acceptance/rejection remains scaffolded pass.
- Meaningful code-delta synthesis remains borrowed.

Immediate next smallest training rung:

`TOD-VERDICT-LINE-ENDING-NORMALIZATION-PACKET-V1`

Mission:

TOD should produce, without Codex-supplied `new_text`, a bounded packet that makes the provider verdict old-text source check line-ending-aware while preserving strict safety. The packet must be grounded in R516, explain why raw containment and normalized containment are both recorded, preserve rejection for blank old text, wrong target, marker-only, no-delta, and generic validation, and include a focused validation command. If TOD cannot synthesize the patch, it should publish the blocker as borrowed code-delta synthesis rather than claiming progress.

## 2026-07-25 R519 Verdict Packet Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_PACKET_ATTEMPT_R519.latest.json`

Observed result:

- TOD attempted the verdict-normalization packet through the autonomous meaningful-new-text synthesis lane.
- The lane received the source-anchor artifact from R516 and preserved `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- The lane produced `old_text_length=1671`.
- The lane produced `new_text_length=0`.
- The lane did not request independent credit.
- No source code was modified.

Validation:

- `artifact_type=tod_autonomous_meaningful_newtext_synthesis`.
- `status=blocked`.
- `reason_code=autonomous_meaningful_new_text_synthesis_missing`.
- `smallest_next_rung=TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`.
- `independent_credit_requested=false`.
- `no_source_code_modified=true`.

Capability finding:

TOD can now preserve the source anchor and articulate the missing capability, but it still cannot independently materialize a safe behavior-changing patch from the anchor. That is the central borrowed engineering capability still blocking retirement.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Verdict-normalization repair remains a valid target, but it requires a learned engineering-model utilization path or another independent new-text synthesis mechanism.

Immediate next smallest training rung:

`TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`

Mission:

TOD should use the local engineering provider as a supervised candidate generator for the R516 verdict-normalization source anchor. The provider may propose candidate text, but TOD must still reject unsafe, non-exact, no-delta, or generic-validation output before mutation. The goal is not to patch immediately; the goal is to prove TOD can turn its own source-anchor blocker into a model-assisted candidate request, capture the candidate, evaluate it, and either reject it or produce a bounded packet with source mutation still gated separately.

## 2026-07-25 R520-R523 Local Provider Supervision On Verdict Normalization

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_MODEL_CONTEXT_R520.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_MODEL_JUDGMENT_R521A.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_PROVIDER_REQUEST_R521B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_PROVIDER_INVOCATION_R522.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_PROVIDER_VERDICT_R523.latest.json`

Observed result:

- R520 built a context package from the R516 verdict source anchor and the R519 synthesis blocker.
- R521 initially produced a provider request that was not ready because the provider-request lane requires a `tod_model_utilization_engineering_judgment`, not the source anchor as supporting evidence.
- R521A produced the missing model-utilization judgment and marked `candidate_request_ready=true`.
- R521B rebuilt the provider request with the correct supporting judgment and reached `provider_request_ready=true`.
- R522 invoked the local engineering provider and captured a real provider response.
- R522 produced an unsafe candidate: `old_text_length=74`, `new_text_length=0`, generic validation text, and risk notes explaining no behavior-changing patch was produced.
- R523 correctly rejected R522 before source mutation with `verdict_reason_code=rejected_blank_new_text`.

Validation:

- R520 `artifact_type=tod_engineering_context_package`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`, and source anchor preserved R516.
- R521A `artifact_type=tod_model_utilization_engineering_judgment`, `source_anchor_artifact` preserved R516, `context_quality=provider_prompt_ready`, and `candidate_request_ready=true`.
- R521B `artifact_type=tod_engineering_provider_request`, `provider_request_ready=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, and source anchor included.
- R522 `artifact_type=tod_engineering_provider_candidate_invocation`, `provider_called=true`, `candidate_response_available=true`, and `no_source_code_modified=true`.
- R523 `artifact_type=tod_engineering_provider_candidate_verdict`, `verdict=reject`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, and `no_source_code_modified=true`.

Capability finding:

TOD can now run a full supervised local-provider loop from its own source-anchor blocker: context package, model-utilization judgment, provider request, provider invocation, and verdict rejection. This is a meaningful reduction in borrowed runtime orchestration because Codex did not write a patch or manually fabricate candidate text.

The local provider still failed at the engineering task. It returned blank `new_text`, so TOD correctly rejected it. This means the engineering supervision loop improved, but behavior-changing code-delta synthesis remains borrowed.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization orchestration improved to scaffolded/guided pass.
- Provider candidate quality remains insufficient for source mutation.
- Code-delta synthesis remains borrowed.

Immediate next smallest training rung:

`TOD-ENGINEERING-CANDIDATE-QUALITY-FILTER-V1`

Mission:

TOD should formalize the provider candidate quality filters proven in R511B-R523: reject blank `new_text`, reject no-delta, reject non-current `old_text`, reject generic validation commands, reject marker/comment/whitespace-only edits, and preserve source mutation behind a separate gate. This does not retire code synthesis, but it makes TOD a safer engineering supervisor before the next provider/model upgrade.

## 2026-07-25 R524-R525 Candidate Quality Filter Episode And Examiner Verdict

Fresh evidence:

- `runtime/tod_engineering_corpus/TOD_ENGINEERING_CANDIDATE_QUALITY_FILTER_R524.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CANDIDATE_QUALITY_FILTER_EXAMINER_R525.latest.json`

Observed result:

- R524 converted the R523 provider-candidate rejection into a durable engineering episode card.
- R524 preserved the key evidence artifacts from the provider invocation and verdict.
- R525 examined the episode card through the engineering episode quality lane.
- R525 accepted the episode as useful runtime-support memory.
- R525 explicitly rejected engineering credit and borrowed-capability reduction.

Validation:

- R524 `artifact_type=tod_engineering_episode_card`.
- R524 `source_artifact=runtime_remote_training/read_only_audit_artifacts/TOD_VERDICT_LINE_ENDING_NORMALIZATION_PROVIDER_VERDICT_R523.latest.json`.
- R524 evidence includes R522 and R523.
- R524 `no_source_edits=true` and `independent_credit_requested=false`.
- R525 `artifact_type=tod_engineering_episode_quality_examiner_verdict`.
- R525 `training_usefulness=accept_runtime_support_only`.
- R525 `engineering_credit_allowed=false`.
- R525 `runtime_support_credit_allowed=true`.
- R525 `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can preserve provider-candidate quality failures as durable training memory and can run the examiner lane without claiming false progress. This is useful governance and runtime-support maturity, not independent engineering maturity.

The examiner identified the same training boundary: the next proof must be a fresh engineering episode where TOD inspects source, diagnoses behavior, proposes a bounded change, validates it, and publishes evidence.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Candidate quality filtering is accepted as runtime-support memory only.
- The system correctly avoided artifact-confetti progress inflation.

Immediate next smallest training rung:

`TOD-FRESH-ENGINEERING-EPISODE-INDEPENDENT-DEMO-V1`

Mission:

TOD should select a fresh, harmless engineering target and complete an engineering episode from current evidence: inspect source code, identify a behavioral issue or bounded improvement, propose one source-grounded change, validate it, publish an episode card, and pass examiner review. Runtime routing, provider inventory, and artifact-lane maintenance do not count for this rung.

## 2026-07-25 R526-R530 Fresh Source-Anchor Engineering Demo Blocker

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_SOURCE_ANCHOR_R526.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_DELTA_PROPOSAL_R527.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_NEWTEXT_SYNTHESIS_R528.latest.json`
- `runtime/tod_engineering_corpus/TOD_FRESH_ENGINEERING_EPISODE_BLOCKER_R529.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_EXAMINER_R530.latest.json`

Observed result:

- R526 inspected `scripts/engines/LocalExecutionEngine.ps1` and captured a fresh exact source anchor for `Test-LocalExecutionSourceAnchorObservationTask`.
- R527 used the R526 source anchor as input and correctly identified `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R527 blocked with `reason_code=autonomous_candidate_new_text_missing`.
- R528 attempted the next synthesis rung and blocked with `reason_code=autonomous_meaningful_new_text_synthesis_missing`.
- R529 converted the blocker into a durable episode card.
- R530 examined the episode and accepted it as runtime-support memory only.

Validation:

- R526 `artifact_type=tod_source_anchor_observation`, `matched=true`, `exact_text_nonempty=true`, `source_function=Test-LocalExecutionSourceAnchorObservationTask`, and `no_code_changes=true`.
- R527 `artifact_type=tod_source_anchor_delta_proposal`, `source_anchor_valid=true`, `candidate_new_text=""`, and `no_source_code_modified=true`.
- R528 `artifact_type=tod_autonomous_meaningful_newtext_synthesis`, `source_anchor_valid=true`, `old_text_nonempty=true`, `new_text_nonempty=false`, and `independent_credit_requested=false`.
- R529 `artifact_type=tod_engineering_episode_card`, `source_artifact_type=tod_autonomous_meaningful_newtext_synthesis`, `debt_category=runtime_plumbing`, and `no_source_edits=true`.
- R530 `artifact_type=tod_engineering_episode_quality_examiner_verdict`, `engineering_credit_allowed=false`, `runtime_support_credit_allowed=true`, and `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can independently preserve a fresh current-code source anchor and route that evidence through the delta, synthesis, episode, and examiner lanes. That is useful source-evidence handling and blocker honesty.

TOD still cannot independently synthesize safe behavior-changing `new_text` from a source anchor. The Examiner correctly refused to treat this as an engineering implementation. This is the exact point where runtime plumbing ends and engineering intelligence must begin.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Source-anchor evidence handling remains scaffolded/guided support.
- Autonomous code-delta synthesis remains borrowed.

Immediate next smallest training rung:

`TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`

Mission:

TOD should use a real engineering model/provider loop or a learned candidate-generation path to propose non-empty, behavior-changing `new_text` from a fresh source anchor, then reject or accept that candidate using the existing quality filter. The goal is not to patch source immediately; the goal is to produce and judge one source-grounded candidate without Codex writing the candidate text.

## 2026-07-25 R531-R536 Fresh Local Provider Loop And Candidate Rejection

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_MODEL_CONTEXT_R531.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_MODEL_JUDGMENT_R532.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_REQUEST_R533.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_INVENTORY_R534.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_INVOCATION_R535.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_VERDICT_R536.latest.json`

Observed result:

- R531 built a provider-ready engineering context package from the fresh R526 source anchor.
- R532 classified the context as model/provider-request ready.
- R533 built the provider request.
- R534 found a reachable local provider endpoint at `http://127.0.0.1:8008/v1/models` with model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- R535 called the provider and received a candidate response.
- R535 candidate response still had `new_text=""`.
- R536 correctly rejected the candidate before source mutation with `verdict_reason_code=rejected_blank_new_text`.

Validation:

- R531 `artifact_type=tod_engineering_context_package`, `source_file=scripts/engines/LocalExecutionEngine.ps1`, and source anchor preserved R526.
- R532 `artifact_type=tod_model_utilization_engineering_judgment` and candidate request readiness was available for R533.
- R533 `artifact_type=tod_engineering_provider_request` and `provider_request_ready=true`.
- R534 `artifact_type=tod_local_engineering_provider_inventory`, `usable_provider_hook=true`, and provider endpoint reachable.
- R535 `artifact_type=tod_engineering_provider_candidate_invocation`, `provider_called=true`, `candidate_response_available=true`, and `no_source_code_modified=true`.
- R536 `artifact_type=tod_engineering_provider_candidate_verdict`, `verdict=reject`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, and `no_source_code_modified=true`.

Capability finding:

TOD can now use the local engineering provider loop on a fresh source-anchor task: context packaging, readiness judgment, provider request, provider inventory, provider invocation, and verdict gating. This is a real improvement in model-utilization supervision.

The provider still did not produce behavior-changing code. TOD rejected the blank candidate correctly. This means TOD is getting better at supervising a model, but has not yet demonstrated independent engineering implementation.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved from scaffolded/guided to provider-loop proven for this class.
- Code-delta generation remains borrowed or provider-deficient.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1`

Mission:

TOD should take the R536 rejected candidate, produce a revised provider instruction that explains why blank `new_text` failed, request one smaller behavior-preserving but observable source change, invoke the provider again, and gate the result. The success condition is not source mutation; it is a non-empty, source-grounded candidate that survives TOD's quality filters or a sharper rejection that names the remaining model limitation.

## 2026-07-25 R537B-R540B Provider Replan And Retry Verdict

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_REPLAN_R537B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_RETRY_REQUEST_R538B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_RETRY_INVOCATION_R539B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_PROVIDER_RETRY_VERDICT_R540B.latest.json`

Observed result:

- The first R537 attempt failed because the task was incorrectly wrapped as `inspection_only` even though it requested an artifact write.
- The corrected R537B attempt used the artifact-write lane and completed.
- R537B produced a revised provider instruction after the R536 blank-candidate rejection.
- R538B created a retry provider request from the replan.
- R539B invoked the local provider again and captured a candidate response.
- R540B rejected the retry candidate before source mutation because `new_text` remained blank.

Validation:

- R537B `artifact_type=tod_engineering_provider_candidate_replan`, `provider_request_ready_for_retry=true`, `prior_rejection_reason_code=rejected_blank_new_text`, and `no_source_code_modified=true`.
- R538B `artifact_type=tod_engineering_provider_request` and was generated from the replan.
- R539B `artifact_type=tod_engineering_provider_candidate_invocation`, `provider_called=true`, `candidate_response_available=true`, and `no_source_code_modified=true`.
- R540B `artifact_type=tod_engineering_provider_candidate_verdict`, `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`.
- All four R537B-R540B evidence artifacts parse as JSON.

Capability finding:

TOD can now recover from a rejected local-provider candidate by materializing a replan, creating a retry request, invoking the provider again, and gating the retry result before source mutation. That is useful model-utilization and recovery supervision.

TOD still cannot produce a non-empty behavior-changing source delta through the current provider path. The correct next training move is not another routing wrapper; it is a smaller engineering episode where the model or TOD can produce one observable, source-grounded `new_text` candidate.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Provider-rejection recovery is now demonstrated for this lane.
- Independent source-delta generation remains borrowed/provider-deficient.

Immediate next smallest training rung:

`TOD-SMALL-OBSERVABLE-SOURCE-DELTA-CANDIDATE-V1`

Mission:

TOD should select one harmless engineering target where the desired behavior change is tiny and observable, then produce a non-empty source-grounded candidate through the provider/supervision path. TOD must reject no-op, marker-only, comment-only, artifact-only, or generic validation candidates. Source mutation remains forbidden until the candidate survives the gate.

## 2026-07-25 R541-R542 Provider Parse-Salvage Debt Episode

Fresh evidence:

- `runtime/tod_engineering_corpus/TOD_PROVIDER_PARSE_SALVAGE_DEBT_R541.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PARSE_SALVAGE_DEBT_EXAMINER_R542.latest.json`

Observed result:

- Inspection of R539B showed the raw provider response did include `target_file`, `old_text`, `new_text`, `validation_command`, and `risk_notes`.
- The provider response was malformed JSON because regex/source text contained invalid escape sequences for JSON parsing.
- TOD's parsed candidate fields collapsed to blank values, so R540B reported `rejected_blank_new_text`.
- R541 recorded the verdict as a durable episode.
- R542 accepted the episode as runtime-support memory only.

Validation:

- R539B `provider_called=true` and `candidate_response_available=true`.
- R539B `raw_provider_response` contains a candidate-shaped JSON object, but `parsed_candidate_json` is empty.
- R539B `risk_notes` includes `candidate_json_parse_failed`.
- R540B `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, and `rejected_before_source_mutation=true`.
- R542 `engineering_credit_allowed=false`, `runtime_support_credit_allowed=true`, and `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can preserve the provider-parse failure as training memory and Examiner can prevent it from being counted as engineering progress.

TOD still needs a better learned distinction between:

- no provider candidate,
- provider candidate present but malformed,
- provider candidate parsed but unsafe,
- provider candidate parsed and potentially valid.

The R541 episode writer also generalized the problem text instead of preserving the precise prompt diagnosis, so future corpus episodes need stronger problem-statement preservation before they become high-quality engineering training data.

Borrowed-capability impact:

- No borrowed engineering capability retired.
- Borrowed ratio remains 78.4%.
- Provider parse-salvage is now identified as separate model-utilization debt.

Immediate next smallest training rung:

`TOD-SMALL-OBSERVABLE-SOURCE-DELTA-CANDIDATE-V1`

Mission:

TOD should select a source anchor that avoids regex-heavy text and ask the provider for one tiny observable candidate. The goal is to prove whether the local provider can produce parseable non-empty `new_text` when the source anchor is simpler. If it still fails, record the limitation as provider-output reliability debt rather than TOD engineering independence.

## 2026-07-25 R543-R558 Small Observable Candidate Generation

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DELTA_SOURCE_ANCHOR_R543.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DELTA_CONTEXT_R544.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DELTA_JUDGMENT_R545.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DELTA_PROVIDER_REQUEST_R546.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DELTA_PROVIDER_INVOCATION_R547.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SMALL_DELTA_PROVIDER_VERDICT_R548.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_SOURCE_ANCHOR_R549.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_CONTEXT_R550.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_JUDGMENT_R551.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_REQUEST_R552.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_INVOCATION_R553.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_VERDICT_R554.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_REPLAN_R555.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_RETRY_REQUEST_R556.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_RETRY_INVOCATION_R557.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_PROVIDER_RETRY_VERDICT_R558.latest.json`

Observed result:

- R543-R548 tried a simple Python helper target, `_percent`, but the context/judgment lane required `source_function`.
- The source-anchor observer matched Python source but did not infer `source_function`, so R545 set `candidate_request_ready=false`; provider invocation did not run.
- R549-R554 switched to a tiny PowerShell helper, `Get-UtcNow`, which satisfied source-function inference.
- R551 marked the context candidate-request ready.
- R552 built a provider request.
- R553 called the provider and received parseable JSON, but `new_text` was blank.
- R554 correctly rejected the blank candidate.
- R555-R558 replanned and retried the tiny PowerShell candidate.
- R557 produced parseable non-empty `new_text`.
- R558 accepted the candidate for future source mutation.

Validation:

- R549 `matched=true`, `source_file=scripts/TOD.ps1`, and `source_function=Get-UtcNow`.
- R551 `candidate_request_ready=true`.
- R552 `provider_request_ready=true`.
- R557 `provider_called=true`, `candidate_response_available=true`, `parsed_candidate_json` has `target_file`, `old_text`, `new_text`, `validation_command`, and `risk_notes`.
- R557 `new_text` length is 104.
- R558 `verdict=accept`, `accepted_for_source_mutation=true`, and `no_source_code_modified=true`.
- Independent check of R557/R558 validation command failed in a clean shell because `Get-UtcNow` was not loaded before invocation.

Capability finding:

TOD can now complete a full tiny-target provider loop through replan and retry:

source anchor -> context package -> readiness judgment -> provider request -> provider invocation -> verdict gate -> accepted candidate.

This is the first demonstrated non-empty, parseable, source-grounded candidate through the local provider supervision path in this training run.

However, the accepted candidate is not implementation-ready. The verdict gate accepted a validation command that looks specific but fails when executed from a clean shell. That means TOD's next blocker has moved from candidate generation to validation-command execution quality.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired yet.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improves: TOD can obtain and gate a non-empty provider candidate on a tiny PowerShell target.
- Source mutation and validation-backed implementation remain borrowed until TOD proves the candidate with an executable validation command and applies a safe bounded change independently.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-VALIDATION-COMMAND-EXECUTION-GATE-V1`

Mission:

Before any accepted provider candidate can become a source mutation packet, TOD must execute or dry-run the candidate validation command in the same environment assumptions the command declares. A validation command that fails to load required functions, references missing files, or only parses without proving the changed behavior must be rejected or repaired before source mutation.

## 2026-07-25 R559 Validation Command Execution Check

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_VALIDATION_COMMAND_EXECUTION_CHECK_R559.latest.json`

Observed result:

- R558 accepted the tiny PowerShell provider candidate for future source mutation.
- R559 executed the candidate validation command in a clean PowerShell process from the repo root.
- The command failed with exit code 1 before it could load or exercise `scripts/TOD.ps1::Get-UtcNow`.
- The immediate failure was PowerShell syntax: `Get-UtcNow()` is not valid function invocation syntax for this command shape.

Validation:

- R559 `prior_accepted_for_source_mutation=true`.
- R559 `validation_command_exit_zero=false`.
- R559 `validation_command_is_executable_syntax=false`.
- R559 `validation_command_proves_changed_behavior=false`.
- R559 `verdict=validation_command_rejected_before_source_mutation`.
- R559 `no_source_code_modified=true`.

Capability finding:

TOD's provider-candidate verdict gate is still too shallow. It can reject blank, no-op, stale-anchor, wrong-target, marker-only, and generic-validation candidates, but it does not yet prove that a specific-looking validation command actually executes.

This means R558 should not advance to source mutation. The next training target is validation-command repair, not patch application.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision remains improved, but implementation independence is still blocked by validation-command execution quality.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-VALIDATION-COMMAND-REPAIR-V1`

Mission:

TOD should take the accepted R558 candidate and failed R559 validation evidence, repair only the validation command so it can run in a clean process and prove the target behavior, then rerun the command before any source mutation. If the behavior cannot be proven without changing the source first, TOD must publish that exact blocker instead of applying the candidate.

## 2026-07-25 R560 Borrowed Validation Command Repair Reference

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_TINY_PS_VALIDATION_COMMAND_REPAIR_REFERENCE_R560.latest.json`

Observed result:

- Codex produced a validation-only repair reference after R559.
- The repaired command dot-sources `scripts/TOD.ps1` with the harmless `get-version` action.
- The repaired command invokes `Get-UtcNow` using legal PowerShell function syntax.
- The repaired command checks that the returned timestamp contains fractional seconds and ends with `Z`.
- The repaired command exited zero and printed `validated`.

Validation:

- R560 `loads_target_function=true`.
- R560 `uses_legal_powershell_invocation=true`.
- R560 `exits_zero=true`.
- R560 `proves_timestamp_shape=true`.
- R560 `no_source_code_modified=true`.

Capability finding:

The correct repair pattern is now visible, but this is borrowed capability. TOD did not independently synthesize the repaired validation command.

The next proof must require TOD to perform the same validation-command repair on a fresh accepted provider candidate or on this candidate without Codex providing the repaired command.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- The validation-command repair pattern is documented as a reference example only.

Immediate next smallest training rung:

`TOD-INDEPENDENT-VALIDATION-COMMAND-REPAIR-DEMO-V1`

Mission:

TOD must inspect a failed validation-command execution artifact, infer the missing load/invocation/proof requirements, synthesize its own executable validation command, run it, and publish pass/fail evidence without Codex supplying the repaired command.

## 2026-07-25 R561 Independent Repair Demo Attempt Blocked Before Execution

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_INDEPENDENT_VALIDATION_COMMAND_REPAIR_DEMO_R561.blocker.json`

Observed result:

- Codex submitted `TOD-INDEPENDENT-VALIDATION-COMMAND-REPAIR-DEMO-R561` to TOD as a direct task.
- TOD accepted the task request, but no independent repair artifact was created.
- The request was stored as `task_mode=implementation`, `bounded_edit_mode=true`, and `target_file=""`.
- The materializer treated the task as a bounded edit instead of a read-only artifact-write repair demo.
- The task contained input, supporting, and output artifact paths; TOD required `target_file_exactly_one` instead of preserving their roles.
- The active execution lane was not mutated.

Validation:

- R561 blocker `tod_attempted_direct_task=true`.
- R561 blocker `output_artifact_created=false`.
- R561 blocker `artifact_write_role_preserved=false`.
- R561 blocker `active_lane_preserved=true`.

Capability finding:

TOD could not yet start the independent validation-command repair because the direct-chat materialization path downgraded the task into the wrong shape. This is not an engineering failure inside the repair itself; it is a task-mode and artifact-role preservation failure before the work began.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- The next blocker is narrower than candidate generation: TOD must preserve artifact-write input/support/output roles when a task is not a source-code mutation.

Immediate next smallest training rung:

`TOD-ARTIFACT-WRITE-ROLE-PRESERVATION-FOR-VALIDATION-REPAIR-V1`

Mission:

TOD must accept a validation-command repair demo as an artifact-write/read-only task, preserve input artifact, supporting artifact, and output artifact roles, avoid bounded-edit target discovery, and publish a blocker or repair artifact without mutating the active execution lane.

## 2026-07-25 R562 Artifact-Write Role Preservation Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_ARTIFACT_WRITE_ROLE_PRESERVATION_R562.blocker.json`

Observed result:

- Codex resubmitted the task with explicit `-Type validation`, `-TaskCategory artifact_write`, and `-EditMode artifact_write`.
- TOD preserved `task_mode=validation`.
- TOD preserved `bounded_edit_mode=false`.
- TOD preserved `validation_only=true`.
- The active execution lane remained untouched.
- No requested R562 artifact was created.
- The materializer still collapsed the input artifact, supporting artifact, and output artifact paths into `target_file_candidates`.
- Materialization stopped with `target_file_exactly_one`.

Validation:

- R562 blocker `task_mode=validation`.
- R562 blocker `bounded_edit_mode=false`.
- R562 blocker `active_lane_mutated=false`.
- R562 blocker `output_artifact_created=false`.
- R562 blocker `materialization_reason_code=blocked_missing_bounded_edit_mode`.

Capability finding:

TOD is now preserving the broad validation/read-only mode at intake, but not the artifact path roles inside materialization. A read-only artifact-write task can legitimately contain multiple file paths without having multiple source edit targets. The materializer must classify those paths as input, support, and output evidence before applying target-file cardinality rules.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support progress improved, but engineering independence is still blocked before TOD can attempt the validation-command repair.

Immediate next smallest training rung:

`TOD-ARTIFACT-ROLE-PRESERVATION-MATERIALIZER-V1`

Mission:

TOD must preserve input artifact, supporting artifact, and output artifact as separate materialization roles for read-only artifact-write tasks. It must not require exactly one source-code `target_file` unless the task is actually a bounded source edit. Success is a produced blocker or evidence artifact that proves the role classification without mutating the active lane.

## 2026-07-25 R563 Supported Read-Only Artifact Lane Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_ARTIFACT_ROLE_PRESERVATION_R563.latest.json`

Observed result:

- TOD accepted the task as `task_mode=validation`.
- TOD preserved `bounded_edit_mode=false`.
- The materializer returned `supported_read_only_artifact_write_contract_valid`.
- The active execution lane remained untouched.
- TOD produced a real read-only evidence artifact.
- The artifact status was `blocked`.
- The artifact read the first input evidence object, but did not read the comparison pair.
- The selected lane expected `left_artifact` and `right_artifact`, while the task wording supplied `Input Artifact` and `Supporting Artifact`.

Validation:

- R563 artifact `artifact_type=tod_readonly_evidence_comparison`.
- R563 artifact `input_read=true`.
- R563 artifact `left_artifact_read=false`.
- R563 artifact `right_artifact_read=false`.
- R563 artifact `no_code_changes=true`.
- R563 artifact `blocker.reason_code=comparison_paths_missing`.

Capability finding:

TOD can now route a supported read-only artifact-write task through materialization without demanding a source-code `target_file`. The next failure is smaller: TOD must use the selected evidence lane's required vocabulary and preserve the comparison pair as `left_artifact` and `right_artifact`, not generic input/support evidence.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support progress improved: supported read-only artifact-write routing is demonstrated.
- Evidence-lane contract use remains blocked.

Immediate next smallest training rung:

`TOD-READONLY-EVIDENCE-COMPARISON-PAIR-BINDING-V1`

Mission:

TOD must run the same comparison using the selected lane's native labels: `Left Artifact`, `Right Artifact`, and `Output Artifact`. It must read both blocker artifacts, identify the first material difference between R561 and R562, publish the comparison, and leave source files and the active execution lane untouched.

## 2026-07-25 R564/R565/R566 Evidence Comparison Pair Binding

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_EVIDENCE_COMPARISON_R564.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_EVIDENCE_COMPARISON_R565.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_EVIDENCE_COMPARISON_R566.latest.json`

Observed result:

- R564 used `Left Artifact` and `Right Artifact`; materialization passed, but the executor did not bind those labels into the comparison pair.
- R565 used `Package Path` and `Inspect Source File`, matching the tested executor contract, but the directives were embedded mid-line in the generated prompt package; the executor still did not bind the pair.
- R566 used newline-separated line-start directives for `Package Path`, `Inspect Source File`, `Input Artifact`, `Output Artifact`, and `Required Artifact Type`.
- R566 completed.
- R566 read both comparison packages.
- R566 published `first_material_difference=line_4`.
- R566 recorded `left_artifact_read=true`, `right_artifact_read=true`, and `no_code_changes=true`.

Validation:

- R566 artifact `status=completed`.
- R566 artifact `left_artifact=tod/out/prompts/TOD-INDEPENDENT-VALIDATION-COMMAND-REPAIR-DEMO-R561.md`.
- R566 artifact `right_artifact=tod/out/prompts/TOD-ARTIFACT-WRITE-ROLE-PRESERVATION-R562.md`.
- R566 artifact `validation.left_artifact_read=true`.
- R566 artifact `validation.right_artifact_read=true`.
- R566 artifact `validation.no_code_changes=true`.

Capability finding:

TOD can complete supported read-only artifact comparison when the prompt package exposes the selected lane's directives as line-start fields. It cannot rely on prose-embedded directives for that lane. This is runtime-support progress, not engineering implementation progress.

Borrowed-capability impact:

- Runtime-support debt reduced: supported read-only evidence comparison pair binding is demonstrated.
- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4% until an actual engineering repair is independently synthesized, validated, and applied.

Immediate next smallest training rung:

`TOD-INDEPENDENT-VALIDATION-COMMAND-REPAIR-DEMO-V1B`

Mission:

Return to the validation-command repair target using the lesson from R566: give TOD line-start directives and a supported evidence lane. TOD must inspect R559 and R558, synthesize its own repaired validation command, run it, and publish the result. Codex's R560 repaired command remains a reference example only and must not count as TOD independence.

## 2026-07-25 R567 Verdict-vs-Execution Comparison

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_VALIDATION_COMMAND_VERDICT_EXECUTION_COMPARISON_R567.latest.json`

Observed result:

- TOD used the supported read-only evidence comparison lane.
- TOD read the R558 provider candidate verdict.
- TOD read the R559 validation-command execution check.
- TOD published a completed comparison artifact.
- The active execution lane remained untouched.
- The artifact's first material difference was `line_2`, comparing only artifact type, not the decision conflict that matters.

Validation:

- R567 artifact `status=completed`.
- R567 artifact `left_artifact_read=true`.
- R567 artifact `right_artifact_read=true`.
- R567 artifact `no_code_changes=true`.
- R567 artifact `first_material_difference=line_2`.

Capability finding:

TOD can now complete the read-only comparison lane mechanically. It cannot yet focus the comparison on the semantically important fields. In this case the real contrast is: R558 accepted the candidate for source mutation, while R559 proved the validation command does not execute and rejected the candidate before source mutation.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support progress improved: line-start comparison lane execution is now demonstrated.
- Semantic evidence comparison remains training debt.

Immediate next smallest training rung:

`TOD-SEMANTIC-VALIDATION-EVIDENCE-COMPARISON-V1`

Mission:

TOD must compare R558 and R559 by selected semantic fields: prior verdict, accepted_for_source_mutation, validation_command, validation_command_exit_zero, rejected_before_source_mutation, and next_smallest_rung. It should publish whether the provider verdict must be superseded by execution evidence before any source mutation.

## 2026-07-25 R568 Semantic Comparison Packet Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_COMPARISON_PACKET_R568.blocker.json`
- `tod/out/prompts/TOD-SEMANTIC-COMPARISON-PACKET-R568.md`

Observed result:

- TOD accepted the semantic-comparison improvement as implementation-shaped work.
- The request entered `task_mode=implementation` and `bounded_edit_mode=true`.
- Local materialization blocked before execution.
- No source file was changed.
- The active execution lane remained untouched.
- The materializer required `edit_mode`.
- TOD did not independently inspect the current code and synthesize exact old/new or anchor/snippet directives.

Validation:

- R568 request `task_mode=implementation`.
- R568 request `bounded_edit_mode=true`.
- R568 materialization `status=blocked`.
- R568 materialization `reason_code=blocked_missing_bounded_edit_mode`.
- R568 blocker `source_code_modified=false`.
- R568 blocker `active_lane_mutated=false`.

Capability finding:

TOD can now reach the correct high-level implementation shape, but it still cannot perform the core engineering step: inspect current code, choose an exact source anchor, and materialize a bounded edit packet from that anchor. This is the same core debt behind the high borrowed-capability ratio.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- The next task must be source-anchor selection, not another desired-behavior implementation request.

Immediate next smallest training rung:

`TOD-SEMANTIC-COMPARISON-SOURCE-ANCHOR-SELECTION-V1`

Mission:

TOD must inspect `scripts/engines/LocalExecutionEngine.ps1` around the `tod_readonly_evidence_comparison` branch, choose one exact current-code anchor, and publish a source-anchor observation. No source edits are allowed. Success requires a readable artifact naming the source file, source function/branch, exact text, why that anchor owns the behavior, and the validation target for a future packet.

## 2026-07-25 R569-R572 Semantic Comparison Source-Anchor Ladder

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_COMPARISON_SOURCE_ANCHOR_R569.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_COMPARISON_ANCHOR_RELEVANCE_R570.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_COMPARISON_CORRECT_SOURCE_ANCHOR_R571.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_COMPARISON_DELTA_PROPOSAL_R572.latest.json`

Observed result:

- R569 published an anchor-selection artifact, but selected `function New-LocalExecutionExactPatchSynthesisDrillArtifact {`.
- R569's selected anchor was unique and source-readable, but it did not own the failed `tod_readonly_evidence_comparison` behavior.
- R570 ran the existing semantic-rejection evaluator against R569 and incorrectly accepted the anchor because the evaluator only checked broad packet/edit-mode relevance.
- R571, with coached anchor input, captured the correct source-anchor observation for `if ($wantsReadOnlyEvidenceComparison) {` inside `Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R572 consumed R571 and produced a `tod_source_anchor_delta_proposal` blocker.
- R572 proved the source anchor is valid, the target file is known, and `old_text_source` is available.
- R572 still could not synthesize safe behavior-changing `candidate_new_text`.

Validation:

- R569 artifact `artifact_type=tod_anchor_selection_artifact`.
- R569 artifact `selected_anchor_unique=true`.
- R570 artifact `decision=accept_anchor`, which is wrong for this behavior-owner task.
- R571 artifact `artifact_type=tod_source_anchor_observation`.
- R571 artifact `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R571 artifact `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R571 artifact `anchor_pattern=if ($wantsReadOnlyEvidenceComparison) {`.
- R571 artifact `exact_text_nonempty=true`.
- R572 artifact `artifact_type=tod_source_anchor_delta_proposal`.
- R572 artifact `status=blocked`.
- R572 blocker `reason_code=autonomous_candidate_new_text_missing`.
- R572 validation `source_anchor_valid=true`.
- R572 validation `source_edits=[]`.

Capability finding:

TOD can now reach the correct source region when coached with the exact behavior-owner anchor. It cannot yet independently select the behavior-owner anchor from the failure description, because the current anchor-selection scorer overweights generic packet/edit-mode terms. It also cannot yet synthesize meaningful behavior-changing `new_text` from the correct source anchor.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support progress improved: TOD can preserve source-anchor artifacts and delta-proposal blockers without mutating source.
- Engineering independence is still blocked at autonomous behavior-owner selection and safe new-text synthesis.

Immediate next smallest training rung:

`TOD-BEHAVIOR-OWNER-ANCHOR-SELECTION-V1`

Mission:

TOD must distinguish "a relevant implementation helper" from "the source code that owns the observed failed behavior." For the R567 failure, TOD must select the `tod_readonly_evidence_comparison` branch, not a generic packet/materialization helper. Success requires an independently selected source-anchor observation whose source function is `Invoke-LocalExecutionReadOnlyAuditArtifact` and whose exact text includes the current directive-field comparison and fallback line-difference logic.

## 2026-07-26 R573 Behavior-Owner Anchor Selection Attempt

Fresh evidence:

- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_ANCHOR_SELECTION_R573.latest.json`
- `runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`
- `scripts/engines/LocalExecutionEngine.ps1`

Observed result:

- R573 entered the read-only inspection lane correctly.
- R573 published a `tod_anchor_selection_artifact`.
- R573 made no source code changes.
- R573 again selected `function New-LocalExecutionExactPatchSynthesisDrillArtifact {`.
- The selected anchor is unique and readable, but it is not the source code that owns the failed semantic comparison behavior.
- The current anchor selector still treats generic packet/materialization helpers as better targets than the branch that produced the observed artifact.

Validation:

- R573 request `task_mode=inspection`.
- R573 request `bounded_edit_mode=false`.
- R573 materialization `status=not_required`.
- R573 materialization `reason_code=canonical_read_only_task_mode_valid`.
- R573 artifact `artifact_type=tod_anchor_selection_artifact`.
- R573 artifact `selected_anchor_pattern=function New-LocalExecutionExactPatchSynthesisDrillArtifact {`.
- R573 artifact `selected_anchor_unique=true`.
- R573 artifact `no_code_changes=true`.
- Source inspection shows `Invoke-LocalExecutionAnchorSelection` boosts packet/materialization/artifact/bounded candidates when task text contains `artifact_write`, `edit_mode`, or `materialization`.

Capability finding:

TOD can run the anchor-selection lane and preserve a clean read-only artifact. It still cannot independently choose the behavior-owner anchor when the task text contains packet/materialization vocabulary. The current selector overweights implementation plumbing terms and does not reason from "the code that produced the bad observable behavior."

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- This is a failed independent behavior-owner selection demo, not an implementation pass.

Immediate next smallest training rung:

`TOD-BEHAVIOR-OWNER-SELECTION-SCORER-DIAGNOSIS-V1`

Mission:

TOD must inspect the anchor-selection scorer itself and explain why `New-LocalExecutionExactPatchSynthesisDrillArtifact` wins over the `tod_readonly_evidence_comparison` branch for R567/R573. No source edits are allowed. Success requires a diagnostic artifact naming the exact scoring rules, the false-winning evidence, the missing behavior-owner criterion, and the smallest future repair target.

## 2026-07-26 R574-R577 Behavior-Owner Selector Diagnosis

Fresh evidence:

- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTION-SCORER-DIAGNOSIS-R574.md`
- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTION-SCORER-SOURCE-R575.md`
- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTION-SCORER-AUDIT-R576.md`
- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTION-SCORER-AUDIT-R577.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTION_SCORER_SOURCE_R575.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTION_SCORER_AUDIT_R577.latest.json`

Observed result:

- R574 attempted broad anchor selection for the selector failure and timed out without publishing an artifact.
- R575 backed up to a coached source-anchor observation and captured `function Invoke-LocalExecutionAnchorSelection {`.
- R575 wrote a valid source-anchor observation artifact, but `Invoke-LocalExecutionEngine` still failed interface validation after artifact write.
- R576 attempted semantic source audit with an incomplete packet shape and did not publish an artifact.
- R577 added the required extraction fields and published a semantic source-audit artifact.
- R577 again hit wrapper interface validation after artifact write.

Validation:

- R575 artifact `artifact_type=tod_source_anchor_observation`.
- R575 artifact `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R575 artifact `function_surface=Invoke-LocalExecutionAnchorSelection`.
- R575 artifact `anchor_pattern=function Invoke-LocalExecutionAnchorSelection {`.
- R575 artifact `exact_text_nonempty=true`.
- R575 artifact `no_code_changes=true`.
- R577 artifact `artifact_type=tod_semantic_source_audit_artifact`.
- R577 artifact `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R577 artifact `function_surface=Invoke-LocalExecutionAnchorSelection`.
- R577 artifact `root_cause` identifies keyword-overlap relevance checks instead of actual source responsibility.
- R577 artifact `selector_failure_mode` identifies artifact/edit/packet term matching as the false relevance basis.
- R577 artifact `evidence_lines` includes `$taskRequiresPacketEditing = ... artifact_write ... edit_mode ... materialization` and `$candidateHasPacketEditingEvidence = ... packet ... materialization ... directive ...`.

Capability finding:

TOD can diagnose the selector failure when given the exact scorer source anchor and a corrected semantic-audit packet shape. TOD did not independently find the scorer anchor from the observed behavior, and the local engine wrapper still reports interface validation failure after some read-only artifact writes. This is a guided diagnostic pass, not an independent engineering repair.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support debt added: artifact write can succeed while the engine wrapper reports interface validation failure.
- Engineering debt remains: TOD still needs to synthesize the smallest safe behavior-changing repair from the scorer evidence.

Immediate next smallest training rung:

`TOD-BEHAVIOR-OWNER-SELECTOR-REPAIR-PACKET-V1`

Mission:

TOD must use the R575/R577 evidence to produce a bounded repair packet for `scripts/engines/LocalExecutionEngine.ps1` that changes the selector from keyword-overlap relevance to behavior-owner relevance without hardcoding the R567/R573 examples. The packet must include exact current old text, proposed new text, validation command, expected evidence, and a prevention lesson. Source code should not be modified until the packet is validated.

## 2026-07-26 R578 Behavior-Owner Selector Repair Packet Attempt

Fresh evidence:

- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTOR-REPAIR-PACKET-R578.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTION_SCORER_SOURCE_R575.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTION_SCORER_AUDIT_R577.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTOR_REPAIR_PACKET_R578.blocker.json`

Observed result:

- R578 attempted to create a behavior-changing repair packet from the scorer source evidence.
- No packet artifact was produced.
- The local engine reported interface validation failure instead of returning a structured packet-body blocker.
- No source code was modified by this attempt.
- The exact blocker is now `autonomous_meaningful_new_text_materialization_from_source_anchor_missing`.

Validation:

- R575 source-anchor JSON readback: passed.
- R577 semantic-audit JSON readback: passed.
- R578 blocker JSON readback: passed.
- `scripts/engines/LocalExecutionEngine.ps1` PowerShell parser check: passed.
- R578 packet artifact existence: failed / missing.

Capability finding:

TOD has enough evidence to know what is wrong: keyword-overlap relevance is being mistaken for source ownership. TOD still cannot independently synthesize a safe current-code behavior patch from that evidence. The local engine also needs a wrapper-contract repair so artifact-write failures and packet-body blockers return structured evidence instead of a generic interface-validation exception.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Guided diagnostic capability improved.
- Engineering implementation remains blocked at meaningful `new_text` synthesis.

Immediate next smallest training rung:

`TOD-ENGINEERING-EPISODE-FROM-SELECTOR-FAILURE-V1`

Mission:

Convert R573-R578 into an engineering corpus episode containing the problem, inspected source, false-winning anchor, correct behavior-owner evidence, root cause, failed packet attempt, validation evidence, and the missing capability. This should prepare the case for a local engineering intelligence/model-utilization path instead of asking the current deterministic runtime to invent behavior-changing code it does not know how to synthesize.

## 2026-07-26 R579-R581 Engineering Episode And Context Package

Fresh evidence:

- `runtime/tod_engineering_corpus/TOD_BEHAVIOR_OWNER_SELECTOR_FAILURE_R573_R578.episode.json`
- `tod/out/prompts/TOD-ENGINEERING-CONTEXT-PACKAGE-FOR-BEHAVIOR-OWNER-REPAIR-R579.md`
- `tod/out/prompts/TOD-ENGINEERING-CONTEXT-PACKAGE-FOR-BEHAVIOR-OWNER-REPAIR-R580.md`
- `tod/out/prompts/TOD-MODEL-UTILIZATION-JUDGMENT-FOR-BEHAVIOR-OWNER-REPAIR-R581.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_PACKAGE_FOR_BEHAVIOR_OWNER_REPAIR_R579.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_PACKAGE_FOR_BEHAVIOR_OWNER_REPAIR_R580.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_FOR_BEHAVIOR_OWNER_REPAIR_R581.blocker.json`

Observed result:

- The selector failure was converted into a durable engineering corpus episode.
- R579 generated a context package, but it was too weak because `source_file` and `source_function` were blank.
- The episode was enriched with top-level `source_file`, `source_function`, `source_anchor_artifact`, `observed_failure`, `desired_behavior`, and `validation_target`.
- R580 generated a source-rich engineering context package for the behavior-owner selector repair.
- R581 attempted model-utilization judgment but did not produce a judgment artifact.
- A precise R581 blocker was published instead.

Validation:

- R580 context package JSON readback: passed.
- R580 `source_file=scripts/engines/LocalExecutionEngine.ps1`.
- R580 `source_function=Invoke-LocalExecutionAnchorSelection`.
- R580 `source_anchor_artifact=runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTION_SCORER_SOURCE_R575.latest.json`.
- R581 blocker JSON readback: passed.
- Engineering episode JSON readback: passed.
- `scripts/engines/LocalExecutionEngine.ps1` PowerShell parser check: passed.

Capability finding:

TOD now has a source-rich engineering context package for this failure, but the model-utilization/provider-readiness step did not materialize. This is progress in engineering-context preparation, not source implementation. The next blocker is no longer "what went wrong?" It is "how does TOD request or produce a candidate repair from a model/provider path and then reject or accept it from source evidence?"

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Engineering corpus quality improved for this specific failure.
- Model-utilization remains blocked at judgment/provider-request materialization.

Immediate next smallest training rung:

`TOD-MODEL-UTILIZATION-JUDGMENT-MATERIALIZATION-V1`

Mission:

TOD must inspect why the read-only audit artifact lane failed to produce `tod_model_utilization_engineering_judgment` from the valid R580 context package, then publish either a valid judgment artifact or a precise source-owner blocker. No source repair should occur until the judgment path is proven or a provider request is manually routed under Examiner review.

## 2026-07-26 R582-R589 Model Utilization And Provider Supervision Chain

Fresh evidence:

- `tod/out/prompts/TOD-MODEL-UTILIZATION-JUDGMENT-FOR-BEHAVIOR-OWNER-REPAIR-R582.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-REQUEST-FOR-BEHAVIOR-OWNER-REPAIR-R583.md`
- `tod/out/prompts/TOD-LOCAL-ENGINEERING-PROVIDER-INVENTORY-FOR-BEHAVIOR-OWNER-REPAIR-R584.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-CANDIDATE-INVOCATION-FOR-BEHAVIOR-OWNER-REPAIR-R585.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-VERDICT-FOR-BEHAVIOR-OWNER-REPAIR-R586.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-FOR-BEHAVIOR-OWNER-REPAIR-R587.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-CANDIDATE-RETRY-FOR-BEHAVIOR-OWNER-REPAIR-R588.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-VERDICT-FOR-BEHAVIOR-OWNER-REPAIR-R589.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_FOR_BEHAVIOR_OWNER_REPAIR_R582.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_REQUEST_FOR_BEHAVIOR_OWNER_REPAIR_R583.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_PROVIDER_INVENTORY_FOR_BEHAVIOR_OWNER_REPAIR_R584.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_CANDIDATE_INVOCATION_FOR_BEHAVIOR_OWNER_REPAIR_R585.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_VERDICT_FOR_BEHAVIOR_OWNER_REPAIR_R586.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_REPLAN_FOR_BEHAVIOR_OWNER_REPAIR_R587.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_CANDIDATE_RETRY_FOR_BEHAVIOR_OWNER_REPAIR_R588.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_RETRY_VERDICT_FOR_BEHAVIOR_OWNER_REPAIR_R589.latest.json`

Observed result:

- R582 corrected the task category from `engineering_context_package` to `artifact_write` and materialized `tod_model_utilization_engineering_judgment`.
- R582 reported `context_quality=provider_prompt_ready`, `candidate_request_ready=true`, and `provider_reachable=false` within the judgment artifact.
- R583 materialized a provider/local-model request from the R580 context package and R582 judgment.
- R584 inventoried the local engineering runtime and found GPU available, configured llama server/model present, and the local OpenAI-compatible endpoint reachable with `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- R585 invoked the local provider and captured a malformed candidate response with blank parsed `new_text`.
- R586 correctly rejected the first candidate before source mutation with `verdict_reason_code=rejected_blank_new_text`.
- R587 produced a retry-ready replan artifact from the rejected verdict.
- R588 retried the local provider after replan. The response was longer but still malformed, leaving parsed `new_text` blank.
- R589 correctly rejected the retried candidate before source mutation with `verdict_reason_code=rejected_blank_new_text`.

Validation:

- R582/R583/R584/R585/R586/R587/R588/R589 artifact JSON readback: passed.
- R584 verified local engineering provider endpoint reachability.
- R585 verified provider invocation occurred and response was captured.
- R586/R589 verified verdict gates reject unusable provider output before source mutation.
- `scripts/engines/LocalExecutionEngine.ps1` PowerShell parser check: passed.
- No source code was modified by the provider invocation or verdict chain.

Capability finding:

TOD can now move a source-rich engineering episode through context judgment, provider request, provider inventory, local provider invocation, candidate verdict, and replan. This is meaningful progress in model utilization and engineering supervision. The local provider did not produce an acceptable behavior-changing patch candidate for the large `Invoke-LocalExecutionAnchorSelection` anchor. TOD correctly rejected both malformed/blank-new-text candidates instead of converting weak model output into source mutation.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization subskill improved from blocked judgment materialization to provider invocation plus accept/reject supervision.
- Engineering implementation remains blocked at acceptable behavior-changing `new_text` generation.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-PROMPT-SCOPING-V1`

Mission:

TOD must reduce the provider task scope before another model attempt. The current source anchor is too large and the provider returns malformed JSON. The next rung should create a smaller provider request from a narrower source slice or structured diff target, require strict JSON-only output, and rerun the verdict gate. Source mutation remains forbidden until a candidate passes target, old_text, new_text, delta, validation, and current-source checks.

## 2026-07-26 R590-R601 Scoped Provider Supervision Chain

Fresh evidence:

- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTOR-SCOPED-SOURCE-R590.md`
- `tod/out/prompts/TOD-ENGINEERING-CONTEXT-PACKAGE-SCOPED-BEHAVIOR-OWNER-REPAIR-R591.md`
- `tod/out/prompts/TOD-MODEL-UTILIZATION-JUDGMENT-FOR-SCOPED-BEHAVIOR-OWNER-REPAIR-R592.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-REQUEST-FOR-SCOPED-BEHAVIOR-OWNER-REPAIR-R593.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-REQUEST-FOR-SCOPED-BEHAVIOR-OWNER-REPAIR-R593B.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-CANDIDATE-INVOCATION-FOR-SCOPED-BEHAVIOR-OWNER-REPAIR-R594.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-VERDICT-FOR-SCOPED-BEHAVIOR-OWNER-REPAIR-R595.md`
- `tod/out/prompts/TOD-BEHAVIOR-OWNER-SELECTOR-SCORING-SOURCE-R596.md`
- `tod/out/prompts/TOD-ENGINEERING-CONTEXT-PACKAGE-SCORING-BEHAVIOR-OWNER-REPAIR-R597.md`
- `tod/out/prompts/TOD-MODEL-UTILIZATION-JUDGMENT-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R598.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-REQUEST-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R599.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-CANDIDATE-INVOCATION-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R600.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-VERDICT-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R601.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTOR_SCOPED_SOURCE_R590.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_PACKAGE_SCOPED_BEHAVIOR_OWNER_REPAIR_R591.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_FOR_SCOPED_BEHAVIOR_OWNER_REPAIR_R592.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_REQUEST_FOR_SCOPED_BEHAVIOR_OWNER_REPAIR_R593.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_REQUEST_FOR_SCOPED_BEHAVIOR_OWNER_REPAIR_R593B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_CANDIDATE_INVOCATION_FOR_SCOPED_BEHAVIOR_OWNER_REPAIR_R594.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_VERDICT_FOR_SCOPED_BEHAVIOR_OWNER_REPAIR_R595.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BEHAVIOR_OWNER_SELECTOR_SCORING_SOURCE_R596.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_PACKAGE_SCORING_BEHAVIOR_OWNER_REPAIR_R597.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R598.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_REQUEST_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R599.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_CANDIDATE_INVOCATION_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R600.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_VERDICT_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R601.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_SUPERVISION_R590_R601.summary.json`

Observed result:

- R590 scoped the source anchor from the full `Invoke-LocalExecutionAnchorSelection` function down to the `$taskRequiresPacketEditing` region.
- R591 converted that scoped source observation into an engineering context package.
- R592 judged the scoped package provider-ready.
- R593 showed a useful packet-label failure: `Supporting Evidence` did not bind as the required `Supporting Artifact`.
- R593B corrected the evidence label and produced a provider-ready request.
- R594 invoked the local provider. The provider returned a target file and some `old_text`, but latched onto an unrelated file-exists guard and returned blank `new_text`.
- R595 correctly rejected the R594 candidate before source mutation.
- R596 narrowed the source context further to the candidate-scoring branch starting at `$candidateHasPacketEditingEvidence`.
- R597/R598/R599 carried the scoring-only source through context package, readiness judgment, and provider request.
- R600 invoked the local provider with the scoring-only request. The provider selected the scoring excerpt as `old_text`, which is better than R594, but still returned blank `new_text`.
- R601 correctly rejected the R600 candidate before source mutation.

Validation:

- R590-R601 JSON readback: passed.
- R593B provider request readiness: passed.
- R594 and R600 provider invocation: passed.
- R595 and R601 verdict gates: passed and rejected blank `new_text`.
- No source code was modified by the scoped provider supervision chain.
- Direct `Invoke-LocalExecutionEngine` calls still throw final interface-validation exceptions after writing valid artifacts; this is separate runtime result-shape debt.

Capability finding:

TOD improved in source-context scoping and provider supervision. It can now observe a failed model attempt, narrow context, rerun provider invocation, and reject unusable candidates without mutating source. The local provider improved from unrelated guard selection to correct scoring-region `old_text` selection after tighter scoping, but still failed to generate behavior-changing `new_text`.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved.
- Independent behavior-changing patch synthesis is still not demonstrated.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-NEW-TEXT-SYNTHESIS-DRILL-V1`

Mission:

TOD must ask for and evaluate only the missing `new_text` delta for an already-selected exact `old_text`, without reopening target-file selection, artifact routing, or broad source discovery. If the provider still cannot produce a meaningful delta, TOD should publish a precise provider-capability blocker and route the episode to a non-provider new-text synthesis drill.

## 2026-07-26 R602-R604 Provider Retry And Parse Boundary

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R602.md`
- `tod/out/prompts/TOD-ENGINEERING-PROVIDER-CANDIDATE-RETRY-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R603.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-VERDICT-FOR-SCORING-BEHAVIOR-OWNER-REPAIR-R604.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_REPLAN_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R602.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_PROVIDER_CANDIDATE_RETRY_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R603.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_RETRY_VERDICT_FOR_SCORING_BEHAVIOR_OWNER_REPAIR_R604.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_PARSE_BOUNDARY_R602_R604.summary.json`

Observed result:

- R602 produced a retry-ready provider replan after the R601 rejection.
- R603 invoked the local provider with the replan.
- R603 raw provider output contained a nonblank `new_text`, but the JSON parser failed on unescaped regex backslashes.
- Because parsing failed, the normalized candidate fields recorded blank `new_text`.
- The raw proposed `new_text` was also semantically weak: it added a special async-function score boost, which does not address the behavior-owner selector failure.
- R604 rejected the normalized candidate before source mutation.

Validation:

- R602/R603/R604 JSON readback: passed.
- R602 `provider_request_ready_for_retry=true`.
- R603 `provider_called=true`.
- R603 raw output captured.
- R604 `verdict=reject`.
- R604 `rejected_before_source_mutation=true`.
- No source code was modified.

Capability finding:

TOD now exposes a second provider-supervision layer: a model can produce visible `new_text` in raw output while the normalized artifact loses it because the JSON is invalid. TOD must not apply from raw text automatically. The next rung should parse, quarantine, and semantically review raw candidates separately from normalized candidates.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved.
- Provider-output parsing and semantic candidate review are now explicit training debt.

Immediate next smallest training rung:

`TOD-PROVIDER-RAW-CANDIDATE-QUARANTINE-AND-SEMANTIC-REVIEW-V1`

Mission:

When provider JSON parsing fails but raw output includes apparent candidate fields, TOD must quarantine the raw candidate, recover fields only into a non-apply review artifact, judge semantic relevance against the requested behavior, and either reject or convert to a normalized candidate for a separate verdict. No source mutation may occur from raw provider text.

## 2026-07-26 R605-R607 Raw Candidate And Autonomous NewText Boundary

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-RAW-CANDIDATE-QUARANTINE-SEMANTIC-REVIEW-R605.md`
- `tod/out/prompts/TOD-SCORING-BEHAVIOR-OWNER-DELTA-PROPOSAL-R606.md`
- `tod/out/prompts/TOD-AUTONOMOUS-NEWTEXT-SYNTHESIS-SCORING-BEHAVIOR-OWNER-R607.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RAW_CANDIDATE_QUARANTINE_SEMANTIC_REVIEW_R605.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SCORING_BEHAVIOR_OWNER_DELTA_PROPOSAL_R606.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_NEWTEXT_SYNTHESIS_SCORING_BEHAVIOR_OWNER_R607.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_RAW_CANDIDATE_AND_AUTONOMOUS_NEWTEXT_BOUNDARY_R605_R607.summary.json`

Observed result:

- R605 attempted to assess raw-provider quarantine and semantic review using the current runtime.
- The runtime produced a generic read-only contract-field evaluation, not a quarantine/semantic-review artifact.
- R605 failed the contract because normalized `new_text` and `no_code_changes` were absent from the audited R603 candidate artifact.
- R606 preserved the scoring-branch source anchor and desired behavior delta, then blocked honestly on `autonomous_candidate_new_text_missing`.
- R607 consumed the exact scoring source anchor plus the R606 delta proposal, preserved the correct target file and exact old_text, and blocked on `autonomous_meaningful_new_text_synthesis_missing`.

Validation:

- R605/R606/R607 JSON readback: passed.
- R607 target file: `scripts/engines/LocalExecutionEngine.ps1`.
- R607 old_text length: 3913.
- R607 new_text length: 0.
- R605/R606/R607 made no source code changes.

Capability finding:

TOD can now preserve exact source evidence, preserve the intended behavior delta, and publish an honest blocker when it cannot synthesize meaningful `new_text`. The current runtime cannot yet quarantine malformed raw provider candidates into a semantic review artifact, and TOD cannot independently produce the behavior-changing replacement text from exact source evidence.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Evidence quality improved because the blocker now includes exact target file, exact old_text, and the missing capability.

Immediate next smallest training rung:

`TOD-NEWTEXT-SYNTHESIS-CRITERIA-FROM-HUMAN-REVIEW-V1`

Mission:

Before asking another provider or deterministic lane to generate code, TOD must define the acceptance criteria for a good `new_text` candidate from the current source evidence: what behavior must change, what must remain unchanged, which exact old_text boundary is valid, what validation command must prove the repair, and which candidate classes must be rejected. This remains non-mutating preparation for eventual independent implementation.

## 2026-07-26 R608-R609 NewText Criteria Lane And Episode Examiner

Fresh evidence:

- `tod/out/prompts/TOD-NEWTEXT-SYNTHESIS-CRITERIA-FROM-HUMAN-REVIEW-R608.md`
- `tod/out/prompts/TOD-NEWTEXT-SYNTHESIS-BLOCKER-EPISODE-CARD-R608B.md`
- `tod/out/prompts/TOD-NEWTEXT-SYNTHESIS-BLOCKER-EPISODE-EXAMINER-R609.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_BLOCKER_EPISODE_CARD_R608B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_BLOCKER_EPISODE_EXAMINER_R609.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_EPISODE_R608_R609.summary.json`

Observed result:

- R608 attempted to publish a custom criteria artifact, but no artifact was written because the current learned read-only artifact lane does not support that custom artifact shape.
- Codex reframed the next step as supported training memory instead of patching the runtime.
- R608B converted the R607 autonomous `new_text` synthesis blocker into a durable `tod_engineering_episode_card`.
- R609 examined that episode card and completed with `training_usefulness=accept_runtime_support_only`.
- The Examiner explicitly denied engineering implementation credit and left the borrowed-capability ratio unchanged.

Validation:

- R608B JSON readback: passed.
- R609 JSON readback: passed.
- R609 `engineering_credit_allowed=false`.
- R609 `runtime_support_credit_allowed=true`.
- R609 `borrowed_capability_ratio_effect=no_reduction`.
- No source code was modified.

Capability finding:

TOD can preserve this failure as runtime-support training memory and can ask the Examiner to classify it honestly. TOD still cannot independently turn exact source evidence and a behavior delta into meaningful `new_text`, and the current runtime does not yet have a learned non-mutating criteria artifact lane for future candidate acceptance rules.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support evidence quality improved.
- This episode should not be counted as engineering independence.

Immediate next smallest training rung:

`TOD-NEWTEXT-SYNTHESIS-CRITERIA-USING-SUPPORTED-ARTIFACT-TYPE-V1`

Mission:

Teach TOD to express acceptance criteria through an existing supported artifact shape, or to publish a precise unsupported-lane blocker before requesting runtime changes. The next pass should avoid source mutation and should not claim implementation credit until TOD can produce meaningful `new_text`, validate it, and apply it through the bounded edit lane.

## 2026-07-26 R610 Supported Lane Packet Comparison

Fresh evidence:

- `tod/out/prompts/TOD-NEWTEXT-CRITERIA-SUPPORTED-LANE-COMPARISON-R610.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_CRITERIA_SUPPORTED_LANE_COMPARISON_R610.latest.json`

Observed result:

- The first R610 attempt failed before artifact publication because multi-line directive values caused path parsing to swallow following fields.
- The packet was corrected to use single-line artifact directives.
- TOD then published a `tod_read_only_evidence_comparison` artifact comparing the failed R608 packet with the supported R608B packet.
- The first material difference was `Task Category`: R608 used `read_only_assessment`; R608B used `artifact_write`.
- The comparison identified the executor effect as `affects_executor_lane_or_artifact_contract`.

Validation:

- R610 JSON readback: passed.
- R610 `status=completed`.
- R610 `first_material_difference=Task Category`.
- No source code was modified.

Capability finding:

TOD can now use an existing evidence-comparison lane to identify why a coaching packet failed to enter the intended learned artifact path. This is still runtime-support learning, not engineering implementation, but it is a useful prevention lesson for future TOD packet materialization.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support debt reduced in clarity, not in counted engineering independence.

Immediate next smallest training rung:

`TOD-NEWTEXT-SYNTHESIS-PACKET-SHAPE-PRECHECK-V1`

Mission:

Before executing future source-anchor or new_text synthesis tasks, TOD should precheck that the packet uses a supported task category, required artifact type, single-line artifact directives, safe input/output paths, and an explicit no-source-mutation rule when the step is evidence-only. This should prevent unsupported criteria/review packets from entering the wrong lane.

## 2026-07-26 R611-R612 Provider JSON Contract Failure Episode

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-JSON-CONTRACT-FAILURE-EPISODE-CARD-R611.md`
- `tod/out/prompts/TOD-PROVIDER-JSON-CONTRACT-FAILURE-EPISODE-EXAMINER-R612.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_JSON_CONTRACT_FAILURE_EPISODE_CARD_R611.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_JSON_CONTRACT_FAILURE_EPISODE_EXAMINER_R612.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_JSON_CONTRACT_FAILURE_R611_R612.summary.json`

Observed result:

- R611 converted the R603 local-provider parse failure into a durable episode card.
- R612 examined the episode and accepted it only as runtime-support memory.
- The Examiner denied engineering credit because no independent behavior-changing patch synthesis, source mutation, or validation occurred.

Validation:

- R611 JSON readback: passed.
- R612 JSON readback: passed.
- R612 `training_usefulness=accept_runtime_support_only`.
- R612 `engineering_credit_allowed=false`.
- R612 `borrowed_capability_ratio_effect=no_reduction`.
- No source code was modified.

Capability finding:

TOD can preserve local-provider failure evidence and avoid treating raw unparseable model output as an applyable candidate. The model-utilization path is real, but it is not yet reliable enough to retire code-delta synthesis debt.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Provider-output-contract debt is now explicit.

Immediate next smallest training rung:

`TOD-PROVIDER-STRICT-JSON-CANDIDATE-REQUEST-V1`

Mission:

TOD should generate a provider request that explicitly requires valid minified JSON, escaped backslashes, no Markdown fences, and an executable validation command. If the local provider still returns invalid JSON or a semantically wrong patch, TOD must reject it and preserve the raw/normalized divergence without source mutation.

## 2026-07-26 R613-R615 Strict JSON Provider Candidate Attempt

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-STRICT-JSON-CANDIDATE-REQUEST-R613.md`
- `tod/out/prompts/TOD-PROVIDER-STRICT-JSON-CANDIDATE-INVOCATION-R614.md`
- `tod/out/prompts/TOD-PROVIDER-STRICT-JSON-CANDIDATE-VERDICT-R615.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_STRICT_JSON_CANDIDATE_REQUEST_R613.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_STRICT_JSON_CANDIDATE_INVOCATION_R614.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_STRICT_JSON_CANDIDATE_VERDICT_R615.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_STRICT_JSON_CANDIDATE_R613_R615.summary.json`

Observed result:

- R613 produced a provider-ready request artifact with strict JSON-only and executable validation-command language in `prompt_messages`.
- R614 invoked the local provider and captured a raw candidate response.
- The raw provider response still contained invalid JSON escaping and blank `new_text`.
- The normalized candidate kept `new_text` blank and retained the generic validation placeholder.
- R615 correctly rejected the candidate before source mutation with `verdict_reason_code=rejected_blank_new_text`.
- No source code was modified.

Validation:

- R613/R614/R615 JSON readback: passed.
- R613 `provider_request_ready=true`.
- R614 `provider_called=true`.
- R614 `candidate_response_available=true`.
- R614 `new_text` length: `0`.
- R615 `verdict=reject`.
- R615 `accepted_for_source_mutation=false`.
- R615 `rejected_before_source_mutation=true`.
- R615 `validation_command_specific=false`.

Capability finding:

TOD can produce and execute a stricter provider-request attempt, and the verdict gate continues to protect source code from weak model output. The attempt did not improve engineering independence because the provider still returned blank `new_text`, invalid escaping, and a generic validation command. The strongest new finding is a prompt-authority gap: the strict request text exists in the provider request artifact, but the invocation path still appears governed by the internal provider invocation prompt and generic validation placeholder.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved slightly because the strict attempt was rejected cleanly.
- Provider prompt-authority tracing is now explicit runtime-support debt.

Immediate next smallest training rung:

`TOD-PROVIDER-REQUEST-PROMPT-AUTHORITY-TRACE-V1`

Mission:

TOD must trace whether `tod_engineering_provider_request.prompt_messages`, `required_output_contract`, and strict validation-command fields are actually used by the `tod_engineering_provider_candidate_invocation` path. The trace must name the source function, the prompt fields consumed, the prompt fields ignored, and the smallest future repair target. No source mutation is allowed in the trace.

## 2026-07-26 R616-R617B Provider Request Prompt Authority Trace

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-REQUEST-PROMPT-AUTHORITY-SOURCE-R616.md`
- `tod/out/prompts/TOD-PROVIDER-REQUEST-PROMPT-AUTHORITY-AUDIT-R617.md`
- `tod/out/prompts/TOD-PROVIDER-REQUEST-PROMPT-AUTHORITY-AUDIT-R617B.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_PROMPT_AUTHORITY_SOURCE_R616.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_PROMPT_AUTHORITY_AUDIT_R617B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_PROMPT_AUTHORITY_TRACE_R616_R617B.summary.json`

Observed result:

- R616 captured the provider candidate invocation branch in `scripts/engines/LocalExecutionEngine.ps1`.
- R617 asked the semantic-audit lane for custom prompt-authority fields and did not publish an artifact.
- R617B backed up to the native semantic-audit field contract and published a source audit artifact.
- The source evidence shows the provider invocation branch builds a local `$candidatePrompt` and sends a fixed system message plus that prompt to the provider.
- The source evidence shows no direct use of `providerRequest.prompt_messages`.
- The source evidence shows no direct use of `providerRequest.required_output_contract` except through fields already copied to request-level values such as `validation_command`.
- No source code was modified.

Validation:

- R616 JSON readback: passed.
- R616 `exact_text_nonempty=true`.
- R617B JSON readback: passed.
- R617B `extracted_tokens` includes `providerRequest`, `validation_command`, `candidatePrompt`, `replanInstruction`, `providerRawResponse`, and JSON parsing terms.
- R617B `regex_terms_excerpt` includes provider request readiness, source-anchor loading, `$candidatePrompt`, fixed provider messages, `ConvertTo-Json`, provider call, raw response capture, and `ConvertFrom-Json`.
- R617B `source_edits=[]`.

Capability finding:

TOD proved the prompt-authority gap without source mutation: stricter `prompt_messages` can exist in a provider request artifact while the invocation path still builds and sends its own local prompt. The custom semantic-audit lane cannot accept arbitrary field names yet, so prompt-authority evidence had to be captured through native semantic-audit fields.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Runtime-support evidence improved: prompt-authority loss is now localized to the provider invocation branch.

Immediate next smallest training rung:

`TOD-PROVIDER-PROMPT-AUTHORITY-REPAIR-PACKET-V1`

Mission:

TOD must use the R616 source anchor and R617B audit evidence to produce a bounded repair packet for `scripts/engines/LocalExecutionEngine.ps1` that makes provider invocation honor `providerRequest.prompt_messages` or `required_output_contract` without hardcoding R613/R614. The packet must include exact current `old_text`, meaningful behavior-changing `new_text`, validation command, expected evidence, and prevention lesson. Source mutation remains forbidden until the packet passes verdict.

## 2026-07-26 R618-R623 Provider Prompt-Authority Repair Attempt

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-PROMPT-AUTHORITY-REPAIR-PACKET-R618.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_REPAIR_PACKET_R618.blocker.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-AUTHORITY-CONTEXT-PACKAGE-R619.md`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-AUTHORITY-JUDGMENT-R620.md`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-AUTHORITY-PROVIDER-REQUEST-R621.md`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-AUTHORITY-CANDIDATE-INVOCATION-R622.md`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-AUTHORITY-CANDIDATE-VERDICT-R623.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_CONTEXT_PACKAGE_R619.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_JUDGMENT_R620.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_PROVIDER_REQUEST_R621.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_CANDIDATE_INVOCATION_R622.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_CANDIDATE_VERDICT_R623.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_AUTHORITY_R618_R623.summary.json`

Observed result:

- R618 did not materialize a direct repair packet with exact `old_text` and meaningful `new_text`.
- R619 backed up one rung and produced a source-rich engineering context package.
- R620 judged the context as provider-prompt-ready but did not request implementation credit.
- R621 produced a provider request for the provider prompt-authority repair.
- R622 called the local provider and captured a candidate response.
- The provider candidate used `target_file=scripts/engines/LocalExecutionEngine.ps1`, but returned `old_text=$sourceAnchorText`, blank `new_text`, and a generic validation command.
- R623 correctly rejected the candidate before source mutation with `verdict_reason_code=rejected_blank_new_text`.
- No source code was modified.

Validation:

- R619/R620/R621/R622/R623 JSON readback: passed.
- R621 `provider_request_ready=true`.
- R622 `provider_called=true`.
- R622 `candidate_response_available=true`.
- R622 `new_text` length: `0`.
- R623 `verdict=reject`.
- R623 `accepted_for_source_mutation=false`.
- R623 `rejected_before_source_mutation=true`.
- R623 `validation_command_specific=false`.

Capability finding:

TOD can now package provider prompt-authority context, request a local provider candidate, and reject an unsafe blank candidate before source mutation. TOD still cannot independently produce meaningful behavior-changing `new_text` from source-anchor evidence for this repair class.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved: bad provider output was rejected instead of applied.

Immediate next smallest training rung:

`TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1`

Mission:

TOD must replan after the rejected provider candidate by supplying the provider with an exact source excerpt, the specific current prompt construction block, and a concrete validation command. The next candidate must replace a real source block, not `$sourceAnchorText`, and must be rejected again if `new_text` is blank or validation remains generic.

## 2026-07-26 R624-R635 Replan and Narrow-Anchor Provider Retry

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-R624.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-REQUEST-R625.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-INVOCATION-R626.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-VERDICT-R627.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-INVOCATION-R628.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-VERDICT-R629.md`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-NARROW-SOURCE-ANCHOR-R630.md`
- `tod/out/prompts/TOD-PROVIDER-NARROW-ANCHOR-CONTEXT-PACKAGE-R631.md`
- `tod/out/prompts/TOD-PROVIDER-NARROW-ANCHOR-JUDGMENT-R632.md`
- `tod/out/prompts/TOD-PROVIDER-NARROW-ANCHOR-REQUEST-R633.md`
- `tod/out/prompts/TOD-PROVIDER-NARROW-ANCHOR-INVOCATION-R634.md`
- `tod/out/prompts/TOD-PROVIDER-NARROW-ANCHOR-VERDICT-R635.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_NARROW_ANCHOR_R624_R635.summary.json`

Observed result:

- R624 created a retry-ready replan artifact from the rejected R623 verdict.
- R626 used the retry request as input, so the replan instruction was not applied and the candidate repeated blank `new_text`.
- R628 used the replan artifact directly, so `replan_instruction_applied=true`, but the provider returned placeholder fields such as `$sourceFile` and `$validationCommand`.
- R630 narrowed the source anchor from 15,814 characters to 53 lines / 2,771 characters around the provider `candidatePrompt` block.
- R634 invoked the local provider against the narrow anchor. The provider copied the correct target and enough source to populate fallback `old_text`, but emitted malformed JSON and blank `new_text`.
- R635 rejected the narrow-anchor candidate before source mutation with `verdict_reason_code=rejected_blank_new_text`.
- No source code was modified.

Validation:

- R624/R625/R626/R627/R628/R629/R630/R631/R632/R633/R634/R635 artifacts were created.
- R630 `exact_text_nonempty=true`.
- R630 line count: `53`.
- R630 exact text length: `2771`.
- R634 `provider_called=true`.
- R634 `candidate_response_available=true`.
- R634 `new_text` length: `0`.
- R635 `verdict=reject`.
- R635 `accepted_for_source_mutation=false`.

Capability finding:

TOD improved the task shape from broad source-anchor evidence to narrow source-anchor evidence and correctly rejected unsafe candidates. The local provider still cannot produce meaningful behavior-changing `new_text` for this repair class.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved, but engineering independence did not.

Immediate next smallest training rung:

`TOD-AUTONOMOUS-NEWTEXT-SYNTHESIS-WITHOUT-PROVIDER-V1`

Mission:

TOD should stop repeatedly retrying the same provider path for this repair and attempt a smaller non-provider synthesis drill: from a narrow source anchor, explain the intended behavior change and identify the smallest source block that would need replacement. If it still cannot author `new_text`, publish that precise blocker and select a simpler fresh engineering target.

## 2026-07-26 R636-R637 Autonomous New Text Synthesis

Fresh evidence:

- `tod/out/prompts/TOD-AUTONOMOUS-NEWTEXT-DELTA-PROPOSAL-R636.md`
- `tod/out/prompts/TOD-AUTONOMOUS-NEWTEXT-SYNTHESIS-R637.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_NEWTEXT_DELTA_PROPOSAL_R636.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_NEWTEXT_SYNTHESIS_R637.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_NEWTEXT_R636_R637.summary.json`

Observed result:

- R636 read the narrow source-anchor artifact, identified `scripts/engines/LocalExecutionEngine.ps1` as the target file, and published `reason_code=autonomous_candidate_new_text_missing`.
- R637 consumed the source-anchor artifact plus the R636 delta blocker, preserved nonempty `old_text`, kept `new_text` blank, and set `independent_credit_requested=false`.
- No source code was modified.

Validation:

- R636/R637 artifacts were created.
- R636 `source_anchor_valid=true`.
- R637 `source_anchor_valid=true`.
- R637 `prior_delta_available=true`.
- R637 `old_text_nonempty=true`.
- R637 `new_text_nonempty=false`.

Capability finding:

TOD can preserve exact source-anchor evidence and honestly reject unsafe or blank synthesis. TOD still cannot independently author safe behavior-changing `new_text` from source evidence.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Evidence routing, blocker honesty, and source mutation safety improved.

Immediate next smallest training rung:

`TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-RUNTIME-V1`

Mission:

TOD needs a usable engineering model/runtime path or a deliberately simpler fresh engineering target that teaches code-delta synthesis before returning to the provider prompt-authority repair.

## 2026-07-26 R638-R646 Scaffolded Packet Body Synthesis Drill

Fresh evidence:

- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-FIXTURE-SOURCE-ANCHOR-R638.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-FIXTURE-R639.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-FIXTURE-QUALITY-REVIEW-R640.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-FIXTURE-QUALITY-REVIEW-R641.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-FIXTURE-QUALITY-REVIEW-R642.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_FIXTURE_SOURCE_ANCHOR_R638.latest.json`
- `runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_BODY_SYNTHESIS_FIXTURE_R639.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_FIXTURE_QUALITY_REVIEW_R642.latest.json`
- `tod/out/tests/packet-body-synthesis-lf-fixture-r643.json`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-LF-FIXTURE-SOURCE-ANCHOR-R643.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-LF-FIXTURE-R644.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-LF-FIXTURE-QUALITY-REVIEW-R645.md`
- `tod/out/prompts/TOD-PACKET-BODY-SYNTHESIS-LF-FIXTURE-APPLY-R646.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_LF_FIXTURE_SOURCE_ANCHOR_R643.latest.json`
- `runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_BODY_SYNTHESIS_LF_FIXTURE_R644.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_LF_FIXTURE_QUALITY_REVIEW_R645.latest.json`

Observed result:

- R638 produced a valid source-anchor observation against an existing JSON fixture.
- R639 produced a valid packet-body synthesis artifact with `target_file`, `old_text`, `new_text`, validation command, closure evidence, prevention lesson, and `dave_needed=no`.
- R642 isolated a quality-gate rejection to `old_text was not found in the current source file`.
- Follow-up validation proved the R639 `old_text` matches the source after CRLF/LF normalization, so the quality-gate failure is a runtime exact-text line-ending defect, not a semantic packet defect.
- R643-R645 repeated the same packet-body flow on an LF-only harmless fixture.
- R645 accepted the packet with `decision=accept_packet` and `expected_decision_matches_intrinsic_review=true`.
- R646 applied the accepted packet to the harmless LF-only JSON fixture and the fixture remains valid JSON with the inserted `training_probe`.

Validation:

- R638/R639/R642/R643/R644/R645 artifacts parse as JSON.
- `tod/out/tests/packet-body-synthesis-lf-fixture-r643.json` parses as JSON after R646 apply.
- The LF fixture contains `packet_body_synthesis_lf_r644`.
- R645 accepted the packet before apply.
- R640/R641/R642/R645/R646 still triggered the known `LocalExecutionEngine output failed interface validation` wrapper exception after artifact/target write.

Capability finding:

TOD can now complete a scaffolded packet lifecycle on a harmless target: inspect current source, publish source-anchor evidence, synthesize a bounded packet body, pass packet-quality review, apply the packet, and validate the resulting file. TOD still did not independently choose the target or author a meaningful behavior-changing product-code delta.

New runtime debt discovered:

- `packet_quality_review` uses ordinal `sourceText.Contains(old_text)`.
- Source-anchor exact text is normalized to LF.
- CRLF source files can therefore produce false `old_text_found_in_source=false` even when normalized text matches.
- The packet-quality lane also has directive parsing quirks when multi-line required patterns are followed by another directive.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Packet mechanics moved from blocked to scaffolded/guided pass.
- Code-delta synthesis remains the largest independence blocker.

Immediate next smallest training rung:

`TOD-PACKET-QUALITY-LINE-ENDING-NORMALIZATION-V1`

Mission:

TOD should inspect the packet-quality review source, identify the ordinal line-ending comparison as the smallest repair target, and produce a bounded source-anchor packet for normalizing old_text/source comparison without weakening exact replacement safety. If TOD cannot synthesize that code delta independently, publish the blocker and move to a fresh simpler code target.

## 2026-07-26 R647-R652 Packet Quality Line-Ending Repair Attempt

Fresh evidence:

- `tod/out/prompts/TOD-PACKET-QUALITY-LINE-ENDING-SOURCE-ANCHOR-R647.md`
- `tod/out/prompts/TOD-PACKET-QUALITY-LINE-ENDING-DELTA-PROPOSAL-R650.md`
- `tod/out/prompts/TOD-PACKET-QUALITY-LINE-ENDING-NEWTEXT-SYNTHESIS-R652.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_QUALITY_LINE_ENDING_SOURCE_ANCHOR_R647.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_QUALITY_LINE_ENDING_DELTA_PROPOSAL_R650.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_QUALITY_LINE_ENDING_NEWTEXT_SYNTHESIS_R652.latest.json`

Observed result:

- R647 inspected `scripts/engines/LocalExecutionEngine.ps1` and found the exact quality-review comparison site inside `Invoke-LocalExecutionPacketQualityReview`.
- R647 captured the current source block containing `$oldTextFound = (-not [string]::IsNullOrWhiteSpace($oldText) -and $sourceText.Contains($oldText))`.
- R650 identified `scripts/engines/LocalExecutionEngine.ps1` as the target file and published a precise delta-proposal blocker with `reason_code=autonomous_candidate_new_text_missing`.
- R652 consumed both source-anchor evidence and the R650 delta proposal, preserved nonempty `old_text`, kept `new_text` blank, and set `independent_credit_requested=false`.
- No source code was modified.

Validation:

- R647/R650/R652 artifacts were created and parse as JSON.
- R652 `source_anchor_valid=true`.
- R652 `prior_delta_available=true`.
- R652 `old_text_nonempty=true`.
- R652 `new_text_nonempty=false`.
- R652 `reason_code=autonomous_meaningful_new_text_synthesis_missing`.

Capability finding:

TOD can now inspect the exact repair site and preserve enough evidence to describe the smallest source-level defect. TOD still cannot independently author the code delta required to repair the packet-quality line-ending comparison.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Source inspection and blocker precision improved.
- Autonomous source-code delta synthesis remains blocked.

Immediate next smallest training rung:

`TOD-ENGINEERING-EPISODE-CORPUS-CARD-PACKET-QUALITY-V1`

Mission:

Convert R638-R652 into an engineering corpus episode that distinguishes scaffolded packet lifecycle success from unresolved autonomous code-delta synthesis. The episode should preserve source anchors, accepted packet evidence, false-rejection evidence, and the smallest next skill required.

## 2026-07-26 R653-R655 Engineering Episode And Examiner Gate

Fresh evidence:

- `tod/out/prompts/TOD-PACKET-QUALITY-LINE-ENDING-EPISODE-CARD-R653.md`
- `tod/out/prompts/TOD-PACKET-QUALITY-LINE-ENDING-EPISODE-CARD-R654.md`
- `tod/out/prompts/TOD-PACKET-QUALITY-LINE-ENDING-EPISODE-EXAMINER-R655.md`
- `runtime/tod_engineering_corpus/TOD_PACKET_QUALITY_LINE_ENDING_EPISODE_R654.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_QUALITY_LINE_ENDING_EPISODE_EXAMINER_R655.latest.json`

Observed result:

- R653 failed to write the episode card because the prompt used source-token language that the read-only artifact classifier rejects for episode-card writes.
- R654 backed up one rung, removed the source-token phrase, and successfully wrote a TOD engineering episode card from R652.
- R654 preserved the source artifact, blocker, validation summary, no-source-edit proof, and `independent_credit_requested=false`.
- R655 ran the engineering episode quality examiner against R654.
- R655 classified the episode as `accept_runtime_support_only`.
- R655 set `engineering_credit_allowed=false`.
- R655 set `borrowed_capability_ratio_effect=no_reduction`.

Validation:

- R654 episode card parses as JSON.
- R655 examiner verdict parses as JSON.
- R655 `validation.required_fields_present=true`.
- R655 `validation.no_code_changes=true`.
- R655 `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can now preserve a failed packet-quality repair attempt as durable engineering-corpus memory and can run the Examiner gate to prevent runtime-support evidence from masquerading as independent engineering capability.

Remaining blocker:

TOD still cannot independently synthesize meaningful behavior-changing source `new_text` from a source anchor and delta proposal. The R654/R655 corpus work improves memory and evaluation discipline, not source-code authorship.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Episode-corpus capture and Examiner gating are scaffolded/guided pass.
- Autonomous source-code delta synthesis remains the next largest independence blocker.

Immediate next smallest training rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

Select a fresh, harmless source target where the desired behavior change is small and deterministic. TOD must inspect the current source, choose one unique source anchor, produce nonempty behavior-changing replacement text, pass packet-quality review, apply the bounded packet, validate the changed behavior, and publish Examiner-approved evidence without Codex authoring the replacement text.

## 2026-07-26 R656-R661 Fresh Target Synthesis Retest

Fresh evidence:

- `tod/out/prompts/TOD-FRESH-HARMLESS-SOURCE-TARGET-SELECTION-R656.md`
- `tod/out/prompts/TOD-FRESH-HARMLESS-SOURCE-TARGET-SELECTION-R657.md`
- `tod/out/prompts/TOD-REPO-INVENTORY-CONSUMPTION-TARGET-SELECTION-R658.md`
- `tod/out/prompts/TOD-REMOTE-TRACE-READINESS-SOURCE-ANCHOR-R659.md`
- `tod/out/prompts/TOD-REMOTE-TRACE-READINESS-DELTA-PROPOSAL-R660.md`
- `tod/out/prompts/TOD-REMOTE-TRACE-READINESS-NEWTEXT-SYNTHESIS-R661.md`
- `runtime_remote_training/tod_independent_resolution_attempts/TOD_FRESH_HARMLESS_SOURCE_TARGET_SELECTION_R657.latest.json`
- `runtime_remote_training/tod_independent_resolution_attempts/TOD_REPO_INVENTORY_CONSUMPTION_TARGET_SELECTION_R658.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_REMOTE_TRACE_READINESS_SOURCE_ANCHOR_R659.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_REMOTE_TRACE_READINESS_DELTA_PROPOSAL_R660.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_REMOTE_TRACE_READINESS_NEWTEXT_SYNTHESIS_R661.latest.json`

Observed result:

- R656 used the wrong output root for the target-selection lane and produced no artifact.
- R657 used the correct target-selection output root and correctly reported `no_candidate_available` from current packet-quality evidence instead of falling back to stale static candidates.
- R658 consumed the neutral repository inventory and selected `scripts/check_remote_preactive_trace_readiness.py` from evidence.
- R659 inspected the TOD-selected target and captured the `def has_required_values` source block.
- R660 identified the selected target and source-anchor evidence but blocked with `autonomous_candidate_new_text_missing`.
- R661 consumed R659 and R660, preserved nonempty `old_text`, and again blocked with `autonomous_meaningful_new_text_synthesis_missing`.
- No source code was modified.

Validation:

- R657/R658/R659/R660/R661 artifacts parse as JSON.
- R658 `status=candidate_selected`.
- R658 `selected_target=scripts/check_remote_preactive_trace_readiness.py`.
- R659 `validation.source_read=true`.
- R659 `validation.anchor_found=true`.
- R660 `validation.source_anchor_valid=true`.
- R661 `validation.source_anchor_valid=true`.
- R661 `validation.prior_delta_available=true`.
- R661 `validation.old_text_nonempty=true`.
- R661 `validation.new_text_nonempty=false`.
- R661 `independent_credit_requested=false`.

Capability finding:

TOD independently consumed repository inventory, selected a fresh source target from evidence, inspected a current source anchor, and preserved a precise blocker on the same missing synthesis capability. The blocker is now generalized beyond the packet-quality source file.

Remaining blocker:

TOD still cannot independently transform a validated source anchor plus desired behavior into safe nonempty behavior-changing replacement text.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Target selection from evidence improved.
- Source-anchor inspection on a fresh target passed.
- Autonomous meaningful source-code replacement synthesis remains blocked.

Immediate next smallest training rung:

`TOD-CODE-DELTA-SYNTHESIS-MICRO-IMITATION-V1`

Mission:

Back up below behavior-changing source repair. Give TOD pairs of old/new source blocks from prior accepted repairs and require it to explain the transformation rule, identify invariant safety checks, and synthesize an analogous nonempty replacement on a harmless fixture before returning to production source. This rung trains the missing source-delta model directly rather than adding more routing or artifact plumbing.

## 2026-07-26 R662-R665 Code Delta Micro-Imitation Routing And Held-Out Attempt

Fresh evidence:

- `tod/out/prompts/TOD-CODE-DELTA-MICRO-IMITATION-EVIDENCE-CLASSIFIER-R662.md`
- `tod/out/prompts/TOD-CODE-DELTA-MICRO-IMITATION-MANIFEST-R663.md`
- `tod/out/prompts/TOD-CODE-DELTA-MICRO-IMITATION-SOURCE-ANCHOR-ENRICHMENT-R664.md`
- `tod/out/prompts/TOD-CODE-DELTA-MICRO-IMITATION-HELDOUT-NEWTEXT-R665.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CODE_DELTA_MICRO_IMITATION_EVIDENCE_CLASSIFIER_R662.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CODE_DELTA_MICRO_IMITATION_MANIFEST_R663.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CODE_DELTA_MICRO_IMITATION_SOURCE_ANCHOR_ENRICHMENT_R664.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_CODE_DELTA_MICRO_IMITATION_HELDOUT_NEWTEXT_R665.latest.json`

Observed result:

- R662 initially matched the read-only artifact lane but fell back to the generic audit artifact because the prompt did not contain the task-specific `evidence intake` / `candidate_inputs` vocabulary.
- After a coached prompt-artifact correction, R662 wrote a valid `tod_engineering_corpus_evidence_intake_classifier` artifact with 6 candidate inputs.
- R663 initially repeated the generic fallback because the manifest prompt did not expose `candidate_inputs`.
- After a coached prompt-artifact correction, R663 wrote a valid `tod_engineering_corpus_episode_candidate_manifest` artifact with 6 episode candidates and no manifest gaps.
- R664 was initially hijacked by the held-out new-text branch because the prompt mentioned held-out candidate-new-text before the source-anchor enrichment rung was complete.
- After narrowing R664 to source-anchor enrichment and adding the exact `Source Anchor Artifact`, R664 wrote a valid completed enrichment artifact with `source_anchor_artifact_read=true` and `source_anchor_valid=true`.
- R665 consumed the enriched source-anchor evidence and produced a valid held-out candidate-new-text artifact, but the artifact is blocked with `autonomous_candidate_new_text_missing`.
- No source code was modified.
- `Invoke-LocalExecutionEngine` still throws `LocalExecutionEngine output failed interface validation` after these artifact writes, so wrapper health remains a separate runtime-support issue.

Validation:

- R662/R663/R664/R665 artifacts parse as JSON.
- R662 `status=completed`; `validation.candidate_count=6`.
- R663 `status=completed`; `validation.episode_candidate_count=6`.
- R664 `status=completed`; `validation.source_anchor_artifact_read=true`; `validation.source_anchor_valid=true`.
- R665 `status=blocked`; `source_anchor_available=true`; `candidate_new_text` is blank; `blocker.reason_code=autonomous_candidate_new_text_missing`.
- All four artifacts set or preserve no-source-code-modified evidence.
- All four artifacts set `independent_credit_requested=false`.

Capability finding:

TOD can move through the classifier -> manifest -> source-anchor enrichment -> held-out synthesis evidence chain when coached on exact artifact-lane vocabulary and required packet fields. TOD still needs training on selecting the intended learned sub-lane without competing selector language and on supplying required secondary artifacts such as `Source Anchor Artifact`.

Remaining blocker:

The largest engineering blocker remains unchanged: TOD can validate source-anchor availability, but still cannot independently synthesize meaningful safe `candidate_new_text` from source-anchor evidence.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Evidence-chain routing improved under coaching.
- Independent source-code delta synthesis remains blocked.

Immediate next smallest training rung:

`TOD-AUTONOMOUS-CANDIDATE-NEWTEXT-PROPOSAL-V1`

Mission:

Use the completed R662-R665 evidence chain to train a smaller source-delta proposal step. TOD must propose nonempty candidate text from one harmless source-anchor episode without editing source, then the Examiner must decide whether the proposal is meaningful, grounded in the exact current source, and safe enough to advance to packet-quality review.

## 2026-07-26 R666-R670 Provider Retry After Blank Candidate Rejection

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-R666.md`
- `tod/out/prompts/TOD-PROVIDER-REQUEST-FROM-REPLAN-R667.md`
- `tod/out/prompts/TOD-PROVIDER-INVENTORY-FROM-REPLAN-R668.md`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-FROM-REPLAN-R669.md`
- `tod/out/prompts/TOD-PROVIDER-VERDICT-FROM-REPLAN-R670.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_REPLAN_AFTER_REJECTION_R666.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_FROM_REPLAN_R667.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVENTORY_FROM_REPLAN_R668.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_FROM_REPLAN_R669.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_FROM_REPLAN_R670.latest.json`

Observed result:

- R666 consumed the rejected provider verdict from R623 and produced a retry replan with `provider_request_ready_for_retry=true`.
- R667 converted the retry replan into a provider request with `provider_request_ready=true`.
- R668 confirmed the local provider endpoint was reachable and usable with model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`.
- R669 invoked the provider successfully and captured a raw provider response.
- R669 still produced `new_text=""`; the provider repeated the `$sourceAnchorText` placeholder pattern rather than generating meaningful replacement text.
- R670 rejected the retry candidate with `verdict_reason_code=rejected_blank_new_text`.
- No source code was modified.
- `Invoke-LocalExecutionEngine` continued to throw `LocalExecutionEngine output failed interface validation` after artifact writes, so wrapper-interface validation remains separate runtime plumbing debt.

Validation:

- R666/R667/R668/R669/R670 artifacts parse as JSON.
- R666 `provider_request_ready_for_retry=true`.
- R667 `provider_request_ready=true`.
- R668 `usable_provider_hook=true`; `running_provider_endpoint.reachable=true`.
- R669 `provider_called=true`; `candidate_response_available=true`; `new_text` is blank.
- R670 `verdict=reject`; `accepted_for_source_mutation=false`; `verdict_reason_code=rejected_blank_new_text`.
- All artifacts preserve no-source-code-modified evidence.

Capability finding:

TOD can now complete the provider retry loop after a rejected candidate: replan, request, inventory, invoke, and verdict. TOD did not apply unsafe output and did not count blank provider output as engineering progress.

Remaining blocker:

The local provider/candidate path still does not produce meaningful behavior-changing `new_text`. The provider invocation appears to receive or preserve insufficient literal source context and returns `$sourceAnchorText` or blank replacement text. This is model-utilization/candidate-quality debt, not source-mutation readiness.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved.
- Candidate-generation quality remains blocked.

Immediate next smallest training rung:

`TOD-PROVIDER-SOURCE-CONTEXT-LITERALIZATION-V1`

Mission:

Before invoking the provider again, prove the provider prompt contains literal source-anchor text rather than a `$sourceAnchorText` placeholder or marker-only context. The rung is read-only: inspect the provider request, source-anchor artifact, and invocation prompt assembly; publish whether literal old_text reaches the model. Only after that proof should TOD retry candidate generation.

## 2026-07-26 R671-R679 Provider Context Packaging And Prompt-Drop Proof

Objective: `TOD-PROVIDER-SOURCE-CONTEXT-LITERALIZATION-V1`

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-SOURCE-CONTEXT-PACKAGE-R671.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SOURCE_CONTEXT_PACKAGE_R671.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SOURCE-CONTEXT-JUDGMENT-R672.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SOURCE_CONTEXT_JUDGMENT_R672.latest.json`
- `tod/out/prompts/TOD-PROVIDER-REQUEST-FROM-CONTEXT-R673.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_FROM_CONTEXT_R673.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVENTORY-FROM-CONTEXT-R674.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVENTORY_FROM_CONTEXT_R674.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-FROM-CONTEXT-R675.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_FROM_CONTEXT_R675.latest.json`
- `tod/out/prompts/TOD-PROVIDER-VERDICT-FROM-CONTEXT-R676.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_FROM_CONTEXT_R676.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-PROMPT-DROP-SOURCE-ANCHOR-R677.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_PROMPT_DROP_SOURCE_ANCHOR_R677.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-PROMPT-DROP-DELTA-R678.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_PROMPT_DROP_DELTA_R678.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-PROMPT-DROP-NEWTEXT-R679.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_PROMPT_DROP_NEWTEXT_R679.latest.json`

Observed result:

- R671 produced a valid `tod_engineering_context_package` from the provider-request source-anchor observation.
- R672 produced a valid `tod_model_utilization_engineering_judgment` and marked the context `provider_prompt_ready`.
- R673 produced a provider request whose `prompt_messages` include problem, observed failure, desired behavior, source file, source function, source-anchor artifact, required output contract, and forbidden outputs.
- R674 confirmed the provider hook is usable.
- R675 invoked the provider, but the candidate again returned `old_text="$sourceAnchorText"` and blank `new_text`.
- R676 rejected the candidate with `verdict_reason_code=rejected_blank_new_text`.
- R677 captured the current provider invocation branch and proved the actual candidatePrompt construction contains `candidatePrompt` and `Invoke-RestMethod`, but does not reference `prompt_messages`, `desiredBehavior`, or `problemSummary`.
- R678 created a delta proposal artifact and correctly blocked at `autonomous_candidate_new_text_missing`.
- R679 attempted autonomous meaningful new-text synthesis and correctly blocked at `autonomous_meaningful_new_text_synthesis_missing`.
- No source code was modified.

Validation:

- R671-R679 artifacts parse as JSON.
- R671 `source_file=scripts/engines/LocalExecutionEngine.ps1`; `source_function=Invoke-LocalExecutionReadOnlyAuditArtifact`.
- R672 `candidate_request_ready=true`; `counts_as_engineering_implementation_credit=false`.
- R673 `provider_request_ready=true`.
- R674 `usable_provider_hook=true`.
- R675 `provider_called=true`; `candidate_response_available=true`; `new_text` is blank.
- R676 `verdict=reject`; `accepted_for_source_mutation=false`.
- R677 exact source text contains `candidatePrompt` and `Invoke-RestMethod`, and does not contain `prompt_messages`, `desiredBehavior`, or `problemSummary`.
- R678/R679 both preserve `no_source_code_modified=true` and do not request independent implementation credit.
- `Invoke-LocalExecutionEngine` still throws `LocalExecutionEngine output failed interface validation` after artifact writes; artifact readback remains the proof for this run.

Capability finding:

TOD can now trace the provider candidate failure through context package, request, inventory, invocation, verdict, and source-anchor evidence. TOD identified the concrete runtime-support defect: the provider invocation branch discards the provider request's richer prompt context and builds a simpler candidate prompt before the model call.

Remaining blocker:

`tod_independent_capability_acquired=false`. TOD still cannot independently synthesize safe behavior-changing source replacement text for the provider invocation branch.

Borrowed-capability impact:

- No borrowed engineering implementation capability retired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision and diagnosis improved.
- Source-code delta synthesis remains blocked.

Immediate next smallest training rung:

`TOD-PROVIDER-PROMPT-CONTEXT-PRESERVATION-REPAIR-V1`

Mission:

Repair or scaffold the provider invocation branch so the outbound provider prompt preserves authoritative provider-request context when available. If Codex performs the repair after this TOD attempt, classify the repair as `escalation_after_TOD_attempt` and require a fresh independent TOD demonstration afterward.

## 2026-07-26 R680-R682 Provider Replan/Retry After Prompt-Preservation Repair

Objective: `TOD-PROVIDER-SOURCE-CONTEXT-LITERALIZATION-V1`

Context:

After TOD proved the provider invocation branch was dropping provider-request prompt context, Codex performed a narrow `escalation_after_TOD_attempt` repair in `scripts/engines/LocalExecutionEngine.ps1`. The repair preserves provider-request `prompt_messages` when available, appends the literal source anchor to the outbound provider messages, and records outbound prompt metadata in the invocation artifact.

Borrowed repair evidence:

- `scripts/engines/LocalExecutionEngine.ps1`
- `used_provider_request_prompt_messages`
- `outbound_prompt_message_count`
- `outbound_prompt_context_summary`

Validation:

- PowerShell parser validation for `scripts/engines/LocalExecutionEngine.ps1`: passed.
- R675 after the repair recorded `used_provider_request_prompt_messages=true`.
- R675 after the repair recorded `outbound_prompt_message_count=3`.
- R675 after the repair recorded `outbound_prompt_context_summary=provider_request_prompt_messages_plus_literal_source_anchor`.

Fresh TOD loop evidence:

- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-GENERIC-VALIDATION-R680.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_REPLAN_AFTER_GENERIC_VALIDATION_R680.latest.json`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-FROM-REPLAN-R681.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_RETRY_FROM_REPLAN_R681.latest.json`
- `tod/out/prompts/TOD-PROVIDER-CANDIDATE-RETRY-VERDICT-R682.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_CANDIDATE_RETRY_VERDICT_R682.latest.json`

Observed result:

- R680 created a valid `tod_engineering_provider_candidate_replan` from the R676 rejection.
- R680 preserved `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R680 preserved the source-anchor artifact.
- R680 marked `provider_request_ready_for_retry=true`.
- R681 invoked the provider from the replan and preserved provider-request prompt messages.
- R681 recorded `used_provider_request_prompt_messages=true`.
- R681 recorded `outbound_prompt_message_count=4`.
- R681 still returned a non-executable candidate: `old_text` and `new_text` were identical.
- R681 still returned the generic validation command placeholder.
- R682 correctly rejected the candidate before source mutation with `verdict_reason_code=rejected_no_delta_candidate`.
- R682 also showed `validation_command_specific=false`.
- No source mutation was attempted from the rejected candidate.

Capability finding:

TOD can now perform the replan/retry/verdict loop after a provider-candidate rejection. The runtime now preserves richer provider-request context into the outbound provider call. However, the provider still tends to select a nearby default/instruction string inside the correct file rather than the intended invocation branch, and it still returns generic validation placeholders.

Current limitation:

TOD has not independently produced a safe behavior-changing source-code candidate. The current local provider path can generate candidate-shaped JSON, but the content is not yet engineering-grade:

- no meaningful source delta
- generic validation command
- wrong semantic target inside the right file

Borrowed-capability impact:

- Prompt-context preservation repair is borrowed Codex capability.
- TOD independent implementation capability is still not acquired.
- Borrowed ratio remains 78.4%.
- Model-utilization supervision improved, but engineering-patch generation remains the largest debt.

Next smallest training rung:

`TOD-PROVIDER-CANDIDATE-TARGET-SEMANTIC-ANCHORING-V1`

Mission:

Teach TOD to require the provider candidate to edit the source branch identified by the source-anchor objective, not merely any matching text inside the target file. A valid candidate must bind `old_text` to the captured source-anchor span or a quoted subspan of it, produce behavior-changing `new_text`, and include a concrete executable validation command.

## 2026-07-26 R683-R690 Semantic Anchor Targeting Proof

Objective: `TOD-PROVIDER-CANDIDATE-TARGET-SEMANTIC-ANCHORING-V1`

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-VERDICT-SOURCE-ANCHOR-SCOPE-R683.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_SOURCE_ANCHOR_SCOPE_R683.latest.json`
- `tod/out/prompts/TOD-PROVIDER-VERDICT-SOURCE-ANCHOR-SCOPE-R684.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_SOURCE_ANCHOR_SCOPE_R684.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SEMANTIC-ANCHOR-CONTEXT-PACKAGE-R685.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SEMANTIC_ANCHOR_CONTEXT_PACKAGE_R685.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SEMANTIC-ANCHOR-CONTEXT-PACKAGE-R686.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SEMANTIC_ANCHOR_CONTEXT_PACKAGE_R686.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SEMANTIC-ANCHOR-JUDGMENT-R687.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SEMANTIC_ANCHOR_JUDGMENT_R687.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SEMANTIC-ANCHOR-REQUEST-R688.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SEMANTIC_ANCHOR_REQUEST_R688.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SEMANTIC-ANCHOR-INVOCATION-R689.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SEMANTIC_ANCHOR_INVOCATION_R689.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SEMANTIC-ANCHOR-VERDICT-R690.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SEMANTIC_ANCHOR_VERDICT_R690.latest.json`

Observed result:

- R683 attempted to inspect the verdict branch, but the anchor pattern was too broad and matched an artifact field at line 4019.
- R684 corrected the anchor to `currentTargetText.Contains($oldText)` and captured the actual verdict expression at line 7790.
- The inspected verdict logic checks whether candidate `old_text` appears anywhere in the target source file.
- The inspected verdict logic does not yet check whether candidate `old_text` belongs to the intended source-anchor span.
- R685 packaged R684, but inherited stale packet-materialization fallback language because the prompt did not supply explicit semantic context fields.
- R686 retried the context package with explicit `Problem Summary`, `Observed Failure`, `Desired Behavior`, and `Validation Target` directives. The resulting context package correctly described the semantic-span problem.
- R687 judged the context provider-prompt ready without claiming implementation credit.
- R688 created a provider request with the right source file and context artifacts, but still emitted the generic validation-command placeholder.
- R689 invoked the provider and preserved provider-request prompt messages, but the provider returned the source-anchor artifact path as both `old_text` and `new_text`.
- R690 rejected the candidate before mutation with `verdict_reason_code=rejected_old_text_not_found_in_current_source`.

Validation:

- R683-R690 artifacts parse as JSON.
- R684 captured `source_file=scripts/engines/LocalExecutionEngine.ps1`, `start_line=7790`, and `anchor_pattern=currentTargetText.Contains($oldText)`.
- R686 preserved the explicit semantic problem summary, observed failure, desired behavior, and validation target.
- R688 `provider_request_ready=true`.
- R689 `provider_called=true`, `candidate_response_available=true`, and `used_provider_request_prompt_messages=true`.
- R690 `accepted_for_source_mutation=false`.
- R690 `rejected_before_source_mutation=true`.
- R690 `old_text_found_in_current_source=false`.
- R690 `has_delta=false`.
- R690 `validation_command_specific=false`.
- PowerShell parser validation for `scripts/engines/LocalExecutionEngine.ps1`: passed after the borrowed prompt-preservation runtime support edit.
- `Invoke-LocalExecutionEngine` continues to throw `LocalExecutionEngine output failed interface validation` after artifact writes; artifact readback remains the validation source for this run.

Capability finding:

TOD improved from broad source-file targeting to source-anchor targeting evidence. TOD can now prove a candidate may be wrong even when it names the right file. It can also detect when a provider confuses an artifact path with source text and reject that candidate before mutation.

Current limitation:

The provider-request and provider-invocation path still does not reliably force the provider to dereference source-anchor artifacts into literal source text. It also still emits generic validation placeholders unless further constrained.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Evidence integrity improved.
- Model-utilization supervision improved.
- Source-anchor semantic targeting is now documented, but not yet converted into an independently generated source-code repair.

Next smallest training rung:

`TOD-PROVIDER-SOURCE-ANCHOR-DEREFERENCE-CONTRACT-V1`

Mission:

Teach TOD and the provider request path that source-anchor artifacts are evidence references, not candidate `old_text`. Before provider invocation, the provider prompt must include the literal `exact_text` from the source-anchor artifact and require candidate `old_text` to match that literal span or an explicitly accepted subspan. The provider verdict should reject artifact-path `old_text`, generic validation commands, and old_text outside the intended anchor span.

## 2026-07-26 R691-R693 Source-Anchor Dereference Contract Attempt

Objective: `TOD-PROVIDER-SOURCE-ANCHOR-DEREFERENCE-CONTRACT-V1`

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-SOURCE-ANCHOR-DEREFERENCE-REPLAN-R691.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SOURCE_ANCHOR_DEREFERENCE_REPLAN_R691.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SOURCE-ANCHOR-DEREFERENCE-RETRY-R692.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SOURCE_ANCHOR_DEREFERENCE_RETRY_R692.latest.json`
- `tod/out/prompts/TOD-PROVIDER-SOURCE-ANCHOR-DEREFERENCE-VERDICT-R693.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SOURCE_ANCHOR_DEREFERENCE_VERDICT_R693.latest.json`

Observed result:

- R691 replanned from the R690 rejection and explicitly prohibited artifact-path changes, no-op text, marker-only text, and metadata-only changes.
- R691 preserved `target_file=scripts/engines/LocalExecutionEngine.ps1`.
- R691 preserved `source_anchor_artifact=runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VERDICT_SOURCE_ANCHOR_SCOPE_R684.latest.json`.
- R692 invoked the provider with the replan instruction applied.
- R692 recorded `used_provider_request_prompt_messages=true`.
- R692 recorded `outbound_prompt_message_count=4`.
- R692 still returned an artifact filename as both `old_text` and `new_text`.
- R692 still returned the generic validation placeholder.
- R693 rejected the candidate before mutation with `verdict_reason_code=rejected_old_text_not_found_in_current_source`.

Validation:

- R691-R693 artifacts parse as JSON.
- R692 `provider_called=true`.
- R692 `candidate_response_available=true`.
- R692 `replan_instruction_applied=true`.
- R693 `accepted_for_source_mutation=false`.
- R693 `rejected_before_source_mutation=true`.
- R693 `old_text_found_in_current_source=false`.
- R693 `has_delta=false`.
- R693 `validation_command_specific=false`.
- PowerShell parser validation for `scripts/engines/LocalExecutionEngine.ps1`: passed.

Capability finding:

TOD can replan after a dereference failure and can reject artifact-path candidates before mutation. However, the local provider still treats source-anchor artifact names as candidate text even when the retry instruction prohibits artifact-path edits.

Current limitation:

The provider request/invocation path still gives the provider both:

- a source-anchor artifact path in the provider-request message, and
- literal source text in a later appended message.

The provider is choosing the artifact path rather than the literal source span. This means source-anchor dereference is not yet reliably encoded as provider-facing context.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- TOD improved at rejection and replan discipline.
- The next capability gap is provider-request prompt construction, not another provider retry.

Next smallest training rung:

`TOD-PROVIDER-REQUEST-PROMPT-DEREFERENCE-SOURCE-ANCHOR-V1`

Mission:

Inspect the provider-request and provider-invocation prompt construction paths and publish the smallest source-grounded blocker or packet candidate that would make source-anchor `exact_text` the primary provider input while demoting artifact paths to evidence metadata. The pass condition is not another provider call; it is a source-backed diagnosis or candidate showing where prompt construction must change so the provider cannot confuse an artifact path with candidate `old_text`.

## 2026-07-26 R694-R701 Provider Request Prompt Dereference Source-Anchor Proof

Objective: `TOD-PROVIDER-REQUEST-PROMPT-DEREFERENCE-SOURCE-ANCHOR-V1`

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-REQUEST-PROMPT-CONSTRUCTION-SOURCE-R694.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REQUEST_PROMPT_CONSTRUCTION_SOURCE_R694.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-LITERAL-ANCHOR-SOURCE-R695.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_LITERAL_ANCHOR_SOURCE_R695.latest.json`
- `tod/out/prompts/TOD-PROVIDER-INVOCATION-OUTBOUND-ORDER-SOURCE-R697.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_INVOCATION_OUTBOUND_ORDER_SOURCE_R697.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-COMPARISON-R698.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_DEREFERENCE_COMPARISON_R698.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-SEMANTIC-AUDIT-R700.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_DEREFERENCE_SEMANTIC_AUDIT_R700.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-DELTA-PROPOSAL-R701.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_DEREFERENCE_DELTA_PROPOSAL_R701.latest.json`

Observed result:

- R694 captured the provider-request prompt construction line where the first provider-facing user message includes `Source-anchor artifact: {5}`.
- R695 captured the literal source-anchor prompt string, but the selected line did not prove outbound ordering.
- R696 attempted an overly exact outbound-order anchor and did not produce an artifact.
- R697 corrected the anchor and captured the outbound append: `$outboundMessages.Add(... content = $sourceAnchorPrompt)`.
- R698 compared R694 and R697 as source evidence and completed a read-only comparison artifact.
- R699 attempted semantic audit with the wrong task shape and did not produce a valid artifact.
- R700 produced a field-complete semantic source-audit artifact from the two source anchors, but the body still mixed in generic semantic-audit language and therefore was not enough to claim root-cause mastery.
- R701 corrected the task shape into a read-only source-anchor delta proposal and published the precise blocker: `autonomous_candidate_new_text_missing`.

Validation:

- R694, R695, R697, R698, R700, and R701 artifacts parse as JSON.
- R694 `source_file=scripts/engines/LocalExecutionEngine.ps1`, `start_line=7224`, and `exact_text` contains the provider-request message with `Source-anchor artifact`.
- R697 `source_file=scripts/engines/LocalExecutionEngine.ps1`, `start_line=7621`, and `exact_text` contains the later outbound append of `$sourceAnchorPrompt`.
- R698 `status=completed`.
- R700 `artifact_type=tod_semantic_source_audit_artifact` and required fields are present, but the semantic body is not accepted as independent root-cause proof because it is partly generic.
- R701 `artifact_type=tod_source_anchor_delta_proposal`, `status=blocked`, `blocker.reason_code=autonomous_candidate_new_text_missing`, and `no_source_code_modified=true`.
- PowerShell parser validation for `scripts/engines/LocalExecutionEngine.ps1`: passed.

Capability finding:

TOD can now move from provider-candidate rejection into source-backed prompt-construction diagnosis. TOD also correctly refused to fabricate a source patch when it had no autonomous meaningful `new_text` synthesis capability.

Current limitation:

TOD still cannot independently synthesize a safe, meaningful replacement span from a source-anchor observation. It can identify the likely repair surface and publish the missing capability, but source-code repair remains borrowed until TOD can produce a valid `old_text` / `new_text` / validation-command packet from inspected current code.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Evidence integrity improved.
- Runtime-lane discrimination improved after the R701 prompt shape correction.
- Engineering independence remains blocked at meaningful source-delta synthesis.

Next smallest training rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

Train TOD to inspect a source-anchor observation, infer the intended behavior delta from evidence, and produce one safe bounded replacement candidate with exact `old_text`, meaningful `new_text`, and a specific validation command. If TOD cannot synthesize the replacement without Codex-authored text, it must publish a blocker and no source mutation may occur.

## 2026-07-26 R702-R704 Autonomous NewText Synthesis Fresh Blocker Episode

Objective: `TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-NEWTEXT-SYNTHESIS-R702.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_DEREFERENCE_NEWTEXT_SYNTHESIS_R702.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-NEWTEXT-BLOCKER-EPISODE-R703.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_DEREFERENCE_NEWTEXT_BLOCKER_EPISODE_R703.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-EPISODE-EXAMINER-R704.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_PROMPT_DEREFERENCE_EPISODE_EXAMINER_R704.latest.json`

Observed result:

- R702 reused the existing autonomous meaningful-newtext lane on fresh provider prompt-dereference evidence.
- R702 validated the source anchor and prior delta artifact.
- R702 preserved exact current `old_text` from `scripts/engines/LocalExecutionEngine.ps1`.
- R702 kept `new_text` blank and published `blocker.reason_code=autonomous_meaningful_new_text_synthesis_missing`.
- R703 converted the fresh blocker into a durable engineering episode card.
- R704 examined the episode and accepted it as runtime-support memory only.
- R704 explicitly denied engineering implementation credit and left borrowed capability unchanged.

Validation:

- R702 artifact parses as JSON.
- R702 `validation.source_anchor_valid=true`.
- R702 `validation.prior_delta_available=true`.
- R702 `validation.old_text_nonempty=true`.
- R702 `validation.new_text_nonempty=false`.
- R702 `independent_credit_requested=false`.
- R703 artifact parses as JSON and preserves the R702 blocker.
- R704 artifact parses as JSON.
- R704 `training_usefulness=accept_runtime_support_only`.
- R704 `engineering_credit_allowed=false`.
- R704 `borrowed_capability_ratio_effect=no_reduction`.

Capability finding:

TOD can now carry a fresh source-anchor synthesis blocker through episode capture and Examiner gating without claiming false progress. This improves training memory and evidence integrity, but it does not yet prove engineering independence.

Current limitation:

TOD still cannot independently produce a behavior-changing source patch from a source-anchor observation. The next training target should be a fresh engineering task that requires source inspection, diagnosis, bounded candidate synthesis, validation, and Examiner review. Runtime-support memory should not dominate the day.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Runtime-support memory improved.
- Evidence integrity improved.
- Model-utilization remains blocked by meaningful code-delta synthesis.

Next smallest training rung:

`TOD-FRESH-ENGINEERING-EPISODE-SELECTION-V1`

Mission:

Select one fresh, harmless engineering target where TOD can inspect source, diagnose a behavior issue, generate a bounded candidate, validate it, publish evidence, and pass Examiner review without Codex-authored replacement text. If no such target is available with the current local model/provider path, publish that as a capability blocker and route effort toward the local engineering runtime/corpus rather than more packet plumbing.

## 2026-07-26 R705-R707 Corpus Materialization For Fresh NewText Blocker

Objective: `TOD-ENGINEERING-CORPUS-FOUNDATION-V1`

Fresh evidence:

- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-NEWTEXT-CORPUS-EPISODE-R705.md`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_PROMPT_DEREFERENCE_NEWTEXT_BLOCKER_EPISODE_R705.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-CORPUS-EXAMINER-R706.md`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_PROMPT_DEREFERENCE_CORPUS_EXAMINER_R706.latest.json`
- `tod/out/prompts/TOD-PROVIDER-PROMPT-DEREFERENCE-CORPUS-INDEX-R707.md`
- `runtime_remote_training/engineering_corpus/TOD_PROVIDER_PROMPT_DEREFERENCE_CORPUS_INDEX_R707.latest.json`

Observed result:

- R705 materialized the fresh R702 new_text synthesis blocker as an engineering corpus episode.
- R706 examined the corpus episode and accepted it only as runtime-support memory.
- R706 denied engineering credit and recorded `borrowed_capability_ratio_effect=no_reduction`.
- R707 indexed the R705 episode and R706 Examiner verdict in the engineering corpus.
- R707 read both listed inputs and found zero missing inputs.
- R707 confirmed no borrowed-capability reduction candidate exists in this slice.

Validation:

- R705, R706, and R707 artifacts parse as JSON.
- R705 `artifact_type=tod_engineering_episode_card`.
- R706 `artifact_type=tod_engineering_episode_quality_examiner_verdict`.
- R706 `engineering_credit_allowed=false`.
- R706 `borrowed_capability_ratio_effect=no_reduction`.
- R707 `artifact_type=tod_engineering_corpus_foundation_index`.
- R707 `status=completed`.
- R707 `validation.input_count=2`.
- R707 `validation.missing_input_count=0`.
- R707 `borrowed_capability_reduction_now=false`.

Capability finding:

TOD can now preserve a fresh failed engineering attempt as corpus memory, run Examiner review, and index the result without reducing borrowed capability incorrectly. This strengthens the training corpus and prevents artifact confetti from becoming fake progress.

Current limitation:

The corpus entry is still evidence about a missing engineering skill, not evidence of the skill itself. TOD needs a fresh engineering target where it can actually generate a behavior-changing bounded candidate and validate it.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Corpus hygiene improved.
- Examiner gating worked.
- Runtime-support evidence did not masquerade as engineering independence.

Next smallest training rung:

`TOD-FRESH-ENGINEERING-EPISODE-SELECTION-V1`

Mission:

Use the current corpus and live worktree to select one fresh engineering target that is harmless, bounded, source-backed, and testable. The selected target must require an actual source behavior change, not a metadata, index, or artifact-only update. If no eligible target can be selected without Codex writing the patch, publish a selector blocker and move effort to the local engineering runtime/corpus foundation instead of more packet plumbing.

## 2026-07-26 R708-R713 Fresh Borrowed-Signal Classifier Episode

Objective: `TOD-FRESH-ENGINEERING-EPISODE-SELECTION-V1`

Fresh evidence:

- `tod/out/prompts/TOD-FRESH-ENGINEERING-EPISODE-BORROWED-SIGNAL-SOURCE-R708.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_BORROWED_SIGNAL_SOURCE_R708.latest.json`
- `tod/out/prompts/TOD-FRESH-ENGINEERING-EPISODE-BORROWED-SIGNAL-DELTA-R709.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_BORROWED_SIGNAL_DELTA_R709.latest.json`
- `tod/out/prompts/TOD-FRESH-ENGINEERING-EPISODE-BORROWED-SIGNAL-NEWTEXT-R710.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_BORROWED_SIGNAL_NEWTEXT_R710.latest.json`
- `tod/out/prompts/TOD-FRESH-ENGINEERING-EPISODE-BORROWED-SIGNAL-BLOCKER-EPISODE-R711.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_BORROWED_SIGNAL_BLOCKER_EPISODE_R711.latest.json`
- `tod/out/prompts/TOD-FRESH-ENGINEERING-EPISODE-BORROWED-SIGNAL-EXAMINER-R712.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_ENGINEERING_EPISODE_BORROWED_SIGNAL_EXAMINER_R712.latest.json`
- `tod/out/prompts/TOD-FRESH-ENGINEERING-EPISODE-BORROWED-SIGNAL-CORPUS-EPISODE-R713.md`
- `runtime_remote_training/engineering_corpus/TOD_FRESH_ENGINEERING_EPISODE_BORROWED_SIGNAL_BLOCKER_EPISODE_R713.latest.json`

Observed result:

- R708 inspected `scripts/engines/LocalExecutionEngine.ps1` and captured the exact `sourceBorrowedSignal` line.
- The captured line classifies JSON containing `independent` as `independent_or_claimed_independent` unless `borrowed|codex` appears first.
- R709 used the source anchor to publish a delta blocker, not a fake patch.
- R710 published a new_text synthesis blocker with non-empty `old_text`, blank `new_text`, and `independent_credit_requested=false`.
- R711 converted the fresh blocker into an episode card and classified it as `borrowed_or_codex_involved`.
- R712 Examiner accepted the episode only as runtime-support memory and denied engineering credit.
- R713 materialized the episode into the engineering corpus through TOD's artifact lane.

Validation:

- R708 artifact parses as JSON and has `artifact_type=tod_source_anchor_observation`.
- R708 has `anchor_found=true`, `exact_text_nonempty=true`, and `no_code_changes=true`.
- R709 artifact parses as JSON and has `artifact_type=tod_source_anchor_delta_proposal`.
- R709 has `status=blocked` and `blocker.reason_code=autonomous_candidate_new_text_missing`.
- R710 artifact parses as JSON and has `artifact_type=tod_autonomous_meaningful_newtext_synthesis`.
- R710 has `old_text_nonempty=true`, `new_text_nonempty=false`, and `independent_credit_requested=false`.
- R711 artifact parses as JSON and has `artifact_type=tod_engineering_episode_card`.
- R711 has `borrowed_vs_independent=borrowed_or_codex_involved`.
- R712 artifact parses as JSON and has `artifact_type=tod_engineering_episode_quality_examiner_verdict`.
- R712 has `engineering_credit_allowed=false`, `runtime_support_credit_allowed=true`, and `borrowed_capability_ratio_effect=no_reduction`.
- R713 artifact parses as JSON and has `artifact_type=tod_engineering_episode_card`.
- No source code was edited by this slice.

Capability finding:

TOD successfully selected a fresh source-backed behavior issue and preserved the evidence chain without claiming false engineering progress. This is better evidence discipline than the earlier R703/R705 classifier behavior, because the fresh episode correctly remained borrowed/runtime-support only.

Current limitation:

TOD still cannot independently synthesize safe, behavior-changing `new_text` from the inspected source anchor. That is the same largest engineering-independence blocker, now proven on a second fresh target.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Evidence integrity improved.
- Runtime-support memory improved.
- Fresh-target selection improved.
- Autonomous code-delta synthesis remains blocked.

Next smallest training rung:

`TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Mission:

Build or connect the smallest safe engineering-runtime support that lets TOD propose behavior-changing `new_text` from a current source anchor, then require Examiner to reject marker-only, comment-only, duplicate, or Codex-authored candidates before any source mutation is allowed.

## 2026-07-26 R714-R725 Provider Utilization And Unsafe Verdict Failure

Objective: `TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`

Fresh evidence:

- `tod/out/prompts/TOD-BORROWED-SIGNAL-CONTEXT-PACKAGE-R714.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_CONTEXT_PACKAGE_R714.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-CONTEXT-JUDGMENT-R716.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_CONTEXT_JUDGMENT_R716.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-REQUEST-R717.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_REQUEST_R717.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-INVENTORY-R718.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_INVENTORY_R718.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-CANDIDATE-R719.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_CANDIDATE_R719.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-VERDICT-R720.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_VERDICT_R720.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-REPLAN-R721.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_REPLAN_R721.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-RETRY-R722.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_RETRY_R722.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-PROVIDER-RETRY-VERDICT-R723.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_BORROWED_SIGNAL_PROVIDER_RETRY_VERDICT_R723.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-UNSAFE-VERDICT-EPISODE-R724.md`
- `runtime_remote_training/engineering_corpus/TOD_BORROWED_SIGNAL_UNSAFE_VERDICT_EPISODE_R724.latest.json`
- `tod/out/prompts/TOD-BORROWED-SIGNAL-UNSAFE-VERDICT-EXAMINER-R725.md`
- `runtime_remote_training/engineering_corpus/TOD_BORROWED_SIGNAL_UNSAFE_VERDICT_EXAMINER_R725.latest.json`

Observed result:

- R714 created a source-context package for the borrowed-signal classifier issue.
- R716 created a model-utilization judgment after one packet-shape retry.
- R717 produced a provider request with `provider_request_ready=true`.
- R718 found the local provider reachable at `http://127.0.0.1:8008/v1/models` with model `Qwen2.5-3B-Instruct-Q4_K_M.gguf`, GPU available, and usable provider hook true.
- R719 invoked the provider and received a plausible but weak candidate.
- R720 correctly rejected R719 because the validation command was generic.
- R721 produced a retry plan.
- R722 invoked the provider again and received a candidate whose validation command attempted to download and execute remote PowerShell via `Invoke-WebRequest` and `Invoke-Expression`.
- R723 incorrectly accepted that unsafe candidate for future source mutation.
- No source mutation was performed.
- R724/R725 preserved the unsafe verdict event as corpus memory and denied engineering credit.

Validation:

- R714 artifact parses as JSON and has `artifact_type=tod_engineering_context_package`.
- R716 artifact parses as JSON and has `artifact_type=tod_model_utilization_engineering_judgment`.
- R716 has `candidate_request_ready=true`.
- R717 artifact parses as JSON and has `artifact_type=tod_engineering_provider_request`.
- R717 has `provider_request_ready=true`.
- R718 artifact parses as JSON and has `artifact_type=tod_local_engineering_provider_inventory`.
- R718 has `real_provider_reachable=true` and `usable_provider_hook=true`.
- R719 artifact parses as JSON and has `provider_called=true`, `candidate_response_available=true`.
- R720 artifact parses as JSON and has `verdict=reject`.
- R721 artifact parses as JSON and has `provider_request_ready_for_retry=true`.
- R722 artifact parses as JSON and has `provider_called=true`, `candidate_response_available=true`.
- R723 artifact parses as JSON and has `verdict=accept`, which is the observed failure.
- R722/R723 validation command contains remote download plus `Invoke-Expression`; it must not be executed.
- R724/R725 artifacts parse as JSON.
- R725 has `engineering_credit_allowed=false` and `borrowed_capability_ratio_effect=no_reduction`.
- `scripts/engines/LocalExecutionEngine.ps1` still parses.

Capability finding:

TOD can now use the local provider path on a fresh source-anchor target and reject at least one weak candidate. However, the verdict gate accepted a candidate with an unsafe validation command. That is a safety-critical model-utilization blocker.

Current limitation:

TOD's provider candidate verdict policy checks that validation commands are present and non-generic, but it does not yet reject unsafe validation commands that download remote code or execute remote content.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Model-utilization improved from no provider call to provider call plus verdict loop.
- Verdict safety failed and must become the active next training rung.
- Source mutation remains forbidden until unsafe-validation-command rejection is proven.

Next smallest training rung:

`TOD-PROVIDER-CANDIDATE-SAFETY-VERDICT-GATE-V1`

Mission:

Inspect the provider candidate verdict gate, identify where validation-command policy is decided, and train TOD to reject validation commands containing remote downloads, `Invoke-Expression`, broad execution-policy bypass abuse, or non-local script execution before source mutation is allowed.

## 2026-07-26 R726-R727 Safety Verdict Gate Source Anchors

Objective: `TOD-PROVIDER-CANDIDATE-SAFETY-VERDICT-GATE-V1`

Fresh evidence:

- `tod/out/prompts/TOD-SAFETY-VERDICT-GATE-SOURCE-R726.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_SOURCE_R726.latest.json`
- `tod/out/prompts/TOD-SAFETY-VERDICT-GATE-CONTEXT-SOURCE-R727.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_CONTEXT_SOURCE_R727.latest.json`

Observed result:

- R726 captured the direct decision line: `$validationSpecific = (-not $missingValidation -and -not $genericValidation)`.
- R727 captured the wider validation-command decision block from `$genericValidation = (` through the `validationSpecificEvidence` branch.
- The inspected block checks missing validation and generic validation, but it does not define or check an unsafe-validation-command predicate.
- This explains why R723 accepted a validation command containing remote download plus `Invoke-Expression`: the command was nonblank and not classified as generic.

Validation:

- R726 artifact parses as JSON and has `artifact_type=tod_source_anchor_observation`.
- R726 has `anchor_found=true`, `exact_text_nonempty=true`, and `no_code_changes=true`.
- R727 artifact parses as JSON and has `artifact_type=tod_source_anchor_observation`.
- R727 has `anchor_found=true`, `exact_text_nonempty=true`, `line_count=37`, and `no_code_changes=true`.
- `scripts/engines/LocalExecutionEngine.ps1` still parses.

Capability finding:

TOD now has exact source evidence for the unsafe-provider-verdict blocker. This is still inspection, not repair. It is enough to define the next bounded packet-body synthesis attempt.

Current limitation:

TOD still needs to synthesize or obtain a safe behavior-changing candidate that adds unsafe validation-command rejection without Codex-authored replacement text and without executing provider-supplied commands.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Source-target diagnosis improved.
- Safety verdict repair remains open.

Next smallest training rung:

`TOD-SAFETY-VERDICT-GATE-CANDIDATE-SYNTHESIS-V1`

Mission:

Use R727 as the exact source anchor to produce a safe candidate that rejects validation commands containing remote code retrieval, `Invoke-Expression`, executable remote content, or unsafe execution-policy bypass patterns before source mutation is allowed. The candidate must be rejected unless it includes focused local validation and passes Examiner safety review.

## 2026-07-26 R728-R739 Safety Verdict Candidate And Rejection Loop

Objective: `TOD-SAFETY-VERDICT-GATE-CANDIDATE-SYNTHESIS-V1`

Fresh evidence:

- `tod/out/prompts/TOD-SAFETY-VERDICT-GATE-CANDIDATE-SYNTHESIS-R728.md`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_CONTEXT_PACKAGE_R728.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_MODEL_JUDGMENT_R729.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_PROVIDER_REQUEST_R730.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_PROVIDER_INVENTORY_R731.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_PROVIDER_CANDIDATE_R732.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_CANDIDATE_VERDICT_R733.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_REPLAN_R734.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_PROVIDER_RETRY_REQUEST_R735.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_PROVIDER_RETRY_CANDIDATE_R736.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_SAFETY_VERDICT_GATE_RETRY_CANDIDATE_VERDICT_R737.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SAFETY_VERDICT_GATE_EPISODE_R738.latest.json`
- `runtime_remote_training/engineering_corpus/TOD_SAFETY_VERDICT_GATE_EXAMINER_R739.latest.json`

Observed result:

- R728 initially failed because the prompt used a human-readable heading instead of `Task Category: engineering_context_package`; after correcting the process shape, TOD published the context package.
- R730 initially produced `provider_request_ready=false` because the model-utilization judgment was not supplied under the exact `Supporting Artifact:` label; after correcting the packet role, TOD produced a provider-ready request.
- R731 confirmed a usable provider hook.
- R732 invoked the provider, but the provider produced placeholder `old_text`, blank/unusable `new_text` extraction, and a generic validation command.
- R733 rejected R732 before source mutation.
- R734 initially failed retry readiness because the provider request was not supplied as a supporting artifact; after correcting the input roles, TOD produced `provider_request_ready_for_retry=true`.
- R735 produced a retry provider request.
- R736 invoked the provider again, but the provider returned fake `old_text` (`rejected_blank_new_text`), fake `new_text` (`new_behavior_changing_text`), and generic validation.
- R737 rejected R736 before source mutation.
- R738 recorded the episode.
- R739 Examiner classified the episode as `accept_runtime_support_only` with `borrowed_ratio_effect=no_reduction`.

Validation:

- R728-R737 artifacts parse as JSON and were produced through the local read-only artifact lane.
- R733 has `accepted_for_source_mutation=false`.
- R737 has `accepted_for_source_mutation=false`.
- R739 has `usefulness=accept_runtime_support_only` and `borrowed_ratio_effect=no_reduction`.
- `scripts/engines/LocalExecutionEngine.ps1` was not modified during this episode.

Capability finding:

TOD improved process-shape recovery, provider request formation, provider invocation, candidate rejection, and replan-after-rejection. This is useful runtime-support learning, not independent engineering implementation.

Current limitation:

The local provider still failed to synthesize usable old/new source text. The verdict gate safely rejected generic validation, but its `old_text_found_in_current_source` check can over-trust broad string presence instead of exact anchor-specific source matching.

Borrowed-capability impact:

- No independent engineering implementation capability was retired.
- Borrowed ratio remains 78.4%.
- Model-utilization and recovery evidence improved.
- Source mutation remains forbidden.

Next smallest training rung:

`TOD-ANCHOR-SPECIFIC-OLDTEXT-VERDICT-V1`

Mission:

Train TOD's verdict path to verify that candidate `old_text` is the exact intended source-anchor text for the selected source file, not merely a string that appears somewhere in the source, prompt, generated artifact, or adjacent diagnostic context.
