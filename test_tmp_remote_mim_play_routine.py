from __future__ import annotations

import ast
import types
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent
ROUTES_PATH = REPO_ROOT / "tmp_remote_mim" / "routes.py"


def load_function_source(path: Path, function_name: str) -> str:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source)
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == function_name:
            segment = ast.get_source_segment(source, node)
            if not segment:
                raise RuntimeError(f"Could not extract {function_name} from {path}")
            return segment
    raise RuntimeError(f"Function {function_name} not found in {path}")


class RequestStub:
    def __init__(self, payload: dict[str, object]) -> None:
        self._payload = payload

    def get_json(self) -> dict[str, object]:
        return self._payload


class TimeStub:
    def sleep(self, _: float) -> None:
        return None


class PlayRoutineContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.play_routine_source = load_function_source(ROUTES_PATH, "play_routine")

    def invoke_play_routine(self, payload: dict[str, object], routines: object) -> tuple[dict[str, object], int]:
        namespace: dict[str, object] = {
            "request": RequestStub(payload),
            "load_routines": lambda: routines,
            "get_serial_connection": lambda: None,
            "jsonify": lambda body: body,
            "time": TimeStub(),
            "print": lambda *args, **kwargs: None,
        }
        exec(self.play_routine_source, namespace)
        response = namespace["play_routine"]()
        self.assertIsInstance(response, tuple)
        return response

    def test_accepts_dict_backed_routine_store(self) -> None:
        response, status_code = self.invoke_play_routine(
            payload={"name": "scan_pose"},
            routines={
                "scan_pose": {
                    "delay": 0,
                    "keyframes": [[90, 80, 70]],
                }
            },
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response["status"], "ok")
        self.assertIn("scan_pose", response["message"])

    def test_accepts_list_backed_routine_store(self) -> None:
        response, status_code = self.invoke_play_routine(
            payload={"name": "scan_pose"},
            routines=[
                {
                    "name": "scan_pose",
                    "delay": 0,
                    "keyframes": [[90, 80, 70]],
                }
            ],
        )

        self.assertEqual(status_code, 200)
        self.assertEqual(response["status"], "ok")

    def test_returns_not_found_for_unknown_routine(self) -> None:
        response, status_code = self.invoke_play_routine(
            payload={"name": "scan_pose"},
            routines={"safe_home": {"delay": 0, "keyframes": []}},
        )

        self.assertEqual(status_code, 404)
        self.assertEqual(response["status"], "error")
        self.assertEqual(response["message"], "Routine not found")


if __name__ == "__main__":
    unittest.main()