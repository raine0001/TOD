#!/usr/bin/env python3
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(name: str) -> dict:
    path = SHARED / name
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data if isinstance(data, dict) else {}


def write_json(name: str, payload: dict) -> None:
    path = SHARED / name
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    observation = read_json("MIM_ARM_PHYSICAL_MOTION_OBSERVATION.latest.json")
    if observation.get("physical_motion_observed") is not True:
        print(json.dumps({"status": "blocked", "reason": "no_positive_physical_observation"}))
        return 2

    area = read_json("MIM_ARM_AREA_EXPLORATION.latest.json")
    viewpoints = area.get("viewpoints") if isinstance(area.get("viewpoints"), list) else []
    software_ok = bool(viewpoints) and all(
        view.get("software_pose_verified") and view.get("returned_home") for view in viewpoints
    )
    if not software_ok:
        print(json.dumps({"status": "blocked", "reason": "software_viewpoints_not_verified"}))
        return 2

    for view in viewpoints:
        view["physical_motion_verified"] = True
        view["physical_motion_evidence_source"] = observation.get("confidence") or "recent_operator_observation"

    blockers = [item for item in (area.get("blockers") or []) if item != "external_physical_motion_verification_missing"]
    area["status"] = "completed_with_evidence"
    area["success"] = True
    area["blockers"] = blockers
    area["physical_motion_observation_applied_at"] = now_iso()
    area.setdefault("verification_policy", {})["physical_motion_supported"] = True
    area.setdefault("verification_policy", {})["physical_motion_observation"] = observation
    area["next_recovery_action"] = ""
    write_json("MIM_ARM_AREA_EXPLORATION.latest.json", area)

    for name in [
        "MIM_ARM_SIM_SYNC_SPACE_STATUS.latest.json",
        "MIM_ARM_WORKSPACE_EXPLORATION_VOICE_ROUTE.latest.json",
    ]:
        payload = read_json(name)
        if not payload:
            continue
        payload["status"] = "completed_with_evidence"
        payload["success"] = True
        payload["blockers"] = [
            item for item in (payload.get("blockers") or []) if item != "external_physical_motion_verification_missing"
        ]
        payload["physical_motion_observation"] = observation
        if name == "MIM_ARM_WORKSPACE_EXPLORATION_VOICE_ROUTE.latest.json":
            payload["response_text"] = (
                "I ran the bounded table workspace exploration. Status is completed_with_evidence; "
                f"{len(viewpoints)} viewpoints; physical motion observed by Dave; returned to the start pose."
            )
        write_json(name, payload)

    print(json.dumps({"status": "completed_with_evidence", "success": True, "viewpoints": len(viewpoints)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
