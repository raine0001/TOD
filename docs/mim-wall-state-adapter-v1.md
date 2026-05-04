# mim_wall State Adapter v1

Status: First adapter specification derived from Shared Integration Contract v1

Purpose: Define the first concrete app adapter in the MIM ecosystem.

This adapter is intentionally narrow.

It exists to let TOD and MIM consume the current state of `mim_wall` without writing back into the Android app during the first rollout stage.

## Adapter Identity

- adapter_id: `mim_wall_state_adapter_v1`
- project_id: `mim_wall`
- contract: `docs/shared-integration-contract-v1.md`
- rollout_stage: `phase_1_read_state`
- write_mode: `read-only`

## Mission

Expose the minimum state needed for:

1. mobile continuity
2. queue-aware handoff reasoning
3. async caller and thread awareness
4. feedback collection for later policy improvement
5. audit-ready reasoning inside TOD and MIM

This adapter does not control the app.

## Source Surfaces In mim_wall

The adapter is built from these existing app seams:

- `CallSessionStore.latestEvents()`
- `CallSessionStore.latestFeedback()`
- `CallSessionStore.unifiedActionQueue()`
- `CallSessionStore.exportTimelineReport()`
- `CallSessionEvent`
- `FeedbackEvent`
- `ActionQueueItem`
- `MimMasterControlStore`
- `GuardianCallScreeningService`
- `IncomingSmsReceiver`
- `CallActionReceiver`

Primary implementation anchors:

- `app/src/main/java/com/dave/callguardian/session/CallSessionStore.kt`
- `app/src/main/java/com/dave/callguardian/session/CallSessionModels.kt`
- `app/src/main/java/com/dave/callguardian/callscreening/GuardianCallScreeningService.kt`
- `app/src/main/java/com/dave/callguardian/messaging/IncomingSmsReceiver.kt`
- `app/src/main/java/com/dave/callguardian/notifications/CallActionReceiver.kt`

## Phase 1 Output Model

The adapter exports one canonical snapshot document.

Preferred filename:

- `MIM_WALL_STATE_ADAPTER.latest.json`

Preferred TOD-side mirror location:

- `tod/out/context-sync/mim_wall/MIM_WALL_STATE_ADAPTER.latest.json`

The payload shape is defined by `tod/templates/mim-wall-state-adapter-snapshot-v1.json`.

### Required top-level sections

1. `project_id`
2. `adapter_id`
3. `generated_at`
4. `device`
5. `control_state`
6. `queue`
7. `timeline`
8. `feedback`
9. `export_meta`

## Required Field Mapping

### Queue mapping

Map `ActionQueueItem` to canonical queue entries.

| mim_wall field | adapter field | notes |
| --- | --- | --- |
| `id` | `queue[].item_id` | preserve app-local id |
| `timestampMs` | `queue[].timestamp_ms` | keep native millis |
| `number` | `queue[].thread_key` | default phone-thread key |
| `status` | `queue[].status` | preserve current queue status |
| `summary` | `queue[].summary` | preserve current summary |
| `source` | `queue[].source` | preserve source category |

### Timeline mapping

Map `CallSessionEvent` to canonical timeline entries.

| mim_wall field | adapter field |
| --- | --- |
| `timestampMs` | `timeline[].timestamp_ms` |
| `category` | `timeline[].category` |
| `detail` | `timeline[].detail` |

### Feedback mapping

Map `FeedbackEvent` to canonical feedback entries.

| mim_wall field | adapter field |
| --- | --- |
| `timestampMs` | `feedback[].timestamp_ms` |
| `label` | `feedback[].label` |
| `note` | `feedback[].note` |

### Control mapping

Map global app control state.

| source | adapter field | notes |
| --- | --- | --- |
| `MimMasterControlStore.isEnabled()` | `control_state.mim_enabled` | whether automation is globally enabled |
| adapter rollout constant | `control_state.mode` | set to `read_only_phase` for v1 |

## Canonical Event Projection Rules

The snapshot itself is not the final event stream.

TOD or MIM may project the snapshot into event envelopes defined by `docs/shared-integration-contract-v1.md` using these mappings:

- queue item discovered -> `queue.item.discovered`
- queue status changed -> `queue.item.status_changed`
- screening timeline category -> `communication.call.screened`
- busy intercept detail match -> `communication.call.busy_intercepted`
- SMS timeline category -> `communication.sms.received` or `communication.sms.reply_state_changed`
- feedback rows -> `feedback.user.labeled`
- master control flip -> `control.mim_enabled.changed`

## Transport Rule

Phase 1 transport is snapshot-based.

Allowed transport options:

1. device-side file export copied into TOD context sync
2. adb pull from a known device export location
3. future workstation sync bridge that writes the same canonical JSON file

All transport methods must produce the same payload shape.

Do not build multiple incompatible transport payloads.

## Authority Rule

This adapter exposes state.

It does not grant write authority for:

- call actions
- text sending
- calendar insertion
- rule changes
- template changes
- voice-provider mode changes
- Android permission changes

If TOD or MIM wants those later, they require a promoted adapter stage and explicit write contract.

## Verification Gate

Before this adapter is treated as production-ready, verify against the real `mim_wall` host project:

1. `./gradlew.bat assembleDebug`
2. `./gradlew.bat lintDebug`
3. `powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1`
4. adapter snapshot schema validation against `tod/templates/mim-wall-state-adapter-snapshot-v1.json`

## Promotion Conditions

Promote this adapter beyond phase 1 only if all of the following are true:

1. snapshot format is stable across repeated exports
2. queue, timeline, and feedback fields are enough for mobile continuity use cases
3. TOD can reason over the snapshot without treating historical rows as live authority
4. downstream identity normalization is stable enough for thread correlation

## Next Build Rule

If a later task implements code for this adapter, it must preserve:

- the payload shape in `tod/templates/mim-wall-state-adapter-snapshot-v1.json`
- the read-only boundary in phase 1
- the shared event and audit envelopes from `docs/shared-integration-contract-v1.md`

No second app adapter should be built before this first adapter has one stable payload and one stable consumer path.
