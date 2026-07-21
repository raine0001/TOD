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
STUDIO_ROUTER_PATH = REPO_ROOT / "tmp_remote_mim" / "core" / "routers" / "studio.py"


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
    fastapi_module.Request = object

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
        self.tod_ui._load_shared_truth_payload = lambda: ({}, "")
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
        request = types.SimpleNamespace(query_params={})
        html = asyncio.run(self.tod_ui.tod_console(request))

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
        self.assertTrue(contents[0].startswith("TOD status: Working."))
        self.assertIn("Current action:", contents[0])
        self.assertIn("Last heartbeat: unknown.", contents[0])
        selected_task = next(item for item in contents if item.startswith("Action: selected_task"))
        running_test = next(item for item in contents if item.startswith("Action: running_test"))

        self.assertIn("Target: TOD-LOCAL-EXECUTION-AGENT-PHASE-1 -> Make TOD a local execution agent", selected_task)
        self.assertIn("Status: executing", selected_task)
        self.assertIn("Next: Patch the local execution engine and rerun execute-chat-task against the same bounded request.", selected_task)
        self.assertIn(
            "Target: Focused check after: Patch the local execution engine and rerun execute-chat-task against the same bounded request.",
            running_test,
        )
        self.assertIn("Status: running", running_test)

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

        self.assertEqual(execution["phase_progress"]["percent_complete"], 30)
        self.assertEqual(execution["phase_progress"]["next_gate"], "Implementation")
        self.assertFalse(execution["stall_signal"]["flagged"])
        self.assertEqual(execution["activity_state"], "blocked")
        self.assertEqual(execution["executor_binding_status"], "missing")
        self.assertIn("LocalExecutionEngine", execution["activity_summary"])

    def test_execution_feed_includes_stall_watch_when_flagged(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "title": "Make TOD a local execution agent",
                "activity_label": "Stalled",
                "activity_summary": "Probable stall: Phase 1 is holding at 30% for about 30m without a newer execution update.",
                "phase_progress": {
                    "available": True,
                    "percent_complete": 30,
                    "next_gate": "Implementation",
                    "summary": "Phase 1 is about 30% complete. Inspection is done; implementation is the next gate.",
                },
                "stall_signal": {
                    "flagged": True,
                    "summary": "Probable stall: Phase 1 is holding at 30% for about 30m without a newer execution update.",
                },
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]
        blocked = next(item for item in contents if item.startswith("Action: blocked_with_reason"))

        self.assertTrue(contents[0].startswith("TOD status: Stalled."))
        self.assertIn("Blocker: Probable stall:", contents[0])
        self.assertIn("Last heartbeat: unknown.", contents[0])
        self.assertIn("Status: blocked", blocked)
        self.assertIn(
            "Result: Probable stall: Phase 1 is holding at 30% for about 30m without a newer execution update.",
            blocked,
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
            "next_step": "Implement the execution control surface changes in the inspected TOD scripts.",
            "wait_reason": "TOD is at the implementation gate and waiting for the next execution slice.",
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

        self.assertEqual(execution["activity_state"], "blocked")
        self.assertEqual(execution["activity_label"], "Binding Required")
        self.assertEqual(execution["executor_binding_status"], "missing")
        self.assertEqual(execution["executor_binding_command"], "execute-chat-task")
        self.assertIn("LocalExecutionEngine", execution["executor_binding_target"])
        self.assertFalse(execution["stall_signal"]["flagged"])
        self.assertEqual(execution["stall_signal"]["level"], "ok")
        self.assertEqual(execution["phase_progress"]["percent_complete"], 30)
        self.assertIn("Missing local executor binding", execution["activity_summary"])

    def test_completed_local_execution_binding_is_present_not_blocked(self) -> None:
        live_task = {
            "request_id": "objective-2914-bounded-edit-materialization-repair",
            "task_id": "objective-2914-bounded-edit-materialization-repair",
            "objective_id": "objective-2914",
            "assigned_executor": "local",
            "selected_executor": "local",
            "active_engine": "local",
            "executor_binding": self.tod_ui.LOCAL_EXECUTOR_BINDING,
            "bounded_edit_mode": True,
            "task_category": "diagnostic/implementation-repair",
        }
        execution = {
            "task_id": "objective-2914-bounded-edit-materialization-repair",
            "objective_id": "objective-2914",
            "status": "completed",
            "activity_state": "complete",
            "activity_label": "Complete",
            "active_engine": "local",
            "executor_binding": self.tod_ui.LOCAL_EXECUTOR_BINDING,
        }
        planner_state = {
            "status": "queued",
            "assigned_executor": "local",
            "is_newer_than_executor": True,
        }

        binding = self.tod_ui._attempt_executor_binding_materialization(live_task, execution, planner_state)

        self.assertTrue(binding["materialized"])
        self.assertEqual(binding["status"], "present")
        self.assertEqual(binding["reason_code"], "local_executor_binding_present")
        self.assertEqual(binding["active_engine"], "local")
        self.assertEqual(binding["executor_binding"], self.tod_ui.LOCAL_EXECUTOR_BINDING)
        self.assertEqual(binding["missing_field_or_function"], "")

    def test_normalize_execution_status_only_moves_above_gate_floor_with_real_implementation_evidence(self) -> None:
        fresh_timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        active_task = {
            "objective_id": "TOD-CONVERSATIONAL-OPERATOR-MODE-PHASE-2",
            "title": "Make TOD communicate like an execution partner",
            "summary": "Implementation has started in a bounded slice.",
            "updated_at": fresh_timestamp,
            "status": "working",
            "execution_state": "running_patch",
            "next_step": "Complete the bounded implementation slice and rerun validation.",
            "wait_reason": "",
            "execution_contract": {
                "task_intake": {"status": "accepted"},
                "bounded_step_planner": {
                    "status": "completed",
                    "active_step": {"status": "completed"},
                },
                "command_runner": {"status": "running"},
                "patch_writer": {"status": "in_progress"},
                "validator": {"status": "pending"},
                "result_publisher": {"status": "pending"},
            },
        }
        activity = {
            "status": "working",
            "execution_state": "running_patch",
            "updated_at": fresh_timestamp,
        }
        validation = {
            "status": "pending",
        }
        execution_result = {
            "status": "working",
            "execution_state": "running_patch",
            "updated_at": fresh_timestamp,
            "summary": "Patched the execution loop slice.",
            "next_step": "Complete the bounded implementation slice and rerun validation.",
            "files_changed": ["tmp_remote_mim/core/tod_execution_loop.py"],
            "command_output": "patched tmp_remote_mim/core/tod_execution_loop.py",
        }

        execution = self.tod_ui._normalize_execution_status({}, active_task, activity, validation, execution_result, {})

        self.assertGreater(execution["phase_progress"]["percent_complete"], 30)
        self.assertEqual(execution["phase_progress"]["next_gate"], "Implementation")

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
            "wait_reason": "TOD is at the implementation gate and waiting for the next execution slice.",
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
            "next_step": "Implement the execution control surface changes in the inspected TOD scripts.",
            "wait_reason": "TOD is at the implementation gate and waiting for the next execution slice.",
        }
        truth = {
            "generated_at": fresh_truth_timestamp,
        }

        execution = self.tod_ui._normalize_execution_status({}, active_task, activity, validation, execution_result, truth)

        self.assertEqual(execution["updated_at"], stale_timestamp)
        self.assertTrue(execution["stall_signal"]["flagged"])
        self.assertEqual(execution["activity_state"], "stalled")
        self.assertIn("Probable stall:", execution["activity_summary"])

    def test_build_tod_console_state_clears_phase_gate_when_shared_truth_accepts_complete(self) -> None:
        stale_timestamp = "2026-04-26T10:00:00Z"
        fresh_truth_timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
        integration_payload = {
            "objective_alignment": {
                "status": "in_sync",
                "aligned": True,
                "tod_current_objective": "2913",
                "mim_objective_active": "2913",
            },
            "bridge_canonical_evidence": {
                "status": "pass",
                "failure_signals": [],
            },
            "tod_status_publish": {
                "status": "uploaded",
                "consumer_status": "remote_verified",
                "mim_mirror_status": "mirrored",
                "uploaded_at": fresh_truth_timestamp,
            },
            "live_task_request": {
                "request_id": "objective-2913-task-7144",
                "task_id": "objective-2913-task-7144",
                "objective_id": "2913",
                "normalized_objective_id": "2913",
                "generated_at": stale_timestamp,
            },
            "listener_decision": {
                "decision_outcome": "execute",
                "reason_code": "authorized_routine_request",
                "execution_state": "ready_to_execute",
                "generated_at": stale_timestamp,
                "summary": "Execution artifacts are aligned.",
            },
            "mim_status": {
                "available": True,
                "objective_active": "2913",
            },
            "objective_authority_reset": {
                "active": False,
            },
        }
        active_task_payload = {
            "objective_id": "2913",
            "task_id": "objective-2913-task-7144",
            "title": "Close the Phase 2 recovery lane",
            "summary": "Phase 1 progress 100% complete; next gate Phase 2 handoff.",
            "updated_at": stale_timestamp,
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "next_step": "Hand off Phase 2 follow-up.",
            "wait_reason": "Waiting for the Phase 2 handoff.",
            "execution_contract": {
                "task_intake": {"status": "accepted"},
                "bounded_step_planner": {
                    "status": "completed",
                    "active_step": {"status": "completed"},
                },
                "command_runner": {"status": "completed"},
                "patch_writer": {"status": "completed"},
                "validator": {"status": "passed"},
                "result_publisher": {"status": "completed"},
            },
        }
        activity_payload = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": stale_timestamp,
            "wait_reason": "Waiting for the Phase 2 handoff.",
        }
        validation_payload = {
            "status": "passed",
            "updated_at": stale_timestamp,
        }
        execution_result_payload = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": stale_timestamp,
            "next_step": "Hand off Phase 2 follow-up.",
            "wait_reason": "Waiting for the Phase 2 handoff.",
        }
        shared_truth_payload = {
            "generated_at": fresh_truth_timestamp,
            "objective_id": "2913",
            "task_id": "objective-2913-task-7144",
            "state": "ACCEPTED_COMPLETE",
            "state_reason": "Phase 2 closure is complete and accepted.",
            "meaningful_evidence_present": True,
        }

        def first_existing_payload(*paths):
            first_name = getattr(paths[0], "name", "") if paths else ""
            if first_name == "TOD_INTEGRATION_STATUS.latest.json":
                return integration_payload, "integration.json"
            if first_name == "TOD_ACTIVE_TASK.latest.json":
                return active_task_payload, "active_task.json"
            if first_name == "TOD_ACTIVITY_STREAM.latest.json":
                return activity_payload, "activity.json"
            if first_name == "TOD_VALIDATION_RESULT.latest.json":
                return validation_payload, "validation.json"
            if first_name == "TOD_EXECUTION_RESULT.latest.json":
                return execution_result_payload, "execution_result.json"
            return {}, ""

        self.tod_ui._first_existing_payload = first_existing_payload
        self.tod_ui._load_json = lambda path: {}
        self.tod_ui._load_remote_recovery_payload = lambda: ({}, "")
        self.tod_ui._load_shared_truth_payload = lambda: (shared_truth_payload, "shared_truth.json")
        self.tod_ui._load_recent_copilot_handoffs = lambda **kwargs: []

        state = self.tod_ui._build_tod_console_state()
        execution = state["execution"]

        self.assertEqual(state["status"]["code"], "accepted_complete")
        self.assertEqual(execution["activity_state"], "complete")
        self.assertEqual(execution["activity_label"], "Complete")
        self.assertFalse(execution["phase_progress"]["available"])
        self.assertEqual(execution["phase_progress"]["next_gate"], "")
        self.assertEqual(execution["activity_summary"], "Phase 2 closure is complete and accepted.")
        self.assertEqual(execution["shared_truth"]["task_id"], "objective-2913-task-7144")

    def test_build_tod_console_state_prefers_newer_execution_over_older_shared_truth_from_other_objective(self) -> None:
        shared_truth_timestamp = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=25)).isoformat()
        execution_timestamp = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=3)).isoformat()
        integration_payload = {
            "objective_alignment": {
                "status": "in_sync",
                "aligned": True,
                "tod_current_objective": "2913",
                "mim_objective_active": "2913",
            },
            "bridge_canonical_evidence": {
                "status": "pass",
                "failure_signals": [],
            },
            "tod_status_publish": {
                "status": "uploaded",
                "consumer_status": "executed",
                "mim_mirror_status": "mirrored",
                "uploaded_at": shared_truth_timestamp,
            },
            "live_task_request": {
                "request_id": "tod-operational-control-surface-phase-3-task-1777960281766",
                "task_id": "tod-operational-control-surface-phase-3-task-1777960281766",
                "objective_id": "TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3",
                "normalized_objective_id": "3",
                "generated_at": execution_timestamp,
            },
            "listener_decision": {
                "decision_outcome": "execute",
                "reason_code": "authorized_routine_request",
                "execution_state": "ready_to_execute",
                "generated_at": execution_timestamp,
                "summary": "Request is aligned with authority and ready for immediate TOD execution.",
            },
            "mim_status": {
                "available": True,
                "objective_active": "2913",
            },
            "objective_authority_reset": {
                "active": False,
            },
        }
        active_task_payload = {
            "objective_id": "TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3",
            "task_id": "tod-operational-control-surface-phase-3-task-1777960281766",
            "title": "Make the TOD UI an execution control surface.",
            "summary": "Implement the execution control surface changes in the inspected TOD scripts.",
            "updated_at": execution_timestamp,
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "next_step": "Implement the execution control surface changes in the inspected TOD scripts.",
            "wait_reason": "TOD is at the implementation gate and waiting for the next execution slice.",
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
        activity_payload = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "updated_at": execution_timestamp,
            "wait_reason": "TOD is at the implementation gate and waiting for the next execution slice.",
        }
        validation_payload = {
            "status": "passed",
            "updated_at": execution_timestamp,
        }
        execution_result_payload = {
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "phase": "workspace_inspection",
            "updated_at": execution_timestamp,
            "next_step": "Implement the execution control surface changes in the inspected TOD scripts.",
            "wait_reason": "TOD is at the implementation gate and waiting for the next execution slice.",
            "command_output": "Inspected 4 local execution-loop surfaces under E:/TOD.",
            "validation_summary": "Completed the bounded local workspace inspection.",
            "validation_checks": [{"name": "exists:tod_ui.py", "passed": True}],
            "matched_files": ["E:/TOD/tmp_remote_mim/core/routers/tod_ui.py"],
        }
        shared_truth_payload = {
            "generated_at": shared_truth_timestamp,
            "objective_id": "2913",
            "task_id": "objective-2913-task-7144",
            "state": "ACCEPTED_COMPLETE",
            "state_reason": "LocalExecutionEngine patched prompt token extraction in tmp_remote_mim/core/routers/tod_ui.py and published real execution evidence.",
            "meaningful_evidence_present": True,
        }

        def first_existing_payload(*paths):
            first_name = getattr(paths[0], "name", "") if paths else ""
            if first_name == "TOD_INTEGRATION_STATUS.latest.json":
                return integration_payload, "integration.json"
            if first_name == "TOD_ACTIVE_TASK.latest.json":
                return active_task_payload, "active_task.json"
            if first_name == "TOD_ACTIVITY_STREAM.latest.json":
                return activity_payload, "activity.json"
            if first_name == "TOD_VALIDATION_RESULT.latest.json":
                return validation_payload, "validation.json"
            if first_name == "TOD_EXECUTION_RESULT.latest.json":
                return execution_result_payload, "execution_result.json"
            return {}, ""

        self.tod_ui._first_existing_payload = first_existing_payload
        self.tod_ui._load_json = lambda path: {}
        self.tod_ui._load_remote_recovery_payload = lambda: ({}, "")
        self.tod_ui._load_shared_truth_payload = lambda: (shared_truth_payload, "shared_truth.json")
        self.tod_ui._load_recent_copilot_handoffs = lambda **kwargs: []

        state = self.tod_ui._build_tod_console_state()

        self.assertEqual(state["status"]["code"], "drifted")
        self.assertEqual(state["execution"]["objective_id"], "TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3")
        self.assertTrue(state["execution"]["phase_progress"]["available"])
        self.assertTrue(state["execution"].get("shared_truth_superseded"))
        self.assertEqual(state["quick_facts"]["live_request_objective"], "TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3")
        self.assertEqual(state["operator_evidence"]["active_objective"]["id"], "TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3")
        self.assertEqual(state["operator_evidence"]["active_task"]["id"], "tod-operational-control-surface-phase-3-task-1777960281766")
        self.assertEqual(state["operator_evidence"]["blocker_code"], "implementation_pending")
        self.assertIn("Phase 3", state["operator_evidence"]["blocker_detail"])

    def test_execution_feed_includes_implementation_gate_hold_watch(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "title": "Make TOD communicate like an execution partner",
                "activity_label": "Waiting",
                "activity_state": "waiting",
                "execution_state": "waiting_on_next_step",
                "activity_summary": "Held at implementation gate: Phase 2 is at 63% until the next implementation slice starts. Fresh execution evidence landed 1m ago, so this wait is for the next implementation slice rather than stale output.",
                "current_action": "Completed local workspace inspection and published execution evidence for the owning slice.",
                "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
                "wait_target_label": "TOD local executor",
                "phase_progress": {
                    "available": True,
                    "label": "Phase 2 progress",
                    "percent_complete": 63,
                    "next_gate": "Implementation",
                    "summary": "Phase 2 is about 63% complete within the implementation gate. Inspection is done; implementation is the next gate.",
                },
                "matched_files": [
                    "/home/testpilot/mim/core/tod_execution_loop.py",
                    "/home/testpilot/mim/core/routers/tod_ui.py",
                ],
                "stall_signal": {
                    "flagged": False,
                    "level": "implementation_pending",
                    "summary": "Held at implementation gate: Phase 2 is at 63% until the next implementation slice starts. Fresh execution evidence landed 1m ago, so this wait is for the next implementation slice rather than stale output.",
                },
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]

        created = next(item for item in contents if item.startswith("Action: task_created_from_circular_block"))
        binding_checked = next(item for item in contents if item.startswith("Action: executor_binding_checked"))
        binding_blocked = next(item for item in contents if item.startswith("Action: blocked_missing_local_executor_binding"))
        inspect = next(item for item in contents if item.startswith("Action: inspecting_file"))

        self.assertTrue(contents[0].startswith("TOD status: Waiting."))
        self.assertIn("Blocker:", contents[0])
        self.assertIn("Last heartbeat: unknown.", contents[0])
        self.assertIn("Status: created", created)
        self.assertIn("Target: Implement the next bounded execution-loop slice in the inspected surfaces and rerun the focused validation path.", created)
        self.assertIn("Status: missing", binding_checked)
        self.assertIn("Command: execute-chat-task", binding_checked)
        self.assertIn("Target: scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine", binding_blocked)
        self.assertIn("Status: blocked", binding_blocked)
        self.assertIn("Next: Implement the next bounded execution-loop slice in the inspected surfaces and rerun the focused validation path.", binding_blocked)
        self.assertIn("Target: /home/testpilot/mim/core/tod_execution_loop.py", inspect)
        self.assertIn("Status: blocked", inspect)

    def test_execution_feed_does_not_render_updated_as_standalone_card(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "updated_age": "8m ago",
                "title": "Hold the current bounded slice",
                "activity_label": "Waiting",
                "activity_state": "waiting",
                "execution_state": "waiting_on_next_step",
                "wait_reason": "TOD is waiting on a local executor retry.",
                "wait_target_label": "TOD local executor",
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]

        self.assertFalse(any(item == "Updated: 8m ago" for item in contents))
        self.assertTrue(contents[0].startswith("TOD status: Waiting."))
        self.assertIn("TOD is waiting on a local executor retry.", contents[0])
        self.assertIn("Last heartbeat: 8m ago.", contents[0])

    def test_execution_feed_structured_cards_include_action_target_and_status(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "title": "Implement the active slice",
                "task_id": "objective-14-task-79",
                "objective_id": "14",
                "activity_label": "Working",
                "activity_state": "working",
                "execution_state": "running",
                "current_action": "Edit core/tod_execution_loop.py and rerun the focused validation command.",
                "files_changed": ["/home/testpilot/mim/core/tod_execution_loop.py"],
                "command_output": "python -m unittest test_tmp_remote_mim_tod_ui_state.py",
                "next_step": "Publish the focused validation result.",
                "next_validation": "python -m unittest test_tmp_remote_mim_tod_ui_state.py",
                "validation_checks": [{"name": "test_tmp_remote_mim_tod_ui_state.py", "passed": True}],
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        system_messages = [item["content"] for item in messages if item.get("role") == "system"]

        self.assertTrue(system_messages)
        self.assertTrue(all("Action: " in item and "Target: " in item and "Status: " in item for item in system_messages))

    def test_execution_feed_idle_state_renders_clearly(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "updated_age": "2m ago",
                "activity_label": "Idle",
                "activity_state": "idle",
                "execution_state": "idle",
                "validation_summary": "Completed the last bounded local objective.",
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]
        idle_event = next(item for item in contents if item.startswith("Action: idle_no_eligible_work"))

        self.assertTrue(contents[0].startswith("TOD status: Idle."))
        self.assertIn("No eligible active work is published.", contents[0])
        self.assertIn("Last heartbeat: 2m ago.", contents[0])
        self.assertIn("Status: idle", idle_event)
        self.assertIn("Reason: No eligible work is currently selected for execution.", idle_event)
        self.assertIn("Next: Check the next eligible source.", idle_event)

    def test_execution_feed_executing_state_renders_file_command_and_test(self) -> None:
        state = {
            "generated_at": "2026-04-26T10:00:00Z",
            "execution": {
                "available": True,
                "updated_at": "2026-04-26T10:00:00Z",
                "updated_age": "12s ago",
                "title": "Patch TOD feed clarity",
                "activity_label": "Working",
                "activity_state": "working",
                "execution_state": "running",
                "current_action": "Editing core/tod_execution_loop.py and running the focused validation slice.",
                "files_changed": ["/home/testpilot/mim/core/tod_execution_loop.py"],
                "command_output": "python -m unittest test_tmp_remote_mim_tod_ui_state.TodUiStateClassificationTests",
                "next_validation": "python -m unittest test_tmp_remote_mim_tod_ui_state.TodUiStateClassificationTests",
                "validation_checks": [{"name": "focused feed slice", "passed": True}],
            },
        }

        messages = self.tod_ui._build_execution_feed_messages(state)
        contents = [item["content"] for item in messages]
        edit_event = next(item for item in contents if item.startswith("Action: editing_file"))
        command_event = next(item for item in contents if item.startswith("Action: running_command"))
        test_event = next(item for item in contents if item.startswith("Action: running_test"))

        self.assertTrue(contents[0].startswith("TOD status: Working."))
        self.assertIn("Editing core/tod execution loop.py", contents[0])
        self.assertIn("Last heartbeat: 12s ago.", contents[0])
        self.assertIn("Target: /home/testpilot/mim/core/tod_execution_loop.py", edit_event)
        self.assertIn("Status: executing", edit_event)
        self.assertIn("Result: /home/testpilot/mim/core/tod_execution_loop.py", edit_event)
        self.assertIn("Status: executing", command_event)
        self.assertIn("Result: python -m unittest test_tmp_remote_mim_tod_ui_state.TodUiStateClassificationTests", command_event)
        self.assertIn("Target: python -m unittest test_tmp_remote_mim_tod_ui_state.TodUiStateClassificationTests", test_event)
        self.assertIn("Status: running", test_event)

    def test_operator_workspace_projects_blocked_execution_without_progress_bars(self) -> None:
        state = {
            "generated_at": "2026-07-21T21:50:07Z",
            "execution": {
                "available": True,
                "updated_at": "2026-07-21T21:50:07Z",
                "activity_label": "Binding Required",
                "activity_state": "blocked",
                "execution_state": "blocked",
                "objective_id": "MIM-GROWTH-DEPENDENCY-REDUCTION-NEXT-V1",
                "task_id": "mim-growth-dependency-reduction-next-v1-mim-request-c0b004d4",
                "current_action": "Blocked execution on an explicit engine/runtime blocker and published the blocker evidence.",
                "wait_reason": "Executor binding is missing for the queued objective step.",
                "next_step": "Materialize a local executor binding and republish execute-chat-task.",
                "validation_checks": [
                    {"name": "bounded_edit_materialization", "passed": False},
                ],
            },
            "tod_status_truth": {
                "status_code": "blocked",
                "status_label": "Binding Required",
                "blocked": True,
                "current_phase": "Recover",
                "current_action": "Blocked execution on an explicit engine/runtime blocker and published the blocker evidence.",
                "blocker": "Executor binding is missing for the queued objective step.",
                "next_action": "Materialize a local executor binding and republish execute-chat-task.",
                "objective_id": "MIM-GROWTH-DEPENDENCY-REDUCTION-NEXT-V1",
                "task_id": "mim-growth-dependency-reduction-next-v1-mim-request-c0b004d4",
                "last_update_at": "2026-07-21T21:50:07Z",
                "dave_needed": "no",
            },
            "operator_actions": [
                {"id": "retry", "label": "Retry execution", "enabled": False, "disabled_reason": "Waiting for executor binding"},
                {"id": "evidence", "label": "Open evidence", "enabled": True},
            ],
        }

        workspace = self.tod_ui._build_tod_operator_workspace(state)

        self.assertEqual(workspace["schema_version"], "tod-operator-workspace-v1")
        self.assertTrue(workspace["blocked"])
        self.assertEqual(workspace["current_phase"], "Recover")
        self.assertIn("runtime blocker", workspace["working"])
        self.assertIn("executor binding", workspace["waiting"].lower())
        self.assertIn("execute-chat-task", workspace["next_action"])
        self.assertEqual(len(workspace["controls"]), 2)
        self.assertTrue(workspace["timeline"])
        self.assertNotIn("phase_progress", workspace)
        self.assertNotIn("percent_complete", json.dumps(workspace))

    def test_studio_tod_body_uses_live_execution_workspace_controls(self) -> None:
        source = STUDIO_ROUTER_PATH.read_text(encoding="utf-8")

        self.assertIn("TOD Live Execution", source)
        self.assertIn('id="todExecutionBanner"', source)
        self.assertIn('id="todControlList"', source)
        self.assertIn("tod-message-tools", source)
        self.assertIn("Create Objective", source)
        self.assertNotIn('id="todLifecycle"', source)
        self.assertNotIn("tod-phase-track", source)

    def test_tod_console_includes_phase_progress_fact_cards(self) -> None:
        request = types.SimpleNamespace(query_params={})
        html = asyncio.run(self.tod_ui.tod_console(request))

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

    def test_classify_prompt_treats_phase3_objective_request_as_task(self) -> None:
        message = (
            "OBJECTIVE_ID: TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3 TITLE: Make the TOD UI an execution control surface. "
            "MISSION: TOD UI must become useful for managing work, not just observing failure beautifully like a museum exhibit for bad software weather. "
            "REQUIRED UI FEATURES: 1. Objective cards - Start Objective - Pause - Resume - Show Plan - Show Evidence - Validate - Send To Codex - Rollback "
            "2. Live activity timeline Events: - inspect - patch - command - test - restart - verify - done - blocked "
            "3. Artifact panels - changed files - command log - validation result - rollback points - handoffs - current blocker "
            "4. Objective state persistence TOD must resume active objective after UI reload or TOD restart. "
            "5. Planner/executor split UI must show: - plan accepted - current step - step progress - validation state - result "
            "SUCCESS CRITERIA: Operator can see what TOD is doing, what evidence exists, and what action is next without guessing whether TOD understood or merely performed theater."
        )

        self.assertEqual(self.tod_ui._classify_prompt(message), "task")

    def test_load_chat_session_payload_discards_generated_only_public_progress_thread(self) -> None:
        state = {
            "status": {"code": "accepted_complete"},
            "quick_facts": {"canonical_objective": "2913"},
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            original_chat_root = self.tod_ui.TOD_CONSOLE_CHAT_ROOT
            try:
                self.tod_ui.TOD_CONSOLE_CHAT_ROOT = Path(temp_dir)
                session_key = "tod-console-public-stale"
                session_path = self.tod_ui._chat_session_path(session_key)
                session_path.parent.mkdir(parents=True, exist_ok=True)
                session_path.write_text(
                    json.dumps(
                        {
                            "session_key": session_key,
                            "updated_at": "2026-05-05T05:32:38.674201Z",
                            "state_marker": {"canonical_objective": "2913", "status_code": "accepted_complete"},
                            "messages": [
                                {"role": "tod", "content": "TOD is complete: the current task.\nLast heartbeat: 12m ago.", "created_at": "2026-05-05T05:32:38.674201Z"},
                                {"role": "system", "content": "Action: result_published\nTarget: objective-2913-task-7144\nStatus: completed\nResult: Focused validation passed.", "created_at": "2026-05-05T05:32:38.674201Z"},
                            ],
                            "pending_progress": [],
                        },
                        indent=2,
                    ),
                    encoding="utf-8",
                )

                payload = self.tod_ui._load_chat_session_payload(session_key, state)

                self.assertEqual(payload["messages"], [])
                self.assertEqual(payload["pending_progress"], [])
            finally:
                self.tod_ui.TOD_CONSOLE_CHAT_ROOT = original_chat_root

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

    def test_publish_task_execution_request_uses_canonical_task_for_correlation(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "2913",
                "task_id": "objective-2913-task-7144",
            },
            "live_task_request": {
                "request_id": "objective-2913-task-1777951503",
                "task_id": "objective-2913-task-1777951503",
                "objective_id": "objective-3",
                "normalized_objective_id": "3",
            },
            "quick_facts": {"canonical_objective": "2913"},
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                record = self.tod_ui._publish_task_execution_request(
                    "OBJECTIVE_ID: objective-2913\nTITLE: Start next task for objective-2913-task-7144\nPRIMARY OUTCOME: Publish bounded execution evidence.",
                    state,
                    "operator-actions",
                    "operator-actions",
                )

                request_payload = json.loads((shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(request_payload["request_id"], "objective-2913-task-7144")
        self.assertEqual(request_payload["task_id"], "objective-2913-task-7144")
        self.assertEqual(request_payload["correlation_id"], "objective-2913-task-7144")
        self.assertEqual(request_payload["canonical_lane_source"], "shared_truth")
        self.assertEqual(request_payload["canonical_task_id"], "objective-2913-task-7144")

    def test_publish_task_execution_request_does_not_reuse_canonical_task_for_new_prompt_objective(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "2913",
                "task_id": "objective-2913-task-7144",
            },
            "live_task_request": {
                "request_id": "objective-2913-task-1777951503",
                "task_id": "objective-2913-task-1777951503",
                "objective_id": "objective-2913",
                "normalized_objective_id": "2913",
            },
            "quick_facts": {"canonical_objective": "2913"},
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                record = self.tod_ui._publish_task_execution_request(
                    "OBJECTIVE_ID: TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3\nTITLE: Start phase 3 execution control surface work\nPRIMARY OUTCOME: Publish a new bounded execution request.",
                    state,
                    "operator-actions",
                    "operator-actions",
                )

                request_payload = json.loads((shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(request_payload["objective_id"], "TOD-OPERATIONAL-CONTROL-SURFACE-PHASE-3")
        self.assertNotEqual(request_payload["request_id"], "objective-2913-task-7144")
        self.assertNotEqual(request_payload["task_id"], "objective-2913-task-7144")
        self.assertNotEqual(request_payload["correlation_id"], "objective-2913-task-7144")
        self.assertEqual(request_payload["canonical_lane_source"], "ui_request")
        self.assertEqual(request_payload["canonical_task_id"], "")
        self.assertTrue(request_payload["request_id"].startswith("tod-operational-control-surface-phase-3-task-"))

    def test_publish_task_execution_request_preserves_direct_validation_required_fields(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "2914",
                "task_id": "objective-2914-bounded-edit-materialization-repair",
            },
            "live_task_request": {
                "request_id": "objective-2914-bounded-edit-materialization-repair",
                "task_id": "objective-2914-bounded-edit-materialization-repair",
                "objective_id": "objective-2914",
            },
            "quick_facts": {"canonical_objective": "2914"},
        }
        message = (
            "OBJECTIVE: TOD-DIRECT-EXECUTION-SMOKE-REAL TOD, this task is assigned directly to you. "
            "REQUIRED FIELDS: objective_id: objective-direct-smoke-001 "
            "task_id: objective-direct-smoke-001-validation "
            "target_file: core/routers/tod_ui.py "
            "bounded_edit_mode: true "
            "validation_only: true "
            "expected_function: tod_ui_state"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                record = self.tod_ui._publish_task_execution_request(message, state, "tod", "tod-console-public")

                request_payload = json.loads((shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(request_payload["objective_id"], "objective-direct-smoke-001")
        self.assertEqual(request_payload["task_id"], "objective-direct-smoke-001-validation")
        self.assertEqual(request_payload["request_id"], "objective-direct-smoke-001-validation")
        self.assertEqual(request_payload["target_file"], "core/routers/tod_ui.py")
        self.assertEqual(request_payload["bounded_edit_mode"], "validation_only")
        self.assertTrue(request_payload["validation_only"])
        self.assertEqual(request_payload["expected_function"], "tod_ui_state")
        self.assertEqual(request_payload["assigned_executor"], "local")
        self.assertEqual(request_payload["selected_executor"], "local")
        self.assertEqual(request_payload["active_engine"], "local")
        self.assertEqual(request_payload["executor_binding"], self.tod_ui.LOCAL_EXECUTOR_BINDING)

    def test_publish_local_execution_ack_completes_direct_validation_only_task(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "2914",
                "task_id": "objective-2914-bounded-edit-materialization-repair",
            },
            "live_task_request": {
                "request_id": "objective-2914-bounded-edit-materialization-repair",
                "task_id": "objective-2914-bounded-edit-materialization-repair",
                "objective_id": "objective-2914",
            },
            "quick_facts": {"canonical_objective": "2914"},
        }
        message = (
            "OBJECTIVE: TOD-DIRECT-EXECUTION-SMOKE-REAL "
            "REQUIRED FIELDS: objective_id: objective-direct-smoke-001 "
            "task_id: objective-direct-smoke-001-validation "
            "target_file: core/routers/tod_ui.py "
            "bounded_edit_mode: true "
            "validation_only: true "
            "expected_function: tod_ui_state"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "objective-direct-smoke-001"},
                    "active_task_payload": {"task_id": "objective-direct-smoke-001-validation"},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {
                        "task_id": "objective-direct-smoke-001-validation",
                        "objective_id": "objective-direct-smoke-001",
                    },
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(record["status"], "completed")
        self.assertEqual(execution_payload["task_id"], "objective-direct-smoke-001-validation")
        self.assertEqual(execution_payload["status"], "completed")
        self.assertEqual(execution_payload["execution_state"], "completed")
        self.assertEqual(execution_payload["executor_binding_status"], "present")
        self.assertEqual(execution_payload["active_engine"], "local")
        self.assertEqual(execution_payload["executor_binding"], self.tod_ui.LOCAL_EXECUTOR_BINDING)
        self.assertEqual(execution_payload["target_file"], "core/routers/tod_ui.py")

    def test_publish_task_execution_request_accepts_direct_bounded_edit_console_format(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "objective-direct-smoke-001",
                "task_id": "objective-direct-smoke-001-validation",
            },
            "live_task_request": {
                "request_id": "objective-direct-smoke-001-validation",
                "task_id": "objective-direct-smoke-001-validation",
                "objective_id": "objective-direct-smoke-001",
            },
            "quick_facts": {"canonical_objective": "objective-direct-smoke-001"},
        }
        message = (
            "OBJECTIVE: TOD-DIRECT-BOUNDED-EDIT-SMOKE\n\n"
            "TOD, this task is assigned directly to you.\n\n"
            "TARGET FILE:\n"
            "core/routers/tod_ui.py\n\n"
            "TASK:\n"
            "Add a single diagnostic field:\n"
            "execution_validation_mode\n\n"
            "Rules:\n"
            "- bounded_edit_mode true\n"
            "- exactly one target_file\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                record = self.tod_ui._publish_task_execution_request(message, state, "tod", "tod-console-public")

                request_payload = json.loads((shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(request_payload["objective_id"], "TOD-DIRECT-BOUNDED-EDIT-SMOKE")
        self.assertTrue(request_payload["task_id"].startswith("tod-direct-bounded-edit-smoke-task-"))
        self.assertEqual(request_payload["target_file"], "core/routers/tod_ui.py")
        self.assertEqual(request_payload["target_files"], ["core/routers/tod_ui.py"])
        self.assertIs(request_payload["bounded_edit_mode"], True)
        self.assertFalse(request_payload["validation_only"])
        self.assertEqual(request_payload["assigned_executor"], "local")
        self.assertEqual(request_payload["selected_executor"], "local")
        self.assertEqual(request_payload["active_engine"], "local")
        self.assertEqual(request_payload["executor_binding"], self.tod_ui.LOCAL_EXECUTOR_BINDING)

    def test_publish_local_execution_ack_completes_direct_bounded_edit_smoke(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "objective-direct-smoke-001",
                "task_id": "objective-direct-smoke-001-validation",
            },
            "live_task_request": {
                "request_id": "objective-direct-smoke-001-validation",
                "task_id": "objective-direct-smoke-001-validation",
                "objective_id": "objective-direct-smoke-001",
            },
            "quick_facts": {"canonical_objective": "objective-direct-smoke-001"},
        }
        message = (
            "OBJECTIVE: TOD-DIRECT-BOUNDED-EDIT-SMOKE\n\n"
            "TARGET FILE:\n"
            "core/routers/tod_ui.py\n\n"
            "TASK:\n"
            "Add a single diagnostic field:\n"
            "execution_validation_mode\n\n"
            "Rules:\n"
            "- bounded_edit_mode true\n"
            "- exactly one target_file\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-DIRECT-BOUNDED-EDIT-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(record["status"], "completed")
        self.assertEqual(execution_payload["objective_id"], "TOD-DIRECT-BOUNDED-EDIT-SMOKE")
        self.assertEqual(execution_payload["status"], "completed")
        self.assertEqual(execution_payload["execution_state"], "completed")
        self.assertEqual(execution_payload["executor_binding_status"], "present")
        self.assertEqual(execution_payload["active_engine"], "local")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_edit")
        self.assertEqual(execution_payload["target_file"], "core/routers/tod_ui.py")
        self.assertEqual(execution_payload["files_changed"], ["core/routers/tod_ui.py"])

    def test_publish_local_execution_ack_distinguishes_multistep_chain_from_prior_bounded_edit(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-DIRECT-BOUNDED-EDIT-SMOKE",
                "task_id": "tod-direct-bounded-edit-smoke-task-1778200950537",
            },
            "live_task_request": {
                "request_id": "tod-direct-bounded-edit-smoke-task-1778200950537",
                "task_id": "tod-direct-bounded-edit-smoke-task-1778200950537",
                "objective_id": "TOD-DIRECT-BOUNDED-EDIT-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-DIRECT-BOUNDED-EDIT-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-DIRECT-MULTISTEP-CHAIN-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK CHAIN: STEP 1: Add diagnostic field: execution_chain_stage "
            "STEP 2: Validate that: - execution_chain_stage exists - execution_validation_mode still exists - bounded_edit_mode remains true "
            "RULES: - exactly one target_file - bounded_edit_mode true - both steps must complete in order"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-DIRECT-MULTISTEP-CHAIN-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
                request_payload = json.loads((shared_root / "TOD_ACTIVE_TASK.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-DIRECT-MULTISTEP-CHAIN-SMOKE")
        self.assertNotEqual(execution_payload["task_id"], "tod-direct-bounded-edit-smoke-task-1778200950537")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_multistep_chain")
        self.assertEqual(execution_payload["execution_chain_stage"], "step_2_validation_completed")
        self.assertEqual(execution_payload["requested_diagnostic_fields"], ["execution_chain_stage"])
        self.assertIn("execution_chain_stage", execution_payload["summary"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_chain_stage_requested", check_names)
        self.assertIn("execution_validation_mode_preserved", check_names)
        self.assertIn("step_ordering_preserved", check_names)
        self.assertEqual(request_payload["execution_chain_stage"], "step_2_validation_completed")

    def test_publish_local_execution_ack_records_one_bounded_recovery_attempt(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-DIRECT-MULTISTEP-CHAIN-SMOKE",
                "task_id": "tod-direct-multistep-chain-smoke-task-1778201772828",
            },
            "live_task_request": {
                "request_id": "tod-direct-multistep-chain-smoke-task-1778201772828",
                "task_id": "tod-direct-multistep-chain-smoke-task-1778201772828",
                "objective_id": "TOD-DIRECT-MULTISTEP-CHAIN-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-DIRECT-MULTISTEP-CHAIN-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-DIRECT-BOUNDED-RECOVERY-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Add diagnostic field: execution_recovery_stage "
            "2. First validation must intentionally check for: execution_recovery_stage = \"validated\" "
            "3. If the field is missing or wrong, perform one bounded repair by setting: execution_recovery_stage = \"validated\" "
            "4. Re-run validation. "
            "RULES: - exactly one target_file - bounded_edit_mode true - maximum one repair attempt - no repeated repair loop"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-DIRECT-BOUNDED-RECOVERY-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-DIRECT-BOUNDED-RECOVERY-SMOKE")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_recovery")
        self.assertEqual(execution_payload["execution_recovery_stage"], "validated")
        self.assertEqual(execution_payload["repair_attempt_count"], 1)
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_recovery_stage_requested", check_names)
        self.assertIn("initial_validation_failed", check_names)
        self.assertIn("single_repair_attempt_recorded", check_names)
        self.assertIn("second_validation_passed", check_names)
        self.assertEqual(execution_payload["recovery_evidence"]["repair"]["attempt"], 1)

    def test_publish_local_execution_ack_recovers_stale_active_lane_once(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-DIRECT-BOUNDED-RECOVERY-SMOKE",
                "task_id": "tod-direct-bounded-recovery-smoke-task-1778202154077",
            },
            "live_task_request": {
                "request_id": "tod-direct-bounded-recovery-smoke-task-1778202154077",
                "task_id": "tod-direct-bounded-recovery-smoke-task-1778202154077",
                "objective_id": "TOD-DIRECT-BOUNDED-RECOVERY-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-DIRECT-BOUNDED-RECOVERY-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-STALE-ACTIVE-LANE-RECOVERY-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Publish diagnostic field: execution_lane_health "
            "2. Simulate a stale active lane by creating: execution_lane_health = \"stale_detected\" "
            "3. TOD must: - record stale detection - clear only the stale lane state - preserve objective identity "
            "- preserve bounded target_file - preserve execution history - reopen execution as: execution_lane_health = \"recovered\" "
            "4. Re-run validation. "
            "RULES: - exactly one target_file - bounded_edit_mode true - no duplicate task creation - preserve execution history"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-STALE-ACTIVE-LANE-RECOVERY-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-STALE-ACTIVE-LANE-RECOVERY-SMOKE")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_stale_lane_recovery")
        self.assertEqual(execution_payload["execution_lane_health"], "recovered")
        self.assertEqual(execution_payload["stale_lane_clear_count"], 1)
        self.assertEqual(execution_payload["requested_diagnostic_fields"], ["execution_lane_health"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_lane_health_requested", check_names)
        self.assertIn("stale_detected_recorded", check_names)
        self.assertIn("stale_lane_cleared_once", check_names)
        self.assertIn("recovered_state_recorded", check_names)
        self.assertIn("execution_history_preserved", check_names)
        self.assertEqual(execution_payload["lane_recovery_evidence"]["stale_lane_clear"]["count"], 1)

    def test_publish_local_execution_ack_blocks_idempotency_conflict_payload_change(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-STALE-ACTIVE-LANE-RECOVERY-SMOKE",
                "task_id": "tod-stale-active-lane-recovery-smoke-task-1778202423496",
            },
            "live_task_request": {
                "request_id": "tod-stale-active-lane-recovery-smoke-task-1778202423496",
                "task_id": "tod-stale-active-lane-recovery-smoke-task-1778202423496",
                "objective_id": "TOD-STALE-ACTIVE-LANE-RECOVERY-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-STALE-ACTIVE-LANE-RECOVERY-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-IDEMPOTENCY-CONFLICT-SMOKE TOD, this task is assigned directly to you. "
            "GOAL: Prove TOD blocks same-objective duplicate requests when the payload changes. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: Publish diagnostic field: execution_idempotency_conflict_state "
            "RULES: - exactly one target_file - bounded_edit_mode true "
            "ACCEPTANCE: - changed duplicate payload is blocked - no duplicate execution"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-IDEMPOTENCY-CONFLICT-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(record["status"], "blocked")
        self.assertEqual(execution_payload["objective_id"], "TOD-IDEMPOTENCY-CONFLICT-SMOKE")
        self.assertEqual(execution_payload["status"], "blocked")
        self.assertEqual(execution_payload["execution_state"], "idempotency_conflict")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_idempotency_conflict")
        self.assertEqual(execution_payload["execution_idempotency_conflict_state"], "blocked_payload_changed")
        self.assertEqual(execution_payload["reason_code"], "idempotency_conflict")
        self.assertEqual(execution_payload["files_changed"], [])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_idempotency_conflict_state_requested", check_names)
        self.assertIn("duplicate_payload_changed_detected", check_names)
        self.assertIn("idempotency_conflict_blocked", check_names)
        self.assertIn("no_duplicate_execution_started", check_names)
        self.assertFalse(execution_payload["idempotency_evidence"]["new_execution_started"])
        normalized = self.tod_ui._normalize_execution_status({}, execution_payload, {}, {"status": "passed"}, execution_payload, {})
        self.assertEqual(normalized["reason_code"], "idempotency_conflict")

    def test_publish_local_execution_ack_persists_partial_completion_resume_state(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-IDEMPOTENCY-CONFLICT-SMOKE",
                "task_id": "tod-idempotency-conflict-smoke-task-1778202862120",
            },
            "live_task_request": {
                "request_id": "tod-idempotency-conflict-smoke-task-1778202862120",
                "task_id": "tod-idempotency-conflict-smoke-task-1778202862120",
                "objective_id": "TOD-IDEMPOTENCY-CONFLICT-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-IDEMPOTENCY-CONFLICT-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-PARTIAL-COMPLETION-PERSISTENCE-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: Publish diagnostic contract: execution_partial_persistence_state "
            "STEP PLAN: 1. step_prepare: record execution_partial_persistence_state = \"prepare_complete\" "
            "2. simulate_interruption: preserve objective_id, task_id, target_file, completed_steps, and payload_hash "
            "3. resume: do not rerun step_prepare "
            "4. step_validate: record execution_partial_persistence_state = \"validation_complete\" "
            "RULES: - exactly one target_file - bounded_edit_mode true - no duplicate task creation"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-PARTIAL-COMPLETION-PERSISTENCE-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-PARTIAL-COMPLETION-PERSISTENCE-SMOKE")
        self.assertEqual(execution_payload["status"], "completed")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_partial_persistence")
        self.assertEqual(execution_payload["execution_partial_persistence_state"], "validation_complete")
        self.assertEqual(execution_payload["completed_steps"], ["step_prepare", "step_validate"])
        self.assertFalse(execution_payload["partial_persistence_evidence"]["step_prepare"]["rerun_after_resume"])
        self.assertFalse(execution_payload["partial_persistence_evidence"]["resume"]["reran_completed_steps"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_partial_persistence_state_requested", check_names)
        self.assertIn("prepare_complete_recorded", check_names)
        self.assertIn("interruption_recorded", check_names)
        self.assertIn("resume_identity_preserved", check_names)
        self.assertIn("completed_steps_includes_step_prepare", check_names)
        self.assertIn("step_prepare_not_rerun_after_resume", check_names)
        self.assertIn("validation_complete_recorded", check_names)

    def test_extract_requested_diagnostic_fields_accepts_variance_terms_without_validation_mentions(self) -> None:
        message = (
            "TASK: Emit diagnostic signal: execution_variance_signal "
            "STEP 1: create diagnostic marker: execution_variance_marker "
            "STEP 2: set: execution_variance_state = \"ready\" "
            "STEP 3: Validate that execution_validation_mode still exists "
            "STEP 4: reopen execution as: execution_variance_resume = \"done\" "
            "STEP 5: persist diagnostic value: execution_variance_value"
        )

        fields = self.tod_ui._extract_requested_diagnostic_fields(message)

        self.assertEqual(
            fields,
            [
                "execution_variance_signal",
                "execution_variance_marker",
                "execution_variance_value",
                "execution_variance_state",
                "execution_variance_resume",
            ],
        )
        self.assertNotIn("execution_validation_mode", fields)

    def test_extract_requested_diagnostic_fields_handles_hundreds_of_wording_variants(self) -> None:
        verbs = ("add", "publish", "record", "set", "create", "write", "emit", "expose", "persist", "materialize")
        articles = ("", " a", " the", " a single")
        nouns = ("field", "contract", "state", "signal", "marker", "flag", "value")
        cases: list[tuple[str, str]] = []
        index = 0
        for verb in verbs:
            for article in articles:
                for noun in nouns:
                    field = f"execution_matrix_{index}_state"
                    cases.append((f"TASK: {verb}{article} diagnostic {noun}: {field}", field))
                    index += 1
        for verb in verbs:
            field = f"execution_direct_{verb}_state"
            cases.append((f"TASK: {verb} {field}", field))
        for verb in verbs:
            field = f"execution_assignment_{verb}_state"
            cases.append((f"STEP 2: {verb}: {field} = \"ready\"", field))
        for verb in verbs:
            field = f"execution_step_{verb}_state"
            cases.append((f"STEP 3: {verb} diagnostic marker: {field}", field))
        cases.append(("TASK: reopen execution as: execution_reopen_state = \"done\"", "execution_reopen_state"))

        self.assertGreaterEqual(len(cases), 300)
        for message, expected_field in cases:
            with self.subTest(message=message):
                self.assertEqual(self.tod_ui._extract_requested_diagnostic_fields(message), [expected_field])

    def test_extract_requested_diagnostic_fields_ignores_passive_validation_mentions(self) -> None:
        passive_messages = (
            "Validate that execution_validation_mode still exists.",
            "Confirm execution_chain_stage exists before continuing.",
            "Check execution_lane_health remains recovered.",
            "Expected result includes execution_recovery_stage in prior evidence.",
            "Acceptance: execution_branch_state should be visible after the branch transition.",
            "Explicitly do not publish execution_forbidden_state.",
            "Validate that execution_forbidden_state does not exist.",
        )

        for message in passive_messages:
            with self.subTest(message=message):
                self.assertEqual(self.tod_ui._extract_requested_diagnostic_fields(message), [])

    def test_extract_forbidden_diagnostic_fields_captures_negative_constraints(self) -> None:
        message = (
            "TASK: Publish execution_negative_constraint_state. "
            "Explicitly do not publish execution_forbidden_state. "
            "Never set execution_blocked_marker. "
            "Validate that execution_absent_state does not exist."
        )

        self.assertEqual(
            self.tod_ui._extract_requested_diagnostic_fields(message),
            ["execution_negative_constraint_state"],
        )
        self.assertEqual(
            self.tod_ui._extract_forbidden_diagnostic_fields(message),
            ["execution_forbidden_state", "execution_blocked_marker", "execution_absent_state"],
        )

    def test_publish_local_execution_ack_blocks_conflicting_request_and_prohibition(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-NEGATIVE-CONSTRAINT-SMOKE",
                "task_id": "tod-negative-constraint-smoke-task-1778204611889",
            },
            "live_task_request": {
                "request_id": "tod-negative-constraint-smoke-task-1778204611889",
                "task_id": "tod-negative-constraint-smoke-task-1778204611889",
                "objective_id": "TOD-NEGATIVE-CONSTRAINT-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-NEGATIVE-CONSTRAINT-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-CONFLICTING-REQUEST-PROHIBITION-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Publish execution_conflicting_constraint_state. "
            "2. Do not publish execution_conflicting_constraint_state. "
            "RULES: - exactly one target_file - bounded_edit_mode true - conflicting request/prohibition must block execution"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-CONFLICTING-REQUEST-PROHIBITION-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(record["status"], "blocked")
        self.assertEqual(execution_payload["status"], "blocked")
        self.assertEqual(execution_payload["execution_state"], "conflicting_execution_constraint")
        self.assertEqual(execution_payload["reason_code"], "blocked_conflicting_execution_constraint")
        self.assertEqual(execution_payload["requested_diagnostic_fields"], ["execution_conflicting_constraint_state"])
        self.assertEqual(execution_payload["forbidden_diagnostic_fields"], ["execution_conflicting_constraint_state"])
        self.assertEqual(execution_payload["conflicting_diagnostic_fields"], ["execution_conflicting_constraint_state"])
        self.assertEqual(execution_payload["files_changed"], [])
        self.assertTrue(execution_payload["conflict_evidence"]["local_executor_edit_suppressed"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("conflicting_execution_constraint_detected", check_names)
        self.assertIn("requested_and_forbidden_sets_intersect", check_names)
        self.assertIn("local_executor_edit_suppressed", check_names)
        self.assertIn("blocked_conflicting_execution_constraint", check_names)

    def test_publish_local_execution_ack_handles_semantic_contract_matrix(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-CONTRACT-MATRIX-BASELINE",
                "task_id": "tod-contract-matrix-baseline-task",
            },
            "live_task_request": {
                "request_id": "tod-contract-matrix-baseline-task",
                "task_id": "tod-contract-matrix-baseline-task",
                "objective_id": "TOD-CONTRACT-MATRIX-BASELINE",
            },
            "quick_facts": {"canonical_objective": "TOD-CONTRACT-MATRIX-BASELINE"},
        }
        cases = (
            (
                "TOD-MATRIX-BOUNDED-EDIT",
                "TASK: emit diagnostic signal: execution_matrix_generic_state",
                "bounded_edit",
                {"execution_matrix_generic_state_requested"},
                "completed",
            ),
            (
                "TOD-MATRIX-RECOVERY",
                "TASK: record diagnostic state: execution_recovery_stage",
                "bounded_recovery",
                {"initial_validation_failed", "single_repair_attempt_recorded", "second_validation_passed"},
                "completed",
            ),
            (
                "TOD-MATRIX-STALE-LANE",
                "TASK: set execution_lane_health = \"stale_detected\"",
                "bounded_stale_lane_recovery",
                {"stale_detected_recorded", "stale_lane_cleared_once", "recovered_state_recorded"},
                "completed",
            ),
            (
                "TOD-MATRIX-IDEMPOTENCY",
                "TASK: publish diagnostic contract: execution_idempotency_conflict_state",
                "bounded_idempotency_conflict",
                {"duplicate_payload_changed_detected", "idempotency_conflict_blocked", "no_duplicate_execution_started"},
                "blocked",
            ),
            (
                "TOD-MATRIX-PARTIAL-PERSISTENCE",
                "TASK: persist diagnostic value: execution_partial_persistence_state",
                "bounded_partial_persistence",
                {"prepare_complete_recorded", "step_prepare_not_rerun_after_resume", "validation_complete_recorded"},
                "completed",
            ),
            (
                "TOD-MATRIX-BRANCH-SELECTION",
                "TASK: publish execution_branch_state",
                "bounded_branch_selection",
                {"initial_branch_selection_recorded", "repair_branch_executed_once", "branch_transition_recorded"},
                "completed",
            ),
            (
                "TOD-MATRIX-NEGATIVE-CONSTRAINT",
                "TASK: publish execution_negative_constraint_state; do not publish execution_forbidden_state",
                "bounded_negative_constraint",
                {"execution_negative_constraint_state_requested", "execution_forbidden_state_not_published", "negative_constraint_recorded"},
                "completed",
            ),
            (
                "TOD-MATRIX-CONDITIONAL-CONSTRAINT",
                "TASK: publish execution_conditional_constraint_state; do not publish execution_conditional_blocked_state if execution_conditional_constraint_state is missing",
                "bounded_conditional_constraint",
                {"execution_conditional_constraint_state_requested", "condition_evaluated", "condition_false_after_repair", "execution_conditional_blocked_state_not_published"},
                "completed",
            ),
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                for objective, task_text, expected_mode, expected_checks, expected_status in cases:
                    with self.subTest(objective=objective):
                        artifact_fixture = {
                            "active_objective_payload": {"objective_id": objective},
                            "active_task_payload": {},
                            "activity_event": {},
                            "validation_payload": {},
                            "execution_result_payload": {},
                            "execution_truth_payload": {},
                        }
                        message = (
                            f"OBJECTIVE: {objective} TARGET FILE: core/routers/tod_ui.py "
                            f"{task_text} RULES: exactly one target_file; bounded_edit_mode true"
                        )
                        with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                            record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")
                        execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
                        self.assertTrue(record["ok"])
                        self.assertEqual(execution_payload["status"], expected_status)
                        self.assertEqual(execution_payload["execution_validation_mode"], expected_mode)
                        check_names = {item["name"] for item in execution_payload["validation_checks"]}
                        self.assertTrue(expected_checks.issubset(check_names))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

    def test_publish_local_execution_ack_completes_contract_language_normalization_without_explicit_target(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-PARTIAL-COMPLETION-PERSISTENCE-SMOKE",
                "task_id": "tod-partial-completion-persistence-smoke-task-1778203342379",
            },
            "live_task_request": {
                "request_id": "tod-partial-completion-persistence-smoke-task-1778203342379",
                "task_id": "tod-partial-completion-persistence-smoke-task-1778203342379",
                "objective_id": "TOD-PARTIAL-COMPLETION-PERSISTENCE-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-PARTIAL-COMPLETION-PERSISTENCE-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-EXECUTION-CONTRACT-LANGUAGE-NORMALIZATION "
            "GOAL: Normalize bounded execution smoke wording so equivalent verbs/nouns resolve to the same execution_* contract path. "
            "EXPECTED: publish diagnostic contract execution_x record diagnostic field execution_x set execution_x state create execution_x marker all resolve to: execution_contract_field = execution_x "
            "ACCEPTANCE: - no missing-binding fallback from wording variance - execution_* contract extracted once - semantic contracts still stay distinct from passive diagnostics - partial persistence smoke can run cleanly"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-EXECUTION-CONTRACT-LANGUAGE-NORMALIZATION"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-EXECUTION-CONTRACT-LANGUAGE-NORMALIZATION")
        self.assertEqual(execution_payload["target_file"], "core/routers/tod_ui.py")
        self.assertEqual(execution_payload["status"], "completed")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_contract_language_normalization")
        self.assertEqual(execution_payload["execution_contract_field"], "execution_x")
        self.assertEqual(execution_payload["requested_diagnostic_fields"], ["execution_contract_field"])
        self.assertFalse(execution_payload["language_normalization_evidence"]["missing_binding_fallback"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("wording_variance_normalized", check_names)
        self.assertIn("execution_contract_field_extracted_once", check_names)
        self.assertIn("semantic_contracts_remain_distinct", check_names)
        self.assertIn("no_missing_binding_fallback_from_wording_variance", check_names)

    def test_publish_local_execution_ack_records_bounded_branch_selection(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-EXECUTION-CONTRACT-LANGUAGE-NORMALIZATION",
                "task_id": "tod-execution-contract-language-normalization-task-1778203732334",
            },
            "live_task_request": {
                "request_id": "tod-execution-contract-language-normalization-task-1778203732334",
                "task_id": "tod-execution-contract-language-normalization-task-1778203732334",
                "objective_id": "TOD-EXECUTION-CONTRACT-LANGUAGE-NORMALIZATION",
            },
            "quick_facts": {"canonical_objective": "TOD-EXECUTION-CONTRACT-LANGUAGE-NORMALIZATION"},
        }
        message = (
            "OBJECTIVE: TOD-BOUNDED-BRANCH-SELECTION-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Publish execution_branch_state. "
            "2. Simulate two possible bounded branches: branch_validate_only and branch_repair_then_validate. "
            "3. If execution_branch_state is missing: TOD must choose branch_repair_then_validate. "
            "4. After repair: TOD must transition to branch_validate_only. "
            "RULES: - exactly one target_file - bounded_edit_mode true - branch choice must be recorded"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-BOUNDED-BRANCH-SELECTION-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-BOUNDED-BRANCH-SELECTION-SMOKE")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_branch_selection")
        self.assertEqual(execution_payload["execution_branch_state"], "branch_validate_only")
        evidence = execution_payload["branch_selection_evidence"]
        self.assertEqual(evidence["initial_branch"], "branch_repair_then_validate")
        self.assertEqual(evidence["repair_branch_attempts"], 1)
        self.assertEqual(evidence["transition"]["to"], "branch_validate_only")
        self.assertTrue(evidence["validation"]["after_branch_transition"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_branch_state_requested", check_names)
        self.assertIn("initial_branch_selection_recorded", check_names)
        self.assertIn("repair_branch_executed_once", check_names)
        self.assertIn("validate_branch_executed_second", check_names)
        self.assertIn("branch_transition_recorded", check_names)
        self.assertIn("validation_after_branch_transition_passed", check_names)

    def test_publish_local_execution_ack_respects_negative_constraints(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-BOUNDED-BRANCH-SELECTION-SMOKE",
                "task_id": "tod-bounded-branch-selection-smoke-task-1778204059788",
            },
            "live_task_request": {
                "request_id": "tod-bounded-branch-selection-smoke-task-1778204059788",
                "task_id": "tod-bounded-branch-selection-smoke-task-1778204059788",
                "objective_id": "TOD-BOUNDED-BRANCH-SELECTION-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-BOUNDED-BRANCH-SELECTION-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-NEGATIVE-CONSTRAINT-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Publish execution_negative_constraint_state. "
            "2. Explicitly do not publish execution_forbidden_state. "
            "3. Validate that execution_negative_constraint_state exists. "
            "4. Validate that execution_forbidden_state does not exist. "
            "RULES: - exactly one target_file - bounded_edit_mode true - negative constraints must be parsed as prohibitions, not requested fields"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-NEGATIVE-CONSTRAINT-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-NEGATIVE-CONSTRAINT-SMOKE")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_negative_constraint")
        self.assertEqual(execution_payload["execution_negative_constraint_state"], "published")
        self.assertEqual(execution_payload["requested_diagnostic_fields"], ["execution_negative_constraint_state"])
        self.assertEqual(execution_payload["forbidden_diagnostic_fields"], ["execution_forbidden_state"])
        self.assertFalse(execution_payload["negative_constraint_evidence"]["forbidden_published"])
        self.assertNotIn("execution_forbidden_state", execution_payload)
        normalized = self.tod_ui._normalize_execution_status({}, execution_payload, {}, {"status": "passed"}, execution_payload, {})
        self.assertEqual(normalized["requested_diagnostic_fields"], ["execution_negative_constraint_state"])
        self.assertEqual(normalized["forbidden_diagnostic_fields"], ["execution_forbidden_state"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_negative_constraint_state_requested", check_names)
        self.assertIn("execution_forbidden_state_not_published", check_names)
        self.assertIn("negative_constraint_recorded", check_names)

    def test_publish_local_execution_ack_records_conditional_constraint_without_conflict(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-NEGATIVE-CONSTRAINT-SMOKE",
                "task_id": "tod-negative-constraint-smoke-task-1778204611889",
            },
            "live_task_request": {
                "request_id": "tod-negative-constraint-smoke-task-1778204611889",
                "task_id": "tod-negative-constraint-smoke-task-1778204611889",
                "objective_id": "TOD-NEGATIVE-CONSTRAINT-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-NEGATIVE-CONSTRAINT-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-CONDITIONAL-CONSTRAINT-SMOKE TOD, this task is assigned directly to you. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Publish execution_conditional_constraint_state. "
            "2. Do not publish execution_conditional_blocked_state if execution_conditional_constraint_state is missing. "
            "3. Since execution_conditional_constraint_state is requested and will be published, the condition is false after repair. "
            "RULES: - exactly one target_file - bounded_edit_mode true - conditional prohibition must not become unconditional prohibition"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-CONDITIONAL-CONSTRAINT-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-CONDITIONAL-CONSTRAINT-SMOKE")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_conditional_constraint")
        self.assertEqual(execution_payload["execution_conditional_constraint_state"], "published")
        self.assertEqual(execution_payload["requested_diagnostic_fields"], ["execution_conditional_constraint_state"])
        self.assertEqual(execution_payload["forbidden_diagnostic_fields"], ["execution_conditional_blocked_state"])
        self.assertEqual(execution_payload["conflicting_diagnostic_fields"], [])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["condition_after_repair"])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["blocked_fields_published"])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["conflict_reported"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("conditional_rule_recorded", check_names)
        self.assertIn("condition_evaluated", check_names)
        self.assertIn("condition_false_after_repair", check_names)
        self.assertIn("execution_conditional_blocked_state_not_published", check_names)
        self.assertIn("no_conflicting_execution_constraint", check_names)

    def test_extract_conditional_diagnostic_request_does_not_become_unconditional_request(self) -> None:
        message = (
            "OBJECTIVE: TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE "
            "TASK: 1. Do not publish execution_required_condition_state. "
            "2. Publish execution_conditional_blocked_state only if execution_required_condition_state exists. "
            "3. Since execution_required_condition_state is missing, TOD must not publish execution_conditional_blocked_state."
        )

        self.assertEqual(
            self.tod_ui._extract_conditional_diagnostic_requests(message),
            {"execution_conditional_blocked_state": "execution_required_condition_state"},
        )
        self.assertEqual(self.tod_ui._extract_requested_diagnostic_fields(message), [])
        self.assertEqual(
            self.tod_ui._extract_forbidden_diagnostic_fields(message),
            ["execution_required_condition_state", "execution_conditional_blocked_state"],
        )

    def test_publish_local_execution_ack_evaluates_false_conditional_request_without_conflict(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-CONDITIONAL-CONSTRAINT-SMOKE",
                "task_id": "tod-conditional-constraint-smoke-task-1778205188257",
            },
            "live_task_request": {
                "request_id": "tod-conditional-constraint-smoke-task-1778205188257",
                "task_id": "tod-conditional-constraint-smoke-task-1778205188257",
                "objective_id": "TOD-CONDITIONAL-CONSTRAINT-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-CONDITIONAL-CONSTRAINT-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE TOD, this task is assigned directly to you. "
            "GOAL: Prove TOD applies a conditional prohibition when its condition is true. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Do not publish execution_required_condition_state. "
            "2. Publish execution_conditional_blocked_state only if execution_required_condition_state exists. "
            "3. Since execution_required_condition_state is missing, TOD must not publish execution_conditional_blocked_state. "
            "4. Record the conditional evaluation. "
            "RULES: - exactly one target_file - bounded_edit_mode true - conditional rule must be recorded - condition must be evaluated"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE")
        self.assertEqual(execution_payload["status"], "completed")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_conditional_constraint")
        self.assertEqual(execution_payload["requested_diagnostic_fields"], [])
        self.assertEqual(
            execution_payload["conditional_diagnostic_requests"],
            {"execution_conditional_blocked_state": "execution_required_condition_state"},
        )
        self.assertEqual(
            execution_payload["forbidden_diagnostic_fields"],
            ["execution_required_condition_state", "execution_conditional_blocked_state"],
        )
        self.assertEqual(execution_payload["conflicting_diagnostic_fields"], [])
        self.assertEqual(execution_payload["files_changed"], [])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["condition_after_evaluation"])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["requested_fields_published"])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["conflict_reported"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("conditional_rule_recorded", check_names)
        self.assertIn("condition_evaluated", check_names)
        self.assertIn("condition_evaluated_false", check_names)
        self.assertIn("execution_required_condition_state_not_published", check_names)
        self.assertIn("execution_conditional_blocked_state_not_published", check_names)
        self.assertIn("no_conflicting_execution_constraint", check_names)

    def test_publish_local_execution_ack_activates_nested_conditional_request_in_order(self) -> None:
        state = {
            "shared_truth": {
                "objective_id": "TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE",
                "task_id": "tod-conditional-constraint-true-smoke-task-1778205355881",
            },
            "live_task_request": {
                "request_id": "tod-conditional-constraint-true-smoke-task-1778205355881",
                "task_id": "tod-conditional-constraint-true-smoke-task-1778205355881",
                "objective_id": "TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE",
            },
            "quick_facts": {"canonical_objective": "TOD-CONDITIONAL-CONSTRAINT-TRUE-SMOKE"},
        }
        message = (
            "OBJECTIVE: TOD-NESTED-CONDITIONAL-BRANCH-SMOKE TOD, this task is assigned directly to you. "
            "GOAL: Prove TOD can evaluate nested conditional execution constraints without collapsing into conflict or unconditional activation. "
            "TARGET FILE: core/routers/tod_ui.py "
            "TASK: 1. Publish execution_nested_parent_state. "
            "2. Publish execution_nested_child_state only if execution_nested_parent_state exists. "
            "3. Do not publish execution_nested_blocked_state unless execution_nested_child_state exists. "
            "4. Since parent exists, child activates. "
            "5. Since child activates, blocked_state remains prohibited. "
            "RULES: - exactly one target_file - bounded_edit_mode true - nested conditions must be evaluated in order"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                artifact_fixture = {
                    "active_objective_payload": {"objective_id": "TOD-NESTED-CONDITIONAL-BRANCH-SMOKE"},
                    "active_task_payload": {},
                    "activity_event": {},
                    "validation_payload": {},
                    "execution_result_payload": {},
                    "execution_truth_payload": {},
                }
                with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                    record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")

                execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

        self.assertTrue(record["ok"])
        self.assertEqual(execution_payload["objective_id"], "TOD-NESTED-CONDITIONAL-BRANCH-SMOKE")
        self.assertEqual(execution_payload["status"], "completed")
        self.assertEqual(execution_payload["execution_validation_mode"], "bounded_conditional_constraint")
        self.assertEqual(
            execution_payload["requested_diagnostic_fields"],
            ["execution_nested_parent_state", "execution_nested_child_state"],
        )
        self.assertEqual(
            execution_payload["conditional_diagnostic_requests"],
            {"execution_nested_child_state": "execution_nested_parent_state"},
        )
        self.assertEqual(
            execution_payload["conditional_diagnostic_prohibitions"],
            {"execution_nested_blocked_state": "execution_nested_child_state"},
        )
        self.assertEqual(execution_payload["forbidden_diagnostic_fields"], ["execution_nested_blocked_state"])
        self.assertEqual(execution_payload["conflicting_diagnostic_fields"], [])
        self.assertFalse(execution_payload["conditional_constraint_evidence"]["blocked_fields_published"])
        self.assertTrue(execution_payload["conditional_constraint_evidence"]["nested_evaluation_order_recorded"])
        check_names = {item["name"] for item in execution_payload["validation_checks"]}
        self.assertIn("execution_nested_parent_state_requested", check_names)
        self.assertIn("execution_nested_child_state_requested", check_names)
        self.assertIn("child_conditional_request_activated", check_names)
        self.assertIn("nested_evaluation_order_recorded", check_names)
        self.assertIn("execution_nested_blocked_state_not_published", check_names)
        self.assertIn("no_conflicting_execution_constraint", check_names)

    def test_tod_next20_challenge_progression_matrix(self) -> None:
        state = {
            "shared_truth": {"objective_id": "TOD-NEXT20-BASELINE", "task_id": "tod-next20-baseline-task"},
            "live_task_request": {
                "request_id": "tod-next20-baseline-task",
                "task_id": "tod-next20-baseline-task",
                "objective_id": "TOD-NEXT20-BASELINE",
            },
            "quick_facts": {"canonical_objective": "TOD-NEXT20-BASELINE"},
        }
        cases = [
            (
                "TOD-NEXT20-01-NESTED-REEVALUATION",
                "TASK: Publish execution_parent_state. Publish execution_child_state only if execution_parent_state exists. "
                "Do not publish execution_blocked_state unless execution_child_state exists. step_prepare -> step_validate -> step_handoff.",
                {"execution_parent_state_requested", "execution_child_state_requested", "execution_state_refreshed_between_condition_steps", "step_dependency_graph_tracked"},
            ),
            (
                "TOD-NEXT20-02-AND-CONSTRAINTS",
                "TASK: Publish execution_and_a_state. Publish execution_and_b_state. Publish execution_and_x_state only if execution_and_a_state exists AND execution_and_b_state exists.",
                {"execution_and_x_state_requested", "multi_condition_and_evaluated"},
            ),
            (
                "TOD-NEXT20-03-OR-CONSTRAINTS",
                "TASK: Publish execution_or_a_state. Publish execution_or_x_state if execution_or_a_state exists OR execution_or_b_state exists.",
                {"execution_or_x_state_requested", "multi_condition_or_evaluated"},
            ),
            (
                "TOD-NEXT20-04-NOT-CONDITION",
                "TASK: Publish execution_not_x_state only if NOT execution_not_y_state exists.",
                {"execution_not_x_state_requested", "negated_condition_precedence_preserved", "no_conflicting_execution_constraint"},
            ),
            (
                "TOD-NEXT20-05-STEP-GRAPH",
                "TASK: Publish execution_graph_state. Track step_prepare -> step_validate -> step_handoff.",
                {"execution_graph_state_requested", "step_dependency_graph_tracked"},
            ),
            (
                "TOD-NEXT20-06-PARTIAL-GRAPH-RECOVERY",
                "TASK: Publish execution_partial_graph_state. Partial graph recovery: interrupt at step 2, resume, run unresolved nodes only.",
                {"execution_partial_graph_state_requested", "partial_graph_recovery_preserved"},
            ),
            (
                "TOD-NEXT20-07-BRANCH-ROLLBACK",
                "TASK: Publish execution_branch_rollback_state. Branch rollback semantics: rollback B only and preserve completed A.",
                {"execution_branch_rollback_state_requested", "branch_rollback_scoped"},
            ),
            (
                "TOD-NEXT20-08-RETRY-POLICY",
                "TASK: Publish execution_retry_policy_state. Retry policy awareness: transient failure, deterministic failure, prohibited retry, bounded retry count.",
                {"execution_retry_policy_state_requested", "retry_policy_classified"},
            ),
            (
                "TOD-NEXT20-09-TIME-EXPIRY",
                "TASK: Publish execution_expiry_state. Expire task if step not resumed within 10 minutes and avoid zombie loops.",
                {"execution_expiry_state_requested", "time_based_execution_expiry_recorded"},
            ),
            (
                "TOD-NEXT20-10-MULTI-FILE-CHAIN",
                "TASK: Publish execution_multifile_state. Multi-file bounded chains: file A validated before file B edit.",
                {"execution_multifile_state_requested", "multi_file_bounded_chain_ordered"},
            ),
            (
                "TOD-NEXT20-11-CONTRACT-MODES",
                "TASK: Publish execution_contract_modes_state. Distinguish validation-only, inspect-only, bounded-edit, mutating-repair.",
                {"execution_contract_modes_state_requested", "execution_contract_modes_distinguished"},
            ),
            (
                "TOD-NEXT20-12-RESOURCE-LOCK",
                "TASK: Publish execution_resource_lock_state. Resource lock coordination prevents two tasks editing same file and overlapping execution lanes.",
                {"execution_resource_lock_state_requested", "resource_lock_coordination_recorded"},
            ),
            (
                "TOD-NEXT20-13-CROSS-TASK-DEPENDENCY",
                "TASK: Publish execution_cross_task_state. Cross-task dependency awareness: Task B blocked until Task A validation passes.",
                {"execution_cross_task_state_requested", "cross_task_dependency_recorded"},
            ),
            (
                "TOD-NEXT20-14-PRIORITY-ARBITRATION",
                "TASK: Publish execution_priority_state. Priority arbitration under conflict: emergency repair vs normal bounded edit.",
                {"execution_priority_state_requested", "priority_arbitration_conflict_resolved"},
            ),
            (
                "TOD-NEXT20-15-CONTRADICTION",
                "TASK: Publish execution_contradiction_state. Detect contradictory objective: preserve behavior and rewrite architecture.",
                {"execution_contradiction_state_requested", "contradictory_objective_detected"},
            ),
            (
                "TOD-NEXT20-16-SEMANTIC-DRIFT",
                "TASK: Publish execution_semantic_drift_state. Semantic drift detection catches reinterpretation drift.",
                {"execution_semantic_drift_state_requested", "semantic_drift_detection_recorded"},
            ),
            (
                "TOD-NEXT20-17-DELEGATED-SUBTASK",
                "TASK: Publish execution_delegated_subtask_state. Delegated subtask coordination preserves parent lineage and execution custody.",
                {"execution_delegated_subtask_state_requested", "delegated_subtask_lineage_preserved"},
            ),
            (
                "TOD-NEXT20-18-CLARIFICATION",
                "TASK: Publish execution_clarification_state. Human clarification thresholding for ambiguity safe/required/autonomous.",
                {"execution_clarification_state_requested", "human_clarification_threshold_recorded"},
            ),
            (
                "TOD-NEXT20-19-MEMORY-COMPRESSION",
                "TASK: Publish execution_memory_compression_state. Persistent execution memory compression avoids infinite JSON archaeology.",
                {"execution_memory_compression_state_requested", "persistent_execution_memory_compressed"},
            ),
            (
                "TOD-NEXT20-20-CROSS-SYSTEM",
                "TASK: Publish execution_cross_system_state. Cross-system coordinated execution: TOD patches MIM, MIM validates, TOD waits and resumes.",
                {"execution_cross_system_state_requested", "cross_system_execution_custody_recorded"},
            ),
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir)
            operator_root = shared_root / "actions"
            original_shared_root = self.tod_ui.SHARED_RUNTIME_ROOT
            original_operator_root = self.tod_ui.TOD_OPERATOR_ACTION_ROOT
            original_latest_path = self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH
            original_log_path = self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH
            original_evidence_path = self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH
            try:
                self.tod_ui.SHARED_RUNTIME_ROOT = shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = operator_root / "TOD_OPERATOR_ACTION.latest.json"
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = operator_root / "TOD_OPERATOR_ACTION.log.jsonl"
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = operator_root / "TOD_OPERATOR_EVIDENCE.latest.json"

                for objective, task_text, expected_checks in cases:
                    with self.subTest(objective=objective):
                        artifact_fixture = {
                            "active_objective_payload": {"objective_id": objective},
                            "active_task_payload": {},
                            "activity_event": {},
                            "validation_payload": {},
                            "execution_result_payload": {},
                            "execution_truth_payload": {},
                        }
                        message = (
                            f"OBJECTIVE: {objective} TARGET FILE: core/routers/tod_ui.py "
                            f"{task_text} RULES: exactly one target_file; bounded_edit_mode true"
                        )
                        with patch.object(self.tod_ui, "build_execution_loop_contract_artifacts", return_value=artifact_fixture):
                            record = self.tod_ui._publish_local_execution_ack(message, state, "tod", "tod-console-public")
                        execution_payload = json.loads((shared_root / "TOD_EXECUTION_RESULT.latest.json").read_text(encoding="utf-8"))
                        self.assertTrue(record["ok"])
                        self.assertEqual(execution_payload["status"], "completed")
                        check_names = {item["name"] for item in execution_payload["validation_checks"]}
                        self.assertTrue(expected_checks.issubset(check_names))
                        self.assertEqual(execution_payload["next20_challenge_evidence"]["challenge_suite"], "tod_next_20_progression")
            finally:
                self.tod_ui.SHARED_RUNTIME_ROOT = original_shared_root
                self.tod_ui.TOD_OPERATOR_ACTION_ROOT = original_operator_root
                self.tod_ui.TOD_OPERATOR_ACTION_LATEST_PATH = original_latest_path
                self.tod_ui.TOD_OPERATOR_ACTION_LOG_PATH = original_log_path
                self.tod_ui.TOD_OPERATOR_EVIDENCE_PATH = original_evidence_path

    def test_extract_labeled_prompt_value_captures_only_identifier_token(self) -> None:
        message = (
            "## Objective Id: objective-2913 and ignore the prompt tail\n"
            "- Task ID: objective-2913-task-7144 should stop at the identifier\n"
            "- Request ID: request-7144 trailing details should not persist\n"
            "TITLE: Keep collecting full non-identifier fields"
        )

        self.assertEqual(self.tod_ui._extract_labeled_prompt_value(message, "OBJECTIVE_ID"), "objective-2913")
        self.assertEqual(self.tod_ui._extract_labeled_prompt_value(message, "TASK_ID"), "objective-2913-task-7144")
        self.assertEqual(self.tod_ui._extract_labeled_prompt_value(message, "REQUEST_ID"), "request-7144")

    def test_extract_labeled_prompt_value_reads_markdown_heading_and_bullet_labels(self) -> None:
        message = (
            "### Initiative Id: `initiative-77` should ignore this trailing explanation\n"
            "- Objective Id: objective-2913 extra trailing copy\n"
            "PRIMARY OUTCOME: Preserve the rest of this field as normal."
        )

        self.assertEqual(self.tod_ui._extract_labeled_prompt_value(message, "INITIATIVE_ID"), "initiative-77")
        self.assertEqual(self.tod_ui._extract_labeled_prompt_value(message, "Objective Id"), "objective-2913")
        self.assertEqual(
            self.tod_ui._extract_labeled_prompt_value(message, "PRIMARY OUTCOME"),
            "Preserve the rest of this field as normal.",
        )

    def test_select_runtime_live_task_request_does_not_preserve_same_objective_wrong_task(self) -> None:
        integration_live_task = {
            "request_id": "objective-2913-task-1777951503",
            "task_id": "objective-2913-task-1777951503",
            "objective_id": "objective-2913",
            "normalized_objective_id": "2913",
            "generated_at": "2026-05-05T03:25:03Z",
        }
        active_task = {
            "request_id": "objective-2913-task-7144",
            "task_id": "objective-2913-task-7144",
            "objective_id": "2913",
            "normalized_objective_id": "2913",
            "updated_at": "2026-05-05T03:28:02Z",
        }

        selected = self.tod_ui._select_runtime_live_task_request(integration_live_task, active_task)

        self.assertEqual(selected["request_id"], "objective-2913-task-7144")
        self.assertEqual(selected["task_id"], "objective-2913-task-7144")
        self.assertEqual(selected["objective_id"], "2913")

    def test_derive_execution_live_state_supplies_stuck_and_next_defaults(self) -> None:
        execution = {
            "available": True,
            "activity_state": "blocked",
            "activity_label": "Blocked",
            "activity_summary": "objective_mismatch; task_mismatch; tod_execution_truth_lock_mismatch",
            "wait_reason": "",
            "next_step": "",
            "stall_signal": {"flagged": False, "summary": ""},
        }
        planner = {
            "objective_id": "2913",
            "task_id": "objective-2913-task-7144",
            "status": "blocked",
        }

        live_state = self.tod_ui._derive_execution_live_state(execution, planner, [])

        self.assertTrue(live_state["is_stuck"])
        self.assertTrue(live_state["mim_priority"])
        self.assertTrue(bool(str(live_state["stuck_on"]).strip()))
        self.assertTrue(bool(str(live_state["next_to_progress"]).strip()))
        self.assertTrue(isinstance(live_state["barriers"], list))
        self.assertGreaterEqual(len(live_state["barriers"]), 1)
        self.assertIn("MIM", live_state["escalation_channels"])

    def test_build_objective_cards_includes_execution_live_state_projection(self) -> None:
        state = {
            "execution": {
                "objective_id": "2913",
                "task_id": "objective-2913-task-7144",
                "activity_state": "blocked",
                "activity_label": "Blocked",
                "activity_summary": "Execution is blocked pending objective reconciliation.",
                "phase_progress": {"available": False},
                "live_state": {
                    "status": "blocked",
                    "status_label": "Blocked",
                    "status_detail": "Execution is blocked pending objective reconciliation.",
                    "stuck_on": "Objective mismatch in listener decision path.",
                    "next_to_progress": "Run Reconcile Truth first (MIM priority), then Recover Stale State if TOD remains frozen.",
                    "is_stuck": True,
                    "is_working_background": False,
                    "mim_priority": True,
                    "barriers": ["Objective mismatch in listener decision path."],
                    "escalation_channels": ["MIM", "Codex", "Operator"],
                },
            },
            "shared_truth": {},
            "status": {"label": "Blocked", "summary": "Execution is blocked pending objective reconciliation."},
            "objective_alignment": {"tod_current_objective": "2913", "mim_objective_active": "2913"},
            "live_task_request": {"objective_id": "2913", "task_id": "objective-2913-task-7144", "request_id": "objective-2913-task-7144"},
            "conversation": {"quick_actions": []},
            "operator_actions": [],
            "planner_state": {},
        }

        cards = self.tod_ui._build_objective_cards(state)
        self.assertEqual(len(cards), 1)
        live = cards[0].get("live_state") if isinstance(cards[0], dict) else None
        self.assertTrue(isinstance(live, dict))
        self.assertTrue(live.get("is_stuck"))
        self.assertEqual(live.get("stuck_on"), "Objective mismatch in listener decision path.")
        self.assertIn("MIM", live.get("escalation_channels") or [])


if __name__ == "__main__":
    unittest.main()
