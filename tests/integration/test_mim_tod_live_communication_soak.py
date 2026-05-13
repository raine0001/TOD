import unittest
from unittest.mock import patch

from scripts.mim_tod_live_communication_soak import (
    _stage_durations,
    _grade_response,
    _poll_ui_until_matching_fresh_done,
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
                            "stage_timestamps": {
                                "operator_request_received_at": "2026-05-08T00:00:00Z",
                                "mim_intent_classified_at": "2026-05-08T00:00:01Z",
                                "tod_handoff_published_at": "2026-05-08T00:00:02Z",
                                "tod_ack_seen_at": "2026-05-08T00:00:03Z",
                                "tod_execution_started_at": "2026-05-08T00:00:04Z",
                                "tod_execution_completed_at": "2026-05-08T00:00:07Z",
                                "tod_result_consumed_at": "2026-05-08T00:00:08Z",
                            },
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
        self.assertIn("stage_latency_summary", payload)
        self.assertIn("execution_start_to_completed_ms", payload["stage_latency_summary"])
        self.assertTrue(payload["p95_bottleneck_stage"])

    def test_stage_durations_include_console_fresh_done(self) -> None:
        durations = _stage_durations(
            {
                "operator_request_received_at": "2026-05-08T00:00:00Z",
                "gateway_received_at": "2026-05-08T00:00:00Z",
                "deterministic_classifier_started_at": "2026-05-08T00:00:00Z",
                "deterministic_classifier_completed_at": "2026-05-08T00:00:01Z",
                "route_decided_at": "2026-05-08T00:00:01Z",
                "mim_intent_classified_at": "2026-05-08T00:00:01Z",
                "tod_handoff_published_at": "2026-05-08T00:00:02Z",
                "tod_ack_seen_at": "2026-05-08T00:00:03Z",
                "tod_execution_started_at": "2026-05-08T00:00:04Z",
                "tod_execution_completed_at": "2026-05-08T00:00:07Z",
                "tod_result_consumed_at": "2026-05-08T00:00:08Z",
                "mim_console_fresh_done_at": "2026-05-08T00:00:10Z",
            }
        )

        self.assertEqual(durations["operator_to_intent_ms"], 1000)
        self.assertEqual(durations["deterministic_classifier_ms"], 1000)
        self.assertEqual(durations["gateway_to_route_decided_ms"], 1000)
        self.assertEqual(durations["execution_start_to_completed_ms"], 3000)
        self.assertEqual(durations["result_consumed_to_console_fresh_done_ms"], 2000)

    def test_poll_ui_requires_matching_fresh_done_identity(self) -> None:
        calls = [
            (
                200,
                {
                    "console_freshness_status": "fresh_done",
                    "last_handoff_id": "other-handoff",
                    "last_tod_task_id": "other-task",
                },
            ),
            (
                200,
                {
                    "console_freshness_status": "fresh_done",
                    "last_handoff_id": "handoff-1",
                    "last_tod_task_id": "task-1",
                },
            ),
        ]

        def fake_http_json(**_kwargs):
            return calls.pop(0)

        with patch("scripts.mim_tod_live_communication_soak._http_json", side_effect=fake_http_json):
            status, state, fresh_at, elapsed = _poll_ui_until_matching_fresh_done(
                base_url="https://example.test",
                username="dave",
                password="secret",
                handoff_id="handoff-1",
                task_id="task-1",
                timeout_seconds=1,
                interval_seconds=0,
            )

        self.assertEqual(status, 200)
        self.assertEqual(state["last_handoff_id"], "handoff-1")
        self.assertTrue(fresh_at)
        self.assertGreaterEqual(elapsed, 0)


if __name__ == "__main__":
    unittest.main()
