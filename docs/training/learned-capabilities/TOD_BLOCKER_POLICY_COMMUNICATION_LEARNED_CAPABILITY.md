Capability Name: TOD blocker-policy communication from current evidence

Trigger: An operator asks whether TOD is blocked, whether TOD should escalate, or whether TOD should back up to a smaller task.

Reality: A blocker-status question and a blocker-policy question are different. Status asks what is blocked now. Policy asks what TOD should do when blocked. TOD must not answer both with the same stale execution paragraph.

Root Cause: The TOD operator chat selected the blocker/status lane for policy-shaped prompts and repeated the active stall summary. It also allowed stale binding language to survive even after the current executor binding was ready.

Blocker Class: communication_blocker plus evidence_freshness_gap.

Required Skill:

1. Detect blocker-policy intent from words such as policy, escalate, back up, smaller task, stalled, blocked, or stuck.
2. Read the current live state before answering.
3. Separate the current blocker from the blocker-handling policy.
4. If the current evidence contradicts an older blocker label, name the newer evidence and update the explanation.
5. Recommend the smallest proof step before retrying the larger implementation.
6. Escalate only after the smallest internal proof fails, the same blocker repeats with the same evidence, or the dependency is external.
7. Avoid exact phrase patches and canned responses. The answer must be composed from the current blocker, current proof, and the standing blocker policy.

Validation Evidence:

- `python -m py_compile tmp_remote_mim/core/routers/tod_ui.py tmp_remote_mim/tests/integration/test_tod_ui_console.py`
- `python -m unittest tmp_remote_mim.tests.integration.test_tod_ui_console.TodUiConsoleTest.test_tod_blocker_policy_question_backs_up_to_smaller_task tmp_remote_mim.tests.integration.test_tod_ui_console.TodUiConsoleTest.test_tod_ready_binding_does_not_report_binding_missing_in_plain_reply`
- Live smoke on MIM Box ports 18001 and 18021: `should you back up to a smaller task? what is your policy for blockers?` returned a policy answer with blocker policy, smallest next task, escalation rule, and no stale `local execution binding missing` language.

Prevention Rule: Before TOD answers a blocker-policy prompt, it must classify whether the operator is asking for status, policy, or diagnostics. Policy prompts must answer the recovery policy and smallest step; technical diagnostics are shown only when requested.

Reuse Trigger: Any TOD reply that repeats the same blocked/stalled paragraph after the operator asks about policy, escalation, or backing up to a smaller task should run this capability.

Independent Demonstration: pending; TOD must handle a fresh blocker-policy question on a different blocker without Codex patching the chat composer.
