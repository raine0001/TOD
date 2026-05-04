# TOD MIM Communication Audit

Date: 2026-04-01

Status: Read-only audit and migration plan. No runtime behavior changes are proposed in this document.

Purpose: map every current persistence lane used for MIM to TOD project and task work, identify duplicate or stale authority paths, and define one canonical live communication method for follow-on cleanup.

## A. Communication Audit Report

### Executive conclusion

The repo does not have one communication method today. It has one primary execution lane plus several overlapping compatibility, projection, coordination, monitoring, and synthetic-write lanes.

The primary execution lane is centered on [scripts/Start-TODMimPacketListener.ps1](scripts/Start-TODMimPacketListener.ps1). That script is both the main consumer of remote MIM packets and the main writer of TOD replies into the listener stage. However, the same runtime also supports legacy request names, alternate trigger names, synthetic publishers, shared-state rebuilders, UI projections, and supervisory restart loops. Those extra lanes do not all execute work, but several of them can make stale work look current or can inject data that competes with the live lane.

The immediate stale-request problem around objective 97 is consistent with this architecture: the listener can correctly suppress stale work while another upstream or adjacent path continues to refresh stale request state.

### Current architecture by lane

1. Live execution lane

- Primary runtime owner: [scripts/Start-TODMimPacketListener.ps1](scripts/Start-TODMimPacketListener.ps1)
- Main local stage: [tod/out/context-sync/listener](tod/out/context-sync/listener)
- Main remote shared root: `192.168.1.120:/home/testpilot/mim/runtime/shared`
- Core behavior:
  - pulls current request and trigger artifacts from remote shared storage
  - applies deduplication and stale-backfill suppression
  - writes current ACK, result, command-status, trigger-ack, journal, and state artifacts
  - mirrors task state into local listener stage for downstream readers

Communication authority correction:

- Communication authority is only `192.168.1.120:/home/testpilot/mim/runtime/shared`.
- `192.168.1.90:/home/testpilot/mim/runtime/shared` and `192.168.1.90:/home/testpilot/mim_arm/runtime/shared` are arm-side runtime or telemetry surfaces only.
- Local mirrors such as [tod/out/context-sync/listener](tod/out/context-sync/listener) and [tod/out/context-sync/ssh-shared](tod/out/context-sync/ssh-shared) are consumable mirrors, not communication authority.

2. Derivative shared-state projection lane

- Primary runtime owner: [scripts/Invoke-TODSharedStateSync.ps1](scripts/Invoke-TODSharedStateSync.ps1)
- Main outputs: [shared_state/integration_status.json](shared_state/integration_status.json), [shared_state/next_actions.json](shared_state/next_actions.json), and related shared_state summaries
- Behavior:
  - reads listener request, result, and journal artifacts
  - merges those with TOD state, MIM export state, readiness, reliability, and approval data
  - produces operator-facing and system-facing projections
- Important constraint:
  - this lane is derivative and should not be treated as the current live task authority
  - local mirrors under `tod/out/context-sync/*` are non-authoritative for communication truth

3. UI and state-bus consumption lane

- Main consumers:
  - [scripts/Start-TOD-UI.ps1](scripts/Start-TOD-UI.ps1)
  - [scripts/Get-TODLightweightStateBus.ps1](scripts/Get-TODLightweightStateBus.ps1)
  - [ui/index.html](ui/index.html)
- Behavior:
  - reads listener-stage artifacts and shared-state projections
  - renders current request, result, status, dialog, and history views
- Risk:
  - if UI surfaces show historical or derived state without clearly marking it as non-authoritative, operators can mistake history for current work

4. Supervisory recovery lane

- Main runtime owner: [scripts/Start-TODRecoveryWatchdog.ps1](scripts/Start-TODRecoveryWatchdog.ps1)
- Behavior:
  - inspects listener-stage freshness, bridge smoke output, UI health, and request-to-result progression
  - can restart the listener and the UI
  - can invoke shared-state refresh
  - can publish dialog notices about failures and resolutions
- Risk:
  - this lane is supervisory, not authoritative for project or task state, but it can change which runtime process is currently writing the live lane

5. Catch-up and gate watcher lane

- Main runtimes:
  - [scripts/Start-TODCatchupGateWatcher.ps1](scripts/Start-TODCatchupGateWatcher.ps1)
  - [scripts/Check-TODRecouplingGate.ps1](scripts/Check-TODRecouplingGate.ps1)
  - [scripts/Register-TODCatchupGateWatcherTask.ps1](scripts/Register-TODCatchupGateWatcherTask.ps1)
- Behavior:
  - reads listener request, result, trigger-ack, integration status, and next-actions projection
  - publishes gate state into shared_state with a single-writer lock
- Risk:
  - this lane consumes live data but writes derivative gate state that can be mistaken for control authority if naming is not explicit

6. Dialog coordination lane

- Main runtime owner: [scripts/Invoke-TODMimDialog.ps1](scripts/Invoke-TODMimDialog.ps1)
- Main files:
  - [shared_state/dialog/MIM_TOD_DIALOG.latest.jsonl](shared_state/dialog/MIM_TOD_DIALOG.latest.jsonl)
  - session logs and session snapshots under [shared_state/dialog](shared_state/dialog)
- Behavior:
  - persists diagnostic, status, blocker, resolution, and handoff messages
  - can be used by the recovery watchdog and the UI
- Constraint:
  - this lane is explicitly not allowed to replace request, ACK, result, review, or command-status artifacts

7. Synthetic and manual injection lane

- Main writers:
  - [scripts/Invoke-TODMimListenerSmoke.ps1](scripts/Invoke-TODMimListenerSmoke.ps1)
  - [scripts/Push-SyntheticResult.ps1](scripts/Push-SyntheticResult.ps1)
  - tmp helper scripts in the repo root that push or inspect MIM-facing state
- Behavior:
  - writes synthetic requests, reviews, go-orders, or results into the same remote or local artifact families used by the live lane
- Risk:
  - these tools are useful for validation, but they are direct competing writers unless isolated from production-like roots

8. Startup and scheduled-task orchestration lane

- Main launchers:
  - [scripts/Start-TODMimListenerStartup.ps1](scripts/Start-TODMimListenerStartup.ps1)
  - [scripts/Register-TODListenerTask.ps1](scripts/Register-TODListenerTask.ps1)
  - [scripts/Start-TODRecoveryWatchdog.ps1](scripts/Start-TODRecoveryWatchdog.ps1)
- Behavior:
  - can start the listener at startup or logon
  - can restart the listener after failures
- Risk:
  - duplicate hosts are partially mitigated by scheduled-task settings and process checks, but multiple control points still exist

### Where persistence currently happens

Current MIM-to-TOD project and task communication is persisted in four distinct categories:

1. Current-state execution packets
  - request, trigger, ACK, result, review, go-order, command-status, listener-state

2. Historical or append-only execution evidence
  - listener journal, validator snapshots, incoming snapshots, log jsonl files

3. Derived status projections
  - integration status, next actions, self-health, state bus, gate watcher outputs, UI summaries

4. Coordination transcripts
  - dialog jsonl and session snapshots

The architecture problem is not that these categories exist. The problem is that naming and consumer behavior allow category 2 and category 3 artifacts to be interpreted as if they were category 1 authority.

### Main duplicate and stale-authority findings

1. The live request lane has a legacy alias.

- Canonical current file: MIM_TOD_TASK_REQUEST.latest.json
- Legacy alias still supported by listener: MIM_TOD_TASK_REQUEST.json
- Result: more than one inbound filename can represent the current request

2. The trigger lane has an alternate alias.

- Canonical current file: MIM_TO_TOD_TRIGGER.latest.json
- Alternate alias still supported by listener: MIM-TO_TOD_TRIGGER.latest.json
- Result: multiple trigger names can wake the same execution lane

3. Project inbox artifacts overlap with live task semantics.

- Listener compatibility logic also references task.json and tasks.json
- Result: project/task backlog files and live execution packets are too close semantically

4. Shared-state projections can pin or preserve objective state independently of the live request lane.

- [scripts/Invoke-TODSharedStateSync.ps1](scripts/Invoke-TODSharedStateSync.ps1) honors existing current_objective_in_progress from [shared_state/next_actions.json](shared_state/next_actions.json)
- Result: a derived file can influence the displayed current objective even when the execution lane has advanced

5. Synthetic tools can write directly into live artifact families.

- [scripts/Invoke-TODMimListenerSmoke.ps1](scripts/Invoke-TODMimListenerSmoke.ps1) writes request, go-order, and review packets
- [scripts/Push-SyntheticResult.ps1](scripts/Push-SyntheticResult.ps1) writes result packets
- Result: non-runtime tools can generate packets that look authoritative

6. Supervisory automation can relaunch the main writer.

- [scripts/Start-TODRecoveryWatchdog.ps1](scripts/Start-TODRecoveryWatchdog.ps1) can stop and restart the listener
- [scripts/Register-TODListenerTask.ps1](scripts/Register-TODListenerTask.ps1) can also launch it at startup or logon
- Result: process ownership is not singular even if artifact ownership is intended to be singular

7. The UI consumes both live and derivative lanes.

- [scripts/Start-TOD-UI.ps1](scripts/Start-TOD-UI.ps1) reads listener artifacts, command status, trigger-ack, and dialog data
- Result: without strict labeling, the UI can visually blur live execution truth with explanatory or historical data

## B. Artifact and Source-of-Truth Matrix

| Artifact or family | Primary producer | Primary consumers | Authoritative for live work | Role | Overwrite or confusion risk |
| --- | --- | --- | --- | --- | --- |
| MIM_TOD_TASK_REQUEST.latest.json | MIM upstream, pulled by listener | listener, UI, bridge smoke, watchdogs, gate checks, shared-state sync | Yes | Canonical inbound current request | High if legacy alias or synthetic writers remain active |
| MIM_TOD_TASK_REQUEST.json | legacy upstream compatibility | listener | No | Legacy compatibility alias | High because it can still be treated as live current request |
| MIM_TO_TOD_TRIGGER.latest.json | MIM upstream | listener | Yes | Canonical wakeup signal for current request | Medium if alternate trigger alias remains |
| MIM-TO_TOD_TRIGGER.latest.json | legacy or alternate upstream | listener | No | Alternate compatibility trigger | High because it duplicates the wakeup lane |
| MIM_TOD_GO_ORDER.latest.json | MIM upstream or smoke tools | listener, smoke validation | Conditional | Governance gate input | Medium because test tools can write it |
| MIM_TOD_REVIEW_DECISION.latest.json | MIM upstream or smoke tools | listener, smoke validation | Conditional | Governance gate input | Medium because test tools can write it |
| TOD_TO_MIM_TRIGGER_ACK.latest.json | listener | MIM upstream, UI, bridge smoke, gate checks | Yes for receipt only | Transport-level trigger acknowledgment | Medium if interpreted as terminal completion |
| TOD_MIM_TASK_ACK.latest.json | listener | MIM upstream, UI, consumers | Yes for acceptance only | Execution acceptance acknowledgment | Medium if consumers skip result and rely only on ACK |
| TOD_MIM_TASK_RESULT.latest.json | listener, synthetic result tool | MIM upstream, UI, bridge smoke, watchdogs, shared-state sync | Yes | Canonical terminal result for the current attempt | High because Push-SyntheticResult can compete with listener ownership |
| TOD_MIM_COMMAND_STATUS.latest.json | listener | UI, state consumers | No | Observability and explanation | Medium if treated as authority instead of telemetry |
| TOD_LOOP_JOURNAL.latest.json | listener | shared-state sync, cadence watcher, live watcher, watchdog | No | Historical execution evidence | High if journal rows are mistaken for current request state |
| listener_state.json | listener | watchdog, gate checks, state consumers | Local only | Listener runtime state and last processed metadata | Medium because it is authoritative only for the local listener host |
| task.json and tasks.json | project or backlog flows, compatibility handling | listener compatibility path | No for live execution | Project or backlog state | High because names overlap with live task semantics |
| shared_state/integration_status.json | shared-state sync | UI, gate checks, watchdog, status surfaces | No | Derived cross-system projection | High if treated as current task truth |
| shared_state/next_actions.json | shared-state sync | UI, gate checks, status surfaces, shared-state sync itself | No | Derived objective and next-step projection | High because existing value can pin displayed current objective |
| shared_state/TOD_SELF_HEALTH_RUN.latest.json and related health files | health maintenance and shared-state flows | operators and status surfaces | No | Health projection | Low to medium |
| shared_state/tod_catchup_gate_watcher.latest.json | catch-up gate watcher | operators and recovery flows | No | Gate monitoring projection | Low to medium |
| shared_state/dialog/* | dialog tool, watchdog | UI, operators | No | Coordination transcript | Medium if operator treats dialog as execution authority |
| validator snapshots and snapshot inboxes | listener and validators | humans, tests, audits | No | Historical evidence | Low unless consumers read them as live state |

## C. Legacy vs Canonical Decision Table

| Path or pattern | Decision | Reason |
| --- | --- | --- |
| MIM_TOD_TASK_REQUEST.latest.json | Keep as canonical | One current inbound request file is required |
| MIM_TO_TOD_TRIGGER.latest.json | Keep as canonical | One current wakeup signal is required |
| TOD_TO_MIM_TRIGGER_ACK.latest.json | Keep as canonical | Needed as transport-level receipt signal |
| TOD_MIM_TASK_ACK.latest.json | Keep as canonical | Needed as execution acceptance signal |
| TOD_MIM_TASK_RESULT.latest.json | Keep as canonical | Needed as terminal execution outcome |
| MIM_TOD_GO_ORDER.latest.json | Keep as canonical gate input | Governance still requires an explicit gate input |
| MIM_TOD_REVIEW_DECISION.latest.json | Keep as canonical gate input | Governance still requires explicit review decision input |
| listener_state.json | Keep as local runtime state only | Useful for watchdogs and diagnostics, but not a cross-system source of truth |
| TOD_MIM_COMMAND_STATUS.latest.json | Keep as telemetry only | Useful for explanation and UI detail, but not live execution authority |
| TOD_LOOP_JOURNAL.latest.json | Keep as history only | Valuable evidence, but must never override current request or result |
| MIM_TOD_TASK_REQUEST.json | Remove after migration window | Duplicate inbound current-request alias |
| MIM-TO_TOD_TRIGGER.latest.json | Remove after migration window | Duplicate trigger alias |
| task.json | Remove from listener live path | Project backlog artifact should not act as execution request |
| tasks.json | Remove from listener live path | Project backlog artifact should not act as execution request |
| shared_state/integration_status.json | Keep as derived projection only | Useful for operator awareness, not for live task authority |
| shared_state/next_actions.json | Keep as derived projection only, remove lane-pinning authority | Useful for operator guidance, dangerous as pseudo-authority |
| shared_state/dialog/* | Keep as coordination-only | This channel is valuable if it remains non-executional |
| Invoke-TODMimListenerSmoke and Push-SyntheticResult writing into production-like roots | Restrict to test-only roots | They are useful, but cannot share the same authoritative namespace |
| tmp helper scripts that publish remote MIM-facing data | Quarantine or remove from standard workflow | They are not safe as ambient runtime writers |

## Recommended Canonical Communication Method

Define one canonical live method called the listener-stage execution contract.

Rules:

1. One current request packet.
  - MIM_TOD_TASK_REQUEST.latest.json

2. One current wakeup packet.
  - MIM_TO_TOD_TRIGGER.latest.json

3. One acceptance sequence owned by TOD.
  - TOD_TO_MIM_TRIGGER_ACK.latest.json for transport receipt
  - TOD_MIM_TASK_ACK.latest.json for accepted execution

4. One terminal result packet owned by TOD.
  - TOD_MIM_TASK_RESULT.latest.json

5. One local runtime state file owned by the listener.
  - listener_state.json

6. Everything else is either:
  - governance input
  - telemetry
  - history
  - coordination transcript
  - synthetic test input

7. No derived file may pin or override the current live request or current live objective.

8. No test, smoke, watchdog, or manual script may write into the canonical namespace outside explicit test roots.

## D. Migration Plan

### Phase 1: Freeze the authority model

Goal: document and enforce which files are live authority and which are not.

Tasks:

1. Mark canonical current files in docs and comments as the only live execution authority.
2. Mark integration status, next actions, journals, dialogs, and gate outputs as derived or historical only.
3. Mark task.json and tasks.json as backlog or project artifacts, not live execution packets.

Exit criteria:

- no ambiguity in docs about which files determine current work

### Phase 2: Remove duplicate inbound aliases from the listener

Goal: ensure exactly one current request filename and one current trigger filename.

Tasks:

1. Add temporary warnings when the listener sees MIM_TOD_TASK_REQUEST.json.
2. Add temporary warnings when the listener sees MIM-TO_TOD_TRIGGER.latest.json.
3. After migration window, stop reading those aliases.

Exit criteria:

- listener consumes only canonical request and canonical trigger names for current execution

### Phase 3: Separate live execution from backlog files

Goal: prevent task.json and tasks.json from being interpreted as live execution traffic.

Tasks:

1. Remove task.json and tasks.json from listener live-request compatibility handling.
2. Keep them only in project or backlog flows where they belong.

Exit criteria:

- backlog files cannot enter the listener as current execution authority

### Phase 4: Remove derived-file influence on live objective selection

Goal: ensure shared-state projections never pin or override current live authority.

Tasks:

1. Remove or narrow current_objective_in_progress lane pinning from [scripts/Invoke-TODSharedStateSync.ps1](scripts/Invoke-TODSharedStateSync.ps1).
2. Rebuild next_actions.json strictly from canonical live packets plus TOD state, not from its own previous projection.
3. Ensure UI labels next_actions and integration_status as projections.

Exit criteria:

- changing a derived file cannot alter the system’s idea of the current live request or current live objective

### Phase 5: Isolate synthetic and manual writers

Goal: keep validation tools while preventing them from competing with production-like namespaces.

Tasks:

1. Move smoke tools to dedicated test roots or add mandatory test-prefix paths.
2. Block Push-SyntheticResult from defaulting into the canonical runtime root.
3. Review tmp helper scripts and either move them under a clearly non-runtime tools area or retire them.

Exit criteria:

- no test or helper script can accidentally publish into the live namespace

### Phase 6: Simplify supervisory ownership

Goal: reduce the number of places that can restart or rehost the canonical writer.

Tasks:

1. Keep one startup path for the listener.
2. Keep the recovery watchdog as supervisor only, with explicit logs when it restarts the listener.
3. Verify that scheduled-task startup and watchdog recovery cannot create competing listener hosts.

Exit criteria:

- one canonical writer process at a time, with clear restart provenance

### Phase 7: Consumer hardening

Goal: ensure every reader treats live, derived, historical, and dialog data differently.

Tasks:

1. Audit UI rendering and state-bus output labels.
2. Audit watchdog and gate-check logic so they read canonical artifacts first and use projections second.
3. Ensure historical journal rows can never become current task state without matching canonical current packets.

Exit criteria:

- consumers cannot visually or programmatically promote stale history into live authority

### Phase 8: Validation plan after implementation

Required validation slices:

1. Alias retirement validation
  - prove the listener ignores removed legacy aliases

2. Live authority validation
  - prove canonical request, trigger, ACK, and result rotate correctly for one new task

3. Stale-backfill validation
  - prove a lower-ordinal historical task is acknowledged as stale without replacing the live task

4. Projection safety validation
  - prove editing derived files does not alter current live execution truth

5. Synthetic isolation validation
  - prove smoke tools cannot write into the live namespace by default

## Implementation Order Recommendation

When implementation begins, the safest order is:

1. consumer labeling and documentation hardening
2. alias warning instrumentation
3. alias removal
4. backlog file separation
5. shared-state pinning removal
6. synthetic-writer isolation
7. restart-path consolidation

This order reduces ambiguity before removing compatibility and lowers the risk of hidden consumer breakage.

## Immediate Read-Only Answer To The Objective 97 Problem

Based on this audit, the most likely explanation for repeated stale objective-97-task-3422 observation is not a failure of the listener’s stale-backfill logic. The more likely causes are:

1. an upstream reissuer continuing to publish the stale request into the canonical inbound file
2. a legacy alias or compatibility path feeding that same stale request back into the listener
3. a projection or consumer surface preserving stale request context in a way that appears current

That means the next implementation work should focus on writer and alias reduction, not on adding more suppression logic to the listener.