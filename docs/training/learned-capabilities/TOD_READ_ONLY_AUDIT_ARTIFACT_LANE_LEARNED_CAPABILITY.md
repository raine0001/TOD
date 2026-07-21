# TOD Read-Only Audit Artifact Lane Learned Capability

Capability Name: TOD read-only diagnostic audit artifact publication

Trigger: TOD must perform a diagnostic, route audit, blocker audit, or self-audit without changing source code.

Reality: Broad diagnostic tasks can be misrouted as `chat_execution` or bounded source-edit work when they are sent through `execute-chat-task`.

Observation: `TSK-TODOPS-001` and `TSK-TODOPS-001A` produced blockers because TOD treated read-only inventory work as a multi-target bounded edit. `TSK-TODOPS-001C` succeeded when TOD used `add-task`, `package-task`, and `invoke-engine` with `task_category=report_only`.

Root Cause: The direct-chat execution wrapper can create a fresh objective wrapper and mutate task category/context. The existing local engine already has a read-only audit artifact lane, but TOD must enter through the correct report-only path.

Blocker Class: capability_blocker

Decomposition Ladder:
1. Prove the evidence file exists.
2. Create a `report_only` task with a narrow audit scope.
3. Include `Task Class: report_only`.
4. Include `Input: <json evidence file>`.
5. Include one output artifact path under `runtime_remote_training/read_only_audit_artifacts/`.
6. Package the task.
7. Use `TOD.ps1 -Action invoke-engine`, not `execute-chat-task`.
8. Validate required read-only artifact fields and `no_code_changes=true`.
9. Add TOD result and review records from evidence.

Smallest Successful Rung: `TSK-TODOPS-001C`

Implementation Summary: TOD published `runtime_remote_training/read_only_audit_artifacts/TOD_TECHNICAL_OPERATIONS_RUNG001C_AUDIT.latest.json` through `Invoke-LocalExecutionReadOnlyAuditArtifact`.

Validation:
- `input evidence read`: pass
- `read-only audit artifact write`: pass
- `required schema readback`: pass
- `no-code-change assertion`: pass
- TOD task status: `reviewed_pass`

General Rule Learned: Read-only diagnostics are not source edits. TOD should route them as `report_only` artifacts and preserve input evidence separately from output targets.

Prevention Rule: Do not use `execute-chat-task` for read-only diagnostic artifact publication until task-category and objective-context preservation are repaired. Use `add-task` -> `package-task` -> `invoke-engine`.

Reuse Trigger: Any objective containing `read-only audit`, `route audit`, `self-audit`, `diagnostic artifact`, `no code changes`, or `no source edits`.

Dependent Capabilities:
- Task category preservation
- Objective context preservation
- Evidence-grounded closure reporting
- Technical operations reliability patrol

Capability Confidence: high for report-only artifact publication through `invoke-engine`; low for `execute-chat-task` wrapper preservation.

Independent Pass Rate: 1 passed after 2 failed wrapper attempts.

Date Frozen: 2026-07-09

Generalized Principle: Readers and auditors must have a no-code lane. A diagnostic system that can only think in source edits will misclassify observation work as implementation work.

## 2026-07-21 Patch Evidence Extension

Capability Extension: TOD read-only patch evidence classification

Trigger: TOD must classify a saved `.patch` file as evidence for route hygiene, response-authority risk, hardcoded response debt, phrase-patch debt, or learned-capability candidates without applying the patch.

Reality: A saved patch under `runtime_remote_training/cleanup_holds/` is not product source and is not itself an implementation target. It is preserved evidence. Treating it as a bounded edit target creates false materialization blockers or tempts unsafe reapplication of old experiments.

Observation: `TSK-ROUTE-EXPERIMENT-PATCH-EVIDENCE-R3` preserved read-only task mode but blocked because `.patch` evidence under `cleanup_holds` was outside the local executor's allowed evidence inputs. `TSK-ROUTE-EXPERIMENT-PATCH-EVIDENCE-R4` and `R5` exposed a second shape issue: a generic `chat_execution` wrapper could still cause bounded-edit materialization even when the task was explicitly read-only. `R6` and `R7` then published read-only classification artifacts from the saved patch without source-code mutation. Fresh-target `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R2` exposed a third shape issue: a stale patch path mentioned as an exclusion could still be treated as the explicit input target. `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3` passed after the executor distinguished explicit `Input Patch:` from exclusion text and registered a fresh route patch from git history.

Root Cause: The original learned capability handled JSON evidence artifacts, not preserved patch evidence. The executor lacked a patch-evidence reader with safe input roots, safe output roots, no-apply guarantees, and authority-risk classification.

Blocker Class: capability_blocker

Decomposition Ladder:
1. Prove the saved `.patch` file exists under an allowed evidence root.
2. Prove the requested output artifact is under `runtime_remote_training/read_only_audit_artifacts/`.
3. Preserve explicit `read_only_assessment` task intent even when the wrapper category is `chat_execution`.
4. Parse the patch as text evidence only.
5. Count changed files, route files, hunks, additions, and deletions.
6. Detect response-authority signals such as visible reply authority, operator-contract injection, active conversation state, observational relationship memory, response-authority audit, and phrase-patch risk.
7. Publish a JSON classification artifact.
8. Assert `no_code_changes=true`.
9. Reject fresh-source mutation as completion evidence.
10. For fresh-target proof, distinguish an explicit patch input from a stale patch path mentioned as an exclusion, warning, or materializer candidate.
11. When no explicit patch input is provided, discover a prior route/authority change from repository history and register it as read-only evidence before classification.

Smallest Successful Rung: `TSK-ROUTE-EXPERIMENT-PATCH-EVIDENCE-R6`

Repeatability Check: `TSK-ROUTE-EXPERIMENT-PATCH-EVIDENCE-R7`

Fresh Analogous Demonstration: `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3`

Implementation Summary: Codex repaired the local executor and mode-precedence control plane after TOD's blocked attempts. TOD then ran the repaired lane and published:
- `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_PATCH_EVIDENCE_R6.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_EXPERIMENT_PATCH_EVIDENCE_R7.latest.json`
- `runtime_remote_training/read_only_audit_artifacts/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.latest.json`

Fresh registration evidence:
- Source commit: `9e9c44454556`
- Registered patch: `runtime_remote_training/cleanup_holds/TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3_9e9c44454556.patch`
- Route files classified: 2
- Signals detected: `visible_reply_authority`, `operator_contract_injection`

Validation:
- `patch evidence input read`: pass
- `patch authority signal extraction`: pass
- `read-only artifact write`: pass
- `no product source edit assertion`: pass
- `Invoke-Pester -Script tests\TOD.ReadOnlyAuditRegression.Tests.ps1`: pass
- `Invoke-Pester -Script tests\TOD.BoundedEditMaterialization.Tests.ps1`: pass
- `TSK-ROUTE-FRESH-PATCH-INDEPENDENT-R3`: pass; fresh patch registered and classified from broad route/authority evidence request

General Rule Learned: A patch can be either an edit instruction or preserved evidence. TOD must classify the task mode before treating a `.patch` as executable. For authority audits, the patch is evidence and must be read, classified, and preserved without application. A path string alone is not proof of explicit input authority; TOD must distinguish direct input directives from stale examples, exclusions, and diagnostic mentions.

Prevention Rule: Do not broaden source-edit safe roots to include cleanup holds. Add explicit read-only evidence readers with narrow input/output roots and `no_code_changes` validation instead.

Reuse Trigger: Any saved `.patch` in `runtime_remote_training/cleanup_holds/` or `tod/out/tests/` that needs route hygiene, hardcoded-response, response-authority, or phrase-patch classification. Also reuse when a route/authority audit needs a fresh analogous target and only repository history can supply the next evidence object.

Dependent Capabilities:
- Direct chat read-only task mode preservation
- Patch evidence safe-root classification
- Response authority audit classification
- Route hygiene boundary discipline

Capability Confidence: medium-high. The lane passed R6/R7, focused regression tests, and R3 fresh-target registration/classification after Codex repaired the stale-path precedence gap.

Independent Pass Rate: 1 fresh analogous demonstration through repaired lane; 2 scaffolded/repeat passes after control-plane repair.

Separate Debt: `APP-TOD-034` is no longer blocked on fresh-target evidence. It remains open for reliability until a future fresh route/authority case passes without additional executor changes.

Date Extended: 2026-07-21

Generalized Principle: Evidence adapters should expand what TOD can inspect, not what TOD can mutate. More readable evidence should not imply broader write authority.
