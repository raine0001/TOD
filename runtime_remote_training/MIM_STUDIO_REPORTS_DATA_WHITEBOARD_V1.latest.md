# MIM Studio Reports Data Whiteboard V1

Generated: 2026-06-02

## Summary

`/studio/reports` is now implemented as a dynamic data whiteboard.

Reports are not a static dashboard catalog. A report starts with a question, loads a dataset, generates a MIM summary, exposes structured rows, and turns findings into possible actions.

## Implemented

- Added `StudioReportCanvas` DB model.
- Added report canvas state and creation APIs:
  - `GET /studio/api/reports/state`
  - `GET /studio/api/reports/dataset`
  - `POST /studio/api/reports/canvases`
- Added CSV export through:
  - `GET /studio/api/reports/dataset?dataset=<key>&format=csv`
- Added `/studio/reports` page with:
  - question-first report prompt
  - dataset selector
  - MIM-generated "what we are looking at" summary
  - stats cards
  - findings
  - actions
  - loaded data table
  - JSON and CSV links
  - saved report canvases
  - available dataset map

## Initial Datasets

- Studio Overview
- Training
- Objectives
- Tasks
- Projects
- Documents
- Document Graph
- TOD Blockers
- System Health

## Validation

- `/health` returned OK.
- `/studio/reports` rendered:
  - Data Whiteboard
  - MIM Summary
  - Loaded Data
  - Saved Canvases
  - Available Datasets
- `GET /studio/api/reports/state?dataset=training&prompt=How%20is%20training%20doing%3F` returned:
  - dataset: training
  - 6 rows
  - 3 findings
  - MIM/TOD training summary with the outcome caveat
- CSV export worked for objectives.
- Saved report canvas created:
  - Objective Stale Work Review
  - dataset: objectives
  - 4 findings
- `/studio/reports?dataset=document_graph&prompt=What%20documents%20connect%20to%20training%3F` rendered the selected question, document graph dataset, findings, and JSON link.

## Operator Outcome

Dave can now use `/studio/reports` as a blank analytical canvas.

The page can answer:

- what data are we looking at?
- what does MIM think it means?
- what rows support that view?
- what findings matter?
- what actions should happen next?

Future app datasets can plug into the same report canvas model for AgentMIM users, MIM Wall subscriptions, accounting vendors, social posts, app health, and customer activity.
