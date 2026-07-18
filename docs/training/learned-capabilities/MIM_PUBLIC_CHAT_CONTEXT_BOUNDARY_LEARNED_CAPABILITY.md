# Learned Capability: Public Chat Context Boundary

## Capability Name
MIM public chat cross-project context isolation and Research Observatory selector discipline.

## Trigger
A public homepage chat answer mentions a project, document set, source artifact, or research initiative that the user did not ask about, especially when a broad user phrase overlaps with a seeded research project title.

## Reality
The public homepage chat is a general interaction surface. A visitor may describe a new idea such as a robotics automation project without intending to enter a Research Observatory initiative.

Research Observatory pages are different. They may pass an explicit research context, use an Observatory session key, or respond when the user names a specific research initiative.

## Observation
The user entered a public homepage chat message about a robotics automation project for a manufacturing facility that produces paper products for food service.

MIM replied with SolAir manufacturing discovery text, including observed BOM language, SolAir frame/blade/motor/solar lanes, and SolAir-specific uncertainty boundaries.

Live response evidence showed the session context could identify `robotics-small-manufacturing`, but the reply still used SolAir manufacturing language. After the SolAir helper boundary was repaired, the public response still prepended a stale SolAir goal from global recall.

A sharper recurrence appeared when a user asked for an automation plan for a disposable tableware manufacturer. In a session that had previously selected `Robotics in Small Manufacturing`, MIM answered from the research archive instead of starting project discovery.

## Root Cause
There were three interacting causes:

1. `public_chat.py::_observatory_research_context_from_message` used token-only title aliases, so a broad word like `manufacturing` could select `Robotics in Small Manufacturing`.
2. `public_research_context.py::research_context_reply` called SolAir-specific answer helpers even when the active research context was not SolAir.
3. Research-context replies accepted a global public-chat recall prefix, so an unrelated SolAir goal could be prepended to a robotics answer.
4. Stored session research context kept winning over new public project-planning language, even when the user was no longer asking an Observatory/research question.

A deployment/runtime issue also delayed visible repair: an unmanaged old uvicorn process owned port `18001`, so `mim-mobile-web.service` could not start the corrected code until the stale process was removed and the managed service was restarted.

## Blocker Class
- `capability_blocker`: MIM/TOD needed context-boundary reasoning, not another hardcoded answer.
- `authority_blocker`: an unmanaged stale runtime process served old code while the managed service failed with port-in-use.
- `data_blocker`: broad user text lacked explicit research-project intent.

## Decomposition Ladder
1. Reproduce the public bad answer with a fresh session key.
2. Inspect returned session context and reply text separately.
3. Check whether the context selector, answer helper, or recall prefix introduced the wrong project.
4. Directly call the research helper with the selected non-SolAir context.
5. Guard SolAir-only helpers behind `context.id == "solair"`.
6. Remove unrelated global recall prefixes from research-context answers.
7. Tighten message-based research matching to explicit initiative id/title only.
8. Add a project-planning escape hatch so stored research context yields when the user asks to build, create, plan, automate, or map a workflow.
9. Verify local syntax.
10. Verify direct remote Python behavior.
11. Verify MIM-box local HTTP behavior on port `18001`.
12. Verify public `www.mimtod.com` behavior through the real endpoint.
13. Preserve the learned rule and recurrence probes.

## Smallest Successful Rung
The smallest successful behavioral rung was a direct remote Python probe:

- context id: `robotics-small-manufacturing`
- reply prefix: `For Robotics in Small Manufacturing...`
- SolAir manufacturing text present: `False`

The final successful product rung was the public HTTP probe:

- broad robotics/manufacturing prompt
- no active research context
- no SolAir text
- no research archive fallback

The follow-up successful product rung was a sticky-session probe:

- first message selected `robotics-small-manufacturing`
- second message asked for an automation plan for a disposable tableware manufacturer
- stored research context was cleared
- reply used project discovery/planning language
- no research archive or metadata-level fallback appeared

## Implementation Summary
Direct production repair performed by Codex:

- `tmp_remote_mim/core/public_research_context.py`
  - SolAir-specific helper branches now run only when `context.id` is `solair`.
  - Research-context replies no longer prepend global visitor recall summaries.
- `tmp_remote_mim/core/routers/public_chat.py`
  - Message-based Research Observatory selection now matches explicit initiative id/title only, not individual title tokens.
  - Stored research context is cleared for new public project/build/planning requests unless the user supplies explicit Observatory context.
  - Manufacturing automation planning prompts are seeded as discovery/planning requests so MIM asks about products, process steps, machinery, volumes, bottlenecks, quality issues, space, budget, timeline, and automation type.
- `tmp_remote_mim/tests/test_public_chat_research_session_context.py`
  - Added focused regression coverage for broad manufacturing prompts and stale SolAir recall.

This was a direct repair, not a proven independent MIM/TOD-authored repair. It must be used as training backfill, not counted as MIM/TOD implementation independence.

## Validation
Validated checks:

- `python -m py_compile tmp_remote_mim/core/public_research_context.py tmp_remote_mim/core/routers/public_chat.py tmp_remote_mim/tests/test_public_chat_research_session_context.py`
- remote direct Python probe returned non-SolAir robotics research text.
- remote local HTTP probe on `127.0.0.1:18001` returned a general robotics automation answer for the broad homepage prompt.
- public HTTP probe to `https://www.mimtod.com/public/chat/message` returned:
  - no SolAir text for broad robotics/manufacturing chat
  - no research archive fallback for broad homepage chat
  - explicit `Robotics in Small Manufacturing` prompt still selected the research initiative
  - `Hi MIM, what can you do?` returned a general MIM answer with no SolAir text
- sticky-session public probe returned:
  - first message selected `robotics-small-manufacturing`
  - second automation-plan message cleared active research context
  - no research archive fallback
  - no metadata-level fallback
  - response asked targeted project-discovery questions

## General Rule Learned
Context selection is authority. If the selector overreaches, the response can be factually grounded in the wrong world.

Broad user language should remain conversational unless the user explicitly names a research initiative or the page/session supplies that research context.

Stored context is a hint, not a cage. A new public project-planning request can shift the conversation away from a prior research initiative.

## Prevention Rule
Do not select a Research Observatory initiative from generic title tokens such as `manufacturing`, `energy`, `health`, `education`, or `robotics`.

Do not run project-specific answer helpers outside their project context.

Do not prepend global visitor memory to a project-grounded answer unless the memory is verified to belong to the same project or session context.

Do not let stored `active_public_project` override public build/planning language. If the latest user turn is a new project-intake request and there is no incoming Observatory context, clear the stored research project before composing the answer.

After deployment, verify the managed service is actually serving the code. If live behavior disagrees with direct module behavior, check stale processes, service state, port ownership, and worker restart state before changing logic again.

## Reuse Trigger
Use this capability when:

- homepage chat mentions the wrong project,
- MIM answers a general idea with Observatory source language,
- SolAir appears in a non-SolAir answer,
- a research response includes stale memory from another project,
- direct Python behavior and live HTTP behavior disagree,
- `mim-mobile-web.service` is active/restarting but another process owns port `18001`.

## Dependent Capabilities
- public chat memory scoping
- Research Observatory context routing
- project-specific evidence helper boundaries
- deployment/runtime service verification
- MIM/TOD direct-fix backfill training

## Capability Confidence
7/10.

The product behavior is verified, but MIM/TOD have not yet independently reproduced the reasoning and repair.

## Independent Pass Rate
Not yet established. Codex performed the diagnosis and production repair. MIM/TOD must pass Backfill 004 from the direct-fix training plan before this can count as learned.

## Date Frozen
2026-07-08

## Generalized Principle
Memory and context are useful only when scoped. A system that remembers everything must also know what not to bring into the current conversation.
