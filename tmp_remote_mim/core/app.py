from contextlib import asynccontextmanager
import hashlib
import ipaddress
import os
import uuid

from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse, Response
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from core import models  # noqa: F401
from core.config import settings
from core.db import Base, SessionLocal, engine
from core.logging_journal import configure_logging, journal_event
from core.mim_ui_auth import login_redirect_url, request_has_valid_mimtod_auth
from core.models import PublicVisitEvent
from core.routers import api_router


configure_logging()


OPTIONAL_ALTER_TABLE_STATEMENTS = (
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS resolution_id INTEGER",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS goal_id INTEGER",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS arguments_json JSONB DEFAULT '{}'::jsonb",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS safety_mode VARCHAR(40) DEFAULT 'standard'",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS requested_executor VARCHAR(120) DEFAULT 'tod'",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS dispatch_decision VARCHAR(40) DEFAULT 'requires_confirmation'",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS trace_id VARCHAR(120) DEFAULT ''",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS managed_scope VARCHAR(120) DEFAULT 'global'",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS status VARCHAR(40) DEFAULT 'pending'",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS reason TEXT DEFAULT ''",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS feedback_json JSONB DEFAULT '{}'::jsonb",
    "ALTER TABLE IF EXISTS capability_executions ADD COLUMN IF NOT EXISTS execution_truth_json JSONB DEFAULT '{}'::jsonb",
)


def _optional_schema_deadlock(exc: Exception) -> bool:
    text_value = str(exc or "").lower()
    return "deadlock detected" in text_value or "lock timeout" in text_value


def _schema_connectivity_unavailable(exc: Exception) -> bool:
    text_value = str(exc or "").lower()
    return isinstance(exc, (ConnectionRefusedError, TimeoutError, OSError)) or any(
        phrase in text_value
        for phrase in (
            "refused the network connection",
            "connection refused",
            "failed to connect",
            "could not connect",
            "asyncpg",
            "targetserverattributenotmatched",
        )
    )


async def _execute_optional_schema_ddl(conn, statement: str) -> None:
    try:
        async with conn.begin_nested():
            await conn.execute(text(statement))
    except DBAPIError as exc:
        if not _optional_schema_deadlock(exc):
            raise
        journal_event(
            actor="system",
            action="startup_optional_schema_ddl_deferred",
            result="degraded",
            metadata={
                "statement": statement,
                "error": str(exc),
            },
        )


async def ensure_schema() -> None:
    async with engine.begin() as conn:
        try:
            await conn.execute(text("SELECT pg_advisory_xact_lock(814523791337610201)"))
        except Exception:
            pass
        await conn.run_sync(Base.metadata.create_all)
        for statement in OPTIONAL_ALTER_TABLE_STATEMENTS:
            await _execute_optional_schema_ddl(conn, statement)


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        await ensure_schema()
    except Exception as exc:
        if not _schema_connectivity_unavailable(exc):
            raise
        journal_event(
            actor="system",
            action="startup_schema_unavailable",
            result="degraded",
            metadata={
                "error": str(exc),
            },
        )
    yield
    await engine.dispose()


app = FastAPI(title=settings.app_name, version=settings.app_version, lifespan=lifespan)
app.include_router(api_router)


OPERATOR_ONLY_PREFIXES = (
    "/studio",
    "/objectives",
    "/mim",
    "/tod",
)

OPERATOR_AUTH_EXEMPT_PREFIXES = (
    "/mim/login",
    "/mim/logout",
)

OPERATOR_CANONICAL_HOST = os.environ.get("MIMTOD_OPERATOR_HOST", "mim.mimtod.com").strip().lower()
OPERATOR_PUBLIC_HOSTS = {
    "mimtod.com",
    "www.mimtod.com",
}

PUBLIC_VISIT_EXCLUDED_PREFIXES = (
    "/studio",
    "/objectives",
    "/mim",
    "/tod",
    "/health",
    "/status",
    "/manifest",
    "/static",
    "/favicon",
    "/api",
    "/operator",
    "/automation",
    "/gateway",
    "/workspace",
    "/tools",
    "/services",
)

PUBLIC_VISIT_INCLUDED_PREFIXES = (
    "/",
    "/demo",
    "/login",
    "/dashboard",
    "/terms",
    "/privacy",
    "/cookies",
    "/public-chat",
    "/apps/templates",
    "/projects",
)

BOT_USER_AGENT_MARKERS = (
    "bot",
    "crawler",
    "spider",
    "preview",
    "curl",
    "wget",
    "uptime",
    "monitor",
    "headless",
)


def _matches_path_prefix(path: str, prefixes: tuple[str, ...]) -> bool:
    clean_path = "/" + str(path or "").lstrip("/")
    return any(clean_path == prefix or clean_path.startswith(f"{prefix}/") for prefix in prefixes)


def _request_host_name(request: Request) -> str:
    forwarded_host = str(request.headers.get("x-forwarded-host") or "").strip()
    raw_host = forwarded_host.split(",", 1)[0].strip() if forwarded_host else str(request.headers.get("host") or request.url.netloc or request.url.hostname or "")
    if raw_host.startswith("[") and "]" in raw_host:
        return raw_host[1 : raw_host.index("]")].strip().lower()
    if ":" in raw_host:
        return raw_host.rsplit(":", 1)[0].strip().lower()
    return raw_host.strip().lower()


def _operator_canonical_redirect(request: Request) -> RedirectResponse | None:
    path = request.url.path or "/"
    if not _matches_path_prefix(path, OPERATOR_ONLY_PREFIXES):
        return None
    host = _request_host_name(request)
    if not OPERATOR_CANONICAL_HOST or host == OPERATOR_CANONICAL_HOST or host not in OPERATOR_PUBLIC_HOSTS:
        return None
    target = f"https://{OPERATOR_CANONICAL_HOST}{path}"
    if request.url.query:
        target = f"{target}?{request.url.query}"
    return RedirectResponse(url=target, status_code=308)


def _operator_auth_required_path(path: str) -> bool:
    return _matches_path_prefix(path, OPERATOR_ONLY_PREFIXES) and not _matches_path_prefix(
        path,
        OPERATOR_AUTH_EXEMPT_PREFIXES,
    )


def _request_ip(request: Request) -> str:
    forwarded = str(request.headers.get("x-forwarded-for") or "").split(",", 1)[0].strip()
    if forwarded:
        return forwarded
    real_ip = str(request.headers.get("x-real-ip") or "").strip()
    if real_ip:
        return real_ip
    return request.client.host if request.client else ""


def _hash_visit_value(value: str) -> str:
    salt = os.environ.get("MIMTOD_VISITOR_HASH_SALT") or settings.app_name
    return hashlib.sha256(f"{salt}:{value}".encode("utf-8", errors="ignore")).hexdigest()[:48]


def _excluded_public_visit_ips() -> set[str]:
    raw = os.environ.get("MIMTOD_EXCLUDED_VISITOR_IPS", "")
    return {part.strip() for part in raw.split(",") if part.strip()}


def _is_private_or_excluded_ip(ip_value: str) -> bool:
    if not ip_value:
        return False
    if ip_value in _excluded_public_visit_ips():
        return True
    try:
        parsed = ipaddress.ip_address(ip_value)
    except ValueError:
        return False
    return bool(parsed.is_private or parsed.is_loopback or parsed.is_link_local)


def _should_track_public_visit(path: str, method: str) -> bool:
    clean_path = "/" + str(path or "").lstrip("/")
    if method.upper() not in {"GET", "POST"}:
        return False
    if _matches_path_prefix(clean_path, PUBLIC_VISIT_EXCLUDED_PREFIXES):
        return False
    return _matches_path_prefix(clean_path, PUBLIC_VISIT_INCLUDED_PREFIXES)


def _public_visit_event_type(path: str, method: str) -> str:
    clean_path = "/" + str(path or "").lstrip("/")
    if clean_path == "/demo":
        return "demo_view"
    if clean_path.startswith("/apps/templates/") and clean_path.endswith("/demo"):
        return "template_demo_view"
    if clean_path == "/login":
        return "login_page_view"
    if clean_path.startswith("/projects") and method.upper() == "POST":
        return "project_portal_action"
    return "page_view"


async def _record_public_visit(
    *,
    request: Request,
    response: Response,
    visitor_id: str,
    internal: bool,
) -> None:
    path = request.url.path or "/"
    method = request.method.upper()
    if not _should_track_public_visit(path, method):
        return
    user_agent = str(request.headers.get("user-agent") or "")[:1000]
    ip_value = _request_ip(request)
    is_internal = internal or _is_private_or_excluded_ip(ip_value)
    ua_lower = user_agent.lower()
    is_bot = any(marker in ua_lower for marker in BOT_USER_AGENT_MARKERS)
    try:
        async with SessionLocal() as session:
            session.add(
                PublicVisitEvent(
                    visitor_hash=_hash_visit_value(visitor_id),
                    ip_hash=_hash_visit_value(ip_value) if ip_value else "",
                    path=path[:500],
                    method=method,
                    status_code=int(getattr(response, "status_code", 0) or 0),
                    referrer=str(request.headers.get("referer") or "")[:2000],
                    user_agent=user_agent,
                    event_type=_public_visit_event_type(path, method),
                    is_internal=is_internal,
                    is_bot=is_bot,
                    metadata_json={
                        "host": str(request.url.hostname or ""),
                        "query_present": bool(request.url.query),
                        "source": "mimtod_public_visit_middleware",
                    },
                )
            )
            await session.commit()
    except Exception as exc:
        journal_event(
            actor="system",
            action="public_visit_event_record_failed",
            result="degraded",
            metadata={"error": exc.__class__.__name__, "path": path},
        )


@app.middleware("http")
async def record_public_visits(request: Request, call_next) -> Response:
    visitor_id = request.cookies.get("mim_public_vid") or uuid.uuid4().hex
    had_cookie = bool(request.cookies.get("mim_public_vid"))
    internal = request_has_valid_mimtod_auth(request)
    response = await call_next(request)
    if _should_track_public_visit(request.url.path or "/", request.method):
        if not had_cookie:
            response.set_cookie(
                "mim_public_vid",
                visitor_id,
                max_age=60 * 60 * 24 * 365,
                httponly=True,
                secure=request.url.scheme == "https",
                samesite="lax",
            )
        await _record_public_visit(
            request=request,
            response=response,
            visitor_id=visitor_id,
            internal=internal,
        )
    return response


@app.middleware("http")
async def require_operator_for_internal_surfaces(request: Request, call_next) -> Response:
    path = request.url.path or "/"
    canonical_redirect = _operator_canonical_redirect(request)
    if canonical_redirect is not None:
        canonical_redirect.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
        canonical_redirect.headers["Cache-Control"] = "no-store"
        return canonical_redirect
    if _operator_auth_required_path(path) and not request_has_valid_mimtod_auth(request):
        if "text/html" in str(request.headers.get("accept") or "").lower() or request.method.upper() == "GET":
            next_path = path
            if request.url.query:
                next_path = f"{path}?{request.url.query}"
            return RedirectResponse(url=login_redirect_url(next_path), status_code=303)
        return Response("mimtod_operator_login_required", status_code=401)
    response = await call_next(request)
    if _matches_path_prefix(path, OPERATOR_ONLY_PREFIXES):
        response.headers["X-Robots-Tag"] = "noindex, nofollow, noarchive"
        response.headers["Cache-Control"] = "no-store"
    return response


@app.middleware("http")
async def add_no_store_headers(request: Request, call_next) -> Response:
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    return response
