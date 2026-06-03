# MIM Studio Apps Registry V1

Generated: 2026-06-02

## Purpose

Create the first `/studio/apps` registry so MIM and TOD can manage applications as first-class systems instead of remembering app details from scattered conversations.

## What Changed

- Added a real `/studio/apps` page.
- Added `/studio/api/apps/state`.
- Expanded `/studio/api/apps/sources`.
- Added TOD-side app source scan artifact: `MIM_TOD_APP_SOURCE_SCAN.latest.json`.
- Removed placeholder page explanations such as `What This Page Owns` and `Current Truth`.
- Replaced `needs scan` posture with actual scanned app facts.
- Registered the initial app fleet:
  - `comm_app / AgentMIM`
  - `MIM Studio`
  - `MIM Wall`
  - `coachMIM`
  - `Mimir`
  - `mim_pulz`
  - `MIM Robotics`
  - `MIM Station`
  - `mim_devl`

## App Registry Fields

Each app source can now carry:

- app key
- display name
- public URL
- local source root
- ecosystem role
- runtime
- DB environment keys
- primary account table
- secondary user table
- known tables
- fallback tables
- TOD reference
- verification reference

## Live Validation

Validated endpoints:

- `GET /health`: healthy
- `GET /studio/api/apps/state`: returned app fleet state
- `GET /studio/apps`: HTTP 200

Page content validation:

- contains `MIM App Registry`
- contains `comm_app / AgentMIM`
- contains `MIM Wall`

Current registry summary:

- registered apps: 9
- live inspectable from MIM host: 1
- scanned by TOD from Windows-side app roots: 8
- DB primary table proven in current Studio DB connection: 1
- dirty repos: 2

TOD-side scan facts:

- `comm_app`: git repo, branch `main`, commit `761cafd8`, dirty count `0`
- `mim_wall`: git repo, branch `main`, commit `6a63663`, dirty count `0`
- `coachMIM`: git repo, branch `main`, commit `a4e0241`, dirty count `1`
- `Mimir`: folder exists, not a git repo
- `mim_pulz`: git repo, branch `main`, commit `031d2da`, dirty count `57`
- `MIM Robotics`: folder exists, not a git repo
- `MIM Station`: folder exists, not a git repo
- `mim_devl`: folder exists, not a git repo

## Important Truth

The MIM host can inspect `/home/testpilot/mim` directly, but it cannot directly inspect Windows-side app roots such as `E:/comm_app` or `E:/mim_wall`.

Those apps are now registered and the first TOD-side app scan publishes:

- git status
- branch
- latest commit
- dirty worktree count
- root file sample

Next scanner passes should add:

- current version
- test/verification commands
- environment key map
- DB table map
- deployment target
- service/vendor dependencies

## comm_app / AgentMIM Notes

`comm_app / AgentMIM` is registered as the business execution layer.

Expected app-specific DB tables include:

- `account_owners`
- `representatives`
- `clients`
- `group_clients`
- `carriers`
- `commissions`
- `other_commissions`
- `policy_agents`
- `audit_logs`

Current Studio DB connection does not expose `account_owners` or `representatives`, so `/apps` and `/reports` correctly show fallback portal counts rather than claiming a true AgentMIM production user count.

## Next Step

Build the TOD app-source scanner so Windows-side app repositories can publish live app facts into Studio:

- repo health
- git state
- current version
- DB schema
- vendor/service map
- deployment map
- support/ticket state
- linked projects/documents/reports
