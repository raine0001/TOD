from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import probe_canonical_task_request as probe


class ProbeCanonicalTaskRequestTests(unittest.TestCase):
    def test_local_probe_orders_identity_fields_first_and_reports_stable_samples(self) -> None:
        payload = {
            "task_id": "objective-97-task-3422",
            "objective_id": "objective-97",
            "correlation_id": "obj97-task3422",
            "generated_at": "2026-04-02T15:48:29Z",
            "sequence": 381549,
            "source_service": "mim",
            "source_instance_id": "mim-primary",
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            target = Path(temp_dir) / "MIM_TOD_TASK_REQUEST.latest.json"
            target.write_text(json.dumps(payload), encoding="utf-8")

            samples = probe.collect_samples(str(target), samples=2, interval_seconds=0.0)
            result = probe.build_result(samples, mode="local", interval_seconds=0.0)

        self.assertEqual(
            list(result.keys())[:4],
            ["hostname", "whoami", "absolute_path", "realpath"],
        )
        self.assertTrue(result["stable_across_samples"])
        self.assertEqual(result["task_id"], "objective-97-task-3422")
        self.assertEqual(result["objective_id"], "objective-97")
        self.assertEqual(result["sample_count"], 2)

    def test_watchdog_self_heal_anchors_republish_to_shared_truth_task(self) -> None:
        script_path = Path(__file__).resolve().parent / "scripts" / "Start-TODRecoveryWatchdog.ps1"
        script_text = script_path.read_text(encoding="utf-8")

        self.assertIn("function Get-CanonicalTaskIdForSelfHeal", script_text)
        self.assertIn("runtime/shared/TOD_MIM_SHARED_TRUTH.latest.json", script_text)
        self.assertIn("request_id = $resolvedTaskId", script_text)
        self.assertIn("task_id = $resolvedTaskId", script_text)
        self.assertIn("correlation_id = $resolvedCorrelationId", script_text)
        self.assertIn("canonical_lane_source = 'shared_truth'", script_text)


if __name__ == "__main__":
    unittest.main()