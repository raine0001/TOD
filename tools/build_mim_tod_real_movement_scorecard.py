from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TRAINING_ROOT = ROOT / "runtime_remote_training"
CONTEXT_SYNC_ROOT = ROOT / "tod" / "out" / "context-sync"


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _metric_current(metrics: list[dict[str, Any]], metric_name: str) -> str:
    for metric in metrics:
        if metric.get("metric") == metric_name:
            return str(metric.get("current", "unknown"))
    return "unknown"


def _parse_percent(current: str) -> int | None:
    first = str(current).split("/", 1)[0].strip().rstrip("%")
    try:
        return int(float(first))
    except ValueError:
        return None


def _operator_score(current: str) -> float | None:
    first = str(current).split("/", 1)[0].strip()
    try:
        return float(first)
    except ValueError:
        return None


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_md(path: Path, payload: dict[str, Any]) -> None:
    lines = [
        "# MIM TOD Real Movement Training V1",
        "",
        f"Generated: {payload['generated_at']}",
        f"Status: {payload['status']}",
        f"Overall: {payload['overall_readout']}",
        "",
        "## Required Movement Loop",
        "",
    ]
    for item in payload["required_loop"]:
        lines.append(f"- {item}")
    lines.extend(["", "## Metrics", ""])
    for metric in payload["metrics"]:
        lines.append(f"- {metric['metric']}: {metric['current']} ({metric['target']})")
    lines.extend(["", "## Cycle 001", ""])
    for action in payload["cycle_001"]["actions"]:
        lines.append(f"- {action['action']}")
        lines.append(f"  Owner: {action['owner']}")
        lines.append(f"  Evidence: {action['evidence']}")
        lines.append(f"  Aging: {action['aging']}")
        lines.append(f"  Dave needed: {action['dave_needed']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    operator = _load_json(TRAINING_ROOT / "MIM_OPERATOR_IMPACT_SCORECARD.latest.json")
    scoreboard = _load_json(TRAINING_ROOT / "MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    idle = _load_json(CONTEXT_SYNC_ROOT / "TOD_IDLE_TRAINING_STATUS.latest.json")
    dispatcher = _load_json(CONTEXT_SYNC_ROOT / "MIM_READY_TASK_DISPATCHER_STATUS.latest.json")

    operator_metrics = operator.get("metrics") if isinstance(operator.get("metrics"), list) else []
    operator_impact = _operator_score(_metric_current(operator_metrics, "Operator Impact"))
    dave_clarity = _parse_percent(_metric_current(operator_metrics, "Dave Needed Clarity"))

    reflection = scoreboard.get("outcome_reflection") if isinstance(scoreboard.get("outcome_reflection"), dict) else {}
    tod_score = scoreboard.get("tod_score") if isinstance(scoreboard.get("tod_score"), dict) else {}
    artifact_metrics = tod_score.get("artifact_metrics") if isinstance(tod_score.get("artifact_metrics"), dict) else {}

    stale_count = reflection.get("stale_artifact_count", "unknown")
    blocked_count = reflection.get("operator_summary", "")
    validated_edits = artifact_metrics.get("validated_edits", {})
    if isinstance(validated_edits, dict):
        validated_edits_value = validated_edits.get("value", "unknown")
    else:
        validated_edits_value = validated_edits

    action_required = (
        operator_impact is None
        or operator_impact < 8
        or dave_clarity is None
        or dave_clarity < 90
        or stale_count not in (0, "0")
    )
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    payload = {
        "generated_at": now,
        "objective_id": "MIM-TOD-REAL-MOVEMENT-TRAINING-V1",
        "status": "action_required" if action_required else "on_track",
        "overall_readout": (
            "Real movement is not proven yet. Operator Impact, stale artifact retirement, and TOD execution evidence must all improve."
            if action_required
            else "Real movement contract is currently on track."
        ),
        "required_loop": [
            "MIM replies include action, owner, evidence, aging, and Dave-needed yes/no.",
            "TOD produces changed files plus validation, or blocks with inspected evidence, every active cycle.",
            "Stale artifacts are retired, refreshed, or mapped to current project state.",
            "Projects older than 24 hours without movement are forced to completed, split, dispatched, waiting-with-evidence, blocked-with-owner, or archived.",
            "Every action records whether it moved the project closer to completion.",
        ],
        "metrics": [
            {
                "metric": "MIM Operator Impact",
                "current": _metric_current(operator_metrics, "Operator Impact"),
                "target": "8/10+",
                "source": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            },
            {
                "metric": "Dave Needed Clarity",
                "current": _metric_current(operator_metrics, "Dave Needed Clarity"),
                "target": "90%+",
                "source": "MIM_OPERATOR_IMPACT_SCORECARD.latest.json",
            },
            {
                "metric": "Stale Artifact Count",
                "current": str(stale_count),
                "target": "decrease every cycle until 0 or source-labeled historical",
                "source": "MIM_TOD_TRAINING_SCOREBOARD.latest.json",
            },
            {
                "metric": "Validated TOD Edits",
                "current": str(validated_edits_value),
                "target": "fresh real execution/blocker evidence each cycle",
                "source": "tod_result_artifacts",
            },
            {
                "metric": "Dispatcher State",
                "current": str(dispatcher.get("status", "unknown")),
                "target": "no idle state without successor action",
                "source": "MIM_READY_TASK_DISPATCHER_STATUS.latest.json",
            },
            {
                "metric": "Idle Training State",
                "current": str(idle.get("status") or idle.get("state") or "unknown"),
                "target": "training produces real movement or a narrower blocker",
                "source": "TOD_IDLE_TRAINING_STATUS.latest.json",
            },
        ],
        "cycle_001": {
            "status": "ready",
            "actions": [
                {
                    "action": "Score the next 10 live MIM operational replies against the five-field contract.",
                    "owner": "MIM",
                    "evidence": "Updated MIM_OPERATOR_IMPACT_SCORECARD with 10 scored replies and per-field pass rates.",
                    "aging": "Review after 10 replies or 24 hours, whichever comes first.",
                    "dave_needed": "no",
                },
                {
                    "action": "Dispatch one bounded TOD task that must inspect, edit or block with evidence, validate, and publish truth.",
                    "owner": "TOD",
                    "evidence": "Fresh TOD result artifact with changed files or inspected blocker, validation output, and successor state.",
                    "aging": "Escalate if no fresh result appears in the next active cycle.",
                    "dave_needed": "no",
                },
                {
                    "action": "Retire, refresh, or map one stale training artifact to a current project state.",
                    "owner": "MIM + TOD",
                    "evidence": "Stale artifact retirement record naming the artifact, current state, owner, and reason.",
                    "aging": "One stale artifact must move per cycle until the stale count is 0 or source-labeled historical.",
                    "dave_needed": "no",
                },
                {
                    "action": "Select one vague working project and force it into completed, split, dispatched, waiting-with-evidence, blocked-with-owner, or archived.",
                    "owner": "MIM",
                    "evidence": "Project event showing successor or terminal state and expected evidence.",
                    "aging": "Any project with 24 hours of no movement must be reviewed.",
                    "dave_needed": "no unless policy, credential, or external-account approval is required.",
                },
                {
                    "action": "Record whether the cycle moved a project closer to completion.",
                    "owner": "MIM + TOD",
                    "evidence": "Movement outcome label: moved, did_not_move, blocked_with_evidence, split, closed, or archived.",
                    "aging": "Record before the next cycle starts.",
                    "dave_needed": "no",
                },
            ],
        },
        "source_snapshot": {
            "training_scoreboard_generated_at": scoreboard.get("generated_at"),
            "operator_scorecard_generated_at": operator.get("generated_at"),
            "dispatcher_generated_at": dispatcher.get("generated_at"),
            "idle_training_generated_at": idle.get("generated_at"),
            "blocked_summary": blocked_count,
        },
    }

    _write_json(TRAINING_ROOT / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json", payload)
    _write_md(TRAINING_ROOT / "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.md", payload)


if __name__ == "__main__":
    main()
