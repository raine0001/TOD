import ast
import json
import os
import re
import sys
import tempfile
import time
import types
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch


def _load_gateway_handoff_helpers() -> types.SimpleNamespace:
    gateway_path = Path(__file__).resolve().parents[2] / "core" / "routers" / "gateway.py"
    module_ast = ast.parse(gateway_path.read_text(encoding="utf-8"))
    helper_names = {
        "_extract_mim_tod_handoff_field",
        "_mim_tod_handoff_bool",
        "_extract_mim_tod_handoff_task_body",
        "_slugify_mim_tod_identifier",
        "_extract_mim_tod_execution_field",
        "_looks_like_mim_tod_inspect_first_request",
        "_payload_contains_value",
        "_load_mim_tod_inspection_artifacts",
        "_mim_tod_inspection_field_present",
        "_parse_iso_to_utc",
        "_mim_tod_stage_timestamp",
        "_mim_tod_timestamp_duration_ms",
        "_mim_tod_stage_durations",
        "_looks_like_mim_tod_project_architecture_plan_request",
        "_looks_like_mim_tod_lane_isolation_plan_request",
        "_looks_like_mim_tod_lane_registry_schema_request",
        "_looks_like_mim_tod_lane_visibility_step_request",
        "_looks_like_mim_tod_lane_registry_next_task_question",
        "_looks_like_generic_next_step_question",
        "_context_mentions_mim_tod_lane_registry_thread",
        "_mim_tod_lane_registry_next_step_followup_response",
        "_looks_like_mim_tod_lane_visibility_continuation_request",
        "_mim_tod_lane_visibility_continuation_response",
        "_looks_like_mim_tod_structured_step_status_query",
        "_mim_tod_structured_step_status_response",
        "_load_mim_tod_json_artifact",
        "_mim_tod_runtime_root_from_shared_root",
        "_mim_tod_first_text",
        "_mim_tod_training_activity_summary",
        "_mim_tod_lane_activity_summary",
        "_mim_tod_latest_handoff_summary",
        "_looks_like_mim_tod_activity_question",
        "_mim_tod_operator_requested_technical_detail",
        "_mim_tod_combined_activity_response",
        "_mim_tod_active_project_status_response",
        "_compact_text",
        "_compact_interface_text",
        "_mim_interface_understanding",
        "_mim_interface_status",
        "_mim_interface_next_action",
        "_mim_interface_result",
        "_mim_operator_requested_response_wrapper_detail",
        "_mim_interface_wrapper_text",
        "_mim_operator_reply_from_wrapper_text",
        "_mim_clean_operator_reply_boilerplate",
        "_mim_enforce_first_person_normal_reply",
        "_build_mim_interface_response",
        "_first_nonempty_mim_tod_value",
        "_looks_like_private_lab_sensor_project_query",
        "_private_lab_sensor_project_reply",
        "_looks_like_mim_self_model_or_operator_state_request",
        "_looks_like_mim_autonomy_roadmap_execution_request",
        "_looks_like_mim_semantic_intent_simulation_request",
        "_looks_like_tod_simulation_factory_request",
        "_looks_like_tod_useful_work_interruption_summary_request",
        "_looks_like_local_useful_work_request",
        "_create_mim_tod_lane_registry",
        "_create_mim_tod_lane_visibility_step",
        "_answer_mim_tod_lane_registry_next_task",
        "_extract_operator_requested_deliverables",
        "_operator_satisfaction_summary",
        "_mim_tod_evidence_git_lines",
        "_load_mim_tod_requested_evidence_bundle",
        "_build_mim_tod_phase_architecture_plan",
        "_build_mim_tod_lane_isolation_plan",
        "_looks_like_mim_project_document_request",
        "_looks_like_mim_project_document_status_request",
        "_looks_like_mim_operational_reasoning_lifecycle_request",
        "_looks_like_mim_operational_lifecycle_status_request",
        "_answer_mim_operational_lifecycle_status",
        "_update_mim_operational_lifecycle_turn_state",
        "_looks_like_implementation_followthrough_request",
        "_looks_like_mim_implementation_objective_request",
        "_has_followthrough_proof",
        "_mim_objective_id_matches",
        "_mim_implementation_dispatch_objective_id",
        "_mim_implementation_dispatch_target_files",
        "_mim_patch_type_selection",
        "_mim_validation_steps_for_patch",
        "_mim_first_pass_request_type",
        "_mim_first_pass_confirmation_policy",
        "_mim_first_pass_self_check",
        "_create_mim_first_pass_failure_audit",
        "_create_tod_consistency_audit_task",
        "_create_reporting_visibility_task",
        "_write_mim_operator_status",
        "_mim_tod_autonomy_capability_slice",
        "_mim_bounded_implementation_slice",
        "_mim_materialize_tod_implementation_dispatch",
        "_route_mim_implementation_objective_to_tod",
        "_mim_document_root",
        "_mim_document_index_path",
        "_slugify_mim_document_identifier",
        "_load_mim_document_index",
        "_write_mim_document_index",
        "_build_mim_project_plan_markdown",
        "_create_mim_project_document",
        "_summarize_latest_mim_project_document",
        "_create_mim_operational_reasoning_lifecycle_objective",
        "_fulfill_mim_tod_requested_evidence",
        "_build_mim_tod_accountability_workflow_trace",
        "_mim_tod_handoff_default_validation_only",
        "_looks_like_mim_tod_executable_handoff_request",
        "_deterministic_mim_tod_classifier_matches",
        "_dispatch_mim_tod_executable_handoff_request",
        "_should_use_web_research",
    }
    constant_names = {
        "REPORTING_VISIBILITY_OBJECTIVES",
    }
    helper_nodes = [
        node
        for node in module_ast.body
        if (
            isinstance(node, ast.FunctionDef)
            and node.name in helper_names
        )
        or (
            isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id in constant_names for target in node.targets)
        )
    ]
    helper_module = ast.Module(body=helper_nodes, type_ignores=[])
    ast.fix_missing_locations(helper_module)
    namespace = {
        "datetime": datetime,
        "timezone": timezone,
        "json": json,
        "Path": Path,
        "re": re,
        "time": time,
        "subprocess": __import__("subprocess"),
        "InputEvent": object,
        "InputEventResolution": object,
        "CapabilityExecution": object,
        "settings": types.SimpleNamespace(allow_web_access=True),
        "_get_json_from_local_tod": lambda *_args, **_kwargs: {},
        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
    }
    exec(compile(helper_module, str(gateway_path), "exec"), namespace)
    exported_names = set(helper_names) | constant_names
    return types.SimpleNamespace(**{name: namespace[name] for name in exported_names})


class MimTodHandoffGatewayTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gateway = _load_gateway_handoff_helpers()

    def test_inspect_first_terms_default_to_validation_before_edit(self) -> None:
        content = (
            "MIM, ask TOD to verify whether execution_direct_lane_health_state already exists "
            "in the TOD UI state. If it already exists, TOD must not edit anything. "
            "If it is missing, TOD may add it safely and validate."
        )

        self.assertTrue(self.gateway._looks_like_mim_tod_inspect_first_request(content))
        self.assertTrue(self.gateway._mim_tod_handoff_default_validation_only(content))
        self.assertTrue(self.gateway._deterministic_mim_tod_classifier_matches(content))

    def test_deterministic_classifier_rejects_unclear_tod_edit_target(self) -> None:
        content = "MIM, ask TOD to edit the thing safely, but I have not named a target file."

        self.assertFalse(self.gateway._deterministic_mim_tod_classifier_matches(content))

    def test_deterministic_classifier_accepts_execution_field_conflict_wording(self) -> None:
        content = (
            "MIM, ask TOD to use the same task identity but change the payload for "
            "execution_live_soak_payload_conflict_state. If that conflicts, block and report the exact reason."
        )

        self.assertTrue(self.gateway._deterministic_mim_tod_classifier_matches(content))

    def test_deterministic_classifier_accepts_execution_field_check_without_named_file(self) -> None:
        content = (
            "MIM, ask TOD to check whether execution_direct_lane_health_state exists and report back; "
            "treat delayed completion as pending, not stale."
        )

        self.assertTrue(self.gateway._deterministic_mim_tod_classifier_matches(content))

    def test_deterministic_classifier_accepts_operator_accountability_evidence_request(self) -> None:
        content = (
            "MIM, ask TOD to answer: what were the last 5 UI objectives, what changed in the UI, "
            "and what verifiable files were changed? Include requested_deliverables, result_quality, "
            "operator_satisfaction_status, and replan_required."
        )

        self.assertTrue(self.gateway._deterministic_mim_tod_classifier_matches(content))

    def test_deterministic_classifier_accepts_live_operator_artifact_review_request(self) -> None:
        content = (
            "MIM, review the current MIM/TOD operator UI and accountability workflow from the live system perspective. "
            "Please inspect the latest MIM/TOD communication and accountability artifacts, then return a concise "
            "operator-facing report. What was the latest MIM->TOD handoff, what did TOD do, what changed, "
            "what evidence proves the work happened, what files were changed, and are there missing outputs? "
            "Please answer in a clear numbered list."
        )

        self.assertTrue(self.gateway._deterministic_mim_tod_classifier_matches(content))

    def test_operator_deliverable_extraction_accepts_changed_files_variants(self) -> None:
        content = (
            "Return a concise operator-facing report with evidence and changed files. "
            "What files were changed, and what evidence proves the work happened?"
        )

        requested = self.gateway._extract_operator_requested_deliverables(content)

        self.assertIn("changed_files", requested)
        self.assertIn("evidence_files", requested)

    def test_project_architecture_plan_request_routes_and_returns_plan(self) -> None:
        content = (
            "MIM, I want you and TOD to act as project managers and system architects for the next phase "
            "of MIM/TOD development. Analyze the current system state, identify remaining weaknesses, "
            "prioritize them, create a realistic phased roadmap, explain dependencies and sequencing, "
            "estimate implementation difficulty/risk, and explain what should NOT be worked on yet."
        )

        self.assertTrue(self.gateway._looks_like_mim_tod_project_architecture_plan_request(content))
        self.assertTrue(self.gateway._deterministic_mim_tod_classifier_matches(content))

        def fake_get(path: str, **_kwargs):
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-execution-mim-tod-diagnostic-state-mim-request-plan",
                        "status": "completed",
                        "started_at": "2026-05-08T16:00:01Z",
                        "updated_at": "2026-05-08T16:00:02Z",
                    },
                }
            return {"execution": {}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                Path("runtime/shared").mkdir(parents=True, exist_ok=True)
                Path("core/routers").mkdir(parents=True, exist_ok=True)
                Path("core/routers/tod_ui.py").write_text("# target\n", encoding="utf-8")
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-plan",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T16:00:00Z",
                        mim_intent_classified_at="2026-05-08T16:00:00Z",
                    )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["operator_satisfaction_status"], "satisfied")
        self.assertFalse(result["replan_required"])
        self.assertIn("1. Top remaining weaknesses:", result["result_reason"])
        self.assertIn("2. Recommended priority order:", result["result_reason"])
        self.assertIn("5. Dependencies between tasks:", result["result_reason"])
        self.assertIn("10. What should NOT be worked on yet:", result["result_reason"])
        self.assertIn("Complexity / confidence / operator impact:", result["result_reason"])
        self.assertIn("phase_architecture_plan", result["delivered_outputs"])

    def test_lane_isolation_plan_request_returns_lane_specific_architecture(self) -> None:
        content = (
            "MIM and TOD, continue into controlled continuity and execution-lane isolation. "
            "Define execution lane identity, lane ownership, stale prevention, lane reconciliation, "
            "lane visibility strategy, validation strategy, and safe future bounded background work. "
            "Do not enable unrestricted parallel execution."
        )

        self.assertTrue(self.gateway._looks_like_mim_tod_lane_isolation_plan_request(content))
        requested = self.gateway._extract_operator_requested_deliverables(content)
        self.assertIn("lane_architecture", requested)
        self.assertIn("lane_reconciliation_strategy", requested)

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                result = self.gateway._build_mim_tod_phase_architecture_plan(
                    content=content,
                    shared_root=shared_root,
                    target_file="core/routers/tod_ui.py",
                    base_reason="TOD returned result handoff ok.",
                    bundle={"changed_files": ["core/routers/gateway.py"]},
                )
            finally:
                os.chdir(original_cwd)

        self.assertIn("Proposed lane architecture", result["result_text"])
        self.assertIn("State ownership model", result["result_text"])
        self.assertIn("Lane visibility strategy", result["result_text"])
        self.assertIn("MIM-TOD-LANE-REGISTRY-SCHEMA-V1", result["result_text"])
        self.assertIn("lane_architecture", result["delivered_outputs"])
        self.assertEqual(result["missing_outputs"], [])

    def test_lane_registry_schema_request_writes_artifact_without_parallel_execution(self) -> None:
        content = (
            "OBJECTIVE: MIM-TOD-LANE-REGISTRY-SCHEMA-V1\n"
            "Goal: create the lane registry without enabling parallel execution yet.\n"
            "Write runtime/shared/TOD_EXECUTION_LANES.latest.json with lane_id, lane_type, "
            "active lane, background lane, stale prevention, and operator_satisfaction_status."
        )

        self.assertTrue(self.gateway._looks_like_mim_tod_lane_registry_schema_request(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                (shared_root / "MIM_TOD_HANDOFF_RESULT.latest.json").write_text(
                    json.dumps(
                        {
                            "request_id": "mim-request-lane",
                            "handoff_id": "mim-tod-handoff-lane",
                            "objective_id": "mim-tod-lane-registry-schema-v1",
                            "task_id": "mim-tod-lane-registry-schema-v1-task",
                            "result_status": "succeeded",
                            "generated_at": "2026-05-08T22:00:00Z",
                        }
                    ),
                    encoding="utf-8",
                )
                result = self.gateway._create_mim_tod_lane_registry(
                    content=content,
                    shared_root=shared_root,
                    request_id="mim-request-lane",
                )
                artifact = json.loads((shared_root / "TOD_EXECUTION_LANES.latest.json").read_text(encoding="utf-8"))
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["result_status"], "succeeded")
        self.assertFalse(artifact["parallel_execution_enabled"])
        self.assertFalse(artifact["background_execution_enabled"])
        self.assertTrue(artifact["single_active_lane_enforced"])
        self.assertEqual(artifact["active_lane_id"], artifact["lanes"][0]["lane_id"])
        self.assertEqual(artifact["lanes"][0]["lane_type"], "active")
        self.assertEqual(artifact["lanes"][0]["task_id"], "mim-tod-lane-registry-schema-v1-task")
        self.assertTrue(artifact["stale_prevention"]["terminal_lanes_cannot_promote_without_new_request_id"])
        self.assertIn("runtime/shared/TOD_EXECUTION_LANES.latest.json", result["reply_text"])

    def test_lane_visibility_next_step_does_not_replay_lane_registry(self) -> None:
        content = (
            "MIM, create the next objective/step from the completed lane registry work. "
            "Create OBJECTIVE: MIM-TOD-LANE-VISIBILITY-UI-V1. "
            "Expose active lane and historical terminal lane in the operator UI. "
            "Keep background execution disabled."
        )

        self.assertFalse(self.gateway._looks_like_mim_tod_lane_registry_schema_request(content))
        self.assertTrue(self.gateway._looks_like_mim_tod_lane_visibility_step_request(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                    json.dumps(
                        {
                            "active_lane_id": "lane-active-demo",
                            "parallel_execution_enabled": False,
                            "background_execution_enabled": False,
                            "lanes": [
                                {
                                    "lane_id": "lane-active-demo",
                                    "lane_type": "active",
                                    "task_id": "task-demo",
                                }
                            ],
                        }
                    ),
                    encoding="utf-8",
                )
                result = self.gateway._create_mim_tod_lane_visibility_step(
                    content=content,
                    shared_root=shared_root,
                    request_id="mim-request-visibility",
                )
                artifact = json.loads((shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").read_text(encoding="utf-8"))
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["result_status"], "succeeded")
        self.assertEqual(artifact["objective_id"], "MIM-TOD-LANE-VISIBILITY-UI-V1")
        self.assertFalse(artifact["scope"]["parallel_execution_enabled"])
        self.assertFalse(artifact["scope"]["background_execution_enabled"])
        self.assertIn("MIM-TOD-LANE-VISIBILITY-UI-V1", result["reply_text"])
        self.assertIn("MIM_TOD_NEXT_OBJECTIVE.latest.json", result["reply_text"])

    def test_lane_registry_next_task_question_answers_from_artifact(self) -> None:
        content = "what is the next objective/task for MIM-TOD-LANE-REGISTRY-SCHEMA-V1"

        self.assertTrue(self.gateway._looks_like_mim_tod_lane_registry_next_task_question(content))
        self.assertFalse(self.gateway._looks_like_mim_tod_lane_registry_schema_request(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                    json.dumps(
                        {
                            "objective_id": "MIM-TOD-LANE-VISIBILITY-UI-V1",
                            "task_id": "mim-tod-lane-visibility-ui-v1-task",
                            "status": "created",
                            "goal": "Expose the lane registry in the operator UI.",
                            "source_registry": {"active_lane_id": "lane-active-demo"},
                        }
                    ),
                    encoding="utf-8",
                )
                (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                    json.dumps({"active_lane_id": "lane-active-demo"}),
                    encoding="utf-8",
                )
                result = self.gateway._answer_mim_tod_lane_registry_next_task(
                    shared_root=shared_root,
                    request_id="mim-request-next-task",
                )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["result_status"], "succeeded")
        self.assertIn("MIM-TOD-LANE-VISIBILITY-UI-V1", result["reply_text"])
        self.assertIn("mim-tod-lane-visibility-ui-v1-task", result["reply_text"])
        self.assertIn("MIM_TOD_NEXT_OBJECTIVE.latest.json", result["reply_text"])

    def test_generic_next_step_scopes_to_recent_lane_registry_thread(self) -> None:
        context = {
            "last_user_input": "what is the next objective/task for MIM-TOD-LANE-REGISTRY-SCHEMA-V1",
            "last_prompt": "The next objective is MIM-TOD-LANE-VISIBILITY-UI-V1.",
        }

        self.assertTrue(self.gateway._looks_like_generic_next_step_question("what is the next step?"))
        self.assertTrue(self.gateway._context_mentions_mim_tod_lane_registry_thread(context))

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                    json.dumps(
                        {
                            "objective_id": "MIM-TOD-LANE-VISIBILITY-UI-V1",
                            "task_id": "mim-tod-lane-visibility-ui-v1-task",
                            "status": "created",
                            "goal": "Expose the lane registry in the operator UI.",
                        }
                    ),
                    encoding="utf-8",
                )
                (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                    json.dumps({"active_lane_id": "lane-active-demo"}),
                    encoding="utf-8",
                )
                reply = self.gateway._mim_tod_lane_registry_next_step_followup_response(
                    "what is the next step?",
                    context,
                )
            finally:
                os.chdir(original_cwd)

        self.assertIn("MIM-TOD-LANE-VISIBILITY-UI-V1", reply)
        self.assertIn("mim-tod-lane-visibility-ui-v1-task", reply)
        self.assertNotIn("zone uncertainty", reply.lower())

    def test_current_work_prefers_runtime_ownership_project_artifact(self) -> None:
        context = {
            "active_goal": "Workspace state indicates zone uncertainty should be stabilized before downstream physical decisions.",
            "last_user_input": "TOD-RUNTIME-OWNERSHIP-MIGRATION-MIM-BOX-V1",
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            shared_root.mkdir(parents=True, exist_ok=True)
            (shared_root / "TOD_RUNTIME_OWNERSHIP.latest.json").write_text(
                json.dumps(
                    {
                        "objective_id": "TOD-RUNTIME-OWNERSHIP-MIGRATION-MIM-BOX-V1",
                        "status": "planning_ready",
                        "implementation_ready": False,
                        "operator_satisfaction_status": "partially_satisfied",
                        "implementation_ready_reason": "MIM box TOD listener services must be installed and validated.",
                    }
                ),
                encoding="utf-8",
            )

            reply = self.gateway._mim_tod_active_project_status_response(
                "hi mim what are you working on?",
                context,
                shared_root=shared_root,
            )

        self.assertIn("TOD runtime ownership migration", reply)
        self.assertIn("Install/verify MIM-box TOD listener", reply)
        self.assertNotIn("objective_id:", reply)
        self.assertNotIn("TOD_RUNTIME_OWNERSHIP.latest.json", reply)
        self.assertNotIn("zone uncertainty should be stabilized", reply.lower())

    def test_current_work_debug_mode_exposes_runtime_ownership_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            shared_root.mkdir(parents=True, exist_ok=True)
            (shared_root / "TOD_RUNTIME_OWNERSHIP.latest.json").write_text(
                json.dumps(
                    {
                        "objective_id": "TOD-RUNTIME-OWNERSHIP-MIGRATION-MIM-BOX-V1",
                        "status": "planning_ready",
                        "implementation_ready": False,
                        "operator_satisfaction_status": "partially_satisfied",
                    }
                ),
                encoding="utf-8",
            )

            reply = self.gateway._mim_tod_active_project_status_response(
                "debug mode: what are you working on? show technical details",
                {"last_user_input": "TOD-RUNTIME-OWNERSHIP-MIGRATION-MIM-BOX-V1"},
                shared_root=shared_root,
            )

        self.assertIn("Technical MIM/TOD focus", reply)
        self.assertIn("objective_id:", reply)
        self.assertIn("TOD_RUNTIME_OWNERSHIP.latest.json", reply)

    def test_operator_interface_response_hides_wrapper_by_default(self) -> None:
        event = types.SimpleNamespace(
            id=7,
            source="text",
            raw_input="Hi MIM, what are you and TOD working on?",
            metadata_json={"request_id": "mim-request-cleanup"},
        )
        resolution = types.SimpleNamespace(
            internal_intent="conversation",
            proposed_goal_description="",
            outcome="store_only",
            reason="conversation_bounded_implementation_dispatch",
            clarification_prompt="MIM and TOD are both active.",
            metadata_json={
                "mim_interface_status_override": "done",
                "mim_interface_next_action_override": "reply directly",
                "mim_interface_result_override": "MIM and TOD are both active.",
                "mim_interface_reply_override": (
                    "Request mim-request-cleanup. I understood: Hi MIM. "
                    "Next action: reply directly. Status: done. "
                    "Result: MIM and TOD are both active."
                ),
            },
        )

        response = self.gateway._build_mim_interface_response(
            event=event,
            resolution=resolution,
            execution=None,
        )

        self.assertEqual(response["reply_text"], "MIM and TOD are both active.")
        self.assertNotIn("Request mim-request-cleanup", response["reply_text"])
        self.assertNotIn("I understood", response["reply_text"])
        self.assertNotIn("Next action", response["reply_text"])
        self.assertIn("internal_envelope", response)
        self.assertEqual(
            response["internal_envelope"]["request_id"],
            "mim-request-cleanup",
        )

    def test_operator_interface_response_exposes_wrapper_when_requested(self) -> None:
        event = types.SimpleNamespace(
            id=8,
            source="text",
            raw_input="debug mode: show request id and response wrapper details",
            metadata_json={"request_id": "mim-request-debug"},
        )
        resolution = types.SimpleNamespace(
            internal_intent="conversation",
            proposed_goal_description="",
            outcome="store_only",
            reason="conversation_bounded_implementation_dispatch",
            clarification_prompt="MIM and TOD are both active.",
            metadata_json={
                "mim_interface_status_override": "done",
                "mim_interface_next_action_override": "reply directly",
                "mim_interface_result_override": "MIM and TOD are both active.",
            },
        )

        response = self.gateway._build_mim_interface_response(
            event=event,
            resolution=resolution,
            execution=None,
        )

        self.assertIn("Request mim-request-debug", response["reply_text"])
        self.assertIn("I understood:", response["reply_text"])
        self.assertIn("Next action:", response["reply_text"])
        self.assertIn("Status: done", response["reply_text"])
        self.assertIn("Result: MIM and TOD are both active.", response["reply_text"])

    def test_operator_interface_response_does_not_treat_task_id_as_debug_by_itself(self) -> None:
        event = types.SimpleNamespace(
            id=9,
            source="text",
            raw_input=(
                "OBJECTIVE: MIM-IMPLEMENTATION-DISPATCH-GATE\n"
                "REQUIRED BEHAVIOR: include objective_id and task_id in the TOD request."
            ),
            metadata_json={"request_id": "mim-request-normal-objective"},
        )
        resolution = types.SimpleNamespace(
            internal_intent="conversation",
            proposed_goal_description="",
            outcome="store_only",
            reason="mim_operational_lifecycle_status_answered",
            clarification_prompt="Dispatched to TOD.",
            metadata_json={
                "mim_interface_status_override": "done",
                "mim_interface_next_action_override": "create TOD request",
                "mim_interface_result_override": "Dispatched to TOD.",
            },
        )

        response = self.gateway._build_mim_interface_response(
            event=event,
            resolution=resolution,
            execution=None,
        )

        self.assertEqual(response["reply_text"], "Dispatched to TOD.")
        self.assertNotIn("I understood", response["reply_text"])
        self.assertNotIn("Next action", response["reply_text"])

    def test_mim_tod_activity_question_reports_specific_artifact_state(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runtime_root = Path(temp_dir) / "runtime"
            shared_root = runtime_root / "shared"
            reports_root = runtime_root / "reports"
            shared_root.mkdir(parents=True, exist_ok=True)
            reports_root.mkdir(parents=True, exist_ok=True)
            (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                json.dumps(
                    {
                        "objective_id": "MIM-CONFIDENCE-AND-CONVERSATIONAL-BALANCE-V1",
                        "task_id": "mim-confidence-training-window",
                        "status": "running",
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                json.dumps(
                    {
                        "active_lane_id": "lane-active-training",
                        "background_execution_enabled": False,
                        "lanes": [
                            {
                                "lane_id": "lane-active-training",
                                "objective_id": "MIM-CONFIDENCE-AND-CONVERSATIONAL-BALANCE-V1",
                                "task_id": "mim-confidence-training-window",
                                "status": "running",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_MIM_TASK_RESULT.latest.json").write_text(
                json.dumps(
                    {
                        "task_id": "tod-idle-training-burst",
                        "result_status": "running",
                        "summary": "TOD is running synthetic idle training.",
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "MIM_TOD_CONSUME_EVIDENCE.latest.json").write_text(
                json.dumps({"reply_status": "pending"}),
                encoding="utf-8",
            )
            (shared_root / "TOD_TRAINING_STATUS.latest.json").write_text(
                json.dumps(
                    {
                        "state": "running",
                        "phase": "synthetic_simulation",
                        "run_id": "tod-synthetic-training-test",
                    }
                ),
                encoding="utf-8",
            )
            (reports_root / "mim_evolution_continuous_training.latest.json").write_text(
                json.dumps(
                    {
                        "status": "running",
                        "phase": "simulation_running",
                        "cycle": 42,
                        "target_conversations": 125,
                    }
                ),
                encoding="utf-8",
            )
            (reports_root / "mim_evolution_training_summary.json").write_text(
                json.dumps(
                    {
                        "conversation": {
                            "overall": 0.8641,
                            "top_failures": [{"tag": "low_relevance", "count": 8}],
                        }
                    }
                ),
                encoding="utf-8",
            )

            reply = self.gateway._mim_tod_active_project_status_response(
                "what are you and tod working on?",
                {},
                shared_root=shared_root,
            )

        self.assertIn("MIM:", reply)
        self.assertIn("TOD:", reply)
        self.assertIn("conversation confidence tuning", reply)
        self.assertNotIn("MIM-CONFIDENCE-AND-CONVERSATIONAL-BALANCE-V1", reply)
        self.assertIn("last score 0.8641", reply)
        self.assertIn("low_relevance", reply)
        self.assertNotIn("mim-confidence-training-window", reply)
        self.assertNotIn("tod-idle-training-burst", reply)
        self.assertNotIn("task_id", reply)
        self.assertNotIn("TOD_TRAINING_STATUS.latest.json", reply)
        self.assertNotIn("runtime is stable and the microphone is idle", reply.lower())

    def test_mim_tod_activity_debug_question_preserves_raw_artifact_detail(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runtime_root = Path(temp_dir) / "runtime"
            shared_root = runtime_root / "shared"
            reports_root = runtime_root / "reports"
            shared_root.mkdir(parents=True, exist_ok=True)
            reports_root.mkdir(parents=True, exist_ok=True)
            (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                json.dumps(
                    {
                        "objective_id": "MIM-CONFIDENCE-AND-CONVERSATIONAL-BALANCE-V1",
                        "task_id": "mim-confidence-training-window",
                        "status": "running",
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                json.dumps(
                    {
                        "active_lane_id": "lane-active-training",
                        "background_execution_enabled": False,
                        "lanes": [
                            {
                                "lane_id": "lane-active-training",
                                "task_id": "mim-confidence-training-window",
                                "status": "running",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_MIM_TASK_RESULT.latest.json").write_text(
                json.dumps(
                    {
                        "task_id": "tod-idle-training-burst",
                        "result_status": "running",
                    }
                ),
                encoding="utf-8",
            )

            reply = self.gateway._mim_tod_active_project_status_response(
                "debug mode: show the technical request ids and raw details for what TOD is doing",
                {},
                shared_root=shared_root,
            )

        self.assertIn("Technical MIM/TOD activity snapshot", reply)
        self.assertIn("mim-confidence-training-window", reply)
        self.assertIn("tod-idle-training-burst", reply)
        self.assertIn("TOD_EXECUTION_LANES.latest.json", reply)

    def test_mim_tod_adaptive_status_prompts_use_distinct_shapes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            runtime_root = Path(temp_dir) / "runtime"
            shared_root = runtime_root / "shared"
            reports_root = runtime_root / "reports"
            shared_root.mkdir(parents=True, exist_ok=True)
            reports_root.mkdir(parents=True, exist_ok=True)
            (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                json.dumps({"objective_id": "MIM-SITUATIONAL-RESPONSE-TONE-V1"}),
                encoding="utf-8",
            )
            (shared_root / "TOD_MIM_TASK_RESULT.latest.json").write_text(
                json.dumps(
                    {
                        "objective_id": "MIM-SITUATIONAL-RESPONSE-TONE-V1",
                        "completion_status": "completed_with_evidence",
                        "changed_files": [
                            "runtime/shared/reporting_behavior/MIM-SITUATIONAL-RESPONSE-TONE-V1.latest.json"
                        ],
                        "validation_results": [{"status": "passed"}],
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_CONSISTENCY_AUDIT.latest.json").write_text(
                json.dumps({"risk_level": "medium", "findings_count": 2}),
                encoding="utf-8",
            )
            (reports_root / "mim_evolution_training_summary.json").write_text(
                json.dumps(
                    {
                        "conversation": {
                            "overall": 0.8614,
                            "top_failures": [{"tag": "missing_confirmation"}],
                        }
                    }
                ),
                encoding="utf-8",
            )

            casual = self.gateway._mim_tod_active_project_status_response(
                "What are you guys working on?",
                {},
                shared_root=shared_root,
            )
            concern = self.gateway._mim_tod_active_project_status_response(
                "Should I be worried?",
                {},
                shared_root=shared_root,
            )
            technical = self.gateway._mim_tod_active_project_status_response(
                "Why did objective 2913 stall?",
                {},
                shared_root=shared_root,
            )
            delta = self.gateway._mim_tod_active_project_status_response(
                "Any change since last update?",
                {},
                shared_root=shared_root,
            )

        self.assertIn("MIM is focused", casual)
        self.assertIn("TOD just proved", casual)
        self.assertNotIn("Evidence:", casual)
        self.assertIn("Severity: watch item", concern)
        self.assertIn("No urgent blocker", concern)
        self.assertIn("Stall diagnosis:", technical)
        self.assertIn("Evidence:", technical)
        self.assertIn("Recovery path", technical)
        self.assertIn("Delta:", delta)
        self.assertNotIn("Training last score", delta)

    def test_lane_visibility_continuation_stays_in_project_context(self) -> None:
        content = (
            "continue to the next step - Implement the UI visibility slice and "
            "validate refresh/reload lane identity."
        )
        context = {
            "last_user_input": "what is the next objective/task for MIM-TOD-LANE-REGISTRY-SCHEMA-V1",
            "last_prompt": "The next objective is MIM-TOD-LANE-VISIBILITY-UI-V1.",
        }

        self.assertTrue(
            self.gateway._looks_like_mim_tod_lane_visibility_continuation_request(
                content,
                context,
            )
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                    json.dumps(
                        {
                            "objective_id": "MIM-TOD-LANE-VISIBILITY-UI-V1",
                            "task_id": "mim-tod-lane-visibility-ui-v1-task",
                            "status": "created",
                        }
                    ),
                    encoding="utf-8",
                )
                (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                    json.dumps({"active_lane_id": "lane-active-demo"}),
                    encoding="utf-8",
                )
                reply = self.gateway._mim_tod_lane_visibility_continuation_response(
                    content,
                    context,
                )
            finally:
                os.chdir(original_cwd)

        self.assertIn("MIM-TOD-LANE-VISIBILITY-UI-V1", reply)
        self.assertIn("mim-tod-lane-visibility-ui-v1-task", reply)
        self.assertIn("No web research", reply)
        self.assertIn("No parallel/background execution", reply)
        self.assertNotIn("research that on the web", reply.lower())

    def test_complete_ui_patch_continues_lane_visibility_context(self) -> None:
        content = "complete the UI patch"
        context = {
            "last_user_input": "what is the status of 1 structured step",
            "last_prompt": "Current step:\n- objective_id: MIM-TOD-LANE-VISIBILITY-UI-V1\n- status: staged / ready for bounded UI implementation",
        }

        self.assertTrue(
            self.gateway._looks_like_mim_tod_lane_visibility_continuation_request(
                content,
                {},
            )
        )
        self.assertTrue(
            self.gateway._looks_like_mim_tod_lane_visibility_continuation_request(
                content,
                context,
            )
        )

    def test_structured_step_status_reports_lane_visibility_step(self) -> None:
        content = "what is the status of 1 structured step"
        context = {
            "last_prompt": "Understood. I'll continue with the lane-visibility UI slice.\n\nObjective:\n- MIM-TOD-LANE-VISIBILITY-UI-V1"
        }

        self.assertTrue(self.gateway._looks_like_mim_tod_structured_step_status_query(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            shared_root.mkdir(parents=True, exist_ok=True)
            (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").write_text(
                json.dumps(
                    {
                        "objective_id": "MIM-TOD-LANE-VISIBILITY-UI-V1",
                        "task_id": "mim-tod-lane-visibility-ui-v1-task",
                        "status": "created",
                        "goal": "Expose the lane registry in the operator UI.",
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_EXECUTION_LANES.latest.json").write_text(
                json.dumps({"active_lane_id": "lane-active-demo"}),
                encoding="utf-8",
            )
            reply = self.gateway._mim_tod_structured_step_status_response(
                shared_root=shared_root,
                context=context,
            )

        self.assertIn("Status of the structured step", reply)
        self.assertIn("MIM-TOD-LANE-VISIBILITY-UI-V1", reply)
        self.assertIn("mim-tod-lane-visibility-ui-v1-task", reply)
        self.assertIn("not proof that the UI patch is complete yet", reply)
        self.assertIn("lane-active-demo", reply)
        self.assertNotIn("online and functioning", reply.lower())

    def test_mim_project_document_request_creates_document_and_index(self) -> None:
        content = (
            "MIM, create a formal project plan document for the next phase of MIM/TOD development. "
            "Include priorities, phases, dependencies, and what should happen next."
        )

        self.assertTrue(self.gateway._looks_like_mim_project_document_request(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                result = self.gateway._create_mim_project_document(
                    content=content,
                    shared_root=shared_root,
                )
                document = result["document"]
                document_path = Path(str(document["path"]))
                index_path = Path(str(result["index_path"]))
                markdown = document_path.read_text(encoding="utf-8")
                index_payload = json.loads(index_path.read_text(encoding="utf-8"))
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["status"], "done")
        self.assertIn("I created a formal document record.", result["reply_text"])
        self.assertIn("runtime", str(document["relative_path"]))
        self.assertIn("# MIM/TOD Next Phase Project Plan", markdown)
        self.assertIn("## Recommended Priority Order", markdown)
        self.assertEqual(index_payload["latest_document_id"], document["document_id"])
        self.assertEqual(index_payload["documents"][0]["document_id"], document["document_id"])

    def test_mim_project_document_status_uses_latest_indexed_plan(self) -> None:
        create_content = "MIM, create a project plan document for MIM/TOD."
        status_content = "MIM, where are we in development of that plan and what is next?"

        self.assertTrue(self.gateway._looks_like_mim_project_document_status_request(status_content))

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                created = self.gateway._create_mim_project_document(
                    content=create_content,
                    shared_root=shared_root,
                )
                summary = self.gateway._summarize_latest_mim_project_document(shared_root=shared_root)
            finally:
                os.chdir(original_cwd)

        self.assertEqual(summary["status"], "done")
        self.assertEqual(summary["document"]["document_id"], created["document"]["document_id"])
        self.assertIn("latest project plan record", summary["reply_text"])
        self.assertIn("What should happen next:", summary["reply_text"])

    def test_operational_reasoning_lifecycle_objective_writes_skillset_artifacts(self) -> None:
        content = (
            "MIM, create the operational reasoning lifecycle skillset objective. "
            "It should develop explicit layers between understanding, initiative continuity, "
            "execution, proof, and satisfaction. The process is interpret, continue, execute, "
            "validate, resume, revisit, reconcile, finish."
        )

        self.assertTrue(self.gateway._looks_like_mim_operational_reasoning_lifecycle_request(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content=content,
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            lifecycle = json.loads(
                (shared_root / "MIM_OPERATIONAL_REASONING_LIFECYCLE.latest.json").read_text(
                    encoding="utf-8"
                )
            )
            next_objective = json.loads(
                (shared_root / "MIM_TOD_NEXT_OBJECTIVE.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(result["status"], "done")
        self.assertEqual(lifecycle["objective_id"], "MIM-OPERATIONAL-REASONING-LIFECYCLE-V1")
        self.assertIn("interpret", lifecycle["process"])
        self.assertIn("proof", lifecycle["reasoning_layers"])
        self.assertIn("satisfaction", lifecycle["reasoning_layers"])
        self.assertIn("DONE requires", " ".join(lifecycle["completion_policy"]))
        self.assertEqual(next_objective["objective_id"], lifecycle["objective_id"])
        self.assertIn("operator-visible lifecycle status", next_objective["next_step"])
        self.assertIn("MIM_OPERATIONAL_REASONING_LIFECYCLE.latest.json", result["reply_text"])

    def test_operational_reasoning_lifecycle_updates_turn_state(self) -> None:
        content = "MIM, create the operational reasoning lifecycle skillset objective."

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content=content,
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            updated = self.gateway._update_mim_operational_lifecycle_turn_state(
                shared_root=shared_root,
                request_id="mim-request-followup",
                raw_input="what is the lifecycle status?",
                resolution_reason="mim_operational_reasoning_lifecycle_status",
                resolution_outcome="store_only",
                resolution_status="completed",
                metadata={},
            )
            persisted = json.loads(
                (shared_root / "MIM_OPERATIONAL_REASONING_LIFECYCLE.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(updated["state_contract"]["request_id"], "mim-request-followup")
        self.assertEqual(persisted["state_contract"]["lifecycle_state"], "finish")
        self.assertEqual(persisted["state_contract"]["operator_satisfaction_status"], "satisfied")
        self.assertFalse(persisted["state_contract"]["replan_required"])
        self.assertEqual(persisted["recent_turns"][0]["request_id"], "mim-request-followup")

    def test_implementation_objective_without_proof_requires_revisit(self) -> None:
        content = (
            "OBJECTIVE: MIM-CONVERSATIONAL-ABSTRACTION-LAYER\n"
            "GOAL: Separate internal execution artifacts from operator-facing responses.\n"
            "VALIDATION: normal operator question returns conversational summary."
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content="create lifecycle",
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            updated = self.gateway._update_mim_operational_lifecycle_turn_state(
                shared_root=shared_root,
                request_id="mim-request-abstraction",
                raw_input=content,
                resolution_reason="tod_objective_summary_next_step_dispatch",
                resolution_outcome="store_only",
                resolution_status="store_only",
                metadata={},
            )

        self.assertEqual(updated["state_contract"]["lifecycle_state"], "revisit")
        self.assertEqual(
            updated["state_contract"]["operator_satisfaction_status"],
            "implementation_not_proven",
        )
        self.assertTrue(updated["state_contract"]["replan_required"])
        self.assertIn("implementation proof", updated["state_contract"]["missing_outputs"])

    def test_implementation_objective_without_proof_materializes_tod_dispatch(self) -> None:
        content = (
            "OBJECTIVE: MIM-IMPLEMENTATION-DISPATCH-GATE\n\n"
            "GOAL: Force implementation objectives into TOD bounded edit execution.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "When implementation_not_proven is detected, create MIM_TOD_TASK_REQUEST.latest.json for TOD.\n"
            "TARGET_FILE: core/routers/gateway.py\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content="create lifecycle",
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            updated = self.gateway._update_mim_operational_lifecycle_turn_state(
                shared_root=shared_root,
                request_id="mim-request-dispatch-gate",
                raw_input=content,
                resolution_reason="mim_operational_lifecycle_status_answered",
                resolution_outcome="store_only",
                resolution_status="completed",
                metadata={},
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["objective_id"], "MIM-IMPLEMENTATION-DISPATCH-GATE")
        self.assertIn("mim-request-dispatch-gate", request_artifact["task_id"])
        self.assertEqual(request_artifact["task_class"], "implementation")
        self.assertEqual(request_artifact["result_status"], "pending")
        self.assertEqual(request_artifact["target"], "TOD")
        self.assertIn("core/routers/gateway.py", request_artifact["target_files"])
        self.assertTrue(request_artifact["completion_gate"]["reject_service_status_only"])
        self.assertEqual(
            updated["state_contract"]["implementation_dispatch"]["status"],
            "dispatched_to_TOD",
        )
        self.assertEqual(updated["state_contract"]["operator_summary"], "dispatched_to_TOD")
        self.assertEqual(
            updated["state_contract"]["operator_satisfaction_status"],
            "implementation_not_proven",
        )

    def test_implementation_objective_classifier_outranks_lifecycle_status_words(self) -> None:
        content = (
            "OBJECTIVE: MIM-OBJECTIVE-ROUTING-AUDIT-AND-CORRECTION\n\n"
            "GOAL:\n"
            "Ensure implementation objectives route to executable gates automatically instead of "
            "lifecycle/status/project-document handling.\n\n"
            "SUCCESS:\n"
            "When operator provides an implementation objective, MIM must classify it as implementation, "
            "dispatch it, and produce evidence or honest blocked state without manual rescue.\n"
        )

        self.assertTrue(self.gateway._looks_like_mim_implementation_objective_request(content))
        self.assertFalse(self.gateway._looks_like_mim_operational_lifecycle_status_request(content))
        self.assertFalse(self.gateway._looks_like_mim_project_document_request(content))

    def test_implementation_objective_route_writes_current_tod_request(self) -> None:
        content = (
            "OBJECTIVE: MIM-OBJECTIVE-ROUTING-AUDIT-AND-CORRECTION\n\n"
            "GOAL: Ensure implementation objectives route to executable gates automatically.\n"
            "SUCCESS: classify it as implementation, dispatch it, and produce evidence or honest blocked state.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-routing-audit",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertIn("Dispatched to TOD", result["reply_text"])
        self.assertEqual(
            request_artifact["objective_id"],
            "MIM-OBJECTIVE-ROUTING-AUDIT-AND-CORRECTION",
        )
        self.assertEqual(request_artifact["task_class"], "implementation")
        self.assertEqual(request_artifact["result_status"], "pending")
        self.assertEqual(request_artifact["target"], "TOD")
        self.assertEqual(request_artifact["next_action"], "tod_bounded_edit_attempt_required")

    def test_bounded_implementation_slice_generator_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-BOUNDED-IMPLEMENTATION-SLICE-GENERATOR\n\n"
            "GOAL:\n"
            "Teach MIM to convert broad implementation requests into one small executable bounded slice.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "Given an implementation objective, MIM must produce:\n"
            "- target component\n"
            "- likely target files\n"
            "- one bounded change\n"
            "- expected evidence\n"
            "- validation command or check\n"
            "- rollback/isolation note\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-slice-generator",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertEqual(
            request_artifact["target_component"],
            "MIM bounded implementation slice generator",
        )
        self.assertIn("core/routers/gateway.py", request_artifact["likely_target_files"])
        self.assertIn(
            "tests/integration/test_mim_tod_handoff_gateway.py",
            request_artifact["likely_target_files"],
        )
        self.assertIn("one target component", request_artifact["bounded_change"])
        self.assertIn("expected_evidence", request_artifact)
        self.assertTrue(request_artifact["expected_evidence"])
        self.assertIn("test_bounded_implementation_slice_generator", request_artifact["validation_command"])
        self.assertIn("rollback", request_artifact["rollback_isolation_note"].lower())
        self.assertEqual(request_artifact["bounded_slice"]["target_component"], request_artifact["target_component"])
        self.assertIn("Bounded implementation slice:", request_artifact["task"])

    def test_likely_fix_path_inference_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-LIKELY-FIX-PATH-INFERENCE\n\n"
            "GOAL:\n"
            "Teach MIM to infer the most likely repair path from observed failure evidence.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "Given logs, artifacts, symptoms, or failed validation, MIM must identify:\n"
            "- probable root cause\n"
            "- supporting evidence\n"
            "- least risky fix path\n"
            "- files to inspect first\n"
            "- confidence level\n\n"
            "SUCCESS:\n"
            "MIM proposes a concrete fix path before escalating to Codex.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-likely-fix-path",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertTrue(self.gateway._looks_like_mim_implementation_objective_request(content))
        self.assertFalse(self.gateway._should_use_web_research(content))
        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertEqual(request_artifact["target_component"], "MIM likely fix path inference")
        self.assertIn("core/routers/gateway.py", request_artifact["files_to_inspect_first"])
        self.assertIn("probable_root_cause", request_artifact)
        self.assertIn("web research fallback", " ".join(request_artifact["supporting_evidence"]))
        self.assertIn("classifier", request_artifact["least_risky_fix_path"])
        self.assertEqual(request_artifact["confidence_level"], "high")
        self.assertIn("test_likely_fix_path_inference", request_artifact["validation_command"])

    def test_alternative_choice_engine_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-ALTERNATIVE-CHOICE-ENGINE\n\n"
            "GOAL:\n"
            "Teach MIM to compare multiple possible next actions and select one.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "For any non-obvious repair, MIM must list:\n"
            "- option A\n"
            "- option B\n"
            "- option C if useful\n"
            "- risk of each\n"
            "- expected evidence of success\n"
            "- selected option\n"
            "- reason selected\n\n"
            "SUCCESS:\n"
            "MIM makes a defensible choice instead of defaulting to status/lifecycle handling.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-choice-engine",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertTrue(self.gateway._looks_like_mim_implementation_objective_request(content))
        self.assertFalse(self.gateway._looks_like_mim_operational_lifecycle_status_request(content))
        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertEqual(request_artifact["target_component"], "MIM alternative choice engine")
        self.assertEqual(request_artifact["selected_option"], "A")
        self.assertIn("least risky", request_artifact["reason_selected"])
        self.assertEqual([item["option"] for item in request_artifact["repair_options"]], ["A", "B", "C"])
        self.assertIn("risk", request_artifact["repair_options"][0])
        self.assertIn("expected_evidence", request_artifact["repair_options"][0])
        self.assertIn("test_alternative_choice_engine", request_artifact["validation_command"])

    def test_confidence_estimation_for_action_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-CONFIDENCE-ESTIMATION-FOR-ACTION\n\n"
            "GOAL:\n"
            "Teach MIM to attach confidence to proposed actions.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "Every proposed implementation path must include:\n"
            "- confidence score: low / medium / high\n"
            "- evidence basis\n"
            "- uncertainty\n"
            "- what would increase confidence\n"
            "- whether action is safe to dispatch\n\n"
            "SUCCESS:\n"
            "MIM can act when confidence is sufficient and escalate when it is not.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-confidence-action",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertTrue(self.gateway._looks_like_mim_implementation_objective_request(content))
        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertEqual(request_artifact["target_component"], "MIM confidence estimation for action")
        self.assertEqual(request_artifact["confidence_score"], "high")
        self.assertTrue(request_artifact["evidence_basis"])
        self.assertIn("local implementation", " ".join(request_artifact["evidence_basis"]))
        self.assertIn("blocked_with_inspection", request_artifact["uncertainty"])
        self.assertIn("changed_files", request_artifact["what_would_increase_confidence"])
        self.assertTrue(request_artifact["safe_to_dispatch"])
        self.assertIn("test_confidence_estimation_for_action", request_artifact["validation_command"])

    def test_minimal_patch_planner_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-MINIMAL-PATCH-PLANNER\n\n"
            "GOAL: Teach MIM to plan the smallest safe patch that can prove or disprove a fix.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "- minimal edit scope\n"
            "- files expected to change\n"
            "- files explicitly out of scope\n"
            "- validation plan\n"
            "- failure fallback\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-minimal-patch",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["target_component"], "MIM minimal patch planner")
        self.assertIn("One helper branch", request_artifact["minimal_edit_scope"])
        self.assertIn("core/routers/gateway.py", request_artifact["files_expected_to_change"])
        self.assertIn("core/handoff_intake_service.py", request_artifact["files_explicitly_out_of_scope"])
        self.assertTrue(request_artifact["validation_plan"])
        self.assertIn("do not broaden scope", request_artifact["failure_fallback"])

    def test_tradeoff_evaluation_loop_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-TRADEOFF-EVALUATION-LOOP\n\n"
            "GOAL: Teach MIM to evaluate tradeoffs before choosing an implementation path.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "- risk\n"
            "- complexity\n"
            "- reversibility\n"
            "- validation ease\n"
            "- chance of solving root cause\n"
            "- chance of causing regression\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-tradeoff",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["target_component"], "MIM tradeoff evaluation loop")
        self.assertEqual(request_artifact["selected_implementation_path"], "A")
        self.assertEqual([item["candidate"] for item in request_artifact["candidate_fix_tradeoffs"]], ["A", "B", "C"])
        self.assertIn("chance_of_solving_root_cause", request_artifact["candidate_fix_tradeoffs"][0])
        self.assertIn("chance_of_causing_regression", request_artifact["candidate_fix_tradeoffs"][0])

    def test_repair_pattern_learning_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: MIM-REPAIR-PATTERN-LEARNING\n\n"
            "GOAL: Teach MIM to learn from successful repair patterns and reuse them.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "- symptom pattern\n"
            "- failed path\n"
            "- successful path\n"
            "- files involved\n"
            "- validation used\n"
            "- reusable lesson\n"
            "- future trigger conditions\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-pattern-learning",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["target_component"], "MIM repair pattern learning")
        self.assertIn("Implementation-style", request_artifact["symptom_pattern"])
        self.assertIn("lifecycle", request_artifact["failed_path"])
        self.assertIn("deterministic", request_artifact["successful_path"])
        self.assertIn("core/routers/gateway.py", request_artifact["files_involved"])
        self.assertTrue(request_artifact["validation_used"])
        self.assertIn("required operator-facing fields", request_artifact["reusable_lesson"])
        self.assertTrue(request_artifact["future_trigger_conditions"])

    def test_tod_safe_local_patch_application_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: TOD-SAFE-LOCAL-PATCH-APPLICATION-V1\n\n"
            "GOAL: Allow TOD to apply a small local patch only when MIM provides a minimal patch plan, "
            "tradeoff assessment, expected changed files, validation plan, and confidence is sufficient.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "- minimal_patch_plan exists\n"
            "- expected_changed_files are specific and safe\n"
            "- out_of_scope files are defined\n"
            "- validation_plan exists\n"
            "- selected tradeoff path is present\n"
            "- confidence is medium/high\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-safe-local-patch",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["target_component"], "TOD safe local patch application")
        self.assertEqual(request_artifact["minimal_patch_plan"]["edit_mode"], "replace_exact_text")
        self.assertEqual(request_artifact["expected_changed_files"], ["scripts/mim_box_tod_packet_listener.py"])
        self.assertIn("core/routers/gateway.py", request_artifact["out_of_scope_files"])
        self.assertTrue(request_artifact["validation_plan"])
        self.assertEqual(request_artifact["selected_tradeoff_path"], "A")
        self.assertEqual(request_artifact["confidence"], "high")
        self.assertEqual(request_artifact["selected_implementation_path"], "A")

    def test_tod_safe_local_patch_generalization_dispatch_fields(self) -> None:
        content = (
            "OBJECTIVE: TOD-SAFE-LOCAL-PATCH-GENERALIZATION-V1\n\n"
            "GOAL: Expand TOD's safe local patch executor from exact-text patching to a small set "
            "of controlled patch types while preserving evidence-gated completion.\n\n"
            "SUPPORTED PATCH TYPES:\n"
            "1. exact_text_replace\n"
            "2. append_guard_block\n"
            "3. insert_after_anchor\n"
            "4. update_literal_value\n"
            "5. add_test_case_block\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-safe-local-patch-generalization",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["target_component"], "TOD safe local patch generalization")
        self.assertEqual(request_artifact["minimal_patch_plan"]["edit_mode"], "insert_before_anchor")
        self.assertEqual(request_artifact["patch_type"], "insert_before_anchor")
        self.assertIn("exact_text_replace", request_artifact["supported_patch_types"])
        self.assertIn("insert_before_anchor", request_artifact["supported_patch_types"])
        self.assertIn("add_test_case_block", request_artifact["supported_patch_types"])
        self.assertEqual(request_artifact["expected_changed_files"], ["scripts/mim_box_tod_packet_listener.py"])
        self.assertEqual(request_artifact["selected_tradeoff_path"], "A")
        self.assertEqual(request_artifact["confidence"], "high")
        self.assertTrue(request_artifact["rollback_note"])

    def test_patch_type_selection_reasoning_dispatch_fields(self) -> None:
        cases = [
            ("Add guard-before behavior before an existing block.", "insert_before_anchor"),
            ("Add post-action behavior after a stable existing block.", "insert_after_anchor"),
            ("Update a config value literal safely.", "update_literal_value"),
            ("Add standalone safety block for idempotent guard logic.", "append_guard_block"),
            ("Add test-only focused test coverage.", "add_test_case_block"),
            ("Replace one known exact block.", "exact_text_replace"),
        ]
        for description, expected_patch_type in cases:
            content = (
                "OBJECTIVE: MIM-PATCH-TYPE-SELECTION-REASONING-V1\n\n"
                "GOAL: Teach MIM to choose the correct supported TOD patch_type.\n\n"
                f"IMPLEMENTATION CONTEXT: {description}\n"
            )

            with self.subTest(expected_patch_type=expected_patch_type), tempfile.TemporaryDirectory() as temp_dir:
                shared_root = Path(temp_dir) / "runtime" / "shared"
                self.gateway._route_mim_implementation_objective_to_tod(
                    shared_root=shared_root,
                    request_id=f"mim-request-{expected_patch_type}",
                    raw_input=content,
                )
                request_artifact = json.loads(
                    (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                        encoding="utf-8"
                    )
                )

            self.assertEqual(request_artifact["target_component"], "MIM patch type selection reasoning")
            self.assertEqual(request_artifact["patch_type"], expected_patch_type)
            self.assertEqual(request_artifact["minimal_patch_plan"]["patch_type"], expected_patch_type)
            self.assertTrue(request_artifact["edit_shape_summary"])
            self.assertTrue(request_artifact["patch_type_rationale"])
            self.assertTrue(request_artifact["rejected_patch_types"])
            self.assertGreaterEqual(len(request_artifact["rejected_patch_types"]), 2)
            self.assertTrue(request_artifact["wrong_selection_evidence"])
            self.assertTrue(request_artifact["selection_confidence_basis"])
            self.assertTrue(request_artifact["fallback_if_patch_fails"])
            self.assertIn("scripts/mim_box_tod_packet_listener.py", request_artifact["expected_changed_files"])
            self.assertTrue(request_artifact["validation_plan"])

    def test_patch_selection_novelty_guard_prevents_recent_type_bias(self) -> None:
        cases = [
            ("Update a config value literal safely after a recent append success.", "update_literal_value", "append_guard_block"),
            ("Add test-only focused test coverage after a recent insert success.", "add_test_case_block", "insert_before_anchor"),
            ("Replace one known exact block after a recent anchor insertion.", "exact_text_replace", "insert_before_anchor"),
            ("Add guard-before behavior before an existing block.", "insert_before_anchor", "append_guard_block"),
            ("Add standalone safety block for idempotent guard logic.", "append_guard_block", "insert_before_anchor"),
        ]
        for description, expected_patch_type, forbidden_patch_type in cases:
            content = (
                "OBJECTIVE: MIM-PATCH-SELECTION-NOVELTY-AND-MISCLASSIFICATION-GUARD-V1\n\n"
                f"IMPLEMENTATION CONTEXT: {description}\n"
            )

            with self.subTest(expected_patch_type=expected_patch_type), tempfile.TemporaryDirectory() as temp_dir:
                shared_root = Path(temp_dir) / "runtime" / "shared"
                self.gateway._route_mim_implementation_objective_to_tod(
                    shared_root=shared_root,
                    request_id=f"mim-request-novelty-{expected_patch_type}",
                    raw_input=content,
                )
                request_artifact = json.loads(
                    (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                        encoding="utf-8"
                    )
                )

            self.assertEqual(request_artifact["patch_type"], expected_patch_type)
            self.assertNotEqual(request_artifact["patch_type"], forbidden_patch_type)
            self.assertEqual(request_artifact["confidence"], "high")
            self.assertGreaterEqual(len(request_artifact["rejected_patch_types"]), 2)
            self.assertTrue(request_artifact["wrong_selection_evidence"])

    def test_patch_selection_ambiguous_shape_downgrades_confidence(self) -> None:
        content = (
            "OBJECTIVE: MIM-PATCH-SELECTION-NOVELTY-AND-MISCLASSIFICATION-GUARD-V1\n\n"
            "IMPLEMENTATION CONTEXT: Ambiguous edit shape; multiple patch types could apply.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-ambiguous-patch-shape",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["confidence"], "low")
        self.assertEqual(request_artifact["patch_type"], "")
        self.assertEqual(request_artifact["minimal_patch_plan"], {})
        self.assertTrue(request_artifact["rejected_patch_types"])

    def test_validation_plan_selection_includes_patch_intent_steps(self) -> None:
        content = (
            "OBJECTIVE: MIM-VALIDATION-PLAN-SELECTION-V1\n\n"
            "GOAL: Teach MIM to choose validation that matches the patch intent.\n\n"
            "IMPLEMENTATION CONTEXT: Change a literal and prove the new value exists.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-validation-plan",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(request_artifact["target_component"], "MIM validation plan selection")
        validation_types = {
            step["validation_type"] for step in request_artifact["validation_steps"]
        }
        self.assertIn("syntax_validation", validation_types)
        self.assertIn("targeted_static_assertion", validation_types)
        self.assertGreater(len(request_artifact["validation_plan"]), 1)
        for step in request_artifact["validation_steps"]:
            self.assertTrue(step["validation_command"])
            self.assertTrue(step["validation_reason"])
            self.assertTrue(step["expected_signal"])
            self.assertTrue(step["failure_meaning"])
            self.assertTrue(step["tied_to_patch_intent"])

    def test_tod_autonomy_objectives_create_bounded_helper_patch(self) -> None:
        objectives = [
            "TOD-PROGRESS-TRUTH-SEPARATION",
            "TOD-EXECUTION-EVIDENCE-SCORING",
            "TOD-EVIDENCE-WEIGHTED-TASK-SELECTION",
            "TOD-FAILURE-MEMORY-LEARNING",
            "TOD-AUTONOMOUS-MAINTENANCE-CYCLE",
            "TOD-AUTONOMOUS-OBJECTIVE-DECOMPOSITION",
            "TOD-MIM-COOPERATIVE-AUTONOMY",
        ]
        for objective in objectives:
            content = f"OBJECTIVE: {objective}\n\nGOAL: implement this TOD autonomy capability.\n"
            with self.subTest(objective=objective), tempfile.TemporaryDirectory() as temp_dir:
                shared_root = Path(temp_dir) / "runtime" / "shared"
                self.gateway._route_mim_implementation_objective_to_tod(
                    shared_root=shared_root,
                    request_id=f"mim-request-{objective.lower()}",
                    raw_input=content,
                )
                request_artifact = json.loads(
                    (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                        encoding="utf-8"
                    )
                )

            self.assertEqual(request_artifact["patch_type"], "append_guard_block")
            self.assertEqual(
                request_artifact["minimal_patch_plan"]["edit_mode"],
                "append_guard_block",
            )
            self.assertIn("scripts/mim_box_tod_packet_listener.py", request_artifact["expected_changed_files"])
            self.assertTrue(request_artifact["validation_steps"])
            self.assertGreater(len(request_artifact["validation_plan"]), 1)
            self.assertIn("TOD autonomy capability:", request_artifact["target_component"])

    def test_initial_request_recovery_dispatch_includes_first_pass_self_check(self) -> None:
        content = (
            "OBJECTIVE: MIM-INITIAL-REQUEST-TO-EXECUTION-RECOVERY\n\n"
            "GOAL: Harden MIM's first-pass handling of operator objectives so broad "
            "implementation requests are correctly classified, shaped into executable TOD "
            "handoffs, and routed without Codex intervention.\n\n"
            "REQUIRED BEHAVIOR:\n"
            "- classify request type\n"
            "- detect whether confirmation is required\n"
            "- inspect current capability contracts\n"
            "- generate a fresh execution envelope\n"
            "- route to TOD execution if implementation-shaped\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._route_mim_implementation_objective_to_tod(
                shared_root=shared_root,
                request_id="mim-request-initial-request-recovery",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(
            request_artifact["target_component"],
            "MIM initial request to execution recovery",
        )
        self.assertEqual(request_artifact["request_type_classification"], "implementation")
        self.assertTrue(request_artifact["allowed_to_proceed_without_confirmation"])
        self.assertFalse(request_artifact["confirmation_required"])
        self.assertTrue(request_artifact["fresh_envelope_id"])
        self.assertEqual(request_artifact["task_class"], "implementation")
        self.assertTrue(request_artifact["validation_steps"])
        self.assertGreater(len(request_artifact["validation_plan"]), 1)
        self.assertIn("core/routers/gateway.py", request_artifact["files_expected_to_change"])
        self.assertIn("core/routers/gateway.py", request_artifact["likely_target_files"])
        self.assertTrue(request_artifact["intake_self_check"]["fresh_envelope_generated"])
        self.assertTrue(request_artifact["intake_self_check"]["prior_patch_template_reuse_rejected"])
        self.assertTrue(request_artifact["intake_self_check"]["intent_tied_validation_present"])
        self.assertFalse(request_artifact["intake_self_check"]["confirmation_required"])
        self.assertEqual(request_artifact["selected_implementation_path"], "A")

    def test_first_pass_failure_audit_writes_taxonomy_artifact(self) -> None:
        content = (
            "OBJECTIVE: MIM-FIRST-PASS-FAILURE-AUDIT\n\n"
            "GOAL: Analyze the last 10 failed MIM initiation attempts and identify the "
            "recurring intake failure classes.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._create_mim_first_pass_failure_audit(
                shared_root=shared_root,
                request_id="mim-request-first-pass-audit",
                raw_input=content,
            )
            artifact = json.loads(
                (shared_root / "MIM_FIRST_PASS_FAILURE_AUDIT.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(result["completion_status"], "completed_with_evidence")
        self.assertFalse(artifact["validation_summary"]["marker_only"])
        self.assertGreaterEqual(artifact["validation_summary"]["attempts_analyzed"], 5)
        self.assertTrue(artifact["validation_summary"]["rules_updated"])
        failure_classes = {item["failure_class"] for item in artifact["failure_classes"]}
        self.assertIn("confirmation_spam", failure_classes)
        self.assertIn("lifecycle_status_swallow", failure_classes)
        self.assertIn("stale_patch_envelope_reuse", failure_classes)
        self.assertIn("py_compile_only_validation", failure_classes)
        self.assertIn("generic_blocked_handoff", failure_classes)
        self.assertFalse(
            self.gateway._looks_like_implementation_followthrough_request(
                raw_input=content,
                resolution_reason="mim_first_pass_failure_audit_completed",
            )
        )

    def test_tod_consistency_audit_task_dispatch_is_audit_only(self) -> None:
        content = (
            "OBJECTIVE: TOD-CONSISTENCY-AUDIT-LOOP\n\n"
            "GOAL: Run a recurring audit to detect code drift, stale fallbacks, duplicate paths, "
            "marker-only implementations, unreachable helpers, and runtime/artifact disagreement.\n\n"
            "RULE: Audit only. No patches during the audit pass unless a critical safety/security defect is detected.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._create_tod_consistency_audit_task(
                shared_root=shared_root,
                request_id="mim-request-consistency-audit",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertEqual(request_artifact["objective_id"], "TOD-CONSISTENCY-AUDIT-LOOP")
        self.assertEqual(request_artifact["task_class"], "diagnostic_only")
        self.assertEqual(request_artifact["objective_type"], "diagnostic_only")
        self.assertTrue(request_artifact["audit_only"])
        self.assertFalse(request_artifact["patch_attempted"])
        self.assertIn("docs/tod-consistency-audit-latest.md", request_artifact["expected_evidence"])
        self.assertEqual(
            request_artifact["idle_behavior_order"],
            [
                "train",
                "audit_consistency",
                "refresh_state_artifacts",
                "propose_next_bounded_improvement",
            ],
        )
        self.assertFalse(
            self.gateway._looks_like_implementation_followthrough_request(
                raw_input=content,
                resolution_reason="tod_consistency_audit_dispatched",
            )
        )

    def test_reporting_visibility_objectives_dispatch_as_diagnostic_proofs(self) -> None:
        objective = "MIM-EXECUTION-SUMMARY-CONTRACT-V1"
        content = (
            f"OBJECTIVE: {objective}\n\n"
            "GOAL: Every completed TOD handoff must produce a clean operator summary.\n"
            "REQUIRED PROOF: completion_status, changed_files, validation_results, behavior_artifact, sample_operator_output.\n"
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            result = self.gateway._create_reporting_visibility_task(
                shared_root=shared_root,
                request_id="mim-request-reporting-visibility",
                raw_input=content,
            )
            request_artifact = json.loads(
                (shared_root / "MIM_TOD_TASK_REQUEST.latest.json").read_text(
                    encoding="utf-8"
                )
            )

        self.assertEqual(result["status"], "dispatched_to_TOD")
        self.assertEqual(request_artifact["objective_id"], objective)
        self.assertEqual(request_artifact["dispatch_kind"], "reporting_visibility_behavior_proof")
        self.assertEqual(request_artifact["task_class"], "diagnostic_only")
        self.assertIn("completion_status", request_artifact["expected_evidence"])
        self.assertIn("sample_operator_output", request_artifact["expected_evidence"])

    def test_implementation_objective_with_proof_does_not_create_tod_dispatch(self) -> None:
        content = "OBJECTIVE: MIM-IMPLEMENTATION-DISPATCH-GATE\nGOAL: implement the dispatch gate."

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content="create lifecycle",
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            updated = self.gateway._update_mim_operational_lifecycle_turn_state(
                shared_root=shared_root,
                request_id="mim-request-proof",
                raw_input=content,
                resolution_reason="tod_objective_summary_next_step_dispatch",
                resolution_outcome="store_only",
                resolution_status="completed",
                metadata={
                    "tod_dispatch": {
                        "changed_files": ["core/routers/gateway.py"],
                        "delivered_outputs": ["implementation dispatch gate"],
                        "validation_commands": ["python -m unittest tests.integration.test_mim_tod_handoff_gateway"],
                    }
                },
            )

            self.assertFalse((shared_root / "MIM_TOD_TASK_REQUEST.latest.json").exists())

        self.assertEqual(updated["state_contract"]["lifecycle_state"], "finish")
        self.assertEqual(updated["state_contract"]["operator_satisfaction_status"], "satisfied")
        self.assertFalse(updated["state_contract"]["implementation_dispatch"])

    def test_implementation_objective_with_changed_files_can_finish(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content="create lifecycle",
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            updated = self.gateway._update_mim_operational_lifecycle_turn_state(
                shared_root=shared_root,
                request_id="mim-request-proof",
                raw_input="OBJECTIVE: implement the abstraction layer",
                resolution_reason="tod_objective_summary_next_step_dispatch",
                resolution_outcome="store_only",
                resolution_status="completed",
                metadata={
                    "tod_dispatch": {
                        "delivered_outputs": ["conversational abstraction layer"],
                        "changed_files": ["core/routers/gateway.py"],
                        "validation_commands": ["python -m unittest tests.integration.test_mim_tod_handoff_gateway"],
                    }
                },
            )

        self.assertEqual(updated["state_contract"]["lifecycle_state"], "finish")
        self.assertEqual(updated["state_contract"]["operator_satisfaction_status"], "satisfied")
        self.assertFalse(updated["state_contract"]["replan_required"])
        self.assertIn("core/routers/gateway.py", updated["state_contract"]["changed_files"])

    def test_operational_lifecycle_status_answers_from_artifact(self) -> None:
        content = "what is the operational lifecycle status?"

        self.assertTrue(self.gateway._looks_like_mim_operational_lifecycle_status_request(content))

        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            self.gateway._create_mim_operational_reasoning_lifecycle_objective(
                content="create lifecycle",
                shared_root=shared_root,
                request_id="mim-request-lifecycle",
            )
            self.gateway._update_mim_operational_lifecycle_turn_state(
                shared_root=shared_root,
                request_id="mim-request-status",
                raw_input=content,
                resolution_reason="mim_operational_lifecycle_status_answered",
                resolution_outcome="store_only",
                resolution_status="completed",
                metadata={},
            )
            result = self.gateway._answer_mim_operational_lifecycle_status(shared_root=shared_root)

        self.assertEqual(result["status"], "done")
        self.assertIn("Operational lifecycle status:", result["reply_text"])
        self.assertIn("MIM-OPERATIONAL-REASONING-LIFECYCLE-V1", result["reply_text"])
        self.assertIn("lifecycle_state:", result["reply_text"])
        self.assertNotIn("online and functioning", result["reply_text"].lower())

    def test_inspect_first_present_field_dispatches_no_edit_branch(self) -> None:
        content = (
            "MIM, ask TOD to verify whether execution_direct_lane_health_state already exists "
            "in the TOD UI state. If it already exists, TOD must not edit anything. "
            "If it is missing, TOD may add it safely and validate."
        )
        requested_paths: list[str] = []

        def fake_get(path: str, *_args, **_kwargs):
            requested_paths.append(path)
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-execution-direct-lane-health-state-mim-request-test",
                        "status": "completed",
                        "started_at": "2026-05-08T15:00:02Z",
                        "updated_at": "2026-05-08T15:00:03Z",
                    },
                }
            return {"state": {"fields": ["execution_direct_lane_health_state"]}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                target_file = Path(temp_dir) / "core" / "routers" / "tod_ui.py"
                target_file.parent.mkdir(parents=True)
                target_file.write_text(
                    'STATE = {"execution_direct_lane_health_state": "validated"}\n',
                    encoding="utf-8",
                )
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T15:00:00Z",
                        mim_intent_classified_at="2026-05-08T15:00:01Z",
                        classification_stage_timestamps={
                            "gateway_received_at": "2026-05-08T15:00:00Z",
                            "deterministic_classifier_started_at": "2026-05-08T15:00:00Z",
                            "deterministic_classifier_completed_at": "2026-05-08T15:00:01Z",
                            "route_decided_at": "2026-05-08T15:00:01Z",
                        },
                    )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["inspect_first_branch"], "inspect_only_no_edit_needed")
        self.assertTrue(result["inspection_field_present"])
        self.assertIn("inspect_only_no_edit_needed", result["result_reason"])
        self.assertNotIn("/tod/ui/state", requested_paths)
        timestamps = result["stage_timestamps"]
        durations = result["stage_durations_ms"]
        self.assertTrue(timestamps["operator_request_received_at"])
        self.assertTrue(timestamps["mim_intent_classified_at"])
        self.assertTrue(timestamps["tod_handoff_published_at"])
        self.assertTrue(timestamps["tod_ack_seen_at"])
        self.assertTrue(timestamps["tod_result_consumed_at"])
        self.assertEqual(timestamps["route_decided_at"], "2026-05-08T15:00:01Z")
        self.assertEqual(timestamps["inspect_first_pre_publish_source"], "target_file_and_durable_artifacts")
        self.assertIn("deterministic_classifier_ms", durations)
        self.assertIn("gateway_to_route_decided_ms", durations)
        self.assertIn("intent_to_handoff_publish_ms", durations)
        self.assertIn("handoff_publish_to_ack_ms", durations)

    def test_inspect_first_uses_consumed_handoff_artifact_as_present_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            shared_root = Path(temp_dir) / "runtime" / "shared"
            shared_root.mkdir(parents=True)
            (shared_root / "MIM_TOD_HANDOFF_RESULT.latest.json").write_text(
                json.dumps(
                    {
                        "result_status": "succeeded",
                        "execution_field": "execution_direct_lane_health_state",
                        "result_reason": "published/validated execution_direct_lane_health_state",
                    }
                ),
                encoding="utf-8",
            )

            present = self.gateway._mim_tod_inspection_field_present(
                shared_root=shared_root,
                inspection_state={"state": {"fields": []}},
                execution_field="execution_direct_lane_health_state",
            )

        self.assertTrue(present)

    def test_inspect_first_uses_target_file_as_present_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            target_file = Path(temp_dir) / "core" / "routers" / "tod_ui.py"
            target_file.parent.mkdir(parents=True)
            target_file.write_text(
                'STATE = {"execution_direct_lane_health_state": "validated"}\n',
                encoding="utf-8",
            )

            present = self.gateway._mim_tod_inspection_field_present(
                shared_root=Path(temp_dir) / "runtime" / "shared",
                inspection_state={"state": {"fields": []}},
                execution_field="execution_direct_lane_health_state",
                target_file=str(target_file),
            )

        self.assertTrue(present)

    def test_inspect_first_missing_field_dispatches_bounded_edit_branch(self) -> None:
        content = (
            "MIM, ask TOD to check whether execution_new_health_state exists in the TOD UI state. "
            "Only if missing, have TOD add it safely and validate."
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": lambda *_args, **_kwargs: {"state": {"fields": []}},
                        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                    )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["inspect_first_branch"], "missing_field_added_and_validated")
        self.assertFalse(result["inspection_field_present"])
        self.assertIn("missing_field_added_and_validated", result["result_reason"])

    def test_dispatch_uses_lightweight_tod_execution_probe_for_start_detection(self) -> None:
        content = (
            "MIM, ask TOD to run validation-only against TARGET_FILE: core/routers/tod_ui.py "
            "and report back.\nTASK_ID: mim-tod-diagnostic-mim-request-test"
        )
        requested_paths: list[str] = []

        def fake_get(path: str, **_kwargs):
            requested_paths.append(path)
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-diagnostic-mim-request-test",
                        "status": "completed",
                        "started_at": "2026-05-08T16:00:02Z",
                        "updated_at": "2026-05-08T16:00:03Z",
                    },
                }
            return {"execution": {}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T16:00:00Z",
                        mim_intent_classified_at="2026-05-08T16:00:00Z",
                    )
            finally:
                os.chdir(original_cwd)

        self.assertIn("/tod/ui/state/execution", requested_paths)
        self.assertNotIn("/tod/ui/state", requested_paths)
        timestamps = result["stage_timestamps"]
        self.assertEqual(timestamps["tod_execution_started_at"], "2026-05-08T16:00:02Z")
        self.assertEqual(timestamps["tod_execution_start_probe"], "tod_execution_probe")
        self.assertIn("ack_to_execution_start_ms", result["stage_durations_ms"])

    def test_dispatch_uses_bridge_artifact_readback_for_ack_timestamp(self) -> None:
        content = (
            "MIM, ask TOD to run validation-only against TARGET_FILE: core/routers/tod_ui.py "
            "and report back.\nTASK_ID: mim-tod-ack-probe-mim-request-test"
        )
        requested_paths: list[str] = []

        def fake_post(path: str, *_args, **_kwargs):
            requested_paths.append(path)
            return {"ok": True}

        def fake_get(path: str, **_kwargs):
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-ack-probe-mim-request-test",
                        "status": "completed",
                        "started_at": "2026-05-08T16:00:02Z",
                        "updated_at": "2026-05-08T16:00:03Z",
                    },
                }
            return {"execution": {}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": fake_post,
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T16:00:00Z",
                        mim_intent_classified_at="2026-05-08T16:00:00Z",
                    )
            finally:
                os.chdir(original_cwd)

        self.assertIn("/tod/ui/chat/message", requested_paths)
        timestamps = result["stage_timestamps"]
        self.assertTrue(timestamps["tod_ack_seen_at"])
        self.assertEqual(timestamps["tod_ack_source"], "bridge_artifact_readback")
        self.assertIn("handoff_publish_to_ack_ms", result["stage_durations_ms"])

    def test_dispatch_invokes_tod_router_in_process_before_http_fallback(self) -> None:
        content = (
            "MIM, ask TOD to run validation-only against TARGET_FILE: core/routers/tod_ui.py "
            "and report back.\nTASK_ID: mim-tod-in-process-mim-request-test"
        )
        requested_paths: list[str] = []
        probe_paths: list[str] = []
        calls: list[str] = []

        fake_core = types.ModuleType("core")
        fake_routers = types.ModuleType("core.routers")
        fake_tod_ui = types.ModuleType("core.routers.tod_ui")

        def fake_build_state():
            calls.append("build_state")
            return {"execution": {}}

        def fake_publish_ack(*_args, **_kwargs):
            calls.append("publish_ack")
            return {
                "ok": True,
                "status": "completed",
                "task_id": "mim-tod-in-process-mim-request-test",
                "generated_at": "2026-05-08T16:00:01Z",
            }

        def fake_publish_request(*_args, **_kwargs):
            calls.append("publish_request")
            return {"ok": True, "status": "published"}

        fake_tod_ui._build_tod_console_state = fake_build_state
        fake_tod_ui._publish_local_execution_ack = fake_publish_ack
        fake_tod_ui._publish_task_execution_request = fake_publish_request
        fake_routers.tod_ui = fake_tod_ui
        fake_core.routers = fake_routers

        def fake_post(path: str, *_args, **_kwargs):
            requested_paths.append(path)
            return {"ok": True}

        def fake_get(path: str, **_kwargs):
            probe_paths.append(path)
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-in-process-mim-request-test",
                        "status": "completed",
                        "started_at": "2026-05-08T16:00:01Z",
                        "updated_at": "2026-05-08T16:00:02Z",
                    },
                }
            return {"execution": {}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                with patch.dict(
                    sys.modules,
                    {
                        "core": fake_core,
                        "core.routers": fake_routers,
                        "core.routers.tod_ui": fake_tod_ui,
                    },
                ), patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": fake_post,
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T16:00:00Z",
                        mim_intent_classified_at="2026-05-08T16:00:00Z",
                    )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(calls, ["build_state", "publish_ack", "publish_request"])
        self.assertNotIn("/tod/ui/chat/message", requested_paths)
        self.assertEqual(probe_paths, [])
        self.assertTrue(result["tod_post_ok"])
        self.assertTrue(result["stage_timestamps"]["tod_execution_started_at"])
        self.assertEqual(result["stage_timestamps"]["tod_result_consumption_source"], "tod_direct_router_result")
        self.assertEqual(result["stage_durations_ms"]["completed_to_result_consumed_ms"], 0)

    def test_lifecycle_completion_without_requested_deliverables_is_not_operator_satisfied(self) -> None:
        content = (
            "MIM, ask TOD to answer: what were the last 5 UI objectives, what changed in the UI, "
            "and what verifiable files were changed? The final result must include requested_deliverables, "
            "delivered_outputs, missing_outputs, result_quality, operator_satisfaction_status, and replan_required."
        )

        def fake_get(path: str, **_kwargs):
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-execution-mim-tod-diagnostic-state-mim-request-test",
                        "status": "completed",
                        "started_at": "2026-05-08T16:00:01Z",
                        "updated_at": "2026-05-08T16:00:02Z",
                    },
                }
            return {"execution": {}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T16:00:00Z",
                        mim_intent_classified_at="2026-05-08T16:00:00Z",
                    )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["result_status"], "execution_complete_but_operator_unsatisfied")
        self.assertEqual(result["operator_satisfaction_status"], "execution_complete_but_operator_unsatisfied")
        self.assertTrue(result["replan_required"])
        self.assertIn("last_ui_objectives", result["missing_outputs"])
        self.assertIn("ui_changes", result["missing_outputs"])
        self.assertIn("Missing outputs remain unresolved", result["result_reason"])
        self.assertIn("validation: incomplete", result["result_reason"])
        self.assertIn("MIM_TOD_REQUESTED_EVIDENCE_FULFILLMENT.latest.json", result["fulfillment_artifact"])

    def test_requested_evidence_fulfillment_can_satisfy_deliverable_contract(self) -> None:
        content = (
            "MIM, ask TOD to answer: what were the last 5 UI objectives, what changed in the UI, "
            "and what verifiable files were changed? The final result must include requested_deliverables, "
            "delivered_outputs, missing_outputs, result_quality, operator_satisfaction_status, and replan_required."
        )

        def fake_get(path: str, **_kwargs):
            if path == "/tod/ui/state/execution":
                return {
                    "source": "tod_execution_probe",
                    "execution": {
                        "task_id": "mim-tod-execution-mim-tod-diagnostic-state-mim-request-test",
                        "status": "completed",
                        "started_at": "2026-05-08T16:00:01Z",
                        "updated_at": "2026-05-08T16:00:02Z",
                    },
                }
            return {"execution": {}}

        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                shared_root = Path("runtime/shared")
                shared_root.mkdir(parents=True, exist_ok=True)
                (shared_root / "MIM_TOD_LIVE_COMMUNICATION_SOAK.latest.json").write_text(
                    json.dumps(
                        {
                            "results": [
                                {
                                    "objective_id": f"ui-objective-{idx}",
                                    "task_id": f"ui-task-{idx}",
                                    "status": "succeeded",
                                    "result_reason": f"Applied UI change {idx} in core/routers/tod_ui.py.",
                                }
                                for idx in range(1, 6)
                            ]
                        }
                    ),
                    encoding="utf-8",
                )
                Path("core/routers").mkdir(parents=True, exist_ok=True)
                Path("core/routers/tod_ui.py").write_text("# test target\n", encoding="utf-8")
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": fake_get,
                        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
                    },
                ):
                    result = self.gateway._dispatch_mim_tod_executable_handoff_request(
                        request_id="mim-request-test",
                        session_key="session-test",
                        content=content,
                        actor="mim",
                        operator_request_received_at="2026-05-08T16:00:00Z",
                        mim_intent_classified_at="2026-05-08T16:00:00Z",
                    )
                fulfillment = json.loads(
                    (shared_root / "MIM_TOD_REQUESTED_EVIDENCE_FULFILLMENT.latest.json").read_text(
                        encoding="utf-8"
                    )
                )
            finally:
                os.chdir(original_cwd)

        self.assertEqual(result["result_status"], "succeeded")
        self.assertEqual(result["operator_satisfaction_status"], "satisfied")
        self.assertFalse(result["replan_required"])
        self.assertEqual(result["missing_outputs"], [])
        self.assertEqual(
            [entry["stage"] for entry in result["workflow_trace"]],
            [
                "request",
                "missing_outputs_detected",
                "evidence_followup_created",
                "evidence_gathered",
                "satisfaction_upgraded",
            ],
        )
        self.assertIn("Iteration 2: missing_outputs_detected", result["workflow_trace_text"])
        self.assertIn("Iteration 5: satisfaction_upgraded", result["workflow_trace_text"])
        self.assertTrue(result["result_reason"].startswith("Done. I reviewed the live MIM/TOD operator workflow."))
        self.assertIn("What happened", result["result_reason"])
        self.assertIn("What changed", result["result_reason"])
        self.assertIn("Files changed", result["result_reason"])
        self.assertIn("Evidence", result["result_reason"])
        self.assertIn("Status", result["result_reason"])
        self.assertNotIn("Requested evidence fulfillment:", result["result_reason"])
        self.assertIn("What happened", result["operator_report"])
        self.assertIn("Operator-facing report:", result["numbered_operator_report"])
        self.assertEqual(result["accountability_view"]["satisfaction_status"], "satisfied")
        self.assertEqual(result["accountability_view"]["replan_required"], False)
        self.assertIn("requested_deliverables", result["accountability_view"]["requested_deliverables"])
        self.assertIn("MIM_TOD_REQUESTED_EVIDENCE_FULFILLMENT.latest.json", result["accountability_view"]["artifact_path"])
        self.assertIn("last_ui_objectives", result["delivered_outputs"])
        self.assertIn("ui_changes", result["delivered_outputs"])
        self.assertIn("changed_files", result["delivered_outputs"])
        self.assertEqual(fulfillment["status"], "satisfied")
        self.assertEqual(len(fulfillment["last_ui_objectives"]), 5)
        self.assertIn("validation: passed", result["result_reason"])
        self.assertIn("requested_deliverables", fulfillment["requested_deliverables"])


if __name__ == "__main__":
    unittest.main()
