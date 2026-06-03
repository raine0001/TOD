# MIM Studio Apps Click-To-Load Standard V1

Generated: 2026-06-02

## Purpose

Standardize `/studio/apps` around compact app cards plus a selected app detail panel.

## Behavior

- `/studio/apps` opens a default selected app detail panel.
- `/studio/apps?app=mim_robotics` opens MIM Robotics directly.
- App cards remain visible for scanning and comparison.
- Clicking a card reloads the page with `?app=<app_key>`.
- Hover is reserved for small hints later; full app context loads on click.

## Selected Detail Panel

The selected app panel now includes:

- selected app identity
- health
- last touched / scan timestamp
- docs placeholder count
- projects placeholder count
- tasks placeholder count
- operations details
- host/runtime/source
- git branch/commit/dirty count
- public deploy URL
- next action
- DB status
- primary/secondary tables
- environment key names
- homepage/provider API status
- DB construct table list
- hosting/fallback count table

## Compact Card Strip

Each app card now shows:

- health
- role
- docs count placeholder
- projects count placeholder
- tasks count placeholder
- risk
- runtime/source status
- git quick status
- users/data quick status
- next action

## Validation

Validated:

- `GET /studio/apps`: HTTP 200
- `GET /studio/apps?app=mim_robotics`: HTTP 200
- direct MIM Robotics URL contains:
  - `Selected App`
  - `MIM Robotics`
  - `PythonAnywhere`
  - `DB Construct`
  - app card links such as `/studio/apps?app=comm_app`

## Next Step

Replace placeholder counts with DB-backed relationships:

- linked documents
- linked projects
- linked tasks
- support tickets
- deployments
- incidents
- version records
- vendor/service records
