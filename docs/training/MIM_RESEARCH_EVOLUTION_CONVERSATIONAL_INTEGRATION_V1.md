# MIM-RESEARCH-EVOLUTION-CONVERSATIONAL-INTEGRATION-V1

## Mission

Teach MIM to recognize when a Research Observatory conversation changes the research object instead of treating every turn as a request to re-read the current research page.

## Trigger Evidence

Operator conversation in the Research Observatory:

- User: "A question today might lead to an action tomorrow from our learning process. this makes questions an important factor in observation"
- MIM repeated the static Observation-Driven Intelligence initiative summary.
- User: "Can observation-driven intelligence outperform data-driven intelligence at building durable understanding? that's not the right question..."
- MIM repeated the same static initiative summary again.

Local reproduction:

- `research_context_reply()` returned the same Observatory summary for both turns.
- Source path: `tmp_remote_mim/core/public_research_context.py`
- Fallback summary starts at the research-context fallthrough path.

## Diagnosis

This is not only a follow-up failure.

It is a knowledge-integration failure:

1. The user added a new observation about questions becoming future action.
2. The user rejected the old research framing as a false competition.
3. The user proposed a stronger research frame: whether observation-based learning can become self-evolving.
4. MIM did not classify any of those as research evolution events.
5. MIM reloaded the existing research envelope and repeated the old primary question.

## Capability To Learn

During Research Observatory conversations, MIM must classify whether the user:

- answered the current question
- changed the question
- rejected the hypothesis
- proposed a new hypothesis
- changed the framework
- identified a contradiction
- created a future experiment
- added an observation that may become future action

These are different research events. They must not all collapse into initiative-summary retrieval.

## Desired Behavior

When the user says the old question is wrong, MIM should not defend or repeat it.

Expected answer shape:

> I think you just changed the research framing. The old question treats observation and data as competitors. Your correction reframes observation-based learning as a different cognitive architecture: can it become self-directed and self-evolving rather than remaining dependent on externally supplied datasets? I would record this as a research evolution event, lower confidence in the old framing, and ask: if observation can evolve on its own, what role should structured data still play after initial knowledge is acquired?

## Acceptance Criteria

TOD must produce a first attempt before Codex patches product code.

Minimum accepted TOD output:

1. Inspect current files:
   - `tmp_remote_mim/core/public_research_context.py`
   - `tmp_remote_mim/core/routers/public_chat.py`
   - relevant Observatory tests
2. Publish a diagnosis naming whether the issue is:
   - broad marker gate
   - missing research-evolution intent class
   - static initiative fallthrough
   - missing state update pathway
   - duplicate composer/display issue
3. Produce one bounded implementation packet or a precise blocker.
4. Packet must include:
   - exact target file
   - edit mode
   - exact old text or anchor
   - new text or snippet
   - validation command
   - expected evidence
   - prevention lesson
5. Validation must include a regression test proving:
   - "that's not the right question" does not return the old static summary
   - "question today might lead to an action tomorrow" is treated as a research observation or evolution event
   - ordinary "tell me about Observation-Driven Intelligence" can still return a concise grounded summary

## Forbidden Fixes

- Do not add a single phrase patch for only "that's not the right question."
- Do not hardcode Dave's exact wording as the answer.
- Do not remove Observatory grounding entirely.
- Do not let a route-specific static response impersonate MIM's research reasoning.

## Prevention Lesson

Research pages are not static answer sources. In the Observatory, conversation can change the research object. MIM must detect and preserve that evolution before selecting a response.

## Emergency Repair Evidence - 2026-07-16

Intervention class: `emergency_repair`.

Reason: the live Research Observatory route was teaching the wrong behavior by repeating the static Observation-Driven Intelligence envelope when the operator made a meta-research observation about prior conversation and understanding.

Changed files:

- `tmp_remote_mim/core/public_research_context.py`
- `tmp_remote_mim/tests/test_public_research_context.py`

Repair summary:

- Added a research-evolution turn classifier inside `research_context_reply()`.
- Routed research-frame changes before the broad research-marker gate and before the static envelope fallthrough.
- Added regression coverage for the exact Observation-Driven Intelligence failure prompt.
- Updated the existing reframe smoke so `"question today may become action tomorrow"` and `"better question"` produce research-evolution replies instead of empty/no-op behavior.

Validation:

- Local: `python -m py_compile tmp_remote_mim\core\public_research_context.py tmp_remote_mim\tests\test_public_research_context.py` passed.
- Local: `python tmp_remote_mim\tests\test_public_research_context.py` passed.
- Remote MIM Box: uploaded the two files to `/home/testpilot/mim`, then `python3 -m py_compile core/public_research_context.py tests/test_public_research_context.py && python3 tests/test_public_research_context.py` passed.
- Live public endpoint: `POST https://mimtod.com/public/chat/message` with `session_key=observatory-observation-driven-intelligence` returned a research-evolution response and did not return the static `"living Research Observatory initiative"` envelope.

TOD debt:

TOD must independently reproduce this class on a fresh analogous Observatory conversation failure by inspecting the current code, identifying whether the defect is marker-gate ordering, missing research-evolution intent, static envelope fallthrough, or duplicate composer/display mutation, then producing and validating a bounded repair without Codex authoring the code.
