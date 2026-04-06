# TOD-MIM Sync Handoff

Date: 2026-03-23
Audience: next TOD chat session

## Issue Summary

- User reported that TOD appears stuck on objective 75 while MIM was believed to have pushed several 80-series tasks.
- TOD-side listener, shared-state sync, and dedupe logic were inspected.
- Current evidence indicates TOD is not missing 80-series packets locally. The canonical MIM export path TOD consumes is still publishing objective 75.

## Confirmed Findings

- TOD listener is alive and polling normally.
- Listener state still shows the last processed request as `objective-75-task-3263`.
- Latest observed task and correlation also remain on objective 75.
- Current command status is `already_processed`, which is expected because the inbound request signature has not changed.
- The remote/shared export mirror under `tod/out/context-sync/ssh-shared` is internally consistent and still pinned to objective 75.
- The shared export metadata explicitly says the export truth was derived from objective-75 target metadata.
- No `objective-80` markers were found in the local mirrored inbound sync artifacts or shared-state files inspected during this session.

## Files To Read First In A New Chat

- `docs/tod_mim_sync_handoff_2026-03-23.md`
- `tod/out/context-sync/listener/listener_state.json`
- `tod/out/context-sync/ssh-shared/MIM_CONTEXT_EXPORT.latest.json`
- `tod/out/context-sync/ssh-shared/MIM_TOD_HANDSHAKE_PACKET.latest.json`
- `tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json`
- `shared_state/integration_status.json`
- `shared_state/tod_recoupling_gate_state.latest.json`

## Key Evidence Snapshot

- Listener remote root: `/home/testpilot/mim/runtime/shared`
- SSH target from `.env`: `MIM_SSH_HOST=mim`, `MIM_SSH_USER=testpilot`, `MIM_SSH_PORT=22`
- Shared export says:
  - `objective_active = 75`
  - `objective_in_flight = 75`
  - `current_next_objective = 75`
- Handshake says:
  - `current_next_objective = 75`
  - `objective_active = 75`
- Listener state says:
  - `last_processed_request_id = objective-75-task-3263`
  - `last_observed_task_id = objective-75-task-3263`
  - `last_command_status = already_processed`

## Current Diagnosis

- This does not currently look like a TOD-side listener bug.
- The most likely causes are:
  - MIM has not published 80-series work into `/home/testpilot/mim/runtime/shared`.
  - The SSH alias `mim` points to a different or stale MIM environment.
  - MIM export or handshake generation is still forcing objective 75 even if other 80-series work exists elsewhere.

## Next Checks

1. Verify on the MIM side that 80-series request/export files were actually written into `/home/testpilot/mim/runtime/shared`.
2. Verify that SSH alias `mim` resolves to the intended active MIM instance.
3. Compare any claimed 80-series task source against the canonical shared files TOD actually reads.
4. If needed, add a TOD-side warning to surface that the remote shared root is healthy but still pinned to objective 75.

## Resume Prompt

Use this in a new chat:

"Read `docs/tod_mim_sync_handoff_2026-03-23.md` first, then continue diagnosing why TOD still sees objective 75 while MIM is believed to have advanced to 80. Prioritize validating the remote shared root and SSH target before changing TOD logic."