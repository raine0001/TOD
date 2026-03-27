# TOD Operator-Chat Stability Note

Date: 2026-03-27
Audience: TOD, MIM, and operator-console maintainers

## Status

Operator-chat stabilization is complete for the validated host seam.

## Reference Points

- the authoritative certification line on this host is `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json`
- direct artifact smoke is the operational gate
- the slower full sweep remains extended validation, not primary certification on this host
- readiness is a first-class execution surface, not an advisory decoration
- direct `/api/operator-chat` remains intentionally stateful across commitment-history changes
- generic response caching on direct `/api/operator-chat` is prohibited
- the sweep `-ArtifactOnly` ineffective branch remains live-derived and self-contained

## Enforced Surfaces

- CLI `run-task` is blocked for `stale`, `invalid`, and `unknown`
- CLI `engineer-run -ApplyPlan` is degraded for `degraded`, `stale`, `invalid`, and `unknown`
- governed operator-chat confirmations are gated by the authoritative readiness signal
- host `/api/run` now enforces readiness before child launch instead of acting as a weaker wrapper surface
- governed host confirmations now honor request-scoped `configPath` when evaluating readiness

## Readiness Model

Active readiness states:

- `valid`
- `degraded`
- `stale`
- `invalid`
- `unknown`

Readiness history is persisted in `shared_state/tod_execution_readiness_history.latest.json` so later investigations do not depend on reconstructing one-off snapshots.

## Adjacent Confidence Sweep

Validated seam-adjacent surfaces for this promotion line:

- operator chat direct responses
- governed action previews and confirms
- readiness query and transition history
- ineffective follow-up suppression
- commitments and trust-chain projection
- governed execution entry points through both direct CLI and host wrapper routing

## Intended Use

Use this note as the plain-English reference for MIM integration and future TOD changes. If a future change conflicts with this note, the change needs explicit re-certification rather than silent reinterpretation of the seam.
