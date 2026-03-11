# TOD Shared State Bus Contract v1

Status: Draft

Purpose: Define a single authoritative, queryable state snapshot for TOD operator views and MIM coordination.

## Scope

This contract defines the payload returned by:
- Action: get-state-bus
- Path: /tod/state-bus

The payload unifies agent, world, capability, intent, execution, reliability, and block/uncertainty state.

## Versioning

- contract_name: tod_state_bus_v1
- service: tod
- path: /tod/state-bus

## Endpoint

Request:

```powershell
.\scripts\TOD.ps1 -Action get-state-bus -Top 10
```

Response:
- JSON object
- stable top-level sections (v1):
  - source_of_truth
  - section_confidence
  - system_posture
  - agent_state
  - world_state
  - capability_state
  - intent_state
  - execution_state
  - reliability_state
  - blocks

## Response Shape (v1)

```json
{
  "path": "/tod/state-bus",
  "service": "tod",
  "generated_at": "2026-03-10T00:00:00Z",
  "objective_id": "OBJ-0001",
  "source_of_truth": {
    "mode": "hybrid",
    "world_state": "mim_authoritative_with_local_cache",
    "intent_state": "mim_authoritative_with_local_projection",
    "execution_state": "hybrid_execution_telemetry",
    "reliability_state": "tod_local_derived",
    "capability_state": "tod_runtime_config",
    "agent_state": "tod_runtime_config",
    "blocks": "tod_local_guardrails"
  },
  "section_confidence": {
    "agent_state": 0.98,
    "world_state": 0.84,
    "capability_state": 0.97,
    "intent_state": 0.85,
    "execution_state": 0.86,
    "reliability_state": 0.90,
    "blocks": 0.84
  },
  "system_posture": {
    "agent_state": "awake",
    "current_alert_state": "warning",
    "active_goal_count": 2,
    "active_execution_count": 1,
    "pending_confirmations": 1,
    "blocked_items": 0,
    "registered_capabilities": 4,
    "current_executor_health": "watch",
    "summary": "SYSTEM POSTURE | Agent: awake | Alert: warning | Executions: 1 active | Pending confirmations: 1 | Blocked items: 0 | Capabilities: 4 registered | Reliability: watch"
  },
  "agent_state": {
    "mode": "hybrid",
    "active_engine": "codex",
    "fallback_engine": "local",
    "current_alert_state": "stable"
  },
  "world_state": {
    "objective": { "id": "OBJ-0001", "title": "...", "status": "open" },
    "objectives_total": 1,
    "tasks_total": 3,
    "reviews_total": 1,
    "results_total": 1,
    "journal_total": 8
  },
  "capability_state": {
    "endpoints": ["/tod/reliability", "/tod/capabilities", "/tod/state-bus", "/tod/version"],
    "drift_detection_enabled": true,
    "fallback_supported": true
  },
  "intent_state": {
    "objective_id": "OBJ-0001",
    "objective_status": "open",
    "objective_priority": "high",
    "task_funnel": {
      "total": 3,
      "by_status": {
        "open": 1,
        "in_progress": 1,
        "reviewed_pass": 1
      }
    },
    "pending_review_count": 1
  },
  "execution_state": {
    "active_task": { "id": "45", "status": "in_progress" },
    "execution_ids": ["exec_22_0001"],
    "recent_routing": [],
    "recent_journal": []
  },
  "reliability_state": {
    "current_alert_state": "stable",
    "drift_warning_count": 0,
    "drift_warnings": []
  },
  "blocks": {
    "contract_drift_blocking": false,
    "routing_guardrail_block_candidates": 0,
    "uncertainties": []
  }
}
```

## Field Semantics

- path, service, generated_at: endpoint metadata.
- objective_id: active objective context used by TOD state bus snapshot.
- source_of_truth: section-level authority tags (local, hybrid, configuration-derived).
- section_confidence: normalized $[0,1]$ confidence scores by section for operator trust calibration.
- system_posture: synthesized command-deck posture summary for at-a-glance operator status.
- agent_state: runtime mode and selected engines.
- world_state: aggregate counts and active objective record.
- capability_state: capabilities relevant to orchestration and observability.
- intent_state: active objective intent and task funnel.
- execution_state: currently active task plus recent routing/journal execution context.
- reliability_state: drift and alert summaries.
- blocks: hard blockers and high-risk uncertainty summaries.

## Compatibility Rules

- Optional historical fields in local state are tolerated.
- Missing collections are represented as empty arrays.
- Missing countable sections are represented as zero.
- New fields may be added in future versions; v1 consumers should ignore unknown fields.

## Operator Use Cases

- Single snapshot polling for dashboard views.
- Context handoff to agents without stitching multiple endpoints.
- Rapid diagnosis of drift, blocks, and execution continuity.

## Future Extensions

Planned additions for v2+:
- explicit confidence score per section
- richer execution lifecycle rollup
- source-of-truth markers by section (local, remote, hybrid)
