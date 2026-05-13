# MIM TOD Communication Soak 100 Report

Generated: 2026-05-08T05:04:07Z
Objective: MIM-TOD-COMMUNICATION-SOAK-100

## Summary

- Total requests run: 194
- Passed: 194
- Failed: 0
- Bugs found: 3
- Bugs fixed: 3

## Result Status Counts

- answered: 36
- blocked_conflicting_execution_constraint: 6
- blocked_needs_operator: 10
- duplicate_completed_replay: 6
- duplicate_replay: 6
- durable_result_preferred: 5
- failed_needs_operator: 4
- fresh_done_recovered: 10
- idempotency_conflict: 6
- inspect_only_no_edit_needed: 20
- missing_field_added_and_validated: 8
- pending_classified: 5
- succeeded: 67
- timeout_recovered: 5

## Bugs Fixed

### natural_handoff_variants_missed_tod_ui_file_validate_it
- Root cause: The natural MIM to TOD detector required narrow TOD UI wording and did not accept tod_ui.py/target file/validate it forms.
- Fix: Expanded natural TOD handoff trigger terms in core/routers/gateway.py.
- Regression: tmp_remote_mim.tests.integration.test_mim_tod_communication_soak

### inspect_first_present_state_defaulted_to_edit
- Root cause: Prior dispatcher selected bounded edit from mutating words before checking durable result evidence.
- Fix: Inspect-first phrases now default to validation, consult TOD state plus durable handoff artifacts, and emit branch result.
- Regression: tmp_remote_mim.tests.integration.test_mim_tod_handoff_gateway

### fresh_done_worklog_replayed_stale_next_move
- Root cause: Generated system-summary cards were appended without replacing old live worklog cards.
- Fix: Fresh handoff completion suppresses stale Next move/current slice/waiting cards and replaces prior generated worklog cards.
- Regression: tmp_remote_mim.tests.integration.test_mim_tod_state_consumer

## Remaining Risks

- The soak is deterministic and synthetic; it does not measure live network latency or worker contention.
- TOD internal implementation quality is simulated through handoff result contracts, not full local executor execution.
- Project-management answers are route-classified, not semantically graded by a language model.

## Summary Table

| request_id | prompt category | expected route | actual route | TOD task id | result status | MIM console status | failure reason | fix applied |
|---|---|---|---|---|---|---|---|---|
| SOAK-A-00-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-00-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-00-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-00-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-00-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-00-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-00-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-00-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-01-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-01-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-01-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-01-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-01-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-01-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-01-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-01-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-02-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-02-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-02-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-02-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-02-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-02-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-02-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-02-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-03-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-03-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-03-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-03-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-03-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-03-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-03-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-03-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-04-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-04-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-04-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-04-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-04-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-04-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-04-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-04-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-05-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-05-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-05-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-05-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-05-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-05-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-05-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-05-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-06-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-06-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-06-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-06-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-06-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-06-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-06-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-06-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-07-validation-only | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-a-07-validation-only | succeeded | fresh_done |  |  |
| SOAK-A-07-bounded-edit | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-soak-basic-state-soak-a-07-bounded-edit | succeeded | fresh_done |  |  |
| SOAK-A-07-inspect-first | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-07-inspect-first | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-A-07-no-op-present | A.Basic TOD handoff | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-a-07-no-op-present | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-B-00-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-00-00 | succeeded | fresh_done |  |  |
| SOAK-B-00-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-00-01 | succeeded | fresh_done |  |  |
| SOAK-B-00-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-00-02 | succeeded | fresh_done |  |  |
| SOAK-B-00-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-00-03 | succeeded | fresh_done |  |  |
| SOAK-B-00-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-00-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-00-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-00-05 | succeeded | fresh_done |  |  |
| SOAK-B-01-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-01-00 | succeeded | fresh_done |  |  |
| SOAK-B-01-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-01-01 | succeeded | fresh_done |  |  |
| SOAK-B-01-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-01-02 | succeeded | fresh_done |  |  |
| SOAK-B-01-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-01-03 | succeeded | fresh_done |  |  |
| SOAK-B-01-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-01-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-01-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-01-05 | succeeded | fresh_done |  |  |
| SOAK-B-02-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-02-00 | succeeded | fresh_done |  |  |
| SOAK-B-02-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-02-01 | succeeded | fresh_done |  |  |
| SOAK-B-02-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-02-02 | succeeded | fresh_done |  |  |
| SOAK-B-02-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-02-03 | succeeded | fresh_done |  |  |
| SOAK-B-02-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-02-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-02-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-02-05 | succeeded | fresh_done |  |  |
| SOAK-B-03-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-03-00 | succeeded | fresh_done |  |  |
| SOAK-B-03-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-03-01 | succeeded | fresh_done |  |  |
| SOAK-B-03-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-03-02 | succeeded | fresh_done |  |  |
| SOAK-B-03-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-03-03 | succeeded | fresh_done |  |  |
| SOAK-B-03-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-03-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-03-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-03-05 | succeeded | fresh_done |  |  |
| SOAK-B-04-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-04-00 | succeeded | fresh_done |  |  |
| SOAK-B-04-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-04-01 | succeeded | fresh_done |  |  |
| SOAK-B-04-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-04-02 | succeeded | fresh_done |  |  |
| SOAK-B-04-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-04-03 | succeeded | fresh_done |  |  |
| SOAK-B-04-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-04-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-04-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-04-05 | succeeded | fresh_done |  |  |
| SOAK-B-05-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-05-00 | succeeded | fresh_done |  |  |
| SOAK-B-05-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-05-01 | succeeded | fresh_done |  |  |
| SOAK-B-05-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-05-02 | succeeded | fresh_done |  |  |
| SOAK-B-05-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-05-03 | succeeded | fresh_done |  |  |
| SOAK-B-05-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-05-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-05-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-05-05 | succeeded | fresh_done |  |  |
| SOAK-B-06-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-06-00 | succeeded | fresh_done |  |  |
| SOAK-B-06-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-06-01 | succeeded | fresh_done |  |  |
| SOAK-B-06-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-06-02 | succeeded | fresh_done |  |  |
| SOAK-B-06-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-06-03 | succeeded | fresh_done |  |  |
| SOAK-B-06-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-06-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-06-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-06-05 | succeeded | fresh_done |  |  |
| SOAK-B-07-00 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-07-00 | succeeded | fresh_done |  |  |
| SOAK-B-07-01 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-typo-lane-state-soak-b-07-01 | succeeded | fresh_done |  |  |
| SOAK-B-07-02 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-b-07-02 | succeeded | fresh_done |  |  |
| SOAK-B-07-03 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-state-soak-b-07-03 | succeeded | fresh_done |  |  |
| SOAK-B-07-04 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-variation-present-state-soak-b-07-04 | missing_field_added_and_validated | fresh_done |  |  |
| SOAK-B-07-05 | B.Natural-language variation | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-b-07-05 | succeeded | fresh_done |  |  |
| SOAK-C-00-00 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-00-01 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-00-02 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-00-03 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-00-04 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-00-05 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-01-00 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-01-01 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-01-02 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-01-03 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-01-04 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-01-05 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-02-00 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-02-01 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-02-02 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-02-03 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-02-04 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-02-05 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-03-00 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-03-01 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-03-02 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-03-03 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-03-04 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-C-03-05 | C.Project management | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-D-00-duplicate objective | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-duplicate-state-soak-d-00-duplicate objective | duplicate_replay | fresh_done |  |  |
| SOAK-D-00-duplicate completed task | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-d-00-duplicate completed task | duplicate_completed_replay | fresh_done |  |  |
| SOAK-D-00-changed payload | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-changed-payload-state-soak-d-00-changed payload | idempotency_conflict | blocked |  |  |
| SOAK-D-00-conflict | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-conflict-state-soak-d-00-conflict | blocked_conflicting_execution_constraint | blocked |  |  |
| SOAK-D-00-unclear target | D.Conflict handling | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-D-01-duplicate objective | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-duplicate-state-soak-d-01-duplicate objective | duplicate_replay | fresh_done |  |  |
| SOAK-D-01-duplicate completed task | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-d-01-duplicate completed task | duplicate_completed_replay | fresh_done |  |  |
| SOAK-D-01-changed payload | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-changed-payload-state-soak-d-01-changed payload | idempotency_conflict | blocked |  |  |
| SOAK-D-01-conflict | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-conflict-state-soak-d-01-conflict | blocked_conflicting_execution_constraint | blocked |  |  |
| SOAK-D-01-unclear target | D.Conflict handling | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-D-02-duplicate objective | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-duplicate-state-soak-d-02-duplicate objective | duplicate_replay | fresh_done |  |  |
| SOAK-D-02-duplicate completed task | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-d-02-duplicate completed task | duplicate_completed_replay | fresh_done |  |  |
| SOAK-D-02-changed payload | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-changed-payload-state-soak-d-02-changed payload | idempotency_conflict | blocked |  |  |
| SOAK-D-02-conflict | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-conflict-state-soak-d-02-conflict | blocked_conflicting_execution_constraint | blocked |  |  |
| SOAK-D-02-unclear target | D.Conflict handling | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-D-03-duplicate objective | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-duplicate-state-soak-d-03-duplicate objective | duplicate_replay | fresh_done |  |  |
| SOAK-D-03-duplicate completed task | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-d-03-duplicate completed task | duplicate_completed_replay | fresh_done |  |  |
| SOAK-D-03-changed payload | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-changed-payload-state-soak-d-03-changed payload | idempotency_conflict | blocked |  |  |
| SOAK-D-03-conflict | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-conflict-state-soak-d-03-conflict | blocked_conflicting_execution_constraint | blocked |  |  |
| SOAK-D-03-unclear target | D.Conflict handling | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-D-04-duplicate objective | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-duplicate-state-soak-d-04-duplicate objective | duplicate_replay | fresh_done |  |  |
| SOAK-D-04-duplicate completed task | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-d-04-duplicate completed task | duplicate_completed_replay | fresh_done |  |  |
| SOAK-D-04-changed payload | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-changed-payload-state-soak-d-04-changed payload | idempotency_conflict | blocked |  |  |
| SOAK-D-04-conflict | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-conflict-state-soak-d-04-conflict | blocked_conflicting_execution_constraint | blocked |  |  |
| SOAK-D-04-unclear target | D.Conflict handling | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-D-05-duplicate objective | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-duplicate-state-soak-d-05-duplicate objective | duplicate_replay | fresh_done |  |  |
| SOAK-D-05-duplicate completed task | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-d-05-duplicate completed task | duplicate_completed_replay | fresh_done |  |  |
| SOAK-D-05-changed payload | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-changed-payload-state-soak-d-05-changed payload | idempotency_conflict | blocked |  |  |
| SOAK-D-05-conflict | D.Conflict handling | tod_handoff | tod_handoff | mim-tod-execution-conflict-state-soak-d-05-conflict | blocked_conflicting_execution_constraint | blocked |  |  |
| SOAK-D-05-unclear target | D.Conflict handling | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-E-00-delayed | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | pending_classified | classified_pending |  |  |
| SOAK-E-00-mim-stale | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-00-overwritten | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | durable_result_preferred | fresh_done |  |  |
| SOAK-E-00-timeout-524 | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | timeout_recovered | fresh_done |  |  |
| SOAK-E-00-ui-not-fresh | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-01-delayed | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | pending_classified | classified_pending |  |  |
| SOAK-E-01-mim-stale | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-01-overwritten | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | durable_result_preferred | fresh_done |  |  |
| SOAK-E-01-timeout-524 | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | timeout_recovered | fresh_done |  |  |
| SOAK-E-01-ui-not-fresh | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-02-delayed | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | pending_classified | classified_pending |  |  |
| SOAK-E-02-mim-stale | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-02-overwritten | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | durable_result_preferred | fresh_done |  |  |
| SOAK-E-02-timeout-524 | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | timeout_recovered | fresh_done |  |  |
| SOAK-E-02-ui-not-fresh | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-03-delayed | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | pending_classified | classified_pending |  |  |
| SOAK-E-03-mim-stale | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-03-overwritten | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | durable_result_preferred | fresh_done |  |  |
| SOAK-E-03-timeout-524 | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | timeout_recovered | fresh_done |  |  |
| SOAK-E-03-ui-not-fresh | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-04-delayed | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | pending_classified | classified_pending |  |  |
| SOAK-E-04-mim-stale | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-E-04-overwritten | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | durable_result_preferred | fresh_done |  |  |
| SOAK-E-04-timeout-524 | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | timeout_recovered | fresh_done |  |  |
| SOAK-E-04-ui-not-fresh | E.Stale/freeze recovery | simulated_recovery | simulated_recovery |  | fresh_done_recovered | fresh_done |  |  |
| SOAK-F-00-success | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-success-state-soak-f-00-success | succeeded | fresh_done |  |  |
| SOAK-F-00-no-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-f-00-no-edit | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-F-00-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-edit-state-soak-f-00-edit | succeeded | fresh_done |  |  |
| SOAK-F-00-blocked | F.Reporting quality | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-F-00-failed | F.Reporting quality | simulated_recovery | simulated_recovery |  | failed_needs_operator | classified_pending |  |  |
| SOAK-F-01-success | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-success-state-soak-f-01-success | succeeded | fresh_done |  |  |
| SOAK-F-01-no-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-f-01-no-edit | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-F-01-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-edit-state-soak-f-01-edit | succeeded | fresh_done |  |  |
| SOAK-F-01-blocked | F.Reporting quality | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-F-01-failed | F.Reporting quality | simulated_recovery | simulated_recovery |  | failed_needs_operator | classified_pending |  |  |
| SOAK-F-02-success | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-success-state-soak-f-02-success | succeeded | fresh_done |  |  |
| SOAK-F-02-no-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-f-02-no-edit | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-F-02-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-edit-state-soak-f-02-edit | succeeded | fresh_done |  |  |
| SOAK-F-02-blocked | F.Reporting quality | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-F-02-failed | F.Reporting quality | simulated_recovery | simulated_recovery |  | failed_needs_operator | classified_pending |  |  |
| SOAK-F-03-success | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-success-state-soak-f-03-success | succeeded | fresh_done |  |  |
| SOAK-F-03-no-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-direct-lane-health-state-soak-f-03-no-edit | inspect_only_no_edit_needed | fresh_done |  |  |
| SOAK-F-03-edit | F.Reporting quality | tod_handoff | tod_handoff | mim-tod-execution-reporting-edit-state-soak-f-03-edit | succeeded | fresh_done |  |  |
| SOAK-F-03-blocked | F.Reporting quality | blocked_needs_operator | blocked_needs_operator |  | blocked_needs_operator | blocked |  |  |
| SOAK-F-03-failed | F.Reporting quality | simulated_recovery | simulated_recovery |  | failed_needs_operator | classified_pending |  |  |
| SOAK-G-00-00 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-00-01 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-00-02 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-00-03 | G.Skill-building | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-g-00-03 | succeeded | fresh_done |  |  |
| SOAK-G-00-04 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-01-00 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-01-01 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-01-02 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-01-03 | G.Skill-building | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-g-01-03 | succeeded | fresh_done |  |  |
| SOAK-G-01-04 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-02-00 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-02-01 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-02-02 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |
| SOAK-G-02-03 | G.Skill-building | tod_handoff | tod_handoff | mim-tod-execution-mim-tod-diagnostic-state-soak-g-02-03 | succeeded | fresh_done |  |  |
| SOAK-G-02-04 | G.Skill-building | mim_answer | mim_answer |  | answered | fresh_done |  |  |

## Recommended Next 10 Challenges

1. Live 25-request MIM to TOD latency soak with bounded concurrency caps.
2. Duplicate request replay against real durable handoff artifacts.
3. Delayed TOD result recovery with UI freshness assertions.
4. Changed-payload idempotency conflict from natural language only.
5. Ambiguous target-file clarification thresholding.
6. Project-management answer quality rubric for what is blocked/what completed.
7. Cross-session handoff context preservation after browser reload.
8. MIM to TOD result overwrite race simulation with timestamp precedence.
9. Operator-facing summary compression for long task histories.
10. End-to-end safe-delegation challenge mixing answer/local/TOD routes.
