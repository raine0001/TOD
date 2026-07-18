# MIM Communication Input Process Audit V1

Date: 2026-07-13

## Purpose

Verify what MIM currently does when communication input arrives, and determine whether MIM is interpreting context or relying on hardcoded prompt expectations.

## Scope

Primary surface inspected:

- `/studio/api/mim/chat`

Supporting modules inspected:

- `tmp_remote_mim/core/routers/studio.py`
- `tmp_remote_mim/core/conversation_purpose_engine.py`
- `tmp_remote_mim/core/routers/public_chat.py`
- `tmp_remote_mim/core/routers/gateway.py`

## Current Studio Input Pipeline

Observed route:

1. Operator submits text through Studio.
2. Browser posts to `/studio/api/mim/chat`.
3. `studio_mim_chat_api` normalizes `page_context`, `prompt`, `prompt_lower`, and `metadata_json`.
4. Route checks self-evolution/status prompt handler.
5. Route checks active conversation context transition.
6. Route checks simple direct reply.
7. Route calls conversation purpose engine.
8. Route checks structural/direct/durability/training handlers.
9. Route may call gateway conversation composer.
10. Route falls back to operator-contract response.

## What Is Hardcoded

The current system uses hardcoded signal lists and phrase gates in multiple places.

Examples:

- `_studio_prompt_is_self_evolution_status_request`
- `classify_conversation_purpose`
- `_exploration_focus`
- `_studio_simple_direct_reply`

These include phrases such as:

- `what are you working on mim`
- `what would you like`
- `explore`
- `mission`
- `goal`
- `current failure`
- `oral exam`
- `bad gateway`

This means the current repair is partly a route vocabulary patch, not a true context-understanding capability.

## What Is Not Hardcoded

The last repair did not hardcode the final MIM answer body for the tested status prompts.

It expanded routing detection so those prompts reach the existing self-evolution status responder. That responder pulls current progress evidence.

However, the route decision itself is still heuristic.

## Critical Finding

The shared `conversation_purpose_engine` still classifies:

`what would you like to explore today MIM?`

as:

`exploration`

with:

`signals=[]`

Studio only handles it correctly because a pre-purpose Studio-specific phrase gate intercepts it first.

That proves the deeper model is incomplete.

## Root Cause

MIM does not yet have a context-first input interpretation stage.

Current architecture:

Operator input

->

Route-specific hardcoded gates

->

Conversation purpose keyword classifier

->

Response mode

Needed architecture:

Operator input

->

Active conversation context model

->

Speaker / actor / addressee model

->

Intent and purpose inference from structure, not exact phrases

->

Evidence-backed response mode

->

Fallback keyword gates only when confidence is low

## Blocker Class

Capability blocker.

## Blocker Name

`context_first_input_interpretation_missing`

## Why This Matters

If MIM keeps gaining phrase patches, it will appear better while becoming more brittle.

The correct capability is not:

Add more prompt variants.

The correct capability is:

Infer what kind of conversation this is from context, structure, addressee, active thread, and prior state.

## Training Objective

`MIM-CONTEXT-FIRST-INPUT-INTERPRETATION-V1`

Mission:

Teach MIM to interpret operator input using conversation context and semantic role before falling back to hardcoded phrase gates.

## Required Capability Model

MIM must identify:

- who is being addressed
- what active thread is in progress
- whether the operator is asking for current state, exploration, curriculum, execution, reflection, correction, or incident handling
- whether the prompt is a follow-up
- whether the prompt changes topic
- what evidence is required before responding

## Training Ladder

1. Read-only audit of current communication surfaces.
2. Build a process map for each major surface.
3. Separate protocol routing from cognitive interpretation.
4. Identify hardcoded phrase gates.
5. Classify which gates are acceptable deterministic protocol rules.
6. Classify which gates hide missing cognitive capability.
7. Design a context-first interpretation object.
8. Test 50 prompts with no exact phrase match.
9. Require MIM to output `active_thread`, `addressee`, `purpose`, `confidence`, `evidence_used`, and `why_not_another_purpose`.
10. Only after that, allow route selection.

## Validation Examples

MIM should treat these as self-status/current-focus prompts without exact phrase matching:

- `what are you thinking about today`
- `what has your attention right now`
- `where is your learning focused`
- `what do you want to explore`
- `what are you trying to understand`

MIM should treat these as exploration prompts:

- `why do brilliant engineering teams miss deadlines`
- `what capability might a company be missing`
- `what makes an organization good at execution`

MIM should treat these as curriculum:

- prompt includes mission, goal, observed failure, rules, pass condition, and required behavior

## Prevention Rule

No new phrase patches should be treated as capability completion.

As of 2026-07-13, the stricter rule is:

No new phrase patches as cognition repair.

Future fixes must train context-first interpretation. Existing phrase gates are debt to retire or demote to deterministic fallback, not a pattern to expand.

Phrase gates may remain only for deterministic protocol, schema, auth, safety, infrastructure, hardware, or backwards-compatibility boundaries.

## Current Assessment

MIM can be made to answer correctly through route patches.

MIM does not yet reliably understand input context before route selection.

That is the capability to train.
