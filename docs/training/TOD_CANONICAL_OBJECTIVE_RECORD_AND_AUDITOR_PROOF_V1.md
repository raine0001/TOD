# TOD Canonical Objective Record And Auditor Proof V1

Status: ready for TOD training  
Owner: TOD  
Codex role: advisory and validation only

## Mission

TOD must use the existing MIM/TOD canonical objective foundation from TOD's execution perspective. This objective does not authorize a new TOD-only objective lifecycle system.

The required change is architectural discipline: TOD adds execution-perspective state to the shared lifecycle instead of creating a second record that can drift from MIM, Studio, or Auditor.

## Existing Foundation To Reuse

TOD must build on these existing truth surfaces:

- `runtime/shared/MIM_TOD_OBJECTIVE_INDEX.latest.json`
- `runtime/shared/MIM_TOD_MANAGED_OBJECTIVES.latest.json`
- `runtime/shared/TOD_ACTIVE_OBJECTIVE.latest.json`
- `runtime/shared/TOD_ACTIVE_TASK.latest.json`
- `runtime/shared/TOD_EXECUTION_TRUTH.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`
- `runtime/shared/TOD_MATERIAL_IMPLEMENTATION_PROOF_POLICY.latest.json`
- `runtime/shared/MIM_TOD_FRESHNESS_PROVENANCE_POLICY.latest.json`
- `/studio/auditor` for independent pass/fail evidence when execution proof needs verification

## TOD Perspective Fields

TOD's objective view should preserve or derive:

- `objective_id`
- `request_id`
- `task_id`
- `task_mode`
- `expected_owner`
- `actual_performer`
- `current_phase`
- `active_step`
- `blocker_state`
- `recovery_state`
- `execution_evidence`
- `validation_plan`
- `validation_results`
- `material_proof_status`
- `freshness_provenance`
- `auditor_evidence_package_id`
- `auditor_verdict`
- `next_action`
- `dave_needed`

## Lifecycle Rule

When TOD accepts or executes an objective, TOD must:

1. Resolve canonical objective and task identity from the existing shared MIM/TOD surfaces.
2. Refuse to create a competing objective dossier if a canonical objective already exists.
3. Add TOD execution state to the existing lifecycle view.
4. Attribute every result to the actual performer.
5. Treat chat replies, hourly summaries, and `.latest` timestamps as summaries only until execution truth and material proof agree.
6. When TOD claims completion or readiness, call Auditor or publish an Auditor evidence request if independent verification is required.
7. Treat completion as non-authoritative until material proof, freshness provenance, and Auditor proof agree for material work.

## Auditor Integration

TOD should use Auditor when:

- a completion claim affects production behavior
- material implementation is declared complete
- a live route or user-visible workflow is part of acceptance
- evidence sources disagree
- Codex was involved and borrowed capability may be counted incorrectly
- a stale artifact could be mistaken for current progress

The Auditor evidence request should include:

- objective id, task id, and request id
- claimed outcome
- changed files or meaningful artifact writes
- validation commands and results
- live-path checks when applicable
- known risks
- expected owner and actual performer
- pass/fail criteria
- requested verdict

## Acceptance Criteria

TOD passes only when it demonstrates this on a fresh TOD-owned task:

- one canonical objective record is resolved before execution
- no parallel TOD objective dossier is created
- active task, execution truth, validation result, and material proof point to the same objective/task lineage
- chat/status text is treated as non-authoritative unless backed by execution truth
- a blocker updates the same lifecycle view instead of creating a competing task
- a completion claim includes material proof or a valid non-material exemption
- Auditor evidence is requested or consumed for independent proof when required
- `/studio/tod` can show the TOD perspective without inventing its own truth

## Negative Tests

TOD must reject or mark non-authoritative:

- wrapper-only success
- chat-only completion claims
- stale `.latest` files without matching execution truth
- a task with different objective lineage
- a second objective dossier for the same objective
- Auditor pass/fail claims that lack source evidence

## First Demonstration

Objective: `TOD-CANONICAL-OBJECTIVE-RECORD-AUDITOR-PROOF-SMOKE-V1`

TOD should:

1. Inspect existing canonical objective and execution truth surfaces.
2. Select one harmless read-only or artifact-writing objective.
3. Resolve canonical objective/task lineage before work begins.
4. Publish a TOD perspective artifact that references the existing canonical record.
5. Request Auditor validation or record why Auditor is not required.
6. Validate that no competing objective record was created.
7. Publish a prevention lesson explaining how TOD will avoid split-brain objective truth.

## Prevention Lesson

TOD does not need its own separate objective brain. TOD needs an execution-perspective lens on the shared MIM/TOD objective brain, with Auditor acting as the independent proof authority when completion or production impact must be trusted.
