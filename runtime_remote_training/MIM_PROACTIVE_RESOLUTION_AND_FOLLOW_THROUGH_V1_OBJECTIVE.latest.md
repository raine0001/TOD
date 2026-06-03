# MIM Proactive Resolution And Follow-Through V1

Generated: 2026-06-03 1:35 PM America/Los_Angeles

## Objective

No project, objective, blocker, commitment, approval, or required operator action is allowed to silently rot.

Every item must move toward one terminal state:

- Complete
- Superseded
- Cancelled
- Escalated
- Waiting On Dave
- Waiting On External Dependency

## Resolution Hierarchy

MIM should always attempt resolution in this order.

1. MIM self-resolution
2. TOD engineering resolution
3. Codex specialist escalation
4. External dependency tracking
5. Dave decision or approval

Dave is not the default blocker. Dave is the final lane when policy, credentials, business approval, or physical confirmation truly require him.

## Operator Action Contract

When something needs Dave, MIM must include:

- What needs Dave
- Reason
- Choices
- Impact if no action
- Affected project
- Current owner
- Age
- Reminder schedule

Example:

What needs Dave: Approve account manager access to commission totals.

Reason: Rep commission totals are confidential and require owner-level approval.

Choices: approve, reject, delegate.

Impact: Account Manager project remains blocked until access policy is decided.

Reminder schedule: 24h, 72h, 7d.

## Aging Rules

- Day 1: visible in Studio
- Day 3: reminder
- Day 7: escalated
- Day 14: persistent nag
- Day 30: high-priority alert
- Day 60: dashboard red flag

## Studio Follow-Through Surface

Create a Follow Through area showing:

- Needs Dave
- Needs MIM
- Needs TOD
- Needs Codex
- Needs External
- Aging over 30 days

Each row should show item, project, owner, state, age, next action, blocker, resolution lane, reminder due, and open link.

## First Validation Cases

- Lab servo COM5 lock: MIM should disconnect/release in-app serial controls or route the page action before asking Dave.
- Studio reports data request: MIM should classify as data-source failure and route investigation to TOD/Codex with evidence.
- Account Manager project: Dave-needed only for sensitive commission access approval.
- AgentMIM forum graphics: continuity lookup before implementation.
- TOD local PowerShell interruptions: TOD resolution lane before Dave interruption.

## Relationship To Continuity

Development Continuity V1 answers: what did we learn?

Proactive Resolution And Follow-Through V1 answers: what still needs to happen?

Together they prevent solved problems and open commitments from disappearing between Codex sessions.
