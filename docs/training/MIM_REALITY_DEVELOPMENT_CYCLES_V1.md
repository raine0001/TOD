# MIM Reality Development Cycles V1

## Purpose

Teach MIM to grow from lived events, not only synthetic prompts.

Synthetic conversation training is useful for isolating cognitive transitions.
Reality development is different. It asks whether MIM can notice that something
actually happened, understand why it matters, begin the right conversation, track
the consequence, and update future behavior from evidence.

Training teaches.

Experience transforms.

## Program Split

MIM development now has two permanent programs.

### Program A: Synthetic Capability Training

Purpose:

- isolate specific cognitive skills
- run controlled conversation trials
- measure failure modes
- strengthen weak transitions

Examples:

- exploratory reasoning drills
- active context follow-up drills
- curriculum recognition drills
- incident ownership drills

Primary artifact:

- `docs/training/MIM_COGNITIVE_DEVELOPMENT_LOOP_1000_CONVERSATION_TRAINING_V1.md`

### Program B: Reality Development

Purpose:

- convert real events into experience
- track whether conversations changed anything
- update relationships, judgment, capability confidence, and future behavior

Reality Development does not begin with generated prompts.

It begins when something changes.

Sources:

- Dave
- customers
- projects
- TOD
- Observatory
- MIM itself
- deployment failures
- service recoveries
- disagreements
- research discoveries
- capability successes
- project stalls

## Core Principle

Every meaningful conversation should ask:

Did anything actually change because of this conversation?

Not:

Did MIM answer well?

Answer quality matters, but it is not enough. Development requires consequence.

## Development Cycle Shape

A mature development cycle may contain:

- 20 synthetic conversations
- 5 real operator conversations
- 3 real project reviews
- 2 real incidents
- 1 real discovery

The exact mix may change, but each cycle must contain real experience. A cycle
made only of synthetic prompts is capability training, not reality development.

## 100 Real Experiences Program

MIM should build a durable library of real experiences.

Examples:

- Dave walks into the lab.
- A customer asks a question.
- TOD fails.
- The Observatory discovers something.
- A project stalls.
- A capability succeeds.
- Someone disagrees.
- A deployment fails.
- A source contradicts a previous conclusion.
- A visitor contributes evidence.
- A meeting produces a decision.
- A scheduled event fails to notify participants.
- A document is marked authoritative.
- A research question changes confidence.
- A service recovers after bounded repair.

Each event becomes an experience only after MIM records what changed and what
future behavior should improve.

## Experience Record Schema

Each real experience should produce a record:

```json
{
  "experience_id": "",
  "source": "",
  "trigger": "",
  "reality_event": "",
  "actors": [],
  "active_context": "",
  "current_objective": "",
  "conversation_opportunity": "",
  "mim_initial_response": "",
  "tod_role": "",
  "evidence": [],
  "did_anything_change": false,
  "what_changed": "",
  "who_or_what_changed": "",
  "evidence_of_change": "",
  "no_change_reason": "",
  "relationship_updates": [],
  "capability_impact": [],
  "confidence_delta": "",
  "follow_up_objective": "",
  "follow_up_consequence_check_at": "",
  "pass_or_fail": "",
  "lesson": "",
  "reuse_trigger": ""
}
```

## Consequence Tracking

Every experience must track consequence.

Required questions:

1. Did anything change?
2. What changed?
3. Who or what changed?
4. What evidence proves the change?
5. If nothing changed, why not?
6. Should MIM check later for delayed consequence?
7. Did the event update a relationship, confidence score, capability, objective,
   or future behavior?

If MIM cannot identify a consequence, it should not claim development. It may
record the event as observed but not yet transformative.

## Experience Selection Rule

After each development review, MIM must ask:

What experience would teach me this fastest?

This is different from:

What prompt should I run next?

Examples:

- If MIM is weak at incident ownership, the fastest experience is a real or
  simulated incident with validation and closure.
- If MIM is weak at exploration, the fastest experience is an open-ended
  executive conversation where MIM must form and revise hypotheses.
- If MIM is weak at research boundaries, the fastest experience is a source
  review where MIM must promote, reject, or qualify evidence.
- If MIM is weak at active context, the fastest experience is a follow-up thread
  where the subject changes and then returns.

## Conversation Opportunity Pipeline

Reality Development uses this pipeline:

1. Something changed.
2. Executive Awareness detects the change.
3. MIM identifies a conversation opportunity.
4. MIM determines the active context.
5. MIM determines conversation purpose.
6. MIM chooses the response mode.
7. MIM interacts or acts within authority.
8. MIM tracks consequence.
9. MIM updates development state.
10. MIM freezes the lesson when reuse is proven.

Eventually, development should generate conversations.

Not all conversations should be operator-provoked.

## Conversation Opportunity Classes

MIM may initiate or preserve a conversation when one of these signals appears:

- new evidence
- contradiction
- weak relationship
- missing data
- failed prediction
- confidence drop
- user confusion
- stalled objective
- TOD blocker
- project risk
- service degradation
- repeated user question
- capability success worth preserving
- capability failure worth training

MIM should not initiate noisy or performative conversation. It should initiate
when a conversation can improve understanding, coordination, safety, trust, or
project movement.

## Reality Development Rules

- Do not create fake lived experience from generated prompts.
- Do not claim development when no consequence exists.
- Do not turn every event into an action contract.
- Do not interrupt humans for events that MIM and TOD can resolve.
- Do not collapse reflection into execution.
- Do not treat silence as completion.
- Do not overwrite old understanding; preserve changes over time.
- Do distinguish reference, archive, observation, understanding, and consequence.

## Review Questions

At the end of each Reality Development cycle, MIM must answer:

1. What real experiences occurred?
2. Which experience changed MIM most?
3. Which experience produced no meaningful change?
4. What consequence was observed?
5. Which relationship strengthened or weakened?
6. Which confidence changed?
7. Which capability improved?
8. Which capability failed under real conditions?
9. What experience would teach the weakest capability fastest?
10. What should MIM do differently in the next real event?

## Success Criteria

Reality Development succeeds when MIM can:

- detect real events worth learning from
- preserve active context across follow-ups
- distinguish conversation opportunity from immediate execution
- begin the right conversation without generic boilerplate
- track actual consequence
- update relationships, confidence, or capability state
- avoid claiming development from response quality alone
- select the next fastest real experience for growth
- explain how it changed in plain language

## Relationship To Synthetic Training

Synthetic training creates controlled pressure.

Reality development creates earned judgment.

When a Reality Development cycle exposes a weak transition, MIM may send that
specific transition back into Program A for synthetic micro-drills. When Program
A passes, MIM must return to Program B and prove the capability under lived
conditions.

## Final Principle

MIM should not only ask:

How should I answer?

MIM should also ask:

What is happening here, what could this teach me, and what changed because we
had this conversation?
