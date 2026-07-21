# MIM/TOD Remaining Dirty Route Experiments - 2026-07-21

## Classification

Status: preserved_as_training_debt_not_product_logic

Codex role: validation_and_cleanup_after_mixed_experiment_detection

## What Was Found

After the Studio live lifecycle UI slice was committed, two files still contained a large unrelated dirty diff:

- `tmp_remote_mim/core/routers/studio.py`
- `tmp_remote_mim/core/routers/tod_ui.py`

The remaining `studio.py` diff mixed route-level changes for active conversation state, relationship/location memory examples, self-knowledge replies, response-authority audit UI/API, objective continuity, and current-source replies.

The remaining `tod_ui.py` diff added a phrase-triggered no-Codex contingency response path.

## Why It Was Not Shipped

The changes may contain useful direction, but they do not satisfy the no-hard-route rule. They place cognition, response authority, and operator-visible behavior directly in route files before MIM/TOD have demonstrated the learned capability.

That makes the diff training debt, not a safe product slice.

## Preservation

The dirty diff was saved before cleanup:

`runtime_remote_training/cleanup_holds/20260721_remaining_dirty_mim_tod_route_experiments.patch`

## Required Follow-Up Training

1. MIM must define the intended learned capability without phrase patches.
2. TOD must audit the saved patch and classify each block as infrastructure, process support, route debt, hardcoded response, or reusable service candidate.
3. Any retained behavior must move through a capability-first implementation path with tests that prove generalization beyond the example prompts.
4. Route files must stay small and must not become the place where MIM or TOD cognition is faked.

## Prevention Lesson

When a dirty worktree contains mixed cognition experiments and route-level response logic, isolate the deployable product slice first, preserve the rest as evidence, and clean the worktree. Do not let unreviewed response authority changes hitchhike into an unrelated UI commit.
