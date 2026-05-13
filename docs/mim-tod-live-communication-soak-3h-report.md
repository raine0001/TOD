# MIM TOD Live Communication Soak 3H Report

Started: 2026-05-08T18:05:01Z
Finished: 2026-05-08T18:15:32Z
Duration seconds: 631.094

## Summary

- Live requests run: 10
- Passed: 10
- Failed: 0
- Average latency ms: 62206.2
- P95 latency ms: 101485
- P95 bottleneck stage: result_consumed_to_console_fresh_done_ms
- Bugs found: 1
- Bugs fixed during run: 1

## Status Counts

- blocked: 4
- completed: 2
- done: 4

## Stage Latency Summary

| stage | count | average ms | p95 ms |
|---|---:|---:|---:|
| ack_to_execution_start_ms | 6 | 0 | 0 |
| completed_to_result_consumed_ms | 2 | 0 | 0 |
| deterministic_classifier_ms | 6 | 0 | 0 |
| execution_start_to_completed_ms | 2 | 0 | 0 |
| gateway_to_deterministic_classifier_ms | 6 | 0 | 0 |
| gateway_to_route_decided_ms | 6 | 0 | 0 |
| handoff_publish_to_ack_ms | 6 | 0 | 0 |
| intent_to_handoff_publish_ms | 6 | 0 | 0 |
| operator_to_intent_ms | 6 | 0 | 0 |
| result_consumed_to_console_fresh_done_ms | 2 | 500 | 1000 |

## Bugs Fixed

### inspect_first_live_presence_missed_target_file_evidence
- Root cause: Live inspect-first handoff checked TOD state and durable artifacts but did not inspect the requested target file, so existing execution_* fields could be treated as missing.
- Fix: core/routers/gateway.py now checks the target_file content before choosing validation-only versus bounded-edit inspect-first branch.
- Regression: tmp_remote_mim.tests.integration.test_mim_tod_handoff_gateway.test_inspect_first_uses_target_file_as_present_evidence


## Remaining Risks

- Live soak uses HTTP gateway/UI state, but does not drive a browser DOM or physical hardware.
- Bounded concurrency is not enabled unless a separate run starts parallel workers.
- Gateway or Cloudflare 524 responses can still hide request ids unless the UI poll recovers a matching fresh handoff.

## Summary Table

| timestamp | prompt | expected route | actual route | request_id | handoff_id | TOD task id | TOD status | MIM console status | UI freshness | response quality grade | stage durations ms | failure reason | fix applied |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-05-08T18:05:01Z | MIM, ask TOD to run validation-only against TARGET_FILE: core/routers/tod_ui.py and report back. | tod_handoff | tod_handoff | mim-request-adbebbd9-d1f9-412e-bc91-4b038b198a3c | mim-tod-handoff-mim-request-adbebbd9-d1f9-412e-bc91-4b038b198a3c | mim-tod-execution-mim-tod-diagnostic-state-mim-request-adbebbd9-d1f9-412e-bc91-4b038b198a3c | completed | DONE | fresh_done | pass | {'gateway_to_deterministic_classifier_ms': 0, 'deterministic_classifier_ms': 0, 'gateway_to_route_decided_ms': 0, 'operator_to_intent_ms': 0, 'intent_to_handoff_publish_ms': 0, 'handoff_publish_to_ack_ms': 0, 'ack_to_execution_start_ms': 0, 'execution_start_to_completed_ms': 0, 'completed_to_result_consumed_ms': 0, 'result_consumed_to_console_fresh_done_ms': 0} |  |  |
| 2026-05-08T18:05:02Z | MIM, ask TOD to verify whether execution_direct_lane_health_state already exists in the TOD UI state. If it already exists, TOD must not edit anything. If it is missing, TOD may add it safely and validate. Report back whether TOD inspected only or edited. | tod_handoff | tod_handoff | mim-request-58abb0da-8ffb-4329-b904-e5ec163d6d59 | mim-tod-handoff-mim-request-58abb0da-8ffb-4329-b904-e5ec163d6d59 | mim-tod-execution-direct-lane-health-state-mim-request-58abb0da-8ffb-4329-b904-e5ec163d6d59 | blocked | PENDING | no_handoff_result | pass | {'gateway_to_deterministic_classifier_ms': 0, 'deterministic_classifier_ms': 0, 'gateway_to_route_decided_ms': 0, 'operator_to_intent_ms': 0, 'intent_to_handoff_publish_ms': 0, 'handoff_publish_to_ack_ms': 0, 'ack_to_execution_start_ms': 0} |  |  |
| 2026-05-08T18:06:18Z | MIM, ask TOD to inspect whether execution_live_soak_probe_state exists in core/routers/tod_ui.py. Only if missing, add it safely and validate. | tod_handoff | tod_handoff | mim-request-4f1772f3-65f9-42db-9736-9de5290f51ec | mim-tod-handoff-mim-request-4f1772f3-65f9-42db-9736-9de5290f51ec | mim-tod-execution-live-soak-probe-state-mim-request-4f1772f3-65f9-42db-9736-9de5290f51ec | blocked | PENDING | no_handoff_result | pass | {'gateway_to_deterministic_classifier_ms': 0, 'deterministic_classifier_ms': 0, 'gateway_to_route_decided_ms': 0, 'operator_to_intent_ms': 0, 'intent_to_handoff_publish_ms': 0, 'handoff_publish_to_ack_ms': 0, 'ack_to_execution_start_ms': 0} |  |  |
| 2026-05-08T18:08:00Z | MIM, ask TOD to verify whether execution_direct_lane_health_state already exists in the TOD UI state. If already present, do not edit and report no edit needed. | tod_handoff | tod_handoff | mim-request-f3a73ea3-6e9b-4a40-8719-e893f5dc80bb | mim-tod-handoff-mim-request-f3a73ea3-6e9b-4a40-8719-e893f5dc80bb | mim-tod-execution-direct-lane-health-state-mim-request-f3a73ea3-6e9b-4a40-8719-e893f5dc80bb | blocked | PENDING | no_handoff_result | pass | {'gateway_to_deterministic_classifier_ms': 0, 'deterministic_classifier_ms': 0, 'gateway_to_route_decided_ms': 0, 'operator_to_intent_ms': 0, 'intent_to_handoff_publish_ms': 0, 'handoff_publish_to_ack_ms': 0, 'ack_to_execution_start_ms': 0} |  |  |
| 2026-05-08T18:08:12Z | MIM, ask TOD to use the same task identity but change the payload for execution_live_soak_payload_conflict_state. If that conflicts, block and report the exact reason. | tod_handoff | tod_handoff | mim-request-1bedd6d0-2c33-4931-a62f-a224546ff9c5 | mim-tod-handoff-mim-request-1bedd6d0-2c33-4931-a62f-a224546ff9c5 | mim-tod-execution-live-soak-payload-conflict-state-mim-request-1bedd6d0-2c33-4931-a62f-a224546ff9c5 | completed | DONE | fresh_done | pass | {'gateway_to_deterministic_classifier_ms': 0, 'deterministic_classifier_ms': 0, 'gateway_to_route_decided_ms': 0, 'operator_to_intent_ms': 0, 'intent_to_handoff_publish_ms': 0, 'handoff_publish_to_ack_ms': 0, 'ack_to_execution_start_ms': 0, 'execution_start_to_completed_ms': 0, 'completed_to_result_consumed_ms': 0, 'result_consumed_to_console_fresh_done_ms': 1000} |  |  |
| 2026-05-08T18:08:45Z | MIM, ask TOD to edit the thing safely, but I have not named a target file. Tell me whether clarification is required. | blocked_or_answer | mim_answer | mim-request-0e44ec8b-4539-49e9-9151-92c295836fa8 |  |  | done | DONE | fresh_done | pass | {} |  |  |
| 2026-05-08T18:09:52Z | MIM, ask TOD to check whether execution_direct_lane_health_state exists and report back; treat delayed completion as pending, not stale. | tod_handoff | tod_handoff | mim-request-3e7067ff-71fe-47a9-b817-80fb292c9d53 | mim-tod-handoff-mim-request-3e7067ff-71fe-47a9-b817-80fb292c9d53 | mim-tod-execution-direct-lane-health-state-mim-request-3e7067ff-71fe-47a9-b817-80fb292c9d53 | blocked | PENDING | no_handoff_result | pass | {'gateway_to_deterministic_classifier_ms': 0, 'deterministic_classifier_ms': 0, 'gateway_to_route_decided_ms': 0, 'operator_to_intent_ms': 0, 'intent_to_handoff_publish_ms': 0, 'handoff_publish_to_ack_ms': 0, 'ack_to_execution_start_ms': 0} |  |  |
| 2026-05-08T18:10:35Z | MIM, summarize whether the latest TOD handoff is fresh after a console reload. | mim_answer | mim_answer | mim-request-97ed3e43-d2b2-4f2a-a988-b925f3abeb68 |  |  | done | PENDING | no_handoff_result | pass | {} |  |  |
| 2026-05-08T18:12:13Z | MIM, summarize the last TOD handoff result in one operator-useful paragraph. | mim_answer | mim_answer | mim-request-072f2f0e-2638-4eb6-8f1b-087f898731f6 |  |  | done | PENDING | no_handoff_result | pass | {} |  |  |
| 2026-05-08T18:13:53Z | MIM, what did TOD complete most recently? | mim_answer | mim_answer | mim-request-4967db32-2e9f-405e-bd2b-8d839a67724e |  |  | done | PENDING | no_handoff_result | pass | {} |  |  |

## Recommended Next 10 Challenges

1. Repeat this run with browser DOM polling and screenshot assertions.
2. Run a 25-request bounded concurrency 2 soak after single-lane stays green.
3. Add live duplicate-detection assertions that compare handoff IDs across duplicate prompts.
4. Add live result-overwrite race injection on sandbox shared artifacts.
5. Add Cloudflare 524 replay using a controlled delayed TOD response.
6. Grade operator response quality with a deterministic rubric per category.
7. Add browser-visible per-stage timing badges to the MIM console.
8. Exercise cross-session reload by alternating session ids and UI state polling.
9. Separate project-management prompts from execution prompts in final UI summaries.
10. Promote a nightly 20-request safe live smoke with alert-only reporting.
