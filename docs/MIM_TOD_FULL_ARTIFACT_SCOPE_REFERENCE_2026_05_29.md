# MIM/TOD Full Artifact Scope Reference

Generated: 2026-05-29
Scope: MIM/TOD reliability stack, project definition portal, application-design pipeline, voice/lab resources, objective execution, and artifact memory.

## Purpose

This reference is the current map for what exists, where truth lives, how data flows, which services matter, and which policies MIM/TOD must preserve while continuing development.

The goal is not to document every historical artifact. The goal is to give MIM, TOD, Codex, and Dave a dependable operating reference for the current architecture.

## Current Product Direction

MIM/TOD is shifting from a raw objective/task system into a business solution design platform.

The current platform path is:

1. User arrives at MIMTOD.com.
2. User logs in or uses demo mode.
3. MIM acts as consultant/sales guide.
4. User describes pain, goal, process, examples, links, documents, screenshots, or desired outcome.
5. MIM performs consultative discovery.
6. MIM creates project blueprint.
7. MIM generates roadmap, value/pricing, provider broker plan, and application foundation plan.
8. User approves roadmap.
9. TOD materializes approved roadmap items into implementation tasks.
10. MIM/TOD validate evidence, learn from outcomes, and reuse patterns.

Core product identity:

- MIM is not a cloning engine.
- MIM is a business solution design engine.
- TOD is the implementation/materialization engine.
- Codex is a repair/escalation implementation resource when MIM/TOD hit a wall.

## Dependables

These are the system components or assumptions MIM/TOD can currently depend on, subject to freshness checks.

### Runtime

- Remote root: `/home/testpilot/mim`
- Local mirror/workspace: `e:\TOD`
- Main deployed app service: `mim-mobile-web.service`
- Main web port: `18001`
- Project portal URL: `https://mim.mimtod.com/login`
- Demo account: `demo@agentmim.com`
- Demo password: `MIM`
- App runtime Python on MIM: `.venv/bin/python`

### Database

Primary execution and product data is DB-driven through PostgreSQL via SQLAlchemy async sessions.

Core execution tables:

- `objectives`
- `tasks`
- `task_results`

Project portal tables:

- `project_portal_accounts`
- `project_portal_projects`
- `project_portal_discovery_sessions`
- `project_portal_blueprints`
- `project_portal_consultative_discoveries`
- `project_portal_implementation_roadmaps`
- `project_portal_roadmap_approvals`
- `project_portal_email_verification_codes`
- `project_portal_value_assessments`
- `project_portal_learning_events`
- `project_portal_reference_research_packets`
- `project_portal_safe_reframes`
- `project_portal_application_foundations`
- `project_portal_solution_catalog`
- `project_portal_pricing_estimates`
- `project_portal_capability_broker_plans`

### File Artifacts

Canonical runtime artifacts live under:

- `/home/testpilot/mim/runtime/shared`

Local training/handoff artifacts live under:

- `runtime_remote_training`
- `shared_state`
- `docs`

Current high-value artifacts include:

- `MIM_PROJECT_PORTAL_CONSULTANT_FIRST_UX.latest.json`
- `MIM_PROJECT_PORTAL_DEMO_UX_AND_GUARDRAILS.latest.json`
- `MIM_PROJECT_PORTAL_DEMO_ACCOUNT.latest.json`
- `MIM_CAPABILITY_TO_PROVIDER_BROKER.latest.json`
- `MIM_PROJECT_PRICING_AND_VALUE_ENGINE.latest.json`
- `MIM_SOLUTION_CATALOG.latest.json`
- `MIM_APPLICATION_FOUNDATION_FRAMEWORK.latest.json`
- `MIM_SAFE_REFRAME_AND_ALTERNATIVE_GENERATION.latest.json`
- `MIM_ETHICAL_SOLUTION_DESIGN_POLICY.latest.json`
- `MIM_ETHICAL_SOLUTION_DESIGN_POLICY_V2.latest.json`
- `MIM_PROJECT_SAAS_REFERENCE_BENCHMARK.latest.json`
- `MIM_PROJECT_REFERENCE_RESEARCH_AND_APP_UNDERSTANDING.latest.json`
- `MIM_TOD_OBJECTIVE_STATE_RECONCILIATION_WATCHDOG.latest.json`
- `MIM_READY_TASK_DISPATCHER_STATUS.latest.json`
- `MIM_OPERATOR_STATUS.latest.json`
- `TOD_RUNTIME_OWNERSHIP.latest.json`
- `TOD_MIM_TASK_RESULT.latest.json`
- `MIM_TOD_HOURLY_REFLECTION.latest.json`
- `MIM_MANIFEST.latest.json`

## Data Flow

### Project Portal Flow

1. Browser loads `/login` or `/projects`.
2. User authenticates through `POST /projects/login`.
3. Session cookie ties requests to `project_portal_accounts`.
4. `/projects/state` returns account-scoped projects, readiness, latest blueprint, and TOD export preview.
5. User starts discovery through `POST /projects/discovery`.
6. MIM creates:
   - `project_portal_projects`
   - `project_portal_discovery_sessions`
   - `project_portal_blueprints`
7. Consultative discovery extends context through `POST /projects/{project_id}/consultative-discovery`.
8. Roadmap is generated through `POST /projects/{project_id}/roadmap`.
9. Value/pricing, foundation, solution catalog, provider broker, and reference research are generated as separate DB-backed packets.
10. If approved, `POST /projects/{project_id}/roadmap/approve` creates:
   - `objectives`
   - `tasks`
   - `project_portal_roadmap_approvals`
11. Dispatcher consumes ready executable tasks.
12. Task evidence is written to `task_results` and runtime artifacts.

### Objective Execution Flow

1. Objective is created in DB or from managed runtime source.
2. Objective must materialize into executable task rows.
3. Task must have ready/readiness and dispatcher-compatible state.
4. `mim-ready-task-dispatcher.service` consumes ready tasks.
5. Executor returns completed_with_evidence or blocked_with_inspection/evidence.
6. Reconciliation watchdog prevents stale running/active states.
7. Operator/dashboard surfaces state from DB-backed truth, not stale deck-only truth.

Hard rule:

An active objective is invalid unless it has one of:

- linked DB task row
- linked dispatcher queue item
- explicit `blocked_with_reason`
- materialization failure artifact

### Training-To-Action Flow

Current target behavior:

1. Training detects failure class.
2. MIM/TOD classify it.
3. MIM/TOD check continuity memory, known-good solutions, prior repairs, and regression history.
4. System creates executable repair task immediately.
5. Dispatcher runs repair or returns a real blocker.
6. Result writes validation evidence.
7. Prevention memory/regression is created.

Failure classes already seen:

- missing executor
- stale truth
- objective drift
- stale running
- dispatcher idle confusion
- voice failure
- materialization blocked
- wrapper-only completion
- fake success
- replay deadlock

## Services

Verified live on 2026-05-29:

| Service | Status | Purpose |
| --- | --- | --- |
| `mim-mobile-web.service` | active | Main FastAPI/web/UI/API runtime |
| `mim-ready-task-dispatcher.service` | active | Consumes ready executable MIM/TOD tasks |
| `mim-tod-objective-state-reconciliation-watchdog.timer` | active | Periodic stale objective/task reconciliation |
| `mim-tod-objective-state-reconciliation-watchdog.service` | inactive | Timer-triggered oneshot; inactive is normal between runs |
| `mim-speech-turn-engine.service` | active | Voice turn/STT/routing/playback flow |
| `mim-box-tod-packet-listener.service` | active | MIM/TOD packet listener and bridge evidence consumer |
| `mim-box-tod-runtime-watchdog.service` | active | Watches packet listener/runtime health |
| `mim-wake-listener.service` | inactive | Wake listener not active at this snapshot |
| `mim-voice-context-12h.service` | inactive | Voice context runner not active at this snapshot |

Important service distinction:

- An inactive timer-triggered oneshot is not automatically a failure.
- Dispatcher idle is healthy when there are no ready executable tasks.
- Stale running objectives are failures only when task/heartbeat evidence proves they are stale.

## API And UI Surfaces

### Project Portal

Primary routes:

- `GET /login`
- `GET /dashboard`
- `GET /projects`
- `GET /projects/state`
- `POST /projects/register`
- `POST /projects/login`
- `POST /projects/verify-email`
- `POST /projects/resend-verification`
- `POST /projects/logout`
- `GET /projects/current-account`
- `POST /projects/discovery`
- `GET /projects/{project_id}`
- `GET /projects/{project_id}/page`
- `PATCH /projects/{project_id}`
- `PATCH /projects/{project_id}/discovery`
- `POST /projects/{project_id}/consultative-discovery`
- `GET /projects/{project_id}/consultative-discovery`
- `POST /projects/{project_id}/roadmap`
- `POST /projects/{project_id}/build-roadmap`
- `GET /projects/{project_id}/roadmap`
- `POST /projects/{project_id}/application-foundation`
- `GET /projects/{project_id}/application-foundation`
- `POST /projects/{project_id}/roadmap/approve`
- `GET /projects/{project_id}/implementation-tasks`
- `GET /projects/{project_id}/tod-export`
- `POST /projects/{project_id}/value-score`
- `POST /projects/{project_id}/feedback`
- `POST /projects/{project_id}/outcome-review`
- `GET /projects/{project_id}/learning-summary`
- `POST /projects/{project_id}/solution-catalog/seed`
- `POST /projects/{project_id}/solution-catalog`
- `GET /projects/{project_id}/solution-catalog`
- `POST /projects/{project_id}/pricing`
- `GET /projects/{project_id}/pricing`
- `POST /projects/{project_id}/capability-broker`
- `GET /projects/{project_id}/capability-broker`
- `POST /projects/{project_id}/reference-research`
- `GET /projects/{project_id}/reference-research`
- `POST /projects/{project_id}/solution-design-policy-check`
- `POST /projects/{project_id}/safe-reframe`
- `POST /projects/{project_id}/safe-reframe/{safe_reframe_id}/accept`

### Other Router Areas

Registered router areas include:

- health/status/manifest
- automation
- gateway
- operator
- objectives
- tasks
- custody
- results
- reviews
- routing
- journal
- memory
- reasoning
- orchestration
- state bus
- interface
- MIM arm
- public chat
- MIM UI
- TOD UI
- shell
- constraints
- planning horizon
- improvement
- execution control
- inquiry
- maintenance
- strategy
- preferences
- stewardship
- workspace
- tools
- services
- self-awareness
- safety

## Policies

### Ethical Solution Design

MIM must not directly clone third-party products.

Allowed:

- pattern extraction
- workflow extraction
- feature category extraction
- business problem discovery
- original custom solution design
- existing solution recommendations

Blocked:

- direct product cloning
- UI replication
- copyrighted content reuse
- logo reuse without ownership/permission
- trademark-confusing naming

If a user asks to duplicate an app, MIM should reframe:

- identify the underlying business goal
- explain what is blocked
- offer a safe alternative
- generate a business-equivalent implementation path
- preserve price-point pain as a valid reason to build a custom alternative

### Reference Research Gate

`POST /projects/{project_id}/reference-research` requires acknowledgement of reference-analysis policy.

Ownership statuses:

- `i_own_it`
- `i_have_permission`
- `analyze_only`
- `not_sure`

Unacknowledged reference research returns:

- `428 reference_analysis_policy_acknowledgement_required`

### Safe Reframe

When decision is `analysis_allowed_build_as_stated_blocked`, approval must not proceed until the user chooses:

- accept safe reframe
- modify request
- cancel

### Demo Guardrails

Demo users may:

- explore portal
- create fake/demo projects
- talk to MIM
- generate discovery, roadmap, pricing, provider, catalog, foundation, and safe-reframe previews

Demo users may not:

- approve real TOD materialization
- create provider activations
- store real credentials
- send emails/texts/calls
- trigger paid API usage beyond demo limits

### Evidence Policy

No status-only completion.

Successful work requires at least one of:

- changed files
- inspected files
- DB rows created/updated
- live route validation
- service validation
- blocked_with_inspection with exact missing dependency

### Freshness And Trust

Fresh wrapper around stale truth is dangerous.

Truth ranking must prefer:

1. live service checks
2. DB task/objective state
3. fresh runtime artifact with evidence
4. local repo inspection
5. stale runtime deck entries

Operator-facing surfaces must say when data is stale, blocked, demo-only, or preview-only.

## MIM/TOD Resources

### MIM Resources

- Voice turn engine
- Speech transcript logs
- Addressing/ambient decision artifacts
- Lab cameras
- OAK-1 Lite wrist/arm camera
- Pi camera
- PC camera when available
- Arduino arm bridge
- I2C distance sensor at Arduino path
- TFmini-S/TOF experimentation history
- MIM arm routes under `/mim/arm`
- Self-awareness and safety routes
- Manifest/context export artifacts

MIM should use sensors/cameras as learning resources, not only as hard stop rules. When physical contact or failure happens, MIM should record the observation, compare camera/sensor evidence, and learn the prevention rule.

### TOD Resources

- Objective/task DB
- Ready task dispatcher
- Packet listener
- Runtime watchdog
- Training artifacts
- Simulation factory
- Continuity memory
- Material implementation proof policy
- Freshness provenance policy
- Canonical authority registry
- PowerShell local scripts and tests
- Runbooks under `docs`

### Codex Resource

Codex remains the hands-on repair and implementation resource when:

- MIM/TOD lack an executor
- a route/service/deployment edit is required
- a local/remote artifact must be reconciled
- evidence says MIM/TOD hit a wall

Rule: every Codex fix should become a MIM/TOD objective, task result, artifact, or memory item so MIM/TOD can learn the pattern.

## Application Generation Stack

Current completed layers:

- account login/session handling
- email verification pathway
- demo account
- project ownership isolation
- discovery
- consultative/pain discovery
- blueprint
- roadmap generation
- approval-to-materialization
- DB-backed application foundation
- solution catalog
- pricing/value engine
- capability-to-provider broker
- reference research
- ethical solution design gate
- safe reframe
- consultant-first portal UX

Next natural layers:

- reduce dashboard dump into plain-language operator/client summaries
- approval-to-TOD task UX refinement
- sandbox preview/change approval
- outcome tracking after deployment
- pattern-library recommendations across clients
- service broker activation workflows
- account billing/plan boundaries

## MIM Application Foundation Framework

Every generated app should start with common commodity components:

- landing page
- login/register
- email verification
- password reset
- dashboard
- profile/settings
- help/wiki
- contact/support
- MIM assistant
- support desk
- suggestions
- admin console
- users/roles/permissions
- billing hooks
- usage
- audit logs
- integration center
- credential vault
- policies: terms/privacy/cookies/consent/data retention
- activity feed
- notifications
- search
- file uploads
- API layer
- sandbox hooks

Competitive components should be project-specific:

- fuel inventory intelligence
- labor optimization
- commission analytics
- robotics coordination
- operational forecasting

## Current Verified Counts

Live DB counts as of 2026-05-29:

| Table | Count |
| --- | ---: |
| `objectives` | 3383 |
| `tasks` | 8201 |
| `task_results` | 112 |
| `project_portal_accounts` | 31 |
| `project_portal_projects` | 31 |
| `project_portal_discovery_sessions` | 28 |
| `project_portal_blueprints` | 28 |
| `project_portal_consultative_discoveries` | 11 |
| `project_portal_implementation_roadmaps` | 9 |
| `project_portal_roadmap_approvals` | 4 |
| `project_portal_value_assessments` | 4 |
| `project_portal_learning_events` | 75 |
| `project_portal_reference_research_packets` | 65 |
| `project_portal_safe_reframes` | 2 |
| `project_portal_application_foundations` | 3 |
| `project_portal_solution_catalog` | 6 |
| `project_portal_pricing_estimates` | 3 |
| `project_portal_capability_broker_plans` | 2 |

Recent project/product objectives:

- `3390` MIM Project Portal consultant-first UX: `completed_with_evidence`
- `3389` MIM Project Portal Demo UX and Guardrails: `completed_with_evidence`
- `3388` MIM Project Portal Demo Account: `completed_with_evidence`
- `3387` MIM Capability to Provider Broker: `completed_with_evidence`
- `3386` MIM Project Pricing and Value Engine: `completed_with_evidence`
- `3385` MIM Solution Catalog: `completed_with_evidence`
- `3384` MIM Application Foundation Framework: `completed_with_evidence`
- `3382` MIM Safe Reframe and Alternative Generation: `completed_with_evidence`

Queued roadmap implementation objectives also exist and should not be treated as failures unless their tasks are ready/stale or their status contradicts evidence.

## Operator Interpretation Rules

When Dave asks "what is MIM/TOD doing right now?", the system should answer plainly:

- what MIM is working on
- what TOD is working on
- what is healthy
- what is blocked
- what needs Dave
- what happens next
- how fresh the evidence is

Do not lead with raw IDs, lifecycle terms, or JSON unless the operator drills down.

Dashboard first section should be:

- MIM Right Now
- TOD Right Now
- System Health
- Needs Attention
- Current Objectives

## Known Open Risks

- Dashboard still has too much technical density below the consultant-first entry.
- Voice stack is better but still needs real microphone calibration and single-output monitoring.
- Some queued roadmap implementation objectives exist; they should be reconciled against approval/demo state.
- MIM/TOD training-to-action reflex is the next major autonomy gap.
- Service activation for third-party providers needs managed/client/self-managed workflows.
- Demo account is useful internally but should be hardened or auto-login gated before public exposure.

## Next Reference Update Triggers

Update this artifact when any of these change:

- new DB tables
- new project portal route
- new materialization policy
- new service or timer
- changed demo guardrail
- changed ethics/reference policy
- new MIM/TOD resource class
- new primary source of truth
- deployed portal UX change
- major objective execution architecture change

## Validation Snapshot

Validated live on MIM:

- `mim-mobile-web.service` active
- `mim-ready-task-dispatcher.service` active
- objective reconciliation timer active
- demo login authenticated
- demo mode true
- top logout visible
- consultant-first MIM greeting visible
- ideas/links/documents intake prompt visible
- latest consultant-first objective recorded in DB with task evidence
