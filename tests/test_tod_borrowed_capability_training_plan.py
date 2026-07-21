import unittest

from tools.build_tod_borrowed_capability_training_plan import build_plan


class TodBorrowedCapabilityTrainingPlanTests(unittest.TestCase):
    def test_plan_groups_borrowed_entries_into_priority_families(self):
        plan = build_plan()
        families = plan["training_families"]
        self.assertGreaterEqual(len(families), 8)
        self.assertEqual(families[0]["family"], "Read-Only Assessment And Authority Classification")
        self.assertIn("APP-TOD-034", families[0]["entry_ids"])
        self.assertIn("Current-Code Bounded Packet Materialization", [item["family"] for item in families])

    def test_registry_duplicate_ids_are_reported(self):
        plan = build_plan()
        self.assertIn("registry_integrity", plan)
        self.assertIn("duplicate_id_count", plan["registry_integrity"])

    def test_each_family_has_proof_gate_and_artifact(self):
        plan = build_plan()
        for family in plan["training_families"]:
            self.assertTrue(family["proof_artifact"])
            self.assertTrue(family["pass_gate"]["unique_objective_id"])
            self.assertTrue(family["pass_gate"]["validation_result"])
            self.assertTrue(family["pass_gate"]["no_wrapper_only_completion"])


if __name__ == "__main__":
    unittest.main()
