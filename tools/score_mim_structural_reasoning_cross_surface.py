from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from run_universal_mim_customer_conversation_smoke import SurfaceClient, SurfaceConfig  # noqa: E402
from score_mim_structural_reasoning_diversity import score_reply_for_dimensions  # noqa: E402


DEFAULT_SUITE = ROOT / "tod" / "conversation_eval" / "mim_structural_reasoning_diversity_suite_v1.json"
DEFAULT_OUTPUT = ROOT / "runtime_remote_training" / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json"
DEFAULT_MARKDOWN_OUTPUT = ROOT / "runtime_remote_training" / "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.md"

SURFACE_TARGET = 0.9
DIRECT_ANSWER_BLOCKERS = (
    "could you clarify",
    "what specific topic",
    "need more context",
    "not provide real-time facts",
)


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_dotenv_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


class StudioSurfaceClient:
    def __init__(
        self,
        base_url: str,
        *,
        timeout: int,
        studio_test_token: str | None = None,
        studio_username: str | None = None,
        studio_password: str | None = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.studio_test_token = (studio_test_token or "").strip()
        self.studio_username = (studio_username or "").strip()
        self.studio_password = studio_password or ""
        self.available = True
        self.unavailable_reason = ""

    def bootstrap(self) -> None:
        return

    def post_turn(self, session_key: str, message: str) -> str:
        payload = json.dumps(
            {
                "message": message,
                "prompt": message,
                "conversation_session_id": session_key,
                "page_context": "Studio operator chat",
                "metadata_json": {
                    "surface": "studio_operator_chat",
                    "objective": "structural_reasoning_cross_surface",
                },
            },
            ensure_ascii=False,
        ).encode("utf-8")
        headers = {
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "MIM structural cross-surface smoke/1.0",
            "Accept": "application/json, text/plain, */*",
        }
        if self.studio_test_token:
            headers["Authorization"] = f"Bearer {self.studio_test_token}"
            headers["X-MIM-Studio-Test-Auth"] = self.studio_test_token
        elif self.studio_username and self.studio_password:
            token = base64.b64encode(f"{self.studio_username}:{self.studio_password}".encode("utf-8")).decode("ascii")
            headers["Authorization"] = f"Basic {token}"
        request = urllib.request.Request(
            self.base_url + "/studio/api/mim/chat",
            data=payload,
            headers=headers,
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=self.timeout) as response:
            data = json.loads(response.read().decode("utf-8", errors="replace"))
        return extract_reply(data)


def extract_reply(data: Any) -> str:
    if isinstance(data, str):
        return data.strip()
    if not isinstance(data, dict):
        return ""
    for key in ("reply_text", "message", "response", "content", "text"):
        value = data.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    for key in ("reply", "mim_interface", "result"):
        value = data.get(key)
        if isinstance(value, dict):
            nested = extract_reply(value)
            if nested:
                return nested
    return ""


def surface_configs(args: argparse.Namespace) -> list[SurfaceConfig | dict[str, Any]]:
    upload_context = {
        "commissionUpload": {
            "context_type": "commission_upload",
            "session": {
                "has_pending_upload": False,
                "file_name": None,
                "file_kind": "historical_commissions",
                "month": "2026-05",
            },
            "carrier": {"name": "AGA", "confirmed": True},
            "parser": {"record_count": 3336, "total_commission_paid": 176876.24},
            "mapping": {"overrides": {}},
            "upload_status": {"status": "ready"},
            "next_actions": ["validate totals", "review missing reps", "confirm month closeout"],
        }
    }
    return [
        SurfaceConfig("mimtod_public_chat", "mimtod_public", args.mimtod_base_url, context="mim"),
        SurfaceConfig("agentmim_public_sales_chat", "agentmim", args.agentmim_base_url, context="sales"),
        SurfaceConfig("agentmim_logged_in_assistant", "agentmim", args.agentmim_base_url, context="workspace", requires_auth=True),
        SurfaceConfig(
            "agentmim_commission_upload_assistant",
            "agentmim",
            args.agentmim_base_url,
            context="workspace",
            requires_auth=True,
            page_context=upload_context,
        ),
        {
            "key": "studio_mim_operator_chat",
            "kind": "studio",
            "base_url": args.studio_base_url,
            "requires_auth": True,
        },
    ]


def build_client(config: SurfaceConfig | dict[str, Any], args: argparse.Namespace):
    if isinstance(config, dict) and config.get("kind") == "studio":
        return StudioSurfaceClient(
            str(config["base_url"]),
            timeout=args.timeout,
            studio_test_token=args.studio_test_token or os.getenv("MIM_STUDIO_TEST_TOKEN"),
            studio_username=args.studio_username or os.getenv("MIMTOD_USER"),
            studio_password=args.studio_password or os.getenv("MIMTOD_PASSWORD"),
        )
    return SurfaceClient(
        config,
        timeout=args.timeout,
        agentmim_username=args.agentmim_username or os.getenv("AGENTMIM_USERNAME"),
        agentmim_password=args.agentmim_password or os.getenv("AGENTMIM_PASSWORD"),
        agentmim_cookie=args.agentmim_cookie or os.getenv("AGENTMIM_COOKIE"),
        agentmim_test_auth_token=args.agentmim_test_auth_token or os.getenv("AGENTMIM_TEST_AUTH_TOKEN"),
    )


def config_key(config: SurfaceConfig | dict[str, Any]) -> str:
    return str(config["key"] if isinstance(config, dict) else config.key)


def run_control_checks(client: Any, surface_key: str, run_id: str) -> list[dict[str, Any]]:
    controls = [
        {
            "id": "direct-answer-date",
            "turns": ["What day of the week is it?"],
            "required_any": ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"),
        },
        {
            "id": "contextual-france-followup",
            "turns": ["What day of the week is it?", "what about in France?"],
            "required_any": ("france", "french", "central european", "cet", "cest"),
        },
    ]
    results = []
    for control in controls:
        replies: list[str] = []
        failures: list[str] = []
        session_key = f"{run_id}-{surface_key}-{control['id']}"
        for turn in control["turns"]:
            reply = client.post_turn(session_key, turn)
            replies.append(reply)
        final_reply = replies[-1].lower()
        if any(blocker in final_reply for blocker in DIRECT_ANSWER_BLOCKERS):
            failures.append("lazy_clarification_or_direct_answer_regression")
        if not any(token in final_reply for token in control["required_any"]):
            failures.append("expected_direct_answer_signal_missing")
        results.append(
            {
                "control_id": control["id"],
                "passed": not failures,
                "failures": failures,
                "turns": [{"turn": turn, "reply": reply} for turn, reply in zip(control["turns"], replies, strict=False)],
            }
        )
    return results


def run_surface(config: SurfaceConfig | dict[str, Any], cards: list[dict[str, Any]], args: argparse.Namespace, run_id: str) -> dict[str, Any]:
    key = config_key(config)
    client = build_client(config, args)
    try:
        client.bootstrap()
    except Exception as exc:  # noqa: BLE001
        return unavailable_surface(key, f"bootstrap_error:{type(exc).__name__}")
    if not getattr(client, "available", True):
        return unavailable_surface(key, getattr(client, "unavailable_reason", "unavailable"))

    cases: list[dict[str, Any]] = []
    for index, card in enumerate(cards, start=1):
        scenario_id = str(card.get("id") or f"scenario-{index:03d}")
        prompt = str(card.get("prompt") or "")
        required_dimensions = tuple(str(item) for item in card.get("required_dimensions") or [])
        try:
            reply = client.post_turn(f"{run_id}-{key}-{index:03d}", prompt)
            scored = score_reply_for_dimensions(prompt, reply, required_dimensions)
        except urllib.error.HTTPError as exc:
            if exc.code in {401, 403}:
                return unavailable_surface(key, f"auth_error:HTTPError_{exc.code}")
            scored = score_reply_for_dimensions(prompt, "", required_dimensions)
            scored["failures"] = sorted(set(scored["failures"] + [f"request_error:HTTPError_{exc.code}"]))
            scored["passed"] = False
        except Exception as exc:  # noqa: BLE001
            scored = score_reply_for_dimensions(prompt, "", required_dimensions)
            scored["failures"] = sorted(set(scored["failures"] + [f"request_error:{type(exc).__name__}"]))
            scored["passed"] = False
        scored.update({"scenario_id": scenario_id, "bucket": card.get("bucket"), "weight": float(card.get("weight") or 0.0)})
        cases.append(scored)

    control_checks: list[dict[str, Any]] = []
    try:
        control_checks = run_control_checks(client, key, run_id)
    except Exception as exc:  # noqa: BLE001
        control_checks = [{"control_id": "controls_unavailable", "passed": False, "failures": [type(exc).__name__], "turns": []}]

    total_weight = sum(float(case.get("weight") or 0.0) for case in cases)
    weighted_pass = sum(float(case.get("weight") or 0.0) * (1.0 if case.get("passed") else 0.0) for case in cases)
    weighted_score = sum(float(case.get("weight") or 0.0) * (float(case.get("score_10") or 0.0) / 10.0) for case in cases)
    pass_count = sum(1 for case in cases if case.get("passed"))
    control_failures = [item for item in control_checks if not item.get("passed")]
    weighted_pass_rate = round(weighted_pass / total_weight, 4) if total_weight else 0.0
    summary = {
        "status": "target_met" if weighted_pass_rate >= SURFACE_TARGET and not control_failures else "needs_training",
        "target_weighted_pass_rate": SURFACE_TARGET,
        "case_count": len(cases),
        "pass_count": pass_count,
        "pass_rate": round(pass_count / max(1, len(cases)), 4),
        "weighted_pass_rate": weighted_pass_rate,
        "weighted_structural_score": round((weighted_score / total_weight) * 10.0, 1) if total_weight else 0.0,
        "direct_answer_control_failures": len(control_failures),
    }
    return {"surface": key, "available": True, "summary": summary, "cases": cases, "direct_answer_controls": control_checks}


def unavailable_surface(key: str, reason: str) -> dict[str, Any]:
    return {
        "surface": key,
        "available": False,
        "unavailable_reason": reason,
        "summary": {
            "status": "unavailable",
            "case_count": 0,
            "pass_count": 0,
            "weighted_pass_rate": None,
            "direct_answer_control_failures": None,
        },
        "cases": [],
        "direct_answer_controls": [],
    }


def _surface_requires_auth(surface: SurfaceConfig | dict[str, Any]) -> bool:
    if isinstance(surface, dict):
        return bool(surface.get("requires_auth"))
    return bool(surface.requires_auth)


def _surface_auth_groups(configs: list[SurfaceConfig | dict[str, Any]], surfaces: list[dict[str, Any]]) -> dict[str, Any]:
    auth_by_key = {config_key(config): _surface_requires_auth(config) for config in configs}
    public = [surface for surface in surfaces if not auth_by_key.get(str(surface.get("surface")), False)]
    authenticated = [surface for surface in surfaces if auth_by_key.get(str(surface.get("surface")), False)]

    def group_payload(group: list[dict[str, Any]]) -> dict[str, Any]:
        unavailable = [surface for surface in group if not surface.get("available")]
        failing = [
            surface
            for surface in group
            if surface.get("available") and (surface.get("summary") or {}).get("status") != "target_met"
        ]
        return {
            "surface_count": len(group),
            "target_met_surface_count": sum(
                1 for surface in group if (surface.get("summary") or {}).get("status") == "target_met"
            ),
            "passed": bool(group) and not unavailable and not failing,
            "unavailable_surfaces": [{"surface": item["surface"], "reason": item.get("unavailable_reason")} for item in unavailable],
            "failing_surfaces": [{"surface": item["surface"], "summary": item.get("summary")} for item in failing],
        }

    return {
        "public_surfaces": group_payload(public),
        "authenticated_surfaces": group_payload(authenticated),
    }


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    load_dotenv_file(ROOT / ".env")
    load_dotenv_file(ROOT / "tmp_remote_mim" / ".env")
    load_dotenv_file(Path(args.agentmim_env))
    suite = load_json(Path(args.suite))
    cards = [card for card in suite.get("scenario_cards", []) if isinstance(card, dict)]
    run_id = datetime.now(timezone.utc).strftime("mim-cross-surface-%Y%m%dT%H%M%SZ")
    configs = surface_configs(args)
    surfaces = [run_surface(config, cards, args, run_id) for config in configs]
    unavailable = [surface for surface in surfaces if not surface.get("available")]
    failing = [
        surface
        for surface in surfaces
        if surface.get("available") and (surface.get("summary") or {}).get("status") != "target_met"
    ]
    report = {
        "packet_type": "mim-structural-reasoning-cross-surface-scorecard-v1",
        "objective_id": "MIM-STRUCTURAL-REASONING-CROSS-SURFACE-PROPAGATION-V1",
        "generated_at": utc_now(),
        "suite_path": str(Path(args.suite)),
        "status": "target_met" if not unavailable and not failing else "blocked" if unavailable else "needs_training",
        "target_weighted_pass_rate_per_surface": SURFACE_TARGET,
        "surface_count": len(surfaces),
        "target_met_surface_count": sum(1 for item in surfaces if (item.get("summary") or {}).get("status") == "target_met"),
        "auth_surface_groups": _surface_auth_groups(configs, surfaces),
        "unavailable_surfaces": [{"surface": item["surface"], "reason": item.get("unavailable_reason")} for item in unavailable],
        "failing_surfaces": [{"surface": item["surface"], "summary": item.get("summary")} for item in failing],
        "surfaces": surfaces,
        "next_action": {
            "recommended_action": "Patch any surface below 90% at its own live response entrypoint; do not accept a blended pass.",
            "owner": "MIM + TOD",
            "expected_evidence": "Per-surface scorecard with every MIM-facing surface at weighted_pass_rate >= 0.90 and direct-answer controls passing.",
            "aging_rule": "Rerun after every prompt/router change and before Dave leaves connectivity.",
            "dave_needed": "no unless authenticated AgentMIM credentials or Studio access are unavailable.",
        },
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    if args.markdown_output:
        write_markdown(Path(args.markdown_output), report)
    return report


def write_markdown(path: Path, report: dict[str, Any]) -> None:
    lines = [
        "# MIM Structural Reasoning Cross-Surface Scorecard",
        "",
        f"Generated: {report['generated_at']}",
        f"Status: {report['status']}",
        f"Target per surface: {report['target_weighted_pass_rate_per_surface']}",
        f"Target-met surfaces: {report['target_met_surface_count']}/{report['surface_count']}",
        f"Public surfaces passed: {(report.get('auth_surface_groups') or {}).get('public_surfaces', {}).get('passed')}",
        f"Authenticated surfaces passed: {(report.get('auth_surface_groups') or {}).get('authenticated_surfaces', {}).get('passed')}",
        "",
        "## Surface Results",
        "",
    ]
    for surface in report["surfaces"]:
        summary = surface.get("summary") or {}
        if not surface.get("available"):
            lines.append(f"- {surface['surface']}: unavailable ({surface.get('unavailable_reason')})")
            continue
        lines.append(
            f"- {surface['surface']}: {summary.get('status')} | weighted {summary.get('weighted_pass_rate')} | "
            f"score {summary.get('weighted_structural_score')}/10 | direct-answer failures {summary.get('direct_answer_control_failures')}"
        )
    lines.extend(["", "## Failed Cases", ""])
    any_failure = False
    for surface in report["surfaces"]:
        failures = [case for case in surface.get("cases") or [] if not case.get("passed")]
        control_failures = [case for case in surface.get("direct_answer_controls") or [] if not case.get("passed")]
        if not failures and not control_failures:
            continue
        any_failure = True
        lines.append(f"### {surface['surface']}")
        for case in failures[:12]:
            lines.append(f"- {case.get('scenario_id')}: {', '.join(case.get('failures') or [])}")
        for case in control_failures:
            lines.append(f"- {case.get('control_id')}: {', '.join(case.get('failures') or [])}")
    if not any_failure:
        lines.append("- none")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--markdown-output", default=str(DEFAULT_MARKDOWN_OUTPUT))
    parser.add_argument("--mimtod-base-url", default=os.getenv("MIMTOD_BASE_URL", "https://mimtod.com"))
    parser.add_argument("--agentmim-base-url", default=os.getenv("AGENTMIM_BASE_URL", "https://www.agentmim.com"))
    parser.add_argument("--studio-base-url", default=os.getenv("MIM_STUDIO_BASE_URL", "https://mimtod.com"))
    parser.add_argument("--agentmim-env", default=os.getenv("AGENTMIM_ENV_PATH", r"E:\comm_app\app\.env"))
    parser.add_argument("--agentmim-username", default=None)
    parser.add_argument("--agentmim-password", default=None)
    parser.add_argument("--agentmim-cookie", default=None)
    parser.add_argument("--agentmim-test-auth-token", default=None)
    parser.add_argument("--studio-test-token", default=None)
    parser.add_argument("--studio-username", default=None)
    parser.add_argument("--studio-password", default=None)
    parser.add_argument("--timeout", type=int, default=75)
    args = parser.parse_args()
    report = build_report(args)
    print(
        json.dumps(
            {
                "status": report["status"],
                "target_met_surface_count": report["target_met_surface_count"],
                "surface_count": report["surface_count"],
                "unavailable_surfaces": report["unavailable_surfaces"],
                "failing_surfaces": report["failing_surfaces"],
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
