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

TOD borrowed skill status: `observed`.

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
- The local engine currently has read-only audit support for JSON evidence artifacts under `runtime_remote_training/read_only_audit_artifacts/`, but it cannot yet consume a saved `.patch` as read-only evidence for classification.

Validation:

- `python -m py_compile scripts/check_remote_preactive_trace_readiness.py scripts/generate_remote_preactive_field_trace_package.py` passed.
- `Invoke-Pester tests/TOD.IntakeArbitration.Tests.ps1` passed the new read-only task preservation test.
- Full Pester result is currently 16 passed / 1 failed. The remaining failure is an existing admin-repair lane expectation, not this read-only preservation repair.

Borrowed capability created:

- `APP-TOD-033: Direct Chat Read-Only Task Mode Preservation`

New training debt discovered:

- `APP-TOD-034: Patch Evidence Ingestion For Read-Only Audits`

TOD independent status remains false. The control plane can now carry read-only work correctly, but TOD still needs to independently run this classification from the saved patch and publish its own artifacts without Codex-provided buckets.

The next smallest rung is not to broaden the safe roots blindly. TOD should learn to convert preserved patch evidence into an allowed read-only evidence object, or add a read-only-only patch evidence lane with explicit no-write validation.

## Next Automatic Action

TOD should complete Rung 1 independently from the saved patch and publish:

- `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_AUTHORITY_CLASSIFICATION_V1.latest.json`
- `docs/training/hard-route-audit/TOD_ROUTE_EXPERIMENT_AUTHORITY_CLASSIFICATION_V1.md`

Then TOD should start Rung 2 on the response-authority audit service packaging path.
