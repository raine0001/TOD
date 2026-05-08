import unittest
from unittest.mock import patch

from scripts.mim_tod_live_communication_soak import (
    _grade_response,
    build_live_cases,
    run_live_soak,
)


class MimTodLiveCommunicationSoakTest(unittest.TestCase):
    def test_live_case_builder_covers_minimum_groups(self) -> None:
        cases = build_live_cases(30)
        categories = {case["prompt_category"] for case in cases}

        self.assertGreaterEqual(len(cases), 30)
        self.assertIn("1.Natural language TOD delegation", categories)
        self.assertIn("2.Inspect-first no-op", categories)
        self.assertIn("12.Project management", categories)

    def test_grade_response_accepts_fresh_done_handoff(self) -> None:
        grade = _grade_response(
            expected_route="tod_handoff",
            response_status=200,
            resolution={
                "tod_dispatch": {
                    "dispatch_kind": "mim_tod_executable_handoff",
                    "handoff_id": "mim-tod-handoff-test",
                    "task_id": "mim-tod-task-test",
                    "result_status": "succeeded",
                    "tod_status": "completed",
                },
                "mim_interface": {"status": "done"},
                "reply": "TOD completed the validation-only handoff and returned result handoff ok.",
            },
            ui_state={
                "console_freshness_status": "fresh_done",
                "system_activity": {"status_label": "DONE"},
            },
        )

        self.assertTrue(grade["passed"])
        self.assertEqual(grade["actual_route"], "tod_handoff")

    def test_grade_response_rejects_fresh_done_stale_display(self) -> None:
        grade = _grade_response(
            expected_route="tod_handoff",
            response_status=200,
            resolution={
                "tod_dispatch": {
                    "dispatch_kind": "mim_tod_executable_handoff",
                    "handoff_id": "mim-tod-handoff-test",
                    "task_id": "mim-tod-task-test",
                    "result_status": "succeeded",
                },
                "mim_interface": {"status": "done"},
                "reply": "TOD completed the handoff and returned a useful operator-facing summary.",
            },
            ui_state={
                "console_freshness_status": "fresh_done",
                "system_activity": {"status_label": "STALE"},
            },
        )

        self.assertFalse(grade["passed"])
        self.assertIn("fresh_done displayed stale status", grade["failure_reason"])

    def test_run_live_soak_uses_transport_and_records_latency(self) -> None:
        def fake_http_json(method, url, username, password, payload=None, timeout_seconds=120):
            if method == "POST":
                return 200, {
                    "request_id": "mim-request-test",
                    "resolution": {
                        "metadata_json": {
                            "tod_dispatch": {
                                "dispatch_kind": "mim_tod_executable_handoff",
                                "handoff_id": "mim-tod-handoff-test",
                                "task_id": "mim-tod-task-test",
                                "result_status": "succeeded",
                                "tod_status": "completed",
                            },
                            "mim_interface_reply_override": "TOD completed the requested handoff and reported a useful result.",
                        }
                    },
                }
            return 200, {
                "console_freshness_status": "fresh_done",
                "system_activity": {"status_label": "DONE"},
            }

        with patch("scripts.mim_tod_live_communication_soak._http_json", side_effect=fake_http_json):
            payload = run_live_soak(
                base_url="https://example.test",
                username="dave",
                password="secret",
                limit=2,
                delay_seconds=0,
                timeout_seconds=1,
            )

        self.assertEqual(payload["total_requests"], 2)
        self.assertEqual(payload["failed"], 0)
        self.assertGreaterEqual(payload["average_latency_ms"], 0)


if __name__ == "__main__":
    unittest.main()
