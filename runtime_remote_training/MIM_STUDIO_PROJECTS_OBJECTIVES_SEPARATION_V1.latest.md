# MIM Studio Projects / Objectives Separation V1

## Purpose

MIM Studio separates value-producing work from capability-growth work.

## Projects

Projects are real-world outcomes.

Examples:

- MIM Accounting
- AgentMIM Account Manager
- Carrier MFA Integration
- Forum Graphics
- MIM Wall
- Vacation planning
- Legal research
- Customer portal
- New mobile app

Projects contain:

- Project Inbox candidate state
- Origin story
- Why it matters
- Priority
- Dave needed: yes/no
- Status lane
- Discovery
- Blueprint
- Roadmap
- Milestones
- Tasks
- Tests
- Deployment
- Maintenance
- Evidence
- Outcome tracking

Project test:

- If completing it benefits Dave, a customer, or the company, it is a project.
- If it would still matter if MIM/TOD disappeared tomorrow, it is a project.

## Signal Inbox / Project Inbox

A project does not start only when someone clicks New Project.

A possible project can begin when Dave or a customer says:

- "This thing sucks."
- "I have an idea."
- "Why doesn't this work?"
- "Wouldn't it be cool if..."
- "Can we make this better?"

MIM must not be literal. Many things are complaints, notes, resolved issues, future ideas, or general observations.

Before creating a project candidate, MIM should classify the signal.

Signal classes:

- Ignore: noise, duplicate, already resolved, or no meaningful future value.
- Observation: useful context for later, but not actionable now.
- Parked idea: interesting but not urgent or not enough evidence yet.
- Merge: belongs inside an existing project.
- Project candidate: clear value, recurring pain, customer impact, strategic importance, or enough scope to track.

Example:

- "Forum image creation quality is poor" can become a project candidate because it affects product quality and brand trust.
- "A user had a login issue due to language barrier but resolved it by typing in English" is probably an observation for future internationalization, not a project by itself.

MIM should capture promising signals as candidates before creating full projects.

Candidate actions:

- Approve
- Park
- Merge with an existing project
- Discard

Candidate states:

- Candidate
- Approved
- Planning
- Implementation
- Testing
- Deployed
- Maintenance
- Archived

Required project fields:

- Origin story
- Why it matters
- Current status
- Priority
- Latest summary
- Next action
- Dave needed: yes/no
- Linked objectives
- Linked tasks
- Linked documents
- Test evidence
- Deployment history
- Timeline / project log
- Lessons learned
- Impact on related projects

## Projects Page V1 Structure

The `/studio/projects` page is the project command surface.

It should show:

- Project Actions: Start Project, Open Project, Review Signal Inbox, Talk To MIM.
- Score cards: Signals, Candidates, Active, Dave Needed.
- Signal Inbox: observations, parked ideas, merge candidates, and project candidates.
- Signal Triage Rule: ignore, observation, park, candidate, or merge.
- Idea-to-Project Workflow: candidate, approval, discovery, blueprint, roadmap, implementation, testing, deployment, maintenance.
- Status Lanes: candidate, planning, implementation, testing, deployed, maintenance.
- Active Project Examples: project name, status, priority, next action.
- Project Detail Anatomy: summary, origin story, discovery, roadmap, testing, deployment, maintenance.
- MIM Conversation Behavior: confirm intent, classify signal, explain value, ask whether to track/park/merge/ignore.
- Next Backend Need: DB-backed project signals, projects, project events, and project links.

## Objectives

Objectives are MIM/TOD internal growth, repair, research, and capability work.

Examples:

- Improve consultative discovery
- Improve recommendation mode
- Improve voice interaction
- Improve blocker resolution
- Improve validation discipline
- Learn a new framework
- Build world model calibration
- Improve visual servoing

Objective test:

- If the main benefit is improving MIM, TOD, robotics capability, validation quality, or training quality, it is an objective.

## Relationship

A project can create objectives.

Example:

- Project: MIM Accounting
- Generated objectives: Improve OCR accuracy, improve vendor matching, improve receipt categorization.

Objectives improve MIM/TOD so future projects are better.

## Studio Navigation Rule

- `/studio/projects` is the hub for value-producing work.
- `/studio/training` is the hub for MIM/TOD evolution.
- `/studio/training/objectives` owns the objectives surface inside Studio.
- `/objectives` remains available as a legacy direct path.
