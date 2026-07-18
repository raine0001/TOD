# Studio Route Seed Contract Mixed Type Learned Capability

## Capability Name

Studio dashboard seed contract mixed-type recovery.

## Trigger

Authenticated Studio routes return HTTP 500 after a seed/backlog change.

## Reality

`/studio/projects` and `/studio/training` both depend on the Studio project state builder. One mixed seed entry was a `StudioProject` object inside a list otherwise treated as dictionaries.

## Observation

Production logs showed:

- `/studio/projects` returned 500.
- `/studio/training` returned 500.
- `_ensure_requested_project_backlog` called `spec.setdefault(...)`.
- One `spec` was already a `StudioProject` and therefore had no `setdefault` method.

## Root Cause

The seed contract allowed mixed object shapes without normalizing them before dictionary-only handling.

## Blocker Class

`infrastructure_blocker` with `data_blocker` cause.

## Decomposition Ladder

1. Verify authenticated Studio routes fail.
2. Inspect production logs for the first stack trace.
3. Identify the shared state builder used by both failing routes.
4. Locate the exact mixed-type seed entry.
5. Normalize the object shape before dictionary-only handling.
6. Compile, restart, and probe affected routes.
7. Freeze the learned rule for TOD.

## Smallest Successful Rung

Normalize `StudioProject` seed entries to dictionaries before `metadata_json` mutation.

## Implementation Summary

Emergency production repair added a guard in `_ensure_requested_project_backlog` so `StudioProject` seed entries are converted to dictionaries before `spec.setdefault("metadata_json", {})`.

## Validation

Authenticated live probes returned HTTP 200:

- `/studio`
- `/studio/projects`
- `/studio/training`
- `/studio/visitors`

Recent service logs showed no new `Traceback`, `AttributeError`, `500`, or `setdefault` errors after validation.

## General Rule Learned

Dashboard seed builders must normalize input contracts before mutating them.

## Prevention Rule

If a route builder accepts seed specs from multiple sources, it must either validate a single canonical type at the boundary or normalize each item before mutation.

## Reuse Trigger

Use this capability when a Studio page fails with dictionary-method errors such as `setdefault`, `get`, or item assignment on ORM objects.

## Dependent Capabilities

- Studio route log triage
- Seed contract validation
- Authenticated route probing
- Emergency production rollback planning

## Capability Confidence

Medium-high after production validation.

## Independent Pass Rate

Not yet measured. TOD should repeat this as a read-only diagnosis drill before future direct implementation.

## Date Frozen

2026-07-09
