# TOD-ROUTE-EXPERIMENT-AUTHORITY-CLASSIFICATION-V1

## Mission

Classify the saved MIM/TOD route experiment patch and decide which parts are safe process support, which parts are reusable service candidates, and which parts are hardcoded response authority that must not return to product code.

This is a read-only TOD training objective. It does not authorize source-code changes.

## Source Evidence

Saved patch:

`runtime_remote_training/cleanup_holds/20260721_remaining_dirty_mim_tod_route_experiments.patch`

Prior cleanup note:

`docs/training/hard-route-audit/MIM_TOD_REMAINING_DIRTY_ROUTE_EXPERIMENTS_20260721.md`

Related authority evidence:

- `runtime_remote_training/read_only_audit_artifacts/MIM_AUDITOR_HARDCODED_RESPONSE_ROUTE_AUDIT_V1.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/MIM_SINGLE_RESPONSE_AUTHORITY_CONTAINMENT_V1B.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/MIM_SINGLE_RESPONSE_AUTHORITY_TRACE_SUITE_V1.latest.json`

## Classification Summary

| Patch Area | Classification | Decision |
| --- | --- | --- |
| Studio chat thread load/save helpers | process_support_candidate | May return only as a small persistence service with schema tests. Do not keep as route bulk. |
| Active objective materialization | reusable_service_candidate | Concept is useful, but must become an objective-state service. Route may call it; route may not own the cognitive state model. |
| Active conversation slot state | reusable_service_candidate | Useful capability, but current patch is prompt/example-shaped. Must be generalized as active conversation state with slot schemas and unseen continuation tests. |
| Observational relationship memory | reusable_service_candidate | Correct product direction, but implementation must store subject-relationship-object facts generically and prove examples beyond location. |
| Location/weather helpers | hardcoded_example_leak | Reject as-is. Location is one relationship type, not a route-owned location module or weather phrase branch. |
| Self-knowledge profile replies | hardcoded_response_authority_risk | Reject visible route replies. A profile can supply evidence, but final text must come from the authoritative composer. |
| Current external source replies | hardcoded_response_authority_risk | Reject as-is. Current-source requests should produce a retrieval/live-source action, not route-authored visible text. |
| Response-authority scan and trace UI | process_support_candidate | Keep concept. Auditor routes may expose service results, but scanner/trace logic belongs in an audit service and must not alter MIM replies. |
| `_studio_cognitive_authority_reply` canned replies | prohibited_semantic_authority | Reject. It directly authors coaching, objective, recommendation, product, and learning replies in a route. |
| Conversation-purpose `enforce_authority` containment | process_support_candidate | Keep concept only if implemented at the authority boundary, not as a late route exception. |
| TOD no-Codex contingency phrase detector | phrase_patch_rejected | Reject as-is. The need is blocker recovery policy and fallback ladder reasoning, not phrase-triggered text. |
| Training attention next-action text injection | route_debt | Reject as route text. Store as training-policy evidence and let MIM/TOD compose from current state. |

## Route Boundary Rule

Routes may:

- authenticate
- parse request payloads
- call a service
- return structured service output
- render service state

Routes may not:

- decide MIM's communication act
- invent MIM's final visible answer
- append operator contracts
- rewrite composer output
- remember facts through ad hoc route globals
- trigger phrase-specific fallback replies
- convert training artifacts into product responses

## Learned-Capability Return Path

Nothing from the saved patch should return through direct copy/paste. A retained idea must pass this ladder:

1. Name the missing capability.
2. Define the data model or service boundary.
3. Remove example-specific wording from implementation.
4. Add tests using at least three unseen examples.
5. Prove the route only delegates to the service.
6. Prove final visible text authority remains with the cognitive composer or explicitly authorized process.
7. Publish evidence and update the apprenticeship registry.

## Required TOD Training Rungs

### Rung 1: Read-Only Patch Classification

TOD inspects the saved patch and publishes a classification artifact. No source files change.

Pass evidence:

- every patch family assigned to a bucket
- prohibited visible-text authorities named
- reusable service candidates named
- no product files modified

### Rung 2: Single Candidate Service Extraction Plan

TOD selects one candidate from the reusable list and writes an extraction plan with target service name, route call boundary, validation tests, and rollback rule.

Suggested first candidate:

`response_authority_audit` service packaging and Auditor display, because it is diagnostic and does not need to author user-visible MIM replies.

### Rung 3: Generalization Test Design

TOD writes tests that prove the chosen capability works on examples not present in the dirty patch.

### Rung 4: Bounded Implementation

Only after Rungs 1-3 pass, TOD may implement one bounded service extraction.

### Rung 5: Authority Verification

Run the response-authority trace suite and verify that no route/template becomes final visible authority unless explicitly authorized.

## Current Verdict

TOD borrowed skill status: `scaffolded_pass`.

The saved patch proves useful instincts, but not safe implementation. It correctly points toward active conversation state, observational relationship memory, and response-authority auditing. It also repeats the exact failure pattern Dave is trying to eliminate: route-level cognition and visible hardcoded answers.

## TOD Attempt And Control-Plane Finding

TOD was given this as a read-only classification task through `execute-chat-task`.

Observed result:

- R1 failed before intake because `-Scope` was missing.
- R2 supplied `-Type read_only_assessment`, but the explicit type was not preserved into `Invoke-ExecuteChatTaskRequest`.
- TOD therefore treated the task as implementation-shaped work and blocked on missing bounded-edit fields instead of performing the assessment.
- Codex repaired the control plane after TOD's blocked attempt by preserving `-Type` as `task_mode` before intake arbitration.
- Regression coverage now proves a read-only `execute-chat-task` request can enter intake without `target_file`, `edit_mode`, or bounded-edit fields.
- R3 preserved `task_mode=read_only_assessment` and `bounded_edit_mode=false`, but local execution still blocked because the saved `.patch` evidence under `runtime_remote_training/cleanup_holds/` is outside the bounded safe roots.
- The local engine previously had read-only audit support for JSON evidence artifacts under `runtime_remote_training/read_only_audit_artifacts/`, but could not consume a saved `.patch` as read-only evidence for classification.
- Codex repaired that borrowed control-plane rung after TOD's blocked attempt by adding a read-only-only patch evidence lane. The lane accepts `.patch` input only from explicit safe evidence roots, publishes JSON artifacts only under `runtime_remote_training/read_only_audit_artifacts/`, and asserts that no product source changes are made by the assessment.
- R4/R5 proved the remaining shape issue: the task still arrived with a `chat_execution` wrapper, so the local engine fell back to bounded-edit materialization.
- Codex repaired the precedence and matcher rules so explicit read-only task intent outranks a generic chat wrapper when a safe patch evidence input/output contract is present.
- R6 then completed through TOD's local execution lane and published `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_PATCH_EVIDENCE_R6.latest.json`.
- R7 repeated the same read-only classification through TOD's local execution lane without additional code changes and published `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_PATCH_EVIDENCE_R7.latest.json`.
- Fresh-target R1/R2 exposed the remaining independence gap: broad "find/register a fresh route patch" tasks still reused the already-classified cleanup patch when the old path appeared as an exclusion or materializer candidate.
- Codex repaired that evidence-selection rung after the R2 blocker by teaching the local executor to distinguish an explicit `Input Patch:` from a stale patch path mentioned as "do not use this", and by adding a fresh route-patch registration lane that discovers committed route diffs from git history.
- R3 then completed through TOD's local execution lane from a broad fresh-target request, registered `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch` from commit `9e9c44454556`, and published `runtime_remote_training/read_only_audit_artifacts/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.latest.json`.

R6/R7 evidence:

- Artifact type: `tod_patch_evidence_authority_classification`
- Tasks: `TSK-ROUTE-EXPERIMENT-PATCH-EVIDENCE-R6`, `TSK-ROUTE-EXPERIMENT-PATCH-EVIDENCE-R7`
- Input patch: `runtime_remote_training/cleanup_holds/20260721_remaining_dirty_mim_tod_route_experiments.patch`
- Route files classified: 2
- Classification counts: `hardcoded_response_authority_risk=1`, `operator_contract_authority_risk=1`, `reusable_service_candidate=2`, `process_support_candidate=1`, `phrase_patch_rejected=1`
- Signals detected: `visible_reply_authority`, `operator_contract_injection`, `active_conversation_state`, `observational_relationship_memory`, `response_authority_audit`, `tod_phrase_patch`
- No source code modified by assessment: true
- Latest execution result advanced to R7 after background execution completed.

R3 fresh-target evidence:

- Artifact type: `tod_patch_evidence_authority_classification`
- Task: `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3`
- Input patch: `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch`
- Source commit: `9e9c44454556`
- Route files classified: 2
- Classification counts: `hardcoded_response_authority_risk=1`, `operator_contract_authority_risk=1`
- Signals detected: `visible_reply_authority`, `operator_contract_injection`
- No source code modified by assessment: true
- Latest execution result advanced to R3 after background execution completed.

Validation:

- `python -m py_compile scripts/check_remote_preactive_trace_readiness.py scripts/generate_remote_preactive_field_trace_package.py` passed.
- `Invoke-Pester tests/TOD.IntakeArbitration.Tests.ps1` passed the new read-only task preservation test.
- Full Pester result is currently 16 passed / 1 failed. The remaining failure is an existing admin-repair lane expectation, not this read-only preservation repair.
- `Invoke-Pester -Script tests\TOD.ReadOnlyAuditRegression.Tests.ps1` passed with the read-only patch evidence lane.
- `Invoke-Pester -Script tests\TOD.BoundedEditMaterialization.Tests.ps1` passed with explicit read-only mode outranking generic `chat_execution`.
- `Invoke-Pester -Script tests\TOD.ReadOnlyAuditRegression.Tests.ps1` passed after adding the stale-patch exclusion regression for fresh target registration.

Borrowed capability created:

- `APP-TOD-033: Direct Chat Read-Only Task Mode Preservation`

Training debt advanced:

- `APP-TOD-034: Patch Evidence Ingestion For Read-Only Audits`

TOD independent status advanced to `independent_demo_passed` for fresh-target evidence registration and read-only classification. R3 did not receive an explicit patch path; TOD used the repaired lane to discover committed route evidence, register a fresh patch, classify it, and publish validation evidence. This is still not `reliable` because the fresh-registration lane itself was Codex-repaired after R2. Reliability requires repeated future fresh analogous cases without more executor changes.

The next smallest rung is a fresh analogous task where TOD selects or registers a patch-evidence target, runs the read-only evidence lane, publishes classification evidence, and explains which behavior may return only through learned capability paths.

Fresh-target limitation resolved:

- The allowed patch evidence roots still preserve saved cleanup patches, but TOD can now register a fresh read-only patch evidence object from committed route history when a second saved cleanup patch does not yet exist.
- The next repeatability bar is reliability: on the next independently discovered route/authority issue, TOD must run the same register -> classify -> publish loop without additional executor repair.

## Next Automatic Action

TOD should continue Rung 2 on the response-authority audit service packaging path. The fresh Rung 1 demonstration is now published:

- `runtime_remote_training/read_only_audit_artifacts/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.latest.json`
- `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch`

Retirement requires at least one more future fresh analogous pass without Codex executor changes.
