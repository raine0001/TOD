"""Generate a MIM/TOD training initiative gate from the latest scoreboard.

The gate turns passive training findings into an explicit recovery ladder:
MIM/TOD peer repair first, Codex next when local repair stalls or the drop is
severe, Dave only when all machine lanes are blocked or a human decision is
actually required.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> dict[str, Any]:
    for encoding in ("utf-8", "utf-8-sig", "utf-16"):
        try:
            return json.loads(path.read_text(encoding=encoding))
        except Exception:
            continue
    return {}


def metric(scoreboard: dict[str, Any], name: str) -> float | None:
    value = (((scoreboard.get("mim_score") or {}).get("metrics") or {}).get(name) or {}).get("today")
    return float(value) if isinstance(value, (int, float)) else None


def write_markdown(packet: dict[str, Any], path: Path) -> None:
    lines = [
        "# MIM/TOD Training Initiative Gate",
        "",
        f"Generated: {packet['generated_at']}",
        f"Status: {packet['status']}",
        f"Escalation target: {packet['escalation']['current_target']}",
        f"Dave needed: {packet['escalation']['dave_needed']}",
        "",
        "## Trigger Reasons",
        "",
    ]
    for reason in packet["trigger_reasons"] or ["none"]:
        lines.append(f"- {reason}")
    lines.extend(["", "## Recovery Ladder", ""])
    for step in packet["recovery_ladder"]:
        lines.append(f"- {step['order']}. {step['owner']}: {step['action']} ({step['status']})")
    lines.extend(["", "## Auto Initiative", ""])
    initiative = packet["auto_initiative"]
    lines.append(f"- Objective: {initiative['objective_id']}")
    lines.append(f"- Owner: {initiative['owner']}")
    lines.append(f"- Action: {initiative['action']}")
    lines.append(f"- Acceptance: {initiative['acceptance']}")
    lines.extend(["", "## TOD Codex Training", ""])
    codex = packet["tod_codex_training"]
    lines.append(f"- Status: {codex.get('status', 'unknown')}")
    lines.append(f"- Topic: {codex.get('current_topic', 'unknown')}")
    lines.append(f"- Goal: {codex.get('goal', 'unknown')}")
    lines.extend(["", "## Next Check", "", f"- {packet['next_check']}"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_gate(out_dir: Path) -> dict[str, Any]:
    scoreboard = load_json(out_dir / "MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    reflection = scoreboard.get("outcome_reflection") if isinstance(scoreboard.get("outcome_reflection"), dict) else {}
    judgment = scoreboard.get("judgment_mode_score") if isinstance(scoreboard.get("judgment_mode_score"), dict) else {}
    codex_status = load_json(out_dir / "TOD_CODEX_PROFICIENCY_TRAINING_STATUS.latest.json")

    intent = metric(scoreboard, "intent_understood")
    answered = metric(scoreboard, "answered_question")
    recommendation = metric(scoreboard, "recommendation_quality")
    jargon = metric(scoreboard, "internal_jargon")
    judgment_pass = judgment.get("pass_rate_percent")
    stale_artifacts = reflection.get("stale_artifacts") if isinstance(reflection.get("stale_artifacts"), list) else []
    reflection_assessment = str(reflection.get("assessment") or "").strip()
    improving = reflection.get("are_they_improving")
    truth_integrity = str(reflection.get("truth_integrity") or "").strip().lower()

    trigger_reasons: list[str] = []
    if str(scoreboard.get("status") or "").startswith("needs_attention"):
        trigger_reasons.append("scoreboard_needs_attention")
    if isinstance(intent, float) and intent < 80:
        trigger_reasons.append(f"mim_intent_understood_below_80:{intent:g}")
    if isinstance(answered, float) and answered < 80:
        trigger_reasons.append(f"mim_answered_question_below_80:{answered:g}")
    if isinstance(recommendation, float) and recommendation < 80:
        trigger_reasons.append(f"mim_recommendation_quality_below_80:{recommendation:g}")
    if isinstance(jargon, float) and jargon > 5:
        trigger_reasons.append(f"mim_internal_jargon_above_5:{jargon:g}")
    if isinstance(judgment_pass, (int, float)) and float(judgment_pass) < 80:
        trigger_reasons.append(f"mim_judgment_mode_below_80:{float(judgment_pass):g}")
    if stale_artifacts:
        trigger_reasons.append(f"stale_reflection_artifacts:{len(stale_artifacts)}")
    if reflection_assessment == "needs_attention" or improving is False:
        trigger_reasons.append("reflection_not_improving")
    if truth_integrity and truth_integrity != "healthy":
        trigger_reasons.append(f"truth_integrity_not_healthy:{truth_integrity}")

    human_required = truth_integrity not in {"", "healthy"} or any(
        reason.startswith("missing_operator") or reason.startswith("credentials") for reason in trigger_reasons
    )
    codex_next = bool(trigger_reasons) and (
        any(reason.startswith("mim_judgment_mode_below_80") for reason in trigger_reasons)
        or any(reason.startswith("mim_intent") or reason.startswith("mim_answered") for reason in trigger_reasons)
        or len(stale_artifacts) >= 5
    )

    if not trigger_reasons:
        status = "healthy_monitor_only"
        current_target = "monitor"
    elif human_required:
        status = "operator_help_required"
        current_target = "Dave"
    else:
        status = "peer_recovery_triggered"
        current_target = "MIM_TOD_peer_recovery"

    recovery_ladder = [
        {
            "order": 1,
            "owner": "MIM+TOD",
            "status": "active" if current_target == "MIM_TOD_peer_recovery" else "standby",
            "action": "MIM names the training gap in plain language; TOD refreshes or repairs the evidence lane with validation.",
        },
        {
            "order": 2,
            "owner": "Codex",
            "status": "next_if_peer_recovery_does_not_clear" if codex_next and not human_required else "standby",
            "action": "Implement or debug the failing gate with exact files, commands, failing checks, and acceptance criteria.",
        },
        {
            "order": 3,
            "owner": "Dave",
            "status": "only_if_machine_lanes_blocked" if not human_required else "required",
            "action": "Decide priority, provide credentials/physical-world confirmation, or override safety/product direction.",
        },
    ]

    auto_action = (
        "Refresh stale TOD evidence artifacts and rerun scoreboard/reflection until needs_attention clears."
        if stale_artifacts
        else "Continue monitoring and rerun judgment/scoreboard checks on the next cadence."
    )
    packet = {
        "packet_type": "mim-tod-training-initiative-gate-v1",
        "generated_at": utc_now(),
        "status": status,
        "trigger_reasons": trigger_reasons,
        "thresholds": {
            "mim_intent_understood_min_percent": 80,
            "mim_answered_question_min_percent": 80,
            "mim_recommendation_quality_min_percent": 80,
            "mim_internal_jargon_max_percent": 5,
            "mim_judgment_mode_min_percent": 80,
            "stale_artifacts_peer_recovery_threshold": 1,
            "stale_artifacts_codex_next_threshold": 5,
        },
        "escalation": {
            "current_target": current_target,
            "codex_next_if_unresolved": bool(codex_next and not human_required),
            "dave_needed": bool(human_required),
            "dave_needed_reason": "none" if not human_required else "truth integrity or human-only dependency requires operator decision",
        },
        "recovery_ladder": recovery_ladder,
        "auto_initiative": {
            "objective_id": "MIM-TOD-TRAINING-AUTO-RECOVERY-GATE-V1",
            "owner": "MIM_TOD_peer_recovery",
            "action": auto_action,
            "acceptance": "Next scoreboard has no below-threshold MIM metrics, judgment smoke remains >=80%, and reflection stale artifacts are reduced or converted into owned follow-on actions.",
        },
        "tod_codex_training": {
            "status": codex_status.get("status") or "unknown",
            "current_topic": codex_status.get("current_topic") or "unknown",
            "goal": codex_status.get("goal") or "unknown",
            "objective_id": codex_status.get("objective_id") or "TOD-CODEX-PROFICIENCY-ROADMAP-AUTORUN-V1",
        },
        "source_files": [
            str(out_dir / "MIM_TOD_TRAINING_SCOREBOARD.latest.json"),
            str(out_dir / "TOD_CODEX_PROFICIENCY_TRAINING_STATUS.latest.json"),
        ],
        "next_check": "Run after every scoreboard refresh and publish this gate beside the scoreboard so drops cannot remain passive findings.",
    }
    return packet


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", default=str(TRAINING_ROOT))
    args = parser.parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    packet = build_gate(out_dir)
    json_path = out_dir / "MIM_TOD_TRAINING_INITIATIVE_GATE.latest.json"
    md_path = out_dir / "MIM_TOD_TRAINING_INITIATIVE_GATE.latest.md"
    json_path.write_text(json.dumps(packet, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(packet, md_path)
    print(json_path)
    print(md_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
