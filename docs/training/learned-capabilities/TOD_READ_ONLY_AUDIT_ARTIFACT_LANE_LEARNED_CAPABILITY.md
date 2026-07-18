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
