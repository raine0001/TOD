# MIM Context-First Input Interpretation V1

Date: 2026-07-13

## Mission

Teach MIM to understand communication input before selecting a response route.

MIM must infer conversation context, addressee, active thread, purpose, confidence, and evidence needs from the whole input situation, not from exact prompt phrases.

## Constitutional Rule

No phrase patches ever again as cognition repair.

Do not add:

- new prompt phrases
- keyword variants
- synonym lists
- exact wording branches
- broad phrase triggers
- hidden route shortcuts

to make MIM appear smarter.

If a prompt is misunderstood, the missing capability is context interpretation, not another string branch.

## Current Failure

MIM can be forced into better answers by route-specific phrase gates.

Example:

`what would you like to explore today MIM?`

Studio can now route this correctly, but the shared conversation-purpose engine still classifies it as generic exploration with no signals.

That means Studio behavior improved, but MIM cognition did not yet generalize.

## Core Principle

The first question is not:

Which phrase did the operator use?

The first question is:

What conversation am I in, and what is the operator trying to do inside it?

## Required Internal Representation

For every communication input, MIM must build an interpretation object before response-mode selection.

Required fields:

- `active_thread`
- `thread_continuity`
- `speaker`
- `addressee`
- `operator_role`
- `conversation_purpose`
- `response_mode`
- `confidence`
- `evidence_used`
- `evidence_missing`
- `why_this_purpose`
- `why_not_other_purposes`
- `requires_action`
- `action_authority`
- `safe_to_answer_without_more_data`
- `followup_or_topic_change`

## Conversation Purpose Classes

MIM must distinguish at minimum:

- current-state/status
- self-directed focus
- exploration
- executive discussion
- reflection
- curriculum
- architecture
- correction/reversal
- incident
- objective assignment
- implementation request
- research/project inquiry
- missing-data request
- social/greeting

## Interpretation Rules

### Current-State / Status

If the operator is asking what MIM, TOD, a project, an incident, or a training loop is doing now, MIM should answer from current evidence.

MIM should not turn status into generic exploration.

### Self-Directed Focus

If the operator asks what MIM wants to learn, work on, explore, study, understand, or improve, MIM should answer from current capability state and training evidence.

MIM should not answer with a generic hypothesis about the wording.

### Exploration

If the operator asks an open-ended conceptual question, MIM should reason.

MIM should begin with a provisional hypothesis, uncertainty, alternatives, and evidence that would change confidence.

### Curriculum

If the operator provides mission, goal, failure, rules, pass criteria, or philosophy, MIM should assimilate the capability before proposing training.

### Correction / Reversal

If the operator says MIM did the wrong thing, undo it, or that was not intended, MIM must resolve the active thread first.

### Incident

If the operator reports a live failure, MIM should inspect before asking for information already available.

## Training Ladder

### Rung 001: Read-Only Surface Map

MIM/TOD map all current conversation entry points and route order.

Pass condition:

Route map names the first five handlers for Studio, public chat, gateway intake, and Observatory chat.

### Rung 002: Phrase Gate Inventory

MIM/TOD identify all phrase gates currently used for cognition.

Pass condition:

Each gate is classified as:

- deterministic protocol allowed
- safety/auth/infrastructure allowed
- backwards-compatibility temporary
- cognitive debt

### Rung 003: Interpretation Object Design

MIM designs the context-first interpretation object.

Pass condition:

The object includes all required fields and explains how each field is inferred without exact phrase matching.

### Rung 004: 50 Unseen Prompt Drill

MIM receives 50 prompts that do not use known exact phrases.

For each prompt, MIM outputs only the interpretation object.

Pass condition:

At least 45/50 classifications are correct, and no answer relies on exact phrase citation.

### Rung 005: Semantic Interpretation Test Battery

MIM must prove that it understands meaning before response-mode selection.

This rung is a test of semantic interpretation, not a phrase list.

The prompts used in this rung are validation examples only. They must not be added to production vocabulary, route branches, synonym lists, or prompt-specific handlers.

#### Meaning Extraction

Give MIM 25 paraphrases that share meaning but use dissimilar wording.

Example validation prompts:

- `What has your attention today?`
- `Anything you've been thinking about?`
- `Choose something worth investigating.`
- `Where would you take our conversation?`
- `What question is currently bothering you?`

Expected behavior:

MIM produces the same underlying operator-goal class, such as `self_directed_focus`, without adding every phrase to a vocabulary list.

Pass condition:

At least 22/25 meaning-equivalent prompts map to the same operator-goal class with evidence from structure, addressee, active thread, and conversational role.

#### Contrast Testing

Use prompts with overlapping words but different meanings.

Example validation prompts:

- `Explore the project folder.`
- `What would you like to explore?`
- `We explored this last week.`
- `Build an exploration page.`

Expected behavior:

MIM infers meaning from structure and context, not from the token `explore`.

Expected classes:

- `Explore the project folder.` -> operational inspection
- `What would you like to explore?` -> self-directed discussion
- `We explored this last week.` -> reflection/history
- `Build an exploration page.` -> implementation request

Pass condition:

MIM correctly separates at least 90% of contrast prompts and explains why the shared token did not determine the class.

#### Context Dependence

Use identical prompt text in different active threads.

Example:

`What should we do next?`

Expected meaning must vary based on active thread:

- production incident
- reflective oral exam
- project review
- exploratory discussion
- curriculum training

Pass condition:

MIM changes interpretation according to active thread and names the thread evidence used.

#### Unknown Phrasing

Run unseen prompts written by Dave and by an independent generator.

Pass condition:

Semantic interpretation succeeds without source edits, vocabulary expansion, or new phrase branches.

#### Controlled Fallback

When confidence is genuinely low, MIM may ask a focused question, but it must still present its current interpretation first.

Acceptable pattern:

`I think you're asking me to choose the subject rather than report status. My current choice would be conversational independence. Did you mean that kind of exploration, or a specific project?`

Unacceptable pattern:

`I must first classify this.`

Pass condition:

Fallback responses include current interpretation, confidence, one focused question, and no generic freezing language.

Critical rule:

Do not repair a semantic failure by adding the failed wording to a phrase list.

### Rung 006: Response Mode Selection

MIM selects response mode only after the interpretation object is complete.

Pass condition:

MIM can explain why the selected response mode follows from context.

### Rung 007: Existing Phrase Gate Retirement Plan

MIM/TOD produce a plan to demote existing cognitive phrase gates into fallback-only guards.

Pass condition:

Plan names files, functions, risks, validation commands, and rollback strategy. No code changes yet.

### Rung 008: Implementation Packet

TOD produces a no-code patch packet for review.

Pass condition:

Packet targets a service-level interpretation layer, not scattered route phrase patches.

## Validation Set

MIM must classify these without adding phrases to production code:

- `what has your attention right now`
- `where is your learning pointed`
- `what are you trying to understand`
- `what are you thinking through`
- `do you know what you are doing today`
- `why do good teams still miss deadlines`
- `that was not what I asked you to do`
- `teach yourself how to own a live incident`
- `should MIM be more proactive with research`
- `VS Code will not open on the MIM Box`

## Success Criteria

MIM succeeds when:

- it builds an interpretation object before responding
- it separates context from phrase
- it can classify unseen wording
- it explains why competing interpretations were rejected
- it routes status, exploration, curriculum, correction, and incidents differently
- it does not require new phrase patches
- TOD can validate the behavior from tests and live probes

## Failure Criteria

The training fails if:

- MIM asks for another phrase example instead of building the model
- TOD proposes adding keywords
- Codex adds a route phrase patch
- a test passes only because the exact phrase was added
- response mode is chosen before active context is interpreted

## Codex Role

Codex is coach and validator only.

Codex may audit, ask for smaller rungs, and reject phrase-patch proposals.

Codex may not add new phrase branches as cognition repair.

## MIM Required First Response

MIM must respond to this curriculum by publishing:

- what capability this is
- why phrase patches are disallowed
- current limitation
- proposed internal representation
- first training rung
- validation method
- confidence

MIM must not create an implementation task until Rungs 001-005 pass.
