import importlib.util
import json
import os
from datetime import datetime as real_datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "build_mim_tod_real_movement_scorecard.py"


def load_module():
    spec = importlib.util.spec_from_file_location("real_movement", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def test_tod_codex_handoff_drift_is_first_class_signal():
    module = load_module()

    current = module._tod_codex_handoff_drift_current(
        {
            "status": "blocked",
            "reason_code": "blocked_missing_bounded_edit_mode",
            "task_id": "task-1",
        },
        {
            "status": "blocked",
            "next_action": "codex_allowed_after_local_blocked_with_inspection",
        },
    )

    assert "handoff_drift_detected" in current
    assert "required=TOD-owned bounded packet or smaller live-path task" in current


def test_packet_field_reads_nested_ready_packet():
    module = load_module()

    payload = {
        "packet_candidate_ready": True,
        "packet": {
            "target_file": "tmp_remote_mim/core/routers/studio.py",
            "intended_edit_mode": "replace_text",
            "old_text": "old",
            "new_text": "new",
        },
    }

    assert module._packet_field(payload, "target_file") == "tmp_remote_mim/core/routers/studio.py"
    assert module._packet_field(payload, "intended_edit_mode", "edit_mode") == "replace_text"
    assert module._packet_field(payload, "old_text") == "old"


def test_real_movement_card_supersedes_stale_packet_blockers_after_material_execution(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "training"
    context_root = tmp_path / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    interventions_root = training_root / "codex_training_interventions"
    runtime_shared = tmp_path / "runtime" / "shared"

    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "CODEX_TRAINING_INTERVENTIONS_ROOT", interventions_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "SELECTION_BLOCKER_PATH", interventions_root / "CODEX_TOD_SELECTION_BLOCKER_REPEAT_20260615T1139Z.latest.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", tmp_path / "shared_state" / "dialog" / "MIM_TOD_DIALOG.sessions.latest.json")
    monkeypatch.setattr(module, "RUNTIME_TOD_ACTIVE_TASK_PATH", runtime_shared / "TOD_ACTIVE_TASK.latest.json")
    monkeypatch.setattr(module, "TOD_EXECUTION_RESULT_PATH", runtime_shared / "TOD_EXECUTION_RESULT.latest.json")
    monkeypatch.setattr(module, "TOD_TASK_REQUEST_PATH", context_root / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json")
    monkeypatch.setattr(module, "RUNTIME_TOD_TASK_REQUEST_PATH", runtime_shared / "MIM_TOD_TASK_REQUEST.latest.json")
    monkeypatch.setattr(module, "TOD_LISTENER_RESULT_PATH", context_root / "listener" / "TOD_MIM_TASK_RESULT.latest.json")
    monkeypatch.setattr(module, "TOD_REFLECTION_PULL_RESULT_PATH", tmp_path / "runtime" / "logs" / "mim_tod_reflection_pull" / "TOD_MIM_TASK_RESULT.latest.json")
    monkeypatch.setattr(module, "TRAINING_TOD_TASK_RESULT_PATH", training_root / "TOD_MIM_TASK_RESULT.latest.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "9.8/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 46},
                    "meaningful_tod_implementations": {"value": 30},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    write_json(
        module.SELECTION_BLOCKER_PATH,
        {
            "generated_at": "2026-06-15T11:39:00Z",
            "status": "active_blocker",
            "blocker_type": "smaller_task_selection",
            "objective_id": "OBJ-0237",
            "dave_needed": "no",
        },
    )
    write_json(
        interventions_root / "CODEX_TOD_STUDIO_TARGET_PACKET_MATERIALIZATION_20260615T210000Z.latest.json",
        {
            "generated_at": "2026-06-15T21:00:00Z",
            "status": "blocked_requires_old_new",
            "next_action": "Repair old/new materialization.",
        },
    )
    write_json(
        attempts_root / "TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json",
        {
            "generated_at": "2026-06-16T16:57:57Z",
            "status": "packet_candidate_ready",
            "task_id": "TSK-3271",
            "packet_candidate_ready": True,
            "packet": {
                "target_file": "tmp_remote_mim/core/routers/studio.py",
                "intended_edit_mode": "replace_text",
                "old_text": "I recommend working on TOD self-authored bounded edit materialization next.",
                "new_text": "I recommend working on TOD current-code packet materialization next.",
                "validation_command": "python -m py_compile tmp_remote_mim/core/routers/studio.py",
                "prevention_lesson": "Use current-code packet materialization.",
                "dave_needed": "no",
            },
            "credit_decision": {"independent_tod_resolution": False},
        },
    )
    write_json(
        runtime_shared / "TOD_NEXT_TASK_SELECTION.latest.json",
        {
            "generated_at": "2026-06-16T17:01:00Z",
            "request_id": "TSK-3272",
            "selected_task_id": "TSK-3272",
            "selection_kind": "packet_candidate_code_task",
            "target_file": "tmp_remote_mim/core/routers/studio.py",
            "target_function_or_rule": "Studio recommendation wording",
            "behavior_delta_one_sentence": "Replace self-authored bounded edit wording with current-code packet materialization wording.",
            "validation_command": "python -m py_compile tmp_remote_mim/core/routers/studio.py",
            "expected_changed_files": ["tmp_remote_mim/core/routers/studio.py"],
            "rollback_note": "Restore old recommendation wording.",
            "prevention_lesson": "Do not stop at packet formation when a ready packet can be materialized.",
        },
    )
    write_json(
        runtime_shared / "TOD_ACTIVE_TASK.latest.json",
        {
            "generated_at": "2026-06-16T17:02:00Z",
            "task_id": "TSK-3272",
            "status": "completed",
        },
    )
    write_json(
        runtime_shared / "TOD_EXECUTION_RESULT.latest.json",
        {
            "generated_at": "2026-06-16T17:02:10Z",
            "task_id": "TSK-3272",
            "status": "completed",
            "summary": "LocalExecutionEngine completed the bounded local fallback for tmp_remote_mim/core/routers/studio.py.",
            "files_changed": ["tmp_remote_mim/core/routers/studio.py"],
            "validation_results": [{"name": "focused_validation_exit_zero", "passed": True}],
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    assert "TOD smaller-task selection is still blocked" not in payload["overall_readout"]
    assert payload["status"] == "on_track"
    independent = next(row for row in payload["metrics"] if row["metric"] == "Independent TOD Resolutions")
    assert independent["current"] == "2"
    selection_blocker = next(row for row in payload["metrics"] if row["metric"] == "TOD Smaller-Task Selection Blocker")
    assert selection_blocker["current"].startswith("superseded_by_packet_candidate_execution")
    packet = next(row for row in payload["metrics"] if row["metric"] == "TOD Current-Code Packet Capability")
    assert "post_timeout_packet_candidate_ready" in packet["current"]
    assert "target=tmp_remote_mim/core/routers/studio.py" in packet["current"]
    studio_packet = next(row for row in payload["metrics"] if row["metric"] == "TOD Studio Target Packet Materialization")
    assert studio_packet["current"].startswith("superseded_by_current_packet_materialization")


def test_real_movement_card_exposes_latest_independent_resolution_blocker(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "training"
    context_root = tmp_path / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 17},
                    "meaningful_tod_implementations": {"value": 11},
                    "independent_tod_resolutions": {"value": 1},
                }
            },
        },
    )
    write_json(attempts_root / "older.json", {"status": "older", "selection_kind": "old"})
    write_json(
        attempts_root / "latest.json",
        {
            "status": "blocked_no_ready_materialized_candidate_after_backlog_audit",
            "selection_kind": "blocked_no_materialized_independent_resolution_candidate",
            "dispatch_status": "blocked_with_reason",
            "source_task_id": "TSK-3145",
            "backlog_audit": {"ready_codeish_task_count": 4},
            "tod_next_action": "Inspect the candidate target file and produce a bounded edit or exact blocker.",
        },
    )
    write_json(
        attempts_root / "newest_visibility_note.json",
        {
            "status": "completed_visibility_repair_not_counted",
            "not_counted_as_independent_resolution": True,
        },
    )
    write_json(
        training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json",
        {
            "status": "ready_for_tod_attempt",
            "exercise_id": "practice-001",
            "required_outputs": ["current_anchor", "proposed_old_text", "proposed_new_text"],
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Candidate State")
    assert "blocked_no_ready_materialized_candidate_after_backlog_audit" in metric["current"]
    assert "ready_codeish=4" in metric["current"]
    assert metric["source"] == "latest.json"
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Next Action")
    assert "bounded edit or exact blocker" in next_action["current"]
    assert next_action["source"] == "latest.json"
    practice = next(row for row in payload["metrics"] if row["metric"] == "Corrected Patch Synthesis Practice")
    assert "ready_for_tod_attempt" in practice["current"]
    assert "exercise=practice-001" in practice["current"]
    assert "required_outputs=3" in practice["current"]


def test_real_movement_card_prefers_latest_no_credit_attempt_over_older_selector(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "training"
    context_root = tmp_path / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "metrics": {
                    "validated_edits": {"value": 23},
                    "meaningful_tod_implementations": {"value": 16},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    old_selector = attempts_root / "older_selector.json"
    latest_no_credit = attempts_root / "latest_no_credit.json"
    write_json(
        old_selector,
        {
            "status": "practice_completed_no_credit_ready_for_behavior_candidate",
            "selection_kind": "blocked_no_behavior_changing_autonomy_candidate",
            "task_id": "TSK-3167",
        },
    )
    write_json(
        latest_no_credit,
        {
            "status": "no_credit_validation_passed_without_material_diff",
            "task_id": "TSK-3171",
            "observed_evidence": {"files_changed": [], "pre_patch_hash": "same", "post_patch_hash": "same"},
            "credit_decision": {"validated_tod_edit": False, "reason": "identical target hash"},
            "next_action": {
                "recommended_action": "Teach the local execution result publisher to reject identical-hash code_change output."
            },
        },
    )
    os.utime(old_selector, (1_700_000_000, 1_700_000_000))
    os.utime(latest_no_credit, (1_700_000_100, 1_700_000_100))

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Candidate State")
    assert "no_credit_validation_passed_without_material_diff" in metric["current"]
    assert "source=TSK-3171" in metric["current"]
    assert metric["source"] == "latest_no_credit.json"
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Next Action")
    assert "identical-hash code_change output" in next_action["current"]


def test_real_movement_card_supersedes_artifact_write_blocker_with_newer_practice_evidence(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "training"
    context_root = tmp_path / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    practice_path = training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", practice_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 25},
                    "meaningful_tod_implementations": {"value": 17},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    blocker_path = attempts_root / "artifact_write_blocker.json"
    write_json(
        blocker_path,
        {
            "generated_at": "2026-06-14T04:03:00Z",
            "status": "blocked_local_artifact_write_regression",
            "selection_kind": "packet_formation_blocked_by_local_artifact_write_regression",
            "dispatch_status": "blocked_with_reason",
            "task_id": "TSK-3183",
            "tod_next_action": "Repair artifact_write before retrying packet formation.",
        },
    )
    write_json(
        practice_path,
        {
            "generated_at": "2026-06-14T04:14:58Z",
            "status": "practice_blocked_with_current_code_inspection",
            "task_id": "TSK-3184",
            "source": "LocalExecutionEngine.artifact_write",
            "exercise_id": "TOD-CORRECTED-PATCH-SYNTHESIS-PRACTICE-V1",
            "required_outputs_filled": True,
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Candidate State")
    assert "artifact_write_validated_by_practice_artifact" in metric["current"]
    assert "blocked_local_artifact_write_regression" not in metric["current"]
    assert metric["source"] == "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json"
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Next Action")
    assert "Do not spend another cycle on artifact_write" in next_action["current"]


def test_real_movement_card_counts_state_proven_independent_resolution_after_packet_gate(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "training"
    context_root = tmp_path / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    state_path = tmp_path / "tod" / "data" / "state.json"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", state_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 25},
                    "meaningful_tod_implementations": {"value": 17},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    write_json(
        attempts_root / "packet.json",
        {
            "generated_at": "2026-06-14T04:47:49Z",
            "status": "packet_candidate_ready",
            "packet_candidate_ready": True,
            "task_id": "TSK-PACKET",
        },
    )
    write_json(
        state_path,
        {
            "tasks": [
                {
                    "id": "TSK-PACKET",
                    "title": "Form packet artifact",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "packet_formation",
                    "updated_at": "2026-06-14T04:48:00Z",
                    "terminal_state": {"event_type": "local_executor_completed", "details": {"review_decision": "pass", "files_changed": ["packet.json"], "failures": []}},
                },
                {
                    "id": "TSK-STATE-PROVEN",
                    "title": "Clarify stale synthesized candidate validation plan",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "code_change",
                    "updated_at": "2026-06-14T04:56:50Z",
                    "terminal_state": {
                        "event_type": "local_executor_completed",
                        "details": {
                            "review_decision": "pass",
                            "files_changed": ["scripts/TOD.ps1"],
                            "failures": [],
                        },
                    },
                },
            ]
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Independent TOD Resolutions")
    assert metric["current"] == "3 (2 scoreboard + 1 state-proven: TSK-STATE-PROVEN)"
    assert metric["source"] == "tod/data/state.json + tod_result_artifacts"


def test_real_movement_card_uses_fresh_selector_display_without_losing_packet_gate(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    state_path = root / "tod" / "data" / "state.json"
    selector_path = root / "runtime" / "shared" / "TOD_NEXT_TASK_SELECTION.latest.json"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", state_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 25},
                    "meaningful_tod_implementations": {"value": 17},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    write_json(
        attempts_root / "packet.json",
        {
            "generated_at": "2026-06-14T04:47:49Z",
            "status": "packet_candidate_ready",
            "packet_candidate_ready": True,
            "task_id": "TSK-PACKET",
        },
    )
    write_json(
        selector_path,
        {
            "generated_at": "2026-06-14T06:36:58Z",
            "selection_kind": "synthesized_independent_resolution_candidate",
            "dispatch_status": "completed",
            "selected_task_id": "TSK-SELECTOR",
            "reason_selected": "TOD synthesized the current bounded scorecard repair.",
        },
    )
    write_json(
        state_path,
        {
            "tasks": [
                {
                    "id": "TSK-OLD",
                    "title": "Old code change before packet gate",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "code_change",
                    "updated_at": "2026-06-14T04:20:00Z",
                    "terminal_state": {
                        "event_type": "local_executor_completed",
                        "details": {"review_decision": "pass", "files_changed": ["old.py"], "failures": []},
                    },
                },
                {
                    "id": "TSK-NEW",
                    "title": "New scorecard code change after gate",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "code_change",
                    "updated_at": "2026-06-14T05:20:00Z",
                    "terminal_state": {
                        "event_type": "local_executor_completed",
                        "details": {"review_decision": "pass", "files_changed": ["new.py"], "failures": []},
                    },
                },
            ]
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    independent = next(row for row in payload["metrics"] if row["metric"] == "Independent TOD Resolutions")
    assert independent["current"] == "3 (2 scoreboard + 1 state-proven: TSK-NEW)"
    candidate = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Candidate State")
    assert candidate["current"] == "completed; selection=synthesized_independent_resolution_candidate; source=TSK-SELECTOR"
    assert candidate["source"] == "TOD_NEXT_TASK_SELECTION.latest.json"
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Next Action")
    assert next_action["current"] == "TOD synthesized the current bounded scorecard repair."


def test_real_movement_card_prefers_exact_field_blocker_next_action(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    state_path = root / "tod" / "data" / "state.json"
    selector_path = root / "runtime" / "shared" / "TOD_NEXT_TASK_SELECTION.latest.json"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", state_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 42},
                    "meaningful_tod_implementations": {"value": 26},
                    "independent_tod_resolutions": {"value": 10},
                }
            },
        },
    )
    write_json(
        selector_path,
        {
            "generated_at": "2026-06-14T18:36:35Z",
            "selection_kind": "blocked_packet_anchor_consumed_requires_fresh_candidate",
            "dispatch_status": "blocked_with_reason",
            "reason_selected": "The latest packet was already applied; choose another target.",
            "validation_plan": [
                "latest packet candidate is not actionable",
                "do not create another packet-formation recovery task for the same consumed anchor; inspect a different current-code behavior target and publish target_file, edit_mode, exact_current_anchor_or_old_text, different_new_text, validation_command, closure_evidence, prevention_lesson, dave_needed=no, or publish a narrower inspected blocker",
            ],
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    candidate = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Candidate State")
    assert "blocked_packet_anchor_consumed_requires_fresh_candidate" in candidate["current"]
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Next Action")
    assert "exact_current_anchor_or_old_text" in next_action["current"]
    assert "The latest packet was already applied" not in next_action["current"]


def test_real_movement_card_newer_packet_does_not_reset_state_proven_count(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    state_path = root / "tod" / "data" / "state.json"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", state_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 25},
                    "meaningful_tod_implementations": {"value": 17},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    write_json(
        attempts_root / "packet_old.json",
        {
            "generated_at": "2026-06-14T04:47:49Z",
            "status": "packet_candidate_ready",
            "packet_candidate_ready": True,
        },
    )
    write_json(
        attempts_root / "packet_new.json",
        {
            "generated_at": "2026-06-14T08:04:54Z",
            "status": "packet_candidate_ready",
            "packet_candidate_ready": True,
        },
    )
    write_json(
        state_path,
        {
            "tasks": [
                {
                    "id": "TSK-BEFORE",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "code_change",
                    "updated_at": "2026-06-14T04:20:00Z",
                    "terminal_state": {"event_type": "local_executor_completed", "details": {"review_decision": "pass", "files_changed": ["before.py"], "failures": []}},
                },
                {
                    "id": "TSK-MIDDLE",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "code_change",
                    "updated_at": "2026-06-14T05:20:00Z",
                    "terminal_state": {"event_type": "local_executor_completed", "details": {"review_decision": "pass", "files_changed": ["middle.py"], "failures": []}},
                },
                {
                    "id": "TSK-AFTER-NEW-PACKET",
                    "status": "completed",
                    "assigned_executor": "local",
                    "task_category": "code_change",
                    "updated_at": "2026-06-14T08:20:00Z",
                    "terminal_state": {"event_type": "local_executor_completed", "details": {"review_decision": "pass", "files_changed": ["after.py"], "failures": []}},
                },
            ]
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    validated = next(row for row in payload["metrics"] if row["metric"] == "Validated TOD Edits")
    assert validated["current"] == "25"
    assert validated["source"] == "tod_result_artifacts"
    metric = next(row for row in payload["metrics"] if row["metric"] == "Independent TOD Resolutions")
    assert metric["current"] == "4 (2 scoreboard + 2 state-proven: TSK-MIDDLE, TSK-AFTER-NEW-PACKET)"


def test_real_movement_card_surfaces_idle_successor_action(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {"metrics": [{"metric": "Operator Impact", "current": "10.0/10"}, {"metric": "Dave Needed Clarity", "current": "100%"}]},
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 33, "source": "tod_result_artifacts + tod/data/state.json"},
                    "meaningful_tod_implementations": {"value": 17},
                    "independent_tod_resolutions": {"value": 2},
                }
            },
        },
    )
    write_json(
        context_root / "MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        {
            "status": "idle_training_running",
            "last_action": "no_ready_task_idle_training_active",
            "idle_training": {
                "blocked_objective_training": {
                    "next_drill": "TOD-BLOCKER-CLEARING-DRILL-004: repair one linked-task empty-evidence blocker end-to-end"
                }
            },
        },
    )
    write_json(
        context_root / "TOD_IDLE_TRAINING_STATUS.latest.json",
        {
            "state": "running",
            "blocked_objective_training": {
                "current_drill": "TOD-BLOCKER-CLEARING-DRILL-003",
                "current_drill_status": "active_with_initial_inspection",
                "next_drill": "TOD-BLOCKER-CLEARING-DRILL-004: repair one linked-task empty-evidence blocker end-to-end",
            },
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    dispatcher = next(row for row in payload["metrics"] if row["metric"] == "Dispatcher State")
    assert "last_action=no_ready_task_idle_training_active" in dispatcher["current"]
    assert "TOD-BLOCKER-CLEARING-DRILL-004" in dispatcher["current"]
    idle = next(row for row in payload["metrics"] if row["metric"] == "Idle Training State")
    assert "current=TOD-BLOCKER-CLEARING-DRILL-003" in idle["current"]
    assert "next=TOD-BLOCKER-CLEARING-DRILL-004" in idle["current"]


def test_completed_blocker_drill_suppresses_stale_next_drill(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    (training_root / "blocked_objective_training").mkdir(parents=True)
    context_root.mkdir(parents=True)
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")

    write_json(training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json", {"metrics": []})
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    write_json(
        training_root / "blocked_objective_training" / "TOD_BLOCKER_RESOLUTION_DRILL_004.latest.json",
        {
            "drill_id": "TOD-BLOCKER-CLEARING-DRILL-004",
            "status": "completed_with_evidence",
        },
    )
    stale_blocker = {
        "next_drill": "TOD-BLOCKER-CLEARING-DRILL-004: repair one linked-task empty-evidence blocker end-to-end",
    }
    write_json(
        context_root / "MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
        {"status": "idle", "idle_training": {"blocked_objective_training": stale_blocker}},
    )
    write_json(
        context_root / "TOD_IDLE_TRAINING_STATUS.latest.json",
        {"state": "completed", "blocked_objective_training": stale_blocker},
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    dispatcher = next(row for row in payload["metrics"] if row["metric"] == "Dispatcher State")
    idle = next(row for row in payload["metrics"] if row["metric"] == "Idle Training State")
    assert "TOD-BLOCKER-CLEARING-DRILL-004" not in dispatcher["current"]
    assert "TOD-BLOCKER-CLEARING-DRILL-004" not in idle["current"]


def test_open_mim_tod_dialog_debt_marks_real_movement_action_required(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    dialog_path = root / "shared_state" / "dialog" / "MIM_TOD_DIALOG.sessions.latest.json"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", dialog_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {
                "artifact_metrics": {
                    "validated_edits": {"value": 38},
                    "meaningful_tod_implementations": {"value": 22},
                    "independent_tod_resolutions": {"value": 10},
                }
            },
        },
    )
    write_json(
        dialog_path,
        {
            "sessions": [
                {
                    "session_id": "old-dialog",
                    "status": "timed_out",
                    "timed_out": False,
                    "updated_at": "2026-06-14T12:00:00Z",
                    "open_reply": {"from": "TOD", "to": "MIM", "summary": "old reply still unresolved"},
                },
                {
                    "session_id": "mim-tod-tsk3221-repeated-consumed-anchor",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T13:42:17Z",
                    "open_reply": {"from": "MIM", "to": "TOD", "summary": "MIM to TOD: repeated consumed anchor."},
                    "last_message": {"task_id": "TSK-3221"},
                },
                {
                    "session_id": "closed-dialog",
                    "status": "closed",
                    "updated_at": "2026-06-14T13:43:00Z",
                    "open_reply": None,
                },
            ]
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Open MIM/TOD Dialog Debt")
    assert metric["current"].startswith("2 open replies; timed_out=1;")
    assert "older_than_24h=" in metric["current"]
    assert "oldest_age_h=" in metric["current"]
    assert "routes=MIM->TOD:1, TOD->MIM:1" in metric["current"]
    assert "oldest=old-dialog" in metric["current"]
    assert "newest=mim-tod-tsk3221-repeated-consumed-anchor" in metric["current"]
    assert metric["source"] == "MIM_TOD_DIALOG.sessions.latest.json"
    assert payload["status"] == "action_required"
    assert "open MIM/TOD dialog debt" in payload["overall_readout"]
    assert "MIM operator impact" not in payload["overall_readout"]
    assert "stale artifact count" not in payload["overall_readout"]


def test_open_mim_tod_dialog_debt_uses_session_state_over_stale_index(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    dialog_dir = root / "shared_state" / "dialog"
    dialog_path = dialog_dir / "MIM_TOD_DIALOG.sessions.latest.json"
    stale_session_path = dialog_dir / "MIM_TOD_DIALOG.session-superseded-open.jsonl"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", dialog_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    write_json(
        dialog_path,
        {
            "sessions": [
                {
                    "session_id": "superseded-open",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T13:51:36Z",
                    "session_path": str(stale_session_path),
                    "open_reply": {"from": "CODEX", "to": "MIM", "summary": "stale aggregate entry"},
                },
                {
                    "session_id": "real-open",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T13:59:50Z",
                    "open_reply": {"from": "TOD", "to": "MIM", "summary": "real unresolved entry"},
                },
            ]
        },
    )
    write_json(
        dialog_dir / "MIM_TOD_DIALOG.session-superseded-open.latest.json",
        {
            "session_id": "superseded-open",
            "status": "closed",
            "updated_at": "2026-06-14T14:03:33Z",
            "open_reply": None,
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Open MIM/TOD Dialog Debt")
    assert metric["current"].startswith("1 open replies;")
    assert "routes=TOD->MIM:1" in metric["current"]
    assert "CODEX->MIM" not in metric["current"]
    assert "oldest=real-open" in metric["current"]
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Open Dialog Debt Next Action")
    assert next_action["current"].startswith("Close, owner-label, or evidence-age the oldest open dialog")
    assert "oldest=real-open" in next_action["current"]
    assert next_action["target"] == "oldest open reply is closed, owner-labeled, or evidence-aged before new training work"
    assert next_action["source"] == "MIM_TOD_DIALOG.sessions.latest.json"


def test_open_dialog_debt_treats_evidence_request_payload_as_governed(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    dialog_dir = root / "shared_state" / "dialog"
    dialog_path = dialog_dir / "MIM_TOD_DIALOG.sessions.latest.json"
    session_path = dialog_dir / "MIM_TOD_DIALOG.session-owned-packet-nudge.jsonl"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", dialog_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    session_path.parent.mkdir(parents=True, exist_ok=True)
    session_path.write_text(
        json.dumps(
            {
                "session_id": "owned-packet-nudge",
                "turn_id": 1,
                "timestamp": "2026-06-15T22:57:16Z",
                "from": "MIM",
                "to": "TOD",
                "message_type": "handoff_request",
                "summary": "TOD must own the next autonomy move.",
                "payload": {
                    "owner": "TOD",
                    "evidence_request": "Reply with selector_ready or no_viable_candidate evidence.",
                    "aging_rule": "Reply in the current training cycle.",
                    "dave_needed": "no",
                },
                "requires_reply": True,
            }
        )
        + "\n",
        encoding="utf-8",
    )
    write_json(
        dialog_path,
        {
            "sessions": [
                {
                    "session_id": "owned-packet-nudge",
                    "status": "awaiting_reply",
                    "timed_out": False,
                    "updated_at": "2026-06-15T22:57:16Z",
                    "session_path": str(session_path),
                    "open_reply": {
                        "from": "MIM",
                        "to": "TOD",
                        "summary": "TOD must own the next autonomy move.",
                        "timestamp": "2026-06-15T22:57:16Z",
                    },
                }
            ]
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Open MIM/TOD Dialog Debt")
    assert metric["current"].startswith("0 unmanaged open replies; 1 governed open replies;")
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Open Dialog Debt Next Action")
    assert next_action["current"].startswith("Governed open replies are acceptable")


def test_open_dialog_debt_treats_required_outputs_payload_as_governed(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    dialog_dir = root / "shared_state" / "dialog"
    dialog_path = dialog_dir / "MIM_TOD_DIALOG.sessions.latest.json"
    session_path = dialog_dir / "MIM_TOD_DIALOG.session-current-code-old-new.jsonl"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", dialog_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    session_path.parent.mkdir(parents=True, exist_ok=True)
    session_path.write_text(
        json.dumps(
            {
                "session_id": "current-code-old-new",
                "turn_id": 1,
                "timestamp": "2026-06-16T15:23:35Z",
                "from": "MIM",
                "to": "TOD",
                "message_type": "handoff_request",
                "summary": "TOD must inspect Studio current code and publish one exact old/new packet.",
                "payload": {
                    "owner": "TOD",
                    "evidence_to_publish": "runtime_remote_training/tod_independent_resolution_attempts/TOD_CURRENT_CODE_OLD_NEW_SYNTHESIS_DRILL.latest.json",
                    "required_outputs": {
                        "target_file": "tmp_remote_mim/core/routers/studio.py",
                        "old_text": "exact current text",
                        "new_text": "different replacement text",
                    },
                    "acceptance": [
                        "TOD inspects tmp_remote_mim/core/routers/studio.py directly.",
                        "No Codex patch supply.",
                    ],
                    "aging_rule": "30 minutes from request timestamp.",
                    "dave_needed": "no",
                },
                "requires_reply": True,
            }
        )
        + "\n",
        encoding="utf-8",
    )
    write_json(
        dialog_path,
        {
            "sessions": [
                {
                    "session_id": "current-code-old-new",
                    "status": "awaiting_reply",
                    "timed_out": False,
                    "updated_at": "2026-06-16T15:23:35Z",
                    "session_path": str(session_path),
                    "open_reply": {
                        "from": "MIM",
                        "to": "TOD",
                        "summary": "TOD must inspect Studio current code and publish one exact old/new packet.",
                        "timestamp": "2026-06-16T15:23:35Z",
                    },
                }
            ]
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Open MIM/TOD Dialog Debt")
    assert metric["current"].startswith("0 unmanaged open replies; 1 governed open replies;")
    assert "governed_aging_rule=30m" in metric["current"]
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Open Dialog Debt Next Action")
    assert next_action["current"].startswith("Governed open replies are acceptable")


def test_active_owner_request_state_uses_only_open_codex_requests(tmp_path, monkeypatch):
    module = load_module()
    root = tmp_path
    training_root = root / "runtime_remote_training"
    context_root = root / "tod" / "out" / "context-sync"
    dialog_dir = root / "shared_state" / "dialog"
    dialog_path = dialog_dir / "MIM_TOD_DIALOG.sessions.latest.json"
    closed_session_path = dialog_dir / "MIM_TOD_DIALOG.session-closed-codex.jsonl"
    monkeypatch.setattr(module, "ROOT", root)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", root / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", dialog_path)

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    write_json(
        dialog_path,
        {
            "sessions": [
                {
                    "session_id": "closed-codex",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T13:50:00Z",
                    "session_path": str(closed_session_path),
                    "open_reply": {"from": "CODEX", "to": "MIM"},
                },
                {
                    "session_id": "active-codex",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T14:16:39Z",
                    "open_reply": {"from": "CODEX", "to": "TOD"},
                    "last_message": {"task_id": "TSK-3221"},
                },
                {
                    "session_id": "active-non-codex",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T14:17:39Z",
                    "open_reply": {"from": "TOD", "to": "MIM"},
                },
            ]
        },
    )
    write_json(
        dialog_dir / "MIM_TOD_DIALOG.session-closed-codex.latest.json",
        {
            "session_id": "closed-codex",
            "status": "closed",
            "open_reply": None,
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Active Owner Request State")
    assert metric["current"].startswith("1 active Codex owner request(s):")
    assert "CODEX->TOD active-codex" in metric["current"]
    assert "task=TSK-3221" in metric["current"]
    assert "closed-codex" not in metric["current"]
    assert "active-non-codex" not in metric["current"]


def test_dialog_debt_age_uses_open_reply_timestamp_not_reminder_update(tmp_path, monkeypatch):
    module = load_module()

    class FixedDatetime(real_datetime):
        @classmethod
        def now(cls, tz=None):
            value = real_datetime(2026, 6, 14, 15, 0, 0, tzinfo=timezone.utc)
            if tz is None:
                return value.replace(tzinfo=None)
            return value.astimezone(tz)

    monkeypatch.setattr(module, "datetime", FixedDatetime)
    dialog_dir = tmp_path / "shared_state" / "dialog"
    dialog_path = dialog_dir / "MIM_TOD_DIALOG.sessions.latest.json"
    write_json(
        dialog_path,
        {
            "sessions": [
                {
                    "session_id": "open-reminded",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-14T14:59:00Z",
                    "open_reply": {
                        "from": "CODEX",
                        "to": "MIM",
                        "timestamp": "2026-06-13T15:00:00Z",
                    },
                    "last_message": {
                        "from": "CODEX",
                        "to": "MIM",
                        "task_id": "REMINDER-DID-NOT-RESET-AGE",
                        "timestamp": "2026-06-14T14:59:00Z",
                    },
                }
            ]
        },
    )

    debt = module._open_dialog_debt_current(dialog_path)
    active = module._active_owner_requests_current(dialog_path)

    assert "oldest=open-reminded" in debt
    assert "oldest_age_h=24.0" in debt
    assert "age_h=24.0" in active
    assert "REMINDER-DID-NOT-RESET-AGE" in active


def test_tod_active_request_alignment_flags_execution_mismatch():
    module = load_module()

    current = module._tod_active_request_alignment_current(
        {
            "request_id": "fresh-request-1",
            "request_status": "published",
            "target": "TOD",
        },
        {
            "task_id": "older-practice-task",
            "status": "completed",
            "summary": "TOD completed a practice artifact instead.",
        },
    )

    assert current.startswith("mismatch;")
    assert "pending_request=fresh-request-1" in current
    assert "latest_execution=older-practice-task" in current
    assert "TOD completed a practice artifact" in current


def test_tod_active_request_alignment_treats_older_execution_as_pending():
    module = load_module()

    current = module._tod_active_request_alignment_current(
        {
            "generated_at": "2026-06-15T07:00:00Z",
            "request_id": "fresh-request-1",
            "request_status": "published",
            "target": "TOD",
        },
        {
            "generated_at": "2026-06-15T06:59:00Z",
            "task_id": "older-practice-task",
            "status": "completed",
            "summary": "TOD completed an earlier task before this request existed.",
        },
    )

    assert current.startswith("pending TOD request fresh-request-1;")
    assert "latest_execution=older-practice-task" in current
    assert "latest_execution_status=completed" in current
    assert "older than current request" in current


def test_real_movement_prefers_newer_runtime_tod_task_request(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "runtime_remote_training"
    context_root = tmp_path / "tod" / "out" / "context-sync"
    runtime_request = tmp_path / "runtime" / "shared" / "MIM_TOD_TASK_REQUEST.latest.json"
    runtime_result = tmp_path / "runtime" / "shared" / "TOD_EXECUTION_RESULT.latest.json"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "TOD_TASK_REQUEST_PATH", context_root / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json")
    monkeypatch.setattr(module, "RUNTIME_TOD_TASK_REQUEST_PATH", runtime_request)
    monkeypatch.setattr(module, "TOD_EXECUTION_RESULT_PATH", runtime_result)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", tmp_path / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", tmp_path / "shared_state" / "dialog" / "MIM_TOD_DIALOG.sessions.latest.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    write_json(
        module.TOD_TASK_REQUEST_PATH,
        {
            "generated_at": "2026-06-14T16:23:10Z",
            "request_id": "stale-ssh-request",
            "target": "TOD",
        },
    )
    write_json(
        runtime_request,
        {
            "generated_at": "2026-06-14T16:27:35Z",
            "request_id": "fresh-runtime-request",
            "task_id": "fresh-runtime-task",
            "target": "TOD",
        },
    )
    write_json(
        runtime_result,
        {
            "generated_at": "2026-06-14T16:29:52Z",
            "task_id": "fresh-runtime-task",
            "status": "blocked",
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    alignment = next(metric for metric in payload["metrics"] if metric["metric"] == "TOD Active Request Alignment")
    assert alignment["current"] == "aligned; request=fresh-runtime-request; task=fresh-runtime-task; execution_status=blocked"
    assert alignment["source"] == "MIM_TOD_TASK_REQUEST.latest.json + TOD_EXECUTION_RESULT.latest.json"


def test_real_movement_uses_reflection_pull_result_for_current_bridge_request(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "runtime_remote_training"
    context_root = tmp_path / "tod" / "out" / "context-sync"
    runtime_request = tmp_path / "runtime" / "shared" / "MIM_TOD_TASK_REQUEST.latest.json"
    stale_local_result = tmp_path / "runtime" / "shared" / "TOD_EXECUTION_RESULT.latest.json"
    reflection_result = tmp_path / "runtime" / "logs" / "mim_tod_reflection_pull" / "TOD_MIM_TASK_RESULT.latest.json"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "TOD_TASK_REQUEST_PATH", context_root / "ssh-shared" / "MIM_TOD_TASK_REQUEST.latest.json")
    monkeypatch.setattr(module, "RUNTIME_TOD_TASK_REQUEST_PATH", runtime_request)
    monkeypatch.setattr(module, "TOD_EXECUTION_RESULT_PATH", stale_local_result)
    monkeypatch.setattr(module, "TOD_LISTENER_RESULT_PATH", context_root / "listener" / "TOD_MIM_TASK_RESULT.latest.json")
    monkeypatch.setattr(module, "TOD_REFLECTION_PULL_RESULT_PATH", reflection_result)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", training_root / "tod_independent_resolution_attempts")
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", tmp_path / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", tmp_path / "shared_state" / "dialog" / "MIM_TOD_DIALOG.sessions.latest.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    write_json(
        runtime_request,
        {
            "generated_at": "2026-06-15T06:42:56Z",
            "request_id": "bridge-request-1",
            "task_id": "bridge-task-1",
            "target": "TOD",
        },
    )
    write_json(
        stale_local_result,
        {
            "generated_at": "2026-06-15T06:43:00Z",
            "task_id": "unrelated-local-task",
            "status": "completed",
        },
    )
    write_json(
        reflection_result,
        {
            "generated_at": "2026-06-15T06:44:16Z",
            "request_id": "bridge-request-1",
            "task_id": "bridge-task-1",
            "result_status": "blocked_with_inspection",
            "summary": "Bounded executor inspected the implementation replan and returned blocked_with_inspection evidence.",
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    alignment = next(metric for metric in payload["metrics"] if metric["metric"] == "TOD Active Request Alignment")
    assert alignment["current"] == "aligned; request=bridge-request-1; task=bridge-task-1; execution_status=blocked_with_inspection"
    assert alignment["source"] == "MIM_TOD_TASK_REQUEST.latest.json + TOD_MIM_TASK_RESULT.latest.json"


def test_precise_blocker_required_next_action_is_preserved(tmp_path, monkeypatch):
    module = load_module()
    training_root = tmp_path / "runtime_remote_training"
    context_root = tmp_path / "tod" / "out" / "context-sync"
    attempts_root = training_root / "tod_independent_resolution_attempts"
    monkeypatch.setattr(module, "ROOT", tmp_path)
    monkeypatch.setattr(module, "TRAINING_ROOT", training_root)
    monkeypatch.setattr(module, "CONTEXT_SYNC_ROOT", context_root)
    monkeypatch.setattr(module, "INDEPENDENT_ATTEMPTS_ROOT", attempts_root)
    monkeypatch.setattr(module, "PATCH_SYNTHESIS_PRACTICE_PATH", training_root / "TOD_CORRECTED_PATCH_SYNTHESIS_PRACTICE_V1.latest.json")
    monkeypatch.setattr(module, "TOD_STATE_PATH", tmp_path / "tod" / "data" / "state.json")
    monkeypatch.setattr(module, "DIALOG_SESSIONS_PATH", tmp_path / "shared_state" / "dialog" / "MIM_TOD_DIALOG.sessions.latest.json")

    write_json(
        training_root / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
        {
            "metrics": [
                {"metric": "Operator Impact", "current": "10.0/10 from 10 live replies"},
                {"metric": "Dave Needed Clarity", "current": "100% / 10 of 10"},
            ]
        },
    )
    write_json(
        training_root / "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
        {
            "outcome_reflection": {"stale_artifact_count": 0},
            "tod_score": {"artifact_metrics": {}},
        },
    )
    write_json(
        attempts_root / "TOD_EXACT_PATCH_SYNTHESIS_DRILL_2026_06_14.latest.json",
        {
            "generated_at": "2026-06-14T14:30:55Z",
            "status": "blocked_with_precise_reason",
            "task_id": "TSK-EXACT-PATCH-SYNTHESIS-DRILL-20260614",
            "blocker": {
                "reason_code": "current_code_old_text_missing",
                "required_next_action": "TOD should inspect the current target file and synthesize one fresh bounded replace_text candidate, or choose a different behavior gap.",
            },
        },
    )

    module.main()

    payload = json.loads((training_root / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json").read_text(encoding="utf-8"))
    metric = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Candidate State")
    assert "blocked_with_precise_reason" in metric["current"]
    next_action = next(row for row in payload["metrics"] if row["metric"] == "Independent Resolution Next Action")
    assert "fresh bounded replace_text candidate" in next_action["current"]


def test_stale_no_viable_selector_is_not_reported_as_active():
    module = load_module()

    current, source, next_action = module._no_viable_candidate_inspection_current(
        {
            "generated_at": "2026-06-15T17:57:26Z",
            "selection_kind": "blocked_no_viable_behavior_candidate",
            "blocked_reason": "No viable fresh behavior-changing candidate is currently proven.",
            "inspected_files": ["tmp_remote_mim/core/routers/gateway.py"],
            "blocker": {
                "required_next_action": "Inspect another target.",
            },
        },
        {
            "generated_at": "2026-06-15T23:50:48Z",
            "status": "blocked",
            "reason_code": "blocked_missing_bounded_edit_mode",
        },
    )

    assert current.startswith("stale; selector older than latest TOD execution")
    assert "blocked_missing_bounded_edit_mode" in current
    assert source == "TOD_NEXT_TASK_SELECTION.latest.json + TOD_EXECUTION_RESULT.latest.json"
    assert "Rerun TOD selector for the current execution blocker" in next_action


def test_blocked_selector_active_task_is_not_reported_as_material_execution(tmp_path, monkeypatch):
    module = load_module()
    monkeypatch.setattr(module, "ROOT", tmp_path)

    write_json(
        tmp_path / "runtime" / "shared" / "TOD_NEXT_TASK_SELECTION.latest.json",
        {
            "request_id": "tod-next-task-selection-none-20260616070044376",
            "selection_kind": "blocked_current_blocker_packet_target_required",
            "dispatch_status": "blocked_with_reason",
            "blocked_reason": "The current blocker requires TOD to synthesize exact old_text/new_text for tmp_remote_mim/core/routers/studio.py.",
        },
    )

    current = module._tod_material_execution_current(
        {
            "task_id": "tod-next-task-selection-none-20260616070044376",
            "status": "active",
        },
        {},
    )

    assert current.startswith("selector_blocked_no_material_dispatch")
    assert "blocked_current_blocker_packet_target_required" in current
    assert "no implementation credit" in current
    assert "status=active" not in current


def test_governed_dialog_debt_exposes_short_aging_window(tmp_path, monkeypatch):
    module = load_module()

    class FixedDatetime(real_datetime):
        @classmethod
        def now(cls, tz=None):
            value = real_datetime(2026, 6, 16, 0, 13, 54, tzinfo=timezone.utc)
            return value if tz else value.replace(tzinfo=None)

    monkeypatch.setattr(module, "datetime", FixedDatetime)
    session_path = tmp_path / "MIM_TOD_DIALOG.session-short-aging.jsonl"
    session_path.write_text(
        json.dumps(
            {
                "session_id": "short-aging",
                "turn_id": 1,
                "timestamp": "2026-06-16T00:03:54Z",
                "from": "MIM",
                "to": "TOD",
                "message_type": "handoff_request",
                "summary": "TOD must refresh selector evidence.",
                "payload": {
                    "evidence_request": "Reply with selector_ready or no_viable_candidate evidence.",
                    "aging_rule": "Reply within 30 minutes.",
                    "dave_needed": "no",
                },
                "requires_reply": True,
            }
        )
        + "\n",
        encoding="utf-8",
    )
    sessions_path = tmp_path / "MIM_TOD_DIALOG.sessions.latest.json"
    write_json(
        sessions_path,
        {
            "sessions": [
                {
                    "session_id": "short-aging",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-16T00:03:54Z",
                    "session_path": str(session_path),
                    "open_reply": {
                        "from": "MIM",
                        "to": "TOD",
                        "timestamp": "2026-06-16T00:03:54Z",
                    },
                }
            ]
        },
    )

    current = module._open_dialog_debt_current(sessions_path)

    assert current.startswith("0 unmanaged open replies; 1 governed open replies;")
    assert "governed_aging_rule=30m" in current
    assert "governed_oldest_age_m=10.0" in current
    assert "Dave needed=no" in current


def test_bounded_edit_materialization_nudge_counts_as_governed_dialog_debt(tmp_path, monkeypatch):
    module = load_module()

    class FixedDatetime(real_datetime):
        @classmethod
        def now(cls, tz=None):
            value = real_datetime(2026, 6, 16, 2, 14, 3, tzinfo=timezone.utc)
            return value if tz else value.replace(tzinfo=None)

    monkeypatch.setattr(module, "datetime", FixedDatetime)
    session_path = tmp_path / "MIM_TOD_DIALOG.session-materialization.jsonl"
    session_path.write_text(
        json.dumps(
            {
                "session_id": "materialization",
                "turn_id": 1,
                "timestamp": "2026-06-16T02:04:03Z",
                "from": "MIM",
                "to": "TOD",
                "message_type": "status_request",
                "summary": "TOD must publish a bounded current-code edit packet.",
                "payload": {
                    "required_tod_action": "Inspect the current target file and publish a bounded edit packet.",
                    "required_fields": [
                        "target_file",
                        "old_text_or_anchor",
                        "new_text_or_snippet",
                        "validation_command",
                        "prevention_lesson",
                    ],
                    "acceptable_result": "TOD-authored bounded edit packet with validation evidence.",
                    "no_credit_if": ["wrapper-only completion", "validation-only downgrade"],
                    "aging_rule": "If no bounded edit packet appears within 30 minutes, keep blocked.",
                    "dave_needed": "no",
                },
                "requires_reply": True,
            }
        )
        + "\n",
        encoding="utf-8",
    )
    sessions_path = tmp_path / "MIM_TOD_DIALOG.sessions.latest.json"
    write_json(
        sessions_path,
        {
            "sessions": [
                {
                    "session_id": "materialization",
                    "status": "awaiting_reply",
                    "updated_at": "2026-06-16T02:04:03Z",
                    "session_path": str(session_path),
                    "open_reply": {
                        "from": "MIM",
                        "to": "TOD",
                        "timestamp": "2026-06-16T02:04:03Z",
                    },
                }
            ]
        },
    )

    current = module._open_dialog_debt_current(sessions_path)

    assert current.startswith("0 unmanaged open replies; 1 governed open replies;")
    assert "governed_aging_rule=30m" in current
    assert "governed_oldest_age_m=10.0" in current
    assert "Dave needed=no" in current


def test_materialization_timeout_state_records_no_credit_without_repeat_nudge(tmp_path):
    module = load_module()
    root = tmp_path / "codex_training_interventions"
    root.mkdir()
    write_json(
        root / "CODEX_TOD_BOUNDED_EDIT_MATERIALIZATION_TIMEOUT_20260616T023838Z.latest.json",
        {
            "generated_at": "2026-06-16T02:38:43Z",
            "status": "timed_out_no_credit",
            "payload": {
                "outcome": "timed_out_no_credit",
                "credit": "none",
                "blocker": "blocked_missing_bounded_edit_mode",
                "observed_response": "No TOD reply before 30-minute governed window expired.",
            },
        },
    )

    current, source, next_action = module._tod_materialization_timeout_current(root)

    assert current.startswith("timed_out_no_credit; count=1;")
    assert "credit=none" in current
    assert "blocked_missing_bounded_edit_mode" in current
    assert source == "CODEX_TOD_BOUNDED_EDIT_MATERIALIZATION_TIMEOUT_20260616T023838Z.latest.json"
    assert "Do not repeat the same materialization nudge" in next_action


def test_current_code_packet_capability_rejects_pre_timeout_packet_evidence(tmp_path):
    module = load_module()
    attempts_root = tmp_path / "tod_independent_resolution_attempts"
    interventions_root = tmp_path / "codex_training_interventions"
    attempts_root.mkdir()
    interventions_root.mkdir()
    write_json(
        interventions_root / "CODEX_TOD_BOUNDED_EDIT_MATERIALIZATION_TIMEOUT_20260616T023838Z.latest.json",
        {
            "generated_at": "2026-06-16T02:38:43Z",
            "status": "timed_out_no_credit",
            "payload": {"outcome": "timed_out_no_credit"},
        },
    )
    write_json(
        attempts_root / "TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json",
        {
            "generated_at": "2026-06-15T17:55:25Z",
            "status": "blocked_candidate_already_applied",
            "task_id": "TSK-3248",
            "packet_candidate_ready": False,
            "blocker": {
                "target_file": "tmp_remote_mim/core/routers/gateway.py",
                "inspected_files": ["tmp_remote_mim/core/routers/gateway.py"],
                "required_next_action": "Choose a different current-code behavior gap.",
            },
        },
    )

    current, source, next_action = module._tod_current_code_packet_capability_current(attempts_root, interventions_root)

    assert current.startswith("no post-timeout packet capability evidence")
    assert "latest packet predates materialization timeout" in current
    assert source == "TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json"
    assert "publish a post-timeout packet" in next_action


def test_current_code_packet_capability_accepts_post_timeout_actionable_packet(tmp_path):
    module = load_module()
    attempts_root = tmp_path / "tod_independent_resolution_attempts"
    interventions_root = tmp_path / "codex_training_interventions"
    attempts_root.mkdir()
    interventions_root.mkdir()
    write_json(
        interventions_root / "CODEX_TOD_BOUNDED_EDIT_MATERIALIZATION_TIMEOUT_20260616T023838Z.latest.json",
        {
            "generated_at": "2026-06-16T02:38:43Z",
            "status": "timed_out_no_credit",
            "payload": {"outcome": "timed_out_no_credit"},
        },
    )
    write_json(
        attempts_root / "TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json",
        {
            "generated_at": "2026-06-16T02:45:00Z",
            "status": "packet_candidate_ready",
            "task_id": "TSK-PACKET",
            "packet_candidate_ready": True,
            "target_file": "tmp_remote_mim/core/routers/gateway.py",
            "intended_edit_mode": "replace_text",
            "old_text": "old gateway line",
            "new_text": "new gateway line",
            "validation_command": "python -m py_compile .\\core\\routers\\gateway.py",
            "prevention_lesson": "Inspect current code before packet dispatch.",
            "dave_needed": "no",
        },
    )

    current, source, next_action = module._tod_current_code_packet_capability_current(attempts_root, interventions_root)

    assert current.startswith("post_timeout_packet_candidate_ready")
    assert "target=tmp_remote_mim/core/routers/gateway.py" in current
    assert "no independent-resolution credit until executed" in current
    assert source == "TOD_PACKET_FORMATION_INDEPENDENT_RECOVERY.latest.json"
    assert "Dispatch the packet-derived code task" in next_action


def test_mim_replan_churn_flags_same_objective_pending_replan_after_no_viable_selector():
    module = load_module()

    current, next_action = module._mim_replan_churn_current(
        {
            "generated_at": "2026-06-16T03:31:31Z",
            "request_id": "objective-a-mim-request-new-replan-1",
            "task_id": "objective-a-mim-request-new-replan-1",
            "objective_id": "objective-a",
            "status": "pending",
        },
        {
            "generated_at": "2026-06-16T03:30:12Z",
            "task_id": "objective-a-mim-request-old-replan-1",
            "objective_id": "objective-a",
            "status": "blocked",
            "reason_code": "blocked_missing_bounded_edit_mode",
        },
        {
            "generated_at": "2026-06-16T03:23:20Z",
            "source_objective": "objective-a",
            "selection_kind": "blocked_no_viable_behavior_candidate",
            "dispatch_status": "blocked_with_reason",
        },
    )

    assert current.startswith("active_replan_churn_no_credit")
    assert "pending=objective-a-mim-request-new-replan-1" in current
    assert "stop issuing same-objective replans" in next_action


def test_mim_replan_churn_flags_pending_replan_waiting_on_stale_no_viable_selector():
    module = load_module()

    current, next_action = module._mim_replan_churn_current(
        {
            "generated_at": "2026-06-16T03:54:50Z",
            "request_id": "objective-a-mim-request-newer-replan-1",
            "task_id": "objective-a-mim-request-newer-replan-1",
            "objective_id": "objective-a",
            "status": "pending",
        },
        {
            "generated_at": "2026-06-16T03:51:12Z",
            "task_id": "objective-a-mim-request-older-replan-1",
            "objective_id": "objective-a",
            "status": "succeeded",
            "result_status": "succeeded",
            "result_reason_code": "execution_completed",
        },
        {
            "generated_at": "2026-06-16T03:23:20Z",
            "selection_kind": "blocked_no_viable_behavior_candidate",
            "dispatch_status": "blocked_with_reason",
        },
    )

    assert current.startswith("pending_replan_waiting_on_fresh_selector")
    assert "pending=objective-a-mim-request-newer-replan-1" in current
    assert "fresh inspected no-viable blocker" in next_action
    assert "do not count this as independent progress" in next_action


def test_material_execution_marks_wrapper_only_blocker_not_active_progress():
    module = load_module()

    current = module._tod_material_execution_current(
        {
            "status": "active",
            "task_id": "TSK-0001",
        },
        {
            "status": "blocked",
            "task_id": "TSK-0001",
            "reason_code": "codex_wrapper_only_no_execution",
            "summary": "Codex wrapper only accepted the packaged prompt without executing it.",
        },
    )

    assert current.startswith("active_but_latest_execution_blocked")
    assert "reason=codex_wrapper_only_no_execution" in current
    assert "task=TSK-0001" in current


def test_selector_field_completeness_rejects_partial_selector():
    module = load_module()
    payload = {
        "selection_kind": "maintenance_training",
        "selected_task_id": "TSK-0001",
    }
    missing_fields = module._selector_missing_bounded_fields(payload)

    current, next_action = module._selector_field_completeness_current(payload, missing_fields)

    assert current.startswith("incomplete; selected=TSK-0001; selection=maintenance_training")
    assert "target_file" in current
    assert "prevention_lesson" in current
    assert "no dispatch credit" in current
    assert "before execution or credit" in next_action


def test_selector_field_completeness_accepts_packet_task_focus_directives():
    module = load_module()
    payload = {
        "selection_kind": "packet_candidate_code_task",
        "task_id": "TSK-3270",
        "task_focus": "\n".join(
            [
                "Target File: tmp_remote_mim/core/routers/studio.py",
                "Edit Mode: replace_text",
                "Old Text:",
                "I recommend working on MIM conversation mode selection next.",
                "New Text:",
                "I recommend working on TOD self-authored bounded edit materialization next.",
                "Validation Command: python -c \"print('ok')\"",
                "Prevention Lesson: TOD must inspect current code before publishing a packet.",
            ]
        ),
    }

    missing_fields = module._selector_missing_bounded_fields(payload)
    current, next_action = module._selector_field_completeness_current(payload, missing_fields)

    assert missing_fields == []
    assert current == "complete; selected=TSK-3270; selection=packet_candidate_code_task; bounded_fields=8/8"
    assert "Dispatch only after material execution validates" in next_action


def test_tod_material_execution_prefers_matching_completed_execution_result():
    module = load_module()

    current = module._tod_material_execution_current(
        {
            "status": "active",
            "task_id": "TSK-3270",
        },
        {
            "status": "completed",
            "task_id": "TSK-3270",
            "summary": "LocalExecutionEngine completed the bounded local fallback.",
            "files_changed": ["tmp_remote_mim/core/routers/studio.py"],
            "validation_results": [
                {"name": "focused_validation_exit_zero", "passed": True},
            ],
        },
    )

    assert current.startswith("completed_material_execution")
    assert "task=TSK-3270" in current
    assert "changed_files=1" in current
    assert "validation=passed" in current
