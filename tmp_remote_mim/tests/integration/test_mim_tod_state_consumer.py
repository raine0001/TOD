import asyncio
import importlib
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


def _stub_module(name: str, **attributes: object) -> types.ModuleType:
    module = types.ModuleType(name)
    for key, value in attributes.items():
        setattr(module, key, value)
    return module


def _placeholder_class(name: str) -> type:
    return type(name, (), {})


def _import_mim_ui_module():
    tmp_remote_mim_root = str(Path(__file__).resolve().parents[2])

    class _FakeRouter:
        def __init__(self, *_: object, **__: object) -> None:
            pass

        def get(self, *_: object, **__: object):
            return lambda fn: fn

        def post(self, *_: object, **__: object):
            return lambda fn: fn

    class _FakeHttpException(Exception):
        def __init__(self, status_code: int, detail: object = None) -> None:
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail

    class _FakeBaseModel:
        pass

    class _FakeRuntimeRecoveryService:
        def __init__(self, *_: object, **__: object) -> None:
            pass

    fastapi_module = _stub_module(
        "fastapi",
        APIRouter=_FakeRouter,
        Depends=lambda *args, **kwargs: None,
        HTTPException=_FakeHttpException,
        Request=_placeholder_class("Request"),
    )
    fastapi_responses_module = _stub_module(
        "fastapi.responses",
        FileResponse=_placeholder_class("FileResponse"),
        HTMLResponse=_placeholder_class("HTMLResponse"),
        RedirectResponse=_placeholder_class("RedirectResponse"),
    )
    pydantic_module = _stub_module("pydantic", BaseModel=_FakeBaseModel)
    sqlalchemy_module = _stub_module("sqlalchemy", select=lambda *args, **kwargs: None)
    sqlalchemy_ext_module = _stub_module("sqlalchemy.ext")
    sqlalchemy_asyncio_module = _stub_module("sqlalchemy.ext.asyncio", AsyncSession=_placeholder_class("AsyncSession"))

    model_names = [
        "Actor",
        "CapabilityExecution",
        "ExecutionStrategyPlan",
        "InputEvent",
        "InputEventResolution",
        "MemoryEntry",
        "SpeechOutputAction",
        "WorkspaceAutonomyBoundaryProfile",
        "WorkspaceExecutionTruthGovernanceProfile",
        "WorkspaceInquiryQuestion",
        "WorkspaceObjectMemory",
        "WorkspaceOperatorResolutionCommitment",
        "WorkspaceOperatorResolutionCommitmentMonitoringProfile",
        "WorkspaceOperatorResolutionCommitmentOutcomeProfile",
        "WorkspacePerceptionSource",
        "WorkspaceStewardshipCycle",
        "WorkspaceStewardshipState",
        "WorkspaceStrategyGoal",
    ]
    models_module = _stub_module("core.models", **{name: _placeholder_class(name) for name in model_names})

    stub_modules = {
        "fastapi": fastapi_module,
        "fastapi.responses": fastapi_responses_module,
        "pydantic": pydantic_module,
        "sqlalchemy": sqlalchemy_module,
        "sqlalchemy.ext": sqlalchemy_ext_module,
        "sqlalchemy.ext.asyncio": sqlalchemy_asyncio_module,
        "core.autonomy_driver_service": _stub_module("core.autonomy_driver_service", build_initiative_status=lambda *args, **kwargs: {}),
        "core.autonomy_boundary_service": _stub_module(
            "core.autonomy_boundary_service",
            build_boundary_action_controls=lambda *args, **kwargs: {},
            build_boundary_decision_basis=lambda *args, **kwargs: {},
            build_boundary_profile_snapshot=lambda *args, **kwargs: {},
        ),
        "core.camera_scene": _stub_module(
            "core.camera_scene",
            collect_fresh_camera_observations=lambda *args, **kwargs: [],
            summarize_camera_observations=lambda *args, **kwargs: "",
        ),
        "core.db": _stub_module("core.db", get_db=lambda *args, **kwargs: None),
        "core.execution_recovery_service": _stub_module("core.execution_recovery_service", evaluate_execution_recovery=lambda *args, **kwargs: {}),
        "core.execution_readiness_service": _stub_module(
            "core.execution_readiness_service",
            execution_readiness_summary=lambda *args, **kwargs: {},
            load_latest_execution_readiness=lambda *args, **kwargs: {},
        ),
        "core.execution_strategy_service": _stub_module(
            "core.execution_strategy_service",
            latest_execution_strategy_plan=lambda *args, **kwargs: {},
            to_execution_strategy_plan_out=lambda *args, **kwargs: {},
        ),
        "core.interface_service": _stub_module(
            "core.interface_service",
            append_interface_message=lambda *args, **kwargs: {},
            list_interface_messages=lambda *args, **kwargs: [],
            to_interface_message_out=lambda *args, **kwargs: {},
            to_interface_session_out=lambda *args, **kwargs: {},
            upsert_interface_session=lambda *args, **kwargs: {},
        ),
        "core.models": models_module,
        "core.config": _stub_module("core.config", settings=types.SimpleNamespace(app_name="MIM Core")),
        "core.mim_ui_auth": _stub_module(
            "core.mim_ui_auth",
            clear_authenticated_mimtod_cookie=lambda *args, **kwargs: None,
            credentials_match=lambda *args, **kwargs: True,
            ensure_authenticated_mimtod_api_request=lambda *args, **kwargs: None,
            maybe_require_mimtod_page_login=lambda *args, **kwargs: None,
            mimtod_auth_required=lambda fn: fn,
            normalize_next_path=lambda value, default="/mim": default if not value else value,
            request_has_valid_mimtod_auth=lambda *args, **kwargs: True,
            set_authenticated_mimtod_cookie=lambda *args, **kwargs: None,
        ),
        "core.mim_arm_dispatch_telemetry": _stub_module("core.mim_arm_dispatch_telemetry", refresh_dispatch_telemetry_record=lambda *args, **kwargs: {}),
        "core.operator_commitment_monitoring_service": _stub_module(
            "core.operator_commitment_monitoring_service",
            latest_commitment_monitoring_profile=lambda *args, **kwargs: {},
            to_operator_resolution_commitment_monitoring_out=lambda *args, **kwargs: {},
        ),
        "core.operator_commitment_outcome_service": _stub_module(
            "core.operator_commitment_outcome_service",
            latest_commitment_outcome_profile=lambda *args, **kwargs: {},
            to_operator_resolution_commitment_outcome_out=lambda *args, **kwargs: {},
        ),
        "core.operator_preference_convergence_service": _stub_module(
            "core.operator_preference_convergence_service",
            latest_scope_learned_preference=lambda *args, **kwargs: {},
            list_learned_preferences=lambda *args, **kwargs: [],
            preference_conflicts=lambda *args, **kwargs: [],
        ),
        "core.operator_resolution_service": _stub_module(
            "core.operator_resolution_service",
            choose_operator_resolution_commitment=lambda *args, **kwargs: None,
            commitment_effect_labels=lambda *args, **kwargs: [],
            commitment_is_recovery_policy_tuning_derived=lambda *args, **kwargs: False,
            commitment_snapshot=lambda *args, **kwargs: {},
        ),
        "core.policy_conflict_resolution_service": _stub_module("core.policy_conflict_resolution_service", list_workspace_policy_conflict_profiles=lambda *args, **kwargs: []),
        "core.proposal_policy_convergence_service": _stub_module("core.proposal_policy_convergence_service", list_workspace_proposal_policy_preferences=lambda *args, **kwargs: []),
        "core.self_evolution_service": _stub_module("core.self_evolution_service", build_self_evolution_briefing=lambda *args, **kwargs: {}),
        "core.runtime_recovery_service": _stub_module("core.runtime_recovery_service", RuntimeRecoveryService=_FakeRuntimeRecoveryService),
        "core.primitive_request_recovery_service": _stub_module("core.primitive_request_recovery_service", load_authoritative_request_status=lambda *args, **kwargs: {}),
        "core.ui_health_service": _stub_module(
            "core.ui_health_service",
            build_mim_ui_health_snapshot=lambda *args, **kwargs: {},
            build_mim_ui_health_snapshot_from_rows=lambda *args, **kwargs: {},
            summarize_runtime_health=lambda *args, **kwargs: {},
        ),
    }

    with patch.dict(sys.modules, stub_modules):
        sys.path.insert(0, tmp_remote_mim_root)
        try:
            sys.modules.pop("core.mim_ui", None)
            return importlib.import_module("core.mim_ui")
        finally:
            sys.path.pop(0)


class MimTodStateConsumerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mim_ui = _import_mim_ui_module()

    def _artifact_loader(self, artifacts: dict[str, dict]):
        def _load(path: Path):
            return artifacts.get(Path(path).name, {})

        return _load

    def test_truth_snapshot_classifies_explicit_blocker(self) -> None:
        now = "2026-05-05T12:00:00Z"
        artifacts = {
            "TOD_INTEGRATION_STATUS.latest.json": {
                "mim_handshake": {"current_next_objective": "2003"},
                "live_task_request": {"normalized_objective_id": "2003"},
            },
            "TOD_EXECUTION_RESULT.latest.json": {
                "generated_at": now,
                "execution_state": "blocked_with_reason",
                "reason_code": "local_fallback_needs_target_or_scope",
                "summary": "Need a bounded implementation target before execution can continue.",
            },
        }

        with (
            patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)),
            patch.object(
                self.mim_ui,
                "load_authoritative_request_status",
                return_value={
                    "request_id": "objective-2003-task-008",
                    "task_id": "objective-2003-task-008",
                    "request_status": "active",
                },
            ),
        ):
            snapshot = self.mim_ui._build_tod_truth_reconciliation_snapshot(
                initiative_driver={"active_objective": {"objective_id": "2003"}},
                authoritative_request={
                    "request_id": "objective-2003-task-008",
                    "task_id": "objective-2003-task-008",
                    "objective_id": "2003",
                },
            )

        self.assertEqual(snapshot["state"], "blocked_with_reason")
        self.assertTrue(snapshot["execution_confirmed"])
        self.assertEqual(snapshot["published_state_source"], "execution_result")
        self.assertIn("bounded implementation target", snapshot["summary"])

    def test_truth_snapshot_classifies_meaningful_completion(self) -> None:
        now = "2026-05-05T12:00:00Z"
        artifacts = {
            "TOD_INTEGRATION_STATUS.latest.json": {
                "mim_handshake": {"current_next_objective": "2003"},
                "live_task_request": {"normalized_objective_id": "2003"},
            },
            "TOD_EXECUTION_RESULT.latest.json": {
                "generated_at": now,
                "execution_state": "completed",
                "summary": "Patch applied and validation succeeded.",
                "meaningful_evidence": ["focused tests passed", "result published"],
            },
        }

        with (
            patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)),
            patch.object(
                self.mim_ui,
                "load_authoritative_request_status",
                return_value={
                    "request_id": "objective-2003-task-008",
                    "task_id": "objective-2003-task-008",
                    "request_status": "active",
                },
            ),
        ):
            snapshot = self.mim_ui._build_tod_truth_reconciliation_snapshot(
                initiative_driver={"active_objective": {"objective_id": "2003"}},
                authoritative_request={
                    "request_id": "objective-2003-task-008",
                    "task_id": "objective-2003-task-008",
                    "objective_id": "2003",
                },
            )

        self.assertEqual(snapshot["state"], "accepted_complete")
        self.assertTrue(snapshot["execution_confirmed"])
        self.assertIn("focused tests passed", snapshot["published_meaningful_evidence"])
        self.assertIn("validation succeeded", snapshot["summary"])

    def test_truth_snapshot_classifies_shared_truth_pending_refresh_as_accepted_complete(self) -> None:
        now = "2026-05-05T12:00:00Z"
        artifacts = {
            "TOD_INTEGRATION_STATUS.latest.json": {
                "mim_handshake": {"current_next_objective": "2913"},
                "live_task_request": {
                    "normalized_objective_id": "2913",
                    "task_id": "objective-2913-task-7144",
                    "request_id": "objective-2913-task-7144",
                },
            },
            "TOD_MIM_SHARED_TRUTH.latest.json": {
                "generated_at": now,
                "objective_id": "2913",
                "task_id": "objective-2913-task-7144",
                "request_id": "objective-2913-task-7144",
                "state": "ACCEPTED_COMPLETE_PENDING_MIM_REFRESH",
                "state_reason": "TOD completed with meaningful evidence, but MIM still needs a refresh.",
                "meaningful_evidence_present": True,
                "tod_view": {
                    "meaningful_evidence_present": True,
                    "meaningful_evidence": ["result_artifact"],
                },
            },
        }

        with (
            patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)),
            patch.object(
                self.mim_ui,
                "load_authoritative_request_status",
                return_value={
                    "request_id": "objective-2913-task-7144",
                    "task_id": "objective-2913-task-7144",
                    "request_status": "active",
                },
            ),
        ):
            snapshot = self.mim_ui._build_tod_truth_reconciliation_snapshot(
                initiative_driver={"active_objective": {"objective_id": "2913"}},
                authoritative_request={
                    "request_id": "objective-2913-task-7144",
                    "task_id": "objective-2913-task-7144",
                    "objective_id": "2913",
                },
            )

        self.assertEqual(snapshot["state"], "accepted_complete_pending_mim_refresh")
        self.assertTrue(snapshot["execution_confirmed"])
        self.assertEqual(snapshot["published_state_source"], "shared_truth")
        self.assertIn("needs a refresh", snapshot["summary"])

    def test_truth_snapshot_ignores_completed_mim_tod_handoff_for_active_alignment(self) -> None:
        now = "2026-05-08T02:40:11Z"
        artifacts = {
            "TOD_INTEGRATION_STATUS.latest.json": {
                "mim_handshake": {"current_next_objective": "2913"},
                "live_task_request": {
                    "normalized_objective_id": "mim-tod-handoff-smoke-001",
                    "task_id": "mim-tod-handoff-smoke-001-validation",
                    "request_id": "mim-tod-handoff-smoke-001-validation",
                },
            },
            "TOD_MIM_TASK_RESULT.latest.json": {
                "generated_at": now,
                "dispatch_kind": "mim_tod_executable_handoff",
                "handoff_id": "mim-tod-handoff-mim-request-440bf459",
                "objective_id": "mim-tod-handoff-smoke-001",
                "task_id": "mim-tod-handoff-smoke-001-validation",
                "request_id": "mim-request-440bf459",
                "status": "succeeded",
                "result_status": "succeeded",
                "result_reason": "TOD completed validation-only handoff; result handoff is ok.",
            },
        }

        with (
            patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)),
            patch.object(
                self.mim_ui,
                "load_authoritative_request_status",
                return_value={
                    "request_id": "objective-2913-task-1778207566",
                    "task_id": "objective-2913-task-1778207566",
                    "request_status": "active",
                },
            ),
        ):
            snapshot = self.mim_ui._build_tod_truth_reconciliation_snapshot(
                initiative_driver={"active_objective": {"objective_id": "2913"}},
                authoritative_request={
                    "request_id": "objective-2913-task-1778207566",
                    "task_id": "objective-2913-task-1778207566",
                    "objective_id": "2913",
                },
            )

        self.assertEqual(snapshot["canonical_objective_id"], "2913")
        self.assertEqual(snapshot["live_request_objective_id"], "2913")
        self.assertTrue(snapshot["completed_handoff_ignored_for_alignment"])
        self.assertEqual(snapshot["completed_mim_tod_handoff"]["objective_id"], "mim-tod-handoff-smoke-001")

    def test_console_freshness_reports_consumed_mim_tod_handoff_result(self) -> None:
        now = "2026-05-08T02:40:11Z"
        artifacts = {
            "TOD_MIM_TASK_RESULT.latest.json": {
                "generated_at": now,
                "dispatch_kind": "mim_tod_executable_handoff",
                "handoff_id": "mim-tod-handoff-mim-request-440bf459",
                "objective_id": "mim-tod-handoff-smoke-001",
                "task_id": "mim-tod-handoff-smoke-001-validation",
                "request_id": "mim-request-440bf459",
                "status": "succeeded",
                "result_status": "succeeded",
                "result_reason": "TOD completed validation-only handoff mim-tod-handoff-smoke-001-validation; result handoff is ok.",
            },
            "MIM_TOD_CONSUME_EVIDENCE.latest.json": {
                "generated_at": now,
                "current": {
                    "task_result": {
                        "handoff_id": "mim-tod-handoff-mim-request-440bf459",
                        "objective_id": "mim-tod-handoff-smoke-001",
                        "task_id": "mim-tod-handoff-smoke-001-validation",
                        "request_id": "mim-request-440bf459",
                        "status": "succeeded",
                        "result_status": "succeeded",
                        "result_reason": "TOD completed validation-only handoff mim-tod-handoff-smoke-001-validation; result handoff is ok.",
                    }
                },
            },
        }

        with patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)):
            freshness = self.mim_ui._mim_tod_handoff_console_freshness()

        self.assertEqual(freshness["console_freshness_status"], "fresh_done")
        self.assertEqual(freshness["last_handoff_id"], "mim-tod-handoff-mim-request-440bf459")
        self.assertEqual(freshness["last_tod_task_id"], "mim-tod-handoff-smoke-001-validation")
        self.assertEqual(freshness["last_tod_result_status"], "succeeded")
        self.assertEqual(freshness["last_consumed_at"], now)
        self.assertEqual(freshness["reply_status"], "done")

        messages = self.mim_ui._build_mim_live_worklog_messages(
            system_activity={
                "status_label": "IDLE",
                "headline": "IDLE - healthy, no live task right now",
                "console_freshness": freshness,
            },
            initiative_driver={"active_objective": {"objective_id": "2913"}},
            operator_reasoning={},
            generated_at=now,
        )
        self.assertTrue(
            any(
                "TOD handoff complete" in str(message.get("content") or "")
                and "mim-tod-handoff-smoke-001-validation" in str(message.get("content") or "")
                for message in messages
            )
        )
        messages_with_next_move = [
            str(message.get("content") or "")
            for message in messages
            if str(message.get("content") or "").startswith("Next move:")
        ]
        self.assertEqual(messages_with_next_move, [])

    def test_console_freshness_fast_path_survives_non_handoff_latest_overwrite(self) -> None:
        consumed_at = "2026-05-08T02:40:11Z"
        newer_at = "2026-05-08T02:41:00Z"
        artifacts = {
            "MIM_TOD_CONSOLE_FRESHNESS.latest.json": {
                "generated_at": consumed_at,
                "consumed_at": consumed_at,
                "dispatch_kind": "mim_tod_executable_handoff",
                "handoff_id": "mim-tod-handoff-mim-request-440bf459",
                "objective_id": "mim-tod-handoff-smoke-001",
                "task_id": "mim-tod-handoff-smoke-001-validation",
                "request_id": "mim-request-440bf459",
                "result_status": "succeeded",
                "reply_status": "done",
                "result_reason": "TOD completed validation-only handoff; result handoff is ok.",
            },
            "TOD_MIM_TASK_RESULT.latest.json": {
                "generated_at": newer_at,
                "objective_id": "2913",
                "task_id": "objective-2913-task-1778250166",
                "status": "pending",
                "result_status": "pending",
            },
            "MIM_TOD_CONSUME_EVIDENCE.latest.json": {
                "generated_at": newer_at,
                "current": {
                    "task_result": {
                        "objective_id": "2913",
                        "task_id": "objective-2913-task-1778250166",
                        "status": "pending",
                    }
                },
            },
        }

        with patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)):
            freshness = self.mim_ui._mim_tod_handoff_console_freshness()

        self.assertEqual(freshness["console_freshness_status"], "fresh_done")
        self.assertEqual(freshness["console_freshness_source"], "consumed_handoff_fast_path")
        self.assertEqual(freshness["last_handoff_id"], "mim-tod-handoff-mim-request-440bf459")
        self.assertEqual(freshness["last_tod_task_id"], "mim-tod-handoff-smoke-001-validation")
        self.assertEqual(freshness["last_consumed_at"], consumed_at)

    def test_console_freshness_fast_path_does_not_mask_newer_different_handoff(self) -> None:
        artifacts = {
            "MIM_TOD_CONSOLE_FRESHNESS.latest.json": {
                "generated_at": "2026-05-08T02:40:11Z",
                "consumed_at": "2026-05-08T02:40:11Z",
                "dispatch_kind": "mim_tod_executable_handoff",
                "handoff_id": "mim-tod-handoff-mim-request-old",
                "objective_id": "mim-tod-old",
                "task_id": "mim-tod-old-validation",
                "request_id": "mim-request-old",
                "result_status": "succeeded",
                "reply_status": "done",
            },
            "MIM_TOD_HANDOFF_RESULT.latest.json": {
                "generated_at": "2026-05-08T02:41:00Z",
                "dispatch_kind": "mim_tod_executable_handoff",
                "handoff_id": "mim-tod-handoff-mim-request-new",
                "objective_id": "mim-tod-new",
                "task_id": "mim-tod-new-validation",
                "request_id": "mim-request-new",
                "status": "pending",
                "result_status": "pending",
            },
        }

        with patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)):
            freshness = self.mim_ui._mim_tod_handoff_console_freshness()

        self.assertEqual(freshness["console_freshness_status"], "no_handoff_result")
        self.assertEqual(freshness["console_freshness_source"], "")
        self.assertEqual(freshness["last_handoff_id"], "")

    def test_console_freshness_state_exposes_done_without_full_ui_recompute(self) -> None:
        now = "2026-05-08T02:40:11Z"
        artifacts = {
            "MIM_TOD_CONSOLE_FRESHNESS.latest.json": {
                "generated_at": now,
                "consumed_at": now,
                "dispatch_kind": "mim_tod_executable_handoff",
                "handoff_id": "mim-tod-handoff-mim-request-440bf459",
                "objective_id": "mim-tod-handoff-smoke-001",
                "task_id": "mim-tod-handoff-smoke-001-validation",
                "request_id": "mim-request-440bf459",
                "result_status": "succeeded",
                "reply_status": "done",
                "result_reason": "TOD completed validation-only handoff; result handoff is ok.",
            },
        }

        with patch.object(self.mim_ui, "_load_json_artifact", side_effect=self._artifact_loader(artifacts)):
            state = self.mim_ui._build_mim_tod_console_freshness_state()

        self.assertEqual(state["console_freshness_status"], "fresh_done")
        self.assertEqual(state["system_activity"]["status_label"], "DONE")
        self.assertEqual(state["last_handoff_id"], "mim-tod-handoff-mim-request-440bf459")
        self.assertEqual(state["last_tod_task_id"], "mim-tod-handoff-smoke-001-validation")

    def test_fresh_done_worklog_suppresses_stale_next_move_recommendation(self) -> None:
        now = "2026-05-08T02:45:00Z"
        messages = self.mim_ui._build_mim_live_worklog_messages(
            system_activity={
                "status_label": "DONE",
                "headline": "DONE - latest TOD handoff result consumed",
                "console_freshness": {
                    "console_freshness_status": "fresh_done",
                    "last_handoff_id": "mim-tod-handoff-mim-request-abc",
                    "last_tod_task_id": "mim-tod-task-abc",
                    "last_tod_result_status": "succeeded",
                    "last_consumed_at": now,
                    "reply_status": "done",
                    "result_reason": "TOD completed bounded edit handoff mim-tod-task-abc; result handoff is ok.",
                },
            },
            initiative_driver={"active_objective": {"objective_id": "2913"}},
            operator_reasoning={
                "current_recommendation": {
                    "summary": "Continue Intentions Stabilization now, complete its remaining bounded tasks.",
                }
            },
            generated_at=now,
        )
        contents = [str(message.get("content") or "") for message in messages]

        self.assertTrue(any("TOD handoff complete" in content for content in contents))
        self.assertFalse(
            any(content.startswith("Next move: Continue Intentions Stabilization") for content in contents)
        )
        self.assertFalse(any(content.startswith("Current slice:") for content in contents))
        self.assertFalse(any(content.startswith("Waiting on:") for content in contents))

    def test_live_worklog_append_replaces_prior_generated_cards(self) -> None:
        now = "2026-05-08T02:46:00Z"
        chat_thread = {
            "messages": [
                {
                    "role": "operator",
                    "message_type": "user",
                    "content": "yes Continue Intentions Stabilization now",
                },
                {
                    "role": "system",
                    "message_type": "system_summary",
                    "content": "Next move: Continue Intentions Stabilization now.",
                },
                {
                    "role": "system",
                    "message_type": "system_summary",
                    "content": "Current slice: stale request is working now.",
                },
            ]
        }
        updated = self.mim_ui._append_mim_live_worklog(
            chat_thread,
            system_activity={
                "status_label": "DONE",
                "headline": "DONE - latest TOD handoff result consumed",
                "console_freshness": {
                    "console_freshness_status": "fresh_done",
                    "last_handoff_id": "mim-tod-handoff-mim-request-abc",
                    "last_tod_task_id": "mim-tod-task-abc",
                    "last_tod_result_status": "succeeded",
                    "last_consumed_at": now,
                    "reply_status": "done",
                    "result_reason": "TOD completed bounded edit handoff mim-tod-task-abc; result handoff is ok.",
                },
            },
            initiative_driver={"active_objective": {"objective_id": "2913"}},
            operator_reasoning={
                "current_recommendation": {
                    "summary": "Continue Intentions Stabilization now.",
                }
            },
            generated_at=now,
        )
        contents = [str(message.get("content") or "") for message in updated["messages"]]

        self.assertIn("yes Continue Intentions Stabilization now", contents)
        self.assertTrue(any(content.startswith("TOD handoff complete:") for content in contents))
        self.assertFalse(any(content.startswith("Next move:") for content in contents))
        self.assertFalse(any(content.startswith("Current slice:") for content in contents))
        self.assertFalse(any(content.startswith("Objective now:") for content in contents))
        self.assertFalse(any("MIM is stale" in content for content in contents))
        self.assertTrue(any("MIM is done on mim-tod-task-abc" in content for content in contents))

    def test_fresh_done_worklog_uses_handoff_target_when_task_id_missing(self) -> None:
        now = "2026-05-08T02:47:00Z"
        messages = self.mim_ui._build_mim_live_worklog_messages(
            system_activity={
                "status_label": "STALE",
                "headline": "STALE - expected work but no real progress",
                "console_freshness": {
                    "console_freshness_status": "fresh_done",
                    "last_handoff_id": "mim-tod-handoff-mim-request-abc",
                    "last_tod_result_status": "succeeded",
                    "last_consumed_at": now,
                    "reply_status": "done",
                    "result_reason": "TOD completed bounded edit handoff; result handoff is ok.",
                },
            },
            initiative_driver={"active_task": {"summary": "Implement bounded work for: handle the thing"}},
            operator_reasoning={},
            generated_at=now,
        )
        contents = [str(message.get("content") or "") for message in messages]

        self.assertTrue(
            any("MIM is done on mim-tod-handoff-mim-request-abc" in content for content in contents)
        )
        self.assertFalse(any("handle the thing" in content for content in contents))

    def test_system_activity_prefers_tod_active_state_over_idle_warning(self) -> None:
        with (
            patch.object(
                self.mim_ui,
                "_build_tod_truth_reconciliation_snapshot",
                return_value={
                    "state": "active",
                    "summary": "TOD published recent active task progress.",
                    "execution_confirmed": True,
                    "canonical_objective_id": "2003",
                    "live_request_objective_id": "2003",
                    "authoritative_source": "TOD",
                },
            ),
            patch.object(
                self.mim_ui,
                "_load_tod_execution_progress_snapshot",
                return_value={"phase_progress": {}, "stall_signal": {}},
            ),
        ):
            payload = self.mim_ui._build_system_activity_snapshot(
                initiative_driver={
                    "active_objective": {"objective_id": "2003"},
                    "activity": {"state": "idle", "summary": "No local heartbeat update."},
                },
                operator_reasoning={"execution_readiness": {"execution_allowed": True, "gate_state": "ready"}},
                runtime_health={"latest": {"captured_at": "2026-05-05T12:00:00Z"}},
                runtime_recovery={"status": "healthy"},
                authoritative_request={"objective_id": "2003", "generated_at": "2026-05-05T12:00:00Z"},
                collaboration_progress={},
                dispatch_telemetry={},
                tod_decision_process={},
            )

        self.assertEqual(payload["status_label"], "ACTIVE")
        self.assertEqual(payload["status_code"], "active")
        self.assertNotEqual(payload["headline"], "STALE - expected work but no real progress")

    def test_system_activity_surfaces_blocker_and_completion_states(self) -> None:
        for state_name, expected_label in (
            ("blocked_with_reason", "BLOCKED_WITH_REASON"),
            ("accepted_complete", "ACCEPTED_COMPLETE"),
        ):
            with self.subTest(state_name=state_name):
                with (
                    patch.object(
                        self.mim_ui,
                        "_build_tod_truth_reconciliation_snapshot",
                        return_value={
                            "state": state_name,
                            "summary": f"TOD published {state_name.replace('_', ' ')}.",
                            "execution_confirmed": True,
                            "canonical_objective_id": "2003",
                            "live_request_objective_id": "2003",
                            "authoritative_source": "TOD",
                        },
                    ),
                    patch.object(
                        self.mim_ui,
                        "_load_tod_execution_progress_snapshot",
                        return_value={"phase_progress": {}, "stall_signal": {}},
                    ),
                ):
                    payload = self.mim_ui._build_system_activity_snapshot(
                        initiative_driver={
                            "active_objective": {"objective_id": "2003"},
                            "activity": {"state": "idle"},
                        },
                        operator_reasoning={"execution_readiness": {"execution_allowed": True, "gate_state": "ready"}},
                        runtime_health={"latest": {"captured_at": "2026-05-05T12:00:00Z"}},
                        runtime_recovery={"status": "healthy"},
                        authoritative_request={"objective_id": "2003", "generated_at": "2026-05-05T12:00:00Z"},
                        collaboration_progress={},
                        dispatch_telemetry={},
                        tod_decision_process={},
                    )

                self.assertEqual(payload["status_label"], expected_label)

    def test_system_activity_prefers_shared_truth_state(self) -> None:
        with (
            patch.object(
                self.mim_ui,
                "_build_tod_truth_reconciliation_snapshot",
                return_value={
                    "state": "execution_unconfirmed",
                    "summary": "TOD has not published recent execution confirmation for the current work yet.",
                    "execution_confirmed": False,
                    "canonical_objective_id": "2003",
                    "live_request_objective_id": "2003",
                    "authoritative_source": "TOD",
                },
            ),
            patch.object(
                self.mim_ui,
                "_load_tod_execution_progress_snapshot",
                return_value={"phase_progress": {}, "stall_signal": {}},
            ),
            patch.object(
                self.mim_ui,
                "_load_shared_truth_artifact",
                return_value={
                    "state": "ACCEPTED_COMPLETE_PENDING_MIM_REFRESH",
                    "state_reason": "TOD completed with meaningful evidence, but MIM still needs a refresh.",
                    "source": "tod-mim-shared-truth-reconciler-v1",
                },
            ),
        ):
            payload = self.mim_ui._build_system_activity_snapshot(
                initiative_driver={
                    "active_objective": {"objective_id": "2003"},
                    "activity": {"state": "idle"},
                },
                operator_reasoning={"execution_readiness": {"execution_allowed": True, "gate_state": "ready"}},
                runtime_health={"latest": {"captured_at": "2026-05-05T12:00:00Z"}},
                runtime_recovery={"status": "healthy"},
                authoritative_request={"objective_id": "2003", "generated_at": "2026-05-05T12:00:00Z"},
                collaboration_progress={},
                dispatch_telemetry={},
                tod_decision_process={},
            )

        self.assertEqual(payload["status_label"], "ACCEPTED_COMPLETE_PENDING_MIM_REFRESH")
        self.assertIn("MIM still needs a refresh", payload["summary"])
        self.assertEqual(payload["shared_truth"]["state"], "ACCEPTED_COMPLETE_PENDING_MIM_REFRESH")

    def test_system_activity_keeps_stale_when_no_valid_tod_evidence_exists(self) -> None:
        with (
            patch.object(
                self.mim_ui,
                "_build_tod_truth_reconciliation_snapshot",
                return_value={
                    "state": "execution_unconfirmed",
                    "summary": "TOD has not published recent execution confirmation for the current work yet.",
                    "execution_confirmed": False,
                    "canonical_objective_id": "2003",
                    "live_request_objective_id": "2003",
                    "authoritative_source": "TOD",
                },
            ),
            patch.object(
                self.mim_ui,
                "_load_tod_execution_progress_snapshot",
                return_value={"phase_progress": {}, "stall_signal": {}},
            ),
        ):
            payload = self.mim_ui._build_system_activity_snapshot(
                initiative_driver={
                    "active_objective": {"objective_id": "2003"},
                    "activity": {"state": "stale", "summary": "Last task update is stale."},
                },
                operator_reasoning={"execution_readiness": {"execution_allowed": True, "gate_state": "ready"}},
                runtime_health={"latest": {"captured_at": "2026-05-05T12:00:00Z"}},
                runtime_recovery={"status": "healthy"},
                authoritative_request={"objective_id": "2003", "generated_at": "2026-05-05T12:00:00Z"},
                collaboration_progress={},
                dispatch_telemetry={},
                tod_decision_process={},
            )

        self.assertEqual(payload["status_label"], "STALE")
        self.assertEqual(payload["status_code"], "stale")

    def test_operator_action_controls_disable_replay_without_identity(self) -> None:
        controls = self.mim_ui._build_operator_action_controls(
            {
                "active_objective": {"id": ""},
                "active_task": {"id": ""},
                "next_validation": "",
            }
        )

        replay = next(item for item in controls if item.get("id") == "force_replay_current_task")
        validate = next(item for item in controls if item.get("id") == "validate_current_task")
        self.assertFalse(replay.get("enabled"))
        self.assertIn("missing", str(replay.get("disabled_reason") or "").lower())
        self.assertFalse(validate.get("enabled"))

    def test_operator_evidence_snapshot_prefers_latest_shared_artifact(self) -> None:
        evidence_payload = {
            "active_objective": {"id": "obj-1", "title": "Objective 1"},
            "active_task": {"id": "task-1", "title": "Task 1"},
            "artifact_timestamps": {"shared_truth": "2026-05-05T12:00:00Z"},
        }

        with patch.object(self.mim_ui, "_load_json_artifact", side_effect=lambda path: evidence_payload if Path(path).name == "TOD_OPERATOR_EVIDENCE.latest.json" else {}):
            snapshot = self.mim_ui._load_operator_evidence_snapshot(shared_root=self.mim_ui.SHARED_RUNTIME_ROOT)

        self.assertEqual(snapshot, evidence_payload)

    def test_load_mim_ui_chat_thread_degrades_when_db_is_unavailable(self) -> None:
        async def _run() -> None:
            with patch.object(
                self.mim_ui,
                "list_interface_messages",
                side_effect=ConnectionRefusedError("The remote computer refused the network connection"),
            ):
                payload = await self.mim_ui._load_mim_ui_chat_thread(db=object())

            self.assertEqual(payload["primary_thread"], self.mim_ui.MIM_PRIMARY_THREAD_KEY)
            self.assertEqual(payload["session"]["status"], "degraded")
            self.assertEqual(payload["messages"], [])

        asyncio.run(_run())

    def test_mim_ui_state_returns_degraded_payload_when_db_is_unavailable(self) -> None:
        async def _run() -> None:
            with (
                patch.object(
                    self.mim_ui,
                    "_build_live_mim_ui_state",
                    side_effect=ConnectionRefusedError("The remote computer refused the network connection"),
                ),
                patch.object(self.mim_ui, "ensure_authenticated_mimtod_api_request", return_value=None),
            ):
                payload = await self.mim_ui.mim_ui_state(request=object(), db=object())

            self.assertEqual(payload["runtime_build"], "mim-ui-degraded-no-db")
            self.assertEqual(payload["operator_reasoning"]["execution_readiness"]["gate_state"], "database_unavailable")
            self.assertEqual(payload["chat_thread"]["session"]["status"], "degraded")
            self.assertFalse(payload["latest_output_allowed"])

        asyncio.run(_run())

    def test_mim_ui_source_contains_shared_operator_action_controls(self) -> None:
        source = Path(self.mim_ui.__file__).read_text(encoding="utf-8")
        self.assertIn('id="operatorActionButtonsMim"', source)
        self.assertIn('id="operatorActionStatusMim"', source)
        self.assertIn("fetch('/operator/actions'", source)
        self.assertIn("renderOperatorActionsMim", source)

    def test_mim_ui_source_uses_lightweight_freshness_visibility_poll(self) -> None:
        source = Path(self.mim_ui.__file__).read_text(encoding="utf-8")
        self.assertIn("async function pollFreshnessVisibility()", source)
        self.assertIn("setInterval(pollFreshnessVisibility, 1000)", source)
        self.assertIn("if (document.hidden) return false;", source)

    def test_mim_ui_source_exposes_execution_lane_visibility(self) -> None:
        source = Path(self.mim_ui.__file__).read_text(encoding="utf-8")
        self.assertIn("Execution Lanes", source)
        self.assertIn("id=\"activeLaneText\"", source)
        self.assertIn("id=\"terminalLaneText\"", source)
        self.assertIn("id=\"backgroundLaneText\"", source)
        self.assertIn("function renderLaneVisibility", source)
        self.assertIn("execution_lanes", source)
        self.assertIn("active_execution_lane", source)

    def test_mim_ui_source_exposes_operational_lifecycle_visibility(self) -> None:
        source = Path(self.mim_ui.__file__).read_text(encoding="utf-8")
        self.assertIn("Operational Lifecycle", source)
        self.assertIn("id=\"lifecycleStateText\"", source)
        self.assertIn("id=\"lifecycleSatisfactionText\"", source)
        self.assertIn("id=\"lifecycleReplanText\"", source)
        self.assertIn("function renderOperationalLifecycle", source)
        self.assertIn("operational_lifecycle", source)
        self.assertIn("MIM_OPERATIONAL_REASONING_LIFECYCLE.latest.json", source)


if __name__ == "__main__":
    unittest.main()
