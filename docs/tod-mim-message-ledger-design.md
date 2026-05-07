# TOD-MIM Message Ledger Design

Generated: 2026-05-06
Objective: TOD-MIM-MESSAGE-LEDGER-DESIGN
Input baseline: docs/tod-mim-current-sync-point-map.md
Constraint: Design only. No runtime migration implementation in this step.

## 1) Design Intent

Replace fragile full-state synchronization coupling with durable message-based coordination.

Principle:
- MIM and TOD are independent agents.
- Agreement is at message and task contract level, not full mirrored state.

Target model:
- DB = durable communication ledger
- JSON = export/debug mirror only
- UI = projection only

## 2) Core Database Schema

Minimum required tables:

1. agent_messages
2. agent_message_events
3. agent_task_claims
4. agent_task_results
5. agent_heartbeats
6. agent_conversation_threads
7. agent_delivery_attempts
8. agent_dead_letters

### 2.1 agent_messages

Purpose:
- Canonical durable message envelope for inter-agent coordination.

Proposed columns:
- message_id (pk, uuid/text)
- thread_id (fk to agent_conversation_threads)
- from_agent
- to_agent
- task_id (nullable)
- correlation_id
- message_type
- payload_json
- status
- created_at
- acknowledged_at (nullable)
- completed_at (nullable)
- expires_at (nullable)
- superseded_by_message_id (nullable)

Indexes:
- (to_agent, status, created_at)
- (correlation_id)
- (task_id)
- (thread_id, created_at)
- partial/dead-letter index on status in (expired, failed, dead_letter)

### 2.2 agent_message_events

Purpose:
- Immutable event trail for each message lifecycle transition.

Columns:
- event_id (pk)
- message_id (fk)
- event_type
- event_status
- event_payload_json
- created_at
- actor_agent

### 2.3 agent_task_claims

Purpose:
- Explicit ownership/claim handoff so objective-only matching stops being authority.

Columns:
- claim_id (pk)
- task_id
- message_id (fk)
- claimed_by_agent
- claim_status
- created_at
- released_at (nullable)

### 2.4 agent_task_results

Purpose:
- Durable task outcome independent from UI/shared mirror artifacts.

Columns:
- result_id (pk)
- task_id
- message_id (fk)
- correlation_id
- result_status
- result_payload_json
- created_at

### 2.5 agent_heartbeats

Purpose:
- Transport/service liveness without conflating with task status.

Columns:
- heartbeat_id (pk)
- agent_id
- status
- heartbeat_payload_json
- created_at
- expires_at

### 2.6 agent_conversation_threads

Purpose:
- Group message exchange into conversation/task threads.

Columns:
- thread_id (pk)
- thread_type
- root_message_id (nullable)
- created_by_agent
- created_at
- closed_at (nullable)
- thread_state

### 2.7 agent_delivery_attempts

Purpose:
- Retry accounting and delivery diagnostics.

Columns:
- attempt_id (pk)
- message_id (fk)
- attempt_number
- delivery_target
- attempt_status
- error_code (nullable)
- error_detail (nullable)
- attempted_at

### 2.8 agent_dead_letters

Purpose:
- Terminal failed/expired messages requiring triage.

Columns:
- dead_letter_id (pk)
- message_id (fk)
- dead_letter_reason
- final_status
- moved_at
- recovery_hint_json (nullable)

## 3) Message Types

Required message_type values:
- request
- ack
- progress
- result
- blocked
- clarification_request
- cancel
- retry
- handoff
- heartbeat

## 4) Message Lifecycle

Required lifecycle statuses:
- created
- delivered
- acknowledged
- running
- completed
- blocked
- failed
- expired
- superseded

Status transition model:
- request: created -> delivered -> acknowledged -> running -> completed|blocked|failed|expired|superseded
- non-failure rule: disagreement/no response is status progression, not process crash inference.

## 5) Minimal Agreement Contract

Fields that must agree across agents:
- task_id
- message_id
- correlation_id
- sender (from_agent)
- receiver (to_agent)
- status

Everything else is supplemental payload.

## 6) What Must Not Be Synchronized

Explicit non-sync set:
- UI state
- internal reasoning
- local metrics
- stale guard memory internals
- objective history as transport authority
- training reports

These remain local diagnostics or projections.

## 7) JSON Compatibility Strategy

### 7.1 Legacy files that become generated DB exports

- runtime/shared/MIM_TOD_TASK_REQUEST.latest.json (export view)
- runtime/shared/MIM_TO_TOD_TRIGGER.latest.json (export view)
- tod/out/context-sync/listener/TOD_MIM_TASK_ACK.latest.json (export view)
- tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json (export view)
- tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json (export projection)
- shared_state/integration_status.json (projection generated from DB + health checks)

### 7.2 Files that become diagnostic only

- shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json
- shared_state/TOD_MIM_REMOTE_* diagnostic artifacts
- tod/out/context-sync/ssh-shared/*
- tod/out/background-chat/*
- watchdog drift logs and recoupling smoke-only outputs

### 7.3 Files likely to become obsolete as authority

- objective-only stale suppression as an execution gate in shared projection files
- mirror-based command status authority where canonical DB status is available

## 8) Safety Rules

1. Canonical authority for inter-agent coordination is DB rows in message/task tables.
2. JSON artifacts are generated mirrors and cannot gate task execution once DB is authoritative.
3. UI endpoints cannot infer process crash from no response; they must project message status.
4. Objective disagreement becomes a blocked/clarification message state, not transport lock.

## 9) Open Design Decisions

1. DB engine selection and hosting boundary (TOD local vs shared service)
2. Exactly-once versus at-least-once delivery semantics (with idempotent message_id)
3. Thread closure policy (time-based versus explicit close message)
4. Retention and archival policy for message events and dead letters

## 10) Expected Outcome

When this design is implemented through phased migration, TOD and MIM coordination is driven by durable message lifecycle state, and stale mirrored files can no longer become accidental execution authority.