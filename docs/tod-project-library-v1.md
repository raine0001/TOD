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

## Verification Order

For registered projects with high-risk feature surfaces, verification should prefer the narrowest acceptance surface first and only then fall back to broader project checks.

For `comm_app`, TOD should verify the AgentMIM admin marketing avatar/video surface first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/TOD/scripts/Invoke-TODCommAppVerification.ps1 -ProjectRoot E:/comm_app
```

That combined verification command should:

- run the feature-scoped marketing avatar/video smoke gate
- use the project-local Python environment when present
- run `pytest --collect-only`
- capture git status before live updates

Then use broader repository checks such as `pytest` or `python -m pytest --collect-only` when deeper validation is required.

This keeps TOD aligned with the actual product surface at `/admin/marketing/?tab=video#video` rather than treating the entire Flask application as one undifferentiated write target.

## Reusable Managed Loop

The `comm_app` workflow is now the first concrete implementation of a reusable TOD process, not a one-off exception.

TOD's reusable application-management loop is:

1. Identify the project from the registry and execution mode from priority.
2. Run the narrowest meaningful verification command.
3. Classify the live repo delta into managed product patch, QA/support artifacts, blocked-scope changes, and manual-review files.
4. Respect execution mode:
	- `guarded-write`: TOD may proceed to bounded edits after verification and triage.
	- `advisory-first`: TOD should plan and classify but not patch directly.
	- `review-only`: TOD should summarize risks and scope only.
5. Run optional advisory quality checks without contaminating the core product patch gate.
6. Patch, then re-run the same verification loop.

The reusable triage command is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/TOD/scripts/Invoke-TODProjectManagedWork.ps1 -ProjectId comm_app -ProjectRoot E:/comm_app
```

That generic command teaches TOD the cross-project process by using:

- project registry boundaries
- project priority execution modes
- project verification command inventory
- repo-delta classification into product patch versus support artifacts

`comm_app` remains the most complete training example because it also has a project-specific verification surface and advisory QA gate, but the generic managed-work loop now applies to other registered projects as well.

## Managed Work Loop

After the required verification gate passes, `comm_app` should move into a TOD-managed work cycle before new edits are started:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/TOD/scripts/Invoke-TODCommAppManagedWork.ps1 -ProjectRoot E:/comm_app
```

That managed-work command should:

- reuse the combined verification artifact as the gatekeeper
- classify pending repo changes into managed product patch files versus QA/support artifacts
- keep untracked QA/reference assets from silently contaminating a product patch
- emit a TOD-ready patch scope so future AgentMIM work can be directed from TOD interaction rather than raw git inspection

For the current AgentMIM avatar/admin workflow, this means TOD can distinguish product files such as `app/services/animation_provider.py` and `tests/test_marketing_animation_provider.py` from helper artifacts like `scripts/qa_*` before continuing with live work.

An additional non-blocking QA advisory pass is now available for `comm_app`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/TOD/scripts/Invoke-TODCommAppSpokespersonQAGate.ps1 -ProjectRoot E:/comm_app -Runs 1 -Duration 6
```

That QA gate should:

- use the project-local Python environment when present
- run the comm_app spokesperson expression fixture
- capture the JSON result as advisory evidence
- remain non-blocking until TOD policy explicitly promotes it to a stricter gate

For help-asset preparation on the marketing surface, TOD now also has a docs-prep command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/TOD/scripts/Invoke-TODCommAppMarketingDocsPrep.ps1 -ProjectRoot E:/comm_app -DemoPassword <password> -Reset
```

That command should:

- use the comm_app local Python environment
- run `flask seed-marketing-demo`
- prepare a screenshot-ready admin marketing workspace with demo avatars, TTS presets, rig data, and queued/completed animation states
- emit a JSON artifact that TOD can use before Playwright capture or future narrated help-video assembly

TOD also now has a capture wrapper for the seeded marketing docs workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/TOD/scripts/Invoke-TODCommAppMarketingDocsCapture.ps1 -ProjectRoot E:/comm_app -DemoPassword <password> -Reset -BootstrapAuth
```

That command should:

- run marketing docs prep first
- optionally bootstrap Playwright auth state
- run the Playwright screenshot capture command
- emit a JSON artifact recording prep, auth, and screenshot stages
- fail clearly when node/npm are unavailable in the runtime environment

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
