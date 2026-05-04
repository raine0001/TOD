# TOD-MIM Shared Contract v1

This document defines the canonical object contracts exchanged between TOD and MIM.

Rule:
- TOD plans.
- MIM remembers.

## Transport
- Protocol: HTTP JSON
- Base URL: configured in [tod/config/tod-config.json](../tod/config/tod-config.json)
- Source of truth mode: remote or hybrid

## Canonical Objects

### Objective
```json
{
  "objective_id": "string",
  "title": "string",
  "description": "string",
  "priority": "string",
  "constraints": ["string"],
  "success_criteria": ["string"],
  "status": "string",
  "created_at": "string"
}
```

### Task
```json
{
  "task_id": "string",
  "objective_id": "string",
  "title": "string",
  "type": "string",
  "scope": "string",
  "dependencies": ["string"],
  "acceptance_criteria": ["string"],
  "priority": "string",
  "origin": "human|tod|mim",
  "emergency": false,
  "status": "string",
  "assigned_to": "string"
}
```

### TaskPlan
```json
{
  "task_id": "string",
  "objective_id": "string",
  "goal": "string",
  "implementation_strategy": "string",
  "dependencies": ["string"],
  "ordering_reason": "string",
  "risks": ["string"],
  "expected_outcomes": ["string"],
  "test_plan": ["string"],
  "verification_plan": ["string"],
  "completion_definition": ["string"],
  "prompt_required": false,
  "prompt_reason": "string"
}
```

### TaskStatus
```json
{
  "task_id": "string",
  "objective_id": "string",
  "queue_rank": 1,
  "status": "string",
  "blocked_reason": "string",
  "next_action": "string",
  "last_updated_at": "string",
  "active": false
}
```

### Result
```json
{
  "result_id": "string",
  "task_id": "string",
  "summary": "string",
  "files_changed": ["string"],
  "tests_run": ["string"],
  "test_results": ["string"],
  "failures": ["string"],
  "recommendations": ["string"],
  "created_at": "string"
}
```

### Review
```json
{
  "review_id": "string",
  "task_id": "string",
  "decision": "string",
  "rationale": "string",
  "continue_allowed": true,
  "escalate_to_user": false,
  "created_at": "string"
}
```

### JournalEntry
```json
{
  "entry_id": "string",
  "actor": "string",
  "action": "string",
  "target_type": "string",
  "target_id": "string",
  "summary": "string",
  "timestamp": "string"
}
```

### Manifest
```json
{
  "system_name": "string",
  "system_version": "string",
  "contract_version": "string",
  "schema_version": "string",
  "repo_signature": "string",
  "capabilities": ["string"],
  "recent_changes": [
    {
      "id": "string",
      "summary": "string",
      "timestamp": "string"
    }
  ],
  "last_updated_at": "string",
  "generated_at": "string"
}
```

## Endpoint Mapping
- new-objective -> POST /objectives
- list-objectives -> GET /objectives
- add-task -> POST /tasks
- list-tasks -> GET /tasks
- add-result -> POST /results
- review-task -> POST /reviews
- show-journal -> GET /journal
- ping-mim -> GET /health and GET /status
- get-manifest -> GET /manifest

## Compatibility Notes
- MIM currently uses integer IDs in API responses for core records.
- TOD keeps local IDs (OBJ-xxxx, TSK-xxxx, etc.) and stores remote ID mappings for bridge operations.
- TOD client normalizes MIM responses into canonical contract shapes above before returning them.
- Task lifecycle flow, queue artifacts, autonomous prompt rules, and console status expectations are defined in [docs/tod-mim-task-lifecycle-contract-v1.md](../docs/tod-mim-task-lifecycle-contract-v1.md).
