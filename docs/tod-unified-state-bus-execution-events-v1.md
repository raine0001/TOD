# TOD Unified State Bus Execution Events v1

Status: Draft
Owner: TOD runtime telemetry (execution-only)
Target Objective: TOD-17 Bus Readiness

## Purpose

Define additive, implementation-ready execution event artifacts so TOD can publish and consume runtime facts on a future Unified State Bus without changing ownership boundaries.

Ownership boundary:
- TOD owns: execution facts, guardrails, retries, drift, recovery, outcomes.
- MIM owns: cognition, strategy, constraint meaning, governance.

## Event Types (TOD runtime)

TOD publishes these event types only:
- `tod.execution.success`
- `tod.execution.failure`
- `tod.execution.blocked`
- `tod.execution.retry`
- `tod.execution.recovered`
- `tod.execution.drift_detected`

## Common Event Envelope

See schema artifact:
- `tod/templates/bus/tod_execution_event_envelope.schema.json`

Envelope intent:
- stable metadata for routing and ingestion
- explicit correlation IDs for cross-system stitching
- reason/severity list for explainability
- bounded execution payload only (no strategy semantics)

## Correlation ID Model

Required IDs:
- `event_id`: unique event UUID for idempotent ingestion.
- `trace_id`: cross-step flow correlation for one execution chain.
- `execution_id`: runtime execution lifecycle ID.

Optional IDs:
- `run_id`: engineering run or cycle container.
- `cycle_id`: bounded cycle identifier.
- `objective_id`, `task_id`: local execution context only.
- `upstream_goal_id`: MIM-origin goal reference (link only, no semantic ownership transfer).

## Reason / Severity Model

Reason list field: `reasons[]`

Each reason entry:
- `code`: machine-readable reason code.
- `severity`: one of `info|warning|error|critical`.
- `category`: one of `execution|guardrail|retry|drift|recovery|outcome`.
- `message`: human-readable explanation.
- `evidence`: optional object with numeric/context details.

Guidance:
- TOD reports observed runtime pressure and outcomes.
- TOD does not infer intent meaning or policy semantics beyond execution scope.

## Sample Events

See sample bundle:
- `tod/templates/bus/tod_execution_event_samples.json`

Includes event examples for:
- success
- failure
- blocked
- retry
- recovered
- drift_detected

## Validation

Lightweight consistency test:
- `tests/TOD.BusReadiness.Tests.ps1`

Checks:
- required envelope fields exist
- event types are allowed
- reason severity/category values are valid
- ownership boundary markers remain TOD-execution scoped

## Stream vs Snapshot Notes

Event stream (bus):
- append-only, time-ordered execution telemetry
- optimized for reactive orchestration and learning loops

Durable snapshots (`shared_state/*`):
- materialized, query-friendly state projections
- optimized for operator review and cross-session handoff

Rule:
- bus events are the change log
- shared_state remains the durable truth ledger for coordination artifacts

## Target Ingestion Path (Future State Bus)

Primary path for unified integration:
- TOD events -> state bus -> MIM ingestion service

Transitional compatibility:
- Filesystem artifact probing (for example shared_state index + snapshot files) is temporary and should be treated as fallback only until bus ingestion is active.

Ownership alignment:
- TOD publishes execution/runtime facts.
- MIM ingestion service consumes those facts and updates memory/improvement context.
- Meaning, cognition, and governance stay on the MIM side.
