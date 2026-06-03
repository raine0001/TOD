# MIM Studio Compact Shell V1

Generated: 2026-06-02

## Purpose

Reduce repeated and static header content across Studio pages.

## Changes

- Removed large page H1 rendering from the Studio shell.
- Removed static subtitle rendering from the Studio shell.
- Reduced brand text size.
- Hid the static Studio brand subtitle.
- Tightened topbar and tab spacing.
- Replaced the old hero block with a compact page label.
- Removed redundant embedded-console intro cards from `/studio/mim` and `/studio/tod`.
- Placeholder pages no longer repeat page title/subtitle in a separate card.

## Validation

Validated live:

- `/studio`
  - no `<h1>`
  - no rendered subtitle class
  - no `Dave's Command Center` large title
- `/studio/mim`
  - no duplicate `MIM Console` card
  - no `Open dedicated` intro card
  - iframe still loads
- `/studio/apps?app=comm_app`
  - no `<h1>`
  - no static app subtitle
  - selected app panel still loads
  - compact page label renders as `MIM Apps`

## Rule

Studio pages should reserve vertical space for live operational content, not static explanations Dave already understands.
