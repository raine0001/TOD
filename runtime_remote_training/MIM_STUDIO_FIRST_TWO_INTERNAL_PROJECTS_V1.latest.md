# MIM Studio First Two Internal Projects V1

Generated: 2026-06-02

## Objective

Turn `/studio/lab` and `/studio/accounting` into the first two official internal MIM/TOD project pages.

## Projects Created

### MIM Lab Exploration

Purpose: exploration hub for robotics experiments, physical builds, workspace calibration, sensors, publications, opportunities, and development tools.

Status: active experiments.

Next action: organize active experiments and prepare the world-model calibration run for the next arm session.

### MIM Operations Accounting

Purpose: internal accounting tool for provider spend, subscriptions, invoices, resource use, project cost allocation, and waste detection.

Status: discovery.

Next action: map provider bills, invoice sources, receipt ingestion, recurring subscriptions, and project cost allocation.

## Page Behavior

`/studio/lab` now separates experiments from projects:

- active experiments
- builds
- development tools
- publications/news
- opportunities

`/studio/accounting` now starts as internal operations accounting:

- provider cost surfaces
- smart waste-detection actions
- provider categories from environment inventory
- phased roadmap from discovery to productization

## Process Test

This intentionally treats both pages as real Studio-managed work, not static tabs. Each has a Studio project record, origin story, why-it-matters field, and next action.

## Verification

- `/studio/lab` should show `MIM Lab Exploration`, `Active Experiments`, `Builds`, `Development Tools`, `Publications / News`, and `Opportunities`.
- `/studio/accounting` should show `MIM Operations Accounting`, `Provider Cost Surfaces`, `Smart Actions`, `Provider Categories`, and phased roadmap cards.
