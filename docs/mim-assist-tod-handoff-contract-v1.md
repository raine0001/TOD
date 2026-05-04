# MIM Assist TOD Handoff Contract v1

Purpose: define how MIM-related implementation work should be handed to TOD so TOD can act as the default engineering executor for MIM Assist without ambiguous task packaging.

## Contract Goal

Every MIM engineering handoff should give TOD enough context to:
- identify the affected runtime surface
- classify the risk and allowed edit zone
- choose the required validation gates
- produce an observable result bundle

## Required Task Fields

Each MIM engineering task should provide these fields.

1. `project_id`
- Expected value for this lane: `mim_wall`

2. `objective_id`
- Stable objective identifier from the MIM or TOD planning surface.

3. `task_id`
- Stable task identifier for the bounded engineering slice.

4. `title`
- One-line engineering objective.

5. `problem_statement`
- What is wrong, stale, missing, or being requested.

6. `target_surface`
- One or more of:
  - `ui_shell`
  - `call_screening`
  - `live_call_runtime`
  - `messaging_dialog`
  - `voice_provider`
  - `session_state`
  - `workstation_bridge`
  - `validation_scripts`

7. `observed_evidence`
- Logs, screenshots, artifacts, scenario failures, or operator-reported symptoms.

8. `expected_behavior`
- What the system should do after the change.

9. `constraints`
- Explicit non-goals, policy limits, or behavior that must be preserved.

10. `edit_scope`
- Paths or modules that are in scope.

11. `validation_requirements`
- Exact required gates such as build, lint, device smoke, automated dialog regression, or UI verification.

12. `rollback_expectation`
- What to restore or disable if the slice fails validation.

## Suggested Optional Fields

1. `risk_class`
- `safe`, `guarded`, `approval_required`

2. `known_failure_zone`
- Example: `capability_drift`, `live_call_interrupt`, `queue_state_divergence`, `provider_degradation`, `snapshot_lag`

3. `operator_approval_required`
- Boolean for manifest/permission, rollout, or security-sensitive changes.

4. `paired_surfaces`
- Additional surfaces likely to move with the primary target.

## Acceptance Criteria Contract

The handoff must define acceptance in observable terms.

Minimum acceptance shape:

1. Behavior acceptance
- The reported defect or requested feature is resolved in the target surface.

2. Safety acceptance
- No unrelated behavior is intentionally changed.

3. Validation acceptance
- Required gates complete successfully or are explicitly reported as unavailable.

4. Artifact acceptance
- Result evidence is written to a deterministic path or summarized from deterministic outputs.

## Result Reporting Contract

TOD should report these fields back for completed MIM work.

1. `task_id`
2. `status`
- `completed`, `blocked`, `partial`, `failed_validation`

3. `files_changed`
- Relative file list

4. `root_cause_summary`
- Short explanation of the actual underlying issue addressed

5. `change_summary`
- What changed at the engineering level

6. `validation_summary`
- Which gates ran and whether they passed

7. `runtime_summary`
- Any observed runtime or UI result after the change

8. `remaining_risks`
- Residual concerns or follow-up items

9. `artifacts`
- Paths to reports, regression output, or generated stewardship evidence

## Rollback and Failure Expectations

When TOD cannot safely complete a MIM task, it should fail closed.

TOD should:

1. preserve working behavior unless an intentional change is required
2. stop before destructive or policy-sensitive changes without explicit approval
3. report the blocking artifact, blocking surface, and next bounded action
4. avoid broad rewrites when a root-cause slice is still possible

## Default Validation Profiles

### Documentation-only or script-only change
- syntax validation if applicable
- script execution in dry or quick mode where available

### App runtime change
- `./gradlew.bat assembleDebug`
- `./gradlew.bat lintDebug`

### Behavior change in screening, messaging, or communicator flow
- build + lint
- `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1`

### Device/runtime recovery change
- build + lint
- `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/device_smoke_test.ps1`
- targeted scenario or busy-intercept verification where relevant

## Example Task Envelope

```json
{
  "project_id": "mim_wall",
  "objective_id": "TOD-MIM-ENGINEERING-STEWARDSHIP",
  "task_id": "mim-wall-runtime-health-export-001",
  "title": "Expose capability drift in the dashboard and stewardship artifact",
  "problem_statement": "Role and permission drift can break runtime behavior without a clear exported health signal.",
  "target_surface": ["ui_shell", "session_state", "validation_scripts"],
  "observed_evidence": ["capability preflight is only visible during regression output"],
  "expected_behavior": "Dashboard and TOD health checks can explain whether call, SMS, and role capability is ready.",
  "constraints": ["Do not change live screening policy", "Keep existing validation scripts working"],
  "edit_scope": [
    "app/src/main/java/com/dave/callguardian/MainActivity.kt",
    "app/src/main/java/com/dave/callguardian/domain",
    "scripts/automated_dialog_regression.ps1"
  ],
  "validation_requirements": [
    "./gradlew.bat assembleDebug",
    "./gradlew.bat lintDebug",
    "powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1"
  ],
  "rollback_expectation": "Revert UI/export changes and keep existing runtime behavior unchanged."
}
```

## Stewardship Rule

For MIM Assist, TOD should be the default execution path when:
- the target falls inside a safe or guarded edit zone
- the required validation profile is known
- the task can be packaged as a bounded slice

Direct operator mediation should be reserved for approval-required changes, unclear authority boundaries, or runtime surfaces that cannot currently be validated.