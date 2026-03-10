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
  "scope": "string",
  "dependencies": ["string"],
  "acceptance_criteria": ["string"],
  "status": "string",
  "assigned_to": "string"
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

## Endpoint Mapping
- new-objective -> POST /objectives
- list-objectives -> GET /objectives
- add-task -> POST /tasks
- list-tasks -> GET /tasks
- add-result -> POST /results
- review-task -> POST /reviews
- show-journal -> GET /journal
- ping-mim -> GET /health and GET /status

## Compatibility Notes
- MIM currently uses integer IDs in API responses for core records.
- TOD keeps local IDs (OBJ-xxxx, TSK-xxxx, etc.) and stores remote ID mappings for bridge operations.
- TOD client normalizes MIM responses into canonical contract shapes above before returning them.
