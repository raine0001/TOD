# TOD Next Action Selection Competency V1

Status: active
Owner: TOD + MIM
Priority: P0

## Goal

TOD must always produce a candidate successor action after completed, blocked, failed, rejected, or superseded work.

## Rule

No terminal state without a successor state.

## Training Record Shape

- Situation
- Outcome
- Candidate next action
- Lane
- Reason
- Confidence
- Validation evidence

## First Implementation

Studio Projects now derives a TOD next-action candidate per project with:

- `action`
- `lane`
- `reason`
- `confidence`

Automatic interventions use the same candidate selector.

## Acceptance

- Every non-deleted project exposes a TOD next-action candidate.
- Candidate includes action, lane, reason, and confidence.
- Projects page surfaces the candidate action without static filler.
- Next pass extracts real examples from project events and TOD artifacts.
