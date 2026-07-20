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
    def test_operator_impact_markdown_distinguishes_scored_from_passing_replies(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "scoreboard.md"
            scoreboard = {
                "generated_at": "2026-07-14T02:10:00Z",
                "status": "needs_attention",
                "training_hours": {
                    "last_7_days": {"value": None, "status": "baseline_needed"},
                    "yesterday": {"value": None, "status": "baseline_needed"},
                    "today": {"value": None, "status": "baseline_needed"},
                },
                "outcome_reflection": {},
                "judgment_mode_score": {},
                "mim_score": {
                    "metrics": {},
                    "operator_impact": {
                        "status": "measured_contract_fields",
                        "operator_impact_score": 7.0,
                        "operator_impact_percent": 70,
                        "pass_count": 4,
                        "sample_count": 10,
                        "generated_at": "2026-07-14T01:49:48Z",
                        "source": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
                    },
                },
                "tod_score": {
                    "metrics": {},
                    "latest_drill": {},
                },
                "recommendation": {
                    "continue_training": True,
                    "next_required_improvement": "repair operator-impact scoring clarity",
                },
            }

            module.write_markdown(scoreboard, path)

            rendered = path.read_text(encoding="utf-8")
            self.assertIn("- Replies scored: 10", rendered)
            self.assertIn("- Fully passing replies: 4/10", rendered)
            self.assertNotIn("- Replies scored: 4/10", rendered)

    def test_pending_deploy_markdown_shows_acceptance_and_proof_steps(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "scoreboard.md"
            scoreboard = {
                "generated_at": "2026-07-14T03:30:00Z",
                "status": "needs_attention",
                "training_hours": {
                    "last_7_days": {"value": None, "status": "baseline_needed"},
                    "yesterday": {"value": None, "status": "baseline_needed"},
                    "today": {"value": None, "status": "baseline_needed"},
                },
                "outcome_reflection": {},
                "judgment_mode_score": {},
                "mim_score": {"metrics": {}, "operator_impact": {}},
                "tod_score": {
                    "metrics": {},
                    "latest_drill": {},
                    "deploy_payloads": {
                        "pending_count": 1,
                        "latest": {
                            "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                            "file": "runtime_remote_training/deploy_payloads/materialization.json",
                            "purpose": "Materialize stale remediation into a bounded request.",
                            "verification_status": "not_verified",
                            "verification_reason": "current live task request is not implementation-shaped",
                            "local_reference_files": ["tmp_remote_mim/core/autonomy_driver_service.py"],
                            "local_patch_readiness": {
                                "status": "local_reference_ready",
                                "ready": True,
                                "checked": [
                                    {
                                        "path": "tmp_remote_mim/core/autonomy_driver_service.py",
                                        "exists": True,
                                    }
                                ],
                                "missing": [],
                            },
                            "target_remote_files": ["/home/testpilot/mim/core/autonomy_driver_service.py"],
                            "acceptance": [
                                "MIM no longer stops at an internal proposed_remediation_task.",
                            ],
                            "post_deploy_commands": [
                                "Verify /home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json has task_class=implementation",
                            ],
                        },
                        "pending_payloads": [],
                    },
                    "deploy_application_result": {
                        "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                        "status": "full_file_payload_applied_post_deploy_test_passed",
                        "applied_file_count": 2,
                        "no_new_channel_required": True,
                        "live_request_emitted": False,
                        "live_deployment_verified": False,
                        "remaining_blockers": [
                            "Fresh MIM_TOD_TASK_REQUEST.latest.json has not yet been emitted as implementation-shaped.",
                        ],
                    },
                },
                "recommendation": {
                    "continue_training": True,
                    "next_required_improvement": "prove bounded remediation materialization",
                },
            }

            module.write_markdown(scoreboard, path)

            rendered = path.read_text(encoding="utf-8")
            self.assertIn("Latest acceptance gates", rendered)
            self.assertIn("MIM no longer stops at an internal proposed_remediation_task", rendered)
            self.assertIn("Local patch readiness: local_reference_ready", rendered)
            self.assertIn("tmp_remote_mim/core/autonomy_driver_service.py", rendered)
            self.assertIn("Latest deploy application result", rendered)
            self.assertIn("full_file_payload_applied_post_deploy_test_passed", rendered)
            self.assertIn("Live request emitted: false", rendered)
            self.assertIn("Latest post-deploy proof steps", rendered)
            self.assertIn("task_class=implementation", rendered)

    def test_deploy_verification_queue_names_owner_and_next_proof(self):
        module = load_scoreboard_module()
        scoreboard = {
            "tod_score": {
                "deploy_payloads": {
                    "pending_payloads": [
                        {
                            "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                            "file": "runtime_remote_training/deploy_payloads/materialization.json",
                            "verification_status": "not_verified",
                            "verification_reason": "current live task request is not implementation-shaped",
                            "local_patch_readiness": {
                                "status": "local_reference_ready",
                                "ready": True,
                            },
                            "application_plan": {
                                "status": "ready_for_existing_send_script",
                                "ready": True,
                            },
                            "post_deploy_commands": [
                                "Verify /home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json has task_class=implementation",
                            ],
                        },
                        {
                            "objective_id": "MIM-CONVERSATION-MODE-SELECTION-V2",
                            "file": "runtime_remote_training/deploy_payloads/conversation.json",
                            "verification_status": "not_verified",
                            "verification_reason": "operator impact score is still 7.0/10",
                            "post_deploy_commands": [
                                "python tools/score_mim_operator_impact_live_10.py",
                            ],
                        },
                    ]
                }
            }
        }

        queue = module.build_deploy_verification_queue(scoreboard)

        self.assertEqual("needs_verification", queue["status"])
        self.assertEqual(2, queue["pending_count"])
        self.assertIn("bridge_state", queue)
        self.assertTrue(queue["bridge_state"]["no_new_channel_required"])
        item = queue["items"][0]
        self.assertEqual("MIM-STALE-REMEDIATION-MATERIALIZATION-V1", item["objective_id"])
        self.assertIn("MIM deploy/runtime owner", item["owner"])
        self.assertIn("no unless credentials", item["dave_needed"])
        self.assertIn("task_class=implementation", item["next_proof"])
        self.assertEqual("local_reference_ready", item["local_patch_readiness"]["status"])
        self.assertEqual("ready_for_existing_send_script", item["application_plan"]["status"])
        self.assertIn("new SSH or transport channel is proposed", item["no_credit_if"])
        conversation = queue["items"][1]
        self.assertEqual("MIM-CONVERSATION-MODE-SELECTION-V2", conversation["objective_id"])
        self.assertIn("operator-impact and durability scorers", conversation["owner"])

    def test_deploy_verification_queue_markdown_is_written(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            queue = {
                "artifact_type": "mim_tod_deploy_verification_queue_v1",
                "generated_at": "2026-07-14T03:45:00Z",
                "status": "needs_verification",
                "pending_count": 1,
                "bridge_state": {
                    "status": "existing_bridge_active_materialization_blocked",
                    "transport": "existing managed listener over shared MIM_TOD_TASK_REQUEST.latest.json",
                    "transport_active": True,
                    "no_new_channel_required": True,
                    "blocker": "request_materialization_missing_bounded_edit_fields",
                    "required_next_action": "Deploy the pending MIM materializer repair through the existing source/deploy path; do not add another SSH channel or transport.",
                    "current_request": {
                        "task_class": "diagnostic_only",
                        "validation_only": True,
                        "changed_files_required_for_success": False,
                        "target_file": "",
                        "target_files_type": "missing",
                        "one_target_file": False,
                    },
                    "request_copies": [
                        {
                            "source": "listener",
                            "implementation_shaped": False,
                            "task_class": "diagnostic_only",
                            "target_file": "",
                            "one_target_file": False,
                            "malformed_reasons": [
                                "task_class=diagnostic_only",
                                "validation_only=true",
                                "changed_files_required_for_success=false",
                                "one_target_file=false",
                            ],
                        }
                    ],
                },
                "items": [
                    {
                        "rank": 1,
                        "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                        "status": "not_verified",
                        "reason": "current live task request is not implementation-shaped",
                        "deploy_payload": "runtime_remote_training/deploy_payloads/materialization.json",
                        "owner": "MIM deploy/runtime owner first; TOD validates execution evidence after the live request is implementation-shaped.",
                        "dave_needed": "no unless credentials are required.",
                        "next_proof": "Verify task_class=implementation",
                        "local_patch_readiness": {
                            "status": "local_reference_ready",
                            "ready": True,
                        },
                        "application_plan": {
                            "status": "ready_for_existing_send_script",
                            "ready": True,
                        },
                        "acceptance": ["MIM no longer stops at proposal."],
                        "proof_steps": ["Verify task_class=implementation"],
                    }
                ],
            }

            paths = module.write_deploy_verification_queue(queue, out_dir)

            self.assertTrue(Path(paths["json"]).exists())
            rendered = Path(paths["md"]).read_text(encoding="utf-8")
            self.assertIn("MIM/TOD Deploy Verification Queue", rendered)
            self.assertIn("Existing Bridge State", rendered)
            self.assertIn("No new channel required: true", rendered)
            self.assertIn("request_materialization_missing_bounded_edit_fields", rendered)
            self.assertIn("Current target: target_file=missing; one_target_file=false", rendered)
            self.assertIn("Request Copies", rendered)
            self.assertIn("listener: implementation_shaped=false", rendered)
            self.assertIn("Local patch readiness: local_reference_ready", rendered)
            self.assertIn("Existing deploy path application: ready_for_existing_send_script", rendered)
            self.assertIn("MIM-STALE-REMEDIATION-MATERIALIZATION-V1", rendered)
            self.assertIn("Verify task_class=implementation", rendered)

    def test_task_request_shape_rejects_empty_target_bounded_request(self):
        module = load_scoreboard_module()
        shape = module.task_request_shape_snapshot(
            {
                "task_class": "implementation",
                "validation_only": False,
                "bounded_edit_mode": True,
                "target_file": "",
                "target_files": {},
                "completion_gate": {"changed_files_required_for_success": True},
            }
        )

        self.assertFalse(shape["implementation_shaped"])
        self.assertFalse(shape["one_target_file"])
        self.assertIn("one_target_file=false", shape["malformed_reasons"])
        self.assertIn("target_files_type=dict", shape["malformed_reasons"])

    def test_pending_deploy_payload_snapshot_counts_unverified_handoffs(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            deploy_root = root / "runtime_remote_training" / "deploy_payloads"
            deploy_root.mkdir(parents=True)
            (deploy_root / "pending.json").write_text(
                json.dumps(
                    {
                        "artifact_type": "deploy_patch_handoff",
                        "generated_at": "2026-07-14T01:58:00Z",
                        "objective_id": "MIM-TOD-REMEDIATION-DISPATCH-BOUNDED-ACTION-V1",
                        "purpose": "Convert dispatch_remediation_task into bounded implementation dispatch.",
                        "local_reference_files": ["tmp_remote_mim/core/bounded_action_registry.py"],
                        "target_remote_files": ["/home/testpilot/mim/core/bounded_action_registry.py"],
                        "acceptance": ["MIM no longer produces diagnostic-only packets."],
                    }
                ),
                encoding="utf-8",
            )
            (deploy_root / "verified.json").write_text(
                json.dumps(
                    {
                        "artifact_type": "deploy_patch_handoff",
                        "generated_at": "2026-07-13T20:00:00Z",
                        "objective_id": "DONE",
                        "status": "deployed_and_verified",
                    }
                ),
                encoding="utf-8",
            )
            module.ROOT = root
            module.TRAINING_ROOT = root / "runtime_remote_training"
            module.DEPLOY_PAYLOADS_ROOT = deploy_root
            module.CONTEXT_SYNC_ROOT = root / "tod" / "out" / "context-sync"
            module.RUNTIME_SHARED_ROOT = root / "runtime" / "shared"
            local_ref = root / "tmp_remote_mim" / "core" / "bounded_action_registry.py"
            local_ref.parent.mkdir(parents=True)
            local_ref.write_text("# local reference\n", encoding="utf-8")

            snapshot = module.pending_deploy_payload_snapshot()

            self.assertEqual(1, snapshot["pending_count"])
            self.assertEqual("MIM-TOD-REMEDIATION-DISPATCH-BOUNDED-ACTION-V1", snapshot["latest"]["objective_id"])
            self.assertEqual(["/home/testpilot/mim/core/bounded_action_registry.py"], snapshot["latest"]["target_remote_files"])
            self.assertEqual("local_reference_ready", snapshot["latest"]["local_patch_readiness"]["status"])
            self.assertTrue(snapshot["latest"]["local_patch_readiness"]["ready"])
            self.assertEqual("ready_for_existing_send_script", snapshot["latest"]["application_plan"]["status"])
            self.assertIn("scripts\\Send-TODMimScript.ps1", snapshot["latest"]["application_plan"]["apply_commands"][0])
            self.assertIn("/home/testpilot/mim/core/bounded_action_registry.py", snapshot["latest"]["application_plan"]["apply_commands"][0])

    def test_pending_deploy_payload_snapshot_explains_unverified_live_evidence(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            training_root = root / "runtime_remote_training"
            deploy_root = training_root / "deploy_payloads"
            context_root = root / "tod" / "out" / "context-sync"
            deploy_root.mkdir(parents=True)
            (deploy_root / "conversation.json").write_text(
                json.dumps(
                    {
                        "artifact_type": "deploy_patch_handoff",
                        "generated_at": "2026-07-13T23:40:00Z",
                        "objective_id": "MIM-CONVERSATION-MODE-SELECTION-V2",
                    }
                ),
                encoding="utf-8",
            )
            (deploy_root / "remediation.json").write_text(
                json.dumps(
                    {
                        "artifact_type": "deploy_patch_handoff",
                        "generated_at": "2026-07-14T01:58:00Z",
                        "objective_id": "MIM-TOD-REMEDIATION-DISPATCH-BOUNDED-ACTION-V1",
                    }
                ),
                encoding="utf-8",
            )
            (deploy_root / "stale_remediation.json").write_text(
                json.dumps(
                    {
                        "artifact_type": "deploy_patch_handoff",
                        "generated_at": "2026-07-14T03:30:00Z",
                        "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                    }
                ),
                encoding="utf-8",
            )
            (training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json").write_text(
                json.dumps(
                    {
                        "operator_impact_score": 7.0,
                        "pass_count": 4,
                        "sample_count": 10,
                    }
                ),
                encoding="utf-8",
            )
            listener_root = context_root / "listener"
            listener_root.mkdir(parents=True)
            (listener_root / "MIM_TOD_TASK_REQUEST.latest.json").write_text(
                json.dumps(
                    {
                        "task_class": "diagnostic_only",
                        "validation_only": True,
                        "completion_gate": {
                            "changed_files_required_for_success": False,
                        },
                    }
                ),
                encoding="utf-8",
            )
            module.ROOT = root
            module.TRAINING_ROOT = training_root
            module.DEPLOY_PAYLOADS_ROOT = deploy_root
            module.CONTEXT_SYNC_ROOT = context_root
            module.RUNTIME_SHARED_ROOT = root / "runtime" / "shared"

            snapshot = module.pending_deploy_payload_snapshot()

            by_objective = {
                item["objective_id"]: item
                for item in snapshot["pending_payloads"]
            }
            conversation = by_objective["MIM-CONVERSATION-MODE-SELECTION-V2"]
            remediation = by_objective["MIM-TOD-REMEDIATION-DISPATCH-BOUNDED-ACTION-V1"]
            stale_remediation = by_objective["MIM-STALE-REMEDIATION-MATERIALIZATION-V1"]
            self.assertEqual("not_verified", conversation["verification_status"])
            self.assertIn("7.0/10", conversation["verification_reason"])
            self.assertEqual("not_verified", remediation["verification_status"])
            self.assertIn("task_class=diagnostic_only", remediation["verification_reason"])
            self.assertEqual("not_verified", stale_remediation["verification_status"])
            self.assertIn("task_class=diagnostic_only", stale_remediation["verification_reason"])

    def test_partial_hunk_deploy_payload_does_not_generate_full_file_send_command(self):
        module = load_scoreboard_module()
        plan = module.deploy_file_application_plan(
            ["tmp_remote_mim/core/routers/studio.py"],
            ["/home/testpilot/mim/core/routers/studio.py"],
            {
                "warning": "Do not upload the whole local reference file. Apply only the route-order hunk.",
            },
        )

        self.assertEqual("partial_patch_hunk_required", plan["status"])
        self.assertFalse(plan["ready"])
        self.assertTrue(plan["partial_patch_required"])
        self.assertEqual([], plan["apply_commands"])
        self.assertIn("full-file Send-TODMimScript upload is intentionally withheld", plan["note"])

    def test_deploy_application_manifest_uses_existing_send_script(self):
        module = load_scoreboard_module()
        queue = {
            "bridge_state": {
                "status": "existing_bridge_active_materialization_blocked",
                "no_new_channel_required": True,
            },
            "items": [
                {
                    "rank": 1,
                    "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                    "deploy_payload": "runtime_remote_training/deploy_payloads/materialization.json",
                    "status": "not_verified",
                    "reason": "current live task request is not implementation-shaped",
                    "proof_steps": ["Verify task_class=implementation"],
                    "application_plan": {
                        "status": "ready_for_existing_send_script",
                        "ready": True,
                        "pairs": [
                            {
                                "local_path": "tmp_remote_mim/core/autonomy_driver_service.py",
                                "remote_path": "/home/testpilot/mim/core/autonomy_driver_service.py",
                                "local_exists": True,
                                "sha256": "abc",
                                "size_bytes": 10,
                                "apply_command": "powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 -LocalPath 'tmp_remote_mim/core/autonomy_driver_service.py' -RemotePath '/home/testpilot/mim/core/autonomy_driver_service.py'",
                            }
                        ],
                        "apply_commands": [
                            "powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 -LocalPath 'tmp_remote_mim/core/autonomy_driver_service.py' -RemotePath '/home/testpilot/mim/core/autonomy_driver_service.py'",
                        ],
                    },
                }
            ],
        }

        manifest = module.build_deploy_application_manifest(queue)

        self.assertEqual("ready_to_apply_existing_path", manifest["status"])
        self.assertTrue(manifest["no_new_channel_required"])
        self.assertEqual("scripts\\Send-TODMimScript.ps1", manifest["existing_apply_script"])
        self.assertIn("Send-TODMimScript.ps1", manifest["items"][0]["apply_commands"][0])
        self.assertIn("does not award TOD independent-resolution credit", manifest["credit_policy"])

    def test_deploy_application_manifest_reports_ready_with_partial_hunks(self):
        module = load_scoreboard_module()
        queue = {
            "bridge_state": {
                "status": "existing_bridge_active_materialization_blocked",
                "no_new_channel_required": True,
            },
            "items": [
                {
                    "rank": 1,
                    "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                    "application_plan": {
                        "status": "ready_for_existing_send_script",
                        "ready": True,
                        "pairs": [
                            {
                                "local_path": "tmp_remote_mim/core/autonomy_driver_service.py",
                                "remote_path": "/home/testpilot/mim/core/autonomy_driver_service.py",
                                "apply_command": "powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 -LocalPath 'a' -RemotePath 'b'",
                            }
                        ],
                        "apply_commands": [
                            "powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 -LocalPath 'a' -RemotePath 'b'",
                        ],
                    },
                },
                {
                    "rank": 2,
                    "objective_id": "MIM-CONVERSATION-MODE-SELECTION-V2",
                    "application_plan": {
                        "status": "partial_patch_hunk_required",
                        "ready": False,
                        "pairs": [
                            {
                                "local_path": "tmp_remote_mim/core/routers/studio.py",
                                "remote_path": "/home/testpilot/mim/core/routers/studio.py",
                                "apply_command": "",
                            }
                        ],
                        "apply_commands": [],
                    },
                },
            ],
        }

        manifest = module.build_deploy_application_manifest(queue)

        self.assertEqual("ready_with_partial_hunks_required", manifest["status"])
        self.assertEqual(1, manifest["ready_count"])
        self.assertEqual(1, manifest["partial_hunk_count"])

    def test_deploy_application_manifest_markdown_is_written(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            manifest = {
                "artifact_type": "mim_tod_deploy_application_manifest_v1",
                "generated_at": "2026-07-14T04:30:00Z",
                "status": "ready_to_apply_existing_path",
                "ready_count": 1,
                "pending_count": 1,
                "no_new_channel_required": True,
                "existing_apply_script": "scripts\\Send-TODMimScript.ps1",
                "credit_policy": "No TOD independent credit.",
                "items": [
                    {
                        "rank": 1,
                        "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                        "application_status": "ready_for_existing_send_script",
                        "ready": True,
                        "verification_status": "not_verified",
                        "verification_reason": "current live task request is not implementation-shaped",
                        "deploy_payload": "runtime_remote_training/deploy_payloads/materialization.json",
                        "apply_commands": ["powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 -LocalPath 'a' -RemotePath 'b'"],
                        "post_deploy_proof_steps": ["Verify task_class=implementation"],
                    }
                ],
            }

            paths = module.write_deploy_application_manifest(manifest, out_dir)

            rendered = Path(paths["md"]).read_text(encoding="utf-8")
            self.assertIn("MIM/TOD Deploy Application Manifest", rendered)
            self.assertIn("No new channel required: true", rendered)
            self.assertIn("Partial hunk payloads", rendered)
            self.assertIn("Send-TODMimScript.ps1", rendered)
            self.assertIn("Verify task_class=implementation", rendered)

    def test_deploy_application_preflight_verifies_hashes_and_existing_script(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            local_file = root / "tmp_remote_mim" / "core" / "autonomy_driver_service.py"
            local_file.parent.mkdir(parents=True)
            local_file.write_text("print('ready')\n", encoding="utf-8")
            digest = __import__("hashlib").sha256(local_file.read_bytes()).hexdigest()
            module.ROOT = root
            manifest = {
                "no_new_channel_required": True,
                "existing_apply_script": "scripts\\Send-TODMimScript.ps1",
                "credit_policy": "No TOD independent credit.",
                "items": [
                    {
                        "rank": 1,
                        "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                        "file_pairs": [
                            {
                                "local_path": "tmp_remote_mim/core/autonomy_driver_service.py",
                                "remote_path": "/home/testpilot/mim/core/autonomy_driver_service.py",
                                "sha256": digest,
                                "apply_command": "powershell -NoProfile -File scripts\\Send-TODMimScript.ps1 -LocalPath 'tmp_remote_mim/core/autonomy_driver_service.py' -RemotePath '/home/testpilot/mim/core/autonomy_driver_service.py'",
                            }
                        ],
                    }
                ],
            }

            preflight = module.build_deploy_application_preflight(manifest)

            self.assertEqual("passed_ready_for_existing_apply", preflight["status"])
            self.assertTrue(preflight["passed"])
            self.assertEqual(1, preflight["verified_pairs"])
            self.assertEqual(1, preflight["verified_full_apply_pairs"])
            self.assertEqual(0, preflight["hunk_required_count"])
            self.assertFalse(preflight["live_deployment_verified"])
            pair = preflight["items"][0]["pairs"][0]
            self.assertTrue(pair["sha256_matches"])
            self.assertTrue(pair["command_uses_existing_script"])
            self.assertTrue(pair["remote_target_valid"])

    def test_deploy_application_preflight_markdown_is_written(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            preflight = {
                "artifact_type": "mim_tod_deploy_application_preflight_v1",
                "generated_at": "2026-07-14T04:45:00Z",
                "status": "ready_with_partial_hunks_required",
                "passed": True,
                "verified_pairs": 1,
                "total_pairs": 1,
                "verified_full_apply_pairs": 0,
                "full_apply_pairs": 0,
                "hunk_required_count": 1,
                "no_new_channel_required": True,
                "live_deployment_verified": False,
                "next_action": "Materialize partial hunk payloads against the live file.",
                "credit_policy": "No TOD independent credit.",
                "items": [
                    {
                        "rank": 1,
                        "objective_id": "MIM-STALE-REMEDIATION-MATERIALIZATION-V1",
                        "passed": True,
                        "application_status": "partial_patch_hunk_required",
                        "ready_for_full_file_apply": False,
                        "pair_count": 1,
                        "pairs": [
                            {
                                "local_path": "tmp_remote_mim/core/autonomy_driver_service.py",
                                "remote_path": "/home/testpilot/mim/core/autonomy_driver_service.py",
                                "local_exists": True,
                                "sha256_matches": True,
                                "command_uses_existing_script": True,
                            }
                        ],
                    }
                ],
            }

            paths = module.write_deploy_application_preflight(preflight, out_dir)

            rendered = Path(paths["md"]).read_text(encoding="utf-8")
            self.assertIn("MIM/TOD Deploy Application Preflight", rendered)
            self.assertIn("Status: ready_with_partial_hunks_required", rendered)
            self.assertIn("Live deployment verified: false", rendered)
            self.assertIn("Partial hunk payloads: 1", rendered)

    def test_deploy_application_preflight_treats_partial_hunks_as_not_failed(self):
        module = load_scoreboard_module()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            local_file = root / "tmp_remote_mim" / "core" / "routers" / "studio.py"
            local_file.parent.mkdir(parents=True)
            local_file.write_text("print('partial')\n", encoding="utf-8")
            digest = __import__("hashlib").sha256(local_file.read_bytes()).hexdigest()
            module.ROOT = root
            manifest = {
                "no_new_channel_required": True,
                "existing_apply_script": "scripts\\Send-TODMimScript.ps1",
                "items": [
                    {
                        "rank": 1,
                        "objective_id": "MIM-CONVERSATION-MODE-SELECTION-V2",
                        "application_status": "partial_patch_hunk_required",
                        "file_pairs": [
                            {
                                "local_path": "tmp_remote_mim/core/routers/studio.py",
                                "remote_path": "/home/testpilot/mim/core/routers/studio.py",
                                "sha256": digest,
                                "apply_command": "",
                            }
                        ],
                    }
                ],
            }

            preflight = module.build_deploy_application_preflight(manifest)

            self.assertEqual("ready_with_partial_hunks_required", preflight["status"])
            self.assertTrue(preflight["passed"])
            self.assertEqual([], preflight["failed_checks"])
            self.assertEqual(1, preflight["hunk_required_count"])
            self.assertEqual(0, preflight["full_apply_pairs"])
            self.assertEqual(1, preflight["verified_pairs"])
            self.assertFalse(preflight["items"][0]["ready_for_full_file_apply"])

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
