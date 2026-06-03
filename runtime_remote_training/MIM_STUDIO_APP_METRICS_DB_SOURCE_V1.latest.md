# MIM Studio App Metrics DB Source V1

Generated: 2026-06-02

## Summary

Studio Reports App Metrics now reads live counts from the connected MIM database instead of stopping at "dataset not connected."

## Connected Sources

The current MIM database contains 127 public tables. For App Metrics V1, Reports now uses:

- `project_portal_accounts`
- `project_portal_projects`
- `workspace_interface_sessions`
- `workspace_interface_messages`
- `input_events`

## Validation Prompt

`how many agentMIM.com users do we have?`

## Live Result

Reports selected:

`App Metrics`

MIM summary:

`From the connected MIM database, I can see 31 known account records in project_portal_accounts. I do not yet see a separate table explicitly named for AgentMIM production users, so I am treating this as the current MIM/portal account count until an app-specific user table or analytics source is registered.`

## Live Counts

- Known account records: 31
- Project portal projects: 31
- Interface sessions in last 30 days: 842,993
- Interface messages in last 30 days: 2,658,334
- Input events in last 30 days: 1,335,799

## Remaining Gap

Reports can now use the connected MIM database, but app-specific source grouping still needs to be formalized.

Needed next:

- map AgentMIM vs Studio vs MIM Wall source names
- register any dedicated AgentMIM production-user table if it exists outside the current named tables
- add Stripe/subscription adapter before reporting paid users, subscription income, or MIM Wall revenue

## Operator Outcome

MIM no longer says App Metrics are simply unavailable.

MIM now uses available DB truth, labels the source, and states the remaining data-source boundary clearly.
