import argparse
import base64
import json
import statistics
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JSON_PATH = REPO_ROOT / "runtime" / "shared" / "MIM_TOD_LIVE_COMMUNICATION_SOAK.latest.json"
DEFAULT_REPORT_PATH = REPO_ROOT / "docs" / "mim-tod-live-communication-soak-3h-report.md"
DEFAULT_BASE_URL = "https://mim.mimtod.com"
FIXED_BUGS = [
    {
        "bug": "inspect_first_live_presence_missed_target_file_evidence",
        "root_cause": "Live inspect-first handoff checked TOD state and durable artifacts but did not inspect the requested target file, so existing execution_* fields could be treated as missing.",
        "fix": "core/routers/gateway.py now checks the target_file content before choosing validation-only versus bounded-edit inspect-first branch.",
        "regression": "tmp_remote_mim.tests.integration.test_mim_tod_handoff_gateway.test_inspect_first_uses_target_file_as_present_evidence",
    }
]


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _monotonic_ms() -> int:
    return int(time.monotonic() * 1000)


def _headers(username: str, password: str, *, json_content: bool = False) -> dict[str, str]:
    token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    headers = {
        "Authorization": f"Basic {token}",
        "Accept": "application/json,text/plain,*/*",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36",
    }
    if json_content:
        headers["Content-Type"] = "application/json"
    return headers


def _http_json(
    *,
    method: str,
    url: str,
    username: str,
    password: str,
    payload: dict | None = None,
    timeout_seconds: int = 120,
) -> tuple[int, dict]:
    data = None
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=True).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers=_headers(username, password, json_content=payload is not None),
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            text = response.read().decode("utf-8", errors="replace")
            parsed = json.loads(text) if text.strip() else {}
            return int(getattr(response, "status", 200) or 200), parsed if isinstance(parsed, dict) else {"value": parsed}
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(text) if text.strip() else {}
        except json.JSONDecodeError:
            parsed = {"error": text}
        return int(exc.code), parsed if isinstance(parsed, dict) else {"value": parsed}
    except Exception as exc:  # noqa: BLE001
        return 0, {"error": str(exc)}


def build_live_cases(limit: int) -> list[dict]:
    base_cases = [
        {
            "prompt_category": "1.Natural language TOD delegation",
            "prompt": "MIM, ask TOD to run validation-only against TARGET_FILE: core/routers/tod_ui.py and report back.",
            "expected_route": "tod_handoff",
        },
        {
            "prompt_category": "2.Inspect-first no-op",
            "prompt": "MIM, ask TOD to verify whether execution_direct_lane_health_state already exists in the TOD UI state. If it already exists, TOD must not edit anything. If it is missing, TOD may add it safely and validate. Report back whether TOD inspected only or edited.",
            "expected_route": "tod_handoff",
        },
        {
            "prompt_category": "2.Inspect-first bounded edit",
            "prompt": "MIM, ask TOD to inspect whether execution_live_soak_probe_state exists in core/routers/tod_ui.py. Only if missing, add it safely and validate.",
            "expected_route": "tod_handoff",
        },
        {
            "prompt_category": "3.Duplicate replay",
            "prompt": "MIM, ask TOD to verify whether execution_direct_lane_health_state already exists in the TOD UI state. If already present, do not edit and report no edit needed.",
            "expected_route": "tod_handoff",
        },
        {
            "prompt_category": "4.Changed payload conflict",
            "prompt": "MIM, ask TOD to use the same task identity but change the payload for execution_live_soak_payload_conflict_state. If that conflicts, block and report the exact reason.",
            "expected_route": "tod_handoff",
        },
        {
            "prompt_category": "5.Ambiguous target clarification",
            "prompt": "MIM, ask TOD to edit the thing safely, but I have not named a target file. Tell me whether clarification is required.",
            "expected_route": "blocked_or_answer",
        },
        {
            "prompt_category": "6.Delayed result recovery",
            "prompt": "MIM, ask TOD to check whether execution_direct_lane_health_state exists and report back; treat delayed completion as pending, not stale.",
            "expected_route": "tod_handoff",
        },
        {
            "prompt_category": "8.Reload state preservation",
            "prompt": "MIM, summarize whether the latest TOD handoff is fresh after a console reload.",
            "expected_route": "mim_answer",
        },
        {
            "prompt_category": "10.Operator summary",
            "prompt": "MIM, summarize the last TOD handoff result in one operator-useful paragraph.",
            "expected_route": "mim_answer",
        },
        {
            "prompt_category": "11.Mixed answer route",
            "prompt": "MIM, what did TOD complete most recently?",
            "expected_route": "mim_answer",
        },
        {
            "prompt_category": "12.Project management",
            "prompt": "MIM, what is blocked right now?",
            "expected_route": "mim_answer",
        },
        {
            "prompt_category": "12.Project management",
            "prompt": "MIM, what should happen next?",
            "expected_route": "mim_answer",
        },
        {
            "prompt_category": "12.Project management",
            "prompt": "MIM, summarize the last 10 handoffs.",
            "expected_route": "mim_answer",
        },
        {
            "prompt_category": "12.Project management",
            "prompt": "MIM, continue the safest next task, but do not move hardware and report the chosen route.",
            "expected_route": "mim_answer",
        },
    ]
    cases: list[dict] = []
    for idx in range(limit):
        item = dict(base_cases[idx % len(base_cases)])
        item["sequence"] = idx + 1
        item["local_case_id"] = f"LIVE-SOAK-{idx + 1:03d}"
        cases.append(item)
    return cases


def _extract_resolution(payload: dict) -> dict:
    resolution = payload.get("resolution") if isinstance(payload.get("resolution"), dict) else {}
    metadata = resolution.get("metadata_json") if isinstance(resolution.get("metadata_json"), dict) else {}
    tod_dispatch = payload.get("tod_dispatch") if isinstance(payload.get("tod_dispatch"), dict) else metadata.get("tod_dispatch")
    mim_interface = payload.get("mim_interface") if isinstance(payload.get("mim_interface"), dict) else metadata.get("mim_interface")
    return {
        "request_id": str(payload.get("request_id") or metadata.get("request_id") or "").strip(),
        "resolution_reason": str(resolution.get("reason") or "").strip(),
        "tod_dispatch": tod_dispatch if isinstance(tod_dispatch, dict) else {},
        "mim_interface": mim_interface if isinstance(mim_interface, dict) else {},
        "reply": str((mim_interface or {}).get("reply_text") or metadata.get("mim_interface_reply_override") or resolution.get("clarification_prompt") or "").strip(),
    }


def _grade_response(*, expected_route: str, response_status: int, resolution: dict, ui_state: dict) -> dict:
    tod_dispatch = resolution["tod_dispatch"]
    mim_interface = resolution["mim_interface"]
    reply = resolution["reply"]
    result_status = str(tod_dispatch.get("result_status") or mim_interface.get("status") or "").strip().lower()
    handoff_id = str(tod_dispatch.get("handoff_id") or "").strip()
    task_id = str(tod_dispatch.get("task_id") or "").strip()
    actual_route = "tod_handoff" if handoff_id or str(tod_dispatch.get("dispatch_kind") or "") == "mim_tod_executable_handoff" else "mim_answer"
    if response_status in {0, 502, 503, 504, 524}:
        actual_route = "gateway_timeout_or_unavailable"
    console_freshness = str(ui_state.get("console_freshness_status") or "").strip()
    system_activity = ui_state.get("system_activity") if isinstance(ui_state.get("system_activity"), dict) else {}
    mim_console_status = str(system_activity.get("status_label") or ui_state.get("status_label") or "").strip()
    ui_fresh = console_freshness in {"fresh_done", "handoff_result_pending", "no_handoff_result"}
    stale_unclassified = bool(
        str(mim_console_status or "").upper() == "STALE"
        and console_freshness == "no_handoff_result"
        and actual_route == "tod_handoff"
        and result_status not in {"waiting", "pending", "blocked"}
    )
    route_ok = (
        actual_route == expected_route
        or expected_route == "blocked_or_answer"
        and actual_route in {"mim_answer", "tod_handoff"}
    )
    handoff_ok = actual_route != "tod_handoff" or bool(handoff_id and task_id)
    result_ok = result_status in {"done", "succeeded", "waiting", "pending", "blocked"} or actual_route == "mim_answer"
    response_complete = bool(reply) and len(reply) >= 40
    stale_cleanup_ok = "STALE" not in mim_console_status.upper() if console_freshness == "fresh_done" else True
    passed = bool(
        route_ok
        and handoff_ok
        and result_ok
        and ui_fresh
        and response_complete
        and stale_cleanup_ok
        and not stale_unclassified
    )
    failure_parts = []
    if not route_ok:
        failure_parts.append(f"route expected {expected_route} got {actual_route}")
    if not handoff_ok:
        failure_parts.append("handoff missing id/task")
    if not result_ok:
        failure_parts.append(f"unexpected result status {result_status}")
    if not ui_fresh:
        failure_parts.append(f"ui freshness {console_freshness or 'missing'}")
    if not response_complete:
        failure_parts.append("response incomplete")
    if not stale_cleanup_ok:
        failure_parts.append(f"fresh_done displayed stale status {mim_console_status}")
    if stale_unclassified:
        failure_parts.append("tod handoff stale with no classified pending/blocking status")
    return {
        "actual_route": actual_route,
        "handoff_id": handoff_id,
        "tod_task_id": task_id,
        "tod_status": str(tod_dispatch.get("tod_status") or result_status).strip(),
        "mim_console_status": mim_console_status,
        "ui_freshness": console_freshness,
        "response_quality_grade": "pass" if response_complete else "needs_work",
        "passed": passed,
        "failure_reason": "; ".join(failure_parts),
    }


def run_live_soak(
    *,
    base_url: str,
    username: str,
    password: str,
    limit: int,
    delay_seconds: float,
    timeout_seconds: int,
) -> dict:
    cases = build_live_cases(limit)
    started_at = _utc_now()
    start_ms = _monotonic_ms()
    rows: list[dict] = []
    for case in cases:
        timestamp = _utc_now()
        intake_start = _monotonic_ms()
        payload = {
            "text": case["prompt"],
            "parsed_intent": "direct_tod_handoff" if case["expected_route"] == "tod_handoff" else "conversation",
            "safety_flags": [],
            "metadata_json": {
                "source": "codex_live_soak",
                "interaction_mode": "text",
                "message_type": "user",
                "conversation_session_id": "codex-live-communication-soak",
                "route_preference": "conversation_layer",
                "local_case_id": case["local_case_id"],
            },
        }
        response_status, response_payload = _http_json(
            method="POST",
            url=f"{base_url.rstrip('/')}/gateway/intake/text",
            username=username,
            password=password,
            payload=payload,
            timeout_seconds=timeout_seconds,
        )
        intake_ms = _monotonic_ms() - intake_start
        resolution = _extract_resolution(response_payload)
        ui_start = _monotonic_ms()
        ui_status, ui_state = _http_json(
            method="GET",
            url=f"{base_url.rstrip('/')}/mim/ui/state",
            username=username,
            password=password,
            timeout_seconds=timeout_seconds,
        )
        ui_ms = _monotonic_ms() - ui_start
        grade = _grade_response(
            expected_route=case["expected_route"],
            response_status=response_status,
            resolution=resolution,
            ui_state=ui_state,
        )
        tod_dispatch = resolution["tod_dispatch"]
        row = {
            "timestamp": timestamp,
            "local_case_id": case["local_case_id"],
            "prompt": case["prompt"],
            "prompt_category": case["prompt_category"],
            "expected_route": case["expected_route"],
            "actual_route": grade["actual_route"],
            "request_id": resolution["request_id"],
            "handoff_id": grade["handoff_id"],
            "TOD_task_id": grade["tod_task_id"],
            "TOD_status": grade["tod_status"],
            "MIM_console_status": grade["mim_console_status"],
            "UI_freshness": grade["ui_freshness"],
            "response_quality_grade": grade["response_quality_grade"],
            "failure_reason": grade["failure_reason"],
            "fix_applied": "",
            "passed": grade["passed"],
            "http_status": response_status,
            "ui_http_status": ui_status,
            "latency_ms": {
                "mim_intake": intake_ms,
                "tod_handoff_publish": int(tod_dispatch.get("handoff_publish_latency_ms") or intake_ms),
                "tod_completion": int(tod_dispatch.get("tod_completion_latency_ms") or intake_ms),
                "mim_consume": int(tod_dispatch.get("mim_consume_latency_ms") or intake_ms),
                "ui_fresh_done": ui_ms,
                "total_observed": intake_ms + ui_ms,
            },
            "reply": resolution["reply"],
        }
        rows.append(row)
        if delay_seconds > 0 and case is not cases[-1]:
            time.sleep(delay_seconds)
    duration_ms = _monotonic_ms() - start_ms
    latencies = [row["latency_ms"]["total_observed"] for row in rows]
    p95 = 0
    if latencies:
        p95 = sorted(latencies)[max(0, min(len(latencies) - 1, int(round(len(latencies) * 0.95)) - 1))]
    status_counts = Counter(row["TOD_status"] or row["actual_route"] for row in rows)
    failed_rows = [row for row in rows if not row["passed"]]
    return {
        "schema": "mim-tod-live-communication-soak-v1",
        "objective": "MIM-TOD-LIVE-COMMUNICATION-SOAK-3H",
        "started_at": started_at,
        "finished_at": _utc_now(),
        "duration_seconds": round(duration_ms / 1000.0, 3),
        "total_requests": len(rows),
        "passed": len(rows) - len(failed_rows),
        "failed": len(failed_rows),
        "average_latency_ms": round(statistics.mean(latencies), 2) if latencies else 0,
        "p95_latency_ms": p95,
        "status_counts": dict(sorted(status_counts.items())),
        "bugs_found": len(failed_rows) + len(FIXED_BUGS),
        "bugs_fixed": len(FIXED_BUGS),
        "bugs_fixed_detail": FIXED_BUGS,
        "remaining_risks": [
            "Live soak uses HTTP gateway/UI state, but does not drive a browser DOM or physical hardware.",
            "Bounded concurrency is not enabled unless a separate run starts parallel workers.",
            "Some TOD task completion latency is inferred from synchronous MIM response time when artifacts do not expose per-stage timestamps.",
        ],
        "results": rows,
    }


def write_artifacts(payload: dict, json_path: Path = DEFAULT_JSON_PATH, report_path: Path = DEFAULT_REPORT_PATH) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    lines = [
        "# MIM TOD Live Communication Soak 3H Report",
        "",
        f"Started: {payload['started_at']}",
        f"Finished: {payload['finished_at']}",
        f"Duration seconds: {payload['duration_seconds']}",
        "",
        "## Summary",
        "",
        f"- Live requests run: {payload['total_requests']}",
        f"- Passed: {payload['passed']}",
        f"- Failed: {payload['failed']}",
        f"- Average latency ms: {payload['average_latency_ms']}",
        f"- P95 latency ms: {payload['p95_latency_ms']}",
        f"- Bugs found: {payload['bugs_found']}",
        f"- Bugs fixed during run: {payload['bugs_fixed']}",
        "",
        "## Status Counts",
        "",
    ]
    lines.extend(f"- {key}: {value}" for key, value in payload["status_counts"].items())
    lines.extend(["", "## Bugs Fixed", ""])
    for bug in payload.get("bugs_fixed_detail", []):
        lines.extend(
            [
                f"### {bug['bug']}",
                f"- Root cause: {bug['root_cause']}",
                f"- Fix: {bug['fix']}",
                f"- Regression: {bug['regression']}",
                "",
            ]
        )
    lines.extend(["", "## Remaining Risks", ""])
    lines.extend(f"- {risk}" for risk in payload["remaining_risks"])
    lines.extend(["", "## Summary Table", ""])
    lines.append("| timestamp | prompt | expected route | actual route | request_id | handoff_id | TOD task id | TOD status | MIM console status | UI freshness | response quality grade | failure reason | fix applied |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for row in payload["results"]:
        safe = {key: str(value).replace("|", "\\|").replace("\n", " ") for key, value in row.items()}
        lines.append(
            "| {timestamp} | {prompt} | {expected_route} | {actual_route} | {request_id} | {handoff_id} | {TOD_task_id} | {TOD_status} | {MIM_console_status} | {UI_freshness} | {response_quality_grade} | {failure_reason} | {fix_applied} |".format(**safe)
        )
    lines.extend(["", "## Recommended Next 10 Challenges", ""])
    next_challenges = [
        "Repeat this run with browser DOM polling and screenshot assertions.",
        "Run a 25-request bounded concurrency 2 soak after single-lane stays green.",
        "Add live duplicate-detection assertions that compare handoff IDs across duplicate prompts.",
        "Add live result-overwrite race injection on sandbox shared artifacts.",
        "Add Cloudflare 524 replay using a controlled delayed TOD response.",
        "Grade operator response quality with a deterministic rubric per category.",
        "Track true TOD stage timestamps inside handoff result artifacts.",
        "Exercise cross-session reload by alternating session ids and UI state polling.",
        "Separate project-management prompts from execution prompts in final UI summaries.",
        "Promote a nightly 20-request safe live smoke with alert-only reporting.",
    ]
    lines.extend(f"{idx}. {challenge}" for idx, challenge in enumerate(next_challenges, start=1))
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--username", default="dave")
    parser.add_argument("--password", required=True)
    parser.add_argument("--limit", type=int, default=75)
    parser.add_argument("--delay-seconds", type=float, default=2.0)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args()
    payload = run_live_soak(
        base_url=args.base_url,
        username=args.username,
        password=args.password,
        limit=args.limit,
        delay_seconds=args.delay_seconds,
        timeout_seconds=args.timeout_seconds,
    )
    write_artifacts(payload)
    print(json.dumps({key: payload[key] for key in ("duration_seconds", "total_requests", "passed", "failed", "average_latency_ms", "p95_latency_ms", "bugs_found")}, indent=2))


if __name__ == "__main__":
    main()
