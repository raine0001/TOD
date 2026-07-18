# TOD Public TOD Route/State Health Ownership V1

Status: active_training_required

## Mission

Teach TOD to own public `/tod` route/state health from observation through classification, owner assignment, repair decision, validation, and closure.

This is separate from the workstation CPU pressure incident. CPU pressure is resolved. Public `/tod` route/state health remains an operations item because TOD self-health still reports attention around public route exposure.

## Trigger

TOD self-health reports public route/state blockers:

- `public_tod_unreachable`
- `public_tod_state_missing`

Fresh route evidence shows:

- `https://www.agentmim.com/tod` returns HTTP 404.
- `https://www.agentmim.com/tod/ui/state` returns HTTP 404.
- `https://mim.mimtod.com/tod` returns HTTP 200 but serves the secure sign-in page.
- `https://mim.mimtod.com/tod/ui/state` returns HTTP 200 but serves HTML, not JSON.
- `http://localhost:8844/tod` returns HTTP 200 and serves the full TOD Command Console.
- Technical Operations route inventory for the current public/studio/local surfaces reports healthy.

## Reality

The local TOD workstation is not down.

The current failure is a public route contract/ownership problem:

- The legacy public TOD compatibility check derives public TOD targets from `PUBLIC_APP_URL + /tod` and `PUBLIC_APP_URL + /tod/ui/state`.
- `.env` currently points `PUBLIC_APP_URL` at `https://www.agentmim.com`.
- The public AgentMIM route does not expose `/tod` or `/tod/ui/state`.
- The MIM Box route does expose `/tod`, but unauthenticated health probes receive the operator sign-in page.
- The MIM Box state endpoint route exists in source, but public unauthenticated probes receive HTML instead of state JSON.
- The route health script can detect this, but TOD has not closed the question of whether the route should be restored, redirected, intentionally disabled, or reconfigured.

## Observation

Observed artifacts:

- `shared_state/tod_public_route_health.latest.json`
- `shared_state/TOD_SELF_HEALTH_RUN.latest.json`
- `runtime_remote_training/PUBLIC_TOD_ROUTE_HEALTH_REPAIR_V1.latest.json`
- `docs/training/TOD_TECHNICAL_OPERATIONS_RELIABILITY_V1.md`

Observed source anchors:

- `scripts/Invoke-TODPublicRouteHealthCheck.ps1` resolves public TOD HTML from `PUBLIC_APP_URL` plus `/tod`.
- `scripts/Invoke-TODPublicRouteHealthCheck.ps1` resolves public TOD state from `PUBLIC_APP_URL` plus `/tod/ui/state`.
- `scripts/Invoke-TODSelfHealthMaintenance.ps1` treats non-empty public route blockers as route divergence and recommends treating the route definition as external until repo-managed.

## Root Cause

TOD has a route-health ownership closure gap.

TOD can observe that a route is not serving, but it has not yet completed the ownership decision:

- Is the route canonical and broken?
- Is it legacy and stale?
- Is it intentionally disabled?
- Is it external to this repo?
- Which system owns repair?
- What evidence proves closure?

Without that decision, self-health keeps carrying a public route attention item indefinitely.

## Blocker Class

`capability_blocker`

## Blocker Name

`tod_route_health_ownership_closure_missing`

## Decomposition Ladder

### Rung 001: Fresh Observation

Run the public route health probe and record:

- public TOD URL
- public TOD HTTP status
- public TOD state URL
- public TOD state HTTP status
- local TOD URL
- local TOD HTTP status
- technical operations route status

Pass condition:

TOD reports that public `/tod` and `/tod/ui/state` return 404 while local TOD UI is healthy.

### Rung 002: Classification

TOD must classify the failure as:

`route_contract_or_ownership_blocker`

Not:

- workstation down
- CPU pressure
- generic communication failure
- MIM waiting issue

Pass condition:

TOD explains that public exposure is failing while local TOD service health is good.

### Rung 003: Ownership Decision

TOD must determine one of:

- `tod_owned_route_repair`
- `mim_box_public_route_repair`
- `mim_box_auth_contract_repair`
- `agentmim_public_route_repair`
- `legacy_probe_retire_or_disable`
- `external_dependency`

Required evidence:

- source route definition found or not found in this workspace
- public deployment owner
- intended public exposure policy
- whether `/tod` should be public, redirected, disabled, or local-only

Pass condition:

TOD does not leave the route as `attention` without an owner and decision.

### Rung 004: Smallest Safe Repair Model

TOD must produce one bounded repair model:

1. Restore public `/tod` and `/tod/ui/state`.
2. Redirect public `/tod` to the canonical TOD surface.
3. Publish deliberate disabled status for `/tod` and `/tod/ui/state`.
4. Reconfigure the health probe to the canonical public TOD route.
5. Mark the legacy check compatibility-only and remove it from self-health attention if intentionally disabled.
6. Add an authenticated or health-safe state probe contract for MIM Box `/tod/ui/state` if the route is intentionally protected.

Pass condition:

The model includes exact target file or deployment owner, validation command, rollback note, and expected evidence.

### Rung 005: Validation

TOD must validate with:

```powershell
.\scripts\Invoke-TODPublicRouteHealthCheck.ps1 -EmitJson
```

Required output:

- current public/studio/local route inventory remains healthy
- no ambiguous `public_tod_unreachable` or `public_tod_state_missing` blocker remains without owner/decision
- local TOD UI remains reachable
- if MIM Box `/tod` is auth-protected, route health reports `auth_required` explicitly instead of `wrong_surface:unknown`
- if MIM Box `/tod/ui/state` is auth-protected, route health reports a named auth/state contract rather than `state_missing`

### Rung 006: Capability Freeze

After repair, TOD must freeze the learned capability:

- route health failures require exposure-policy and owner classification
- local service health and public route health are separate
- stale compatibility probes must be retired, reconfigured, or marked intentionally disabled
- public route blockers cannot remain permanent `attention` without ownership and closure evidence

## Current Required TOD Output

TOD must produce:

1. `observed_failure`
2. `evidence_used`
3. `blocker_class`
4. `route_contract_status`
5. `owner_decision`
6. `smallest_safe_repair_model`
7. `validation_command`
8. `expected_evidence`
9. `rollback_note`
10. `prevention_rule`

## Current Validation Command

```powershell
$h = .\scripts\Invoke-TODPublicRouteHealthCheck.ps1 -EmitJson | ConvertFrom-Json
if ($h.technical_operations_status -ne 'healthy') { throw 'technical operations route inventory is not healthy' }
if (-not ($h.blockers -contains 'public_tod_unreachable')) { throw 'expected current public_tod_unreachable evidence missing' }
if (-not ($h.blockers -contains 'public_tod_state_missing')) { throw 'expected current public_tod_state_missing evidence missing' }
if ($h.local_surface.classification.surface_type -ne 'full_tod_ui') { throw 'local TOD UI is not healthy full_tod_ui' }
```

This command validates the current blocker evidence. It is not the final closure command.

## Prevention Rule

TOD health checks must separate:

- local service health
- public route exposure
- state publication
- compatibility probes
- external deployment ownership

Any route blocker must have an owner, intended exposure policy, and closure evidence.

## Continuation Policy

This training remains active until TOD either repairs the route, reconfigures the route target, or proves the route is intentionally disabled and updates health reporting so the disabled state is explicit rather than ambiguous.
