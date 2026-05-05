import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent
RECOUPLE_SCRIPT = REPO_ROOT / "scripts" / "Invoke-TODCanonicalLatestArtifactRecoupling.ps1"
RECONCILE_SCRIPT = REPO_ROOT / "scripts" / "reconcile_tod_mim_shared_truth.py"


def _load_reconcile_module():
    spec = importlib.util.spec_from_file_location("reconcile_tod_mim_shared_truth", RECONCILE_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class CanonicalLatestArtifactRecouplingTest(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        cls.reconcile_module = _load_reconcile_module()

    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp(prefix="tod-recouple-"))
        self.shared_root = self.temp_dir / "runtime" / "shared"
        self.shared_root.mkdir(parents=True, exist_ok=True)
        self.shared_state = self.temp_dir / "shared_state"
        self.shared_state.mkdir(parents=True, exist_ok=True)
        self.shared_truth_path = self.shared_root / "TOD_MIM_SHARED_TRUTH.latest.json"
        self.integration_path = self.shared_state / "integration_status.json"

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _write_json(self, path: Path, payload: dict):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def _read_json(self, path: Path):
        return json.loads(path.read_text(encoding="utf-8"))

    def _stale_artifacts(self):
        summary = (
            "Codex wrapper only accepted the packaged prompt without executing it, and the safe local "
            "fallback could not execute this task scope."
        )
        return {
            "TOD_ACTIVE_OBJECTIVE.latest.json": {
                "generated_at": "2026-05-05T01:12:59.2705113Z",
                "updated_at": "2026-05-05T01:12:59.2705113Z",
                "source": "tod.local.run-task",
                "request_id": "TSK-0891",
                "task_id": "TSK-0891",
                "objective_id": "OBJ-0631",
                "normalized_objective_id": "0631",
                "title": "Re-check execution readiness",
                "summary": summary,
                "status": "active",
                "execution_state": "blocked_with_reason",
            },
            "TOD_ACTIVE_TASK.latest.json": {
                "generated_at": "2026-05-05T01:13:13.3904356Z",
                "updated_at": "2026-05-05T01:13:13.3904356Z",
                "source": "tod.next-task-selection",
                "request_id": "tod-next-task-selection-TSK-0891-20260505011208024",
                "task_id": "TSK-0891",
                "objective_id": "OBJ-0631",
                "normalized_objective_id": "0631",
                "title": "Re-check execution readiness",
                "status": "active",
                "execution_state": "selected_for_dispatch",
            },
            "TOD_ACTIVITY_STREAM.latest.json": {
                "generated_at": "2026-05-05T01:13:13.3904356Z",
                "updated_at": "2026-05-05T01:13:13.3904356Z",
                "source": "tod.next-task-selection",
                "request_id": "tod-next-task-selection-TSK-0891-20260505011208024",
                "task_id": "TSK-0891",
                "objective_id": "OBJ-0631",
                "normalized_objective_id": "0631",
                "title": "Re-check execution readiness",
                "status": "active",
                "execution_state": "selected_for_dispatch",
            },
            "TOD_VALIDATION_RESULT.latest.json": {
                "generated_at": "2026-05-05T01:12:59.2705113Z",
                "updated_at": "2026-05-05T01:12:59.2705113Z",
                "source": "tod.local.run-task",
                "request_id": "TSK-0891",
                "task_id": "TSK-0891",
                "objective_id": "OBJ-0631",
                "normalized_objective_id": "0631",
                "title": "Re-check execution readiness",
                "summary": summary,
                "status": "blocked",
                "phase": "local_run_task",
            },
            "TOD_EXECUTION_RESULT.latest.json": {
                "generated_at": "2026-05-05T01:12:59.2705113Z",
                "updated_at": "2026-05-05T01:12:59.2705113Z",
                "source": "tod.local.run-task",
                "request_id": "TSK-0891",
                "task_id": "TSK-0891",
                "objective_id": "OBJ-0631",
                "normalized_objective_id": "0631",
                "title": "Re-check execution readiness",
                "summary": summary,
                "status": "blocked",
                "execution_state": "blocked_with_reason",
                "phase": "local_run_task",
            },
            "TOD_EXECUTION_TRUTH.latest.json": {
                "generated_at": "2026-05-05T01:12:59.2705113Z",
                "source": "tod.local.run-task",
                "summary": {
                    "execution_count": 1,
                    "latest_execution_at": "2026-05-05T01:12:59.2705113Z",
                    "objective_id": "OBJ-0631",
                    "task_id": "TSK-0891",
                    "request_id": "TSK-0891",
                    "summary": summary,
                    "reason_code": "codex_wrapper_only_no_execution",
                },
                "recent_execution_truth": [
                    {
                        "generated_at": "2026-05-05T01:12:59.2705113Z",
                        "objective_id": "OBJ-0631",
                        "task_id": "TSK-0891",
                        "request_id": "TSK-0891",
                        "execution_state": "blocked_with_reason",
                        "status": "blocked",
                        "summary": summary,
                    }
                ],
            },
            "TOD_NEXT_TASK_SELECTION.latest.json": {
                "generated_at": "2026-05-05T01:12:08.0248793Z",
                "source": "tod-next-task-selection-v1",
                "source_objective": "OBJ-0631",
                "selected_task_id": "TSK-0891",
                "reason_selected": "Selected stale task.",
                "request_id": "tod-next-task-selection-TSK-0891-20260505011208024",
                "selected_task_title": "Re-check execution readiness",
                "selected_task_scope": "Execution readiness artifact is older than policy allows.",
                "selection_kind": "same_objective_next_task",
                "expected_evidence": ["meaningful_execution_evidence"],
                "validation_plan": ["codex-wrapper execution handoff"],
            },
        }

    def _canonical_shared_truth(self):
        return {
            "generated_at": "2026-05-05T02:47:21.662337Z",
            "source": "tod-mim-shared-truth-reconciler-v1",
            "objective_id": "2913",
            "task_id": "objective-2913-task-7144",
            "request_id": "objective-2913-task-7144",
            "correlation_id": "objective-2913-task-7144",
            "task_title": "Project 3 task 2: Patch token extraction so only the identifier value is captured.",
            "phase": "execution",
            "state": "DISAGREEMENT",
            "state_reason": "objective_mismatch; task_mismatch",
            "blocker_code": "prod_unreachable",
            "blocker_detail": "prod_unreachable; prod_verification_incomplete",
            "tod_view": {
                "state": "blocked_with_reason",
                "objective_id": "0631",
                "task_id": "TSK-0891",
            },
            "mim_view": {
                "state": "blocked_with_reason",
                "reason": "prod_unreachable; prod_verification_incomplete",
                "objective_id": "2913",
                "task_id": "objective-2913-task-7144",
                "request_id": "objective-2913-task-7144",
                "task_title": "Project 3 task 2: Patch token extraction so only the identifier value is captured.",
                "phase": "execution",
                "authority_source": "formal_program_truth",
                "authoritative": True,
            },
            "disagreement_detected": True,
            "disagreement_reason": "objective_mismatch; task_mismatch",
            "authoritative_next_action": "preserve canonical MIM lane and clear stale non-matching TOD artifacts",
            "canonical_lane_source": "formal_program_truth",
        }

    def _integration_status(self):
        return {
            "generated_at": "2026-05-05T02:58:34.6988908Z",
            "compatible": True,
            "mim_status": {
                "available": True,
                "generated_at": "2026-05-05T02:58:05.948215Z",
                "is_stale": False,
                "objective_active": "2913",
                "phase": "execution",
                "blockers": "prod_unreachable; prod_verification_incomplete",
            },
            "mim_handshake": {"available": True},
        }

    def _artifact_dict_after_recoupling(self):
        artifact_names = [
            "TOD_EXECUTION_RESULT.latest.json",
            "TOD_EXECUTION_TRUTH.latest.json",
            "TOD_NEXT_TASK_SELECTION.latest.json",
            "TOD_ACTIVITY_STREAM.latest.json",
            "TOD_ACTIVE_TASK.latest.json",
            "TOD_VALIDATION_RESULT.latest.json",
        ]
        artifacts = {}
        for name in artifact_names:
            artifacts[name] = (self._read_json(self.shared_root / name), str(self.shared_root / name))
        artifacts["task_status_review"] = ({}, str(self.shared_root / "MIM_TASK_STATUS_REVIEW.latest.json"))
        artifacts["decision_task"] = ({}, str(self.shared_root / "MIM_DECISION_TASK.latest.json"))
        artifacts["mim_context_export"] = (
            {
                "exported_at": "2026-05-05T02:58:05.948215Z",
                "source_of_truth": {
                    "objective_active_source": "formal_program_truth",
                    "manifest_source_selection_reason": "selected freshest workspace/runtime manifest",
                    "formal_program_truth": {
                        "generated_at": "2026-05-05T02:58:05.948215Z",
                        "objective": "2913",
                        "task_id": "7144",
                        "task_title": "Project 3 task 2: Patch token extraction so only the identifier value is captured.",
                        "execution_state": "executing",
                    },
                    "objective_target": {"objective": "2913", "status": "in_progress"},
                },
            },
            str(self.temp_dir / "MIM_CONTEXT_EXPORT.latest.json"),
        )
        artifacts["integration_status"] = (self._integration_status(), str(self.integration_path))
        return {
            "execution_result": artifacts["TOD_EXECUTION_RESULT.latest.json"],
            "execution_truth": artifacts["TOD_EXECUTION_TRUTH.latest.json"],
            "next_task_selection": artifacts["TOD_NEXT_TASK_SELECTION.latest.json"],
            "activity_stream": artifacts["TOD_ACTIVITY_STREAM.latest.json"],
            "active_task": artifacts["TOD_ACTIVE_TASK.latest.json"],
            "validation_result": artifacts["TOD_VALIDATION_RESULT.latest.json"],
            "execution_lock": ({}, str(self.shared_root / "TOD_EXECUTION_LOCK.latest.json")),
            "task_status_review": artifacts["task_status_review"],
            "decision_task": artifacts["decision_task"],
            "mim_context_export": artifacts["mim_context_export"],
            "integration_status": artifacts["integration_status"],
        }

    def _run_recoupling(self):
        command = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(RECOUPLE_SCRIPT),
            "-SharedRoot",
            str(self.shared_root),
            "-SharedTruthPath",
            str(self.shared_truth_path),
            "-IntegrationStatusPath",
            str(self.integration_path),
            "-SkipReconcile",
            "-EmitJson",
        ]
        completed = subprocess.run(command, capture_output=True, text=True, check=True)
        return json.loads(completed.stdout)

    def test_recoupling_archives_stale_latest_and_restores_canonical_lane(self):
        for name, payload in self._stale_artifacts().items():
            self._write_json(self.shared_root / name, payload)
        self._write_json(self.shared_truth_path, self._canonical_shared_truth())
        self._write_json(self.integration_path, self._integration_status())

        result = self._run_recoupling()

        self.assertEqual(result["canonical_objective_id"], "2913")
        self.assertEqual(result["canonical_task_id"], "objective-2913-task-7144")
        self.assertEqual(result["recoupled_count"], 7)

        superseded_root = self.shared_root / "superseded"
        self.assertTrue((superseded_root / "TOD_EXECUTION_RESULT.latest.json" / "latest.superseded.json").exists())
        archived = self._read_json(superseded_root / "TOD_EXECUTION_RESULT.latest.json" / "latest.superseded.json")
        self.assertEqual(archived["previous_lane"]["objective_id"], "OBJ-0631")
        self.assertEqual(archived["canonical_lane"]["objective_id"], "2913")

        execution_result = self._read_json(self.shared_root / "TOD_EXECUTION_RESULT.latest.json")
        self.assertEqual(execution_result["objective_id"], "2913")
        self.assertEqual(execution_result["task_id"], "objective-2913-task-7144")
        self.assertEqual(execution_result["reason_code"], "canonical_latest_artifact_needs_refresh")

        next_selection = self._read_json(self.shared_root / "TOD_NEXT_TASK_SELECTION.latest.json")
        self.assertEqual(next_selection["source_objective"], "2913")
        self.assertEqual(next_selection["selected_task_id"], "objective-2913-task-7144")

        reconciled = self.reconcile_module.reconcile_shared_truth_payload(self._artifact_dict_after_recoupling())
        self._write_json(self.shared_truth_path, reconciled)

        residual = []
        for path in self.shared_root.glob("*.latest.json"):
            payload = self._read_json(path)
            text = json.dumps(payload)
            if "0631" in text:
                residual.append(path.name)
        self.assertEqual(residual, [])

        self.assertEqual(reconciled["state"], "BLOCKED_WITH_REASON")
        self.assertFalse(reconciled["disagreement_detected"])
        self.assertNotIn("objective_mismatch", reconciled["state_reason"])
        self.assertEqual(reconciled["objective_id"], "2913")
        self.assertEqual(reconciled["task_id"], "objective-2913-task-7144")

    def test_recoupling_rejects_mismatched_execution_lock(self):
        for name, payload in self._stale_artifacts().items():
            self._write_json(self.shared_root / name, payload)
        self._write_json(self.shared_truth_path, self._canonical_shared_truth())
        self._write_json(self.integration_path, self._integration_status())
        self._write_json(
            self.shared_root / "TOD_EXECUTION_LOCK.latest.json",
            {
                "generated_at": "2026-05-05T02:58:10Z",
                "source": "tod-execution-lock-v1",
                "writer": "Start-TODMimPacketListener",
                "objective_id": "2913",
                "task_id": "objective-2913-task-1777951503",
                "request_id": "objective-2913-task-1777951503",
                "correlation_id": "objective-2913-task-1777951503",
            },
        )

        command = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(RECOUPLE_SCRIPT),
            "-SharedRoot",
            str(self.shared_root),
            "-SharedTruthPath",
            str(self.shared_truth_path),
            "-IntegrationStatusPath",
            str(self.integration_path),
            "-SkipReconcile",
            "-EmitJson",
        ]

        completed = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("Execution lock task mismatch", completed.stderr)


if __name__ == "__main__":
    unittest.main()