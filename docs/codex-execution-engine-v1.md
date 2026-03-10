# CodexExecutionEngine v1

CodexExecutionEngine is the first concrete execution provider for TOD's execution-engine interface.

Implementation file:
- [scripts/engines/CodexExecutionEngine.ps1](../scripts/engines/CodexExecutionEngine.ps1)

## Provided Functions
- `Get-CodexExecutionEngineSpec`
- `Invoke-CodexExecutionEngineWrapper`
- `Invoke-CodexExecutionEngine` (compatibility alias)
- `Convert-CodexEngineResultToTodResult`

## Behavior
- Accepts `EngineTaskContext` from interface contract.
- Uses `prompt_path` package input when available.
- Produces `EngineExecutionResult` with engine metadata:
  - `engine_name`
  - `engine_version`
  - `execution_id`
  - `status`
- Captures wrapper execution traces as stdout/stderr equivalent payload in `raw_output.io_capture`.
- Validates output via `Test-EngineContract` before returning.

## Current Mode
This implementation is a provider-adapter wrapper (non-networked execution mode) that normalizes package-path execution output.

Use now for:
- package-path wrapper invocation
- structured output shape compatibility
- execution metadata propagation
- stdout/stderr-equivalent capture for auditing

## Notes
- `Invoke-CodexExecutionEngine` delegates to `Invoke-CodexExecutionEngineWrapper` to preserve existing call sites.
