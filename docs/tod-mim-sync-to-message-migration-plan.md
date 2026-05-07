# TOD-MIM Sync To Message-Ledger Migration Plan

Generated: 2026-05-06
Objective: TOD-MIM-MESSAGE-LEDGER-DESIGN
Constraint: Migration design only. No runtime behavior changes in this deliverable.

## 1) Migration Strategy

Use a surgical bridge migration to avoid destabilizing active TOD/MIM coordination.

Phases:
1. observe-only
2. dual-write
3. DB-read preferred
4. JSON export-only
5. legacy authority removal

## 2) Phase Definitions

## Phase A: observe-only

Goal:
- Introduce DB ledger schema and write observational telemetry only.

Behavior:
- Existing JSON authority model remains unchanged.
- DB receives shadow records for request/ack/progress/result/block events.

Exit criteria:
- DB event capture coverage >= 99% of current packet lifecycle events.
- No user-visible behavior change.

## Phase B: dual-write

Goal:
- Keep current JSON writers, add DB writes in same transaction boundary (best effort with reconciliation).

Behavior:
- JSON remains authority.
- DB keeps shadow truth with message and event rows.

Exit criteria:
- Reconciliation shows no sustained divergence between JSON authority and DB shadow for key contract fields.

## Phase C: DB-read preferred

Goal:
- Move consumers to read DB first, JSON fallback only when DB unavailable.

Behavior:
- TOD UI and MIM UI endpoints become DB-first projections.
- Listener/sync decision paths use DB status when present.

Exit criteria:
- Fallback read ratio remains low and controlled.
- Blocked/completed/running statuses are consistent across consumers.

## Phase D: JSON export-only

Goal:
- Convert legacy JSON sync artifacts into generated exports from DB state.

Behavior:
- No execution path treats JSON files as authority.
- JSON is retained for compatibility, debugging, and external tooling transition.

Exit criteria:
- All execution gates reference DB, not JSON mirrors.

## Phase E: legacy authority removal

Goal:
- Remove or downgrade old sync authority logic that can cause stale lockouts.

Target removals/downgrades:
- objective alignment blockers as transport lock
- stale_guard as authority lock
- shared truth as execution lock
- mirror-based status authority

Exit criteria:
- Message lifecycle states become the only inter-agent coordination contract for execution status.

## 3) Mapping From Current Risks To Migration Controls

| Current Risk | Migration Control |
|---|---|
| Objective mismatch blocks dispatch | Represent disagreement as blocked/clarification_request message status instead of hard transport lock |
| Stale mirror promoted to authority | DB canonical read precedence in Phase C+, JSON export-only in Phase D |
| Dedup/high-watermark drift | message_id and correlation_id idempotency in DB-backed lifecycle |
| Empty or delayed packet interpreted as crash | status remains pending/expired/retrying/dead_letter; no implicit crash semantics |
| UI projection becoming authority | UI reads projection view from DB status model only |

## 4) Compatibility Matrix

| Surface | Phase A | Phase B | Phase C | Phase D | Phase E |
|---|---|---|---|---|---|
| Canonical request/trigger packets | authority | authority + DB shadow | fallback | export | export/legacy |
| ACK/RESULT packets | authority-adjacent | dual-write | DB-first | export | export/legacy |
| integration_status/objectives projections | current | current + DB shadow compare | DB-first projection | generated projection | generated projection |
| UI endpoints | current projections | current projections | DB-read preferred | DB projections | DB projections |

## 5) Safety and Rollback

Phase rollback rule:
- Each phase keeps previous authoritative path available until phase exit criteria are met.

Rollback mechanisms:
- Feature flag by read/write precedence mode
- Per-endpoint DB-read toggle
- Export-generation toggle for JSON outputs

## 6) Implementation Readiness Checklist

Before runtime migration work begins:

- Sync-point inventory validated against latest runtime surfaces
- DB schema migration scripts reviewed
- Event/status enum contract frozen
- Reconciliation tooling prepared for Phase B
- UI projection queries designed for DB-read preferred mode
- Legacy authority paths explicitly tagged for removal candidate list

## 7) Stop Condition Satisfaction

This plan provides a complete phased migration design from current mixed authority sync to DB-backed message coordination, with compatibility and rollback controls, without changing runtime behavior in this deliverable.