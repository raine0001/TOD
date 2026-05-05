import importlib.util
import unittest
from datetime import datetime, timezone
from pathlib import Path


def _load_module():
    module_path = Path(__file__).resolve().parent / "scripts" / "reconcile_tod_mim_shared_truth.py"
    spec = importlib.util.spec_from_file_location("reconcile_tod_mim_shared_truth", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ReconcileSharedTruthTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.module = _load_module()
        cls.now = datetime(2026, 5, 5, 0, 20, 0, tzinfo=timezone.utc)

    def _artifacts(self, **overrides):
        base = {
            "execution_result": ({}, "execution_result.json"),
            "execution_truth": ({}, "execution_truth.json"),
            "execution_lock": ({}, "execution_lock.json"),
            "next_task_selection": ({}, "next_task_selection.json"),
            "activity_stream": ({}, "activity_stream.json"),
            "active_task": ({}, "active_task.json"),
            "validation_result": ({}, "validation_result.json"),
            "task_status_review": ({}, "task_status_review.json"),
            "decision_task": ({}, "decision_task.json"),
            "mim_context_export": ({}, "mim_context_export.json"),
            "integration_status": ({}, "integration_status.json"),
        }
        base.update(overrides)
        return base

    def test_complete_plus_mim_stale_becomes_pending_refresh(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:17:01Z",
                    "execution_state": "completed",
                    "task_id": "TSK-2208",
                    "objective_id": "2913",
                    "request_id": "TSK-2208",
                    "title": "Bounded repair",
                    "summary": "TOD completed the bounded repair with real evidence.",
                    "files_changed": ["docs/example.md"],
                    "commands_run": ["git diff -- docs/example.md"],
                    "execution_evidence": {
                        "meaningful_evidence": ["files_changed", "result_artifact"],
                        "validation_passed": True,
                    },
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "mim_status": {"is_stale": True, "objective_active": "2913", "phase": "execution"},
                },
                "integration_status.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "ACCEPTED_COMPLETE_PENDING_MIM_REFRESH")
        self.assertEqual(payload["authoritative_next_action"], "refresh MIM consumer / republish shared truth")
        self.assertTrue(payload["meaningful_evidence_present"])

    def test_complete_plus_non_authoritative_mim_blocker_becomes_pending_refresh(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:17:01Z",
                    "execution_state": "completed",
                    "task_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                    "request_id": "objective-2913-task-7144",
                    "title": "Patch token extraction",
                    "summary": "TOD completed the bounded repair with real evidence.",
                    "execution_evidence": {
                        "meaningful_evidence": ["result_artifact"],
                        "validation_passed": True,
                    },
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution", "blockers": "prod_unreachable; prod_verification_incomplete"},
                },
                "integration_status.json",
            ),
            mim_context_export=(
                {
                    "exported_at": "2026-05-05T00:18:00Z",
                    "source_of_truth": {
                        "objective_active_source": "live_task_request",
                        "manifest_source_selection_reason": "selected freshest runtime task request",
                        "formal_program_truth": {
                            "generated_at": "2026-05-05T00:17:30Z",
                            "objective": "2913",
                            "task_id": "7144",
                            "task_title": "Patch token extraction",
                            "execution_state": "executing",
                        },
                        "objective_target": {"objective": "2913", "status": "in_progress"},
                        "live_task_request_signal": {"task_id": "7144", "objective_authority_eligible": True},
                    },
                },
                "mim_context_export.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "ACCEPTED_COMPLETE_PENDING_MIM_REFRESH")
        self.assertEqual(payload["authoritative_next_action"], "refresh MIM consumer / republish shared truth")

    def test_blocked_with_reason_wins(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:17:01Z",
                    "execution_state": "blocked_with_reason",
                    "reason_code": "local_fallback_needs_target_or_scope",
                    "summary": "Need a bounded implementation target.",
                    "task_id": "TSK-2209",
                    "objective_id": "2913",
                },
                "execution_result.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "BLOCKED_WITH_REASON")
        self.assertEqual(payload["authoritative_next_action"], "address blocker")
        self.assertEqual(payload["blocker_code"], "local_fallback_needs_target_or_scope")

    def test_blocked_with_reason_for_canonical_task_keeps_exact_task_scoped_blocker(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:17:01Z",
                    "updated_at": "2026-05-05T00:17:01Z",
                    "execution_state": "blocked_with_reason",
                    "reason_code": "codex_wrapper_only_no_execution",
                    "summary": "The codex wrapper accepted the prompt but did not execute the task.",
                    "task_id": "objective-2913-task-7144",
                    "request_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution"},
                },
                "integration_status.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "BLOCKED_WITH_REASON")
        self.assertEqual(payload["objective_id"], "2913")
        self.assertEqual(payload["task_id"], "objective-2913-task-7144")
        self.assertEqual(payload["blocker_code"], "codex_wrapper_only_no_execution")

    def test_recent_activity_becomes_active(self) -> None:
        artifacts = self._artifacts(
            activity_stream=(
                {
                    "generated_at": "2026-05-05T00:18:30Z",
                    "status": "running",
                    "execution_state": "running",
                    "current_action": "Applying the current bounded patch.",
                    "objective_id": "2913",
                    "task_id": "TSK-2210",
                },
                "activity_stream.json",
            ),
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:18:35Z",
                    "execution_state": "running",
                    "summary": "TOD is actively working the bounded slice.",
                    "objective_id": "2913",
                    "task_id": "TSK-2210",
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution"},
                },
                "integration_status.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "ACTIVE")
        self.assertEqual(payload["authoritative_next_action"], "wait/check next activity deadline")

    def test_no_op_rejected_requires_replay_or_replan(self) -> None:
        artifacts = self._artifacts(
            next_task_selection=(
                {
                    "generated_at": "2026-05-05T00:18:00Z",
                    "dispatch_status": "blocked_with_reason",
                    "last_terminal_outcome": {
                        "classification": "no_op_rejected",
                        "execution_state": "no_op_rejected",
                        "reason_code": "no_meaningful_execution_evidence",
                        "summary": "Execution produced no meaningful evidence.",
                    },
                    "selected_task_id": "TSK-2211",
                    "source_objective": "2913",
                },
                "next_task_selection.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "REPLAY_OR_REPLAN_REQUIRED")
        self.assertEqual(payload["authoritative_next_action"], "forced replay or replan")

    def test_mismatch_becomes_disagreement(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:17:01Z",
                    "execution_state": "completed",
                    "task_id": "TSK-2212",
                    "objective_id": "2913",
                    "execution_evidence": {"meaningful_evidence": ["result_artifact"]},
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "mim_status": {"is_stale": False, "objective_active": "2914", "phase": "execution"},
                },
                "integration_status.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "DISAGREEMENT")
        self.assertTrue(payload["disagreement_detected"])
        self.assertEqual(payload["authoritative_next_action"], "reconcile authoritative artifact sources")

    def test_older_completed_result_does_not_override_newer_matching_blocker(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-04T23:40:00Z",
                    "updated_at": "2026-05-04T23:40:00Z",
                    "execution_state": "completed",
                    "task_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                    "summary": "TOD previously completed this slice with evidence.",
                    "execution_evidence": {"meaningful_evidence": ["result_artifact"]},
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "generated_at": "2026-05-05T00:19:00Z",
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution", "generated_at": "2026-05-05T00:19:00Z", "blockers": "prod_unreachable; prod_verification_incomplete"},
                },
                "integration_status.json",
            ),
            mim_context_export=(
                {
                    "exported_at": "2026-05-05T00:19:00Z",
                    "source_of_truth": {
                        "objective_active_source": "formal_program_truth",
                        "formal_program_truth": {
                            "generated_at": "2026-05-05T00:18:50Z",
                            "objective": "2913",
                            "task_id": "7144",
                            "task_title": "Patch token extraction",
                            "execution_state": "executing",
                        },
                        "objective_target": {"objective": "2913", "status": "in_progress"},
                    },
                },
                "mim_context_export.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "BLOCKED_WITH_REASON")
        self.assertEqual(payload["objective_id"], "2913")

    def test_fresh_matching_completed_result_overrides_older_blocker(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:19:30Z",
                    "updated_at": "2026-05-05T00:19:30Z",
                    "execution_state": "completed",
                    "task_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                    "summary": "TOD completed the active objective with real evidence.",
                    "execution_evidence": {"meaningful_evidence": ["files_changed", "result_artifact"]},
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "generated_at": "2026-05-05T00:18:00Z",
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution", "generated_at": "2026-05-05T00:18:00Z", "blockers": "prod_unreachable; prod_verification_incomplete"},
                },
                "integration_status.json",
            ),
            mim_context_export=(
                {
                    "exported_at": "2026-05-05T00:18:00Z",
                    "source_of_truth": {
                        "objective_active_source": "formal_program_truth",
                        "formal_program_truth": {
                            "generated_at": "2026-05-05T00:17:50Z",
                            "objective": "2913",
                            "task_id": "7144",
                            "task_title": "Patch token extraction",
                            "execution_state": "executing",
                        },
                        "objective_target": {"objective": "2913", "status": "in_progress"},
                    },
                },
                "mim_context_export.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "ACCEPTED_COMPLETE")
        self.assertEqual(payload["authoritative_next_action"], "refresh MIM consumer / republish shared truth")

    def test_formal_executing_objective_wins_canonical_lane_on_mismatch(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:10:00Z",
                    "updated_at": "2026-05-05T00:10:00Z",
                    "execution_state": "completed",
                    "task_id": "TSK-2208",
                    "objective_id": "1682",
                    "request_id": "TSK-2208",
                    "title": "Old completed objective",
                    "summary": "Older TOD result from a different objective.",
                    "execution_evidence": {"meaningful_evidence": ["result_artifact"]},
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "generated_at": "2026-05-05T00:19:00Z",
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution", "generated_at": "2026-05-05T00:19:00Z", "blockers": "prod_unreachable; prod_verification_incomplete"},
                },
                "integration_status.json",
            ),
            mim_context_export=(
                {
                    "exported_at": "2026-05-05T00:19:00Z",
                    "source_of_truth": {
                        "objective_active_source": "formal_program_truth",
                        "formal_program_truth": {
                            "generated_at": "2026-05-05T00:18:50Z",
                            "objective": "2913",
                            "task_id": "7144",
                            "task_title": "Patch token extraction so only the identifier value is captured.",
                            "execution_state": "executing",
                        },
                        "objective_target": {"objective": "2913", "status": "in_progress"},
                    },
                },
                "mim_context_export.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "DISAGREEMENT")
        self.assertEqual(payload["objective_id"], "1682")
        self.assertEqual(payload["task_id"], "TSK-2208")
        self.assertEqual(payload["canonical_lane_source"], "tod_execution_artifacts")

    def test_stale_completed_result_cannot_supersede_fresh_active_task(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-04T18:00:00Z",
                    "updated_at": "2026-05-04T18:00:00Z",
                    "execution_state": "completed",
                    "task_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                    "summary": "Old completed result.",
                    "execution_evidence": {"meaningful_evidence": ["result_artifact"]},
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "generated_at": "2026-05-05T00:19:00Z",
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution", "generated_at": "2026-05-05T00:19:00Z"},
                },
                "integration_status.json",
            ),
            mim_context_export=(
                {
                    "exported_at": "2026-05-05T00:19:00Z",
                    "source_of_truth": {
                        "objective_active_source": "formal_program_truth",
                        "formal_program_truth": {
                            "generated_at": "2026-05-05T00:18:50Z",
                            "objective": "2913",
                            "task_id": "7144",
                            "task_title": "Patch token extraction",
                            "execution_state": "executing",
                        },
                        "objective_target": {"objective": "2913", "status": "in_progress"},
                    },
                },
                "mim_context_export.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "ACTIVE")
        self.assertEqual(payload["objective_id"], "2913")

    def test_execution_lock_prevents_mim_task_status_override(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-05T00:10:00Z",
                    "updated_at": "2026-05-05T00:10:00Z",
                    "execution_state": "running",
                    "task_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                    "request_id": "objective-2913-task-7144",
                },
                "execution_result.json",
            ),
            execution_lock=(
                {
                    "generated_at": "2026-05-05T00:19:30Z",
                    "source": "tod-execution-lock-v1",
                    "writer": "Start-TODMimPacketListener",
                    "objective_id": "2913",
                    "task_id": "objective-2913-task-7144",
                    "request_id": "objective-2913-task-7144",
                    "correlation_id": "objective-2913-task-7144",
                },
                "execution_lock.json",
            ),
            task_status_review=(
                {
                    "generated_at": "2026-05-05T00:20:00Z",
                    "objective_id": "2913",
                    "task_id": "objective-2913-task-1777951503",
                    "request_id": "objective-2913-task-1777951503",
                    "blocking_reason_codes": ["prod_unreachable"],
                },
                "task_status_review.json",
            ),
            integration_status=(
                {
                    "generated_at": "2026-05-05T00:20:00Z",
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution"},
                },
                "integration_status.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["task_id"], "objective-2913-task-7144")
        self.assertEqual(payload["request_id"], "objective-2913-task-7144")
        self.assertEqual(payload["canonical_lane_source"], "execution_lock")
        self.assertTrue(payload["execution_lock"]["active"])
        self.assertIn("mim_execution_truth_override_rejected", payload["disagreement_reason"])

    def test_old_artifacts_become_stale(self) -> None:
        artifacts = self._artifacts(
            execution_result=(
                {
                    "generated_at": "2026-05-04T18:00:00Z",
                    "execution_state": "running",
                    "summary": "Old execution artifact.",
                    "objective_id": "2913",
                    "task_id": "TSK-2213",
                },
                "execution_result.json",
            ),
            integration_status=(
                {
                    "mim_status": {"is_stale": False, "objective_active": "2913", "phase": "execution"},
                },
                "integration_status.json",
            ),
        )

        payload = self.module.reconcile_shared_truth_payload(artifacts, now=self.now)

        self.assertEqual(payload["state"], "STALE")
        self.assertEqual(payload["authoritative_next_action"], "self-driving task selection loop")


if __name__ == "__main__":
    unittest.main()