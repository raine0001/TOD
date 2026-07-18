import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "build_mim_operator_impact_scorecard.py"


def load_module():
    spec = importlib.util.spec_from_file_location("build_mim_operator_impact_scorecard", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class OperatorImpactScorecardTests(unittest.TestCase):
    def test_real_movement_fallback_surfaces_live10_blocker(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            training_root = Path(tmp)
            interventions = training_root / "codex_training_interventions"
            interventions.mkdir(parents=True)
            module.TRAINING_ROOT = training_root
            module.LIVE_10_PATH = training_root / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
            module.REAL_MOVEMENT_PATH = training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"
            module.STRUCTURAL_PATH = training_root / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
            module.CROSS_SURFACE_PATH = training_root / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
            module.CONTEXT_GROUNDING_PATH = training_root / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
            module.OUTCOME_BINDING_PATH = training_root / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
            module.INTERVENTIONS_ROOT = interventions

            module.REAL_MOVEMENT_PATH.write_text(
                json.dumps(
                    {
                        "generated_at": "2026-07-14T00:00:00Z",
                        "metrics": [
                            {
                                "metric": "MIM Operator Impact",
                                "current": "7.0/10 from 10 live replies",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            blocker_path = interventions / "CODEX_MIM_OPERATOR_IMPACT_LIVE10_RERUN_BLOCKED_20260714T0010Z.json"
            blocker_path.write_text(
                json.dumps(
                    {
                        "error": "urllib.error.URLError: WinError 10013 socket access forbidden",
                        "impact": "Cannot refresh live-10 from this runtime.",
                        "aging_rule": "Retry from an authorized live-validation lane.",
                    }
                ),
                encoding="utf-8-sig",
            )

            scorecard = module.build_scorecard()

        self.assertEqual(scorecard["status"], "live_detail_blocked")
        self.assertEqual(scorecard["operator_impact_score"], 7.0)
        self.assertIn(str(blocker_path), scorecard["source_files"])
        self.assertEqual(scorecard["summary_fallback_reason"], "Cannot refresh live-10 from this runtime.")
        live_detail = next(row for row in scorecard["metrics"] if row["metric"] == "Live Reply Detail")
        self.assertIn("WinError 10013", live_detail["current"])

    def test_real_movement_fallback_surfaces_transport_blocker(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            training_root = Path(tmp)
            interventions = training_root / "codex_training_interventions"
            interventions.mkdir(parents=True)
            module.TRAINING_ROOT = training_root
            module.LIVE_10_PATH = training_root / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
            module.REAL_MOVEMENT_PATH = training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"
            module.STRUCTURAL_PATH = training_root / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
            module.CROSS_SURFACE_PATH = training_root / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
            module.CONTEXT_GROUNDING_PATH = training_root / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
            module.OUTCOME_BINDING_PATH = training_root / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
            module.INTERVENTIONS_ROOT = interventions

            module.REAL_MOVEMENT_PATH.write_text(
                json.dumps(
                    {
                        "generated_at": "2026-07-14T00:00:00Z",
                        "metrics": [
                            {
                                "metric": "MIM Operator Impact",
                                "current": "7.0/10 from 10 live replies",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            blocker_path = interventions / "CODEX_MIM_OPERATOR_IMPACT_LIVE_DEPLOY_AND_SCORER_TRANSPORT_BLOCKED_20260714T0018Z.json"
            blocker_path.write_text(
                json.dumps(
                    {
                        "summary": "Local runtime cannot deploy or rerun live operator-impact scoring.",
                        "why_forward_motion_is_blocked": "SSH and HTTPS scorer paths are blocked.",
                        "aging_rule": "Retry from an authorized lane immediately.",
                    }
                ),
                encoding="utf-8",
            )

            scorecard = module.build_scorecard()

        self.assertEqual(scorecard["status"], "live_detail_blocked")
        self.assertIn(str(blocker_path), scorecard["source_files"])
        self.assertEqual(
            scorecard["summary_fallback_reason"],
            "Local runtime cannot deploy or rerun live operator-impact scoring.",
        )
        live_detail = next(row for row in scorecard["metrics"] if row["metric"] == "Live Reply Detail")
        self.assertIn("live validation blocked", live_detail["current"])
        self.assertIn("cannot deploy", live_detail["current"])

    def test_real_movement_fallback_surfaces_responder_silence_blocker(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            training_root = Path(tmp)
            interventions = training_root / "codex_training_interventions"
            interventions.mkdir(parents=True)
            module.TRAINING_ROOT = training_root
            module.LIVE_10_PATH = training_root / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
            module.REAL_MOVEMENT_PATH = training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"
            module.STRUCTURAL_PATH = training_root / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
            module.CROSS_SURFACE_PATH = training_root / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
            module.CONTEXT_GROUNDING_PATH = training_root / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
            module.OUTCOME_BINDING_PATH = training_root / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
            module.INTERVENTIONS_ROOT = interventions

            module.REAL_MOVEMENT_PATH.write_text(
                json.dumps(
                    {
                        "generated_at": "2026-07-14T00:00:00Z",
                        "metrics": [
                            {
                                "metric": "MIM Operator Impact",
                                "current": "7.0/10 from 10 live replies",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            blocker_path = interventions / "CODEX_TOD_SELECTOR_CONTRACT_RESPONDER_SILENCE_20260714T0050Z.json"
            blocker_path.write_text(
                json.dumps(
                    {
                        "summary": "TOD did not answer the governed selector contract before the 30-minute aging rule elapsed.",
                        "why_forward_motion_is_blocked": "Live MIM operator-impact proof remains blocked.",
                        "aging_rule": "Do not create a duplicate request; classify responder silence and recover the acknowledgement path.",
                    }
                ),
                encoding="utf-8",
            )

            scorecard = module.build_scorecard()

        self.assertEqual(scorecard["status"], "live_detail_blocked")
        self.assertIn(str(blocker_path), scorecard["source_files"])
        self.assertEqual(
            scorecard["summary_fallback_reason"],
            "TOD did not answer the governed selector contract before the 30-minute aging rule elapsed.",
        )
        live_detail = next(row for row in scorecard["metrics"] if row["metric"] == "Live Reply Detail")
        self.assertIn("30-minute aging rule", live_detail["current"])

    def test_real_movement_fallback_prefers_fresh_blocked_live10_artifact(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            training_root = Path(tmp)
            interventions = training_root / "codex_training_interventions"
            interventions.mkdir(parents=True)
            module.TRAINING_ROOT = training_root
            module.LIVE_10_PATH = training_root / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
            module.REAL_MOVEMENT_PATH = training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"
            module.STRUCTURAL_PATH = training_root / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
            module.CROSS_SURFACE_PATH = training_root / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
            module.CONTEXT_GROUNDING_PATH = training_root / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
            module.OUTCOME_BINDING_PATH = training_root / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
            module.INTERVENTIONS_ROOT = interventions

            module.REAL_MOVEMENT_PATH.write_text(
                json.dumps(
                    {
                        "generated_at": "2026-07-14T00:00:00Z",
                        "metrics": [
                            {
                                "metric": "MIM Operator Impact",
                                "current": "7.0/10 from 10 live replies",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            module.LIVE_10_PATH.write_text(
                json.dumps(
                    {
                        "packet_type": "mim-operator-impact-live-10-scorecard-v1",
                        "status": "blocked",
                        "blocker_class": "live_validation_blocked",
                        "error": "URLError: socket policy blocked",
                        "sample_count": 0,
                        "pass_count": 0,
                        "operator_impact_score": 0.0,
                        "metrics": [
                            {
                                "metric": "Live Validation Blocker",
                                "baseline": "live Studio POST succeeds",
                                "current": "URLError: socket policy blocked",
                                "source": "tools/score_mim_operator_impact_live_10.py",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            scorecard = module.build_scorecard()

        self.assertEqual(scorecard["status"], "live_detail_blocked")
        self.assertIn(str(module.LIVE_10_PATH), scorecard["source_files"])
        live_detail = next(row for row in scorecard["metrics"] if row["metric"] == "Live Reply Detail")
        self.assertIn("socket policy blocked", live_detail["current"])

    def test_zero_sample_real_movement_recovers_last_verified_operator_score(self):
        module = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            training_root = Path(tmp)
            interventions = training_root / "codex_training_interventions"
            interventions.mkdir(parents=True)
            module.TRAINING_ROOT = training_root
            module.LIVE_10_PATH = training_root / "MIM_OPERATOR_IMPACT_LIVE_10_SCORECARD.latest.json"
            module.REAL_MOVEMENT_PATH = training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json"
            module.STRUCTURAL_PATH = training_root / "MIM_STRUCTURAL_REASONING_DIVERSITY_SCORECARD.latest.json"
            module.CROSS_SURFACE_PATH = training_root / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
            module.CONTEXT_GROUNDING_PATH = training_root / "MIM_CONTEXT_GROUNDED_CONVERSATION_SCORECARD.latest.json"
            module.OUTCOME_BINDING_PATH = training_root / "MIM_OPERATOR_IMPACT_OUTCOME_BINDING.latest.json"
            module.INTERVENTIONS_ROOT = interventions

            module.REAL_MOVEMENT_PATH.write_text(
                json.dumps(
                    {
                        "generated_at": "2026-07-14T00:00:00Z",
                        "metrics": [
                            {
                                "metric": "MIM Operator Impact",
                                "current": "0.0/10 from 0 live replies",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (interventions / "CODEX_TOD_SELECTOR_CONTRACT_RESPONDER_SILENCE_20260714T0050Z.json").write_text(
                json.dumps(
                    {
                        "observed_state": {
                            "operator_impact_score": "7.0/10 from 10 live replies",
                        },
                    }
                ),
                encoding="utf-8",
            )
            module.LIVE_10_PATH.write_text(
                json.dumps(
                    {
                        "status": "blocked",
                        "error": "URLError: socket blocked",
                        "sample_count": 0,
                        "pass_count": 0,
                        "operator_impact_score": 0.0,
                        "metrics": [{"metric": "Live Validation Blocker", "current": "blocked"}],
                    }
                ),
                encoding="utf-8",
            )

            scorecard = module.build_scorecard()

        self.assertEqual(scorecard["operator_impact_score"], 7.0)
        self.assertEqual(scorecard["sample_count"], 10)
        operator = next(row for row in scorecard["metrics"] if row["metric"] == "Operator Impact")
        self.assertEqual(operator["current"], "7.0/10 from 10 live replies")


if __name__ == "__main__":
    unittest.main()
