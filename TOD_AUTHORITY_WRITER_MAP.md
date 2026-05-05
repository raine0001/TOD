# TOD Authority Writer Map

## Scope

This map covers source-backed writers for these artifact families in the TOD workspace:

- `TOD_MIM_*.json`
- `MIM_TOD_*.json`
- `TOD_ACTIVE_*.json`
- `TOD_EXECUTION_*.json`
- `TOD_MIM_COMMAND_STATUS.latest.json`
- `TOD_MIM_SHARED_TRUTH.latest.json`

It separates authoritative runtime writers from mirror, diagnostic, replay, and simulation surfaces. The intent is to describe who is allowed to write `.latest` state, where lineage is enforced, where stale memory is retained, and where objective-only reconciliation is intentionally allowed.

## Authority Summary

### Primary authoritative writers

| Writer | Functions | Artifacts | Role | Overwrites `.latest` | Archives/supersedes | Validation behavior |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts/Start-TODMimPacketListener.ps1` | `Publish-CommandStatus`, `Publish-ExecutionDecision`, `Add-LoopJournalEntry`, `Update-TaskHighWatermark`, `Get-ObjectiveHighWatermark`, `New-StaleGuardMetadata`, `Get-BridgeRuntimeStatus` | `TOD_MIM_COMMAND_STATUS.latest.json`, `TOD_MIM_EXECUTION_DECISION.latest.json`, `TOD_MIM_TASK_ACK.latest.json`, `TOD_MIM_TASK_RESULT.latest.json`, `TOD_LOOP_JOURNAL.latest.json`, `listener_state.json` | Live bridge runtime authority for TOD-side ACK/result/decision/status and stale-guard memory | Yes | No formal archive on normal writes; latest is overwritten in place | ACK and RESULT packets are wrapped with contract envelope, sequence/runtime fields, and validated via Python runtime validator before publish. Command status is not independently contract-validated, but it mirrors validated runtime state. |
| `scripts/Invoke-TODCanonicalLatestArtifactRecoupling.ps1` | `Test-ArtifactNeedsRecoupling`, `New-CanonicalRecouplingPayload`, internal `Write-JsonFile` | `TOD_ACTIVE_OBJECTIVE.latest.json`, `TOD_ACTIVE_TASK.latest.json`, `TOD_EXECUTION_RESULT.latest.json`, `TOD_EXECUTION_TRUTH.latest.json`, `TOD_ACTIVITY_STREAM.latest.json`, `TOD_VALIDATION_RESULT.latest.json` | Canonical lane publisher for runtime/shared execution artifacts | Yes | Yes, previous payloads move into `superseded/<artifact>/latest.*.json` | Uses canonical objective/task inputs and lane comparison logic; treats mismatched objective or task in current latest payload as recoupling trigger. |
| `scripts/reconcile_tod_mim_shared_truth.py` | `reconcile_shared_truth_payload`, `write_shared_truth` | `TOD_MIM_SHARED_TRUTH.latest.json` | Reconciled truth surface combining TOD execution artifacts and MIM exports | Yes | No archive in writer itself | Normalizes objective IDs, composes canonical task references, compares timestamps, and intentionally allows limited objective-level precedence from MIM authority sources. |

### Secondary writers with controlled mutation

| Writer | Functions | Artifacts | Role | Overwrites `.latest` | Archives/supersedes | Validation behavior |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts/Invoke-TODForcedExecutionReplay.ps1` | `Invoke-ForcedExecutionReplayInternal`, `New-ForcedReplayRequest`, `New-ForcedReplayTrigger`, `New-ForcedReplayCommandStatus`, `Update-ListenerStateForForcedReplay` | `MIM_TOD_TASK_REQUEST.latest.json`, `MIM_TO_TOD_TRIGGER.latest.json`, `TOD_MIM_COMMAND_STATUS.latest.json`, `listener_state.json` | Explicit replay mutator that rewrites live request lineage for a forced replay path | Yes | Yes, archives live artifacts under `archive/forced-execution-replay/...` | Refuses replay if live request objective/task do not match requested replay lane; requires explicit `-Force`. |
| `scripts/Copy-TODCurrentStateToContextSync.ps1` | main copy loop | Many mirrored `TOD_MIM_*` and `MIM_TOD_*` artifacts plus `CURRENT_TOD_MIM_STATE_INDEX.latest.json` and `.md` | Mirror/syndication surface from canonical local sources to context-sync root | Yes | No | Does not validate lineage; copies whatever source file currently exists and records hash/timestamp metadata. |

## Writer Inventory

### Live runtime authority

#### `scripts/Start-TODMimPacketListener.ps1`

This is the decisive writer for live bridge lineage.

Artifacts written locally and, when configured, pushed remotely:

- `MIM_TOD_TASK_REQUEST.latest.json` is consumed, not authored, by the listener.
- `TOD_MIM_TASK_ACK.latest.json`
- `TOD_MIM_TASK_RESULT.latest.json`
- `TOD_MIM_COMMAND_STATUS.latest.json`
- `TOD_MIM_EXECUTION_DECISION.latest.json`
- `TOD_LOOP_JOURNAL.latest.json`
- `listener_state.json`
- runtime contract binding and violation sidecars
- coordination and troubleshooting sidecars adjacent to the main lane

Authority behavior:

- Treats itself as the live TOD-side writer for ACK, result, decision, status, and bridge stale-memory state.
- Writes `.latest` files directly.
- Mirrors the same payloads to the remote shared surface after local write.
- Holds high-watermark, dedup, and stale-guard memory inside `listener_state.json` and `TOD_LOOP_JOURNAL.latest.json`.

Validation behavior:

- ACK packets are built, enveloped, sequenced, then validated with `Test-ContractRuntimePacket` before publish.
- RESULT packets are built, enveloped, sequenced, then validated with the same runtime contract validator before publish.
- Validation failures create `TOD_MIM_RUNTIME_CONTRACT_VIOLATION.latest.json`, update runtime binding state, and downgrade command status to `contract_violation_rejected`.
- `Publish-CommandStatus` persists listener-state observations and emits a status packet that includes `bridge_runtime`, `stale_guard`, trigger context, and references to ACK/RESULT state.

Overwrite and archival behavior:

- Overwrites `.latest` files in place.
- Does not archive normal ACK/RESULT/STATUS writes.
- Replay and some recovery flows create separate archive directories outside normal publish logic.

#### `scripts/Invoke-TODCanonicalLatestArtifactRecoupling.ps1`

This script republishes runtime/shared canonical latest artifacts when current latest files do not match the canonical lane.

Artifacts written:

- `TOD_ACTIVE_OBJECTIVE.latest.json`
- `TOD_ACTIVE_TASK.latest.json`
- `TOD_EXECUTION_RESULT.latest.json`
- `TOD_EXECUTION_TRUTH.latest.json`
- `TOD_ACTIVITY_STREAM.latest.json`
- `TOD_VALIDATION_RESULT.latest.json`
- `TOD_MIM_SHARED_TRUTH.latest.json` via the reconcile script unless `-SkipReconcile` is used

Authority behavior:

- Treats the provided canonical objective/task as the lane to restore.
- Replaces mismatched latest artifacts with canonical recoupled payloads.
- Suitable for repairing shared runtime surfaces after drift.

Validation behavior:

- `Test-ArtifactNeedsRecoupling` flags a payload when normalized objective differs or when task differs.
- The writer uses canonical objective and task parameters to stamp all replacement payloads.

Overwrite and archival behavior:

- Overwrites `.latest` payloads directly.
- Archives prior latest payloads into `superseded/<artifact-name>/latest.*.json` before replacement.

#### `scripts/reconcile_tod_mim_shared_truth.py`

This is the shared-truth reconciler and the only direct writer of `TOD_MIM_SHARED_TRUTH.latest.json` in the repo.

Artifacts written:

- `TOD_MIM_SHARED_TRUTH.latest.json`

Authority behavior:

- Merges TOD execution artifacts with MIM exports and status surfaces.
- Produces an explicitly reconciled truth view rather than a raw mirror of any single writer.
- Can prefer MIM authority when the MIM authority source is one of `formal_program_truth`, `task_status_review`, or `decision_task`.

Validation behavior:

- Normalizes objective IDs.
- Picks task/request/correlation values from a prioritized set of sources.
- Calculates freshness from timestamps.
- Marks MIM state authoritative only when authority source belongs to the explicit authority set.
- Supports objective-level precedence without exact task match in a limited set of cases described below.

Overwrite and archival behavior:

- Overwrites the shared truth `.latest` path directly.
- Does not archive prior payloads on its own.

### Mutation and replay helpers

#### `scripts/Invoke-TODForcedExecutionReplay.ps1`

Artifacts written:

- `MIM_TOD_TASK_REQUEST.latest.json`
- `MIM_TO_TOD_TRIGGER.latest.json`
- `TOD_MIM_COMMAND_STATUS.latest.json`
- `listener_state.json`
- forced replay report under archive path

Authority behavior:

- This is not the normal authoritative writer for steady-state runtime.
- It is an explicit operator mutation surface that rewrites live request lineage to force replay.

Validation behavior:

- Refuses replay unless the current live request objective and task match the requested target.
- Requires explicit `-Force`.
- Mutates request and correlation lineage and updates listener replay state.

Overwrite and archival behavior:

- Overwrites live `.latest` files.
- Archives existing live artifacts before mutation.

### Mirror and syndication writers

#### `scripts/Copy-TODCurrentStateToContextSync.ps1`

Artifacts written include mirrored copies of:

- `TOD_MIM_INTEGRATION_STATUS.latest.json`
- `TOD_MIM_NEXT_ACTIONS.latest.json`
- `TOD_MIM_CURRENT_BUILD_STATE.latest.json`
- `TOD_MIM_OBJECTIVES.latest.json`
- `TOD_MIM_CONTRACT_ACCEPTANCE.latest.json`
- `TOD_MIM_CONTRACT_FORMAL_AGREEMENT.latest.json`
- `TOD_MIM_BRIDGE_SMOKE.latest.json`
- `TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json`
- `TOD_MIM_ARM_AUTHORITY_SMOKE.latest.json`
- `TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json`
- `TOD_MIM_SUPERVISED_EXECUTION.latest.json`
- `TOD_MIM_RECOVERY_WATCHDOG.latest.json`
- `TOD_MIM_WATCHDOG_DRIFT_GUARD.latest.json`
- `TOD_MIM_NEXT_STEP_CONSENSUS.latest.json`
- `TOD_MIM_NEXT_STEP_POLICY.latest.json`
- `TOD_MIM_CODEX_NEXT_STEPS.latest.json`
- `TOD_MIM_MANAGED_WORK.latest.json`
- `TOD_MIM_MANAGED_WORK_CLEANUP.latest.json`
- `MIM_TOD_HANDSHAKE_PACKET.latest.json`
- `MIM_TOD_TASK_REQUEST.latest.json`
- `MIM_CONTEXT_EXPORT.latest.json`
- `MIM_MANIFEST.latest.json`

Authority behavior:

- Pure mirror; not a source of truth.
- Copies source files into context-sync and writes a state index.

Validation behavior:

- No lineage validation beyond source existence and hash capture.

Overwrite and archival behavior:

- Overwrites copied targets.
- No archive behavior.

### Diagnostic and contract-state writers

These scripts write adjacent `TOD_MIM_*` state but should not be treated as canonical lane writers:

| Writer | Artifacts | Classification |
| --- | --- | --- |
| `scripts/Compare-TODMimBoundaryBaseline.ps1` | `TOD_MIM_BOUNDARY_DELTA.latest.json` | diagnostic diff |
| `scripts/Compare-TODMimExecutionDispatchBaseline.ps1` | `TOD_MIM_EXECUTION_DISPATCH_DELTA.latest.json` | diagnostic diff |
| `scripts/Invoke-TODMimBridgeSmoke.ps1` | `TOD_MIM_BRIDGE_SMOKE.latest.json` | bridge smoke evidence |
| `scripts/Invoke-TODMimRemoteBoundaryDiagnostics.ps1` | `TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json`, `TOD_MIM_REMOTE_REQUEST_PROBE.latest.json` | boundary diagnostics |
| `scripts/Invoke-TODMimArmAuthoritySmoke.ps1` | `TOD_MIM_ARM_AUTHORITY_SMOKE.latest.json`, `TOD_MIM_ARM_STATUS_UPLOAD_RECEIPT.latest.json` | ARM smoke/receipt |
| `scripts/Invoke-TODMimContractAcceptance.ps1` | contract receipt/rejection and `shared_state/TOD_MIM_CONTRACT_ACCEPTANCE.latest.json` | contract acceptance state |
| `scripts/Invoke-TODMimFormalContractAgreement.ps1` | `shared_state/TOD_MIM_CONTRACT_FORMAL_AGREEMENT.latest.json` | formal contract state |
| `scripts/Get-TODMimRuntimeContractBindingStatus.ps1` | reads binding/violation files and summarizes status | reader/reporter, not authoritative lane writer |

### Simulation and test-only writers

These produce valid artifact shapes but are not production authority surfaces:

| Writer | Artifacts | Classification |
| --- | --- | --- |
| `scripts/Invoke-TODMimExecutionSimulation.ps1` | request, ACK, result, decision, command status under scenario directories | simulation |
| `scripts/Invoke-TODMimListenerSmoke.ps1` | temporary request/go/review files and smoke outputs | smoke harness |
| `tests/*.ps1` and `test_*.py` fixtures | synthetic packet payloads | test-only |

## Stale Guard, High-Watermark, and Dedup Sources

### `listener_state.json`

Primary fields managed by `Start-TODMimPacketListener.ps1`:

- `last_processed_request_id`
- `last_processed_request_signature`
- `last_observed_request_id`
- `last_observed_task_id`
- `last_observed_correlation_id`
- `high_watermark_request_id`
- `high_watermark_objective_id`
- `high_watermark_ordinal`
- `high_watermark_sequence`
- `last_stale_guard`
- blocked-resume and coordination carry-forward fields
- scoped forced replay entries

Authority behavior:

- This is live listener memory and directly influences dedup, stale rejection, bounded replay, and command-status carry-forward.

### `TOD_LOOP_JOURNAL.latest.json`

Managed by `Add-LoopJournalEntry` in `Start-TODMimPacketListener.ps1`.

Stored signals include:

- `request_id`
- `objective_id`
- `ack_status`
- `execution_status`
- `retry_reason`
- cadence and retry weight fields
- regression signatures and readiness snapshots

Authority behavior:

- This journal is not just telemetry. `Get-ObjectiveHighWatermark` uses it through `Get-MaxObservedTaskOrdinal` to recover the highest known task ordinal per objective.
- When journal history outranks the current request ordering, the stale guard can reject a request and preserve a prior current-processing lane.

### High-watermark selection

`Update-TaskHighWatermark` updates state when:

- no prior watermark exists
- the candidate is for the same objective and has a newer sequence
- sequence is absent but ordinal is greater

`Get-ObjectiveHighWatermark` merges:

- state watermark from `listener_state.json`
- journal-derived watermark from `TOD_LOOP_JOURNAL.latest.json`

and can report a combined source of `listener_state_and_loop_journal`.

### Stale guard construction

`New-StaleGuardMetadata` records:

- decision
- reason `higher_authoritative_task_ordinal_active`
- objective id
- comparison basis
- current request ordinal and sequence
- high-watermark source, field, request id, ordinal, and sequence
- trigger sequence

This payload is then embedded in `TOD_MIM_COMMAND_STATUS.latest.json` and also persisted to `listener_state.last_stale_guard` unless explicitly cleared.

## `bridge_runtime.current_processing.task_id` Lifecycle

### Set

Primary live source:

- `Get-BridgeRuntimeStatus` in `Start-TODMimPacketListener.ps1` builds the runtime payload consumed by ACK, RESULT, DECISION, and COMMAND_STATUS.
- The live execution branch passes `-CurrentTaskId $requestTaskId -CurrentCorrelationId $requestCorrelationId`.
- The stale-backfill branch intentionally passes the high-watermark task id instead of the current request task id, which is how stale lineage can persist if journal/state watermark memory is wrong.

Other set points:

- `Invoke-TODForcedExecutionReplay.ps1` stamps replay command-status/trigger state with replay task lineage.
- test and simulation harnesses fabricate the same structure for validation.

### Preserved

- `Publish-CommandStatus` mirrors whichever `BridgeRuntime` payload it is handed.
- ACK, RESULT, and DECISION payloads all embed the same runtime object during a cycle.
- shared truth and some diagnostics read but do not rewrite this field directly.

### Cleared or replaced

- It is not explicitly nulled in the normal listener path.
- It changes only when a new `BridgeRuntime` payload is constructed from a different task.
- The stale-guard metadata may outlive a corrected current-processing task unless `listener_state.last_stale_guard` is explicitly cleared before success publication.

### Compared or validated

- `scripts/validate_tod_mim_runtime_packet.py` requires exact identity match for `bridge_runtime.current_processing.task_id` and `correlation_id` against expected values for ACK and RESULT packets.
- `scripts/Compare-TODMimExecutionDispatchBaseline.ps1` reads it into dispatch delta output.
- `scripts/Get-TODLightweightStateBus.ps1` reads it to determine whether bridge runtime matches expected task state.
- `scripts/Invoke-TODMimBridgeSmoke.ps1` reads it as a high-watermark source.

## Objective-Only Matching Without Exact Task Match

This is intentionally narrow and belongs only in reconciliation and recoupling, not in strict packet validation.

### Allowed in shared-truth reconciliation

`reconcile_tod_mim_shared_truth.py` allows objective-level precedence when:

- the MIM view has an authority source in `formal_program_truth`, `task_status_review`, or `decision_task`
- objectives match and MIM is active/blocked while TOD is not fresher or not completed with evidence
- or objectives differ and authoritative MIM is fresher than TOD

It also composes objective/task identity from `live_task_request_signal` only when `objective_authority_eligible` is true.

### Allowed in canonical recoupling

`Invoke-TODCanonicalLatestArtifactRecoupling.ps1` treats a payload as needing recoupling when:

- normalized objective differs from canonical objective
- task differs from canonical task

That means an objective can remain the same while task is replaced and the latest payload is recoupled onto the new canonical task.

### Not allowed in strict runtime packet validation

`validate_tod_mim_runtime_packet.py` enforces exact objective, task, request, correlation, and `bridge_runtime.current_processing` identity for ACK/RESULT runtime packets. Objective-only matching is not accepted there.

## Recommended Database Mapping

### Core runtime tables

| Table | Backing writers | Key columns | Notes |
| --- | --- | --- | --- |
| `tod_listener_command_status` | `Start-TODMimPacketListener.ps1` | `generated_at`, `request_id`, `task_id`, `correlation_id` | Stores command-status events and embedded stale-guard/runtime snapshots. |
| `tod_listener_execution_decisions` | `Start-TODMimPacketListener.ps1` | `generated_at`, `request_id`, `task_id` | Decision outcomes before execution. |
| `tod_listener_task_acks` | `Start-TODMimPacketListener.ps1` | `generated_at`, `request_id`, `task_id`, `correlation_id` | Strictly validated ACK packets. |
| `tod_listener_task_results` | `Start-TODMimPacketListener.ps1` | `generated_at`, `request_id`, `task_id`, `correlation_id` | Strictly validated RESULT packets. |
| `tod_listener_loop_journal` | `Start-TODMimPacketListener.ps1` | `timestamp`, `request_id`, `objective_id` | Includes cadence, retry, regression, and readiness signals; also used for high-watermark recovery. |
| `tod_listener_state_snapshots` | `Start-TODMimPacketListener.ps1` | `generated_at` or `written_at`, `high_watermark_request_id` | Snapshot storage for live listener memory; preserve each write if moved to DB. |

### Shared runtime tables

| Table | Backing writers | Key columns | Notes |
| --- | --- | --- | --- |
| `tod_execution_active_tasks` | `Invoke-TODCanonicalLatestArtifactRecoupling.ps1` | `generated_at`, `objective_id`, `task_id` | Canonical active task lane in shared runtime. |
| `tod_execution_results` | `Invoke-TODCanonicalLatestArtifactRecoupling.ps1` | `generated_at`, `objective_id`, `task_id` | Canonical execution result lane. |
| `tod_execution_truth` | `Invoke-TODCanonicalLatestArtifactRecoupling.ps1` | `generated_at`, `objective_id`, `task_id` | Canonical execution truth rows. |
| `tod_execution_validation_results` | `Invoke-TODCanonicalLatestArtifactRecoupling.ps1` | `generated_at`, `objective_id`, `task_id` | Validation summaries for shared runtime state. |
| `tod_activity_stream` | `Invoke-TODCanonicalLatestArtifactRecoupling.ps1` | `generated_at`, `objective_id`, `task_id` | Activity/event stream. |
| `tod_mim_shared_truth` | `reconcile_tod_mim_shared_truth.py` | `generated_at`, `objective_id`, `task_id`, `authority_source` | Reconciled truth surface with TOD/MIM precedence metadata. |

### Mirror and contract tables

| Table | Backing writers | Key columns | Notes |
| --- | --- | --- | --- |
| `tod_context_sync_index` | `Copy-TODCurrentStateToContextSync.ps1` | `generated_at`, `file_name` | Index of mirrored artifacts and hashes. |
| `tod_mim_contract_acceptance` | `Invoke-TODMimContractAcceptance.ps1` | `generated_at`, `contract_version` | Acceptance/rejection state. |
| `tod_mim_contract_agreements` | `Invoke-TODMimFormalContractAgreement.ps1` | `generated_at`, `contract_version` | Formal agreement and activation status. |
| `tod_mim_bridge_diagnostics` | smoke/boundary scripts | `generated_at`, `diagnostic_type` | Non-authoritative observability only. |
| `tod_artifact_supersedes` | `Invoke-TODCanonicalLatestArtifactRecoupling.ps1`, replay archive flows | `artifact_name`, `superseded_at`, `replacement_generated_at` | Tracks archived prior latest payloads. |

## Operational Conclusions

- The live runtime authority for task lineage is `Start-TODMimPacketListener.ps1`, not shared truth, not the context-sync mirror, and not the boundary diagnostics.
- `TOD_MIM_SHARED_TRUTH.latest.json` is authoritative only as a reconciled view. It is not the writer of ACK/result/command-status lineage.
- Objective-only matching is allowed only in reconciliation and recoupling. It should never be used to accept a runtime ACK or RESULT packet.
- `listener_state.json` and `TOD_LOOP_JOURNAL.latest.json` are part of the authority system because they directly influence stale-guard decisions and effective current-processing lineage.
- Any future DB migration should preserve a strict separation between:
  - immutable validated runtime packets
  - mutable listener memory
  - reconciled truth views
  - mirror and diagnostic outputs
