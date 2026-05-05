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
        self.assertEqual(execution["phase_progress"]["percent_complete"], 60)
        self.assertIn("rather than stale output", execution["activity_summary"])

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

        self.assertGreater(execution["phase_progress"]["percent_complete"], 60)
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
        shared_truth_timestamp = "2026-05-05T05:32:38.674201Z"
        execution_timestamp = "2026-05-05T05:51:21Z"
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
            "summary": "Implement the next bounded execution-loop slice in the inspected surfaces and rerun the focused validation path.",
            "updated_at": execution_timestamp,
            "status": "waiting",
            "execution_state": "waiting_on_next_step",
            "next_step": "Implement the next bounded execution-loop slice in the inspected surfaces and rerun the focused validation path.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step. It is not waiting on MIM, the operator, or Codex.",
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
            "wait_reason": "TOD is waiting on its own next bounded local implementation step. It is not waiting on MIM, the operator, or Codex.",
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
            "next_step": "Implement the next bounded execution-loop slice in the inspected surfaces and rerun the focused validation path.",
            "wait_reason": "TOD is waiting on its own next bounded local implementation step. It is not waiting on MIM, the operator, or Codex.",
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

        self.assertIn(
            "Stall watch: Held at implementation gate: Phase 2 is at 63% until the next implementation slice starts. Fresh execution evidence landed 1m ago, so this wait is for the next implementation slice rather than stale output.",
            contents,
        )
        self.assertIn(
            "Live state: waiting. execution_state=waiting_on_next_step. Freshness: unknown.",
            contents,
        )
        self.assertIn(
            "File focus: /home/testpilot/mim/core/tod_execution_loop.py",
            contents,
        )
        self.assertIn(
            "Wait owner: TOD local executor",
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
                                {"role": "tod", "content": "Live execution feed: TOD is complete on the current task.", "created_at": "2026-05-05T05:32:38.674201Z"},
                                {"role": "system", "content": "Phase 1 progress: 100% complete. Next gate: Phase 2 handoff.", "created_at": "2026-05-05T05:32:38.674201Z"},
                                {"role": "system", "content": "Updated: 12m ago", "created_at": "2026-05-05T05:32:38.674201Z"},
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


if __name__ == "__main__":
    unittest.main()