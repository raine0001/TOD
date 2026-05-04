from __future__ import annotations

import asyncio
import datetime
import importlib.util
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parent
ROUTER_PATH = REPO_ROOT / "tmp_remote_mim" / "core" / "routers" / "tod_ui.py"


def load_tod_ui_module() -> types.ModuleType:
    fastapi_module = types.ModuleType("fastapi")

    class RouterStub:
        def __init__(self, *args, **kwargs) -> None:
            pass

        def get(self, *args, **kwargs):
            def decorator(func):
                return func

            return decorator

        def post(self, *args, **kwargs):
            def decorator(func):
                return func

            return decorator

    class HTTPExceptionStub(Exception):
        def __init__(self, status_code: int = 500, detail: str = "") -> None:
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    fastapi_module.APIRouter = RouterStub
    fastapi_module.Body = lambda *args, **kwargs: None
    fastapi_module.HTTPException = HTTPExceptionStub
    fastapi_module.Query = lambda *args, **kwargs: None

    responses_module = types.ModuleType("fastapi.responses")
    responses_module.FileResponse = object
    responses_module.HTMLResponse = str

    core_module = types.ModuleType("core")
    core_config_module = types.ModuleType("core.config")
    core_config_module.PROJECT_ROOT = REPO_ROOT / "tmp_remote_mim"
    core_config_module.settings = types.SimpleNamespace(app_name="TOD")
    core_tod_execution_loop_module = types.ModuleType("core.tod_execution_loop")
    core_tod_execution_loop_module.build_execution_loop_contract_artifacts = lambda *args, **kwargs: {}
    core_tod_execution_loop_module.execute_bounded_local_inspection = lambda *args, **kwargs: {}

    sys.modules["fastapi"] = fastapi_module
    sys.modules["fastapi.responses"] = responses_module
    sys.modules["core"] = core_module
    sys.modules["core.config"] = core_config_module
    sys.modules["core.tod_execution_loop"] = core_tod_execution_loop_module

    spec = importlib.util.spec_from_file_location("test_tod_ui_module", ROUTER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load router module from {ROUTER_PATH}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TodUiStateClassificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tod_ui = load_tod_ui_module()

    def test_local_rebuilt_publish_with_ready_listener_is_aligned(self) -> None:
        integration_payload = {
            "objective_alignment": {
                "status": "in_sync",
                "aligned": True,
                "tod_current_objective": "2464",
                "mim_objective_active": "2464",
            },
            "bridge_canonical_evidence": {
                "status": "unknown",
                "failure_signals": [],
            },
            "tod_status_publish": {
                "status": "local_rebuilt",
                "consumer_status": "local_rebuild",
                "mim_mirror_status": "unknown",
                "uploaded_at": "2026-04-26T07:50:06Z",
            },
            "live_task_request": {
                "request_id": "objective-2464-task-6245-implement-bounded-work-for-handle-that-thing",
                "task_id": "objective-2464-task-6245",
                "objective_id": "objective-2464",
                "normalized_objective_id": "2464",
                "generated_at": "2026-04-20T09:06:43Z",
            },
            "listener_decision": {
                "decision_outcome": "execute",
                "reason_code": "authorized_routine_request",
                "execution_state": "ready_to_execute",
                "next_step_recommendation": "execute_now",
                "generated_at": "2026-04-26T07:58:00Z",
                "summary": "Request is aligned with authority and ready for immediate TOD execution.",
            },
            "mim_status": {
                "available": True,
                "objective_active": "2464",
            },
            "objective_authority_reset": {
                "active": False,
            },
            "mim_handshake": {
                "current_next_objective": "2464",
            },
            "training_status": {
                "state": "completed",
                "state_label": "TRAINING COMPLETE",
                "percent_complete": 100,
                "summary": "Final report and artifacts are available.",
            },
        }

        self.tod_ui._first_existing_payload = lambda *paths: (integration_payload, "integration.json")
        self.tod_ui._load_json = lambda path: {}
        self.tod_ui._load_remote_recovery_payload = lambda: ({}, "")
        self.tod_ui._load_recent_copilot_handoffs = lambda **kwargs: []

        state = self.tod_ui._build_tod_console_state()

        self.assertEqual(state["status"]["code"], "aligned")
        self.assertEqual(state["status"]["label"], "ALIGNED")
        self.assertEqual(state["quick_facts"]["publish_status"], "local rebuilt")
        self.assertEqual(state["quick_facts"]["listener_state"], "ready to execute")
        self.assertEqual(state["listener_decision"]["decision_outcome"], "execute")
        self.assertEqual(state["operator_guidance"], [])

    def test_quick_actions_expose_training_and_codex_labels(self) -> None:
        integration_payload = {
            "objective_alignment": {
                "status": "in_sync",
                "aligned": True,
                "tod_current_objective": "2464",
                "mim_objective_active": "2464",
            },
            "bridge_canonical_evidence": {
                "status": "unknown",
                "failure_signals": [],
            },
            "tod_status_publish": {
                "status": "local_rebuilt",
                "consumer_status": "local_rebuild",
                "mim_mirror_status": "unknown",
                "uploaded_at": "2026-04-26T07:50:06Z",
            },
            "listener_decision": {
                "decision_outcome": "execute",
                "reason_code": "authorized_routine_request",
                "execution_state": "ready_to_execute",
                "next_step_recommendation": "execute_now",
                "generated_at": "2026-04-26T07:58:00Z",
                "summary": "Request is aligned with authority and ready for immediate TOD execution.",
            },
            "mim_status": {
                "available": True,
                "objective_active": "2464",
            },
            "objective_authority_reset": {
                "active": False,
            },
        }

        self.tod_ui._first_existing_payload = lambda *paths: (integration_payload, "integration.json")
        self.tod_ui._load_json = lambda path: {}
        self.tod_ui._load_remote_recovery_payload = lambda: ({}, "")
        self.tod_ui._load_recent_copilot_handoffs = lambda **kwargs: []

        state = self.tod_ui._build_tod_console_state()

        quick_actions = {item["id"]: item for item in state["conversation"]["quick_actions"]}
        self.assertEqual(quick_actions["start-training"]["label"], "TOD Training")
        self.assertEqual(quick_actions["send-to-copilot"]["label"], "Send To Codex")

    def test_tod_console_includes_copy_last_reply_button(self) -> None:
        html = asyncio.run(self.tod_ui.tod_console())

        self.assertIn("Copy Last TOD Reply", html)
        self.assertIn("copyLastTodResponseButton", html)
        self.assertIn("Copied the last user action and TOD reply.", html)
        self.assertIn("lines.join('\\n')", html)

    def test_operator_chat_payload_enables_execution(self) -> None:
        state = {
            "status": {"code": "aligned", "label": "ALIGNED", "summary": "Ready."},
            "quick_facts": {
                "canonical_objective": "2464",
                "live_request_objective": "2464",
                "listener_state": "ready to execute",
                "decision_outcome": "execute",
                "training_state": "TRAINING COMPLETE",
                "training_progress": "100%",
            },
            "generated_at": "2026-04-26T10:00:00Z",
        }

        with patch.object(
            self.tod_ui,
            "_resolve_training_request",
            return_value={
                "available": True,
                "reason": "ready",
                "request_path": "E:/TOD/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
                "trigger_path": "E:/TOD/runtime/shared/MIM_TO_TOD_TRIGGER.latest.json",
                "tod_action": "start-training-runbook",
            },
        ):
            payload = self.tod_ui._build_chat_payload("copilot-operator-chat", [], state, surface="chat")

        self.assertEqual(payload["session"]["mode"], "chat")
        self.assertFalse(payload["guardrails"]["commands_blocked"])
        self.assertFalse(payload["guardrails"]["live_execution_blocked"])
        self.assertTrue(payload["guardrails"]["execution_enabled"])
        self.assertTrue(payload["capabilities"]["training_start"]["available"])
        self.assertEqual(payload["links"][2]["href"], "/mim")

    def test_chat_console_includes_direct_links_and_actions(self) -> None:
        html = asyncio.run(self.tod_ui.chat_console())

        self.assertIn("Direct Copilot And Codex Bridge", html)
        self.assertIn("/chat/ui/state", html)
        self.assertIn("/chat/ui/message", html)
        self.assertIn("/chat/ui/handoff", html)
        self.assertIn("/chat/ui/action/training", html)
        self.assertIn("Open MIM Codex Chat", html)
        self.assertIn("Start 6h Training", html)
        self.assertIn("lines.join('\\n')", html)

    def test_execution_feed_compacts_slice_and_next_validation(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "title": "Make TOD a local execution agent",
                "objective_id": "TOD-LOCAL-EXECUTION-AGENT-PHASE-1",
                "activity_label": "Working",
                "summary": (
                    "Implement the bounded local execution loop slice that patches the targeted engine file, "
                    "reruns focused validation, and republishes the execution truth without reopening broad inspection."
                ),
                "next_step": "Patch the local execution engine and rerun execute-chat-task against the same bounded request.",
                "next_validation": "execute_now",
                "phase_progress": {
                    "available": True,
                    "label": "Phase 1 progress",
                    "percent_complete": 55,
                    "next_gate": "Implementation",
                    "summary": "Phase 1 is about 55% complete. Inspection is done; implementation is the next gate.",
                },
                "stall_signal": {
                    "flagged": False,
                },
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]
        current_slice = next(item for item in contents if item.startswith("Current slice:"))
        testing_next = next(item for item in contents if item.startswith("Testing next:"))
        phase_progress = next(item for item in contents if item.startswith("Phase 1 progress:"))

        self.assertLess(len(current_slice), 170)
        self.assertTrue(current_slice.endswith("..."))
        self.assertEqual(phase_progress, "Phase 1 progress: 55% complete. Next gate: Implementation.")
        self.assertEqual(
            testing_next,
            "Testing next: Focused check after: Patch the local execution engine and rerun execute-chat-task against the same bounded request.",
        )

    def test_normalize_execution_status_reports_phase_progress_and_probable_stall(self) -> None:
        active_task = {
            "objective_id": "TOD-LOCAL-EXECUTION-AGENT-PHASE-1",
            "title": "Make TOD a local execution agent",
            "summary": "Completed bounded inspection and waiting on the next implementation slice.",
            "updated_at": "2026-04-26T10:00:00Z",
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
            "execution_contract": {
                "task_intake": {"status": "accepted"},
                "bounded_step_planner": {
                    "status": "completed",
                    "active_step": {"status": "completed"},
                },
                "command_runner": {"status": "completed"},
                "patch_writer": {"status": "pending"},
                "validator": {"status": "passed"},
                "result_publisher": {"status": "completed"},
            },
        }
        activity = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": "2026-04-26T10:00:00Z",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
        }
        validation = {
            "status": "passed",
        }
        execution_result = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": "2026-04-26T10:00:00Z",
            "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
        }

        execution = self.tod_ui._normalize_execution_status({}, active_task, activity, validation, execution_result, {})

        self.assertEqual(execution["phase_progress"]["percent_complete"], 60)
        self.assertEqual(execution["phase_progress"]["next_gate"], "Implementation")
        self.assertTrue(execution["stall_signal"]["flagged"])
        self.assertEqual(execution["activity_state"], "stalled")
        self.assertIn("Probable stall:", execution["activity_summary"])

    def test_execution_feed_includes_stall_watch_when_flagged(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "title": "Make TOD a local execution agent",
                "activity_label": "Stalled",
                "activity_summary": "Probable stall: Phase 1 is holding at 60% for about 30m without a newer execution update.",
                "phase_progress": {
                    "available": True,
                    "percent_complete": 60,
                    "next_gate": "Implementation",
                    "summary": "Phase 1 is about 60% complete. Inspection is done; implementation is the next gate.",
                },
                "stall_signal": {
                    "flagged": True,
                    "summary": "Probable stall: Phase 1 is holding at 60% for about 30m without a newer execution update.",
                },
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]

        self.assertIn(
            "Stall watch: Probable stall: Phase 1 is holding at 60% for about 30m without a newer execution update.",
            contents,
        )

    def test_normalize_execution_status_reports_implementation_gate_hold_before_hard_stall(self) -> None:
        fresh_timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        active_task = {
            "objective_id": "TOD-CONVERSATIONAL-OPERATOR-MODE-PHASE-2",
            "title": "Make TOD communicate like an execution partner",
            "summary": "Completed bounded inspection and waiting on the next implementation slice.",
            "updated_at": fresh_timestamp,
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
            "execution_contract": {
                "task_intake": {"status": "accepted"},
                "bounded_step_planner": {
                    "status": "completed",
                    "active_step": {"status": "completed"},
                },
                "command_runner": {"status": "completed"},
                "patch_writer": {"status": "pending"},
                "validator": {"status": "passed"},
                "result_publisher": {"status": "completed"},
            },
        }
        activity = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": fresh_timestamp,
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
        }
        validation = {
            "status": "passed",
        }
        execution_result = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": fresh_timestamp,
            "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
        }

        execution = self.tod_ui._normalize_execution_status({}, active_task, activity, validation, execution_result, {})

        self.assertEqual(execution["activity_state"], "waiting")
        self.assertFalse(execution["stall_signal"]["flagged"])
        self.assertEqual(execution["stall_signal"]["level"], "implementation_pending")
        self.assertIn("Held at implementation gate:", execution["stall_signal"]["summary"])
        self.assertGreater(execution["phase_progress"]["percent_complete"], 60)
        self.assertIn("rather than stale output", execution["activity_summary"])

    def test_truth_timestamp_does_not_mask_stale_execution_artifacts(self) -> None:
        stale_timestamp = "2026-04-26T10:00:00Z"
        fresh_truth_timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        active_task = {
            "objective_id": "TOD-CONVERSATIONAL-OPERATOR-MODE-PHASE-2",
            "title": "Make TOD communicate like an execution partner",
            "summary": "Completed bounded inspection and waiting on the next implementation slice.",
            "updated_at": stale_timestamp,
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
            "execution_contract": {
                "task_intake": {"status": "accepted"},
                "bounded_step_planner": {
                    "status": "completed",
                    "active_step": {"status": "completed"},
                },
                "command_runner": {"status": "completed"},
                "patch_writer": {"status": "pending"},
                "validator": {"status": "passed"},
                "result_publisher": {"status": "completed"},
            },
        }
        activity = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": stale_timestamp,
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
        }
        validation = {
            "status": "passed",
            "updated_at": stale_timestamp,
        }
        execution_result = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": stale_timestamp,
            "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
        }
        truth = {
            "generated_at": fresh_truth_timestamp,
        }

        execution = self.tod_ui._normalize_execution_status({}, active_task, activity, validation, execution_result, truth)

        self.assertEqual(execution["updated_at"], stale_timestamp)
        self.assertTrue(execution["stall_signal"]["flagged"])
        self.assertEqual(execution["activity_state"], "stalled")
        self.assertIn("Probable stall:", execution["activity_summary"])

    def test_execution_feed_includes_implementation_gate_hold_watch(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "title": "Make TOD communicate like an execution partner",
                "activity_label": "Waiting",
                "activity_summary": "Held at implementation gate: Phase 2 is at 63% until the next implementation slice starts. Fresh execution evidence landed 1m ago, so this wait is for the next implementation slice rather than stale output.",
                "phase_progress": {
                    "available": True,
                    "label": "Phase 2 progress",
                    "percent_complete": 63,
                    "next_gate": "Implementation",
                    "summary": "Phase 2 is about 63% complete within the implementation gate. Inspection is done; implementation is the next gate.",
                },
                "stall_signal": {
                    "flagged": False,
                    "level": "implementation_pending",
                    "summary": "Held at implementation gate: Phase 2 is at 63% until the next implementation slice starts. Fresh execution evidence landed 1m ago, so this wait is for the next implementation slice rather than stale output.",
                },
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]

        self.assertIn(
            "Stall watch: Held at implementation gate: Phase 2 is at 63% until the next implementation slice starts. Fresh execution evidence landed 1m ago, so this wait is for the next implementation slice rather than stale output.",
            contents,
        )

    def test_tod_console_includes_phase_progress_fact_cards(self) -> None:
        html = asyncio.run(self.tod_ui.tod_console())

        self.assertIn("factPhaseProgress", html)
        self.assertIn("factStallWatch", html)
        self.assertIn("Stall watch clear.", html)

    def test_chat_ui_message_starts_training_when_requested(self) -> None:
        state = {
            "status": {"code": "aligned", "label": "ALIGNED", "summary": "Ready."},
            "quick_facts": {
                "canonical_objective": "2464",
                "live_request_objective": "2464",
                "listener_state": "ready to execute",
                "decision_outcome": "execute",
                "training_state": "TRAINING COMPLETE",
                "training_progress": "100%",
            },
            "generated_at": "2026-04-26T10:00:00Z",
        }

        with (
            patch.object(self.tod_ui, "_build_tod_console_state", return_value=state),
            patch.object(self.tod_ui, "_load_chat_messages", return_value=[]),
            patch.object(self.tod_ui, "_save_chat_messages", return_value=None),
            patch.object(
                self.tod_ui,
                "_start_training_runbook",
                return_value={
                    "ok": True,
                    "status": "queued",
                    "generated_at": "2026-04-26T10:05:00Z",
                    "request_id": "objective-2464-task-1777200991275",
                    "objective_id": "objective-2464",
                    "details": {
                        "launcher_type": "mim_to_tod_bridge_request",
                        "tod_action": "start-training-runbook",
                    },
                },
            ),
        ):
            payload = asyncio.run(
                self.tod_ui.chat_ui_message(
                    {
                        "session_key": "copilot-operator-chat",
                        "mode": "chat",
                        "message": "start the next 6h training runbook now",
                    }
                )
            )

        self.assertEqual(payload["session"]["mode"], "chat")
        self.assertIn("Training request queued.", payload["messages"][-1]["content"])
        self.assertFalse(payload["guardrails"]["live_execution_blocked"])

    def test_start_training_runbook_queues_bridge_request_and_trigger(self) -> None:
        state = {
            "quick_facts": {
                "canonical_objective": "2464",
            },
            "objective_alignment": {
                "mim_objective_active": "2464",
            },
            "live_task_request": {
                "objective_id": "objective-2464",
            },
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            operator_root = shared_root / "tod_operator_actions"
            request_path = shared_root / "MIM_TOD_TASK_REQUEST.latest.json"
            trigger_path = shared_root / "MIM_TO_TOD_TRIGGER.latest.json"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root

                result = self.tod_ui._start_training_runbook(state)

                self.assertTrue(result["ok"])
                self.assertEqual(result["status"], "queued")
                self.assertEqual(result["objective_id"], "objective-2464")
                self.assertTrue(request_path.exists())
                self.assertTrue(trigger_path.exists())

                request_payload = json.loads(request_path.read_text(encoding="utf-8"))
                trigger_payload = json.loads(trigger_path.read_text(encoding="utf-8"))

                self.assertEqual(request_payload["tod_action"], "start-training-runbook")
                self.assertEqual(request_payload["objective_id"], "objective-2464")
                self.assertEqual(request_payload["request_id"], result["request_id"])
                self.assertEqual(trigger_payload["trigger"], result["request_id"])
                self.assertEqual(trigger_payload["artifact"], "MIM_TOD_TASK_REQUEST.latest.json")
                self.assertEqual(trigger_payload["task_id"], result["task_id"])
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root


if __name__ == "__main__":
    unittest.main()