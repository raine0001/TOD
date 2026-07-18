# Learned Capability: Cross-Surface Conversation Purpose Routing V1

Capability Name: Cross-surface conversation purpose routing and formatter containment.

Trigger: A conversation behaves correctly on one MIM surface but incorrectly on another surface, especially when reflective, curriculum, architecture, executive discussion, or incident messages are converted into operational contracts.

Reality: MIM had more than one operator-facing conversation path. The direct Studio API used conversation purpose recognition, while MIM Wall and gateway fallback paths could enter deterministic gateway responders and formatter logic before the purpose decision was enforced.

Observation: A reflective oral-exam prompt returned an operational contract with fields such as `Recommended action`, `Owner`, `Expected evidence`, `Aging rule`, and `Dave needed` on real operator gateway surfaces, while the direct Studio API already classified reflection correctly.

Root Cause: Conversation purpose recognition was not the first shared doorway for all operator surfaces. Some gateway paths could be intercepted by active-project/context responders or later wrapped by the operator-impact formatter.

Blocker Class: authority_blocker plus routing_contract_gap plus validation_gap.

Decomposition Ladder:

1. Preserve the operator-visible bad reply.
2. Identify every surface the operator could be using.
3. Inspect the page JavaScript to find each POST endpoint.
4. Test the internal Studio API separately from the real wall/gateway endpoints.
5. Compare reply mode and forbidden formatter markers.
6. Locate deterministic responders that run before the intended purpose engine.
7. Locate formatter logic that appends operational contracts.
8. Add or require a shared purpose decision before deterministic project/status responders.
9. Suppress operational contract formatting only when the shared purpose engine says the conversation is non-operational.
10. Validate all surfaces with the same prompt and expected no-contract result.
11. Freeze the route-ordering rule for future MIM/TOD surfaces.

Smallest Successful Rung: The same reflective oral-exam prompt returns `reflective_oral_exam` without operational contract fields on `/studio/api/mim/chat`, `/gateway/intake/text`, and `/gateway/intake`.

Implementation Summary: Codex created a shared conversation purpose engine, wired gateway conversation-layer paths to it before active-project fallback, added a contract suppression flag for non-operational replies, and aligned Studio direct chat with the shared engine.

Validation:

- Compile: `python3 -m py_compile core/conversation_purpose_engine.py core/routers/gateway.py core/routers/studio.py`
- Focused tests: `.venv/bin/python -m pytest -q tests/integration/test_conversation_purpose_engine_gateway_contract.py tests/integration/test_studio_conversation_purpose_engine.py`
- Runtime: `mim-mobile-web.service` active after restart.
- Live probes: `/studio/api/mim/chat`, `/gateway/intake/text`, and `/gateway/intake` all returned reflective oral-exam responses without operational contract fields.

General Rule Learned: A cognitive router is not real until every operator surface enters through it before deterministic responders and formatters.

Prevention Rule: Any new MIM conversation surface must publish its endpoint, route preference, formatter path, and purpose-engine coverage test before it is considered production-safe.

Reuse Trigger: Reuse this capability when a message is classified correctly in one route but not another, when an operational contract appears in a reflective/curriculum conversation, or when a new UI surface is added.

Dependent Capabilities: endpoint tracing, route-source inspection, live HTTP probing, formatter containment, conversation purpose classification, evidence-only closure reporting.

Capability Confidence: 8/10 for the repaired MIM surfaces. Lower for future surfaces until TOD proves route coverage with live probes.

Independent Pass Rate: Not yet measured. Codex performed the emergency repair. TOD must backfill the reasoning and pass at least one unseen cross-surface simulation before claiming independence.

Date Frozen: 2026-07-11.

Separate Debt: Build a formal capability registry-backed answer synthesizer so reflective oral-exam content is generated from capability history rather than route-local response logic.

Generalized Principle: Test the surface the operator actually uses. Internal service success is useful evidence, not final proof.
