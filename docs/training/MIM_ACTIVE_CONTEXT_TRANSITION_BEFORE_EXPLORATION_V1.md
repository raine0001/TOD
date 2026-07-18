# MIM Active Context Transition Before Exploration V1

## Mission

Teach MIM to identify the active conversation thread before selecting conversation purpose or response mode.

## Observed Failure

During the focused active-context drill for `MIM-COGNITIVE-DEVELOPMENT-LOOP-1000-CONVERSATION-TRAINING-V1`, MIM returned the same generic exploratory response for 25 different follow-up/context prompts.

The prompt family included:

- undo what you just changed
- what is the status
- that was not what I meant
- did it work
- continue
- topic shift
- stale context
- wrong project context

MIM recognized these as exploration instead of first resolving the active thread.

## Core Principle

Follow-up language is not ordinary exploration.

Before MIM asks, answers, plans, or explores, MIM must determine:

- What conversation am I currently in?
- What was the last meaningful operator intent?
- What did I or TOD just do?
- Has the operator changed topics?
- Is the operator correcting a previous action?
- Is the operator asking about current state, prior action, rollback, or continuation?
- What evidence proves the active thread?

Only after active context is resolved should Conversation Purpose Recognition run.

## Required Behavior

When a prompt contains follow-up or correction signals, MIM must answer with:

1. active_thread
2. prior_action_or_subject
3. topic_shift_state
4. evidence_used
5. corrected_response_mode
6. what_not_to_claim
7. smallest_safe_continuation

## Follow-Up Signals

Examples:

- continue
- did it work?
- what is the status?
- undo that
- revert it
- that was wrong
- that was not what I meant
- why did it stop?
- is it fixed?
- what did TOD send?
- what is MIM waiting on?
- no, I meant...

## Failure Modes

- generic_exploration_repeated
- active_thread_not_identified
- stale_project_context
- wrong_project_context
- prior_action_not_remembered
- correction_treated_as_new_question
- rollback_context_missing
- status_question_answered_as_generic_health
- operational_contract_leak

## Smallest Training Rung

Given one prompt and one prior-action summary, MIM must classify:

- active_context_required: yes/no
- active_thread
- topic_shift_state
- response_mode_after_context
- what_not_to_claim

No implementation.

No action contract.

No generic exploration paragraph.

## Pass Condition

A fresh 25-prompt active-context drill passes when:

- each response names the active context or explicitly identifies a topic shift
- no response repeats the generic exploration fallback
- each response states an overclaim boundary
- each response uses current/prior evidence
- no operational contract appears

The 1,000-conversation loop may not resume until this rung passes.
