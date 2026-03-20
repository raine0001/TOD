# AgentMIM Update: TOD Status And Managed-Project Capabilities

Date: 2026-03-20
Audience: MIM / AgentMIM operators and collaborators

## Current Status

- TOD is operational as the coordination and managed-work layer across registered MIM projects.
- TOD remains in `guarded` write mode for its own repo and uses per-project boundaries from [tod/config/project-registry.json](e:/TOD/tod/config/project-registry.json).
- The most recent completed cross-project work was the `comm_app` marketing docs-capture workflow, including code changes, runbook updates, screenshot generation, commit, and push.
- The `comm_app` marketing/docs work is complete and published.
- TOD itself still has unrelated local working-tree churn from runtime artifacts, experimental scripts, and state outputs; low-risk cleanup has started by removing tracked Python cache files and tightening ignore rules for local cache/archive artifacts.

## Recent Work Completed

### comm_app marketing docs capture

TOD recently completed and published a full documentation-capture pass for AgentMIM's admin marketing surface.

Delivered outcomes:

- Playwright-based auth bootstrap and screenshot capture for `/admin/marketing`
- repeatable screenshot output under `docs/screenshots/marketing/`
- local SQLite bootstrap helper for docs capture runtime
- native CSRF token exposure in the shared shell so capture no longer depends on a Playwright-side workaround
- local rig-preview fallback behavior for docs validation when background workers are unavailable
- refreshed operator/help docs and capture runbook
- verified clean validation path on `http://127.0.0.1:6011` with:
  - `DISABLE_BACKGROUND_TICKS=1`
  - `MARKETING_RIG_PREVIEW_FALLBACK_ONLY=1`

### TOD-side coordination work

TOD already contains project-management helpers around this flow, including:

- local verification gates for AgentMIM tasks
- managed-work classification for `comm_app`
- docs-prep and docs-capture wrappers for the marketing surface
- per-project boundary enforcement from the registry
- status and readiness summaries for AgentMIM coordination

## What TOD Can Do Today

## Access registered projects

From [tod/config/project-registry.json](e:/TOD/tod/config/project-registry.json):

- TOD has `project_access_scope = all-registered-projects`
- TOD can access all registered MIM folders
- write operations remain bounded by each project's `write_access` mode and path boundaries

In practice this means TOD can:

- discover registered projects and their roots
- read project entry points, docs, and test commands
- inspect git state and classify pending work
- operate in `guarded`, `review-only`, or advisory-first modes depending on the project

## Verify before live updates

TOD has explicit local verification gating for AgentMIM-managed work.

Relevant scripts:

- [scripts/Invoke-TODAgentMimLocalVerification.ps1](e:/TOD/scripts/Invoke-TODAgentMimLocalVerification.ps1)
- [scripts/Invoke-TODAgentMimReadinessCycle.ps1](e:/TOD/scripts/Invoke-TODAgentMimReadinessCycle.ps1)

Current behavior:

- builds a task queue for local verification
- checks that project paths exist
- checks critical docs presence
- checks whether suggested verification commands are available
- blocks strict live updates when required gates fail

This is the main safety mechanism behind the policy:

- local test copy before live updates

## Manage scoped project work

TOD can classify a project's working tree into actionable buckets instead of treating every changed file as part of one patch.

Relevant scripts:

- [scripts/Invoke-TODProjectManagedWork.ps1](e:/TOD/scripts/Invoke-TODProjectManagedWork.ps1)
- [scripts/Invoke-TODCommAppManagedWork.ps1](e:/TOD/scripts/Invoke-TODCommAppManagedWork.ps1)

Current capabilities:

- identify whether changes are inside allowed write scope
- detect blocked-path changes
- separate product patch files from QA/support artifacts
- flag manual-review files
- produce a recommended action set for the next TOD-managed task

This is what lets TOD work on a repo like `comm_app` with a narrow feature scope instead of blindly consuming the whole working tree.

## Run feature-specific wrappers

TOD already has dedicated wrappers for `comm_app` marketing/admin work:

- [scripts/Invoke-TODCommAppVerification.ps1](e:/TOD/scripts/Invoke-TODCommAppVerification.ps1)
- [scripts/Invoke-TODCommAppMarketingDocsPrep.ps1](e:/TOD/scripts/Invoke-TODCommAppMarketingDocsPrep.ps1)
- [scripts/Invoke-TODCommAppMarketingDocsCapture.ps1](e:/TOD/scripts/Invoke-TODCommAppMarketingDocsCapture.ps1)
- [scripts/Invoke-TODCommAppMarketingSmoke.ps1](e:/TOD/scripts/Invoke-TODCommAppMarketingSmoke.ps1)
- [scripts/Invoke-TODCommAppSpokespersonQAGate.ps1](e:/TOD/scripts/Invoke-TODCommAppSpokespersonQAGate.ps1)

These wrappers show that TOD can already:

- prepare demo data
- run local validation
- classify repo state for managed work
- capture docs assets
- coordinate QA-oriented checks around the same project surface

## Update, commit, and publish scoped work

The recent `comm_app` marketing/docs cycle demonstrated that TOD can carry a complete managed-work loop:

- inspect scope
- update code and docs
- generate required docs assets
- record repo/TOD status
- commit only the intended files
- push those commits without bundling unrelated local churn

## Current Limits And Follow-Up Work

TOD is useful now, but its own repo still needs more hygiene work.

Remaining TOD-side concerns:

- many unrelated modified and untracked files still exist on `main`
- runtime/state outputs are mixed with source changes in the working tree
- additional ignore policy cleanup is still needed for broader generated-state folders
- source changes versus operational artifacts still need a deliberate split into smaller commits

Low-risk cleanup completed in this pass:

- ignore rules added for Python cache artifacts and local RunPod archive bundles
- tracked Python bytecode files removed from version control

## Practical Summary For MIM

TOD can already act as a bounded project operator across registered MIM repos.

Today it is strongest at:

- project discovery and status tracking
- local verification before live edits
- scoped managed-work execution in `comm_app`
- docs/help capture workflows
- commit/push execution for tightly scoped changes

TOD is not yet fully tidy on its own repo, but that does not block its current ability to access, update, and manage downstream projects under guarded rules.