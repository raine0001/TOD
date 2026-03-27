# TOD Execution Readiness Promotion Note

Date: 2026-03-27
Audience: TOD, MIM, and operator-console maintainers

## Promotion Decision

TOD now treats the direct operator-chat artifact smoke result as the authoritative execution-readiness gate on this host.

Authoritative surface:

- `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json`
- produced by direct execution of `scripts/Test-TODOperatorChatSweepArtifact.ps1`

Non-authoritative surface on this host:

- wrapper-style Pester console output for the sweep suite

## Frozen Certification Contract

Maintain these invariants as the host certification seam:

- authoritative host certification comes from `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json`
- direct `/api/operator-chat` must not use generic response caching across mutable sweep or commitment state
- the sweep `-ArtifactOnly` ineffective branch must remain live-derived and self-contained rather than depending on ambient history

Validation tiers on this host:

- operational certification = `scripts/Test-TODOperatorChatSweepArtifact.ps1` and the durable artifact smoke result
- extended validation = the slower full sweep exercised by `scripts/Invoke-TODOperatorChatSweep.ps1` and `tests/TOD.OperatorChatSweep.Tests.ps1`

The full sweep remains useful for deeper regression coverage, but it is not the primary certification gate for host readiness.

## Cache Safety Rule

Internal design rule for operator-chat caching on this host:

Safe to cache:

- helper query resolution
- harness-isolated query caches
- preview reuse when state is intentionally shared and preview identity is preserved

Unsafe to cache:

- generic direct `/api/operator-chat` response caching
- recommendation paths that depend on commitment-history mutation
- sweep-sensitive stateful chat branches

If a path can change recommendation output or ineffective flags after commitment history mutates, it must not be hidden behind generic response reuse.

## Runtime Contract

Execution readiness is now published as a graded control-plane signal instead of a binary pass/fail hint.

Primary states:

- `valid`
- `degraded`
- `stale`
- `invalid`
- `unknown`

Important reasons include:

- `artifact_passed`
- `artifact_display_stale`
- `artifact_stale`
- `artifact_failed`
- `artifact_missing`
- `parse_failure`
- `policy_disabled`

`run-task` remains blocked for `stale`, `invalid`, and `unknown`.

`engineer-run` remains degraded for `degraded`, `stale`, `invalid`, and `unknown`.

Wrapper behavior by state is now explicit:

- `valid`: allow execution and allow governed confirms
- `degraded`: allow execution, degrade `engineer-run -ApplyPlan` to advisory or planned-only behavior, and keep governed previews available
- `stale`: block `run-task`, block governed confirms, and degrade `engineer-run -ApplyPlan`
- `invalid`: block `run-task`, block governed confirms, and degrade `engineer-run -ApplyPlan`
- `unknown`: block `run-task`, block governed confirms, and degrade `engineer-run -ApplyPlan`

## Freshness Policy

TOD now distinguishes between two freshness windows:

- execution freshness via `max_artifact_age_minutes`
- display freshness via `display_max_artifact_age_minutes`

If the artifact is still within execution freshness but outside display freshness, readiness reports `degraded` instead of `stale`. That preserves bounded execution while making the operator-facing surface explicitly non-fresh.

## Wrapper Audit Result

The remaining host-side execution entry points were audited against the wrapper rule.

Launch surfaces covered by wrapper-level readiness enforcement:

- `POST /api/run`
- governed `POST /api/operator-chat-action` confirmation

Non-wrapper execution paths were reviewed and remain rooted in `scripts/TOD.ps1`, where readiness is applied before action dispatch:

- direct CLI calls to `scripts/TOD.ps1`
- local helper scripts that shell into TOD actions
- recovery or replay helpers that invoke TOD through the CLI surface

Request-scoped readiness configuration is now honored on host wrapper surfaces. Readiness decisions must use the request `configPath` when it is supplied and must not silently fall back to the host default config for those requests.

## History And Consumers

Readiness transitions are now recorded in:

- `shared_state/tod_execution_readiness_history.latest.json`

Each transition now carries:

- prior and new readiness status
- prior and new reason
- transition timestamp
- artifact path and freshness metadata
- host and session metadata for the evaluating process

Shared-state consumers now receive the richer readiness payload and transition history through:

- `shared_state/current_build_state.json`
- `shared_state/execution_evidence.json`
- `shared_state/contracts.json`

Listener-side execution traces also now preserve the graded readiness state and the resulting policy outcome.

The lightweight query surface for recent readiness transitions remains:

- `./scripts/TOD.ps1 -Action get-execution-readiness`
- `POST /api/run` with `action = get-execution-readiness`

## Operator Chat Execution

Governed operator-chat confirmation now checks the authoritative readiness gate before executing the bounded action. Preview remains available so operators can inspect proposed actions even when execution is blocked.

## Promotion Scope

This promotion note covers:

- artifact-first execution-readiness authority
- graded readiness publication
- readiness history tracking
- shared-state consumer propagation
- operator-chat confirmation gating

This note does not claim completion for wider cleanup tasks such as the broader adjacent sweep, cache-specific regressions beyond the readiness path, or remaining operational cleanup outside the authoritative gate flow.
