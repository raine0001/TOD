# TOD Operator Chat Console v1

## Objective

Objective 85 adds a read-only operator chat layer on top of live TOD status. The goal is to make dense operational state explainable without turning TOD into a general assistant or a freeform shell.

## Scope

This version is constrained to explanation and guided suggestion.

- Read live TOD dashboard state from the same backend truth sources already used by the console.
- Explain warnings, bridge posture, cadence, maintenance, current objective state, and recent changes.
- Support recent-change summaries for both a fixed observation window and a fallback baseline of the last successful completion when recent completions are available.
- State explicitly when a requested last-successful-completion baseline falls back to a bounded recent-time window because no scoped successful completion was found.
- Suggest bounded next actions through existing UI-safe action paths.
- Do not execute arbitrary commands.
- Do not bypass existing UI action controls.

## Supported Intents

- `summarize_status`
- `explain_warning`
- `explain_bridge_status`
- `explain_cadence`
- `explain_maintenance`
- `suggest_next_action`
- `summarize_current_objective`
- `summarize_recent_changes`

## Response Contract

`POST /api/operator-chat`

Request fields:

- `query`: natural-language operational question
- `intent`: optional explicit constrained intent
- `objective_id`: optional objective override
- `window_minutes`: optional recent-change window, default `10`

Response shape:

- `query`
- `intent`
- `objective_id`
- `generated_at`
- `capabilities.intents`
- `capabilities.safe_actions`
- `response.summary`
- `response.evidence[]`
- `response.recommended_next_step`
- `response.suggested_actions[]`
- `response.confidence`
- `response.flags[]`
- `response.limitations[]`
- `response.citations[]`

Citation behavior:

- backend returns stable `section` and `field` tokens
- UI maps those tokens to concrete dashboard elements such as cadence health, bridge summary, listener heartbeat, maintenance severity, and action live status
- citation clicks scroll to and highlight the most relevant field and its containing card

Response flags:

- `listener_telemetry_fallback` means the answer is grounded in listener fallback mode rather than full `state.json`
- `recent_completion_baseline_fallback` means a requested last-successful-completion baseline was unavailable and the answer used a bounded recent-time window instead
- `observe_before_act` means the console has enough evidence to suggest investigation, but it is still steering the operator through bounded read-only refreshes before any intervention

## Data Sources

Operator chat must stay aligned with the live dashboard. It reads from:

- `/api/project-status` semantics through `Get-ProjectStatusPayload`
- listener journal and request/result packets
- bridge artifacts
- maintenance artifact `shared_state/TOD_SELF_HEALTH_RUN.latest.json`
- recovery watchdog state

## Safety Boundaries

- No arbitrary shell execution
- No unbounded restart logic
- No side-channel action path outside `/api/run` or existing UI refresh flows
- Suggested actions are bounded to read-only or existing UI-safe refresh paths

## UI Shape

The dashboard keeps its current card layout and adds a `TOD Operator Chat` card.

The panel includes:

- guided prompt buttons
- freeform but constrained operational question input
- inline legend for fallback-state tags so operators can interpret evidence posture without leaving the dashboard
- structured operator answers
- evidence cards
- suggested safe actions
- clickable citations back to dashboard cards
- confidence and limitation tags

## TOD-MIM Directed Continuation

Operator chat should not ask the operator to choose natural next steps when TOD and MIM can decide through their bounded coordination path. Objective 86 should add governed action confirmation and audit, not general execution.

See `docs/tod-operator-chat-console-v2-objective86.md` for the initial design scaffold.

- action confirmation flow
- allowed-vs-blocked explanation
- action audit trail
- existing control-path reuse only
