# MIM Studio Reports Conversational Dataset Selection V1

Generated: 2026-06-02

## Summary

`/studio/reports` now treats the operator prompt as the primary input.

The dataset selector is no longer the main decision surface. MIM infers the dataset from the question when possible and explains which dataset was selected.

## Implemented

- Added prompt-based dataset inference.
- Added App Metrics dataset for app user/subscriber/revenue/usage questions.
- Added "You Asked" and "MIM Chose" cards to make the report flow conversational.
- Changed the primary action from "Build Report" to "Ask MIM".
- Added honest missing-source behavior for app analytics.

## Validation

Test prompt:

`how many agentMIM.com users do we have?`

Even when the request URL included `dataset=projects`, Reports selected:

`App Metrics`

MIM summary:

`I understand the question is about AgentMIM users or app analytics. I do not have the live AgentMIM user/subscriber dataset connected to Studio Reports yet, so I cannot honestly answer the count. The correct next step is to connect the app account, analytics, or subscription source and then rerun this canvas.`

Live checks passed:

- `/health` returned OK.
- `/studio/api/reports/state?dataset=projects&prompt=how%20many%20agentMIM.com%20users%20do%20we%20have%3F` returned `dataset=app_metrics`.
- `/studio/reports?...` rendered:
  - You Asked
  - MIM Chose
  - App Metrics
  - not connected

## Operator Outcome

Reports now behaves more like a MIM conversation:

Dave asks the question first.
MIM chooses the dataset.
MIM explains what is missing when the right data source is unavailable.
