# LocalExecutionEngine v1 (Placeholder)

LocalExecutionEngine is a provider-independent placeholder execution engine.

Implementation file:
- [scripts/engines/LocalExecutionEngine.ps1](../scripts/engines/LocalExecutionEngine.ps1)

## Purpose
Provide a selectable non-Codex engine path in TOD architecture so execution is not provider-locked.

## Current Behavior
- Accepts `EngineTaskContext`
- Returns `EngineExecutionResult` with:
  - `engine_name = local`
  - `status = not_implemented`
  - explicit not-implemented summary/failure/recommendations
  - `needs_escalation = true`

## Functions
- `Get-LocalExecutionEngineSpec`
- `Invoke-LocalExecutionEngine`
- `Convert-LocalEngineResultToTodResult`

## Selection
TOD config supports:
- `execution_engine.active = local`
- `execution_engine.fallback = local`

This placeholder is intentionally non-executing and should be replaced by a real local strategy in future tasks.
