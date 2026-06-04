# MIM Studio Projects Table Organization V1

Status: completed_with_evidence
Owner: MIM + TOD
Priority: P0

## Goal

Make the Studio Projects inbox table sortable, filterable, and searchable as the project list grows.

## Requirements

- Click-sort every visible column.
- Add quick filters: All, Finished, In Process, Queued, Blockers, Dave Needed.
- Add search across project title, status, owner, progress, blocker, next action, Dave flag, work state, and project type.
- Boolean search should support simple AND/OR/quoted phrases if practical.
- Preserve click-to-open project rows.
- Add no static descriptive filler text.

## Execution

MIM owns the project spec and follow-through.

TOD owns implementation and validation.

Codex stepped in after the task stayed active without closing evidence.

## Completion Evidence

- Projects table renders sortable headers with visible direction state.
- Projects table renders quick filters: All, Finished, In Process, Queued, Blockers, Dave Needed.
- Projects table search uses row data and supports quoted phrases plus OR groups.
- Project rows retain click-to-open behavior.
- Studio reconciliation now marks this project completed at 100% instead of resetting it to working/25%.

## Follow-Up

Monitor live behavior and reopen only if sorting, filtering, search, or row opening fails.
