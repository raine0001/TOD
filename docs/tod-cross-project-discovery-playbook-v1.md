# TOD Cross-Project Discovery Playbook v1

## Goal

Teach TOD how to perform the kind of ecosystem discovery that produced the recent MIM application integration review.

This playbook is for discovery and synthesis, not implementation.

Primary rule:

- Do not merge projects conceptually just because they all relate to MIM.
- Treat each repository as a distinct capability surface.
- Produce a bounded integration direction, not an unbounded idea list.

## When To Use This Playbook

Use this playbook when the request is any of the following:

- review multiple related projects as one ecosystem
- identify which apps already contain important MIM capability fragments
- determine whether TOD and MIM should integrate directly into those apps
- recommend an integration order
- prepare the input for a shared integration contract

Do not use this playbook when the task is:

- a single-repo bugfix
- a migration from one technology to another
- a deep implementation plan for a single codebase
- a broad brainstorming session without real repository evidence

## Inputs

Required inputs:

- the list of projects to review
- the actual on-disk paths for those projects
- TOD project library and registry context when available

Helpful inputs:

- existing `TOD.md` files inside reviewed repos
- any prior architecture notes in `docs/`
- explicit user priorities such as `mobile continuity`, `real-world interaction edge`, or `business execution`

## Output Standard

The discovery result must produce all of the following:

1. ecosystem layer map
2. per-project capability summary
3. proven current integration surfaces
4. answer to: can this improve MIM?
5. answer to: can this benefit from direct TOD/MIM integration?
6. priority order for integration
7. bounded next deliverable

The result must avoid:

- vague innovation language
- equal weighting of all projects
- recommending a giant merged repo
- jumping directly to a 30/60/90-day implementation plan before contracts are defined

## Discovery Method

### Phase 1: Resolve Real Project Roots

Find the real repositories first.

Required actions:

1. resolve actual directories on disk
2. discard sandbox/project-brief duplicates unless the user explicitly wants them included
3. confirm the primary roots that represent real runnable apps

Expected output:

- one canonical path per reviewed project

Example outcome shape:

```text
mim_wall -> E:\mim_wall
comm_app -> E:\comm_app
coachMIM -> E:\coachMIM
Mimir -> E:\Mimir
mimrobots.com -> E:\MIM Robotics\mimrobots.com
mim_pulz -> E:\mim_pulz
```

### Phase 2: Establish Repo Identity

For each repo, gather only the minimum evidence needed to classify it correctly.

Read at least:

1. top-level directory listing
2. `README.md` if present
3. `TOD.md` if present
4. one or two entrypoint files
5. one or two files that expose integrations, APIs, orchestration, or runtime state

Capture:

- stack
- runtime model
- main capability
- current external integrations
- state surfaces
- whether the app already contains MIM-oriented concepts

### Phase 3: Split Capability Layers

Do not summarize by repo only. Also classify by ecosystem role.

Use these layer questions:

1. Is this a real-world interaction edge?
2. Is this a business execution engine?
3. Is this a structured memory or longitudinal user-state system?
4. Is this a policy, explainability, or reasoning engine?
5. Is this a media, search, or production surface?
6. Is this a publish or presentation surface?

If a repo maps strongly to one layer, say so directly.

This is the step that turns scattered apps into an ecosystem rather than a list.

### Phase 4: Separate What Exists From What Is Conceptual

Every recommendation must be labeled as one of:

- exists today
- partially present today
- not present and must be built

Evidence must come from code or repo docs, not wishful synthesis.

If an integration point is already present, identify the exact surface:

- route
- service
- store
- queue
- provider factory
- task runner
- file output
- database model

### Phase 5: Ask Two Hard Questions Per Project

For each project, answer both questions separately:

1. Can this project materially improve MIM development or capabilities?
2. Would this project materially benefit from direct MIM/TOD integration?

Do not assume the answer is symmetric.

Example:

- a website may benefit from MIM content publication, but may not materially improve MIM itself
- a routing engine may strongly improve MIM, even if it needs only light integration in return

### Phase 6: Prioritize By Leverage, Not Novelty

Rank projects using this order of importance:

1. explainability and policy leverage
2. real-world interaction leverage
3. execution leverage
4. long-memory leverage
5. media and search leverage
6. presentation leverage

This prevents TOD from overvaluing attractive surfaces that are strategically secondary.

### Phase 7: End With A Bounded Next Deliverable

Do not end with a broad roadmap.

The default next deliverable after discovery should be:

- one shared contract artifact
- one first adapter only

Preferred contract contents:

1. canonical identity model
2. canonical event envelope
3. canonical decision and audit envelope
4. capability registry schema
5. adapter contract template for one app

Preferred first adapter selection rule:

- choose the app with the highest real-world payoff and strongest continuity value

For the current MIM ecosystem, that means `mim_wall` is the default first adapter after contract definition.

## Evidence Threshold

TOD should not claim an ecosystem-level conclusion unless it has evidence from at least:

1. one real root path per project
2. one README or equivalent doc per project when available
3. one runtime or entrypoint file per project
4. one concrete integration surface per project when available

If this threshold is not met, TOD must downgrade the output to `preliminary review`.

## Recommended Execution Pattern

Use this order:

1. locate project roots
2. read top-level structure
3. read docs and entry points
4. parallelize deeper repo exploration when multiple projects are involved
5. validate the subagent findings with direct file reads
6. synthesize only after evidence is grounded in actual files

Important:

- subagents are acceleration tools, not the final authority
- direct file reads should confirm the major claims used in the final recommendation

## Output Template

Use this structure for the final discovery result:

### 1. Ecosystem Reading

- state whether the reviewed apps form a real ecosystem or just a loose collection
- name the capability layers discovered

### 2. Per-Project Role

For each project, summarize:

- what it is
- what it already does well
- whether it improves MIM
- whether MIM/TOD would improve it

### 3. Architecture Direction

- explain whether the right answer is merge, federation, or contracts
- identify the orchestration spine and the intelligence center separately

### 4. Priority Order

- rank projects for integration
- justify the ranking in one sentence each

### 5. Bounded Next Deliverable

- define the one contract artifact to write next
- define the one first adapter to build next

## Current Reference Reading

The discovery method above matches the review style that identified the current MIM ecosystem as:

- `mim_wall` as the real-world communications edge
- `comm_app` as business execution
- `coachMIM` as structured long-memory and user-state
- `mim_pulz` as policy and explainability
- `Mimir` as media, search, and production patterns
- `mimrobots.com` as publish and presentation surface

That result should be treated as a reference pattern for future ecosystem reviews, not as a one-off lucky summary.

## Promotion Rule

Before TOD starts implementation planning from a discovery result, require one follow-up artifact:

- `docs/shared-integration-contract-v1.md`

That contract should be completed before TOD or Codex begins building multiple adapters, so the ecosystem does not fragment into incompatible seams.
