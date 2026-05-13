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
        "_mim_tod_active_project_status_response",
        "_first_nonempty_mim_tod_value",
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
    }
    helper_nodes = [
        node
        for node in module_ast.body
        if isinstance(node, ast.FunctionDef) and node.name in helper_names
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
        "_get_json_from_local_tod": lambda *_args, **_kwargs: {},
        "_post_json_to_local_tod": lambda *_args, **_kwargs: {"ok": True},
    }
    exec(compile(helper_module, str(gateway_path), "exec"), namespace)
    return types.SimpleNamespace(**{name: namespace[name] for name in helper_names})


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
        self.assertIn("TOD_RUNTIME_OWNERSHIP.latest.json", reply)
        self.assertIn("Install/verify MIM-box TOD listener", reply)
        self.assertNotIn("zone uncertainty should be stabilized", reply.lower())

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
