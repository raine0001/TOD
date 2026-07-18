import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "materialize_tod_worktree_path_classification.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "materialize_tod_worktree_path_classification", SCRIPT
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class WorktreePathClassificationMaterializerTests(unittest.TestCase):
    def test_classifies_every_path_with_owner_action_bucket(self):
        module = load_module()
        cleanliness = {
            "dirty_count_before": 8,
            "remaining_dirty_count": 8,
            "items": [
                {"path": ".env", "status": "M"},
                {
                    "path": "runtime_remote_training/read_only_audit_artifacts/example.json",
                    "status": "??",
                },
                {"path": "tmp_remote_mim/core/routers/studio.py", "status": "M"},
                {"path": "scripts/TOD.ps1", "status": "M"},
                {"path": "tests/TOD.ReadOnlyAuditRegression.Tests.ps1", "status": "??"},
                {
                    "path": "docs/training/learned-capabilities/EXAMPLE.md",
                    "status": "??",
                },
                {"path": "tod/config/project-registry.json", "status": "M"},
                {"path": "CODEX.md", "status": "M"},
            ],
        }

        manifest = module.build_manifest(cleanliness)

        self.assertTrue(manifest["ok"])
        self.assertEqual(manifest["summary"]["classified_paths"], 8)
        self.assertEqual(manifest["summary"]["unclassified_paths"], 0)
        by_path = {entry["path"]: entry for entry in manifest["paths"]}
        self.assertEqual(by_path[".env"]["bucket"], "secret_or_local_environment")
        self.assertEqual(
            by_path["tmp_remote_mim/core/routers/studio.py"]["bucket"],
            "remote_mim_product_patch",
        )
        self.assertEqual(by_path["scripts/TOD.ps1"]["bucket"], "tod_control_plane_script")
        self.assertEqual(
            by_path["tests/TOD.ReadOnlyAuditRegression.Tests.ps1"]["bucket"],
            "validation_test_change",
        )
        for entry in manifest["paths"]:
            self.assertTrue(entry["owner"])
            self.assertTrue(entry["action"])
            self.assertTrue(entry["bucket"])

    def test_cli_writes_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            input_path = tmp_path / "cleanliness.json"
            output_path = tmp_path / "manifest.json"
            input_path.write_text(
                json.dumps(
                    {
                        "items": [
                            {"path": "tools/publish_tod_execution_authority_audit.py", "status": "??"},
                            {"path": "tod/data/state.zero-byte-20260707T164547.json.bak", "status": "??"},
                        ]
                    }
                ),
                encoding="utf-8",
            )

            proc = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--input",
                    str(input_path),
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(proc.returncode, 0, proc.stderr)
            manifest = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["summary"]["classified_paths"], 2)
            self.assertEqual(manifest["summary"]["unclassified_paths"], 0)


if __name__ == "__main__":
    unittest.main()
