# MIM Enterprise Observatory First Real Workflow V1

Owner: MIM

Implementer: TOD

Codex role: coach and validator only

## Goal

Build one complete user-visible Enterprise Observatory workflow.

This slice is not another infrastructure layer. It must demonstrate why Enterprise Observatory exists.

## Selected Workflow

Enterprise Current Work and Blockers:

Enterprise -> Current Work -> Blockers -> Who Owns What -> What's Next -> Executive Summary

This is the smallest real workflow that creates executive value. It tells a user what is happening, what is blocked, who owns it, and what should happen next.

## Required Experience

The Enterprise page should show:

- Enterprise executive summary
- Current work
- Blocked work
- Who owns what
- One recommended next action

Each section must use real current evidence when available. If evidence is unavailable, show an honest empty state that explains what evidence is needed.

## Non-Negotiables

- No placeholder-only sections.
- No fake demo metrics.
- No hardcoded MIM responses.
- No route-specific MIM personality.
- No OpenAI or RunPod dependency.
- No Codex-written implementation packet.
- No whole-file dirty mirror deployment.

## Acceptance Criteria

- A logged-in demo enterprise user can open the workflow.
- The workflow shows current work, blockers, ownership, and next action in one connected view.
- At least one displayed value is backed by a real artifact, database row, or service query.
- Remote compile/import validation passes.
- Live route or API smoke passes.
- TOD publishes implementation evidence.
- APP-TOD-025 proficiency is updated only if TOD actually performs the implementation pattern.

## Product Direction

MIM owns what Enterprise Observatory becomes.

TOD owns one bounded implementation slice at a time.

Codex validates whether the work is real.
