import ast
import json
import os
import re
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
        "_mim_tod_handoff_default_validation_only",
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

    def test_inspect_first_present_field_dispatches_no_edit_branch(self) -> None:
        content = (
            "MIM, ask TOD to verify whether execution_direct_lane_health_state already exists "
            "in the TOD UI state. If it already exists, TOD must not edit anything. "
            "If it is missing, TOD may add it safely and validate."
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            original_cwd = os.getcwd()
            os.chdir(temp_dir)
            try:
                with patch.dict(
                    self.gateway._dispatch_mim_tod_executable_handoff_request.__globals__,
                    {
                        "_get_json_from_local_tod": lambda *_args, **_kwargs: {
                            "state": {"fields": ["execution_direct_lane_health_state"]}
                        },
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

        self.assertEqual(result["inspect_first_branch"], "inspect_only_no_edit_needed")
        self.assertTrue(result["inspection_field_present"])
        self.assertIn("inspect_only_no_edit_needed", result["result_reason"])

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


if __name__ == "__main__":
    unittest.main()
