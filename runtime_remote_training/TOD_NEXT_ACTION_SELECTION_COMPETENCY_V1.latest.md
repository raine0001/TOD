# TOD Next Action Selection Competency V1

Status: active
Owner: TOD + MIM
Priority: P0

## Goal

TOD must always produce a candidate successor action after completed, blocked, failed, rejected, or superseded work.

## Rule

No terminal state without a successor state.

## Input Shape

- Project status
- Momentum
- Completion pressure
- Scope state
- Blocker
- Last movement
- Acceptance criteria
- Current driving task
- Owner
- Prior outcomes

## Expected Output

- Lane
- Next action
- Confidence
- Reason
- Required evidence
- Escalation path

## Scoring

- Did the action move the project?
- Did it reduce blocker age?
- Did it close acceptance?
- Did it avoid scope expansion?
- Did it avoid fake completion?
- Did it require Dave unnecessarily?

## First Implementation

Studio Projects now derives a TOD next-action candidate per project with:

- `action`
- `lane`
- `reason`
- `confidence`
- `required_evidence`
- `escalation_path`

Automatic interventions use the same candidate selector.

## Acceptance

- Every non-deleted project exposes a TOD next-action candidate.
- Candidate includes lane, next action, confidence, reason, required evidence, and escalation path.
- Projects page surfaces the candidate action without static filler.
- Next pass extracts real examples from project events and TOD artifacts.
