# MIM/TOD App Source Registry - comm_app V1

Generated: 2026-06-02

## Purpose

Teach MIM and TOD that AgentMIM is backed by the `comm_app` application source, not only by MIM Studio portal tables.

## Registered App Source

- App key: `comm_app`
- Display name: `comm_app / AgentMIM`
- Public URL: `https://www.agentmim.com`
- Local source root: `E:/comm_app`
- Ecosystem role: business execution layer
- Runtime: Render Flask app
- DB environment keys: `DATABASE_URI`, `DATABASE_URL`

## Expected comm_app DB Tables

From `E:/comm_app/models/db_connect.py`, the app-specific production database expects tables including:

- `account_owners`
- `representatives`
- `clients`
- `group_clients`
- `carriers`
- `commissions`
- `other_commissions`
- `policy_agents`
- `audit_logs`

## Current Studio Reports Truth

Studio Reports now knows the difference between:

- Real `comm_app` account/user tables: `account_owners`, `representatives`
- Fallback MIM/portal tables: `project_portal_accounts`, `project_portal_projects`
- Interface telemetry tables: `workspace_interface_sessions`, `workspace_interface_messages`, `input_events`

Current validation found:

- `account_owners`: missing from the currently connected Studio Reports DB
- `representatives`: missing from the currently connected Studio Reports DB
- `project_portal_accounts`: available, 31 rows
- `project_portal_projects`: available, 31 rows

This means Studio Reports can provide fallback portal/account context, but should not claim a true AgentMIM user count until the Render `comm_app` DB binding is registered and verified.

## Live Endpoints

- App source registry: `/studio/api/apps/sources`
- Conversational reports canvas: `/studio/reports`
- Reports API: `/studio/api/reports/state`

## Validation

Prompt tested:

`how many agentMIM.com users do we have?`

Result:

- Dataset selected: `app_metrics`
- Requested app: `comm_app / AgentMIM`
- Summary explicitly reports that `account_owners` is the true app account table but is missing from the current Studio DB connection.
- Fallback count shown: 31 portal account records.
- Next action shown: verify/bind the true `comm_app` Render database.

## TOD Learning Rule

TOD should treat each managed app as a source bundle:

- app root
- runtime type
- deployment host
- DB env keys
- primary account/user tables
- verification commands
- known fallback tables
- app-specific risk areas

For AgentMIM questions, TOD should inspect `E:/comm_app` and its Render DB contract before relying on MIM Studio fallback tables.
