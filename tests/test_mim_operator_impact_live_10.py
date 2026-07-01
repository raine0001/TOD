import importlib.util
import unittest
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


if __name__ == "__main__":
    unittest.main()
