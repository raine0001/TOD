from __future__ import annotations

import importlib.util
import sys
import tempfile
import types
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent
MIM_UI_PATH = REPO_ROOT / "tmp_remote_mim" / "core" / "mim_ui.py"


def _install_module(name: str, **attrs) -> types.ModuleType:
    module = types.ModuleType(name)
    for key, value in attrs.items():
        setattr(module, key, value)
    sys.modules[name] = module
    return module


def load_mim_ui_module() -> types.ModuleType:
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

    class BaseModelStub:
        def __init__(self, **kwargs) -> None:
            for key, value in kwargs.items():
                setattr(self, key, value)

    class RuntimeRecoveryServiceStub:
        def __init__(self, *args, **kwargs) -> None:
            pass

        def get_summary(self) -> dict:
            return {}

    def async_result(value):
        async def _inner(*args, **kwargs):
            return value

        return _inner

    def dummy_class(name: str):
        return type(name, (), {})

    _install_module(
        "fastapi",
        APIRouter=RouterStub,
        Depends=lambda *args, **kwargs: None,
        HTTPException=HTTPExceptionStub,
        Request=type("Request", (), {}),
    )
    _install_module(
        "fastapi.responses",
        FileResponse=object,
        HTMLResponse=str,
        RedirectResponse=object,
    )
    _install_module("pydantic", BaseModel=BaseModelStub)
    _install_module("sqlalchemy", select=lambda *args, **kwargs: None)
    _install_module("sqlalchemy.ext")
    _install_module("sqlalchemy.ext.asyncio", AsyncSession=type("AsyncSession", (), {}))
    _install_module("core")
    _install_module("core.autonomy_driver_service", build_initiative_status=async_result({}))
    _install_module(
        "core.autonomy_boundary_service",
        build_boundary_action_controls=lambda *args, **kwargs: {},
        build_boundary_decision_basis=lambda *args, **kwargs: {},
        build_boundary_profile_snapshot=lambda *args, **kwargs: {},
    )
    _install_module(
        "core.camera_scene",
        collect_fresh_camera_observations=lambda *args, **kwargs: [],
        summarize_camera_observations=lambda *args, **kwargs: {},
    )
    _install_module("core.db", get_db=lambda: None)
    _install_module("core.execution_recovery_service", evaluate_execution_recovery=async_result({}))
    _install_module(
        "core.execution_readiness_service",
        execution_readiness_summary=lambda *args, **kwargs: "",
        load_latest_execution_readiness=lambda *args, **kwargs: {},
    )
    _install_module(
        "core.execution_strategy_service",
        latest_execution_strategy_plan=async_result(None),
        to_execution_strategy_plan_out=lambda *args, **kwargs: {},
    )
    _install_module(
        "core.interface_service",
        append_interface_message=async_result((None, None)),
        list_interface_messages=async_result(({}, [])),
        to_interface_message_out=lambda row: row,
        to_interface_session_out=lambda row: row,
        upsert_interface_session=async_result({}),
    )
    _install_module(
        "core.models",
        Actor=dummy_class("Actor"),
        CapabilityExecution=dummy_class("CapabilityExecution"),
        ExecutionStrategyPlan=dummy_class("ExecutionStrategyPlan"),
        InputEvent=dummy_class("InputEvent"),
        InputEventResolution=dummy_class("InputEventResolution"),
        MemoryEntry=dummy_class("MemoryEntry"),
        SpeechOutputAction=dummy_class("SpeechOutputAction"),
        WorkspaceAutonomyBoundaryProfile=dummy_class("WorkspaceAutonomyBoundaryProfile"),
        WorkspaceExecutionTruthGovernanceProfile=dummy_class("WorkspaceExecutionTruthGovernanceProfile"),
        WorkspaceInquiryQuestion=dummy_class("WorkspaceInquiryQuestion"),
        WorkspaceObjectMemory=dummy_class("WorkspaceObjectMemory"),
        WorkspaceOperatorResolutionCommitment=dummy_class("WorkspaceOperatorResolutionCommitment"),
        WorkspaceOperatorResolutionCommitmentMonitoringProfile=dummy_class("WorkspaceOperatorResolutionCommitmentMonitoringProfile"),
        WorkspaceOperatorResolutionCommitmentOutcomeProfile=dummy_class("WorkspaceOperatorResolutionCommitmentOutcomeProfile"),
        WorkspacePerceptionSource=dummy_class("WorkspacePerceptionSource"),
        WorkspaceStewardshipCycle=dummy_class("WorkspaceStewardshipCycle"),
        WorkspaceStewardshipState=dummy_class("WorkspaceStewardshipState"),
        WorkspaceStrategyGoal=dummy_class("WorkspaceStrategyGoal"),
    )
    _install_module(
        "core.config",
        settings=types.SimpleNamespace(
            remote_shell_domain="",
            allow_openai=False,
            openai_api_key="",
            app_name="MIM",
        ),
    )
    _install_module(
        "core.mim_ui_auth",
        clear_authenticated_mimtod_cookie=lambda *args, **kwargs: None,
        credentials_match=lambda *args, **kwargs: False,
        ensure_authenticated_mimtod_api_request=lambda *args, **kwargs: None,
        maybe_require_mimtod_page_login=lambda *args, **kwargs: None,
        mimtod_auth_required=lambda *args, **kwargs: False,
        normalize_next_path=lambda value: value,
        request_has_valid_mimtod_auth=lambda *args, **kwargs: False,
        set_authenticated_mimtod_cookie=lambda *args, **kwargs: None,
    )
    _install_module("core.mim_arm_dispatch_telemetry", refresh_dispatch_telemetry_record=lambda *args, **kwargs: {})
    _install_module(
        "core.operator_commitment_monitoring_service",
        latest_commitment_monitoring_profile=async_result(None),
        to_operator_resolution_commitment_monitoring_out=lambda *args, **kwargs: {},
    )
    _install_module(
        "core.operator_commitment_outcome_service",
        latest_commitment_outcome_profile=async_result(None),
        to_operator_resolution_commitment_outcome_out=lambda *args, **kwargs: {},
    )
    _install_module(
        "core.operator_preference_convergence_service",
        latest_scope_learned_preference=async_result(None),
        list_learned_preferences=async_result([]),
        preference_conflicts=lambda *args, **kwargs: [],
    )
    _install_module(
        "core.operator_resolution_service",
        choose_operator_resolution_commitment=lambda *args, **kwargs: None,
        commitment_effect_labels=lambda *args, **kwargs: [],
        commitment_is_recovery_policy_tuning_derived=lambda *args, **kwargs: False,
        commitment_snapshot=lambda *args, **kwargs: {},
    )
    _install_module("core.policy_conflict_resolution_service", list_workspace_policy_conflict_profiles=async_result([]))
    _install_module("core.proposal_policy_convergence_service", list_workspace_proposal_policy_preferences=async_result([]))
    _install_module("core.self_evolution_service", build_self_evolution_briefing=async_result({"briefing": {}}))
    _install_module("core.runtime_recovery_service", RuntimeRecoveryService=RuntimeRecoveryServiceStub)
    _install_module("core.primitive_request_recovery_service", load_authoritative_request_status=lambda *args, **kwargs: {})
    _install_module(
        "core.ui_health_service",
        build_mim_ui_health_snapshot=lambda *args, **kwargs: {},
        build_mim_ui_health_snapshot_from_rows=lambda *args, **kwargs: {},
        summarize_runtime_health=lambda *args, **kwargs: "",
    )

    spec = importlib.util.spec_from_file_location("test_mim_ui_module", MIM_UI_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load MIM UI module from {MIM_UI_PATH}")

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MimUiWorklogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mim_ui = load_mim_ui_module()

    def test_build_mim_live_worklog_messages_compacts_operator_readable_lines(self) -> None:
        messages = self.mim_ui._build_mim_live_worklog_messages(
            system_activity={
                "status_label": "ACTIVE",
                "headline": "MIM is actively moving the current objective through a bounded implementation slice.",
                "summary": "MIM is patching the live execution view and checking whether coordination stays aligned.",
                "stall_reason": "Waiting for TOD bridge feedback before opening a second objective.",
                "tod_phase_progress": {
                    "available": True,
                    "percent_complete": 60,
                    "next_gate": "Implementation",
                },
                "tod_stall_signal": {
                    "flagged": False,
                    "age_seconds": 240,
                    "summary": "",
                },
            },
            initiative_driver={
                "active_objective": {"display_title": "Make MIM status visible in the primary thread"},
                "active_task": {"display_title": "Patch MIM operator thread live worklog"},
                "next_task": {"display_title": "Validate live worklog rendering after refresh"},
            },
            operator_reasoning={
                "active_work": {
                    "summary": "Patch the primary thread so operators can see what MIM is working on in real time without opening another panel.",
                },
                "self_evolution": {
                    "natural_language_development_next_step": "Validate the refreshed thread and tighten any noisy status text.",
                },
            },
            generated_at="2026-05-04T12:00:00Z",
        )

        contents = [item["content"] for item in messages]
        self.assertEqual(contents[0], "Live MIM feed: MIM is active on Patch MIM operator thread live worklog.")
        self.assertIn("Objective now: Make MIM status visible in the primary thread", contents)
        self.assertTrue(any(item.startswith("Current slice: Patch the primary thread") for item in contents))
        self.assertIn("Waiting on: Waiting for TOD bridge feedback before opening a second objective.", contents)
        self.assertIn("Phase 1 progress: 60% complete. Next gate: Implementation.", contents)
        self.assertIn("Stall watch: Clear. Last TOD update about 4m ago.", contents)
        self.assertIn("Next move: Validate the refreshed thread and tighten any noisy status text.", contents)

    def test_derive_tod_execution_progress_snapshot_reports_progress_and_stall(self) -> None:
        snapshot = self.mim_ui._derive_tod_execution_progress_snapshot(
            {
                "status": "waiting",
                "execution_state": "waiting_on_next_step",
                "updated_at": "2026-04-26T10:00:00Z",
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
            },
            {
                "status": "waiting",
                "execution_state": "waiting_on_next_step",
                "updated_at": "2026-04-26T10:00:00Z",
                "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
            },
            {
                "status": "passed",
            },
            {
                "status": "waiting",
                "execution_state": "waiting_on_next_step",
                "updated_at": "2026-04-26T10:00:00Z",
                "next_step": "Implement the next bounded local implementation step in the inspected surfaces.",
                "wait_reason": "TOD is waiting on its own next bounded local implementation step.",
            },
            {},
        )

        self.assertEqual(snapshot["phase_progress"]["percent_complete"], 60)
        self.assertEqual(snapshot["phase_progress"]["next_gate"], "Implementation")
        self.assertTrue(snapshot["stall_signal"]["flagged"])
        self.assertEqual(snapshot["activity_state"], "waiting")

    def test_append_mim_live_worklog_preserves_existing_thread_messages(self) -> None:
        payload = self.mim_ui._append_mim_live_worklog(
            {
                "primary_thread": "primary_operator",
                "messages": [{"role": "operator", "content": "Show me what MIM is doing now.", "created_at": "2026-05-04T11:59:00Z"}],
            },
            system_activity={"status_label": "IDLE", "summary": "No live task requires motion."},
            initiative_driver={},
            operator_reasoning={},
            generated_at="2026-05-04T12:00:00Z",
        )

        self.assertEqual(payload["messages"][0]["content"], "Show me what MIM is doing now.")
        self.assertTrue(payload["messages"][-1]["content"].startswith("Status now:") or payload["messages"][-1]["content"].startswith("Objective now:") or payload["messages"][-1]["content"].startswith("Live MIM feed:"))
        self.assertGreater(len(payload["messages"]), 1)

    def test_voice_do_not_disturb_state_updates_voice_learning_artifact(self) -> None:
        original_path = self.mim_ui.MIM_VOICE_INTERACTION_LEARNING_ARTIFACT
        with tempfile.TemporaryDirectory() as temp_dir:
            artifact_path = Path(temp_dir) / "MIM_VOICE_INTERACTION_LEARNING.latest.json"
            self.mim_ui.MIM_VOICE_INTERACTION_LEARNING_ARTIFACT = artifact_path
            try:
                enabled = self.mim_ui._write_voice_do_not_disturb_state(enabled=True, source="unit_test")
                payload = self.mim_ui._load_json_artifact(artifact_path)
                overrides = payload["active_overrides"]
                self.assertTrue(enabled["enabled"])
                self.assertTrue(overrides["do_not_disturb_mode"])
                self.assertTrue(overrides["phone_quiet_mode"])
                self.assertEqual(overrides["suppress_reason"], "ui_do_not_disturb")

                disabled = self.mim_ui._write_voice_do_not_disturb_state(enabled=False, source="unit_test")
                payload = self.mim_ui._load_json_artifact(artifact_path)
                overrides = payload["active_overrides"]
                self.assertFalse(disabled["enabled"])
                self.assertFalse(overrides["do_not_disturb_mode"])
                self.assertFalse(overrides["phone_quiet_mode"])
                self.assertNotIn("suppress_reason", overrides)
            finally:
                self.mim_ui.MIM_VOICE_INTERACTION_LEARNING_ARTIFACT = original_path


if __name__ == "__main__":
    unittest.main()
