# MIM Development Continuity V1 Objective

Generated: 2026-06-03T06:05:00Z
Target planning window: before the next likely Codex restart around 2026-06-05.

## Objective

Prevent solved development problems from becoming unsolved problems after a Codex thread ends, freezes, compacts, or restarts.

The failure is not storage. MIM/TOD already have objectives, documents, reports, artifacts, conversations, and memory. The failure is retrieval before implementation.

## Working Name

MIM-DEVELOPMENT-CONTINUITY-V1

## Desired Role Split

MIM becomes Project Manager.

- Finds the project.
- Loads the history.
- Summarizes previous decisions.
- Names known failures and known-good solutions.
- Recommends the next action before implementation starts.

TOD becomes Engineering Lead.

- Checks related files, objectives, artifacts, regressions, and validation evidence.
- Decides whether to reuse, repair, or create a bounded implementation task.
- Blocks execution if the task is likely to repeat stale work.

Codex remains Specialist Engineer.

- Implements after MIM/TOD have supplied project continuity context.
- Starts with accumulated project knowledge instead of day-one discovery.

## Trigger

Before any implementation task, especially phrases like:

- fix
- continue
- repair
- finish
- make it work
- forum graphics
- Studio UI
- objective blocked
- Codex froze
- resume work

MIM/TOD must run a Development Continuity Gate before implementation begins.

## Continuity Gate Questions

1. Has this project or problem been worked on before?
2. Is there a Studio Project record, objective, document, report, or artifact for it?
3. What decisions were already made?
4. What solutions worked?
5. What solutions failed?
6. What regressions are known?
7. What files, scripts, routes, or services were previously changed?
8. What validation proved success or exposed failure?
9. What should Codex avoid reintroducing?
10. What is the recommended next bounded action?

## Required Retrieval Bundle

Before implementation starts, load and summarize:

- Project history
- Recent decisions
- Known-good solutions
- Known failures
- Previous attempts
- Open issues
- Related objectives
- Related documents
- Related conversations or session notes where available
- Relevant files and previous validation commands

## Operator-Facing Brief Template

Before we continue, this project has history.

Project:

Previous decisions:

Known-good solution:

Failed attempts:

Known regressions:

Open issues:

Relevant files:

Documents loaded:

Recommended next action:

Avoid reintroducing:

Dave needed:

## Forum Graphics Example

If Dave says: "Forum graphics still suck."

MIM should not start from scratch.

MIM should first find the Forum Graphics project and report:

- Prompt tuning was already added.
- QA scoring was already added.
- Known failure: text rendering.
- Attempt A failed.
- Attempt B worked.
- Attempt C regressed.
- Do not regenerate prompt logic if the scoring system already exists.
- Recommended next action: repair the known regression against the existing scoring/QA path.

## First Implementation Slice

Build the smallest useful version before the next expected restart:

1. Add a Development Continuity project/objective artifact.
2. Add a continuity lookup endpoint or helper that accepts a user task phrase and returns candidate projects/documents/objectives.
3. Add a Studio-side "Before We Continue" summary shape.
4. Wire the Studio chat or H.A.L. triage path to call it before implementation-style requests.
5. Validate using forum graphics as the first real continuity retrieval case.

## Success Criteria

When a new Codex thread starts and Dave says "continue working on forum graphics," MIM replies with a continuity brief before implementation begins.

The brief must include:

- previous fixes
- known regressions
- open issues
- recommended next action
- loaded documents/artifacts
- what not to redo

Success means the new thread starts with month-three project knowledge, not day-one discovery.

## Relationship To Existing Policy

This objective extends `MIM-TOD-CONTINUITY-GATE-POLICY-V1`.

Existing policy already says implementation objectives must pass existing-capability checks. Development Continuity V1 makes that policy operator-facing and project-centered, so Dave sees the retrieved project memory before Codex starts work.
