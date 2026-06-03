# MIM Studio Projects DB-Backed V1

## Implemented

Studio Projects now has DB-backed records for:

- `studio_project_signals`
- `studio_projects`
- `studio_project_events`
- `studio_project_links`

## Purpose

MIM can now store project signals and projects as durable records instead of static page examples.

## API Surface

- `GET /studio/api/projects/state`
- `POST /studio/api/project-signals`
- `POST /studio/api/projects`
- `POST /studio/api/project-signals/{signal_id}/promote`
- `POST /studio/api/projects/{project_id}/events`

## Validated

- Project state endpoint returns seeded DB rows.
- Project page renders from DB state.
- Created real signal: `Documents Library`.
- Recorded project event on `MIM Project Studio`.
- Promoted `Documents Library` signal into a project.
- `/studio/documents` updated as the MIM library concept page.

## Notes

The MIM web runner disables FastAPI lifespan, so schema creation was added to `scripts/run_mim_mobile_web.sh` before uvicorn starts.

## Next

Create the actual document library backend:

- document records
- tags
- source links
- project/objective/task links
- upload/index/search path
- MIM retrieval behavior
