# MIM Hardcoded Answer Audit And Replacement V1

Generated: 2026-07-13

## Capability Name

Hardcoded answer detection and replacement with evidence-shaped response composition.

## Trigger

Dave asked Codex to verify that MIM was not hardcoding answers after MIM repeatedly returned the same exploratory paragraph for different operator prompts.

## Reality

MIM was not hardcoding the exact live self-evolution prompt in production code, but production code did contain canned exploratory answer bodies.

## Observation

`tmp_remote_mim/core/conversation_purpose_engine.py` contained fixed exploratory reply paragraphs in `_build_exploratory_reasoning_reply`.

TOD attempted the repair through `execute-chat-task`, but the local execution lane materialized the task as validation-only and published `blocked_missing_local_executor_result` with no changed files.

## Root Cause

The conversation-purpose engine recognized exploration, then used fixed answer bodies instead of composing a prompt-grounded hypothesis from current signals.

TOD also lacks a reliable bounded local execution path for this class of source edit when the request arrives as a chat task.

## Blocker Class

- `capability_blocker`: MIM response integrity; TOD bounded source-edit execution.
- `response_integrity_regression`: MIM can classify a conversation correctly while still responding from canned answer bodies.

## Decomposition Ladder

Level 1: Verify whether exact user prompts are hardcoded.

Level 2: Locate fixed answer bodies that can trigger from broad phrase patterns.

Level 3: Replace canned answer bodies with a small response composer that uses prompt-derived focus, hypothesis, alternative, and evidence-needed fields.

Level 4: Add tests proving varied exploratory prompts do not produce identical text.

Level 5: Add tests proving exact live prompts are not present in production core files.

Level 6: Train TOD to perform this same audit and replacement without Codex-authored code.

## Smallest Successful Rung

Focused local validation passed:

```text
python -m unittest tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_exploratory_reasoning_is_prompt_grounded_not_canned tmp_remote_mim.tests.test_studio_training_chat.StudioTrainingChatTest.test_live_self_evolution_prompt_is_not_hardcoded_in_production_core
..
Ran 2 tests in 0.020s
OK
```

## Implementation Summary

`_build_exploratory_reasoning_reply` now derives a response from prompt-signal categories:

- organizational execution
- research interpretation
- trust and reality correspondence
- project discovery
- open exploration

The reply still has a consistent reasoning structure, but the hypothesis, relationship, alternative, and evidence request come from prompt-derived focus instead of fixed example answers.

## Validation

Passed:

- `python -m py_compile tmp_remote_mim/core/conversation_purpose_engine.py tmp_remote_mim/tests/test_studio_training_chat.py`
- focused no-hardcode unittest pair above
- source scan found no production-core hits for:
  - `this is an exploration question`
  - `visible symptom may not be the root capability gap`
  - `They are probably missing executive coordination`
  - `hi MIM what would you like to work on or learn today?`
- remote MIM box deploy and probe:
  - copied `tmp_remote_mim/core/conversation_purpose_engine.py` to `/home/testpilot/mim/core/conversation_purpose_engine.py`
  - restarted `mim-mobile-web.service` and `mim-training-web.service`
  - both services returned active
  - `/studio/api/mim/chat` on ports `18001` and `18021` returned `source=studio_conversation_purpose_engine`, `mode=exploratory_reasoning`, `generic_leak=False`, and `has_hypothesis=True`

Known validation debt:

The broader legacy `tmp_remote_mim/tests/test_studio_training_chat.py` direct run still has unrelated failures in training-page wording and chat-shell expectations. Those failures predate this narrow repair and should become a separate validation-harness cleanup objective.

## General Rule Learned

Conversation classification is not enough.

After MIM selects a conversation purpose, the response must still be composed from current context, evidence, uncertainty, and the user's actual prompt. A correct route followed by a canned answer is still a failure.

## Prevention Rule

Do not place long fixed MIM answer paragraphs in production routing or purpose engines.

Allowed:

- schemas
- response modes
- protocol labels
- short structural scaffolds
- safety text

Not allowed:

- exact natural-language answers
- broad phrase triggers that return fixed conclusions
- canned exploratory biographies
- fixed responses that pretend to be current reasoning

## Reuse Trigger

Use this capability whenever:

- two different user prompts receive near-identical MIM answers,
- MIM says it is exploring but does not reason from the actual prompt,
- a route classifier is paired with a fixed answer body,
- MIM's answer sounds fluent but ignores current context.

## Dependent Capabilities

- conversation purpose recognition
- active conversation context
- exploratory reasoning
- evidence-grounded response composition
- TOD bounded source-edit execution

## Capability Confidence

Local focused confidence: medium-high.

System confidence: medium-high, because live MIM service deployment and route probes passed. Full legacy suite cleanup remains a separate validation-harness debt.

## Independent Pass Rate

TOD independent pass: 0/1 for this repair.

Codex escalation pass: 1/1 focused local repair.

## Date Frozen

Not frozen. This is a training artifact and apprenticeship record until TOD independently repeats the capability on an unseen analogous hardcoded-answer case.
