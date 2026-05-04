# Shared Integration Contract v1

Status: Baseline contract after cross-project ecosystem discovery

Purpose: Define the first common contract for integrating the current MIM application ecosystem without collapsing the projects into one merged repository.

Architecture rule:

- MIM is the shared intelligence layer.
- TOD is the orchestration and audit spine.
- Each application remains an independent capability node behind a stable adapter contract.

## Scope

This contract standardizes only the shared seam between ecosystem applications and the MIM plus TOD core.

This v1 covers:

1. canonical identity model
2. canonical event envelope
3. canonical decision and audit envelope
4. capability registry schema
5. first adapter contract for `mim_wall`

This v1 does not attempt to define:

- internal repo architecture for every project
- direct database sharing across apps
- a universal RPC layer for all systems
- immediate write access from TOD into every app

## Integration Posture

The ecosystem should be federated through contracts, not merged into a giant repo.

Current ecosystem roles:

- `mim_wall`: real-world communications edge
- `comm_app`: business execution layer
- `coachMIM`: structured long-memory and user-state layer
- `mim_pulz`: policy and explainability layer
- `Mimir`: media, search, and production layer
- `mimrobots.com`: publish and presentation layer

The first adapter after this contract is `mim_wall`, and its first stage is read-only state export.

## 1) Canonical Identity Model

Goal: let all connected systems refer to the same people, devices, sessions, and applications without inventing incompatible local aliases.

### Identity object

```json
{
  "identity_id": "subj_01HZY8Y3Q4G5H6J7K8L9M0N1P2",
  "identity_type": "person",
  "role": "caller",
  "display_name": "Unknown caller",
  "external_refs": {
    "phone_e164": "+15551234567",
    "app_user_id": null,
    "crm_contact_id": null,
    "device_contact_id": null
  },
  "source": {
    "project_id": "mim_wall",
    "system": "mim_wall",
    "captured_at": "2026-04-13T00:00:00Z"
  },
  "confidence": 0.92,
  "labels": ["unknown", "external", "phone-contact"]
}
```

### Required identity rules

- `identity_id` is the canonical cross-system identifier used after normalization.
- `identity_type` must be one of: `person`, `organization`, `device`, `service`, `thread`, `session`, `project`.
- `role` is context-specific and may vary by event, for example `caller`, `owner`, `rep`, `coach_user`, `operator`.
- `external_refs` stores system-native identifiers and raw keys.
- `source.project_id` identifies the app that first emitted or resolved the identity.
- `confidence` is required whenever the identity is inferred rather than confirmed.

### Identity normalization rules

- Phone numbers should normalize to E.164 when possible.
- App-local IDs must remain preserved in `external_refs`; do not overwrite local truth.
- A single person may appear in multiple systems with different native keys; those map to one canonical `identity_id` only after explicit reconciliation.
- No cross-app write action should depend on display name matching alone.

## 2) Canonical Event Envelope

Goal: every app can publish state and activity in a form MIM and TOD can consume without app-specific parsing logic at every downstream consumer.

### Event envelope

```json
{
  "event_id": "evt_01HZY92TQ0W7M4N8A5J2X6R3K9",
  "event_type": "communication.call.screened",
  "occurred_at": "2026-04-13T00:00:00Z",
  "project_id": "mim_wall",
  "adapter_id": "mim_wall_state_adapter_v1",
  "subject": {
    "identity_id": "subj_01HZY8Y3Q4G5H6J7K8L9M0N1P2",
    "role": "caller"
  },
  "channel": {
    "kind": "phone",
    "thread_id": "+15551234567",
    "direction": "inbound"
  },
  "state": {
    "status": "awaiting_reply",
    "summary": "Busy-call follow-up started",
    "source_category": "screening"
  },
  "payload": {
    "raw_category": "screening",
    "detail": "Busy-call interception for +15551234567: intercepted=true sms_sent=true"
  },
  "correlation": {
    "trace_id": "trace_communications_0001",
    "thread_key": "+15551234567",
    "origin_event_id": null
  },
  "confidence": 0.95,
  "mutability": "historical",
  "privacy": {
    "contains_pii": true,
    "redaction_level": "restricted"
  }
}
```

### Required event fields

- `event_id`: globally unique event identifier.
- `event_type`: canonical dotted classification.
- `occurred_at`: ISO-8601 UTC timestamp.
- `project_id`: emitting app.
- `adapter_id`: emitting adapter contract version.
- `subject`: canonical identity binding.
- `payload`: raw or normalized app-specific data.
- `correlation`: trace and thread continuity.
- `mutability`: `historical`, `current_state`, or `derived_projection`.

### Event type guidance

Recommended event families:

- `communication.call.*`
- `communication.sms.*`
- `queue.item.*`
- `feedback.user.*`
- `policy.config.*`
- `decision.route.*`
- `capability.execution.*`
- `publish.content.*`

### Event handling rules

- Historical facts must not be treated as live task authority without an explicit current-state marker.
- Derived projections are allowed, but must declare `mutability=derived_projection`.
- Raw app detail may be preserved in `payload`, but cross-system logic should rely on normalized `state` and `event_type`.

## 3) Canonical Decision And Audit Envelope

Goal: every cross-system recommendation, policy decision, or execution decision can be audited later with enough rationale to explain what happened.

### Decision and audit envelope

```json
{
  "decision_id": "dec_01HZY9BY0Q6K7P8R1S2T3U4V5W",
  "decision_type": "handoff.recommendation",
  "created_at": "2026-04-13T00:00:00Z",
  "project_id": "tod",
  "producer": {
    "system": "tod",
    "component": "orchestrator",
    "actor": "tod"
  },
  "subject": {
    "identity_id": "subj_01HZY8Y3Q4G5H6J7K8L9M0N1P2",
    "role": "caller"
  },
  "inputs": {
    "event_ids": ["evt_01HZY92TQ0W7M4N8A5J2X6R3K9"],
    "capability_refs": ["mim_wall.queue.read"],
    "policy_refs": ["mim_wall.screening.rules.v1"]
  },
  "decision": {
    "outcome": "continue_async_text_path",
    "confidence": 0.88,
    "requires_human_review": false,
    "write_authority_required": false
  },
  "rationale": {
    "summary": "Caller is already in an awaiting-reply state after busy-call intercept.",
    "factors": [
      "Existing queue state is awaiting_reply",
      "Busy interception already sent text prompt",
      "No override or closure signal observed"
    ]
  },
  "constraints": {
    "policy_boundary": "read_only_adapter_phase",
    "blocked_actions": ["force_send_sms", "modify_android_permissions"]
  },
  "trace": {
    "trace_id": "trace_communications_0001",
    "source_of_truth": "mim_wall_state_adapter_v1",
    "mutability": "derived_projection"
  },
  "artifacts": {
    "status_path": "shared_state/integration_status.json",
    "supporting_files": []
  }
}
```

### Required audit rules

- Every non-trivial decision must include `inputs`, `decision`, and `rationale`.
- If a decision is inferred from projected state, `trace.source_of_truth` must say so.
- `write_authority_required=true` is mandatory for any action that mutates a remote app.
- `requires_human_review=true` is mandatory whenever the contract, policy boundary, or confidence threshold is not satisfied.

## 4) Capability Registry Schema

Goal: expose what each connected app can do, what it can publish, and how safe it is for TOD or MIM to consume or invoke.

### Capability registry entry

```json
{
  "capability_id": "mim_wall.queue.read",
  "project_id": "mim_wall",
  "display_name": "Read unified action queue",
  "kind": "state-reader",
  "adapter_id": "mim_wall_state_adapter_v1",
  "entry_mode": "read-only",
  "interaction_class": "mobile-communications",
  "state_inputs": ["queue", "timeline", "feedback"],
  "events_emitted": [
    "queue.item.discovered",
    "communication.sms.reply_state_changed",
    "feedback.user.labeled"
  ],
  "actions_supported": [],
  "decision_support": ["continuity", "handoff", "mobile_access_path"],
  "write_scope": "none",
  "verification_gate": [
    "./gradlew.bat assembleDebug",
    "./gradlew.bat lintDebug",
    "powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/automated_dialog_regression.ps1 -Iterations 1"
  ],
  "adapter_stage": "phase_1_read_state"
}
```

### Required capability fields

- `capability_id`: stable unique capability key.
- `project_id`: owning application.
- `kind`: one of `state-reader`, `event-publisher`, `command-adapter`, `policy-sync`, `decision-engine`, `publish-surface`.
- `entry_mode`: `read-only`, `guarded-write`, `human-mediated`, or `review-only`.
- `events_emitted`: normalized event types produced by this capability.
- `actions_supported`: bounded mutation actions, if any.
- `write_scope`: explicit mutation boundary.
- `adapter_stage`: maturity stage for rollout.

### Capability governance rules

- No capability may advertise write behavior without an explicit `write_scope`.
- A capability in `phase_1_read_state` must emit events only and must not mutate the remote app.
- Verification gates must be tied to the real host application, not invented synthetic checks.

## 5) First Adapter Contract: mim_wall

Adapter id: `mim_wall_state_adapter_v1`

Role: First real ecosystem adapter. Read-only export of queue, timeline, feedback, and control posture from the Android communications edge.

Why first:

- highest real-world payoff
- strongest mobile continuity value
- strongest direct path toward “MIM while you are away”

### Source surfaces already present in mim_wall

Current concrete seams in `E:/mim_wall`:

- `CallSessionStore.latestEvents()` in `app/src/main/java/com/dave/callguardian/session/CallSessionStore.kt`
- `CallSessionStore.latestFeedback()` in `app/src/main/java/com/dave/callguardian/session/CallSessionStore.kt`
- `CallSessionStore.unifiedActionQueue()` in `app/src/main/java/com/dave/callguardian/session/CallSessionStore.kt`
- `CallSessionStore.exportTimelineReport()` in `app/src/main/java/com/dave/callguardian/session/CallSessionStore.kt`
- `CallSessionEvent`, `FeedbackEvent`, and `ActionQueueItem` in `app/src/main/java/com/dave/callguardian/session/CallSessionModels.kt`
- `MimMasterControlStore` in `app/src/main/java/com/dave/callguardian/domain/MimMasterControlStore.kt`
- `ScreeningRulesStore` in `app/src/main/java/com/dave/callguardian/domain/ScreeningRulesStore.kt`
- `MessageTemplateStore` in `app/src/main/java/com/dave/callguardian/domain/MessageTemplateStore.kt`
- `VoiceAgentFactory` in `app/src/main/java/com/dave/callguardian/voice/VoiceAgentFactory.kt`
- `GuardianCallScreeningService` in `app/src/main/java/com/dave/callguardian/callscreening/GuardianCallScreeningService.kt`
- `IncomingSmsReceiver` in `app/src/main/java/com/dave/callguardian/messaging/IncomingSmsReceiver.kt`
- `CallActionReceiver` in `app/src/main/java/com/dave/callguardian/notifications/CallActionReceiver.kt`

### Adapter stage

Initial adapter stage:

- `phase_1_read_state`

Allowed behavior in this stage:

- read queue state
- read recent events
- read feedback labels
- read whether MIM automation is globally enabled
- publish normalized events into TOD and MIM
- support mobile continuity and handoff reasoning

Forbidden behavior in this stage:

- change Android permissions remotely
- force-call or force-text actions from TOD
- mutate screening rules remotely
- mutate message templates remotely
- inject UI actions into the device session

### Read model for mim_wall adapter

The adapter must export these normalized collections:

```json
{
  "project_id": "mim_wall",
  "adapter_id": "mim_wall_state_adapter_v1",
  "generated_at": "2026-04-13T00:00:00Z",
  "control_state": {
    "mim_enabled": true,
    "mode": "read_only_phase"
  },
  "queue": [
    {
      "thread_key": "+15551234567",
      "status": "awaiting_reply",
      "summary": "Busy-call follow-up started",
      "source": "screening",
      "timestamp_ms": 1712966400000
    }
  ],
  "timeline": [
    {
      "category": "screening",
      "detail": "Busy-call interception for +15551234567: intercepted=true sms_sent=true",
      "timestamp_ms": 1712966400000
    }
  ],
  "feedback": [
    {
      "label": "correct_spam",
      "note": "Caller was marketing spam",
      "timestamp_ms": 1712966500000
    }
  ]
}
```

### Required event mappings

The adapter should emit at minimum:

- `queue.item.discovered`
- `queue.item.status_changed`
- `communication.call.screened`
- `communication.call.busy_intercepted`
- `communication.sms.received`
- `communication.sms.reply_state_changed`
- `feedback.user.labeled`
- `control.mim_enabled.changed`

### Identity rules for mim_wall

- The default thread subject is the normalized phone number.
- `thread_key` should be the normalized phone number unless a stronger thread identifier exists later.
- Owner identity should be the device owner or app owner, not the caller.
- Caller names from contacts remain advisory labels until linked to a stronger canonical identity.

### First integration use cases

This first adapter exists to support only these MIM plus TOD workflows:

1. mobile continuity
2. async caller/thread awareness
3. queue-aware handoff decisions
4. feedback capture for future policy improvement
5. audit-ready reasoning about what mim_wall already knows

### Promotion path after phase 1

Only after phase 1 is stable should the adapter expand:

- `phase_2_policy_sync`: guarded writes into screening rules and message templates
- `phase_3_human_mediated_actions`: human-approved callback or reply suggestions
- `phase_4_bounded_write_actions`: tightly controlled remote action requests with explicit write authority

## Implementation Rule

No additional adapters should be built until this contract is treated as the baseline reference for:

- identity
- events
- decisions and audit
- capability registry entries
- adapter rollout stages

That prevents `comm_app`, `coachMIM`, `Mimir`, `mim_pulz`, and `mimrobots.com` from drifting into five incompatible integration styles.

## Immediate Next Build Step

The first concrete adapter artifacts after this contract are now:

- `docs/mim-wall-state-adapter-v1.md`
- `tod/templates/mim-wall-state-adapter-snapshot-v1.json`

No broader multi-app adapter wave should begin before that first adapter remains stable against this contract.
