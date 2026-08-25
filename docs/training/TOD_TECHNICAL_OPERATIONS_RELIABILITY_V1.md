# TOD Technical Operations Reliability V1

## Objective

Train TOD into the Technical Operations Director role: the system that watches MIM/TOD infrastructure, detects failures before users do, starts recovery without waiting, and publishes truthful status.

## Role Boundary

TOD owns technical operations.

MIM owns operator-facing coordination and product judgment.

Codex coaches and validates. Codex may perform emergency repair only when the control plane is already broken or TOD cannot make a bounded attempt.

## Scope

TOD must watch and maintain:

- TOD workstation health
- MIM Box service health
- public `mimtod.com` routes
- `mim.mimtod.com` Studio routes
- authenticated operator pages
- `/studio/projects`, `/studio/training`, `/studio/visitors`, `/studio/systems`
- MIM/TOD dialog and task request lanes
- runtime/shared latest artifacts
- scheduled training and daemon status
- document viewer and media pipelines
- Zoom/calendar/event support surfaces
- AgentMIM `/forum` post image/media health
- AgentMIM `/help` support ticket intake and response closure
- database-backed public activity and visitor surfaces
- git/worktree restore readiness

## Operating Doctrine

TOD does not wait for Dave or users to report broken pipes.

Every monitored surface must have:

- owner
- route or service identifier
- expected response
- expected content marker
- freshness rule
- log source
- recovery owner
- safe diagnostic command
- safe recovery command, when allowed
- escalation rule

## Training Ladder

### Rung 001: Inventory

TOD produces a service inventory with route/service, owner, authority, probe command, expected marker, and recovery boundary.

Pass condition:

- Inventory includes TOD local, MIM Box, public web, Studio, communication, scheduled training, DB-backed visitor pages, document/media, and event tools.
- No route is listed without an expected marker.

### Rung 002: Baseline Probe

TOD runs existing probes and records current health.

Required existing tools to inspect first:

- `scripts/Invoke-TODSelfHealthMaintenance.ps1`
- `scripts/Invoke-TODPublicRouteHealthCheck.ps1`
- `scripts/Invoke-TODSmoke.ps1`
- `scripts/Invoke-TODSmokeWatch.ps1`
- `scripts/Invoke-TODPcCrashObservation.ps1`

Pass condition:

- TOD publishes a baseline artifact with current state, gaps, and missing probes.
- TOD distinguishes "script ran" from "site/service verified."

### Rung 003: Studio Route Watch

TOD validates authenticated Studio pages.

Required routes:

- `/studio`
- `/studio/projects`
- `/studio/training`
- `/studio/visitors`

Pass condition:

- Each route reports HTTP status, expected title/content marker, response length, and latest error-log evidence.
- A 500 produces `down`, not `unknown`.

### Rung 004: MIM Box Service Watch

TOD checks MIM Box system/user services and recent logs.

Pass condition:

- Service state, restart age, recent errors, and log source are recorded.
- TOD does not claim health from process existence alone.

### Rung 005: TOD Workstation Self Maintenance

TOD checks local PC health.

Required checks:

- recent crash or freeze evidence
- disk free space
- git worktree restore readiness
- driver/update watch notes
- scheduled TOD daemon health
- power/sleep settings relevant to overnight runs

Pass condition:

- TOD publishes local health with risks, safe actions, and external actions.

### Rung 006: Failure Classification Drill

TOD is given three controlled failures or historical incidents and must classify them:

- route 500
- stale queue / no ACK
- local PC freeze

Pass condition:

- TOD classifies blocker type, evidence, owner, smallest diagnostic, safe repair, and validation target without Codex root-cause first.

### Rung 007: Safe Recovery Drill

TOD performs only safe recovery:

- refresh probe
- restart allowed service
- quarantine stale projection only when authority is proven
- validate external route

Pass condition:

- TOD proves recovery with before/after evidence.
- No destructive action runs without guardrail classification.

### Rung 008: Operator-Visible Status

TOD publishes concise status for MIM/Studio:

- healthy/degraded/down/blocked
- what changed
- what TOD is doing
- evidence
- Dave required: yes/no

Pass condition:

- A non-engineer can tell whether the system is healthy and what TOD is doing.

### Rung 009: Incident Freeze

Every new pattern becomes a Learned Capability.

Pass condition:

- Freeze includes Capability Name, Trigger, Reality, Observation, Root Cause, Blocker Class, Decomposition Ladder, Smallest Successful Rung, Implementation Summary, Validation, General Rule Learned, Prevention Rule, Reuse Trigger, Dependent Capabilities, Capability Confidence, Independent Pass Rate, Date Frozen, and Generalized Principle.

### Rung 010: Autonomous Patrol

TOD runs a recurring patrol and reports only deltas or failures.

Pass condition:

- At least three patrol cycles complete.
- TOD reports no noise when healthy.
- TOD reports and starts recovery when degraded.
- TOD does not create duplicate artifacts for unchanged state.

### Rung 011: Public Media Patrol

TOD checks that public pages with required media still expose and serve media assets.

Initial required surface:

- `https://www.agentmim.com/forum`

Pass condition:

- `/forum` route is reachable.
- `/forum` contains at least one image candidate.
- At least one image candidate returns HTTP 2xx or 3xx.
- A missing/broken media surface produces `technical_route_media_unhealthy:<route_label>`, not `healthy`.
- TOD records the media candidate URLs checked and the HTTP result for each.

Training lesson:

TOD must not treat "page loaded" as "media pipeline healthy." A forum whose posts load without generated images is degraded.

### Rung 012: Helpdesk Intake and Closure Patrol

TOD verifies that public help requests become TOD-visible work, not just a UI success message or admin email.

Initial required surface:

- `https://www.agentmim.com/help`
- AgentMIM support ticket model/API/admin ticket queue

Pass condition:

- `/help` route is reachable.
- Submitted support tickets create a durable ticket record.
- Ticket records include enough fields for TOD to classify the issue, owner, requester, current status, and required evidence.
- TOD has a read-only patrol path that lists open/new tickets.
- TOD can publish a TOD-visible ticket queue artifact.
- TOD can acknowledge, update, and close a ticket through an approved response lane.
- A help request is not considered handed to TOD until TOD can see it in that durable queue.

Training lesson:

`tod_handoff=true` is not proof of operational handoff. TOD must be able to independently patrol, acknowledge, work, update, and close the ticket.

### Rung 013: Worktree Restore Readiness

TOD keeps the workspace recoverable while active development continues.

Pass condition:

- TOD can separate source changes, tests, docs, runtime artifacts, generated captures, and external mirror changes.
- TOD can report dirty worktree categories without exposing secrets.
- TOD can identify which changes are commit-ready and which are still active work.
- TOD never destroys unrelated user or MIM/TOD work while cleaning.
- TOD publishes a restore-readiness summary before any long unattended run.

Training lesson:

A dirty worktree is not automatically bad, but an unexplained dirty worktree is operational risk. TOD must keep it understandable enough to recover from a machine loss.

## Initial Training Seed

Use the Studio failure from 2026-07-09 as the first incident:

- `/studio/projects` and `/studio/training` returned 500.
- Production logs showed `AttributeError: 'StudioProject' object has no attribute 'setdefault'`.
- Root cause was mixed seed contract: one `StudioProject` object in a dictionary seed list.
- Emergency repair normalized the seed entry before dictionary mutation.
- TOD must learn to detect, diagnose, classify, and validate this class of failure.

## Success Criteria

100% means:

- service inventory exists
- probes cover all critical surfaces
- Studio route health is authenticated and validated
- MIM Box service health is checked
- TOD PC self-maintenance is checked
- communication lanes are checked
- failures create blocker packets automatically
- safe recovery begins automatically
- operator-visible status is published
- incidents freeze learned capabilities
- three patrol cycles complete without Codex doing the reasoning
- public media checks cover `/forum`
- helpdesk intake is visible to TOD through a durable queue
- worktree restore readiness is reported without touching secrets

## Current Expected First Blocker

The existing TOD public route health script focuses on `/tod` and does not yet cover the full `mimtod.com` and `mim.mimtod.com` Studio surface.

Expected classification:

`capability_blocker`: technical operations patrol inventory is incomplete.

Smallest repair:

TOD produces a read-only route/service inventory and identifies which existing probes can be reused before writing any new code.

## Current Live Patrol Update

Generated during the public-site patrol expansion.

Observed:

- `mimtod.com` public routes are now included in the Technical Operations route inventory.
- `mim.mimtod.com/studio` routes are now included in the Technical Operations route inventory.
- `agentmim.com/forum` is now included with a required media probe.
- `agentmim.com/help` is now included as a public support ticket intake route.
- The latest live patrol showed `/forum` reachable and at least two image assets returning HTTP 200.
- The latest live patrol showed `/help` reachable and returning its expected support marker.
- The local TOD UI route remained unreachable at `http://localhost:8844/tod`.

Remaining blocker:

`tod_helpdesk_durable_inbox_missing`

Classification:

`capability_blocker`

Reality:

AgentMIM ticket creation records `tod_handoff=true`, but the inspected flow does not yet prove that TOD has a durable ticket inbox, patrol artifact, acknowledgement, response, and closure lane.

Smallest training rung:

TOD performs a read-only support ticket lane audit:

1. identify the support ticket model/table/API
2. identify the ticket statuses and owner/requester fields
3. identify whether TOD has a readable open-ticket queue
4. identify how TOD should acknowledge and update a ticket
5. publish a blocker or proof artifact

No ticket responder implementation begins until the read-only lane audit proves the existing contract.

## Local TOD UI Startup Repair

Observed:

- Technical Operations patrol reported `technical_route_unreachable:local_tod_ui`.
- `http://localhost:8844/tod` and `http://localhost:8844/api/project-status` were not reachable.
- Running `scripts/Start-TOD-UI.ps1 -Port 8844 -NoAutoOpen` started the listener, then crashed while calling `Start-TodUiLanProxy`.
- Root cause: local-only startup passed an empty `ListenHost` into the LAN proxy helper, and the helper parameter rejected empty strings before its own "No LAN advertise host requested" branch could run.

Repair:

- `scripts/Start-TOD-UI.ps1` now allows an empty `ListenHost` for `Start-TodUiLanProxy`.
- The helper can now return the existing no-proxy result instead of crashing local-only UI startup.

Validation:

- `scripts/Start-TOD-UI.ps1` parses successfully.
- `Invoke-Pester .\tests\TOD.UiStartup.Tests.ps1 -PassThru` returned `2 passed, 0 failed`.
- `http://localhost:8844/api/project-status` returned HTTP 200 after startup.
- Technical Operations patrol now reports `technical_operations_status=healthy`.

Separate route-contract debt:

`legacy_public_tod_route_contract_stale`

Reality:

The older public TOD compatibility check still targets `https://www.agentmim.com/tod` and `https://www.agentmim.com/tod/ui/state`, which now return 404. The expanded Technical Operations route inventory is healthy, but the legacy compatibility status remains `attention`.

Training rule:

TOD must separate current public site health from obsolete compatibility probes. A stale probe must be retired, reconfigured, or explicitly marked compatibility-only; it must not be allowed to mask current route health.

## Live Infrastructure Inventory and Drift Ownership

Implemented on 2026-08-25 as a scaffolded Technical Operations capability:

- The existing TODBOX boot and 15-minute connectivity verifier now publishes `/var/lib/todbox-connectivity/system-inventory.latest.json`.
- Inventory facts include TOD ownership, hostname/interface policy, systemd service state and dependency fields, unit configuration hashes, active model lanes, AgentMIM's stable MIM gateway hostname and mode, and evidence URLs.
- Missing tunnel origin mapping is recorded as `origin_mapping_proven=false`, not inferred.
- A configuration fingerprint produces change-only history under `/var/lib/todbox-connectivity/inventory-changes/`.
- An unchanged patrol updates freshness without creating duplicate history.
- `todbox-system-inventory-query forum_image_generation` returns the current tunnel evidence.
- TOD's evidence query automatically receives the fresh inventory, allowing natural-language infrastructure answers without starting discovery from zero.

Current acceptance evidence:

- owner: `TOD`
- stable endpoint: `https://mim.mimtod.com`
- mode: `managed_tunnel`
- tunnel service: `cloudflared-todbox-hosting.service`
- status: `reachable`
- maximum inventory age: 900 seconds
- origin mapping: not proven
- live acceptance: passed with scaffolded inventory context

Independence boundary:

This capability remains `scaffolded_pass`. TOD must independently absorb a fresh analogous service/configuration change and update or extend the inventory without Codex selecting the fields or implementation.
