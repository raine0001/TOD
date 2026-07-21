# TOD Organizational Maintenance Cycle V1

## Mission

TOD must maintain the organization, not just execute isolated repairs. This cycle updates the measurement system, the Auditor truth surface, enterprise planning, AgentMIM planning, and the authority model that keeps Dave, MIM, TOD, Codex, and Auditor aligned.

## Codex Role

`advisory_and_validation_only`

Codex may package the cycle, define measurement contracts, validate evidence, and identify missing proof. TOD owns execution. Codex-authored implementation does not count as TOD progress.

## Priority Order

1. Scorecard updates
2. Auditor update
3. Enterprise build review
4. AgentMIM roadmap review
5. Organizational Constitution V1 freeze

## Scorecard Update Requirements

The old scorecards measured activity, movement, and specific behavior suites. The new scorecards must also measure whether the organization is becoming more capable.

### MIM Scorecard Metrics

- Executive Recommendation Quality
- Conversation Act Recognition
- Objective Stewardship
- Coaching Assimilation
- Reflection Quality
- Product Mastery
- Audience Adaptation
- Referential Continuity
- Active Objective Continuity
- Evidence Source Selection

### TOD Scorecard Metrics

- Independent Execution
- Recovery Quality
- Evidence Integrity
- Blocker Honesty
- Replan Quality
- Bounded Slice Selection
- Execution Ownership
- Borrowed Capability Reduction
- Autonomous Recovery Rate

### Required Borrowed Capability Ratio

TOD scorecards must report borrowed capability ratio as a trend, not only as a yes/no state.

Required shape:

```json
{
  "borrowed_capability_ratio": {
    "current": {
      "borrowed_count": 0,
      "independent_count": 0,
      "retired_count": 0,
      "borrowed_percent": 0,
      "independent_percent": 0
    },
    "previous": null,
    "trend": "baseline|improving|flat|regressing|unknown"
  }
}
```

## Auditor Update Requirements

`/studio/auditor` should become the operational truth center.

The Auditor should answer four questions:

1. Can I trust the system?
2. What is actually true?
3. What is MIM claiming?
4. Why should I believe it?

The Auditor must separate:

- verified behavior
- claims awaiting verification
- regressions
- operator-needed items
- live audit queue
- failures worth investigating
- trust delta
- skeptical review

The default Auditor page should not be a normal MIM chat. It should be evidence-first. Conversation belongs behind "Ask the Auditor" or the Behavior Lab.

## Enterprise Review Requirements

Enterprise should become a long-term product mastery objective for MIM.

Review must distinguish:

- implemented tenant foundation
- implemented login/setup shell
- user-visible Enterprise home
- missing first-login setup wizard pieces
- clean-slate tenant boundary
- next product slices
- MIM's current product understanding

## AgentMIM Review Requirements

AgentMIM should have its own roadmap review because it is outward-facing and user-impacting.

Review must include:

- forum image generation
- commission upload and audit intelligence
- referring/sub-rep reports
- client identity merge
- quote workflow
- MIM side-assistant timeouts
- customer-facing support/ticket flow

## Organizational Constitution V1

Freeze the operating model:

Dave -> MIM -> TOD -> Codex -> Auditor

Define:

- who can originate strategy
- who owns interpretation
- who owns execution
- who can validate claims
- who can patch production
- what counts as borrowed capability
- when escalation is allowed
- what must be visible to Dave

## Acceptance

This cycle is complete only when:

- `runtime_remote_training/MIM_TOD_ORGANIZATIONAL_MAINTENANCE_SCORECARD.latest.json` exists.
- The scorecard includes all MIM cognitive metrics listed above.
- The scorecard includes all TOD execution-quality metrics listed above.
- Borrowed capability ratio is calculated from the apprenticeship registry.
- Unknown/unmeasured metrics are marked as instrumentation-required instead of scored.
- `docs/training/MIM_TOD_ORGANIZATIONAL_CONSTITUTION_V1.md` exists.
- Enterprise and AgentMIM roadmap review sections are represented in the scorecard.
- The Auditor rebuild is represented as a next implementation objective, not falsely marked complete.
- Validation proves the scorecard builder runs.
- No product route hardcodes are added.

## Current Training Rule

If TOD cannot execute a step, the blocker becomes the training objective. Back up one rung, prove the smaller capability, then resume this cycle.
