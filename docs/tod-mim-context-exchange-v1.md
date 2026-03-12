# TOD-MIM Context Exchange v1

Purpose: keep TOD, MIM, and collaborators aligned while TOD continues local execution.

## Contract Summary

TOD publishes a periodic context snapshot and all collaborators/MIM drop structured progress updates into a shared inbox.

- Snapshot producer: TOD
- Update producers: MIM + collaborators
- Snapshot format: YAML + JSON
- Update format: JSON

## Shared Paths

Configured in [tod/config/context-exchange.json](../tod/config/context-exchange.json).

- Export directory: `tod/out/context-sync/exports`
- Latest snapshot (YAML): `tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.yaml`
- Latest snapshot (JSON): `tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json`
- Inbound updates inbox: `tod/inbox/context-sync/updates`
- Processed updates: `tod/out/context-sync/processed`
- Update ingestion log: `tod/out/context-sync/context-updates-log.jsonl`

## Snapshot Shape

Header and sections mirror your collaborator handoff style:

- `MIM_CONTEXT_EXPORT`
- `system` (name/environment/gpu)
- `status` (objective_active/phase/reliability/trend/blockers)
- `recent_actions`
- `projects`
- `next_actions`

## Inbound Update JSON Shape

Recommended payload:

```json
{
  "source": "mim-gateway",
  "actor": "planner-bot",
  "channel": "architecture-review",
  "update_type": "planning",
  "project": "TOD",
  "summary": "verification gate checklist updated",
  "details": {
    "owner": "ops",
    "links": ["docs/tod-project-library-v1.md"]
  },
  "created_at": "2026-03-12T02:00:00Z"
}
```

## Commands

Export latest context snapshot:

```powershell
.\scripts\Invoke-TODContextExchange.ps1 -Action export
```

Export with explicit next actions:

```powershell
.\scripts\Invoke-TODContextExchange.ps1 -Action export -NextActions "finalize verification gate","begin objective 21 planning","publish collaborator plan delta"
```

Check exchange status:

```powershell
.\scripts\Invoke-TODContextExchange.ps1 -Action status
```

Ingest all pending inbound updates:

```powershell
.\scripts\Invoke-TODContextExchange.ps1 -Action ingest
```

Ingest one specific file:

```powershell
.\scripts\Invoke-TODContextExchange.ps1 -Action ingest -InputPath "tod/inbox/context-sync/updates/update-001.json"
```

## Coordination Workflow

1. TOD runs `-Action export` on cadence or after major milestone changes.
2. Collaborators read `MIM_CONTEXT_EXPORT.latest.yaml` and prepare planning/architecture updates.
3. Collaborators and MIM drop JSON updates into `tod/inbox/context-sync/updates`.
4. TOD runs `-Action ingest` to accept, log, and move updates to processed.
5. Any critical update should be reflected in TOD objective/task planning in the next cycle.
