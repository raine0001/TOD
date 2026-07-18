# Learned Capability: SolAir Evidence Routing And Answer Compression V1

Capability Name: Source-grounded SolAir answer routing, evidence conflict handling, and direct-answer compression.

Trigger: A SolAir question mentions solar panel, solar film, solar fin, PV, blade material, parts, components, power, watts, output, or wind speed.

Reality: SolAir research questions can point to different evidence lanes. Solar-panel questions should not use wind power curves. Blade-material questions should not dump the full bill of material. Wind-output questions have at least two evidence views: a conservative calculated physics-limit workbook and a higher Dyocore/SolAir chart workbook.

Observation: MIM previously answered a solar-panel question with wind-turbine output, treated a higher chart lane as the practical answer without enough conflict framing, and answered a blade-material question by dumping a broad BOM inventory.

Root Cause: The research context router matched broad power terms before stronger domain terms such as solar, panel, fin, PV, and film. The BOM reply path had no direct-answer branch for specific component/material questions. Tests preserved the older behavior by expecting the higher chart lane as a normal output answer.

Blocker Class: capability_blocker plus validation_gap.

Decomposition Ladder:
1. Identify whether the question is asking about solar, wind, blade material, broad parts, or major components.
2. Route solar-panel/PV/film questions before generic power questions.
3. Route blade-material questions before broad BOM questions.
4. Lead wind-output answers with physics-limit calculations and label chart values as separate unresolved evidence.
5. Compress direct answers before adding evidence boundaries.
6. Add tests for every previously wrong prompt.
7. Deploy to MIM box and verify live public chat behavior with SolAir page context.

Smallest Successful Rung: Direct solar-panel prompt with page context returns the solar evidence lane and does not include the wind curve dump.

Implementation Summary: Updated `core/public_research_context.py` to add solar-panel power detection, solar evidence reply, blade-material reply, key-component BOM summarization, supplier part-number display, and conflict-aware wind output summaries.

Validation:
- Local `test_public_research_context.py`: passed.
- Local `test_public_chat_research_session_context.py`: passed.
- Remote MIM-box `test_public_research_context.py`: passed.
- Remote MIM-box `test_public_chat_research_session_context.py`: passed.
- Live public chat probes passed for solar-panel output, blade material, 10 mph wind output, and major components using the SolAir Observatory page context.

General Rule Learned: Strong domain terms outrank generic terms. "Power" alone is not enough to select an evidence lane when the question also names a subsystem.

Prevention Rule: Every direct factual research answer must choose the narrowest evidence lane, answer the direct question first, cite source basis, and expose uncertainty or conflicts without dumping adjacent evidence.

Reuse Trigger: Reuse when a research answer confuses subsystem output, cites adjacent artifacts, dumps inventory for a specific material/component question, or treats one evidence view as final while another authoritative-looking source conflicts.

Dependent Capabilities: research document assimilation, source artifact loading, BOM row extraction, public chat research-session context, direct-answer compression, evidence conflict classification.

Capability Confidence: 8/10 for the covered SolAir prompts. Lower for unseen research domains until the same routing pattern is generalized beyond SolAir-specific artifacts.

Independent Pass Rate: Not measured as TOD-independent. Codex performed this escalation after repeated live failure; this remains TOD training debt.

Date Frozen: 2026-07-06.

Generalized Principle: Evidence routing is part of reasoning. The system should not answer from the first matching artifact; it should select the evidence lane that best matches the user's actual object of inquiry.
