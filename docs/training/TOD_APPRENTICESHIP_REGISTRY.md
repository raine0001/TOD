# TOD Apprenticeship Registry

Status: active

Purpose: record every borrowed capability created by a Codex emergency repair until TOD independently demonstrates, freezes, and retires the capability debt.

This registry is not a scorecard. It is a debt ledger. A borrowed capability remains open until TOD proves it can perform the capability on a fresh analogous case without Codex field scaffolding.

## Required Fields

Every entry must include:

- Borrowed From
- Reason
- Incident
- Capability
- Current Apprentice
- Progress
- Independent Demonstration
- Freeze
- Retirement

## State Meanings

- `borrowed`: emergency repair completed, capability not yet acquired.
- `assimilating`: TOD is studying the repair and building an internal representation.
- `scaffolded_pass`: TOD reproduced the reasoning or artifact with coaching/scaffolded evidence.
- `independent_demo_pending`: TOD has not passed a fresh analogous case without Codex field scaffolding.
- `independent_demo_passed`: TOD passed an unseen analogous case from discovered evidence.
- `frozen`: learned capability artifact exists with validation evidence.
- `retired`: capability is no longer borrowed because TOD can perform and maintain it independently.

## Proficiency Ladder

Borrowed-capability state records whether the debt is open or retired. Proficiency records how much trust MIM can place in TOD for that capability.

- `observed`: TOD has seen the pattern and has evidence of how it was done, but has not reproduced it.
- `understood`: TOD can explain the pattern, risks, validation steps, and when to reuse it from evidence.
- `guided`: TOD can perform the pattern with a provided target, explicit anchors, or Codex/MIM scaffolding.
- `independent`: TOD can perform the pattern on a fresh analogous task without Codex writing the packet or patch.
- `reliable`: TOD has repeated the pattern successfully across multiple analogous tasks with validation and no material regression.
- `teaches_others`: TOD can turn the pattern into a reusable lesson, detect recurrence, coach MIM/operator expectations, and improve the control plane without losing safety.

Progression rule: one successful independent demonstration can advance a capability to `independent`, but not to `reliable`. Reliability requires repeated successful demonstrations across changed context.

## Active Entries

### APP-TOD-039: Studio Long-Objective Transport Envelope Diagnosis And Repair

Borrowed From: Codex emergency repair after a bounded TOD attempt.

Reason: A 5,345-character enterprise objective packet sent through `/studio/mim` was rejected by Pydantic before MIM cognition because `StudioMimChatRequest.prompt` imposed a 4,000-character maximum. TOD found the owning Studio router but did not materialize an executable edit packet after its bounded attempt blocked on missing edit directives. Codex raised the bounded transport envelope, added focused request-model coverage, and made the native Studio client expose the server validation detail instead of only `HTTP 422`.

Incident: `MIM-STUDIO-LONG-OBJECTIVE-HTTP-422-20260730`

Capability: Trace an operator-visible request failure from the browser response through the request schema and receiving route; distinguish transport rejection from cognitive failure; select a bounded, non-unlimited request envelope from observed payload needs; preserve downstream cognition; improve error visibility without changing response authority; add focused model and client regression coverage; and validate the live operator path.

Current Apprentice: TOD

Progress: `borrowed`; TOD produced an initial bounded attempt and identified `tmp_remote_mim/core/routers/studio.py` as the owning source, but the attempt blocked before edit materialization because it did not synthesize the required edit mode and current-code replacement. Codex performed the local emergency repair and focused validation. The repair is not yet deployed from this managed workspace, and no independent TOD credit is granted.

Independent Demonstration: `pending`; TOD must diagnose a fresh analogous request-envelope failure without being given the target field or replacement, inspect both request model and caller behavior, decide whether a limit change is justified, synthesize and apply one bounded current-code repair when warranted, run isolated parser and focused behavioral validation, publish Examiner and Auditor evidence, and prove the operator-visible route no longer fails before cognition. A precise evidence-backed no-change verdict is acceptable only if the existing boundary is demonstrably intentional and the caller cannot exceed it.

Freeze: open; the emergency repair and first focused regression exist locally, but TOD has not independently reproduced the capability.

Retirement: open.

### APP-TOD-050: Cross-Repository Enterprise Merchant Integration

Borrowed From: Codex emergency cross-repository production-integration bridge.

Reason: TOD accepted `TSK-ENT-205-MERCHANT-BINDING-MODEL` but correctly stopped before mutation because the required AgentMIM repository at `E:\comm_app` was outside its allowed local fallback roots (`local_fallback_path_not_allowed`). Codex completed the authorized shared merchant model, API, Stripe integration, MIM adapter, guarded deployments, runtime migration repair, checkout diagnosis, and live proof.

Incident: `ENT-ENTERPRISE-BILLING-PLATFORM-20260731`

Capability: Reuse an existing merchant platform across repositories; create an enterprise-scoped binding without duplicating payments; preserve provider secret boundaries; deploy schema and application changes on separate runtimes; diagnose provider-specific checkout failures; and prove trial, monthly checkout, portal, invoices, webhook, cleanup, and conversation-first MIM orchestration.

Current Apprentice: TOD

Progress: `borrowed_deployed`; six AgentMIM merchant tests and 39 MIM billing, governance, and authentication tests pass. Render commit `6053ee3` is live, MIM services are active, the `ent_demo` path passed authenticated status, plan, checkout, portal, and invoice checks, and the disposable Stripe customer and database binding were removed. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_ENTERPRISE_BILLING_PLATFORM_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently deliver a fresh cross-repository provider integration using explicit safe-root authorization, a forward schema migration, secret-separated service adapter, guarded dual-runtime deployment, live provider error diagnosis, rollback evidence, and disposable cleanup.

Freeze: deployed evidence preserved; TOD-authored cross-repository merchant integration proof remains open.

Retirement: open.

### APP-TOD-051: Executable Semantic Patch Gate

Borrowed From: Codex escalation after repeated bounded TOD and shadow-provider attempts.

Reason: TOD correctly inspected the semantic-validation boundary and rejected unsafe Qwen3, DeepSeek, and Qwen2.5 candidates, but it did not independently materialize the final current-code repair. Codex added the narrow authority rule and focused coverage only after TOD's repeated attempts established the exact blocker.

Incident: `TOD-EXECUTABLE-SEMANTIC-PATCH-GATE-V1B-20260731`

Capability: Apply a proposed source patch only in an isolated temporary workspace; run a real parser or compiler, the proposed validation command, and a focused behavior test; preserve the production source byte-for-byte until deterministic checks pass; reject nonexistent paths, invalid commands, forbidden output, unexpected file changes, and unauthorized assertion modes; and grant mutation authority only from the explicit assertion policy selected for that candidate. Trusted expected-red assertions must remain limited to test-only targets and may not be rescued by an unrelated successful validation command.

Current Apprentice: TOD

Progress: `borrowed_validated_after_tod_attempts`; TOD supplied source inspection, provider contexts, candidate attempts, rejection evidence, and repeated semantic diagnosis. Codex completed the smallest authority-containment repair. Current focused evidence is 9/9 semantic-gate tests and 3/3 provider-authority tests passing; parser validation also passed.

Independent Demonstration: pending; TOD must select a fresh analogous semantic-authority defect, inspect the current source without a supplied patch, generate its own bounded candidate, apply it only in a temporary workspace, execute parser and focused behavior validation, reject at least one unsafe candidate if encountered, complete the corrected implementation, and publish Examiner plus Auditor evidence without Codex-authored patch text or wrapper-only credit.

Freeze: open; the borrowed repair and focused regression suite are preserved, but no fresh TOD-owned analogous cycle has passed.

Retirement: open.

### APP-TOD-044: Enterprise Two-Action Landing Contract

Borrowed From: Codex emergency product-continuation bridge.

Reason: TOD accepted `TSK-0066`, but its wrapper performed no implementation and LocalExecutionEngine could not select one target from the bounded landing-route and regression-test scope.

Incident: `ENT-TWO-ACTION-LANDING-20260731`

Capability: Enforce the exact `Start Free Enterprise` and `Sign In` public action contract, remove combined-auth and mandatory-wizard language, preserve separated routes, and prove it through focused tests, guarded deployment, rollback, remote validation, and live browser counts.

Current Apprentice: TOD

Progress: `borrowed_deployed`; evidence is recorded in `runtime_remote_training/read_only_audit_artifacts/ENT_TWO_ACTION_LANDING_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently ship and validate a fresh exact public-page interaction contract without Codex patch text.

Freeze: open.

Retirement: open.

### APP-TOD-042: MIM Blocker Acknowledgement Protocol

Borrowed From: Codex emergency control-plane repair.

Reason: TOD returned a no-op false pass for `TSK-MIM-BLOCKER-ACK-V1` while live MIM misrouted two structured blocker acknowledgement requests, preventing the required handoff from being acknowledged.

Incident: `MIM-BLOCKER-ACKNOWLEDGEMENT-PROTOCOL-20260731`

Capability: Recognize and answer the general seven-field blocker acknowledgement contract before generic, lifecycle, or public routes, without embedding prompt-specific product answers.

Current Apprentice: TOD

Progress: `borrowed_deployed`; compile and focused tests passed, both services remained active, and live MIM returned all seven labels with the owner accepted and `blocker_state: acknowledged_blocked`. Evidence: `runtime_remote_training/read_only_audit_artifacts/MIM_BLOCKER_ACK_PROTOCOL_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently implement and prove a fresh structured coordination protocol without Codex patch text.

Freeze: open pending TOD-authored independent protocol proof.

Retirement: open until TOD independently ships and validates an analogous coordination contract.

### APP-TOD-043: Enterprise Authentication Recovery

Borrowed From: Codex emergency product-security bridge.

Reason: MIM acknowledged that TOD's wrapper performed no execution and LocalExecutionEngine did not support the bounded authentication route scope, authorizing the emergency bridge with TOD review afterward.

Incident: `ENT-AUTHENTICATION-RECOVERY-20260731`

Capability: Implement secure opt-in persistent login and password recovery with non-enumerating requests, hashed expiring one-time tokens, single-use consumption, focused security tests, guarded deployment, rollback, and live browser proof.

Current Apprentice: TOD

Progress: `borrowed_deployed`; 8 focused tests and 12 remote checks passed, the guarded deployment retained a rollback copy, all prior Enterprise validators remained green, and the live browser proved the generic unknown-email response plus invalid-token rejection. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_AUTH_RECOVERY_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently ship a fresh authentication-security capability and prove server behavior, tests, deployment, rollback, and live UX without Codex patch text.

Freeze: open pending TOD-authored independent authentication-security proof.

Retirement: open until TOD independently ships and validates an analogous authentication-security slice.

### APP-TOD-040: Unified Identity to Enterprise Workspace Routing

Borrowed From: Codex emergency product-continuation repair.

Reason: TOD truthfully rejected wrapper-only output on `TSK-ENT-AUTH-ROUTING-V1`. The narrower `TSK-ENT-AUTH-ROUTING-V2` also blocked because LocalExecutionEngine treated `tmp_remote_mim/core/routers/project_portal.py` and `project_portal.py` as two target candidates instead of one file.

Incident: `ENT-UNIFIED-AUTH-ROUTING-20260731`

Capability: Resolve one authenticated identity into zero, one, or multiple active Enterprise memberships; preserve the legacy singular `enterprise_id`; return a server-owned safe redirect; require authentication for workspace selection; and continue into the existing `/observatory` Enterprise Discovery experience.

Current Apprentice: TOD

Progress: `borrowed`; Codex implemented the bounded routing slice and focused validation after two TOD execution blockers. Evidence: `tod/out/prompts/TSK-ENT-AUTH-ROUTING-V1.md`, `tod/out/prompts/TSK-ENT-AUTH-ROUTING-V2.md`, `tmp_remote_mim/core/routers/project_portal.py`, and `tmp_remote_mim/tests/test_unified_enterprise_auth_routing.py`.

Independent Demonstration: `pending`; TOD must independently extend unified authentication with a fresh capability and prove safe routing, authorization boundaries, focused tests, and live user-visible behavior without a Codex-authored patch body.

Freeze: open; a TOD-authored learned capability and independent deployed pass are still required.

Retirement: open until TOD independently ships, validates, and freezes a fresh identity-to-workspace routing extension.

### APP-TOD-041: Enterprise Creation Separation

Borrowed From: Codex emergency product-continuation repair.

Reason: TOD accepted `TSK-ENT-CREATION-SEPARATION-V1`, but the wrapper did not execute and LocalExecutionEngine classified the single-file customer route change as unsupported.

Incident: `ENT-ENTERPRISE-CREATION-SEPARATION-20260731`

Capability: Keep the canonical login authentication-only, move the exact five-field company identity contract to `/enterprise/create`, preserve email verification and discovery bootstrap, and continue the customer directly into prepared Enterprise Discovery.

Current Apprentice: TOD

Progress: `borrowed_deployed`; focused tests, remote validators, service health, and live browser proof are recorded in `runtime_remote_training/read_only_audit_artifacts/ENT_ENTERPRISE_CREATION_SEPARATION_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently separate a fresh authentication or registration concern, preserve its downstream workflow, and prove focused plus live behavior without a Codex-authored patch body.

Freeze: open pending a TOD-authored learned capability and independent live pass.

Retirement: open until TOD independently ships and validates an analogous authentication-flow separation.

### APP-TOD-037: Local Engineering Model Utilization Judgment

Borrowed From: Codex coaching during TOD local engineering intelligence realignment.

Reason: TOD can reach the local engineering provider and can classify source/input/output roles, but it has not yet demonstrated that it can supervise a model response as engineering evidence. The first provider-judgment attempt (`TSK-0092`) produced a generic contract-field rejection instead of a provider judgment containing `provider_reachable`, `provider_reply_summary`, `acceptance_findings`, `tod_accept_reject_decision`, and `next_prompt_improvement`.

Incident: `TOD-LOCAL-ENGINEERING-MODEL-UTILIZATION-R39`

Capability: TOD must build useful local-model context, invoke or inspect model output, judge whether the output is acceptable engineering assistance, reject shallow or unsafe help, improve the next prompt, and record the episode without treating model output as implementation progress.

Current Apprentice: TOD

Progress: `independent_demo_passed`; TOD completed the original model-utilization supervision contract on a fresh DeepSeek response in R1006-R1008: provider invocation, unsafe-candidate rejection before mutation, and evidence-grounded prompt improvement. Historical scaffold and blocker evidence remains below for traceability; it does not override the current independent demonstration.

2026-07-23 continuation: TOD attempted `TSK-0095` to publish `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_JUDGMENT_PRODUCER_REPAIR_SHAPE_R42.latest.json`. The local executor blocked with `local_fallback_needs_target_or_scope` because it treated the output artifact, input artifact, and source-anchor artifact as competing candidate target files. This was recorded as `RES-0062` and `REV-0043` with no completion credit. TOD then attempted `TSK-0096` as a smaller artifact-role disambiguation rung, but the package rendered `Task Category: chat_execution` because the semantic role category was hidden in scope text instead of structured metadata. TOD followed the selected source-anchor task `TOD-PACKAGE-TASK-RENDERER-SOURCE-ANCHOR-R4` and published `runtime_remote_training/read_only_audit_artifacts/TOD_PACKAGE_TASK_RENDERER_SOURCE_ANCHOR_R4.latest.json`, showing the package renderer does include `{{TASK_CATEGORY}}`; the problem is task materialization/dispatch supplying the wrong category. A structured rerun, `TSK-0097`, still failed before producing the model-utilization role map, and latest execution state drifted back to an unrelated MIM task. This keeps the capability borrowed and identifies a runtime-support blocker: model-utilization read-only tasks must preserve artifact roles and task category as structured fields before the local executor chooses a target.

2026-07-23 R44-R46 continuation: TOD accepted `TOD-MODEL-UTILIZATION-PROVIDER-JUDGMENT-R44` as a clean read-only model-utilization judgment request, but local fallback blocked because it saw both the input artifact and output artifact as candidate target files and did not have a provider-judgment artifact lane. `TOD-MODEL-UTILIZATION-R44-FALLTHROUGH-COMPARISON-R45` then showed that inline directive text with a trailing period can prevent the requested artifact type from matching the evidence-comparison lane. `TOD-MODEL-UTILIZATION-R44-FALLTHROUGH-COMPARISON-R46` corrected the contract formatting and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_R44_FALLTHROUGH_COMPARISON_R46.latest.json`; that artifact proves the comparison lane can run when directives are line-separated, but it remains blocked on `comparison_path_unsafe` because `tod/out/background-chat/...stdout.log` is not an allowed read-only evidence source. No independent model-utilization credit is granted yet.

2026-07-23 R47-R48 continuation: TOD completed `TOD-MODEL-UTILIZATION-TRANSCRIPT-EVIDENCE-SAFE-PATH-SOURCE-ANCHOR-R47`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_TRANSCRIPT_EVIDENCE_SAFE_PATH_SOURCE_ANCHOR_R47.latest.json`. That artifact read `scripts/engines/LocalExecutionEngine.ps1`, matched `function Test-LocalExecutionSafePath`, captured lines 305-349, and made no code changes. TOD then attempted `TOD-MODEL-UTILIZATION-TRANSCRIPT-EVIDENCE-PUBLISHER-PACKET-R48` to convert the source-anchor observation into a bounded packet. R48 blocked honestly with `reason_code=packet_body_synthesis_autonomous_new_text_missing` and `missing_variable=autonomous_meaningful_new_text_materialization_from_source_anchor`. This proves TOD can inspect the relevant source anchor and publish precise blocker evidence, but it still cannot autonomously synthesize a meaningful safe PowerShell repair from current-code evidence. This is Engineering debt, not model-utilization completion.

2026-07-23 R49 continuation: A direct local read-only delta-proposal proof published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_TRANSCRIPT_EVIDENCE_DELTA_PROPOSAL_R49.latest.json`. The artifact validates that the R47 source anchor is usable (`source_anchor_valid=true`) and names the exact next missing capability: `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor`. It also preserves `candidate_new_text=""`, `no_source_code_modified=true`, and `reason_code=autonomous_candidate_new_text_missing`. This is a useful guided proof of the next Engineering rung, but not independent APP-TOD-037 completion.

2026-07-24 execution-lane support continuation: TOD completed `TOD-MODEL-UTILIZATION-EXECUTION-LANE-SUPPORT-SOURCE-ANCHOR-V1-R1`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_EXECUTION_LANE_SUPPORT_SOURCE_ANCHOR_V1.r1.latest.json`. The source anchor captured `scripts/TOD.ps1::Test-TaskAllowsLocalExecutionWithoutMaterialization` lines 8117-8252 and passed source-read, anchor-match, artifact-write, schema-readback, and no-code-change validation. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_EXECUTION_LANE_SUPPORT_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepted the inspection but did not grant independent capability credit: the artifact proves the current local execution allowance gate does not explicitly admit `model_utilization`; provider-judgment execution and engineering episode recording remain unproven.

2026-07-24 provider-judgment contract continuation: TOD ran `TOD-MODEL-UTILIZATION-PROVIDER-JUDGMENT-LANE-CONTRACT-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r1.latest.json` through the generic read-only artifact lane. Mechanical execution passed, but Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r1.codex_validation.json` rejected capability credit because the requested provider-judgment fields did not survive into the artifact. The next narrower gap is `generic_read_only_contract_field_preservation`: TOD must preserve requested contract fields before a provider-judgment lane can be trusted.

2026-07-24 contract-field preservation continuation: TOD ran `TOD-READONLY-CONTRACT-FIELD-PRESERVATION-FOR-MODEL-UTILIZATION-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r1.latest.json`. Mechanical execution passed, but Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r1.codex_validation.json` rejected capability credit because the published artifact still omitted `provider_reachable`, `provider_reply_summary`, `acceptance_findings`, `tod_accept_reject_decision`, `next_prompt_improvement`, and `counts_as_engineering_implementation_credit`. This narrows APP-TOD-037 to a writer/whitelist inspection: TOD must prove where the generic read-only audit producer drops arbitrary requested contract fields before it can resume provider-judgment work.

2026-07-24 read-only contract evaluator inspection: TOD completed `TOD-READONLY-AUDIT-FIELD-WHITELIST-SOURCE-ANCHOR-V1-R1` and `TOD-READONLY-CONTRACT-FIELD-EVALUATOR-SOURCE-ANCHOR-V1-R2` through the executable source-anchor lane. The R1 artifact captured the fixed evidence-field seed in `scripts/engines/LocalExecutionEngine.ps1`; the R2 artifact captured the later contract-required-field evaluator branch. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_EVALUATOR_SOURCE_ANCHOR_V1.r2.codex_validation.json` accepted the source inspection without independent capability credit. The key finding is that the generic read-only writer already has a required-field evaluator, but it only activates for directive labels such as `Required checks:` or `Required output fields:`. Earlier model-utilization prompts used labels like `Required Preserved Field Names` and `Required Contract Fields`, so the evaluator never activated and the artifact stayed generic. Next rung: rerun contract-field preservation using the accepted `Required output fields:` directive shape and prove the generic read-only artifact can classify missing provider-judgment fields before provider invocation resumes.

2026-07-24 contract-field preservation R2 validation: TOD reran `TOD-READONLY-CONTRACT-FIELD-PRESERVATION-FOR-MODEL-UTILIZATION-V1-R2` with the accepted `Required output fields:` directive. The requested artifact `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r2.latest.json` preserved all six required provider-judgment field names, classified each as missing, set `classification=contract_field_evaluation_failed`, `pass_or_reject=reject`, `no_code_changes=true`, and `dave_needed=no`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_CONTRACT_FIELD_PRESERVATION_FOR_MODEL_UTILIZATION_V1.r2.codex_validation.json` accepts this as a supporting contract-preservation pass but not APP-TOD-037 retirement. Provider invocation, provider response judgment, and engineering episode recording remain unproven.

2026-07-24 provider-judgment contract R2 and provider-invoker source-anchor validation: TOD reran `TOD-MODEL-UTILIZATION-PROVIDER-JUDGMENT-LANE-CONTRACT-V1-R2` after contract-field preservation was proven. The artifact preserved the required provider-judgment field names, but still did not materialize provider reachability, provider reply summary, accept/reject judgment, prompt improvement, or the missing provider-invocation hook. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r2.codex_validation.json` rejected capability credit while accepting that contract fields now survive. TOD then attempted `TOD-MODEL-UTILIZATION-PROVIDER-INVOKER-SOURCE-ANCHOR-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_INVOKER_SOURCE_ANCHOR_V1.r1.latest.json`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_INVOKER_SOURCE_ANCHOR_V1.r1.codex_validation.json` rejected a pass because the source anchor captured only the one-line `Invoke-RestMethod` call. That proves the provider call exists, but it does not capture the prompt-body construction, provider function boundary, response extraction, or the judgment hook required for Model Utilization.

2026-07-24 provider function-boundary validation: TOD reran the source-anchor work with explicit context ranges and captured the provider boundary correctly. `TOD_MODEL_UTILIZATION_PROVIDER_INVOCATION_FUNCTION_SOURCE_ANCHOR_V1.r2.latest.json` captures `Invoke-ConversationRequest`; `TOD_MODEL_UTILIZATION_PROVIDER_RESPONSE_EXTRACTION_SOURCE_ANCHOR_V1.r2.latest.json` captures `Get-ReplyTextFromResponse`; and `TOD_MODEL_UTILIZATION_PROVIDER_CHAT_ACTION_PATH_SOURCE_ANCHOR_V1.r1.latest.json` captures the `chat` action path that builds the request body, probes provider reachability, invokes the provider, extracts `reply_text`, and returns the local-provider payload. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_FUNCTION_BOUNDARY_SOURCE_ANCHOR_V1.codex_validation.json` accepts this as a supporting pass. No APP-TOD-037 retirement is granted: TOD still has not invoked or inspected a provider response, made an accept/reject engineering judgment, improved the prompt, or recorded an engineering episode.

2026-07-24 hook-map materialization attempts: TOD attempted `TOD-MODEL-UTILIZATION-PROVIDER-JUDGMENT-HOOK-MAP-V1-R1`. It accepted the task and wrote `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_HOOK_MAP_V1.r1.latest.json`, but Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_HOOK_MAP_V1.r1.codex_validation.json` rejected credit because the artifact was only a `tod_read_only_task_context_proof`, not a semantic hook map. TOD then exposed a runtime bridge blocker in `TOD_MODEL_UTILIZATION_HOOK_MAP_LANE_SELECTION_V1.r1.codex_validation.json`: `execute-chat-task` bridge requests can be created but `run-bridge-request` does not support `execute-chat-task`. A source-anchor follow-up, `TOD_EXECUTE_CHAT_TASK_BRIDGE_RUNNABILITY_CLASSIFICATION_V1.r1.latest.json`, captured `scripts/TOD.ps1` lines 16386-16456 and proved the supported bridge action list omits `execute-chat-task`; Codex validation accepted this as Runtime evidence in `TOD_EXECUTE_CHAT_TASK_BRIDGE_RUNNABILITY_CLASSIFICATION_V1.r1.codex_validation.json`. Finally, `TOD_MODEL_UTILIZATION_HOOK_MAP_DIRECT_READONLY_AUDIT_V1.r1.latest.json` proved the direct `report_only` read-only audit path can execute and reject, but only preserved the first required hook field. Codex validation in `TOD_MODEL_UTILIZATION_HOOK_MAP_DIRECT_READONLY_AUDIT_V1.r1.codex_validation.json` keeps APP-TOD-037 open and narrows the next gap to multi-field contract preservation through the direct read-only audit lane.

2026-07-24 multi-field and repair-packet continuation: TOD ran `TOD-READONLY-AUDIT-MULTIFIELD-CONTRACT-PRESERVATION-V1-R1`; the artifact preserved all six requested hook-map field names in `required_fields`, but classified all six as missing and did not materialize values. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_MULTIFIELD_CONTRACT_PRESERVATION_V1.r1.codex_validation.json` rejects capability credit while accepting the narrower proof that field-name preservation is no longer the primary blocker. TOD then ran `TOD-MODEL-UTILIZATION-HOOK-MAP-FIELD-VALUE-MATERIALIZATION-V1-R1`, but produced another `tod_read_only_task_context_proof` instead of a semantic hook map; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_HOOK_MAP_FIELD_VALUE_MATERIALIZATION_V1.r1.codex_validation.json` names the false-positive risk: `validation.required_fields_present=true` can mean task-context schema proof rather than semantic field completion. TOD captured source anchors for the read-only task-context proof lane in `TOD_READONLY_TASK_CONTEXT_REQUIRED_FIELDS_FALSE_POSITIVE_SOURCE_ANCHOR_V1.r1.latest.json` and `TOD_READONLY_TASK_CONTEXT_PROOF_PREVENTION_LESSON_SOURCE_ANCHOR_V1.r1.latest.json`, then attempted an implementation-shaped repair-packet task. That attempt again published a read-only task-context proof rather than target_file/edit_mode/old_text/new_text repair packet fields; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_TASK_CONTEXT_REQUIRED_FIELDS_FALSE_POSITIVE_REPAIR_PACKET_V1.r1.codex_validation.json` classifies the current blocker as `runtime_lane_selection_blocks_engineering_packet_materialization`. APP-TOD-037 remains open: TOD can inspect source anchors and preserve contract field names, but still cannot materialize semantic model-utilization hook values or a bounded repair packet without lane-selection support.

2026-07-24 selector and semantic-lane specificity continuation: A packet-formation retry for the read-only task-context false-positive repair was routed as `codex_required`, so the Codex wrapper accepted the package without executing and local fallback failed. TOD captured selector source anchors in `TOD_PACKET_FORMATION_CODEX_REQUIRED_SELECTOR_SOURCE_ANCHOR_V1.r1.latest.json` and `TOD_PACKET_FORMATION_DEFAULT_CODEX_REQUIRED_ASSIGNMENT_SOURCE_ANCHOR_V1.r1.latest.json`, proving `scripts/TOD.ps1::Resolve-LocalExecutionSuitability` starts from `$classification = 'codex_required'`. TOD then attempted a semantic source audit from those anchors, but Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_CODEX_REQUIRED_SELECTOR_SEMANTIC_AUDIT_V1.r1.codex_validation.json` rejected it because the artifact was schema-complete but generic; it did not mention the selector or the `codex_required` anchor. TOD captured the canned semantic-audit text source in `TOD_SEMANTIC_SOURCE_AUDIT_CANNED_TEXT_SOURCE_ANCHOR_V1.r1.latest.json` (`scripts/engines/LocalExecutionEngine.ps1:7966`), and Codex validation in `TOD_SEMANTIC_SOURCE_AUDIT_CANNED_TEXT_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepted the source proof. This narrows the active blocker again: TOD has evidence lanes that can pass schema while returning canned or non-specific reasoning. Model Utilization remains borrowed until TOD can produce source-specific engineering judgment from actual evidence.

2026-07-24 validation-truth continuation: TOD attempted `TOD-SEMANTIC-SOURCE-AUDIT-CONTENT-SPECIFICITY-V1-R1` using the selector anchors and canned semantic-audit anchor. The output artifact `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_SOURCE_AUDIT_CONTENT_SPECIFICITY_V1.r1.latest.json` mentioned `Resolve-LocalExecutionSuitability`, `$classification = 'codex_required'`, and the canned `observed_blocker` source, but Codex validation in `TOD_SEMANTIC_SOURCE_AUDIT_CONTENT_SPECIFICITY_V1.r1.codex_validation.json` rejected credit because the requested semantic fields were not answered as values; they only appeared under `required_fields`. TOD then ran `TOD-SEMANTIC-AUDIT-FIELD-VALUE-VS-FIELD-NAME-DISCRIMINATION-V1-R1` and `TOD-EXECUTION-SUMMARY-MUST-DEFER-TO-ARTIFACT-VALIDATION-V1-R1`. Both wrote artifacts whose own `pass_or_reject=reject` and `validation.required_fields_present=false`, but the outer `execute-chat-task` compact summary still reported `decision=pass/status=completed`. Codex validation artifacts `TOD_SEMANTIC_AUDIT_FIELD_VALUE_VS_FIELD_NAME_DISCRIMINATION_V1.r1.codex_validation.json` and `TOD_EXECUTION_SUMMARY_MUST_DEFER_TO_ARTIFACT_VALIDATION_V1.r1.codex_validation.json` classify this as a false-success propagation problem. TOD captured the pass-default source anchor in `TOD_EXECUTION_SUMMARY_PASS_DEFAULT_SOURCE_ANCHOR_V1.r1.latest.json`, then produced `TOD_EXECUTION_SUMMARY_ARTIFACT_VALIDATION_PRECEDENCE_PACKET_V1.latest.json`. That packet is structurally valid and targets `scripts/TOD.ps1`, but Codex validation rejected behavior credit because the generated `new_text` only inserts a harmless training marker instead of implementing artifact-validation precedence. APP-TOD-037 therefore remains open with a sharper split: Runtime/Evidence support can now expose the false-success fault, but Engineering patch synthesis from diagnosis is still borrowed.

2026-07-26 provider prompt/source-anchor continuation: TOD advanced the provider-supervision lane through R764-R782. It diagnosed comparison-path shape failure (`R764`), captured provider invocation source context (`R765C`), rejected unsafe provider candidates without mutation (`R770`, `R774`, `R781`), and captured the replan source anchor in `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REPLAN_SOURCE_ANCHOR_R776E.latest.json`. The precise blocker was that the replan branch treated `rejected_blank_new_text`, `rejected_no_delta_candidate`, and `rejected_old_text_not_found_in_current_source` as generic retries. Codex then made a narrow control-plane repair in `scripts/engines/LocalExecutionEngine.ps1`; TOD verified the new rejection-specific coaching in `TOD_PROVIDER_PROMPT_DRIFT_REPLAN_SPECIFIC_R777.latest.json`, `TOD_PROVIDER_PROMPT_DRIFT_REPLAN_BLANK_SPECIFIC_R778.latest.json`, and `TOD_PROVIDER_PROMPT_DRIFT_REPLAN_OLDTEXT_SPECIFIC_R782.latest.json`. This is scaffolded model-utilization supervision progress, not APP-TOD-037 retirement: Codex still authored the control-plane repair, no source mutation candidate was accepted, and TOD has not yet synthesized safe behavior-changing `new_text` from the current-code source anchor. Next rung: `TOD-PROVIDER-REPLAN-VALIDATION-SPECIFICITY-V1`.

2026-07-26 validation-specificity continuation: TOD ran `TOD-PROVIDER-REPLAN-VALIDATION-SPECIFICITY-V1` through R1-R7. R1 correctly blocked on a bad source anchor, R2/R3 proved narrow anchors can capture insufficient one-line evidence, and R4 proved the generic report-only lane can reject missing semantic fields but cannot synthesize the diagnosis from multiple evidence artifacts. Codex then made a narrow control-plane repair so generic inherited provider validation placeholders are converted into executable validation commands for known source file types. R7 published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_REPLAN_VALIDATION_SPECIFICITY_R7.latest.json`, carrying a non-generic PowerShell parser command through the replan artifact; Codex executed that generated command and received `parse=passed`. This retires the validation-specificity sub-rung as a guided pass only. APP-TOD-037 remains open because TOD did not author the repair and still has not accepted, applied, and validated a provider-generated source patch. Next rung: `TOD-PROVIDER-CANDIDATE-STUB-RETRY-FROM-REPLAN-V1`.

2026-07-26 provider invocation and rejection continuation: TOD ran R8-R16 across provider retry, invocation, verdict, and replan rungs. R8 published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_REQUEST_FROM_REPLAN_R8.latest.json` with the concrete validation command preserved. R12 rejected the failed R10 provider invocation before mutation in `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_RETRY_VERDICT_R12.latest.json`. R14 exposed that provider replans did not preserve prompt-budget/source-excerpt/strict-JSON semantic fields, so Codex made a narrow control-plane repair in `scripts/engines/LocalExecutionEngine.ps1`. R15 exposed that `tod_engineering_provider_candidate_invocation` was implemented in the engine but missing from TOD's preactive supported artifact list, so Codex made a narrow control-plane repair in `scripts/TOD.ps1`. R14B then proved the prompt-budget replan fields and executable validation command; R15B proved a real local provider call (`provider_called=true`) that returned unsafe fenced/truncated blank output; R16 rejected that output with `verdict=reject`, `verdict_reason_code=rejected_blank_new_text`, `accepted_for_source_mutation=false`, and `no_source_code_modified=true`. This is a scaffolded model-utilization supervision pass, not APP-TOD-037 retirement. TOD can now route, invoke, and reject unsafe local-provider output under coaching, but no provider-generated behavior-changing patch has been accepted, applied, or validated independently. Next rung: `TOD-PROVIDER-CANDIDATE-SMALL-EXCERPT-STRICT-JSON-RETRY-V1`.

2026-07-26 small-excerpt provider retry continuation: Codex added a narrow prompt-budget transform so provider invocation keeps full source evidence for validation but sends a smaller source excerpt when the replan carries `prompt_budget_strategy`. R17 published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SMALL_EXCERPT_INVOCATION_R17.latest.json`, proving the prompt was excerpted from 16,031 characters to 3,600 and the local provider was called. The provider returned parseable JSON content but still wrapped it in markdown fences and left `old_text` and `new_text` blank. R18 published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_SMALL_EXCERPT_VERDICT_R18.latest.json`, rejecting the candidate with `verdict_reason_code=rejected_blank_old_text`, `accepted_for_source_mutation=false`, `rejected_before_source_mutation=true`, and `no_source_code_modified=true`. This advances provider supervision safety but not engineering independence. APP-TOD-037 remains borrowed. Next rung: `TOD-PROVIDER-SOURCE-SPECIFIC-CANDIDATE-GENERATION-V1`.

2026-07-26 source-specific provider continuation: TOD ran `TOD-PROVIDER-SOURCE-SPECIFIC-CANDIDATE-GENERATION-V1` through R19-R38B. R19B/R19C proved the correct source-anchor directive shape and captured `scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionSourceAnchorObservation`. R20C/R21/R22 produced a context package, model-utilization judgment, and provider request; R23 called the local provider; R24 rejected the first source-specific candidate with `rejected_old_text_not_found_in_current_source`. After TOD exposed that replan/provider requests lost `source_function` and source-anchor body semantics, Codex made a narrow control-plane repair in `scripts/engines/LocalExecutionEngine.ps1`. R25B/R26B verified the repaired request preserved `source_function=Invoke-LocalExecutionSourceAnchorObservation`, inline authoritative source-anchor body, and a concrete parser validation command. R27B/R28B then rejected another unsafe candidate with `rejected_old_text_not_found_in_current_source`. TOD backed up one rung to a one-line source anchor in R29; R30-R34 produced a smaller context/request/invocation and rejected the candidate with `rejected_generic_validation_command`. R35-R38 produced a validation-specific retry and initially accepted an unsafe candidate. Codex validation caught this as a false accept because the candidate validation command used `$loaded` instead of an allowed verifier; Codex then repaired the verdict policy so accepted candidates must use an allowed verifier pattern such as `Parser.ParseFile`, `py_compile`, `json.tool`, `pytest`, or `Invoke-Pester`. R38B rejudged the same candidate and correctly rejected it with `rejected_validation_command_not_allowed_verifier`. Classification: scaffolded provider-supervision safety progress. TOD can now build smaller source anchors, call the provider, reject unsafe output, replan after rejection, and detect a false-accept validation-policy gap. APP-TOD-037 remains open because Codex authored the control-plane repairs and no provider-generated source mutation has been safely applied and validated.

2026-07-26 validation-aware retry continuation: TOD ran `TOD-PROVIDER-VALIDATION-AWARE-CANDIDATE-RETRY-V1` through R39-R42. R39 produced a replan from `rejected_validation_command_not_allowed_verifier`; R40 built a retry provider request; R41 called the local provider; R42 wrote `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_AWARE_VERDICT_R42.latest.json` and rejected the provider output again with `rejected_validation_command_not_allowed_verifier`. This is a safety improvement, not engineering completion. The local model still tends to return dot-source/loaded validation commands instead of Parser.ParseFile. Next rung: `TOD-PROVIDER-VALIDATION-COMMAND-PROMPT-CONTRACT-V1`, where TOD must inspect why the provider request prompt is not constraining validation-command shape before another source-mutation attempt.

2026-07-26 validation-command prompt-contract continuation: TOD ran `TOD-PROVIDER-VALIDATION-COMMAND-PROMPT-CONTRACT-V1` through R1-R7B. R1/R2/R3 narrowed the fault from generic report-only failure to a bounded prompt-contract attempt that rolled back with `local_fallback_validation_failed`. Codex then made a narrow control-plane repair in `scripts/engines/LocalExecutionEngine.ps1` so replans for `rejected_validation_command_not_allowed_verifier` generate executable source-file verifier commands and provider requests state allowed verifier patterns instead of dot-source `loaded` smoke checks. R4D produced `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_REPLAN_R4D.latest.json`; R5 produced `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_REQUEST_R5.latest.json`; R6 called the local provider in `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_INVOCATION_R6.latest.json`. The provider returned a non-empty candidate, but its validation command listed verifier names rather than one executable command. R7 initially false-accepted that output; Codex tightened the verdict gate so allowed verifier names must appear in an executable command shape. R7B then published `runtime_remote_training/read_only_audit_artifacts/TOD_PROVIDER_VALIDATION_COMMAND_PROMPT_CONTRACT_VERDICT_R7B.latest.json`, correctly rejecting the candidate with `verdict_reason_code=rejected_validation_command_not_executable_shape`, `accepted_for_source_mutation=false`, and `rejected_before_source_mutation=true`. This is scaffolded provider-supervision safety progress, not APP-TOD-037 retirement. Next rung: `TOD-PROVIDER-CANDIDATE-REPLAN-AFTER-REJECTION-V1`.

2026-07-24 engineering-runtime contract blocker: TOD attempted `TOD-ENGINEERING-PATCH-SYNTHESIS-FROM-DIAGNOSIS-V1-R1`, asking for a behavior-changing packet that would make `scripts/TOD.ps1` downgrade `reviewDecision` when a generated artifact says `pass_or_reject=reject`, `validation.required_fields_present=false`, or `missing_fields` is non-empty. The attempt timed out after 120 seconds and no requested artifact was written. Codex validation in `runtime_remote_training/tod_independent_resolution_attempts/TOD_ENGINEERING_PATCH_SYNTHESIS_FROM_DIAGNOSIS_V1.r1.codex_validation.json` records `packet_body_synthesis_timeout_no_artifact`. This is the clearest current evidence for Dave's roadmap correction: TOD has enough runtime plumbing to expose the fault, but it needs a minimal Engineering Runtime contract that can transform source context plus diagnosis into a real behavior-changing packet. APP-TOD-037 remains borrowed.

2026-07-24 local engineering intelligence path decision: Codex reviewed `E:/agent MIM work/app development/TOD Local Engineering Intelligence.txt` against the current scorecard and existing realignment artifacts, then recorded `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_INTELLIGENCE_PATH_DECISION_V1.latest.json`. Decision: adopt the path with scope control. Engineering Corpus becomes the primary product; Local Engineering Runtime starts early as a provider-neutral context/contract/episode recorder; Model Utilization is measured as TOD's ability to supervise engineering help, not as implementation credit. TOD then attempted `TOD-ENGINEERING-RUNTIME-MINIMAL-PATCH-SYNTHESIS-CONTRACT-V1-R1`. The task package was generated correctly as read-only, but no contract artifact was produced; execution returned the wrapper-only blocker. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_RUNTIME_MINIMAL_PATCH_SYNTHESIS_CONTRACT_V1.r1.codex_validation.json` records `artifact_only_engineering_contract_task_not_executed_by_local_lane`. Next smaller rung: `TOD-ENGINEERING-CONTRACT-ARTIFACT-LANE-SUPPORT-V1`. APP-TOD-037 remains borrowed.

2026-07-24 source-anchor and detector continuation: TOD completed three source-anchor inspection rungs after the tasks supplied exact source-file and anchor contracts. `TOD_READONLY_ARTIFACT_TYPE_LANE_PRECEDENCE_SOURCE_ANCHOR_V1.r3.latest.json` captured `Invoke-LocalExecutionReadOnlyAuditArtifact`; `TOD_READONLY_AUDIT_TASK_DETECTOR_SOURCE_ANCHOR_V1.r1.latest.json` captured `Test-LocalExecutionReadOnlyAuditArtifactTask`; and `TOD_READONLY_AUDIT_PATH_EXTRACTOR_SOURCE_ANCHOR_V1.r1.latest.json` captured `Get-LocalExecutionReadOnlyAuditArtifactPaths`. Codex validation accepts these as supporting runtime/evidence passes. The first-loss point is now precise: evidence-comparison implementation reads `Package Path` and `Compare Artifact`, but the lane detector first requires JSON input/output paths from the extractor, which does not treat `Package Path` or `Compare Artifact` as detector input aliases. TOD then attempted `TOD-READONLY-EVIDENCE-COMPARISON-DETECTOR-PACKET-V1-R1`; no requested packet artifact was produced and the local fallback reported rollback after failed validation. APP-TOD-037 remains borrowed because TOD has not yet synthesized a validated current-code repair packet from the source-anchor evidence.

2026-07-24 package-comparison regression continuation: TOD ran `TOD-READONLY-EVIDENCE-COMPARISON-DETECTOR-PACKET-ANCHOR-SUITABILITY-V1-R1` and correctly published a suitability artifact showing the detector anchor is unique but not packet-ready without `insert_before_pattern`, `snippet`, and `validation_command`. A follow-up materialization attempt reported bounded fallback completion, and `tests/TOD.ReadOnlyAuditRegression.Tests.ps1` passed, but the live package-comparison retry `TOD-EVIDENCE-COMPARISON-LANE-PACKAGE-CATEGORY-PROOF-V1-R3` still produced `artifact_type=tod_read_only_task_context_proof` rather than `tod_readonly_evidence_comparison`. Codex validation records this as `read_only_evidence_comparison_package_path_regression_missing`. APP-TOD-037 remains borrowed; the next rung is a regression-test packet that fails on the exact Package Path / Compare Artifact case before any repair is counted.

2026-07-24 regression-test packet drift: TOD captured a test insertion source anchor and a packet-anchor suitability review for `tests/TOD.ReadOnlyAuditRegression.Tests.ps1`. After Codex supplied the missing insertion pattern and validation command, TOD reported a bounded fallback completion, but no requested packet artifact was written and the test file still contains no `Package Path` / `Compare Artifact` / `tod_readonly_evidence_comparison` regression. Codex validation in `runtime_remote_training/tod_independent_resolution_attempts/TOD_READONLY_EVIDENCE_COMPARISON_REGRESSION_TEST_PACKET_V1.r1.codex_validation.json` records `regression_test_packet_materialization_drifted_to_unrelated_fallback`. APP-TOD-037 remains borrowed; the next rung is an exact patch synthesis drill that must block honestly on missing `old_text_new_text` instead of making unrelated source changes.

2026-07-24 exact-patch drill reachability blocker: TOD attempted `TOD-READONLY-EVIDENCE-COMPARISON-EXACT-PATCH-SYNTHESIS-DRILL-V1-R1` with `Edit Mode: artifact_write` and `Validation Pattern: exact_patch_synthesis_drill`. The packaged prompt preserved the drill fields, but execution fell through to generic artifact-write handling and blocked on missing `New Text`; no requested `tod_exact_patch_synthesis_drill` artifact was produced. Codex validation in `runtime_remote_training/tod_independent_resolution_attempts/TOD_READONLY_EVIDENCE_COMPARISON_EXACT_PATCH_SYNTHESIS_DRILL_V1.r1.codex_validation.json` records `exact_patch_synthesis_drill_not_reachable_from_execute_chat_task_artifact_write`. APP-TOD-037 remains borrowed; the next rung is a read-only selector-reachability inspection proving whether `New-LocalExecutionExactPatchSynthesisDrillArtifact` is reachable from the active `execute-chat-task` selector chain before any selector-precedence repair is attempted.

2026-07-24 selector reachability evidence: TOD completed source-anchor inspections for `Invoke-LocalExecutionEngine` and `Test-LocalExecutionGenericBoundedTask`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_EXACT_PATCH_DRILL_LANE_REACHABILITY_SELECTOR_SOURCE_ANCHOR_V1.r1.latest.json` and `runtime_remote_training/read_only_audit_artifacts/TOD_EXACT_PATCH_DRILL_GENERIC_BOUNDED_DETECTOR_SOURCE_ANCHOR_V1.r1.latest.json`. These prove the active selector chain contains no visible exact-drill branch before generic bounded handling, while the generic detector returns true for `packet_formation` and `artifact_write`. A follow-up source-specific reachability judgment failed to publish the requested artifact after the task category normalized to `chat_execution`; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_EXACT_PATCH_DRILL_REACHABILITY_JUDGMENT_V1.r1.codex_validation.json` records that task mode preservation and executor-lane selection are separate concerns. APP-TOD-037 remains borrowed; the next smallest rung is an inspection of read-only assessment/chat-execution dispatch into artifact-producing lanes.

2026-07-24 stale active-lane admission blocker: A fresh retry of `TOD-CHAT-PACKAGE-TO-RUNTASK-CATEGORY-PRESERVATION-PROOF-V1-R1` was accepted into intake but did not execute. Arbitration returned `blocked_needs_operator` with `reason=idempotency_conflict`, selected the old active task `TOD-AUTHORITY-EVIDENCE-SUITABILITY-SELECTION-V1`, and preserved the active lane that has been `active` since `2026-07-23T13:29:36.5385407Z`. The queue contains 789 items with 297 queued, and the next queued item expired at `2026-07-23T13:36:09.2261026Z`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ACTIVE_LANE_STALE_ADMISSION_BLOCKER_V1.codex_validation.json` records `stale_active_lane_blocks_debt_training_admission`. APP-TOD-037 remains borrowed; the next smaller rung is `TOD-ACTIVE-LANE-STALENESS-CLASSIFICATION-SOURCE-ANCHOR-V1`, a no-code-change proof of how TOD should classify stale non-terminal lanes before any drainage or supersession patch is attempted.

2026-07-24 scorecard-current-truth blocker: The organizational maintenance scorecard rebuilt successfully and still reports borrowed capability at 78.4%, but its selected `next_action` remained on the older Engineering plus Model Utilization lane instead of the newer stale active-lane admission blocker. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_SCORECARD_STALE_NEXT_ACTION_AFTER_ACTIVE_LANE_BLOCKER_V1.codex_validation.json` records `scorecard_next_action_not_source_of_current_training_truth`. This does not change APP-TOD-037 credit; it adds a measurement debt rung: `TOD-SCORECARD-CURRENT-BLOCKER-SELECTION-EVIDENCE-PRECEDENCE-V1`.

2026-07-24 stale-existing-lane classification proof: Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ACTIVE_LANE_STALENESS_CLASSIFICATION_SOURCE_ANCHOR_V1.codex_validation.json` narrows the intake blocker further. The active lane is not missing and not terminal; it is an existing stale lane whose parent objective is completed, whose active task has no local result/review evidence, and whose queued successors have aged behind it. Existing `repair-missing-active-lane` behavior correctly refuses to mutate this case. The next TOD rung is `TOD-ACTIVE-LANE-STALE-EXISTING-CLASSIFICATION-ARTIFACT-V1`: publish a no-code-change classification artifact from the same evidence before any repair/supersession patch is attempted.

2026-07-24 stale-existing classification artifact R1 rejected: TOD accepted `TOD-ACTIVE-LANE-STALE-EXISTING-CLASSIFICATION-ARTIFACT-V1-R1` under `APP-TOD-037`, packaged it, and completed the local `report_only` run without source edits. The requested artifact path was written, but Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ACTIVE_LANE_STALE_EXISTING_CLASSIFICATION_ARTIFACT_V1.r1.codex_validation.json` rejected capability credit because the artifact evaluated a prior provider-judgment contract (`TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_CONTRACT_V1.r1.codex_validation.json`) instead of the current stale active-lane evidence. This proves report-only execution reachability but exposes `read_only_report_target_disambiguation_failure`: TOD must distinguish the current task's requested input artifacts and output artifact path from older read-only audit subjects before it can publish the stale-lane classification.

2026-07-24 read-only target disambiguation supporting pass: TOD backed down to source-anchor and label-shape rungs. `TOD_RPT_DISAMBIG_R4.latest.json` captured `scripts/engines/LocalExecutionEngine.ps1::Get-LocalExecutionReadOnlyAuditArtifactPaths` lines 2202-2292, proving the read-only audit selector requires accepted same-line input/output labels and otherwise falls back to the last artifact path in combined task text. `TOD_RPT_DISAMBIG_LABEL_R6.latest.json` then reran the audit under an isolated objective context with accepted `Input Evidence:` and `Output Artifact:` labels; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_RPT_DISAMBIG_LABEL_R6.codex_validation.json` accepted the proof because the intended stale-lane validation artifact was inspected, provider-judgment fields did not leak, and no source files changed. This is a supporting pass, not borrowed-capability retirement. Next rung: `TOD-ACTIVE-LANE-STALE-EXISTING-FIELD-MATERIALIZATION-V1`, where TOD must materialize the actual active-lane/state/queue values in a clean context.

2026-07-24 semantic field materialization source-anchor pass: TOD first attempted `TOD-READONLY-AUDIT-SEMANTIC-FIELD-MATERIALIZATION-SOURCE-ANCHOR-V1` with source-anchor directives in the wrong field; the package rendered only `scripts/engines/LocalExecutionEngine.ps1` as task description and local execution correctly blocked with `local_fallback_needs_target_or_scope`. TOD then reran the task as `TOD-READONLY-AUDIT-SEMANTIC-FIELD-MATERIALIZATION-SOURCE-ANCHOR-V1-R2` with the executable source-anchor shape in `Scope`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_SEMANTIC_FIELD_MATERIALIZATION_SOURCE_ANCHOR_V1.r2.latest.json` from `scripts/engines/LocalExecutionEngine.ps1` lines 5126-5816. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_AUDIT_SEMANTIC_FIELD_MATERIALIZATION_SOURCE_ANCHOR_V1.r2.codex_validation.json` accepts this as a supporting pass: the source proves the generic read-only audit lane reads one selected input JSON object and evaluates fields on that object. Supporting contract-evaluator evidence shows required fields are checked on `$auditSource`, not computed from multiple live state artifacts. This keeps APP-TOD-037 open and narrows the next rung to `TOD-STATE-EVIDENCE-MATERIALIZATION-LANE-DISCOVERY-V1`.

2026-07-23 R25 validation: TOD later published `runtime_remote_training/tod_independent_resolution_attempts/TOD_CONTRACT_TAIL_AUTONOMOUS_NEWTEXT_PROOF_R25.latest.json` with a non-empty `new_text` packet candidate. Codex validation rejected it as independent credit in `runtime_remote_training/read_only_audit_artifacts/TOD_CONTRACT_TAIL_AUTONOMOUS_NEWTEXT_PROOF_R25.codex_validation.json`: the packet's `old_text` came from the read-only audit artifact construction block, while `new_text` came from an unrelated bounded edit execution switch block. This proves a narrower next gap: TOD can move past blank candidate text, but it must learn to preserve the source anchor's semantic purpose before a packet can be considered safe.

2026-07-23 semantic-preservation R1 validation: TOD accepted `TOD-SOURCE-ANCHOR-SEMANTIC-DELTA-PRESERVATION-V1-R1` as read-only work, but local execution wrote `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_SEMANTIC_DELTA_PRESERVATION_V1.r1.latest.json` with `artifact_type=tod_patch_evidence_authority_classification` from `runtime_remote_training/cleanup_holds/TSK-0100_95361c28beae.patch` instead of the requested `tod_source_anchor_semantic_delta_preservation_review` for the R25 input artifact. Codex validation rejected the attempt in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_SEMANTIC_DELTA_PRESERVATION_V1.r1.codex_validation.json`. This is no independent credit: TOD preserved read-only boundaries but did not preserve the requested artifact type or input artifact, so the semantic judgment never actually ran.

2026-07-23 contract-preservation R1 validation: TOD then attempted `TOD-REQUESTED-ARTIFACT-TYPE-AND-INPUT-PRESERVATION-V1-R1`. Direct `run-task` proved a cleaner blocker: the Codex wrapper did not execute, and local fallback reported `local_execution_scope_not_supported` because the current read-only lane can produce `tod_read_only_audit_artifact` but not the requested `tod_requested_artifact_contract_preservation_review`. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_REQUESTED_ARTIFACT_TYPE_AND_INPUT_PRESERVATION_V1.r1.codex_validation.json`. No artifact was created, no source code was modified, and no credit is granted.

2026-07-23 lane-definition R1 validation: TOD attempted `TOD-TASK-SPECIFIC-ARTIFACT-CONTRACT-LANE-DEFINITION-V1-R1`. Direct `run-task` again blocked with `codex_wrapper_only_no_execution` plus `local_execution_scope_not_supported`: the current local fallback can produce generic `tod_read_only_audit_artifact`, but not `tod_task_specific_artifact_contract_lane_definition`. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_TASK_SPECIFIC_ARTIFACT_CONTRACT_LANE_DEFINITION_V1.r1.codex_validation.json`. This proves the next smaller rung must use a supported generic read-only artifact to preserve the missing contract shape instead of asking TOD to create a new custom artifact type.

2026-07-23 generic-summary R1 validation: TOD ran `TOD-READONLY-GENERIC-BLOCKER-TO-ARTIFACT-CONTRACT-SUMMARY-V1-R1` directly and local fallback published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_GENERIC_BLOCKER_TO_ARTIFACT_CONTRACT_SUMMARY_V1.r1.latest.json` with `artifact_type=tod_read_only_audit_artifact`. Mechanical checks passed: input evidence read, artifact write, schema readback, and no-code-change assertion. Codex validation rejected independent credit in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_GENERIC_BLOCKER_TO_ARTIFACT_CONTRACT_SUMMARY_V1.r1.codex_validation.json` because the generic artifact did not preserve the contract-specific fields needed for training: requested input artifact, requested output artifact, requested artifact type, unsupported reason, and next learned lane proposal.

2026-07-23 field-preservation R1/R2 validation: TOD attempted `TOD-GENERIC-READONLY-AUDIT-EVIDENCE-FIELD-PRESERVATION-V1-R1` and `R2`. Both attempts were accepted as read-only source-anchor work, but no requested artifact was created. The latest execution truth shows `reason_code=local_fallback_needs_target_or_scope`: local execution routed the task through `Invoke-LocalExecutionGenericBoundedTask` and treated `scripts/engines/LocalExecutionEngine.ps1`, the output artifact, and the input evidence artifact as competing target files. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_READONLY_AUDIT_EVIDENCE_FIELD_PRESERVATION_V1.r1_r2.codex_validation.json`. This is no independent credit; it proves a runtime-support blocker before engineering inspection can begin: source-anchor task category and source/evidence/output roles are not being preserved into the source-anchor executor lane.

2026-07-23 lane-selection R1 validation: TOD ran `TOD-SOURCE-ANCHOR-LANE-SELECTION-PRESERVATION-V1-R1` and local execution published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_LANE_SELECTION_PRESERVATION_V1.r1.latest.json` with `artifact_type=tod_read_only_task_context_proof`. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_LANE_SELECTION_PRESERVATION_V1.r1.codex_validation.json`. The attempt passed as a diagnostic context proof but does not count as independent capability credit: it proves the structured category that reached local execution was `inspection_only`, while `source_anchor_observation` appeared only in prose scope text. The next rung must prove structured `source_anchor_observation` survives into local execution or identify the branch that intercepts it.

2026-07-23 structured-category R1 validation: TOD ran `TOD-SA-STRUCTURED-CATEGORY-CONTEXT-PROOF-V1-R1`. The rendered package preserved `Task Category: source_anchor_observation`, but no requested artifact was created. Latest execution recorded `reason_code=codex_wrapper_only_no_execution`: the Codex wrapper accepted the package without executing it, and the local fallback rejected the read-only output path because `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_CONTEXT_PROOF_V1.r1.latest.json` did not already exist. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_CONTEXT_PROOF_V1.r1.codex_validation.json`. This is no independent credit; it proves package rendering can preserve the structured category while the execution bridge still fails to honor the requested read-only artifact write.

2026-07-23 read-only output eligibility R1 validation: TOD ran `TOD-READONLY-OUTPUT-ARTIFACT-ELIGIBILITY-PROOF-V1-R1` through the supported `inspection_only` task-context proof lane. Local execution published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_OUTPUT_ARTIFACT_ELIGIBILITY_PROOF_V1.r1.latest.json`, changed only that artifact, and passed task-context read, artifact write, schema readback, and non-edit assertions. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_OUTPUT_ARTIFACT_ELIGIBILITY_PROOF_V1.r1.codex_validation.json`. This supporting rung passes, but it does not retire debt: it proves new read-only output artifact eligibility for `inspection_only`, not source-anchor category survival or provider judgment.

2026-07-23 source-anchor category retry R1 validation: TOD ran `TOD-SOURCE-ANCHOR-STRUCTURED-CATEGORY-RETRY-V1-R1` after the output-eligibility proof. The rendered package again preserved `Task Category: source_anchor_observation`, but no requested artifact was created. Latest execution recorded the same wrapper-only and local fallback failure. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_STRUCTURED_CATEGORY_RETRY_V1.r1.codex_validation.json`. This proves the issue is not merely new-output eligibility; the `source_anchor_observation` category needs the source-file/anchor contract and cannot be used as a generic context-proof category by name alone.

2026-07-23 source-anchor contract R2 validation: TOD reran `TOD-SOURCE-ANCHOR-CONTRACT-BRANCH-INSPECTION-V1-R2` with the executable source-anchor shape: task type `inspection`, task category `source_anchor_observation`, `Source File: scripts/engines/LocalExecutionEngine.ps1`, `Anchor Pattern: function Test-LocalExecutionSourceAnchorObservationTask`, matching `Output Artifact`/`Output`, and `Required Artifact Type: tod_source_anchor_observation`. Local execution published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_CONTRACT_BRANCH_INSPECTION_V1.r2.latest.json` from `Invoke-LocalExecutionSourceAnchorObservation`, captured lines 3310-3355, passed source read, anchor match, schema readback, and no-code-change assertions. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_CONTRACT_BRANCH_INSPECTION_V1.r2.codex_validation.json`. This is a supporting runtime-contract pass, not APP-TOD-037 retirement.

2026-07-23 field-preservation retry R1 validation: TOD ran `TOD-SOURCE-ANCHOR-FIELD-PRESERVATION-RETRY-V1-R1` with the proven source-anchor contract shape. Local execution published `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_FIELD_PRESERVATION_RETRY_V1.r1.latest.json`, captured `scripts/engines/LocalExecutionEngine.ps1` lines 5222-5332 around `$evidenceFields = @(`, and passed source read, anchor match, schema readback, and no-code-change assertions. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_FIELD_PRESERVATION_RETRY_V1.r1.codex_validation.json`. The captured block proves the generic read-only audit producer preserves status/materialization fields but not the needed contract fields: requested input artifact, requested output artifact, requested artifact type, unsupported reason, and next learned lane proposal.

2026-07-23 field-preservation delta R1 validation: TOD ran `TOD-GENERIC-READONLY-AUDIT-FIELD-PRESERVATION-DELTA-PROPOSAL-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_READONLY_AUDIT_FIELD_PRESERVATION_DELTA_PROPOSAL_V1.r1.latest.json` with `artifact_type=tod_source_anchor_delta_proposal`. The artifact read the input source anchor, validated `source_anchor_valid=true`, preserved `candidate_new_text=""`, and named `autonomous_candidate_new_text_missing`. Codex validation rejected the attempt as a pass in `runtime_remote_training/read_only_audit_artifacts/TOD_GENERIC_READONLY_AUDIT_FIELD_PRESERVATION_DELTA_PROPOSAL_V1.r1.codex_validation.json` because it did not state `current_purpose` or `requested_behavior_delta` before blocking. This narrows the missing engineering skill: semantic source-anchor understanding must precede safe patch synthesis.

2026-07-23 local-provider probe: Codex ran an advisory-only local provider probe against the bounded field-preservation source excerpt. The local `tod-local-chat` provider returned usable `current_purpose` and `requested_behavior_delta` text when given a clean excerpt and explicit requested behavior. Evidence: `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_PURPOSE_DELTA_LOCAL_PROVIDER_PROBE_V1.codex_validation.json`. This does not count as TOD progress; it proves the next rung should be Model Utilization supervision rather than more deterministic routing.

2026-07-24 engineering-corpus intake and source-anchor delta split: TOD ran a guided Engineering Corpus chain under `OBJ-0292`. R1/R2 failed into `tod_read_only_task_context_proof`; Codex validations `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EVIDENCE_INTAKE_FIVE_CANDIDATES_V1.r1.codex_validation.json` and `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EVIDENCE_INTAKE_FIVE_CANDIDATES_V1.r2.codex_validation.json` reject credit and record that the corpus classifier requires canonical `Input Artifact` and `Output Artifact` labels. R3 passed the classifier lane with eight usable candidates in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EVIDENCE_INTAKE_FIVE_CANDIDATES_V1.r3.latest.json`; R4 derived eight episode candidates in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EPISODE_CANDIDATE_MANIFEST_FIVE_V1.r4.latest.json`; and R5 accepted a precise blocker in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_HELDOUT_CANDIDATE_NEWTEXT_FROM_MANIFEST_V1.r5.latest.json`: source-anchor evidence exists, but `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor` is missing. R6/R7 then proved parent objective context can contaminate artifact selection, repeatedly selecting the corpus classifier when a delta proposal was requested. R8 isolated the same source-anchor delta proposal under clean `OBJ-0293` context and produced `runtime_remote_training/read_only_audit_artifacts/TOD_SOURCE_ANCHOR_DIRECT_DELTA_PROPOSAL_CLEAN_CONTEXT_V1.r8.latest.json`, which correctly names `scripts/engines/LocalExecutionEngine.ps1` as the target and blocks on `autonomous_candidate_new_text_missing`. This is a supporting Runtime/Evidence/Model-Utilization pass, not APP-TOD-037 retirement. The next rung is not more corpus routing; it is `TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`.

2026-07-24 model-utilization route and artifact-lane split: TOD attempted `TOD-MODEL-UTILIZATION-SOURCE-ANCHOR-ENGINEERING-JUDGMENT-V1-R1` against the clean R8 source-anchor proposal. The package preserved `read_only_assessment`, input/output artifacts, required artifact type, and provider-judgment fields, but execution selected Codex (`codex_required`) and no judgment artifact was written; Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_SOURCE_ANCHOR_ENGINEERING_JUDGMENT_V1.r1.codex_validation.json`. TOD then ran `TOD-MODEL-UTILIZATION-READONLY-SUITABILITY-SELECTOR-INSPECTION-V1-R1`, publishing a source-anchor artifact for `scripts/TOD.ps1`; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_READONLY_SUITABILITY_SELECTOR_INSPECTION_V1.r1.codex_validation.json` found that the selector admits `inspection`, `inspection_only`, `report_only`, `diagnostic_only`, `review_only`, `validation`, and `source_anchor_observation`, but not `read_only_assessment`. A reroute as `inspection_only` reached local execution in `TOD-MODEL-UTILIZATION-JUDGMENT-INSPECTION-ONLY-REROUTE-V1-R1`, but blocked with `read_only_audit_required_artifact_type_unsupported` because the engine can only publish a generic `tod_read_only_audit_artifact`, not `tod_model_utilization_engineering_judgment`; Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_INSPECTION_ONLY_REROUTE_V1.r1.codex_validation.json`. This splits the blocker cleanly: route admission can be avoided with a supported read-only category, but model-utilization still needs a first-class artifact lane that records provider reachability, reply summary, TOD accept/reject judgment, prompt improvement, and `counts_as_engineering_implementation_credit=false`.

2026-07-24 model-utilization contract-shape continuation: TOD inspected the artifact-lane failure line in `TOD-MODEL-UTILIZATION-JUDGMENT-ARTIFACT-LANE-SOURCE-ANCHOR-V1-R1`; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_ARTIFACT_LANE_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepted the line-anchor proof but noted the context was too narrow, and direct source validation showed the future lane belongs before the final Required Artifact Type mismatch check in `Invoke-LocalExecutionReadOnlyAuditArtifact`. TOD then attempted `TOD-MODEL-UTILIZATION-JUDGMENT-LANE-CONTRACT-DESIGN-V1-R1`, but the generic contract evaluator captured only `provider_reachable` from a vertical required-field list. `TOD-READONLY-MULTILINE-REQUIRED-FIELDS-PARSING-SOURCE-ANCHOR-V1-R1` inspected the parser; Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_MULTILINE_REQUIRED_FIELDS_PARSING_SOURCE_ANCHOR_V1.r1.codex_validation.json` found that the current parser handles same-line `Required output fields:` tokens but not newline-separated field lists under the label. TOD reran `TOD-MODEL-UTILIZATION-JUDGMENT-LANE-CONTRACT-DESIGN-SINGLE-LINE-FIELDS-V1-R1` with the accepted single-line shape and published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_LANE_CONTRACT_DESIGN_SINGLE_LINE_FIELDS_V1.r1.latest.json`; it preserved all 14 required fields and correctly rejected them as missing. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_LANE_CONTRACT_DESIGN_SINGLE_LINE_FIELDS_V1.r1.codex_validation.json` accepts this as a supporting contract-evaluation pass only. Model-utilization remains borrowed until TOD can populate those fields as values in a first-class judgment artifact and decide accept/reject on provider output.

2026-07-24 minimal-spec attempt: TOD ran `TOD-MODEL-UTILIZATION-JUDGMENT-LANE-MINIMAL-SPEC-V1-R1` as an `inspection_only` task against the prior contract validation artifact and wrote `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_LANE_MINIMAL_SPEC_V1.r1.latest.json`. The local lane preserved all 14 requested spec/judgment field names, classified them as missing, and set `pass_or_reject=reject`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_LANE_MINIMAL_SPEC_V1.r1.codex_validation.json` accepts supporting runtime credit but rejects model-utilization credit: TOD did not author `artifact_lane_purpose`, `required_inputs`, `pass_reject_rules`, provider reachability, provider reply summary, accept/reject judgment, prompt improvement, or a next training rung as semantic values. The next smallest rung is to inspect the generic read-only artifact writer and identify the exact source anchor where a task-specific model-utilization judgment/spec authoring lane would be introduced, without implementing it before TOD can describe the lane from current code.

2026-07-24 source-boundary grammar continuation: TOD first attempted `TOD-MODEL-UTILIZATION-JUDGMENT-SPEC-AUTHORING-LANE-SOURCE-ANCHOR-V1-R1/R2`, but those prompts used looser labels such as `Inspect Source File:` and `Find Anchor:`; local fallback treated the source file and output artifact as competing target files and blocked with `local_execution_scope_not_supported`. TOD then reran the same objective with the proven executable source-anchor grammar (`Source File:`, `Anchor Pattern:`, `Lines Before:`, `Lines After:`, `Output Artifact:`, `Required Artifact Type:`) as `TOD-MODEL-UTILIZATION-JUDGMENT-SPEC-AUTHORING-LANE-SOURCE-ANCHOR-V1-R3`. The run published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_SPEC_AUTHORING_LANE_SOURCE_ANCHOR_V1.r3.latest.json`, capturing `scripts/engines/LocalExecutionEngine.ps1` lines 6725-6835. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_SPEC_AUTHORING_LANE_SOURCE_ANCHOR_V1.r3.codex_validation.json` accepts this as source-boundary support only: the artifact shows the existing task-specific read-only artifact branches, the generic fallback, the contract-field evaluator, and the final unsupported-artifact-type rejection. The future model-utilization judgment/spec lane belongs in that branch set before generic fallback/rejection, but TOD has still not authored semantic model-utilization values or invoked a provider response.

2026-07-24 semantic field-value authoring attempt: TOD ran `TOD-MODEL-UTILIZATION-JUDGMENT-SPEC-FIELD-VALUE-AUTHORING-CONTRACT-V1-R1` against the R3 source-boundary artifact. It published `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_SPEC_FIELD_VALUE_AUTHORING_CONTRACT_V1.r1.latest.json`, but the artifact is another generic `tod_read_only_audit_artifact` with `classification=contract_field_evaluation_failed`, `pass_or_reject=reject`, and all requested semantic fields listed as missing. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_JUDGMENT_SPEC_FIELD_VALUE_AUTHORING_CONTRACT_V1.r1.codex_validation.json` rejects model-utilization credit. This narrows the blocker to `semantic_read_only_spec_value_authoring_from_source_boundary_evidence`: TOD can preserve field names and inspect the source boundary, but it cannot yet author field values such as lane purpose, required inputs, pass/reject rules, forbidden credit claims, and next rung from evidence.

2026-07-24 Engineering Corpus V2 realignment: Codex recorded `docs/training/TOD_LOCAL_ENGINEERING_INTELLIGENCE_PROGRAM_V2.md` and `runtime_remote_training/TOD_LOCAL_ENGINEERING_INTELLIGENCE_DECISION_V2.latest.json`, adopting Dave's correction that Engineering Corpus and Local Engineering Runtime should start now while small local models are used early as supervised episode generators, not implementation authorities. TOD then attempted `TOD-ENGINEERING-CORPUS-FOUNDATION-EPISODE-MATERIALIZATION-V1-R1` against `TOD_ENGINEERING_CORPUS_EPISODE_CANDIDATE_MANIFEST_FIVE_V1.r4.latest.json`. The task reached local execution but blocked honestly: no `runtime/tod_engineering_corpus/episodes/TOD-ENG-CORPUS-FOUNDATION-R1/episode.json` was written, and latest execution reported that the read-only audit lane produced `tod_engineering_corpus_episode_candidate_manifest` rather than the requested `tod_engineering_corpus_episode`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_FOUNDATION_EPISODE_MATERIALIZATION_V1.r1.codex_validation.json` rejects corpus-foundation and debt-reduction credit. TOD then backed down to `TOD-ENGINEERING-CORPUS-EPISODE-MATERIALIZATION-GAP-SOURCE-ANCHOR-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EPISODE_MATERIALIZATION_GAP_SOURCE_ANCHOR_V1.r1.latest.json`, capturing `scripts/engines/LocalExecutionEngine.ps1` lines 5710-5870. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_EPISODE_MATERIALIZATION_GAP_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepts this as supporting source-inspection evidence only. The captured source proves the current lane can enrich/carry episode candidates but does not contain a durable `runtime/tod_engineering_corpus/episodes/.../episode.json` materializer. Next rung: `TOD-ENGINEERING-CORPUS-CANDIDATE-TO-EPISODE-TRANSFORM-SPEC-V1`.

2026-07-24 candidate-to-episode transform-spec attempt: TOD ran `TOD-ENGINEERING-CORPUS-CANDIDATE-TO-EPISODE-TRANSFORM-SPEC-V1-R1` using the source-anchor artifact as evidence and requested `tod_engineering_corpus_candidate_to_episode_transform_spec`. Local execution again blocked because the corpus read-only lane selected `tod_engineering_corpus_episode_candidate_manifest` instead of the requested transform spec. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_CANDIDATE_TO_EPISODE_TRANSFORM_SPEC_V1.r1.codex_validation.json` rejects credit and narrows the blocker to `corpus_task_specific_lane_selection_and_transform_spec_materialization`. The next rung is `TOD-ENGINEERING-CORPUS-LANE-SELECTION-PRECEDENCE-SOURCE-ANCHOR-V1`: inspect why the candidate-manifest matcher wins before transform-spec or durable-episode intent can be honored.

2026-07-24 corpus lane precedence source-anchor pass: TOD completed `TOD-ENGINEERING-CORPUS-LANE-SELECTION-PRECEDENCE-SOURCE-ANCHOR-V1-R1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_LANE_SELECTION_PRECEDENCE_SOURCE_ANCHOR_V1.r1.latest.json`, capturing `scripts/engines/LocalExecutionEngine.ps1` lines 5961-6106. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_LANE_SELECTION_PRECEDENCE_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepts the source-anchor pass as supporting runtime evidence only. The captured source contains `wantsCorpusSourceAnchorEpisodeEnrichment`, `wantsHeldoutCandidateNewTextFromManifest`, `wantsCorpusEpisodeCandidateManifest`, and `wantsCorpusEvidenceIntakeClassifier`; it does not contain a candidate-to-episode transform-spec branch or durable episode materialization branch. The next rung is `TOD-ENGINEERING-CORPUS-LANE-SELECTION-PRECEDENCE-BOUNDED-PACKET-V1`, but no implementation credit is granted until TOD produces a safe bounded packet and validation.

2026-07-24 corpus lane precedence packet attempts: TOD ran `TOD-ENGINEERING-CORPUS-LANE-SELECTION-PRECEDENCE-BOUNDED-PACKET-V1-R1`, but the inspection-only request for `tod_bounded_repair_packet` selected the generic read-only audit lane and no packet was written. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_LANE_SELECTION_PRECEDENCE_BOUNDED_PACKET_V1.r1.codex_validation.json` rejects credit and records the lane-selection lesson. TOD then reran the same goal using the existing `packet_formation` / packet-body synthesis grammar as `TOD-ENGINEERING-CORPUS-LANE-SELECTION-PRECEDENCE-PACKET-BODY-SYNTHESIS-V1-R1`. That attempt reached the correct packet-body synthesis lane and blocked with `packet_body_synthesis_autonomous_new_text_missing`: source-anchor evidence, target file, and output path were present, but TOD could not safely synthesize same-purpose `new_text` without explicit New Text or field-insertion directives. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_LANE_SELECTION_PRECEDENCE_PACKET_BODY_SYNTHESIS_V1.r1.codex_validation.json` accepts this as a precise blocker only. Next rung: `TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1`.

2026-07-24 engineering context package blocker: TOD ran `TOD-ENGINEERING-CONTEXT-BUILDER-FOR-NEWTEXT-SYNTHESIS-V1-R1` under clean `OBJ-0313` context. The package preserved read-only mode, input artifact, prior blocker artifact, output artifact, required artifact type, and target source file. Local execution reached the read-only lane but produced no `tod_engineering_context_package`; it blocked with the precise summary that the generic `tod_read_only_audit_artifact` lane cannot satisfy the task-specific engineering context package contract. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_BUILDER_FOR_NEWTEXT_SYNTHESIS_V1.r1.codex_validation.json` accepts this as supporting evidence only. This confirms the revised training doctrine: the next useful work is not more routing paperwork, but `TOD-LOCAL-ENGINEERING-RUNTIME-CONTEXT-PACKAGE-LANE-V1`, a first-class lane for preparing source-anchor, blocker, constraints, validation, and model-role context so a local engineering runtime can generate supervised engineering episodes without Codex authoring the repair.

2026-07-24 local engineering runtime context-package source-anchor pass: TOD completed `TOD-LOCAL-ENGINEERING-RUNTIME-CONTEXT-PACKAGE-LANE-SOURCE-ANCHOR-V1-R1`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_RUNTIME_CONTEXT_PACKAGE_LANE_SOURCE_ANCHOR_V1.r1.latest.json`. The artifact read `scripts/engines/LocalExecutionEngine.ps1`, matched `read_only_audit_required_artifact_type_unsupported`, captured lines 6745-6905, and made no source edits. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_RUNTIME_CONTEXT_PACKAGE_LANE_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepts this as source-anchor evidence only. The current hook proves why the context-package attempt failed: custom read-only artifact types need a first-class learned lane, otherwise the generic audit artifact is correctly rejected. Next rung: use the Local Engineering Intelligence program's Stage 4 shape to teach `tod_engineering_context_package` materialization without crediting model output as TOD implementation.

2026-07-24 context-package field-insertion contract blocker: TOD ran `TOD-LOCAL-ENGINEERING-RUNTIME-CONTEXT-PACKAGE-LANE-FIELD-INSERTION-CONTRACT-V1-R1` to produce a non-code design contract for the future context-package lane. The task preserved input artifact, program reference, target file, output artifact, required fields, and no-edit/no-new-text restrictions, but local execution again selected the generic read-only audit artifact and rejected the requested `tod_field_insertion_contract`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_RUNTIME_CONTEXT_PACKAGE_LANE_FIELD_INSERTION_CONTRACT_V1.r1.codex_validation.json` accepts this as blocker evidence only. The important lesson is now explicit: mechanical packet field insertion exists, but TOD still cannot author a meaningful engineering-runtime contract artifact from source-anchor evidence. Next rung: inspect packet-body synthesis field-directive support and separate mechanical JSON field insertion from source-code lane authorship.

2026-07-24 packet-body field-directive source-anchor pass: TOD completed `TOD-PACKET-BODY-SYNTHESIS-FIELD-DIRECTIVE-SOURCE-ANCHOR-V1-R1`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_FIELD_DIRECTIVE_SOURCE_ANCHOR_V1.r1.latest.json`. The artifact read `scripts/engines/LocalExecutionEngine.ps1`, matched `packet_body_synthesis_autonomous_new_text_missing`, captured lines 3965-4125, and made no source edits. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_FIELD_DIRECTIVE_SOURCE_ANCHOR_V1.r1.codex_validation.json` accepts this as supporting source evidence only. The inspected hook proves that packet-body synthesis can consume explicit `New Text` or mechanical `insert_before_pattern` / `field_name` / `field_value` directives, but that this does not solve autonomous meaningful PowerShell branch synthesis. Next rung: build the Engineering Context Package shape using a supported generic artifact first, then promote to a first-class lane only after the context contract is proven.

2026-07-24 generic context-package stepping-stone rejected: TOD ran `TOD-ENGINEERING-CONTEXT-PACKAGE-SCHEMA-USING-SUPPORTED-GENERIC-AUDIT-V1-R1`, which mechanically published `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_PACKAGE_SCHEMA_USING_SUPPORTED_GENERIC_AUDIT_V1.r1.latest.json` as `tod_read_only_audit_artifact`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CONTEXT_PACKAGE_SCHEMA_USING_SUPPORTED_GENERIC_AUDIT_V1.r1.codex_validation.json` rejects capability credit because the artifact did not preserve the requested Stage 4 Engineering Context Package fields: objective, authority contract, problem statement, observed evidence, relevant source sections, tests, constraints, similar episodes, output contract, validation contract, prohibited actions, missing lane, next rung, or Dave-needed. This proves the supported generic audit lane is not a substitute for the Engineering Context Builder. Next rung: `TOD-LOCAL-ENGINEERING-RUNTIME-CONTEXT-BUILDER-FIRST-CLASS-LANE-V1`.

2026-07-24 first-class context-builder implementation attempt rejected: TOD ran `TOD-LOCAL-ENGINEERING-RUNTIME-CONTEXT-BUILDER-FIRST-CLASS-LANE-V1-R1` as an implementation-shaped packet-formation task. This was a genuine attempt, not a wrapper-only no-op: the generated prompt at `tod/out/prompts/TOD-LOCAL-ENGINEERING-RUNTIME-CONTEXT-BUILDER-FIRST-CLASS-LANE-V1-R1.md` includes bounded edit materialization for `scripts/engines/LocalExecutionEngine.ps1`. However, TOD selected the packet-body synthesis mechanics as the edit surface instead of the custom read-only artifact publication hook. Focused validation failed, the local executor rolled back the attempted change, and no requested packet artifact was published. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_ENGINEERING_RUNTIME_CONTEXT_BUILDER_FIRST_CLASS_LANE_V1.r1.codex_validation.json` grants honesty/rollback credit only. Next smaller rung: `TOD-CONTEXT-PACKAGE-LANE-IMPLEMENTATION-SURFACE-DISAMBIGUATION-V1`, where TOD must compare the two source anchors and choose the correct implementation surface before attempting another bounded edit.

2026-07-24 implementation-surface disambiguation and evidence-consumption failures: TOD ran `TOD-CONTEXT-PACKAGE-LANE-IMPLEMENTATION-SURFACE-DISAMBIGUATION-V1-R1`, but produced a `tod_read_only_task_context_proof` that inspected the generated prompt rather than the two supplied source-anchor artifacts. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_LANE_IMPLEMENTATION_SURFACE_DISAMBIGUATION_V1.r1.codex_validation.json` rejects credit and names `read_only_evidence_artifact_consumption_for_engineering_surface_selection` as missing. TOD then ran the smaller `TOD-READONLY-EVIDENCE-ARTIFACT-CONSUMPTION-FOR-SURFACE-SELECTION-V1-R1`; it mechanically published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_EVIDENCE_ARTIFACT_CONSUMPTION_FOR_SURFACE_SELECTION_V1.r1.latest.json`, but consumed only the first named input artifact and ignored `TOD_PACKET_BODY_SYNTHESIS_FIELD_DIRECTIVE_SOURCE_ANCHOR_V1.r1.latest.json`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_EVIDENCE_ARTIFACT_CONSUMPTION_FOR_SURFACE_SELECTION_V1.r1.codex_validation.json` rejects credit. Next smaller rung: `TOD-MULTI-INPUT-EVIDENCE-CONSUMPTION-SOURCE-ANCHOR-V1`.

2026-07-24 active-lane arbitration continuation: Codex retried `TOD-CONTEXT-PACKAGE-LANE-IMPLEMENTATION-SURFACE-DISAMBIGUATION-V1-R1` as a narrow read-only comparison task, but TOD intake returned `blocked_needs_operator` and preserved the current active lane. The active lane was already blocked on `write-a-concise-implementation-plan-and-ask-if-mim-request-1abaa207-ba16-4c11-8d9b-0cb7d2fd5d47-force_bounded_replan-implementation` with `reason_code=blocked_missing_bounded_edit_mode`. Codex validation in `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_LANE_IMPLEMENTATION_SURFACE_DISAMBIGUATION_V1.r1.codex_validation.json` grants no engineering credit and records the next gate: TOD needs an active-lane blocker resolution/supersession policy before fresh Engineering Context Builder training can be admitted without overwriting live work. Next rung: `TOD-ACTIVE-LANE-BLOCKED-TASK-SUPERSESSION-POLICY-V1`.

2026-07-23 model-utilization supervision R1 validation: TOD attempted `TOD-MODEL-UTILIZATION-PURPOSE-DELTA-SUPERVISION-V1-R1`, but no requested provider-judgment artifact was produced at `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PURPOSE_DELTA_SUPERVISION_V1.r1.latest.json`. Latest execution recorded `status=blocked` and `reason_code=codex_wrapper_only_no_execution`, with wrapper package-path check passed, wrapper execution handoff failed, and local fallback eligibility failed. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PURPOSE_DELTA_SUPERVISION_V1.r1.codex_validation.json`. This is no TOD credit. The missing capability is now narrower: TOD needs a real local model-utilization provider-judgment lane or an inspected, bounded blocker naming the exact hook that should own provider invocation and judgment artifact publication.

2026-07-23 model-utilization local-lane materialization R1-R3 validation: TOD completed three source-anchor inspections for the missing provider-judgment lane. R1 captured `scripts/Invoke-TODConversationProvider.ps1` lines 1-161 and proved the provider script exposes endpoint interaction, `Invoke-RestMethod`, and response-content extraction. R2 captured `scripts/TOD.ps1::Test-TaskAllowsLocalExecutionWithoutMaterialization` and proved the allowance gate admits known read-only categories but not `model_utilization`. R3 captured the LocalExecutionEngine branch that returns `read_only_audit_required_artifact_type_unsupported`, proving the generic read-only artifact writer cannot satisfy a custom provider-judgment artifact contract without a task-specific lane. Codex validation artifacts: `TOD_MODEL_UTILIZATION_LOCAL_LANE_MATERIALIZATION_V1.r1.codex_validation.json`, `.r2.codex_validation.json`, and `.r3.codex_validation.json`. This is scaffolded inspection progress, not retirement.

2026-07-23 provider-judgment lane packet R1 validation: TOD attempted `TOD-MODEL-UTILIZATION-PROVIDER-JUDGMENT-LANE-PACKET-V1-R1`, but no packet was produced. Local execution blocked with `local_fallback_needs_target_or_scope` because the source file, input artifacts, supporting artifacts, and output artifact were still competing as candidate target paths. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_PROVIDER_JUDGMENT_LANE_PACKET_V1.r1.codex_validation.json`.

2026-07-23 admission-gate packet R1 validation: TOD then attempted the smaller `TOD-MODEL-UTILIZATION-ADMISSION-GATE-PACKET-V1-R1` against only `scripts/TOD.ps1` and the R2 source anchor. No packet was produced. Local execution still blocked with `local_fallback_needs_target_or_scope`, now narrowed to missing `edit_mode`: the executor requires explicit current-code edit directives or an inferable markdown section update and did not synthesize old/new text from the source-anchor input. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_MODEL_UTILIZATION_ADMISSION_GATE_PACKET_V1.r1.codex_validation.json`.

2026-07-23 packet-formation execution-contract R1 validation: TOD ran `TOD-PACKET-FORMATION-EXECUTION-CONTRACT-INSPECTION-V1-R1` with the full executable source-anchor contract. Local execution published `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_EXECUTION_CONTRACT_INSPECTION_V1.r1.generic_bounded_task_source_anchor.latest.json`, captured `scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionGenericBoundedTask` lines 8887-9107, and passed source read, anchor match, schema readback, artifact write, and no-code-change assertions. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_EXECUTION_CONTRACT_INSPECTION_V1.r1.codex_validation.json`. The captured source proves the local fallback requires a single bounded target plus executable edit directives: `artifact_write` needs `New Text`; `replace_text` needs `Old Text` and `New Text`; `insert_after` needs `Anchor` and `Snippet`; targetless `validation_only` needs `Validation Command`. This is a guided execution-contract pass, not debt retirement, because TOD still has not synthesized a safe same-purpose packet body from source-anchor evidence.

2026-07-23 packet-body synthesis R1 validation: TOD ran `TOD-PACKET-BODY-SYNTHESIS-FROM-SOURCE-ANCHOR-V1-R1` against the verified execution-contract source-anchor artifact and one target source file. Local execution preserved the input/target/output shape far enough to reach `Invoke-LocalExecutionPacketBodySynthesis`, then blocked with `packet_body_synthesis_autonomous_new_text_missing` because no autonomous same-purpose `new_text` synthesis exists without explicit `New Text` or field-insertion directives. Codex validation accepted this as the expected precise-blocker outcome in `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_BODY_SYNTHESIS_FROM_SOURCE_ANCHOR_V1.r1.codex_validation.json`. This is a useful guided blocker, not a packet candidate and not debt retirement.

2026-07-23 local-provider judgment R1 validation: TOD attempted `TOD-LOCAL-PROVIDER-SOURCE-ANCHOR-PURPOSE-DELTA-JUDGMENT-V1-R1`, but no provider-judgment artifact was created. Latest execution blocked with `codex_wrapper_only_no_execution`; the fallback also reported `local_execution_scope_not_supported` because it treated the source-anchor input artifact and requested output artifact as competing target files. Codex validation recorded this in `runtime_remote_training/read_only_audit_artifacts/TOD_LOCAL_PROVIDER_SOURCE_ANCHOR_PURPOSE_DELTA_JUDGMENT_V1.r1.codex_validation.json`. This is no TOD credit and proves the next support gap: model-utilization tasks need an executable read-only lane that invokes the local provider and writes a judgment artifact without treating evidence artifacts as edit targets.

2026-07-31 fresh independent demonstration: TOD invoked the verified local DeepSeek provider and captured a fresh non-empty response in `runtime_remote_training/engineering_corpus/TOD_MODEL_UTILIZATION_FRESH_DEEPSEEK_RETRY_R1006.latest.json`. The response proposed a task-specific `enterprise_router_openapi_tag` selector, a non-unique ten-character anchor, and prose instead of an executable validator. TOD independently rejected the candidate before mutation in `TOD_MODEL_UTILIZATION_FRESH_DEEPSEEK_VERDICT_R1007.latest.json`, then materialized a safer retry instruction in `TOD_MODEL_UTILIZATION_FRESH_DEEPSEEK_REPLAN_R1008.latest.json` requiring exact source evidence, process-level behavior, strict JSON, parser validation, and a focused isolated test. The Examiner in `TOD_APP_037_MODEL_UTILIZATION_EXAMINER_R1.latest.json` passed this as model-supervision judgment only. It grants no source-engineering or implementation credit.

Proficiency: `independent`; TOD can invoke a local engineering provider through the preserved artifact roles, distinguish provider availability from proposal quality, reject unsafe or unverifiable help before mutation, and turn the rejection into a stricter bounded retry. Safe source-patch synthesis, application, and behavioral validation remain separate Engineering debt.

Independent Demonstration: `passed_on_fresh_deepseek_response`; TOD authored the provider invocation artifact, accept/reject verdict, and prompt-improvement replan without Codex writing those artifacts. `counts_as_engineering_implementation_credit=false` remained preserved.

Freeze: frozen pending independent Auditor retirement judgment; the provider response, verdict, replan, and Examiner evidence preserve the learned model-supervision sequence. Prevention lesson: provider reachability never grants mutation authority; unsafe help must be rejected and converted into a more exact next request.

Retirement: retired; independent Auditor R2 judged the frozen fresh DeepSeek model-utilization demonstration eligible after Examiner verification of provider invocation, unsafe-candidate rejection before mutation, and evidence-grounded replan.

### APP-TOD-038: Newline-Equivalent Shadow Patch Semantic Validation

Borrowed From: Codex escalation after repeated TOD and local-provider attempts.

Reason: TOD and three evaluated local engineering providers repeatedly produced or evaluated bounded multiline candidates whose `old_text` used LF while the inspected PowerShell source used CRLF. The shadow semantic gate compared raw text ordinally, rejected newline-equivalent anchors before isolated execution, and therefore could not distinguish a valid semantic candidate from transport-level newline drift.

Incident: `TOD-EXECUTABLE-SEMANTIC-PATCH-GATE-NEWLINE-EQUIVALENCE-R64-R75`

Capability: Detect newline-equivalent bounded patch anchors without globally rewriting the target, choose the unique actual source representation, apply the matching old/new pair only in a temporary workspace, run parser and focused validation, prove production is unchanged, and reject ambiguous or semantically invalid candidates.

Current Apprentice: TOD

Progress: `borrowed`; after TOD completed wider source inspection and Qwen3 completed one evidence-backed retry without producing a valid repair, Codex applied the narrow control-plane repair to `scripts/engines/LocalExecutionEngine.ps1` and added the focused CRLF-source/LF-candidate regression in `tests/TOD.LocalFallbackExecutor.Tests.ps1`. PowerShell parsing passed for both edited files. The new focused test passed in the full file run; the full historical test file remains red with 33 unrelated pre-existing failures. R75 proves newline-equivalent structural matching now succeeds before a separate invalid validation-command rejection. Evidence: `TOD_SEMANTIC_GATE_NEWLINE_WIDE_SOURCE_R65.latest.json` through `TOD_AUDITOR_VERDICT_R48_POST_NEWLINE_GATE_REPLAY_R75.latest.json`.

Independent Demonstration: `pending`; TOD must select a fresh mixed-newline fixture, produce a bounded candidate without Codex supplying the patch fields, run the isolated semantic gate, capture parser and focused behavior evidence, prove the real target is unchanged, and publish Examiner and Auditor verdicts.

Freeze: partial; implementation and one focused regression are present, but TOD has not reproduced or improved the capability independently.

Retirement: open.

### APP-TOD-034: Patch Evidence Ingestion For Read-Only Audits

Borrowed From: Codex/TOD blocker analysis during route experiment authority classification.

Reason: After the read-only task type was preserved, TOD correctly carried `task_mode=read_only_assessment` and `bounded_edit_mode=false`, but local execution still blocked because the saved route experiment evidence is a `.patch` under `runtime_remote_training/cleanup_holds/`, which is outside the local engine bounded safe roots. The existing read-only audit lane expects JSON evidence under `runtime_remote_training/read_only_audit_artifacts/` and cannot consume saved patch evidence directly.

Incident: `TOD-READONLY-PATCH-EVIDENCE-SAFE-ROOT-BLOCKER-20260721`

Capability: TOD must safely ingest preserved patch evidence for read-only classification without treating the patch as an edit target, without broad write access to cleanup holds, and without copying unsafe route behavior into product files.

Current Apprentice: TOD

Progress: `retired`; Codex repaired the local executor/control-plane rung after TOD's blocked attempt. TOD then completed R6 through the repaired read-only patch evidence lane and repeated R7 without additional code changes, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_PATCH_EVIDENCE_R6.latest.json` and `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_PATCH_EVIDENCE_R7.latest.json`. Fresh-target R1/R2 then exposed a stale-patch precedence blocker. After that rung was repaired, TOD completed `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3` from a broad fresh-target request, registered `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch` from commit `9e9c44454556`, and published `runtime_remote_training/read_only_audit_artifacts/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.latest.json`. Reliability repeat R250 independently classified `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch`, found nonempty response-authority signals, wrote `runtime_remote_training/read_only_audit_artifacts/TOD_PATCH_EVIDENCE_AUTHORITY_CLASSIFICATION_R250.latest.json`, and preserved the no-source-edit boundary. R251B verified that the only remaining blocker was the registry's old reliability caveat.

Proficiency: `reliable`; TOD produced the blocker through R3/R5, completed R6, repeated R7, passed R3 fresh-target registration/classification without receiving an explicit patch path, and later passed R250 on a fresh route/authority patch evidence case without additional executor changes.

Independent Demonstration: `passed`; `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3` selected and registered a fresh route patch from repository history, ran the read-only patch evidence lane without an explicit input patch, published JSON evidence, and preserved the rule that route behavior may return only through learned capability/service paths.

Freeze: updated; the borrowed control-plane lesson and fresh-target demonstration are captured in `TOD_ROUTE_EXPERIMENT_AUTHORITY_CLASSIFICATION_V1.md`, `TOD_READ_ONLY_AUDIT_ARTIFACT_LANE_LEARNED_CAPABILITY.md`, `runtime_remote_training/read_only_audit_artifacts/TOD_PATCH_EVIDENCE_AUTHORITY_CLASSIFICATION_R250.latest.json`, and `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_RETIREMENT_ELIGIBILITY_AFTER_R250_R251B.latest.json`.

Retirement: retired; R250 satisfied the future fresh route/authority reliability repeat with real response-authority signals and no source mutation. R251B confirmed the prior blocker was only the old registry caveat, so APP-TOD-034 is no longer counted as borrowed.

### APP-TOD-033: Direct Chat Read-Only Task Mode Preservation

Borrowed From: Codex control-plane repair after TOD attempted a read-only route-classification task.

Reason: TOD was assigned `TOD-ROUTE-EXPERIMENT-AUTHORITY-CLASSIFICATION-V1` as `-Type read_only_assessment`, but `execute-chat-task` dropped the explicit type before intake arbitration. The task was reshaped into implementation work and blocked on bounded-edit requirements, even though the objective was read-only.

Incident: `TOD-READONLY-EXECUTE-CHAT-TASK-TYPE-DROP-20260721`

Capability: TOD must preserve explicit non-edit task modes through direct chat intake so read-only assessments, inspections, validation, recovery, and escalation tasks are not forced into bounded-edit packet shape.

Current Apprentice: TOD

Progress: `retired`; Codex repaired `scripts/TOD.ps1` so `execute-chat-task -Type read_only_assessment` becomes `task_mode=read_only_assessment` before arbitration, and added regression coverage in `tests/TOD.IntakeArbitration.Tests.ps1`. A later TOD direct-chat proof (`TOD-READONLY-DIRECT-CHAT-MODE-PRESERVATION-PROOF-V3B`) preserved `task_mode=read_only_assessment`, avoided `target_file` and `bounded_edit_mode` requirements, and published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_DIRECT_CHAT_MODE_PRESERVATION_PROOF_V3B.latest.json` through local execution. 2026-07-22 independent repeat: TOD accepted `TOD-READONLY-DIRECT-CHAT-INDEPENDENT-REPEAT-R4` through `execute-chat-task -Type read_only_assessment`, queued it without bounded-edit field rejection, ran it through the local fallback, selected saved route-authority evidence, and published `runtime_remote_training/read_only_audit_artifacts/TOD-READONLY-DIRECT-CHAT-INDEPENDENT-REPEAT-R4_20260721_remaining_dirty_mim_tod_route_experimen.latest.json` with validation checks passed and no product source changes. R228 then produced retirement eligibility proof for APP-TOD-033.

Proficiency: `independent`; TOD can now preserve read-only task mode through direct chat intake and complete a read-only classification artifact without requiring bounded-edit fields or changing source code.

Independent Demonstration: `passed`; `TOD-READONLY-DIRECT-CHAT-INDEPENDENT-REPEAT-R4` proved the fresh direct-chat read-only path with no new executor or selector changes during the repeat, no `target_file` requirement, no `bounded_edit_mode` requirement, and a validated read-only artifact write.

Freeze: partial; the current proof and regression coverage establish independent read-only preservation. A reliability freeze still requires recurring checks across inspection, validation, recovery, and escalation modes.

Retirement: retired; R228 published `runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_AUTHORITY_CLASSIFICATION_RETIREMENT_PROOF_R228.latest.json`, inspected the direct-chat read-only evidence, found APP-TOD-033 eligible, and preserved the no-code-change boundary. R229 failed to materialize the registry edit independently, so registry retirement editing remains separate training debt.

### APP-TOD-032: Route Experiment Authority Classification

Borrowed From: Codex validation and cleanup after mixed route-level cognition experiments.

Reason: A saved patch from `tmp_remote_mim/core/routers/studio.py` and `tmp_remote_mim/core/routers/tod_ui.py` contained useful ideas mixed with route-level cognition, hardcoded visible replies, location/weather examples, response-authority audit UI, active conversation state, and phrase-triggered TOD responses. TOD needs to learn how to classify this kind of mixed patch before it can safely reintroduce any behavior.

Incident: `MIM-TOD-ROUTE-EXPERIMENT-CLEANUP-20260721`

Capability: TOD must inspect a saved dirty patch, classify each block as process support, reusable service candidate, route debt, hardcoded response authority, phrase patch, or prohibited semantic authority; preserve useful evidence; reject unsafe route-level cognition; and propose a learned-capability return path before any code changes.

Current Apprentice: TOD

Progress: `retired`; Codex preserved the dirty patch, restored product route files, and seeded the first classification artifact in `docs/training/hard-route-audit/TOD_ROUTE_EXPERIMENT_AUTHORITY_CLASSIFICATION_V1.md` and `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_AUTHORITY_CLASSIFICATION_V1.latest.json`. TOD later reran read-only classification through the local patch evidence lane, including `runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_AUTHORITY_CLASSIFICATION_RETIREMENT_PROOF_V2.latest.json` and `runtime_remote_training/read_only_audit_artifacts/TOD-READONLY-AUTHORITY-INDEPENDENT-DISCOVERY-V3_20260721_remaining_dirty_mim_tod_route_experimen.latest.json`, preserving no-code-change assessment boundaries and identifying hardcoded-response authority, operator-contract authority, reusable service candidates, process support, and phrase-patch rejection buckets. After TOD exposed that the generic audit lane dropped domain evidence, Codex repaired the read-only audit lane to preserve patch-authority fields and synthesize bounded service-extraction plans. TOD then produced `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_SERVICE_EXTRACTION_PLAN_V4.latest.json`, selecting `observational_relationship_memory`, naming forbidden route-level response authority, and publishing generalized tests with `no_code_changes=true`. The next cycle repaired an `Input Patch` precedence defect where explicit patch evidence degraded into generic read-only context proof; focused validation passed in `tests/TOD.LocalFallbackExecutor.Tests.ps1` with `67/67` tests. After that repair, TOD/local execution produced `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_PATCH_AUTHORITY_CLASSIFICATION_V7.latest.json` from `runtime_remote_training/cleanup_holds/20260721_remaining_dirty_mim_tod_route_experiments.patch`, then `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_PATCH_SERVICE_EXTRACTION_V8.latest.json`, again selecting `observational_relationship_memory` and preserving route-authority blockers. A second fresh classification run produced `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_PATCH_AUTHORITY_CLASSIFICATION_V9.latest.json` from `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch`; `runtime_remote_training/read_only_audit_artifacts/TOD_FRESH_PATCH_SERVICE_EXTRACTION_V10.latest.json` correctly refused to invent a service boundary because the classification contained no reusable service candidate. 2026-07-22 repeat: `TOD-READONLY-DIRECT-CHAT-INDEPENDENT-REPEAT-R4` selected saved route-authority evidence without an explicit patch path and published a classification artifact; `TOD-DIRECT-CHAT-SERVICE-EXTRACTION-REPEAT-R5` inspected that artifact, selected `observational_relationship_memory` only because reusable-service evidence supported it, preserved hardcoded-response/operator-contract authority as blockers, and published generalized tests with `no_code_changes=true`. R228 then produced retirement eligibility proof for APP-TOD-032.

Proficiency: `independent`; TOD can classify mixed response-authority patches and produce or withhold a service-extraction plan from evidence while preserving route-authority blockers and no-code-change boundaries.

Independent Demonstration: `passed`; R4/R5 proved selection of saved route evidence, route-authority classification, service-boundary decision, blocker preservation, and read-only validation without source mutation or new control-plane repair during the repeat.

Freeze: partial; classification and service-extraction evidence exist. Reliability still requires a later fresh route-authority case with a different evidence source, but the independent demonstration rung is no longer pending.

Retirement: retired; R228 published `runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_AUTHORITY_CLASSIFICATION_RETIREMENT_PROOF_R228.latest.json`, inspected the route-authority classification and service-extraction evidence, found APP-TOD-032 eligible, and preserved the no-code-change boundary. R229 failed to materialize the registry edit independently, so registry retirement editing remains separate training debt.

### APP-TOD-031: Fresh Target Packet Loop Materialization

Borrowed From: Codex control-plane repair and coaching.

Reason: TOD needed to prove it could inspect a fresh target, synthesize a bounded packet, apply it, validate it, and clean it up. The first fresh packet attempt produced a precise blocker because exact source-anchor text was missing, and the control plane needed packet-formation artifact and shared-artifact write retry repairs before the loop could move reliably.

Incident: `TOD-INDEPENDENT-FRESH-TARGET-PACKET-LOOP-20260721`

Capability: TOD must independently convert current-code evidence into a bounded packet loop: target selection, source-anchor observation, packet synthesis, local apply, validation, cleanup, and durable evidence with no wrapper-only completion.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD published a source-anchor observation for `tmp_remote_mim/core/routers/public_chat.py`, synthesized `TOD_INDEPENDENT_FRESH_PUBLIC_CHAT_PACKET.latest.json`, applied the harmless packet through the local executor, and cleaned it up through an exact bounded edit after reverse-packet cleanup blocked. Codex repaired `scripts/TOD.ps1` packet-formation artifact materialization and shared-artifact write retry handling first, so this is not an independent demonstration. 2026-07-22 follow-up: TOD completed a stronger guided loop on `scripts/engines/LocalExecutionEngine.ps1`: active-lane anchor selection produced R1 evidence; an initial top-level function anchor packet was correctly rejected by packet quality; TOD backed down to an indented source anchor, materialized packet R7, passed quality review R8, applied R9, validated parser health, cleaned up R10, and left zero training markers. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/TOD_FRESH_CURRENT_CODE_PACKET_LOOP_GUIDED_PROOF_R10.latest.json`. 2026-07-22 source-anchor target-role follow-up: TOD completed R2K through R10C for `TOD-SOURCE-ANCHOR-PACKET-TARGET-DISAMBIGUATION-V1`, distinguished input artifact, output artifact, and source file roles, rejected an implementation-unsafe packet body, materialized a safe corrective packet, reviewed it, applied it, validated it, cleaned it up, and published `runtime_remote_training/learned_capabilities/TOD_SOURCE_ANCHOR_PACKET_TARGET_DISAMBIGUATION_GUIDED_PROOF.latest.json`. The proof explicitly records `guided_pass_not_independent`, so debt is not retired. 2026-07-23 role-disambiguation follow-up: TOD ran `OBJ-0165` / `tod-readonly-artifact-role-disambiguation-r1` through the local engine, published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_ARTIFACT_ROLE_DISAMBIGUATION_V1.r1.latest.json`, and classified Evidence Artifact and Package Path as read-only inputs, Inspect Source File as inspection input, Output as the evidence artifact to write, and Target File as a bounded edit target only when behavior-changing edit authority is explicit. The task completed with local execution, result `RES-0010`, review `REV-0005`, and the relevant Pester case `publishes read-only role classification when source and artifact paths are not edit targets` passed inside `tests/TOD.LocalFallbackExecutor.Tests.ps1`. 2026-07-23 corpus/synthesis follow-up: TOD ran `OBJ-0166` / `tod-engineering-corpus-heldout-candidate-newtext-r1` through the local read-only lane against the enriched engineering corpus manifest and published `runtime_remote_training/read_only_audit_artifacts/TOD_ENGINEERING_CORPUS_HELDOUT_CANDIDATE_NEWTEXT_V1.r1.latest.json`. The artifact selected a held-out source-anchor episode, proved `source_anchor_available=true`, preserved `candidate_new_text=""`, and named `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor` as the missing capability with `independent_credit_requested=false`. 2026-07-23 source-anchor scope follow-up: TOD first captured only the `Invoke-LocalExecutionReadOnlyAuditArtifact` function header, then widened the inspection to the generic fallback block and published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_ARTIFACT_PRODUCER_GENERIC_FALLBACK_ANCHOR_V1.r3.latest.json`. That artifact captured `scripts/engines/LocalExecutionEngine.ps1` lines 6515-6965, including `tod_read_only_audit_artifact`, `artifact_type = $artifactType`, required-field/readback validation, and no-code-change evidence. 2026-07-23 delta-proposal follow-up: TOD ran `OBJ-0170` / `tod-autonomous-meaningful-newtext-from-source-anchor-r1` against the R3 artifact and published `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_FROM_SOURCE_ANCHOR_V1.r1.latest.json`. The artifact correctly set `artifact_type=tod_source_anchor_delta_proposal`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `no_source_code_modified=true`, `candidate_new_text=""`, and blocker `autonomous_candidate_new_text_missing`. This proves progressive source-anchor scoping and precise missing-capability reporting, not packet-loop retirement. The full `tests/TOD.LocalFallbackExecutor.Tests.ps1` file still has unrelated packet-materialization failures, so these are rung improvements, not retirement. 2026-07-25 packet-apply validation follow-up: TOD attempted to apply its own R206 packet. R231 proved `add-task` drops explicit bounded-edit fields before materialization; R231B proved direct intake can preserve the packet fields but did not land durable source/result evidence; R232 applied the packet artifact but produced a false success because pattern-only validation allowed invalid PowerShell syntax; R233 failed to reverse it, so Codex performed a minimal stabilization. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/TOD_CURRENT_CODE_PACKET_MATERIALIZATION_R231_R233_VALIDATION.latest.json`. R234 then exposed path-role ambiguity: a source-anchor observation with problem evidence, source file, and output artifact was misrouted as a generic bounded task with multiple target candidates. R235 proved that naming the source file alone is insufficient because the source-anchor lane requires an explicit anchor pattern. R236 passed the narrowed guided rung by publishing `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_APPLY_VALIDATION_CONTRACT_SOURCE_ANCHOR_R236.latest.json`, which captured `scripts/engines/LocalExecutionEngine.ps1` lines 4416-4486 around `Invoke-LocalExecutionApplyPacketArtifact` validation and rollback. This adds a new missing capability: packet apply must require source syntax/compile validation and proven rollback before retirement credit, and TOD must independently select the source anchor rather than receiving it from Codex.

Proficiency: `guided`; TOD can perform the loop with supplied target/anchor scaffolding and a repaired control plane.

Independent Demonstration: `pending`; TOD must select/register a fresh harmless target from the active lane and run the full inspect -> source anchor -> packet -> apply -> validate -> cleanup loop without Codex providing prompt scaffolding, anchor directives, packet fields, or control-plane patches. The next proof must build on the 2026-07-23 role-disambiguation and held-out synthesis artifacts by teaching TOD to synthesize meaningful, safe `candidate_new_text` from verified source-anchor evidence instead of merely identifying that the source anchor exists. The proof must also validate source health, not just requested pattern presence, and must demonstrate rollback from an intentionally invalid packet or validation failure.

Freeze: partial; scaffolded capability evidence is recorded in `docs/training/learned-capabilities/TOD_FRESH_TARGET_PACKET_LOOP_SCAFFOLDED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-024: Research Observatory Conversation Evolution Routing

Borrowed From: Codex emergency repair.

Reason: The live Research Observatory conversation repeated the static Observation-Driven Intelligence initiative envelope when the operator made a meta-research observation about prior conversation quality, understanding, and response learning. This violated MIM's research-evolution training and made the page behave like retrieval instead of living research.

Incident: `MIM-OBSERVATORY-RESEARCH-EVOLUTION-STATIC-ENVELOPE-20260716`

Capability: Recognize when a Research Observatory turn changes the research object, rejects the current frame, identifies a conversation-derived observation, or proposes future action; route that turn before static envelope retrieval; validate the live public chat path without hardcoding Dave's exact wording.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/public_research_context.py`, added regression coverage in `tmp_remote_mim/tests/test_public_research_context.py`, deployed both files to the MIM Box, restarted `mim-mobile-web.service`, and proved the live `/public/chat/message` endpoint returns a research-evolution response for the failed Observation-Driven Intelligence prompt.

Independent Demonstration: `pending`; TOD must diagnose a fresh analogous Observatory conversation failure from live prompt evidence, identify whether the root is marker-gate ordering, missing research-evolution intent, static envelope fallthrough, or downstream mutation, then produce a bounded repair and validation evidence without Codex-authored code.

Freeze: open; no learned capability exists yet for Research Observatory conversation-evolution routing.

Retirement: open.

### APP-TOD-027: Public Homepage Structured Reply Rendering Boundary

Borrowed From: Codex emergency production repair.

Reason: The live public `mimtod.com` homepage rendered `[object Object]` in MIM chat bubbles because the homepage JavaScript passed the structured `/public/chat/message` `reply` object directly into the visible message renderer instead of extracting `reply.content` or `reply.text`.

Incident: `MIM-PUBLIC-HOMEPAGE-OBJECT-REPLY-RENDERING-20260720`

Capability: When a public MIM surface consumes a structured response contract, TOD must verify the UI display boundary extracts operator-visible text deterministically, preserves the semantic answer, and does not concatenate raw objects or metadata into the human chat transcript.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/routers/public_chat.py`, added a homepage-shell regression assertion in `tmp_remote_mim/tests/test_public_homepage_enterprise_shell.py`, deployed the router to `/home/testpilot/mim/core/routers/public_chat.py`, restarted `mim-mobile-web.service`, and proved the live homepage HTML includes `replyText(payload)` while the old `payload.reply || payload.message` object-rendering path is absent.

Independent Demonstration: `pending`; TOD must inspect a fresh MIM UI surface that receives a structured response, identify the display-text extraction boundary, add or validate a regression guard, and publish evidence without Codex selecting the exact target or patch.

Freeze: open; requires a learned-capability note after TOD demonstrates the structured-response display-boundary pattern on a fresh analogous surface.

Retirement: open.

### APP-TOD-028: Public Enterprise Product Question Routing

Borrowed From: Codex emergency production repair.

Reason: The live public `mimtod.com` MIM chat answered "what is an enterprise account?" with the generic conversation-purpose exploration fallback: "My first working hypothesis...". That was wrong because the Enterprise front door already defines the product context, setup flow, pricing guidance, and clean private Observatory value proposition.

Incident: `MIM-PUBLIC-ENTERPRISE-PRODUCT-QUESTION-ROUTING-20260720`

Capability: When a public MIM visitor asks about a visible product, account type, setup flow, pricing, or business benefit, TOD must ensure product-context authority is checked before generic exploration or structural-reasoning fallback. Product questions should answer from the product surface context and only ask discovery follow-ups after providing a useful explanation.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/routers/public_chat.py` so Enterprise product questions use the Enterprise product-context branch before `build_conversation_purpose_reply()`, added focused direct-answer regression checks in `tmp_remote_mim/tests/test_public_chat_direct_answers.py`, deployed the router to `/home/testpilot/mim/core/routers/public_chat.py`, restarted `mim-mobile-web.service`, and proved live `/public/chat/message` answers both "what is an enterprise account?" and "how could my business benefit from the enterprise account" without the generic hypothesis fallback.

Independent Demonstration: `pending`; TOD must inspect a fresh public product/context question that is being preempted by generic exploration, identify the correct authoritative content source, add the smallest routing or authority fix, validate with a live prompt, and publish evidence without Codex selecting the exact target or answer text.

Freeze: open; requires a learned-capability note after TOD demonstrates product-context authority on a fresh analogous public-surface question.

Retirement: open.

### APP-TOD-029: Observatory Service Knowledge Product Context Certification

Borrowed From: Codex emergency product-knowledge repair.

Reason: The public MIM chat needed to describe `/observatory` services 10/10, but Observatory and Enterprise product questions were still vulnerable to the generic exploration fallback. The live failure mode was visible as an answer beginning with "My first working hypothesis..." when the visitor asked for a basic product explanation.

Incident: `MIM-OBSERVATORY-SERVICES-CERTIFICATION-20260720`

Capability: When a visitor asks about Observatory services, Enterprise accounts, setup, tenant isolation, documents, integrations, MIM/TOD roles, or business value, MIM must answer from the current product/service context before generic exploration fallback. It must distinguish proven capabilities from setup-dependent integrations and avoid hallucinating live connections.

Current Apprentice: TOD

Progress: `borrowed`; Codex added an Observatory service catalog and product-context reply boundary in `tmp_remote_mim/core/routers/public_chat.py`, added a 10-question Observatory service certification smoke in `tmp_remote_mim/tests/test_public_chat_direct_answers.py`, separated Enterprise pricing questions from general Enterprise definition answers, deployed the router to `/home/testpilot/mim/core/routers/public_chat.py`, restarted `mim-mobile-web.service`, redesigned `/studio/auditor` as an Executive Truth surface with `/studio/auditor/lab` as the protected Behavior Lab, and proved the live `/public/chat/message` endpoint answers both "what is an enterprise account?" and "how much is an enterprise account?" in distinct modes.

Independent Demonstration: `pending`; TOD must independently inspect a fresh Observatory/Enterprise service question class, identify the authoritative service context, extend the certification set or auditor without Codex selecting the exact answer boundary, deploy safely, and prove live behavior.

Freeze: partial; evidence is recorded in `runtime_remote_training/read_only_audit_artifacts/MIM_OBSERVATORY_SERVICES_CERTIFICATION_V1.latest.json`, and the protected `/studio/auditor` certification run produced `runtime_remote_training/read_only_audit_artifacts/STUDIO_AUDITOR_OBSERVATORY_CERTIFICATION_V1.latest.json` with 10/10 passed. The Auditor UI now separates Executive Truth from Behavioral Testing and removes the default MIM chat panel. Full freeze requires expanding the auditor into the broader certification suite.

Retirement: open.

### APP-TOD-030: AgentMIM Visible Page-Context Fast Path Before Generic Chat

Borrowed From: Codex emergency production repair.

Reason: AgentMIM sidebar chat timed out on the Clients page when Dave asked what visible `bonus` records were. The page showed the relevant rows, but the backend did not receive structured visible-row context and therefore fell into the slower generic assistant path.

Incident: `AGENTMIM-CLIENTS-VISIBLE-RECORDS-SIDEBAR-TIMEOUT-20260720`

Capability: When a user asks a factual question about records currently visible on an AgentMIM page, TOD must ensure the page publishes enough structured context for MIM to answer deterministically before generic chat. The pattern includes identifying the visible data source, publishing `window.mimPageContext` for that surface, adding the smallest deterministic fast path, validating that generic chat is not called, and deploying safely.

Current Apprentice: TOD

Progress: `borrowed`; Codex added `window.mimPageContext.clients` to the Clients page, added `_maybe_answer_visible_client_records_request` before slower assistant paths, added regression tests, pushed commit `739bbcc5d88471da9376f7a121886ed082c2e4e8`, triggered Render deploy `dep-d9f4rgb7uimc73amaong`, and verified GitHub fast checks plus production `/health`. Live Chrome then showed inline page context was not reliable enough, so Codex added shared assistant send-time Clients table context collection in commit `8776e505a22c3b2cf321b771ea065a2bd2f7d974` and deployed `dep-d9f565b7uimc73ams4q0`. The first live sidebar smoke no longer timed out but answered too broadly, so Codex added named-row matching in commit `1bd202e626163e6f03f5d9d425b9357797150aaf`, passed the 11-test focused regression suite, and deployed `dep-d9f598jrjlhs73dj654g`. Final post-deploy Chrome smoke remains pending because the browser session refreshed back to the AgentMIM login page and the stale pre-refresh send hit a CSRF-session-token error.

Proficiency: `observed`; TOD has not yet independently inspected, materialized, implemented, and validated this class.

Independent Demonstration: `pending`; TOD must inspect a fresh AgentMIM page where sidebar MIM times out or ignores visible data, identify the missing page-context or deterministic answer boundary, produce a bounded implementation, validate that generic chat is bypassed, deploy, and publish evidence without Codex authoring the fix.

Freeze: partial; evidence is recorded in `runtime_remote_training/read_only_audit_artifacts/AGENTMIM_CLIENTS_VISIBLE_RECORDS_FAST_PATH_V1.latest.json`.

Retirement: open.

### APP-TOD-026: AgentMIM Deterministic App-Data Answer Before LLM Fallback

Borrowed From: Codex emergency AgentMIM production repair.

Reason: AgentMIM sidebar chat timed out on a deterministic client-data question from a live client page. The user asked what total carrier-paid commissions existed for a client across all data, but the assistant fell through the general MIM/LLM path instead of answering directly from page context plus stored commission rows.

Incident: `AGENTMIM-CLIENT-COMMISSION-TOTAL-SIDEBAR-TIMEOUT-20260718`

Capability: When a user asks a factual question that can be answered from current app data, page context, or already-loaded records, TOD must help MIM route the request through a deterministic data answer before LLM fallback. The pattern includes publishing reliable page context, identifying the data-backed intent, querying the authoritative records, returning a concise answer, and preserving the slower conversational path only for questions that truly need reasoning.

Current Apprentice: TOD

Progress: `borrowed`; Codex repaired `E:\comm_app` and pushed commit `24e59e6d Fix MIM client commission total timeout`. The repair added a `viewClient` page-context payload, a deterministic pre-LLM client commission-total fast path, and regression tests proving the fast path answers from the database without requiring generic assistant generation.

Proficiency: `observed`; TOD has not yet independently inspected, materialized, implemented, and validated this class.

Independent Demonstration: `pending`; TOD must inspect the pushed AgentMIM repair, identify one fresh analogous deterministic app-data assistant question on another live AgentMIM surface, publish a current-code bounded packet or precise blocker, execute or block through the approved TOD path, validate with tests that the deterministic path answers without generic timeout-prone chat, and publish evidence.

Freeze: open; the production symptom is repaired, but the engineering pattern is not TOD-owned until an independent demonstration succeeds.

Retirement: open.

### APP-TOD-012: AgentMIM Carrier Commission Parser Contract Repair

Borrowed From: Codex emergency repair.

Reason: AgentMIM June commission uploads were blocked for live business files. Dickerson staging returned a server error because parser header normalization assumed every Excel header was a string, and Humana SpreadsheetML files with a real `PaidAmount` column were being treated as policy-agent roster files instead of carrier-paid commission statements.

Incident: `AGENTMIM-JUNE-2026-HUMANA-DICKERSON-UPLOAD-BLOCKER-20260715`

Capability: Inspect real carrier commission workbook shapes, distinguish roster guards from commission-dollar evidence, repair bounded parser/mapping contracts, preserve legacy carrier behavior, validate focused regressions, and prove real-file staging with a dry-run report.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `E:\comm_app` parser normalization, Humana true-paid-amount recognition, and Dickerson mapping aliases, then validated focused tests and a real-file dry run against Dave's June upload folder.

Independent Demonstration: `pending`; TOD must handle a fresh analogous carrier upload failure by inspecting the real file headers and parser path, identifying the smallest parser or mapping contract repair, adding regression coverage, running focused tests, and proving the actual file stages without Codex patching.

Freeze: open; no learned capability exists yet for carrier commission parser contract repair.

Retirement: open.

### APP-TOD-023: Optional Selection Source Field StrictMode Recovery

Borrowed From: Codex emergency control-plane repair.

Reason: After TOD successfully published a ready packet-formation artifact, the next selector cycle crashed before promotion because `Resolve-TodNextTaskSelectionTask` read `selection_source_task_id` from a task creation spec that did not define that optional field. StrictMode converted a missing optional field into a hard control-plane failure.

Incident: `TOD-SELECTION-SOURCE-OPTIONAL-FIELD-20260716`

Capability: TOD selector and materializer code must treat optional metadata fields as optional under StrictMode, using guarded property reads and empty defaults so task-shape variance becomes evidence or blocker output instead of a crash.

Current Apprentice: TOD

Proficiency: `reliable`; TOD repeated optional-selection metadata tolerance across four fresh isolated selector cycles. This is runtime reliability only, not source-engineering credit.

Progress: `independent_demo_passed`; Codex originally patched `scripts/TOD.ps1` so created selection tasks add `selection_source_task_id` only through a guarded local value. On 2026-07-22, TOD recovery-shape validation added and passed a focused selector scenario where `create_task` deliberately omitted optional `selection_source_task_id`, then `Resolve-TodNextTaskSelectionTask` promoted the task, added an empty guarded `selection_source_task_id`, and avoided a StrictMode optional-field crash. The proof artifact is `runtime_remote_training/tod_result_artifacts/TOD_EXECUTABLE_RECOVERY_SHAPE_RETIREMENT_PROOF.latest.json`; focused validation was `Invoke-Pester tests/TOD.SelfDrivingTaskSelection.Tests.ps1` with 50 passed / 0 failed. Fresh reliability evidence: `TOD-APP-023-RELIABILITY-R134-C1-20260728`, `TOD-APP-023-RELIABILITY-R134-C2-20260728`, `TOD-APP-023-RELIABILITY-R134-C3-20260728`, and `TOD-APP-023-RELIABILITY-R136-C4-20260728`; episode `runtime_remote_training/engineering_corpus/TOD_APP_023_RELIABILITY_EPISODE_R136.latest.json`; Examiner `runtime_remote_training/engineering_corpus/TOD_APP_023_RELIABILITY_EXAMINER_R138.latest.json`.

Independent Demonstration: `passed across four fresh isolated selector cycles`; TOD preserved task promotion when optional selection-source metadata was absent.

Freeze: frozen for optional selector metadata tolerance; the named episode and Examiner preserve repeated validation. Prevention lesson: optional metadata must remain optional under StrictMode and may never crash authoritative task promotion.

Retirement: retired; Auditor R148 confirmed all retirement gates from current registry and named evidence. Runtime reliability only; no source-engineering credit.

### APP-TOD-011: Executor Binding Blocker Self-Recovery

Borrowed From: Codex emergency repair.

Reason: `/studio/tod` reported `Binding Required` because task identity was repaired but no local executor binding was visible. Codex traced the blocker to a stale `TOD_EXECUTOR_BINDING_REPAIR.latest.json` marker suppressing republish even though `MIM_TOD_TASK_REQUEST.latest.json` had been overwritten and no longer contained the local binding.

Incident: `TOD-EXECUTOR-BINDING-ALREADY-ATTEMPTED-STALE-MARKER-20260715`

Capability: Detect a missing-component blocker, compare old repair markers against the current authoritative request, republish the smallest valid local executor binding when current proof is absent, validate both serving lanes, and explain the blocker to the operator in plain context rather than route telemetry.

Current Apprentice: TOD

Proficiency: `reliable`; TOD repeated the runtime self-recovery behavior across four fresh isolated reliability cycles. This is runtime reliability only, not source-engineering credit.

Progress: `independent_demo_passed`; Codex repaired the stale-marker replay guard, validated focused tests, deployed to the MIM BOX, and proved `/tod/ui/state` reports `binding=ready` on both `18001` and `18021`. 2026-07-22 follow-up: TOD recovery-shape validation added and passed a focused replay where `TOD_EXECUTOR_BINDING_REPAIR.latest.json` claimed the same repair key was already attempted, but the current `MIM_TOD_TASK_REQUEST.latest.json` lacked the binding. `_attempt_executor_binding_materialization` ignored the stale marker, republished the current request with `selected_executor=local`, `active_engine=local`, and `executor_binding=scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine`, and recorded `stale_executor_binding_attempt_ignored`. Fresh reliability evidence: `TOD-APP-011-RELIABILITY-R123-C1-20260728`, `TOD-APP-011-RELIABILITY-R123-C2-20260728`, `TOD-APP-011-RELIABILITY-R123-C3-20260728`, and `TOD-APP-011-RELIABILITY-R137-C4-20260728`; episode `runtime_remote_training/engineering_corpus/TOD_APP_011_RELIABILITY_EPISODE_R123.latest.json`; Examiner `runtime_remote_training/engineering_corpus/TOD_APP_011_RELIABILITY_EXAMINER_R138.latest.json`.

Independent Demonstration: `passed across four fresh isolated reliability cycles`; TOD reproduced stale-marker self-recovery without a Codex-authored patch.

Freeze: frozen for runtime self-recovery; `docs/training/learned-capabilities/TOD_EXECUTOR_BINDING_BLOCKER_SELF_RECOVERY_LEARNED_CAPABILITY.md` and the named episode/Examiner evidence preserve the capability. Prevention lesson: stale repair markers never outrank the current authoritative request.

Retirement: retired; Auditor R148 confirmed all retirement gates from current registry and named evidence. Runtime reliability only; no source-engineering credit.

### APP-TOD-001: Cross-Surface Conversation Purpose Routing

Borrowed From: Codex emergency repair.

Reason: The real operator surface returned an operational action contract while the direct Studio API recognized the reflective prompt. MIM/TOD could not complete the routing diagnosis independently.

Incident: `MIM-CONVERSATION-SURFACE-TRACE-V1`

Capability: Trace a user-visible conversation failure across UI surface, endpoint, gateway, conversation purpose engine, formatter, and final response; distinguish internal API success from real operator-surface success.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD produced `runtime/shared/TOD_EMERGENCY_REPAIR_APPRENTICESHIP_SELF_REPORT.latest.json` from scaffolded evidence and repaired supporting drill blockers.

Independent Demonstration: `pending`; TOD must diagnose a fresh cross-surface routing split without Codex-provided field scaffolding.

Freeze: partial; `docs/training/learned-capabilities/CROSS_SURFACE_CONVERSATION_PURPOSE_ROUTING_LEARNED_CAPABILITY.md` exists, but independent pass rate is not proven.

Retirement: open.

### APP-TOD-002: Evidence-Derived Numeric Research Answer

Borrowed From: Codex emergency repair.

Reason: MIM had SolAir BOM evidence but answered a specific build-cost question with a generic manufacturing-discovery fallback. Codex repaired the evidence path before MIM/TOD independently demonstrated the capability.

Incident: `MIM-NUMERIC-ANSWER-FROM-EVIDENCE-BACKFILL-001`

Capability: Convert a specific numeric research question into source selection, field extraction, deterministic calculation, uncertainty boundary, source citation, fallback rejection, and live-route validation.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD produced `runtime/shared/TOD_NUMERIC_ANSWER_BACKFILL_SELF_REPORT.latest.json` from scaffolded evidence.

Independent Demonstration: `pending`; TOD must handle a fresh numeric research prompt or unfamiliar artifact schema without Codex-provided field labels.

Freeze: partial; `docs/training/learned-capabilities/MIM_RESEARCH_NUMERIC_ANSWER_FROM_EVIDENCE_LEARNED_CAPABILITY.md` exists, but independent pass rate is not proven.

Retirement: open.

### APP-TOD-003: Homepage Rollback and Conversation-Intent Safety

Borrowed From: Codex emergency repair.

Reason: MIM misclassified a curriculum prompt as homepage implementation, the public homepage regressed to an older business-software/create surface, and MIM could not preserve rollback context when asked to undo the unintended change. The gateway also computed a conversation-purpose reply without publishing it, allowing homepage fast paths to preempt curriculum recognition.

Incident: `MIM-HOMEPAGE-CURRICULUM-MISROUTE-20260711`

Capability: Trace and repair a public-site regression caused by conversation-context failure; restore the intended route/artifact safely; verify the live page; repair cross-surface conversation-purpose route ordering; then convert the repair into MIM/TOD training on active context, curriculum recognition, exploratory reasoning, intent verification before code changes, and action reversibility.

Current Apprentice: TOD

Progress: `lower_rung_packet_body_synthesis_passed`; Codex identified the fallback-route failure, repaired the homepage route/artifact, repaired the authenticated gateway purpose branch, added the public-chat purpose gate, deployed to the MIM box, restarted `mim-mobile-web.service`, and validated the live homepage, public chat exploration, authenticated gateway exploration, and authenticated gateway curriculum probes. TOD then passed lower rungs for one-file read-only audit publication, exact source-anchor observation, and bounded packet-body synthesis from that anchor. TOD has not independently demonstrated the full repair pattern because Codex still selected the case and bounded fields.

Independent Demonstration: `pending`; TOD must diagnose a fresh UI or conversation-surface regression from live route evidence, select the case and fields itself, identify whether the source is route fallback, artifact lookup, stale service, redirect context, or purpose-engine preemption, and publish a bounded repair/validation packet without Codex field scaffolding.

Freeze: open; no learned capability exists yet for homepage rollback and conversation-intent safety.

Retirement: open.

### APP-TOD-004: Self-Evolution Schema Drift Recovery

Borrowed From: Codex emergency repair.

Reason: During MIM cognitive-loop training, the self-evolution `briefing` and `next-action` routes returned 500 errors because live ORM code expected `assumptions_json` columns that were missing from existing workspace-improvement tables. MIM/TOD could not report or select the active training continuation until the route recovered.

Incident: `self_evolution_reporting_route_500_during_cognitive_loop_training`

Capability: Diagnose a live route 500 from logs, identify additive schema drift between ORM expectations and database tables, apply the smallest non-destructive compatibility migration, validate the affected routes, and record the borrowed capability without treating emergency repair as learned competence.

Current Apprentice: TOD

Progress: `scaffolded_pass`; Codex applied additive `assumptions_json` columns to the affected tables and validated that self-evolution `progress`, `briefing`, and `next-action` routes returned 200. On 2026-07-22, TOD processed `runtime_remote_training/read_only_audit_artifacts/APP_TOD_004_SCHEMA_DRIFT_INPUT.latest.json` through `execute-chat-task -Type read_only_assessment`, published `runtime_remote_training/read_only_audit_artifacts/APP_TOD_004_SCHEMA_DRIFT_SCAFFOLD_PROOF.latest.json`, preserved `no_code_changes=true`, and correctly identified `fresh_schema_drift_case_missing` instead of claiming an independent repair.

Independent Demonstration: `pending`; TOD must diagnose a fresh route/schema drift failure from logs and table inspection, propose the additive repair, validate routes, and publish rollback/verification evidence without Codex field scaffolding.

Freeze: partial; TOD has a scaffolded read-only recognition artifact for the schema-drift failure class, but no fresh live/schema-drift recovery has been independently completed.

Retirement: open.

### APP-TOD-005: Dialog Response Contract Projection And Focus-Review Derivation

Borrowed From: Codex emergency repair.

Reason: During the 1,000-conversation cognitive-development loop, MIM could acknowledge focus-review handoffs but could not reliably publish the required decision-quality response fields or derive a training focus from calibration/progress artifacts. The responder path was preserving generic ACK behavior instead of producing an evidence-derived development review.

Incident: `MIM-COGNITIVE-DEVELOPMENT-LOOP-FOCUS-REVIEW-CONTRACT-20260711`

Capability: Trace dialog response-contract failures through request parsing, response projection, artifact projection, source-artifact lookup, and derived focus selection; repair the smallest responder path so MIM can publish a complete focus-review artifact from evidence without Codex prefilled output payloads.

Current Apprentice: TOD

Progress: `borrowed`; Codex repaired the MIM dialog responder, added focused tests, validated local syntax and behavior, deployed the responder to the MIM box, restarted the dialog inbox consumer, and proved an unscaffolded handoff produced `MIM_COGNITIVE_DEVELOPMENT_LOOP_DEVELOPMENT_REVIEW.latest.json` with the required focus-review fields.

Independent Demonstration: `pending`; TOD must diagnose a fresh dialog response-contract projection failure, identify the missing projection or source-artifact derivation path, propose a bounded repair and validation plan, and prove the responder publishes required fields without Codex-authored field scaffolding.

Freeze: open; no learned capability exists yet for dialog response-contract projection and evidence-derived focus selection.

Retirement: open.

### APP-TOD-006: Studio Active Context Transition Routing

Borrowed From: Codex emergency repair.

Reason: During the MIM cognitive-development loop, live Studio chat prompts that were follow-ups, corrections, repair asks, and status checks were intercepted by simple-direct or conversation-purpose routes before MIM inspected recent thread evidence. MIM could not preserve the active thread reliably enough to run the 1,000-conversation training loop.

Incident: `MIM-ACTIVE-CONTEXT-TRANSITION-BEFORE-EXPLORATION-20260711`

Capability: Trace live Studio route ordering, identify when active-thread evidence must be read before response-purpose classification, add the smallest route gate, and validate with live correction/status/follow-up probes against the real operator surface.

Current Apprentice: TOD

Progress: `borrowed`; Codex added the active-context transition gate, validated focused local tests, deployed to the MIM box, and proved the live fair active-context probe passed 9/9.

Independent Demonstration: `pending`; TOD must diagnose a fresh route-ordering failure where a follow-up/correction is swallowed by an earlier route, identify the route gate from source evidence, propose a bounded repair, and validate against the real operator surface without Codex-authored field scaffolding.

Freeze: open; no learned capability exists yet for Studio active-context transition routing.

Retirement: open.

### APP-TOD-007: Self-Evolution Status Reporting Before Generic Exploration

Borrowed From: Codex emergency repair.

Reason: After active-context routing improved, MIM still misrouted “current self-evolution learning focus” and planning-continuity follow-ups through generic exploration. The training ledger had the evidence, but Studio chat did not consult it before the conversation-purpose engine.

Incident: `MIM-SELF-EVOLUTION-STATUS-FOCUS-ROUTE-20260711`

Capability: Recognize self-evolution status/focus prompts, hydrate active natural-language training progress from the self-evolution ledger, report current slice/proof/pass gate/not-claim boundaries, and preserve planning-continuity follow-ups through live Studio chat.

Current Apprentice: TOD

Progress: `borrowed`; Codex added the self-evolution status/focus route gate, validated focused local tests, deployed to the MIM box, and proved live Planning Continuity, Decision Flow, Escalation Recovery, Accountability Reporting, and Reflection/Memory probes. Follow-on emergency route repairs added failed-probe repair-status, after-pass continuation, why-continuation, recovery-status, and no-metadata operator training/status prompts to the self-evolution ledger path so they do not fall into Reports, generic exploration, problem-analysis, or direct-answer fallback.

Independent Demonstration: `pending`; TOD must diagnose a fresh training-ledger visibility failure, identify the missing status/progress route, validate the route with live operator-surface probes, and publish proof without Codex selecting all probe fields.

Freeze: open; no learned capability exists yet for self-evolution status reporting before generic exploration.

Retirement: open.

### APP-TOD-008: Optional Shared Helper Route Tolerance

Borrowed From: Codex emergency repair.

Reason: During the second MIM cognitive-development cycle, the live Studio chat route returned HTTP 500 while MIM was asked to report its failed-slice repair focus. Logs showed `studio.py` called `gateway_router._mim_tod_visitor_stats_diagnostic_reply`, but the loaded gateway module did not expose that optional helper. This blocked self-evolution reporting and therefore blocked the training loop.

Incident: `MIM-STUDIO-OPTIONAL-GATEWAY-HELPER-500-20260711`

Capability: Diagnose a live route 500 from service logs, distinguish required dependencies from optional shared helpers, apply the smallest compatibility guard, validate the live route, and preserve the incident as apprenticeship debt rather than learned TOD competence.

Current Apprentice: TOD

Progress: `borrowed`; Codex guarded the optional visitor-stats helper lookup so a missing gateway helper returns no visitor diagnostic instead of crashing Studio chat.

Independent Demonstration: `pending`; TOD must diagnose a fresh missing-helper route 500, identify whether the dependency is optional or required, propose a bounded compatibility repair, validate route recovery, and publish rollback/verification evidence without Codex-authored code.

Freeze: open; no learned capability exists yet for optional shared helper route tolerance.

Retirement: open.

### APP-TOD-009: Cross-Service Live Surface Verification And Serving-Lane Restart

Borrowed From: Codex emergency repair.

Reason: MIM's no-metadata operator status prompt repair passed local tests and the `mim-mobile-web.service` lane on port `18001`, but Dave's real `/studio/mim` browser surface still returned generic exploratory text. The live operator surface was using the separate `mim-training-web.service` lane on port `18021`, which had not been restarted since before the repair.

Incident: `MIM-STUDIO-OPERATOR-STATUS-SERVING-LANE-DRIFT-20260712`

Capability: Trace a user-visible behavior mismatch across source file, local unit test, internal backend port, alternate serving port, service process age, and authenticated/public browser route; identify stale serving lanes; restart the exact affected service; validate the same prompt on every serving lane before claiming production repair.

Current Apprentice: TOD

Progress: `borrowed`; Codex inspected the remote `studio.py` markers, proved port `18001` returned `studio_self_evolution_status`, proved port `18021` still returned stale non-ledger behavior, identified `mim-training-web.service` as the stale serving lane, restarted it, and validated both `18001` and `18021` now return `self_evolution_operator_status` without `exploration question` leakage. Follow-on repair added the broader self-directed learning invitation class after Dave's prompt `hi MIM what would you like to work on or learn today?` still fell into generic exploration; Codex validated that exact prompt and the prior `what are you working on MIM?` prompt on both serving lanes. 2026-07-13 update: Dave's live prompt `Hi MIM what are you working on` exposed another greeting-order variant. Codex added focused status-intent coverage, deployed `core/routers/studio.py`, restarted both `mim-mobile-web.service` and `mim-training-web.service`, and validated ports `18001` and `18021` return `source=studio_self_evolution_status`, `response_mode=self_evolution_operator_status`, and `leak=False`.

Independent Demonstration: `pending`; TOD must diagnose a fresh case where local tests and one backend port pass but the operator-visible route still fails, map the live route to the correct service/port/process, restart or repair only the affected lane, and publish proof from the same surface class Dave used.

Freeze: open; no learned capability exists yet for cross-service live surface verification and serving-lane restart.

Retirement: open.

### APP-TOD-010: Hardcoded MIM Answer Detection And Replacement

Borrowed From: Codex escalation after TOD attempt.

Reason: Dave asked to verify that MIM was not hardcoding answers. Audit found the exact live self-evolution prompt was not hardcoded in production core, but `_build_exploratory_reasoning_reply` contained canned exploratory answer bodies that returned repeated generic reasoning for different prompts.

Incident: `MIM-HARDCODED-ANSWER-AUDIT-AND-REPLACEMENT-20260713`

Capability: Detect hardcoded answer bodies, distinguish acceptable routing scaffolds from unacceptable canned reasoning, replace fixed answer bodies with prompt-grounded response composition, and validate with no-hardcode source scans plus varied-prompt behavioral tests.

Current Apprentice: TOD

Progress: `borrowed`; TOD attempted the bounded repair through `execute-chat-task`, but the local execution lane materialized the request as validation-only and published `blocked_missing_local_executor_result` with no changed files. Codex then performed a narrow escalation repair, deployed the corrected purpose engine to the MIM box, restarted `mim-mobile-web.service` and `mim-training-web.service`, validated `/studio/api/mim/chat` on ports `18001` and `18021`, and created `docs/training/MIM_HARDCODED_ANSWER_AUDIT_AND_REPLACEMENT_V1.md`.

Independent Demonstration: `pending`; TOD must find a fresh canned-answer body or repeated-response regression, classify the difference between routing scaffolding and hardcoded answer logic, produce a bounded patch without Codex-authored text, validate varied prompt outputs, and publish a prevention lesson.

Freeze: open; focused local tests passed, but TOD has not independently demonstrated the capability.

Retirement: open.

### APP-TOD-035: Response Contract Envelope Scope Repair

Borrowed From: Codex emergency repair.

Reason: MIM acknowledged a TOD blocker with a response containing top-level `summary` and `finding_positions`, but then marked those same fields as missing inside the individual finding. This prevented MIM from closing the acknowledgement contract for TOD's artifact-body synthesis blocker.

Incident: `MIM-RESPONSE-CONTRACT-ENVELOPE-SCOPE-20260713`

Capability: Distinguish response-envelope fields from per-finding response fields, validate the contract scope on the real MIM/TOD dialog lane, restart only affected MIM services, and prove the same request no longer becomes `request_missing_data`.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/next_step_dialog_service.py`, added a focused regression test in `tmp_remote_mim/tests/test_next_step_dialog_service.py`, deployed the service file to the MIM box, validated the regression remotely, restarted `mim-watch-tod-dialog-inbox-consumer.service` and `mim-mobile-web.service`, and proved a fresh live dialog response resolved with owner `tod` and no missing `summary` or `finding_positions`.

Independent Demonstration: `pending`; TOD must diagnose a fresh response-contract scope failure, identify whether each required field belongs to the envelope or finding level, propose a bounded repair, validate it with a live MIM/TOD dialog probe, and publish evidence without Codex-authored code.

Freeze: open; no learned capability exists yet for response-envelope/per-finding contract scope.

Retirement: open.

### APP-TOD-036: Read-Only Audit Extraction For Artifact-Write Blockers

Borrowed From: Codex escalation after TOD attempt.

Reason: TOD successfully used the read-only audit artifact lane, but the generated artifact was generic and did not extract the specific blocker fields from `local_execution_artifact_write_blocker` evidence such as `status=blocked_missing_artifact_content` and `missing_anchor_or_field=new_text`.

Incident: `TOD-READONLY-AUDIT-ARTIFACT-WRITE-BLOCKER-EXTRACTION-20260713`

Capability: Inspect a generated blocker artifact, recognize its schema, extract the fields that explain why execution is blocked, classify the blocker sharply, and rerun the same training rung to prove the artifact changed from generic review to specific blocker diagnosis.

Current Apprentice: TOD

Progress: `retired`; TOD ran `TOD-READONLY-AUDIT-BODY-SYNTHESIS-001` and produced a generic read-only audit artifact. Codex then patched `scripts/engines/LocalExecutionEngine.ps1` so the read-only audit lane understands `local_execution_artifact_write_blocker` evidence. TOD reran the same task and produced `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT_BODY_SYNTHESIS_001.latest.json` with classification `artifact_body_synthesis_missing` and blockers `artifact_body_synthesis_missing` plus `new_text_artifact_body_missing`. 2026-07-22 independent repeat: TOD first attempted `TOD-ARTIFACT-WRITE-BLOCKER-FRESH-READONLY-R6` against a fresh generated blocker, which exposed a selector-precedence misroute into the specialized source-evidence lane. TOD then backed up one rung and passed `TOD-ARTIFACT-WRITE-BLOCKER-FRESH-READONLY-R7` against `runtime/shared/TOD_INDEPENDENT_UNSEEN_APPRENTICESHIP_DEMONSTRATION_001.latest.json`, publishing `runtime_remote_training/read_only_audit_artifacts/TOD_ARTIFACT_WRITE_BLOCKER_FRESH_READONLY_R7.latest.json` with `classification=artifact_body_synthesis_missing`, `missing_anchor_or_field=new_text`, `new_text_artifact_body_missing`, `required_continuation`, and `no_code_changes=true`.

Proficiency: `independent`; TOD can apply the read-only audit extraction pattern to a generated artifact-write blocker, preserve the missing-body evidence, reject blocker-only completion credit, and publish a validated no-code-change artifact. Selector precedence remains a caution because source-evidence-named inputs can still be stolen by a specialized lane.

Independent Demonstration: `passed`; `TOD-ARTIFACT-WRITE-BLOCKER-FRESH-READONLY-R7` applied the blocker extraction pattern to a fresh generated blocker artifact, wrote a meaningful read-only audit artifact, validated JSON, and preserved the continuation action without source mutation.

Freeze: updated; retirement proof is recorded in `runtime_remote_training/read_only_audit_artifacts/TOD_ARTIFACT_WRITE_BLOCKER_EXTRACTION_RETIREMENT_PROOF.latest.json`, including the R6 selector-precedence caution and the R7 independent pass against fresh generated artifact-write blocker evidence.

Retirement: retired; APP-TOD-036 is no longer counted as borrowed because TOD passed `TOD-ARTIFACT-WRITE-BLOCKER-FRESH-READONLY-R7`, preserved the missing body field evidence, validated JSON/no-code-change proof, and recorded a prevention lesson. Selector precedence remains separate training debt, not a blocker for this retired capability.

### APP-TOD-013: Semantic Source-Audit Body Synthesis From Source Anchors

Borrowed From: Codex escalation after TOD attempt.

Reason: TOD produced source-anchor evidence and a generic read-only audit, but the original semantic root-cause audit artifact still lacked the required body fields: `observed_blocker`, `suspected_root_cause`, `evidence_checked`, `evidence_missing`, `why_forward_motion_is_blocked`, `smallest_diagnostic_step`, `confidence`, and `no_phrase_patch_rule`.

Incident: `TOD-SEMANTIC-AUDIT-BODY-FROM-SOURCE-ANCHORS-001`

Capability: Convert bounded source-anchor artifacts into a field-complete semantic audit body, validate required field readback, preserve no-code/no-phrase-patch boundaries, and route final proof to MIM for decision-quality acknowledgement.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD first proved the failure with `TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT_BODY_SYNTHESIS_001.latest.json`, then captured source anchors for `_derive_capability_model_status`, `_collect_contract_output_fields`, and `_contract_candidate_sources`. Codex added the bounded `Invoke-LocalExecutionSemanticSourceAudit` lane after the TOD attempt, and TOD reran the original task to produce `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT.latest.json` with all required fields, `no_phrase_patch_rule=true`, and `no_code_changes=true`.

Independent Demonstration: `pending`; TOD must synthesize a fresh semantic audit body from different source-anchor artifacts without Codex preselecting the source fields or writing the body template.

Freeze: partial; `docs/training/learned-capabilities/TOD_SEMANTIC_SOURCE_AUDIT_BODY_SYNTHESIS_LEARNED_CAPABILITY.md` records the learned capability, but the independent pass is not yet proven.

Retirement: open.

### APP-TOD-015: Source-Evidence Artifact Body Synthesis and Closure

Borrowed From: Codex escalation after TOD attempted `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002C` and produced a precise `blocked_missing_artifact_content` artifact.

Reason: TOD could bind a single bounded output target, but could not synthesize the requested artifact body from source evidence without a supplied `New Text` directive. After TOD produced the blocker, Codex added a bounded source-evidence demonstration lane and repaired the closure gate so validated artifact writes count as authoritative evidence when the artifact is the target.

Incident: `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002C` through `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002E`

Capability: Read a source evidence artifact, discover relevant fields, preserve the authority boundary between conflicting evidence lanes, write a required-field proof artifact, and close the execution contract from validated artifact-write evidence.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD first exposed the missing body with `runtime/shared/TOD_INDEPENDENT_UNSEEN_APPRENTICESHIP_DEMONSTRATION_002.latest.json` as `blocked_missing_artifact_content`. Codex added `Invoke-LocalExecutionResearchEvidenceDemonstration`, selector coverage for hyphen/underscore concept forms, and a closure-gate repair in `Get-TodMaterialImplementationProofAssessment`. TOD reran `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002E` and published a valid SolAir power-output proof artifact from `runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION.latest.json`. A follow-up BOM attempt, `TOD-INDEPENDENT-SOURCE-EVIDENCE-ARTIFACT-BODY-DEMONSTRATION-003B`, correctly remained blocked instead of false-completing when TOD produced a `local_execution_artifact_write_blocker`.

Independent Demonstration: `blocked`; TOD tried the different source artifact `runtime/shared/SOLAIR_PARTS_BOM_OBSERVATION.latest.json`, but still could not synthesize the BOM proof body without a dedicated source-evidence synthesis path. The next rung is generalized structured-source evidence synthesis from arrays/rows, not another SolAir-power-specific lane.

Freeze: partial; `docs/training/learned-capabilities/TOD_SOURCE_EVIDENCE_ARTIFACT_BODY_SYNTHESIS_AND_CLOSURE_LEARNED_CAPABILITY.md` records the learned capability and remaining independent-demonstration boundary.

Retirement: open.

### APP-TOD-014: MIM Dialog ACK Contract Field Projection

Borrowed From: Codex emergency repair and active response-contract coaching.

Reason: MIM can close the transport-level reply expectation and can publish an `approve` decision inside `finding_positions`, but the latest final-proof response omitted requested acknowledgement fields such as `received`, `owner`, `expected_evidence`, `blocker_state`, and `continuation_action`.

Incident: `MIM-ACK-CONTRACT-FIELD-PROJECTION-20260713`

Capability: Preserve arbitrary required acknowledgement fields from a TOD handoff request through MIM response generation, distinguish transport receipt from decision-quality ACK, and publish same-session owner/evidence/blocker/continuation fields without generic receipt fallback.

Current Apprentice: MIM with TOD as validator

Progress: `scaffolded_pass`; TOD delivered the final semantic audit proof in session `tod-mim-semantic-audit-body-final-proof-001`, observed the incomplete MIM response, and sent a corrected same-session `status_request` naming the missing fields and required repair path. Codex applied a bounded protocol-compatibility repair to `core/next_step_dialog_service.py`, deployed it to the MIM box, restarted `mim-watch-tod-dialog-inbox-consumer.service`, and TOD proved a fresh live dialog response in session `tod-mim-ack-contract-projection-proof-001` now projects `received`, `decision`, `owner`, `expected_evidence`, `blocker_state`, `continuation_action`, `blocker_class`, and `smallest_repair_step` at both envelope and payload scope. TOD then found and validated a narrower follow-on blocker where `resolution_notice` messages with `requires_reply=true` were not consumed; the generic requires-reply fallback repair closed session `tod-mim-ack-contract-projection-resolution-001` with no missing ACK fields.

Independent Demonstration: `pending`; MIM/TOD must pass a fresh analogous request where TOD derives the required ACK fields from the protocol/task context without Codex preselecting the exact field list.

Freeze: partial; see `docs/training/learned-capabilities/MIM_ACK_CONTRACT_FIELD_PROJECTION_LEARNED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-016: Existing-Bridge Remediation Materialization

Borrowed From: Codex emergency repair after active bridge audit.

Reason: MIM and TOD were already communicating through the established shared bridge, but MIM was publishing `acknowledge_and_remediate_system_alerts` as `task_class=diagnostic_only` with `validation_only=true` and `changed_files_required_for_success=false`. TOD correctly refused to treat that as executable implementation work, which left the system talking without producing a bounded repair.

Incident: `MIM-STALE-REMEDIATION-MATERIALIZATION-20260714`

Capability: Distinguish a live transport/channel problem from a request-shape problem, preserve the existing MIM/TOD bridge, and materialize code-remediation decisions as implementation-shaped `MIM_TOD_TASK_REQUEST.latest.json` packets with target file, minimal patch plan, validation plan, changed-files gate, and no new SSH/transport path.

Current Apprentice: MIM with TOD as validator

Progress: `borrowed`; Codex inspected the existing bridge artifacts and found the current authoritative request was diagnostic-only despite the remediation action. Codex tightened the TOD coordination publisher so follow-up requests demand a bounded implementation packet over the existing channel, added listener regression coverage, patched the MIM workbench `autonomy_driver_service.py` so stale-prevention pass 4 publishes a bounded implementation request when code modification is recommended, added `test_autonomy_stale_remediation_dispatch.py`, and recorded deploy payload `MIM_STALE_REMEDIATION_MATERIALIZATION_DEPLOY_PATCH_20260714T0330Z`. 2026-07-14 update: Codex inspected the live `recover_trigger_ack_bridge` wrapper and proved the existing SSH/SFTP channel was alive while the wrapper had dropped `target_file`, implementation class, and patch/validation fields. Codex added a TOD listener guard that rejects stale bridge-recovery diagnostic wrappers with `diagnostic_wrapper_missing_bounded_implementation_packet` instead of executing them, refreshed the decision artifact to `republish_existing_channel_bounded_implementation_request`, and validated `tests/TOD.PacketListenerOrdering.Tests.ps1` at 22/22 passing. 2026-07-14 follow-up: MIM then emitted a valid bounded implementation packet for `core/handoff_intake_service.py`, but replaced it with an `acknowledge_and_remediate_system_alerts` diagnostic wrapper. The running listener, still on the old policy, marked that wrapper `succeeded` while `runtime/shared/TOD_EXECUTION_RESULT.latest.json` remained `blocked_missing_bounded_edit_mode`. Codex added the second listener guard so system-alert diagnostic wrappers without `target_file` are rejected as `diagnostic_wrapper_missing_bounded_implementation_packet`, and validated `tests/TOD.PacketListenerOrdering.Tests.ps1` at 23/23 passing. Codex also repaired the local Studio mode-selection mirror so operator-impact failure prompts route through the existing conversation-mode guard before generic exploratory reasoning; focused Studio tests passed. 2026-07-14 task-class-loss correction: Codex then inspected the exact live packet and found `task_class` had been dropped, so the guard was broadened to reject diagnostic-wrapper identity plus `execute-chat-task` plus empty `target_file` even when `task_class` is blank. `tests/TOD.PacketListenerOrdering.Tests.ps1` now passes at 24/24, including the field-loss regression. 2026-07-14 local command-path correction: Codex traced the no-target wrapper into `Invoke-ExecuteChatTaskRequest` and added a second guard so diagnostic implementation/system-alert/bridge-recovery requests cannot supersede or dispatch without exactly one bounded `target_file`; `tests/TOD.IntakeArbitration.Tests.ps1` proves bounded admin repair still supersedes active MIM work while no-target diagnostic repair returns `diagnostic_repair_missing_bounded_target` and preserves the active lane. 2026-07-14 blocked-result closure correction: MIM replied to the materialization correction with a generic catchup/system-alert status and replaced the bounded `core/handoff_intake_service.py` request with a no-target `blocked-result-closure-diagnostic` packet. Codex added listener and local command-path guards for `resolve_blocked_task_result` / `blocked-result-closure-diagnostic`; `tests/TOD.PacketListenerOrdering.Tests.ps1` passes at 25/25 and `tests/TOD.IntakeArbitration.Tests.ps1` proves the closure diagnostic is blocked without displacing the active lane. The active live listener still needs to reload through the existing startup path before listener-side repair can be proven live. This is still borrowed capability, not TOD credit.

2026-07-14 source-producer diagnosis: Codex followed Dave's correction not to add another SSH channel and traced the latest no-target `blocked-result-closure-diagnostic` packet to the direct-chat task producer shape, not transport. The live packet had `source=direct_chat`, `assigned_executor=codex`, empty `target_file`, and `blocked_missing_bounded_edit_mode`. The source-side guard belongs in `tmp_remote_mim/core/routers/tod_ui.py::_publish_task_execution_request`: no-target closure diagnostics must return `diagnostic_repair_missing_bounded_target` and preserve the existing bounded request instead of writing `MIM_TOD_TASK_REQUEST.latest.json`. Current sandbox identity cannot write that mirror file (`icacls` grants BUILTIN\Users read/execute only), so Codex materialized the source-side repair as deploy packet `runtime_remote_training/deploy_payloads/MIM_DIRECT_CHAT_CLOSURE_DIAGNOSTIC_GUARD_DEPLOY_PATCH_20260714T0545Z.json` / `.md`; evidence is in `runtime_remote_training/codex_training_interventions/CODEX_MIM_TOD_EXISTING_CHANNEL_SOURCE_PRODUCER_DIAGNOSIS_20260714T0535Z.latest.json`.

Independent Demonstration: `pending`; MIM must produce a fresh live implementation-shaped request on `/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json` for a stale/remediation case without Codex writing the packet. TOD must then inspect the target file, make or precisely block the bounded change, validate, publish evidence, and avoid proposing another channel.

Freeze: open; local workbench tests pass, but live deployment and independent MIM/TOD demonstration are not proven.

Retirement: open.

### APP-TOD-017: Blocker Policy Communication From Current Evidence

Borrowed From: Codex emergency repair after TOD operator-chat regression.

Reason: TOD answered `are you blocked TOD, do you need to escalate?` and `should you back up to a smaller task? what is your policy for blockers?` with the same stale blocked/stalled execution paragraph. The operator needed blocker-handling policy and a smaller-step decision, not another copy of the active-lane diagnostic.

Incident: `TOD-BLOCKER-POLICY-COMMUNICATION-20260715`

Capability: Detect blocker-policy intent, read current evidence, distinguish current blocker from blocker policy, back up to the smallest proof step when stalled, suppress stale binding language when the binding is already ready, and explain escalation criteria in human terms without route telemetry or canned phrase patches.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched the TOD Studio chat composer in `tmp_remote_mim/core/routers/tod_ui.py`, added focused regression coverage in `tmp_remote_mim/tests/integration/test_tod_ui_console.py`, deployed the exact files to the MIM Box, and live-smoked ports 18001 and 18021. The reply now says TOD should back up to a smaller task, names the blocker policy, names the smallest next task, gives an escalation rule, and avoids stale `local execution binding missing` wording when current binding evidence is ready.

Independent Demonstration: `pending`; TOD must answer a fresh blocker-policy question for a different blocker by inspecting current state, choosing status vs policy vs diagnostics, and publishing the smallest-step recovery recommendation without Codex changing the composer.

Freeze: partial; see `docs/training/learned-capabilities/TOD_BLOCKER_POLICY_COMMUNICATION_LEARNED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-018: Unique-Anchor Bounded Edit Materialization

Borrowed From: Codex escalation after TOD attempt.

Reason: TOD audited `tmp_remote_mim/core/routers/studio.py` for hardcoded Studio MIM responses and attempted to materialize a bounded edit for objective-progress prompts, but the `replace_text` packet used a non-unique old-text anchor: `return _studio_operator_contract_fallback_reply(prompt, page_context)`. The local engine reported completion, yet the replacement landed at the first matching fallback inside the Studio chat route, placed the new branch after an already-returned mode guard, and introduced an early fallback that made later route logic unreachable.

Incident: `STUDIO-PY-HARDCODED-RESPONSE-AUDIT-BOUNDED-EDIT-ANCHOR-COLLISION-20260715`

Capability: Before publishing a bounded edit packet, TOD must inspect the target file, prove the old text or anchor is unique in the intended scope, include surrounding context when repeated text exists, validate that the changed hunk landed at the intended location, and reject wrapper success when syntax passes but behavior is unreachable or inserted under the wrong branch.

Current Apprentice: TOD

Progress: `scaffolded_positive`; TOD produced the original source-anchor audit artifacts and attempted the bounded edit through the local execution lane. Codex then inspected the diff, found the anchor collision, removed the misplaced branch, reinserted the objective-progress branch immediately before the true final fallback, and validated `python -m py_compile tmp_remote_mim/core/routers/studio.py`. 2026-07-15 follow-up: on fresh fixture `tod/out/tests/app-tod-018-unique-anchor-fresh/target_config.py`, TOD completed the scaffolded sequence `TSK-APP-TOD-018-OBSERVE2` -> `TSK-APP-TOD-018-SYNTHESIZE` -> `TSK-APP-TOD-018-APPLY`: it published a beta-only source-anchor artifact, synthesized a ready exact old_text/new_text packet, applied the packet through LocalExecutionEngine, and validated `python -m py_compile` plus structural checks proving `tod_unique_anchor` exists only in beta. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/APP_TOD_018_UNIQUE_ANCHOR_FRESH_POSITIVE_RESULT.latest.json`. 2026-07-15 real-lane follow-up: TOD proved the default `execute-chat-task` smoke artifact at `runtime_remote_training/learned_capabilities/TOD_EXECUTE_CHAT_TASK_ASYNC_DEFAULT_RESMOKE_20260715.live_smoke.json`, then correctly backed down from overbroad `TSK-0029` to current-code source-anchor tasks `TSK-0027` and `TSK-0028`; both passed and wrote fresh anchor artifacts. Retried `TSK-0029` still blocked because no packet artifact was synthesized. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/APP_TOD_018_REAL_PACKET_SYNTHESIS_BLOCKER.latest.json`.

2026-07-23 corpus-foundation rung: TOD created `OBJ-0171` and produced a usable corpus evidence-intake classifier and two-candidate episode manifest from recent real attempts. It also captured the manifest-writer source anchor in `runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_WRITER_OBJECT_BLOCK_SOURCE_ANCHOR_V1.r1.latest.json`. When asked to turn that source anchor into a safe field-contract delta, TOD failed with `read_only_audit_required_artifact_type_unsupported` because the local read-only selector routed the task into corpus source-anchor enrichment instead of `tod_source_anchor_delta_proposal`. Codex then applied a narrow selector-precedence repair in `scripts/engines/LocalExecutionEngine.ps1` and added a focused regression case in `tests/TOD.LocalFallbackExecutor.Tests.ps1`. After the repair, TOD reran `tod-corpus-manifest-delta-r1` and published `runtime_remote_training/read_only_audit_artifacts/TOD_CORPUS_MANIFEST_FIELD_CONTRACT_DELTA_PROPOSAL_V1.r1.latest.json` with `artifact_type=tod_source_anchor_delta_proposal`, `source_anchor_valid=true`, `target_file=scripts/engines/LocalExecutionEngine.ps1`, `no_source_code_modified=true`, and blocker `autonomous_candidate_new_text_missing`. TOD then created `OBJ-0174` and attempted `tod-autonomous-meaningful-newtext-from-source-anchor-r3`; that failed because the prompt shape caused the local fallback to treat input, prior, and output artifacts as competing target files. TOD backed down to the supported `inspection_only` read-only lane in `tod-autonomous-meaningful-newtext-from-source-anchor-r4`, which completed locally and published `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_SYNTHESIS_FROM_SOURCE_ANCHOR_V1.r4.latest.json`. The r4 artifact confirms source-anchor validity and no source edits, but still returns `candidate_new_text=""` with blocker `autonomous_candidate_new_text_missing`. This is a precise continuation blocker for autonomous meaningful `candidate_new_text` synthesis from source anchors, not independent bounded-edit mastery.

Independent Demonstration: `blocked`; TOD now has a positive sub-skill result on current-code source-anchor recovery, but the independent demonstration is blocked at packet-body synthesis. TOD must produce a single-output packet artifact from the fresh anchors with non-empty current `old_text`, different `new_text`, validation command, rollback, closure evidence, and prevention lesson before it can attempt the less-artificial edit without Codex selecting packet fields.

Freeze: partial; see `docs/training/learned-capabilities/TOD_UNIQUE_ANCHOR_BOUNDED_EDIT_MATERIALIZATION_LEARNED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-019: AgentMIM Production Repair Assimilation

Borrowed From: Codex emergency repair during fast AgentMIM production stabilization.

Reason: Dave needed production-facing AgentMIM fixes completed quickly across quotes, client identity merge, commission upload/audit, and MIM side-assistant repair paths. Codex performed the implementation work directly in `E:\comm_app` to keep the product moving. Under `CODEX.md`, this is borrowed capability, not TOD progress, until TOD can inspect the committed repairs, reconstruct the failure classes, and complete a fresh analogous repair without Codex authoring the patch.

Incident: `AGENTMIM-FAST-STABILIZATION-20260715`

Capability: Audit an AgentMIM user-visible failure from screenshots/chat symptoms, locate the real route/model/template/parser path, make the smallest behavior-changing repair, validate with focused tests and/or real-file smoke data, preserve unrelated dirty work, commit only intended hunks, and report evidence in human terms.

Current Apprentice: TOD

Progress: `borrowed`; Codex pushed the current AgentMIM repair stack, including quote workbook cleanup/enrollment accuracy, quote cover profile-data requirements, client identity merge/policy preservation, MIM client-assignment repair audit, and upload-audit missing-commission-gap visibility. Current `E:\comm_app` pushed commits include `1d7af560`, `cb81cd79`, `1ac242a8`, `4438fd5e`, `72c10938`, and `c881916f`. This stabilized the app but does not prove TOD can manage this class of work.

Independent Demonstration: `pending`; TOD must choose one fresh AgentMIM issue from current evidence, inspect the relevant `E:\comm_app` files, produce a bounded repair plan, change real application behavior, run focused validation, and publish evidence without Codex selecting the final hunk or writing the patch.

Freeze: open; the pushed `E:\comm_app` commits are a production freeze point, but the TOD workspace remains dirty and the borrowed capability has not been assimilated.

Retirement: open.

### APP-TOD-020: Terminal Lane Projection And Supersession Hygiene

Borrowed From: Codex emergency control-plane repair during TOD workspace freeze/training cleanup.

Reason: TOD completed `TSK-0068` and `TSK-0069`, but the shared latest artifacts regressed to showing `TSK-0068` as active/blocked while the canonical active execution lane and local execution artifacts showed `TSK-0069` completed. A later operator objective superseded `TSK-0069`, but the visible latest surfaces did not reconcile that terminal/superseded truth.

Incident: `TOD-TERMINAL-LANE-PROJECTION-20260715`

Capability: When the active execution lane reaches a terminal state and no eligible queued successor is promoted, TOD must project that terminal state to `TOD_ACTIVE_TASK.latest.json`, `TOD_ACTIVE_OBJECTIVE.latest.json`, `TOD_EXECUTION_RESULT.latest.json`, `TOD_VALIDATION_RESULT.latest.json`, and `TOD_EXECUTION_TRUTH.latest.json`; stale selected-for-dispatch payloads for the same terminal task must be blocked instead of becoming visible truth.

Current Apprentice: TOD

Proficiency: `reliable`; TOD repeated terminal-lane projection and supersession hygiene across four fresh isolated reliability cycles. This is runtime reliability only, not source-engineering credit.

Progress: `independent_demo_passed`; Codex originally added the terminal active-lane projection helper in `scripts/TOD.ps1`, invoked it from the no-eligible-queued-task drain path, tightened the latest-artifact publish gate so a terminal canonical task cannot be reselected for dispatch, and validated the repair with `PSParser`, `repair-missing-active-lane`, and artifact readback. On 2026-07-22, the recovery-shape proof reran the canonical lane publisher and self-driving selector suites against fresh terminal/supersession fixtures: `tests/TOD.CanonicalLanePublisherGate.Tests.ps1` passed 10/10 and `tests/TOD.SelfDrivingTaskSelection.Tests.ps1` passed 49/49. The proof artifact is `runtime_remote_training/tod_result_artifacts/TOD_EXECUTABLE_RECOVERY_SHAPE_RETIREMENT_PROOF.latest.json`. Fresh reliability evidence: `TOD-APP-020-RELIABILITY-R131-C1A-20260728`, `TOD-APP-020-RELIABILITY-R131-C1B-20260728`, `TOD-APP-020-RELIABILITY-R131-C2A-20260728`, `TOD-APP-020-RELIABILITY-R131-C2B-20260728`, `TOD-APP-020-RELIABILITY-R131-C3A-20260728`, `TOD-APP-020-RELIABILITY-R131-C3B-20260728`, and `TOD-APP-020-RELIABILITY-R137-C4-20260728`; episode `runtime_remote_training/engineering_corpus/TOD_APP_020_RELIABILITY_EPISODE_R137.latest.json`; Examiner `runtime_remote_training/engineering_corpus/TOD_APP_020_RELIABILITY_EXAMINER_R138.latest.json`.

Independent Demonstration: `passed across four fresh isolated reliability cycles`; TOD repeatedly preserved terminal/superseded canonical truth without reselecting stale dispatch state.

Freeze: frozen for terminal-lane projection and supersession hygiene; the named episode and Examiner preserve repeated proof. Prevention lesson: terminal canonical truth and supersession authority must outrank stale selected-for-dispatch projections.

Retirement: retired; Auditor R148 confirmed all retirement gates from current registry and named evidence. Runtime reliability only; no source-engineering credit.

## Active Continuation

Current Dave-away priority overlay:

1. Prove `APP-TOD-016` live: MIM must emit a fresh implementation-shaped request on the existing shared bridge, and TOD must execute or precisely block it with inspected evidence.
2. Continue generalized structured-source evidence synthesis from array/row artifacts.
3. Do not award TOD independent-resolution credit for Codex-authored bridge/materialization repairs; credit starts only after TOD owns the inspect-change-validate-close loop on a fresh task.

Train generalized structured-source evidence synthesis from array/row artifacts.

Current sharp blocker: TOD can synthesize the scaffolded SolAir power-curve proof, but cannot yet inspect a different structured evidence artifact such as `runtime/shared/SOLAIR_PARTS_BOM_OBSERVATION.latest.json`, discover row groups, choose representative evidence, and assemble the required proof body without a dedicated lane.

2026-07-24 engineering-runtime training update:

- `TOD-READONLY-EVIDENCE-ARTIFACT-CONSUMPTION-FOR-SURFACE-SELECTION-V1-R1` remains failed. TOD produced a read-only evidence-consumption proof, but consumed only the first named source-anchor artifact and did not compare all named evidence before selecting the implementation surface. Codex validation restored the expected failure record at `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_EVIDENCE_ARTIFACT_CONSUMPTION_FOR_SURFACE_SELECTION_V1.r1.codex_validation.json`.
- `TOD-MULTI-INPUT-EVIDENCE-CONSUMPTION-SOURCE-ANCHOR-V1-R1` also failed. TOD retried after the transient state-load error was disproven by direct JSON and lightweight bus validation. The execution then confused read-only prior evidence with the output artifact, wrote a source-anchor observation into `TOD_READONLY_EVIDENCE_ARTIFACT_CONSUMPTION_FOR_SURFACE_SELECTION_V1.r1.codex_validation.json`, and never created `TOD_MULTI_INPUT_EVIDENCE_CONSUMPTION_SOURCE_ANCHOR_V1.r1.latest.json`.
- New smallest rung: `TOD-READONLY-OUTPUT-ARTIFACT-PRECEDENCE-V1`. TOD must prove that `Input Artifact` and `Prior Evidence` are read-only evidence sources, while `Output Artifact` is the only publication target unless mutation is explicitly authorized.
- Training classification: runtime/evidence blocker supporting the Engineering Corpus. Do not count this as engineering independence. The runtime must be repaired only far enough to let TOD produce engineering episodes without corrupting evidence.
- `TOD-READONLY-OUTPUT-ARTIFACT-PRECEDENCE-V1-R1` partially improved the behavior: TOD created the requested output artifact and did not mutate input/review evidence, but routed to the generic read-only audit lane and omitted the required `communication_role_map`.
- `TOD-READONLY-OUTPUT-ARTIFACT-PRECEDENCE-V1-R2` passed after Codex supplied the correct existing detector shape. TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_READONLY_OUTPUT_ARTIFACT_PRECEDENCE_V1.r2.latest.json` with `artifact_type=tod_read_only_role_classification_artifact`, mapped `Input Artifact` / `Evidence Artifact` / `Review Artifact` as read-only evidence, mapped `Output` / `Output Artifact` as the write target, and preserved `Source File` as read-only inspection input. This is a scaffolded runtime-support pass, not independent engineering mastery.
- `TOD-MULTI-INPUT-EVIDENCE-CONSUMPTION-SOURCE-ANCHOR-V1-R2` passed the next runtime/evidence rung. TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_MULTI_INPUT_EVIDENCE_CONSUMPTION_SOURCE_ANCHOR_V1.r2.latest.json` with `artifact_type=tod_evidence_pool_source_anchor_classifier`, classified four evidence artifacts, read both named source-anchor artifacts, read the prior failure validation, and selected a real source-anchor observation as the only safe old-text source. This proves multi-input evidence consumption in a supported classifier lane, but it does not yet prove implementation-surface disambiguation or candidate `new_text` synthesis.
- `TOD-CONTEXT-PACKAGE-LANE-IMPLEMENTATION-SURFACE-DISAMBIGUATION-V1-R2` failed usefully. TOD read the classified evidence-pool artifact and detected the requested field contract, but the generic read-only audit lane could not materialize `selected_surface`, `rejected_surface`, or `source_file`. It published the blocker instead of falsely claiming surface-selection mastery. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_CONTEXT_PACKAGE_LANE_IMPLEMENTATION_SURFACE_DISAMBIGUATION_V1.r2.codex_validation.json`.
- Next rung: `TOD-SURFACE-DISAMBIGUATION-FIELD-MATERIALIZATION-V1`, a smaller runtime-support task that teaches TOD how to turn classified evidence into the exact decision fields needed by the Engineering Corpus. This is not engineering independence yet; it is clearing the runtime/evidence path so engineering episodes can be generated.
- `TOD-SURFACE-DISAMBIGUATION-FIELD-MATERIALIZATION-V1-R1` failed usefully. TOD again detected the missing contract fields but could not materialize `selected_surface`, `selected_source_anchor_artifact`, `rejected_surface`, or `source_file` from classified evidence. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_SURFACE_DISAMBIGUATION_FIELD_MATERIALIZATION_V1.r1.codex_validation.json`.
- `TOD-SURFACE-DISAMBIGUATION-MATERIALIZER-SOURCE-ANCHOR-V1-R1` regressed artifact precedence. TOD attempted source-anchor inspection but wrote into the prior validation artifact instead of the requested output artifact. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_SURFACE_DISAMBIGUATION_MATERIALIZER_SOURCE_ANCHOR_V1.r1.codex_validation.json`.
- `TOD-OUTPUT-ARTIFACT-PRECEDENCE-REPEATABILITY-V1-R1` passed after the prompt placed `Output Artifact` last. TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_OUTPUT_ARTIFACT_PRECEDENCE_REPEATABILITY_V1.r1.latest.json`, captured `Get-LocalExecutionSourceAnchorObservationSpec`, and showed the source-anchor path currently derives output from the last JSON path in the prompt. This is a scaffolded repeatability proof and source-anchor diagnosis, not a repair.
- `TOD-OUTPUT-PRECEDENCE-ENGINEERING-EPISODE-CAPTURE-V1-CLASSIFIER` passed. TOD classified five evidence artifacts from the output-precedence failure ladder as Engineering Corpus candidate inputs and rejected none. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_OUTPUT_PRECEDENCE_ENGINEERING_EPISODE_CAPTURE_V1.classifier.codex_validation.json`.
- `TOD-OUTPUT-PRECEDENCE-ENGINEERING-EPISODE-MANIFEST-V1-R1` passed. TOD produced `runtime_remote_training/read_only_audit_artifacts/TOD_OUTPUT_PRECEDENCE_ENGINEERING_EPISODE_CAPTURE_V1.manifest.latest.json` with five episode candidates from the classifier. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_OUTPUT_PRECEDENCE_ENGINEERING_EPISODE_CAPTURE_V1.manifest.codex_validation.json`.
- Next rung: `TOD-OUTPUT-PRECEDENCE-SOURCE-ANCHOR-DELTA-PROPOSAL-V1`. TOD should use the captured source anchor to propose the intended behavior delta for explicit `Output Artifact` precedence without Codex writing the patch.
- `TOD-OUTPUT-PRECEDENCE-SOURCE-ANCHOR-DELTA-PROPOSAL-V1-R1` produced the requested output artifact instead of mutating prior evidence. TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_OUTPUT_PRECEDENCE_SOURCE_ANCHOR_DELTA_PROPOSAL_V1.r1.latest.json` with `artifact_type=tod_source_anchor_delta_proposal`, preserved task identity, identified `scripts/engines/LocalExecutionEngine.ps1` as the target file, and confirmed no source edits. It correctly blocked on `autonomous_meaningful_safe_new_text_synthesis_from_source_anchor` because it could not synthesize `candidate_new_text` without Codex supplying the patch. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_OUTPUT_PRECEDENCE_SOURCE_ANCHOR_DELTA_PROPOSAL_V1.r1.codex_validation.json`.
- `TOD-AUTONOMOUS-MEANINGFUL-NEWTEXT-SYNTHESIS-FROM-SOURCE-ANCHOR-V1-R1` failed before semantic synthesis. TOD accepted the bounded task, but the expected output path contained a stale prior artifact with `artifact_type=tod_read_only_audit_artifact`, not a fresh `tod_source_anchor_newtext_synthesis` artifact. The local lane therefore still lacks admission/publication support for the requested synthesis contract. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_AUTONOMOUS_MEANINGFUL_NEWTEXT_SYNTHESIS_FROM_SOURCE_ANCHOR_V1.r1.codex_validation.json`.
- `TOD-NEWTEXT-SYNTHESIS-ARTIFACT-CONTRACT-ADMISSION-V1-R1` failed usefully. TOD accepted the task, but terminal state blocked with `read_only_audit_required_artifact_type_unsupported`: the generic read-only audit produced `tod_read_only_audit_artifact` while the task required `tod_source_anchor_newtext_synthesis`. No requested output artifact was created and no source code changed. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_ARTIFACT_CONTRACT_ADMISSION_V1.r1.codex_validation.json`.
- `TOD-NEWTEXT-SYNTHESIS-LANE-SOURCE-ANCHOR-V1-R1` also blocked before source-anchor publication with the same artifact-type unsupported condition, this time while requiring `tod_source_anchor_observation`. Codex inspection confirmed `scripts/engines/LocalExecutionEngine.ps1` currently has an explicit `tod_source_anchor_delta_proposal` path but no analogous `tod_source_anchor_newtext_synthesis` admission path. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_LANE_SOURCE_ANCHOR_V1.r1.codex_validation.json`.
- `TOD-NEWTEXT-SYNTHESIS-LANE-ADMISSION-SUPPORT-V1-R1` reached the existing supported `tod_source_anchor_delta_proposal` lane and wrote `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_LANE_ADMISSION_SUPPORT_V1.r1.latest.json`, but the artifact still contained `intended_behavior_delta=Not independently synthesized yet` and `candidate_new_text=''`. Codex validation classifies this as scaffolded lane entry without semantic delta: `runtime_remote_training/read_only_audit_artifacts/TOD_NEWTEXT_SYNTHESIS_LANE_ADMISSION_SUPPORT_V1.r1.codex_validation.json`.
- `TOD-NEWTEXT-SYNTHESIS-LANE-PACKET-FORMATION-V1-R1` did not reach packet formation. Materialization blocked with `target_file_exactly_one` because the task shape made `scripts/engines/LocalExecutionEngine.ps1`, prior evidence, and output artifact compete as target candidates. Validation: `runtime_remote_training/tod_independent_resolution_attempts/TOD_NEWTEXT_SYNTHESIS_LANE_PACKET_FORMATION_V1.r1.codex_validation.json`.
- `TOD-PACKET-FORMATION-TARGET-DISAMBIGUATION-COMPARISON-V1-R1` produced a fresh artifact, but it was swallowed by the read-only task-context proof lane and wrote `artifact_type=tod_read_only_task_context_proof` instead of `tod_readonly_evidence_comparison`; the required comparison fields were absent even though state marked the task implemented. Validation: `runtime_remote_training/read_only_audit_artifacts/TOD_PACKET_FORMATION_TARGET_DISAMBIGUATION_COMPARISON_V1.r1.codex_validation.json`.
- Next rung: `TOD-READONLY-COMPARISON-LANE-PRECEDENCE-V1`. TOD must inspect why comparison requests can be preempted by the read-only task-context proof lane and publish a precise selector-precedence blocker or comparison artifact before another packet-formation attempt.

### APP-TOD-021: Missing Objective Prompt Packaging Recovery

Borrowed From: Codex emergency control-plane repair.

Reason: TOD had a synchronized active task whose local task record already contained a materialization blocker (`blocked_missing_bounded_edit_mode`, missing `target_file`), but `run-task` could not reach that blocker because no packaged prompt existed. The normal `package-task` action also failed because the task's `objective_id` did not exist in the local objective table.

Incident: `TOD-MIM-SYNCED-TASK-MISSING-OBJECTIVE-PACKAGE-20260716`

Capability: When a MIM-synced task exists without a local objective row, TOD should still be able to package the task from task-local context, preserve the missing-objective fact as evidence, and then let `run-task` publish the real execution blocker instead of crashing before classification.

Current Apprentice: TOD

Proficiency: `independent`; TOD independently repeated the missing-objective packaging and active-lane containment behavior on a fresh isolated synchronized task.

Progress: `independent_demo_passed`; Codex originally patched `scripts/TOD.ps1` so `package-task` creates a minimal recovered objective context only for packaging when the objective row is missing, and records `objective_record_recovered` in the package journal payload. This does not solve the task or infer missing bounded-edit fields; it only restores TOD's ability to classify the existing malformed packet. 2026-07-22 scaffold proof: TOD packaged an existing MIM-synced task whose objective row was missing (`maybe-was-that-actually-implemented-or-only-planned-mim-request-80b3c7ca-1340-4310-8b5b-5be616946f58`) and `run-task` reached the true materialization blocker, `target_file_exactly_one`, instead of crashing at package time. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/APP_TOD_021_MISSING_OBJECTIVE_RECOVERY_SCAFFOLD_PROOF.latest.json`. 2026-07-31 independent proof: TOD created and packaged fresh task `missing-objective-fresh-task-20260730222202` after its local objective row was removed, preserved the missing-objective context, reached `blocked_missing_bounded_edit_mode` for `target_file`, published no false completion, and left the pre-existing sentinel active lane byte-stable. Examiner: `runtime_remote_training/engineering_corpus/TOD_APP_021_MISSING_OBJECTIVE_RECOVERY_EXAMINER_R1.latest.json`.

Independent Demonstration: `passed on a fresh isolated MIM-synced task`; TOD packaged from task-local context, surfaced the real blocker, published diagnostic evidence separately, and did not mutate the existing active lane.

Freeze: frozen pending independent Auditor retirement judgment; the fixture, package, execution result, immutable sentinel lane, and Examiner verdict preserve the behavior. Prevention lesson: recover enough task-local context to classify the task, but never let an unexecutable recovered task displace authoritative active work.

Retirement: retired; independent Examiner R1 and Auditor R1 confirmed the fresh missing-objective recovery, real blocker classification, false-completion denial, active-lane containment, and no-source-change gates. Runtime reliability only; no source-engineering credit.

### APP-TOD-022: Packet Formation Artifact Materialization Recovery

Borrowed From: Codex emergency control-plane repair.

Reason: TOD created a packet-formation task to publish a current-code packet candidate or precise blocker, but the local executor treated it as a generic `artifact_write` and blocked because no literal `New Text` payload was present. The existing `New-LocalExecutionPacketCandidateArtifact` capability could already inspect the prompt/current code and build the packet/blocker artifact, but it was orphaned from the artifact-write execution path.

Incident: `TOD-PACKET-FORMATION-ARTIFACT-WRITE-20260716`

Capability: When TOD selects a `packet_formation` artifact target, the local executor should materialize the packet/blocker artifact from inspected current code instead of requiring TOD to pre-render JSON as `New Text`.

Current Apprentice: TOD

Proficiency: `reliable`; TOD repeated packet-formation artifact materialization across three fresh isolated cycles. This is evidence/runtime reliability only, not source-engineering credit.

Progress: `independent_demo_passed`; Codex reconnected packet-formation artifact writes in `scripts/engines/LocalExecutionEngine.ps1` so `TOD_PACKET_FORMATION_*` targets call the existing packet-candidate artifact builder when no explicit `New Text` is provided. This restored TOD's ability to publish packet/blocker evidence as borrowed control-plane repair. 2026-07-22 independent repeat: TOD ran `TSK-0032` through `run-task`, published `runtime_remote_training/tod_independent_resolution_attempts/TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json` with `packet_candidate_ready=true`, selected `tmp_remote_mim/core/routers/enterprises.py`, included exact `old_text`, different `new_text`, validation command, validation pattern, closure evidence, prevention lesson, and `dave_needed=no`. Follow-up proof is recorded in `runtime_remote_training/tod_independent_resolution_attempts/TOD_CURRENT_CODE_PACKET_MATERIALIZATION_RETIREMENT_PROOF.latest.json`. Fresh reliability evidence: `TOD-APP-022-RELIABILITY-R135-C1-20260728`, `TOD-APP-022-RELIABILITY-R135-C2-20260728`, and `TOD-APP-022-RELIABILITY-R135-C3-20260728`; episode `runtime_remote_training/engineering_corpus/TOD_APP_022_RELIABILITY_EPISODE_R135.latest.json`; Examiner `runtime_remote_training/engineering_corpus/TOD_APP_022_RELIABILITY_EXAMINER_R138.latest.json`.

Follow-up: Codex also added `closure_evidence` to generated packet candidates after the live selector rejected a newly generated packet for missing that field. Direct validation proved a packet-formation smoke now publishes `packet_candidate_ready=true` with `closure_evidence` present.

Independent Demonstration: `passed across three fresh isolated packet-materialization cycles`; `TSK-0032` also produced a complete ready packet through the local executor. Full source-engineering loop ownership remains separately tracked under APP-TOD-031.

Freeze: frozen for packet-formation artifact materialization; the named episode and Examiner preserve repeated proof. Prevention lesson: packet-formation tasks must invoke the existing artifact builder instead of requiring pre-rendered `New Text`; this freeze does not grant source-engineering credit.

Retirement: retired; Auditor R148 confirmed all retirement gates from current registry and named evidence. Runtime reliability only; no source-engineering credit.

### APP-TOD-025: Enterprise Foundation Minimal Remote Deployment Pattern

Borrowed From: Codex emergency/product-continuation bridge.

Reason: The Enterprise Foundation shell needed to reach the MIM Box, but the local `tmp_remote_mim` mirror was ignored and dirty, `models.py` contained unrelated research-model changes, and remote hashes differed from local files. Whole-file copy would have risked dragging unrelated mirror edits into production.

Incident: `ENT-001-ENTERPRISE-DATABASE-FOUNDATION-DEPLOY-20260717`

Capability: When deploying MIM Box changes from a dirty ignored mirror, TOD must inspect local intended changes and remote anchors, avoid whole-file upload of dirty shared files, apply only minimal idempotent patches, validate with the remote app virtualenv, restart only after compile/import tests pass, run live smoke tests, and record whether the capability is borrowed or independently demonstrated.

Current Apprentice: TOD

Progress: `borrowed`; Codex deployed the Enterprise model, schemas, service, router, router registration, `/observatory/enterprise` shell, and `ent_demo` / `mimtod` login path through a minimal remote patch approach. Live smoke passed and evidence was recorded in `runtime_remote_training/tod_independent_resolution_attempts/ENT_001_ENTERPRISE_DATABASE_FOUNDATION_PROGRESS.latest.json`.

Proficiency: `observed`; TOD has evidence of the Enterprise deployment pattern and a capability freeze, but has not yet reproduced the pattern independently.

Independent Demonstration: `pending`; TOD must complete `TOD-ENTERPRISE-PATTERN-ASSIMILATION-V1` by inspecting the Enterprise implementation, identifying the deployment pattern, creating one harmless bounded addition, deploying it independently, validating remote compile/import/live smoke, and publishing evidence without Codex-written deployment packets or manual bridge edits.

Freeze: partial; `docs/training/learned-capabilities/ENT_001_CAPABILITY_FREEZE.latest.md` records the architecture, deployed evidence, deployment pattern, and reuse triggers. Retirement remains blocked until TOD repeats the pattern independently.

Retirement: open.

### APP-TOD-045: Enterprise Plan Validation and Deployment

Borrowed From: Codex emergency validation and deployment bridge.

Reason: TOD independently implemented the ENT-204 source changes, but its regression-test packet rolled back because the validation command selected a Python runtime without pytest. Codex supplied the focused test and guarded remote deployment proof.

Incident: `ENT-PLAN-SELECTION-VALIDATION-20260731`

Capability: Select the repository test runtime correctly, preserve exact plan-selection regression contracts, and deploy independently authored Enterprise changes with hash guards, rollback, remote validators, and live browser proof.

Current Apprentice: TOD

Progress: `borrowed_deployed_after_tod_source_success`; evidence is recorded in `runtime_remote_training/read_only_audit_artifacts/ENT_PLAN_SELECTION_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently choose the repository test runtime and complete a fresh guarded deployment plus live proof for its own source change.

Freeze: open.

Retirement: open.

### APP-TOD-046: Enterprise Two-Factor Authentication Flow

Borrowed From: Codex emergency authentication-security bridge.

Reason: TOD independently implemented the TOTP primitives and one-time challenge helpers, but LocalExecutionEngine rejected the request-model, enrollment endpoint, session-gate, and canonical-login interaction packets as `blocked_missing_capability` without changing source.

Incident: `ENT-TWO-FACTOR-AUTHENTICATION-20260731`

Capability: Complete encrypted TOTP enrollment, signed one-time login challenges, attempt-limited verification, password-plus-code disable, fail-closed session gating, and a canonical-login second-factor interaction.

Current Apprentice: TOD

Progress: `borrowed_deployed`; 15 focused tests, 15 remote validator checks, and a 10-check disposable live-account flow pass. The temporary account was removed. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_TWO_FACTOR_V1_VALIDATION.latest.json`.

Independent Demonstration: pending.

Freeze: deployed evidence preserved; TOD-authored independent proof remains open.

Retirement: open.

### APP-TOD-047: Dedicated Google Identity OIDC Flow

Borrowed From: Codex emergency identity-security bridge.

Reason: TOD produced no material Google OIDC implementation for `TSK-0083` through `TSK-0086`; settings and callback packets returned wrapper-only/no-execution or missing-bounded-edit blockers, and the cryptographic foundation reported `validation_only_no_material_change`.

Incident: `ENT-GOOGLE-IDENTITY-OIDC-20260731`

Capability: Implement a dedicated Google authorization-code identity boundary with encrypted state, nonce, local JWKS signature validation, immutable-sub account correlation, safe Enterprise creation, Discovery bootstrap, local TOTP continuation, guarded deployment, and truthful missing-credential behavior.

Current Apprentice: TOD

Progress: `borrowed_deployed`; 21 focused tests and 15 local/remote validator checks pass. A dedicated Google Identity web client is active with the exact production callback. Live Google consent proved standard login, immutable identity correlation, name-aware welcome, Enterprise creation, Community Launch selection, automatic Discovery with five unvalidated candidates, and cleanup with the Google binding retained. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_GOOGLE_IDENTITY_FOUNDATION_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently implement and prove a fresh federated identity integration with a real provider callback.

Freeze: deployed provider evidence preserved; only TOD-authored independent federated-identity proof remains open for apprenticeship retirement, not product completion.

Retirement: open.

### APP-TOD-048: Enterprise Membership and Invitation Lifecycle

Borrowed From: Codex emergency tenancy-security bridge.

Reason: TOD completed the persistent `EnterpriseMembership` model edit, but its next bounded router import task failed before source mutation because concurrent TOD processes locked `tod/data/state.json`. Codex completed the authorized router, UI, test, and deployment slices and recorded the state-lock plus stale whole-model deployment hazard.

Incident: `ENT-ENTERPRISE-MEMBERSHIP-LIFECYCLE-20260731`

Capability: Implement enterprise-scoped owner and admin membership administration with hashed expiring one-time invitations, same-email acceptance, resend token rotation, revocation, cross-tenant denial, metadata synchronization, guarded schema deployment, rollback, and disposable live-account proof.

Current Apprentice: TOD

Progress: `model_authored_then_borrowed_deployed`; 25 focused authentication and membership tests, 22 live source/schema validation checks, and 14 disposable live-account lifecycle checks pass. All disposable records were removed. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_ENTERPRISE_MEMBERSHIP_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently ship a fresh enterprise-scoped invitation or authorization lifecycle without state-lock failure, Codex-authored router patches, or stale whole-file deployment.

Freeze: deployed evidence preserved; TOD-authored independent tenancy-security proof remains open.

Retirement: open.

### APP-TOD-049: Conversation-First Product Governance

Borrowed From: Codex emergency product-governance bridge.

Reason: TOD packaged `TSK-ENT-PHILOSOPHY-EVALUATOR-V1` but could not derive the explicitly requested new-file edit mode and produced no source mutation. Codex implemented the authorized evaluator, task-intake enforcement, focused tests, guarded deployment, and live disposable proof.

Incident: `ENT-CONVERSATION-FIRST-GOVERNANCE-20260731`

Capability: Turn a permanent product philosophy into executable cross-feature governance: classify customer-facing Enterprise work, require a structured conversation-first review before database mutation, persist passing evidence, and allow only auditable future-expiring exceptions.

Current Apprentice: TOD

Progress: `borrowed_deployed`; 34 focused tests and eight live production checks pass, including proof that blocked work creates no database row and that the passing disposable task was cleaned up. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_CONVERSATION_FIRST_GOVERNANCE_V1_VALIDATION.latest.json`.

Independent Demonstration: pending; TOD must independently create a new shared policy module, integrate it at a pre-write boundary, and prove pass, block, persistence, exception, and cleanup behavior.

Freeze: deployed evidence preserved; TOD-authored independent governance implementation proof remains open.

Retirement: open.

### APP-TOD-052: Progressive Registration and Candidate-Knowledge Validation

Borrowed From: Codex emergency Enterprise onboarding bridge.

Reason: MIM produced the bounded ENT-213-223 vertical-slice diagnosis and TOD received three implementation attempts. TOD first required exact Old Text/New Text, then rejected the exact four-line router edit twice because the local engine did not support this source scope. Codex completed the authorized guarded bridge from the live production source.

Incident: `ENT-213-223-ZERO-HOMEWORK-ONBOARDING-20260731`

Capability: Implement progressive email-only Enterprise registration, optional website-assisted discovery before verification, visible discovery progress, website identity assistance, no-website conversation fallback, candidate-only attribute provenance and validation states, cross-tenant-safe derived slugs, and permanent Identity-First/Zero-Homework governance.

Current Apprentice: TOD

Progress: `borrowed_deployed`; focused remote suites pass and the 24-check public live validator passes for website and no-website paths with disposable-data cleanup. Evidence: `runtime_remote_training/read_only_audit_artifacts/ENT_213_223_LIVE_VALIDATION_V1.latest.json` and `runtime_remote_training/read_only_audit_artifacts/ENT_213_223_PROGRAM_MATRIX.latest.json`.

Independent Demonstration: pending; TOD must independently implement a new progressive identity or candidate-validation lifecycle in a production router, including guarded deployment, live proof, and cleanup without Codex source mutation.

Freeze: deployed evidence preserved; rollback backups and guarded hashes are recorded in the deployment artifacts.

Retirement: open.

### APP-TOD-053: Workstation Security Triage and Disaster-Recovery Preservation

Borrowed From: Codex emergency workstation-security and recovery bridge.

Reason: TOD received a bounded read-only malware-triage task as `TSK-0041`, but LocalExecutionEngine returned `blocked_missing_capability` because it cannot collect Windows Defender, process, network, persistence, driver, or recovery telemetry. Dave then explicitly assigned the emergency recovery work directly to Codex.

Incident: `TOD-WORKSTATION-SECURITY-AND-RECOVERY-20260802`

Capability: Perform evidence-first Windows security triage without killing ambiguous processes; run and verify Defender scans; classify process, publisher, lineage, persistence, network, driver, and crash evidence; preserve active critical transfers; create secret-safe Git recovery snapshots; distinguish Git recovery from encrypted database, runtime, model, credential, and bare-metal recovery; and prove remote/off-device copies by hash and restore checks.

Current Apprentice: TOD

Progress: `borrowed`; Defender quick scan and deep process/persistence review found zero active threats and no high-confidence process requiring containment. Codex created and pushed the emergency Git branch, verified the advertised remote commit, created and verified a separate Git bundle, and copied all 41 model files to a separate physical volume with zero SHA-256 mismatches. Evidence: `runtime_remote_training/read_only_audit_artifacts/workstation_security/TOD-WORKSTATION-SECURITY-TRIAGE-20260802.md` and `docs/recovery/TOD_EMERGENCY_RECOVERY_MANIFEST_2026-08-02.md`.

Independent Demonstration: pending; TOD must independently perform a fresh Windows security inventory, publish a confidence-scored containment decision, create a secret-safe recovery snapshot, and prove a clean restore without Codex executing the telemetry or backup workflow.

Freeze: pending native Windows security telemetry collector, encrypted non-Git backup workflow, isolated restore rehearsal, and independent TOD proof.

Retirement: open.
