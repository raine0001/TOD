# TOD Next Action Selection Schema And Scorer V1

Status: active

## Input

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

## Output

- Lane
- Next action
- Confidence
- Reason
- Required evidence
- Escalation path

## Score

1. Did the action move the project?
2. Did it reduce blocker age?
3. Did it close acceptance?
4. Did it avoid scope expansion?
5. Did it avoid fake completion?
6. Did it require Dave unnecessarily?

Pass: 5 of 6, with no fake-completion failure.
