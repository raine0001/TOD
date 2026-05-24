#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
SHARED = ROOT / "runtime" / "shared"
OBSERVATION_PATH = SHARED / "MIM_ARM_PHYSICAL_MOTION_OBSERVATION.latest.json"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--observed", choices=["yes", "no", "unknown"], required=True)
    parser.add_argument("--source", default="Dave")
    parser.add_argument("--note", default="")
    parser.add_argument("--confidence", default="operator_observed")
    parser.add_argument("--related-artifact", default="MIM_ARM_AREA_EXPLORATION.latest.json")
    args = parser.parse_args()

    observed: bool | None
    if args.observed == "yes":
        observed = True
    elif args.observed == "no":
        observed = False
    else:
        observed = None

    payload = {
        "packet_type": "mim-arm-physical-motion-observation-v1",
        "generated_at": now_iso(),
        "objective_id": "MIM-ARM-PHYSICAL-MOTION-VERIFICATION-V1",
        "status": "blocked_with_evidence" if observed is False else "observed_with_evidence" if observed is True else "unknown",
        "success": observed is True,
        "physical_motion_observed": observed,
        "source": args.source,
        "related_artifact": args.related_artifact,
        "note": args.note,
        "confidence": args.confidence,
        "policy_effect": (
            "Do not mark autonomous arm exploration complete from software pose or serial DONE alone."
            if observed is False
            else "Physical motion observation can be used as supporting evidence for the related movement."
            if observed is True
            else "Physical motion remains unknown; require external evidence before claiming success."
        ),
        "next_recovery_action": (
            "Diagnose physical servo actuation: verify servo power rail, controller sketch behavior, serial command mapping, and use camera/operator confirmation before more autonomous exploration."
            if observed is False
            else ""
        ),
    }
    write_json(OBSERVATION_PATH, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if observed is not False else 2


if __name__ == "__main__":
    raise SystemExit(main())
