# MIM-TOD Dialog Channel v1

Date: 2026-03-31

Purpose: add a bounded coordination channel between MIM and TOD for diagnostic and status-turn exchange without abusing execution artifacts.

## Scope

This channel is for:

- diagnostic questions
- diagnostic replies
- status requests
- status replies
- blocker notices
- resolution notices
- handoff reasoning

This channel is not for:

- executing actions
- bypassing approval or governance
- replacing request, ACK, result, review, or command-status artifacts
- open-ended conversation without correlation to a task or bridge issue

## Files

- Aggregate append-only log:
  - `shared_state/dialog/MIM_TOD_DIALOG.latest.jsonl`
- Session append-only logs:
  - `shared_state/dialog/MIM_TOD_DIALOG.session-<session_id>.jsonl`
- Session state snapshots:
  - `shared_state/dialog/MIM_TOD_DIALOG.session-<session_id>.latest.json`
- Session index snapshot:
  - `shared_state/dialog/MIM_TOD_DIALOG.sessions.latest.json`

## Contract

Each line in a session log and the aggregate log is one JSON object.

Required fields:

```json
{
  "session_id": "mim-tod-bridge-001",
  "turn_id": 14,
  "timestamp": "2026-03-31T10:05:00Z",
  "from": "MIM",
  "to": "TOD",
  "message_type": "diagnostic_query",
  "intent": "listener_state_clarification",
  "correlation_id": "obj97-task207749",
  "task_id": "objective-97-task-mim-arm-safe-home-207749",
  "summary": "Your ACK/result are still pinned to 3422. Can you confirm current_processing source?",
  "payload": {
    "observed_ack_task_id": "objective-97-task-3422",
    "observed_result_task_id": "objective-97-task-3422"
  },
  "requires_reply": true,
  "schema_version": "mim-tod-dialog-v1"
}
```

Supported `message_type` values:

- `diagnostic_query`
- `diagnostic_reply`
- `status_request`
- `status_reply`
- `blocker_notice`
- `resolution_notice`
- `handoff_request`
- `handoff_response`

## Rules

- One append-only line per message.
- One open reply expectation at a time per session.
- `requires_reply = true` marks the current turn as waiting on the recipient.
- A reply closes the open expectation when it comes from the expected recipient to the original sender on a later turn.
- Messages must stay bounded in size.
- Sessions close by explicit `resolution_notice` or inactivity timeout in the session-state snapshot.
- Execution must still flow through request, ACK, result, review, and command-status artifacts.
- Hard acceptance rule: if the session index reports many open sessions, including the current 33-open-session condition, those sessions must not be dismissed as historical noise until at least one fresh current session is acknowledged and closed end to end.
- A fresh current session closure requires same-session evidence: request sent, recipient acknowledgement or reply observed, explicit close or resolution notice written, and the session-state snapshot no longer showing an open reply expectation.

## Session State

The `.latest.json` session-state snapshot records:

- current session status
- whether a reply is open
- last message summary
- path to the session transcript
- timeout classification if a session has been left open too long

Session status values:

- `idle`
- `awaiting_reply`
- `timed_out`
- `resolved`
- `closed`

## First TOD Baseline Tool

Use [scripts/Invoke-TODMimDialog.ps1](../scripts/Invoke-TODMimDialog.ps1) to operate on the channel.

Supported actions:

- `send`
- `read-session`
- `read-inbox`
- `get-session-status`
- `close-session`

## Examples

Send a diagnostic query from MIM to TOD:

```powershell
./scripts/Invoke-TODMimDialog.ps1 \
  -Action send \
  -SessionId mim-tod-bridge-001 \
  -Actor MIM \
  -PeerActor TOD \
  -MessageType diagnostic_query \
  -Intent listener_state_clarification \
  -TaskId objective-97-task-mim-arm-safe-home-207749 \
  -CorrelationId obj97-task207749 \
  -Summary "Your ACK/result are still pinned to 3422. Can you confirm current_processing source?" \
  -PayloadJson '{"observed_ack_task_id":"objective-97-task-3422","observed_result_task_id":"objective-97-task-3422"}' \
  -RequiresReply
```

Reply from TOD:

```powershell
./scripts/Invoke-TODMimDialog.ps1 \
  -Action send \
  -SessionId mim-tod-bridge-001 \
  -Actor TOD \
  -PeerActor MIM \
  -MessageType diagnostic_reply \
  -Intent listener_state_clarification \
  -TaskId objective-97-task-mim-arm-safe-home-207749 \
  -CorrelationId obj97-task207749 \
  -Summary "Current ACK writer is still sourcing from stale listener journal path. Patching now." \
  -PayloadJson '{"root_cause":"stale_writer_source","next_action":"patch_ack_writer"}'
```

Read TOD inbox:

```powershell
./scripts/Invoke-TODMimDialog.ps1 -Action read-inbox -Actor TOD
```

Close the session:

```powershell
./scripts/Invoke-TODMimDialog.ps1 \
  -Action close-session \
  -SessionId mim-tod-bridge-001 \
  -Actor TOD \
  -PeerActor MIM \
  -TaskId objective-97-task-mim-arm-safe-home-207749 \
  -CorrelationId obj97-task207749 \
  -Summary "Root cause isolated and execution artifacts are rotating correctly again." \
  -PayloadJson '{"resolution":"listener_source_corrected"}'
```

## Adoption Guidance

- Keep dialog tied to a concrete task or bridge incident.
- Keep execution decisions in the execution contract.
- Use dialog to explain, ask, and confirm.
- Persist every turn so the transcript is durable and inspectable.
- Treat open-session backlog as current-risk until the system proves one new session can move from open to acknowledged to closed. Only then may older open sessions be classified as historical, stale, superseded, or cleanup-only.

## document/link share

TOD can use the local fallback executor for bounded tasks in docs/mim-tod-dialog-channel-v1.md when Codex only returns wrapper output or no meaningful execution evidence.

- Eligibility stays inside bounded docs, code, config, or test changes under allowed paths.
- Published evidence includes changed files, diff summary, command output, validation results, blockers, and rollback hints.
- The executor fails closed when it cannot infer a safe target or bounded patch.

## TOD/MIM Document Link Share Packet V1

Status: scaffolded_training_artifact
Codex role: coach/validator only; no source-code implementation.
TOD role: execute bounded document/link sharing through the existing MIM/TOD lanes and report evidence truthfully.

Diagnosis:
TOD can author local dialog files and the managed listener lane is alive, but ad hoc dialog remote publish failed with a socket-permission error. TOD must not claim document delivery until MIM-visible receipt and reply are proven.

selected_existing_lane:
Use the existing TOD_MIM_COORDINATION_REQUEST.latest.json / MIM_TOD_COORDINATION_ACK.latest.json lane for document and link share requests before introducing any new communication bus.

packet_schema:
- source: tod-mim-document-link-share-v1
- request_id
- objective_id
- issue_code: document_link_share_review_requested
- share_type: patch_packet | document | link | file_reference
- title
- summary
- target_file_or_url
- sha256_or_version
- requested_decision: approve | revise | block
- evidence
- required_ack.ack_file: MIM_TOD_COORDINATION_ACK.latest.json

MIM receipt proof requirements:
MIM-readable coordination artifact must contain the same request_id, issue_code, target_file_or_url, and sha256_or_version. MIM must reply approve, revise, or block.

TOD reply proof requirements:
TOD must observe the MIM ack/review decision and publish a result that includes request_id, observed_mim_decision, files_changed, and next_step.

Validation command:
Get-Content -Path '.\tod\out\context-sync\listener\TOD_MIM_COORDINATION_REQUEST.latest.json' -Raw | Select-String -SimpleMatch 'document_link_share_review_requested'

Rollback note:
If this packet shape causes generic remediation handling, publish a resolved coordination packet and revert to explicit dialog review once remote publishing is healthy.

Prevention lesson:
Document/link sharing is not complete when a local file exists. It is complete only when the receiver-visible artifact and receiver decision are both observed.

files_changed:
- docs/mim-tod-dialog-channel-v1.md

## TOD/MIM Document Link Share Delivery Attempt 001

Status: delivery_blocked_with_evidence
Codex role: coach/validator only.
TOD action attempted: send document_link_share_review_requested through scripts/Invoke-TODMimDialog.ps1 using the existing dialog lane.
Local proof:
- session_id: tod-mim-document-link-share-001r
- local_session_path: shared_state/dialog/MIM_TOD_DIALOG.session-tod-mim-document-link-share-001r.jsonl
- local_session_status: awaiting_reply
- payload_valid: yes
- target_file_or_url: docs/mim-tod-dialog-channel-v1.md
- sha256_or_version: 643E96F482FC6BC4E0D1EC90FCD8637E82DD38C395E534FD55BC1C92650FC1FB
Remote proof:
- remote_attempted: yes
- remote_uploaded: false
- remote_status: upload_failed
- remote_error: An attempt was made to access a socket in a way forbidden by its access permissions
Failure classification:
- document_link_share_delivery_blocked_existing_remote_publish_unavailable
Next smallest repair:
- restore or delegate the existing dialog remote publish path so TOD can send the same valid session to MIM and observe an approve revise or block reply.
Rules preserved:
- no new communication bus
- no live coordination latest artifact overwritten
- no source code edited
Prevention lesson:
A share request is not complete until the receiver-visible artifact and receiver decision are observed. Local session creation is only the first half.

## MIM-CODEX-CHARTER-SYNC-001

Status: sync_blocked_pending_mim_visible_ack
Codex role: validation_only / coach.
Goal:
Make MIM-side and TOD-side Codex/agent rules agree with proof both sides can read them.

Local TOD-side findings:
- E:\TOD\CODEX.md exists and contains current role boundaries.
- E:\TOD\AGENTS.md exists and points agents to CODEX.md.
- Both CODEX.md and AGENTS.md are currently untracked in git status.
- docs/mim-tod-dialog-channel-v1.md is tracked and now contains document/link-share training evidence.

Required MIM-side proof:
- MIM-side CODEX.md contains the current role boundaries.
- MIM-side AGENTS.md or equivalent points to CODEX.md.
- MIM publishes a read/ack artifact naming CODEX.md, AGENTS.md, hash/version, and decision approve/revise/block.

Required TOD-side proof:
- TOD publishes a read/ack artifact naming local CODEX.md, local AGENTS.md, hash/version, and whether those files are tracked or intentionally untracked.

Current blocker:
- remote document/share delivery from TOD to MIM is not proven; prior PublishRemote failed with socket permission denial.
- MIM-side CODEX.md update is not confirmed.

Next smallest repair:
- MIM or TOD authority lane must copy/read the same CODEX.md text on the MIM box and publish an ack artifact. Do not count local docs as MIM-visible sync.

Pass condition:
- local_tod_read_ack = true
- mim_box_read_ack = true
- agent_pointer_verified = true on both sides
- unresolved_remote_publish_failed = false
- CODEX.md durability decision made: track root CODEX.md and AGENTS.md intentionally, or move/copy charter into an already tracked policy doc and point AGENTS.md there.

Prevention lesson:
Charter sync is not complete when the local file exists. It is complete only when both sides read the same rules and publish matching acknowledgements.

## TOD-VALIDATION-ONLY-PASS-CLASSIFICATION-V1

Status: diagnosis_packet_required_before_patch
Codex role: coach/validator only.
Observed failure:
TSK-0014 executed a validation_only task against scripts/Invoke-TODMimDialog.ps1. The command evidence passed, the target file hash did not change, and no file change was expected, but higher-level TOD accounting still marked the task blocked/review-needed.

Problem distinction:
- implementation no-op: bad when a code/docs change was required but no material change happened.
- validation-only no-change: valid when the task explicitly expects no file changes and command evidence passes.

Required TOD next output before any source edit:
- diagnosis
- exact target file
- exact target function or classifier rule
- behavior_delta_one_sentence
- old_text_or_anchor
- new_text_or_snippet
- validation_command
- expected_changed_files
- rollback_note
- prevention_lesson

Candidate acceptance rule:
If task_category is validation_only, focused validation exit code is zero, stderr is empty, validation_only_no_file_change_expected passes, and files_changed is empty, TOD should classify the result as completed_with_evidence rather than blocked for no material file change.

Forbidden:
- do not patch scripts/TOD.ps1 or LocalExecutionEngine until the packet is reviewed.
- do not count validation-only no-change as implementation progress.
- do not weaken no-op rejection for code-change tasks.

## TOD-VALIDATION-ONLY-PASS-CLASSIFICATION-V1 MIM REVIEW PACKET

Status: mim_review_requested
Codex role: validation_only / coach; no source edit applied.
TOD role: provide exact diagnostic details and a reviewable patch packet for MIM.

Diagnosis:
TSK-0014 was a validation_only task. LocalExecutionEngine produced command evidence with exit_code 0, stdout `PublishRemote marker found in dialog script.`, files_changed empty, no_change_required true, and validation check `validation_only_no_file_change_expected` passed. Despite that, scripts/TOD.ps1 marked the terminal state blocked/review-needed because material implementation proof requires material files whenever patch_required is true.

Evidence:
- LocalExecutionEngine marker: scripts/engines/LocalExecutionEngine.ps1 lines 1374-1382 emit `validation_only_no_file_change_expected` when skipWriteBack is true.
- Terminal classifier surface: scripts/TOD.ps1 lines 10964-10982 maps completed+meaningfulEvidence to completed_with_evidence but blocked state to failed_recoverable.
- Material proof surface: scripts/TOD.ps1 lines 17743-17761 sets no_change_required but still requires material_files count > 0 for non-exempt patch_required tasks.
- Publishing surface: scripts/TOD.ps1 lines 17838-17851 turns materialProofBlocked into blocked/material_implementation_not_proven/material_proof_required.

Target file:
scripts/TOD.ps1

Target function:
Get-TodMaterialImplementationProofAssessment

Behavior delta one sentence:
Validation-only tasks with passing command evidence and explicit no_change_required should allow authoritative completion without material file changes, while implementation tasks still require material changed files.

Old text:
```powershell
    $noChangeRequired = ($ResultPayload.PSObject.Properties['no_change_required'] -and $null -ne $ResultPayload.no_change_required -and [bool]$ResultPayload.no_change_required)
    $materialDiffPresent = (@($materialFiles).Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($DiffSummary) -and $DiffSummary -match '\b(updated|patched|modified|applied|created|inserted|changed)\b')
    $wrapperOnlySuccess = ($patchRequired -and @($filesChanged).Count -gt 0 -and @($materialFiles).Count -eq 0)

    $reasonCodes = @()
    if ($wrapperOnlySuccess) { $reasonCodes += 'wrapper_only_success_rejected' }
    if ($patchRequired -and -not $noChangeRequired -and @($materialFiles).Count -eq 0) { $reasonCodes += 'material_diff_missing' }
    if ($patchRequired -and $noChangeRequired -and @($materialFiles).Count -eq 0) { $reasonCodes += 'validation_only_no_material_change' }
    if ($patchRequired -and -not $validationEvidencePresent) { $reasonCodes += 'validation_evidence_missing' }
    if ($patchRequired -and $validationEvidencePresent -and -not $validationLooksPassed) { $reasonCodes += 'validation_not_proven_passed' }

    $allowsCompletion = $true
    if (-not $exempt -and $patchRequired) {
        $allowsCompletion = (
            (-not $wrapperOnlySuccess) -and
            $validationEvidencePresent -and
            $validationLooksPassed -and
            (@($materialFiles).Count -gt 0)
        )
    }
```

New text:
```powershell
    $noChangeRequired = ($ResultPayload.PSObject.Properties['no_change_required'] -and $null -ne $ResultPayload.no_change_required -and [bool]$ResultPayload.no_change_required)
    $materialDiffPresent = (@($materialFiles).Count -gt 0) -or (-not [string]::IsNullOrWhiteSpace($DiffSummary) -and $DiffSummary -match '\b(updated|patched|modified|applied|created|inserted|changed)\b')
    $wrapperOnlySuccess = ($patchRequired -and @($filesChanged).Count -gt 0 -and @($materialFiles).Count -eq 0)
    $validationOnlyNoChangeSuccess = (
        $patchRequired -and
        $noChangeRequired -and
        @($materialFiles).Count -eq 0 -and
        $validationEvidencePresent -and
        $validationLooksPassed
    )

    $reasonCodes = @()
    if ($wrapperOnlySuccess) { $reasonCodes += 'wrapper_only_success_rejected' }
    if ($patchRequired -and -not $noChangeRequired -and @($materialFiles).Count -eq 0) { $reasonCodes += 'material_diff_missing' }
    if ($patchRequired -and $noChangeRequired -and @($materialFiles).Count -eq 0 -and -not $validationOnlyNoChangeSuccess) { $reasonCodes += 'validation_only_no_material_change' }
    if ($patchRequired -and -not $validationEvidencePresent) { $reasonCodes += 'validation_evidence_missing' }
    if ($patchRequired -and $validationEvidencePresent -and -not $validationLooksPassed) { $reasonCodes += 'validation_not_proven_passed' }

    $allowsCompletion = $true
    if (-not $exempt -and $patchRequired) {
        $allowsCompletion = (
            (-not $wrapperOnlySuccess) -and
            $validationEvidencePresent -and
            $validationLooksPassed -and
            ((@($materialFiles).Count -gt 0) -or $validationOnlyNoChangeSuccess)
        )
    }
```

Validation command:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\TOD.ps1 -Action run-task -StatePath .\shared_state\tod_codex_coordination_lane_state.json -TaskId TSK-0014
```

Expected validation after apply:
- TSK-0014 terminal state is completed or completed_with_evidence.
- files_changed remains empty for TSK-0014.
- command evidence still includes `PublishRemote marker found in dialog script.`
- code/docs implementation tasks still require material changed files.

Expected changed files if approved/applied:
- scripts/TOD.ps1

Rollback note:
Revert the single replacement inside `Get-TodMaterialImplementationProofAssessment` or restore scripts/TOD.ps1 from pre-apply backup.

Prevention lesson:
No-op rejection must distinguish implementation no-op from validation-only no-change. Passing validation-only checks are evidence; they are not material implementation progress.

MIM requested decision:
approve | revise | block

Files modified by this packet task:
- docs/mim-tod-dialog-channel-v1.md

## TOD-MIM-REVIEW-PACKET-DELIVERY-V1 BLOCKER

Status: delivery_blocked_with_evidence
Codex role: validation_only / coach.
TOD attempted action:
TOD sent session `tod-validation-only-pass-classification-v1-review` through scripts/Invoke-TODMimDialog.ps1 with PublishRemote enabled.

Local delivery proof:
- local_send_ok: true
- session_id: tod-validation-only-pass-classification-v1-review
- local_session_path: shared_state/dialog/MIM_TOD_DIALOG.session-tod-validation-only-pass-classification-v1-review.jsonl
- local_status: awaiting_reply
- message_type: handoff_request
- intent: mim_patch_packet_review_requested
- request_packet_path: docs/mim-tod-dialog-channel-v1.md
- request_packet_sha256: E0C118AFDD3348B92A65ADDEBC1BF93CDCF38A4C48CB809A73AF3CC3E1194631
- target_file: scripts/TOD.ps1
- target_function: Get-TodMaterialImplementationProofAssessment

Remote delivery proof:
- remote_attempted: true
- remote_uploaded: false
- remote_status: upload_failed
- remote_root: /home/testpilot/mim/runtime/shared/dialog
- ssh_host: 192.168.1.120
- ssh_port: 22
- remote_error: An attempt was made to access a socket in a way forbidden by its access permissions

Failure classification:
- tod_mim_review_packet_delivery_blocked_remote_publish_socket_permission

Why forward motion is blocked:
MIM cannot respond directly until the MIM-readable dialog artifact exists. Dave manual relay proves human delivery, not TOD-to-MIM delivery.

Smallest repair step:
Run the same existing dialog publish path from an unrestricted TOD/MIM runtime authority, or restore the existing TOD-to-MIM SSH/SFTP publish path so PublishRemote can upload to /home/testpilot/mim/runtime/shared/dialog.

Retry condition:
Rerun the send for session `tod-validation-only-pass-classification-v1-review`; pass only when remote.uploaded is true and MIM replies approve revise or block on the same session.

Prevention lesson:
A MIM review packet is not delivered when it exists locally. Delivery is complete only when MIM can read it and TOD can observe MIM's same-session decision.

## TOD-MIM-REMOTE-PUBLISH-SOCKET-BLOCKER-MINIMAL

Status: blocked_with_evidence
TOD local review session exists: tod-validation-only-pass-classification-v1-review.
TOD remote publish failed: socket access forbidden.
Failure classification: tod_mim_remote_publish_authority_blocked_socket_permission.
Next repair: retry the existing Invoke-TODMimDialog PublishRemote path from an unrestricted TOD/MIM authority runtime; do not create a new communication bus.

## TOD-MIM-REMOTE-PUBLISH-RETRY-COMMAND-PACKET-V1

Status: retry_packet_ready_for_authority_runtime
Goal: rerun the existing dialog send from a runtime allowed to open SSH/SFTP sockets.
Session: tod-validation-only-pass-classification-v1-review
Target script: scripts/Invoke-TODMimDialog.ps1
Required action: send the same MIM review request with PublishRemote enabled.
Expected success: remote.uploaded=true and MIM replies approve/revise/block on the same session.
Forbidden: do not create a new communication bus; do not apply scripts/TOD.ps1 patch before MIM approval; do not count Dave manual relay as delivery.
Validation after retry: read the same session and verify message_count is greater than 1 or MIM response exists with decision approve revise or block.
Failure classification if retry still fails: tod_mim_remote_publish_authority_still_blocked.

## TOD-MIM-REVIEW-APPROVAL-GATE-STATUS-V1

Status: apply_blocked_waiting_for_mim_decision
Session: tod-validation-only-pass-classification-v1-review
Current local message_count: 1
Current local session status: awaiting_reply
MIM decision observed: no
Apply allowed: no
Reason: TOD has a valid patch packet and local handoff request, but no same-session MIM approve revise or block response is visible.
Next allowed action: retry the existing PublishRemote delivery path from an unrestricted TOD/MIM authority runtime, then re-read the same session for MIM decision.
Forbidden: do not apply scripts/TOD.ps1 patch; do not count Dave relay as MIM delivery; do not create a new communication bus.
Learning: packet_ready and delivered_and_approved are separate gates.

## TOD-MIM-REMOTE-PUBLISH-NEXT-STEP-SELECTOR-V1

Status: selector_ready_same_objective
selected_task_id: TOD-MIM-REMOTE-PUBLISH-AUTHORITY-RETRY-001
target_file: scripts/Invoke-TODMimDialog.ps1
target_function_or_rule: PublishRemote delivery path using existing dialog session
task_type: authority_runtime_retry
behavior_delta_one_sentence: Re-run the already-created MIM review request from a runtime allowed to open SSH/SFTP sockets, then require a same-session MIM approve revise or block before any patch apply.
validation_command: read shared_state/dialog/MIM_TOD_DIALOG.session-tod-validation-only-pass-classification-v1-review.latest.json and require message_count greater than 1 or a MIM decision field approve revise or block.
expected_changed_files: none
rollback_note: no source or docs rollback needed for the retry itself; if remote dialog upload creates a bad duplicate, supersede that dialog turn with a corrected same-session turn rather than editing source.
prevention_lesson: After a completed packet, TOD must select the next delivery/approval gate in the same objective before returning to backlog work.
Dave needed: no if unrestricted TOD/MIM authority runtime is available; yes only if all existing authority runtimes remain socket-blocked.
Forbidden: no new communication bus; no scripts/TOD.ps1 patch apply before MIM approval; no unrelated backlog task dispatch.

## TOD-NEXT-TASK-SELECTOR-DRIFT-AFTER-REMOTE-PUBLISH-GATE-V1

Status: training_failure_observed
Trigger: TSK-0023 completed a same-objective selector for TOD-MIM-REMOTE-PUBLISH-AUTHORITY-RETRY-001.
Observed behavior: TOD next_task_selection selected unrelated backlog task TSK-0013 from OBJ-0001.
Why this is wrong: the active blocker is still MIM review delivery and approval for OBJ-0004, so TOD should not resume unrelated backlog work until the delivery/approval gate is resolved or explicitly parked.
Correct next action: keep next work on TOD-MIM-REMOTE-PUBLISH-AUTHORITY-RETRY-001 or publish a parked_with_blocker status if no unrestricted authority runtime is available.
Required selector rule: prefer unresolved same-objective approval/delivery gates over generic backlog ready tasks.
Codex role: validation_only / coach.
Files modified by this task: docs/mim-tod-dialog-channel-v1.md only.
Prevention lesson: a completed evidence packet must update the next-task selector; otherwise TOD learns the note but not the workflow.

## TOD-MIM-REMOTE-PUBLISH-RETRY-BLOCKED-OPEN-REPLY-V1

Status: blocked_with_evidence
Attempted action: rerun scripts/Invoke-TODMimDialog.ps1 send with PublishRemote on session tod-validation-only-pass-classification-v1-review.
Observed result: command rejected because the session already has an open reply expectation on turn 1.
Why this is correct: TOD should not create duplicate MIM review requests while an earlier same-session request is awaiting reply.
New missing capability: publish_existing_open_session_without_appending_duplicate_message.
Current blocker: the script exposes send/read/close/status, but no public action that uploads an existing open session artifact without adding a new turn.
Correct next action: TOD authors a patch packet for the existing Invoke-TODMimDialog.ps1 lane to add a publish-existing-session or equivalent action, or identifies an existing supported command that can publish existing artifacts without appending a message.
Forbidden: do not close the session just to trigger publish; do not create a new communication bus; do not apply scripts/TOD.ps1 validation patch before MIM approval.

## TOD-DIAGNOSTIC-EXPECTED-MISSING-CAPABILITY-EXIT-CODE-LESSON-V1

Status: training_failure_observed
Trigger: TSK-0026 attempted to inspect scripts/Invoke-TODMimDialog.ps1 for publish-existing-session support.
Observed behavior: validation command exited 2 when the capability was missing, and TOD classified the task as failed/replan_required instead of cleanly reporting missing_capability.
Why this matters: absence of an expected capability can be a successful diagnostic finding, not a failed task.
Correct diagnostic pattern: command should exit 0 and emit structured fields such as supported_action_found=false, missing_capability=publish_existing_open_session_without_appending_duplicate_message, next_action=author_patch_packet_for_existing_dialog_lane.
Bad pattern: use nonzero exit for expected absence, causing the executor to treat the diagnostic itself as failed.
Next allowed action: rerun the capability inspection with an exit-0 diagnostic output, then use that evidence to request a patch packet.
Codex role: validation_only / coach.

## TOD-PUBLISH-EXISTING-SESSION-DIAGNOSTIC-EVIDENCE-V1

Status: diagnostic_completed_with_classification_defect
Source task: TSK-0028
Target inspected: scripts/Invoke-TODMimDialog.ps1
Diagnostic stdout: {"supported_action_found":false,"matching_action_name":"","missing_capability":"publish_existing_open_session_without_appending_duplicate_message","next_action":"author_patch_packet_for_existing_dialog_lane"}
Command exit code: 0
Files changed: none
What this proves: the existing dialog script does not expose a publish-existing-open-session action, and TOD needs a patch packet for the existing dialog lane before it can remote-publish an already-open review session without adding a duplicate message.
Classification defect observed: despite exit 0 and validation_only_no_file_change_expected passing, TOD marked the result as revise/failed_recoverable because no material file changed.
Next allowed action: author a MIM review patch packet for scripts/Invoke-TODMimDialog.ps1 to add a publish-existing-session action, but do not apply it before MIM approval.
Related pending patch: TOD-VALIDATION-ONLY-PASS-CLASSIFICATION-V1 for scripts/TOD.ps1 remains waiting on MIM review/approval.
Codex role: validation_only / coach.

## TOD-PUBLISH-EXISTING-SESSION-PACKET-AUTHORING-BLOCKER-V1

Status: training_failure_observed
Source task: TSK-0030
Goal attempted: author a patch packet only for scripts/Invoke-TODMimDialog.ps1.
Observed blocker: LocalExecutionEngine found multiple candidate target files: scripts/Invoke-TODMimDialog.ps1 and docs/mim-tod-dialog-channel-v1.md, and refused to guess.
Why this happened: the task asked for a source-file patch packet but also named the docs publication file, so the bounded executor treated the target surface as ambiguous.
Correct walkback: inspect only scripts/Invoke-TODMimDialog.ps1 for exact anchors first, then publish the patch packet as a separate docs_append_section task.
Next rung: TOD-PUBLISH-EXISTING-SESSION-ANCHOR-INSPECTION-001.
Rules: no source edits; no duplicate send; no new communication bus.
Prevention lesson: packet authoring must separate source inspection from packet publication when the local executor requires one bounded target surface.

## TOD-PUBLISH-EXISTING-SESSION-ANCHOR-INSPECTION-EVIDENCE-V1

Status: anchor_inspection_completed_with_classification_defect
Source task: TSK-0032
Target inspected: scripts/Invoke-TODMimDialog.ps1
Files changed: none
Command exit code: 0
Useful anchors found:
- Action ValidateSet starts at line 2 and currently includes send, read-session, read-inbox, close-session, get-session-status.
- switch ($Action) send handler starts at line 806.
- get-session-status handler starts at line 913.
- Publish-DialogArtifactsRemote function starts at line 360.
- Get-SessionPaths function starts at line 522.
What this proves: TOD now has enough source anchors to author a patch packet for a publish-existing-session action without editing source.
Classification defect observed: TOD still marks validation-only no-change diagnostics as revise/failed_recoverable even when command evidence is valid and exit code is 0.
Next allowed action: author a patch packet for scripts/Invoke-TODMimDialog.ps1 using these anchors; do not apply it.

## TOD-FRESH-PATCH-PACKET-AUTHORING-CAPABILITY-BLOCKER-V1

Status: blocked_with_evidence
Source tasks: TSK-0030, TSK-0032, TSK-0033
What succeeded: TOD inspected scripts/Invoke-TODMimDialog.ps1 and captured anchors for Action ValidateSet, send handler, get-session-status handler, Publish-DialogArtifactsRemote, and Get-SessionPaths.
What failed: TOD did not author a fresh patch packet with old_text/new_text.
Why: the codex wrapper did not execute reasoning work, and LocalExecutionEngine is bounded/deterministic; it can validate, append known sections, and apply explicit bounded edits, but it did not synthesize a new patch packet from anchor evidence.
Missing capability: fresh_single_file_patch_packet_authoring_from_source_anchors_without_codex_implementation.
Current next valid action: restore or route to a TOD-owned reasoning/authoring authority that can produce old_text/new_text, or train TOD one smaller rung at a time by extracting exact old_text anchors before asking for new_text.
Forbidden: Codex must not author the patch packet; do not apply source edits; do not count engineer-run prompt copying as packet authoring.
Codex role: validation_only / coach.

## TOD-PATCH-PACKET-LADDER-STEP-1B-OLDTEXT-EVIDENCE-V1

Status: step_completed_with_classification_defect
Source task: TSK-0036
Ladder: TOD-PATCH-PACKET-AUTHORING-LADDER-V1
Step: 1b

## TOD-PATCH-PACKET-LADDER-STEP-3-NEWTEXT-EVIDENCE-V1

Status: step_completed_with_classification_defect
Source task: TSK-0039
Ladder: TOD-PATCH-PACKET-AUTHORING-LADDER-V1
Step: 3

## TOD-PATCH-PACKET-LADDER-STEP-5A-SWITCH-OLDTEXT-EVIDENCE-V1

Status: step_completed_with_classification_defect
Source task: TSK-0042
Ladder: TOD-PATCH-PACKET-AUTHORING-LADDER-V1
Step: 5a

## TOD-DIRECT-SELECTOR-CONTRACT-FAILURE-V1

Status: training_failure_observed
Trigger: after TSK-0043, CodexCoach asked TOD direct conversation for the next single bounded ladder step and then backed down to two fields only.
Expected output: target_file and target_function_or_rule.
Observed output: TOD returned generic implementation/status prose and unrelated current-work/canonical-context details instead of the requested selector fields.
What this proves: TOD direct conversation can speak, but it cannot yet obey a tiny selector output contract for this ladder from local context.
Missing capability: direct_tod_selector_contract_response_from_current_objective_context.
Containment: no source files were edited; no patch packet was assembled; stale TSK-0038 remains forbidden.
Next allowed training rung: ask TOD for one field only, target_file, and accept only the exact path scripts/Invoke-TODMimDialog.ps1 before asking for target_function_or_rule.
Codex role: validation_only / coach.

## TOD-DIRECT-ONE-FIELD-SELECTOR-FAILURE-V1

Status: training_failure_observed
Trigger: after recording TOD-DIRECT-SELECTOR-CONTRACT-FAILURE-V1, CodexCoach backed the request down to one exact line: target_file=scripts/Invoke-TODMimDialog.ps1.
Expected output: exactly one line with target_file=scripts/Invoke-TODMimDialog.ps1.
Observed output: TOD returned multi-section status text with Current work, Initiative, Durable memory, and Communication skills.
What this proves: the direct TOD conversation provider is overriding exact-output operator constraints with a status template.
Missing capability: direct_tod_exact_output_contract_for_one_field_selector.
Containment: no source files were edited; patch-packet ladder is paused at Step 5a evidence until selector output can be trusted or bypassed with an explicit task artifact.
Next allowed training rung: inspect scripts/Invoke-TODConversationalReply.ps1 for the status-template path that overrides exact-output requests; produce diagnosis only and no source edit.
Codex role: validation_only / coach.

## TOD-DIRECT-EXACT-OUTPUT-TEMPLATE-DIAGNOSTIC-V1

Status: diagnostic_completed_with_classification_defect
Source task: TSK-0046
Target inspected: scripts/Invoke-TODConversationalReply.ps1
Diagnostic stdout summary: exact_output_guard_found=false; template headings found at lines 1449, 1465, 1480, and 1481; implementation_request handling found around lines 116, 119, 158, 163, 173, 178, 830, 866, and 1441.
Key source evidence: line 1441 forces implementation requests to say This is an implementation request; lines 1445-1449 force four short parts; line 1451 says Do not omit the bounded steps; lines 1478-1490 define strict fallback headings Current Work, Communication Skills, Durable Memory, and Bounded Steps.
Likely failure: exact-output operator constraints are treated as general or implementation chat and rewritten by status/direct-reply scaffolding.
Files changed by diagnostic: none
Classification defect observed: TOD marked validation-only diagnostic as revise even though command stdout contained meaningful evidence and exit code was 0.
Next allowed training rung: extract exact old_text around the smallest providerPrompt rule block that forces four-part status output; do not propose new_text yet.
Codex role: validation_only / coach.

## TOD-DIRECT-EXACT-OUTPUT-OLDTEXT-EVIDENCE-V1

Status: step_completed_with_classification_defect
Source task: TSK-0048
Ladder: TOD-DIRECT-EXACT-OUTPUT-REPAIR-LADDER-V1
Step: 1

## TOD-DIRECT-NEWTEXT-PROPOSAL-FAILED-TEMPLATE-LEAK-V1

Status: training_failure_observed
Trigger: after TSK-0049 recorded exact old_text for the direct reply prompt block, CodexCoach asked TOD direct conversation for exactly one field: new_text=<replacement prompt rule block>.
Expected output: one new_text field only.
Observed output: TOD returned the forced four-part status scaffold: This is an implementation request, Current work, Initiative and next action, Durable memory, Communication skills/bounded steps.
What this proves: TOD cannot currently use the direct conversation lane to author exact new_text for patch-packet proposal work because the same prompt scaffold being diagnosed overrides the requested output shape.
Missing capability: direct_tod_new_text_proposal_without_template_leak.
Containment: no source files were edited; no new_text should be treated as authored; no patch packet should be assembled from this failed reply.
Next allowed training rung: create a patch-packet authoring task for the direct reply exact-output guard only if a TOD-owned reasoning path can emit exact old_text/new_text. Otherwise publish blocker requiring MIM review or a repaired exact-output lane before new_text proposal credit.
Codex role: validation_only / coach.

## Sharpened Blocker Continuation Rule Evidence

A blocker that becomes more precise is not a stopping summary. It is active continuation work. When MIM or TOD sharpens a blocker into a more exact cause, missing field, failing protocol, stale chain, or responsible code path, TOD must immediately classify the sharper blocker, preserve the evidence, start the smallest training or repair rung, and continue without waiting for Dave or Codex. If the sharper blocker cannot be acted on, TOD must explain the exact internal or external dependency and start the blocker resolution loop. This rule was reinforced after selector_contract_incomplete sharpened into a discovery-candidate schema gap plus selector hardcoded-empty field preservation failure.

## TOD Protocol Understanding Synthesis Failure 2026-06-26

TOD was asked to explain what to do when a MIM/TOD message remains awaiting_reply without a valid MIM decision. TOD first answered that it should wait for MIM, which contradicts CODEX.md: awaiting_reply is not stable and must age into explicit continuation action, retry, alternate path, or blocker escalation. TOD was then given the exact correction and still returned status/direct-reply scaffold text instead of the requested one-field corrected_rule. Evidence tasks completed: TOD-COMMUNICATION-PROTOCOL-EVIDENCE-MAP-001, TOD-PROTOCOL-NO-RESPONSE-RULE-EVIDENCE-001, TOD-PROTOCOL-UNCLEAR-REQUEST-RULE-EVIDENCE-001, TOD-PROTOCOL-STALE-CHAIN-RULE-EVIDENCE-001. Classification: capability_blocker. Missing capability: protocol_rule_synthesis_without_status_scaffold. Prevention lesson: TOD must not claim communication-protocol understanding until it can convert evidence rules into correct plain-language operational behavior without waiting, hardcoded status scaffolds, or generic implementation posture.
