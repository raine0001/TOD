#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
MODULE = ROOT / "scripts" / "mim_wake_listen_loop.py"
OUT = ROOT / "runtime" / "shared" / "MIM_VOICE_DIRECT_ADDRESS_GATE_VALIDATION.latest.json"


def load_module():
    spec = importlib.util.spec_from_file_location("mim_wake_listen_loop", MODULE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def main():
    wake = load_module()
    scene = {"conversation_mode": "single_speaker_or_unknown"}
    cases = [
        {
            "name": "direct_mim_current_tasks",
            "text": "MIM, what are your current tasks?",
            "expect_addressed": True,
            "expect_route_intent": "current_task_status",
        },
        {
            "name": "direct_implicit_current_work",
            "text": "What are you working on right now?",
            "expect_addressed": True,
            "expect_route_intent": "current_task_status",
        },
        {
            "name": "ambient_phone_plan",
            "text": "I will text you when I leave. We are going to Karens.",
            "expect_addressed": False,
        },
        {
            "name": "ambient_dinner_late",
            "text": "Dinner thing, I am late.",
            "expect_addressed": False,
        },
        {
            "name": "ambient_continuation",
            "text": "which is where we went with that",
            "expect_addressed": False,
        },
        {
            "name": "direct_hearing_check",
            "text": "MIM, can you hear me?",
            "expect_addressed": True,
        },
    ]
    results = []
    ok = True
    for case in cases:
        decision = wake.decide_voice_addressing(case["text"], scene=scene, source="synthetic_validation")
        route = wake.route_followup(case["text"])
        passed = decision.get("addressed_to_mim") is case["expect_addressed"]
        if case.get("expect_route_intent"):
            passed = passed and route.get("intent") == case["expect_route_intent"]
        ok = ok and passed
        results.append(
            {
                "case": case["name"],
                "text": case["text"],
                "passed": passed,
                "expected_addressed": case["expect_addressed"],
                "addressed": decision.get("addressed_to_mim"),
                "reason_code": decision.get("reason_code"),
                "recommended_action": decision.get("recommended_action"),
                "explicit_mim_work_question": decision.get("explicit_mim_work_question"),
                "other_human_conversation": decision.get("other_human_conversation"),
                "route_intent": route.get("intent"),
                "route_action": route.get("action"),
                "route_response": route.get("response_text", "")[:220],
            }
        )
    payload = {
        "packet_type": "mim-voice-direct-address-gate-validation-v1",
        "success": ok,
        "status": "passed" if ok else "failed",
        "validated_module": str(MODULE),
        "results": results,
    }
    OUT.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
