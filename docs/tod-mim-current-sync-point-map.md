# TOD-MIM Current Sync Point Map

Generated: 2026-05-06
Objective: TOD-MIM-SYNC-POINT-INVENTORY
Scope: Current runtime synchronization only. No runtime behavior changes.

## 1) System Surfaces In Scope

- File artifacts under `runtime/shared`, `shared_state`, `tod/out/context-sync/*`, `tod/out/background-chat/*`
- TOD sync scripts and listener services
- TOD UI/API projection endpoints consuming sync state
- MIM remote shared artifacts fetched through SSH/SFTP
- Recovery/watchdog and stale-guard state used to gate execution

## 2) Current Sync Point Inventory

Legend for classification:
- message
- mirror
- authority
- cache
- UI projection
- recovery artifact
- stale guard / memory
- diagnostic only

| Sync Point | Location | Classification | Writers | Readers | Execution Authority Role | Notes |
|---|---|---|---|---|---|---|
| MIM task request packet | runtime/shared/MIM_TOD_TASK_REQUEST.latest.json (remote canonical copy under /home/testpilot/mim/runtime/shared) | authority + message | MIM dispatcher/service | Start-TODMimPacketListener.ps1, bridge smoke scripts | Primary ingress authority for TOD-side task intake | Canonical request source; disagreement with local objective can block dispatch |
| MIM trigger packet | runtime/shared/MIM_TO_TOD_TRIGGER.latest.json (remote + local mirror) | message | MIM dispatcher/service | Listener, bridge scripts | Trigger signal only | Carries task/correlation context |
| TOD ACK packet | tod/out/context-sync/listener/TOD_MIM_TASK_ACK.latest.json | message | Start-TODMimPacketListener.ps1 | Contract checks, diagnostics | Not primary authority | Contract-compliant acknowledgment output |
| TOD RESULT packet | tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json | authority + message | Start-TODMimPacketListener.ps1 | Invoke-TODSharedStateSync.ps1, recoupling gate checks | Completion/blocked result authority for MIM-facing sync | Promoted into shared_state objective/task projections |
| Command status packet | tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json | mirror + stale guard / memory | Listener | UI projections, sync checks | Secondary authority candidate (risk) | Contains stale_guard and high-watermark fields |
| Listener state store | tod/out/context-sync/listener/listener_state.json | stale guard / memory + recovery artifact | Listener | Listener dedup path, sync scripts | Local dedup authority | Prevents replay; high-watermark persistence |
| Listener activity snapshot | tod/out/context-sync/listener/listener_activity.json | diagnostic only + UI projection | Listener | UI/project-status views, diagnostics | Non-authoritative | Most recent packet activity state |
| SSH shared mirror copy | tod/out/context-sync/ssh-shared/MIM_CONTEXT_EXPORT.latest.json | mirror | Remote MIM export, copied by sync scripts | Bridge/smoke checks, diagnostics | Non-canonical mirror (risk if treated as authority) | Can lag behind canonical request artifact |
| Handshake mirror | tod/out/context-sync/ssh-shared/MIM_TOD_HANDSHAKE_PACKET.latest.json | message + mirror | MIM handshake publisher | Listener/bridge checks | Contract context only | Used for compatibility/state checks |
| Integration status | shared_state/integration_status.json | cache + UI projection + mirror | Invoke-TODSharedStateSync.ps1 | TOD UI routes, operator chat status, checks | Derived authority in UI if canonical packet unavailable | Consolidated health/alignment state |
| Objectives projection | shared_state/objectives.json | mirror + cache | Sync scripts from tod/data/state.json and listener outputs | UI and next-step logic | Derived authority (risk when stale) | Tie-breaking logic prefers richer completion snapshots |
| Next actions | shared_state/next_actions.json | authority + UI projection | TOD orchestration / operator-chat path | Listener objective upsert path, UI | Can block objective upsert and execution routing | Critical disagreement surface |
| Bridge smoke output | shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json | diagnostic only | Invoke-TODMimBridgeSmoke.ps1 | Operators, diagnostics | Non-authoritative | Freshness and canonical mismatch signal |
| Runtime binding state | tod/out/context-sync/listener/TOD_MIM_RUNTIME_BINDING_STATE.latest.json | diagnostic only + stale guard / memory | Runtime validators/listener checks | Smoke/diagnostic tools | Non-authoritative | Contract mismatch and binding status details |
| Contract acceptance packet | shared_state/TOD_MIM_CONTRACT_ACCEPTANCE.latest.json | authority | Invoke-TODMimContractAcceptance.ps1 | Contract validators and gates | Contract authority for sync path trust | Checksum/contract acceptance state |
| Contract receipt packet | tod/out/context-sync/listener/TOD_MIM_CONTRACT_RECEIPT.latest.json and remote receipt export | message + authority | Contract acceptance script | MIM side and diagnostics | Contract handoff authority | Receipt proves contract acknowledgment |
| Drift guard state | shared_state/tod_watchdog_drift_guard.latest.json (+ log) | recovery artifact + stale guard / memory | Start-TODRecoveryWatchdog.ps1 | Recovery checks, UI diagnostics | Guard authority for restart/remediation decisions | Detects lag/stall and stale progression |
| Recovery watchdog state | shared_state/tod_recovery_watchdog.latest.json | recovery artifact + diagnostic only | Start-TODRecoveryWatchdog.ps1 | UI health and operators | Recovery status only | Captures restart/repair cycle details |
| Operator action audit | shared_state/tod_operator_chat_action_audit.latest.json (+ log) | UI projection + stale guard / memory | Operator chat action endpoints | UI and diagnostics | Local authority for one-time action governance | TTL/single-use confirmation tracking |
| Operator commitments | shared_state/tod_operator_chat_commitment.latest.json (+ log) | UI projection + stale guard / memory | Operator chat commitment endpoints | Next-step and operator UI | Local authority for commitment flow | Can influence what is considered in-progress |
| Training/authority summary artifacts | shared_state/tod_training_status.latest.json, shared_state/TOD_AUTHORITY_SUMMARY.latest.json | mirror + UI projection | TOD status publish paths | MIM arm views, diagnostics | Secondary/status authority only | Must not gate direct task execution |
| TOD UI project status projection | scripts/Start-TOD-UI.ps1 routes (for example /api/project-status, /api/activity-stream, operator chat endpoints) | UI projection | TOD API handlers | UI clients at localhost:8844 and operator console consumers | Projection only by design, but can become de-facto authority if source stale | Should reflect canonical packet/result before mirrored caches |

## 3) Endpoints, Scripts, Services, and UI Consumers Involved In Sync

### Scripts and services

- scripts/Start-TODMimPacketListener.ps1
  - Writes: ACK/RESULT/COMMAND_STATUS/listener_state/listener_activity artifacts
  - Reads: request/trigger packets, next_actions, objectives/integration mirrors
  - Service role: primary packet intake, dedup, stale guard, result emission

- scripts/Invoke-TODSharedStateSync.ps1
  - Writes: shared_state integration/objective projections
  - Reads: remote SSH mirrors and listener artifacts
  - Service role: projection reconciliation and alignment summary

- scripts/Invoke-TODMimBridgeSmoke.ps1
  - Writes: bridge smoke diagnostics
  - Reads: canonical request and mirror/export surfaces
  - Service role: health and mismatch signaling

- scripts/Invoke-TODMimContractAcceptance.ps1
  - Writes: contract acceptance and receipt artifacts
  - Reads: remote contract files and runtime packet surfaces
  - Service role: trust/contract gating metadata

- scripts/Start-TODRecoveryWatchdog.ps1
  - Writes: recovery and drift guard artifacts
  - Reads: shared status and sync freshness surfaces
  - Service role: recovery/stall remediation metadata

### UI/API consumers

- scripts/Start-TOD-UI.ps1
  - Consumes shared_state and listener-derived artifacts for:
    - /api/project-status
    - /api/activity-stream
    - operator-chat and operator action/commitment endpoints
  - Role: projection layer that can accidentally mask stale authority if source precedence is wrong

- UI client at http://localhost:8844/
  - Reads projected API payloads
  - Should remain projection-only and not become write-back authority for sync

- MIM console consumers
  - Consume contract/authority summary exports and cross-agent status packets
  - Should treat these as status projections, not canonical execution authority

## 4) Where Disagreement Can Block Execution

1. Canonical objective mismatch
- Incoming request objective disagrees with current in-progress objective in next_actions/objective projections.
- Effect: stale ignored behavior or blocked progression.

2. Objective upsert guard conflict
- Listener rejects or supersedes objective updates when next_actions indicates different active in-progress objective.
- Effect: request accepted at transport layer but blocked at objective gate.

3. Dedup/high-watermark disagreement
- Request signature or suffix ordinal handling disagrees with listener_state high-watermark memory.
- Effect: valid new work can be treated as replay, or stale work can be re-accepted.

4. Contract acceptance disagreement
- Contract/binding artifact mismatch between expected and observed packet contract states.
- Effect: acceptance/result path is blocked or downgraded to diagnostic failure.

5. Mirror-vs-canonical mismatch in smoke/guard checks
- SSH mirror export disagrees with canonical request packet.
- Effect: operational gating can hold dispatch despite recent canonical update.

## 5) Where Stale Data Can Become Authority

1. shared_state/integration_status.json used as de-facto authority when canonical request/result is unavailable.
2. shared_state/objectives.json reused after lag and treated as current execution truth.
3. next_actions.json stale current objective blocks valid incoming objective.
4. listener_state high-watermark persistence drift promotes outdated replay decisions.
5. SSH mirror exports from tod/out/context-sync/ssh-shared treated as canonical instead of diagnostic mirror.
6. UI projection endpoints become operational authority during transport errors if source precedence is not explicit.

## 6) Objective-only Matching Locations

Primary objective-centric matching in current stack:

- Listener intake and stale suppression logic in Start-TODMimPacketListener.ps1
- Objective upsert conflict checks against shared_state/next_actions.json
- Suffix/ordinal objective progression checks in stale_guard/high-watermark decisions
- Bridge smoke canonical objective alignment checks between request and export mirrors

Risk note:
- Objective-only matching can collapse distinct task intents into the same objective bucket, causing valid new requests to be blocked or stale requests to be promoted.

## 7) Writer/Reader Matrix (Condensed)

| Artifact Group | Primary Writers | Primary Readers |
|---|---|---|
| Canonical request/trigger | MIM dispatcher/services | Listener, bridge smoke, sync reconciliation |
| ACK/RESULT/STATUS packets | Listener | Shared-state sync, checks, UI projections |
| Shared-state projections | Invoke-TODSharedStateSync.ps1, TOD orchestration routes | TOD UI APIs, operator-chat surfaces, diagnostics |
| Contract artifacts | Contract acceptance script | Listener checks, smoke gates, MIM status consumers |
| Recovery/stale-guard artifacts | Recovery watchdog + listener | Health routes, diagnostics, recoupling checks |
| Operator governance artifacts | Operator-chat action/commitment routes | Operator UI and next-step selectors |

## 8) Dangerous Areas To Change First

Highest-risk sync points (change-safety warning):

1. Listener dedup and stale_guard objective/high-watermark logic
2. next_actions/objective upsert guard coupling
3. Canonical request source precedence vs SSH mirror exports
4. RESULT packet promotion pipeline into shared_state projections
5. UI source-precedence rules for project-status/activity projection under transport failures

## 9) Runtime/Generated Artifacts To Exclude From Authority Decisions

Treat as diagnostic/export only:

- shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json
- shared_state/TOD_MIM_REMOTE_* diagnostics
- tod/out/context-sync/ssh-shared/* mirror copies
- tod/out/background-chat/*
- tod/out/tests/tmp-* fixtures
- audit/log mirrors that do not drive dispatch contracts

## 10) Bottom Line

Current TOD/MIM sync is a mixed model: canonical request/result packets plus multiple mirrored projections and stale-guard memories. The most dangerous failure mode is not transport failure but authority confusion between canonical packet truth and stale mirrored projections. This map is the required baseline for message-ledger migration design.# TOD-MIM Current Sync Point Map

Generated: 2026-05-06
Objective: TOD-MIM-SYNC-POINT-INVENTORY
Scope: Current runtime synchronization only. No runtime behavior changes.

## 1) System Surfaces In Scope

- File artifacts under `runtime/shared`, `shared_state`, `tod/out/context-sync/*`, `tod/out/background-chat/*`
- TOD sync scripts and listener services
- TOD UI/API projection endpoints consuming sync state
- MIM remote shared artifacts fetched through SSH/SFTP
- Recovery/watchdog and stale-guard state used to gate execution

## 2) Current Sync Point Inventory

Legend for classification:
- message
- mirror
- authority
- cache
- UI projection
- recovery artifact
- stale guard / memory
- diagnostic only

| Sync Point | Location | Classification | Writers | Readers | Execution Authority Role | Notes |
|---|---|---|---|---|---|---|
| MIM task request packet | runtime/shared/MIM_TOD_TASK_REQUEST.latest.json (remote canonical copy under /home/testpilot/mim/runtime/shared) | authority + message | MIM dispatcher/service | Start-TODMimPacketListener.ps1, bridge smoke scripts | Primary ingress authority for TOD-side task intake | Canonical request source; disagreement with local objective can block dispatch |
| MIM trigger packet | runtime/shared/MIM_TO_TOD_TRIGGER.latest.json (remote + local mirror) | message | MIM dispatcher/service | Listener, bridge scripts | Trigger signal only | Carries task/correlation context |
| TOD ACK packet | tod/out/context-sync/listener/TOD_MIM_TASK_ACK.latest.json | message | Start-TODMimPacketListener.ps1 | Contract checks, diagnostics | Not primary authority | Contract-compliant acknowledgment output |
| TOD RESULT packet | tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json | authority + message | Start-TODMimPacketListener.ps1 | Invoke-TODSharedStateSync.ps1, recoupling gate checks | Completion/blocked result authority for MIM-facing sync | Promoted into shared_state objective/task projections |
| Command status packet | tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json | mirror + stale guard / memory | Listener | UI projections, sync checks | Secondary authority candidate (risk) | Contains stale_guard and high-watermark fields |
| Listener state store | tod/out/context-sync/listener/listener_state.json | stale guard / memory + recovery artifact | Listener | Listener dedup path, sync scripts | Local dedup authority | Prevents replay; high-watermark persistence |
| Listener activity snapshot | tod/out/context-sync/listener/listener_activity.json | diagnostic only + UI projection | Listener | UI/project-status views, diagnostics | Non-authoritative | Most recent packet activity state |
| SSH shared mirror copy | tod/out/context-sync/ssh-shared/MIM_CONTEXT_EXPORT.latest.json | mirror | Remote MIM export, copied by sync scripts | Bridge/smoke checks, diagnostics | Non-canonical mirror (risk if treated as authority) | Can lag behind canonical request artifact |
| Handshake mirror | tod/out/context-sync/ssh-shared/MIM_TOD_HANDSHAKE_PACKET.latest.json | message + mirror | MIM handshake publisher | Listener/bridge checks | Contract context only | Used for compatibility/state checks |
| Integration status | shared_state/integration_status.json | cache + UI projection + mirror | Invoke-TODSharedStateSync.ps1 | TOD UI routes, operator chat status, checks | Derived authority in UI if canonical packet unavailable | Consolidated health/alignment state |
| Objectives projection | shared_state/objectives.json | mirror + cache | Sync scripts from tod/data/state.json and listener outputs | UI and next-step logic | Derived authority (risk when stale) | Tie-breaking logic prefers richer completion snapshots |
| Next actions | shared_state/next_actions.json | authority + UI projection | TOD orchestration / operator-chat path | Listener objective upsert path, UI | Can block objective upsert and execution routing | Critical disagreement surface |
| Bridge smoke output | shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json | diagnostic only | Invoke-TODMimBridgeSmoke.ps1 | Operators, diagnostics | Non-authoritative | Freshness and canonical mismatch signal |
| Runtime binding state | tod/out/context-sync/listener/TOD_MIM_RUNTIME_BINDING_STATE.latest.json | diagnostic only + stale guard / memory | Runtime validators/listener checks | Smoke/diagnostic tools | Non-authoritative | Contract mismatch and binding status details |
| Contract acceptance packet | shared_state/TOD_MIM_CONTRACT_ACCEPTANCE.latest.json | authority | Invoke-TODMimContractAcceptance.ps1 | Contract validators and gates | Contract authority for sync path trust | Checksum/contract acceptance state |
| Contract receipt packet | tod/out/context-sync/listener/TOD_MIM_CONTRACT_RECEIPT.latest.json and remote receipt export | message + authority | Contract acceptance script | MIM side and diagnostics | Contract handoff authority | Receipt proves contract acknowledgment |
| Drift guard state | shared_state/tod_watchdog_drift_guard.latest.json (+ log) | recovery artifact + stale guard / memory | Start-TODRecoveryWatchdog.ps1 | Recovery checks, UI diagnostics | Guard authority for restart/remediation decisions | Detects lag/stall and stale progression |
| Recovery watchdog state | shared_state/tod_recovery_watchdog.latest.json | recovery artifact + diagnostic only | Start-TODRecoveryWatchdog.ps1 | UI health and operators | Recovery status only | Captures restart/repair cycle details |
| Operator action audit | shared_state/tod_operator_chat_action_audit.latest.json (+ log) | UI projection + stale guard / memory | Operator chat action endpoints | UI and diagnostics | Local authority for one-time action governance | TTL/single-use confirmation tracking |
| Operator commitments | shared_state/tod_operator_chat_commitment.latest.json (+ log) | UI projection + stale guard / memory | Operator chat commitment endpoints | Next-step and operator UI | Local authority for commitment flow | Can influence what is considered in-progress |
| Training/authority summary artifacts | shared_state/tod_training_status.latest.json, shared_state/TOD_AUTHORITY_SUMMARY.latest.json | mirror + UI projection | TOD status publish paths | MIM arm views, diagnostics | Secondary/status authority only | Must not gate direct task execution |
| TOD UI project status projection | scripts/Start-TOD-UI.ps1 routes (for example /api/project-status, /api/activity-stream, operator chat endpoints) | UI projection | TOD API handlers | UI clients at localhost:8844 and operator console consumers | Projection only by design, but can become de-facto authority if source stale | Should reflect canonical packet/result before mirrored caches |

## 3) Endpoints, Scripts, Services, and UI Consumers Involved In Sync

### Scripts and services

- scripts/Start-TODMimPacketListener.ps1
  - Writes: ACK/RESULT/COMMAND_STATUS/listener_state/listener_activity artifacts
  - Reads: request/trigger packets, next_actions, objectives/integration mirrors
  - Service role: primary packet intake, dedup, stale guard, result emission

- scripts/Invoke-TODSharedStateSync.ps1
  - Writes: shared_state integration/objective projections
  - Reads: remote SSH mirrors and listener artifacts
  - Service role: projection reconciliation and alignment summary

- scripts/Invoke-TODMimBridgeSmoke.ps1
  - Writes: bridge smoke diagnostics
  - Reads: canonical request and mirror/export surfaces
  - Service role: health and mismatch signaling

- scripts/Invoke-TODMimContractAcceptance.ps1
  - Writes: contract acceptance and receipt artifacts
  - Reads: remote contract files and runtime packet surfaces
  - Service role: trust/contract gating metadata

- scripts/Start-TODRecoveryWatchdog.ps1
  - Writes: recovery and drift guard artifacts
  - Reads: shared status and sync freshness surfaces
  - Service role: recovery/stall remediation metadata

### UI/API consumers

- scripts/Start-TOD-UI.ps1
  - Consumes shared_state and listener-derived artifacts for:
    - /api/project-status
    - /api/activity-stream
    - operator-chat and operator action/commitment endpoints
  - Role: projection layer that can accidentally mask stale authority if source precedence is wrong

- UI client at http://localhost:8844/
  - Reads projected API payloads
  - Should remain projection-only and not become write-back authority for sync

- MIM console consumers
  - Consume contract/authority summary exports and cross-agent status packets
  - Should treat these as status projections, not canonical execution authority

## 4) Where Disagreement Can Block Execution

1. Canonical objective mismatch
- Incoming request objective disagrees with current in-progress objective in next_actions/objective projections.
- Effect: stale ignored behavior or blocked progression.

2. Objective upsert guard conflict
- Listener rejects or supersedes objective updates when next_actions indicates different active in-progress objective.
- Effect: request accepted at transport layer but blocked at objective gate.

3. Dedup/high-watermark disagreement
- Request signature or suffix ordinal handling disagrees with listener_state high-watermark memory.
- Effect: valid new work can be treated as replay, or stale work can be re-accepted.

4. Contract acceptance disagreement
- Contract/binding artifact mismatch between expected and observed packet contract states.
- Effect: acceptance/result path is blocked or downgraded to diagnostic failure.

5. Mirror-vs-canonical mismatch in smoke/guard checks
- SSH mirror export disagrees with canonical request packet.
- Effect: operational gating can hold dispatch despite recent canonical update.

## 5) Where Stale Data Can Become Authority

1. shared_state/integration_status.json used as de-facto authority when canonical request/result is unavailable.
2. shared_state/objectives.json reused after lag and treated as current execution truth.
3. next_actions.json stale current objective blocks valid incoming objective.
4. listener_state high-watermark persistence drift promotes outdated replay decisions.
5. SSH mirror exports from tod/out/context-sync/ssh-shared treated as canonical instead of diagnostic mirror.
6. UI projection endpoints become operational authority during transport errors if source precedence is not explicit.

## 6) Objective-only Matching Locations

Primary objective-centric matching in current stack:

- Listener intake and stale suppression logic in Start-TODMimPacketListener.ps1
- Objective upsert conflict checks against shared_state/next_actions.json
- Suffix/ordinal objective progression checks in stale_guard/high-watermark decisions
- Bridge smoke canonical objective alignment checks between request and export mirrors

Risk note:
- Objective-only matching can collapse distinct task intents into the same objective bucket, causing valid new requests to be blocked or stale requests to be promoted.

## 7) Writer/Reader Matrix (Condensed)

| Artifact Group | Primary Writers | Primary Readers |
|---|---|---|
| Canonical request/trigger | MIM dispatcher/services | Listener, bridge smoke, sync reconciliation |
| ACK/RESULT/STATUS packets | Listener | Shared-state sync, checks, UI projections |
| Shared-state projections | Invoke-TODSharedStateSync.ps1, TOD orchestration routes | TOD UI APIs, operator-chat surfaces, diagnostics |
| Contract artifacts | Contract acceptance script | Listener checks, smoke gates, MIM status consumers |
| Recovery/stale-guard artifacts | Recovery watchdog + listener | Health routes, diagnostics, recoupling checks |
| Operator governance artifacts | Operator-chat action/commitment routes | Operator UI and next-step selectors |

## 8) Dangerous Areas To Change First

Highest-risk sync points (change-safety warning):

1. Listener dedup and stale_guard objective/high-watermark logic
2. next_actions/objective upsert guard coupling
3. Canonical request source precedence vs SSH mirror exports
4. RESULT packet promotion pipeline into shared_state projections
5. UI source-precedence rules for project-status/activity projection under transport failures

## 9) Runtime/Generated Artifacts To Exclude From Authority Decisions

Treat as diagnostic/export only:

- shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json
- shared_state/TOD_MIM_REMOTE_* diagnostics
- tod/out/context-sync/ssh-shared/* mirror copies
- tod/out/background-chat/*
- tod/out/tests/tmp-* fixtures
- audit/log mirrors that do not drive dispatch contracts

## 10) Bottom Line

Current TOD/MIM sync is a mixed model: canonical request/result packets plus multiple mirrored projections and stale-guard memories. The most dangerous failure mode is not transport failure but authority confusion between canonical packet truth and stale mirrored projections. This map is the required baseline for message-ledger migration design.