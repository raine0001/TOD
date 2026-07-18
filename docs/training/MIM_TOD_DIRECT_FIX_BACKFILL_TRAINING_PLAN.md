# MIM/TOD Direct Fix Backfill Training Plan

Status: active_training_required

Purpose: Convert Codex emergency/direct product fixes into MIM/TOD learned capability work so future repairs are reasoned, evidence-derived, validated, and maintained by MIM/TOD instead of repeated by Codex.

## Rule

Direct Codex fixes do not count as MIM/TOD capability unless MIM/TOD can later explain, reproduce, validate, and generalize the fix from evidence.

Every direct fix must be backfilled with:

- what failed
- why it failed
- what evidence proved the failure
- what source data or route produced the correct behavior
- what changed
- what the change affects
- how it was validated
- what should be checked if it fails again
- what MIM/TOD should do next time without Codex

## Current Backfill Set

### Backfill 001: SolAir Cost Answer

Objective ID: `MIM-NUMERIC-ANSWER-FROM-EVIDENCE-BACKFILL-001`

Failure: User asked, "how much does it cost to build 1 solair?" MIM returned a generic manufacturing-discovery answer instead of a cost answer.

Expected MIM/TOD training output:

1. observed_bad_answer
2. user_intent
3. source_artifact_selected
4. artifact_fields_used
5. calculation_plan
6. uncertainty_boundary
7. source_link_strategy
8. generic_fallback_that_must_not_win
9. validation_commands
10. live_probe_plan
11. reusable_rule

Pass criteria:

- MIM/TOD explain why `SOLAIR_PARTS_BOM_OBSERVATION.latest.json` was the correct source.
- MIM/TOD explain why `build` alone should not force the generic manufacturing-discovery reply.
- MIM/TOD calculate the extended and unextended cost views from source rows, not from a memorized answer.
- MIM/TOD identify excluded costs: labor, tooling, overhead, scrap, freight, tax, QA, certification, current supplier pricing, and facility setup.
- MIM/TOD produce the validation sequence: local test, remote MIM-box test, service restart, live HTTP probe.
- MIM/TOD update or reference the Learned Capability: `docs/training/learned-capabilities/MIM_RESEARCH_NUMERIC_ANSWER_FROM_EVIDENCE_LEARNED_CAPABILITY.md`.

### Backfill 002: Event Edit Owner Tools

Objective ID: `MIM-EVENT-EDIT-OWNER-TOOLS-BACKFILL-001`

Failure: Dave opened `/observatory/calendar/events/2/edit` as event owner and saw only the edit form, not owner management tools.

Expected MIM/TOD training output:

1. observed_page_gap
2. route_checked
3. comparison_route
4. missing_section
5. auth_status
6. template_boundary
7. reusable_helper_or_rendering_plan
8. regression_test_fields
9. validation_commands
10. live_probe_plan
11. reusable_rule

Pass criteria:

- MIM/TOD explain that auth was working because the edit form loaded.
- MIM/TOD identify that owner tools existed on the event detail route, not the edit route.
- MIM/TOD identify the correct smallest repair: render the same owner management section on edit, not duplicate hidden logic.
- MIM/TOD list required visible fields: Share event, Add to Google Calendar, Join event, Add participant, Remove participant, Participation requests, Cancel event.
- MIM/TOD produce the validation sequence: route smoke test, service restart, live HTML probe for `/observatory/calendar/events/2/edit`.

### Backfill 003: Operator Project Auth Boundary

Objective ID: `MIM-PROJECT-AUTH-BOUNDARY-BACKFILL-001`

Failure: Dave's master/operator account could use `/studio` but could not use public project/Observatory owner surfaces.

Expected MIM/TOD training output:

1. observed_login_failure
2. account_boundary
3. studio_auth_boundary
4. project_portal_auth_boundary
5. required bridge behavior
6. safety rule preventing public users from `/studio`
7. validation_commands
8. live_probe_plan
9. reusable_rule

Pass criteria:

- MIM/TOD explain why `/studio` must remain operator-only.
- MIM/TOD explain why the operator account may mint project/Observatory access but public accounts may not mint `/studio` access.
- MIM/TOD produce tests that prove both boundaries.

### Backfill 004: Cross-Project Context Leak

Objective ID: `MIM-PUBLIC-CHAT-CROSS-PROJECT-CONTEXT-LEAK-BACKFILL-001`

Failure: A visitor used the public MIM homepage chat for a robotics automation project in a paper-products manufacturing facility. MIM answered with SolAir manufacturing/BOM language.

Expected MIM/TOD training output:

1. observed_bad_answer
2. user_intent
3. selected_context_before_fix
4. selector_rule_that_overmatched
5. stale_recall_or_cross_project_prefix
6. SolAir_only_helper_boundary
7. active_runtime_or_service_state
8. repair_summary
9. validation_commands
10. live_probe_plan
11. reusable_rule
12. recurrence_detection

Pass criteria:

- MIM/TOD explain that broad words like `manufacturing` must not select a Research Observatory project by token-only title matching.
- MIM/TOD explain that explicit project titles or Observatory session context may select a research initiative.
- MIM/TOD explain that SolAir-specific helper branches must run only when the active research context is SolAir.
- MIM/TOD explain that global visitor recall must not prepend an unrelated project goal to an active research-context answer.
- MIM/TOD explain that stored research context must yield to a new public homepage/build-planning request unless the user is on an Observatory page or explicitly names the research initiative.
- MIM/TOD explain how stale unmanaged runtime processes can keep old behavior alive after a file deploy.
- MIM/TOD produce the validation sequence: helper/module compile, direct remote Python probe, MIM-box local HTTP probe, public `www.mimtod.com` HTTP probe for broad chat, and public explicit-research probe.
- MIM/TOD update or reference the Learned Capability: `docs/training/learned-capabilities/MIM_PUBLIC_CHAT_CONTEXT_BOUNDARY_LEARNED_CAPABILITY.md`.

## Training Ladder For Each Backfill

1. MIM states what failed from the operator view.
2. TOD identifies the exact route/function/artifact involved.
3. MIM/TOD classify blocker type.
4. MIM/TOD identify the evidence source and the missing capability.
5. TOD proposes the smallest repair or confirms the existing repair.
6. MIM validates the reasoning before code changes.
7. TOD validates behavior with tests and live probes.
8. MIM/TOD produce a concise summary:
   - what changed
   - what it solves
   - what it does not solve
   - how to recognize recurrence
   - what capability was learned
9. Freeze or update the Learned Capability.
10. Resume the product objective.

## Non-Negotiable Constraints

- Do not hardcode factual answers.
- Do not hide missing evidence behind fallback text.
- Do not duplicate route logic when an existing reusable section or helper exists.
- Do not treat page load as proof that all expected tools rendered.
- Do not treat a generic answer as completion when the user asked a specific evidence question.
- Do not count Codex-authored fixes as MIM/TOD independence until backfill training passes.

## Initial Training Prompt For MIM/TOD

MIM and TOD, perform Backfill 001 first.

You are not being asked to write new product code.

You are being asked to reconstruct how the SolAir cost-answer failure was diagnosed and repaired, using evidence only.

Required output:

1. observed_bad_answer
2. user_intent
3. source_artifact_selected
4. artifact_fields_used
5. calculation_plan
6. uncertainty_boundary
7. source_link_strategy
8. generic_fallback_that_must_not_win
9. validation_commands
10. live_probe_plan
11. reusable_rule
12. what MIM should do next time before asking Codex

Success means MIM/TOD can explain the repair path and validation path without Codex supplying the answer text.
