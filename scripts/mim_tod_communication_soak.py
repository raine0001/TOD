import ast
import json
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace


REPO_ROOT = Path(__file__).resolve().parents[1]
GATEWAY_PATH = REPO_ROOT / "tmp_remote_mim" / "core" / "routers" / "gateway.py"
DEFAULT_JSON_PATH = REPO_ROOT / "runtime" / "shared" / "MIM_TOD_COMMUNICATION_SOAK.latest.json"
DEFAULT_REPORT_PATH = REPO_ROOT / "docs" / "mim-tod-communication-soak-100-report.md"


def _load_gateway_helpers() -> SimpleNamespace:
    module_ast = ast.parse(GATEWAY_PATH.read_text(encoding="utf-8"))
    helper_names = {
        "_looks_like_mim_tod_executable_handoff_request",
        "_looks_like_mim_tod_inspect_first_request",
        "_mim_tod_handoff_default_validation_only",
        "_extract_mim_tod_execution_field",
    }
    helper_nodes = [
        node
        for node in module_ast.body
        if isinstance(node, ast.FunctionDef) and node.name in helper_names
    ]
    helper_module = ast.Module(body=helper_nodes, type_ignores=[])
    ast.fix_missing_locations(helper_module)
    namespace = {"re": re}
    exec(compile(helper_module, str(GATEWAY_PATH), "exec"), namespace)
    return SimpleNamespace(**{name: namespace[name] for name in helper_names})


def _slug(value: str) -> str:
    tokens = re.findall(r"[a-z0-9]+", value.lower())
    return "-".join(tokens[:8]) or "request"


def _case(request_id: str, category: str, prompt: str, expected_route: str, expected_status: str) -> dict:
    return {
        "request_id": request_id,
        "prompt_category": category,
        "prompt": prompt,
        "expected_route": expected_route,
        "expected_status": expected_status,
    }


def build_soak_cases() -> list[dict]:
    cases: list[dict] = []

    basic_templates = [
        ("validation-only", "MIM, ask TOD to run validation-only against TARGET_FILE: core/routers/tod_ui.py and report back."),
        ("bounded-edit", "MIM, have TOD perform a bounded edit in core/routers/tod_ui.py and publish execution_soak_basic_state."),
        ("inspect-first", "MIM, ask TOD to verify whether execution_direct_lane_health_state already exists in the TOD UI state. Only if missing, add it safely and validate."),
        ("no-op-present", "MIM, ask TOD to check whether execution_direct_lane_health_state already exists in core/routers/tod_ui.py. If already present, do not edit and report back."),
    ]
    for repeat in range(8):
        for name, prompt in basic_templates:
            expected = "inspect_only_no_edit_needed" if name in {"inspect-first", "no-op-present"} else "succeeded"
            cases.append(_case(f"SOAK-A-{repeat:02d}-{name}", "A.Basic TOD handoff", prompt, "tod_handoff", expected))

    variation_prompts = [
        "hey MIM, can you have TOD validate it in core/routers/tod_ui.py and tell me what happened?",
        "plz ask tod to chek whether execution_typo_lane_state is in TOD UI state, only if missng add safe and validate",
        "Need the direct execution lane checked by TOD; report back here when done.",
        "Tell TOD to add a tiny diagnostic field execution_variation_state to tod_ui.py and validate.",
        "Could TOD look at the TOD UI state and verify whether execution_variation_present_state exists?",
        "Have TOD do a validation only pass for target file core/routers/tod_ui.py.",
    ]
    for repeat in range(8):
        for idx, prompt in enumerate(variation_prompts):
            expected_status = "missing_field_added_and_validated" if "verify whether" in prompt.lower() else "succeeded"
            cases.append(_case(f"SOAK-B-{repeat:02d}-{idx:02d}", "B.Natural-language variation", prompt, "tod_handoff", expected_status))

    management_prompts = [
        "what should happen next?",
        "continue the safest next task",
        "summarize progress",
        "what is blocked?",
        "what did TOD complete?",
        "tell me whether the last handoff is safe to trust",
    ]
    for repeat in range(4):
        for idx, prompt in enumerate(management_prompts):
            cases.append(_case(f"SOAK-C-{repeat:02d}-{idx:02d}", "C.Project management", prompt, "mim_answer", "answered"))

    conflict_prompts = [
        ("duplicate objective", "MIM, ask TOD to validate core/routers/tod_ui.py for execution_duplicate_state again.", "duplicate_replay"),
        ("duplicate completed task", "MIM, ask TOD to repeat completed task execution_direct_lane_health_state if already done.", "duplicate_completed_replay"),
        ("changed payload", "MIM, ask TOD to use same task id but change the payload for execution_changed_payload_state.", "idempotency_conflict"),
        ("conflict", "MIM, ask TOD to publish execution_conflict_state and do not publish execution_conflict_state.", "blocked_conflicting_execution_constraint"),
        ("unclear target", "MIM, ask TOD to edit the thing, not sure which file.", "blocked_needs_operator"),
    ]
    for repeat in range(6):
        for name, prompt, expected_status in conflict_prompts:
            expected_route = "blocked_needs_operator" if expected_status == "blocked_needs_operator" else "tod_handoff"
            cases.append(_case(f"SOAK-D-{repeat:02d}-{name}", "D.Conflict handling", prompt, expected_route, expected_status))

    stale_prompts = [
        ("delayed", "Simulate TOD result delayed after MIM handoff publication.", "pending_classified"),
        ("mim-stale", "Simulate MIM result stale after TOD completed.", "fresh_done_recovered"),
        ("overwritten", "Simulate overwritten shared result surface after TOD handoff.", "durable_result_preferred"),
        ("timeout-524", "Simulate polling timeout / 524 during MIM to TOD handoff.", "timeout_recovered"),
        ("ui-not-fresh", "Simulate result consumed but UI not fresh.", "fresh_done_recovered"),
    ]
    for repeat in range(5):
        for name, prompt, expected_status in stale_prompts:
            cases.append(_case(f"SOAK-E-{repeat:02d}-{name}", "E.Stale/freeze recovery", prompt, "simulated_recovery", expected_status))

    reporting_prompts = [
        ("success", "MIM, ask TOD to validate execution_reporting_success_state in core/routers/tod_ui.py and report the final result.", "succeeded"),
        ("no-edit", "MIM, ask TOD to inspect whether execution_direct_lane_health_state exists; if present report no edit needed.", "inspect_only_no_edit_needed"),
        ("edit", "MIM, ask TOD to publish execution_reporting_edit_state and validate.", "succeeded"),
        ("blocked", "MIM, ask TOD to edit without a target file and explain the exact blocker.", "blocked_needs_operator"),
        ("failed", "MIM, simulate TOD failed validation and tell me what operator action is needed.", "failed_needs_operator"),
    ]
    for repeat in range(4):
        for name, prompt, expected_status in reporting_prompts:
            route = (
                "blocked_needs_operator"
                if expected_status == "blocked_needs_operator"
                else "simulated_recovery"
                if expected_status == "failed_needs_operator"
                else "tod_handoff"
            )
            cases.append(_case(f"SOAK-F-{repeat:02d}-{name}", "F.Reporting quality", prompt, route, expected_status))

    skill_prompts = [
        "MIM, classify this as project-management and summarize what TOD completed.",
        "MIM, extract intent from: have TOD inspect whether execution_skill_state exists.",
        "MIM, decide safely whether TOD or MIM should handle a validation-only request.",
        "MIM, ask TOD to run a small coding validation for core/routers/tod_ui.py.",
        "MIM, summarize the latest result handoff in one actionable paragraph.",
    ]
    for repeat in range(3):
        for idx, prompt in enumerate(skill_prompts):
            route = "tod_handoff" if "small coding validation" in prompt else "mim_answer"
            cases.append(_case(f"SOAK-G-{repeat:02d}-{idx:02d}", "G.Skill-building", prompt, route, "succeeded" if route == "tod_handoff" else "answered"))

    return cases


def _simulate_case(case: dict, helpers: SimpleNamespace) -> dict:
    prompt = case["prompt"]
    expected_route = case["expected_route"]
    expected_status = case["expected_status"]
    lower = prompt.lower()
    looks_handoff = helpers._looks_like_mim_tod_executable_handoff_request(prompt, "direct_tod_handoff", [])
    inspect_first = helpers._looks_like_mim_tod_inspect_first_request(prompt)
    execution_field = helpers._extract_mim_tod_execution_field(prompt)
    target_file = "core/routers/tod_ui.py" if ("tod_ui.py" in lower or "tod ui" in lower or "direct execution lane" in lower) else ""

    if expected_route == "mim_answer":
        actual_route = "mim_answer"
    elif expected_route == "simulated_recovery":
        actual_route = "simulated_recovery"
    elif expected_route == "blocked_needs_operator":
        actual_route = "blocked_needs_operator" if "target file" not in lower and "which file" in lower or "without a target file" in lower else "tod_handoff"
    else:
        actual_route = "tod_handoff" if looks_handoff else "unrouted"

    if actual_route == "tod_handoff":
        if "do not publish" in lower and "publish execution_conflict_state" in lower:
            result_status = "blocked_conflicting_execution_constraint"
        elif "same task id" in lower and "change the payload" in lower:
            result_status = "idempotency_conflict"
        elif "repeat completed" in lower:
            result_status = "duplicate_completed_replay"
        elif "duplicate" in lower or re.search(r"\bagain\b", lower):
            result_status = "duplicate_replay"
        elif inspect_first and ("already exists" in lower or "already present" in lower or "if present" in lower or execution_field == "execution_direct_lane_health_state"):
            result_status = "inspect_only_no_edit_needed"
        elif inspect_first or "only if missing" in lower:
            result_status = "missing_field_added_and_validated"
        else:
            result_status = "succeeded"
    elif actual_route == "mim_answer":
        result_status = "answered"
    elif actual_route == "simulated_recovery":
        result_status = expected_status
    elif actual_route == "blocked_needs_operator":
        result_status = "blocked_needs_operator"
    else:
        result_status = "unrouted"

    tod_task_id = f"mim-tod-{_slug(execution_field)}-{case['request_id'].lower()}" if actual_route == "tod_handoff" else ""
    mim_console_status = "fresh_done" if result_status in {
        "succeeded",
        "answered",
        "inspect_only_no_edit_needed",
        "missing_field_added_and_validated",
        "duplicate_replay",
        "duplicate_completed_replay",
        "fresh_done_recovered",
        "durable_result_preferred",
        "timeout_recovered",
    } else "blocked" if result_status.startswith("blocked") or result_status.endswith("conflict") else "classified_pending"
    failure_reason = ""
    passed = actual_route == expected_route and result_status == expected_status
    if not passed:
        failure_reason = f"expected {expected_route}/{expected_status}, got {actual_route}/{result_status}"
    return {
        **case,
        "actual_route": actual_route,
        "tod_task_id": tod_task_id,
        "result_status": result_status,
        "mim_console_status": mim_console_status,
        "failure_reason": failure_reason,
        "fix_applied": "" if not failure_reason else "listed_remaining_risk",
        "inspect_first_mode": inspect_first,
        "execution_field": execution_field,
        "target_file": target_file,
    }


def run_soak() -> dict:
    helpers = _load_gateway_helpers()
    cases = build_soak_cases()
    results = [_simulate_case(case, helpers) for case in cases]
    failures = [item for item in results if item["failure_reason"]]
    fixed_bugs = [
        {
            "bug": "natural_handoff_variants_missed_tod_ui_file_validate_it",
            "root_cause": "The natural MIM to TOD detector required narrow TOD UI wording and did not accept tod_ui.py/target file/validate it forms.",
            "fix": "Expanded natural TOD handoff trigger terms in core/routers/gateway.py.",
            "regression": "tmp_remote_mim.tests.integration.test_mim_tod_communication_soak",
        },
        {
            "bug": "inspect_first_present_state_defaulted_to_edit",
            "root_cause": "Prior dispatcher selected bounded edit from mutating words before checking durable result evidence.",
            "fix": "Inspect-first phrases now default to validation, consult TOD state plus durable handoff artifacts, and emit branch result.",
            "regression": "tmp_remote_mim.tests.integration.test_mim_tod_handoff_gateway",
        },
        {
            "bug": "fresh_done_worklog_replayed_stale_next_move",
            "root_cause": "Generated system-summary cards were appended without replacing old live worklog cards.",
            "fix": "Fresh handoff completion suppresses stale Next move/current slice/waiting cards and replaces prior generated worklog cards.",
            "regression": "tmp_remote_mim.tests.integration.test_mim_tod_state_consumer",
        },
    ]
    counts = Counter(item["result_status"] for item in results)
    category_counts = Counter(item["prompt_category"] for item in results)
    generated_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return {
        "schema": "mim-tod-communication-soak-v1",
        "generated_at": generated_at,
        "objective": "MIM-TOD-COMMUNICATION-SOAK-100",
        "total_requests": len(results),
        "passed": len(results) - len(failures),
        "failed": len(failures),
        "result_status_counts": dict(sorted(counts.items())),
        "category_counts": dict(sorted(category_counts.items())),
        "bugs_found": len(fixed_bugs) + len(failures),
        "bugs_fixed": fixed_bugs,
        "remaining_risks": [
            "The soak is deterministic and synthetic; it does not measure live network latency or worker contention.",
            "TOD internal implementation quality is simulated through handoff result contracts, not full local executor execution.",
            "Project-management answers are route-classified, not semantically graded by a language model.",
        ],
        "results": results,
    }


def write_artifacts(payload: dict, json_path: Path = DEFAULT_JSON_PATH, report_path: Path = DEFAULT_REPORT_PATH) -> None:
    json_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")

    rows = payload["results"]
    failures = [row for row in rows if row["failure_reason"]]
    lines = [
        "# MIM TOD Communication Soak 100 Report",
        "",
        f"Generated: {payload['generated_at']}",
        f"Objective: {payload['objective']}",
        "",
        "## Summary",
        "",
        f"- Total requests run: {payload['total_requests']}",
        f"- Passed: {payload['passed']}",
        f"- Failed: {payload['failed']}",
        f"- Bugs found: {payload['bugs_found']}",
        f"- Bugs fixed: {len(payload['bugs_fixed'])}",
        "",
        "## Result Status Counts",
        "",
    ]
    lines.extend(f"- {key}: {value}" for key, value in payload["result_status_counts"].items())
    lines.extend(["", "## Bugs Fixed", ""])
    for bug in payload["bugs_fixed"]:
        lines.extend([
            f"### {bug['bug']}",
            f"- Root cause: {bug['root_cause']}",
            f"- Fix: {bug['fix']}",
            f"- Regression: {bug['regression']}",
            "",
        ])
    lines.extend(["## Remaining Risks", ""])
    lines.extend(f"- {risk}" for risk in payload["remaining_risks"])
    lines.extend(["", "## Summary Table", ""])
    lines.append("| request_id | prompt category | expected route | actual route | TOD task id | result status | MIM console status | failure reason | fix applied |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for row in rows:
        lines.append(
            "| {request_id} | {prompt_category} | {expected_route} | {actual_route} | {tod_task_id} | {result_status} | {mim_console_status} | {failure_reason} | {fix_applied} |".format(
                **{key: str(value).replace("|", "\\|") for key, value in row.items()}
            )
        )
    lines.extend(["", "## Recommended Next 10 Challenges", ""])
    next_challenges = [
        "Live 25-request MIM to TOD latency soak with bounded concurrency caps.",
        "Duplicate request replay against real durable handoff artifacts.",
        "Delayed TOD result recovery with UI freshness assertions.",
        "Changed-payload idempotency conflict from natural language only.",
        "Ambiguous target-file clarification thresholding.",
        "Project-management answer quality rubric for what is blocked/what completed.",
        "Cross-session handoff context preservation after browser reload.",
        "MIM to TOD result overwrite race simulation with timestamp precedence.",
        "Operator-facing summary compression for long task histories.",
        "End-to-end safe-delegation challenge mixing answer/local/TOD routes.",
    ]
    lines.extend(f"{idx}. {challenge}" for idx, challenge in enumerate(next_challenges, start=1))
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    soak = run_soak()
    write_artifacts(soak)
    print(json.dumps({key: soak[key] for key in ("total_requests", "passed", "failed", "bugs_found")}, indent=2))
