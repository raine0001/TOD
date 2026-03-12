# TOD Shared Development Log Contract v1

Purpose: define how TOD, MIM, and collaborators maintain a synchronized development log without losing source-of-truth integrity.

## Scope

This contract governs:

- Canonical shared state snapshots in shared_state/
- Append-only operational logs
- Inbound/outbound context exchange updates
- ChatGPT/handoff snapshots for external collaboration

## Canonical Artifacts

State snapshots (overwrite allowed by sync script only):

- shared_state/current_build_state.json
- shared_state/objectives.json
- shared_state/contracts.json
- shared_state/next_actions.json
- shared_state/shared_development_log_plan.json

Append-only logs (never rewrite historical entries):

- shared_state/dev_journal.jsonl
- tod/out/context-sync/context-updates-log.jsonl

Handoff snapshots:

- shared_state/chatgpt_update.md
- shared_state/chatgpt_update.json
- shared_state/latest_summary.md

## Ownership Model

TOD responsibilities:

- Generate canonical shared_state files.
- Ingest collaborator/MIM updates from inbox.
- Append objective-level sync events to dev journal.

MIM responsibilities:

- Consume shared_state snapshots for planning/memory persistence.
- Publish structured updates into TOD context inbox.
- Correlate execution feedback and objective lifecycle updates.

Collaborator responsibilities:

- Submit structured updates with source, actor, project, summary.
- Use shared_state artifacts as canonical view.
- Avoid direct edits to canonical shared_state files.

## Cadence

Event-driven triggers:

- after focused quality gate
- after full regression
- after context ingest/export cycle
- after objective transition

Periodic fallback:

- minimum: daily
- recommended: once per active development session

## Merge Rules

- Append-only for journal and context-update logs.
- All timestamps must be UTC ISO-8601.
- Canonical shared_state snapshots are written by automation, not manual edits.
- Keep updates objective-scoped and machine-readable.
- Preserve original inbound payload content when writing context update log records.

## Required Update Envelope (Context Inbox)

Recommended JSON shape:

{
  "source": "mim-gateway",
  "actor": "planner-bot",
  "channel": "planning",
  "update_type": "planning",
  "project": "TOD",
  "summary": "Objective gate plan adjusted",
  "details": {
    "owner": "ops"
  },
  "created_at": "2026-03-12T03:00:00Z"
}

## Execution Command

Run full refresh bundle:

```powershell
.\scripts\Invoke-TODShareBundleRefresh.ps1
```

Run shared-state-only refresh:

```powershell
.\scripts\Invoke-TODSharedStateSync.ps1
```
