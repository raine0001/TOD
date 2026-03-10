# ExecutionEngine Interface v1

This document defines the engine contract for TOD task execution.

## Design Goal
Allow TOD to run different execution providers without changing task packaging, review logic, or MIM persistence flows.

## Core Types
Defined in [scripts/engines/ExecutionEngine.ps1](../scripts/engines/ExecutionEngine.ps1):
- `Get-ExecutionEngineInterfaceSpec`
- `New-EngineTaskContext`
- `New-EngineExecutionResult`
- `Complete-EngineExecutionResult`
- `Test-EngineContract`

## EngineTaskContext
Input contract passed into engines.

Required fields:
- `task_id`

Common fields:
- `objective_id`
- `title`
- `scope`
- `prompt_path`
- `allowed_files[]`
- `validation_commands[]`
- `metadata{}`

## EngineExecutionResult
Standardized output contract from every engine.

Metadata fields:
- `engine_name`
- `engine_version`
- `execution_id`
- `status`
- `started_at`
- `completed_at`

Task/result fields:
- `task_id`
- `summary`
- `files_changed[]`
- `tests_run[]`
- `test_results[]`
- `failures[]`
- `recommendations[]`
- `needs_escalation`
- `raw_output`

## Lifecycle Hooks
Lifecycle hooks are standardized as interface stages:
- `prepare`
- `execute`
- `finalize`

Lifecycle expectation:
1. TOD creates `EngineTaskContext`
2. Selected engine performs `prepare`
3. Selected engine performs `execute`
4. Selected engine performs `finalize`
5. TOD validates with `Test-EngineContract` and persists execution result into result/review flows

## Compatibility Requirements
- Engine output must remain compatible with TOD result/review payloads.
- Engines should avoid side effects outside task scope unless explicitly allowed.
- Engines must provide `engine_name` and `engine_version` for auditability.

## Planned Implementations
- `CodexExecutionEngine` (primary)
- `LocalExecutionEngine` (placeholder/stub for provider-independent fallback)
