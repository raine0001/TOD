# MIM Self-Status Prompt Context Routing Repair V1

Date: 2026-07-13

## Capability Name

Self-status prompt routing without exploratory scaffold leakage.

## Trigger

Dave asked MIM, through the real Studio MIM surface:

`Hi MIM what are you working on`

MIM answered with a generic exploratory scaffold instead of reporting its current work from evidence.

Follow-on trigger:

`what would you like to explore today MIM?`

MIM again answered with the generic exploratory scaffold. This proved the first repair covered `work on` and `learn` variants but not self-directed exploration/research verbs.

## Reality

The local mirror had a repaired self-evolution status responder, but the live operator surface can be served by multiple MIM web lanes. A local test pass or one backend-port pass is not enough proof that the browser route is repaired.

## Observation

- Local focused tests did not originally cover the greeting-order prompt form.
- Remote `core/routers/studio.py` did not contain the exact `mim what are you working on` status intent marker before deployment.
- Both `mim-mobile-web.service` and `mim-training-web.service` were active.
- After deployment and restart, both backend ports returned `studio_self_evolution_status` for the exact prompt.
- A second prompt, `what would you like to explore today MIM?`, failed because the self-directed learning invitation vocabulary did not include `explore`.

## Root Cause

The Studio status-intent matcher recognized some direct forms such as `what are you working on MIM`, but did not robustly handle greeting/order variants such as `Hi MIM what are you working on`. The self-directed learning invitation branch also recognized `work on`, `learn`, `focus on`, `train on`, and `practice`, but missed `explore`, `investigate`, `research`, `study`, and `understand`. These prompts fell through to the conversation-purpose exploratory composer, which generated plausible but wrong exploration answers.

## Blocker Class

Capability blocker plus live-surface verification blocker.

## Decomposition Ladder

1. Prove the exact operator prompt fails on the live surface.
2. Locate the Studio route that handles `/studio/api/mim/chat`.
3. Inspect route ordering before the conversation-purpose engine.
4. Find the status-intent detector.
5. Add the smallest intent-recognition repair that routes to the existing progress-ledger responder.
6. Add a focused regression test for the exact prompt form.
7. Compile the changed router.
8. Run focused tests.
9. Deploy the router to the MIM box.
10. Restart both serving lanes.
11. Probe both backend ports with the exact prompt.
12. Freeze the lesson and require TOD independent demonstration.

## Smallest Successful Rung

Add `mim what are you working on` to the existing self-status intent terms, broaden the existing fallback to recognize self-directed `you/your` forms for `what are you working on` prompts, and expand self-directed learning invitation verbs to include `explore`, `investigate`, `research`, `study`, and `understand`.

This does not hardcode the answer. It only routes the prompt to the existing evidence-grounded self-evolution status responder.

## Implementation Summary

Changed:

- `tmp_remote_mim/core/routers/studio.py`
- `tmp_remote_mim/tests/test_studio_training_chat.py`

Behavior change:

- `Hi MIM what are you working on` now routes to `studio_self_evolution_status`.
- `what would you like to explore today MIM?` now routes to `studio_self_evolution_status`.
- The reply is generated from current self-evolution progress, not from the generic exploratory scaffold.

## Validation

Local:

- `python -m py_compile tmp_remote_mim/core/routers/studio.py tmp_remote_mim/core/conversation_purpose_engine.py`
- `.venv\Scripts\python.exe -m unittest tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_operator_status_prompts_without_metadata_use_progress_ledger tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_exploratory_reasoning_is_prompt_grounded_not_canned tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_live_self_evolution_prompt_is_not_hardcoded_in_production_core`

Remote:

- Deployed `core/routers/studio.py` to `/home/testpilot/mim/core/routers/studio.py`.
- Ran remote compile: `.venv/bin/python -m py_compile core/routers/studio.py`.
- Restarted `mim-mobile-web.service` and `mim-training-web.service`.
- Probed ports `18001` and `18021` with `Hi MIM what are you working on`.
- Probed ports `18001` and `18021` with `what would you like to explore today MIM?`.

Remote probe result:

- `source=studio_self_evolution_status`
- `response_mode=self_evolution_operator_status`
- `leak=False`

Follow-on remote probe result:

- `source=studio_self_evolution_status`
- `response_mode=self_evolution_operator_status`
- `leak=False`
- `status=True`

## General Rule Learned

Self-status prompts are not exploration prompts. When the operator asks what MIM is doing, training, learning, focusing on, working on, exploring, researching, investigating, studying, or trying to understand, MIM should answer from current state evidence before any general conversation-purpose reasoning runs.

## Prevention Rule

Every new conversation-purpose or exploratory-reasoning repair must include negative tests for self-status prompts so MIM does not turn status questions into generic philosophy.

## Reuse Trigger

Use this capability when:

- MIM answers a self-status prompt with a generic hypothesis.
- MIM says a status question is exploration.
- Local tests pass but the browser surface still shows old behavior.
- One MIM backend port passes but another serving lane still fails.

## Dependent Capabilities

- Active conversation context recognition.
- Conversation purpose recognition.
- Self-evolution progress ledger reporting.
- Cross-service live surface verification.
- Emergency repair apprenticeship.

## Capability Confidence

Implementation confidence: high for the tested prompt family.

Independence confidence: not acquired by TOD yet. This was a Codex emergency repair and remains apprenticeship debt.

## Independent Pass Rate

TOD independent pass rate: pending.

Required TOD demonstration:

TOD must diagnose a fresh live-surface mismatch where local tests pass but a real operator route still fails, map the route to its service lane, apply or request the bounded repair, restart only the necessary service, and prove the same user-visible prompt now routes correctly.

## Date Frozen

2026-07-13 as an emergency repair lesson.

## 2026-07-15 Follow-Up: Self-Directed Focus Prompt

Trigger:

`what would you like to focus training on?`

Observed regression:

The live Studio route still let this prompt fall through to `studio_conversation_purpose_engine` and the generic exploratory scaffold even though gateway-level self-directed focus detection already existed.

Repair:

The Studio self-evolution status detector now recognizes focus-training phrasing such as `focus training`, `training focus`, `focus your training`, `focus to train`, and `train next`. When the prompt asks what MIM would like to work on, learn, explore, study, or focus training on, the Studio route answers from current training evidence as a self-directed priority choice instead of a status dump or generic exploration.

Validation:

- Local: `python -m py_compile tmp_remote_mim/core/routers/studio.py tmp_remote_mim/tests/test_studio_training_chat.py`
- Local: `python -m unittest tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_operator_status_prompts_without_metadata_use_progress_ledger tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_studio_self_directed_focus_uses_progress_ledger_before_exploration tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_gateway_self_directed_focus_selects_priorities_from_evidence tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_live_self_evolution_prompt_is_not_hardcoded_in_production_core`
- Remote: `.venv/bin/python -m py_compile core/routers/studio.py tests/test_studio_training_chat.py`
- Remote: `.venv/bin/python -m unittest tests.test_studio_training_chat.StudioTrainingChatTest.test_studio_self_directed_focus_uses_progress_ledger_before_exploration tests.test_studio_training_chat.StudioTrainingChatTest.test_operator_status_prompts_without_metadata_use_progress_ledger`
- Live ports `18001` and `18021`: `what would you like to focus training on?` returned `source=studio_self_evolution_status`, `response_mode=self_evolution_operator_status`, with no exploratory scaffold and no operator contract block.

Training debt:

This remains borrowed/scaffolded route repair. TOD should independently detect the next self-directed prompt that falls through to exploration, inspect route ordering, choose the smallest detector or authority fix, validate both lanes, and update the learned capability without Codex selecting the exact phrases.
