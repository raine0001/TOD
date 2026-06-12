from __future__ import annotations

import argparse
import http.cookiejar
import json
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from run_public_mim_general_conversation_smoke import _score_reply


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SUITE = REPO_ROOT / "tod" / "conversation_eval" / "public_mim_customer_conversation_suite_v1.json"
DEFAULT_OUTPUT = REPO_ROOT / "shared_state" / "conversation_eval" / "universal_mim_customer_conversation_smoke.latest.json"
DEFAULT_MARKDOWN_OUTPUT = REPO_ROOT / "runtime_remote_training" / "UNIVERSAL_MIM_CUSTOMER_CONVERSATION_SMOKE_V1.latest.md"

SURFACE_WEIGHTS = {
    "mimtod_public_chat": 0.25,
    "agentmim_login_sales_chat": 0.2,
    "agentmim_logged_in_assistant": 0.2,
    "agentmim_upload_commission_assistant": 0.2,
    "agentmim_project_workspace_assistant": 0.15,
}

INTERNAL_JARGON_MARKERS = (
    "mim-request-",
    "mim_tod_",
    "tod_result_artifacts",
    "objective id",
    "artifact id",
    "dispatcher state",
    "lifecycle",
)


@dataclass
class SurfaceConfig:
    key: str
    kind: str
    base_url: str
    context: str = "workspace"
    requires_auth: bool = False
    page_context: dict[str, Any] | None = None


class SurfaceClient:
    def __init__(
        self,
        config: SurfaceConfig,
        *,
        timeout: int,
        agentmim_username: str | None = None,
        agentmim_password: str | None = None,
        agentmim_cookie: str | None = None,
    ) -> None:
        self.config = config
        self.timeout = timeout
        self.agentmim_username = agentmim_username
        self.agentmim_password = agentmim_password
        self.agentmim_cookie = agentmim_cookie
        self.cookie_jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookie_jar))
        self.csrf_token = ""
        self.available = True
        self.unavailable_reason = ""

    def bootstrap(self) -> None:
        if self.config.kind == "mimtod_public":
            return
        self._bootstrap_agentmim()

    def _open(self, request: urllib.request.Request):
        return self.opener.open(request, timeout=self.timeout)

    def _agentmim_url(self, path: str) -> str:
        return self.config.base_url.rstrip("/") + path

    def _extract_csrf(self, html: str) -> str:
        patterns = [
            r'name="csrf_token"[^>]*value="([^"]+)"',
            r"const\s+salesCsrfToken\s*=\s*\"([^\"]*)\"",
        ]
        for pattern in patterns:
            match = re.search(pattern, html)
            if match:
                return match.group(1)
        return ""

    def _seed_cookie_header(self, request: urllib.request.Request) -> None:
        if self.agentmim_cookie:
            request.add_header("Cookie", self.agentmim_cookie)

    def _bootstrap_agentmim(self) -> None:
        login_url = self._agentmim_url("/login")
        request = urllib.request.Request(login_url, headers={"User-Agent": "MIM universal smoke/1.0"})
        self._seed_cookie_header(request)
        try:
            with self._open(request) as response:
                html = response.read().decode("utf-8", errors="replace")
        except Exception as exc:  # noqa: BLE001
            self.available = False
            self.unavailable_reason = f"bootstrap_error:{type(exc).__name__}"
            return
        self.csrf_token = self._extract_csrf(html)
        if not self.csrf_token:
            self.available = False
            self.unavailable_reason = "csrf_not_found"
            return
        if not self.config.requires_auth:
            return
        if self.agentmim_cookie:
            return
        if not self.agentmim_username or not self.agentmim_password:
            self.available = False
            self.unavailable_reason = "auth_required"
            return
        form = urllib.parse.urlencode(
            {
                "csrf_token": self.csrf_token,
                "username": self.agentmim_username,
                "password": self.agentmim_password,
                "remember_me": "y",
                "submit": "Sign In",
            }
        ).encode("utf-8")
        login_request = urllib.request.Request(
            login_url,
            data=form,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Referer": login_url,
                "Origin": self.config.base_url.rstrip("/"),
                "User-Agent": "MIM universal smoke/1.0",
            },
            method="POST",
        )
        try:
            with self._open(login_request) as response:
                final_url = response.geturl()
                html = response.read().decode("utf-8", errors="replace")
        except Exception as exc:  # noqa: BLE001
            self.available = False
            self.unavailable_reason = f"login_error:{type(exc).__name__}"
            return
        if "/login" in final_url and "Invalid username or password" in html:
            self.available = False
            self.unavailable_reason = "login_failed"

    def post_turn(self, session_key: str, message: str) -> str:
        if self.config.kind == "mimtod_public":
            return self._post_mimtod_public(session_key, message)
        return self._post_agentmim(message)

    def _post_mimtod_public(self, session_key: str, message: str) -> str:
        payload = json.dumps(
            {"message": message, "mode": "mim", "session_key": session_key},
            ensure_ascii=False,
        ).encode("utf-8")
        request = urllib.request.Request(
            self.config.base_url.rstrip("/") + "/public/chat/message",
            data=payload,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )
        with self._open(request) as response:
            data = json.loads(response.read().decode("utf-8"))
        return str((data.get("reply") or {}).get("content") or "").strip()

    def _post_agentmim(self, message: str) -> str:
        payload_data: dict[str, Any] = {
            "message": message,
            "context": self.config.context,
        }
        if self.config.page_context:
            payload_data["page_context"] = self.config.page_context
        payload = json.dumps(payload_data, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            self._agentmim_url("/agent/message"),
            data=payload,
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "X-CSRFToken": self.csrf_token,
                "Referer": self._agentmim_url("/login"),
                "Origin": self.config.base_url.rstrip("/"),
                "User-Agent": "MIM universal smoke/1.0",
            },
            method="POST",
        )
        self._seed_cookie_header(request)
        with self._open(request) as response:
            data = json.loads(response.read().decode("utf-8"))
        return str(data.get("message") or data.get("response") or "").strip()


def _load_suite(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _select_cards(cards: list[dict[str, Any]], count: int, seed: int, sweep: bool) -> list[dict[str, Any]]:
    if sweep:
        return cards[:count]
    rng = random.Random(seed)
    if count >= len(cards):
        selected = list(cards)
        rng.shuffle(selected)
        return selected
    return rng.sample(cards, count)


def _surface_configs(args: argparse.Namespace) -> list[SurfaceConfig]:
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
    project_context = {
        "projectWorkspace": {
            "context_type": "project_workspace",
            "active_project": "customer app prototype",
            "status": "needs next recommended action",
        }
    }
    all_surfaces = {
        "mimtod_public_chat": SurfaceConfig(
            key="mimtod_public_chat",
            kind="mimtod_public",
            base_url=args.mimtod_base_url,
            context="mim",
        ),
        "agentmim_login_sales_chat": SurfaceConfig(
            key="agentmim_login_sales_chat",
            kind="agentmim",
            base_url=args.agentmim_base_url,
            context="sales",
        ),
        "agentmim_logged_in_assistant": SurfaceConfig(
            key="agentmim_logged_in_assistant",
            kind="agentmim",
            base_url=args.agentmim_base_url,
            context="workspace",
            requires_auth=True,
        ),
        "agentmim_upload_commission_assistant": SurfaceConfig(
            key="agentmim_upload_commission_assistant",
            kind="agentmim",
            base_url=args.agentmim_base_url,
            context="workspace",
            requires_auth=True,
            page_context=upload_context,
        ),
        "agentmim_project_workspace_assistant": SurfaceConfig(
            key="agentmim_project_workspace_assistant",
            kind="agentmim",
            base_url=args.agentmim_base_url,
            context="workspace",
            requires_auth=True,
            page_context=project_context,
        ),
    }
    requested = args.surfaces or list(all_surfaces.keys())
    return [all_surfaces[key] for key in requested]


def _score_surface_runs(cards: list[dict[str, Any]], runs: list[dict[str, Any]]) -> dict[str, Any]:
    failure_count = sum(1 for item in runs if not item["passed"])
    category_stats: dict[str, dict[str, Any]] = {}
    cards_by_id = {card.get("id"): card for card in cards}
    for item in runs:
        bucket = str(item.get("bucket") or "unknown")
        stat = category_stats.setdefault(bucket, {"count": 0, "passed": 0, "failed": 0, "weight": 0.0})
        stat["count"] += 1
        card = cards_by_id.get(item.get("scenario_id")) or {}
        stat["weight"] = max(float(stat["weight"]), float(card.get("category_weight") or 0.0))
        if item["passed"]:
            stat["passed"] += 1
        else:
            stat["failed"] += 1
    weighted_total = 0.0
    weighted_score = 0.0
    for stat in category_stats.values():
        stat["pass_rate"] = round(float(stat["passed"]) / max(1, int(stat["count"])), 4)
        if float(stat["weight"]) > 0:
            weighted_total += float(stat["weight"])
            weighted_score += float(stat["weight"]) * float(stat["pass_rate"])
    return {
        "scenario_count": len(runs),
        "passed_count": len(runs) - failure_count,
        "failure_count": failure_count,
        "pass_rate": round((len(runs) - failure_count) / max(1, len(runs)), 4),
        "weighted_pass_rate": round(weighted_score / weighted_total, 4) if weighted_total else None,
        "category_stats": category_stats,
    }


def _has_internal_jargon(reply: str) -> bool:
    lowered = reply.lower()
    return any(marker in lowered for marker in INTERNAL_JARGON_MARKERS)


def run_surface(
    config: SurfaceConfig,
    cards: list[dict[str, Any]],
    *,
    run_id: str,
    timeout: int,
    delay_seconds: float,
    agentmim_username: str | None,
    agentmim_password: str | None,
    agentmim_cookie: str | None,
) -> dict[str, Any]:
    client = SurfaceClient(
        config,
        timeout=timeout,
        agentmim_username=agentmim_username,
        agentmim_password=agentmim_password,
        agentmim_cookie=agentmim_cookie,
    )
    client.bootstrap()
    if not client.available:
        return {
            "surface": config.key,
            "available": False,
            "unavailable_reason": client.unavailable_reason,
            "summary": {
                "scenario_count": 0,
                "passed_count": 0,
                "failure_count": 0,
                "pass_rate": None,
                "weighted_pass_rate": None,
            },
            "runs": [],
        }
    runs: list[dict[str, Any]] = []
    for index, card in enumerate(cards, start=1):
        session_key = f"{run_id}-{config.key}-{index:03d}"
        turns = [str(turn) for turn in card.get("user_turns") or []]
        card_failures: list[str] = []
        turn_results: list[dict[str, Any]] = []
        for turn_index, turn in enumerate(turns):
            try:
                reply = client.post_turn(session_key, turn)
                failures = _score_reply(card, turn, reply, turn_index)
                if _has_internal_jargon(reply):
                    failures.append("internal_jargon_leakage")
            except (OSError, TimeoutError, urllib.error.HTTPError, ValueError) as exc:
                reply = ""
                failures = [f"request_error:{type(exc).__name__}"]
            card_failures.extend(failures)
            turn_results.append({"turn": turn, "reply": reply, "failures": failures})
            if delay_seconds:
                time.sleep(delay_seconds)
        runs.append(
            {
                "scenario_id": card.get("id"),
                "bucket": card.get("bucket"),
                "passed": not card_failures,
                "failures": sorted(set(card_failures)),
                "turns": turn_results,
            }
        )
    return {
        "surface": config.key,
        "available": True,
        "summary": _score_surface_runs(cards, runs),
        "runs": runs,
    }


def _rollup(surface_reports: list[dict[str, Any]]) -> dict[str, Any]:
    available = [report for report in surface_reports if report.get("available")]
    weighted_total = 0.0
    weighted_score = 0.0
    internal_jargon_failures = 0
    for report in available:
        key = str(report.get("surface"))
        weight = SURFACE_WEIGHTS.get(key, 0.0)
        rate = ((report.get("summary") or {}).get("weighted_pass_rate"))
        if isinstance(rate, (int, float)) and weight > 0:
            weighted_total += weight
            weighted_score += weight * float(rate)
        for run in report.get("runs") or []:
            if "internal_jargon_leakage" in (run.get("failures") or []):
                internal_jargon_failures += 1
    unavailable = [report for report in surface_reports if not report.get("available")]
    return {
        "surface_count": len(surface_reports),
        "available_surface_count": len(available),
        "unavailable_surface_count": len(unavailable),
        "unavailable_surfaces": [
            {"surface": report.get("surface"), "reason": report.get("unavailable_reason")}
            for report in unavailable
        ],
        "weighted_pass_rate": round(weighted_score / weighted_total, 4) if weighted_total else None,
        "internal_jargon_failure_count": internal_jargon_failures,
        "success_threshold": 0.95,
        "passes_threshold": bool(weighted_total and weighted_score / weighted_total >= 0.95 and internal_jargon_failures == 0 and not unavailable),
    }


def _write_markdown(path: Path, report: dict[str, Any]) -> None:
    lines = [
        "# Universal MIM Customer Conversation Smoke V1",
        "",
        f"- Generated: {report['generated_at']}",
        f"- Suite: {report['suite_path']}",
        f"- Scenarios per surface: {report['scenario_count_per_surface']}",
        f"- Universal weighted pass rate: {report['rollup'].get('weighted_pass_rate')}",
        f"- Internal jargon failures: {report['rollup'].get('internal_jargon_failure_count')}",
        f"- Passes threshold: {report['rollup'].get('passes_threshold')}",
        "",
        "## Surfaces",
    ]
    for surface in report["surfaces"]:
        summary = surface.get("summary") or {}
        if not surface.get("available"):
            lines.append(f"- {surface['surface']}: unavailable ({surface.get('unavailable_reason')})")
            continue
        lines.append(
            f"- {surface['surface']}: weighted {summary.get('weighted_pass_rate')} "
            f"({summary.get('passed_count')}/{summary.get('scenario_count')} scenarios)"
        )
    lines.extend(["", "## Failures"])
    any_failure = False
    for surface in report["surfaces"]:
        failures = [item for item in surface.get("runs") or [] if not item.get("passed")]
        if not failures:
            continue
        any_failure = True
        lines.append(f"### {surface['surface']}")
        for item in failures[:20]:
            lines.append(f"- {item.get('scenario_id')}: {', '.join(item.get('failures') or [])}")
    if not any_failure:
        lines.append("- none")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_smoke(args: argparse.Namespace) -> dict[str, Any]:
    suite = _load_suite(Path(args.suite))
    cards = _select_cards(list(suite["scenario_cards"]), args.count, args.seed, args.sweep)
    run_id = datetime.now(timezone.utc).strftime("universal-mim-smoke-%Y%m%dT%H%M%SZ")
    surface_reports = []
    for config in _surface_configs(args):
        surface_reports.append(
            run_surface(
                config,
                cards,
                run_id=run_id,
                timeout=args.timeout,
                delay_seconds=args.delay_seconds,
                agentmim_username=args.agentmim_username or os.getenv("AGENTMIM_USERNAME"),
                agentmim_password=args.agentmim_password or os.getenv("AGENTMIM_PASSWORD"),
                agentmim_cookie=args.agentmim_cookie or os.getenv("AGENTMIM_COOKIE"),
            )
        )
    report = {
        "schema_version": "UNIVERSAL-MIM-CUSTOMER-CONVERSATION-SMOKE-V1",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "suite_path": str(Path(args.suite)),
        "scenario_count_per_surface": len(cards),
        "surfaces": surface_reports,
        "rollup": _rollup(surface_reports),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if args.markdown_output:
        _write_markdown(Path(args.markdown_output), report)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", default=str(DEFAULT_SUITE))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--markdown-output", default=str(DEFAULT_MARKDOWN_OUTPUT))
    parser.add_argument("--mimtod-base-url", default=os.getenv("MIMTOD_BASE_URL", "http://192.168.1.120:18001"))
    parser.add_argument("--agentmim-base-url", default=os.getenv("AGENTMIM_BASE_URL", "https://www.agentmim.com"))
    parser.add_argument("--agentmim-username", default=None)
    parser.add_argument("--agentmim-password", default=None)
    parser.add_argument("--agentmim-cookie", default=None)
    parser.add_argument("--surface", dest="surfaces", action="append", choices=sorted(SURFACE_WEIGHTS))
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--seed", type=int, default=20260612)
    parser.add_argument("--timeout", type=int, default=75)
    parser.add_argument("--sweep", action="store_true")
    parser.add_argument("--delay-seconds", type=float, default=0.0)
    args = parser.parse_args()
    report = run_smoke(args)
    print(json.dumps({"rollup": report["rollup"], "surfaces": [s["summary"] | {"surface": s["surface"], "available": s["available"]} for s in report["surfaces"]]}, indent=2))


if __name__ == "__main__":
    main()
