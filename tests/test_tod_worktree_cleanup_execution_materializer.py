import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "materialize_tod_worktree_cleanup_execution.py"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "materialize_tod_worktree_cleanup_execution", SCRIPT
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class WorktreeCleanupExecutionMaterializerTests(unittest.TestCase):
    def test_builds_non_destructive_cleanup_slices(self):
        module = load_module()
        classification = {
            "paths": [
                {
                    "path": "scripts/materialize_tod_worktree_path_classification.py",
                    "bucket": "tod_control_plane_tool",
                },
                {
                    "path": "tmp_remote_mim/core/routers/studio.py",
                    "bucket": "remote_mim_product_patch",
                },
                {
                    "path": "docs/training/EXAMPLE.md",
                    "bucket": "training_or_objective_document",
                },
                {
                    "path": "CODEX.md",
                    "bucket": "governance_document_change",
                },
            ]
        }

        manifest = module.build_execution_manifest(classification)

        self.assertTrue(manifest["ok"])
        self.assertTrue(manifest["non_destructive"])
        self.assertFalse(manifest["tod_independent_capability_acquired"])
        self.assertTrue(manifest["policy"]["cleanup_does_not_mean_revert"])
        by_slice = {entry["slice_id"]: entry for entry in manifest["execution_slices"]}
        self.assertIn(
            "scripts/materialize_tod_worktree_path_classification.py",
            by_slice["commit_current_codex_reviewed_slice"]["paths"],
        )
        self.assertIn(
            "tmp_remote_mim/core/routers/studio.py",
            by_slice["remote_mim_product_patch_review"]["paths"],
        )
        self.assertIn(
            "CODEX.md",
            by_slice["manual_governance_or_deletion_review"]["paths"],
        )

    def test_cli_writes_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            input_path = tmp_path / "classification.json"
            output_path = tmp_path / "cleanup.json"
            input_path.write_text(
                json.dumps(
                    {
                        "paths": [
                            {
                                "path": "tests/test_tod_worktree_cleanup_execution_materializer.py",
                                "bucket": "validation_test_change",
                            }
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
            self.assertEqual(manifest["objective_id"], "TOD-WORKTREE-CLEANUP-EXECUTION-V1")
            self.assertEqual(manifest["summary"]["execution_slices"], 6)


if __name__ == "__main__":
    unittest.main()
