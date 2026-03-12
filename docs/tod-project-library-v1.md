# TOD Project Library v1

## Goal

Treat external app folders as managed domains, not raw file access targets.

The project library enables layered integration:

1. Read-only discovery and indexing.
2. Advisory planning.
3. Controlled implementation with policy gates.
4. Cross-project pattern learning.

## Core Files

- Registry: `tod/config/project-registry.json`
- Priority: `tod/config/project-priority.json`
- Media profiles: `tod/config/media-pipeline-profiles.json`
- Media runtime: `tod/config/media-runtime.json`
- Index: `tod/data/project-library-index.json`
- Discovery script: `scripts/Update-TODProjectLibrary.ps1`
- Policy gate script: `scripts/Test-TODProjectAccessPolicy.ps1`
- Queue script: `scripts/Get-TODProjectExecutionQueue.ps1`

## Scope

The registry now covers all known top-level MIM development folders under `E:/`.

This includes software domains and media-oriented domains (for example `MIM BOX` and `mim images`) so TOD can progressively support image/media/document creation workflows alongside code engineering.

## Registry Semantics

Each project entry defines:

- identity: `id`, `name`, `type`
- location: `path`
- operational hints: `languages`, `entry_points`, `test_commands`
- governance: `risk_level`, `write_access`
- boundaries: `allowed_paths`, `blocked_paths`, `notes`

## Operating Policy

- Default mode is read-only discovery.
- Advisory mode can propose plans and risk notes without edits.
- Controlled implementation requires explicit review thresholds and test validation.
- Runtime/state artifacts should remain out of default write scope.

## Discovery Output

`Update-TODProjectLibrary.ps1` scans registered projects and produces:

- existence and path normalization
- sampled file paths
- extension distribution summary
- discovered test artifacts
- discovered entrypoint hints
- unregistered top-level directories under library root

## Commands

Refresh index from `E:\`:

```powershell
.\scripts\Update-TODProjectLibrary.ps1 -RootPath "E:\\"
```

Run training with discovery enabled:

```powershell
.\scripts\Invoke-TODTrainingLoop.ps1 -LibraryRoot "E:\\"
```

Validate write boundaries before any patch operation:

```powershell
.\scripts\Test-TODProjectAccessPolicy.ps1 -ProjectId "comm_app" -RelativePaths "src/core/service.py","secrets/token.txt"
```

Project-scoped sandbox mutation paths are enforced, and mutation actions must use:

- `projects/<project_id>/<relative_path>`

Examples:

```powershell
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "projects/comm_app/src/core/service.py" -Content "# allowed"
.\scripts\TOD.ps1 -Action sandbox-write -SandboxPath "projects/comm_app/secrets/token.txt" -Content "# blocked"
```

Execution mode from `tod/config/project-priority.json` is now enforced at runtime for direct mutations:

- `guarded-write`: allowed (still subject to path policy)
- `advisory-first`: blocked for direct mutation
- `review-only`: blocked for direct mutation

Build prioritized execution queue:

```powershell
.\scripts\Get-TODProjectExecutionQueue.ps1
```

Run mode-routed queue execution:

```powershell
.\scripts\Invoke-TODProjectQueueRunner.ps1 -Top 10 -DryRun
.\scripts\Invoke-TODProjectQueueRunner.ps1 -Top 5 -ExecuteGuardedWrites
```

If `-RelativePath` is omitted, the runner auto-selects an allowed path per project from registry boundaries.

Run media pipeline orchestration:

```powershell
.\scripts\Invoke-TODMediaPipeline.ps1 -ProjectId "mim_images" -Capability "image-generation" -Prompt "coachmim challenge card, high contrast" -DryRun
.\scripts\Invoke-TODMediaPipeline.ps1 -ProjectId "tod" -Capability "diagram-dashboard-rendering" -Prompt "state-bus health dashboard" -Execute
```

Media architecture model:

- TOD is orchestrator/controller.
- Local graphics service handles generation/edit/inference.
- Project policy + execution mode remain gatekeepers for output writes.
