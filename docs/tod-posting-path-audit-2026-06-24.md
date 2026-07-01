# TOD Posting Path Audit - 2026-06-24

## Purpose

Audit where local TOD posts data for MIM, which paths are authoritative, which paths are mirrors or side channels, and why TOD can appear to post successfully while MIM does not receive or act on the data.

This audit does not create a new communication tool or repair path. It only maps the existing paths and identifies the current wrong-path risks.

## Executive Finding

TOD is posting to at least four different local or remote surfaces:

1. Local dialog files under `shared_state/dialog`.
2. Remote dialog files under `/home/testpilot/mim/runtime/shared/dialog`.
3. Local listener stage files under `tod/out/context-sync/listener`.
4. Shared latest artifacts under local `runtime/shared`, local mirror `tmp_remote_mim/runtime/shared`, and remote `/home/testpilot/mim/runtime/shared`.

The active MIM task, result, decision, Studio, UI, and packet-listener consumers mostly use `/home/testpilot/mim/runtime/shared/*.latest.json`, not the dialog subdirectory. The dialog lane is a side conversation surface. It is not the execution/reporting authority.

Current risk: TOD can post a blocker, training note, or MIM question into `shared_state/dialog` or `/home/testpilot/mim/runtime/shared/dialog` and believe it notified MIM, while MIM's active operational consumers continue reading only `/home/testpilot/mim/runtime/shared/TOD_MIM_*.latest.json` and `MIM_TOD_*.latest.json`.

## Authoritative Surface Assessment

| Surface | Path | Current role | Authority status |
| --- | --- | --- | --- |
| MIM/TOD live task bridge | `/home/testpilot/mim/runtime/shared/*.latest.json` | MIM writes requests/triggers; TOD writes ACK/result/decision/status; MIM UI and Studio consume these | Authoritative for execution and reporting |
| TOD local listener stage | `tod/out/context-sync/listener/*.latest.json` | TOD local copy of MIM request and TOD outputs | Local working/staging copy, not remote proof by itself |
| TOD local runtime shared | `runtime/shared/*.latest.json` | TOD local execution/activity/selection artifacts | Local canonical TOD artifact surface; remote proof only after publish |
| Local remote mirror | `tmp_remote_mim/runtime/shared/*.latest.json` | Local mirror of remote MIM shared root | Mirror/simulation, not proof MIM received data |
| Dialog channel | `shared_state/dialog/MIM_TOD_DIALOG.*` | Local append-only MIM/TOD diagnostic conversation | Side channel; not execution authority |
| Remote dialog channel | `/home/testpilot/mim/runtime/shared/dialog/MIM_TOD_DIALOG.*` | MIM-readable dialog mirror | Side channel; stale in current evidence |
| MIM ARM status root | `/home/testpilot/mim_arm/runtime/shared` | Primary upload for TOD status in shared-state sync | MIM ARM status surface; MIM still needs mirror in `/home/testpilot/mim/runtime/shared` |
| Message ledger DB | `runtime/shared/TOD_MIM_MESSAGE_LEDGER.sqlite3` | Observe-only shadow ledger when enabled | Not current authority; DB file missing locally |

## Script-Level Map

### 1. `scripts/Invoke-TODMimDialog.ps1`

Purpose: bounded diagnostic/status dialog channel.

Local default:

- `DialogDir = shared_state/dialog`
- Aggregate log: `shared_state/dialog/MIM_TOD_DIALOG.latest.jsonl`
- Session log: `shared_state/dialog/MIM_TOD_DIALOG.session-<session>.jsonl`
- Session state: `shared_state/dialog/MIM_TOD_DIALOG.session-<session>.latest.json`
- Session index: `shared_state/dialog/MIM_TOD_DIALOG.sessions.latest.json`

Remote default:

- Env override: `MIM_TOD_DIALOG_REMOTE_ROOT`
- Default: `/home/testpilot/mim/runtime/shared/dialog`

Publish behavior:

- `send` writes local session log, aggregate log, session state, and session index.
- With `-PublishRemote`, it uploads those same files to the remote dialog root.
- `close-session` does the same local writes and optional remote publish.

Problem:

The dialog lane is explicitly documented as not replacing request, ACK, result, review, or command-status artifacts. Posting only here is not enough to move execution or prove MIM received a task/result.

Current evidence:

- Local dialog index exists and is active.
- Local dialog index reported 204 sessions.
- Current local status counts:
  - `awaiting_reply`: 17
  - `open`: 5
  - `replied`: 161
  - `closed`: 18
  - `resolved`: 4
- Remote dialog root exists, but its newest observed index was older than local: remote `/home/testpilot/mim/runtime/shared/dialog/MIM_TOD_DIALOG.sessions.latest.json` was last modified at about 20:12 local, while local `shared_state/dialog/MIM_TOD_DIALOG.sessions.latest.json` had advanced to about 20:19 local.

Classification:

- Coordination blocker: dialog expectations are not proving receiver acknowledgement.
- Authority blocker: dialog lane is being treated like a delivery authority even though it is only a diagnostic side channel.
- Data freshness blocker: remote dialog mirror can lag local dialog state.

### 2. `scripts/Start-TODMimPacketListener.ps1`

Purpose: active local TOD listener for MIM requests and TOD responses.

Default parameters:

- `RemoteRoot = /home/testpilot/mim/runtime/shared`
- `StageDir = tod/out/context-sync/listener`
- `SyncStageDir = tod/out/context-sync/ssh-shared`

Local stage files:

- `tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json`
- `tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.json`
- `tod/out/context-sync/listener/MIM_TOD_GO_ORDER.latest.json`
- `tod/out/context-sync/listener/MIM_TOD_REVIEW_DECISION.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_TASK_ACK.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_TASK_TROUBLESHOOTING.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_EXECUTION_DECISION.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_COORDINATION_REQUEST.latest.json`
- `tod/out/context-sync/listener/MIM_TOD_COORDINATION_ACK.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_EMERGENCY_REQUEST.latest.json`
- `tod/out/context-sync/listener/MIM_TOD_EMERGENCY_ACK.latest.json`

Remote shared-root files:

- `/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`
- `/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.json`
- `/home/testpilot/mim/runtime/shared/MIM_TOD_GO_ORDER.latest.json`
- `/home/testpilot/mim/runtime/shared/MIM_TOD_REVIEW_DECISION.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_TASK_ACK.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_TASK_RESULT.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_TASK_TROUBLESHOOTING.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_COMMAND_STATUS.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_EXECUTION_DECISION.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_COORDINATION_REQUEST.latest.json`
- `/home/testpilot/mim/runtime/shared/MIM_TOD_COORDINATION_ACK.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_STALL_ALERT.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_TO_MIM_TRIGGER_ACK.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_TO_MIM_PING.latest.json`

Publish behavior:

- ACK and RESULT are written locally and then uploaded to the remote shared root using `Write-RemoteFileFromText`.
- Execution decision is written locally and uploaded to `TOD_MIM_EXECUTION_DECISION.latest.json`.
- Coordination, emergency, stall, command status, and troubleshooting artifacts are also written to the remote shared root.

Current evidence:

- Local listener decision was fresh and said `requested_executor=tod`, `decision_outcome=execute`.
- Local listener ACK was fresh and accepted the current request.
- Local listener result had a recent successful result for the prior request.
- Remote shared root showed fresh `TOD_MIM_TASK_ACK.latest.json`, `TOD_MIM_TASK_RESULT.latest.json`, `TOD_MIM_EXECUTION_DECISION.latest.json`, `TOD_MIM_COMMAND_STATUS.latest.json`, `TOD_INTEGRATION_STATUS.latest.json`, and `TOD_TRAINING_STATUS.latest.json`.

Important caveat:

`MIM_TOD_TASK_REQUEST.latest.json` had a fresh file modification time due to sync, but its payload `generated_at` was older. Consumers must not treat file mtime alone as request freshness.

Classification:

- This is the active authoritative lane.
- If MIM is not seeing TOD, this lane should be checked before the dialog lane.
- If a TOD response exists only in dialog and not in one of these latest artifacts, it is not operationally delivered.

### 3. `scripts/Invoke-TODSharedStateSync.ps1`

Purpose: refresh MIM context into TOD and publish TOD integration/training status.

MIM pull defaults:

- `MimSshSharedRoot = /home/testpilot/mim/runtime/shared`
- `MimSshStagingRoot = tod/out/context-sync/ssh-shared`

Pulled MIM artifacts:

- `/home/testpilot/mim/runtime/shared/MIM_CONTEXT_EXPORT.latest.json`
- `/home/testpilot/mim/runtime/shared/MIM_CONTEXT_EXPORT.latest.yaml`
- `/home/testpilot/mim/runtime/shared/MIM_MANIFEST.latest.json`
- `/home/testpilot/mim/runtime/shared/MIM_TOD_HANDSHAKE_PACKET.latest.json`
- `/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`

Local pull targets:

- `tod/out/context-sync/ssh-shared/MIM_CONTEXT_EXPORT.latest.json`
- `tod/out/context-sync/ssh-shared/MIM_CONTEXT_EXPORT.latest.yaml`
- `tod/out/context-sync/ssh-shared/MIM_MANIFEST.latest.json`
- `tod/out/context-sync/ssh-shared/MIM_TOD_HANDSHAKE_PACKET.latest.json`
- `tod/out/context-sync/ssh-shared/MIM_TOD_TASK_REQUEST.latest.json`

TOD status publish defaults:

- Primary: `/home/testpilot/mim_arm/runtime/shared`
- Mirror: `/home/testpilot/mim/runtime/shared`

Published status files:

- `TOD_INTEGRATION_STATUS.latest.json`
- `TOD_integration_status.latest.json`
- `TOD_TRAINING_STATUS.latest.json`
- `TOD_training_status.latest.json`

Problem:

This script can successfully publish to MIM ARM while still needing the MIM mirror to prove that the main MIM runtime saw the update. Its own validation logic treats `mim_mirror_status=mirrored` as required for full remote publish verification.

Classification:

- Infrastructure/data blocker if primary upload succeeds but mirror fails.
- Authority blocker if status in MIM ARM is treated as proof that main MIM consumed the update.

### 4. `scripts/TOD.ps1`

Purpose: TOD task creation, execution, local shared artifacts, and remote publish of selected runtime artifacts.

Execution shared roots:

- `runtime/shared`
- `tmp_remote_mim/runtime/shared`

Common local artifacts written by TOD:

- `runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`
- `runtime/shared/TOD_ACTIVE_TASK.latest.json`
- `runtime/shared/TOD_ACTIVE_OBJECTIVE.latest.json`
- `runtime/shared/TOD_ACTIVITY_STREAM.latest.json`
- `runtime/shared/TOD_VALIDATION_RESULT.latest.json`
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json`
- `runtime/shared/TOD_EXECUTION_TRUTH.latest.json`
- `runtime/shared/TOD_NEXT_TASK_SELECTION.latest.json`

Remote publish:

- Function: `Publish-RemoteTodExecutionArtifacts`
- Default remote root: `/home/testpilot/mim/runtime/shared`
- It publishes only existing local artifact paths passed from `runtime/shared`.
- `tmp_remote_mim/runtime/shared` is not itself proof of remote MIM delivery.

Current evidence:

- `runtime/shared/TOD_ACTIVITY_STREAM.latest.json` was fresh and showed a queued/current action.
- `runtime/shared/TOD_EXECUTION_RESULT.latest.json` was older than activity and showed a blocker for `MIM-BOX-LISTENER-PATH-AUTHORITY-RESOLUTION-V1`.
- `tmp_remote_mim/runtime/shared` mirrored many local runtime shared files.
- Recent write-failure records exist for `runtime/shared/TOD_ACTIVITY_STREAM.latest.json`, `tmp_remote_mim/runtime/shared/TOD_ACTIVITY_STREAM.latest.json`, `runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json`, and `tmp_remote_mim/runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json`.

Classification:

- Data freshness blocker: activity can be fresh while execution result remains older.
- Infrastructure blocker: write failures on shared artifacts were recorded.
- Authority blocker: a write to `tmp_remote_mim/runtime/shared` is not a MIM receipt.

### 5. `scripts/Copy-TODCurrentStateToContextSync.ps1`

Purpose: copy selected local TOD state files into a context-sync destination and build an index.

Important target names:

- `TOD_MIM_INTEGRATION_STATUS.latest.json`
- `TOD_MIM_NEXT_ACTIONS.latest.json`
- `TOD_MIM_CURRENT_BUILD_STATE.latest.json`
- `TOD_MIM_OBJECTIVES.latest.json`
- `TOD_MIM_LATEST_SUMMARY.latest.md`
- `TOD_MIM_CONTRACT_ACCEPTANCE.latest.json`
- `TOD_MIM_CONTRACT_FORMAL_AGREEMENT.latest.json`
- `TOD_MIM_BRIDGE_SMOKE.latest.json`
- `TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json`
- `MIM_TOD_HANDSHAKE_PACKET.latest.json`
- `MIM_TOD_TASK_REQUEST.latest.json`
- `CURRENT_TOD_MIM_STATE_INDEX.latest.json`
- `CURRENT_TOD_MIM_STATE_INDEX.latest.md`

Classification:

- Context-sync mirror, not primary MIM delivery.
- Useful for snapshots and operator readouts.
- Not enough to prove MIM consumed a current TOD task/result.

## MIM-Side Consumption Evidence

Mirrored MIM code in `tmp_remote_mim` shows these active consumers:

- `scripts/mim_box_tod_packet_listener.py` defaults to:
  - `runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`
  - `runtime/shared/TOD_MIM_TASK_ACK.latest.json`
  - `runtime/shared/TOD_MIM_TASK_RESULT.latest.json`
- `core/routers/mim_ui.py` reads:
  - `runtime/shared/TOD_MIM_EXECUTION_DECISION.latest.json`
  - `runtime/shared/TOD_MIM_COORDINATION_REQUEST.latest.json`
  - `runtime/shared/MIM_TOD_COORDINATION_ACK.latest.json`
  - `runtime/shared/TOD_MIM_TASK_RESULT.latest.json`
- `core/routers/studio.py` reads:
  - `runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`
  - `runtime/shared/TOD_MIM_TASK_RESULT.latest.json`
- `core/routers/gateway.py` repeatedly references:
  - `runtime/shared/MIM_TOD_TASK_REQUEST.latest.json`
  - `runtime/shared/TOD_MIM_TASK_RESULT.latest.json`

Dialog consumers also exist:

- `core/next_step_dialog_service.py` uses `shared_root / "dialog"`.
- `core/routers/tod_ui.py` has `DIALOG_ROOT = SHARED_RUNTIME_ROOT / "dialog"`.

Interpretation:

The dialog path exists and is valid, but it is not the main task/result authority. The operational MIM/TOD bridge is still the shared-root latest-file lane.

## Database / Ledger Finding

The expected DB path is:

- `runtime/shared/TOD_MIM_MESSAGE_LEDGER.sqlite3`

Current local evidence:

- The DB file does not exist.
- `scripts/Start-TODMimPacketListener.ps1` only enables ledger writes when `MESSAGE_LEDGER_MODE=observe_only`.
- Ledger calls use `scripts/tod_mim_message_ledger.py` with `--mode observe_only`.
- The migration is `db/migrations/20260506_tod_mim_message_ledger_phase_a_observe_only.sql`.

Conclusion:

The DB is not the current authoritative communication lane. It is an observe-only shadow ledger when enabled. In this local checkout, the default DB file is absent, so the active path cannot be DB-backed right now.

## Current Wrong-Path Failure Modes

### Failure Mode 1: Dialog-only delivery

TOD writes a MIM question or blocker into:

- `shared_state/dialog/MIM_TOD_DIALOG.*`
- optionally `/home/testpilot/mim/runtime/shared/dialog/MIM_TOD_DIALOG.*`

MIM's active task/result/status consumers read:

- `/home/testpilot/mim/runtime/shared/TOD_MIM_TASK_RESULT.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_EXECUTION_DECISION.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_COORDINATION_REQUEST.latest.json`
- `/home/testpilot/mim/runtime/shared/TOD_MIM_COMMAND_STATUS.latest.json`

Result:

TOD thinks it posted; MIM may not see it in the operational surface.

### Failure Mode 2: Local mirror mistaken for remote receipt

TOD writes:

- `tmp_remote_mim/runtime/shared/*.latest.json`

But MIM consumes:

- `/home/testpilot/mim/runtime/shared/*.latest.json`

Result:

Local evidence exists, but remote MIM receipt is unproven.

### Failure Mode 3: Mtime freshness hides payload staleness

Observed:

- `runtime/shared/MIM_TOD_TASK_REQUEST.latest.json` had a fresh local modification time.
- Its payload `generated_at` remained old.

Result:

Sync can make an old request look fresh if validation only checks file timestamp. Validation must compare request id, task id, correlation id, objective id, and payload `generated_at`.

### Failure Mode 4: MIM ARM status mistaken for main MIM status

TOD status can publish to:

- `/home/testpilot/mim_arm/runtime/shared`

But main MIM bridge evidence is:

- `/home/testpilot/mim/runtime/shared`

Result:

Status upload may be real but still not prove that the main MIM runtime consumed the update unless the MIM mirror is verified.

### Failure Mode 5: Open-session backlog normalized as historical

Observed:

- 204 local dialog sessions.
- 17 `awaiting_reply`.
- 5 `open`.

Result:

This cannot be dismissed as historical noise until a new current session is opened, acknowledged, and closed end to end on the path MIM actually consumes.

## Blocker Classification

| Blocker | Class | Evidence | Owner |
| --- | --- | --- | --- |
| TOD posts to dialog but MIM operational consumers watch shared root | Authority blocker | Dialog root and shared root are separate; MIM task/result consumers use shared root | TOD owns proof; MIM owns consumer acknowledgement |
| Remote dialog mirror lags local dialog state | Infrastructure/data blocker | Remote dialog latest observed older than local index | TOD owns publish verification |
| DB expected but not active | Authority blocker | Ledger DB missing; mode is observe-only only | MIM/TOD jointly own authority decision |
| Local mirror treated like delivery | Data/coordination blocker | `tmp_remote_mim` is local, not MIM receipt | TOD owns validation discipline |
| Shared artifact write failures | Infrastructure blocker | `shared_state/tod_shared_artifact_write_failures` records unauthorized writes | TOD owns repair or precise blocker |
| Open dialog backlog | Coordination blocker | 17 awaiting reply, 5 open | TOD owns fresh close proof; MIM owns reply/ack visibility |

## What TOD Should Do Next

Objective:

`TOD-POSTING-PATH-AUTHORITY-PROOF-001`

Goal:

Prove TOD can post one current MIM-visible item to the correct existing path and that MIM can see and acknowledge it, without creating a new communication tool.

Required evidence:

1. Classify the blocker before training begins:
   - primary class: authority blocker
   - secondary classes: coordination blocker, data freshness blocker
2. Create one fresh test session in the existing dialog lane.
3. Publish a matching MIM-visible coordination request to:
   - local: `tod/out/context-sync/listener/TOD_MIM_COORDINATION_REQUEST.latest.json`
   - remote: `/home/testpilot/mim/runtime/shared/TOD_MIM_COORDINATION_REQUEST.latest.json`
4. Verify MIM acknowledgement at:
   - local: `tod/out/context-sync/listener/MIM_TOD_COORDINATION_ACK.latest.json`
   - remote: `/home/testpilot/mim/runtime/shared/MIM_TOD_COORDINATION_ACK.latest.json`
5. Close the fresh dialog session.
6. Verify the fresh session is no longer `open` or `awaiting_reply`.
7. Publish a final result to:
   - local: `tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json`
   - remote: `/home/testpilot/mim/runtime/shared/TOD_MIM_TASK_RESULT.latest.json`

Pass condition:

- MIM sends or observes one current request/ack path.
- TOD posts to the shared root, not only dialog.
- MIM ack is visible in the shared root.
- Fresh session closes.
- No new communication tools.
- DB is not claimed authoritative unless the active runtime actually reads/writes it.

Fail condition:

- TOD only updates `shared_state/dialog`.
- TOD only updates `tmp_remote_mim/runtime/shared`.
- TOD reports success based only on local file creation.
- TOD reports success based only on file mtime without matching request id/task id/correlation id.
- TOD claims DB communication without an existing DB file and active runtime consumers.

## Immediate Operator Readout

This is a local TOD posting-path issue with an authority mismatch:

- The correct operational MIM path is `/home/testpilot/mim/runtime/shared/*.latest.json`.
- TOD's dialog path is valid but secondary.
- TOD's DB ledger is not active authority.
- `tmp_remote_mim/runtime/shared` is not proof of delivery.
- The next proof must force TOD to post into the existing shared-root coordination/result lane and verify MIM acknowledgement there.

