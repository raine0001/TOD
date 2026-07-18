import importlib.util
import unittest
from argparse import Namespace
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "score_mim_operator_impact_live_10.py"


def load_module():
    spec = importlib.util.spec_from_file_location("score_mim_operator_impact_live_10", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class OperatorImpactLive10Tests(unittest.TestCase):
    def test_status_leakage_fails_even_with_contract_fields(self):
        module = load_module()
        reply = (
            "Training is active, but the useful question is whether it is changing behavior. "
            "Right now my mode-selection score is 100%. "
            "Recommended action: rerun the live score. "
            "Owner: MIM. Evidence: scorecard artifact. Aging: within 24h. Dave needed: no."
        )
        scored = module.score_reply(reply)
        self.assertTrue(scored["status_leakage"])
        self.assertFalse(scored["passed"])
        self.assertLessEqual(scored["score_10"], 6.0)

    def test_clean_operator_contract_passes(self):
        module = load_module()
        reply = (
            "The next useful task is to inspect TOD's ready backlog and choose one behavior-changing repair. "
            "Owner: TOD selects and runs it; MIM watches for stale evidence. "
            "Evidence: a result artifact with changed files, validation output, and closure state. "
            "Aging: rerun the selector within 24h if no task appears. "
            "Dave needed: no unless credentials are required."
        )
        scored = module.score_reply(reply)
        self.assertFalse(scored["status_leakage"])
        self.assertTrue(scored["passed"])

    def test_blocked_report_keeps_live_failure_auditable(self):
        module = load_module()
        args = Namespace(studio_base_url="https://mimtod.com", timeout=45)
        report = module.build_blocked_report(args, RuntimeError("socket blocked"))

        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["sample_count"], 0)
        self.assertEqual(report["pass_count"], 0)
        self.assertEqual(report["operator_impact_score"], 0.0)
        self.assertEqual(report["dave_needed"], "no unless all TOD/MIM live-validation runtimes lack network or credentials")
        self.assertIn("socket blocked", report["error"])
        self.assertIn("durable blocked artifact", report["prevention_lesson"])
        self.assertTrue(report["expected_evidence"])

    def test_blocked_report_preserves_prior_operator_score(self, tmp_path=None):
        module = load_module()
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            training_root = Path(tmp)
            module.OPERATOR_SCORECARD_PATH = training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json"
            module.REAL_MOVEMENT_PATH = training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"
            module.OPERATOR_SCORECARD_PATH.parent.mkdir(parents=True, exist_ok=True)
            module.OPERATOR_SCORECARD_PATH.write_text(
                '{"operator_impact_score": 7.0, "sample_count": 10}',
                encoding="utf-8",
            )
            args = Namespace(studio_base_url="https://mimtod.com", timeout=45)
            report = module.build_blocked_report(args, RuntimeError("socket blocked"))

        self.assertEqual(report["last_verified_operator_impact"], "7.0/10 from 10 live replies")


if __name__ == "__main__":
    unittest.main()
