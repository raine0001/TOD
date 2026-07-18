# ENT-001 Capability Freeze

## Capability Added
Enterprise Foundation V1 added the first deployable Enterprise Observatory shell:

- Enterprise database model.
- Enterprise create/list/get/update/soft-delete service.
- Enterprise API router.
- `/observatory/enterprise` shell route.
- `ent_demo` / `mimtod` demo login path through the project portal login route.

## Architectural Purpose
This slice gives MIM a durable enterprise object to govern future Observatory work. MIM owns product direction and enterprise roadmap decisions. TOD owns bounded implementation slices after MIM selects the next product step.

Target product sequence:

1. Enterprise Dashboard
2. Enterprise Health
3. Enterprise Objectives
4. Enterprise Documents
5. Enterprise Analytics
6. Enterprise AI

## Deployment Pattern
The safe deployment pattern was not whole-file copy from the local mirror.

Observed constraints:

- `tmp_remote_mim` is ignored locally and does not behave like a normal clean source tree.
- `tmp_remote_mim/core/models.py` contained unrelated existing research-model changes.
- The remote MIM Box files differed from local mirror hashes.
- Whole-file upload risked dragging unrelated local mirror changes into production.

Safe pattern used:

1. Inspect local intended changes and remote target anchors.
2. Add new files directly when they are isolated.
3. Apply idempotent remote patch logic for large dirty files.
4. Compile in the remote app virtualenv.
5. Run focused tests in the remote app virtualenv.
6. Restart the service only after compile/import tests pass.
7. Run live route and login smoke tests.
8. Record borrowed capability debt if Codex performed the bridge.

## Validation Evidence
Evidence file:

`runtime_remote_training/tod_independent_resolution_attempts/ENT_001_ENTERPRISE_DATABASE_FOUNDATION_PROGRESS.latest.json`

Passed checks:

- Remote MIM Box `./.venv/bin/python -m py_compile` for all touched startup-loaded modules.
- Remote MIM Box `./.venv/bin/python tests/test_enterprise_service.py`: 3 tests passed.
- Remote MIM Box API router import smoke confirmed `/enterprises` and `/enterprises/{enterprise_id}`.
- Remote MIM Box demo login helper accepted `ent_demo` and rejected wrong password.
- Remote MIM Box Observatory route smoke passed.
- `mim-mobile-web.service` restarted and remained active.
- Live `/observatory/enterprise` rendered `Enterprise Observatory`.
- Live `/enterprises` returned an empty list before demo login.
- Live `/projects/login` with `ent_demo` / `mimtod` authenticated and provisioned `enterprise_id=ent_demo`.
- Live `/enterprises` returned the `ent_demo` enterprise after login.

## Lessons Learned
The feature pattern is not the primary lesson. The deployment pattern is.

TOD must learn to:

- Distinguish dirty mirrors from deployable source.
- Avoid whole-file remote replacement when target files contain unrelated local changes.
- Prefer idempotent, anchor-based minimal patches for large shared files.
- Validate with the same interpreter and service context used by production.
- Treat a successful local compile as insufficient until remote import and live smoke pass.
- Preserve capability credit honestly: Codex-authored bridges are borrowed capability.

## Reuse Triggers
Reuse this pattern when:

- A feature touches MIM Box startup-loaded modules.
- Local mirror files are ignored or dirty.
- Remote file hashes differ from local mirror hashes.
- A deploy requires touching model/schema/router registry/login or app startup code.
- The change must be applied without pulling unrelated local edits into production.

## Independent TOD Status
Status: borrowed capability.

Proficiency: observed.

Reason: Codex performed the minimal remote patch deployment bridge and shaped the service/router/demo-login slices after TOD could not yet complete this class end to end.

Independent demonstration required:

TOD must inspect the Enterprise implementation, identify the deployment pattern, create one harmless bounded addition, deploy it without Codex-written deployment packet or manual bridge edits, validate it remotely, publish evidence, and avoid copying the Enterprise feature itself.
