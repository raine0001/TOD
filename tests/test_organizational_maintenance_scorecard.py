import unittest

from tools.build_organizational_maintenance_scorecard import (
    borrowed_capability_ratio,
    parse_apprenticeship_registry,
)


class OrganizationalMaintenanceScorecardTests(unittest.TestCase):
    def test_parse_apprenticeship_registry_progress_states(self):
        text = """
### APP-TOD-001: First Skill

Progress: `borrowed`; Codex did it.

Proficiency: `observed`

Retirement: open.

### APP-TOD-002: Second Skill

Progress: `independent_demo_passed`; TOD repeated it.

Proficiency: `independent`

Retirement: open pending reliability.
"""
        entries = parse_apprenticeship_registry(text)
        self.assertEqual([entry["id"] for entry in entries], ["APP-TOD-001", "APP-TOD-002"])
        self.assertEqual(entries[0]["progress"], "borrowed")
        self.assertEqual(entries[1]["progress"], "independent_demo_passed")


    def test_borrowed_capability_ratio_trends_down_when_borrowed_percent_decreases(self):
        current = [
            {"progress": "borrowed"},
            {"progress": "independent_demo_passed"},
            {"progress": "retired"},
            {"progress": "scaffolded_pass"},
        ]
        previous = {"current": {"borrowed_percent": 75.0}}
        result = borrowed_capability_ratio(current, previous)
        self.assertEqual(result["current"]["borrowed_count"], 2)
        self.assertEqual(result["current"]["independent_count"], 2)
        self.assertEqual(result["current"]["retired_count"], 1)
        self.assertEqual(result["current"]["borrowed_percent"], 50.0)
        self.assertEqual(result["trend"], "improving")


if __name__ == "__main__":
    unittest.main()
