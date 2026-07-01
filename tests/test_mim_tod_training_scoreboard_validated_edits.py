import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "generate_mim_tod_training_scoreboard.py"


def load_scoreboard_module():
    spec = importlib.util.spec_from_file_location("generate_mim_tod_training_scoreboard", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class ValidatedTodEditLedgerTests(unittest.TestCase):
    def test_tod_artifact_snapshot_uses_newest_execution_artifact(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            training_root = root / "runtime_remote_training"
            shared_root = root / "runtime" / "shared"
            training_root.mkdir(parents=True)
            shared_root.mkdir(parents=True)
            (training_root / "TOD_EXECUTION_RESULT.latest.json").write_text(
                json.dumps(
                    {
                        "generated_at": "2026-06-13T23:35:51Z",
                        "updated_at": "2026-06-13T23:35:51Z",
                        "task_id": "TSK-OLD",
                        "status": "completed",
                        "files_changed": ["runtime_remote_training/old.json"],
                        "prevention_lesson": "Older training-root execution evidence should not beat a newer shared result.",
                        "validation_results": [{"name": "old", "passed": True}],
                    }
                ),
                encoding="utf-8",
            )
            (shared_root / "TOD_EXECUTION_RESULT.latest.json").write_text(
                json.dumps(
                    {
                        "generated_at": "2026-06-14T00:10:09Z",
                        "updated_at": "2026-06-14T00:10:09Z",
                        "task_id": "TSK-NEW",
                        "status": "completed",
                        "files_changed": ["scripts/TOD.ps1"],
                        "prevention_lesson": "Newest shared execution evidence should drive the latest TOD artifact snapshot.",
                        "validation_results": [{"name": "new", "passed": True}],
                    }
                ),
                encoding="utf-8",
            )
            module.TRAINING_ROOT = training_root
            module.RUNTIME_SHARED_ROOT = shared_root
            module.TOD_RESULT_ARTIFACT_ROOTS = [training_root / "tod_result_artifacts", shared_root / "tod_result_artifacts"]
            module.INDEPENDENT_ATTEMPTS_ROOT = training_root / "tod_independent_resolution_attempts"
            module.TOD_STATE_PATH = root / "tod" / "data" / "state.json"

            snapshot = module.tod_artifact_metric_snapshot()

            self.assertEqual(1, snapshot["validated_edits"]["value"])
            self.assertEqual(["scripts/TOD.ps1"], snapshot["validated_edit_records"][0]["changed_files"])

    def test_validated_edit_ledger_counts_distinct_validated_changes(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact_root = root / "tod_result_artifacts"
            artifact_root.mkdir(parents=True)
            (artifact_root / "edit-1.json").write_text(
                json.dumps(
                    {
                        "validated_edit_id": "edit-1",
                        "generated_at": "2026-06-12T20:00:00Z",
                        "status": "completed",
                        "changed_files": ["scripts/example.py"],
                        "prevention_lesson": "Require changed-file proof and validation before counting a TOD edit.",
                        "validation": {
                            "status": "passed",
                            "checks": [{"name": "compile", "passed": True}],
                        },
                    }
                ),
                encoding="utf-8",
            )
            (artifact_root / "edit-2.json").write_text(
                json.dumps(
                    {
                        "validated_edit_id": "edit-2",
                        "generated_at": "2026-06-12T21:00:00Z",
                        "status": "completed",
                        "files_changed": ["tests/test_example.py"],
                        "prevention_lesson": "Require unique result artifacts so validated edits cannot be double-counted.",
                        "validation_results": [{"name": "unit", "passed": True}],
                    }
                ),
                encoding="utf-8",
            )
            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            records = module.load_validated_edit_ledger()
            self.assertEqual(2, len(records))
            self.assertEqual({"edit-1", "edit-2"}, {record["id"] for record in records})

    def test_tod_artifact_snapshot_supplements_strict_state_proven_validated_edits(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact_root = root / "tod_result_artifacts"
            attempts_root = root / "training" / "tod_independent_resolution_attempts"
            state_path = root / "tod" / "data" / "state.json"
            artifact_root.mkdir(parents=True)
            attempts_root.mkdir(parents=True)
            (artifact_root / "artifact-edit.json").write_text(
                json.dumps(
                    {
                        "validated_edit_id": "artifact-edit",
                        "generated_at": "2026-06-14T04:40:00Z",
                        "status": "completed",
                        "changed_files": ["scripts/example.py"],
                        "prevention_lesson": "Artifact ledger edits still count when validated.",
                        "validation_results": [{"name": "compile", "passed": True}],
                    }
                ),
                encoding="utf-8",
            )
            (attempts_root / "packet.json").write_text(
                json.dumps(
                    {
                        "generated_at": "2026-06-14T04:47:49Z",
                        "packet_candidate_ready": True,
                    }
                ),
                encoding="utf-8",
            )
            state_path.parent.mkdir(parents=True)
            state_path.write_text(
                json.dumps(
                    {
                        "tasks": [
                            {
                                "id": "TSK-BEFORE-GATE",
                                "title": "Before gate code change",
                                "status": "completed",
                                "assigned_executor": "local",
                                "task_category": "code_change",
                                "updated_at": "2026-06-14T04:20:00Z",
                                "terminal_state": {
                                    "event_type": "local_executor_completed",
                                    "details": {
                                        "review_decision": "pass",
                                        "files_changed": ["scripts/old.py"],
                                        "failures": [],
                                    },
                                },
                            },
                            {
                                "id": "TSK-STATE-PROVEN",
                                "title": "After gate code change",
                                "status": "completed",
                                "assigned_executor": "local",
                                "task_category": "code_change",
                                "updated_at": "2026-06-14T05:20:00Z",
                                "terminal_state": {
                                    "event_type": "local_executor_completed",
                                    "details": {
                                        "review_decision": "pass",
                                        "files_changed": ["scripts/new.py"],
                                        "failures": [],
                                    },
                                },
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )

            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            module.INDEPENDENT_ATTEMPTS_ROOT = attempts_root
            module.TOD_STATE_PATH = state_path

            snapshot = module.tod_artifact_metric_snapshot()

            self.assertEqual(2, snapshot["validated_edits"]["value"])
            self.assertIn("tod/data/state.json", snapshot["validated_edits"]["source"])
            self.assertEqual({"artifact-edit", "TSK-STATE-PROVEN"}, {record["id"] for record in snapshot["validated_edit_records"]})

    def test_validated_edit_ledger_rejects_missing_lesson_and_wrapper_only_records(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact_root = root / "tod_result_artifacts"
            artifact_root.mkdir(parents=True)
            base = {
                "generated_at": "2026-06-12T22:00:00Z",
                "status": "completed",
                "changed_files": ["scripts/example.py"],
                "validation": {
                    "status": "passed",
                    "checks": [{"name": "compile", "passed": True}],
                },
            }
            missing_lesson = dict(base)
            missing_lesson["validated_edit_id"] = "missing-lesson"
            (artifact_root / "missing-lesson.json").write_text(json.dumps(missing_lesson), encoding="utf-8")

            wrapper_only = dict(base)
            wrapper_only["validated_edit_id"] = "wrapper-only"
            wrapper_only["prevention_lesson"] = "Wrapper-only completions must not count as validated TOD edits."
            wrapper_only["wrapper_only_completion"] = True
            (artifact_root / "wrapper-only.json").write_text(json.dumps(wrapper_only), encoding="utf-8")

            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            self.assertEqual([], module.load_validated_edit_ledger())
            audit = module.validated_edit_artifact_audit()
            self.assertEqual(
                {
                    "missing_prevention_lesson": 1,
                    "wrapper_only_completion": 1,
                },
                audit["rejection_counts"],
            )

    def test_validated_edit_ledger_rejects_failed_nested_validation_check(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            artifact_root = Path(tmp) / "tod_result_artifacts"
            artifact_root.mkdir(parents=True)
            (artifact_root / "failed-check.json").write_text(
                json.dumps(
                    {
                        "validated_edit_id": "failed-check",
                        "generated_at": "2026-06-12T22:45:00Z",
                        "status": "completed",
                        "changed_files": ["tmp_remote_mim/core/routers/studio.py"],
                        "prevention_lesson": "Failed nested checks must override a broad passed/completed status.",
                        "validation": {
                            "status": "passed",
                            "checks": [
                                {"name": "compile", "passed": True},
                                {"name": "live_smoke", "passed": False},
                            ],
                        },
                    }
                ),
                encoding="utf-8",
            )
            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            self.assertEqual([], module.load_validated_edit_ledger())
            self.assertEqual({"missing_validation_evidence": 1}, module.validated_edit_artifact_audit()["rejection_counts"])

    def test_meaningful_implementation_requires_real_code_behavior_and_live_path(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact_root = root / "tod_result_artifacts"
            artifact_root.mkdir(parents=True)
            common = {
                "generated_at": "2026-06-12T23:00:00Z",
                "status": "completed",
                "prevention_lesson": "Meaningful implementation metrics must not count low-impact metadata work.",
                "validation": {
                    "status": "passed",
                    "checks": [{"name": "unit", "passed": True}],
                },
            }
            low_impact = dict(common)
            low_impact.update(
                {
                    "validated_edit_id": "scoreboard-only",
                    "changed_files": ["scripts/generate_mim_tod_training_scoreboard.py"],
                    "behavior_change": "Changed scoreboard classification.",
                    "live_paths_affected": ["/studio/training"],
                }
            )
            (artifact_root / "scoreboard-only.json").write_text(json.dumps(low_impact), encoding="utf-8")

            meaningful = dict(common)
            meaningful.update(
                {
                    "validated_edit_id": "live-code",
                    "changed_files": ["tmp_remote_mim/core/routers/studio.py"],
                    "behavior_change": "Training replies now include the five-field operator contract.",
                    "live_paths_affected": ["/studio/api/mim/chat"],
                }
            )
            (artifact_root / "live-code.json").write_text(json.dumps(meaningful), encoding="utf-8")

            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            records = module.load_validated_edit_ledger()
            meaningful_records = [record for record in records if record["meaningful_implementation"]]
            self.assertEqual(["live-code"], [record["id"] for record in meaningful_records])

    def test_independent_resolution_requires_tod_owned_no_dave_no_codex(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            artifact_root = root / "tod_result_artifacts"
            artifact_root.mkdir(parents=True)
            base = {
                "generated_at": "2026-06-12T23:30:00Z",
                "status": "completed",
                "changed_files": ["tmp_remote_mim/core/routers/studio.py"],
                "behavior_change": "Fixed a live training chat behavior.",
                "live_paths_affected": ["/studio/api/mim/chat"],
                "problem_identified": "Training prompts were routed to the wrong handler.",
                "fix_summary": "Routed training page prompts through the training context handler first.",
                "prevention_lesson": "Independent resolutions must record problem, fix, validation, and ownership.",
                "validation": {
                    "status": "passed",
                    "checks": [{"name": "live-smoke", "passed": True}],
                },
            }
            tod_owned = dict(base)
            tod_owned.update(
                {
                    "validated_edit_id": "tod-owned",
                    "resolution_owner": "TOD",
                    "dave_needed": "no",
                    "codex_needed": "no",
                    "selected_by_tod": True,
                    "codex_patch_supplied": False,
                    "successor_state": "closed_after_validation",
                }
            )
            (artifact_root / "tod-owned.json").write_text(json.dumps(tod_owned), encoding="utf-8")

            codex_assisted = dict(base)
            codex_assisted.update(
                {
                    "validated_edit_id": "codex-assisted",
                    "resolution_owner": "TOD",
                    "dave_needed": "no",
                    "codex_needed": "yes",
                }
            )
            (artifact_root / "codex-assisted.json").write_text(json.dumps(codex_assisted), encoding="utf-8")

            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            records = module.load_validated_edit_ledger()
            independent_records = [record for record in records if record["independent_resolution"]]
            self.assertEqual(["tod-owned"], [record["id"] for record in independent_records])

    def test_new_independent_resolution_requires_tod_selection_and_closure_proof(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            artifact_root = Path(tmp) / "tod_result_artifacts"
            artifact_root.mkdir(parents=True)
            base = {
                "generated_at": "2026-06-13T15:00:00Z",
                "status": "completed",
                "changed_files": ["tmp_remote_mim/core/routers/studio.py"],
                "behavior_change": "Fixed a live training chat behavior.",
                "live_paths_affected": ["/studio/api/mim/chat"],
                "problem_identified": "Training prompts were routed to the wrong handler.",
                "fix_summary": "Routed training page prompts through the training context handler first.",
                "prevention_lesson": "Independent resolutions must prove TOD selected, fixed, validated, and closed the problem.",
                "validation": {
                    "status": "passed",
                    "checks": [{"name": "live-smoke", "passed": True}],
                },
                "resolution_owner": "TOD",
                "dave_needed": "no",
                "codex_needed": "no",
                "codex_patch_supplied": False,
            }
            missing_selection = dict(base)
            missing_selection["validated_edit_id"] = "missing-selection"
            missing_selection["successor_state"] = "closed_after_validation"
            (artifact_root / "missing-selection.json").write_text(json.dumps(missing_selection), encoding="utf-8")

            missing_closure = dict(base)
            missing_closure["validated_edit_id"] = "missing-closure"
            missing_closure["selected_by_tod"] = True
            (artifact_root / "missing-closure.json").write_text(json.dumps(missing_closure), encoding="utf-8")

            codex_patch = dict(base)
            codex_patch.update(
                {
                    "validated_edit_id": "codex-patch",
                    "selected_by_tod": True,
                    "codex_patch_supplied": True,
                    "successor_state": "closed_after_validation",
                }
            )
            (artifact_root / "codex-patch.json").write_text(json.dumps(codex_patch), encoding="utf-8")

            strict = dict(base)
            strict.update(
                {
                    "validated_edit_id": "strict-independent",
                    "selected_by_tod": True,
                    "successor_state": "closed_after_validation",
                }
            )
            (artifact_root / "strict-independent.json").write_text(json.dumps(strict), encoding="utf-8")

            module.TOD_RESULT_ARTIFACT_ROOTS = [artifact_root]
            records = module.load_validated_edit_ledger()
            independent_records = [record for record in records if record["independent_resolution"]]
            self.assertEqual(["strict-independent"], [record["id"] for record in independent_records])

    def test_forum_graphics_continuity_validation_resolves_pending_next_action(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            training_root = root / "runtime_remote_training"
            shared_root = root / "runtime" / "shared"
            training_root.mkdir(parents=True)
            shared_root.mkdir(parents=True)
            training_set_path = training_root / "TOD_NEXT_ACTION_SELECTION_TRAINING_SET.latest.json"
            validation_path = training_root / "MIM_DEVELOPMENT_CONTINUITY_FORUM_GRAPHICS_VALIDATION_2026_06_14.latest.json"
            training_set_path.write_text(
                json.dumps(
                    {
                        "records": [
                            {
                                "situation": "MIM Development Continuity V1 is waiting on the first real continuity lookup/brief validation against forum graphics.",
                                "lane": "blocker_repair",
                                "candidate_next_action": "Run blocker repair: identify the smallest unblock step, attempt it, then escalate only if MIM/TOD cannot clear it.",
                            },
                            {
                                "situation": "MIM Operations Accounting is in discovery and has no explicit acceptance criteria.",
                                "lane": "planning",
                                "candidate_next_action": "Define acceptance criteria and one current driving task before claiming progress.",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            validation_path.write_text(
                json.dumps(
                    {
                        "status": "validated_with_existing_evidence",
                        "validation_case": "forum graphics",
                        "continuity_gate_result": {"has_prior_work": True},
                    }
                ),
                encoding="utf-8",
            )

            module.TRAINING_ROOT = training_root
            module.RUNTIME_SHARED_ROOT = shared_root
            module.CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH = validation_path
            module.LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH = training_root / "missing-lab-acceptance.json"
            module.MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH = training_root / "missing-accounting-acceptance.json"
            module.MIM_SCOPE_COMPLETION_AUDIT_PATH = training_root / "missing-scope-audit.json"

            snapshot = module.tod_next_action_accuracy_snapshot()

            self.assertEqual(1, snapshot["pending_count"])
            self.assertEqual(1, snapshot["scored_count"])
            scored = snapshot["scored_records"][0]
            self.assertTrue(scored["passed"])
            self.assertEqual(str(validation_path), scored["evidence_artifact"])
            self.assertIn("continuity brief validated", scored["outcome"])
            self.assertNotIn("MIM Development Continuity V1", snapshot["pending_records"][0]["situation"])

    def test_lab_workbench_acceptance_proof_resolves_pending_next_action(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            training_root = root / "runtime_remote_training"
            shared_root = root / "runtime" / "shared"
            training_root.mkdir(parents=True)
            shared_root.mkdir(parents=True)
            training_set_path = training_root / "TOD_NEXT_ACTION_SELECTION_TRAINING_SET.latest.json"
            acceptance_path = training_root / "LAB_WORKBENCH_SERVO_TESTER_ACCEPTANCE_PROOF_2026_06_14.latest.json"
            training_set_path.write_text(
                json.dumps(
                    {
                        "records": [
                            {
                                "situation": "LAB Workbench Servo Tester has active hardware work but lacks explicit acceptance criteria.",
                                "lane": "planning",
                                "candidate_next_action": "Define acceptance criteria and one current driving task before claiming progress.",
                            },
                            {
                                "situation": "MIM Operations Accounting is in discovery and has no explicit acceptance criteria.",
                                "lane": "planning",
                                "candidate_next_action": "Define acceptance criteria and one current driving task before claiming progress.",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            acceptance_path.write_text(
                json.dumps(
                    {
                        "status": "accepted_completed",
                        "project_title": "LAB Workbench Servo Tester",
                        "operator_evidence": {"operator_completion": True},
                    }
                ),
                encoding="utf-8",
            )

            module.TRAINING_ROOT = training_root
            module.RUNTIME_SHARED_ROOT = shared_root
            module.LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH = acceptance_path
            module.CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH = training_root / "missing-continuity-validation.json"
            module.MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH = training_root / "missing-accounting-acceptance.json"
            module.MIM_SCOPE_COMPLETION_AUDIT_PATH = training_root / "missing-scope-audit.json"

            snapshot = module.tod_next_action_accuracy_snapshot()

            self.assertEqual(1, snapshot["pending_count"])
            self.assertEqual(1, snapshot["scored_count"])
            scored = snapshot["scored_records"][0]
            self.assertTrue(scored["passed"])
            self.assertEqual(6, scored["score"])
            self.assertEqual(str(acceptance_path), scored["evidence_artifact"])
            self.assertIn("operator acceptance proof", scored["outcome"])
            self.assertNotIn("LAB Workbench Servo Tester", snapshot["pending_records"][0]["situation"])

    def test_operations_accounting_acceptance_criteria_resolves_pending_next_action(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            training_root = root / "runtime_remote_training"
            shared_root = root / "runtime" / "shared"
            training_root.mkdir(parents=True)
            shared_root.mkdir(parents=True)
            training_set_path = training_root / "TOD_NEXT_ACTION_SELECTION_TRAINING_SET.latest.json"
            acceptance_path = training_root / "tod_result_artifacts" / "MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_CRITERIA_2026_06_14.latest.json"
            acceptance_path.parent.mkdir(parents=True)
            training_set_path.write_text(
                json.dumps(
                    {
                        "records": [
                            {
                                "situation": "MIM Operations Accounting is in discovery and has no explicit acceptance criteria.",
                                "lane": "planning",
                                "candidate_next_action": "Define acceptance criteria and one current driving task before claiming progress.",
                            },
                            {
                                "situation": "MIM Scope Completion Discipline V1 is active and has acceptance criteria.",
                                "lane": "execution",
                                "candidate_next_action": "Audit active projects for scope expansion and create follow-on projects when new work exceeds original acceptance by more than 30%.",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            acceptance_path.write_text(
                json.dumps(
                    {
                        "status": "acceptance_defined",
                        "project_title": "MIM Operations Accounting",
                        "first_driving_task": "Create the first internal provider-spend snapshot.",
                        "acceptance_criteria": [
                            "/studio/accounting shows MIM Operations Accounting.",
                            "Provider Cost Surfaces are visible.",
                            "Smart Actions are visible.",
                        ],
                    }
                ),
                encoding="utf-8",
            )

            module.TRAINING_ROOT = training_root
            module.RUNTIME_SHARED_ROOT = shared_root
            module.MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH = acceptance_path
            module.CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH = training_root / "missing-continuity-validation.json"
            module.LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH = training_root / "missing-lab-acceptance.json"
            module.MIM_SCOPE_COMPLETION_AUDIT_PATH = training_root / "missing-scope-audit.json"

            snapshot = module.tod_next_action_accuracy_snapshot()

            self.assertEqual(1, snapshot["pending_count"])
            self.assertEqual(1, snapshot["scored_count"])
            scored = snapshot["scored_records"][0]
            self.assertTrue(scored["passed"])
            self.assertEqual(5, scored["score"])
            self.assertEqual(str(acceptance_path), scored["evidence_artifact"])
            self.assertIn("acceptance criteria", scored["outcome"])
            self.assertNotIn("MIM Operations Accounting", snapshot["pending_records"][0]["situation"])

    def test_scope_completion_audit_resolves_scope_and_powershell_pending_actions(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            training_root = root / "runtime_remote_training"
            shared_root = root / "runtime" / "shared"
            training_root.mkdir(parents=True)
            shared_root.mkdir(parents=True)
            training_set_path = training_root / "TOD_NEXT_ACTION_SELECTION_TRAINING_SET.latest.json"
            audit_path = training_root / "tod_result_artifacts" / "MIM_SCOPE_COMPLETION_DISCIPLINE_AUDIT_2026_06_14.latest.json"
            audit_path.parent.mkdir(parents=True)
            training_set_path.write_text(
                json.dumps(
                    {
                        "records": [
                            {
                                "situation": "TOD Local PowerShell Migration has scope expansion and prior result-contract issues.",
                                "lane": "blocker_repair",
                                "candidate_next_action": "Split expanded result-binding work from the original migration acceptance before claiming completion.",
                            },
                            {
                                "situation": "MIM Scope Completion Discipline V1 is active and has acceptance criteria.",
                                "lane": "execution",
                                "candidate_next_action": "Audit active projects for scope expansion and create follow-on projects when new work exceeds original acceptance by more than 30%.",
                            },
                            {
                                "situation": "An unrelated project still has no evidence.",
                                "lane": "execution",
                                "candidate_next_action": "Inspect evidence before claiming movement.",
                            },
                        ]
                    }
                ),
                encoding="utf-8",
            )
            audit_path.write_text(
                json.dumps(
                    {
                        "status": "audit_completed_with_follow_on_split",
                        "findings": [
                            {
                                "project": "TOD Local PowerShell Migration",
                                "classification": "scope_expanded_with_follow_on_split",
                                "follow_on_project": "MIM-TOD-RESULT-BINDING-V1",
                                "original_acceptance": "Prove visible local PowerShell prompts are gone.",
                            },
                            {
                                "project": "MIM Scope Completion Discipline V1",
                                "classification": "active_acceptance_with_audit_evidence",
                                "remaining_work": "Keep applying the rule to future active projects.",
                            },
                        ],
                        "scoreboard_resolution": {
                            "tod_local_powershell_migration_pending_record": "resolved_as_scope_split",
                            "mim_scope_completion_discipline_pending_record": "resolved_as_audit_completed",
                            "completion_claim": "partial_movement_only",
                        },
                    }
                ),
                encoding="utf-8",
            )

            module.TRAINING_ROOT = training_root
            module.RUNTIME_SHARED_ROOT = shared_root
            module.MIM_SCOPE_COMPLETION_AUDIT_PATH = audit_path
            module.CONTINUITY_FORUM_GRAPHICS_VALIDATION_PATH = training_root / "missing-continuity-validation.json"
            module.LAB_WORKBENCH_ACCEPTANCE_PROOF_PATH = training_root / "missing-lab-acceptance.json"
            module.MIM_OPERATIONS_ACCOUNTING_ACCEPTANCE_PATH = training_root / "missing-accounting-acceptance.json"

            snapshot = module.tod_next_action_accuracy_snapshot()

            self.assertEqual(1, snapshot["pending_count"])
            self.assertEqual(2, snapshot["scored_count"])
            self.assertTrue(all(item["passed"] for item in snapshot["scored_records"]))
            self.assertEqual(
                [5, 5],
                sorted(item["score"] for item in snapshot["scored_records"]),
            )
            self.assertTrue(
                all(item["evidence_artifact"] == str(audit_path) for item in snapshot["scored_records"])
            )
            self.assertTrue(
                all("closed_acceptance" not in item["passed_dimensions"] for item in snapshot["scored_records"])
            )
            pending_situations = [item["situation"] for item in snapshot["pending_records"]]
            self.assertEqual(["An unrelated project still has no evidence."], pending_situations)


if __name__ == "__main__":
    unittest.main()
