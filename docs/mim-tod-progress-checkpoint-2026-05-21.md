# MIM/TOD Progress Checkpoint - 2026-05-21

## Current worktree shape

This checkpoint was created after recovering context around the MIM private-lab camera/microphone resource-access thread and cleaning the immediate test harness drift.

Tracked source/runtime changes currently fall into these groups:

- MIM UI operator visibility:
  - `tmp_remote_mim/core/mim_ui.py`
  - `tmp_remote_mim/core/routers/mim_ui.py`
  - Adds `operator_status` loading/rendering from `runtime/shared/MIM_OPERATOR_STATUS.latest.json`.
  - Keeps raw communication/activity panels below the new canonical current-work card.

- MIM gateway routing and response behavior:
  - `tmp_remote_mim/core/routers/gateway.py`
  - Adds local/private-lab camera and microphone resource-access replies.
  - Adds self-model/operator-state routing.
  - Adds implementation-objective dispatch materialization.
  - Adds operator-summary routes for training batches and useful-work interruption artifacts.
  - Hides raw request wrappers by default and exposes them only for explicit technical/debug requests.
  - Prefers `TOD_RUNTIME_OWNERSHIP.latest.json` for current-work answers when that artifact exists.

- Focused regression coverage:
  - `tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py`
  - Expands the isolated gateway helper loader for new helper functions/constants.
  - Adds tests for wrapper hiding, implementation dispatch, lifecycle follow-through, audit/reporting routes, batch summaries, and current-work artifact preference.

- Watchdog publication repair:
  - `scripts/Start-TODRecoveryWatchdog.ps1`
  - Extends fresh pending noncanonical handoff detection to include `MIM_TOD_IMPLEMENTATION_DISPATCH.latest.json`.

- State/generated artifacts:
  - `shared_state/watchdog-repair/MIM_TOD_TASK_REQUEST.latest.json`
  - `tod/data/engineering-memory.json`
  - `tod/knowledge/engineering-memory/routing_decision_memory.json`

- New untracked artifact folder:
  - `runtime_remote_training/`
  - 55 files containing Batch 10-23 training summaries/results, useful-work interruption simulation, growth-cycle artifacts, and reinforcement-alpha artifacts.

## Camera/microphone resource-access status

The MIM UI already contains browser-side media capability handling:

- frontend media status model and TTL snapshot
- microphone/camera device enumeration
- microphone permission/openability handling through `navigator.mediaDevices.getUserMedia`
- camera device selection/status reporting
- frontend media status POSTs to `/mim/ui/frontend-media-status`
- microphone transcript events posted to `/gateway/perception/mic/events`

The gateway now has a private-lab sensor project reply path. It distinguishes resource authority from live capture truth: MIM can say the private lab cameras/mics are authorized resources, but should not claim a specific live feed is working until an openability/capture probe proves it.

## Validation run

Clean checks:

- `git diff --check`
- `python -m py_compile tmp_remote_mim/core/mim_ui.py tmp_remote_mim/core/routers/mim_ui.py tmp_remote_mim/core/routers/gateway.py tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py`
- `python -m unittest tmp_remote_mim.tests.integration.test_mim_tod_handoff_gateway`

Focused gateway suite result:

- 62 tests passed.

## Suggested cleanup groups

Recommended source checkpoint:

- `tmp_remote_mim/core/routers/gateway.py`
- `tmp_remote_mim/tests/integration/test_mim_tod_handoff_gateway.py`
- `tmp_remote_mim/core/mim_ui.py`
- `tmp_remote_mim/core/routers/mim_ui.py`
- `scripts/Start-TODRecoveryWatchdog.ps1`
- `docs/mim-tod-progress-checkpoint-2026-05-21.md`

Recommended separate artifact checkpoint, if artifacts should be versioned:

- `runtime_remote_training/`
- `shared_state/watchdog-repair/MIM_TOD_TASK_REQUEST.latest.json`
- `tod/data/engineering-memory.json`
- `tod/knowledge/engineering-memory/routing_decision_memory.json`

If artifacts are not intended to be committed, leave them unstaged or move them to an ignored/archive path after confirming retention policy.

## Next bounded step

Before continuing camera/microphone setup, decide whether to commit the source checkpoint separately from generated artifacts. After that, resume with the first bounded sensor task: inventory available camera/microphone devices, prove which are openable from the MIM UI/runtime context, and publish a device-status artifact instead of relying on permission claims alone.
