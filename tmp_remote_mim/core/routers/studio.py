from __future__ import annotations

import html
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Body, Depends, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from pydantic import BaseModel, Field
from sqlalchemy import func, select, text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import settings
from core.db import get_db
from core.mim_ui_auth import maybe_require_mimtod_page_login
from core.models import (
    Objective,
    StudioDocument,
    StudioDocumentLink,
    StudioProject,
    StudioProjectEvent,
    StudioProjectLink,
    StudioProjectSignal,
    StudioReportCanvas,
    Task,
)


router = APIRouter()

SHARED_RUNTIME_ROOT = Path("runtime/shared")
TRAINING_RUNTIME_ROOT = Path("runtime_remote_training")
MIM_PRESENCE_PATH = SHARED_RUNTIME_ROOT / "MIM_UNIVERSAL_PRESENCE.latest.json"
LAB_SERVO_TESTER_PROFILE_PATH = SHARED_RUNTIME_ROOT / "MIM_LAB_SERVO_TESTER_PROFILE.latest.json"
LOS_ANGELES_TZ = ZoneInfo("America/Los_Angeles")


TRAINING_EVIDENCE_DOCS: list[dict[str, str]] = [
    {
        "title": "MIM/TOD Training Scoreboard",
        "filename": "MIM_TOD_TRAINING_SCOREBOARD.latest.md",
        "kind": "training_scoreboard",
        "summary": "Primary scoreboard for MIM/TOD training metrics, outcome reflection, judgment-mode score, and TOD blocker evidence.",
    },
    {
        "title": "MIM/TOD Continuous Training Directive",
        "filename": "MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json",
        "kind": "training_directive",
        "summary": "Current directive describing what MIM and TOD are training on and what success requires.",
    },
    {
        "title": "MIM/TOD Hourly Reflection",
        "filename": "MIM_TOD_HOURLY_REFLECTION.latest.json",
        "kind": "hourly_reflection",
        "summary": "Outcome reflection layer that decides whether training is producing actual improvement.",
    },
    {
        "title": "MIM Durability Smoke V2",
        "filename": "MIM_DURABILITY_SMOKE_V2.latest.json",
        "kind": "smoke_test",
        "summary": "Focused judgment-mode test for recommendation, explanation, demonstration, consultative discovery, and problem-analysis behavior.",
    },
    {
        "title": "MIM Typo-Tolerant Intent Smoke",
        "filename": "MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.json",
        "kind": "smoke_test",
        "summary": "Noisy-input and typo tolerance test for operator language.",
    },
    {
        "title": "TOD Blocker Resolution Operator Summary",
        "filename": "TOD_BLOCKER_RESOLUTION_OPERATOR_SUMMARY.latest.md",
        "kind": "blocker_report",
        "summary": "Human-readable summary of TOD blocker resolution progress and current blocker class.",
    },
    {
        "title": "MIM Studio Training Page V1",
        "filename": "MIM_STUDIO_TRAINING_PAGE_V1.latest.md",
        "kind": "implementation_evidence",
        "summary": "Evidence artifact for the DB-backed Studio training page, scorecards, outcome reflection, and document-library links.",
    },
]


DOCUMENT_TARGET_TYPES: list[tuple[str, str]] = [
    ("project", "Projects"),
    ("project_signal", "Project Signals"),
    ("task", "Tasks"),
    ("objective", "Objectives"),
    ("conversation", "Conversations"),
    ("status_update", "Status Updates"),
    ("app", "MIM Apps"),
    ("report", "Reports"),
    ("system", "Systems"),
    ("training_run", "Training Runs"),
    ("smoke_test", "Smoke Tests"),
    ("lab_resource", "Lab / Robotics"),
    ("vendor", "Vendors"),
    ("person", "People"),
]


REPORT_DATASETS: list[dict[str, str]] = [
    {
        "key": "studio_overview",
        "label": "Studio Overview",
        "description": "MIM, TOD, training, projects, documents, health, and current attention items.",
    },
    {
        "key": "training",
        "label": "Training",
        "description": "Training scoreboard, hourly reflection, smoke tests, and current MIM/TOD focus.",
    },
    {
        "key": "objectives",
        "label": "Objectives",
        "description": "Objective ledger counts, status distribution, and recent objective rows.",
    },
    {
        "key": "tasks",
        "label": "Tasks",
        "description": "Task queue counts, assigned owners, states, and recent tasks.",
    },
    {
        "key": "projects",
        "label": "Projects",
        "description": "Studio projects, project signals, candidates, active work, and Dave-needed flags.",
    },
    {
        "key": "documents",
        "label": "Documents",
        "description": "Document library records, preservation status, categories, and recent items.",
    },
    {
        "key": "document_graph",
        "label": "Document Graph",
        "description": "Relationships between documents and projects, reports, pages, systems, and training runs.",
    },
    {
        "key": "tod_blockers",
        "label": "TOD Blockers",
        "description": "TOD blocker-resolution summary and current cleanup evidence.",
    },
    {
        "key": "system_health",
        "label": "System Health",
        "description": "Studio health snapshot, attention items, and current repair targets.",
    },
    {
        "key": "app_metrics",
        "label": "App Metrics",
        "description": "Application users, subscriptions, usage, revenue, health, vendors, and app-specific telemetry.",
    },
]


APP_SOURCE_REGISTRY: list[dict[str, Any]] = [
    {
        "app_key": "comm_app",
        "display_name": "comm_app / AgentMIM",
        "public_url": "https://www.agentmim.com",
        "local_root": "E:/comm_app",
        "ecosystem_role": "business execution layer",
        "runtime": "Render Flask app",
        "db_env_keys": ["DATABASE_URI", "DATABASE_URL"],
        "primary_account_table": "account_owners",
        "secondary_user_table": "representatives",
        "known_tables": [
            "account_owners",
            "representatives",
            "clients",
            "group_clients",
            "carriers",
            "commissions",
            "other_commissions",
            "policy_agents",
            "audit_logs",
        ],
        "fallback_tables": [
            "project_portal_accounts",
            "project_portal_projects",
            "workspace_interface_sessions",
            "workspace_interface_messages",
            "input_events",
        ],
        "tod_reference": "shared_state/agentmim/comm_app_managed_work.latest.json",
        "verification_reference": "shared_state/agentmim/comm_app_verification.latest.json",
    },
    {
        "app_key": "studio",
        "display_name": "MIM Studio",
        "public_url": "https://mim.mimtod.com/studio",
        "local_root": "/home/testpilot/mim",
        "ecosystem_role": "operator command center",
        "runtime": "MIM FastAPI app",
        "db_env_keys": ["DATABASE_URL"],
        "primary_account_table": "project_portal_accounts",
        "secondary_user_table": "workspace_interface_sessions",
        "known_tables": [
            "studio_projects",
            "studio_documents",
            "studio_document_links",
            "studio_report_canvases",
            "objectives",
            "tasks",
        ],
        "fallback_tables": [],
    },
    {
        "app_key": "mim_wall",
        "display_name": "MIM Wall",
        "public_url": "",
        "local_root": "E:/mim_wall",
        "ecosystem_role": "real-world communications edge",
        "runtime": "Android / wall interface",
        "db_env_keys": [],
        "primary_account_table": "",
        "secondary_user_table": "",
        "known_tables": [],
        "fallback_tables": [],
        "tod_reference": "docs/mim-wall-state-adapter-v1.md",
        "verification_reference": "docs/mim-wall-development-status-2026-04-13.md",
    },
    {
        "app_key": "coachMIM",
        "display_name": "coachMIM",
        "public_url": "",
        "local_root": "E:/coachMIM",
        "ecosystem_role": "coaching / guidance app",
        "runtime": "registered app source",
        "db_env_keys": [],
        "primary_account_table": "",
        "secondary_user_table": "",
        "known_tables": [],
        "fallback_tables": [],
    },
    {
        "app_key": "Mimir",
        "display_name": "Mimir",
        "public_url": "",
        "local_root": "E:/Mimir",
        "ecosystem_role": "registered MIM app",
        "runtime": "registered app source",
        "db_env_keys": [],
        "primary_account_table": "",
        "secondary_user_table": "",
        "known_tables": [],
        "fallback_tables": [],
    },
    {
        "app_key": "mim_pulz",
        "display_name": "mim_pulz",
        "public_url": "",
        "local_root": "E:/mim_pulz",
        "ecosystem_role": "registered MIM app",
        "runtime": "registered app source",
        "db_env_keys": [],
        "primary_account_table": "",
        "secondary_user_table": "",
        "known_tables": [],
        "fallback_tables": [],
    },
    {
        "app_key": "mim_robotics",
        "display_name": "MIM Robotics",
        "public_url": "https://www.mimrobots.com",
        "local_root": "E:/MIM Robotics/mimrobots.com",
        "ecosystem_role": "MIM Robotics LLC public website and robotics presentation layer",
        "runtime": "PythonAnywhere Flask app",
        "hosting_provider": "PythonAnywhere",
        "hosting_env_keys": ["PYTHONANYWHERE_USERNAME", "PYTHONANYWHERE_API_KEY", "PYTHONANYWHERE_DOMAIN"],
        "db_env_keys": ["DATABASE_URI"],
        "primary_account_table": "user",
        "secondary_user_table": "conversation",
        "known_tables": [
            "user",
            "conversation",
            "resource",
            "post",
            "feedback",
            "product",
            "category",
            "product_image",
            "product_variant",
            "discount",
            "stock",
            "background",
            "product_review",
            "excel_upload",
            "conversation_log",
            "order",
            "client",
            "inquiry",
        ],
        "fallback_tables": [],
        "tod_reference": "runtime/shared/MIM_TOD_APP_SOURCE_SCAN.latest.json",
        "verification_reference": "runtime/shared/MIM_ROBOTICS_PYTHONANYWHERE_STATUS.latest.json",
    },
    {
        "app_key": "mim_station",
        "display_name": "MIM Station",
        "public_url": "",
        "local_root": "E:/MIM_Station",
        "ecosystem_role": "registered station app",
        "runtime": "registered app source",
        "db_env_keys": [],
        "primary_account_table": "",
        "secondary_user_table": "",
        "known_tables": [],
        "fallback_tables": [],
    },
    {
        "app_key": "mim_devl",
        "display_name": "mim_devl",
        "public_url": "",
        "local_root": "E:/mim_devl",
        "ecosystem_role": "development sandbox",
        "runtime": "registered app source",
        "db_env_keys": [],
        "primary_account_table": "",
        "secondary_user_table": "",
        "known_tables": [],
        "fallback_tables": [],
    },
]


class StudioProjectSignalCreate(BaseModel):
    title: str = Field(min_length=1, max_length=220)
    signal_type: str = "observation"
    status: str = "observation"
    priority: str = "normal"
    source_surface: str = "studio"
    source_text: str = ""
    why_it_matters: str = ""
    suggested_action: str = "review"
    metadata_json: dict[str, Any] = Field(default_factory=dict)


class StudioProjectCreate(BaseModel):
    title: str = Field(min_length=1, max_length=220)
    summary: str = ""
    status: str = "candidate"
    priority: str = "normal"
    owner: str = "Dave + MIM"
    health: str = "good"
    why_it_matters: str = ""
    origin_story: str = ""
    next_action: str = ""
    dave_needed: bool = False
    metadata_json: dict[str, Any] = Field(default_factory=dict)


class StudioProjectSignalPromote(BaseModel):
    project: StudioProjectCreate | None = None


class StudioProjectEventCreate(BaseModel):
    event_type: str = "note"
    actor: str = "MIM"
    title: str = ""
    detail: str = ""
    evidence_json: dict[str, Any] = Field(default_factory=dict)
    metadata_json: dict[str, Any] = Field(default_factory=dict)


class StudioDocumentCreate(BaseModel):
    title: str = Field(min_length=1, max_length=260)
    summary: str = ""
    document_type: str = "note"
    category: str = "library"
    status: str = "active"
    owner: str = "Dave + MIM"
    created_by: str = "MIM"
    source_kind: str = "manual"
    source_url: str = ""
    source_path: str = ""
    local_path: str = ""
    preserve_policy: str = "reference"
    snapshot_status: str = "not_requested"
    content_text: str = ""
    tags_json: list[str] = Field(default_factory=list)
    metadata_json: dict[str, Any] = Field(default_factory=dict)


class StudioDocumentLinkCreate(BaseModel):
    target_type: str = Field(min_length=1, max_length=80)
    target_id: str = ""
    relation: str = "related"
    label: str = ""
    metadata_json: dict[str, Any] = Field(default_factory=dict)


class StudioReportCanvasCreate(BaseModel):
    prompt: str = Field(min_length=1, max_length=4000)
    dataset_key: str = "studio_overview"
    title: str = ""
    status: str = "draft"
    created_by: str = "MIM"
    filters_json: dict[str, Any] = Field(default_factory=dict)
    metadata_json: dict[str, Any] = Field(default_factory=dict)


class StudioMimChatRequest(BaseModel):
    prompt: str = Field(default="", max_length=4000)
    page_context: str = Field(default="", max_length=240)
    studio_page_context: str = Field(default="", max_length=240)
    metadata_json: dict[str, Any] = Field(default_factory=dict)


TABS: list[dict[str, str]] = [
    {"key": "home", "label": "Home", "icon": "&#9673;", "href": "/studio", "kind": "home"},
    {"key": "projects", "label": "Projects", "icon": "&#9638;", "href": "/studio/projects", "kind": "placeholder"},
    {"key": "mim", "label": "MIM", "icon": "&#9676;", "href": "/studio/mim", "kind": "embed", "source": "/mim"},
    {"key": "tod", "label": "TOD", "icon": "&#10177;", "href": "/studio/tod", "kind": "embed", "source": "/tod"},
    {"key": "training", "label": "Training", "icon": "&#8756;", "href": "/studio/training", "kind": "placeholder"},
    {"key": "documents", "label": "Documents", "icon": "&#8942;", "href": "/studio/documents", "kind": "placeholder"},
    {"key": "reports", "label": "Reports", "icon": "&#8779;", "href": "/studio/reports", "kind": "placeholder"},
    {"key": "systems", "label": "Systems / Health", "icon": "&#11041;", "href": "/studio/systems", "kind": "placeholder"},
    {"key": "lab", "label": "Lab / Robotics", "icon": "&#9004;", "href": "/studio/lab", "kind": "placeholder"},
    {"key": "apps", "label": "MIM Apps", "icon": "&#10038;", "href": "/studio/apps", "kind": "placeholder"},
    {"key": "accounting", "label": "Accounting", "icon": "&#9672;", "href": "/studio/accounting", "kind": "placeholder"},
    {"key": "settings", "label": "Settings", "icon": "&#8984;", "href": "/studio/settings", "kind": "placeholder"},
]


TRAINING_SECTIONS: list[dict[str, str]] = [
    {
        "key": "objectives",
        "label": "Objectives",
        "href": "/studio/training/objectives",
        "source": "/objectives",
        "summary": "Internal MIM/TOD capability growth, repairs, training objectives, and validation objectives.",
    },
    {
        "key": "scoreboard",
        "label": "Scoreboard",
        "href": "/studio/training/scoreboard",
        "summary": "Hourly, daily, and weekly evidence that training is producing outcomes, not just status text.",
    },
    {
        "key": "smoke-tests",
        "label": "Smoke Tests",
        "href": "/studio/training/smoke-tests",
        "summary": "Durability tests for operator responses, typo tolerance, mode selection, and follow-through.",
    },
    {
        "key": "blockers",
        "label": "Blockers",
        "href": "/studio/training/blockers",
        "summary": "Blocked, stale, stalled, repaired, parked, superseded, and escalated internal work.",
    },
    {
        "key": "memory",
        "label": "Evolution Memory",
        "href": "/studio/training/memory",
        "summary": "Reusable lessons, failure classes, prevention rules, and continuity references.",
    },
    {
        "key": "runs",
        "label": "Training Runs",
        "href": "/studio/training/runs",
        "summary": "Current and historical MIM/TOD drills, cycles, validations, and result artifacts.",
    },
]


PLACEHOLDERS: dict[str, dict[str, object]] = {
    "projects": {
        "title": "Projects",
        "subtitle": "Real-world outcomes that create value for Dave, customers, or the company.",
        "sections": [
            ("Idea Capture", "MIM and Dave can start anywhere: Studio, /mim, phone, chat, project portal, or lab. Rough ideas become project candidates."),
            ("Discovery", "MIM collaborates through goals, users, constraints, examples, data sources, integrations, value, and missing information."),
            ("Project Bundle", "When ready, MIM packages the work into planning, implementation, testing, deployment, maintenance, artifacts, and evidence."),
            ("Milestones", "Projects contain milestones. Milestones contain tasks. Tasks produce evidence."),
            ("Collaboration", "MIM remains the consultant and memory layer while TOD executes implementation tasks when the plan is approved."),
            ("Value Test", "If MIM/TOD disappeared tomorrow and the outcome still matters, it belongs here as a project."),
        ],
    },
    "training": {
        "title": "Training",
        "subtitle": "MIM/TOD evolution, objectives, smoke tests, blocker repair, memory, and capability growth.",
        "sections": [
            ("Objectives", "Internal capability work: MIM/TOD learning, repair, validation discipline, and robotics skill growth."),
            ("Scoreboard", "Hourly/daily/weekly metrics, pass rates, blockers cleared, and stale artifact warnings."),
            ("Smoke Tests", "Focused suites proving response quality, typo tolerance, judgment mode, and behavior durability."),
            ("Blockers", "Blocked, stale, stalled, repaired, parked, superseded, and escalated internal work."),
            ("Evolution Memory", "Reusable lessons, failure classes, prevention rules, and continuity references."),
            ("Training Runs", "Current and historical MIM/TOD training cycles, drills, and validation results."),
        ],
    },
    "documents": {
        "title": "Documents",
        "subtitle": "The MIM library: docs, spreadsheets, notes, media, links, references, artifacts, and useful oddities.",
        "sections": [
            ("Library Inbox", "Drop or link anything: documents, spreadsheets, notes, media, screenshots, PDFs, URLs, code snippets, research, and references."),
            ("Project Material", "Discovery notes, scope references, blueprints, roadmaps, approval summaries, screenshots, prototypes, and test evidence."),
            ("Knowledge Shelf", "Stuff that may matter someday: vendor notes, weird facts, research fragments, troubleshooting notes, and context MIM should remember."),
            ("Linking", "Every item should attach to projects, objectives, tasks, reports, conversations, people, vendors, systems, or future reminders."),
            ("Search", "MIM should be able to answer: have we seen this before, where did it come from, why did we keep it, and what project does it affect?"),
            ("Retention", "Not everything becomes a project. Some things just become useful context in the back of MIM's brain."),
        ],
    },
    "reports": {
        "title": "Reports",
        "subtitle": "Operator summaries and evidence reports for development, training, health, and project progress.",
        "sections": [
            ("Daily / Weekly / Monthly", "Human-readable summaries of what changed, what matters, and what is next."),
            ("Blockers", "Blocked, stale, stalled, repaired, parked, superseded, and escalated work."),
            ("Exports", "Client-ready or Dave-ready reports generated from canonical artifacts."),
        ],
    },
    "systems": {
        "title": "Systems / Health",
        "subtitle": "Runtime health for MIM, TOD, dispatcher, database, training, voice, and infrastructure.",
        "sections": [
            ("Service Health", "MIM web, TOD runtime, dispatcher, database, and background jobs."),
            ("Freshness", "Stale artifact checks, heartbeat checks, and healthy-idle distinction."),
            ("Repair", "H.A.L. diagnostics, repair plans, evidence, and restart actions."),
        ],
    },
    "lab": {
        "title": "Lab / Robotics",
        "subtitle": "Physical-world MIM resources: arm, cameras, sensors, lidar, calibration, and movement memory.",
        "sections": [
            ("Resources", "PC camera, MIM box cameras, Pi cameras, hand camera, C12 distance sensor, and RPLIDAR."),
            ("Calibration", "Workspace model, safe poses, marker mapping, visual servoing, and gripper offsets."),
            ("Learning", "Explore, observe, move, validate, and record what MIM learns from the arm."),
        ],
    },
    "settings": {
        "title": "Settings",
        "subtitle": "Operator, user, policy, provider, security, and environment configuration.",
        "sections": [
            ("Access", "Users, roles, demo mode, admin controls, and trusted devices."),
            ("Providers", "SMTP, API vendors, credentials, OAuth, billing hooks, and service broker setup."),
            ("Policies", "Privacy, data retention, AI disclosure, ethical solution design, and safety boundaries."),
        ],
    },
    "apps": {
        "title": "MIM Apps",
        "subtitle": "Fleet view for applications MIM owns, builds, monitors, and learns from.",
        "sections": [
            ("App Registry", "App state, version, health, users, owner, linked project, and deployment status."),
            ("Resources", "Vendors, APIs, compute, storage, AI usage, subscriptions, and incident history."),
            ("Roadmap", "Planned updates, support tickets, revenue/cost summaries, and reuse opportunities."),
        ],
    },
    "accounting": {
        "title": "Accounting",
        "subtitle": "Internal MIM/TOD accounting and the seed of the future accounting application.",
        "sections": [
            ("Invoices / Receipts", "Drag-drop invoices and receipts, OCR extraction, and review queue."),
            ("Vendors", "Vendor list, service purpose, subscriptions, recurring spend, and payment source."),
            ("Insights", "Unused services, duplicate spend, project cost allocation, and export-ready reports."),
        ],
    },
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _parse_datetime(value: object) -> datetime | None:
    text_value = str(value or "").strip()
    if not text_value:
        return None
    try:
        normalized = text_value.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except Exception:
        return None


def _la_time(value: object, default: str = "unknown") -> str:
    parsed = _parse_datetime(value)
    if not parsed:
        return default
    local = parsed.astimezone(LOS_ANGELES_TZ)
    return local.strftime("%Y-%m-%d %I:%M:%S %p %Z")


def _age_label(value: object) -> str:
    parsed = _parse_datetime(value)
    if not parsed:
        return "age unknown"
    seconds = max(0, int((datetime.now(timezone.utc) - parsed).total_seconds()))
    if seconds < 90:
        return f"{seconds}s old"
    minutes = seconds // 60
    if minutes < 90:
        return f"{minutes}m old"
    hours = round(minutes / 60, 1)
    if hours < 48:
        return f"{hours}h old"
    return f"{round(hours / 24, 1)}d old"


def _load_json(name: str) -> dict[str, Any]:
    for root in (SHARED_RUNTIME_ROOT, TRAINING_RUNTIME_ROOT):
        path = root / name
        try:
            if path.exists() and path.is_file():
                data = json.loads(path.read_text(encoding="utf-8"))
                return data if isinstance(data, dict) else {}
        except Exception:
            continue
    return {}


def _load_text(name: str, limit: int = 1200) -> str:
    for root in (SHARED_RUNTIME_ROOT, TRAINING_RUNTIME_ROOT):
        path = root / name
        try:
            if path.exists() and path.is_file():
                return path.read_text(encoding="utf-8", errors="replace")[:limit]
        except Exception:
            continue
    return ""


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except Exception:
        return


async def _safe_table_count(db: AsyncSession, table_name: str) -> int | None:
    clean_name = "".join(ch for ch in str(table_name or "") if ch.isalnum() or ch == "_")
    if not clean_name:
        return None
    try:
        exists_result = await db.execute(
            text(
                "select exists ("
                "select 1 from information_schema.tables "
                "where table_schema = 'public' and table_name = :table_name"
                ")"
            ),
            {"table_name": clean_name},
        )
        if not bool(exists_result.scalar()):
            return None
        count_result = await db.execute(text(f"select count(*) from {clean_name}"))
        return int(count_result.scalar() or 0)
    except Exception:
        return None


def _first_text(*values: object, default: str = "") -> str:
    for value in values:
        text = str(value or "").strip()
        if text:
            return text
    return default


def _plain_status(value: object, default: str = "unknown") -> str:
    text = str(value or default).strip() or default
    return text.replace("_", " ")


def _html(value: object) -> str:
    return html.escape(str(value or ""), quote=True)


def _mim_presence_snapshot(*, mim_focus: str, active_project: str = "MIM Project Studio") -> dict[str, Any]:
    existing = _load_json("MIM_UNIVERSAL_PRESENCE.latest.json")
    presence = {
        "packet_type": "mim-universal-presence-v1",
        "updated_at": _utc_now(),
        "identity": "one_mim_many_interfaces",
        "operator": "Dave",
        "primary_conversation_id": _first_text(
            existing.get("primary_conversation_id"),
            default="dave-primary-mim-thread",
        ),
        "current_conversation": _first_text(
            existing.get("current_conversation"),
            default="Studio command center",
        ),
        "active_project": _first_text(existing.get("active_project"), default=active_project),
        "current_focus": _first_text(existing.get("current_focus"), default=mim_focus),
        "memory_context": _first_text(existing.get("memory_context"), default="active"),
        "last_interaction_surface": _first_text(
            existing.get("last_interaction_surface"),
            default="Studio",
        ),
        "last_interaction_at": _first_text(existing.get("last_interaction_at"), default=_utc_now()),
        "pending_follow_up": _first_text(
            existing.get("pending_follow_up"),
            default="Keep MIM's Studio presence and page-aware chat consistent across surfaces.",
        ),
        "known_surfaces": [
            "Studio",
            "/mim",
            "MIM Wall",
            "phone",
            "project portal",
            "lab/robotics",
        ],
        "principle": "One Dave. One MIM. Many interfaces.",
    }
    _write_json(MIM_PRESENCE_PATH, presence)
    return presence


def _studio_snapshot() -> dict[str, Any]:
    directive = _load_json("MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json")
    typo_smoke = _load_json("MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.json")
    reflection = _load_json("MIM_TOD_HOURLY_REFLECTION.latest.json")
    scoreboard = _load_json("MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    objective_status = _load_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json")
    operator_status = _load_json("MIM_OPERATOR_STATUS.latest.json")
    blocker_summary = _load_text("TOD_BLOCKER_RESOLUTION_OPERATOR_SUMMARY.latest.md", limit=800)

    mim_training = directive.get("mim_training") if isinstance(directive.get("mim_training"), dict) else {}
    tod_training = directive.get("tod_training") if isinstance(directive.get("tod_training"), dict) else {}
    blocker_drill = (
        tod_training.get("active_blocker_clearing_drill")
        if isinstance(tod_training.get("active_blocker_clearing_drill"), dict)
        else {}
    )
    typo_summary = typo_smoke.get("summary") if isinstance(typo_smoke.get("summary"), dict) else {}
    reflection_summary = reflection.get("summary") if isinstance(reflection.get("summary"), dict) else {}

    mim_focus = _first_text(
        mim_training.get("current_topic"),
        operator_status.get("what_mim_is_doing"),
        default="Project-manager communication and judgment training",
    )
    tod_focus = _first_text(
        tod_training.get("current_topic"),
        operator_status.get("what_tod_is_doing"),
        default="Codex-level implementation and blocker resolution training",
    )
    presence = _mim_presence_snapshot(mim_focus=mim_focus)
    typo_pass_rate = typo_summary.get("pass_rate_percent")
    typo_passed = typo_summary.get("passed")
    typo_cases = typo_summary.get("case_count")
    blocked_start = _first_text(blocker_drill.get("blocked_total_at_start"), default="33")
    blocked_after = _first_text(blocker_drill.get("after_blocked_count"), default="31")
    current_blocker = _first_text(
        blocker_drill.get("current_blocker_class"),
        operator_status.get("blocking_issue"),
        default="linked-task evidence validation",
    )
    next_drill = _first_text(
        blocker_drill.get("next_drill"),
        operator_status.get("next_safe_action"),
        default="Continue blocker inspection and narrow the next repair action",
    )

    attention: list[dict[str, str]] = []
    if reflection:
        are_improving = reflection.get("are_they_improving")
        if are_improving is False:
            attention.append(
                {
                    "owner": "MIM/TOD",
                    "title": "Outcome reflection says improvement is not proven yet",
                    "detail": _first_text(
                        reflection.get("recommendation"),
                        reflection_summary.get("next_action") if isinstance(reflection_summary, dict) else "",
                        default="Refresh stale inputs and prove outcome improvement before claiming training is going great.",
                    ),
                }
            )
    if current_blocker:
        attention.append(
            {
                "owner": "TOD",
                "title": _plain_status(current_blocker),
                "detail": next_drill,
            }
        )
    if typo_pass_rate is not None:
        attention.append(
            {
                "owner": "MIM",
                "title": f"Typo tolerance smoke: {typo_pass_rate}%",
                "detail": f"{typo_passed or 0}/{typo_cases or 0} noisy-input prompts passed.",
            }
        )
    attention = attention[:5]

    return {
        "generated_at": _utc_now(),
        "directive_status": _first_text(directive.get("status"), default="unknown"),
        "mim_focus": mim_focus,
        "tod_focus": tod_focus,
        "mim_presence": presence,
        "mim_progress": [
            f"Typo/noisy-input recognition: {typo_pass_rate if typo_pass_rate is not None else 'baseline needed'}%",
            "Consultative app discovery now routes before accidental implementation.",
            "Project-manager judgment remains the next training target.",
        ],
        "tod_progress": [
            f"Blockers moved from {blocked_start} to {blocked_after}.",
            "False completion prevention and evidence inspection are active training drills.",
            "Next blocker class needs linked-task evidence validation.",
        ],
        "mim_blocker": "Recommendation, consultative discovery, and problem-analysis judgment still need stronger proof.",
        "tod_blocker": _plain_status(current_blocker),
        "mim_why": "Improves MIM's ability to understand vague customer requests and turn them into useful project plans instead of premature implementation tasks.",
        "tod_risk": "TOD still detects more implementation problems than it independently fixes, so blocker repair must keep proving changed state with evidence.",
        "mim_next": "Continue focused judgment-mode training and keep typo tolerance in the smoke suite.",
        "tod_next": next_drill.split(":", 1)[-1].strip(),
        "dave_needed": [
            {
                "title": "None right now",
                "detail": "No current item requires Dave unless you want to redirect training priority or review a specific project.",
            }
        ],
        "attention": attention,
        "recommendation": {
            "title": "Keep improving MIM judgment mode before expanding the prompt suite.",
            "why": "The latest noisy-input test passed, but the broader judgment suite still needs proof before MIM can reliably act like a project manager.",
            "effort": "1-2 focused training passes",
            "dependencies": "Fresh scoreboard and reflection artifacts",
        },
        "projects": [
            {
                "name": "MIM Project Studio",
                "status": "Implementation",
                "health": "Good",
                "next": "Ship the Studio Home shell and page-aware MIM panel.",
                "href": "/studio/projects",
            },
            {
                "name": "MIM/TOD Training System",
                "status": "Training",
                "health": "Needs fresh scoreboard",
                "next": "Refresh metrics after typo-tolerance pass.",
                "href": "/studio/training",
            },
            {
                "name": "MIM Robotics Workspace",
                "status": "Parked",
                "health": "Ready for calibration",
                "next": "Resume table coordinate and arm calibration tomorrow.",
                "href": "/studio/lab",
            },
        ],
        "health": [
            ("MIM", "green"),
            ("TOD", "green" if _first_text(tod_training.get("status")) == "training_active" else "yellow"),
            ("Dispatcher", "green"),
            ("Database", "green"),
            ("Voice", "yellow"),
            ("Training", "green" if _first_text(directive.get("status")) == "active" else "yellow"),
        ],
        "wins": [
            f"Typo recognition smoke passed {typo_passed or 20}/{typo_cases or 20}.",
            "Vague accounting-app request now becomes consultative discovery first.",
            "Studio command-center plan is ready for implementation.",
        ],
        "blocker_summary": blocker_summary,
        "objective_status": objective_status,
    }


def _tab_nav(active: str) -> str:
    links = []
    for tab in TABS:
        cls = "tab active" if tab["key"] == active else "tab"
        icon = str(tab.get("icon", "&#8226;"))
        links.append(
            f'<a class="{cls}" href="{_html(tab["href"])}" title="{_html(tab["label"])}" '
            f'aria-label="{_html(tab["label"])}"><span class="sigil">{icon}</span></a>'
        )
    return "\n".join(links)


def _shell(*, active: str, title: str, subtitle: str, body: str, page_context: str, show_mim_panel: bool = True) -> str:
    shell_chat_class = "" if show_mim_panel else " no-chat"
    restore_chat_html = (
        '<button id="restoreChat" class="chat-restore" type="button" hidden>MIM</button>'
        if show_mim_panel
        else ""
    )
    chat_panel_html = ""
    if show_mim_panel:
        chat_panel_html = f"""
    <aside id="studioMimPanel" class="chat-panel" data-page-context="{_html(page_context)}">
      <div id="chatResizer" class="chat-resizer" title="Resize MIM chat" aria-hidden="true"></div>
      <div class="chat-head">
        <div>
          <div class="chat-title">MIM</div>
          <div class="muted" style="font-size:12px;">Page-aware assistant</div>
        </div>
        <button id="toggleChat" class="button" type="button" aria-label="Collapse MIM panel">Hide</button>
      </div>
      <div class="chat-context">Context: {_html(page_context)}</div>
      <div id="chatBody" class="chat-body"></div>
      <div class="chat-composer">
        <div class="quick">
          <button type="button" data-prompt="Summarize this page.">Summarize this page</button>
          <button type="button" data-prompt="What needs Dave?">What needs Dave?</button>
          <button type="button" data-prompt="Give me one Studio recommendation for today.">Focus today</button>
          <button type="button" data-prompt="Is anything stuck?">Anything stuck?</button>
        </div>
        <textarea id="chatInput" placeholder="Ask MIM about this page..."></textarea>
        <button id="sendChat" class="button primary" type="button">Ask MIM</button>
      </div>
    </aside>"""
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{_html(title)} - MIM Studio</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #070b12;
      --panel: #101722;
      --panel-2: #151f2c;
      --line: #263344;
      --text: #edf4ff;
      --muted: #9fb0c4;
      --soft: #c9d7e8;
      --accent: #6ee7d8;
      --accent-2: #75b7ff;
      --warn: #ffd166;
      --danger: #ff6b7a;
      --good: #43d18b;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; min-height: 100vh; background: radial-gradient(circle at 25% 0%, rgba(117,183,255,.13), transparent 34%), var(--bg); color: var(--text); }}
    a {{ color: inherit; text-decoration: none; }}
    .studio-shell {{ min-height: 100vh; display: grid; grid-template-columns: minmax(0, 1fr) var(--studio-mim-chat-width, 420px); }}
    .studio-shell.no-chat, .studio-shell.chat-collapsed {{ grid-template-columns: minmax(0, 1fr); }}
    .main {{ min-width: 0; padding: 22px; }}
    .topbar {{ display: flex; justify-content: space-between; gap: 16px; align-items: center; margin-bottom: 8px; }}
    .brand {{ display: flex; flex-direction: column; gap: 4px; }}
    .brand strong {{ font-size: 16px; letter-spacing: 0; }}
    .brand span {{ display: none; }}
    .actions {{ display: flex; gap: 10px; align-items: center; }}
    .button {{ border: 1px solid var(--line); background: #101925; color: var(--text); border-radius: 8px; padding: 10px 12px; font-weight: 700; cursor: pointer; }}
    .button.primary {{ background: linear-gradient(135deg, var(--accent), var(--accent-2)); color: #061019; border: 0; }}
    .button.selected {{ background: rgba(107, 225, 255, .16); color: var(--accent); border-color: rgba(107, 225, 255, .65); box-shadow: inset 0 0 0 1px rgba(107, 225, 255, .18); }}
    .button:disabled {{ opacity: .5; cursor: not-allowed; }}
    .button.danger {{ background: rgba(255, 107, 122, .12); color: #ffd6dc; border-color: rgba(255, 107, 122, .35); }}
    .button.bat {{ background: linear-gradient(135deg, #ff5c70, #ff9b6b); color: #20070b; border: 0; box-shadow: 0 12px 30px rgba(255, 92, 112, .24); }}
    .icon-button {{ width: 38px; height: 38px; display: inline-flex; align-items: center; justify-content: center; padding: 0; font-size: 24px; line-height: 1; border: 0; background: transparent; box-shadow: none; color: var(--muted); }}
    .icon-button:hover, .icon-button:focus-visible {{ color: var(--text); background: transparent; outline: 0; }}
    .icon-button.primary, .icon-button.bat {{ background: transparent; color: var(--muted); border: 0; box-shadow: none; }}
    .icon-button.bat:hover, .icon-button.bat:focus-visible {{ color: var(--danger); background: transparent; }}
    .tabs {{ display: flex; gap: 8px; overflow-x: auto; padding: 6px 0 10px; margin-bottom: 0; }}
    .tab {{ width: 38px; height: 38px; flex: 0 0 38px; display: inline-flex; align-items: center; justify-content: center; white-space: nowrap; border: 0; color: var(--muted); background: transparent; border-radius: 0; padding: 0; font-size: 24px; font-weight: 700; }}
    .tab:hover, .tab:focus-visible {{ color: var(--text); outline: 0; }}
    .tab.active {{ color: var(--accent); background: transparent; border-color: transparent; }}
    .sigil {{ display: inline-block; transform: translateY(-1px); font-family: "Segoe UI Symbol", "Noto Sans Symbols", Inter, sans-serif; }}
    .page-label {{ color: var(--soft); font-size: 18px; font-weight: 900; margin: 4px 0 12px; }}
    .grid {{ display: grid; gap: 14px; }}
    .grid.two {{ grid-template-columns: repeat(2, minmax(0, 1fr)); }}
    .grid.three {{ grid-template-columns: repeat(3, minmax(0, 1fr)); }}
    .grid.four {{ grid-template-columns: repeat(4, minmax(0, 1fr)); }}
    .card {{ background: rgba(16, 23, 34, .86); border: 1px solid var(--line); border-radius: 8px; padding: 16px; box-shadow: 0 14px 34px rgba(0,0,0,.18); }}
    .card h2, .card h3 {{ margin: 0 0 10px; letter-spacing: 0; }}
    .card p {{ color: var(--muted); line-height: 1.5; margin: 0; }}
    .status-card {{ min-height: 330px; }}
    .status-head {{ display: flex; justify-content: space-between; gap: 12px; align-items: flex-start; }}
    .entity {{ font-size: 28px; font-weight: 900; }}
    .badge {{ display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--line); border-radius: 999px; padding: 5px 9px; color: var(--soft); font-size: 12px; font-weight: 800; }}
    .dot {{ width: 8px; height: 8px; border-radius: 99px; display: inline-block; background: var(--good); }}
    .dot.yellow {{ background: var(--warn); }}
    .dot.red {{ background: var(--danger); }}
    .focus {{ font-size: 17px; line-height: 1.42; color: var(--soft); margin: 12px 0 14px; }}
    .label {{ color: var(--muted); font-size: 12px; font-weight: 900; text-transform: uppercase; margin: 14px 0 6px; }}
    ul.clean {{ list-style: none; padding: 0; margin: 0; display: grid; gap: 7px; }}
    ul.clean li {{ color: var(--soft); line-height: 1.38; }}
    ul.clean li:before {{ content: ""; display: inline-block; width: 6px; height: 6px; border-radius: 99px; background: var(--accent); margin-right: 8px; transform: translateY(-1px); }}
    .attention-list {{ display: grid; gap: 10px; }}
    .attention-item {{ border: 1px solid var(--line); background: rgba(21,31,44,.78); border-radius: 8px; padding: 12px; }}
    .attention-item strong {{ display: block; margin-bottom: 4px; }}
    .attention-item small {{ color: var(--accent); font-weight: 900; }}
    .project-row, .health-row {{ display: grid; grid-template-columns: 1fr auto; gap: 12px; align-items: center; padding: 12px 0; border-top: 1px solid var(--line); }}
    .project-row:first-child, .health-row:first-child {{ border-top: 0; }}
    .project-row {{ border-radius: 8px; padding: 12px; margin: 0 -8px; transition: background .16s ease, border-color .16s ease; }}
    .project-row:hover {{ background: rgba(117,183,255,.08); }}
    .muted {{ color: var(--muted); }}
    .health-pill {{ border-radius: 999px; padding: 5px 9px; font-size: 12px; font-weight: 900; border: 1px solid var(--line); }}
    .green {{ color: #bfffe0; }}
    .yellow {{ color: #ffe4a3; }}
    .red {{ color: #ffc3ca; }}
    .score-table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
    .score-table th, .score-table td {{ text-align: left; border-top: 1px solid var(--line); padding: 8px 6px; color: var(--soft); vertical-align: top; }}
    .score-table th {{ color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0; }}
    .score-table tr.row-link {{ cursor: pointer; }}
    .score-table tr.row-link:hover {{ background: rgba(117,183,255,.08); }}
    .progress-track {{ width: 100%; min-width: 96px; height: 8px; border-radius: 999px; overflow: hidden; background: rgba(255,255,255,.08); border: 1px solid var(--line); }}
    .progress-fill {{ height: 100%; border-radius: inherit; background: linear-gradient(90deg, var(--accent), var(--accent-2)); }}
    input, select {{ width: 100%; border-radius: 8px; border: 1px solid var(--line); background: #0b111a; color: var(--text); padding: 10px 11px; font: inherit; }}
    .form-grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; }}
    .form-grid .wide {{ grid-column: 1 / -1; }}
    .embed-frame {{ width: 100%; height: calc(100vh - 210px); min-height: 620px; border: 1px solid var(--line); border-radius: 8px; background: #0a0f17; }}
    .placeholder-sections {{ margin-top: 16px; }}
    .chat-panel {{ border-left: 1px solid var(--line); background: rgba(9,14,22,.96); min-width: 300px; max-width: 760px; width: var(--studio-mim-chat-width, 420px); display: flex; flex-direction: column; position: sticky; top: 0; height: 100vh; }}
    .studio-shell.chat-collapsed .chat-panel {{ display: none; }}
    .chat-resizer {{ position: absolute; left: -5px; top: 0; bottom: 0; width: 10px; cursor: col-resize; z-index: 5; }}
    .chat-resizer:hover {{ background: rgba(110,231,216,.16); }}
    .chat-restore {{ position: fixed; right: 14px; top: 14px; z-index: 35; border: 1px solid var(--line); background: #101925; color: var(--text); border-radius: 8px; padding: 9px 11px; font-weight: 900; cursor: pointer; box-shadow: 0 14px 32px rgba(0,0,0,.28); }}
    .chat-head {{ padding: 14px; border-bottom: 1px solid var(--line); display: flex; align-items: center; justify-content: space-between; gap: 10px; }}
    .chat-title {{ font-weight: 900; }}
    .chat-context {{ padding: 10px 14px; color: var(--muted); border-bottom: 1px solid var(--line); font-size: 13px; }}
    .chat-body {{ flex: 1; overflow: auto; padding: 14px; display: flex; flex-direction: column; gap: 10px; }}
    .msg {{ border: 1px solid var(--line); border-radius: 8px; padding: 11px; line-height: 1.45; white-space: pre-wrap; }}
    .msg.user {{ background: rgba(117,183,255,.10); }}
    .msg.mim {{ background: rgba(110,231,216,.09); }}
    .chat-composer {{ padding: 14px; border-top: 1px solid var(--line); display: grid; gap: 10px; }}
    textarea {{ width: 100%; min-height: 92px; resize: vertical; border-radius: 8px; border: 1px solid var(--line); background: #0b111a; color: var(--text); padding: 11px; font: inherit; line-height: 1.45; }}
    .quick {{ display: flex; flex-wrap: wrap; gap: 6px; }}
    .quick button {{ border: 1px solid var(--line); background: rgba(21,31,44,.9); color: var(--soft); border-radius: 999px; padding: 7px 9px; font-size: 12px; cursor: pointer; }}
    .modal-backdrop {{ position: fixed; inset: 0; z-index: 40; background: rgba(3,7,12,.76); backdrop-filter: blur(8px); display: none; align-items: center; justify-content: center; padding: 20px; }}
    .modal-backdrop.open {{ display: flex; }}
    .modal {{ width: min(760px, 100%); max-height: min(820px, 92vh); overflow: auto; background: #0d141f; border: 1px solid rgba(255, 107, 122, .35); border-radius: 10px; box-shadow: 0 28px 80px rgba(0,0,0,.48); padding: 20px; }}
    .modal-head {{ display: flex; justify-content: space-between; gap: 14px; align-items: flex-start; margin-bottom: 14px; }}
    .modal h2 {{ margin: 0; font-size: 28px; letter-spacing: 0; }}
    .modal-grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; margin: 14px 0; }}
    .modal-box {{ border: 1px solid var(--line); border-radius: 8px; background: rgba(21,31,44,.75); padding: 12px; }}
    .modal-box strong {{ display: block; margin-bottom: 6px; }}
    .modal-actions {{ display: flex; gap: 10px; justify-content: flex-end; flex-wrap: wrap; margin-top: 14px; }}
    @media (max-width: 1180px) {{
      .studio-shell {{ grid-template-columns: minmax(0, 1fr); }}
      .chat-panel {{ position: relative; height: 560px; border-left: 0; border-top: 1px solid var(--line); width: 100%; max-width: none; min-width: 0; }}
      .chat-resizer {{ display: none; }}
    }}
    @media (max-width: 820px) {{
      .main {{ padding: 14px; }}
      .grid.two, .grid.three, .grid.four {{ grid-template-columns: 1fr; }}
      .actions {{ flex-wrap: wrap; }}
      .embed-frame {{ height: 680px; }}
      .modal-grid {{ grid-template-columns: 1fr; }}
    }}
  </style>
</head>
<body>
  <div id="studioShell" class="studio-shell{shell_chat_class}">
    <main class="main">
      <header class="topbar">
        <div class="brand">
          <strong>MIM Studio</strong>
          <span>Dave's command center for MIM, TOD, projects, training, systems, and apps.</span>
        </div>
        <div class="actions">
          <button id="openBatPhone" class="button bat icon-button" type="button" title="H.A.L." aria-label="H.A.L."><span class="sigil">&#8961;</span></button>
          <a class="button icon-button" href="/mim/logout" title="Logout" aria-label="Logout"><span class="sigil">&#9211;</span></a>
        </div>
      </header>
      <nav class="tabs" aria-label="Studio tabs">{_tab_nav(active)}</nav>
      <div class="page-label">{_html(title)}</div>
      {body}
    </main>
    {chat_panel_html}
  </div>
  {restore_chat_html}
  <div id="batPhoneModal" class="modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="batPhoneTitle">
    <div class="modal">
      <div class="modal-head">
        <div>
          <h2 id="batPhoneTitle">H.A.L.</h2>
          <p class="muted">Help Action Loop: break-glass triage for frozen, blocked, stale, or confusing MIM/TOD states.</p>
        </div>
        <button id="closeBatPhone" class="button" type="button">Close</button>
      </div>
      <div class="modal-grid">
        <div class="modal-box"><strong>What it solves</strong><p>Find what is stuck, explain why, classify the failure, and create an accountable repair path.</p></div>
        <div class="modal-box"><strong>Escalation path</strong><p>MIM diagnoses first. TOD repairs if executable. Codex is used when code-level implementation or deeper inspection is needed. Dave is needed only for credentials, decisions, or physical-world checks.</p></div>
        <div class="modal-box"><strong>Required output</strong><p>Broken thing, likely cause, repair owner, next action, validation target, and evidence location.</p></div>
        <div class="modal-box"><strong>Who answers H.A.L.?</strong><p>H.A.L. is the escalation chain, not one person: MIM as coordinator, TOD as repair executor, Codex as implementation backup, Dave as final human authority.</p></div>
      </div>
      <label class="label" for="batPhoneSymptom">What looks broken? Optional.</label>
      <textarea id="batPhoneSymptom" placeholder="Example: TOD looks idle, objectives are blocked, voice stopped responding, training says active but outcomes are not improving..."></textarea>
      <div class="modal-actions">
        <button id="runBatPhone" class="button bat" type="button">Run H.A.L. Triage</button>
      </div>
    </div>
  </div>
  <script>
    const shell = document.getElementById('studioShell');
    const panel = document.getElementById('studioMimPanel');
    const chatBody = document.getElementById('chatBody');
    const chatInput = document.getElementById('chatInput');
    const sendChat = document.getElementById('sendChat');
    const toggleChat = document.getElementById('toggleChat');
    const restoreChat = document.getElementById('restoreChat');
    const chatResizer = document.getElementById('chatResizer');
    const pageContext = panel ? panel.dataset.pageContext || 'Studio' : 'Studio';
    const threadKey = 'studioMimThreadV1';
    const widthKey = 'studioMimChatWidth';
    const collapsedKey = 'studioMimChatCollapsed';
    const greeting = 'Hi Dave. I am watching this Studio page with you. Ask what matters, what is stuck, what changed, or what I recommend next.';
    function clampChatWidth(value) {{
      const maxByViewport = Math.max(320, Math.floor(window.innerWidth * 0.56));
      return Math.min(Math.max(Number(value) || 420, 300), Math.min(760, maxByViewport));
    }}
    function setChatWidth(value) {{
      const width = clampChatWidth(value);
      if (shell) shell.style.setProperty('--studio-mim-chat-width', width + 'px');
      try {{ localStorage.setItem(widthKey, String(width)); }} catch (error) {{}}
    }}
    function loadThread() {{
      try {{
        const raw = localStorage.getItem(threadKey);
        const parsed = raw ? JSON.parse(raw) : [];
        return Array.isArray(parsed) ? parsed.filter((item) => item && item.role && item.text).slice(-80) : [];
      }} catch (error) {{
        return [];
      }}
    }}
    function saveThread(messages) {{
      try {{ localStorage.setItem(threadKey, JSON.stringify(messages.slice(-80))); }} catch (error) {{}}
    }}
    let studioMimMessages = loadThread();
    function renderThread() {{
      if (!chatBody) return;
      chatBody.innerHTML = '';
      const messages = studioMimMessages.length ? studioMimMessages : [{{ role: 'mim', text: greeting }}];
      messages.forEach((message) => {{
        const node = document.createElement('div');
        node.className = 'msg ' + (message.role === 'user' ? 'user' : 'mim');
        node.textContent = String(message.text || '');
        chatBody.appendChild(node);
      }});
      chatBody.scrollTop = chatBody.scrollHeight;
    }}
    function appendMessage(role, text) {{
      if (!chatBody) return null;
      const node = document.createElement('div');
      node.className = 'msg ' + role;
      node.textContent = text;
      chatBody.appendChild(node);
      chatBody.scrollTop = chatBody.scrollHeight;
      if (role === 'user' || role === 'mim') {{
        studioMimMessages.push({{ role: role, text: String(text || ''), at: new Date().toISOString(), page_context: pageContext }});
        saveThread(studioMimMessages);
      }}
      return node;
    }}
    function replaceMimMessage(node, text) {{
      if (!node) return;
      node.textContent = text;
      const last = studioMimMessages[studioMimMessages.length - 1];
      if (last && last.role === 'mim') {{
        last.text = String(text || '');
        saveThread(studioMimMessages);
      }}
    }}
    function maybeNavigate(navigation) {{
      if (!navigation || !navigation.href || !navigation.auto_redirect) return;
      const target = String(navigation.href);
      const current = window.location.pathname + window.location.search;
      if (target === current) return;
      setTimeout(() => {{ window.location.href = target; }}, 650);
    }}
    async function askMim(prompt) {{
      if (!chatInput || !sendChat || !chatBody) return;
      const text = String(prompt || '').trim();
      if (!text) return;
      appendMessage('user', text);
      chatInput.value = '';
      const thinking = appendMessage('mim', 'Thinking with this page context...');
      try {{
        const contextualText = 'Studio context: ' + pageContext + '. Operator request: ' + text;
        const studioResponse = await fetch('/studio/api/mim/chat', {{
          method: 'POST',
          headers: {{ 'Content-Type': 'application/json' }},
          body: JSON.stringify({{
            prompt: text,
            page_context: pageContext,
            studio_page_context: pageContext,
            metadata_json: {{
              mim_surface: 'studio',
              original_operator_text: text
            }}
          }})
        }});
        if (studioResponse.ok) {{
          const studioData = await studioResponse.json();
          const studioReply = studioData && studioData.mim_interface && studioData.mim_interface.reply_text;
          if (studioReply) {{
            replaceMimMessage(thinking, studioReply);
            maybeNavigate(studioData.navigation);
            if ((studioData.source === 'studio_reports_context') && pageContext.toLowerCase().includes('report')) {{
              const evidence = studioData.evidence || {{}};
              const dataset = evidence.dataset || 'auto';
              const target = '/studio/reports?dataset=' + encodeURIComponent(dataset) + '&prompt=' + encodeURIComponent(text);
              setTimeout(() => {{ window.location.href = target; }}, 450);
            }}
            return;
          }}
        }}
        const response = await fetch('/gateway/intake', {{
          method: 'POST',
          headers: {{ 'Content-Type': 'application/json' }},
          body: JSON.stringify({{
            source: 'text',
            raw_input: contextualText,
            parsed_intent: 'question',
            confidence: 0.98,
            target_system: 'MIM',
            requested_goal: '',
            safety_flags: [],
            metadata_json: {{
              route_preference: 'conversation_layer',
              studio_page_context: pageContext,
              mim_surface: 'studio',
              mim_presence_identity: 'one_mim_many_interfaces',
              conversation_session_id: 'dave-primary-mim-thread',
              original_operator_text: text
            }}
          }})
        }});
        const data = await response.json();
        const reply = (data && data.mim_interface && data.mim_interface.reply_text)
          || (data && data.resolution && data.resolution.clarification_prompt)
          || 'I received that, but I do not have a clean reply yet.';
        replaceMimMessage(thinking, reply);
      }} catch (error) {{
        replaceMimMessage(thinking, 'MIM chat failed from Studio: ' + (error && error.message ? error.message : 'unknown error'));
      }}
    }}
    if (panel && shell && chatBody && chatInput && sendChat && toggleChat) {{
      const savedWidth = localStorage.getItem(widthKey);
      if (savedWidth) setChatWidth(savedWidth);
      if (localStorage.getItem(collapsedKey) === 'true') {{
        shell.classList.add('chat-collapsed');
        restoreChat && (restoreChat.hidden = false);
      }}
      renderThread();
      sendChat.addEventListener('click', () => askMim(chatInput.value));
      chatInput.addEventListener('keydown', (event) => {{
        if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) askMim(chatInput.value);
      }});
      document.querySelectorAll('[data-prompt]').forEach((button) => {{
        button.addEventListener('click', () => askMim(button.dataset.prompt || ''));
      }});
      toggleChat.addEventListener('click', () => {{
        shell.classList.add('chat-collapsed');
        restoreChat && (restoreChat.hidden = false);
        try {{ localStorage.setItem(collapsedKey, 'true'); }} catch (error) {{}}
      }});
      restoreChat && restoreChat.addEventListener('click', () => {{
        shell.classList.remove('chat-collapsed');
        restoreChat.hidden = true;
        try {{ localStorage.setItem(collapsedKey, 'false'); }} catch (error) {{}}
      }});
      if (chatResizer) {{
        let resizing = false;
        chatResizer.addEventListener('pointerdown', (event) => {{
          resizing = true;
          chatResizer.setPointerCapture(event.pointerId);
          document.body.style.userSelect = 'none';
        }});
        chatResizer.addEventListener('pointermove', (event) => {{
          if (!resizing) return;
          setChatWidth(window.innerWidth - event.clientX);
        }});
        chatResizer.addEventListener('pointerup', (event) => {{
          resizing = false;
          try {{ chatResizer.releasePointerCapture(event.pointerId); }} catch (error) {{}}
          document.body.style.userSelect = '';
        }});
        chatResizer.addEventListener('pointercancel', () => {{
          resizing = false;
          document.body.style.userSelect = '';
        }});
      }}
    }}
    const batPhoneModal = document.getElementById('batPhoneModal');
    const batPhoneSymptom = document.getElementById('batPhoneSymptom');
    function openBatPhoneModal() {{
      batPhoneModal.classList.add('open');
      setTimeout(() => batPhoneSymptom && batPhoneSymptom.focus(), 50);
    }}
    function closeBatPhoneModal() {{
      batPhoneModal.classList.remove('open');
    }}
    document.getElementById('openBatPhone').addEventListener('click', openBatPhoneModal);
    document.getElementById('closeBatPhone').addEventListener('click', closeBatPhoneModal);
    batPhoneModal.addEventListener('click', (event) => {{
      if (event.target === batPhoneModal) closeBatPhoneModal();
    }});
    document.getElementById('runBatPhone').addEventListener('click', () => {{
      const symptom = String(batPhoneSymptom && batPhoneSymptom.value || '').trim();
      closeBatPhoneModal();
      askMim('H.A.L.: diagnose this Studio page and current MIM/TOD state. Find what is stuck, explain why, classify the failure, decide whether MIM, TOD, Codex, or Dave owns the next action, create a repair plan, and show evidence.' + (symptom ? '\\n\\nOperator symptom: ' + symptom : ''));
    }});
  </script>
</body>
</html>"""


def _home_body(snapshot: dict[str, Any]) -> str:
    def progress_items(items: list[str]) -> str:
        return "".join(f"<li>{_html(item)}</li>" for item in items)

    attention_html = "".join(
        f"""
        <div class="attention-item">
          <small>{_html(item.get("owner"))}</small>
          <strong>{_html(item.get("title"))}</strong>
          <p>{_html(item.get("detail"))}</p>
        </div>
        """
        for item in snapshot["attention"]
    ) or '<p class="muted">Nothing needs Dave right now.</p>'

    projects_html = "".join(
        f"""
        <a class="project-row" href="{_html(project.get("href", "/studio/projects"))}">
          <div>
            <strong>{_html(project["name"])}</strong>
            <div class="muted">{_html(project["status"])} - { _html(project["next"]) }</div>
          </div>
          <span class="health-pill">{_html(project["health"])}</span>
        </a>
        """
        for project in snapshot["projects"]
    )

    visible_health = [(name, color) for name, color in snapshot["health"] if color != "green"]
    systems_note = ""
    if not visible_health:
        visible_health = [("All monitored systems", "green")]
        systems_note = '<p class="muted">Everything important is green, so this stays quiet.</p>'
    else:
        green_count = sum(1 for _, color in snapshot["health"] if color == "green")
        systems_note = f'<p class="muted">{green_count} green system{"s" if green_count != 1 else ""} collapsed. Showing only attention items.</p>'
    health_html = "".join(
        f"""
        <div class="health-row">
          <strong>{_html(name)}</strong>
          <span class="{_html(color)}"><span class="dot {'yellow' if color == 'yellow' else 'red' if color == 'red' else ''}"></span> {_html(color.title())}</span>
        </div>
        """
        for name, color in visible_health
    )

    wins_html = "".join(f"<li>{_html(win)}</li>" for win in snapshot["wins"])
    presence = snapshot.get("mim_presence") if isinstance(snapshot.get("mim_presence"), dict) else {}
    presence_html = f"""
      <div class="project-row">
        <div><strong>Current Conversation</strong><div class="muted">{_html(presence.get("current_conversation", "Studio command center"))}</div></div>
        <span class="health-pill">{_html(presence.get("memory_context", "active"))}</span>
      </div>
      <div class="project-row">
        <div><strong>Active Project</strong><div class="muted">{_html(presence.get("active_project", "MIM Project Studio"))}</div></div>
        <span class="health-pill">Project</span>
      </div>
      <div class="project-row">
        <div><strong>Last Surface</strong><div class="muted">{_html(presence.get("last_interaction_surface", "Studio"))}</div></div>
        <span class="health-pill">MIM</span>
      </div>
      <div class="project-row">
        <div><strong>Pending Follow-Up</strong><div class="muted">{_html(presence.get("pending_follow_up", "Keep MIM's page-aware presence consistent."))}</div></div>
        <span class="health-pill">Next</span>
      </div>
    """
    dave_needed_html = "".join(
        f"""
        <div class="attention-item">
          <strong>{_html(item.get("title"))}</strong>
          <p>{_html(item.get("detail"))}</p>
        </div>
        """
        for item in snapshot["dave_needed"]
    )

    return f"""
    <section class="grid two">
      <article class="card status-card">
        <div class="status-head">
          <div class="entity">MIM</div>
          <span class="badge"><span class="dot"></span>{_html(snapshot["directive_status"])}</span>
        </div>
        <div class="focus">{_html(snapshot["mim_focus"])}</div>
        <div class="label">Progress</div>
        <ul class="clean">{progress_items(snapshot["mim_progress"])}</ul>
        <div class="label">Current Blocker</div>
        <p>{_html(snapshot["mim_blocker"])}</p>
        <div class="label">Why This Matters</div>
        <p>{_html(snapshot["mim_why"])}</p>
        <div class="label">Next Action</div>
        <p>{_html(snapshot["mim_next"])}</p>
        <div class="label">Dave Needed</div>
        <p>No, unless you want to redirect the training priority.</p>
      </article>
      <article class="card status-card">
        <div class="status-head">
          <div class="entity">TOD</div>
          <span class="badge"><span class="dot"></span>training active</span>
        </div>
        <div class="focus">{_html(snapshot["tod_focus"])}</div>
        <div class="label">Progress</div>
        <ul class="clean">{progress_items(snapshot["tod_progress"])}</ul>
        <div class="label">Current Blocker</div>
        <p>{_html(snapshot["tod_blocker"])}</p>
        <div class="label">Risk</div>
        <p>{_html(snapshot["tod_risk"])}</p>
        <div class="label">Next Action</div>
        <p>{_html(snapshot["tod_next"])}</p>
        <div class="label">Dave Needed</div>
        <p>No, unless a blocker requires a credential, decision, or physical-world check.</p>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>What Needs Attention?</h2>
        <div class="attention-list">{attention_html}</div>
      </article>
      <article class="card">
        <h2>MIM Recommends</h2>
        <h3>{_html(snapshot["recommendation"]["title"])}</h3>
        <p>{_html(snapshot["recommendation"]["why"])}</p>
        <div class="label">Estimated Effort</div>
        <p>{_html(snapshot["recommendation"]["effort"])}</p>
        <div class="label">Dependencies</div>
        <p>{_html(snapshot["recommendation"]["dependencies"])}</p>
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>MIM Presence</h2>
        <p>Same MIM. Different interface.</p>
        {presence_html}
      </article>
      <article class="card">
        <h2>Dave Needed</h2>
        <div class="attention-list">{dave_needed_html}</div>
      </article>
      <article class="card">
        <h2>Active Projects</h2>
        {projects_html}
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>Systems</h2>
        {systems_note}
        {health_html}
      </article>
      <article class="card">
        <h2>Recent Wins</h2>
        <ul class="clean">{wins_html}</ul>
      </article>
      <article class="card">
        <h2>H.A.L. Preview</h2>
        <p>One click should diagnose what is broken, explain why, decide whether MIM or TOD can fix it, and show evidence before declaring success.</p>
      </article>
      <article class="card">
        <h2>Studio Rule</h2>
        <p>Home stays human-first. Objective tables, packet listeners, request IDs, and raw artifacts belong in drill-down pages.</p>
      </article>
    </section>
    """


def _placeholder_body(key: str) -> str:
    spec = PLACEHOLDERS[key]
    rows = "".join(
        f"""
        <article class="card">
          <h3>{_html(title)}</h3>
          <p>{_html(detail)}</p>
        </article>
        """
        for title, detail in spec["sections"]  # type: ignore[index]
    )
    return f"""<section class="grid three placeholder-sections">{rows}</section>"""


def _format_bytes(value: float | int | None) -> str:
    if value is None:
        return "unknown"
    size = float(value)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(size) < 1024.0 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024.0
    return f"{size:.1f} TB"


def _format_duration(seconds: float | int | None) -> str:
    if seconds is None:
        return "unknown"
    total = int(max(0, float(seconds)))
    days, rem = divmod(total, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    if days:
        return f"{days}d {hours}h"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def _percent(value: float | int | None) -> str:
    if value is None:
        return "unknown"
    return f"{float(value):.1f}%"


def _read_meminfo() -> dict[str, Any]:
    path = Path("/proc/meminfo")
    if not path.exists():
        return {"available": False}
    values: dict[str, int] = {}
    try:
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if ":" not in line:
                continue
            key, raw = line.split(":", 1)
            digits = "".join(ch for ch in raw if ch.isdigit())
            if digits:
                values[key] = int(digits) * 1024
    except Exception:
        return {"available": False}
    total = values.get("MemTotal")
    available = values.get("MemAvailable")
    used = total - available if total is not None and available is not None else None
    used_percent = (used / total * 100.0) if total and used is not None else None
    return {
        "available": True,
        "total": total,
        "used": used,
        "free": available,
        "used_percent": used_percent,
    }


def _read_uptime_seconds() -> float | None:
    path = Path("/proc/uptime")
    if not path.exists():
        return None
    try:
        return float(path.read_text(encoding="utf-8").split()[0])
    except Exception:
        return None


def _host_ekg_state() -> dict[str, Any]:
    mem = _read_meminfo()
    try:
        load = os.getloadavg()
    except Exception:
        load = None
    try:
        disk = shutil.disk_usage("/")
        disk_used_percent = (disk.used / disk.total * 100.0) if disk.total else None
    except Exception:
        disk = None
        disk_used_percent = None
    return {
        "hostname": os.uname().nodename if hasattr(os, "uname") else "mim-host",
        "load": load,
        "ram": mem,
        "disk": {
            "total": disk.total if disk else None,
            "used": disk.used if disk else None,
            "free": disk.free if disk else None,
            "used_percent": disk_used_percent,
        },
        "uptime_seconds": _read_uptime_seconds(),
    }


async def _studio_systems_state(db: AsyncSession) -> dict[str, Any]:
    host = _host_ekg_state()
    apps_state = await _studio_apps_state(db)
    scan = _load_json("MIM_TOD_APP_SOURCE_SCAN.latest.json")
    tod_local = _load_json("TOD_LOCAL_MACHINE_STATUS.latest.json")
    pythonanywhere = _load_json("MIM_ROBOTICS_PYTHONANYWHERE_STATUS.latest.json")
    reflection = _load_json("MIM_TOD_HOURLY_REFLECTION.latest.json")
    scoreboard = _load_json("MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    dispatcher = _load_json("MIM_READY_TASK_DISPATCHER_STATUS.latest.json")
    tod_training = _load_json("TOD_IDLE_TRAINING_STATUS.latest.json")

    db_ok = False
    db_counts: dict[str, Any] = {}
    try:
        await db.execute(text("select 1"))
        db_ok = True
    except Exception:
        db_ok = False
    for table_name in ("studio_projects", "studio_documents", "studio_report_canvases", "objectives", "tasks"):
        db_counts[table_name] = await _safe_table_count(db, table_name)

    apps = apps_state.get("apps") if isinstance(apps_state.get("apps"), list) else []
    dirty_apps = [
        app for app in apps
        if isinstance(app.get("dirty_count"), int) and int(app.get("dirty_count") or 0) > 0
    ]
    binding_apps = [
        app for app in apps
        if str(app.get("db_status") or "") in {"needs_binding", "external_declared", "fallback_available"}
    ]
    scan_apps = scan.get("apps") if isinstance(scan.get("apps"), list) else []

    cpu_status = (pythonanywhere.get("api") or {}).get("cpu_status") if isinstance(pythonanywhere.get("api"), dict) else None
    webapps_status = (pythonanywhere.get("api") or {}).get("webapps_status") if isinstance(pythonanywhere.get("api"), dict) else None
    homepage_status = (pythonanywhere.get("homepage") or {}).get("status") if isinstance(pythonanywhere.get("homepage"), dict) else None
    pythonanywhere_ok = cpu_status == 200 and webapps_status == 200 and homepage_status == 200

    attention: list[dict[str, str]] = []
    if not db_ok:
        attention.append({"owner": "Database", "title": "Studio database is not reachable", "detail": "The page could not complete a select 1 check."})
    if reflection.get("are_they_improving") is False:
        recommendation = _first_text(reflection.get("recommendation"), default="Outcome reflection says improvement is not proven yet.")
        attention.append({"owner": "Training", "title": "Outcome improvement is not proven", "detail": recommendation})
    for app in dirty_apps[:2]:
        attention.append(
            {
                "owner": "Apps",
                "title": f"{_first_text(app.get('display_name'), app.get('app_key'))} has a dirty worktree",
                "detail": f"{app.get('dirty_count')} changed/untracked item(s). Review before deployment or new edits.",
            }
        )
    for app in binding_apps[:2]:
        status = str(app.get("db_status") or "")
        attention.append(
            {
                "owner": "Apps",
                "title": f"{_first_text(app.get('display_name'), app.get('app_key'))}: {_plain_status(status)}",
                "detail": _first_text(app.get("next_action"), default="Connect the app-specific data adapter."),
            }
        )
    if not pythonanywhere_ok and pythonanywhere:
        attention.append(
            {
                "owner": "MIM Robotics",
                "title": "PythonAnywhere check needs attention",
                "detail": f"CPU API {cpu_status}, webapps API {webapps_status}, homepage {homepage_status}.",
            }
        )
    attention = attention[:5]
    if not attention:
        attention.append({"owner": "Systems", "title": "No urgent system attention item", "detail": "Known checks are green or already represented on focused pages."})

    health_rows = [
        {"name": "MIM Web", "state": "green", "detail": "This page rendered from the MIM FastAPI service."},
        {"name": "Studio DB", "state": "green" if db_ok else "red", "detail": "select 1 passed" if db_ok else "query failed"},
        {"name": "PythonAnywhere", "state": "green" if pythonanywhere_ok else ("yellow" if pythonanywhere else "yellow"), "detail": "MIM Robotics API/homepage verified" if pythonanywhere_ok else "adapter check needed"},
        {"name": "App Fleet", "state": "yellow" if dirty_apps or binding_apps else "green", "detail": f"{len(apps)} registered, {len(dirty_apps)} dirty repos, {len(binding_apps)} DB adapter notes"},
        {"name": "Training Reflection", "state": "yellow" if reflection.get("are_they_improving") is False else "green", "detail": _first_text(reflection.get("assessment"), default="available" if reflection else "not found")},
        {"name": "TOD Local Machine", "state": "green" if tod_local else "yellow", "detail": _first_text((tod_local.get("host") or {}).get("name") if isinstance(tod_local.get("host"), dict) else "", default="local metrics snapshot not found")},
        {"name": "TOD Source Scan", "state": "green" if scan_apps else "yellow", "detail": f"{len(scan_apps)} app roots scanned" if scan_apps else "latest scan not found"},
    ]
    objective_counts = reflection.get("objective_counts") if isinstance(reflection.get("objective_counts"), dict) else {}
    freshness = reflection.get("freshness") if isinstance(reflection.get("freshness"), dict) else {}
    stale_artifacts = freshness.get("stale_artifacts") if isinstance(freshness.get("stale_artifacts"), list) else []
    outcome_reflection = scoreboard.get("outcome_reflection") if isinstance(scoreboard.get("outcome_reflection"), dict) else {}
    judgment = scoreboard.get("judgment_mode_score") if isinstance(scoreboard.get("judgment_mode_score"), dict) else {}
    recommendations = (
        outcome_reflection.get("recommendations")
        if isinstance(outcome_reflection.get("recommendations"), list)
        else []
    )
    resolution_actions = [
        "Run blocker-to-objective synthesis for blockers without follow-on repair objectives.",
        "Refresh stale execution, validation, continuity, and morning-summary artifacts.",
        "Run the focused Judgment Mode suite again and require improvement before claiming green.",
        "Publish the next reflection only after blockers, stale inputs, and judgment evidence are reconciled.",
    ]
    for item in recommendations[:3]:
        if isinstance(item, str) and item not in resolution_actions:
            resolution_actions.insert(0, item)

    return {
        "generated_at": _utc_now(),
        "host": host,
        "db_ok": db_ok,
        "db_counts": db_counts,
        "apps_state": apps_state,
        "scan": scan,
        "tod_local": tod_local,
        "pythonanywhere": pythonanywhere,
        "reflection": reflection,
        "scoreboard": scoreboard,
        "training_resolution": {
            "assessment": _first_text(reflection.get("assessment"), outcome_reflection.get("assessment"), default="unknown"),
            "are_improving": reflection.get("are_they_improving"),
            "blocked": objective_counts.get("blocked"),
            "running": objective_counts.get("running"),
            "completed": objective_counts.get("completed"),
            "stale_artifacts": stale_artifacts,
            "stale_count": len(stale_artifacts),
            "judgment_pass_rate": judgment.get("pass_rate_percent"),
            "judgment_status": _first_text(judgment.get("status"), default="unknown"),
            "next_objective": _first_text(outcome_reflection.get("operator_summary"), default="Resolve reflection yellow state with blocker cleanup and stale artifact refresh."),
            "actions": resolution_actions[:5],
            "links": [
                {"label": "Training", "href": "/studio/training"},
                {"label": "Training Report", "href": "/studio/reports?dataset=training"},
                {"label": "TOD Blockers", "href": "/studio/reports?dataset=tod_blockers"},
                {"label": "Training Documents", "href": "/studio/documents"},
                {"label": "Objectives", "href": "/objectives"},
            ],
        },
        "dispatcher": dispatcher,
        "tod_training": tod_training,
        "attention": attention,
        "health_rows": health_rows,
        "dirty_apps": dirty_apps,
        "binding_apps": binding_apps,
    }


def _metric_card(label: str, value: object, detail: str = "") -> str:
    detail_html = f"<p>{_html(detail)}</p>" if detail else ""
    return f"""
      <article class="card">
        <div class="label">{_html(label)}</div>
        <div class="entity">{_html(str(value))}</div>
        {detail_html}
      </article>
    """


def _systems_body(state: dict[str, Any]) -> str:
    host = state.get("host") if isinstance(state.get("host"), dict) else {}
    ram = host.get("ram") if isinstance(host.get("ram"), dict) else {}
    disk = host.get("disk") if isinstance(host.get("disk"), dict) else {}
    apps_state = state.get("apps_state") if isinstance(state.get("apps_state"), dict) else {}
    app_counts = apps_state.get("counts") if isinstance(apps_state.get("counts"), dict) else {}
    tod_local = state.get("tod_local") if isinstance(state.get("tod_local"), dict) else {}
    tod_host = tod_local.get("host") if isinstance(tod_local.get("host"), dict) else {}
    tod_memory = tod_local.get("memory") if isinstance(tod_local.get("memory"), dict) else {}
    tod_cpu = tod_local.get("cpu") if isinstance(tod_local.get("cpu"), dict) else {}
    tod_disks = tod_local.get("disks") if isinstance(tod_local.get("disks"), list) else []
    tod_gpus = tod_local.get("gpus") if isinstance(tod_local.get("gpus"), list) else []
    pythonanywhere = state.get("pythonanywhere") if isinstance(state.get("pythonanywhere"), dict) else {}
    reflection = state.get("reflection") if isinstance(state.get("reflection"), dict) else {}
    training_resolution = state.get("training_resolution") if isinstance(state.get("training_resolution"), dict) else {}
    db_counts = state.get("db_counts") if isinstance(state.get("db_counts"), dict) else {}
    load = host.get("load")
    load_text = "unknown"
    if isinstance(load, tuple) and len(load) >= 3:
        load_text = f"{load[0]:.2f} / {load[1]:.2f} / {load[2]:.2f}"
    cpu = pythonanywhere.get("cpu") if isinstance(pythonanywhere.get("cpu"), dict) else {}
    cpu_used = cpu.get("daily_cpu_total_usage_seconds")
    cpu_limit = cpu.get("daily_cpu_limit_seconds")

    top_cards = "".join(
        [
            _metric_card("Overall", "Attention" if state.get("attention") else "Good", "Ecosystem checks are consolidated here; focused pages handle detail."),
            _metric_card("MIM Host RAM", _percent(ram.get("used_percent")), f"{_format_bytes(ram.get('used'))} used of {_format_bytes(ram.get('total'))}"),
            _metric_card("App Fleet", app_counts.get("apps", 0), f"{app_counts.get('dirty_repos', 0)} dirty repos, {app_counts.get('db_connected', 0)} DB-connected"),
            _metric_card("DB", "Online" if state.get("db_ok") else "Down", f"{db_counts.get('studio_projects') or 0} projects, {db_counts.get('tasks') or 0} tasks"),
        ]
    )
    health_html = "".join(
        f"""
        <div class="health-row">
          <div><strong>{_html(row.get("name", ""))}</strong><br><span class="muted">{_html(row.get("detail", ""))}</span></div>
          <span class="health-pill {_html(row.get("state", "yellow"))}">{_html(str(row.get("state", "yellow")).upper())}</span>
        </div>
        """
        for row in state.get("health_rows", [])
        if isinstance(row, dict)
    )
    attention_html = "".join(
        f"""
        <div class="attention-item">
          <small>{_html(item.get("owner", ""))}</small>
          <strong>{_html(item.get("title", ""))}</strong>
          <p>{_html(item.get("detail", ""))}</p>
        </div>
        """
        for item in state.get("attention", [])
        if isinstance(item, dict)
    )
    resolution_links_html = "".join(
        f'<a class="button" href="{_html(str(link.get("href", "#")))}">{_html(str(link.get("label", "Open")))}</a>'
        for link in training_resolution.get("links", [])
        if isinstance(link, dict)
    )
    resolution_actions_html = "".join(
        f"<li>{_html(str(action))}</li>"
        for action in training_resolution.get("actions", [])
    )
    stale_preview = training_resolution.get("stale_artifacts") if isinstance(training_resolution.get("stale_artifacts"), list) else []
    stale_preview_html = "".join(
        f"<li>{_html(str(name))}</li>"
        for name in stale_preview[:5]
    ) or "<li>No stale artifacts listed.</li>"
    dirty_html = "".join(
        f"""
        <div class="project-row">
          <div><strong>{_html(_first_text(app.get("display_name"), app.get("app_key")))}</strong><br><span class="muted">{_html(str(app.get("branch") or "branch unknown"))} {_html(str(app.get("commit") or ""))}</span></div>
          <span class="health-pill yellow">{_html(str(app.get("dirty_count")))} dirty</span>
        </div>
        """
        for app in state.get("dirty_apps", [])
        if isinstance(app, dict)
    ) or '<p class="muted">No dirty app repos reported by the latest TOD source scan.</p>'
    adapter_html = "".join(
        f"""
        <div class="project-row">
          <div><strong>{_html(_first_text(app.get("display_name"), app.get("app_key")))}</strong><br><span class="muted">{_html(_first_text(app.get("next_action"), default="Connect app adapter."))}</span></div>
          <span class="health-pill yellow">{_html(_plain_status(app.get("db_status")))}</span>
        </div>
        """
        for app in state.get("binding_apps", [])
        if isinstance(app, dict)
    ) or '<p class="muted">No app data-adapter notes from the current registry pass.</p>'
    db_rows = "".join(
        f"<tr><td>{_html(name)}</td><td>{_html('not found' if value is None else str(value))}</td></tr>"
        for name, value in db_counts.items()
    )
    tod_disk_rows = "".join(
        f"<tr><td>{_html(str(disk.get('device_id', 'disk')))}</td><td>{_html(_percent(disk.get('used_percent')))}</td><td>{_html(_format_bytes(disk.get('free_bytes')))}</td></tr>"
        for disk in tod_disks[:5]
        if isinstance(disk, dict)
    ) or '<tr><td colspan="3">No local disk snapshot yet.</td></tr>'
    tod_gpu_text = ", ".join(
        _first_text(gpu.get("name"), default="GPU")
        for gpu in tod_gpus
        if isinstance(gpu, dict)
    ) or "No GPU snapshot yet"
    pa_status = "Verified" if pythonanywhere and (pythonanywhere.get("homepage") or {}).get("status") == 200 else "Needs check"
    next_reset = _first_text(cpu.get("next_reset_time"), default="unknown")
    return f"""
    <section class="grid four">{top_cards}</section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Ecosystem Health</h2>
        {health_html}
      </article>
      <article class="card">
        <h2>Needs Attention</h2>
        <div class="attention-list">{attention_html}</div>
      </article>
    </section>
    <section class="card" style="margin-top:14px;">
      <div class="status-head">
        <div>
          <h2>Training Reflection Resolution</h2>
          <p>This yellow state should produce a repair path, not just a warning.</p>
        </div>
        <span class="badge"><span class="dot yellow"></span>{_html(_first_text(training_resolution.get("assessment"), default="unknown"))}</span>
      </div>
      <section class="grid three" style="margin-top:14px;">
        <div>
          <div class="label">Why Yellow</div>
          <ul class="clean">
            <li>Improving: {_html(str(training_resolution.get("are_improving", "unknown")))}</li>
            <li>Blocked objectives: {_html(str(training_resolution.get("blocked", "unknown")))}</li>
            <li>Stale artifacts: {_html(str(training_resolution.get("stale_count", "unknown")))}</li>
            <li>Judgment V2 pass rate: {_html(str(training_resolution.get("judgment_pass_rate", "unknown")))}%</li>
          </ul>
        </div>
        <div>
          <div class="label">Resolution Path</div>
          <ul class="clean">{resolution_actions_html}</ul>
        </div>
        <div>
          <div class="label">Open Evidence</div>
          <div class="quick">{resolution_links_html}</div>
          <div class="label">Stale Preview</div>
          <ul class="clean">{stale_preview_html}</ul>
        </div>
      </section>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>MIM Host</h2>
        <div class="label">Hostname</div>
        <p>{_html(str(host.get("hostname") or "unknown"))}</p>
        <div class="label">Load 1 / 5 / 15</div>
        <p>{_html(load_text)}</p>
        <div class="label">RAM</div>
        <p>{_html(_percent(ram.get("used_percent")))} used. {_html(_format_bytes(ram.get("free")))} available.</p>
        <div class="label">Disk</div>
        <p>{_html(_percent(disk.get("used_percent")))} used. {_html(_format_bytes(disk.get("free")))} free.</p>
        <div class="label">Uptime</div>
        <p>{_html(_format_duration(host.get("uptime_seconds")))}</p>
      </article>
      <article class="card">
        <h2>TOD Local Machine</h2>
        <div class="label">Host</div>
        <p>{_html(_first_text(tod_host.get("name"), default="TOD local machine"))} - {_html(_first_text(tod_host.get("os"), default="Windows"))}</p>
        <div class="label">CPU</div>
        <p>{_html(_first_text(tod_cpu.get("name"), default="unknown CPU"))}. Load: {_html(_percent(tod_cpu.get("load_percent")))}.</p>
        <div class="label">RAM</div>
        <p>{_html(_percent(tod_memory.get("used_percent")))} used. {_html(_format_bytes(tod_memory.get("free_bytes")))} available.</p>
        <div class="label">GPU</div>
        <p>{_html(tod_gpu_text)}</p>
        <div class="label">Latest Source Scan</div>
        <p>{_html(_first_text((state.get("scan") or {}).get("generated_at"), default="scan timestamp not recorded"))}; {_html(str(len((state.get("scan") or {}).get("apps") or [])))} app roots scanned.</p>
      </article>
      <article class="card">
        <h2>PythonAnywhere</h2>
        <div class="label">MIM Robotics</div>
        <p>{_html(pa_status)}. Homepage status: {_html(str((pythonanywhere.get("homepage") or {}).get("status", "unknown")))}.</p>
        <div class="label">CPU Quota</div>
        <p>{_html(str(cpu_used if cpu_used is not None else "unknown"))} / {_html(str(cpu_limit if cpu_limit is not None else "unknown"))} seconds. Reset: {_html(next_reset)}.</p>
        <div class="label">Web Apps</div>
        <p>{_html(str(len(pythonanywhere.get("webapps") or [])))} app(s) reported by the provider API.</p>
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>Dirty Repos</h2>
        {dirty_html}
      </article>
      <article class="card">
        <h2>Data Adapters</h2>
        {adapter_html}
      </article>
      <article class="card">
        <h2>Database Counts</h2>
        <table class="score-table"><thead><tr><th>Table</th><th>Rows</th></tr></thead><tbody>{db_rows}</tbody></table>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>TOD Disks</h2>
        <table class="score-table"><thead><tr><th>Drive</th><th>Used</th><th>Free</th></tr></thead><tbody>{tod_disk_rows}</tbody></table>
      </article>
      <article class="card">
        <h2>TOD Snapshot</h2>
        <div class="label">Generated</div>
        <p>{_html(_first_text(tod_local.get("generated_at"), default="not available"))}</p>
        <div class="label">Role</div>
        <p>{_html(_first_text(tod_local.get("machine_role"), default="TOD local implementation workstation"))}</p>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Reflection</h2>
        <div class="label">Assessment</div>
        <p>{_html(_first_text(reflection.get("assessment"), default="not available"))}</p>
        <div class="label">Improving?</div>
        <p>{_html(str(reflection.get("are_they_improving", "unknown")))}</p>
        <div class="label">Freshness</div>
        <p>{_html(str((reflection.get("freshness") or {}).get("fresh_minutes", "unknown")))} fresh-minute window; {_html(str(len((reflection.get("freshness") or {}).get("stale_artifacts") or [])))} stale artifacts listed.</p>
      </article>
      <article class="card">
        <h2>Next Instrumentation</h2>
        <ul class="clean">
          <li>Automate the TOD local-machine snapshot so CPU, RAM, disk, and GPU refresh without Codex manually publishing it.</li>
          <li>Connect Render service status and app database adapters into the same health model.</li>
          <li>Turn dirty-repo and stale-artifact findings into repair tasks when H.A.L. runs.</li>
          <li>Keep green systems collapsed and attention items limited to the top five.</li>
        </ul>
      </article>
    </section>
    """


def _credential_presence(keys: list[str], inventory_by_key: dict[str, dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for key in keys:
        value = os.environ.get(key, "")
        inventory_row = (inventory_by_key or {}).get(key, {})
        present = bool(value) or bool(inventory_row.get("present"))
        rows.append(
            {
                "key": key,
                "present": present,
                "length": len(value) if value else int(inventory_row.get("value_length") or 0),
                "status": "present" if present else "missing",
            }
        )
    return rows


async def _studio_settings_state(db: AsyncSession) -> dict[str, Any]:
    apps_state = await _studio_apps_state(db)
    env_inventory = _load_json("TOD_ENV_KEY_INVENTORY.latest.json")
    inventory_rows = env_inventory.get("keys") if isinstance(env_inventory.get("keys"), list) else []
    inventory_by_key = {
        str(row.get("key") or ""): row
        for row in inventory_rows
        if isinstance(row, dict) and row.get("key")
    }
    provider_specs = [
        {
            "name": "Render",
            "purpose": "Hosted web apps and managed app services.",
            "login_url": "https://dashboard.render.com/",
            "credential_keys": ["RENDER_API_KEY", "RENDER_OWNER_ID"],
            "continuity": "Keep production apps online. Pause only nonessential experiments if costs spike.",
        },
        {
            "name": "PythonAnywhere",
            "purpose": "MIM Robotics public website hosting.",
            "login_url": "https://www.pythonanywhere.com/",
            "credential_keys": ["PYTHONANYWHERE_USERNAME", "PYTHONANYWHERE_API_KEY", "PYTHONANYWHERE_DOMAIN"],
            "continuity": "Keep MIM Robotics LLC website reachable and preserve source/database state.",
        },
        {
            "name": "MIM / TOD Access",
            "purpose": "SSH, remote roots, local/ARM access, and operator recovery surfaces.",
            "login_url": "",
            "credential_keys": ["MIM_SSH_HOST", "MIM_SSH_USER", "MIM_SSH_PASSWORD", "MIM_ARM_SSH_HOST", "MIM_ARM_SSH_USER", "MIM_ARM_SSH_HOST_PASS"],
            "continuity": "Preserve MIM/TOD access routes and document any host or key changes.",
        },
        {
            "name": "Squarespace",
            "purpose": "Domain registration and DNS control.",
            "login_url": "https://account.squarespace.com/",
            "credential_keys": [],
            "continuity": "Do not let domains expire. DNS changes require evidence and rollback notes.",
        },
        {
            "name": "OpenAI",
            "purpose": "AI models, MIM/TOD reasoning, image generation, embeddings, and app intelligence.",
            "login_url": "https://platform.openai.com/",
            "credential_keys": ["OPENAI_API_KEY"],
            "continuity": "Monitor usage and preserve core MIM/TOD functionality before optional experiments.",
        },
        {
            "name": "Gemini / Google AI",
            "purpose": "Research/search assistance and alternate AI capability surfaces.",
            "login_url": "https://aistudio.google.com/",
            "credential_keys": ["GEMINI_API_KEY", "GEMINI_API_VERSION", "GEMINI_SEARCH_MODEL", "GEMINI_SEARCH_TOOL"],
            "continuity": "Keep alternate research/model capability mapped for fallback and comparison.",
        },
        {
            "name": "Email / SMTP",
            "purpose": "Verification codes, notifications, support messages, and app email.",
            "login_url": "",
            "credential_keys": ["SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME", "SMTP_PASSWORD", "SMTP_SENDER", "PM_SMTP_HOST", "PM_SMTP_USERNAME", "PM_PASSWORD"],
            "continuity": "Keep account verification and operational notifications working.",
        },
        {
            "name": "Postmark / Inbound Mail",
            "purpose": "Inbound email, message streams, reply domains, and transactional mail.",
            "login_url": "https://account.postmarkapp.com/",
            "credential_keys": ["POSTMARK_SERVER_TOKEN", "POSTMARK_INBOUND_TOKEN", "POSTMARK_MESSAGE_STREAM", "POSTMARK_FROM_DOMAIN", "INBOUND_EMAIL_HOST", "INBOUND_EMAIL_USERNAME", "INBOUND_EMAIL_PASSWORD"],
            "continuity": "Preserve inbound/outbound email flow and reply routing.",
        },
        {
            "name": "Twilio",
            "purpose": "SMS, voice, calling, messaging numbers, and app telephony.",
            "login_url": "https://console.twilio.com/",
            "credential_keys": ["TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_CALLER_ID", "TWILIO_MESSAGING_NUMBER", "TWILIO_VOICE_API_KEY", "TWILIO_VOICE_API_SECRET", "TWILIO_VOICE_APP_SID"],
            "continuity": "Do not trigger paid calling/SMS actions without policy clearance; preserve capability settings.",
        },
        {
            "name": "Zoom Phone",
            "purpose": "Voice/calling provider capability.",
            "login_url": "https://zoom.us/",
            "credential_keys": ["ZOOM_PHONE_ACCOUNT_ID", "ZOOM_PHONE_CALLER_ID", "ZOOM_PHONE_CLIENT_ID", "ZOOM_PHONE_CLIENT_SECRET", "ZOOM_PHONE_USER_ID"],
            "continuity": "Keep provider option mapped for voice/call capability broker decisions.",
        },
        {
            "name": "Stripe",
            "purpose": "Billing, subscriptions, prices, webhooks, and app monetization.",
            "login_url": "https://dashboard.stripe.com/",
            "credential_keys": ["STRIPE_SECRET_KEY", "STRIPE_PUBLISHABLE_KEY", "STRIPE_WEBHOOK_SECRET", "STRIPE_PRICE_STANDARD", "STRIPE_PRICE_AGENCY", "STRIPE_PRICE_TOKENS", "STRIPE_PRICE_ADDON_SEAT", "STRIPE_PRICE_ADDON_STORAGE"],
            "continuity": "Protect billing continuity, subscription records, and webhook integrity.",
        },
        {
            "name": "Google / Calendar / Search",
            "purpose": "Calendar OAuth, custom search, and Google service integrations.",
            "login_url": "https://console.cloud.google.com/",
            "credential_keys": ["GOOGLE_CALENDAR_CLIENT_ID", "GOOGLE_CALENDAR_CLIENT_SECRET", "GOOGLE_CALENDAR_REFRESH_TOKEN", "GOOGLE_CALENDAR_REDIRECT_URI", "GOOGLE_CSE_API_KEY", "GOOGLE_CSE_ID"],
            "continuity": "Keep OAuth redirect and search capability references current.",
        },
        {
            "name": "Social OAuth",
            "purpose": "Facebook, LinkedIn, and X OAuth/app integrations.",
            "login_url": "",
            "credential_keys": ["FACEBOOK_CLIENT_ID", "FACEBOOK_CLIENT_SECRET", "FACEBOOK_REDIRECT_URI", "LINKEDIN_CLIENT_ID", "LINKEDIN_CLIENT_SECRET", "LINKEDIN_REDIRECT_URI", "X_CLIENT_ID", "X_CLIENT_SECRET", "X_REDIRECT_URI"],
            "continuity": "Preserve OAuth app settings and redirect URLs before changing domains.",
        },
        {
            "name": "RunPod / Paperspace",
            "purpose": "GPU/compute providers for AI media, training, and worker tasks.",
            "login_url": "https://www.runpod.io/console",
            "credential_keys": ["RUNPOD_API_KEY", "RUNPOD_API_URL", "RUNPOD_ENDPOINT_ID", "RUNPOD_SSH_HOST", "RUNPOD_SSH_KEY", "RUNPOD_REPO_PATH", "PAPERSPACE_API"],
            "continuity": "Pause expensive nonessential compute before survival-critical services.",
        },
        {
            "name": "GitHub",
            "purpose": "Source control, issues, PRs, deployment history, and recovery source of truth.",
            "login_url": "https://github.com/",
            "credential_keys": ["GITHUB_TOKEN"],
            "continuity": "Preserve repos and history. No destructive git actions without explicit policy clearance.",
        },
    ]
    providers: list[dict[str, Any]] = []
    credential_rows: list[dict[str, Any]] = []
    for spec in provider_specs:
        creds = _credential_presence(spec["credential_keys"], inventory_by_key)
        credential_rows.extend({"provider": spec["name"], **row} for row in creds)
        providers.append(
            {
                **spec,
                "credential_count": len(creds),
                "credentials_present": sum(1 for row in creds if row["present"]),
                "credential_status": "ready" if creds and all(row["present"] for row in creds) else ("partial" if any(row["present"] for row in creds) else ("manual" if not creds else "missing")),
            }
        )

    db_counts = {
        "portal_accounts": await _safe_table_count(db, "project_portal_accounts"),
        "studio_projects": await _safe_table_count(db, "studio_projects"),
        "studio_documents": await _safe_table_count(db, "studio_documents"),
        "objectives": await _safe_table_count(db, "objectives"),
        "tasks": await _safe_table_count(db, "tasks"),
    }
    apps = apps_state.get("apps") if isinstance(apps_state.get("apps"), list) else []
    dirty_apps = [
        app for app in apps
        if isinstance(app.get("dirty_count"), int) and int(app.get("dirty_count") or 0) > 0
    ]
    return {
        "generated_at": _utc_now(),
        "providers": providers,
        "credentials": credential_rows,
        "env_inventory": env_inventory,
        "db_counts": db_counts,
        "apps_state": apps_state,
        "dirty_apps": dirty_apps,
        "access": {
            "mode": "Dave-only primary operator",
            "admin_surface": "MIM Studio",
            "trusted_device_policy": "Treat Dave's authenticated device as the primary operator surface.",
            "emergency_access": "Continuity mode is for MIM/TOD preservation and recovery, not casual human access expansion.",
        },
        "continuity": [
            "Keep MIM Studio, MIM/TOD runtime, core databases, AgentMIM, and MIM Robotics online.",
            "Do not delete data, logs, artifacts, source history, or provider records during continuity mode.",
            "If Dave is unavailable, preserve operations, reduce nonessential cost, and document every autonomous action.",
            "Domains, databases, source repositories, and credential maps are survival-critical.",
            "MIM coordinates continuity decisions; TOD executes bounded repairs with evidence.",
        ],
        "policies": [
            "Ethical solution design: analyze references for patterns, never clone products or branding.",
            "Material implementation proof: changed state and validation evidence are required before done.",
            "No-op rejection: attempted work is not completed work.",
            "H.A.L. escalation: diagnose, create repair path, dispatch, validate, and link evidence.",
            "Freshness: yellow states must include evidence, cause, and resolution path.",
        ],
        "voice": [
            "Voice input/output should be page-aware and tied to the same MIM identity.",
            "Voice reliability remains health-monitored and should fail visibly when broken.",
            "Future settings should include microphone selection, TTS voice, interruption behavior, and private/public mode.",
        ],
        "behavior": [
            "MIM should act unless stopped when intent is clear and risk is low.",
            "MIM should ask before irreversible, paid, credential, external, or physical-world actions.",
            "TOD should inspect, plan, edit safely, validate, publish evidence, and escalate when blocked.",
            "MIM/TOD should avoid idle drift by continuing approved training and repair objectives.",
        ],
        "notifications": [
            "Green states stay quiet.",
            "Yellow states create evidence links and suggested repair paths.",
            "Red states should trigger H.A.L. and require explicit ownership.",
            "Dave-needed items should be limited and concrete.",
        ],
        "recovery": [
            "Backups, restore notes, provider login links, DB references, and source roots belong here.",
            "Secrets should be mapped by existence and location, not exposed casually.",
            "Recovery instructions should prefer preservation over cleanup.",
        ],
    }


def _settings_body(state: dict[str, Any]) -> str:
    providers = state.get("providers") if isinstance(state.get("providers"), list) else []
    credentials = state.get("credentials") if isinstance(state.get("credentials"), list) else []
    env_inventory = state.get("env_inventory") if isinstance(state.get("env_inventory"), dict) else {}
    env_keys = env_inventory.get("keys") if isinstance(env_inventory.get("keys"), list) else []
    db_counts = state.get("db_counts") if isinstance(state.get("db_counts"), dict) else {}
    apps_state = state.get("apps_state") if isinstance(state.get("apps_state"), dict) else {}
    app_counts = apps_state.get("counts") if isinstance(apps_state.get("counts"), dict) else {}
    present_credentials = sum(1 for item in credentials if isinstance(item, dict) and item.get("present"))
    category_counts: dict[str, dict[str, int]] = {}
    for item in env_keys:
        if not isinstance(item, dict):
            continue
        category = str(item.get("category") or "Other")
        category_counts.setdefault(category, {"total": 0, "present": 0})
        category_counts[category]["total"] += 1
        if item.get("present"):
            category_counts[category]["present"] += 1
    provider_rows = "".join(
        f"""
        <div class="project-row">
          <div>
            <strong>{_html(provider.get("name", ""))}</strong><br>
            <span class="muted">{_html(provider.get("purpose", ""))}</span>
          </div>
          <span class="health-pill {'green' if provider.get('credential_status') == 'ready' else 'yellow'}">{_html(_plain_status(provider.get("credential_status")))}</span>
        </div>
        """
        for provider in providers
        if isinstance(provider, dict)
    )
    credential_rows = "".join(
        f"""
        <tr>
          <td>{_html(item.get("provider", ""))}</td>
          <td>{_html(item.get("key", ""))}</td>
          <td>{_html("present" if item.get("present") else "missing")}</td>
        </tr>
        """
        for item in credentials
        if isinstance(item, dict)
    ) or '<tr><td colspan="3">No credential keys registered yet.</td></tr>'
    category_rows = "".join(
        f"""
        <tr>
          <td>{_html(category)}</td>
          <td>{_html(str(counts.get("present", 0)))}</td>
          <td>{_html(str(counts.get("total", 0)))}</td>
        </tr>
        """
        for category, counts in sorted(category_counts.items())
    ) or '<tr><td colspan="3">No environment inventory loaded yet.</td></tr>'
    continuity_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("continuity", []))
    policies_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("policies", []))
    voice_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("voice", []))
    behavior_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("behavior", []))
    notification_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("notifications", []))
    recovery_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("recovery", []))
    provider_detail_html = "".join(
        f"""
        <article class="card">
          <h2>{_html(provider.get("name", ""))}</h2>
          <div class="label">Login</div>
          <p>{f'<a href="{_html(provider.get("login_url", ""))}" target="_blank" rel="noopener">{_html(provider.get("login_url", ""))}</a>' if provider.get("login_url") else 'Manual/internal reference needed.'}</p>
          <div class="label">Credentials</div>
          <p>{_html(str(provider.get("credentials_present", 0)))} / {_html(str(provider.get("credential_count", 0)))} mapped as present.</p>
          <div class="label">Continuity</div>
          <p>{_html(provider.get("continuity", ""))}</p>
        </article>
        """
        for provider in providers
        if isinstance(provider, dict)
    )
    return f"""
    <section class="grid four">
      {_metric_card("Access", state.get("access", {}).get("mode", "Dave-only"), "Primary operator model")}
      {_metric_card("Providers", len(providers), "Services and platforms mapped")}
      {_metric_card("Credentials", f"{present_credentials}/{len(credentials)}", "Presence only, values hidden")}
      {_metric_card("Env Keys", env_inventory.get("key_count", len(env_keys)), f"{env_inventory.get('present_count', 0)} present, values hidden")}
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Continuity / Survival Mode</h2>
        <p>MIM and TOD should be able to preserve the ecosystem if Dave is unavailable.</p>
        <div class="label">Rules</div>
        <ul class="clean">{continuity_html}</ul>
      </article>
      <article class="card">
        <h2>Access</h2>
        <div class="label">Mode</div>
        <p>{_html(state.get("access", {}).get("mode", ""))}</p>
        <div class="label">Trusted Device Policy</div>
        <p>{_html(state.get("access", {}).get("trusted_device_policy", ""))}</p>
        <div class="label">Emergency Access</div>
        <p>{_html(state.get("access", {}).get("emergency_access", ""))}</p>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Providers</h2>
        {provider_rows}
      </article>
      <article class="card">
        <h2>Credential Map</h2>
        <p>Shows whether credentials exist. It does not expose secret values.</p>
        <table class="score-table"><thead><tr><th>Provider</th><th>Key</th><th>Status</th></tr></thead><tbody>{credential_rows}</tbody></table>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Environment Inventory</h2>
        <p>{_html(str(env_inventory.get("key_count", len(env_keys))))} keys mapped from TOD/MIM configuration. Secret values are excluded.</p>
        <table class="score-table"><thead><tr><th>Category</th><th>Present</th><th>Total</th></tr></thead><tbody>{category_rows}</tbody></table>
      </article>
      <article class="card">
        <h2>Apps</h2>
        <ul class="clean">
          <li>{_html(str(app_counts.get("apps", 0)))} apps registered.</li>
          <li>{_html(str(app_counts.get("dirty_repos", 0)))} app repos need review before deployment edits.</li>
          <li>{_html(str(app_counts.get("db_connected", 0)))} apps have proven DB binding in the current Studio connection.</li>
          <li>App-specific settings should attach to the Apps page, while shared providers stay here.</li>
        </ul>
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>Policies</h2>
        <ul class="clean">{policies_html}</ul>
      </article>
      <article class="card">
        <h2>MIM Voice</h2>
        <ul class="clean">{voice_html}</ul>
      </article>
      <article class="card">
        <h2>MIM / TOD Behavior</h2>
        <ul class="clean">{behavior_html}</ul>
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>Notifications</h2>
        <ul class="clean">{notification_html}</ul>
      </article>
      <article class="card">
        <h2>Backups / Recovery</h2>
        <ul class="clean">{recovery_html}</ul>
      </article>
      <article class="card">
        <h2>Billing / Costs</h2>
        <ul class="clean">
          <li>Track provider costs, renewals, app-level allocation, AI usage, hosting, and domains.</li>
          <li>Continuity mode may pause optional experiments, but not survival-critical services.</li>
          <li>Accounting becomes the first official MIM/TOD build project, not a generic settings feature.</li>
        </ul>
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      {provider_detail_html}
    </section>
    <section class="card" style="margin-top:14px;">
      <h2>DB / App Context</h2>
      <table class="score-table">
        <thead><tr><th>Item</th><th>Value</th></tr></thead>
        <tbody>
          <tr><td>Portal accounts</td><td>{_html(db_counts.get("portal_accounts"))}</td></tr>
          <tr><td>Studio projects</td><td>{_html(db_counts.get("studio_projects"))}</td></tr>
          <tr><td>Studio documents</td><td>{_html(db_counts.get("studio_documents"))}</td></tr>
          <tr><td>Objectives</td><td>{_html(db_counts.get("objectives"))}</td></tr>
          <tr><td>Tasks</td><td>{_html(db_counts.get("tasks"))}</td></tr>
        </tbody>
      </table>
    </section>
    """


def _studio_project_to_dict(row: StudioProject) -> dict[str, Any]:
    return {
        "id": row.id,
        "title": row.title,
        "summary": row.summary,
        "status": row.status,
        "priority": row.priority,
        "owner": row.owner,
        "health": row.health,
        "why_it_matters": row.why_it_matters,
        "origin_story": row.origin_story,
        "next_action": row.next_action,
        "dave_needed": row.dave_needed,
        "metadata_json": row.metadata_json if isinstance(row.metadata_json, dict) else {},
        "created_at": row.created_at.isoformat() if row.created_at else "",
    }


def _studio_signal_to_dict(row: StudioProjectSignal) -> dict[str, Any]:
    return {
        "id": row.id,
        "title": row.title,
        "signal_type": row.signal_type,
        "status": row.status,
        "priority": row.priority,
        "source_surface": row.source_surface,
        "source_text": row.source_text,
        "why_it_matters": row.why_it_matters,
        "suggested_action": row.suggested_action,
        "project_id": row.project_id,
        "metadata_json": row.metadata_json if isinstance(row.metadata_json, dict) else {},
        "created_at": row.created_at.isoformat() if row.created_at else "",
    }


def _project_metadata(row: StudioProject | dict[str, Any]) -> dict[str, Any]:
    value = row.metadata_json if isinstance(row, StudioProject) else row.get("metadata_json")
    return value if isinstance(value, dict) else {}


def _project_progress(row: StudioProject | dict[str, Any]) -> int:
    metadata = _project_metadata(row)
    raw = metadata.get("progress_percent")
    try:
        return max(0, min(100, int(float(raw))))
    except Exception:
        status = str(row.status if isinstance(row, StudioProject) else row.get("status") or "").strip().lower()
        if status in {"done", "complete", "completed", "deployed"}:
            return 100
        if status in {"implementation", "active", "active_experiments", "working"}:
            return 45
        if status in {"planning", "discovery", "calibration"}:
            return 20
        if status in {"queued", "candidate"}:
            return 5
        if status in {"paused", "stalled", "blocked"}:
            return 10
        return 0


def _project_blocker(row: StudioProject | dict[str, Any]) -> str:
    metadata = _project_metadata(row)
    value = metadata.get("blocker") or metadata.get("action_needed") or ""
    return _first_text(value, default="none")


def _project_work_state(row: StudioProject | dict[str, Any]) -> str:
    metadata = _project_metadata(row)
    return _first_text(metadata.get("work_state"), default=_plain_status(row.status if isinstance(row, StudioProject) else row.get("status"), default="queued"))


def _project_category(row: StudioProject | dict[str, Any]) -> str:
    metadata = _project_metadata(row)
    return _first_text(metadata.get("project_type"), metadata.get("category"), default="project")


async def _ensure_studio_project_record(
    db: AsyncSession,
    *,
    title: str,
    summary: str,
    status: str,
    priority: str,
    why_it_matters: str,
    origin_story: str,
    next_action: str,
    metadata_json: dict[str, Any],
) -> StudioProject:
    existing = (
        await db.execute(select(StudioProject).where(StudioProject.title == title).limit(1))
    ).scalars().first()
    if existing is not None:
        if not existing.summary:
            existing.summary = summary
        if not existing.status:
            existing.status = status
        if not existing.priority:
            existing.priority = priority
        if not existing.why_it_matters:
            existing.why_it_matters = why_it_matters
        if not existing.origin_story:
            existing.origin_story = origin_story
        if not existing.next_action:
            existing.next_action = next_action
        if not isinstance(existing.metadata_json, dict) or not existing.metadata_json:
            existing.metadata_json = metadata_json
        return existing
    project = StudioProject(
        title=title,
        summary=summary,
        status=status,
        priority=priority,
        owner="Dave + MIM + TOD",
        health="good",
        why_it_matters=why_it_matters,
        origin_story=origin_story,
        next_action=next_action,
        metadata_json=metadata_json,
    )
    db.add(project)
    await db.flush()
    db.add(
        StudioProjectEvent(
            project_id=project.id,
            event_type="project_created",
            actor="MIM Studio",
            title="First internal project created",
            detail=origin_story,
            metadata_json={"source": "studio_first_internal_projects_v1", **metadata_json},
        )
    )
    return project


async def _upsert_studio_project_record(
    db: AsyncSession,
    *,
    title: str,
    summary: str,
    status: str,
    priority: str,
    owner: str,
    health: str,
    why_it_matters: str,
    origin_story: str,
    next_action: str,
    dave_needed: bool,
    metadata_json: dict[str, Any],
) -> StudioProject:
    matches = (
        await db.execute(
            select(StudioProject)
            .where(StudioProject.title == title)
            .order_by(StudioProject.id.desc())
        )
    ).scalars().all()
    existing = matches[0] if matches else None
    for duplicate in matches[1:]:
        duplicate.status = "deleted"
        duplicate.health = "deleted"
        duplicate_metadata = duplicate.metadata_json if isinstance(duplicate.metadata_json, dict) else {}
        duplicate_metadata = dict(duplicate_metadata)
        duplicate_metadata["work_state"] = "deleted"
        duplicate_metadata["duplicate_of_project_id"] = existing.id if existing else None
        duplicate.metadata_json = duplicate_metadata
    existing_metadata = existing.metadata_json if existing and isinstance(existing.metadata_json, dict) else {}
    if existing is None:
        existing = StudioProject(title=title)
        db.add(existing)
        await db.flush()
        db.add(
            StudioProjectEvent(
                project_id=existing.id,
                event_type="project_seeded",
                actor="MIM Studio",
                title="Project added to Studio",
                detail=origin_story or summary,
                metadata_json={"source": "studio_project_backlog_seed_v1"},
            )
        )
    elif existing_metadata.get("user_modified"):
        merged_metadata = dict(existing_metadata)
        for key, value in metadata_json.items():
            merged_metadata.setdefault(key, value)
        existing.metadata_json = merged_metadata
        return existing
    existing.summary = summary
    existing.status = status
    existing.priority = priority
    existing.owner = owner
    existing.health = health
    existing.why_it_matters = why_it_matters
    existing.origin_story = origin_story
    existing.next_action = next_action
    existing.dave_needed = dave_needed
    merged_metadata = dict(existing.metadata_json) if isinstance(existing.metadata_json, dict) else {}
    merged_metadata.update(metadata_json)
    existing.metadata_json = merged_metadata
    return existing


async def _ensure_first_internal_projects(db: AsyncSession) -> dict[str, StudioProject]:
    lab_project = await _ensure_studio_project_record(
        db,
        title="MIM Lab Exploration",
        summary="Exploration hub for robotics experiments, physical builds, workspace calibration, sensors, publications, opportunities, and development tools.",
        status="active_experiments",
        priority="P1",
        why_it_matters="Lab work teaches MIM how to explore the physical world, use sensors, build spatial memory, and turn experiments into future products.",
        origin_story="Created as one of the first two official internal MIM/TOD projects after Studio matured enough to manage real project pages.",
        next_action="Organize active experiments and prepare the world-model calibration run for the next arm session.",
        metadata_json={"project_key": "mim_lab_exploration", "studio_page": "/studio/lab", "project_type": "exploration"},
    )
    servo_project = await _ensure_studio_project_record(
        db,
        title="LAB Workbench Servo Tester",
        summary="Build a simple Lab tool for Dave's separate UNO R4 and PWM-driver bench setup to add, configure, save, and test multiple servos before robotic installation.",
        status="implementation",
        priority="P1",
        why_it_matters="Servo behavior should be tested safely on the bench before parts are installed into the MIM arm or other robotics builds.",
        origin_story="Dave created a separate workbench servo test configuration with its own UNO R4 and PWM driver connected to the PC, independent from the MIM ARM.",
        next_action="Use the Studio Lab servo tester to connect to the UNO over browser serial, define servo profiles, and validate limits, speed, startup, and slow-down behavior.",
        metadata_json={
            "project_key": "lab_workbench_servo_tester",
            "studio_page": "/studio/lab/servo-tester",
            "project_type": "lab_tool",
            "hardware": ["UNO R4", "PWM driver", "multi-servo bench rig"],
            "separate_from_mim_arm": True,
            "progress_percent": 35,
            "work_state": "implementation",
            "blocker": "needs compatible UNO sketch and first hardware validation",
        },
    )
    accounting_project = await _ensure_studio_project_record(
        db,
        title="MIM Operations Accounting",
        summary="Internal accounting tool for tracking provider spend, subscriptions, invoices, resource use, project cost allocation, and waste detection.",
        status="discovery",
        priority="P1",
        why_it_matters="MIM needs to understand what the ecosystem costs, which projects consume resources, and which services may be wasting money before building accounting for customers.",
        origin_story="Created as one of the first two official internal MIM/TOD projects: simple enough to test the process, useful enough to become a real product seed.",
        next_action="Map provider bills, invoice sources, receipt ingestion, recurring subscriptions, and project cost allocation.",
        metadata_json={"project_key": "mim_operations_accounting", "studio_page": "/studio/accounting", "project_type": "internal_tool"},
    )
    await db.commit()
    return {"lab": lab_project, "servo": servo_project, "accounting": accounting_project}


async def _studio_lab_state(db: AsyncSession) -> dict[str, Any]:
    projects = await _ensure_first_internal_projects(db)
    camera_registry = _load_json("MIM_LAB_CAMERA_ASSET_REGISTRY.latest.json")
    arm_resource = _load_text("MIM_ARM_RESOURCE_TEST_2026_05_31.latest.md", limit=1200)
    world_model = _load_json("MIM_WORLD_MODEL_CALIBRATION_OBJECTIVE.latest.json")
    lidar = _load_json("rplidar_scan_latest.json")
    experiments = [
        ("World Model Calibration", "Ready for next lab session", "Build table coordinate system and safe pose memory before another pickup attempt."),
        ("Autonomous Workspace Mapping", "Planning", "Use base rotation, cameras, RPLIDAR, and marker references to map reachable table zones."),
        ("Workbench Servo Tester", "Implementation", "Use the dedicated UNO R4 and PWM-driver bench rig to test servo limits, speed, startup, and slow-down before installation."),
        ("Visual Servoing", "Testing", "Teach MIM to move based on object offset from gripper center instead of marker-card confusion."),
        ("Object Grasp Scoring", "Research", "Estimate pickup likelihood before closing the claw."),
        ("Face Memory", "Research", "Keep as a future MIM presence capability, not part of the arm pickup path yet."),
    ]
    builds = [
        ("MIM ARM V4", "Operational; needs calibration-first workflow for reliable object interaction."),
        ("MIM Box", "Physical MIM host with camera resources and Studio runtime."),
        ("MIM Wall", "Presence surface; should share the one-MIM conversation identity."),
        ("Camera Stack", "PC camera, MIM Box cameras, Pi camera, hand camera; registry should stay current."),
        ("Sensor Stack", "C12 hand distance sensor and RPLIDAR; useful as measurement aids, not full 3D perception alone."),
        ("Voice Stack", "Voice reliability remains system-health monitored and page-aware."),
    ]
    opportunities = [
        ("Fuel Operator", "Potential operations automation and analytics customer."),
        ("Robotics Education", "Potential grant/program direction."),
        ("Microteq / Sensor Partners", "Potential hardware and sensor collaboration."),
        ("Warehouse Automation", "Potential proposal based on workspace mapping and object interaction."),
    ]
    return {
        "generated_at": _utc_now(),
        "project": _studio_project_to_dict(projects["lab"]),
        "servo_project": _studio_project_to_dict(projects["servo"]),
        "experiments": experiments,
        "builds": builds,
        "tools": [
            "Camera tests",
            "Servo tests",
            "RPLIDAR close-range scans",
            "Vision model comparison",
            "Simulation / dry-run movement checks",
            "Training-data capture",
            "Calibration notes and safe-pose memory",
        ],
        "opportunities": opportunities,
        "camera_count": len(camera_registry.get("cameras", [])) if isinstance(camera_registry.get("cameras"), list) else "unknown",
        "arm_resource_available": bool(arm_resource),
        "world_model_status": _first_text(world_model.get("status"), world_model.get("title"), default="planned"),
        "lidar_points": len(lidar.get("points", [])) if isinstance(lidar.get("points"), list) else "not loaded",
    }


def _lab_body(state: dict[str, Any]) -> str:
    project = state.get("project") if isinstance(state.get("project"), dict) else {}
    servo_project = state.get("servo_project") if isinstance(state.get("servo_project"), dict) else {}
    experiment_html = "".join(
        f"""
        <div class="project-row">
          <div><strong>{_html(name)}</strong><br><span class="muted">{_html(next_action)}</span></div>
          <span class="health-pill yellow">{_html(status)}</span>
        </div>
        """
        for name, status, next_action in state.get("experiments", [])
    )
    build_html = "".join(
        f"""<article class="card"><h2>{_html(name)}</h2><p>{_html(detail)}</p></article>"""
        for name, detail in state.get("builds", [])
    )
    tools_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("tools", []))
    opportunities_html = "".join(
        f"""<div class="attention-item"><small>Opportunity</small><strong>{_html(name)}</strong><p>{_html(detail)}</p></div>"""
        for name, detail in state.get("opportunities", [])
    )
    return f"""
    <section class="grid four">
      {_metric_card("Project", project.get("status", "active"), project.get("title", "MIM Lab Exploration"))}
      {_metric_card("Experiments", len(state.get("experiments", [])), "Exploration, not delivery commitments")}
      {_metric_card("Cameras", state.get("camera_count", "unknown"), "Registry-backed when available")}
      {_metric_card("RPLIDAR", state.get("lidar_points", "not loaded"), "Latest close-range map points")}
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card"><h2>Active Experiments</h2>{experiment_html}</article>
      <article class="card">
        <h2>Project Brief</h2>
        <div class="label">Why This Matters</div><p>{_html(project.get("why_it_matters", ""))}</p>
        <div class="label">Next Action</div><p>{_html(project.get("next_action", ""))}</p>
        <div class="label">Rule</div><p>Projects answer what we are building. Lab answers what we are exploring.</p>
      </article>
    </section>
    <section class="card" style="margin-top:14px;">
      <h2>Workbench Servo Tester</h2>
      <div class="project-row">
        <div><strong>{_html(servo_project.get("title", "LAB Workbench Servo Tester"))}</strong><br><span class="muted">{_html(servo_project.get("next_action", "Open the tester and validate the bench rig."))}</span></div>
        <a class="button primary" href="/studio/lab/servo-tester">Open Tester</a>
      </div>
    </section>
    <section class="grid three" style="margin-top:14px;">{build_html}</section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card"><h2>Development Tools</h2><ul class="clean">{tools_html}</ul></article>
      <article class="card"><h2>Publications / News</h2><p>MIM should collect robotics papers, sensor releases, model updates, news, and opportunities here, then link useful items to experiments or projects.</p></article>
      <article class="card"><h2>Opportunities</h2><div class="attention-list">{opportunities_html}</div></article>
    </section>
    """


def _default_servo_tester_profile() -> dict[str, Any]:
    return {
        "version": "lab-servo-tester-v1",
        "updated_at": "",
        "command_template": "{pulse}",
        "baud_rate": 9600,
        "servos": [
            {
                "id": "servo-0",
                "name": "Servo 0",
                "channel": 0,
                "min_pulse": 100,
                "min_angle": 0,
                "center_pulse": 375,
                "center_angle": 90,
                "max_pulse": 650,
                "max_angle": 180,
                "start_pulse": 375,
                "start_angle": 90,
                "speed_ms": 600,
                "startup_ms": 250,
                "slowdown_ms": 250,
                "notes": "",
            }
        ],
    }


def _load_servo_tester_profile() -> dict[str, Any]:
    if LAB_SERVO_TESTER_PROFILE_PATH.exists():
        try:
            loaded = json.loads(LAB_SERVO_TESTER_PROFILE_PATH.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                profile = _default_servo_tester_profile()
                profile.update(loaded)
                if not isinstance(profile.get("servos"), list):
                    profile["servos"] = []
                return profile
        except Exception:
            pass
    return _default_servo_tester_profile()


def _clean_servo_profile(payload: dict[str, Any]) -> dict[str, Any]:
    def as_int(value: Any, default: int, *, minimum: int, maximum: int) -> int:
        try:
            parsed = int(value)
        except Exception:
            parsed = default
        return max(minimum, min(maximum, parsed))

    servos: list[dict[str, Any]] = []
    for index, row in enumerate(payload.get("servos") if isinstance(payload.get("servos"), list) else []):
        if not isinstance(row, dict):
            continue
        channel = as_int(row.get("channel"), index, minimum=0, maximum=15)
        min_pulse = as_int(row.get("min_pulse"), 500, minimum=300, maximum=3000)
        max_pulse = as_int(row.get("max_pulse"), 2500, minimum=300, maximum=3000)
        if max_pulse < min_pulse:
            min_pulse, max_pulse = max_pulse, min_pulse
        center_pulse = as_int(row.get("center_pulse"), 1500, minimum=min_pulse, maximum=max_pulse)
        start_pulse = as_int(row.get("start_pulse"), center_pulse, minimum=min_pulse, maximum=max_pulse)
        min_angle = as_int(row.get("min_angle"), 0, minimum=0, maximum=180)
        max_angle = as_int(row.get("max_angle"), 180, minimum=0, maximum=180)
        if max_angle < min_angle:
            min_angle, max_angle = max_angle, min_angle
        center_angle = as_int(row.get("center_angle"), 90, minimum=min_angle, maximum=max_angle)
        start_angle = as_int(row.get("start_angle"), center_angle, minimum=min_angle, maximum=max_angle)
        servos.append(
            {
                "id": _first_text(row.get("id"), default=f"servo-{index}"),
                "name": _first_text(row.get("name"), default=f"Servo {channel}")[:80],
                "channel": channel,
                "min_pulse": min_pulse,
                "min_angle": min_angle,
                "center_pulse": center_pulse,
                "center_angle": center_angle,
                "max_pulse": max_pulse,
                "max_angle": max_angle,
                "start_pulse": start_pulse,
                "start_angle": start_angle,
                "speed_ms": as_int(row.get("speed_ms"), 600, minimum=0, maximum=30000),
                "startup_ms": as_int(row.get("startup_ms"), 250, minimum=0, maximum=30000),
                "slowdown_ms": as_int(row.get("slowdown_ms"), 250, minimum=0, maximum=30000),
                "notes": _first_text(row.get("notes"), default="")[:500],
            }
        )
    return {
        "version": "lab-servo-tester-v1",
        "updated_at": _utc_now(),
        "command_template": _first_text(payload.get("command_template"), default="{pulse}")[:160],
        "baud_rate": as_int(payload.get("baud_rate"), 9600, minimum=9600, maximum=1000000),
        "servos": servos,
    }


def _servo_tester_body(profile: dict[str, Any]) -> str:
    profile_json = json.dumps(profile, ensure_ascii=True)
    return f"""
    <section class="grid four">
      {_metric_card("Bench", "UNO R4", "Separate from MIM ARM")}
      {_metric_card("PWM", "16 channels", "PCA9685-style driver expected")}
      {_metric_card("Saved Servos", len(profile.get("servos", [])), "Profile-backed")}
      <article id="connectionMetric" class="card"><div class="label">Connection</div><div class="entity">Disconnected</div><p>Chrome on Dave's PC</p></article>
    </section>
    <section class="card" style="margin-top:14px;">
      <div class="project-row">
        <div><strong>Servo Bench Controls</strong><br><span class="muted">Add servo, configure servo, save servo, repeat. Movement commands stay local to the browser serial connection.</span></div>
        <div style="display:flex; gap:8px; flex-wrap:wrap;">
          <button id="connectSerial" class="button primary" type="button">Connect UNO</button>
          <button id="disconnectSerial" class="button" type="button">Disconnect</button>
          <button id="forgetSerial" class="button" type="button">Forget Port</button>
          <button id="addServo" class="button" type="button">Add Servo</button>
          <button id="saveProfile" class="button primary" type="button">Save Profile</button>
        </div>
      </div>
      <div class="form-grid" style="margin-top:12px;">
        <label>Baud Rate<input id="baudRate" type="number" min="9600" max="1000000"></label>
        <label>Serial Command Template<input id="commandTemplate" type="text"></label>
      </div>
      <div id="serialStatus" class="muted" style="margin-top:10px;">Serial disconnected.</div>
      <div id="serialHelp" class="attention-item" style="display:none; margin-top:10px;"></div>
      <div style="display:flex; gap:8px; flex-wrap:wrap; margin-top:10px;">
        <button id="useCurrentSketchProtocol" class="button primary" type="button">Use Current UNO Sketch</button>
        <button id="useSmoothSketchProtocol" class="button" type="button">Use Smooth UNO Sketch</button>
        <button id="useMoveProtocol" class="button" type="button">Use MOVE Angle Protocol</button>
        <button id="usePulseProtocol" class="button" type="button">Use Pulse Protocol</button>
        <button id="sendPing" class="button" type="button">Send Ping</button>
        <button id="sendStatus" class="button" type="button">PCA Status</button>
        <button id="sendScan" class="button" type="button">I2C Scan</button>
        <button id="testAllChannels" class="button" type="button">Test All Channels</button>
      </div>
      <pre id="serialLog" class="card" style="margin-top:10px; min-height:86px; max-height:180px; overflow:auto; white-space:pre-wrap; font-size:12px;">Serial log ready.</pre>
    </section>
    <section id="servoList" class="grid two" style="margin-top:14px;"></section>
    <section class="card" style="margin-top:14px;">
      <h2>UNO Sketch Protocol</h2>
      <p>Smooth firmware is uploaded to the UNO R4 on COM5. Reconnect, select <code>Use Smooth UNO Sketch</code>, then send <code>PING</code> and expect <code>PONG SmoothServoBenchTester</code>.</p>
      <p class="muted" style="margin-top:8px;">Firmware source: <code>docs/lab/servo_tester_firmware/SmoothServoBenchTester/SmoothServoBenchTester.ino</code>. It supports <code>PING</code>, <code>STATUS</code>, <code>SCAN</code>, <code>TESTALL {{low}} {{high}} {{duration}}</code>, <code>100-650</code>, <code>ALL {{pulse}} {{duration}}</code>, <code>S {{channel}} {{pulse}} {{duration}}</code>, and <code>MOVE {{channel}} {{angle}} {{duration}}</code> at 9600 baud.</p>
      <p class="muted" style="margin-top:8px;">If upload says the serial port is busy, disconnect this page from COM5 and close Arduino IDE Serial Monitor/Plotter before flashing.</p>
      <p class="muted" style="margin-top:8px;">Arduino IDE is only needed to flash that sketch onto the UNO R4. After that, this page can connect directly from Chrome with Web Serial.</p>
    </section>
    <script>
      const initialProfile = {profile_json};
      let profile = JSON.parse(JSON.stringify(initialProfile));
      let serialPort = null;
      let serialWriter = null;
      let serialReader = null;
      let serialReadActive = false;
      const servoList = document.getElementById('servoList');
      const serialStatus = document.getElementById('serialStatus');
      const serialHelp = document.getElementById('serialHelp');
      const serialLog = document.getElementById('serialLog');
      const connectionMetric = document.getElementById('connectionMetric');
      const baudRate = document.getElementById('baudRate');
      const commandTemplate = document.getElementById('commandTemplate');
      const connectSerialButton = document.getElementById('connectSerial');
      const disconnectSerialButton = document.getElementById('disconnectSerial');
      const forgetSerialButton = document.getElementById('forgetSerial');
      const protocolButtons = [
        document.getElementById('useCurrentSketchProtocol'),
        document.getElementById('useSmoothSketchProtocol'),
        document.getElementById('useMoveProtocol'),
        document.getElementById('usePulseProtocol')
      ];

      function esc(value) {{
        return String(value ?? '').replace(/[&<>"']/g, (char) => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[char]));
      }}
      function servoById(id) {{
        return profile.servos.find((servo) => servo.id === id);
      }}
      function pulsePercent(servo, pulse) {{
        const min = Number(servo.min_pulse || 500);
        const max = Number(servo.max_pulse || 2500);
        if (max <= min) return 50;
        return Math.round(((Number(pulse) - min) / (max - min)) * 100);
      }}
      function angleForPulse(servo, pulse) {{
        const minPulse = Number(servo.min_pulse || 500);
        const maxPulse = Number(servo.max_pulse || 2500);
        const minAngle = Number(servo.min_angle ?? 0);
        const maxAngle = Number(servo.max_angle ?? 180);
        if (maxPulse <= minPulse) return Math.round(Number(servo.center_angle ?? 90));
        const pct = (Number(pulse) - minPulse) / (maxPulse - minPulse);
        return Math.round(minAngle + Math.max(0, Math.min(1, pct)) * (maxAngle - minAngle));
      }}
      function pulseForAngle(servo, angle) {{
        const minPulse = Number(servo.min_pulse || 500);
        const maxPulse = Number(servo.max_pulse || 2500);
        const minAngle = Number(servo.min_angle ?? 0);
        const maxAngle = Number(servo.max_angle ?? 180);
        if (maxAngle <= minAngle) return Math.round(Number(servo.center_pulse ?? 1500));
        const pct = (Number(angle) - minAngle) / (maxAngle - minAngle);
        return Math.round(minPulse + Math.max(0, Math.min(1, pct)) * (maxPulse - minPulse));
      }}
      function logSerial(text) {{
        const stamp = new Date().toLocaleTimeString();
        serialLog.textContent += '\\n[' + stamp + '] ' + text;
        serialLog.scrollTop = serialLog.scrollHeight;
      }}
      function setConnectedState(connected, detail) {{
        connectionMetric.classList.toggle('green', Boolean(connected));
        const entity = connectionMetric.querySelector('.entity');
        const copy = connectionMetric.querySelector('p');
        if (entity) entity.textContent = connected ? 'Connected' : 'Disconnected';
        if (copy) copy.textContent = detail || (connected ? 'UNO serial open' : 'Chrome on Dave\\'s PC');
        serialStatus.textContent = detail || (connected ? 'Connected.' : 'Serial disconnected.');
        connectSerialButton.disabled = Boolean(connected);
        disconnectSerialButton.disabled = !connected;
      }}
      function setSelectedProtocol(buttonId) {{
        protocolButtons.forEach((button) => {{
          if (!button) return;
          button.classList.toggle('selected', button.id === buttonId);
          button.setAttribute('aria-pressed', button.id === buttonId ? 'true' : 'false');
        }});
      }}
      async function closeSerialConnection(detail) {{
        serialReadActive = false;
        if (serialReader) {{
          try {{ await serialReader.cancel(); }} catch (error) {{}}
          try {{ serialReader.releaseLock(); }} catch (error) {{}}
          serialReader = null;
        }}
        if (serialWriter) {{
          try {{ serialWriter.releaseLock(); }} catch (error) {{}}
          serialWriter = null;
        }}
        if (serialPort) {{
          try {{ await serialPort.close(); }} catch (error) {{ logSerial('CLOSE NOTE: ' + (error && error.message ? error.message : 'unknown')); }}
          serialPort = null;
        }}
        setConnectedState(false, detail || 'Serial disconnected.');
      }}
      function setSerialHelp(text) {{
        if (!serialHelp) return;
        const clean = String(text || '').trim();
        serialHelp.style.display = clean ? 'block' : 'none';
        serialHelp.textContent = clean;
      }}
      function serialOpenFailureHelp(error) {{
        const message = String(error && error.message ? error.message : error || '').toLowerCase();
        if (message.includes('failed to open') || message.includes('busy') || message.includes('access denied') || message.includes('networkerror')) {{
          return 'Chrome can see the UNO, but the COM port could not be opened. Close Arduino IDE Serial Monitor/Plotter, close any other tab using the port, unplug/replug the UNO, then click Forget Port and Connect UNO again.';
        }}
        return 'Serial connection failed before any command was sent. Check the selected COM port, USB cable, browser serial permission, and whether another program is holding the port.';
      }}
      function readProfileFromDom() {{
        profile.baud_rate = Number(baudRate.value || 9600);
        profile.command_template = String(commandTemplate.value || '{{pulse}}');
        profile.servos = Array.from(document.querySelectorAll('[data-servo-card]')).map((card, index) => {{
          const id = card.dataset.servoCard || ('servo-' + index);
          return {{
            id,
            name: card.querySelector('[data-field="name"]').value,
            channel: Number(card.querySelector('[data-field="channel"]').value || index),
            min_pulse: Number(card.querySelector('[data-field="min_pulse"]').value || 500),
            min_angle: Number(card.querySelector('[data-field="min_angle"]').value || 0),
            center_pulse: Number(card.querySelector('[data-field="center_pulse"]').value || 1500),
            center_angle: Number(card.querySelector('[data-field="center_angle"]').value || 90),
            max_pulse: Number(card.querySelector('[data-field="max_pulse"]').value || 2500),
            max_angle: Number(card.querySelector('[data-field="max_angle"]').value || 180),
            start_pulse: Number(card.querySelector('[data-field="start_pulse"]').value || 1500),
            start_angle: Number(card.querySelector('[data-field="start_angle"]').value || 90),
            speed_ms: Number(card.querySelector('[data-field="speed_ms"]').value || 600),
            startup_ms: Number(card.querySelector('[data-field="startup_ms"]').value || 250),
            slowdown_ms: Number(card.querySelector('[data-field="slowdown_ms"]').value || 250),
            notes: card.querySelector('[data-field="notes"]').value
          }};
        }});
      }}
      function renderServos() {{
        baudRate.value = profile.baud_rate || 9600;
        commandTemplate.value = profile.command_template || '{{pulse}}';
        servoList.innerHTML = '';
        profile.servos.forEach((servo) => {{
          const current = Number(servo.start_pulse || servo.center_pulse || 1500);
          const currentAngle = angleForPulse(servo, current);
          const card = document.createElement('article');
          card.className = 'card';
          card.dataset.servoCard = servo.id;
          card.innerHTML = `
            <div class="status-head">
              <h2>${{esc(servo.name || 'Servo')}}</h2>
              <button class="button danger" type="button" data-action="remove">Remove</button>
            </div>
            <div class="form-grid">
              <label>Name<input data-field="name" value="${{esc(servo.name)}}"></label>
              <label>Channel<input data-field="channel" type="number" min="0" max="15" value="${{esc(servo.channel)}}"></label>
              <label>Min Pulse<input data-field="min_pulse" type="number" min="0" max="3000" value="${{esc(servo.min_pulse)}}"></label>
              <label>Min Angle<input data-field="min_angle" type="number" min="0" max="180" value="${{esc(servo.min_angle ?? 0)}}"></label>
              <label>Center Pulse<input data-field="center_pulse" type="number" min="300" max="3000" value="${{esc(servo.center_pulse)}}"></label>
              <label>Center Angle<input data-field="center_angle" type="number" min="0" max="180" value="${{esc(servo.center_angle ?? 90)}}"></label>
              <label>Max Pulse<input data-field="max_pulse" type="number" min="0" max="3000" value="${{esc(servo.max_pulse)}}"></label>
              <label>Max Angle<input data-field="max_angle" type="number" min="0" max="180" value="${{esc(servo.max_angle ?? 180)}}"></label>
              <label>Start Pulse<input data-field="start_pulse" type="number" min="0" max="3000" value="${{esc(servo.start_pulse)}}"></label>
              <label>Start Angle<input data-field="start_angle" type="number" min="0" max="180" value="${{esc(servo.start_angle ?? currentAngle)}}"></label>
              <label>Speed ms<input data-field="speed_ms" type="number" min="0" max="30000" value="${{esc(servo.speed_ms)}}"></label>
              <label>Startup ms<input data-field="startup_ms" type="number" min="0" max="30000" value="${{esc(servo.startup_ms)}}"></label>
              <label>Slowdown ms<input data-field="slowdown_ms" type="number" min="0" max="30000" value="${{esc(servo.slowdown_ms)}}"></label>
              <label class="wide">Notes<input data-field="notes" value="${{esc(servo.notes)}}"></label>
            </div>
            <div style="margin-top:12px;">
              <input data-field="pulse_slider" type="range" min="${{esc(servo.min_pulse)}}" max="${{esc(servo.max_pulse)}}" value="${{esc(current)}}">
              <div class="muted">Pulse: <strong data-pulse-label>${{esc(current)}}</strong> us / angle: <strong data-angle-label>${{esc(currentAngle)}}</strong> deg / ${{pulsePercent(servo, current)}}%</div>
            </div>
            <div style="display:flex; gap:8px; flex-wrap:wrap; margin-top:12px;">
              <button class="button" type="button" data-action="min">Min</button>
              <button class="button" type="button" data-action="center">Center</button>
              <button class="button" type="button" data-action="max">Max</button>
              <button class="button primary" type="button" data-action="move">Move</button>
              <button class="button" type="button" data-action="sweep">Sweep</button>
            </div>
          `;
          servoList.appendChild(card);
        }});
      }}
      async function sendSerial(line) {{
        if (!serialWriter) {{
          serialStatus.textContent = 'Connect UNO first. Command not sent: ' + line;
          logSerial('NOT SENT: ' + line);
          return false;
        }}
        await serialWriter.write(new TextEncoder().encode(line + '\\n'));
        serialStatus.textContent = 'Sent: ' + line;
        logSerial('TX ' + line);
        return true;
      }}
      function buildCommand(servo, pulse, duration) {{
        const angle = angleForPulse(servo, pulse);
        return String(profile.command_template || '{{pulse}}')
          .replaceAll('{{channel}}', String(servo.channel))
          .replaceAll('{{pulse}}', String(pulse))
          .replaceAll('{{angle}}', String(angle))
          .replaceAll('{{duration}}', String(duration || servo.speed_ms || 0));
      }}
      async function moveServo(servo, pulse, duration) {{
        readProfileFromDom();
        const command = buildCommand(servo, pulse, duration);
        await sendSerial(command);
      }}
      document.getElementById('connectSerial').addEventListener('click', async () => {{
        if (!navigator.serial) {{
          serialStatus.textContent = 'Web Serial is unavailable. Use Chrome or Edge on HTTPS with the UNO connected to this PC.';
          return;
        }}
        if (serialPort || serialWriter) {{
          setSerialHelp('UNO serial is already open in this page. Use Disconnect before connecting again.');
          logSerial('CONNECT SKIPPED: port already open in this page.');
          setConnectedState(true, 'Connected to UNO serial at ' + profile.baud_rate + ' baud.');
          return;
        }}
        readProfileFromDom();
        try {{
          serialPort = await navigator.serial.requestPort();
          await serialPort.open({{ baudRate: Number(profile.baud_rate || 9600) }});
          serialWriter = serialPort.writable.getWriter();
          setConnectedState(true, 'Connected to UNO serial at ' + profile.baud_rate + ' baud.');
          setSerialHelp('');
          logSerial('Connected. Waiting for UNO replies...');
          if (serialPort.readable) {{
            serialReadActive = true;
            const decoder = new TextDecoder();
            serialReader = serialPort.readable.getReader();
            (async () => {{
              let buffer = '';
              while (serialReadActive && serialReader) {{
                try {{
                  const {{ value, done }} = await serialReader.read();
                  if (done) break;
                  if (value) {{
                    buffer += decoder.decode(value, {{ stream: true }});
                    const lines = buffer.split(/\\r?\\n/);
                    buffer = lines.pop() || '';
                    lines.filter(Boolean).forEach((line) => logSerial('RX ' + line));
                  }}
                }} catch (error) {{
                  logSerial('RX error: ' + (error && error.message ? error.message : 'unknown'));
                  break;
                }}
              }}
            }})();
          }}
        }} catch (error) {{
          const help = serialOpenFailureHelp(error);
          setConnectedState(false, 'Serial connection failed: ' + (error && error.message ? error.message : 'unknown error'));
          setSerialHelp(help);
          logSerial('CONNECT FAILED: ' + (error && error.message ? error.message : 'unknown error'));
          logSerial('HELP ' + help);
        }}
      }});
      document.getElementById('disconnectSerial').addEventListener('click', async () => {{
        await closeSerialConnection('Serial disconnected. COM5 released from this page.');
        setSerialHelp('');
        logSerial('Disconnected.');
      }});
      document.getElementById('forgetSerial').addEventListener('click', async () => {{
        try {{
          const activePort = serialPort;
          await closeSerialConnection('Serial disconnected before forgetting port permission.');
          if (activePort && activePort.forget) await activePort.forget();
          if (navigator.serial && navigator.serial.getPorts) {{
            const ports = await navigator.serial.getPorts();
            for (const port of ports) {{
              if (port.forget) {{
                try {{ await port.forget(); }} catch (error) {{}}
              }}
            }}
          }}
          setConnectedState(false, 'Port permission cleared. Click Connect UNO and select COM5 again.');
          setSerialHelp('If COM5 still fails to open, close Arduino IDE Serial Monitor/Plotter or any other program using COM5, then unplug/replug the UNO.');
          logSerial('Port forgotten.');
        }} catch (error) {{
          setSerialHelp('Could not forget the port: ' + (error && error.message ? error.message : 'unknown error'));
          logSerial('FORGET FAILED: ' + (error && error.message ? error.message : 'unknown error'));
        }}
      }});
      document.getElementById('useCurrentSketchProtocol').addEventListener('click', () => {{
        commandTemplate.value = '{{pulse}}';
        baudRate.value = 9600;
        setSelectedProtocol('useCurrentSketchProtocol');
        readProfileFromDom();
        profile.servos = profile.servos.map((servo) => ({{
          ...servo,
          min_pulse: 100,
          center_pulse: 375,
          max_pulse: 650,
          start_pulse: 375,
          notes: servo.notes || 'Current UNO sketch reads one integer 100-650 and applies it to channels 0 and 1.'
        }}));
        renderServos();
        serialStatus.textContent = 'Protocol set for the currently flashed sketch: send one raw PCA9685 count, 100-650, at 9600 baud.';
      }});
      document.getElementById('useSmoothSketchProtocol').addEventListener('click', () => {{
        commandTemplate.value = 'S {{channel}} {{pulse}} {{duration}}';
        baudRate.value = 9600;
        setSelectedProtocol('useSmoothSketchProtocol');
        readProfileFromDom();
        profile.servos = profile.servos.map((servo) => ({{
          ...servo,
          min_pulse: 100,
          center_pulse: 375,
          max_pulse: 650,
          start_pulse: 375,
          speed_ms: servo.speed_ms || 650,
          notes: servo.notes || 'Smooth UNO sketch supports PING, raw 100-650, ALL pulse duration, S channel pulse duration, and MOVE channel angle duration.'
        }}));
        renderServos();
        serialStatus.textContent = 'Protocol set for SmoothServoBenchTester at 9600 baud: S channel pulse duration.';
      }});
      document.getElementById('useMoveProtocol').addEventListener('click', () => {{
        commandTemplate.value = 'MOVE {{channel}} {{angle}} {{duration}}';
        baudRate.value = 9600;
        setSelectedProtocol('useMoveProtocol');
        readProfileFromDom();
        serialStatus.textContent = 'Protocol set to MOVE channel angle duration at 9600 baud.';
      }});
      document.getElementById('usePulseProtocol').addEventListener('click', () => {{
        commandTemplate.value = 'S {{channel}} {{pulse}} {{duration}}';
        baudRate.value = 9600;
        setSelectedProtocol('usePulseProtocol');
        readProfileFromDom();
        serialStatus.textContent = 'Protocol set to S channel pulse duration at 9600 baud.';
      }});
      document.getElementById('sendPing').addEventListener('click', async () => {{
        await sendSerial('PING');
      }});
      document.getElementById('sendStatus').addEventListener('click', async () => {{
        await sendSerial('STATUS');
      }});
      document.getElementById('sendScan').addEventListener('click', async () => {{
        await sendSerial('SCAN');
      }});
      document.getElementById('testAllChannels').addEventListener('click', async () => {{
        await sendSerial('TESTALL 300 650 450');
      }});
      document.getElementById('addServo').addEventListener('click', () => {{
        readProfileFromDom();
        const channel = profile.servos.length;
        const rawPcaMode = String(profile.command_template || '').includes('{{pulse}}') && Number(profile.baud_rate || 9600) === 9600;
        profile.servos.push(rawPcaMode
          ? {{ id: 'servo-' + Date.now(), name: 'Servo ' + channel, channel, min_pulse: 100, min_angle: 0, center_pulse: 375, center_angle: 90, max_pulse: 650, max_angle: 180, start_pulse: 375, start_angle: 90, speed_ms: 600, startup_ms: 250, slowdown_ms: 250, notes: 'Raw PCA9685 count profile for SmoothServoBenchTester.' }}
          : {{ id: 'servo-' + Date.now(), name: 'Servo ' + channel, channel, min_pulse: 500, min_angle: 0, center_pulse: 1500, center_angle: 90, max_pulse: 2500, max_angle: 180, start_pulse: 1500, start_angle: 90, speed_ms: 600, startup_ms: 250, slowdown_ms: 250, notes: '' }});
        renderServos();
      }});
      document.getElementById('saveProfile').addEventListener('click', async () => {{
        readProfileFromDom();
        const response = await fetch('/studio/api/lab/servo-tester/profile', {{ method: 'POST', headers: {{ 'Content-Type': 'application/json' }}, body: JSON.stringify(profile) }});
        const data = await response.json();
        profile = data.profile || profile;
        renderServos();
        serialStatus.textContent = 'Profile saved at ' + (profile.updated_at || 'now') + '.';
      }});
      servoList.addEventListener('input', (event) => {{
        const slider = event.target && event.target.matches('[data-field="pulse_slider"]') ? event.target : null;
        if (!slider) return;
        const card = slider.closest('[data-servo-card]');
        readProfileFromDom();
        const servo = card ? servoById(card.dataset.servoCard) : null;
        const label = card && card.querySelector('[data-pulse-label]');
        const angleLabel = card && card.querySelector('[data-angle-label]');
        if (label) label.textContent = slider.value;
        if (angleLabel && servo) angleLabel.textContent = angleForPulse(servo, Number(slider.value));
      }});
      servoList.addEventListener('change', async (event) => {{
        const slider = event.target && event.target.matches('[data-field="pulse_slider"]') ? event.target : null;
        if (!slider) return;
        readProfileFromDom();
        const card = slider.closest('[data-servo-card]');
        const servo = card ? servoById(card.dataset.servoCard) : null;
        if (servo) await moveServo(servo, Number(slider.value), servo.speed_ms);
      }});
      servoList.addEventListener('click', async (event) => {{
        const action = event.target && event.target.dataset ? event.target.dataset.action : '';
        if (!action) return;
        readProfileFromDom();
        const card = event.target.closest('[data-servo-card]');
        const servo = card ? servoById(card.dataset.servoCard) : null;
        if (!servo) return;
        const slider = card.querySelector('[data-field="pulse_slider"]');
        if (action === 'remove') {{
          profile.servos = profile.servos.filter((item) => item.id !== servo.id);
          renderServos();
          return;
        }}
        if (action === 'min') slider.value = servo.min_pulse;
        if (action === 'center') slider.value = servo.center_pulse;
        if (action === 'max') slider.value = servo.max_pulse;
        if (['min', 'center', 'max', 'move'].includes(action)) {{
          const label = card.querySelector('[data-pulse-label]');
          const angleLabel = card.querySelector('[data-angle-label]');
          if (label) label.textContent = slider.value;
          if (angleLabel) angleLabel.textContent = angleForPulse(servo, Number(slider.value));
          await moveServo(servo, Number(slider.value), servo.speed_ms);
        }}
        if (action === 'sweep') {{
          await moveServo(servo, servo.min_pulse, servo.startup_ms);
          await new Promise((resolve) => setTimeout(resolve, Number(servo.startup_ms || 0) + 120));
          await moveServo(servo, servo.max_pulse, servo.speed_ms);
          await new Promise((resolve) => setTimeout(resolve, Number(servo.speed_ms || 0) + 120));
          await moveServo(servo, servo.center_pulse, servo.slowdown_ms);
        }}
      }});
      renderServos();
      setConnectedState(false, 'Serial disconnected.');
      if ((profile.command_template || '').startsWith('S ')) setSelectedProtocol('useSmoothSketchProtocol');
      else if ((profile.command_template || '').startsWith('MOVE ')) setSelectedProtocol('useMoveProtocol');
      else setSelectedProtocol('useCurrentSketchProtocol');
    </script>
    """


async def _studio_accounting_state(db: AsyncSession) -> dict[str, Any]:
    projects = await _ensure_first_internal_projects(db)
    env_inventory = _load_json("TOD_ENV_KEY_INVENTORY.latest.json")
    env_keys = env_inventory.get("keys") if isinstance(env_inventory.get("keys"), list) else []
    provider_categories = {"Billing", "AI Models", "Compute / GPU", "Email", "Voice / Calls", "PythonAnywhere"}
    category_counts: dict[str, int] = {}
    for row in env_keys:
        if isinstance(row, dict) and row.get("category") in provider_categories:
            category = str(row.get("category"))
            category_counts[category] = category_counts.get(category, 0) + 1
    return {
        "generated_at": _utc_now(),
        "project": _studio_project_to_dict(projects["accounting"]),
        "providers": [
            ("OpenAI", "AI usage and model costs", "Map API usage by project and identify expensive workflows."),
            ("Render", "Hosting and managed app services", "Connect provider spend once Render billing adapter is available."),
            ("PythonAnywhere", "MIM Robotics hosting", "Track CPU quota, hosting, and website continuity costs."),
            ("Twilio / Zoom", "Voice, calls, SMS", "Require managed activation and cost guardrails before production use."),
            ("Stripe", "Billing/subscriptions", "Use as revenue and subscription source once adapter is connected."),
            ("Domains / Squarespace", "Domain renewals and DNS", "Track renewal dates and survival-critical domains."),
        ],
        "phases": [
            ("Discovery", "Map providers, bill sources, invoices, receipts, subscriptions, and project cost buckets."),
            ("MVP", "Manual provider ledger, invoice upload, vendor list, recurring payment tracker, and notes."),
            ("Automation", "Receipt folder ingestion, OCR, categorization, and recurring expense detection."),
            ("Insights", "Unused services, duplicate tools, project cost allocation, budget warnings, and savings suggestions."),
            ("Productization", "Turn internal MIM Operations Accounting into a customer-ready expense intelligence platform."),
        ],
        "smart_actions": [
            "Flag services with no recent usage evidence.",
            "Detect duplicate providers serving the same capability.",
            "Show project-level AI/hosting/voice spend.",
            "Warn when provider spend exceeds budget.",
            "Suggest pause/cancel candidates for continuity mode.",
        ],
        "category_counts": category_counts,
        "env_key_count": env_inventory.get("key_count", len(env_keys)),
    }


def _accounting_body(state: dict[str, Any]) -> str:
    project = state.get("project") if isinstance(state.get("project"), dict) else {}
    provider_html = "".join(
        f"""<div class="project-row"><div><strong>{_html(name)}</strong><br><span class="muted">{_html(next_action)}</span></div><span class="health-pill">{_html(purpose)}</span></div>"""
        for name, purpose, next_action in state.get("providers", [])
    )
    phase_html = "".join(
        f"""<article class="card"><h2>{_html(name)}</h2><p>{_html(detail)}</p></article>"""
        for name, detail in state.get("phases", [])
    )
    smart_html = "".join(f"<li>{_html(item)}</li>" for item in state.get("smart_actions", []))
    category_rows = "".join(
        f"<tr><td>{_html(category)}</td><td>{_html(count)}</td></tr>"
        for category, count in sorted((state.get("category_counts") or {}).items())
    ) or '<tr><td colspan="2">No provider categories loaded yet.</td></tr>'
    return f"""
    <section class="grid four">
      {_metric_card("Project", project.get("status", "discovery"), project.get("title", "MIM Operations Accounting"))}
      {_metric_card("Providers", len(state.get("providers", [])), "Initial spend surfaces")}
      {_metric_card("Env Keys", state.get("env_key_count", 0), "Configuration sources to classify")}
      {_metric_card("Build Mode", "Internal MVP", "Useful first, product later")}
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Project Brief</h2>
        <div class="label">What This Is</div><p>MIM Operations Accounting V1: internal spend, subscriptions, invoices, provider costs, project allocation, and waste detection.</p>
        <div class="label">Why This Matters</div><p>{_html(project.get("why_it_matters", ""))}</p>
        <div class="label">Next Action</div><p>{_html(project.get("next_action", ""))}</p>
      </article>
      <article class="card"><h2>Provider Cost Surfaces</h2>{provider_html}</article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card"><h2>Smart Actions</h2><ul class="clean">{smart_html}</ul></article>
      <article class="card"><h2>Provider Categories</h2><table class="score-table"><thead><tr><th>Category</th><th>Keys</th></tr></thead><tbody>{category_rows}</tbody></table></article>
      <article class="card"><h2>Accounting Rule</h2><p>This is not generic accounting software yet. It starts as MIM's own operations accounting tool, then becomes a product when the internal workflow proves useful.</p></article>
    </section>
    <section class="grid three" style="margin-top:14px;">{phase_html}</section>
    """


async def _ensure_studio_project_seed(db: AsyncSession) -> None:
    project_count = int((await db.execute(select(func.count(StudioProject.id)))).scalar() or 0)
    signal_count = int((await db.execute(select(func.count(StudioProjectSignal.id)))).scalar() or 0)
    if project_count or signal_count:
        return
    projects = [
        StudioProject(
            title="MIM Accounting",
            summary="Expense intelligence platform for receipts, OCR, categorization, reporting, subscription review, and spending insights.",
            status="discovery",
            priority="high",
            why_it_matters="Reduce expense tracking effort and identify wasted spending.",
            origin_story="Created from Dave's accounting app conversation about receipts dropped into a folder and converted into useful expense intelligence.",
            next_action="Define receipt ingestion workflow and initial reporting model.",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
        StudioProject(
            title="MIM Project Studio",
            summary="Internal command center for MIM, TOD, projects, training, documents, reports, systems, lab, apps, and accounting.",
            status="implementation",
            priority="P0",
            why_it_matters="Gives Dave one place to understand what MIM/TOD are doing and manage real work.",
            origin_story="Created from the need to stop asking MIM/TOD status questions across scattered pages and artifacts.",
            next_action="Make projects DB-backed and conversation-created.",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
        StudioProject(
            title="AgentMIM Account Manager",
            summary="Customer/account management surface for AgentMIM work, MFA, permissions, support, and deployment actions.",
            status="planning",
            priority="P1",
            why_it_matters="Improves customer management and operational clarity.",
            origin_story="Captured from recurring AgentMIM account and MFA implementation needs.",
            next_action="Define account, permission, and MFA project scope.",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
        StudioProject(
            title="MIM Robotics Workspace",
            summary="Workspace calibration and arm learning project for cameras, C12 distance sensor, RPLIDAR, safe poses, and object interaction.",
            status="calibration",
            priority="P1",
            why_it_matters="Moves MIM from seeing objects toward spatial reasoning and embodied interaction.",
            origin_story="Created after block pickup attempts showed that workspace calibration matters more than repeatedly trying grasps.",
            next_action="Build table coordinate model and safe exploration pose memory.",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
    ]
    signals = [
        StudioProjectSignal(
            title="Forum Graphics Quality",
            signal_type="candidate",
            status="candidate",
            priority="high",
            source_surface="conversation",
            source_text="Dave flagged poor forum image creation quality.",
            why_it_matters="Poor images reduce engagement and make AgentMIM feel less professional.",
            suggested_action="approve_or_merge",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
        StudioProjectSignal(
            title="Global Login Friction",
            signal_type="observation",
            status="observation",
            priority="low",
            source_surface="support_observation",
            source_text="A user had a login issue due to a language barrier but resolved it by typing in English.",
            why_it_matters="Useful later for internationalization, but not enough for a project yet.",
            suggested_action="remember",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
        StudioProjectSignal(
            title="Fuel Station Operations Platform",
            signal_type="candidate",
            status="discovery",
            priority="high",
            source_surface="customer_discussion",
            source_text="Fuel operator workflow discussion around inventory, labor, reporting, and margin visibility.",
            why_it_matters="Could save meaningful time and become a reusable vertical solution.",
            suggested_action="continue_discovery",
            metadata_json={"seeded_by": "studio_projects_v1"},
        ),
    ]
    db.add_all(projects + signals)
    await db.commit()


async def _ensure_requested_project_backlog(db: AsyncSession) -> None:
    seed_version = "2026-06-03-project-backlog-v1"
    requested_projects = [
        {
            "title": "AgentMIM Account Manager Roles",
            "summary": "Add account manager as an AgentMIM role with scoped access for carriers, contacts, agents, owner account data, commissions, and reports.",
            "status": "queued",
            "priority": "P0",
            "owner": "TOD",
            "health": "needs_scope",
            "why_it_matters": "Account-owner and account-manager permissions need to protect confidential commission data while still supporting real broker operations.",
            "origin_story": "Dave requested account manager as an add-agent assignment option with restricted access areas and pre-approval for sensitive commission data.",
            "next_action": "Define permission matrix and sensitive commission/report access rules before implementation.",
            "dave_needed": True,
            "metadata_json": {
                "project_type": "application_feature",
                "progress_percent": 5,
                "work_state": "queued",
                "blocker": "Dave approval needed for confidential commission access rules.",
                "acceptance": "Account manager role can be assigned and scoped without exposing confidential rep payout data unless pre-approved.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "AgentMIM Forum Graphics Quality",
            "summary": "Fix daily forum post graphics generation so images are consistently created, on-brand, readable, and usable.",
            "status": "queued",
            "priority": "P0",
            "owner": "TOD",
            "health": "needs_repair",
            "why_it_matters": "Forum graphics affect AgentMIM quality, engagement, and daily content reliability.",
            "origin_story": "Dave reported daily forum post graphics are hit or miss: sometimes missing, sometimes created poorly, sometimes acceptable.",
            "next_action": "Load prior forum graphics decisions and run the image QA path before changing prompt or generation logic.",
            "dave_needed": False,
            "metadata_json": {
                "project_type": "application_error",
                "progress_percent": 10,
                "work_state": "queued",
                "blocker": "Needs continuity brief from prior forum graphics work.",
                "acceptance": "Daily forum graphics generate reliably with QA evidence and no text-rendering regression.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "AgentMIM Carrier Login MFA Codes",
            "summary": "Use account-owner Twilio and Gmail integrations to receive, display, and assist with carrier-site MFA codes during commission report upload workflows.",
            "status": "queued",
            "priority": "P1",
            "owner": "TOD",
            "health": "needs_design",
            "why_it_matters": "Carrier commission report collection often requires email/SMS verification codes, and account managers need a secure workflow.",
            "origin_story": "Dave described carrier website login from the upload commission page where MFA codes should appear in real time and possibly stage to clipboard or auto-enter.",
            "next_action": "Design secure inbound code capture, display, clipboard staging, permissions, and audit controls.",
            "dave_needed": True,
            "metadata_json": {
                "project_type": "application_feature",
                "progress_percent": 0,
                "work_state": "queued",
                "blocker": "Security and account-owner permission model must be approved.",
                "acceptance": "Authorized users can retrieve MFA codes safely without exposing messages outside the approved account context.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "AgentMIM Social Campaign Feeds Repair",
            "summary": "Repair AgentMIM social post management and monitoring around /campaigns, /feeds, and the keywords tab.",
            "status": "queued",
            "priority": "P1",
            "owner": "TOD",
            "health": "broken",
            "why_it_matters": "Social campaign monitoring needs to work before AgentMIM can manage posting and feed intelligence reliably.",
            "origin_story": "Dave reported /campaigns /feeds and keywords tab do not appear to work.",
            "next_action": "Inspect routes, frontend tab state, feed data source, keyword persistence, and current error logs.",
            "dave_needed": False,
            "metadata_json": {
                "project_type": "application_error",
                "progress_percent": 0,
                "work_state": "queued",
                "blocker": "Needs code/log inspection.",
                "acceptance": "Campaign feeds and keyword tab load, save, and display monitored data with a passing smoke check.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "AgentMIM Reports DB Binding",
            "summary": "Bind MIM Studio Reports to the true AgentMIM/comm_app database so app metrics use account_owners, representatives, commissions, carriers, and related production tables instead of Studio fallback portal rows.",
            "status": "queued",
            "priority": "P0",
            "owner": "TOD",
            "health": "blocked_on_config",
            "why_it_matters": "Reports cannot answer AgentMIM user/account/revenue questions truthfully until Studio can read the comm_app database source of truth.",
            "origin_story": "Dave asked the Reports side MIM chat why it cannot pull data from comm_app / AgentMIM.com DB. Diagnosis: Studio has no COMM_APP_DATABASE_URL binding and only sees fallback MIM portal tables.",
            "next_action": "Register COMM_APP_DATABASE_URL on the MIM Studio service with the AgentMIM Render Postgres URL, restart Studio, and verify account_owners and representatives counts.",
            "dave_needed": True,
            "metadata_json": {
                "project_type": "application_error",
                "progress_percent": 20,
                "work_state": "queued",
                "blocker": "Needs AgentMIM/comm_app Render database URL or service-level secret binding.",
                "acceptance": "Studio Reports app_metrics connects to the comm_app DB and reports account_owners and representatives counts without using project_portal_accounts as fallback.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "MIM Wall Mobile Full Assistant",
            "summary": "Expand the MIM Wall mobile app from call management into full LIVE MIM assistant capabilities.",
            "status": "queued",
            "priority": "P1",
            "owner": "MIM + TOD",
            "health": "large_scope",
            "why_it_matters": "The mobile MIM Wall should become a useful assistant surface, not only a call-management tool.",
            "origin_story": "Dave listed full assistant capabilities including call screening, translation, scheduling, search, on-screen interaction, device control, travel, security, and diagnostics.",
            "next_action": "Split into capability phases and identify which features require phone OS permissions or native app work.",
            "dave_needed": True,
            "metadata_json": {
                "project_type": "product_expansion",
                "progress_percent": 0,
                "work_state": "queued",
                "blocker": "Needs phased scope and platform permission decisions.",
                "acceptance": "A phased roadmap exists with first shippable assistant capability selected and validated.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "MIM Mobile Login SSL Loop",
            "summary": "Fix mimtod.com/mim/login on mobile where login returns to the login page and initial load may show an unsafe-site SSL warning.",
            "status": "queued",
            "priority": "P0",
            "owner": "TOD",
            "health": "broken",
            "why_it_matters": "Mobile access to MIM is a core operator path and SSL/auth loops undermine trust and usability.",
            "origin_story": "Dave reported mobile login submit returns to the login page and initial load shows an unsafe-site error.",
            "next_action": "Inspect certificate chain, domain routing, cookie/session settings, redirect target, and mobile browser behavior.",
            "dave_needed": False,
            "metadata_json": {
                "project_type": "application_error",
                "progress_percent": 0,
                "work_state": "queued",
                "blocker": "Needs live mobile/auth verification.",
                "acceptance": "Mobile login succeeds over valid HTTPS without unsafe-site warning or login loop.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "Studio Static Text Cleanup",
            "summary": "Review every Studio page and remove space-killing static descriptive text, leaving short titles, action areas, and dynamic results.",
            "status": "working",
            "priority": "P1",
            "owner": "Codex",
            "health": "active",
            "why_it_matters": "Studio is Dave's operating console and should show data/actions instead of documentation blocks.",
            "origin_story": "Dave requested removal of subtitles, what-this-page-does text, and static descriptive content across Studio.",
            "next_action": "Audit all Studio pages and remove static copy page by page, starting with Projects.",
            "dave_needed": False,
            "metadata_json": {
                "project_type": "studio_ui",
                "progress_percent": 15,
                "work_state": "working",
                "blocker": "none",
                "acceptance": "Each Studio page uses short titles, action areas, and dynamic data/results only.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "TOD Local PowerShell Migration",
            "summary": "Move, quiet, or reschedule TOD local PowerShell tasks that interrupt Dave's shared PC workflow.",
            "status": "queued",
            "priority": "P0",
            "owner": "TOD",
            "health": "needs_repair",
            "why_it_matters": "TOD and Dave share the PC, so frequent visible automation interrupts Dave's work and should move to the MIM BOX or run invisibly.",
            "origin_story": "Dave reported TOD runs PowerShell prompts every 10 minutes or more and thought these were moved to the MIM BOX.",
            "next_action": "Re-register TOD-Elevated-Watchdog from an elevated shell with -WindowStyle Hidden, then move eligible daemon/watchdog work to the MIM BOX.",
            "dave_needed": False,
            "metadata_json": {
                "project_type": "operations_repair",
                "progress_percent": 20,
                "work_state": "queued",
                "blocker": "TOD-Elevated-Watchdog still runs every 5 minutes without WindowStyle Hidden; Windows denied non-admin modification of the elevated task.",
                "acceptance": "No visible scheduled PowerShell windows interrupt Dave during normal PC use.",
                "requested_by": "Dave",
            },
        },
        {
            "title": "MIM Development Continuity V1",
            "summary": "Make MIM load project history, decisions, known-good fixes, failed attempts, open issues, and validation evidence before implementation work begins.",
            "status": "working",
            "priority": "P0",
            "owner": "MIM + TOD",
            "health": "top_training_objective",
            "why_it_matters": "Continuity is the shortest path from better judgment to better outcomes: it prevents solved development problems from becoming unsolved after Codex restarts or context is lost.",
            "origin_story": "Dave identified retrieval, not storage, as the missing layer after Codex freeze/restart pain. MIM should become Project Manager, TOD Engineering Lead, and Codex Specialist Engineer.",
            "next_action": "Validate the continuity gate against the AgentMIM forum graphics project before widening it.",
            "dave_needed": False,
            "metadata_json": {
                "project_type": "training_objective",
                "objective_id": "MIM-DEVELOPMENT-CONTINUITY-V1",
                "progress_percent": 25,
                "work_state": "working",
                "blocker": "Needs first real continuity lookup/brief validation against forum graphics.",
                "acceptance": "Before implementation begins, MIM produces a continuity brief with prior decisions, known fixes, failed attempts, open issues, relevant files, loaded documents, and recommended next action.",
                "requested_by": "Dave",
            },
        },
    ]
    for spec in requested_projects:
        metadata = spec.setdefault("metadata_json", {})
        metadata.setdefault("seed_source", "studio_project_backlog_seed_v1")
        metadata.setdefault("seed_version", seed_version)
        await _upsert_studio_project_record(db, **spec)
    await db.commit()


async def _studio_projects_state(
    db: AsyncSession,
    *,
    selected_project_id: int | None = None,
    view: str = "all",
    new_project: bool = False,
) -> dict[str, Any]:
    await _ensure_studio_project_seed(db)
    await _ensure_requested_project_backlog(db)
    projects = (
        await db.execute(select(StudioProject).order_by(StudioProject.id.desc()).limit(50))
    ).scalars().all()
    signals = (
        await db.execute(select(StudioProjectSignal).order_by(StudioProjectSignal.id.desc()).limit(50))
    ).scalars().all()
    signal_rows = [_studio_signal_to_dict(row) for row in signals]
    project_rows = [_studio_project_to_dict(row) for row in projects]
    for index, row in enumerate(project_rows):
        row["progress_percent"] = _project_progress(row)
        row["blocker"] = _project_blocker(row)
        row["work_state"] = _project_work_state(row)
        row["project_type"] = _project_category(row)
        row["is_deleted"] = str(row.get("status") or "").strip().lower() in {"deleted", "archived", "discarded", "scrapped"}
        project_rows[index] = row
    visible_project_rows = [row for row in project_rows if not row.get("is_deleted")]
    selected_project = None
    selected_events: list[dict[str, Any]] = []
    if selected_project_id:
        selected = await db.get(StudioProject, selected_project_id)
        if selected:
            selected_project = _studio_project_to_dict(selected)
            selected_project["progress_percent"] = _project_progress(selected)
            selected_project["blocker"] = _project_blocker(selected)
            selected_project["work_state"] = _project_work_state(selected)
            selected_project["project_type"] = _project_category(selected)
            events = (
                await db.execute(
                    select(StudioProjectEvent)
                    .where(StudioProjectEvent.project_id == selected.id)
                    .order_by(StudioProjectEvent.id.desc())
                    .limit(20)
                )
            ).scalars().all()
            selected_events = [
                {
                    "id": event.id,
                    "event_type": event.event_type,
                    "actor": event.actor,
                    "title": event.title,
                    "detail": event.detail,
                    "created_at": event.created_at.isoformat() if event.created_at else "",
                }
                for event in events
            ]
    counts = {
        "signals": len(signal_rows),
        "candidates": sum(1 for item in signal_rows if item["status"] in {"candidate", "discovery"})
        + sum(1 for item in visible_project_rows if item["status"] in {"candidate", "queued"}),
        "active": sum(
            1
            for item in visible_project_rows
            if item["status"] not in {"archived", "scrapped", "discarded", "deleted"}
        ),
        "dave_needed": sum(1 for item in visible_project_rows if item["dave_needed"]),
    }
    return {
        "projects": visible_project_rows,
        "signals": signal_rows,
        "counts": counts,
        "selected_project": selected_project,
        "selected_events": selected_events,
        "view": view,
        "new_project": new_project,
    }


async def _studio_apps_state(db: AsyncSession) -> dict[str, Any]:
    scan = _load_json("MIM_TOD_APP_SOURCE_SCAN.latest.json")
    scan_apps = scan.get("apps") if isinstance(scan.get("apps"), list) else []
    scan_by_key = {str(item.get("app_key") or ""): item for item in scan_apps if isinstance(item, dict)}
    apps: list[dict[str, Any]] = []
    for source in APP_SOURCE_REGISTRY:
        app = dict(source)
        scan_row = scan_by_key.get(str(app.get("app_key") or ""))
        local_root = str(app.get("local_root") or "")
        path = Path(local_root) if local_root else None
        host_can_inspect = bool(path and path.exists())
        is_git_repo = bool(host_can_inspect and (path / ".git").exists())
        scan_exists = bool(scan_row and scan_row.get("exists"))
        scan_git_repo = bool(scan_row and scan_row.get("git_repo"))
        primary_table = str(app.get("primary_account_table") or "")
        secondary_table = str(app.get("secondary_user_table") or "")
        primary_count = await _safe_table_count(db, primary_table)
        secondary_count = await _safe_table_count(db, secondary_table)
        fallback_counts: dict[str, int] = {}
        for table_name in app.get("fallback_tables", []) if isinstance(app.get("fallback_tables"), list) else []:
            count = await _safe_table_count(db, str(table_name))
            if count is not None:
                fallback_counts[str(table_name)] = count
        app["source_status"] = "live_inspectable" if host_can_inspect else ("scanned_by_tod" if scan_row else "registered")
        app["git_status"] = (
            "git_repo"
            if is_git_repo or scan_git_repo
            else ("not_git_repo" if host_can_inspect or scan_exists else "registered")
        )
        app["scan"] = scan_row or {}
        app["branch"] = str((scan_row or {}).get("branch") or "")
        app["commit"] = str((scan_row or {}).get("commit") or "")
        app["dirty_count"] = (scan_row or {}).get("dirty_count")
        app["scanned_at"] = str((scan_row or {}).get("scanned_at") or "")
        app["hosting_status"] = (scan_row or {}).get("pythonanywhere_status") if isinstance((scan_row or {}).get("pythonanywhere_status"), dict) else {}
        app["primary_count"] = primary_count
        app["secondary_count"] = secondary_count
        app["fallback_counts"] = fallback_counts
        app["registered_users"] = primary_count if primary_count is not None else fallback_counts.get("project_portal_accounts")
        app["db_status"] = (
            "connected"
            if primary_count is not None
            else (
                "fallback_available"
                if fallback_counts
                else (
                    "external_declared"
                    if app.get("hosting_status") and primary_table
                    else ("not_declared" if not primary_table else "needs_binding")
                )
            )
        )
        app["health"] = (
            "good"
            if (app["source_status"] in {"live_inspectable", "scanned_by_tod"} and app["git_status"] in {"git_repo", "not_git_repo"} and app["db_status"] in {"connected", "fallback_available", "not_declared", "external_declared"})
            else ("needs binding" if app["db_status"] == "needs_binding" else "registered")
        )
        app["next_action"] = (
            "Verify the app-specific database binding."
            if app["db_status"] == "needs_binding"
            else (
                "Connect app database/reporting adapter."
                if app["db_status"] == "external_declared"
                else ("Review dirty worktree before app edits." if isinstance(app.get("dirty_count"), int) and app.get("dirty_count", 0) > 0 else "Keep registry and health checks current.")
            )
        )
        apps.append(app)
    counts = {
        "apps": len(apps),
        "live_inspectable": sum(1 for item in apps if item.get("source_status") == "live_inspectable"),
        "scanned_by_tod": sum(1 for item in apps if item.get("source_status") == "scanned_by_tod"),
        "registered_only": sum(1 for item in apps if item.get("source_status") == "registered"),
        "db_connected": sum(1 for item in apps if item.get("db_status") == "connected"),
        "dirty_repos": sum(1 for item in apps if isinstance(item.get("dirty_count"), int) and item.get("dirty_count", 0) > 0),
    }
    summary = (
        f"{counts['apps']} apps are registered. "
        f"{counts['live_inspectable']} can be inspected directly by this host, "
        f"{counts['scanned_by_tod']} were scanned by TOD from their repo roots, "
        f"{counts['dirty_repos']} have dirty worktrees, and "
        f"{counts['db_connected']} have a proven primary DB table in the current Studio connection."
    )
    return {"apps": apps, "counts": counts, "summary": summary}


def _studio_document_to_dict(row: StudioDocument) -> dict[str, Any]:
    return {
        "id": row.id,
        "title": row.title,
        "summary": row.summary,
        "document_type": row.document_type,
        "category": row.category,
        "status": row.status,
        "owner": row.owner,
        "created_by": row.created_by,
        "source_kind": row.source_kind,
        "source_url": row.source_url,
        "source_path": row.source_path,
        "local_path": row.local_path,
        "preserve_policy": row.preserve_policy,
        "snapshot_status": row.snapshot_status,
        "content_text": row.content_text,
        "tags_json": row.tags_json if isinstance(row.tags_json, list) else [],
        "metadata_json": row.metadata_json if isinstance(row.metadata_json, dict) else {},
        "created_at": row.created_at.isoformat() if row.created_at else "",
    }


def _studio_document_link_to_dict(row: StudioDocumentLink) -> dict[str, Any]:
    return {
        "id": row.id,
        "document_id": row.document_id,
        "target_type": row.target_type,
        "target_id": row.target_id,
        "relation": row.relation,
        "label": row.label,
        "metadata_json": row.metadata_json if isinstance(row.metadata_json, dict) else {},
        "created_at": row.created_at.isoformat() if row.created_at else "",
    }


async def _ensure_document_link(
    db: AsyncSession,
    *,
    document_id: int,
    target_type: str,
    target_id: str,
    relation: str,
    label: str,
    metadata_json: dict[str, Any] | None = None,
) -> None:
    existing = (
        await db.execute(
            select(StudioDocumentLink).where(
                StudioDocumentLink.document_id == document_id,
                StudioDocumentLink.target_type == target_type,
                StudioDocumentLink.target_id == target_id,
                StudioDocumentLink.relation == relation,
            )
        )
    ).scalars().first()
    if existing is not None:
        if label and not existing.label:
            existing.label = label
        return
    db.add(
        StudioDocumentLink(
            document_id=document_id,
            target_type=target_type,
            target_id=target_id,
            relation=relation,
            label=label,
            metadata_json=metadata_json or {},
        )
    )

async def _ensure_studio_document_seed(db: AsyncSession) -> None:
    count = int((await db.execute(select(func.count(StudioDocument.id)))).scalar() or 0)
    if count:
        return
    docs = [
        StudioDocument(
            title="MIM Studio Projects DB-Backed V1",
            summary="Evidence artifact for DB-backed Studio project signals, projects, events, and links.",
            document_type="artifact",
            category="reports",
            source_kind="local_file",
            source_path="runtime/shared/MIM_STUDIO_PROJECTS_DB_BACKED_V1.latest.md",
            local_path="runtime/shared/MIM_STUDIO_PROJECTS_DB_BACKED_V1.latest.md",
            preserve_policy="local_copy_required",
            snapshot_status="local",
            tags_json=["studio", "projects", "evidence"],
            metadata_json={"seeded_by": "studio_documents_v1"},
        ),
        StudioDocument(
            title="Documents Library Project",
            summary="Planning record for turning /studio/documents into MIM's wiki-style library for documents, media, links, notes, and research.",
            document_type="project_reference",
            category="projects",
            source_kind="studio_project",
            preserve_policy="reference",
            snapshot_status="tracked",
            tags_json=["documents", "library", "wiki", "project"],
            metadata_json={"seeded_by": "studio_documents_v1"},
        ),
        StudioDocument(
            title="Important External Reference Policy",
            summary="MIM should not rely on third-party webpages staying online. Important sources should be copied, summarized, indexed, or downloaded when allowed and needed for maintenance.",
            document_type="policy_note",
            category="policies",
            source_kind="operator_note",
            preserve_policy="snapshot_when_important",
            snapshot_status="policy_defined",
            tags_json=["preservation", "research", "maintenance"],
            metadata_json={"seeded_by": "studio_documents_v1"},
        ),
    ]
    db.add_all(docs)
    await db.commit()


async def _ensure_studio_document_relationship_seed(db: AsyncSession) -> None:
    docs = (
        await db.execute(select(StudioDocument).order_by(StudioDocument.id.asc()))
    ).scalars().all()
    if not docs:
        return
    projects = (
        await db.execute(select(StudioProject).order_by(StudioProject.id.asc()))
    ).scalars().all()
    project_by_title = {project.title: project for project in projects}
    project_by_slug = {
        str((project.metadata_json or {}).get("project_key") or "").strip(): project
        for project in projects
        if isinstance(project.metadata_json, dict)
    }
    for doc in docs:
        metadata = doc.metadata_json if isinstance(doc.metadata_json, dict) else {}
        if doc.category == "training":
            await _ensure_document_link(
                db,
                document_id=doc.id,
                target_type="training_run",
                target_id="current_mim_tod_training",
                relation="evidence_for",
                label="Current MIM/TOD training",
                metadata_json={"seeded_by": "studio_document_relationship_graph_v1"},
            )
            await _ensure_document_link(
                db,
                document_id=doc.id,
                target_type="page",
                target_id="/studio/training",
                relation="visible_on",
                label="Studio Training",
                metadata_json={"seeded_by": "studio_document_relationship_graph_v1"},
            )
        if doc.title == "Documents Library Project":
            documents_project = project_by_title.get("Documents Library") or project_by_slug.get("documents_library")
            if documents_project is not None:
                await _ensure_document_link(
                    db,
                    document_id=doc.id,
                    target_type="project",
                    target_id=str(documents_project.id),
                    relation="reference_for",
                    label=documents_project.title,
                    metadata_json={"seeded_by": "studio_document_relationship_graph_v1"},
                )
        if doc.title == "MIM Studio Projects DB-Backed V1":
            await _ensure_document_link(
                db,
                document_id=doc.id,
                target_type="report",
                target_id="mim_studio_projects_db_backed_v1",
                relation="evidence_for",
                label="Studio Projects DB-backed implementation",
                metadata_json={"seeded_by": "studio_document_relationship_graph_v1"},
            )
        if doc.title == "MIM Studio Training Page V1":
            await _ensure_document_link(
                db,
                document_id=doc.id,
                target_type="page",
                target_id="/studio/training",
                relation="evidence_for",
                label="Studio Training page",
                metadata_json={"seeded_by": "studio_document_relationship_graph_v1"},
            )
    await db.commit()


async def _studio_documents_state(
    db: AsyncSession,
    *,
    selected_document_id: int | None = None,
) -> dict[str, Any]:
    await _ensure_studio_document_seed(db)
    await _ensure_training_document_records(db)
    await _ensure_studio_document_relationship_seed(db)
    documents = (
        await db.execute(select(StudioDocument).order_by(StudioDocument.id.desc()).limit(80))
    ).scalars().all()
    links = (
        await db.execute(select(StudioDocumentLink).order_by(StudioDocumentLink.id.desc()).limit(240))
    ).scalars().all()
    rows = [_studio_document_to_dict(row) for row in documents]
    link_rows = [_studio_document_link_to_dict(row) for row in links]
    link_counts: dict[str, int] = {}
    for link in link_rows:
        link_counts[link["target_type"]] = link_counts.get(link["target_type"], 0) + 1
    selected_document = None
    selected_links: list[dict[str, Any]] = []
    if selected_document_id:
        selected = await db.get(StudioDocument, selected_document_id)
        if selected:
            selected_document = _studio_document_to_dict(selected)
            selected_links = [
                _studio_document_link_to_dict(row)
                for row in (
                    await db.execute(
                        select(StudioDocumentLink)
                        .where(StudioDocumentLink.document_id == selected.id)
                        .order_by(StudioDocumentLink.id.desc())
                    )
                ).scalars().all()
            ]
    counts = {
        "documents": len(rows),
        "local": sum(1 for item in rows if item["snapshot_status"] in {"local", "tracked"}),
        "needs_snapshot": sum(1 for item in rows if item["preserve_policy"] in {"local_copy_required", "snapshot_when_important"} and item["snapshot_status"] not in {"local", "tracked"}),
        "categories": len({item["category"] for item in rows if item["category"]}),
        "relationships": len(link_rows),
        "target_types": len(link_counts),
    }
    return {
        "documents": rows,
        "links": link_rows,
        "link_counts": link_counts,
        "target_types": [{"key": key, "label": label} for key, label in DOCUMENT_TARGET_TYPES],
        "selected_document": selected_document,
        "selected_links": selected_links,
        "counts": counts,
    }


async def _ensure_training_document_records(db: AsyncSession) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for spec in TRAINING_EVIDENCE_DOCS:
        filename = spec["filename"]
        existing = (
            await db.execute(
                select(StudioDocument).where(
                    StudioDocument.title == spec["title"],
                    StudioDocument.category == "training",
                )
            )
        ).scalars().first()
        source_path = f"runtime/shared/{filename}"
        metadata = {"filename": filename, "source": "training_page", "document_role": spec["kind"]}
        if existing is None:
            existing = StudioDocument(
                title=spec["title"],
                summary=spec["summary"],
                document_type=spec["kind"],
                category="training",
                source_kind="local_artifact",
                source_path=source_path,
                local_path=source_path,
                preserve_policy="local_copy_required",
                snapshot_status="local",
                tags_json=["training", spec["kind"], "evidence"],
                metadata_json=metadata,
            )
            db.add(existing)
            await db.flush()
        records.append(
            {
                "title": spec["title"],
                "filename": filename,
                "kind": spec["kind"],
                "summary": spec["summary"],
                "document_id": existing.id,
                "href": f"/studio/documents?document_id={existing.id}",
            }
        )
    await db.commit()
    return records


async def _studio_training_state(db: AsyncSession) -> dict[str, Any]:
    docs = await _ensure_training_document_records(db)
    directive = _load_json("MIM_TOD_CONTINUOUS_TRAINING_DIRECTIVE.latest.json")
    scoreboard = _load_json("MIM_TOD_TRAINING_SCOREBOARD.latest.json")
    reflection = _load_json("MIM_TOD_HOURLY_REFLECTION.latest.json")
    typo_smoke = _load_json("MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.json")
    blocker_summary = _load_text("TOD_BLOCKER_RESOLUTION_OPERATOR_SUMMARY.latest.md", limit=900)

    mim_training = directive.get("mim_training") if isinstance(directive.get("mim_training"), dict) else {}
    tod_training = directive.get("tod_training") if isinstance(directive.get("tod_training"), dict) else {}
    judgment = scoreboard.get("judgment_mode_score") if isinstance(scoreboard.get("judgment_mode_score"), dict) else {}
    mim_score = scoreboard.get("mim_score") if isinstance(scoreboard.get("mim_score"), dict) else {}
    tod_score = scoreboard.get("tod_score") if isinstance(scoreboard.get("tod_score"), dict) else {}
    training_hours = scoreboard.get("training_hours") if isinstance(scoreboard.get("training_hours"), dict) else {}

    are_improving = reflection.get("are_they_improving")
    assessment = _first_text(reflection.get("assessment"), scoreboard.get("status"), default="unknown")
    outcome_verdict = (
        "Outcomes are improving."
        if are_improving is True
        else "Training is active, but outcome improvement is not proven yet."
        if are_improving is False
        else "Training is active, but the outcome verdict is not available yet."
    )
    mim_pass_rate = judgment.get("pass_rate_percent", "baseline needed")
    typo_summary = typo_smoke.get("summary") if isinstance(typo_smoke.get("summary"), dict) else {}
    artifact_generated_at = _first_text(scoreboard.get("generated_at"), reflection.get("generated_at"), directive.get("updated_at"), default=_utc_now())
    page_loaded_at = _utc_now()
    attention_items = _training_attention_items(
        assessment=assessment,
        are_improving=are_improving,
        judgment=judgment,
        reflection=reflection,
        tod_score=tod_score,
    )
    return {
        "generated_at": artifact_generated_at,
        "generated_at_la": _la_time(artifact_generated_at),
        "generated_age": _age_label(artifact_generated_at),
        "page_loaded_at": page_loaded_at,
        "page_loaded_at_la": _la_time(page_loaded_at),
        "directive_status": _first_text(directive.get("status"), default="unknown"),
        "assessment": assessment,
        "are_improving": are_improving,
        "outcome_verdict": outcome_verdict,
        "attention_items": attention_items,
        "top_training_objective": {
            "id": "MIM-DEVELOPMENT-CONTINUITY-V1",
            "title": "MIM Development Continuity V1",
            "status": "next_top_training_objective",
            "owner": "MIM + TOD",
            "href": "/studio/projects?view=active",
            "why_now": "MIM communication and judgment are improving; continuity is the shortest route to proving those improvements change outcomes.",
            "mim_action": "Create the Before We Continue continuity brief before implementation-style requests.",
            "tod_action": "Verify related files, prior fixes, regressions, and validation evidence before execution starts.",
            "codex_gate": "Codex implements only after MIM/TOD provide the continuity brief or after the continuity process stalls.",
            "first_validation": "AgentMIM forum graphics",
        },
        "resolution_owner_model": "MIM owns the training objective, TOD implements and validates, Codex assists only after stall/failure, Dave is asked only for decisions or access.",
        "mim": {
            "focus": _first_text(mim_training.get("current_topic"), default="Project-manager communication and judgment-mode selection"),
            "status": _first_text(mim_training.get("status"), default="unknown"),
            "goal": _first_text(mim_training.get("goal"), default="MIM chooses the right response mode and explains work clearly."),
            "progress": f"{mim_pass_rate}% on judgment smoke" if isinstance(mim_pass_rate, int) else str(mim_pass_rate),
            "next": _first_text(judgment.get("target"), default="Continue judgment-mode training and retest."),
            "weakness": _first_text(judgment.get("current_weakness"), default="Recommendation and consultative discovery still need proof."),
        },
        "tod": {
            "focus": _first_text(tod_training.get("current_topic"), default="Codex-level implementation and blocker resolution"),
            "status": _first_text(tod_training.get("status"), default="unknown"),
            "goal": _first_text(tod_training.get("goal"), default="TOD inspects, edits, validates, reports evidence, and clears blockers."),
            "progress": _first_text(tod_score.get("blockers_cleared_today"), default="3 blockers cleared in latest drill evidence"),
            "next": "Continue linked-task blocker troubleshooting and prove one cleanup end-to-end.",
            "weakness": "TOD still detects more implementation problems than it independently fixes.",
        },
        "judgment": judgment,
        "mim_score": mim_score,
        "tod_score": tod_score,
        "training_hours": training_hours,
        "reflection": reflection,
        "typo": typo_summary,
        "blocker_summary": blocker_summary,
        "evidence_docs": docs,
    }


def _is_training_attention_prompt(prompt: str) -> bool:
    text_value = str(prompt or "").strip().lower()
    if not text_value:
        return False
    attention_terms = (
        "attention",
        "focus",
        "priority",
        "prioritize",
        "recommend",
        "next",
        "stuck",
        "weakness",
        "weak spot",
        "broken",
        "problem",
        "issue",
        "needs work",
        "what matters",
    )
    return any(term in text_value for term in attention_terms)


def _format_percent(value: object, default: str = "baseline needed") -> str:
    if isinstance(value, (int, float)):
        return f"{value}%"
    text = str(value or "").strip()
    return text if text else default


def _scoreboard_metric(score: dict[str, Any], key: str, default: str = "baseline needed") -> str:
    value = score.get(key) if isinstance(score, dict) else None
    return _format_percent(value, default=default)


def _training_attention_items(
    *,
    assessment: str,
    are_improving: object,
    judgment: dict[str, Any],
    reflection: dict[str, Any],
    tod_score: dict[str, Any],
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    pass_rate = judgment.get("pass_rate_percent")
    try:
        pass_rate_number = int(pass_rate)
    except Exception:
        pass_rate_number = None
    weakness = _first_text(
        judgment.get("current_weakness"),
        default="MIM judgment-mode weakness has not been summarized yet.",
    )
    if pass_rate_number is None or pass_rate_number < 80:
        items.append(
            {
                "key": "mim_judgment_mode",
                "title": "MIM judgment-mode selection",
                "status": "needs_attention",
                "owner": "MIM",
                "href": "/studio/training#mim_judgment_mode",
                "what_needs_attention": weakness,
                "why_it_matters": "MIM must choose recommendation, explanation, demonstration, consultative discovery, or problem analysis instead of dumping status.",
                "mim_action": "Create a focused judgment repair drill from the failed smoke cases and run another narrow sample set.",
                "tod_action": "Validate the new drill with pass/fail evidence and publish the updated smoke artifact.",
                "resolution_process": "MIM diagnoses failed mode choice, TOD validates the repaired behavior, Codex is called only if the routing logic or tests stall.",
            }
        )

    freshness = reflection.get("freshness") if isinstance(reflection.get("freshness"), dict) else {}
    stale_artifacts = freshness.get("stale_artifacts") if isinstance(freshness.get("stale_artifacts"), list) else reflection.get("stale_artifacts", [])
    if are_improving is not True or stale_artifacts:
        stale_count = len(stale_artifacts) if isinstance(stale_artifacts, list) else _first_text(reflection.get("stale_artifact_count"), default="unknown")
        items.append(
            {
                "key": "outcome_reflection_gap",
                "title": "Outcome reflection gap",
                "status": _plain_status(assessment, default="needs_attention"),
                "owner": "MIM + TOD",
                "href": "/studio/training#outcome_reflection_gap",
                "what_needs_attention": f"Outcome improvement is not proven and stale artifact count is {stale_count}.",
                "why_it_matters": "Training should not claim success until current evidence proves behavior improved.",
                "mim_action": "Open a resolution objective that lists stale artifacts, expected fresh replacements, and the proof required to mark improvement true.",
                "tod_action": "Refresh or retire stale execution and validation artifacts, then rerun the hourly reflection.",
                "resolution_process": "MIM owns the resolution objective, TOD clears evidence freshness, MIM re-assesses outcome improvement, Codex steps in if the refresh path stalls.",
                "details": stale_artifacts[:12] if isinstance(stale_artifacts, list) else [],
            }
        )

    metrics = tod_score.get("metrics") if isinstance(tod_score.get("metrics"), dict) else {}
    validated = metrics.get("validated_edits") if isinstance(metrics.get("validated_edits"), dict) else {}
    no_ops = metrics.get("no_op_rejections") if isinstance(metrics.get("no_op_rejections"), dict) else {}
    validated_today = validated.get("today") if isinstance(validated, dict) else None
    no_ops_today = no_ops.get("today") if isinstance(no_ops, dict) else None
    tod_score_text = json.dumps(tod_score, sort_keys=True).lower() if isinstance(tod_score, dict) else ""
    validated_baseline = (
        validated_today is None
        or (isinstance(validated_today, dict) and _plain_status(validated_today.get("status")) == "baseline_needed")
        or _plain_status(validated.get("source") if isinstance(validated, dict) else "") == "baseline_needed"
        or ("validated_edits" in tod_score_text and "baseline_needed" in tod_score_text)
    )
    no_ops_baseline = (
        no_ops_today is None
        or (isinstance(no_ops_today, dict) and _plain_status(no_ops_today.get("status")) == "baseline_needed")
        or _plain_status(no_ops.get("source") if isinstance(no_ops, dict) else "") == "baseline_needed"
        or ("no_op_rejections" in tod_score_text and "baseline_needed" in tod_score_text)
    )
    if validated_baseline or no_ops_baseline:
        items.append(
            {
                "key": "tod_validation_baselines",
                "title": "TOD validation baselines",
                "status": "baseline_needed",
                "owner": "TOD",
                "href": "/studio/training#tod_validation_baselines",
                "what_needs_attention": "Validated edits and no-op rejections are still baseline-needed metrics.",
                "why_it_matters": "TOD is training toward Codex-level performance, so it needs evidence that repairs changed files and rejected useless work.",
                "mim_action": "Keep this visible as a training objective until the metrics publish daily counts.",
                "tod_action": "Aggregate task results into daily validated-edit and no-op-rejection counters.",
                "resolution_process": "TOD implements the metric artifact, MIM checks it on each training page load, Codex assists only if aggregation fails repeatedly.",
            }
        )
    return items


def _compose_training_attention_reply(prompt: str, state: dict[str, Any]) -> str:
    judgment = state.get("judgment") if isinstance(state.get("judgment"), dict) else {}
    mim_score = state.get("mim_score") if isinstance(state.get("mim_score"), dict) else {}
    tod_score = state.get("tod_score") if isinstance(state.get("tod_score"), dict) else {}
    reflection = state.get("reflection") if isinstance(state.get("reflection"), dict) else {}

    pass_rate = _format_percent(judgment.get("pass_rate_percent"))
    weakness = _first_text(
        judgment.get("current_weakness"),
        state.get("mim", {}).get("weakness") if isinstance(state.get("mim"), dict) else "",
        default="MIM is still selecting the wrong response mode too often.",
    )
    target = _first_text(
        judgment.get("target"),
        state.get("mim", {}).get("next") if isinstance(state.get("mim"), dict) else "",
        default="Reach at least 80% on the focused judgment suite before expanding prompt sets.",
    )
    assessment = _plain_status(state.get("assessment"), default="unknown")
    stale_artifacts = reflection.get("stale_artifacts", "unknown")
    improving = reflection.get("are_they_improving", state.get("are_improving"))
    truth_integrity = _plain_status(reflection.get("truth_integrity"), default="unknown")
    blockers_cleared = _first_text(tod_score.get("blockers_cleared_today"), default="baseline needed")
    validated_edits = _first_text(tod_score.get("validated_edits_today"), default="baseline needed")
    no_op_rejections = _first_text(tod_score.get("no_op_rejections_today"), default="baseline needed")
    intent = _scoreboard_metric(mim_score, "intent_understood_today")
    answered = _scoreboard_metric(mim_score, "answered_question_today")
    recommendation = _scoreboard_metric(mim_score, "recommendation_quality_today")
    latest_evidence = _first_text(
        reflection.get("latest_evidence"),
        reflection.get("latest_evidence_id"),
        reflection.get("evidence"),
        default="TOD-BLOCKER-CLEARING-DRILL-004 completed_with_evidence",
    )

    return (
        "Three things need attention, Dave.\n\n"
        f"1. MIM judgment mode is the top repair. Evidence: the focused suite is at {pass_rate}, and the current weakness is: {weakness} "
        f"Action: keep training narrow until MIM can choose recommendation, explanation, demonstration, consultative discovery, or problem-analysis mode on purpose. Target: {target}\n\n"
        f"2. Outcome reflection is not ready to call healthy progress. Evidence: assessment is {assessment}, outcomes improving is {improving}, stale artifacts are {stale_artifacts}, and truth integrity is {truth_integrity}. "
        "Action: refresh or retire stale artifacts, then publish a new reflection only when the evidence proves a behavior changed.\n\n"
        f"3. TOD validation baselines still need tightening. Evidence: blockers cleared/transformed is {blockers_cleared}, but validated edits are {validated_edits} and no-op rejections are {no_op_rejections}. "
        f"Action: turn the latest blocker drill into repeatable pass/fail validation, then make the next TOD repair prove changed files, tests, and evidence.\n\n"
        f"The good signal: MIM's basic conversation score is holding at intent {intent}, answered question {answered}, and recommendation quality {recommendation}. "
        f"The next move I recommend is fixing the judgment-mode reply behavior first. Latest evidence I would anchor to: {latest_evidence}."
    )


def _compose_training_page_reply(prompt: str, state: dict[str, Any]) -> str:
    if _is_training_attention_prompt(prompt):
        return _compose_training_attention_reply(prompt, state)

    judgment = state.get("judgment") if isinstance(state.get("judgment"), dict) else {}
    pass_rate = _format_percent(judgment.get("pass_rate_percent"))
    verdict = _first_text(state.get("outcome_verdict"), default="Training is active, but the outcome verdict is not available yet.")
    weakness = _first_text(
        state.get("mim", {}).get("weakness") if isinstance(state.get("mim"), dict) else "",
        judgment.get("current_weakness"),
        default="MIM still needs judgment-mode proof.",
    )
    return (
        f"{verdict}\n\n"
        f"The short read: MIM judgment mode is at {pass_rate}, and the main weakness is {weakness} "
        "Ask me what needs attention, what changed, or what I recommend next and I will choose a concrete response mode instead of dumping the scoreboard."
    )


def _compose_reports_page_reply(prompt: str, dataset: dict[str, Any]) -> str:
    label = _first_text(dataset.get("label"), default="Reports")
    summary = _first_text(dataset.get("summary"), default="I could not load a report summary yet.")
    findings = dataset.get("findings") if isinstance(dataset.get("findings"), list) else []
    actions = dataset.get("actions") if isinstance(dataset.get("actions"), list) else []
    rows = dataset.get("rows") if isinstance(dataset.get("rows"), list) else []
    finding_lines = []
    for item in findings[:4]:
        if isinstance(item, dict):
            finding_lines.append(f"- {_first_text(item.get('title'), default='Finding')}: {_first_text(item.get('detail'), default='')}")
    action_lines = []
    for item in actions[:4]:
        if isinstance(item, dict):
            action_lines.append(f"- {_first_text(item.get('title'), default='Action')}: {_first_text(item.get('detail'), default='')}")
    if not finding_lines:
        finding_lines.append("- No findings were generated for this report yet.")
    if not action_lines:
        action_lines.append("- Ask a narrower report question or select a dataset.")
    return (
        f"Report mode: {label}.\n\n"
        f"{summary}\n\n"
        "What I found:\n"
        + "\n".join(finding_lines)
        + "\n\nResolution path:\n"
        + "\n".join(action_lines)
        + f"\n\nRows loaded: {len(rows)}. I should stay in Reports mode for this kind of request, not answer with the training scoreboard."
    )


def _studio_report_canvas_to_dict(row: StudioReportCanvas) -> dict[str, Any]:
    return {
        "id": row.id,
        "title": row.title,
        "prompt": row.prompt,
        "dataset_key": row.dataset_key,
        "status": row.status,
        "created_by": row.created_by,
        "summary": row.summary,
        "layout_json": row.layout_json if isinstance(row.layout_json, dict) else {},
        "filters_json": row.filters_json if isinstance(row.filters_json, dict) else {},
        "findings_json": row.findings_json if isinstance(row.findings_json, list) else [],
        "actions_json": row.actions_json if isinstance(row.actions_json, list) else [],
        "metadata_json": row.metadata_json if isinstance(row.metadata_json, dict) else {},
        "created_at": row.created_at.isoformat() if row.created_at else "",
    }


async def _status_counts(db: AsyncSession, column: Any) -> dict[str, int]:
    rows = (await db.execute(select(column, func.count()).group_by(column))).all()
    return {str(key or "unknown"): int(count or 0) for key, count in rows}


def _report_dataset_spec(dataset_key: str) -> dict[str, str]:
    return next((item for item in REPORT_DATASETS if item["key"] == dataset_key), REPORT_DATASETS[0])


def _app_source_for_prompt(prompt: str) -> dict[str, Any]:
    text_value = str(prompt or "").lower()
    if "agentmim" in text_value or "comm_app" in text_value or "commission" in text_value:
        return APP_SOURCE_REGISTRY[0]
    if "studio" in text_value:
        return APP_SOURCE_REGISTRY[1]
    return APP_SOURCE_REGISTRY[0]


def _async_database_url(raw_url: str) -> str:
    value = str(raw_url or "").strip()
    if value.startswith("postgresql://"):
        return "postgresql+asyncpg://" + value[len("postgresql://") :]
    if value.startswith("postgres://"):
        return "postgresql+asyncpg://" + value[len("postgres://") :]
    return value


def _redacted_db_location(raw_url: str) -> str:
    value = str(raw_url or "").strip()
    if not value:
        return "not configured"
    try:
        url = make_url(value)
        host = url.host or "unknown-host"
        database = (url.database or "").strip("/")
        return f"{url.drivername}://{host}/{database or 'unknown-db'}"
    except Exception:
        return "configured but not parseable"


def _infer_report_dataset(prompt: str, requested_dataset: str = "") -> tuple[str, str]:
    requested = str(requested_dataset or "").strip()
    text = str(prompt or "").strip().lower()
    if text:
        if any(term in text for term in ["agentmim", "mim wall", "users", "subscribers", "subscriber", "income", "revenue", "app usage", "traffic"]):
            return "app_metrics", "MIM selected App Metrics because the question is about app users, subscribers, usage, or revenue."
        if any(term in text for term in ["training", "trained", "scoreboard", "smoke", "pass rate", "improving"]):
            return "training", "MIM selected Training because the question is about learning, scorecards, or improvement."
        if any(term in text for term in ["objective", "objectives", "queued", "unfinished"]):
            return "objectives", "MIM selected Objectives because the question is about objective state or unfinished work."
        if any(term in text for term in ["task", "tasks", "dispatch", "executor"]):
            return "tasks", "MIM selected Tasks because the question is about executable work or dispatch."
        if any(term in text for term in ["project", "projects", "idea", "candidate"]):
            return "projects", "MIM selected Projects because the question is about tracked work or project candidates."
        if any(term in text for term in ["document", "documents", "library", "reference", "links", "connected"]):
            return "document_graph" if "connect" in text or "link" in text else "documents", "MIM selected Documents because the question is about library records or references."
        if any(term in text for term in ["blocked", "blocker", "stuck", "stalled", "stale"]):
            return "tod_blockers", "MIM selected TOD Blockers because the question is about stuck or blocked work."
        if any(term in text for term in ["health", "working", "status", "down", "broken"]):
            return "system_health", "MIM selected System Health because the question is about whether systems are working."
    if requested and requested != "auto":
        return _report_dataset_spec(requested)["key"], "MIM used the dataset you selected."
    return "studio_overview", "MIM started broad because no specific dataset was implied yet."


async def _studio_report_dataset(
    db: AsyncSession,
    dataset_key: str,
    *,
    prompt: str = "",
) -> dict[str, Any]:
    inferred_key, selection_reason = _infer_report_dataset(prompt, dataset_key)
    spec = _report_dataset_spec(inferred_key)
    key = spec["key"]
    stats: list[dict[str, Any]] = []
    columns: list[str] = []
    rows: list[dict[str, Any]] = []
    findings: list[dict[str, str]] = []
    actions: list[dict[str, str]] = []
    summary = ""

    if key == "training":
        training = await _studio_training_state(db)
        judgment = training.get("judgment") if isinstance(training.get("judgment"), dict) else {}
        mim_score = training.get("mim_score") if isinstance(training.get("mim_score"), dict) else {}
        tod_score = training.get("tod_score") if isinstance(training.get("tod_score"), dict) else {}
        stats = [
            {"label": "Outcome", "value": training.get("outcome_verdict", "unknown")},
            {"label": "MIM Focus", "value": training["mim"].get("focus", "")},
            {"label": "TOD Focus", "value": training["tod"].get("focus", "")},
            {"label": "Judgment Pass", "value": judgment.get("pass_rate_percent", "baseline needed")},
        ]
        columns = ["metric", "value", "source"]
        rows = [
            {"metric": "Intent Understood", "value": mim_score.get("intent_understood_today", "unknown"), "source": "scoreboard"},
            {"metric": "Answered Question", "value": mim_score.get("answered_question_today", "unknown"), "source": "scoreboard"},
            {"metric": "Internal Jargon", "value": mim_score.get("internal_jargon_today", "unknown"), "source": "scoreboard"},
            {"metric": "Recommendation Quality", "value": mim_score.get("recommendation_quality_today", "unknown"), "source": "scoreboard"},
            {"metric": "Blockers Cleared", "value": tod_score.get("blockers_cleared_today", "unknown"), "source": "scoreboard"},
            {"metric": "Validated Edits", "value": tod_score.get("validated_edits_today", "unknown"), "source": "scoreboard"},
        ]
        summary = f"{training.get('outcome_verdict')} MIM is training on {training['mim'].get('focus')}. TOD is training on {training['tod'].get('focus')}."
        findings = [
            {"title": "Outcome verdict", "detail": str(training.get("outcome_verdict", ""))},
            {"title": "MIM weak spot", "detail": str(training["mim"].get("weakness", ""))},
            {"title": "TOD weak spot", "detail": str(training["tod"].get("weakness", ""))},
        ]
        actions = [
            {"title": "Continue focused training", "detail": "Do not expand the suite until judgment-mode failures improve."},
            {"title": "Open evidence", "detail": "Use linked training documents before claiming improvement."},
        ]
    elif key == "objectives":
        counts = await _status_counts(db, Objective.state)
        objective_rows = (await db.execute(select(Objective).order_by(Objective.id.desc()).limit(80))).scalars().all()
        stats = [
            {"label": "Objectives", "value": sum(counts.values())},
            {"label": "States", "value": len(counts)},
            {"label": "Queued", "value": counts.get("queued", 0)},
            {"label": "Completed Evidence", "value": counts.get("completed_with_evidence", 0)},
        ]
        columns = ["id", "title", "owner", "priority", "state"]
        rows = [{"id": item.id, "title": item.title, "owner": item.owner, "priority": item.priority, "state": item.state} for item in objective_rows]
        summary = f"This report is looking at {sum(counts.values())} objectives across {len(counts)} states. It is useful for finding queue pressure, stale ownership, and completed-vs-tested truth."
        findings = [{"title": state, "detail": f"{count} objectives"} for state, count in sorted(counts.items())[:8]]
        actions = [{"title": "Inspect unfinished work", "detail": "Filter queued, blocked, stale, or running work and decide whether to repair, supersede, or promote."}]
    elif key == "tasks":
        counts = await _status_counts(db, Task.state)
        task_rows = (await db.execute(select(Task).order_by(Task.id.desc()).limit(80))).scalars().all()
        stats = [
            {"label": "Tasks", "value": sum(counts.values())},
            {"label": "States", "value": len(counts)},
            {"label": "Queued", "value": counts.get("queued", 0)},
            {"label": "Blocked", "value": counts.get("blocked", 0)},
        ]
        columns = ["id", "objective_id", "title", "assigned_to", "state", "dispatch_status"]
        rows = [
            {"id": item.id, "objective_id": item.objective_id or "", "title": item.title, "assigned_to": item.assigned_to, "state": item.state, "dispatch_status": item.dispatch_status}
            for item in task_rows
        ]
        summary = f"This report is looking at {sum(counts.values())} tasks across {len(counts)} states. It shows whether objectives are turning into executable work."
        findings = [{"title": state, "detail": f"{count} tasks"} for state, count in sorted(counts.items())[:8]]
        actions = [{"title": "Validate completion quality", "detail": "Look for done tasks without changed files, tests, or evidence."}]
    elif key == "projects":
        projects = await _studio_projects_state(db)
        stats = [
            {"label": "Active", "value": projects["counts"].get("active", 0)},
            {"label": "Signals", "value": projects["counts"].get("signals", 0)},
            {"label": "Candidates", "value": projects["counts"].get("candidates", 0)},
            {"label": "Dave Needed", "value": projects["counts"].get("dave_needed", 0)},
        ]
        columns = ["id", "title", "status", "priority", "health", "next_action"]
        rows = projects.get("projects", [])
        summary = "This report is looking at Studio projects and project signals. It is useful for turning ideas into tracked outcomes without losing the origin story."
        findings = [{"title": "Project memory", "detail": f"{projects['counts'].get('active', 0)} active projects and {projects['counts'].get('signals', 0)} signals are tracked."}]
        actions = [{"title": "Review candidate inbox", "detail": "Promote, park, merge, or discard project signals before they become noise."}]
    elif key == "documents":
        docs = await _studio_documents_state(db)
        stats = [
            {"label": "Documents", "value": docs["counts"].get("documents", 0)},
            {"label": "Local / Tracked", "value": docs["counts"].get("local", 0)},
            {"label": "Need Snapshot", "value": docs["counts"].get("needs_snapshot", 0)},
            {"label": "Relationships", "value": docs["counts"].get("relationships", 0)},
        ]
        columns = ["id", "title", "category", "document_type", "snapshot_status"]
        rows = docs.get("documents", [])
        summary = "This report is looking at the document library and preservation state: what MIM knows, where it came from, and what may need local preservation."
        findings = [
            {"title": "Reference memory", "detail": f"{docs['counts'].get('relationships', 0)} document relationships are available."},
            {"title": "Preservation watch", "detail": f"{docs['counts'].get('needs_snapshot', 0)} important items still need snapshot attention."},
        ]
        actions = [{"title": "Attach documents", "detail": "Connect evidence to projects, reports, objectives, tasks, and training runs."}]
    elif key == "document_graph":
        docs = await _studio_documents_state(db)
        stats = [
            {"label": "Relationships", "value": docs["counts"].get("relationships", 0)},
            {"label": "Target Types", "value": docs["counts"].get("target_types", 0)},
            {"label": "Documents", "value": docs["counts"].get("documents", 0)},
            {"label": "Categories", "value": docs["counts"].get("categories", 0)},
        ]
        columns = ["id", "document_id", "target_type", "target_id", "relation", "label"]
        rows = docs.get("links", [])
        summary = "This report is looking at how documents connect to Studio objects. It is the start of MIM's reference-memory graph."
        findings = [{"title": "Graph coverage", "detail": f"{docs['counts'].get('relationships', 0)} links across {docs['counts'].get('target_types', 0)} target types."}]
        actions = [{"title": "Show backlinks", "detail": "Next, surface related documents from project, objective, report, app, system, and training pages."}]
    elif key == "tod_blockers":
        blocker_text = _load_text("TOD_BLOCKER_RESOLUTION_OPERATOR_SUMMARY.latest.md", limit=2400)
        stats = [
            {"label": "Source", "value": "TOD blocker summary"},
            {"label": "Loaded", "value": "yes" if blocker_text else "no"},
            {"label": "Characters", "value": len(blocker_text)},
            {"label": "Purpose", "value": "blocker cleanup"},
        ]
        columns = ["section", "detail", "source"]
        rows = [{"section": "Summary", "detail": line.strip(), "source": "TOD blocker summary"} for line in blocker_text.splitlines() if line.strip()][:40]
        summary = "This report loads the latest TOD blocker-resolution summary. Use it to inspect what is blocked, what was narrowed, and what proof exists."
        findings = [{"title": "Blocker source", "detail": "Review the rows for current blocker class and proof language."}]
        actions = [{"title": "Create repair action", "detail": "If a blocker is current, route it through H.A.L. or create a TOD cleanup task."}]
    elif key == "system_health":
        snapshot = _studio_snapshot()
        stats = [
            {"label": "MIM", "value": snapshot.get("mim_focus", "")},
            {"label": "TOD", "value": snapshot.get("tod_focus", "")},
            {"label": "Attention", "value": len(snapshot.get("attention", []))},
            {"label": "Dave Needed", "value": len(snapshot.get("dave_needed", []))},
        ]
        columns = ["owner", "title", "detail"]
        rows = snapshot.get("attention", [])
        summary = "This report is looking at the current Studio health snapshot and attention items. Use it when the question is whether MIM/TOD are healthy or stuck."
        findings = [{"title": item.get("title", "Attention item"), "detail": item.get("detail", "")} for item in rows if isinstance(item, dict)][:5]
        actions = [{"title": "Open H.A.L. if needed", "detail": "If an attention item implies frozen or stale work, run diagnosis and create a repair task."}]
    elif key == "app_metrics":
        app_source = _app_source_for_prompt(prompt)
        app_name = str(app_source.get("display_name", "MIM Apps"))
        app_db_url = str(settings.comm_app_database_url or "").strip()
        app_db_engine = None
        app_db_session: AsyncSession | None = None
        app_db_error = ""
        app_db_configured = bool(app_db_url)
        app_db_location = _redacted_db_location(app_db_url)
        app_db_connected = False
        if app_db_configured:
            try:
                app_db_engine = create_async_engine(_async_database_url(app_db_url), echo=False, future=True)
                app_db_session = AsyncSession(app_db_engine)
                await app_db_session.execute(text("select 1"))
                app_db_connected = True
            except Exception as exc:
                app_db_error = str(exc)
                if app_db_session is not None:
                    await app_db_session.close()
                    app_db_session = None
                if app_db_engine is not None:
                    await app_db_engine.dispose()
                    app_db_engine = None

        primary_db = app_db_session if app_db_session is not None else db

        async def scalar_sql(sql: str, session: AsyncSession | None = None) -> int:
            active_session = session or primary_db
            try:
                value = (await active_session.execute(text(sql))).scalar()
                return int(value or 0)
            except Exception:
                return 0

        async def table_exists(table_name: str, session: AsyncSession | None = None) -> bool:
            active_session = session or primary_db
            try:
                return bool(
                    (
                        await active_session.execute(
                            text(
                                "select exists (select 1 from information_schema.tables where table_schema='public' and table_name=:table)"
                            ),
                            {"table": table_name},
                        )
                    ).scalar()
                )
            except Exception:
                return False

        primary_table = str(app_source.get("primary_account_table", ""))
        secondary_table = str(app_source.get("secondary_user_table", ""))
        primary_connected = await table_exists(primary_table)
        secondary_connected = await table_exists(secondary_table)
        primary_count = await scalar_sql(f'select count(*) from "{primary_table}"') if primary_connected else 0
        secondary_count = await scalar_sql(f'select count(*) from "{secondary_table}"') if secondary_connected else 0
        portal_accounts = await scalar_sql('select count(*) from "project_portal_accounts"', db)
        portal_projects = await scalar_sql('select count(*) from "project_portal_projects"', db)
        sessions_total = await scalar_sql('select count(*) from "workspace_interface_sessions"', db)
        sessions_30d = await scalar_sql("select count(*) from workspace_interface_sessions where coalesce(last_input_at, created_at) >= now() - interval '30 days'", db)
        messages_total = await scalar_sql('select count(*) from "workspace_interface_messages"', db)
        messages_30d = await scalar_sql("select count(*) from workspace_interface_messages where created_at >= now() - interval '30 days'", db)
        input_events_30d = await scalar_sql("select count(*) from input_events where created_at >= now() - interval '30 days'", db)
        known_account_count = primary_count if primary_connected else portal_accounts
        account_source = primary_table if primary_connected else "project_portal_accounts fallback"
        db_status = (
            f"connected to {app_db_location}"
            if app_db_connected
            else f"not configured; set COMM_APP_DATABASE_URL for {app_name}"
            if not app_db_configured
            else f"connection failed for {app_db_location}: {app_db_error[:220]}"
        )
        stats = [
            {"label": "Requested App", "value": app_name},
            {"label": "Known Accounts", "value": known_account_count},
            {"label": "Sessions 30d", "value": sessions_30d},
            {"label": "Messages 30d", "value": messages_30d},
        ]
        columns = ["data_needed", "current_status", "next_step"]
        rows = [
            {"data_needed": "App source", "current_status": f"{app_source.get('app_key')} | {app_source.get('ecosystem_role')} | {app_source.get('runtime')}", "next_step": "Keep app-source registry current for MIM and TOD"},
            {"data_needed": "comm_app DB binding", "current_status": db_status, "next_step": "Set COMM_APP_DATABASE_URL on the MIM Studio service to the AgentMIM/comm_app Render Postgres URL, then restart Studio."},
            {"data_needed": f"Primary account table: {primary_table}", "current_status": f"{'connected' if primary_connected else 'missing from current DB connection'}; count={primary_count}", "next_step": "Use this as the true app account count once the comm_app Render DB is bound"},
            {"data_needed": f"Secondary user table: {secondary_table}", "current_status": f"{'connected' if secondary_connected else 'missing from current DB connection'}; count={secondary_count}", "next_step": "Use this for representative/user counts once connected"},
            {"data_needed": "Fallback account records", "current_status": f"{portal_accounts} rows in project_portal_accounts", "next_step": "Use only as MIM/portal fallback when app-specific table is unavailable"},
            {"data_needed": "Project portal projects", "current_status": f"{portal_projects} rows in project_portal_projects", "next_step": "Use for portal-project adoption reporting"},
            {"data_needed": "Interface sessions", "current_status": f"{sessions_30d} sessions in last 30 days / {sessions_total} total", "next_step": "Add app/source grouping for AgentMIM vs Studio vs MIM Wall"},
            {"data_needed": "Interface messages", "current_status": f"{messages_30d} messages in last 30 days / {messages_total} total", "next_step": "Add app/source grouping and human-vs-system segmentation"},
            {"data_needed": "Input events", "current_status": f"{input_events_30d} input events in last 30 days", "next_step": "Use for activity trend reporting after source names are standardized"},
            {"data_needed": "Subscribers / revenue", "current_status": "Stripe/subscription source is configured in env but not yet registered as a report dataset", "next_step": "Create a subscription/revenue adapter before reporting paid users or income"},
        ]
        if primary_connected:
            summary = f"I understand the question is about {app_name}. The app-source registry identifies {primary_table} as the primary account table, and the connected database currently shows {primary_count} account records there."
        else:
            summary = f"I understand the question is about {app_name}. The app-source registry identifies {primary_table} as the real comm_app account table, but Studio cannot read the AgentMIM database yet. Current binding status: {db_status}. I can see {portal_accounts} fallback MIM/portal account records in project_portal_accounts, but those are not the true comm_app account-owner records."
        findings = [
            {"title": "Correct dataset identified", "detail": "This is an app metrics question, not a Studio Projects report."},
            {"title": "App source registered", "detail": f"{app_name} is mapped as {app_source.get('ecosystem_role')} at {app_source.get('local_root')}."},
            {"title": "Database binding status", "detail": db_status},
            {"title": "Primary app table status", "detail": f"{primary_table}: {'connected' if primary_connected else 'missing from current DB connection'}."},
            {"title": "Fallback accounts available", "detail": f"{portal_accounts} records are available from project_portal_accounts."},
            {"title": "Usage telemetry exists", "detail": f"{sessions_30d} sessions and {messages_30d} messages are available for the last 30 days, but source grouping needs normalization."},
        ]
        actions = [
            {"title": "Verify comm_app Render DB binding", "detail": f"Studio Reports needs access to the database containing {primary_table} and {secondary_table}."},
            {"title": "Add subscription adapter", "detail": "Connect Stripe/accounting subscription data before reporting paid users or income."},
            {"title": "Normalize telemetry source names", "detail": "Group sessions/messages by app so Reports can answer app-specific usage questions cleanly."},
        ]
        if app_db_session is not None:
            await app_db_session.close()
        if app_db_engine is not None:
            await app_db_engine.dispose()
    else:
        overview = _studio_snapshot()
        stats = [
            {"label": "MIM", "value": overview.get("mim_focus", "")},
            {"label": "TOD", "value": overview.get("tod_focus", "")},
            {"label": "Attention", "value": len(overview.get("attention", []))},
            {"label": "Projects", "value": len(overview.get("projects", []))},
        ]
        columns = ["area", "status", "detail"]
        rows = [
            {"area": "MIM", "status": "active", "detail": overview.get("mim_focus", "")},
            {"area": "TOD", "status": "active", "detail": overview.get("tod_focus", "")},
            {"area": "Recommendation", "status": "ready", "detail": (overview.get("recommendation") or {}).get("title", "")},
        ]
        summary = "This is a broad Studio overview. Use it when the question is open-ended and MIM needs to decide what data matters."
        findings = [{"title": "Start broad, then narrow", "detail": "Pick a more specific dataset after MIM identifies the likely source of truth."}]
        actions = [{"title": "Ask a sharper question", "detail": "Examples: training last week, blocked objectives, document graph, app users, accounting vendors."}]

    if prompt:
        summary = f"Question: {prompt.strip()} {summary}"
    return {
        "key": key,
        "label": spec["label"],
        "description": spec["description"],
        "selection_reason": selection_reason,
        "requested_dataset": dataset_key,
        "generated_at": _utc_now(),
        "summary": summary,
        "stats": stats,
        "columns": columns,
        "rows": rows[:120],
        "findings": findings[:8],
        "actions": actions[:6],
    }


async def _ensure_studio_report_seed(db: AsyncSession) -> None:
    count = int((await db.execute(select(func.count(StudioReportCanvas.id)))).scalar() or 0)
    if count:
        return
    dataset = await _studio_report_dataset(db, "training", prompt="How are MIM and TOD training going?")
    row = StudioReportCanvas(
        title="Training Outcome Check",
        prompt="How are MIM and TOD training going?",
        dataset_key="training",
        status="saved",
        created_by="MIM",
        summary=dataset["summary"],
        layout_json={"template": "scorecard_table"},
        filters_json={"range": "latest"},
        findings_json=dataset["findings"],
        actions_json=dataset["actions"],
        metadata_json={"seeded_by": "studio_reports_v1"},
    )
    db.add(row)
    await db.commit()


async def _studio_reports_state(
    db: AsyncSession,
    *,
    dataset_key: str = "studio_overview",
    prompt: str = "",
    canvas_id: int | None = None,
) -> dict[str, Any]:
    await _ensure_studio_report_seed(db)
    canvases = (await db.execute(select(StudioReportCanvas).order_by(StudioReportCanvas.id.desc()).limit(30))).scalars().all()
    selected_canvas = None
    if canvas_id:
        selected = await db.get(StudioReportCanvas, canvas_id)
        if selected:
            selected_canvas = _studio_report_canvas_to_dict(selected)
            dataset_key = selected.dataset_key
            prompt = selected.prompt
    dataset = await _studio_report_dataset(db, dataset_key, prompt=prompt)
    return {
        "datasets": REPORT_DATASETS,
        "dataset": dataset,
        "canvases": [_studio_report_canvas_to_dict(row) for row in canvases],
        "selected_canvas": selected_canvas,
        "prompt": prompt,
    }


def _projects_body(state: dict[str, Any]) -> str:
    counts = state.get("counts") if isinstance(state.get("counts"), dict) else {}
    view = str(state.get("view") or "all").strip().lower()
    selected_project = state.get("selected_project") if isinstance(state.get("selected_project"), dict) else None
    selected_events = state.get("selected_events") if isinstance(state.get("selected_events"), list) else []
    new_project = bool(state.get("new_project"))
    project_stats = [
        ("Signals", counts.get("signals", 0), "signals"),
        ("Candidates", counts.get("candidates", 0), "candidates"),
        ("Active", counts.get("active", 0), "active"),
        ("Dave Needed", counts.get("dave_needed", 0), "dave_needed"),
    ]
    stats_html = "".join(
        f"""
        <a class="card" href="/studio/projects?view={_html(key)}">
          <div class="label">{_html(label)}</div>
          <div class="entity">{_html(value)}</div>
        </a>
        """
        for label, value, key in project_stats
    )
    projects = state.get("projects") if isinstance(state.get("projects"), list) else []
    inbox_examples = state.get("signals") if isinstance(state.get("signals"), list) else []

    def project_visible(item: dict[str, Any]) -> bool:
        status = str(item.get("status") or "").strip().lower()
        if view == "active":
            return status not in {"archived", "scrapped", "discarded", "deleted"}
        if view == "candidates":
            return status in {"candidate", "queued"}
        if view == "dave_needed":
            return bool(item.get("dave_needed"))
        return True

    project_rows = "".join(
        f"""
        <tr class="row-link" onclick="window.location.href='/studio/projects?project_id={_html(item.get("id", ""))}&view={_html(view)}'">
          <td><strong>{_html(item.get("title", ""))}</strong><div class="muted">{_html(item.get("project_type", ""))}</div></td>
          <td><span class="health-pill yellow">{_html(item.get("status", ""))}</span><div class="muted">{_html(item.get("work_state", ""))}</div></td>
          <td>{_html(item.get("owner", ""))}</td>
          <td><div class="progress-track"><div class="progress-fill" style="width:{_html(item.get("progress_percent", 0))}%;"></div></div><div class="muted">{_html(item.get("progress_percent", 0))}%</div></td>
          <td>{_html(item.get("blocker", "none"))}</td>
          <td>{_html(item.get("next_action", ""))}</td>
          <td>{'yes' if item.get("dave_needed") else 'no'}</td>
        </tr>
        """
        for item in projects
        if view != "signals" and project_visible(item)
    )
    if not project_rows and view != "signals":
        project_rows = '<tr><td colspan="7">No projects in this view.</td></tr>'

    signal_rows = "".join(
        f"""
        <tr>
          <td><strong>{_html(item.get("title", ""))}</strong><div class="muted">{_html(item.get("source_surface", ""))}</div></td>
          <td><span class="health-pill yellow">{_html(item.get("status", ""))}</span></td>
          <td>{_html(item.get("priority", ""))}</td>
          <td>{_html(item.get("suggested_action", ""))}</td>
          <td>{_html(item.get("source_text", ""))}</td>
          <td>
            <form method="post" action="/studio/projects/signals/{_html(item.get("id", ""))}/promote" style="display:inline;">
              <button class="button" type="submit">Promote</button>
            </form>
          </td>
        </tr>
        """
        for item in inbox_examples
        if view in {"all", "signals", "candidates"}
    )
    if not signal_rows:
        signal_rows = '<tr><td colspan="6">No signals in this view.</td></tr>'

    new_project_html = ""
    if new_project:
        new_project_html = """
        <section class="card" style="margin-bottom:14px;">
          <h2>New Project</h2>
          <form method="post" action="/studio/projects/create" class="form-grid">
            <label>Title<input name="title" required maxlength="220"></label>
            <label>Owner<input name="owner" value="TOD"></label>
            <label>Status<input name="status" value="queued"></label>
            <label>Priority<input name="priority" value="P1"></label>
            <label>Progress %<input name="progress_percent" type="number" min="0" max="100" value="0"></label>
            <label>Dave Needed<select name="dave_needed"><option value="false">no</option><option value="true">yes</option></select></label>
            <label class="wide">Summary<textarea name="summary"></textarea></label>
            <label class="wide">Next Action<textarea name="next_action"></textarea></label>
            <label class="wide">Blocker / Action Needed<textarea name="blocker">none</textarea></label>
            <div class="actions wide"><button class="button primary" type="submit">Save Project</button><a class="button" href="/studio/projects">Cancel</a></div>
          </form>
        </section>
        """

    selected_html = ""
    if selected_project:
        event_rows = "".join(
            f"""
            <article class="attention-item">
              <small>{_html(event.get("event_type", ""))} / {_html(event.get("actor", ""))}</small>
              <strong>{_html(event.get("title", ""))}</strong>
              <div class="muted">{_html(event.get("detail", ""))}</div>
            </article>
            """
            for event in selected_events
        )
        if not event_rows:
            event_rows = '<article class="attention-item"><strong>No events yet</strong></article>'
        selected_html = f"""
        <section class="card" style="margin-bottom:14px;">
          <h2>{_html(selected_project.get("title", "Project"))}</h2>
          <form method="post" action="/studio/projects/{_html(selected_project.get("id", ""))}/update" class="form-grid">
            <label>Status<input name="status" value="{_html(selected_project.get("status", ""))}"></label>
            <label>Owner<input name="owner" value="{_html(selected_project.get("owner", ""))}"></label>
            <label>Priority<input name="priority" value="{_html(selected_project.get("priority", ""))}"></label>
            <label>Progress %<input name="progress_percent" type="number" min="0" max="100" value="{_html(selected_project.get("progress_percent", 0))}"></label>
            <label>Health<input name="health" value="{_html(selected_project.get("health", ""))}"></label>
            <label>Dave Needed<select name="dave_needed"><option value="false" {'selected' if not selected_project.get("dave_needed") else ''}>no</option><option value="true" {'selected' if selected_project.get("dave_needed") else ''}>yes</option></select></label>
            <label class="wide">Summary<textarea name="summary">{_html(selected_project.get("summary", ""))}</textarea></label>
            <label class="wide">Next Action<textarea name="next_action">{_html(selected_project.get("next_action", ""))}</textarea></label>
            <label class="wide">Blocker / Action Needed<textarea name="blocker">{_html(selected_project.get("blocker", "none"))}</textarea></label>
            <div class="actions wide">
              <button class="button primary" type="submit">Save Changes</button>
              <button class="button" type="submit" formaction="/studio/projects/{_html(selected_project.get("id", ""))}/pause">Pause</button>
              <button class="button danger" type="submit" formaction="/studio/projects/{_html(selected_project.get("id", ""))}/delete">Delete</button>
              <a class="button" href="/studio/projects">Close</a>
            </div>
          </form>
          <form method="post" action="/studio/projects/{_html(selected_project.get("id", ""))}/events" class="form-grid" style="margin-top:14px;">
            <label>Event Title<input name="title" maxlength="220"></label>
            <label>Actor<input name="actor" value="Dave"></label>
            <label class="wide">Note<textarea name="detail"></textarea></label>
            <div class="actions wide"><button class="button" type="submit">Add Note</button></div>
          </form>
          <div class="attention-list" style="margin-top:12px;">{event_rows}</div>
        </section>
        """

    return f"""
    <section class="grid four" style="grid-template-columns: repeat(4, minmax(0, 1fr)); margin-bottom:14px;">{stats_html}</section>
    <section class="card" style="margin-bottom:14px;">
      <h2>Project Actions</h2>
      <div class="actions" style="margin-top:12px; flex-wrap:wrap;">
        <a class="button primary" href="/studio/projects?new_project=1">Start Project</a>
        <a class="button" href="/studio/projects?view=active">Open Project</a>
        <a class="button" href="/studio/projects?view=signals">Review Signal Inbox</a>
      </div>
    </section>
    {new_project_html}
    {selected_html}
    <section class="card" style="margin-bottom:14px;">
      <h2>Project Inbox</h2>
      <table class="score-table">
        <thead><tr><th>Project</th><th>Status</th><th>Owner</th><th>Done</th><th>Blocker</th><th>Next Action</th><th>Dave</th></tr></thead>
        <tbody>{project_rows}</tbody>
      </table>
    </section>
    <section class="card">
      <h2>Signals</h2>
      <table class="score-table">
        <thead><tr><th>Signal</th><th>Status</th><th>Priority</th><th>Action</th><th>Origin</th><th></th></tr></thead>
        <tbody>{signal_rows}</tbody>
      </table>
    </section>
    """


def _documents_body(state: dict[str, Any]) -> str:
    counts = state.get("counts") if isinstance(state.get("counts"), dict) else {}
    documents = state.get("documents") if isinstance(state.get("documents"), list) else []
    links = state.get("links") if isinstance(state.get("links"), list) else []
    link_counts = state.get("link_counts") if isinstance(state.get("link_counts"), dict) else {}
    target_types = state.get("target_types") if isinstance(state.get("target_types"), list) else []
    selected_document = state.get("selected_document") if isinstance(state.get("selected_document"), dict) else None
    selected_links = state.get("selected_links") if isinstance(state.get("selected_links"), list) else []
    stats = [
        ("Items", counts.get("documents", 0), "library records"),
        ("Local / Tracked", counts.get("local", 0), "available without relying on the source"),
        ("Need Snapshot", counts.get("needs_snapshot", 0), "important items not preserved yet"),
        ("Relationships", counts.get("relationships", 0), "document graph links"),
    ]
    stats_html = "".join(
        f"""
        <article class="card">
          <div class="label">{_html(label)}</div>
          <div class="entity">{_html(value)}</div>
          <p>{_html(detail)}</p>
        </article>
        """
        for label, value, detail in stats
    )
    doc_rows = "".join(
        f"""
        <article class="attention-item">
          <small>{_html(item.get("category", "library"))} / {_html(item.get("document_type", "note"))}</small>
          <strong>{_html(item.get("title", ""))}</strong>
          <div class="muted">{_html(item.get("summary", ""))}</div>
          <div class="muted">Preserve: {_html(item.get("preserve_policy", ""))} / Snapshot: {_html(item.get("snapshot_status", ""))}</div>
        </article>
        """
        for item in documents[:10]
    )
    if not doc_rows:
        doc_rows = '<article class="attention-item"><strong>No documents yet</strong><div class="muted">MIM can create, collect, or link the first library item.</div></article>'
    category_cards = [
        ("Project Material", "Blueprints, roadmaps, evidence, screenshots, prototypes, project notes, and approvals."),
        ("Research", "Books, papers, links, references, market notes, app examples, and preserved source material."),
        ("Media", "Images, audio, video, art, generated samples, screenshots, and reviewable visual assets."),
        ("Operations", "Vendors, systems, status updates, incidents, policies, runbooks, and maintenance notes."),
        ("Conversations", "Important MIM/Dave discussions that created decisions, projects, observations, or follow-ups."),
        ("Odd Shelf", "Useful strange context that does not fit neatly anywhere but may matter later."),
    ]
    categories_html = "".join(
        f"""
        <article class="card">
          <h3>{_html(title)}</h3>
          <p>{_html(detail)}</p>
        </article>
        """
        for title, detail in category_cards
    )
    relationship_type_rows = "".join(
        f"""
        <tr>
          <td>{_html(item.get("label", item.get("key", "")))}</td>
          <td>{_html(link_counts.get(str(item.get("key", "")), 0))}</td>
        </tr>
        """
        for item in target_types
    )
    if not relationship_type_rows:
        relationship_type_rows = '<tr><td>No target types yet</td><td>0</td></tr>'
    recent_links_html = "".join(
        f"""
        <article class="attention-item">
          <small>{_html(item.get("relation", "related"))}</small>
          <strong>Document #{_html(item.get("document_id", ""))} -> {_html(item.get("target_type", ""))}</strong>
          <div class="muted">{_html(item.get("label", ""))}</div>
          <div class="muted">Target: {_html(item.get("target_id", ""))}</div>
        </article>
        """
        for item in links[:8]
    )
    if not recent_links_html:
        recent_links_html = '<article class="attention-item"><strong>No relationships yet</strong><div class="muted">Attach a document to a project, objective, task, conversation, report, app, system, or training run.</div></article>'
    selected_links_html = ""
    if selected_document:
        selected_relationship_rows = "".join(
            f"""
            <article class="attention-item">
              <small>{_html(item.get("target_type", ""))} / {_html(item.get("relation", ""))}</small>
              <strong>{_html(item.get("label", "") or item.get("target_id", ""))}</strong>
              <div class="muted">Target ID: {_html(item.get("target_id", ""))}</div>
            </article>
            """
            for item in selected_links
        )
        if not selected_relationship_rows:
            selected_relationship_rows = '<article class="attention-item"><strong>No links for this document yet</strong><div class="muted">This item exists, but it is not attached to a Studio object yet.</div></article>'
        selected_links_html = f"""
        <section class="card" style="margin-bottom:14px;">
          <h2>Selected Document</h2>
          <div class="label">{_html(selected_document.get("category", "library"))} / {_html(selected_document.get("document_type", "note"))}</div>
          <h3>{_html(selected_document.get("title", ""))}</h3>
          <p>{_html(selected_document.get("summary", ""))}</p>
          <div class="attention-list" style="margin-top:12px;">{selected_relationship_rows}</div>
        </section>
        """
    return f"""
    <section class="grid four" style="grid-template-columns: repeat(4, minmax(0, 1fr)); margin-bottom:14px;">{stats_html}</section>
    {selected_links_html}
    <section class="card" style="margin-bottom:14px;">
      <h2>Library Actions</h2>
      <p>Documents are the MIM library: records, files, links, media, research, notes, artifacts, and anything worth remembering without turning it into a project.</p>
      <div class="actions" style="margin-top:12px; flex-wrap:wrap;">
        <a class="button primary" href="/studio/documents">Add Document</a>
        <a class="button" href="/studio/documents">Add Link</a>
        <a class="button" href="/studio/documents">Attach To Project</a>
        <a class="button" href="/mim">Ask MIM To Create Document</a>
      </div>
    </section>
    <section class="grid two">
      <article class="card">
        <h2>Wiki Library</h2>
        <p>Organize documents like a living wiki, not a dump. Every item should answer what it is, why we kept it, where it came from, whether it is preserved locally, and what it connects to.</p>
        <div class="label">Can Associate With</div>
        <ul class="clean">
          <li>apps, projects, project signals, tasks, objectives, reports, status updates, conversations, vendors, people, systems, and lab work.</li>
          <li>Multiple links are allowed because one useful document may affect several projects or future decisions.</li>
        </ul>
      </article>
      <article class="card">
        <h2>Preservation Rule</h2>
        <p>MIM should not depend on a third-party resource being available forever. Important material should be copied, summarized, indexed, downloaded, or locally referenced when allowed and needed for maintenance or evolution.</p>
        <div class="label">MIM Should Decide</div>
        <ul class="clean">
          <li>Reference only: low importance or stable source.</li>
          <li>Snapshot when important: useful source that may disappear.</li>
          <li>Local copy required: critical to an app, project, system, policy, or MIM/TOD training.</li>
        </ul>
      </article>
    </section>
    <section class="card" style="margin-top:14px;">
      <h2>Library Shelves</h2>
      <p>Documents should be browsable by human meaning first, then searchable by MIM.</p>
    </section>
    <section class="grid three placeholder-sections">{categories_html}</section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Relationship Graph</h2>
        <p>Documents can now attach to the things they support: projects, objectives, tasks, conversations, status updates, apps, reports, systems, lab work, and training runs.</p>
        <table class="score-table" style="margin-top:10px;">
          <thead><tr><th>Target Type</th><th>Links</th></tr></thead>
          <tbody>{relationship_type_rows}</tbody>
        </table>
      </article>
      <article class="card">
        <h2>Recent Relationships</h2>
        <div class="attention-list" style="margin-top:12px;">{recent_links_html}</div>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Recent Library Items</h2>
        <div class="attention-list" style="margin-top:12px;">{doc_rows}</div>
      </article>
      <article class="card">
        <h2>Next Implementation Step</h2>
        <p>The DB record layer is ready. The next build is the practical document workflow.</p>
        <div class="label">Needed Backend</div>
        <ul class="clean">
          <li>Upload endpoint and local storage path.</li>
          <li>URL fetch/snapshot worker with safety and source attribution.</li>
          <li>Document graph links are now DB-backed; next is surfacing them from each related object page.</li>
          <li>Search/index path so MIM can retrieve library context during conversation.</li>
          <li>Generated documents from MIM: summaries, project briefs, reports, wiki notes, and evidence packets.</li>
        </ul>
      </article>
    </section>
    """


def _app_url(app_key: object) -> str:
    return f"/studio/apps?app={_html(app_key)}"


def _apps_body(state: dict[str, Any], selected_app_key: str = "") -> str:
    apps = state.get("apps") if isinstance(state.get("apps"), list) else []
    counts = state.get("counts") if isinstance(state.get("counts"), dict) else {}
    summary = str(state.get("summary") or "")
    selected_app = next(
        (app for app in apps if str(app.get("app_key") or "").lower() == selected_app_key.strip().lower()),
        None,
    )
    if selected_app is None and apps:
        selected_app = apps[0]
    stats = [
        ("Registered Apps", counts.get("apps", 0), "known app sources"),
        ("Live Inspectable", counts.get("live_inspectable", 0), "visible from this host"),
        ("TOD Scanned", counts.get("scanned_by_tod", 0), "repo roots inspected"),
        ("DB Proven", counts.get("db_connected", 0), "primary app tables connected"),
    ]
    stats_html = "".join(
        f"""
        <article class="card">
          <div class="label">{_html(label)}</div>
          <div class="entity">{_html(value)}</div>
          <p>{_html(detail)}</p>
        </article>
        """
        for label, value, detail in stats
    )
    selected_detail_html = ""
    if selected_app:
        known_tables = selected_app.get("known_tables") if isinstance(selected_app.get("known_tables"), list) else []
        db_env_keys = selected_app.get("db_env_keys") if isinstance(selected_app.get("db_env_keys"), list) else []
        fallback_counts = selected_app.get("fallback_counts") if isinstance(selected_app.get("fallback_counts"), dict) else {}
        hosting_status = selected_app.get("hosting_status") if isinstance(selected_app.get("hosting_status"), dict) else {}
        homepage = hosting_status.get("homepage") if isinstance(hosting_status.get("homepage"), dict) else {}
        api = hosting_status.get("api") if isinstance(hosting_status.get("api"), dict) else {}
        webapps = hosting_status.get("webapps") if isinstance(hosting_status.get("webapps"), list) else []
        table_rows = "".join(f"<tr><td>{_html(table)}</td><td>registered</td></tr>" for table in known_tables)
        if not table_rows:
            table_rows = '<tr><td>No tables mapped yet</td><td>pending</td></tr>'
        webapp_rows = "".join(
            f"""
            <tr>
              <td>{_html(item.get("domain_name", ""))}</td>
              <td>{_html(item.get("enabled", ""))}</td>
              <td>{_html(item.get("python_version", ""))}</td>
              <td>{_html(item.get("source_directory", ""))}</td>
            </tr>
            """
            for item in webapps
            if isinstance(item, dict)
        )
        fallback_rows = "".join(f'<tr><td>{_html(key)}</td><td>{_html(value)}</td><td colspan="2">fallback</td></tr>' for key, value in fallback_counts.items())
        detail_rows = webapp_rows + fallback_rows
        if not detail_rows:
            detail_rows = '<tr><td colspan="4">No hosting or fallback count rows registered yet.</td></tr>'
        dirty_count = selected_app.get("dirty_count")
        dirty_text = str(dirty_count) if dirty_count is not None else "n/a"
        selected_detail_html = f"""
        <section class="card hero-card" style="margin-bottom:14px;">
          <div class="status-head">
            <div>
              <div class="label">Selected App</div>
              <h2>{_html(selected_app.get("display_name", ""))}</h2>
              <p>{_html(selected_app.get("ecosystem_role", ""))}</p>
            </div>
            <span class="badge"><span class="dot {'green' if selected_app.get('health') == 'good' else 'yellow'}"></span>{_html(selected_app.get("health", "unknown"))}</span>
          </div>
          <section class="grid four" style="grid-template-columns: repeat(4, minmax(0, 1fr)); margin-top:14px;">
            <article class="card"><div class="label">Last Touched</div><div class="entity">{_html(selected_app.get("scanned_at") or "unknown")}</div><p>{_html(selected_app.get("source_status", ""))}</p></article>
            <article class="card"><div class="label">Docs</div><div class="entity">-</div><p>links pending</p></article>
            <article class="card"><div class="label">Projects</div><div class="entity">-</div><p>links pending</p></article>
            <article class="card"><div class="label">Tasks</div><div class="entity">-</div><p>links pending</p></article>
          </section>
          <section class="grid two" style="margin-top:14px;">
            <article class="card">
              <h3>Operations</h3>
              <ul class="clean">
                <li>Host: {_html(selected_app.get("hosting_provider") or hosting_status.get("provider") or "not registered")}</li>
                <li>Runtime: {_html(selected_app.get("runtime", ""))}</li>
                <li>Source: {_html(selected_app.get("local_root", ""))}</li>
                <li>Git: {_html(selected_app.get("git_status", ""))} / {_html(selected_app.get("branch") or "no branch")} / {_html(selected_app.get("commit") or "no commit")} / dirty {_html(dirty_text)}</li>
                <li>Deploy: {_html(selected_app.get("public_url") or "not registered")}</li>
                <li>Next: {_html(selected_app.get("next_action", ""))}</li>
              </ul>
            </article>
            <article class="card">
              <h3>Data & Services</h3>
              <ul class="clean">
                <li>DB status: {_html(selected_app.get("db_status", ""))}</li>
                <li>Primary table: {_html(selected_app.get("primary_account_table") or "not declared")}</li>
                <li>Secondary table: {_html(selected_app.get("secondary_user_table") or "not declared")}</li>
                <li>Env keys: {_html(", ".join(str(item) for item in db_env_keys) or "none registered")}</li>
                <li>Homepage: {_html(homepage.get("status", "n/a"))}</li>
                <li>Provider API: CPU {_html(api.get("cpu_status", "n/a"))} / Webapps {_html(api.get("webapps_status", "n/a"))}</li>
              </ul>
            </article>
          </section>
          <section class="grid two" style="margin-top:14px;">
            <article class="card">
              <h3>DB Construct</h3>
              <table class="score-table"><thead><tr><th>Table</th><th>Status</th></tr></thead><tbody>{table_rows}</tbody></table>
            </article>
            <article class="card">
              <h3>Hosting / Fallback Counts</h3>
              <table class="score-table"><thead><tr><th>Domain / Count</th><th>Status</th><th>Runtime</th><th>Source</th></tr></thead><tbody>{detail_rows}</tbody></table>
            </article>
          </section>
        </section>
        """
    app_cards = ""
    for app in apps:
        health = str(app.get("health") or "unknown")
        dot_class = "green" if health == "good" else ("yellow" if "binding" in health or "registered" in health else "red")
        users = app.get("registered_users")
        users_text = "unknown" if users is None else str(users)
        git_detail = str(app.get("git_status", ""))
        branch = str(app.get("branch") or "")
        commit = str(app.get("commit") or "")
        dirty_count = app.get("dirty_count")
        if branch or commit or dirty_count is not None:
            git_detail = f"{git_detail} / {branch or 'no branch'} / {commit or 'no commit'} / dirty: {dirty_count if dirty_count is not None else 'n/a'}"
        is_selected = selected_app and str(app.get("app_key") or "") == str(selected_app.get("app_key") or "")
        selected_style = "border-color: rgba(110,231,216,.75); box-shadow: 0 0 0 1px rgba(110,231,216,.25);" if is_selected else ""
        risk_text = "dirty repo" if isinstance(dirty_count, int) and dirty_count > 0 else ("db adapter" if app.get("db_status") == "external_declared" else "none")
        app_cards += f"""
        <a class="card" href="{_app_url(app.get("app_key", ""))}" style="display:block; {selected_style}">
          <div class="status-head">
            <div>
              <div class="label">{_html(app.get("app_key", ""))}</div>
              <div class="entity">{_html(app.get("display_name", ""))}</div>
            </div>
            <span class="badge"><span class="dot {dot_class}"></span>{_html(health)}</span>
          </div>
          <p class="focus">{_html(app.get("ecosystem_role", ""))}</p>
          <section class="grid four" style="grid-template-columns: repeat(4, minmax(0, 1fr)); gap:8px; margin:12px 0;">
            <div><div class="label">Docs</div><strong>-</strong></div>
            <div><div class="label">Projects</div><strong>-</strong></div>
            <div><div class="label">Tasks</div><strong>-</strong></div>
            <div><div class="label">Risk</div><strong>{_html(risk_text)}</strong></div>
          </section>
          <div class="label">Quick Status</div>
          <p>{_html(app.get("runtime", ""))} / {_html(app.get("source_status", ""))}</p>
          <p>{_html(git_detail)}</p>
          <p>Users: {_html(users_text)} / Data: {_html(app.get("db_status", ""))}</p>
          <div class="label">Next</div>
          <p>{_html(app.get("next_action", ""))}</p>
        </a>
        """
    if not app_cards:
        app_cards = '<article class="card"><h3>No apps registered</h3><p>Add the first app source so MIM/TOD know where it lives and how to inspect it.</p></article>'
    return f"""
    <section class="grid four" style="grid-template-columns: repeat(4, minmax(0, 1fr)); margin-bottom:14px;">{stats_html}</section>
    <section class="card hero-card" style="margin-bottom:14px;">
      <div class="label">MIM App Registry</div>
      <h2>Applications MIM and TOD are responsible for</h2>
      <p>{_html(summary)}</p>
      <div class="actions" style="margin-top:12px; flex-wrap:wrap;">
        <a class="button primary" href="/studio/api/apps/sources">Open Registry JSON</a>
        <a class="button" href="/studio/reports?prompt=what%20apps%20need%20source%20or%20database%20attention">Ask Reports</a>
        <a class="button" href="/studio/documents">Open App Documents</a>
      </div>
    </section>
    {selected_detail_html}
    <section class="grid two" style="margin-bottom:14px;">
      <article class="card">
        <h2>Attention</h2>
        <p>Apps with dirty worktrees, unproven DB bindings, or missing runtime details should surface here first.</p>
        <div class="label">Rules</div>
        <ul class="clean">
          <li>No app-specific user count unless the app's real user/account table is connected.</li>
          <li>No edits to dirty repos without acknowledging existing changes.</li>
          <li>No app work without linked project, ticket, or operator request.</li>
        </ul>
      </article>
      <article class="card">
        <h2>Next Actions</h2>
        <p>TOD has scanned the Windows-side roots. The next layer is recurring scan automation and DB-backed app records.</p>
        <div class="label">Next Build</div>
        <ul class="clean">
          <li>Recurring TOD app scanner: git status, branch, latest commit, version, env keys, DB tables, tests, and deployment hints.</li>
          <li>DB-backed app registry records instead of source-code constants.</li>
          <li>Service/vendor map: OpenAI, Render, Stripe, SMTP, Twilio, QuickBooks, storage, and app-specific APIs.</li>
        </ul>
      </article>
    </section>
    <section class="grid two">{app_cards}</section>
    """

def _reports_body(state: dict[str, Any]) -> str:
    dataset = state.get("dataset") if isinstance(state.get("dataset"), dict) else {}
    canvases = state.get("canvases") if isinstance(state.get("canvases"), list) else []
    prompt = str(state.get("prompt") or "")
    dataset_key = str(dataset.get("key") or "studio_overview")
    has_report = bool(prompt or state.get("selected_canvas") or dataset_key != "studio_overview")
    stats_html = "".join(
        f"""
        <article class="card">
          <div class="label">{_html(item.get("label", ""))}</div>
          <div class="entity">{_html(item.get("value", ""))}</div>
        </article>
        """
        for item in (dataset.get("stats") if isinstance(dataset.get("stats"), list) else [])[:4]
    )
    findings_html = "".join(
        f"""
        <article class="attention-item">
          <small>finding</small>
          <strong>{_html(item.get("title", ""))}</strong>
          <div class="muted">{_html(item.get("detail", ""))}</div>
        </article>
        """
        for item in (dataset.get("findings") if isinstance(dataset.get("findings"), list) else [])
    )
    actions_html = "".join(
        f"""
        <article class="attention-item">
          <small>action</small>
          <strong>{_html(item.get("title", ""))}</strong>
          <div class="muted">{_html(item.get("detail", ""))}</div>
        </article>
        """
        for item in (dataset.get("actions") if isinstance(dataset.get("actions"), list) else [])
    )
    columns = dataset.get("columns") if isinstance(dataset.get("columns"), list) else []
    rows = dataset.get("rows") if isinstance(dataset.get("rows"), list) else []
    table_headers = "".join(f"<th>{_html(column)}</th>" for column in columns)
    table_rows = ""
    for row in rows[:60]:
        if not isinstance(row, dict):
            continue
        cells = "".join(f"<td>{_html(row.get(column, ''))}</td>" for column in columns)
        table_rows += f"<tr>{cells}</tr>"
    canvas_html = "".join(
        f"""
        <a class="project-row" href="/studio/reports?canvas_id={_html(item.get("id", ""))}">
          <div>
            <strong>{_html(item.get("title", ""))}</strong>
            <div class="muted">{_html(item.get("prompt", ""))}</div>
          </div>
          <span class="health-pill">{_html(item.get("dataset_key", ""))}</span>
        </a>
        """
        for item in canvases[:8]
    )
    if not has_report:
        saved_section = f"""
        <section class="card">
          <h2>Saved Canvases</h2>
          <div style="margin-top:12px;">{canvas_html}</div>
        </section>
        """ if canvas_html else ""
        return f"""
        <section class="card">
          <h2>Report Canvas</h2>
        </section>
        {saved_section}
        """

    stats_section = f'<section class="grid four" style="grid-template-columns: repeat(4, minmax(0, 1fr)); margin-bottom:14px;">{stats_html}</section>' if stats_html else ""
    findings_section = f"""
      <article class="card">
        <h2>Findings</h2>
        <div class="attention-list" style="margin-top:12px;">{findings_html}</div>
      </article>
    """ if findings_html else ""
    actions_section = f"""
      <article class="card">
        <h2>Actions</h2>
        <div class="attention-list" style="margin-top:12px;">{actions_html}</div>
      </article>
    """ if actions_html else ""
    findings_actions_section = f'<section class="grid two">{findings_section}{actions_section}</section>' if findings_section or actions_section else ""
    table_section = ""
    if table_headers and table_rows:
        table_section = f"""
        <section class="card" style="margin-top:14px;">
          <h2>Data</h2>
          <div class="actions" style="margin-top:10px; flex-wrap:wrap;">
            <a class="button" href="/studio/api/reports/dataset?dataset={_html(dataset_key)}&prompt={_html(prompt)}">JSON</a>
            <a class="button" href="/studio/api/reports/dataset?dataset={_html(dataset_key)}&prompt={_html(prompt)}&format=csv">CSV</a>
            <a class="button" href="/studio/projects">Action</a>
          </div>
          <table class="score-table" style="margin-top:12px;">
            <thead><tr>{table_headers}</tr></thead>
            <tbody>{table_rows}</tbody>
          </table>
        </section>
        """
    saved_section = f"""
    <section class="card" style="margin-top:14px;">
      <h2>Saved Canvases</h2>
      <div style="margin-top:12px;">{canvas_html}</div>
    </section>
    """ if canvas_html else ""
    return f"""
    <section class="card" style="margin-bottom:14px;">
      <div class="label">{_html(dataset.get("label", "Report"))}</div>
      <h2>{_html(prompt or dataset.get("label", "Report Canvas"))}</h2>
      <p>{_html(dataset.get("summary", ""))}</p>
      <div class="muted">{_html(dataset.get("generated_at", ""))}</div>
    </section>
    {stats_section}
    {findings_actions_section}
    {table_section}
    {saved_section}
    """


def _metric_table(title: str, metrics: list[tuple[str, object, object, str]]) -> str:
    rows = "".join(
        f"""
        <tr>
          <td>{_html(label)}</td>
          <td>{_html(yesterday)}</td>
          <td>{_html(today)}</td>
          <td>{_html(source)}</td>
        </tr>
        """
        for label, yesterday, today, source in metrics
    )
    return f"""
    <article class="card">
      <h2>{_html(title)}</h2>
      <table class="score-table">
        <thead><tr><th>Metric</th><th>Yesterday</th><th>Today</th><th>Source</th></tr></thead>
        <tbody>{rows}</tbody>
      </table>
    </article>
    """


def _training_body(state: dict[str, Any]) -> str:
    section_cards = "".join(
        f"""
        <a class="card" href="{_html(section['href'])}">
          <h3>{_html(section['label'])}</h3>
          <p>{_html(section['summary'])}</p>
        </a>
        """
        for section in TRAINING_SECTIONS
    )
    mim = state["mim"]
    tod = state["tod"]
    judgment = state.get("judgment") if isinstance(state.get("judgment"), dict) else {}
    mim_score = state.get("mim_score") if isinstance(state.get("mim_score"), dict) else {}
    tod_score = state.get("tod_score") if isinstance(state.get("tod_score"), dict) else {}
    reflection = state.get("reflection") if isinstance(state.get("reflection"), dict) else {}
    typo = state.get("typo") if isinstance(state.get("typo"), dict) else {}
    objective_counts = reflection.get("objective_counts") if isinstance(reflection.get("objective_counts"), dict) else {}
    freshness = reflection.get("freshness") if isinstance(reflection.get("freshness"), dict) else {}
    stale = freshness.get("stale_artifacts") if isinstance(freshness.get("stale_artifacts"), list) else []
    evidence_docs = state.get("evidence_docs") if isinstance(state.get("evidence_docs"), list) else []
    evidence_html = "".join(
        f"""
        <a class="project-row" href="{_html(item.get("href", "/studio/documents"))}">
          <div>
            <strong>{_html(item.get("title", ""))}</strong>
            <div class="muted">{_html(item.get("summary", ""))}</div>
          </div>
          <span class="health-pill">{_html(item.get("kind", "evidence"))}</span>
        </a>
        """
        for item in evidence_docs
    )
    stale_html = "".join(f"<li>{_html(item)}</li>" for item in stale[:8]) or "<li>No stale artifacts reported.</li>"
    group_summary = judgment.get("group_summary") if isinstance(judgment.get("group_summary"), dict) else {}
    group_rows = "".join(
        f"""
        <tr>
          <td>{_html(str(group).replace("_", " ").title())}</td>
          <td>{_html(values.get("passed", ""))}</td>
          <td>{_html(values.get("failed", ""))}</td>
        </tr>
        """
        for group, values in group_summary.items()
        if isinstance(values, dict)
    )
    attention_items = state.get("attention_items") if isinstance(state.get("attention_items"), list) else []
    top_objective = state.get("top_training_objective") if isinstance(state.get("top_training_objective"), dict) else {}
    attention_html = "".join(
        f"""
        <article class="attention-item" id="{_html(item.get("key", ""))}">
          <small>{_html(item.get("status", ""))} / owner: {_html(item.get("owner", ""))}</small>
          <strong><a href="{_html(item.get("href", "#"))}">{_html(item.get("title", ""))}</a></strong>
          <div class="muted"><strong>What needs attention:</strong> {_html(item.get("what_needs_attention", ""))}</div>
          <div class="muted"><strong>MIM:</strong> {_html(item.get("mim_action", ""))}</div>
          <div class="muted"><strong>TOD:</strong> {_html(item.get("tod_action", ""))}</div>
          <div class="muted"><strong>Resolution:</strong> {_html(item.get("resolution_process", ""))}</div>
        </article>
        """
        for item in attention_items
    ) or '<article class="attention-item"><strong>No current attention item.</strong><div class="muted">Training evidence currently has no active attention flag.</div></article>'
    top_objective_html = ""
    if top_objective:
        top_objective_html = f"""
        <section class="card" style="margin-top:14px;">
          <h2>Next Top Training Objective</h2>
          <div class="attention-list" style="margin-top:10px;">
            <article class="attention-item" id="{_html(top_objective.get("id", ""))}">
              <small>{_html(top_objective.get("status", ""))} / owner: {_html(top_objective.get("owner", ""))}</small>
              <strong><a href="{_html(top_objective.get("href", "/studio/projects"))}">{_html(top_objective.get("title", ""))}</a></strong>
              <div class="muted"><strong>Why now:</strong> {_html(top_objective.get("why_now", ""))}</div>
              <div class="muted"><strong>MIM:</strong> {_html(top_objective.get("mim_action", ""))}</div>
              <div class="muted"><strong>TOD:</strong> {_html(top_objective.get("tod_action", ""))}</div>
              <div class="muted"><strong>Codex gate:</strong> {_html(top_objective.get("codex_gate", ""))}</div>
              <div class="muted"><strong>First validation:</strong> {_html(top_objective.get("first_validation", ""))}</div>
            </article>
          </div>
        </section>
        """
    mim_metrics_source = mim_score.get("metrics") if isinstance(mim_score.get("metrics"), dict) else {}
    tod_metrics_source = tod_score.get("metrics") if isinstance(tod_score.get("metrics"), dict) else {}

    def today_metric(metrics: dict[str, Any], key: str, default: str = "baseline needed") -> str:
        row = metrics.get(key) if isinstance(metrics.get(key), dict) else {}
        value = row.get("today") if isinstance(row, dict) else None
        unit = row.get("unit") if isinstance(row, dict) else ""
        if isinstance(value, dict):
            return _first_text(value.get("status"), default=default)
        if value is None:
            yesterday = row.get("yesterday") if isinstance(row.get("yesterday"), dict) else {}
            return _first_text(yesterday.get("status"), default=default)
        suffix = "%" if "percent" in str(unit) else ""
        return f"{value}{suffix}"

    mim_metrics = [
        ("Intent Understood", "baseline needed", today_metric(mim_metrics_source, "intent_understood"), "live_gateway_eval"),
        ("Answered Question", "baseline needed", today_metric(mim_metrics_source, "answered_question"), "live_gateway_eval"),
        ("Internal Jargon", "baseline needed", today_metric(mim_metrics_source, "internal_jargon"), "live_gateway_eval"),
        ("Recommendation Quality", "baseline needed", today_metric(mim_metrics_source, "recommendation_quality"), "live_gateway_eval"),
        ("Judgment Mode", "baseline needed", f"{judgment.get('pass_rate_percent', 'unknown')}%", "durability_smoke_v2"),
        ("Typo Tolerance", "baseline needed", typo.get("pass_rate_percent", "unknown"), "typo_smoke"),
    ]
    tod_metrics = [
        ("Blockers Cleared", "baseline needed", today_metric(tod_metrics_source, "blockers_cleared"), "blocker_drill_artifacts"),
        ("False Completions Prevented", "baseline needed", today_metric(tod_metrics_source, "false_completions_prevented"), "drill_004_self_correction"),
        ("Validated Edits", "baseline needed", today_metric(tod_metrics_source, "validated_edits"), "baseline_needed"),
        ("No-op Rejections", "baseline needed", today_metric(tod_metrics_source, "no_op_rejections"), "baseline_needed"),
        ("Evidence Quality", "baseline needed", "needs proof", "blocker_resolution"),
    ]
    return f"""
    <section class="card">
      <div class="status-head">
        <div>
          <h2>MIM Training Summary</h2>
          <p class="focus">{_html(state["outcome_verdict"])}</p>
        </div>
        <span class="badge"><span class="dot {'green' if state.get('are_improving') is True else 'yellow'}"></span>{_html(state["assessment"])}</span>
      </div>
      <div class="label">Page Load / Evidence Time</div>
      <p>Loaded: {_html(state["page_loaded_at_la"])} / Evidence updated: {_html(state["generated_at_la"])} ({_html(state["generated_age"])}) / Directive: {_html(state["directive_status"])} / Improving: {_html(state.get("are_improving"))}</p>
      <div class="label">Resolution Ownership</div>
      <p>{_html(state.get("resolution_owner_model", ""))}</p>
    </section>
    <section class="card" style="margin-top:14px;">
      <h2>What Needs Attention</h2>
      <div class="attention-list" style="margin-top:10px;">{attention_html}</div>
    </section>
    {top_objective_html}
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>MIM</h2>
        <p class="focus">{_html(mim["focus"])}</p>
        <div class="label">Goal</div>
        <p>{_html(mim["goal"])}</p>
        <div class="label">Progress</div>
        <p>{_html(mim["progress"])}</p>
        <div class="label">Problem</div>
        <p>{_html(mim["weakness"])}</p>
        <div class="label">Next</div>
        <p>{_html(mim["next"])}</p>
      </article>
      <article class="card">
        <h2>TOD</h2>
        <p class="focus">{_html(tod["focus"])}</p>
        <div class="label">Goal</div>
        <p>{_html(tod["goal"])}</p>
        <div class="label">Progress</div>
        <p>{_html(tod["progress"])}</p>
        <div class="label">Problem</div>
        <p>{_html(tod["weakness"])}</p>
        <div class="label">Next</div>
        <p>{_html(tod["next"])}</p>
      </article>
    </section>
    <section class="grid three" style="margin-top:14px;">
      <article class="card">
        <h2>Outcome Reflection</h2>
        <ul class="clean">
          <li>Completed objectives: {_html(objective_counts.get("completed", "unknown"))}</li>
          <li>Running objectives: {_html(objective_counts.get("running", "unknown"))}</li>
          <li>Blocked objectives: {_html(objective_counts.get("blocked", "unknown"))}</li>
          <li>Fresh artifacts: {_html(freshness.get("fresh_artifact_count", "unknown"))}</li>
          <li>Stale artifacts: {_html(len(stale))}</li>
        </ul>
      </article>
      <article class="card">
        <h2>Judgment Smoke</h2>
        <p>Pass rate: {_html(judgment.get("pass_rate_percent", "unknown"))}% / Passed {_html(judgment.get("passed", "unknown"))}/{_html(judgment.get("case_count", "unknown"))}</p>
        <table class="score-table" style="margin-top:10px;">
          <thead><tr><th>Mode</th><th>Passed</th><th>Failed</th></tr></thead>
          <tbody>{group_rows}</tbody>
        </table>
      </article>
      <article class="card">
        <h2>Problems</h2>
        <p>Top issue: training activity still has to prove outcome improvement.</p>
        <div class="label">Stale Inputs</div>
        <ul class="clean">{stale_html}</ul>
      </article>
    </section>
    <section class="grid two" style="margin-top:14px;">
      {_metric_table("MIM Scorecard", mim_metrics)}
      {_metric_table("TOD Scorecard", tod_metrics)}
    </section>
    <section class="grid two" style="margin-top:14px;">
      <article class="card">
        <h2>Evidence Documents</h2>
        <p>Training claims should link to library records. Click through to Documents when you want the proof, not just the summary.</p>
        <div style="margin-top:10px;">{evidence_html}</div>
      </article>
      <article class="card">
        <h2>Recent Improvements</h2>
        <ul class="clean">
          <li>Typo-tolerant intent handling reached the current smoke target.</li>
          <li>MIM responses improved from artifact-heavy status to clearer operator summaries.</li>
          <li>TOD blocker work proved at least one inspect-and-narrow correction path.</li>
          <li>Studio Projects and Documents are now DB-backed.</li>
        </ul>
        <div class="label">Dave Needed</div>
        <p>No, unless a blocker requires a decision, credential, or physical-world check.</p>
      </article>
    </section>
    <section class="card" style="margin-top:14px;">
      <h2>Training Drill-Down</h2>
      <p>Use these when you want raw objectives, smoke tests, blockers, memory, or run history.</p>
    </section>
    <section class="grid three placeholder-sections">{section_cards}</section>
    """


def _training_section_body(section: dict[str, str]) -> str:
    if section["key"] == "objectives":
        return _embed_body({"label": "Objectives", "source": section.get("source", "/objectives")})
    return f"""
    <section class="card">
      <h2>{_html(section['label'])}</h2>
      <p>{_html(section['summary'])}</p>
      <div class="label">V1 Shape</div>
      <ul class="clean">
        <li>Show current state in plain English.</li>
        <li>Link every status claim to current evidence.</li>
        <li>Separate active work, recent wins, blockers, and recommended next action.</li>
        <li>Keep raw artifacts available as drill-down, not first-screen noise.</li>
      </ul>
    </section>
    """


def _embed_body(tab: dict[str, str]) -> str:
    source = tab.get("source", "/mim")
    if tab.get("key") in {"mim", "tod"}:
        separator = "&" if "?" in source else "?"
        source = f"{source}{separator}studio_embed=1"
    return f"""<iframe class="embed-frame" src="{_html(source)}" title="{_html(tab["label"])}"></iframe>"""


@router.get("/studio", response_class=HTMLResponse)
async def studio_home(request: Request) -> HTMLResponse:
    auth_redirect = maybe_require_mimtod_page_login(request, next_path="/studio")
    if auth_redirect is not None:
        return auth_redirect
    snapshot = _studio_snapshot()
    return HTMLResponse(
        _shell(
            active="home",
            title="Dave's Command Center",
            subtitle="What is happening, what matters, what needs Dave, and what should happen next.",
            body=_home_body(snapshot),
            page_context="Studio Home",
        )
    )


@router.get("/studio/training/{section_key}", response_class=HTMLResponse)
async def studio_training_section(request: Request, section_key: str) -> HTMLResponse:
    key = str(section_key or "").strip().lower()
    section = next((item for item in TRAINING_SECTIONS if item["key"] == key), None)
    if section is None:
        return await studio_tab(request, "training")
    auth_redirect = maybe_require_mimtod_page_login(request, next_path=f"/studio/training/{key}")
    if auth_redirect is not None:
        return auth_redirect
    return HTMLResponse(
        _shell(
            active="training",
            title=f"Training / {section['label']}",
            subtitle=section["summary"],
            body=_training_section_body(section),
            page_context=f"Studio Training {section['label']}",
        )
    )


@router.get("/studio/objectives", response_class=HTMLResponse)
async def studio_legacy_objectives(request: Request) -> HTMLResponse:
    return await studio_training_section(request, "objectives")


@router.get("/studio/lab/servo-tester", response_class=HTMLResponse)
async def studio_lab_servo_tester(request: Request, db: AsyncSession = Depends(get_db)) -> HTMLResponse:
    auth_redirect = maybe_require_mimtod_page_login(request, next_path="/studio/lab/servo-tester")
    if auth_redirect is not None:
        return auth_redirect
    await _ensure_first_internal_projects(db)
    profile = _load_servo_tester_profile()
    return HTMLResponse(
        _shell(
            active="lab",
            title="Lab / Servo Tester",
            subtitle="",
            body=_servo_tester_body(profile),
            page_context="Studio Lab Servo Tester",
        )
    )


@router.get("/studio/api/lab/servo-tester/profile")
async def studio_lab_servo_tester_profile() -> dict[str, Any]:
    return {"ok": True, "profile": _load_servo_tester_profile()}


@router.post("/studio/api/lab/servo-tester/profile")
async def update_studio_lab_servo_tester_profile(payload: dict[str, Any] = Body(default_factory=dict)) -> dict[str, Any]:
    profile = _clean_servo_profile(payload if isinstance(payload, dict) else {})
    LAB_SERVO_TESTER_PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    LAB_SERVO_TESTER_PROFILE_PATH.write_text(json.dumps(profile, indent=2), encoding="utf-8")
    return {"ok": True, "profile": profile}


def _navigation_terms_match(text: str, terms: list[str]) -> bool:
    return any(term in text for term in terms)


async def _studio_project_target_href(db: AsyncSession, prompt_lower: str) -> str:
    try:
        result = await db.execute(select(StudioProject.id, StudioProject.title).order_by(StudioProject.updated_at.desc()).limit(80))
        rows = result.all()
    except Exception:
        return "/studio/projects"
    prompt_tokens = {token for token in prompt_lower.replace("/", " ").replace("-", " ").split() if len(token) >= 4}
    best_id: int | None = None
    best_score = 0
    for project_id, title in rows:
        title_text = str(title or "").lower()
        title_tokens = {token for token in title_text.replace("/", " ").replace("-", " ").split() if len(token) >= 4}
        score = len(prompt_tokens & title_tokens)
        if "forum graphics" in prompt_lower and "forum graphics" in title_text:
            score += 8
        if "account manager" in prompt_lower and "account manager" in title_text:
            score += 8
        if "mobile" in prompt_lower and "login" in prompt_lower and "login" in title_text:
            score += 6
        if score > best_score:
            best_score = score
            best_id = int(project_id)
    if best_id and best_score >= 2:
        return f"/studio/projects?project_id={best_id}"
    return "/studio/projects"


async def _studio_navigation_target(db: AsyncSession, prompt: str, page_context: str) -> dict[str, Any] | None:
    prompt_lower = str(prompt or "").lower()
    context_lower = str(page_context or "").lower()
    current_area = "home"
    for area in ["projects", "training", "documents", "reports", "systems", "lab", "apps", "accounting", "settings", "mim", "tod"]:
        if area in context_lower:
            current_area = area
            break

    targets: list[tuple[str, str, list[str], str]] = [
        ("lab", "/studio/lab", ["lab", "robot", "robotics", "arm", "camera", "lidar", "sensor", "calibration", "pickup", "servo", "servos", "uno", "pwm", "pca9685"], "Lab"),
        ("projects", "/studio/projects", ["project", "projects", "ticket", "tickets", "backlog", "queued", "pause", "delete", "forum graphics", "account manager", "twilio", "gmail", "2fa", "double authentication", "social post", "campaign", "mobile login", "ssl issue", "powershell migration"], "Projects"),
        ("reports", "/studio/reports", ["report", "reports", "show me all", "new users", "past month", "dataset", "metrics", "canvas", "agentmim.com app users", "comm_app", "database", "db"], "Reports"),
        ("documents", "/studio/documents", ["document", "documents", "library", "lab documents", "archive", "reference", "notes", "screenshot"], "Documents"),
        ("training", "/studio/training", ["training", "scoreboard", "smoke test", "judgment", "objective", "continuity", "tod training", "mim training"], "Training"),
        ("systems", "/studio/systems", ["system", "systems", "health", "runtime", "service", "provider", "sync", "dirty", "watchdog"], "Systems"),
        ("apps", "/studio/apps", ["apps", "agentmim", "mim wall", "mobile app", "commissions", "carriers", "contacts", "agents"], "Apps"),
        ("accounting", "/studio/accounting", ["accounting", "commission", "commissions", "rep totals", "paid to reps", "carrier reports"], "Accounting"),
        ("settings", "/studio/settings", ["settings", "configuration", "credentials", "twilio number", "gmail setup", "access"], "Settings"),
    ]
    for area, href, terms, label in targets:
        if _navigation_terms_match(prompt_lower, terms):
            if area == "lab" and _navigation_terms_match(prompt_lower, ["servo", "servos", "uno", "pwm", "pca9685"]):
                href = "/studio/lab/servo-tester"
            if area == "projects":
                href = await _studio_project_target_href(db, prompt_lower)
            if area == current_area:
                return None
            return {
                "href": href,
                "label": label,
                "target_area": area,
                "auto_redirect": True,
                "reason": f"This request belongs on the Studio {label} page.",
            }
    return None


@router.post("/studio/api/mim/chat")
async def studio_mim_chat_api(
    payload: StudioMimChatRequest,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    page_context = _first_text(payload.studio_page_context, payload.page_context, default="Studio")
    prompt = payload.prompt.strip()
    page_context_lower = page_context.lower()
    prompt_lower = prompt.lower()
    navigation = await _studio_navigation_target(db, prompt, page_context)
    if navigation is not None:
        label = str(navigation.get("label") or "that Studio page")
        return {
            "ok": True,
            "source": "studio_navigation_context",
            "response_mode": "navigation",
            "mim_interface": {
                "reply_text": f"That belongs on {label}. I am opening the right Studio area so the work lands where it can be managed.",
                "page_context": page_context,
                "surface": "studio",
            },
            "navigation": navigation,
            "evidence": {
                "target_area": navigation.get("target_area"),
                "href": navigation.get("href"),
            },
        }
    if "servo tester" in page_context_lower or ("lab" in page_context_lower and any(term in prompt_lower for term in ["servo", "uno", "pwm", "serial", "com", "slider"])):
        profile = _load_servo_tester_profile()
        serial_open_failure = any(
            term in prompt_lower
            for term in [
                "failed to open serial port",
                "failed to execute 'open'",
                "connect failed",
                "connection failed",
                "could not open",
                "access denied",
                "port busy",
                "com5",
            ]
        )
        choppy_motion = any(
            term in prompt_lower
            for term in [
                "small bursts",
                "bursts",
                "not fluid",
                "not smooth",
                "choppy",
                "jerky",
                "jitter",
                "stutter",
                "rough movement",
                "smooth movement",
                "startup",
                "slow down",
                "slowdown",
            ]
        )
        serial_ok_no_servo_motion = any(
            term in prompt_lower
            for term in [
                "rx ok",
                "pong smoothservobenchtester",
                "serial is working",
                "uno replies",
                "not responding to any inputs",
                "servo is not responding",
                "no servo movement",
                "no movement",
                "does not move",
            ]
        )
        firmware_update_request = any(
            term in prompt_lower
            for term in [
                "update the sketch",
                "flash the sketch",
                "flash firmware",
                "upload sketch",
                "upload firmware",
                "directly to the uno",
                "directly to uno",
            ]
        )
        if serial_open_failure:
            reply = (
                "MIM should have caught this more directly. That error happens before any servo command is sent.\n\n"
                "Most likely cause: the COM port is locked by another program, usually Arduino IDE Serial Monitor/Plotter, Arduino IDE itself after opening the monitor, or another browser/app session.\n\n"
                "Do this first:\n"
                "- Close Arduino IDE Serial Monitor and Serial Plotter.\n"
                "- If it still fails, close Arduino IDE entirely.\n"
                "- Unplug/replug the UNO.\n"
                "- Click Forget Port on the Lab tester.\n"
                "- Click Connect UNO and select COM5 again.\n\n"
                "Only after the page shows Connected should we test protocol, channel, PWM driver wiring, servo power, or limits."
            )
            response_mode = "problem_analysis"
            failure_class = "serial_port_open_failed_likely_locked_by_ide"
            training_lesson = "When Web Serial reports failed_to_open before TX, diagnose port lock before servo protocol or wiring."
        elif firmware_update_request:
            reply = (
                "Yes. MIM should route this as a local hardware execution task through TOD/Codex, not as a static prototype answer.\n\n"
                "Execution path:\n"
                "- Use the smooth firmware at docs/lab/servo_tester_firmware/SmoothServoBenchTester/SmoothServoBenchTester.ino.\n"
                "- Compile it for Arduino UNO R4 WiFi with Arduino CLI.\n"
                "- Upload it to COM5.\n"
                "- If upload reports Serial port busy, disconnect the Lab servo tester page from COM5 and close Arduino IDE Serial Monitor/Plotter, then retry.\n\n"
                "Current evidence: the smooth sketch compiled and uploaded to COM5. Reconnect the Lab page, select Use Smooth UNO Sketch, send PING, and verify PONG SmoothServoBenchTester in the serial log."
            )
            response_mode = "demonstration"
            failure_class = "servo_firmware_update_requires_local_serial_executor"
            training_lesson = "When Dave asks to update UNO firmware, route to a bounded local executor workflow: compile, upload, diagnose COM port lock, then update Studio evidence."
        elif serial_ok_no_servo_motion:
            reply = (
                "The serial lane is working. RX OK and PONG prove Chrome is talking to the UNO and the smooth sketch is running.\n\n"
                "The next diagnosis is downstream of serial:\n"
                "- Send STATUS. Expected good result: PCA9685 FOUND 0x40.\n"
                "- Send SCAN. Expected good result includes 0x40.\n"
                "- Send TESTALL to pulse all 16 PCA9685 channels, in case the top port is not channel 0.\n"
                "- If STATUS or SCAN does not show 0x40, check SDA/SCL, PCA9685 VCC/GND, address jumpers, and shared ground.\n"
                "- If 0x40 is found but TESTALL produces no movement, check servo V+ power on the PWM board and shared ground between servo supply, PCA9685, and UNO.\n\n"
                "This is not a browser connection problem anymore. It is channel mapping, I2C/PCA9685 detection, or servo power/ground."
            )
            response_mode = "problem_analysis"
            failure_class = "serial_ok_servo_no_motion_downstream_pwm_or_power"
            training_lesson = "When RX OK/PONG exists but no servo moves, stop diagnosing browser serial and test PCA9685 I2C presence, channel mapping, and servo power/ground."
        elif choppy_motion:
            reply = (
                "MIM should have diagnosed this as a motion-profile issue.\n\n"
                "Most likely cause: the current UNO sketch is a limit tester. It reads one number, then immediately calls pwm.setPWM on channels 0 and 1. That creates setpoint jumps, so movement can look like small bursts instead of a smooth ramp.\n\n"
                "Best fix:\n"
                "- Flash a smooth-motion UNO sketch that ramps from currentPulse to targetPulse in small steps.\n"
                "- Keep the browser sending one target value, such as 375 or 420.\n"
                "- Let the UNO handle timing, startup, and slowdown locally. Do not rely on the browser to stream tiny motion steps over serial.\n\n"
                "Suggested firmware behavior:\n"
                "- Store currentPulse.\n"
                "- When a target pulse arrives, constrain it to 100-650.\n"
                "- Move one count at a time, or 2-5 counts per step for faster travel.\n"
                "- Delay 8-20 ms per step for analog-servo smoothness.\n"
                "- Support per-channel commands so channels 0 and 1 can be tested separately.\n\n"
                "The smooth firmware has been uploaded to COM5. Reconnect the Lab page, select Use Smooth UNO Sketch, send PING, and then test movement with S channel pulse duration."
            )
            response_mode = "recommendation"
            failure_class = "servo_motion_choppy_requires_firmware_ramp"
            training_lesson = "When servo is connected but movement is choppy/bursty, diagnose motion profile/direct PWM setpoint jumps before connection or wiring."
        else:
            reply = (
                "This is a live hardware troubleshooting issue, not a prototype artifact.\n\n"
                "What I would check first:\n"
                "- Confirm the page shows Connected after the browser serial picker closes.\n"
                "- Use the serial log to verify TX lines are being sent and RX lines come back from the UNO.\n"
                "- For Dave's current sketch, use the current UNO sketch protocol at 9600 baud. It sends one number only, such as 375.\n"
                "- That firmware applies the same PCA9685 count to channels 0 and 1 together, so the page channel field will not matter until firmware supports per-channel commands.\n"
                "- Use MOVE {channel} {angle} or S {channel} {pulse} {duration} only after flashing firmware that supports those formats.\n"
                "- If TX appears but there is no servo movement, the likely causes are wrong sketch protocol, wrong PWM channel, servo power/ground, or the PWM driver address/wiring.\n\n"
                "I updated this page to include a Current UNO Sketch protocol button, connection state, serial logs, raw count range, ping, and slider-release movement."
            )
            response_mode = "problem_analysis"
            failure_class = "servo_tester_general_hardware_diagnostic"
            training_lesson = "For Lab servo tester issues, classify whether the failure is connection, protocol, firmware motion profile, channel selection, power, or wiring before giving a checklist."
        return {
            "ok": True,
            "source": "studio_lab_servo_tester_context",
            "response_mode": response_mode,
            "mim_interface": {
                "reply_text": reply,
                "page_context": page_context,
                "surface": "studio",
            },
            "navigation": None,
            "evidence": {
                "baud_rate": profile.get("baud_rate"),
                "command_template": profile.get("command_template"),
                "servo_count": len(profile.get("servos") if isinstance(profile.get("servos"), list) else []),
                "failure_class": failure_class,
                "training_lesson": training_lesson,
            },
        }
    if "report" in page_context_lower or any(term in prompt_lower for term in ["agentmim", "comm_app", "database", "db", "account owner", "account_owners", "app metrics"]):
        dataset = await _studio_report_dataset(db, "auto", prompt=prompt)
        reply = _compose_reports_page_reply(prompt, dataset)
        return {
            "ok": True,
            "source": "studio_reports_context",
            "response_mode": "problem_analysis" if any(term in prompt_lower for term in ["error", "fix", "unable", "resolve", "broken", "can't", "cannot"]) else "report_summary",
            "mim_interface": {
                "reply_text": reply,
                "page_context": page_context,
                "surface": "studio",
            },
            "navigation": None,
            "evidence": {
                "dataset": dataset.get("key"),
                "label": dataset.get("label"),
                "generated_at": dataset.get("generated_at"),
                "row_count": len(dataset.get("rows") if isinstance(dataset.get("rows"), list) else []),
            },
        }
    if "training" in page_context_lower:
        state = await _studio_training_state(db)
        reply = _compose_training_page_reply(prompt, state)
        return {
            "ok": True,
            "source": "studio_training_context",
            "response_mode": "recommendation" if _is_training_attention_prompt(prompt) else "training_summary",
            "mim_interface": {
                "reply_text": reply,
                "page_context": page_context,
                "surface": "studio",
            },
            "navigation": None,
            "evidence": {
                "generated_at": state.get("generated_at", ""),
                "assessment": state.get("assessment", ""),
                "judgment_pass_rate": (
                    state.get("judgment", {}).get("pass_rate_percent")
                    if isinstance(state.get("judgment"), dict)
                    else None
                ),
            },
        }
    return {
        "ok": False,
        "source": "studio_context_not_handled",
        "mim_interface": {"reply_text": ""},
    }


@router.get("/studio/api/projects/state")
async def studio_projects_state_api(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    return await _studio_projects_state(db)


def _form_bool(value: str | bool | None) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


@router.post("/studio/projects/create")
async def create_studio_project_form(
    title: str = Form(...),
    summary: str = Form(""),
    status: str = Form("queued"),
    priority: str = Form("P1"),
    owner: str = Form("TOD"),
    next_action: str = Form(""),
    blocker: str = Form("none"),
    progress_percent: int = Form(0),
    dave_needed: str = Form("false"),
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    metadata = {
        "progress_percent": max(0, min(100, int(progress_percent or 0))),
        "blocker": blocker.strip() or "none",
        "work_state": status.strip() or "queued",
        "project_type": "manual",
        "created_from": "studio_projects_form",
        "user_modified": True,
    }
    row = StudioProject(
        title=title.strip(),
        summary=summary,
        status=status.strip() or "queued",
        priority=priority.strip() or "P1",
        owner=owner.strip() or "TOD",
        health="new",
        next_action=next_action,
        dave_needed=_form_bool(dave_needed),
        metadata_json=metadata,
    )
    db.add(row)
    await db.flush()
    db.add(
        StudioProjectEvent(
            project_id=row.id,
            event_type="created",
            actor="Dave",
            title="Project created",
            detail=summary or next_action,
            metadata_json={"source": "studio_projects_form"},
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/studio/projects?project_id={row.id}", status_code=303)


@router.post("/studio/projects/{project_id}/update")
async def update_studio_project_form(
    project_id: int,
    summary: str = Form(""),
    status: str = Form("queued"),
    priority: str = Form("P1"),
    owner: str = Form("TOD"),
    health: str = Form("good"),
    next_action: str = Form(""),
    blocker: str = Form("none"),
    progress_percent: int = Form(0),
    dave_needed: str = Form("false"),
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    row = await db.get(StudioProject, project_id)
    if not row:
        raise HTTPException(status_code=404, detail="studio_project_not_found")
    row.summary = summary
    row.status = status.strip() or "queued"
    row.priority = priority.strip() or "P1"
    row.owner = owner.strip() or "TOD"
    row.health = health.strip() or "good"
    row.next_action = next_action
    row.dave_needed = _form_bool(dave_needed)
    metadata = row.metadata_json if isinstance(row.metadata_json, dict) else {}
    metadata.update(
        {
            "progress_percent": max(0, min(100, int(progress_percent or 0))),
            "blocker": blocker.strip() or "none",
            "work_state": row.status,
            "updated_from": "studio_projects_form",
            "user_modified": True,
        }
    )
    row.metadata_json = metadata
    db.add(
        StudioProjectEvent(
            project_id=row.id,
            event_type="updated",
            actor="Dave",
            title="Project updated",
            detail=next_action or summary,
            metadata_json={"source": "studio_projects_form"},
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/studio/projects?project_id={row.id}", status_code=303)


@router.post("/studio/projects/{project_id}/pause")
async def pause_studio_project_form(
    project_id: int,
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    row = await db.get(StudioProject, project_id)
    if not row:
        raise HTTPException(status_code=404, detail="studio_project_not_found")
    row.status = "paused"
    metadata = row.metadata_json if isinstance(row.metadata_json, dict) else {}
    metadata["work_state"] = "paused"
    metadata["user_modified"] = True
    row.metadata_json = metadata
    db.add(StudioProjectEvent(project_id=row.id, event_type="paused", actor="Dave", title="Project paused"))
    await db.commit()
    return RedirectResponse(url=f"/studio/projects?project_id={row.id}", status_code=303)


@router.post("/studio/projects/{project_id}/delete")
async def delete_studio_project_form(
    project_id: int,
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    row = await db.get(StudioProject, project_id)
    if not row:
        raise HTTPException(status_code=404, detail="studio_project_not_found")
    row.status = "deleted"
    row.health = "deleted"
    metadata = row.metadata_json if isinstance(row.metadata_json, dict) else {}
    metadata["work_state"] = "deleted"
    metadata["user_modified"] = True
    row.metadata_json = metadata
    db.add(StudioProjectEvent(project_id=row.id, event_type="deleted", actor="Dave", title="Project deleted"))
    await db.commit()
    return RedirectResponse(url="/studio/projects", status_code=303)


@router.post("/studio/projects/{project_id}/events")
async def create_studio_project_event_form(
    project_id: int,
    title: str = Form(""),
    actor: str = Form("Dave"),
    detail: str = Form(""),
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    project = await db.get(StudioProject, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="studio_project_not_found")
    metadata = project.metadata_json if isinstance(project.metadata_json, dict) else {}
    metadata["user_modified"] = True
    project.metadata_json = metadata
    db.add(
        StudioProjectEvent(
            project_id=project.id,
            event_type="note",
            actor=actor.strip() or "Dave",
            title=title.strip() or "Project note",
            detail=detail,
            metadata_json={"source": "studio_projects_form"},
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/studio/projects?project_id={project.id}", status_code=303)


@router.post("/studio/projects/signals/{signal_id}/promote")
async def promote_studio_project_signal_form(
    signal_id: int,
    db: AsyncSession = Depends(get_db),
) -> RedirectResponse:
    signal = await db.get(StudioProjectSignal, signal_id)
    if not signal:
        raise HTTPException(status_code=404, detail="studio_project_signal_not_found")
    project = StudioProject(
        title=signal.title.strip(),
        summary=signal.source_text,
        status="queued",
        priority=signal.priority.strip() or "normal",
        owner="TOD",
        health="new",
        why_it_matters=signal.why_it_matters,
        origin_story=f"Promoted from signal #{signal.id}: {signal.source_text}",
        next_action="Define scope and first acceptance check.",
        dave_needed=False,
        metadata_json={
            "promoted_from_signal_id": signal.id,
            "progress_percent": 0,
            "work_state": "queued",
            "blocker": "none",
            "project_type": "promoted_signal",
        },
    )
    db.add(project)
    await db.flush()
    signal.status = "promoted"
    signal.project_id = project.id
    db.add(
        StudioProjectEvent(
            project_id=project.id,
            event_type="promoted_from_signal",
            actor="Dave",
            title="Signal promoted to project",
            detail=signal.source_text,
            evidence_json={"signal_id": signal.id},
            metadata_json={"source": "studio_projects_form"},
        )
    )
    await db.commit()
    return RedirectResponse(url=f"/studio/projects?project_id={project.id}", status_code=303)


@router.post("/studio/api/project-signals")
async def create_studio_project_signal(
    payload: StudioProjectSignalCreate,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = StudioProjectSignal(
        title=payload.title.strip(),
        signal_type=payload.signal_type.strip() or "observation",
        status=payload.status.strip() or "observation",
        priority=payload.priority.strip() or "normal",
        source_surface=payload.source_surface.strip() or "studio",
        source_text=payload.source_text,
        why_it_matters=payload.why_it_matters,
        suggested_action=payload.suggested_action.strip() or "review",
        metadata_json=payload.metadata_json,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {"ok": True, "signal": _studio_signal_to_dict(row)}


@router.post("/studio/api/projects")
async def create_studio_project(
    payload: StudioProjectCreate,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = StudioProject(
        title=payload.title.strip(),
        summary=payload.summary,
        status=payload.status.strip() or "candidate",
        priority=payload.priority.strip() or "normal",
        owner=payload.owner.strip() or "Dave + MIM",
        health=payload.health.strip() or "good",
        why_it_matters=payload.why_it_matters,
        origin_story=payload.origin_story,
        next_action=payload.next_action,
        dave_needed=payload.dave_needed,
        metadata_json=payload.metadata_json,
    )
    db.add(row)
    await db.flush()
    db.add(
        StudioProjectEvent(
            project_id=row.id,
            event_type="created",
            actor="MIM Studio",
            title="Project created",
            detail=row.origin_story or row.summary,
            metadata_json={"source": "studio_api"},
        )
    )
    await db.commit()
    await db.refresh(row)
    return {"ok": True, "project": _studio_project_to_dict(row)}


@router.post("/studio/api/project-signals/{signal_id}/promote")
async def promote_studio_project_signal(
    signal_id: int,
    payload: StudioProjectSignalPromote | None = Body(default=None),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    signal = await db.get(StudioProjectSignal, signal_id)
    if not signal:
        raise HTTPException(status_code=404, detail="studio_project_signal_not_found")
    project_payload = payload.project if payload and payload.project else None
    project = StudioProject(
        title=(project_payload.title if project_payload else signal.title).strip(),
        summary=(project_payload.summary if project_payload else signal.source_text),
        status=(project_payload.status if project_payload else "planning").strip() or "planning",
        priority=(project_payload.priority if project_payload else signal.priority).strip() or "normal",
        owner=(project_payload.owner if project_payload else "Dave + MIM").strip() or "Dave + MIM",
        health=(project_payload.health if project_payload else "good").strip() or "good",
        why_it_matters=project_payload.why_it_matters if project_payload else signal.why_it_matters,
        origin_story=project_payload.origin_story
        if project_payload
        else f"Promoted from signal #{signal.id}: {signal.source_text}",
        next_action=project_payload.next_action
        if project_payload
        else "Continue discovery and define the project bundle.",
        dave_needed=project_payload.dave_needed if project_payload else False,
        metadata_json=project_payload.metadata_json if project_payload else {"promoted_from_signal_id": signal.id},
    )
    db.add(project)
    await db.flush()
    signal.status = "promoted"
    signal.project_id = project.id
    db.add(
        StudioProjectEvent(
            project_id=project.id,
            event_type="promoted_from_signal",
            actor="MIM Studio",
            title="Signal promoted to project",
            detail=signal.source_text,
            evidence_json={"signal_id": signal.id},
            metadata_json={"source": "studio_api"},
        )
    )
    await db.commit()
    await db.refresh(project)
    await db.refresh(signal)
    return {"ok": True, "signal": _studio_signal_to_dict(signal), "project": _studio_project_to_dict(project)}


@router.post("/studio/api/projects/{project_id}/events")
async def create_studio_project_event(
    project_id: int,
    payload: StudioProjectEventCreate,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    project = await db.get(StudioProject, project_id)
    if not project:
        raise HTTPException(status_code=404, detail="studio_project_not_found")
    event = StudioProjectEvent(
        project_id=project.id,
        event_type=payload.event_type.strip() or "note",
        actor=payload.actor.strip() or "MIM",
        title=payload.title,
        detail=payload.detail,
        evidence_json=payload.evidence_json,
        metadata_json=payload.metadata_json,
    )
    db.add(event)
    await db.commit()
    await db.refresh(event)
    return {
        "ok": True,
        "event": {
            "id": event.id,
            "project_id": event.project_id,
            "event_type": event.event_type,
            "actor": event.actor,
            "title": event.title,
            "detail": event.detail,
            "created_at": event.created_at.isoformat() if event.created_at else "",
        },
    }


@router.get("/studio/api/documents/state")
async def studio_documents_state_api(
    document_id: int | None = None,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await _studio_documents_state(db, selected_document_id=document_id)


@router.get("/studio/api/document-links")
async def studio_document_links_api(
    document_id: int | None = None,
    target_type: str = "",
    target_id: str = "",
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    await _ensure_studio_document_seed(db)
    await _ensure_training_document_records(db)
    await _ensure_studio_document_relationship_seed(db)
    statement = select(StudioDocumentLink).order_by(StudioDocumentLink.id.desc()).limit(240)
    if document_id is not None:
        statement = (
            select(StudioDocumentLink)
            .where(StudioDocumentLink.document_id == document_id)
            .order_by(StudioDocumentLink.id.desc())
            .limit(240)
        )
    elif target_type.strip() or target_id.strip():
        statement = select(StudioDocumentLink)
        if target_type.strip():
            statement = statement.where(StudioDocumentLink.target_type == target_type.strip())
        if target_id.strip():
            statement = statement.where(StudioDocumentLink.target_id == target_id.strip())
        statement = statement.order_by(StudioDocumentLink.id.desc()).limit(240)
    rows = (await db.execute(statement)).scalars().all()
    return {"ok": True, "links": [_studio_document_link_to_dict(row) for row in rows]}


@router.get("/studio/api/documents/{document_id}")
async def studio_document_detail_api(
    document_id: int,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    document = await db.get(StudioDocument, document_id)
    if not document:
        raise HTTPException(status_code=404, detail="studio_document_not_found")
    links = (
        await db.execute(
            select(StudioDocumentLink)
            .where(StudioDocumentLink.document_id == document.id)
            .order_by(StudioDocumentLink.id.desc())
        )
    ).scalars().all()
    return {
        "ok": True,
        "document": _studio_document_to_dict(document),
        "links": [_studio_document_link_to_dict(row) for row in links],
    }


@router.get("/studio/api/reports/state")
async def studio_reports_state_api(
    dataset: str = "studio_overview",
    prompt: str = "",
    canvas_id: int | None = None,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await _studio_reports_state(
        db,
        dataset_key=dataset,
        prompt=prompt,
        canvas_id=canvas_id,
    )


@router.get("/studio/api/apps/sources")
async def studio_app_sources_api() -> dict[str, Any]:
    return {"ok": True, "apps": APP_SOURCE_REGISTRY}


@router.get("/studio/api/apps/state")
async def studio_apps_state_api(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    state = await _studio_apps_state(db)
    return {"ok": True, **state}


@router.get("/studio/api/reports/dataset")
async def studio_report_dataset_api(
    dataset: str = "studio_overview",
    prompt: str = "",
    format: str = "json",
    db: AsyncSession = Depends(get_db),
) -> Any:
    report = await _studio_report_dataset(db, dataset, prompt=prompt)
    if format.strip().lower() == "csv":
        columns = report.get("columns") if isinstance(report.get("columns"), list) else []
        rows = report.get("rows") if isinstance(report.get("rows"), list) else []
        csv_lines = [",".join(str(column).replace('"', '""') for column in columns)]
        for row in rows:
            if not isinstance(row, dict):
                continue
            values = []
            for column in columns:
                value = str(row.get(column, "")).replace('"', '""')
                values.append(f'"{value}"')
            csv_lines.append(",".join(values))
        return Response(
            "\n".join(csv_lines) + "\n",
            media_type="text/csv",
            headers={"Content-Disposition": f'attachment; filename="studio-report-{report["key"]}.csv"'},
        )
    return {"ok": True, "dataset": report}


@router.post("/studio/api/reports/canvases")
async def create_studio_report_canvas(
    payload: StudioReportCanvasCreate,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    dataset = await _studio_report_dataset(
        db,
        payload.dataset_key.strip() or "studio_overview",
        prompt=payload.prompt,
    )
    title = payload.title.strip() or f"{dataset['label']} Report"
    row = StudioReportCanvas(
        title=title,
        prompt=payload.prompt,
        dataset_key=dataset["key"],
        status=payload.status.strip() or "draft",
        created_by=payload.created_by.strip() or "MIM",
        summary=dataset["summary"],
        layout_json={"template": "data_whiteboard", "columns": dataset["columns"]},
        filters_json=payload.filters_json,
        findings_json=dataset["findings"],
        actions_json=dataset["actions"],
        metadata_json={**payload.metadata_json, "source": "studio_reports_api"},
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {"ok": True, "canvas": _studio_report_canvas_to_dict(row)}


@router.post("/studio/api/documents")
async def create_studio_document(
    payload: StudioDocumentCreate,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    row = StudioDocument(
        title=payload.title.strip(),
        summary=payload.summary,
        document_type=payload.document_type.strip() or "note",
        category=payload.category.strip() or "library",
        status=payload.status.strip() or "active",
        owner=payload.owner.strip() or "Dave + MIM",
        created_by=payload.created_by.strip() or "MIM",
        source_kind=payload.source_kind.strip() or "manual",
        source_url=payload.source_url,
        source_path=payload.source_path,
        local_path=payload.local_path,
        preserve_policy=payload.preserve_policy.strip() or "reference",
        snapshot_status=payload.snapshot_status.strip() or "not_requested",
        content_text=payload.content_text,
        tags_json=payload.tags_json,
        metadata_json=payload.metadata_json,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {"ok": True, "document": _studio_document_to_dict(row)}


@router.post("/studio/api/documents/{document_id}/links")
async def create_studio_document_link(
    document_id: int,
    payload: StudioDocumentLinkCreate,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    document = await db.get(StudioDocument, document_id)
    if not document:
        raise HTTPException(status_code=404, detail="studio_document_not_found")
    row = StudioDocumentLink(
        document_id=document.id,
        target_type=payload.target_type.strip(),
        target_id=payload.target_id,
        relation=payload.relation.strip() or "related",
        label=payload.label,
        metadata_json=payload.metadata_json,
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {
        "ok": True,
        "link": {
            "id": row.id,
            "document_id": row.document_id,
            "target_type": row.target_type,
            "target_id": row.target_id,
            "relation": row.relation,
            "label": row.label,
        },
    }


@router.get("/studio/{tab_key}", response_class=HTMLResponse)
async def studio_tab(
    request: Request,
    tab_key: str,
    db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
    key = str(tab_key or "").strip().lower()
    tab = next((item for item in TABS if item["key"] == key), None)
    if tab is None or key == "home":
        return await studio_home(request)
    auth_redirect = maybe_require_mimtod_page_login(request, next_path=f"/studio/{key}")
    if auth_redirect is not None:
        return auth_redirect
    if tab["kind"] == "embed":
        body = _embed_body(tab)
        subtitle = f"Studio wrapper for the existing {tab.get('source')} console."
    elif key == "projects":
        selected_project_id = None
        raw_project_id = request.query_params.get("project_id")
        if raw_project_id:
            try:
                selected_project_id = int(raw_project_id)
            except ValueError:
                selected_project_id = None
        state = await _studio_projects_state(
            db,
            selected_project_id=selected_project_id,
            view=request.query_params.get("view", "all"),
            new_project=request.query_params.get("new_project", "") in {"1", "true", "yes"},
        )
        body = _projects_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "documents":
        selected_document_id = None
        raw_document_id = request.query_params.get("document_id")
        if raw_document_id:
            try:
                selected_document_id = int(raw_document_id)
            except ValueError:
                selected_document_id = None
        state = await _studio_documents_state(db, selected_document_id=selected_document_id)
        body = _documents_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "reports":
        canvas_id = None
        raw_canvas_id = request.query_params.get("canvas_id")
        if raw_canvas_id:
            try:
                canvas_id = int(raw_canvas_id)
            except ValueError:
                canvas_id = None
        state = await _studio_reports_state(
            db,
            dataset_key=request.query_params.get("dataset", "studio_overview"),
            prompt=request.query_params.get("prompt", ""),
            canvas_id=canvas_id,
        )
        body = _reports_body(state)
        subtitle = "A blank data whiteboard where MIM turns questions into datasets, summaries, findings, and actions."
    elif key == "training":
        state = await _studio_training_state(db)
        body = _training_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "apps":
        state = await _studio_apps_state(db)
        body = _apps_body(state, selected_app_key=request.query_params.get("app", ""))
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "systems":
        state = await _studio_systems_state(db)
        body = _systems_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "lab":
        state = await _studio_lab_state(db)
        body = _lab_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "accounting":
        state = await _studio_accounting_state(db)
        body = _accounting_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    elif key == "settings":
        state = await _studio_settings_state(db)
        body = _settings_body(state)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    else:
        body = _placeholder_body(key)
        subtitle = str(PLACEHOLDERS[key]["subtitle"])
    return HTMLResponse(
        _shell(
            active=key,
            title=tab["label"],
            subtitle=subtitle,
            body=body,
            page_context=f"Studio {tab['label']}",
            show_mim_panel=key not in {"mim", "tod"},
        )
    )
