import importlib.util
import unittest
from pathlib import Path


def _load_module():
    module_path = Path(__file__).resolve().parent / "scripts" / "validate_tod_mim_runtime_packet.py"
    spec = importlib.util.spec_from_file_location("validate_tod_mim_runtime_packet", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidateTodMimRuntimePacketTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.module = _load_module()

    def test_packet_identity_rejects_root_task_mismatch(self) -> None:
        result = {"errors": []}

        expected = self.module.validate_packet_identity_consistency(
            result,
            {
                "request_id": "objective-2913-task-7144",
                "task_id": "objective-2913-task-1777951503",
                "objective_id": "2913",
                "correlation_id": "objective-2913-task-7144",
            },
        )

        self.assertEqual(expected["task_id"], "objective-2913-task-1777951503")
        self.assertTrue(any(error["code"] == "task_id_mismatch" for error in result["errors"]))

    def test_embedded_scope_rejects_selected_task_id_mismatch(self) -> None:
        result = {"errors": []}
        expected = {
            "request_id": "objective-2913-task-7144",
            "task_id": "objective-2913-task-7144",
            "objective_id": "2913",
            "correlation_id": "objective-2913-task-7144",
        }

        self.module.validate_embedded_request_scope(
            result,
            {
                "selected_task_id": "objective-2913-task-1777951503",
                "current_task_id": "objective-2913-task-7144",
            },
            "integration",
            expected,
        )

        mismatches = [error for error in result["errors"] if error["code"] == "embedded_identity_mismatch"]
        self.assertEqual(len(mismatches), 1)
        self.assertIn("integration.selected_task_id", mismatches[0]["detail"])


if __name__ == "__main__":
    unittest.main()