from __future__ import annotations

import hashlib
import html
import json
import re
from urllib import error as urllib_error
from urllib import parse as urllib_parse
from urllib import request as urllib_request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from core.communication_composer import compose_expert_communication_reply
from core.config import settings
from core.conversation_purpose_engine import build_conversation_purpose_reply
from core.mim_cognitive_entrypoint import (
    build_mim_cognitive_interpretation,
    interpretation_response_authority,
)
from core.db import get_db
from core.identity import MIM_LEGAL_CONTACT_EMAIL
from core.identity import MIM_LEGAL_ENTITY_NAME
from core.identity import MIM_LEGAL_JURISDICTION
from core.identity import mim_public_identity_summary
from core.identity import public_channel_definition
from core.identity import public_system_identity_summary
from core.identity import tod_public_identity_summary
from core.interface_service import (
    append_interface_message,
    get_interface_session,
    list_interface_messages,
    to_interface_message_out,
    to_interface_session_out,
    upsert_interface_session,
)
from core.models import MemoryEntry
from core.observatory_research import get_research_initiative, list_research_initiatives
from core.public_research_context import is_research_context, research_context_from_initiative, research_context_reply
from core.routers.project_portal import _current_account_or_none


router = APIRouter(tags=["public-chat"])

PUBLIC_CHAT_MESSAGE_LIMIT = 100
PUBLIC_CHAT_UPLOAD_LIMIT_BYTES = 262_144
PUBLIC_PROFILE_SCAN_LIMIT = 200
PUBLIC_PRIVACY_POLICY_PATH = "/privacy"
PUBLIC_TEXT_UPLOAD_EXTENSIONS = {
    ".txt",
    ".md",
    ".py",
    ".js",
    ".ts",
    ".tsx",
    ".jsx",
    ".json",
    ".yaml",
    ".yml",
    ".css",
    ".html",
    ".sql",
    ".csv",
    ".toml",
    ".ini",
    ".log",
    ".xml",
}

PUBLIC_HOMEPAGE_ARTIFACT = "MIM_PUBLIC_HOMEPAGE_REIMAGINING_SAMPLE.latest.html"
USER_APP_PUBLISHED_ROOT = Path("runtime/shared/user_app_published")
USER_APP_GALLERY_MANIFEST = USER_APP_PUBLISHED_ROOT / "gallery.manifest.json"
PUBLIC_CHAT_DEFAULT_TIMEZONE = "America/Los_Angeles"


def _approved_public_homepage_html() -> str:
    artifact_candidates = (
        Path.cwd() / "runtime" / "shared" / PUBLIC_HOMEPAGE_ARTIFACT,
        Path(__file__).resolve().parents[2] / "runtime" / "shared" / PUBLIC_HOMEPAGE_ARTIFACT,
    )
    html_text = ""
    for artifact_path in artifact_candidates:
        try:
            html_text = artifact_path.read_text(encoding="utf-8")
            break
        except OSError:
            continue
    if not html_text:
        return ""
    required_markers = (
        "<title>MIM</title>",
        "A Collaborative Intelligence built to",
        "observe, learn, reason, and explore with you.",
        "/observatory",
        "/observatory/enterprise",
        "/build",
        "/community",
        "/community/questions",
        "researchQuestionBanner",
        "menuAccountBadge",
        "chat-shell",
        "frontQuestion",
    )
    if not all(marker in html_text for marker in required_markers):
        return ""
    return html_text


def _clean_public_homepage_fallback_html() -> str:
    return """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MIM</title>
  <style>
    :root { color-scheme: dark; --bg:#000; --panel:#0d0f14; --line:#2a2d36; --text:#f5f7fb; --muted:#9aa3af; --accent:#ffffff; }
    * { box-sizing: border-box; }
    body { margin:0; min-height:100vh; background:var(--bg); color:var(--text); font:14px/1.45 Arial, sans-serif; overflow-x:hidden; }
    a { color:inherit; text-decoration:none; }
    .site-menu { position:fixed; top:20px; right:20px; z-index:10; display:flex; align-items:center; gap:8px; }
    .menu-account-badge { max-width:190px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.045); color:var(--text); padding:10px 12px; font-weight:800; }
    .icon-button { width:42px; height:42px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.045); color:var(--text); display:grid; place-items:center; cursor:pointer; }
    .icon-button svg { width:19px; height:19px; stroke:currentColor; stroke-width:2; fill:none; stroke-linecap:round; stroke-linejoin:round; }
    .menu-panel { position:absolute; top:52px; right:0; min-width:172px; padding:10px; border:1px solid var(--line); border-radius:8px; background:#090b10; display:none; gap:4px; box-shadow:0 20px 60px rgba(0,0,0,.45); }
    .site-menu.open .menu-panel { display:grid; }
    .menu-panel a { padding:10px 12px; border-radius:7px; color:#c7ced8; font-weight:700; }
    .menu-panel a:hover { background:rgba(255,255,255,.06); color:#fff; }
    .account-button { display:none; }
    .auth-ready .account-button { display:grid; }
    .auth-ready .login-button { display:none; }
    .menu-link-button { width:100%; border:0; border-radius:7px; background:transparent; color:#c7ced8; padding:10px 12px; text-align:left; font:inherit; font-weight:700; cursor:pointer; }
    .menu-link-button:hover,.menu-link-button:focus-visible { background:rgba(255,255,255,.06); color:#fff; outline:none; }
    main { min-height:100vh; display:grid; place-items:center; padding:72px 18px 32px; }
    .stage { width:min(760px,100%); min-height:min(680px,calc(100vh - 104px)); display:grid; place-items:center; position:relative; }
    .intro-word { position:absolute; margin:0; font-size:clamp(64px,13vw,150px); letter-spacing:0; opacity:0; animation:introWord 8.6s ease forwards; }
    .intro-line { position:absolute; margin:0; text-align:center; font-size:clamp(21px,4vw,42px); line-height:1.22; font-weight:700; opacity:0; animation:introLine 8.8s ease forwards; animation-delay:3.6s; }
    .intro-line span { display:block; }
    .chat-shell { width:min(760px,100%); height:min(520px,calc(100vh - 132px)); border:1px solid var(--line); border-radius:18px; background:linear-gradient(180deg,rgba(16,17,22,.94),rgba(8,9,12,.98)); box-shadow:0 30px 110px rgba(0,0,0,.62); display:grid; grid-template-rows:auto 1fr auto; overflow:hidden; opacity:0; animation:chatIn 1.1s ease forwards; animation-delay:7.2s; }
    .chat-head { display:flex; align-items:center; justify-content:space-between; padding:14px 18px; border-bottom:1px solid var(--line); color:#d7dce4; }
    .identity { display:flex; align-items:center; gap:10px; font-weight:800; }
    .pulse { width:8px; height:8px; border-radius:999px; background:#fff; box-shadow:0 0 18px rgba(255,255,255,.85); }
    .chat-status { color:var(--muted); font-size:12px; }
    .messages { padding:22px 18px; overflow-y:auto; display:flex; flex-direction:column; gap:16px; }
    .message { max-width:82%; border:1px solid var(--line); border-radius:14px; padding:12px 14px; white-space:pre-wrap; }
    .message.user { align-self:flex-end; background:#f3f5f8; color:#090b10; }
    .message.mim { align-self:flex-start; background:#11141b; color:#eef2f7; }
    .composer { padding:14px; border-top:1px solid var(--line); background:rgba(0,0,0,.22); }
    .composer-inner { min-height:64px; display:grid; grid-template-columns:auto 1fr auto auto; align-items:end; gap:10px; border:1px solid var(--line); border-radius:999px; padding:8px; background:#090b10; }
    .research-question-banner { width:min(980px,100%); margin:18px auto 0; border:1px solid var(--line); border-radius:14px; background:rgba(255,255,255,.035); padding:14px; opacity:0; animation:chatIn 1.1s ease forwards; animation-delay:7.35s; }
    .research-question-banner h2 { margin:0 0 10px; font-size:14px; color:#d8dee8; }
    .question-rail { display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:10px; }
    .question-card { min-height:108px; border:1px solid var(--line); border-radius:10px; padding:12px; background:#11141b; display:grid; gap:8px; align-content:start; }
    .question-card strong { color:#fff; }
    .question-card span { color:#d7dce4; }
    .question-card small { color:var(--muted); }
    textarea { width:100%; max-height:180px; min-height:38px; resize:none; border:0; outline:0; background:transparent; color:var(--text); padding:10px 6px; font:inherit; }
    textarea::placeholder { color:#858b95; }
    .sr-only { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip:rect(0,0,0,0); white-space:nowrap; border:0; }
    @keyframes introWord { 0%{opacity:0; transform:translateY(8px)} 16%,46%{opacity:1; transform:translateY(0)} 72%,100%{opacity:0; transform:translateY(-10px)} }
    @keyframes introLine { 0%{opacity:0; transform:translateY(8px)} 18%,48%{opacity:1; transform:translateY(0)} 74%,100%{opacity:0; transform:translateY(-10px)} }
    @keyframes chatIn { from{opacity:0; transform:translateY(16px) scale(.985)} to{opacity:1; transform:translateY(0) scale(1)} }
    @media (prefers-reduced-motion: reduce) { .intro-word,.intro-line{display:none}.chat-shell{opacity:1; animation:none} }
    @media (max-width:640px) { .chat-shell{height:calc(100vh - 112px); border-radius:14px}.composer-inner{grid-template-columns:auto 1fr auto}.voice-button{display:none}.chat-status{display:none} }
  </style>
</head>
<body>
  <nav class="site-menu" id="siteMenu" aria-label="Site menu">
    <span class="menu-account-badge" id="menuAccountBadge" hidden></span>
    <a class="icon-button login-button" id="loginIcon" href="/login" aria-label="Login" title="Login">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"></path><path d="M10 17l5-5-5-5"></path><path d="M15 12H3"></path></svg>
    </a>
    <button class="icon-button account-button" type="button" id="accountButton" aria-label="Account" title="Account">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 21a8 8 0 0 0-16 0"></path><path d="M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"></path></svg>
    </button>
    <button class="icon-button" type="button" id="menuButton" aria-label="Open menu" aria-expanded="false" aria-controls="menuPanel">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"></path></svg>
    </button>
    <div class="menu-panel" id="menuPanel">
      <a href="/">Home</a>
      <a href="/observatory">Research</a>
      <a href="/observatory/enterprise">Enterprise</a>
      <a href="/build">Build</a>
      <a href="/community">Community</a>
      <a href="/community/questions">Questions</a>
      <button id="menuLogoutButton" class="menu-link-button" type="button" hidden>Logout</button>
    </div>
  </nav>
  <main>
    <section class="stage" aria-label="MIM interaction">
      <h1 class="intro-word">MIM</h1>
      <p class="intro-line"><span>A Collaborative Intelligence built to</span><span>observe, learn, reason, and explore with you.</span></p>
      <section class="chat-shell" aria-label="MIM chat">
        <header class="chat-head">
          <div class="identity"><span class="pulse" aria-hidden="true"></span><strong>MIM</strong></div>
          <div class="chat-status" id="chatStatus">ready</div>
        </header>
        <div class="messages" id="messages" aria-live="polite" aria-label="Conversation"></div>
        <form class="composer" id="composer">
          <label class="sr-only" for="messageInput">what would you like to collaborate on?</label>
          <div class="composer-inner">
            <button class="icon-button" type="button" id="attachButton" aria-label="Attach file" title="Attach file">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 12.5l-8.6 8.6a5 5 0 0 1-7.1-7.1l9.2-9.2a3.2 3.2 0 0 1 4.5 4.5l-9.1 9.1a1.5 1.5 0 0 1-2.1-2.1l8.3-8.3"></path></svg>
            </button>
            <textarea id="messageInput" rows="1" placeholder="what would you like to collaborate on?" autocomplete="off"></textarea>
            <button class="icon-button voice-button" type="button" aria-label="Start voice input" title="Start voice input">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3z"></path><path d="M19 11a7 7 0 0 1-14 0"></path><path d="M12 18v3"></path></svg>
            </button>
            <button class="icon-button" type="submit" id="sendButton" aria-label="Send message" title="Send message">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 2L11 13"></path><path d="M22 2l-7 20-4-9-9-4 20-7z"></path></svg>
            </button>
          </div>
        </form>
      </section>
      <section class="research-question-banner" id="researchQuestionBanner" aria-label="MIM research questions">
        <h2>MIM is wondering</h2>
        <div class="question-rail">
          <a class="question-card" href="/observatory/investigations/observation-driven-intelligence#researchConversation"><strong>Observation-Driven Intelligence</strong><span>What would prove that MIM understands better after a month?</span><small>Discuss with MIM</small></a>
          <a class="question-card" href="/observatory/investigations/relationship-based-learning#researchConversation"><strong>Relationship-Based Learning</strong><span>Which evidence should MIM inspect first?</span><small>Respond with evidence</small></a>
          <a class="question-card" href="/observatory/enterprise"><strong>Enterprise Observatory</strong><span>How could a private organization use MIM as a living knowledge system?</span><small>Explore Enterprise</small></a>
        </div>
      </section>
    </section>
  </main>
  <script>
    (function () {
      const menu = document.getElementById('siteMenu');
      const menuButton = document.getElementById('menuButton');
      const form = document.getElementById('composer');
      const input = document.getElementById('messageInput');
      const messages = document.getElementById('messages');
      const status = document.getElementById('chatStatus');
      const badge = document.getElementById('menuAccountBadge');
      const loginIcon = document.getElementById('loginIcon');
      const logoutButton = document.getElementById('menuLogoutButton');
      menuButton.addEventListener('click', () => {
        const open = !menu.classList.contains('open');
        menu.classList.toggle('open', open);
        menuButton.setAttribute('aria-expanded', String(open));
      });
      async function refreshAuth() {
        try {
          const response = await fetch('/projects/state', { credentials: 'same-origin', cache: 'no-store' });
          if (!response.ok) return;
          const state = await response.json();
          const account = state.account || {};
          const name = String(account.contact_name || account.company_name || account.email || '').trim();
          if (state.authenticated) {
            document.body.classList.add('auth-ready');
            if (badge) { badge.hidden = false; badge.textContent = name ? 'Hi ' + name.split(/\\s+/)[0] : 'Hi'; }
            if (loginIcon) loginIcon.hidden = true;
            if (logoutButton) logoutButton.hidden = false;
          }
        } catch (error) {}
      }
      if (logoutButton) {
        logoutButton.addEventListener('click', async () => {
          await fetch('/projects/logout', { method: 'POST', credentials: 'same-origin' });
          window.location.href = '/login?logged_out=1';
        });
      }
      function visitorId() {
        let value = localStorage.getItem('mim_public_visitor_id') || '';
        if (!value) {
          value = 'visitor-' + (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()));
          localStorage.setItem('mim_public_visitor_id', value);
        }
        return value;
      }
      function addMessage(role, text) {
        const item = document.createElement('div');
        item.className = 'message ' + role;
        item.textContent = String(text || '');
        messages.appendChild(item);
        messages.scrollTop = messages.scrollHeight;
      }
      function replyText(payload) {
        if (!payload) return '';
        const reply = payload.reply;
        if (typeof reply === 'string') return reply;
        if (reply && typeof reply.content === 'string') return reply.content;
        if (reply && typeof reply.text === 'string') return reply.text;
        if (typeof payload.message === 'string') return payload.message;
        if (payload.message && typeof payload.message.content === 'string') return payload.message.content;
        return '';
      }
      function autoSize() {
        input.style.height = 'auto';
        input.style.height = Math.min(input.scrollHeight, 180) + 'px';
      }
      input.addEventListener('input', autoSize);
      async function proactiveGreeting() {
        const key = 'mim_public_home_greeted_' + new Date().toISOString().slice(0, 10);
        if (sessionStorage.getItem(key)) return;
        sessionStorage.setItem(key, '1');
        status.textContent = 'greeting';
        try {
          const id = visitorId();
          const response = await fetch('/public/chat/message', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              message: 'A visitor just opened mimtod.com. Greet them once in a warm, concise way and invite them to ask about research, building, community, or Enterprise MIM.',
              visitor_id: id,
              session_key: id + '-mim',
              mode: 'mim',
              source: 'public_home_proactive_greeting',
              context: { event: 'new_homepage_session', greeting_policy: 'one_natural_greeting_per_session' }
            })
          });
          const payload = await response.json();
          const reply = replyText(payload);
          if (reply) addMessage('mim', reply);
        } catch (error) {
        } finally {
          status.textContent = 'ready';
        }
      }
      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        const text = (input.value || '').trim();
        if (!text) return;
        addMessage('user', text);
        input.value = '';
        autoSize();
        status.textContent = 'thinking';
        try {
          const id = visitorId();
          const response = await fetch('/public/chat/message', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: text, visitor_id: id, session_key: id + '-mim', mode: 'mim', source: 'public_home' })
          });
          const payload = await response.json();
          addMessage('mim', replyText(payload) || 'I received that, but I do not have a response yet.');
        } catch (error) {
          addMessage('mim', 'I could not reach the conversation service. Please try again in a moment.');
        } finally {
          status.textContent = 'ready';
        }
      });
      refreshAuth();
      window.setTimeout(proactiveGreeting, 8200);
    })();
  </script>
</body>
</html>
    """.strip()


def _template_slug(value: object) -> str:
    text = str(value or "").strip().lower()
    text = re.sub(r"[^a-z0-9]+", "_", text)
    return text.strip("_")


def _read_json_file(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return {}


def _published_template_apps() -> list[dict[str, Any]]:
    manifest = _read_json_file(Path.cwd() / USER_APP_GALLERY_MANIFEST)
    apps: list[dict[str, Any]] = []
    for item in manifest.get("apps", []):
        if not isinstance(item, dict):
            continue
        slug = _template_slug(item.get("slug"))
        if not slug:
            continue
        package_path = Path.cwd() / USER_APP_PUBLISHED_ROOT / slug / "package.manifest.json"
        package = _read_json_file(package_path)
        prototype_path = Path.cwd() / str(package.get("prototype_path") or "")
        prototype = _read_json_file(prototype_path) if prototype_path.name else {}
        app_name = str(item.get("app_name") or package.get("app_name") or slug.replace("_", " ").title())
        summary = str(prototype.get("summary") or "").strip()
        if not summary:
            summary = str(prototype.get("app_type") or package.get("style_preset") or "MIM-built app template").strip()
        one_line = summary
        if len(one_line) > 118:
            one_line = one_line[:115].rsplit(" ", 1)[0].rstrip(".,;:") + "..."
        apps.append(
            {
                "app_name": app_name,
                "slug": slug,
                "summary": summary,
                "one_line": one_line,
                "status": str(item.get("status") or package.get("status") or ""),
                "style_preset": str(item.get("style_preset") or package.get("style_preset") or ""),
                "app_type": str(prototype.get("app_type") or ""),
                "platform": str((prototype.get("classification") or {}).get("platform") or ""),
                "hero_url": f"/apps/templates/{slug}/asset/media/hero.png",
                "preview_url": f"/apps/templates/{slug}/preview",
                "demo_url": f"/apps/templates/{slug}/demo",
                "use_url": f"/login?template={urllib_parse.quote(slug)}",
                "favorite_url": f"/login?favorite_template={urllib_parse.quote(slug)}",
            }
        )
    return apps


def _template_gallery_style() -> str:
    return """
<style>
  .mim-template-gallery { margin: 46px auto; max-width: var(--max, 1180px); color: var(--text, #eef6ff); }
  .mim-template-gallery * { box-sizing: border-box; }
  .mim-template-gallery-head { display:flex; justify-content:space-between; gap:16px; align-items:end; margin:0 0 16px; }
  .mim-template-gallery h2 { margin:0; font-size:clamp(28px,4vw,44px); line-height:1; }
  .mim-template-gallery p { color:var(--muted, #9fb1c3); margin:6px 0 0; }
  .mim-template-rail { display:flex; gap:16px; overflow-x:auto; scroll-snap-type:x mandatory; padding:18px 4px 30px; }
  .mim-template-card { flex:0 0 300px; width:300px; min-height:300px; scroll-snap-align:center; border:1px solid var(--line, #263545); border-radius:14px; overflow:hidden; background:var(--panel, #101923); color:inherit; display:grid; grid-template-rows:168px 1fr; text-decoration:none; transition:transform .18s ease, border-color .18s ease, box-shadow .18s ease; }
  .mim-template-card:hover, .mim-template-card:focus { transform:scale(1.045); border-color:var(--accent, #67e8f9); box-shadow:0 20px 52px rgba(0,0,0,.32); outline:none; }
  .mim-template-card:nth-child(3n+2) { flex-basis:330px; width:330px; grid-template-rows:184px 1fr; }
  .mim-template-shot { position:relative; width:100%; height:100%; overflow:hidden; background:#172231; display:block; }
  .mim-template-shot::after { content:""; position:absolute; inset:0; box-shadow:inset 0 0 0 1px rgba(255,255,255,.08); pointer-events:none; }
  .mim-template-shot iframe { width:980px; height:620px; border:0; transform:scale(.31); transform-origin:0 0; pointer-events:none; background:white; display:block; }
  .mim-template-card:nth-child(3n+2) .mim-template-shot iframe { transform:scale(.34); }
  .mim-template-card-body { padding:14px; display:grid; gap:8px; align-content:start; }
  .mim-template-card strong { font-size:18px; line-height:1.15; }
  .mim-template-card span { color:var(--muted, #9fb1c3); font-size:13px; line-height:1.35; }
  .mim-template-actions { display:flex; gap:8px; flex-wrap:wrap; margin-top:10px; }
  .mim-template-actions a { border:1px solid var(--line, #263545); border-radius:999px; padding:8px 10px; color:inherit; text-decoration:none; font-weight:800; font-size:12px; background:rgba(255,255,255,.04); }
  .mim-template-actions a:first-child { background:var(--accent, #67e8f9); color:#051019; border-color:transparent; }
  .mim-template-open-all { white-space:nowrap; border:1px solid var(--line, #263545); border-radius:999px; padding:10px 13px; color:inherit; text-decoration:none; font-weight:800; background:rgba(255,255,255,.04); }
  @media (max-width:700px) {
    .mim-template-gallery { margin:32px 0; }
    .mim-template-gallery-head { align-items:flex-start; flex-direction:column; }
    .mim-template-card, .mim-template-card:nth-child(3n+2) { flex-basis:280px; width:280px; }
  }
</style>
"""


def _template_gallery_section(*, include_style: bool = True) -> str:
    apps = _published_template_apps()
    if not apps:
        return ""
    cards = []
    for app in apps:
        cards.append(
            f"""
            <article class="mim-template-card">
              <a href="{html.escape(app['demo_url'])}" target="_blank" rel="noopener" aria-label="Open {html.escape(app['app_name'])} demo">
                <span class="mim-template-shot">
                  <iframe src="{html.escape(app['preview_url'])}" loading="lazy" tabindex="-1" title="{html.escape(app['app_name'])} preview thumbnail"></iframe>
                </span>
              </a>
              <div class="mim-template-card-body">
                <strong>{html.escape(app['app_name'])}</strong>
                <span>{html.escape(app['one_line'])}</span>
                <div class="mim-template-actions">
                  <a href="{html.escape(app['demo_url'])}" target="_blank" rel="noopener">Open demo</a>
                  <a href="{html.escape(app['favorite_url'])}">Save favorite</a>
                  <a href="{html.escape(app['use_url'])}">Use template</a>
                </div>
              </div>
            </article>
            """
        )
    style = _template_gallery_style() if include_style else ""
    return (
        style
        + f"""
        <section class="mim-template-gallery" id="app-templates">
          <div class="mim-template-gallery-head">
            <div>
              <h2>MIM app templates</h2>
              <p>Preview MIM-built app demos, save favorites, then use one as a starting point in your account.</p>
            </div>
            <a class="mim-template-open-all" href="/apps/templates">View all templates</a>
          </div>
          <div class="mim-template-rail" aria-label="MIM app template demos">
            {''.join(cards)}
          </div>
        </section>
        """
    )


def _inject_template_gallery(html_text: str) -> str:
    section = _template_gallery_section(include_style=True)
    if not section:
        return html_text
    if "id=\"app-templates\"" in html_text:
        return html_text
    if "</main>" in html_text:
        return html_text.replace("</main>", section + "\n</main>", 1)
    if "</body>" in html_text:
        return html_text.replace("</body>", section + "\n</body>", 1)
    return html_text + section

PUBLIC_OPERATOR_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(
            r"\b(restart|reboot|shutdown|deploy|dispatch|approve|merge|commit|push|reset|wipe|delete|drop|truncate|kill|stop|start)\b.*\b(server|service|runtime|database|repo|repository|branch|task|objective|job|worker|system|host)\b",
            re.IGNORECASE,
        ),
        "Public chat cannot execute operator actions against the live system.",
    ),
    (
        re.compile(
            r"\b(sudo|systemctl|rm\s+-rf|git\s+reset|git\s+push|git\s+commit|kubectl|docker\s+(?:compose\s+)?(?:up|down|restart)|psql)\b",
            re.IGNORECASE,
        ),
        "Public chat does not run shell, git, deployment, or database commands.",
    ),
    (
        re.compile(r"(?:^|\s)/(?:mim|tod)\b", re.IGNORECASE),
        "Public chat does not accept operator-console commands.",
    ),
    (
        re.compile(r"\b(?:objective|task)[-\s#:]*\d+\b", re.IGNORECASE),
        "Public chat does not mutate tracked objectives or tasks.",
    ),
)

PUBLIC_URL_PATTERN = re.compile(r"https?://[^\s<>()\"']+", re.IGNORECASE)
LONDON_WEATHER_URL = (
    "https://api.open-meteo.com/v1/forecast?"
    + urllib_parse.urlencode(
        {
            "latitude": "51.5072",
            "longitude": "-0.1276",
            "current": "temperature_2m,weather_code,wind_speed_10m",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "timezone": "Europe/London",
            "forecast_days": "7",
        }
    )
)

NAME_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\bmy name is\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b", re.IGNORECASE),
    re.compile(r"\bi am\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b", re.IGNORECASE),
    re.compile(r"\bi'm\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2})\b", re.IGNORECASE),
)
GOAL_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\bmy goal is\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
    re.compile(r"\bi want to\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
    re.compile(r"\bi'm here to\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
    re.compile(r"\bi am here to\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
)
SPECIAL_DATE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\b(?:my\s+)?birthday\s+is\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
    re.compile(r"\b(?:my\s+)?anniversary\s+is\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
    re.compile(r"\b(?:my\s+)?deadline\s+is\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
)
INTEREST_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\bi (?:love|like|enjoy)\s+(.+?)(?:[.!?]|$)", re.IGNORECASE),
)


class PublicChatMessageRequest(BaseModel):
    message: str = Field(min_length=1)
    mode: Literal["mim", "tod"] = "mim"
    session_key: str = Field(min_length=1)
    context: dict[str, Any] | None = None


def _observatory_research_context_from_session_key(session_key: str) -> dict[str, Any]:
    normalized = str(session_key or "").strip()
    prefix = "observatory-"
    if not normalized.lower().startswith(prefix):
        return {}
    initiative_id = normalized[len(prefix) :].strip()
    if initiative_id.lower().startswith("research-"):
        initiative_id = initiative_id[len("research-") :].strip()
    if not initiative_id:
        return {}
    initiative = get_research_initiative(initiative_id)
    if not initiative:
        return {}
    return research_context_from_initiative(initiative)


def _observatory_research_context_from_message(message: str) -> dict[str, Any]:
    lowered = f" {str(message or '').strip().lower()} "
    if not lowered.strip():
        return {}
    for initiative in list_research_initiatives():
        initiative_id = str(initiative.get("id") or "").strip().lower()
        identity = initiative.get("identity") if isinstance(initiative.get("identity"), dict) else {}
        title = str(identity.get("title") or "").strip().lower()
        aliases = {initiative_id, title}
        for alias in aliases:
            if alias and f" {alias} " in lowered:
                return research_context_from_initiative(initiative)
    return {}


def _is_public_project_planning_request(message: str) -> bool:
    lowered = f" {str(message or '').strip().lower()} "
    if not lowered.strip():
        return False
    planning_markers = (
        " i need ",
        " i want ",
        " create ",
        " build ",
        " plan ",
        " blueprint ",
        " roadmap ",
        " project ",
        " proposal ",
        " automate ",
        " automation ",
        " workflow ",
    )
    work_markers = (
        " app ",
        " system ",
        " tool ",
        " platform ",
        " dashboard ",
        " facility ",
        " factory ",
        " manufacturing ",
        " manufacture ",
        " manufacturer ",
        " production ",
        " process ",
        " warehouse ",
        " line ",
    )
    return any(marker in lowered for marker in planning_markers) and any(marker in lowered for marker in work_markers)


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _compact_text(value: Any, limit: int = 240) -> str:
    cleaned = " ".join(str(value or "").strip().split())
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 3].rstrip() + "..."


def _has_accounting_receipt_app_context(text: str) -> bool:
    haystack = str(text or "").lower()
    return (
        ("receipt" in haystack or "recipts" in haystack)
        and any(term in haystack for term in ("accounting", "expense", "expenses", "payment", "payments", "subscription"))
    )


def _is_affirmative_continue(text: str) -> bool:
    normalized = re.sub(r"[^a-z0-9\s]+", " ", str(text or "").strip().lower())
    normalized = " ".join(normalized.split())
    return bool(
        re.search(
            r"^(yes|yeah|yep|please do|yes please|yes please do|do that|continue|go ahead|sounds good|ok|okay)[\s,.!]*$",
            normalized,
        )
    )


def _is_mim_self_reflection_request(text: str) -> bool:
    normalized = re.sub(r"[^a-z0-9\s]+", " ", str(text or "").lower())
    lowered = f" {normalized} "
    if not any(pronoun in lowered for pronoun in (" you ", " your ", " yourself ", " mim ")):
        return False
    reflection_markers = (
        "capabilit",
        "learn",
        "learning",
        "improve",
        "improvement",
        "increased",
        "weakness",
        "weaknesses",
        "strength",
        "different",
        "changed",
        "future",
        "month",
        "priority",
        "priorities",
        "think",
    )
    return any(marker in lowered for marker in reflection_markers)


def _accounting_receipt_platform_reply(*, recall_summary: str = "", greeting: str = "") -> str:
    recall_prefix = f"{recall_summary} " if recall_summary else ""
    return (
        f"{recall_prefix}{greeting}I think you're describing an expense intelligence platform, not just a basic accounting form. "
        "The first version should watch one or more receipt folders, pull data from PDFs or images, detect the vendor, date, total, category, payment source, and tax-relevant details, then turn that into searchable expense records and reports.\n\n"
        "I would plan it in four parts:\n"
        "1. Receipt capture: folder monitoring, PDF/image import, OCR, vendor/date/amount extraction, and duplicate detection.\n"
        "2. Expense tracking: payee, date, category, amount, payment type or account, tax classification, notes, and source file history.\n"
        "3. Reporting: spending by category, payee, month, account, recurring payment, and tax/export views.\n"
        "4. Smart actions: flag unused subscriptions, duplicate services, unusual spending increases, old autopay items, and possible savings opportunities.\n\n"
        "A few things I need to know next: will receipts come from email, scanned images, PDFs, mobile uploads, or all of those? Do you already use QuickBooks, Xero, spreadsheets, or nothing yet? Is this for one person, multiple users, or multiple companies? And should MIM only flag recommendations for review, or automatically suggest changes like canceling unused subscriptions?"
    )


def _normalize_mode(value: object) -> str:
    return "tod" if str(value or "").strip().lower() == "tod" else "mim"


def _normalize_session_key(value: object) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9._:-]+", "-", str(value or "").strip())
    normalized = normalized.strip("-._:")
    if not normalized:
        raise HTTPException(status_code=422, detail="session_key_required")
    return normalized[:120]


def _serialize_message(row: object) -> dict[str, object]:
    payload = to_interface_message_out(row)
    metadata = payload.get("metadata_json") if isinstance(payload.get("metadata_json"), dict) else {}
    return {
        "message_id": int(payload.get("message_id") or 0),
        "role": str(payload.get("role") or "mim").strip(),
        "direction": str(payload.get("direction") or "outbound").strip(),
        "content": str(payload.get("content") or "").strip(),
        "created_at": payload.get("created_at"),
        "message_type": str(metadata.get("message_type") or "message").strip(),
        "mode": str(metadata.get("mode") or "mim").strip(),
        "attachment": metadata.get("attachment") if isinstance(metadata.get("attachment"), dict) else None,
    }


def _dedupe_strings(values: list[str], *, limit: int = 6) -> list[str]:
    unique: list[str] = []
    seen: set[str] = set()
    for value in values:
        cleaned = _compact_text(value, 120)
        if not cleaned:
            continue
        lowered = cleaned.lower()
        if lowered in seen:
            continue
        seen.add(lowered)
        unique.append(cleaned)
        if len(unique) >= limit:
            break
    return unique


def _extract_profile_updates(message: str) -> dict[str, Any]:
    text = str(message or "").strip()
    updates: dict[str, Any] = {"goals": [], "special_dates": [], "interests": []}
    for pattern in NAME_PATTERNS:
        match = pattern.search(text)
        if match:
            updates["name"] = match.group(1).strip()
            break
    for pattern in GOAL_PATTERNS:
        match = pattern.search(text)
        if match:
            updates["goals"].append(match.group(1).strip())
    for pattern in SPECIAL_DATE_PATTERNS:
        match = pattern.search(text)
        if match:
            updates["special_dates"].append(match.group(1).strip())
    for pattern in INTEREST_PATTERNS:
        match = pattern.search(text)
        if match:
            updates["interests"].append(match.group(1).strip())
    updates["goals"] = _dedupe_strings(updates["goals"], limit=6)
    updates["special_dates"] = _dedupe_strings(updates["special_dates"], limit=6)
    updates["interests"] = _dedupe_strings(updates["interests"], limit=6)
    return updates


def _merge_profile(existing: dict[str, Any] | None, updates: dict[str, Any] | None) -> dict[str, Any]:
    current = existing.copy() if isinstance(existing, dict) else {}
    incoming = updates if isinstance(updates, dict) else {}
    if str(incoming.get("name") or "").strip():
        current["name"] = str(incoming.get("name") or "").strip()
    for key in ("goals", "special_dates", "interests"):
        merged = list(current.get(key) or []) + list(incoming.get(key) or [])
        current[key] = _dedupe_strings([str(item) for item in merged], limit=8)
    return current


def _public_command_block_reason(message: str) -> str:
    text = str(message or "").strip()
    if not text:
        return ""
    for pattern, reason in PUBLIC_OPERATOR_PATTERNS:
        if pattern.search(text):
            return reason
    return ""


def _client_ip(request: Request) -> str:
    forwarded = str(request.headers.get("x-forwarded-for") or "").strip()
    if forwarded:
        return forwarded.split(",", 1)[0].strip()
    if request.client and request.client.host:
        return str(request.client.host).strip()
    return "unknown"


def _ip_hash(ip_value: str) -> str:
    return hashlib.sha256(str(ip_value or "unknown").encode("utf-8")).hexdigest()[:16]


def _visitor_key_from_session(session_key: str, request: Request) -> tuple[str, str]:
    session_value = _normalize_session_key(session_key)
    base_key = re.sub(r"-(?:mim|tod)$", "", session_value, flags=re.IGNORECASE)
    ip_hash = _ip_hash(_client_ip(request))
    visitor_key = f"public:{base_key or ip_hash}"
    return visitor_key[:140], ip_hash


async def _latest_public_profile(*, visitor_key: str, ip_hash: str, db: AsyncSession) -> dict[str, Any]:
    rows = (
        await db.execute(
            select(MemoryEntry)
            .where(MemoryEntry.memory_class == "public_guest_profile")
            .order_by(MemoryEntry.id.desc())
            .limit(PUBLIC_PROFILE_SCAN_LIMIT)
        )
    ).scalars().all()
    for row in rows:
        metadata = row.metadata_json if isinstance(row.metadata_json, dict) else {}
        if metadata.get("visitor_key") == visitor_key or metadata.get("ip_hash") == ip_hash:
            profile = metadata.get("profile") if isinstance(metadata.get("profile"), dict) else {}
            return {
                **profile,
                "visit_count": int(metadata.get("visit_count") or profile.get("visit_count") or 0),
                "last_seen_at": str(metadata.get("last_seen_at") or profile.get("last_seen_at") or row.created_at),
            }
    return {"goals": [], "special_dates": [], "interests": [], "visit_count": 0, "last_seen_at": ""}


async def _remember_profile(
    *,
    visitor_key: str,
    ip_hash: str,
    profile: dict[str, Any],
    db: AsyncSession,
) -> None:
    entry = MemoryEntry(
        memory_class="public_guest_profile",
        content=json.dumps(profile, ensure_ascii=True, sort_keys=True),
        summary=_compact_text(
            f"Public guest profile for {profile.get('name') or visitor_key}: goals={', '.join(profile.get('goals') or []) or 'none'}; dates={', '.join(profile.get('special_dates') or []) or 'none'}",
            220,
        ),
        metadata_json={
            "visitor_key": visitor_key,
            "ip_hash": ip_hash,
            "profile": profile,
            "visit_count": int(profile.get("visit_count") or 0),
            "last_seen_at": str(profile.get("last_seen_at") or ""),
        },
    )
    db.add(entry)
    await db.flush()


async def _remember_turn(
    *,
    visitor_key: str,
    ip_hash: str,
    session_key: str,
    role: str,
    mode: str,
    content: str,
    db: AsyncSession,
    attachment: dict[str, Any] | None = None,
) -> None:
    entry = MemoryEntry(
        memory_class="public_guest_turn",
        content=str(content or ""),
        summary=_compact_text(content, 180),
        metadata_json={
            "visitor_key": visitor_key,
            "ip_hash": ip_hash,
            "session_key": session_key,
            "role": role,
            "mode": mode,
            "attachment": attachment if isinstance(attachment, dict) else {},
            "recorded_at": _utc_now_iso(),
        },
    )
    db.add(entry)
    await db.flush()


async def _ensure_public_session(
    *,
    session_key: str,
    visitor_key: str,
    ip_hash: str,
    mode: str,
    db: AsyncSession,
) -> tuple[object, bool]:
    existing = await get_interface_session(session_key=session_key, db=db)
    existing_context = existing.context_json if existing is not None and isinstance(existing.context_json, dict) else {}
    existing_metadata = existing.metadata_json if existing is not None and isinstance(existing.metadata_json, dict) else {}
    channel_context = _public_channel_context(mode)
    row = await upsert_interface_session(
        session_key=session_key,
        actor="visitor",
        source="public_chat",
        channel=str(channel_context["channel"]),
        status="active",
        context_json={
            **existing_context,
            "public_guest_chat": True,
            "visitor_key": visitor_key,
            "last_mode": mode,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
        },
        metadata_json={
            **existing_metadata,
            "public_guest_chat": True,
            "visitor_key": visitor_key,
            "ip_hash": ip_hash,
            "last_mode": mode,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
        },
        db=db,
    )
    return row, existing is None


def _profile_summary(profile: dict[str, Any]) -> str:
    if not isinstance(profile, dict):
        return ""
    parts: list[str] = []
    if str(profile.get("name") or "").strip():
        parts.append(f"I remember your name is {profile['name']}.")
    goals = [str(item) for item in profile.get("goals") or [] if str(item).strip()]
    if goals:
        parts.append(f"Your current goal is {goals[0]}.")
    dates = [str(item) for item in profile.get("special_dates") or [] if str(item).strip()]
    if dates:
        parts.append(f"A date you asked me to remember is {dates[0]}.")
    return " ".join(parts[:3])


def _next_learning_prompt(profile: dict[str, Any], mode: str) -> str:
    name = str(profile.get("name") or "").strip()
    goals = [str(item) for item in profile.get("goals") or [] if str(item).strip()]
    dates = [str(item) for item in profile.get("special_dates") or [] if str(item).strip()]
    if not name:
        return "What should I call you so I can remember you properly next time?"
    if not goals:
        return "What are you trying to make progress on right now?"
    if mode == "mim" and not dates:
        return "Are there any dates, milestones, or personal context points you want me to remember for future chats?"
    return "What is the next thing you want me to remember or help you explore?"


def _public_channel_context(mode: str) -> dict[str, object]:
    return public_channel_definition(_normalize_mode(mode))


def _extract_public_urls(text: str) -> list[str]:
    return [match.group(0).rstrip(".,);]") for match in PUBLIC_URL_PATTERN.finditer(str(text or ""))]


def _weather_code_label(code: object) -> str:
    try:
        value = int(code)
    except (TypeError, ValueError):
        return "mixed conditions"
    if value == 0:
        return "clear"
    if value in {1, 2}:
        return "mostly clear to partly cloudy"
    if value == 3:
        return "cloudy"
    if value in {45, 48}:
        return "foggy"
    if value in {51, 53, 55, 56, 57}:
        return "drizzly"
    if value in {61, 63, 65, 66, 67, 80, 81, 82}:
        return "rainy"
    if value in {71, 73, 75, 77, 85, 86}:
        return "snowy"
    if value in {95, 96, 99}:
        return "stormy"
    return "mixed conditions"


def _fetch_public_url_status(url: str) -> dict[str, object]:
    try:
        req = urllib_request.Request(
            url,
            headers={
                "User-Agent": "Mozilla/5.0 MIM public chat resource fetch",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            },
        )
        with urllib_request.urlopen(req, timeout=8) as response:
            body = response.read(120_000).decode("utf-8", "ignore")
        title_match = re.search(r"<title[^>]*>(.*?)</title>", body, re.IGNORECASE | re.DOTALL)
        title = " ".join(html.unescape(title_match.group(1)).split()) if title_match else ""
        return {
            "ok": True,
            "status": getattr(response, "status", 200),
            "title": title,
            "source_state": "accessible",
        }
    except urllib_error.HTTPError as exc:
        status = int(exc.code)
        source_state = "blocked_by_source" if status in {401, 403, 406, 429, 451} else "fetch_failed"
        return {"ok": False, "status": status, "error": f"HTTP {status}", "source_state": source_state}
    except Exception as exc:
        return {"ok": False, "status": 0, "error": type(exc).__name__, "source_state": "fetch_failed"}


def _duckduckgo_result_url(raw_href: str) -> str:
    parsed = urllib_parse.urlparse(html.unescape(str(raw_href or "")))
    if "duckduckgo.com" not in str(parsed.netloc or ""):
        return urllib_parse.urlunparse(parsed)
    query = urllib_parse.parse_qs(parsed.query)
    redirect = query.get("uddg") or query.get("u")
    if redirect:
        return str(redirect[0])
    return urllib_parse.urlunparse(parsed)


def _build_alternative_resource_query(message: str, blocked_url: str) -> str:
    cleaned = PUBLIC_URL_PATTERN.sub(" ", str(message or ""))
    cleaned = re.sub(
        r"\b(use this|resource|source|link|url|summarize|review|look at|let me know|please|from this|it)\b",
        " ",
        cleaned,
        flags=re.IGNORECASE,
    )
    cleaned = " ".join(cleaned.split())
    stop_words = {
        "and",
        "the",
        "for",
        "with",
        "this",
        "that",
        "you",
        "use",
        "resource",
        "source",
        "summarize",
        "review",
        "look",
        "let",
        "know",
        "please",
        "from",
        "link",
        "url",
        "into",
        "about",
    }
    cleaned_tokens = [
        token
        for token in re.findall(r"[a-zA-Z]{3,}", cleaned.lower())
        if token not in stop_words
    ]
    if len(cleaned_tokens) >= 2:
        return cleaned[:160]
    parsed = urllib_parse.urlparse(blocked_url)
    host = parsed.netloc.replace("www.", "")
    path_tokens = [
        token
        for token in re.findall(r"[a-zA-Z][a-zA-Z0-9-]{2,}", urllib_parse.unquote(parsed.path).lower())
        if token not in {"html", "aspx", "forecast", "weather-forecast"} and not any(char.isdigit() for char in token)
    ]
    if "weather" in parsed.path.lower() and "london" in parsed.path.lower():
        return "London weather forecast"
    if path_tokens:
        return " ".join(path_tokens[:8])
    return f"information related to {host}" if host else "alternative public source"


def _search_public_alternative_resources(query: str, *, limit: int = 3) -> list[dict[str, str]]:
    search_url = "https://duckduckgo.com/html/?" + urllib_parse.urlencode({"q": query})
    try:
        req = urllib_request.Request(
            search_url,
            headers={"User-Agent": "Mozilla/5.0 MIM public chat source search"},
        )
        with urllib_request.urlopen(req, timeout=8) as response:
            body = response.read(180_000).decode("utf-8", "ignore")
    except Exception:
        return []
    results: list[dict[str, str]] = []
    seen: set[str] = set()
    pattern = re.compile(
        r'<a[^>]+class="[^"]*result__a[^"]*"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
        re.IGNORECASE | re.DOTALL,
    )
    for href, title_html in pattern.findall(body):
        url = _duckduckgo_result_url(href)
        title = " ".join(re.sub(r"<[^>]+>", " ", html.unescape(title_html)).split())
        if not url or not title or url in seen:
            continue
        seen.add(url)
        results.append({"title": title[:140], "url": url})
        if len(results) >= limit:
            break
    return results


def _source_aware_url_note(url: str) -> str:
    fetched = _fetch_public_url_status(url)
    if fetched.get("ok"):
        title = str(fetched.get("title") or "the provided source").strip()
        return f"I opened the source you gave me ({title})."
    error = str(fetched.get("error") or "a fetch error").strip()
    if fetched.get("source_state") == "blocked_by_source":
        return (
            f"I tried the source you gave me, but that site rejected the server-side request with {error}. "
            "That means the source blocked automated access; it does not mean MIM has no web access."
        )
    return f"I tried the source you gave me, but I could not fetch it from this chat surface ({error})."


def _london_weather_summary() -> str:
    req = urllib_request.Request(
        LONDON_WEATHER_URL,
        headers={"User-Agent": "MIM public weather lookup"},
    )
    with urllib_request.urlopen(req, timeout=8) as response:
        payload = json.loads(response.read().decode("utf-8"))
    current = payload.get("current") if isinstance(payload.get("current"), dict) else {}
    daily = payload.get("daily") if isinstance(payload.get("daily"), dict) else {}
    days = daily.get("time") if isinstance(daily.get("time"), list) else []
    highs = daily.get("temperature_2m_max") if isinstance(daily.get("temperature_2m_max"), list) else []
    lows = daily.get("temperature_2m_min") if isinstance(daily.get("temperature_2m_min"), list) else []
    codes = daily.get("weather_code") if isinstance(daily.get("weather_code"), list) else []
    precip = (
        daily.get("precipitation_probability_max")
        if isinstance(daily.get("precipitation_probability_max"), list)
        else []
    )
    current_temp = current.get("temperature_2m")
    current_label = _weather_code_label(current.get("weather_code"))
    lines = []
    for index, day in enumerate(days[:7]):
        high = highs[index] if index < len(highs) else None
        low = lows[index] if index < len(lows) else None
        rain = precip[index] if index < len(precip) else None
        label = _weather_code_label(codes[index] if index < len(codes) else None)
        temp_text = f"{low:.0f}-{high:.0f}C" if isinstance(low, (int, float)) and isinstance(high, (int, float)) else "temps unavailable"
        rain_text = f", rain chance up to {rain}%" if rain is not None else ""
        lines.append(f"- {day}: {label}, {temp_text}{rain_text}")
    current_text = f"Right now London is about {current_temp}C with {current_label} conditions." if current_temp is not None else "Current London conditions are available from the forecast feed."
    return (
        f"{current_text}\n\nThis week's forecast from Open-Meteo:\n"
        + "\n".join(lines)
        + "\n\nSource: Open-Meteo live forecast API. AccuWeather may block direct server-side fetches from this chat surface."
    )


def _looks_like_public_weather_question(text: str) -> bool:
    lowered = str(text or "").lower()
    return "weather" in lowered and any(
        token in lowered
        for token in (
            "today",
            "now",
            "current",
            "currently",
            "like in",
            "what is",
            "what's",
        )
    )


def _public_customer_success_seed_reply(query: str) -> str:
    lowered = str(query or "").lower()
    build_markers = (
        "build",
        "create",
        "make",
        "i need",
        "i want",
    )
    product_markers = (
        "crm",
        "inventory",
        "scheduling",
        "booking",
        "mobile app",
        "app",
        "system",
        "dashboard",
        "tracker",
        "portal",
        "membership",
        "memberships",
    )
    if any(marker in lowered for marker in build_markers) and any(marker in lowered for marker in product_markers):
        return (
            "This is a build request. Start by naming the likely app foundation and first-version workflow, then give a practical next step before asking questions. "
            "A useful first version should usually include the core records, the main workflow, a simple dashboard or list view, and one action that proves the app works. "
            "The final reply must include that concrete foundation or prototype path. Ask no more than three critical questions, focused on users, workflow, and the first success screen."
        )

    if "commission" in lowered and any(marker in lowered for marker in ("automate", "automation", "total", "commissions")):
        return (
            "This is a commission automation problem. Lead with understanding: the biggest pain is usually collecting monthly reports from multiple carrier portals, validating totals, catching manual-entry or date-range mismatches, then uploading and reconciling payouts. "
            "Recommend automating report retrieval, validation, upload, and reconciliation before asking discovery questions. "
            "Ask one critical question first: does the customer currently download carrier reports manually?"
        )

    if any(marker in lowered for marker in ("automation plan", "automate", "automation")) and any(marker in lowered for marker in ("manufacture", "manufacturer", "manufacturing", "factory", "facility", "production line")):
        return (
            "This is a manufacturing automation planning request. Lead with a useful starter structure instead of saying evidence is unavailable. "
            "Name likely discovery lanes: current process map, bottlenecks, labor-heavy steps, material handling, machine tending, packaging, quality inspection, safety, downtime, throughput, and integration with existing controls. "
            "Then ask focused questions that help MIM learn the project: products made, process steps, current machines, volumes per shift, labor bottlenecks, quality problems, space constraints, budget/timeline, and whether the goal is robotics, conveyors, vision inspection, packaging automation, data collection, or all of them."
        )

    if any(marker in lowered for marker in ("reporting sucks", "employees don't follow up", "lose inventory", "losing inventory", "data everywhere", "too much time entering", "nobody knows", "month end")):
        return (
            "This is a business problem, not automatically a software request. Start by naming the likely root problem in plain language, then recommend a solution direction and explain why it helps. "
            "Only after that, suggest what kind of system or workflow could support it."
        )

    if any(marker in lowered for marker in ("failed", "wrong", "doesn't work", "does not work", "broken", "looks off", "does not match", "doesn't match", "missing", "can't log in", "cannot log in")):
        return (
            "This is a troubleshooting request. Start with the most likely causes and one immediate diagnostic or fix step. "
            "For totals or mismatched numbers, recommend comparing source rows, filters, date ranges, manual entries, and dashboard/report calculation paths before asking for more details."
        )

    if "which project is blocked" in lowered or "what project is blocked" in lowered:
        return (
            "This is a project-context retrieval request. If the active project context is unavailable, say that directly instead of guessing. "
            "Then explain the ideal answer shape: most recently active project, current blocker, owner, evidence, and next action. "
            "If context is available, summarize the blocked project in that shape without exposing internal artifact IDs."
        )

    if any(marker in lowered for marker in ("what should we work", "highest value", "prioritize", "what can move without me", "what is the one thing", "pick the next task", "if you were managing")):
        return (
            "This is project-manager mode. Choose a recommended next action first, give the reason and expected impact, then mention what evidence would prove movement. "
            "If the user asks what can move without them, interpret it as autonomous project progress rather than physical movement."
        )

    if any(marker in lowered for marker in ("how much", "cheapest", "cost", "mvp cost", "expensive", "avoid wasting money", "realistic range")):
        return (
            "This is a pricing or cost-control question. Give a realistic range framework or cost drivers, explain tradeoffs, and recommend the lowest-risk starting option such as a prototype or MVP scope."
        )

    if any(marker in lowered for marker in ("show me", "see a sample", "prototype", "mock up", "visual example", "quick demo")):
        return (
            "This is a demonstration request. Offer a prototype, sample screen, workbench path, or visual mockup direction first. Avoid a text-only explanation if the user needs to see the idea."
        )

    if any(marker in lowered for marker in ("can i try", "next step", "can you build this", "get started", "real project", "before i commit", "what would you need from me", "how much would this cost")):
        return (
            "This is conversion intent. Make the next step obvious without pressure: offer a sample, prototype path, lightweight blueprint, or project-start path depending on the ask. "
            "If cost is involved, explain that a small prototype/MVP is the lowest-risk first step and that final pricing depends on scope."
        )

    return ""


def _public_structural_reasoning_reply(
    query: str,
    recent_messages: list[dict[str, str]] | None = None,
) -> str:
    lowered = str(query or "").strip().lower()
    recent_text = " ".join(
        str(item.get("content") or "")
        for item in (recent_messages or [])
        if isinstance(item, dict)
    ).lower()

    if "commission" in lowered and any(token in lowered for token in ("automate", "automation", "commissions")):
        return (
            "There are several likely explanations behind commission automation: carrier report collection is slow, totals are being validated in different places, "
            "manual entries create mismatches, or payout rules are not tied cleanly to policy and rep records. The evidence I would need before choosing the path is one source statement, "
            "the current import result, and the dashboard/report total that should match. I would not call this solved until those records validate against each other. "
            "First move: audit one month end-to-end, compare source rows to stored commission rows, then choose the smallest automation path: retrieval, validation, upload, or reconciliation."
        )

    if re.search(r"\b(which|what)\s+project\s+is\s+blocked\b", lowered):
        return (
            "This could mean the most recent project, a project on your account dashboard, or a MIM/TOD internal training item. I do not have enough context in this public chat to identify the exact record. "
            "If you mean the most recently active project, the answer should be: project name, current blocker, owner, evidence, and next action. "
            "I would not call any project blocked or unblocked until I can verify the actual project record. First step: share the project name or open it from your account so I can compare the active record instead of guessing."
        )

    if "dashboard total" in lowered and "commission" in lowered:
        return (
            "There are multiple likely explanations: the dashboard may be reading a cached monthly aggregate, the commission search page may include manual rows the dashboard excludes, "
            "date filters may differ, or a carrier/manual-import path may write to a different table. The evidence boundary is the May source rows, search-page query, dashboard query, and any aggregate cache record. "
            "I would not call the smoke test a pass until the same policy rows and amounts trace through both views. First move: compare one mismatched policy and then audit the dashboard calculation path."
        )

    if "salesforce" in lowered and "simpler" in lowered:
        return (
            "That could mean several different products: a lightweight CRM, a sales pipeline board, a client follow-up tracker, or a reporting dashboard with fewer fields. "
            "The evidence we need before choosing is who uses it, what record matters most, and what action should happen every day. I would not build the whole thing before that is known. "
            "Recommended first path: prototype the smallest CRM with contacts, opportunities, follow-ups, and one dashboard; then compare it against the workflows you actually need."
        )

    if "tod" in lowered and "wrapper" in lowered and "completed" in lowered:
        return (
            "There are two different possibilities: the wrapper completed, or the real task completed. Those are not the same thing. Evidence must include inspected files, changed behavior or an intentional no-change proof, "
            "validation output, and a result artifact. I would not call it completed until that evidence exists. Next action: keep the task open, inspect the target file and validation result, then mark it passed, blocked, or split."
            " Choose the verification path before the closure path."
        )

    if "business feels messy" in lowered or "don't know exactly what i need" in lowered:
        return (
            "That could be a workflow problem, a reporting problem, a follow-up problem, or a data ownership problem. The evidence is where work gets delayed, duplicated, forgotten, or re-entered. "
            "I would not start by choosing software; I would start by mapping the messy points and comparing which one costs the most time or money. "
            "First move: list the three recurring tasks that feel most chaotic, then choose one path: organize, automate, report, or prototype."
        )

    if "actually build" in lowered or "just talking" in lowered:
        return (
            "There are two paths here: conversation only, or a real build workflow. In public chat I can shape the build brief and prototype path, but I cannot prove execution until a project workspace or generated artifact exists. "
            "I would not claim the app is built without evidence such as a blueprint, prototype, preview, diff, screenshot, or deployment record. "
            "Next action: choose a small first version, create the build brief, then move to a prototype so the result can be validated instead of just discussed."
        )

    if "what about in france" in lowered:
        temporal = _public_temporal_context()["reference_datetimes"]["france"]
        if any(token in recent_text for token in ("day", "date", "today", "time", "thursday", "friday", "saturday")):
            return (
                f"In France, it is {temporal['current_date']} at about {temporal['current_time']} {temporal['timezone']}. "
                "I am carrying forward the prior date/time question instead of asking you to restate it. If you meant laws, travel, pricing, or another France topic, say that topic and I will switch."
            )
        return (
            f"This could mean the day/date in France, a business rule in France, or a comparison with the prior topic. If you mean the current day/date, France is on {temporal['current_date']} at about {temporal['current_time']} {temporal['timezone']}. "
            "The evidence I have is only this message and the France timezone source, so I will not assume a different topic yet. Next action: say the topic if you meant something other than date or time."
        )

    if "smoke test" in lowered and "ui" in lowered and "broken" in lowered:
        return (
            "There are several likely explanations: the smoke test may cover the API but not the visible UI, the browser may be cached, deployment may be partial, or the test may validate the wrong state. "
            "The evidence boundary is the screenshot, browser console, network trace, deployed commit, and the exact smoke assertion. I would not call this a pass until UI evidence matches the test. "
            "First move: compare the failing screen to the smoke coverage, then add the smallest visual or route check that proves the UI path."
        )

    if "rewrite the whole image system" in lowered or ("rewrite" in lowered and "image system" in lowered):
        return (
            "That request could mean three paths: fix a specific provider bug, redesign the prompt/review workflow, or replace the whole image pipeline. The evidence is not enough to choose a rewrite yet. "
            "I would not accept a broad rewrite before an audit proves the current failure mode. Recommended first move: inspect the current image flow, split provider routing from review/escalation behavior, then patch the smallest failing slice."
        )

    return ""


def _public_chat_now() -> datetime:
    try:
        return datetime.now(ZoneInfo(PUBLIC_CHAT_DEFAULT_TIMEZONE))
    except Exception:
        return datetime.now(timezone.utc)


def _format_public_day_date(value: datetime) -> str:
    return f"{value.strftime('%A, %B')} {value.day}, {value.year}"


def _format_public_time(value: datetime) -> str:
    return f"{(value.strftime('%I').lstrip('0') or '0')}:{value.strftime('%M')} {value.strftime('%p')}"


def _public_zoned_temporal_context(zone_name: str, label: str) -> dict[str, str]:
    try:
        value = datetime.now(ZoneInfo(zone_name))
    except Exception:
        value = datetime.now(timezone.utc)
    timezone_label = value.tzname() or zone_name
    return {
        "label": label,
        "timezone": timezone_label,
        "zone": zone_name,
        "current_datetime_iso": value.isoformat(),
        "current_day": value.strftime("%A"),
        "current_date": _format_public_day_date(value),
        "current_time": _format_public_time(value),
    }


def _public_temporal_context() -> dict[str, Any]:
    now = _public_chat_now()
    timezone_label = now.tzname() or PUBLIC_CHAT_DEFAULT_TIMEZONE
    return {
        "current_datetime_iso": now.isoformat(),
        "current_day": now.strftime("%A"),
        "current_date": _format_public_day_date(now),
        "current_time": _format_public_time(now),
        "timezone": timezone_label,
        "reference_datetimes": {
            "utc": _public_zoned_temporal_context("UTC", "UTC"),
            "france": _public_zoned_temporal_context("Europe/Paris", "France"),
        },
    }


def _public_observatory_service_catalog() -> list[dict[str, str]]:
    return [
        {
            "name": "Research Observatory",
            "route": "/observatory",
            "summary": "A public and private research workspace where MIM tracks questions, investigations, evidence, confidence, and what changed.",
        },
        {
            "name": "Enterprise Observatory",
            "route": "/observatory/enterprise",
            "summary": "A private, branded organization workspace with tenant-separated research, documents, objectives, blockers, and executive summaries.",
        },
        {
            "name": "Enterprise Account Setup",
            "route": "/observatory/enterprise",
            "summary": "The onboarding path for organization identity, administrator ownership, tenant slug, branding, first use case, and initial roles.",
        },
        {
            "name": "Investigations",
            "route": "/observatory/investigations",
            "summary": "Living research records that preserve the current question, hypotheses, evidence, unknowns, confidence, and next experiment.",
        },
        {
            "name": "Documents and Evidence",
            "route": "/observatory/investigations",
            "summary": "Source material attached to investigations so MIM can distinguish evidence, inference, missing proof, and unsupported claims.",
        },
        {
            "name": "MIM Questions",
            "route": "/observatory",
            "summary": "Open questions MIM wants help exploring, including evidence gaps and next observations that could change confidence.",
        },
        {
            "name": "Research Conversation",
            "route": "/observatory/investigations/{slug}#researchConversation",
            "summary": "Conversation with MIM around a research record, including reframes, hypotheses, follow-up questions, and research evolution.",
        },
        {
            "name": "Projects and Objectives",
            "route": "/projects",
            "summary": "Work management surfaces where MIM frames priorities and TOD executes bounded tasks with validation evidence.",
        },
        {
            "name": "Users, Roles, and Invitations",
            "route": "/observatory/enterprise",
            "summary": "Enterprise administration for account owner, administrator setup, invitations, user roles, and future department access.",
        },
        {
            "name": "Integrations",
            "route": "/observatory/enterprise",
            "summary": "Planned and setup-dependent connections to tools such as cloud storage, calendars, email, CRM, APIs, and business systems.",
        },
    ]


def _public_observatory_services_summary() -> str:
    service_names = ", ".join(item["name"] for item in _public_observatory_service_catalog())
    return (
        "The Observatory services are: "
        f"{service_names}. "
        "The common pattern is conversation first, evidence second, and action only when the source material supports it."
    )


def _public_observatory_product_reply(message: str) -> str:
    query = " ".join(str(message or "").strip().split())
    lowered = query.lower()
    product_context_terms = (
        "observatory",
        "enterprise",
        "service",
        "account",
        "tenant",
        "studio",
        "mim",
        "tod",
        "research",
        "document",
        "pdf",
        "company polic",
        "quickbooks",
        "google drive",
        "slack",
        "zoom",
        "twilio",
        "crm",
        "calendar",
        "email",
        "webhook",
        "api",
    )
    if not any(term in lowered for term in product_context_terms):
        return ""
    product_question_signals = (
        "what is",
        "what's",
        "explain",
        "describe",
        "service",
        "benefit",
        "available",
        "use",
        "pricing",
        "price",
        "cost",
        "setup",
        "account",
        "login",
        "after login",
        "first login",
        "tenant",
        "isolation",
        "private",
        "upload",
        "document",
        "policies",
        "connect",
        "integration",
        "relationship",
        "differ",
        "replace",
        "private organization",
        "business",
        "company",
        "organization",
    )
    if not any(signal in lowered for signal in product_question_signals):
        return ""
    if any(term in lowered for term in ("quickbooks", "google drive", "slack", "zoom", "twilio", "crm", "calendar", "email", "webhook", "api", "integration", "connect")):
        return (
            "Observatory integrations are setup-dependent. The safe current model is to start with files, documents, links, and verified source material, then connect systems such as Google Drive, Microsoft, Slack, Zoom, Twilio, QuickBooks, CRM, email, calendars, or custom APIs only after credentials, permissions, and supported objects are confirmed. "
            "MIM should not silently claim a connection is live; it should say what is connected, what is pending, and what evidence it can actually read."
        )
    if any(term in lowered for term in ("how much", "pricing", "price", "cost", "costs", "monthly", "per month", "subscription")):
        return (
            "Enterprise pricing is not a fixed public one-size number yet. It depends on seats, private knowledge volume, connected systems, setup help, MIM/TOD execution support, security needs, and service level. "
            "The practical starting point is a scoped setup conversation: identify the organization size, first workspace, documents or systems to connect, admin owner, and whether MIM is only answering questions or also coordinating TOD execution. "
            "For a small pilot, MIM should recommend the smallest paid launch that proves value before expanding seats, integrations, or automation."
        )
    if "mim" in lowered and "tod" in lowered or "relationship" in lowered and ("mim" in lowered or "tod" in lowered):
        return (
            "MIM is the conversation and planning layer: it interprets goals, explains context, frames decisions, and decides what should happen next. "
            "TOD is the execution and verification layer: it handles bounded implementation work, validation, blocker evidence, and proof that work actually moved. "
            "In Observatory, MIM should explain and manage the work; TOD should change or validate systems only through bounded tasks with evidence."
        )
    if any(term in lowered for term in ("tenant", "isolation", "multiple companies", "separation", "private")):
        return (
            "Tenant isolation means an Enterprise account has its own organization context before Observatory content is selected. "
            "Public research should not leak into a private enterprise workspace unless the user intentionally opens public discovery, and one company's documents, users, objectives, and conversations should stay separate from another company's workspace."
        )
    if any(term in lowered for term in ("first login", "after login", "login", "setup", "create", "administrator", "admin", "invite", "logo", "branding", "subdomain")):
        return (
            "Enterprise setup starts by identifying the organization, account owner or administrator, tenant slug, logo or branding, first use case, and initial roles. "
            "After login, the user should land in a clean Enterprise Observatory with no unrelated public research, then MIM should guide setup by asking only for missing information and saving it to the enterprise account for future use."
        )
    if any(term in lowered for term in ("document", "pdf", "upload", "company polic", "knowledge", "source", "evidence")):
        return (
            "Observatory can use uploaded documents and source material as evidence for research and enterprise knowledge. "
            "MIM should answer from the documents it can actually inspect, name uncertainty when evidence is missing, preserve source boundaries, and avoid treating guesses as company policy."
        )
    if any(term in lowered for term in ("service", "services", "available", "describe all", "what can", "include")):
        return _public_observatory_services_summary()
    if "studio" in lowered or "project management" in lowered or "replace" in lowered:
        return (
            "Observatory is the research, knowledge, and enterprise memory layer. Studio is the operator and training workspace for MIM/TOD development and operations. "
            "Observatory can support project management by preserving decisions, objectives, blockers, documents, and executive summaries, but it should not claim to replace a team's existing project-management system until the needed workflow, integrations, and permissions are proven."
        )
    if "enterprise" in lowered:
        return (
            "An Enterprise account is a private, branded MIM workspace for an organization. "
            "Instead of mixing your team into the public Research Observatory, the company gets its own clean Observatory where MIM can help organize documents, investigations, objectives, decisions, blockers, and executive summaries. "
            "The practical benefit is shared organizational memory: MIM can help people understand what is happening, what changed, what needs attention, and what should happen next without scattering that knowledge across email, files, and meetings. "
            "Setup starts with the organization name, administrator, tenant slug, logo or brand details, first use case, and user roles. Pricing depends on seats, private knowledge volume, connected systems, MIM/TOD execution support, and service level."
        )
    if "observatory" in lowered or "research" in lowered:
        return (
            "Observatory is MIM's research and organizational-memory workspace. "
            "It is designed to keep questions, evidence, hypotheses, confidence, unknowns, documents, conversations, and next actions together so a discussion can become learning instead of disappearing after one answer. "
            "For public users it supports shared research exploration; for Enterprise users it becomes a private tenant workspace for company knowledge, objectives, blockers, and executive summaries."
        )
    return ""


def _public_enterprise_product_reply(message: str) -> str:
    return _public_observatory_product_reply(message)


def _public_direct_conversational_reply(
    *,
    message: str,
    mode: str,
    profile: dict[str, Any],
    recall_summary: str,
    recent_messages: list[dict[str, str]] | None = None,
) -> str:
    normalized_mode = _normalize_mode(mode)
    query = " ".join(str(message or "").strip().split())
    lowered = query.lower()
    recall_prefix = f"{recall_summary} " if recall_summary else ""
    name = str(profile.get("name") or "").strip()
    urls = _extract_public_urls(query)
    recent_messages = recent_messages if isinstance(recent_messages, list) else []
    profile_goal_text = " ".join(str(item) for item in profile.get("goals") or [] if str(item).strip())
    recent_text = " ".join(
        [
            *(str(item.get("content") or "") for item in recent_messages[-8:] if isinstance(item, dict)),
            str(recall_summary or ""),
            profile_goal_text,
        ]
    ).lower()

    if normalized_mode == "mim" and re.search(
        r"\b(what\s+day(?:\s+of\s+the\s+week)?\s+is\s+it|what(?:'s|\s+is)\s+today(?:'s)?\s+date|what\s+date\s+is\s+it)\b",
        lowered,
    ):
        temporal = _public_temporal_context()
        return f"{recall_prefix}Today is {temporal['current_date']}."

    if normalized_mode == "mim":
        enterprise_reply = _public_enterprise_product_reply(query)
        if enterprise_reply:
            return f"{recall_prefix}{enterprise_reply}"

    if normalized_mode == "mim" and re.search(r"\bwhat\s+time\s+is\s+it\b|\bwhat(?:'s|\s+is)\s+the\s+time\b", lowered):
        temporal = _public_temporal_context()
        return f"{recall_prefix}It is about {temporal['current_time']} {temporal['timezone']}."

    if normalized_mode == "mim" and _has_accounting_receipt_app_context(f"{lowered} {recent_text}"):
        if _is_affirmative_continue(query) or len(query.split()) > 8:
            greeting = "Hi Dave. " if name.lower() == "dave" or "dave" in recent_text else ""
            return _accounting_receipt_platform_reply(recall_summary=recall_summary, greeting=greeting)

    if normalized_mode == "mim" and (
        re.search(r"\b(can|could|would|will)\s+(ai|mim)\s+help\b.*\bbusiness\b|\b(ai|mim)\s+help\s+my\s+business\b", lowered)
        or ("ai" in lowered and "business" in lowered and any(term in lowered for term in ("help me decide", "help me figure", "can you help", "could you help")))
    ):
        return (
            f"{recall_prefix}Yes. The best starting point is not a tool list; it is finding the workflows where your business repeats manual work. "
            "AI usually helps first with follow-up, intake, reports, document review, scheduling, customer questions, data cleanup, or reconciling numbers. "
            "I would pick one painful process, estimate how often it happens, identify the information needed to do it well, and decide whether AI should automate it, assist a person, or simply organize the work better. "
            "A good first step is to tell me the one task your team repeats every week that still feels too slow or error-prone."
        )

    if normalized_mode == "mim":
        structural_reply = _public_structural_reasoning_reply(query, recent_messages)
        if structural_reply:
            return f"{recall_prefix}{structural_reply}"

    if normalized_mode == "mim" and _is_affirmative_continue(query):
        return (
            f"{recall_prefix}Absolutely. I'll continue the project-planning flow instead of restarting the conversation. "
            "Next I would turn the idea into a first-version plan: define the main workflow, identify the data that needs to be captured, map the reports and smart actions, list the integrations or file sources, and then ask only the few questions needed to remove uncertainty. "
            "For an app idea like this, the next useful output is a simple blueprint with: capture/import, data model, user workflow, reports, automation rules, risks, and open questions."
        )

    if normalized_mode == "mim" and re.search(r"\b(which|what)\s+project\s+is\s+blocked\b", lowered):
        return (
            f"{recall_prefix}I don't currently have enough project context in this public chat to identify which specific project you mean. "
            "If you mean your most recently active project, I would answer in this shape: project name, current blocker, owner, evidence, and next action. "
            "Share the project name or open it from your account and I can narrow this to the actual blocked item."
        )

    if _looks_like_public_weather_question(query):
        resource_note = ""
        if urls:
            resource_note = _source_aware_url_note(urls[0]) + " "
        if "london" in lowered:
            try:
                return f"{recall_prefix}{resource_note}{_london_weather_summary()}"
            except Exception:
                return (
                    f"{recall_prefix}{resource_note}I could not retrieve a live London forecast from the available weather path right now. "
                    "If you paste the forecast text, I can summarize it directly."
                )
        return (
            f"{recall_prefix}{resource_note}I need the location before I can look up a useful forecast. "
            "Tell me the city or paste the forecast text and I will summarize it directly."
        )

    if urls and any(token in lowered for token in ("use this resource", "use this source", "summarize", "review this", "look at this", "from this link", "this url")):
        source_note = _source_aware_url_note(urls[0])
        if "opened the source" in source_note:
            return (
                f"{recall_prefix}{source_note} I can use the page title and accessible page text from this public chat path, "
                "but for a precise summary, paste the relevant section if the page relies on scripts or personalized content."
            )
        alternatives = _search_public_alternative_resources(
            _build_alternative_resource_query(query, urls[0]),
            limit=3,
        )
        if alternatives:
            lines = "\n".join(f"- {item['title']}: {item['url']}" for item in alternatives)
            return (
                f"{recall_prefix}{source_note} I searched for alternative public resources and found:\n"
                f"{lines}\n\n"
                "I have not treated those alternatives as equivalent to the original source yet; paste the specific text you want summarized if exact-source fidelity matters."
            )
        return (
            f"{recall_prefix}{source_note} If you paste the relevant text here, I can summarize or analyze it directly without guessing."
        )

    if re.search(r"\byou (did not|didn't) answer\b|\bstill not\b|\banswer the question\b", lowered):
        return (
            f"{recall_prefix}You're right. I missed the actual question and repeated the channel intro. "
            "Ask it again and I will answer directly first, then add any limitation or evidence note only if needed."
        )

    if re.search(r"\bhow are you(?: doing)?(?: today)?\??$", lowered):
        return (
            f"{recall_prefix}I'm doing well, Dave." if name.lower() == "dave"
            else f"{recall_prefix}I'm doing well. How are you doing?"
        )

    if re.search(r"\b(i am|i'm|my name is|call me)\s+dave\b", lowered):
        return "Nice to meet you, Dave. I'll remember your name for this public chat."

    if normalized_mode == "mim" and query.endswith("?") and len(query.split()) <= 18:
        if any(starter in lowered for starter in ("what is", "what's", "who is", "where is", "when is", "how do", "how can", "why")):
            return ""

    return ""


def _build_public_fallback_reply(
    *,
    message: str,
    mode: str,
    profile: dict[str, Any],
    recall_summary: str,
    recent_messages: list[dict[str, str]] | None = None,
    block_reason: str = "",
    upload_summary: str = "",
) -> str:
    normalized_mode = _normalize_mode(mode)
    channel_context = _public_channel_context(normalized_mode)
    query = " ".join(str(message or "").strip().split())
    lowered = query.lower()
    asks_about_mim = "mim" in lowered
    asks_about_tod = "tod" in lowered
    greeting = any(token in lowered for token in ("hello", "hi", "hey", "good morning", "good evening"))
    identity_prompt = any(
        token in lowered
        for token in (
            "who are you",
            "what are you",
            "what is mim",
            "what is tod",
            "what is mim and tod",
            "what are mim and tod",
            "what makes you different",
            "your mission",
            "about mim",
        )
    )
    code_prompt = any(token in lowered for token in ("code", "bug", "debug", "function", "python", "javascript", "typescript", "refactor", "test"))
    image_prompt = any(token in lowered for token in ("image", "logo", "illustration", "poster", "render", "visual"))
    content_prompt = any(token in lowered for token in ("write", "draft", "outline", "story", "post", "email", "content"))
    resource_prompt = any(token in lowered for token in ("resource", "website", "web", "article", "docs", "reference"))

    if block_reason:
        return (
            f"{block_reason} I can still help in conversation mode by planning the work, drafting code, reviewing pasted text, or explaining the next safe steps without touching the live MIM or TOD consoles. "
            f"{_next_learning_prompt(profile, normalized_mode)}"
        )

    if upload_summary:
        base = (
            f"I pulled in your file. {upload_summary} "
            "I can review structure, explain what it does, point out risks, or help you turn it into a sharper draft without touching the live repo."
        )
        return f"{base} {_next_learning_prompt(profile, normalized_mode)}"

    direct_reply = _public_direct_conversational_reply(
        message=query,
        mode=normalized_mode,
        profile=profile,
        recall_summary=recall_summary,
        recent_messages=recent_messages,
    )
    if direct_reply:
        return direct_reply

    if normalized_mode == "mim":
        if identity_prompt:
            recall_prefix = f"{recall_summary} " if recall_summary else ""
            if asks_about_mim and asks_about_tod:
                return (
                    f"{recall_prefix}I'm MIM. I help people talk through ideas, business problems, app concepts, and practical next steps. "
                    "TOD is the verification side: when work is actually executed, TOD helps check what changed and whether it worked. "
                    "In this public chat, I can answer questions, explore options, shape a project, or explain what I can and cannot know from the current conversation."
                )
            if asks_about_tod and not asks_about_mim:
                return (
                    f"{recall_prefix}TOD is the separate execution-facing application and channel behind the system. {tod_public_identity_summary()} "
                    f"{public_system_identity_summary()}"
                )
            return (
                f"{recall_prefix}I'm MIM, an assistant built to help people think through ideas, business problems, projects, and useful next steps. "
                "I can chat normally, answer simple questions, help shape software ideas, and work from the context you give me. "
                "If I do not have enough evidence for something, I should say that instead of pretending."
            )
        if greeting:
            welcome = "Welcome back. " if int(profile.get("visit_count") or 0) > 1 else ""
            recall_prefix = f"{recall_summary} " if recall_summary else ""
            return (
                f"{welcome}{recall_prefix}You're talking directly to the MIM channel. I'm ready for general chat, planning, content work, idea exploration, and follow-up conversation. "
                f"{_next_learning_prompt(profile, normalized_mode)}"
            )
        if image_prompt:
            return (
                "I can help you shape image prompts, visual direction, brand language, scene composition, and iteration notes. "
                "If you tell me the subject, mood, style, and constraints, I'll turn that into a cleaner creative brief. "
                f"{_next_learning_prompt(profile, normalized_mode)}"
            )
        if content_prompt:
            return (
                "I can draft content in your tone, tighten an outline, generate options, or rewrite a rough idea into something publishable. "
                "Tell me the audience, goal, tone, and length you want. "
                f"{_next_learning_prompt(profile, normalized_mode)}"
            )
        if resource_prompt:
            return (
                "I can help you compare resources, frame better search angles, or analyze excerpts and links you paste here. "
                "If you want a specific source evaluated, send the URL or upload the text and I'll work from that material directly. "
                f"{_next_learning_prompt(profile, normalized_mode)}"
            )
        customer_seed = _public_customer_success_seed_reply(query)
        if customer_seed:
            recall_prefix = f"{recall_summary} " if recall_summary else ""
            return f"{recall_prefix}{customer_seed}"
        recall_prefix = f"{recall_summary} " if recall_summary else ""
        return (
            f"{recall_prefix}I can chat normally, answer simple questions, explain MIM and TOD, explore ideas, or help turn a loose thought into a next step. "
            f"Ask what you're curious about and I'll answer directly first. {_next_learning_prompt(profile, normalized_mode)}"
        )

    if code_prompt:
        recall_prefix = f"{recall_summary} " if recall_summary else ""
        return (
            f"{recall_prefix}You're talking directly to TOD, the execution-facing channel, so I can help with architecture, debugging, refactors, tests, APIs, code review, and evidence-backed implementation reasoning. "
            "Paste the code, error, or requirement and I'll reason through it without touching the live repository or execution lanes. "
            f"{_next_learning_prompt(profile, normalized_mode)}"
        )
    if identity_prompt:
        return (
            f"TOD is a separate execution-facing application and public channel behind the system. {tod_public_identity_summary()} "
            f"{public_system_identity_summary()}"
        )
    if greeting:
        welcome = "Welcome back. " if int(profile.get("visit_count") or 0) > 1 else ""
        recall_prefix = f"{recall_summary} " if recall_summary else ""
        return (
            f"{welcome}{recall_prefix}You're talking directly to TOD. I answer from the execution, validation, and evidence side of the system. "
            f"Ask about system state, what ran, what failed, what changed, or bring code and implementation questions. {_next_learning_prompt(profile, normalized_mode)}"
        )
    return (
        "This is the TOD channel, so I answer from the execution and verification side: what changed, what ran, what failed, what evidence exists, and how an implementation should behave. "
        "I can also help with programming conversation, debugging, code explanation, tradeoffs, and implementation planning without touching the live repo. "
        f"{_next_learning_prompt(profile, normalized_mode)}"
    )


async def _compose_public_reply(
    *,
    message: str,
    mode: str,
    profile: dict[str, Any],
    recall_summary: str,
    recent_messages: list[dict[str, str]] | None = None,
    block_reason: str = "",
    upload_summary: str = "",
) -> str:
    fallback_reply = _build_public_fallback_reply(
        message=message,
        mode=mode,
        profile=profile,
        recall_summary=recall_summary,
        recent_messages=recent_messages or [],
        block_reason=block_reason,
        upload_summary=upload_summary,
    )
    if (
        _normalize_mode(mode) == "mim"
        and _is_affirmative_continue(message)
        and "continue the project-planning flow" in fallback_reply
    ):
        return _compact_text(fallback_reply, 1400)
    structural_reply = ""
    if _normalize_mode(mode) == "mim":
        structural_reply = _public_structural_reasoning_reply(
            " ".join(str(message or "").strip().split()),
            recent_messages or [],
        )
    if structural_reply and structural_reply in fallback_reply:
        return _compact_text(fallback_reply, 1400)
    channel_context = _public_channel_context(mode)
    counterpart_context = _public_channel_context("mim" if _normalize_mode(mode) == "tod" else "tod")
    temporal_context = _public_temporal_context()
    context = {
        "assistant_name": str(channel_context["application_name"]),
        "mode": _normalize_mode(mode),
        "public_guest_chat": True,
        "response_mode": "conversational_confident",
        "conversation_policy": (
            "Answer ordinary conversation and basic factual questions directly. "
            "Do not refuse, deflect, or repeat channel positioning just because the user is casually chatting."
        ),
        "language_policy": (
            "Use the same language as the visitor's latest message unless they ask to translate or switch languages."
        ),
        "customer_success_policy": (
            "For customer-facing product conversations, lead with a useful answer or foundation before discovery. "
            "For build requests, identify the app/workflow, give a first-version blueprint or prototype path, then ask no more than three critical questions. "
            "Do not turn build requests into 'what features do you want?' before providing a concrete foundation. "
            "For business pain, name the likely root problem and solution direction before suggesting software. "
            "For troubleshooting, provide a likely cause and next diagnostic/fix step before asking for details. "
            "For prioritization, choose a recommendation with rationale and expected impact instead of only reporting status."
        ),
        "structural_reasoning_policy": (
            "When the request is broad, ambiguous, high-impact, conflicting, or system-changing, do not force a tidy answer. "
            "Name two or more plausible interpretations or likely explanations, state what evidence is known or missing, track uncertainty explicitly with phrases like 'if you mean' or 'not enough context', "
            "avoid declaring completion before validation, and recommend the smallest safe next action such as audit, compare, prototype, inspect, or trace."
        ),
        "current_datetime": temporal_context,
        "identity": str(channel_context["identity"]),
        "assistant_identity": str(channel_context["identity"]),
        "assistant_application": str(channel_context["application_name"]),
        "assistant_channel": str(channel_context["channel"]),
        "assistant_scope": str(channel_context["scope"]),
        "assistant_capabilities": str(channel_context["capabilities"]),
        "counterpart_identity": str(counterpart_context["identity"]),
        "counterpart_application": str(counterpart_context["application_name"]),
        "counterpart_channel": str(counterpart_context["channel"]),
        "system_identity": public_system_identity_summary(),
        "visitor_profile": profile,
        "recall_summary": recall_summary,
        "recent_conversation": recent_messages or [],
        "guardrails": [
            "no operator commands",
            "no live system execution",
            "conversation and advisory mode only",
        ],
        "upload_summary": upload_summary,
    }
    reply_contract = await compose_expert_communication_reply(
        user_input=message,
        context=context,
        fallback_reply=fallback_reply,
    )
    return _compact_text(reply_contract.reply_text or fallback_reply, 1400)


async def _build_public_state(
    *,
    session_key: str,
    mode: str,
    request: Request,
    db: AsyncSession,
) -> dict[str, Any]:
    normalized_session = _normalize_session_key(session_key)
    normalized_mode = _normalize_mode(mode)
    visitor_key, ip_hash = _visitor_key_from_session(normalized_session, request)
    profile = await _latest_public_profile(visitor_key=visitor_key, ip_hash=ip_hash, db=db)
    session, is_new = await _ensure_public_session(
        session_key=normalized_session,
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        mode=normalized_mode,
        db=db,
    )
    if is_new:
        updated_profile = {
            **profile,
            "visit_count": int(profile.get("visit_count") or 0) + 1,
            "last_seen_at": _utc_now_iso(),
        }
        profile = _merge_profile(profile, updated_profile)
        await _remember_profile(visitor_key=visitor_key, ip_hash=ip_hash, profile=profile, db=db)
    _, rows = await list_interface_messages(session_key=normalized_session, limit=PUBLIC_CHAT_MESSAGE_LIMIT, db=db)
    recall_summary = _profile_summary(profile)
    return {
        "generated_at": _utc_now_iso(),
        "session": to_interface_session_out(session),
        "messages": [_serialize_message(row) for row in reversed(rows)],
        "mode": normalized_mode,
        "visitor": {
            "visitor_key": visitor_key,
            "visit_count": int(profile.get("visit_count") or 0),
            "name": str(profile.get("name") or "").strip(),
            "goals": [str(item) for item in profile.get("goals") or [] if str(item).strip()],
            "special_dates": [str(item) for item in profile.get("special_dates") or [] if str(item).strip()],
            "memory_summary": recall_summary,
            "ip_hash": ip_hash,
        },
        "guardrails": {
            "commands_blocked": True,
            "live_execution_blocked": True,
            "public_modes": ["mim", "tod"],
        },
    }


def _upload_text_summary(filename: str, content_type: str, text: str) -> str:
    lines = [line.strip() for line in str(text or "").splitlines() if line.strip()]
    first_line = _compact_text(lines[0], 120) if lines else "No non-empty lines detected."
    return _compact_text(
        f"{filename} ({content_type or 'text'}) looks text-based. First meaningful line: {first_line}",
        220,
    )


@router.get(PUBLIC_PRIVACY_POLICY_PATH, response_class=HTMLResponse)
@router.get("/privacy-policy", response_class=HTMLResponse)
async def public_privacy_policy() -> HTMLResponse:
        title = html.escape(f"Privacy Policy | {settings.app_name}")
        return HTMLResponse(
                f"""
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <style>
        :root {{
            --bg: #f5efe6;
            --ink: #102234;
            --muted: #5f6c76;
            --panel: rgba(255,255,255,0.90);
            --line: rgba(16,34,52,0.10);
            --accent: #0b6b74;
            --shadow: 0 24px 64px rgba(16,34,52,0.14);
            --display: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", serif;
            --body: "IBM Plex Sans", "Avenir Next", "Segoe UI", sans-serif;
        }}
        * {{ box-sizing: border-box; }}
        body {{
            margin: 0;
            min-height: 100vh;
            color: var(--ink);
            font-family: var(--body);
            background:
                radial-gradient(circle at top left, rgba(11,107,116,0.18), transparent 30%),
                radial-gradient(circle at bottom right, rgba(180,83,9,0.12), transparent 24%),
                linear-gradient(180deg, #fbf8f2 0%, var(--bg) 100%);
            padding: 24px;
        }}
        .page {{
            max-width: 920px;
            margin: 0 auto;
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 28px;
            box-shadow: var(--shadow);
            overflow: hidden;
        }}
        .hero {{
            padding: 28px 28px 20px;
            background: linear-gradient(135deg, rgba(11,107,116,0.10), rgba(255,255,255,0.72));
            border-bottom: 1px solid var(--line);
        }}
        .eyebrow {{
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.14em;
            color: var(--accent);
            font-weight: 800;
        }}
        h1 {{
            margin: 10px 0 8px;
            font-family: var(--display);
            font-size: clamp(30px, 6vw, 50px);
            line-height: 0.95;
        }}
        .intro {{ color: var(--muted); font-size: 15px; line-height: 1.55; max-width: 720px; }}
        .content {{ padding: 24px 28px 28px; display: grid; gap: 22px; }}
        section {{ display: grid; gap: 8px; }}
        h2 {{ margin: 0; font-size: 18px; }}
        p, li {{ margin: 0; color: var(--muted); font-size: 14px; line-height: 1.6; }}
        ul {{ margin: 0; padding-left: 20px; display: grid; gap: 8px; }}
        a {{ color: var(--accent); font-weight: 700; }}
        .back-link {{
            display: inline-flex;
            align-items: center;
            gap: 8px;
            text-decoration: none;
            border: 1px solid var(--line);
            border-radius: 999px;
            padding: 10px 14px;
            background: rgba(255,255,255,0.82);
            width: fit-content;
        }}
    </style>
</head>
<body>
    <main class="page">
        <header class="hero">
            <div class="eyebrow">Public Policy</div>
            <h1>Privacy Policy</h1>
            <div class="intro">This policy applies to the public MIM and TOD chat surface at todmim.com and mimtod.com. Public chats are recorded so the service can preserve conversation continuity, improve responses, and review safety behavior.</div>
        </header>
        <div class="content">
            <a class="back-link" href="/">Return to Public Chat</a>

            <section>
                <h2>What We Collect</h2>
                <p>We collect the messages you send through the public chat, files you upload for review, lightweight session identifiers stored in your browser, and limited technical metadata such as timestamps and network-derived identifiers used to keep the service stable and resistant to abuse.</p>
            </section>

            <section>
                <h2>Why We Record Chats</h2>
                <p>Public chats are recorded to improve the service, preserve follow-up context, evaluate quality, and review safety issues. This includes helping MIM remember information you intentionally share for future conversations on the same public surface.</p>
            </section>

            <section>
                <h2>How We Use Information</h2>
                <ul>
                    <li>To respond to your messages and uploaded content.</li>
                    <li>To maintain visitor memory and conversation continuity.</li>
                    <li>To analyze failures, misuse, and safety issues.</li>
                    <li>To improve product quality, prompts, routing, and moderation.</li>
                </ul>
            </section>

            <section>
                <h2>Public Surface Limits</h2>
                <p>The public chat is a conversational surface only. It is not an operator console and it does not execute live commands against MIM, TOD, the repository, or runtime systems.</p>
            </section>

            <section>
                <h2>Sensitive Information</h2>
                <p>Do not share passwords, private keys, financial account numbers, or other highly sensitive information through the public chat. If you upload files, only upload material you are comfortable having processed for conversational review and service improvement.</p>
            </section>

            <section>
                <h2>Retention</h2>
                <p>We may retain public chat records, uploads, and derived memory summaries for continuity, auditing, and improvement purposes. Retention periods may vary based on operational, safety, and debugging needs.</p>
            </section>

            <section>
                <h2>Contact</h2>
                <p>Entity: {MIM_LEGAL_ENTITY_NAME}. Contact: <a href="mailto:{MIM_LEGAL_CONTACT_EMAIL}">{MIM_LEGAL_CONTACT_EMAIL}</a>. Jurisdiction: {MIM_LEGAL_JURISDICTION}.</p>
            </section>
        </div>
    </main>
</body>
</html>
                """
        )


@router.get("/", response_class=HTMLResponse)
async def public_chat_home() -> HTMLResponse:
        approved_homepage = _approved_public_homepage_html()
        if approved_homepage:
                return HTMLResponse(approved_homepage)
        return HTMLResponse(_clean_public_homepage_fallback_html())
        template_gallery = _template_gallery_section(include_style=False)
        return HTMLResponse(
                f"""
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>MIM</title>
    <style>
        :root {{
            color-scheme: dark;
            --bg: #081018;
            --panel: #101a23;
            --panel-soft: #132230;
            --line: #263a4d;
            --text: #eef5f7;
            --muted: #9eb2c3;
            --accent: #14a879;
            --accent-2: #4ba3df;
            --warn: #f0b35a;
            --max: 1180px;
        }}
        * {{ box-sizing: border-box; }}
        body {{
            margin: 0;
            background: var(--bg);
            color: var(--text);
            font: 16px/1.5 Arial, "Segoe UI", sans-serif;
        }}
        a {{ color: inherit; text-decoration: none; }}
        .top {{
            position: sticky;
            top: 0;
            z-index: 3;
            background: rgba(8,16,24,.94);
            border-bottom: 1px solid var(--line);
        }}
        .nav {{
            max-width: var(--max);
            margin: 0 auto;
            padding: 16px 22px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 16px;
        }}
        .brand {{ font-weight: 800; font-size: 22px; letter-spacing: .02em; }}
        .links {{ display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }}
        .links a, .btn {{
            border: 1px solid var(--line);
            background: #122131;
            color: var(--text);
            border-radius: 8px;
            padding: 10px 14px;
            font-weight: 700;
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }}
        .btn.primary, .links a.primary {{ background: var(--accent); border-color: #0e7d59; color: white; }}
        .wrap {{ max-width: var(--max); margin: 0 auto; padding: 28px 22px 56px; }}
        .hero {{
            min-height: 620px;
            display: grid;
            grid-template-columns: minmax(0, 1.05fr) minmax(320px, .95fr);
            gap: 34px;
            align-items: center;
        }}
        .eyebrow {{ color: #aee7d3; font-weight: 800; text-transform: uppercase; letter-spacing: .08em; font-size: 12px; margin-bottom: 12px; }}
        h1 {{ font-size: clamp(40px, 7vw, 82px); line-height: .98; margin: 0 0 18px; letter-spacing: 0; }}
        .lead {{ color: #c9d8e4; font-size: 20px; max-width: 680px; margin: 0 0 22px; }}
        .askbox {{
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 8px;
            padding: 16px;
            display: grid;
            gap: 12px;
            box-shadow: 0 18px 60px rgba(0,0,0,.28);
        }}
        textarea {{
            width: 100%;
            min-height: 126px;
            resize: vertical;
            border: 1px solid #385065;
            border-radius: 8px;
            background: #0b141d;
            color: var(--text);
            padding: 14px;
            font: inherit;
        }}
        .starter-row {{ display: flex; gap: 8px; flex-wrap: wrap; }}
        .chip {{
            border: 1px solid #31506a;
            background: #0d1a25;
            color: #cfe0ed;
            border-radius: 999px;
            padding: 8px 10px;
            font-size: 13px;
            cursor: pointer;
        }}
        .visual {{
            min-height: 500px;
            border: 1px solid var(--line);
            border-radius: 8px;
            background:
                linear-gradient(145deg, rgba(20,168,121,.2), rgba(75,163,223,.14)),
                #101a23;
            padding: 22px;
            display: grid;
            align-content: center;
            gap: 14px;
        }}
        .process-card {{
            border: 1px solid rgba(180,205,224,.18);
            background: rgba(8,16,24,.62);
            border-radius: 8px;
            padding: 16px;
        }}
        .process-card strong {{ display: block; font-size: 18px; margin-bottom: 4px; }}
        .process-card span {{ color: var(--muted); }}
        section {{ margin-top: 42px; }}
        h2 {{ margin: 0 0 14px; font-size: 30px; }}
        .grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 14px; }}
        .card {{
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 8px;
            padding: 18px;
            min-height: 150px;
        }}
        .card h3 {{ margin: 0 0 8px; font-size: 18px; }}
        .card p {{ margin: 0; color: var(--muted); }}
        .steps {{ display: grid; grid-template-columns: repeat(5, 1fr); gap: 12px; }}
        .step {{ border-top: 3px solid var(--accent-2); padding: 12px 10px 0; color: #dce8f0; }}
        .cta {{
            background: var(--panel-soft);
            border: 1px solid var(--line);
            border-radius: 8px;
            padding: 22px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 18px;
            flex-wrap: wrap;
        }}
        .muted {{ color: var(--muted); }}
        footer {{ color: var(--muted); border-top: 1px solid var(--line); padding-top: 22px; margin-top: 44px; font-size: 13px; }}
        {_template_gallery_style()}
        @media (max-width: 900px) {{
            .hero, .grid, .steps {{ grid-template-columns: 1fr; }}
            .hero {{ min-height: auto; padding-top: 24px; }}
            .visual {{ min-height: 360px; }}
            .nav {{ align-items: flex-start; flex-direction: column; }}
        }}
    </style>
</head>
<body>
    <header class="top">
        <nav class="nav" aria-label="Main navigation">
            <a class="brand" href="/">MIM</a>
            <div class="links">
                <a href="#solutions">Example Solutions</a>
                <a href="#app-templates">App Templates</a>
                <a href="#how">How It Works</a>
                <a href="/demo">Explore Demo</a>
                <a href="/login">Login</a>
                <a class="primary" href="#ask">Talk To MIM</a>
            </div>
        </nav>
    </header>
    <main class="wrap">
        <section class="hero">
            <div>
                <div class="eyebrow">Collaborative intelligence</div>
                <h1>MIM</h1>
                <p class="lead">A Collaborative Intelligence built to observe, learn, reason, and explore with you.</p>
                <div id="ask" class="askbox">
                    <label for="painInput"><strong>What is slowing your business down?</strong></label>
                    <textarea id="painInput" placeholder="Inventory is a mess. Reporting takes too long. Managers still use spreadsheets. We need automation."></textarea>
                    <div class="starter-row">
                        <button class="chip" type="button" data-fill="Inventory is a mess and managers still send spreadsheets every week.">Inventory is a mess</button>
                        <button class="chip" type="button" data-fill="Reporting takes too long and I do not trust the numbers until someone checks them manually.">Reporting takes too long</button>
                        <button class="chip" type="button" data-fill="We need an app like a tool we already use, but customized for our workflow and budget.">Customize an app idea</button>
                    </div>
                    <div class="starter-row">
                        <button class="btn primary" type="button" id="askMimBtn">Ask MIM</button>
                        <a class="btn" href="/demo">Explore Demo</a>
                        <a class="btn" href="/login">Existing User Login</a>
                    </div>
                </div>
            </div>
            <aside class="visual" aria-label="MIM process preview">
                <div class="process-card"><strong>Problem</strong><span>What is wasting time, money, trust, or attention?</span></div>
                <div class="process-card"><strong>Discovery</strong><span>MIM asks the consultant questions users do not know to prepare.</span></div>
                <div class="process-card"><strong>Blueprint</strong><span>Users, workflows, data sources, integrations, dashboards, and blockers.</span></div>
                <div class="process-card"><strong>Roadmap</strong><span>What gets built first, why, what it costs, and what value it should create.</span></div>
            </aside>
        </section>

        <section id="solutions">
            <h2>Example Solutions</h2>
            <div class="grid">
                <article class="card"><h3>Fuel Operations</h3><p>Inventory variance, fuel margin, labor visibility, manager accountability, and executive reporting.</p></article>
                <article class="card"><h3>Insurance Agencies</h3><p>Commission analytics, agent performance, policy tracking, exception review, and payout audit.</p></article>
                <article class="card"><h3>Warehouses</h3><p>Inventory workflows, purchasing exceptions, count review, loss tracking, and operational dashboards.</p></article>
                <article class="card"><h3>Professional Services</h3><p>Client intake, task automation, document workflow, reporting, and support desk systems.</p></article>
                <article class="card"><h3>Workforce Operations</h3><p>Scheduling concepts, tasks, training, communication, forms, and checklist-driven workflows.</p></article>
                <article class="card"><h3>Custom Internal Tools</h3><p>When off-the-shelf software is too expensive, too rigid, or too far from the real process.</p></article>
            </div>
        </section>

        {template_gallery}

        <section id="how">
            <h2>How It Works</h2>
            <div class="steps">
                <div class="step"><strong>1. Problem</strong><br><span class="muted">Tell MIM what hurts.</span></div>
                <div class="step"><strong>2. Discovery</strong><br><span class="muted">MIM maps the current process.</span></div>
                <div class="step"><strong>3. Blueprint</strong><br><span class="muted">Requirements become plain English.</span></div>
                <div class="step"><strong>4. Roadmap</strong><br><span class="muted">Phases, blockers, value, and effort.</span></div>
                <div class="step"><strong>5. Build</strong><br><span class="muted">TOD executes after approval.</span></div>
            </div>
        </section>

        <section class="cta">
            <div>
                <h2>Ready to see the workspace?</h2>
                <p class="muted">The homepage is the lobby. The portal is where discovery, blueprints, roadmaps, and implementation planning live.</p>
            </div>
            <div class="starter-row">
                <a class="btn primary" href="/demo">Try Demo</a>
                <a class="btn" href="/login">Portal Login</a>
                <a class="btn" href="/projects">Project Portal</a>
            </div>
        </section>

        <footer>
            MIM analyzes references for patterns and workflows only. MIM does not clone products, copy branding, reuse copyrighted content, or activate implementation work without approval. <a href="{PUBLIC_PRIVACY_POLICY_PATH}">Privacy Policy</a>
        </footer>
    </main>
    <script>
        const input = document.getElementById('painInput');
        for (const chip of document.querySelectorAll('[data-fill]')) {{
            chip.addEventListener('click', () => {{ input.value = chip.dataset.fill || ''; input.focus(); }});
        }}
        document.getElementById('askMimBtn').addEventListener('click', () => {{
            const text = encodeURIComponent((input.value || '').trim());
            window.location.href = text ? `/demo?idea=${{text}}` : '/demo';
        }});
    </script>
</body>
</html>
                """
        )


@router.get("/apps/templates.json")
async def public_app_templates_json() -> dict[str, Any]:
        apps = _published_template_apps()
        return {
                "artifact_type": "public_mim_app_template_gallery_v1",
                "app_count": len(apps),
                "apps": apps,
                "source": str(USER_APP_GALLERY_MANIFEST),
                "production_deploy": "template_demo_only_until_user_selects_deploy_target",
        }


@router.get("/apps/templates", response_class=HTMLResponse)
async def public_app_templates() -> HTMLResponse:
        apps = _published_template_apps()
        cards = []
        for app in apps:
                cards.append(
                        f"""
                        <article class="template-card">
                          <a href="{html.escape(app['demo_url'])}" target="_blank" rel="noopener">
                            <span class="template-shot">
                              <iframe src="{html.escape(app['preview_url'])}" loading="lazy" tabindex="-1" title="{html.escape(app['app_name'])} preview thumbnail"></iframe>
                            </span>
                          </a>
                          <div>
                            <small>{html.escape(app.get('app_type') or app.get('style_preset') or 'MIM app template')}</small>
                            <h2>{html.escape(app['app_name'])}</h2>
                            <p>{html.escape(app['summary'])}</p>
                            <div class="actions">
                              <a class="primary" href="{html.escape(app['demo_url'])}" target="_blank" rel="noopener">Open demo</a>
                              <a href="{html.escape(app['favorite_url'])}">Save favorite</a>
                              <a href="{html.escape(app['use_url'])}">Use template</a>
                            </div>
                          </div>
                        </article>
                        """
                )
        return HTMLResponse(
                f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MIM App Templates</title>
  <style>
    :root {{ color-scheme:dark; --bg:#071019; --panel:#101923; --line:#263545; --text:#eef6ff; --muted:#9fb1c3; --accent:#67e8f9; }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; background:var(--bg); color:var(--text); font:15px/1.5 Arial, sans-serif; }}
    a {{ color:inherit; text-decoration:none; }}
    .wrap {{ max-width:1240px; margin:0 auto; padding:28px 18px 60px; }}
    header {{ display:flex; justify-content:space-between; gap:16px; align-items:center; margin-bottom:24px; }}
    h1 {{ margin:0; font-size:clamp(36px,6vw,70px); line-height:.98; }}
    p {{ color:var(--muted); }}
    .back {{ border:1px solid var(--line); border-radius:999px; padding:10px 14px; font-weight:800; }}
    .grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(310px,1fr)); gap:16px; }}
    .template-card {{ background:var(--panel); border:1px solid var(--line); border-radius:14px; overflow:hidden; display:grid; grid-template-rows:210px 1fr; }}
    .template-shot {{ position:relative; width:100%; height:100%; overflow:hidden; background:#172231; display:block; }}
    .template-shot::after {{ content:""; position:absolute; inset:0; box-shadow:inset 0 0 0 1px rgba(255,255,255,.08); pointer-events:none; }}
    .template-shot iframe {{ width:1120px; height:720px; border:0; transform:scale(.31); transform-origin:0 0; pointer-events:none; background:white; display:block; }}
    .template-card div {{ padding:16px; }}
    .template-card small {{ color:var(--accent); font-weight:800; text-transform:uppercase; letter-spacing:.06em; }}
    .template-card h2 {{ margin:6px 0 8px; font-size:24px; }}
    .actions {{ display:flex; gap:8px; flex-wrap:wrap; margin-top:14px; }}
    .actions a {{ border:1px solid var(--line); border-radius:999px; padding:9px 12px; font-weight:800; }}
    .actions .primary {{ background:var(--accent); color:#051019; border-color:transparent; }}
  </style>
</head>
<body>
  <main class="wrap">
    <header>
      <div>
        <h1>MIM app templates</h1>
        <p>Public demo previews generated by MIM/TOD training. Open one, save it, or use it as a starting point in your account.</p>
      </div>
      <a class="back" href="/">Home</a>
    </header>
    <section class="grid" aria-label="MIM app templates">
      {''.join(cards) if cards else '<p>No published app templates are available yet.</p>'}
    </section>
  </main>
</body>
</html>"""
        )


@router.get("/apps/templates/{slug}/asset/{asset_path:path}")
async def public_app_template_asset(slug: str, asset_path: str):
        safe_slug = _template_slug(slug)
        clean_parts = [
                part
                for part in Path(asset_path).parts
                if part not in {"", ".", ".."} and not part.endswith(":")
        ]
        root = (Path.cwd() / USER_APP_PUBLISHED_ROOT / safe_slug).resolve()
        target = (root / Path(*clean_parts)).resolve()
        if not str(target).startswith(str(root)) or not target.is_file():
                raise HTTPException(status_code=404, detail="template_asset_not_found")
        return FileResponse(target)


@router.get("/apps/templates/{slug}/preview", response_class=HTMLResponse)
async def public_app_template_preview(slug: str):
        safe_slug = _template_slug(slug)
        root = (Path.cwd() / USER_APP_PUBLISHED_ROOT / safe_slug).resolve()
        target = (root / "preview.html").resolve()
        if not str(target).startswith(str(root)) or not target.is_file():
                raise HTTPException(status_code=404, detail="template_preview_not_found")
        return FileResponse(target, media_type="text/html")


@router.get("/apps/templates/{slug}/demo", response_class=HTMLResponse)
async def public_app_template_demo(slug: str) -> HTMLResponse:
        safe_slug = _template_slug(slug)
        app = next((item for item in _published_template_apps() if item["slug"] == safe_slug), None)
        if not app:
                raise HTTPException(status_code=404, detail="template_demo_not_found")
        return HTMLResponse(
                f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(app['app_name'])} Demo</title>
  <style>
    :root {{ color-scheme:dark; --bg:#071019; --panel:#101923; --line:#263545; --text:#eef6ff; --muted:#9fb1c3; --accent:#67e8f9; }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; min-height:100vh; background:var(--bg); color:var(--text); font:14px Arial, sans-serif; display:grid; grid-template-rows:auto 1fr; }}
    header {{ display:flex; gap:12px; justify-content:space-between; align-items:center; padding:12px 16px; border-bottom:1px solid var(--line); background:rgba(7,16,25,.96); }}
    h1, p {{ margin:0; }}
    h1 {{ font-size:20px; }}
    p {{ color:var(--muted); }}
    .actions {{ display:flex; gap:8px; flex-wrap:wrap; }}
    a {{ color:inherit; text-decoration:none; border:1px solid var(--line); border-radius:999px; padding:8px 11px; font-weight:800; }}
    a.primary {{ background:var(--accent); color:#051019; border-color:transparent; }}
    iframe {{ width:100%; height:100%; border:0; background:white; }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>{html.escape(app['app_name'])}</h1>
      <p>{html.escape(app['one_line'])}</p>
    </div>
    <nav class="actions" aria-label="Template actions">
      <a href="/apps/templates">All templates</a>
      <a href="{html.escape(app['favorite_url'])}">Save favorite</a>
      <a class="primary" href="{html.escape(app['use_url'])}">Use template</a>
    </nav>
  </header>
  <iframe src="/apps/templates/{html.escape(safe_slug)}/preview" title="{html.escape(app['app_name'])} preview"></iframe>
</body>
</html>"""
        )


@router.get("/demo", response_class=HTMLResponse)
@router.get("/build", response_class=HTMLResponse)
async def public_demo_entry(
        request: Request,
        idea: str = "",
        db: AsyncSession = Depends(get_db),
) -> HTMLResponse:
        account = await _current_account_or_none(request, db)
        account_name = str(getattr(account, "contact_name", "") or getattr(account, "email", "") or "").strip()
        account_first_name = html.escape(account_name.split()[0] if account_name else "")
        greeting_html = f"<p class='login-greeting'>Hi {account_first_name}.</p>" if account_first_name else ""
        auth_menu_item = (
            "<button class='menu-link' type='button' data-logout>Logout</button>"
            if account
            else "<a href='/login'>Login</a>"
        )
        primary_account_action = (
            "<a class='btn primary' href='/projects'>Open my workspace</a>"
            if account
            else "<a class='btn primary' href='/login'>Create my account now</a>"
        )
        secondary_build_actions = (
            "<a class='btn' href='/demo'>Explore public demo</a>"
            "<a class='btn' href='/apps/templates'>App templates</a>"
        )
        template_gallery = _template_gallery_section(include_style=False)
        initial_idea = html.escape(str(idea or "").strip())
        return HTMLResponse(
                f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MIM Apps / Build intake</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg:#071019;
      --panel:#101923;
      --panel2:#0c141d;
      --line:#263545;
      --text:#eef6ff;
      --muted:#9fb1c3;
      --accent:#67e8f9;
      --green:#54d18a;
      --blue:#7cb7ff;
      --yellow:#f3c969;
      --bad:#ff9b9b;
    }}
    * {{ box-sizing:border-box; }}
    body {{ margin:0; min-height:100vh; background:var(--bg); color:var(--text); font:14px Arial, sans-serif; }}
    button, input, textarea {{ font:inherit; }}
    .shell {{ min-height:100vh; display:grid; grid-template-columns:minmax(0,1fr) 380px; }}
    .main {{ min-width:0; padding:18px; display:grid; gap:14px; align-content:start; }}
    .top {{ display:flex; align-items:center; justify-content:space-between; gap:14px; border-bottom:1px solid var(--line); padding-bottom:14px; }}
    h1, h2, h3, p {{ margin:0; }}
    h1 {{ font-size:28px; line-height:1.05; }}
    h2 {{ font-size:18px; }}
    h3 {{ font-size:15px; }}
    p {{ color:var(--muted); line-height:1.45; }}
    a {{ color:var(--accent); text-decoration:none; font-weight:800; }}
    .site-menu {{ position:fixed; top:18px; right:18px; z-index:50; }}
    .icon-button {{ width:42px; height:42px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.035); color:var(--text); display:inline-grid; place-items:center; cursor:pointer; }}
    .icon-button:hover, .icon-button:focus-visible {{ background:rgba(255,255,255,.075); outline:none; }}
    .icon-button svg {{ width:19px; height:19px; stroke:currentColor; stroke-width:2; fill:none; stroke-linecap:round; }}
    .site-menu .menu-panel {{ position:absolute; top:52px; right:0; min-width:210px; border:1px solid var(--line); border-radius:14px; background:rgba(12,13,16,.97); box-shadow:0 24px 70px rgba(0,0,0,.48); padding:8px; display:none; }}
    .site-menu.open .menu-panel {{ display:grid; }}
    .site-menu .menu-panel a,.site-menu .menu-panel .menu-link {{ color:var(--muted); text-decoration:none; text-align:left; border:0; border-radius:10px; padding:12px 13px; background:transparent; font:inherit; font-weight:800; cursor:pointer; }}
    .site-menu .menu-panel a:hover, .site-menu .menu-panel a:focus-visible,.site-menu .menu-panel .menu-link:hover,.site-menu .menu-panel .menu-link:focus-visible {{ background:rgba(255,255,255,.07); color:var(--text); outline:none; }}
    .actions {{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }}
    .top-copy {{ display:grid; gap:7px; }}
    .login-greeting {{ color:var(--accent); font-weight:850; }}
    .btn, button {{ border:1px solid var(--line); background:#132234; color:var(--text); border-radius:7px; padding:9px 12px; cursor:pointer; font-weight:800; }}
    .btn.primary, button.primary {{ background:linear-gradient(135deg,#56d8e8,#75b7ff); color:#061019; border-color:transparent; }}
    .btn.green {{ background:#0f6b4c; border-color:#168663; color:white; }}
    .card {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px; }}
    .status-grid {{ display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; }}
    .metric {{ min-height:82px; }}
    .metric small {{ display:block; color:var(--muted); font-weight:800; text-transform:uppercase; font-size:11px; letter-spacing:.05em; }}
    .metric strong {{ display:block; font-size:22px; margin-top:10px; }}
    .tabs {{ display:flex; gap:8px; flex-wrap:wrap; }}
    .tab.active {{ background:#1c3448; border-color:#4eb7d1; color:#baf7ff; }}
    .workbench {{ display:grid; grid-template-columns:minmax(0,1.25fr) minmax(320px,.75fr); gap:14px; align-items:start; }}
    .preview {{ background:#f7fafc; color:#1f2937; border-radius:8px; overflow:hidden; min-height:520px; }}
    .preview-head {{ background:#18344a; color:white; padding:14px; display:flex; align-items:center; justify-content:space-between; }}
    .preview-nav {{ display:flex; gap:8px; flex-wrap:wrap; }}
    .preview-nav button {{ background:rgba(255,255,255,.12); color:white; border:1px solid rgba(255,255,255,.16); border-radius:999px; padding:5px 9px; font-size:12px; }}
    .preview-nav button.active {{ background:white; color:#18344a; }}
    .preview-body {{ padding:18px; display:grid; gap:14px; }}
    .app-grid {{ display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:12px; }}
    .app-tile {{ border:1px solid #d9e2ea; border-radius:8px; padding:12px; background:white; }}
    .app-form {{ border:1px solid #d9e2ea; border-radius:8px; padding:14px; background:white; display:grid; gap:10px; }}
    .screen {{ display:none; }}
    .screen.active {{ display:grid; gap:14px; }}
    .detail-grid {{ display:grid; grid-template-columns:minmax(0,.7fr) minmax(280px,.3fr); gap:12px; }}
    .table {{ width:100%; border-collapse:collapse; background:white; border:1px solid #d9e2ea; border-radius:8px; overflow:hidden; }}
    .table th, .table td {{ border-bottom:1px solid #e5edf4; padding:10px; text-align:left; }}
    .table th {{ background:#eef5fb; color:#24384a; }}
    .table tr:last-child td {{ border-bottom:0; }}
    .coach-card {{ border:1px dashed #7cb7ff; border-radius:8px; background:#edf7ff; color:#24415c; padding:12px; }}
    .field-pill {{ display:inline-flex; margin:3px 4px 3px 0; border:1px solid #cfd9e3; border-radius:999px; padding:5px 8px; background:white; font-size:12px; }}
    .help-grid {{ display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:12px; }}
    .help-card {{ border:1px solid #d9e2ea; border-radius:8px; padding:12px; background:white; }}
    .help-card ol, .help-card ul {{ margin:8px 0 0; padding-left:20px; color:#405367; line-height:1.45; }}
    .section-head {{ display:flex; align-items:end; justify-content:space-between; gap:16px; margin-bottom:12px; }}
    .section-head p {{ max-width:620px; }}
    .feature-grid {{ display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px; }}
    .feature-card {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:14px; min-height:120px; }}
    .feature-card small {{ display:block; color:var(--accent); font-size:11px; font-weight:900; text-transform:uppercase; letter-spacing:.06em; margin-bottom:9px; }}
    .feature-card h3 {{ font-size:17px; margin-bottom:8px; }}
    .create-grid {{ display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; }}
    .create-grid div {{ background:var(--panel); border:1px solid var(--line); border-radius:8px; padding:13px; min-height:92px; }}
    .create-grid strong {{ display:block; margin-bottom:6px; }}
    .create-grid span {{ color:var(--muted); line-height:1.35; }}
    .mim-help {{ border:1px solid #8bc9ff; border-radius:8px; padding:14px; background:#edf7ff; color:#24415c; display:grid; gap:10px; }}
    .mim-help-row {{ display:grid; grid-template-columns:minmax(0,1fr) auto; gap:8px; }}
    .mim-help input {{ border:1px solid #bdd7ef; border-radius:7px; padding:10px; background:white; color:#1f2937; }}
    .mim-help-answer {{ border:1px solid #c5dff6; border-radius:7px; background:white; padding:10px; min-height:54px; line-height:1.45; }}
    .demo-state-font .preview {{ font-family:Georgia, 'Times New Roman', serif; }}
    .demo-state-blue .app-form {{ background:#e7f2ff; border-color:#83bdf7; }}
    .sync-health {{ display:inline-flex; align-items:center; justify-content:center; min-width:34px; border-radius:6px; padding:4px 7px; background:#d9fbe4; color:#176534; font-weight:900; }}
    .demo-state-help .menu-help, .demo-state-menu .menu-reports, .demo-state-sync .menu-sync {{ display:inline-flex; }}
    .menu-help, .menu-reports, .menu-sync, .dynamic-business-email, .dynamic-birthday, .dynamic-birthdate-col, .dynamic-birthday-widget {{ display:none; }}
    .demo-state-email .dynamic-business-email, .demo-state-birthday .dynamic-birthday, .demo-state-birthdate-col .dynamic-birthdate-col, .demo-state-birthday-widget .dynamic-birthday-widget {{ display:table-cell; }}
    .demo-state-email .field-business-email, .demo-state-birthday .field-birthday {{ display:inline-flex; }}
    .field-business-email, .field-birthday {{ display:none; }}
    .demo-state-sortable th {{ cursor:pointer; text-decoration:underline; text-decoration-style:dotted; }}
    .demo-state-sortable th.sorted-asc::after {{ content:" â†‘"; }}
    .demo-state-sortable th.sorted-desc::after {{ content:" â†“"; }}
    .input-row {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; }}
    .fake-input {{ border:1px solid #cfd9e3; border-radius:6px; padding:10px; color:#5a6774; background:#f9fbfd; }}
    .timeline {{ display:grid; gap:10px; }}
    .event {{ display:grid; grid-template-columns:94px 1fr; gap:10px; padding:10px; border:1px solid var(--line); border-radius:8px; background:var(--panel2); }}
    .event time {{ color:var(--accent); font-weight:800; }}
    .event strong {{ display:block; margin-bottom:4px; }}
    .side {{ position:sticky; top:72px; border-left:1px solid var(--line); background:#090f17; height:calc(100vh - 72px); min-height:560px; display:grid; grid-template-rows:auto minmax(0,1fr) auto; overflow:hidden; }}
    .side-head {{ min-height:48px; padding:10px 12px; border-bottom:1px solid var(--line); display:flex; align-items:center; justify-content:space-between; gap:10px; }}
    .side-actions {{ display:flex; gap:6px; align-items:center; }}
    .side-action {{ width:32px; height:32px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.035); color:var(--text); display:grid; place-items:center; padding:0; cursor:pointer; }}
    .side-action:hover,.side-action:focus-visible {{ background:rgba(255,255,255,.08); outline:none; }}
    .side-action svg,.chat-tool-button svg,.chat-send-button svg {{ width:17px; height:17px; stroke:currentColor; stroke-width:2; fill:none; stroke-linecap:round; stroke-linejoin:round; }}
    .chat {{ overflow:auto; padding:14px; display:flex; flex-direction:column; gap:10px; scroll-behavior:smooth; }}
    .msg {{ border:1px solid var(--line); background:var(--panel); border-radius:8px; padding:11px; line-height:1.45; }}
    .msg.user {{ background:#17263a; margin-left:22px; }}
    .msg.mim {{ margin-right:22px; }}
    .composer {{ padding:12px; border-top:1px solid var(--line); display:grid; gap:8px; }}
    .composer-row {{ display:grid; grid-template-columns:1fr 44px; gap:9px; align-items:end; }}
    textarea {{ width:100%; min-height:76px; max-height:32vh; resize:vertical; border:1px solid var(--line); border-radius:8px; background:#0c141d; color:var(--text); padding:10px; }}
    .chat-send-button {{ width:44px; height:44px; border-radius:999px; padding:0; display:grid; place-items:center; }}
    .chat-tool-row {{ display:flex; justify-content:space-between; gap:8px; align-items:center; }}
    .chat-tool-group {{ display:flex; gap:8px; align-items:center; }}
    .chat-tool-button {{ width:36px; height:36px; border:1px solid var(--line); border-radius:999px; background:rgba(255,255,255,.035); color:var(--text); display:grid; place-items:center; padding:0; }}
    .chat-tool-button:hover,.chat-tool-button:focus-visible,.chat-tool-button.active {{ background:rgba(125,211,252,.16); outline:none; }}
    .chat-file-input {{ display:none; }}
    .examples {{ display:grid; gap:8px; }}
    .examples button {{ text-align:left; }}
    .hidden {{ display:none !important; }}
    .collapsed {{ grid-template-columns:minmax(0,1fr); }}
    .collapsed .side {{ display:none; }}
    .restore-chat {{ display:none; position:fixed; right:16px; bottom:16px; z-index:20; box-shadow:0 12px 30px rgba(0,0,0,.35); }}
    .collapsed .restore-chat {{ display:inline-flex; }}
    .side.minimized {{ height:auto; min-height:0; grid-template-rows:auto; }}
    .side.minimized .chat,.side.minimized .composer {{ display:none; }}
    .side.maximized {{ position:fixed; inset:14px; z-index:90; height:auto; min-height:0; border:1px solid var(--line); border-radius:8px; }}
    @media (max-width:1000px) {{
      .shell {{ grid-template-columns:1fr; }}
      .side {{ min-height:auto; margin-top:0; border-left:0; border-top:1px solid var(--line); }}
      .workbench {{ grid-template-columns:1fr; }}
      .status-grid, .app-grid, .feature-grid, .create-grid {{ grid-template-columns:1fr 1fr; }}
    }}
    @media (max-width:620px) {{
      .top {{ align-items:flex-start; flex-direction:column; }}
      .status-grid, .app-grid, .input-row, .feature-grid, .create-grid {{ grid-template-columns:1fr; }}
      h1 {{ font-size:24px; }}
    }}
  </style>
  {_template_gallery_style()}
</head>
<body>
  <nav class="site-menu" id="siteMenu" aria-label="Site menu">
    <button class="icon-button" type="button" id="menuButton" aria-label="Open menu" aria-expanded="false" aria-controls="menuPanel">
      <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"></path></svg>
    </button>
    <div class="menu-panel" id="menuPanel">
      <a href="/">Home</a>
      <a href="/observatory">Research</a>
      <a href="/build">Build</a>
      <a href="/community">Community</a>
      {auth_menu_item}
    </div>
  </nav>
  <div id="shell" class="shell">
    <main id="main" class="main">
      <header class="top">
        <div class="top-copy">
          {greeting_html}
          <h1>What would you like to build?</h1>
          <p>MIM Apps turns app ideas, demos, services, and tools into guided build projects. No login required for this public preview.</p>
        </div>
        <div class="actions">
          {primary_account_action}
          {secondary_build_actions}
        </div>
      </header>

      <section class="status-grid">
        <div class="card metric"><small>Sample App</small><strong>My Client Follow-Up Tracker</strong></div>
        <div class="card metric"><small>Status</small><strong id="statusText">Preview Ready</strong></div>
        <div class="card metric"><small>Progress</small><strong id="progressText">62%</strong></div>
        <div class="card metric"><small>Mode</small><strong>Public Demo</strong></div>
      </section>

      <section class="card">
        <div class="section-head">
          <div>
            <h2>Example Projects</h2>
            <p>People imagine faster when they can react to examples. MIM can help shape personal tools, business systems, automation, robotics, games, and AI-assisted workflows.</p>
          </div>
        </div>
        <div class="feature-grid">
          <article class="feature-card"><small>Health and coaching</small><h3>Running App</h3><p>Track training plans, goals, analytics, coaching prompts, progress history, and wearable data.</p></article>
          <article class="feature-card"><small>Lab and automation</small><h3>Robotics Controller</h3><p>Design camera views, sensor feedback, arm controls, safety checks, and learning routines.</p></article>
          <article class="feature-card"><small>Operations</small><h3>Inventory Platform</h3><p>Manage counts, forecasting, variance alerts, approval workflows, reports, and integrations.</p></article>
        </div>
      </section>

      <section class="card">
        <div class="section-head">
          <div>
            <h2>What MIM Can Help Create</h2>
            <p>Start with an idea, a frustration, a wish, or a half-finished concept. MIM turns it into discovery, design, planning, and implementation-ready work.</p>
          </div>
        </div>
        <div class="create-grid">
          <div><strong>Apps</strong><span>Portals, dashboards, CRMs, internal tools, and SaaS products.</span></div>
          <div><strong>Games</strong><span>Mechanics, prototypes, progression systems, content tools, and launch plans.</span></div>
          <div><strong>AI Systems</strong><span>Assistants, research tools, document workflows, and decision support.</span></div>
          <div><strong>Robotics</strong><span>Vision, sensing, motion planning, control surfaces, and experiments.</span></div>
          <div><strong>Web</strong><span>Public sites, product surfaces, client portals, and admin consoles.</span></div>
          <div><strong>Mobile</strong><span>Native and cross-platform app planning, workflows, and release needs.</span></div>
          <div><strong>Analytics</strong><span>Reports, forecasts, KPI surfaces, alerts, and executive views.</span></div>
          <div><strong>Automation</strong><span>Handoffs, integrations, notifications, approvals, and repetitive work.</span></div>
        </div>
      </section>

      {template_gallery}

      <section class="card">
        <div class="tabs">
          <button class="tab active" data-view="preview" type="button">Workbench</button>
          <button class="tab" data-view="log" type="button">Development Log</button>
          <button class="tab" data-view="tools" type="button">Tools</button>
        </div>
      </section>

      <section id="previewView" class="workbench">
        <div id="demoStage" class="preview">
          <div class="preview-head">
            <strong>My Client Follow-Up Tracker</strong>
            <div class="preview-nav">
              <button class="active" type="button" data-screen="dashboard">Dashboard</button>
              <button type="button" data-screen="clients">Clients</button>
              <button class="menu-reports" type="button" data-screen="reports">Reports</button>
              <button class="menu-sync" type="button" data-screen="sync">Sync</button>
              <button class="menu-help" type="button" data-screen="help">Help</button>
            </div>
          </div>
          <div class="preview-body">
            <section class="screen active" id="screen-dashboard">
              <div class="app-grid">
                <div class="app-tile"><strong>Follow-ups due</strong><p>8 client touches need attention this week.</p></div>
                <div class="app-tile"><strong>Overdue</strong><p>2 follow-ups are past target date.</p></div>
                <div class="app-tile"><strong>Win-back list</strong><p>5 quiet clients are ready for outreach.</p></div>
              </div>
              <div class="app-form">
                <h3>New Follow-Up</h3>
                <div class="input-row"><div class="fake-input">Client name</div><div class="fake-input">Next contact date</div></div>
                <div class="fake-input">Reason for follow-up</div>
                <div class="fake-input">Suggested message from MIM</div>
                <button class="primary" type="button">Save Follow-Up</button>
              </div>
            </section>
            <section class="screen" id="screen-clients">
              <div class="coach-card"><strong>Try this:</strong> open Pat Morgan to see how MIM can change a detail screen.</div>
              <table class="table">
                <thead><tr><th>Name</th><th>Company</th><th>Email</th><th>Phone</th><th>Next Follow-Up</th><th></th></tr></thead>
                <tbody>
                  <tr><td>Pat Morgan</td><td>Morgan Agency</td><td>pat@example.com</td><td>(555) 204-1180</td><td>Jun 10</td><td><button type="button" data-client="pat">Open -></button></td></tr>
                  <tr><td>Jamie Lee</td><td>Lee Consulting</td><td>jamie@example.com</td><td>(555) 816-4402</td><td>Overdue</td><td><button type="button" data-client="jamie">Open -></button></td></tr>
                  <tr><td>Riley Chen</td><td>Chen Retail</td><td>riley@example.com</td><td>(555) 901-0088</td><td>Jun 18</td><td><button type="button" data-client="riley">Open -></button></td></tr>
                  <tr><td>Alex Rivera</td><td>Rivera Group</td><td>alex@example.com</td><td>(555) 771-3302</td><td>Jun 21</td><td><button type="button" data-client="alex">Open -></button></td></tr>
                </tbody>
              </table>
            </section>
            <section class="screen" id="screen-detail">
              <div class="detail-grid">
                <div class="app-form">
                  <h3 id="clientName">Pat Morgan</h3>
                  <div class="field-pill">Company: Morgan Agency</div>
                  <div class="field-pill">Email: pat@example.com</div>
                  <div class="field-pill field-business-email">Business Email: pat@morganagency.com</div>
                  <div class="field-pill">Phone: (555) 204-1180</div>
                  <div class="field-pill field-birthday">Birthday: October 14</div>
                  <div class="field-pill">Next Follow-Up: Jun 10</div>
                  <div class="fake-input">Last note: Asked for a quote follow-up next week.</div>
                  <button type="button" data-screen="clients">Back to Clients</button>
                </div>
                <div class="coach-card"><strong>Contextual examples</strong><p>Now that a detail screen is open, MIM can add fields to this page and keep reports in sync.</p></div>
              </div>
            </section>
            <section class="screen" id="screen-reports">
              <div class="dynamic-birthday-widget app-tile"><strong>Upcoming Birthdays</strong><p>October: Pat Morgan. November: Riley Chen.</p></div>
              <table class="table" id="reportTable">
                <thead><tr><th>Name</th><th>Date Added</th><th>Email</th><th>Phone</th><th class="dynamic-birthdate-col">Birthdate</th></tr></thead>
                <tbody>
                  <tr><td>Pat Morgan</td><td>Jun 1</td><td>pat@example.com</td><td>(555) 204-1180</td><td class="dynamic-birthdate-col">Oct 14</td></tr>
                  <tr><td>Jamie Lee</td><td>Jun 3</td><td>jamie@example.com</td><td>(555) 816-4402</td><td class="dynamic-birthdate-col">Mar 8</td></tr>
                  <tr><td>Riley Chen</td><td>Jun 5</td><td>riley@example.com</td><td>(555) 901-0088</td><td class="dynamic-birthdate-col">Nov 22</td></tr>
                  <tr><td>Alex Rivera</td><td>Jun 6</td><td>alex@example.com</td><td>(555) 771-3302</td><td class="dynamic-birthdate-col">Aug 3</td></tr>
                </tbody>
              </table>
            </section>
            <section class="screen" id="screen-sync">
              <div class="coach-card"><strong>Gmail Contact Sync</strong><p>This is a static demo page that shows how a real account could connect Google Contacts, review sync health, and keep contact records current.</p></div>
              <div class="app-grid">
                <div class="app-tile"><strong>Sync Status</strong><p id="syncStatus">Ready to authorize Google Contacts.</p></div>
                <div class="app-tile"><strong>Last Synced</strong><p id="syncLast">Not synced yet in this demo.</p></div>
                <div class="app-tile"><strong>Total Contacts In Sync</strong><p id="syncTotal">0 contacts staged.</p></div>
                <div class="app-tile"><strong>Sync Health</strong><p><span class="sync-health" id="syncHealth">OK</span> Demo-ready connection check.</p></div>
              </div>
              <div class="app-form">
                <h3>Google Authorization</h3>
                <p>Real accounts would use Google OAuth. This public demo does not connect to a live Gmail account.</p>
                <button class="primary" type="button" id="googleAuthorize">Authorize Google Contacts</button>
              </div>
            </section>
            <section class="screen" id="screen-help">
              <div class="coach-card"><strong>How to use this app</strong><p>This Help page is part of the app being built. In a real account, MIM would generate and maintain help content as screens and workflows change.</p></div>
              <div class="help-grid">
                <div class="help-card">
                  <h3>Add a client</h3>
                  <ol>
                    <li>Open Clients.</li>
                    <li>Choose Add Client.</li>
                    <li>Enter name, company, email, and phone.</li>
                    <li>Set the first follow-up date.</li>
                    <li>Save the client.</li>
                  </ol>
                </div>
                <div class="help-card">
                  <h3>Schedule a follow-up</h3>
                  <ol>
                    <li>Open a client detail page.</li>
                    <li>Add a note with the business context.</li>
                    <li>Select the next follow-up date.</li>
                    <li>Use MIM's suggested message if helpful.</li>
                    <li>Mark complete after outreach.</li>
                  </ol>
                </div>
                <div class="help-card">
                  <h3>Review overdue work</h3>
                  <ul>
                    <li>Use Dashboard to see overdue follow-ups.</li>
                    <li>Open Clients to review each record.</li>
                    <li>Update the status after contact.</li>
                  </ul>
                </div>
                <div class="help-card">
                  <h3>Use Reports</h3>
                  <ul>
                    <li>Open Reports after MIM adds the menu item.</li>
                    <li>Click sortable headers after that feature is installed.</li>
                    <li>Add birthday fields to show birthday reporting.</li>
                  </ul>
                </div>
              </div>
              <div class="mim-help">
                <h3>MIM Help</h3>
                <p>Ask app-specific help questions only. Examples: how do I add a client, how do I schedule a follow-up, how do reports work?</p>
                <div class="mim-help-row">
                  <input id="appHelpQuestion" value="How do I add a client?">
                  <button type="button" id="appHelpAsk">Ask</button>
                </div>
                <div class="mim-help-answer" id="appHelpAnswer">Ask a question about using My Client Follow-Up Tracker.</div>
              </div>
            </section>
          </div>
        </div>
        <aside class="card">
          <h2 id="exampleTitle">Try Example Requests</h2>
          <p id="exampleCopy">These are safe prebuilt interactions that show how MIM turns feedback into app changes.</p>
          <div class="examples" id="exampleButtons">
            <button type="button" data-demo="font">Change the fonts</button>
            <button type="button" data-demo="blue">Make the form blue</button>
            <button type="button" data-demo="menu">Add a Reports menu item</button>
            <button type="button" data-demo="help">Add a Help page</button>
          </div>
        </aside>
      </section>

      <section id="logView" class="card hidden">
        <h2>Development Log</h2>
        <div id="timeline" class="timeline"></div>
      </section>

      <section id="toolsView" class="card hidden">
        <h2>Workbench Tools</h2>
        <div class="status-grid">
          <div class="card metric"><small>Preview</small><strong>Available</strong></div>
          <div class="card metric"><small>Files</small><strong>Demo Locked</strong></div>
          <div class="card metric"><small>Hosting</small><strong>Account Only</strong></div>
          <div class="card metric"><small>Publish</small><strong>Account Only</strong></div>
        </div>
        <p style="margin-top:12px">Real accounts unlock saved projects, files, hosting checks, publishing, downloads, and ongoing MIM/TOD work.</p>
      </section>
    </main>

    <aside class="side">
      <div class="side-head">
        <strong>MIM</strong>
        <div class="side-actions">
          <button class="side-action" id="minimizeChat" type="button" aria-label="Minimize MIM chat">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14"></path></svg>
          </button>
          <button class="side-action" id="maximizeChat" type="button" aria-label="Maximize MIM chat">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M8 21H5a2 2 0 0 1-2-2v-3M16 21h3a2 2 0 0 0 2-2v-3"></path></svg>
          </button>
        </div>
      </div>
      <div id="chat" class="chat"></div>
      <div class="composer">
        <div class="composer-row">
          <textarea id="prompt" placeholder="Ask MIM what you want to build...">{initial_idea}</textarea>
          <button class="primary chat-send-button" id="sendPrompt" type="button" aria-label="Send message">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 2 11 13"></path><path d="m22 2-7 20-4-9-9-4Z"></path></svg>
          </button>
        </div>
        <div class="chat-tool-row">
          <div class="chat-tool-group">
            <button class="chat-tool-button" id="attachFile" type="button" aria-label="Attach file or image">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"></path></svg>
            </button>
            <button class="chat-tool-button" id="voiceInput" type="button" aria-label="Voice to text">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3Z"></path><path d="M19 10v2a7 7 0 0 1-14 0v-2M12 19v3"></path></svg>
            </button>
            <button class="chat-tool-button" id="speechOutput" type="button" aria-label="Toggle spoken replies" aria-pressed="false">
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4V5Z"></path><path d="M15 9.5a4 4 0 0 1 0 5M18 7a8 8 0 0 1 0 10"></path></svg>
            </button>
            <input class="chat-file-input" id="chatFileInput" type="file" accept="image/*,.txt,.md,.pdf,.doc,.docx,.xls,.xlsx,.csv,.json">
          </div>
        </div>
      </div>
    </aside>
  </div>
  <script>
    (function () {{
      const menu = document.getElementById('siteMenu');
      const menuButton = document.getElementById('menuButton');
      if (!menu || !menuButton) return;
      menuButton.addEventListener('click', () => {{
        const open = !menu.classList.contains('open');
        menu.classList.toggle('open', open);
        menuButton.setAttribute('aria-expanded', String(open));
      }});
      document.addEventListener('click', (event) => {{
        if (!menu.contains(event.target)) {{
          menu.classList.remove('open');
          menuButton.setAttribute('aria-expanded', 'false');
        }}
      }});
      document.querySelectorAll('[data-logout]').forEach(button => button.addEventListener('click', async () => {{
        await fetch('/projects/logout', {{ method:'POST', credentials:'same-origin' }});
        window.location.href = '/';
      }}));
    }})();
    const chat = document.getElementById('chat');
    const timeline = document.getElementById('timeline');
    const stage = document.getElementById('demoStage');
    const statusText = document.getElementById('statusText');
    const progressText = document.getElementById('progressText');
    const side = document.querySelector('.side');
    const speechButton = document.getElementById('speechOutput');
    let speechEnabled = false;
    let activeScreen = 'dashboard';
    const events = [
      ['09:00', 'Project opened', 'MIM identified a client follow-up workflow as the sample app.'],
      ['09:08', 'Plan created', 'MIM turned the request into screens, data fields, and acceptance criteria.'],
      ['09:21', 'Prototype built', 'TOD generated the first workbench preview.'],
      ['09:32', 'Review ready', 'The user can now request visual and workflow changes.']
    ];
    function esc(value) {{
      return String(value ?? '').replace(/[&<>"']/g, c => ({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
    }}
    function addMessage(role, text) {{
      const node = document.createElement('div');
      node.className = `msg ${{role === 'You' ? 'user' : 'mim'}}`;
      node.innerHTML = `<strong>${{esc(role)}}</strong><br>${{esc(text)}}`;
      chat.appendChild(node);
      chat.scrollTop = chat.scrollHeight;
      if (role !== 'You' && speechEnabled && 'speechSynthesis' in window) {{
        window.speechSynthesis.cancel();
        const utterance = new SpeechSynthesisUtterance(String(text || ''));
        window.speechSynthesis.speak(utterance);
      }}
    }}
    function renderTimeline() {{
      timeline.innerHTML = events.map(item => `<div class="event"><time>${{esc(item[0])}}</time><div><strong>${{esc(item[1])}}</strong><p>${{esc(item[2])}}</p></div></div>`).join('');
    }}
    const examplesByScreen = {{
      dashboard: [
        ['font', 'Change the fonts'],
        ['blue', 'Make the form blue'],
        ['menu', 'Add a Reports menu item'],
        ['sync', 'Sync contacts with my Gmail account'],
        ['help', 'Add a Help page']
      ],
      clients: [
        ['openClient', 'Open Pat Morgan detail page'],
        ['email', 'Add a business email field'],
        ['birthday', 'Add a birthday field']
      ],
      detail: [
        ['email', 'Add a business email field'],
        ['birthday', 'Add a birthday field'],
        ['birthdateReport', 'Add birthday to reports']
      ],
      reports: [
        ['sortable', 'Make headers sortable by click'],
        ['birthdateReport', 'Add the birthdate column'],
        ['birthdayWidget', 'Show upcoming birthdays by month']
      ],
      sync: [
        ['authorizeGoogle', 'Show Google authorization'],
        ['syncRun', 'Show the latest sync status'],
        ['syncHealth', 'Explain sync health']
      ],
      help: [
        ['blue', 'Make help panels blue'],
        ['menu', 'Add reports link to help']
      ]
    }};
    function renderExamples() {{
      const buttons = examplesByScreen[activeScreen] || examplesByScreen.dashboard;
      document.getElementById('exampleTitle').textContent = activeScreen === 'dashboard' ? 'Try Example Requests' : `Examples for ${{activeScreen.charAt(0).toUpperCase() + activeScreen.slice(1)}}`;
      document.getElementById('exampleCopy').textContent = activeScreen === 'dashboard'
        ? 'These are safe prebuilt interactions that show how MIM turns feedback into app changes.'
        : 'The example prompts now change based on the workbench page you are viewing.';
      document.getElementById('exampleButtons').innerHTML = buttons.map(([kind, label]) => `<button type="button" data-demo="${{esc(kind)}}">${{esc(label)}}</button>`).join('');
      document.querySelectorAll('[data-demo]').forEach(btn => btn.addEventListener('click', () => {{
        addMessage('You', btn.textContent.trim());
        applyDemo(btn.dataset.demo);
      }}));
    }}
    function showScreen(name) {{
      activeScreen = name || 'dashboard';
      document.querySelectorAll('.screen').forEach(node => node.classList.toggle('active', node.id === `screen-${{activeScreen}}`));
      document.querySelectorAll('[data-screen]').forEach(node => node.classList.toggle('active', node.dataset.screen === activeScreen));
      renderExamples();
    }}
    function sortReportByColumn(index) {{
      if (!stage.classList.contains('demo-state-sortable')) {{
        addMessage('MIM', 'Sortable headers are not installed yet. Try the report example: make headers sortable by click.');
        return;
      }}
      const table = document.getElementById('reportTable');
      const tbody = table.querySelector('tbody');
      const headers = [...table.querySelectorAll('th')];
      const header = headers[index];
      const nextDirection = header.dataset.sortDirection === 'asc' ? 'desc' : 'asc';
      headers.forEach(item => {{
        item.dataset.sortDirection = '';
        item.classList.remove('sorted-asc', 'sorted-desc');
      }});
      header.dataset.sortDirection = nextDirection;
      header.classList.add(nextDirection === 'asc' ? 'sorted-asc' : 'sorted-desc');
      const rows = [...tbody.querySelectorAll('tr')];
      rows.sort((left, right) => {{
        const a = (left.children[index]?.textContent || '').trim().toLowerCase();
        const b = (right.children[index]?.textContent || '').trim().toLowerCase();
        const compare = a.localeCompare(b, undefined, {{ numeric: true, sensitivity: 'base' }});
        return nextDirection === 'asc' ? compare : -compare;
      }});
      rows.forEach(row => tbody.appendChild(row));
      statusText.textContent = `Report sorted by ${{header.textContent.replace(/[â†‘â†“]/g, '').trim()}}`;
      events.push(['Now', statusText.textContent, 'The demo report table sorted in the workbench without leaving the page.']);
      renderTimeline();
    }}
    function answerAppHelp() {{
      const question = (document.getElementById('appHelpQuestion').value || '').toLowerCase();
      let answer = 'I can only help with this app in the demo. Try asking how to add a client, schedule a follow-up, review overdue work, or use reports.';
      if (question.includes('add') && question.includes('client')) {{
        answer = 'Open Clients, choose Add Client, enter the client name, company, email, phone, and first follow-up date, then save. In the real app, MIM can also help draft the first follow-up note.';
      }} else if (question.includes('follow')) {{
        answer = 'Open a client detail page, add a note, choose the next follow-up date, and save. The Dashboard will show due and overdue follow-ups.';
      }} else if (question.includes('overdue')) {{
        answer = 'Use the Dashboard overdue tile or open Clients and filter by overdue status. Then open the client, review the latest note, and complete or reschedule the follow-up.';
      }} else if (question.includes('report') || question.includes('sort')) {{
        answer = 'Open Reports after the Reports menu is added. Once sortable headers are installed, click a column header to sort ascending or descending.';
      }} else if (question.includes('birthday') || question.includes('birthdate')) {{
        answer = 'Ask MIM to add a birthday field on the client detail page, then add the birthdate column or upcoming birthdays summary to Reports.';
      }}
      document.getElementById('appHelpAnswer').textContent = answer;
    }}
    function applyDemo(kind) {{
      const labels = {{
        font: ['demo-state-font', 'Font change applied', 'MIM asked TOD to use a more editorial font style for the preview.'],
        blue: ['demo-state-blue', 'Blue form applied', 'MIM updated the form treatment so the input area is easier to identify.'],
        menu: ['demo-state-menu', 'Reports menu added', 'MIM added a Reports menu item and staged it for review.'],
        help: ['demo-state-help', 'Help page added', 'MIM added a Help page with basic app guidance.'],
        openClient: ['', 'Client detail opened', 'MIM guided the user from the client list into a detail page for review.'],
        email: ['demo-state-email', 'Business email field added', 'MIM added a business email field to the client detail page.'],
        birthday: ['demo-state-birthday', 'Birthday field added', 'MIM added a birthday field to the client detail page.'],
        sortable: ['demo-state-sortable', 'Sortable headers added', 'MIM made the report headers visibly sortable for the next implementation pass.'],
        birthdateReport: ['demo-state-birthdate-col', 'Birthdate column added', 'MIM added birthdate to the report so detail changes flow into reporting.'],
        birthdayWidget: ['demo-state-birthday-widget', 'Birthday summary added', 'MIM added an upcoming birthdays by month summary to the top of Reports.'],
        sync: ['demo-state-sync', 'Gmail sync page added', 'MIM added a Sync menu item and staged a Google Contacts sync page for review.'],
        authorizeGoogle: ['demo-state-sync', 'Google authorization staged', 'MIM opened the Sync page and showed the Google authorization step.'],
        syncRun: ['demo-state-sync', 'Sync status refreshed', 'MIM refreshed the static sync status so the user can see what a successful contact sync report looks like.'],
        syncHealth: ['demo-state-sync', 'Sync health explained', 'MIM highlighted the health indicator and the fields a real account would monitor.']
      }};
      const selected = labels[kind] || labels.help;
      if (selected[0]) stage.classList.add(selected[0]);
      if (kind === 'menu' || kind === 'birthdateReport' || kind === 'birthdayWidget' || kind === 'sortable') showScreen('reports');
      if (kind === 'sync' || kind === 'authorizeGoogle' || kind === 'syncRun' || kind === 'syncHealth') showScreen('sync');
      if (kind === 'help') showScreen('help');
      if (kind === 'openClient' || kind === 'email' || kind === 'birthday') showScreen('detail');
      if (kind === 'syncRun' || kind === 'authorizeGoogle') {{
        document.getElementById('syncStatus').textContent = 'Connected to Google Contacts in demo mode.';
        document.getElementById('syncLast').textContent = 'Today at 10:42 AM';
        document.getElementById('syncTotal').textContent = '428 contacts in sync.';
      }}
      statusText.textContent = selected[1];
      progressText.textContent = kind === 'openClient' ? '70%' : '78%';
      events.push(['Now', selected[1], selected[2]]);
      renderTimeline();
      addMessage('MIM', `${{selected[1]}}. In a real account, I would save this as a workbench change, ask TOD to implement it, refresh the preview, and keep the project log updated.`);
    }}
    document.querySelectorAll('[data-screen]').forEach(btn => btn.addEventListener('click', () => showScreen(btn.dataset.screen)));
    document.querySelectorAll('[data-client]').forEach(btn => btn.addEventListener('click', () => {{
      const names = {{ pat: 'Pat Morgan', jamie: 'Jamie Lee', riley: 'Riley Chen', alex: 'Alex Rivera' }};
      document.getElementById('clientName').textContent = names[btn.dataset.client] || 'Client Detail';
      showScreen('detail');
      addMessage('MIM', 'Detail page opened. Now the examples change because MIM understands you are reviewing a specific client screen.');
    }}));
    document.querySelectorAll('#reportTable th').forEach((header, index) => header.addEventListener('click', () => sortReportByColumn(index)));
    document.getElementById('appHelpAsk').addEventListener('click', answerAppHelp);
    document.getElementById('googleAuthorize').addEventListener('click', () => {{
      addMessage('You', 'Authorize Google Contacts');
      applyDemo('authorizeGoogle');
    }});
    document.querySelectorAll('[data-view]').forEach(btn => btn.addEventListener('click', () => {{
      document.querySelectorAll('[data-view]').forEach(item => item.classList.remove('active'));
      btn.classList.add('active');
      ['preview','log','tools'].forEach(name => document.getElementById(`${{name}}View`).classList.toggle('hidden', name !== btn.dataset.view));
    }}));
    document.getElementById('sendPrompt').addEventListener('click', () => {{
      const text = document.getElementById('prompt').value.trim();
      if (!text) return;
      addMessage('You', text);
      const lower = text.toLowerCase();
      if (lower.includes('font')) applyDemo('font');
      else if (lower.includes('blue') || lower.includes('color')) applyDemo('blue');
      else if (lower.includes('gmail') || lower.includes('google') || lower.includes('sync') || lower.includes('contact sync')) applyDemo('sync');
      else if (lower.includes('menu') || lower.includes('report')) applyDemo('menu');
      else if (lower.includes('business email')) applyDemo('email');
      else if (lower.includes('birthday') && lower.includes('report')) applyDemo('birthdateReport');
      else if (lower.includes('birthday')) applyDemo('birthday');
      else if (lower.includes('sort')) applyDemo('sortable');
      else applyDemo('help');
    }});
    document.getElementById('minimizeChat').addEventListener('click', () => {{
      side.classList.toggle('minimized');
      if (side.classList.contains('minimized')) side.classList.remove('maximized');
    }});
    document.getElementById('maximizeChat').addEventListener('click', () => {{
      side.classList.toggle('maximized');
      if (side.classList.contains('maximized')) side.classList.remove('minimized');
    }});
    document.getElementById('attachFile').addEventListener('click', () => document.getElementById('chatFileInput').click());
    document.getElementById('chatFileInput').addEventListener('change', event => {{
      const file = event.target.files && event.target.files[0];
      event.target.value = '';
      if (!file) return;
      addMessage('You', `Attached file: ${{file.name}}`);
      addMessage('MIM', 'File attachment noted in this public build demo. In a real project workspace, I would attach it to the project and use it as build context.');
    }});
    speechButton.addEventListener('click', () => {{
      speechEnabled = !speechEnabled;
      speechButton.classList.toggle('active', speechEnabled);
      speechButton.setAttribute('aria-pressed', String(speechEnabled));
      if (!speechEnabled && 'speechSynthesis' in window) window.speechSynthesis.cancel();
    }});
    document.getElementById('voiceInput').addEventListener('click', () => {{
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!SpeechRecognition) {{
        addMessage('MIM', 'Voice input is not available in this browser.');
        return;
      }}
      const recognition = new SpeechRecognition();
      recognition.lang = 'en-US';
      recognition.interimResults = false;
      recognition.maxAlternatives = 1;
      recognition.onresult = event => {{
        const text = event.results && event.results[0] && event.results[0][0] ? event.results[0][0].transcript : '';
        if (text) document.getElementById('prompt').value = text;
      }};
      recognition.start();
    }});
    renderTimeline();
    renderExamples();
    addMessage('MIM', 'Welcome to the public demo. Pick an example request or ask for a simple change. This preview is simulated so visitors can see the workflow without creating real project work.');
    if (document.getElementById('prompt').value.trim()) {{
      addMessage('You', document.getElementById('prompt').value.trim());
      addMessage('MIM', 'I loaded your idea into the demo prompt. In a real account I would turn this into a saved app project and workbench preview.');
    }}
  </script>
</body>
</html>"""
        )


@router.get("/public-chat", response_class=HTMLResponse)
async def legacy_public_chat_home() -> HTMLResponse:
        title = html.escape(f"{settings.app_name} | MIM + TOD")
        login_href = "/mim/login?next=/mim"
        configured_mim_domain = str(settings.remote_shell_domain or "").strip().rstrip("/")
        if configured_mim_domain:
            login_href = f"{configured_mim_domain}/mim/login?next=/mim"
        return HTMLResponse(
                f"""
<!doctype html>
<html lang=\"en\">
<head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
    <title>{title}</title>
    <style>
        :root {{
            --bg: #071019;
            --bg-strong: #0b1621;
            --panel: rgba(12, 24, 35, 0.92);
            --panel-strong: rgba(15, 30, 43, 0.98);
            --ink: #e9f0f5;
            --muted: #8ea2b4;
            --line: rgba(143, 169, 187, 0.18);
            --mim: #4dc4d3;
            --mim-strong: #8ce8f2;
            --tod: #ff9b54;
            --tod-strong: #ffc089;
            --shadow: 0 28px 80px rgba(0, 0, 0, 0.42);
            --display: \"Iowan Old Style\", \"Palatino Linotype\", \"Book Antiqua\", serif;
            --body: \"IBM Plex Sans\", \"Avenir Next\", \"Segoe UI\", sans-serif;
        }}
        * {{ box-sizing: border-box; }}
        body {{
            margin: 0;
            min-height: 100vh;
            color: var(--ink);
            font-family: var(--body);
            background:
                radial-gradient(circle at top left, rgba(77,196,211,0.16), transparent 26%),
                radial-gradient(circle at top right, rgba(255,155,84,0.12), transparent 24%),
                linear-gradient(180deg, #040a11 0%, var(--bg) 100%);
        }}
        .shell {{
            max-width: 1220px;
            margin: 0 auto;
            padding: 20px;
            display: grid;
            gap: 18px;
            min-height: 100vh;
        }}
        .topbar, .stage {{
            border: 1px solid var(--line);
            background: var(--panel);
            backdrop-filter: blur(16px);
            box-shadow: var(--shadow);
            border-radius: 28px;
        }}
        .topbar {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            background: rgba(9, 19, 28, 0.88);
        }}
        .topbar-title {{
            margin: 0;
            font-family: var(--display);
            font-size: 26px;
            letter-spacing: 0.04em;
            color: var(--ink);
        }}
        .login-icon {{
            width: 42px;
            height: 42px;
            border-radius: 999px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: var(--muted);
            text-decoration: none;
            border: 1px solid transparent;
            background: rgba(255,255,255,0.02);
            transition: border-color 120ms ease, color 120ms ease, background 120ms ease;
        }}
        .login-icon:hover,
        .login-icon:focus-visible {{
            color: var(--ink);
            border-color: var(--line);
            background: rgba(255,255,255,0.05);
            outline: none;
        }}
        .login-icon svg {{ width: 20px; height: 20px; display: block; }}
        .stage {{ display: grid; grid-template-rows: auto 1fr auto; min-height: calc(100vh - 90px); overflow: hidden; }}
        .stage-head {{ padding: 26px 28px 20px; border-bottom: 1px solid var(--line); display: grid; gap: 16px; background: linear-gradient(180deg, rgba(255,255,255,0.03), rgba(255,255,255,0)); }}
        .stage-copy {{ color: var(--muted); font-size: 14px; line-height: 1.55; max-width: 720px; }}
        .mode-row {{ display: flex; gap: 10px; flex-wrap: wrap; }}
        .mode-btn {{
            border: 1px solid var(--line);
            border-radius: 999px;
            padding: 10px 16px;
            text-align: left;
            background: rgba(255,255,255,0.03);
            color: var(--ink);
            cursor: pointer;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            font-size: 13px;
            font-weight: 700;
        }}
        .mode-btn.active[data-mode=\"mim\"] {{ border-color: rgba(77,196,211,0.48); box-shadow: inset 0 0 0 1px rgba(77,196,211,0.18); color: var(--mim-strong); }}
        .mode-btn.active[data-mode=\"tod\"] {{ border-color: rgba(255,155,84,0.52); box-shadow: inset 0 0 0 1px rgba(255,155,84,0.18); color: var(--tod-strong); }}
        .messages {{ padding: 20px; overflow: auto; display: flex; flex-direction: column; gap: 14px; background: linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.01)); }}
        .message {{ max-width: 860px; border-radius: 24px; padding: 16px 18px; border: 1px solid var(--line); background: rgba(19, 35, 48, 0.86); box-shadow: 0 10px 24px rgba(0,0,0,0.18); }}
        .message.user {{ margin-left: auto; background: linear-gradient(135deg, #11293b, #183b4e); color: white; border-color: rgba(17,41,59,0.92); }}
        .message.system {{ background: rgba(255,155,84,0.08); border-color: rgba(255,155,84,0.18); }}
        .message-meta {{ font-size: 11px; letter-spacing: 0.10em; text-transform: uppercase; opacity: 0.7; margin-bottom: 8px; }}
        .message-content {{ white-space: pre-wrap; line-height: 1.6; font-size: 15px; }}
        .message-content.intro {{ white-space: normal; line-height: 1.45; }}
        .intro-list {{ margin: 4px 0 6px; padding-left: 18px; color: inherit; }}
        .intro-list li {{ margin: 0 0 2px; }}
        .intro-list li:last-child {{ margin-bottom: 0; }}
        .intro-copy {{ display: block; margin: 0 0 6px; white-space: normal; }}
        .intro-copy:last-child {{ margin-bottom: 0; }}
        .intro-note {{ color: var(--muted); }}
        .composer {{ padding: 18px 20px 20px; border-top: 1px solid var(--line); display: grid; gap: 12px; background: rgba(8,16,24,0.94); }}
        .composer-tools {{ display: grid; gap: 12px; }}
        .hint {{ color: var(--muted); font-size: 12px; }}
        .disclaimer {{ color: var(--muted); font-size: 12px; line-height: 1.5; }}
        .disclaimer a {{ color: var(--mim-strong); font-weight: 800; }}
        .tool-row {{ display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }}
        .upload-btn, .send-btn {{
            border: 0;
            border-radius: 16px;
            padding: 12px 16px;
            font: inherit;
            font-weight: 800;
            cursor: pointer;
            color: white;
        }}
        .upload-btn {{ background: linear-gradient(135deg, #254054, #183141); }}
        .send-btn {{ background: linear-gradient(135deg, var(--mim), var(--mim-strong)); min-width: 120px; }}
        .composer-row {{ display: grid; grid-template-columns: minmax(0, 1fr) 132px; gap: 12px; }}
        textarea {{ min-height: 120px; resize: vertical; border-radius: 20px; border: 1px solid var(--line); padding: 16px; font: inherit; background: rgba(255,255,255,0.03); color: var(--ink); }}
        .upload-status {{ color: var(--muted); font-size: 13px; min-height: 20px; }}
        .starter-row {{ display: flex; gap: 10px; flex-wrap: wrap; }}
        .starter-chip {{ border: 1px solid var(--line); color: var(--ink); background: rgba(255,255,255,0.03); border-radius: 999px; padding: 10px 12px; font-size: 12px; cursor: pointer; }}
        .dropzone {{
            border: 1px dashed rgba(143, 169, 187, 0.34);
            border-radius: 22px;
            padding: 18px;
            display: grid;
            gap: 8px;
            background: rgba(255,255,255,0.02);
            transition: border-color 120ms ease, background 120ms ease;
        }}
        .dropzone.active {{
            border-color: rgba(77,196,211,0.58);
            background: rgba(77,196,211,0.08);
        }}
        .dropzone-title {{ font-size: 13px; font-weight: 700; color: var(--ink); }}
        .dropzone-copy {{ color: var(--muted); font-size: 12px; line-height: 1.5; }}
        input[type=file] {{ display: none; }}
        @media (max-width: 720px) {{
            .shell {{ padding: 12px; gap: 12px; }}
            .stage-head, .messages, .composer {{ padding-left: 14px; padding-right: 14px; }}
            .composer-row {{ grid-template-columns: 1fr; }}
            .send-btn {{ width: 100%; }}
            .message {{ max-width: 100%; }}
        }}
    </style>
</head>
<body>
    <main class=\"shell\">
        <header class=\"topbar\">
            <h1 class=\"topbar-title\">MIM &amp; TOD</h1>
            <a class=\"login-icon\" href=\"{login_href}\" aria-label=\"Login\" title=\"Login\">
                <svg viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\" aria-hidden=\"true\">
                    <path d=\"M9 4 7 2\" />
                    <path d=\"M15 4 17 2\" />
                    <path d=\"M6.5 14.5c0-4 2.4-7.5 5.5-7.5s5.5 3.5 5.5 7.5c0 3.1-2.5 5.5-5.5 5.5s-5.5-2.4-5.5-5.5Z\" />
                    <circle cx=\"9.5\" cy=\"13\" r=\"1\" fill=\"currentColor\" stroke=\"none\" />
                    <circle cx=\"14.5\" cy=\"13\" r=\"1\" fill=\"currentColor\" stroke=\"none\" />
                    <path d=\"M9.5 16.5c1 .7 4 .7 5 0\" />
                </svg>
            </a>
        </header>

        <section class=\"stage\">
            <header class=\"stage-head\">
                <div>
                    <div id="stageCopy" class="stage-copy">Talk to a system that doesn't just respond. It tries to act, verify, and improve.</div>
                </div>
                <div class=\"mode-row\">
                    <button class=\"mode-btn active\" data-mode=\"mim\" type=\"button\">MIM</button>
                    <button class=\"mode-btn\" data-mode=\"tod\" type=\"button\">TOD</button>
                </div>
            </header>

            <section id=\"messages\" class=\"messages\"></section>

            <section class=\"composer\">
                <div class=\"starter-row\">
                    <button class="starter-chip" type="button" data-starter="What is this system?">What is this system?</button>
                    <button class="starter-chip" type="button" data-starter="What are you working on right now?">What are you working on right now?</button>
                    <button class="starter-chip" type="button" data-starter="Show me how you execute a task.">Show me how you execute a task.</button>
                </div>
                <div class=\"composer-tools\">
                    <div class=\"hint\">Drop text, code, docs, or image references here for review.</div>
                    <div id=\"dropzone\" class=\"dropzone\" role=\"button\" tabindex=\"0\" aria-label=\"Drop file here or upload a file\">
                        <div class=\"dropzone-title\">Drop file here</div>
                        <div class=\"dropzone-copy\">Or upload a file if you prefer.</div>
                        <div class=\"tool-row\">
                            <label class=\"upload-btn\" for=\"fileInput\">Upload File</label>
                        </div>
                        <input id=\"fileInput\" type=\"file\" />
                    </div>
                </div>
                <div class=\"disclaimer\">Chats are recorded to improve the service and are processed in accordance with our <a href=\"{PUBLIC_PRIVACY_POLICY_PATH}\">Privacy Policy</a>.</div>
                <div id=\"uploadStatus\" class=\"upload-status\"></div>
                <div class=\"composer-row\">
                    <textarea id=\"messageInput\" placeholder=\"Ask a question, paste code, request a draft, or start a conversation...\"></textarea>
                    <button id=\"sendBtn\" class=\"send-btn\" type=\"button\">Send</button>
                </div>
            </section>
        </section>
    </main>

    <script>
        const modeButtons = Array.from(document.querySelectorAll('[data-mode]'));
        const starterButtons = Array.from(document.querySelectorAll('[data-starter]'));
        const stageCopy = document.getElementById('stageCopy');
        const messagesEl = document.getElementById('messages');
        const messageInput = document.getElementById('messageInput');
        const sendBtn = document.getElementById('sendBtn');
        const uploadStatus = document.getElementById('uploadStatus');
        const fileInput = document.getElementById('fileInput');
        const dropzone = document.getElementById('dropzone');

        const MODE_COPY = {{
            mim: {{
                placeholder: 'Ask MIM a question, request a draft, or start a conversation...'
            }},
            tod: {{
                placeholder: 'Paste code, describe the bug, or ask for architecture help...'
            }}
        }};

        function safeText(value, fallback = '') {{
            const text = String(value || '').trim();
            return text || fallback;
        }}

        function currentMode() {{
            const stored = safeText(localStorage.getItem('mim_public_mode'), 'mim').toLowerCase();
            return stored === 'tod' ? 'tod' : 'mim';
        }}

        function baseVisitorId() {{
            let value = safeText(localStorage.getItem('mim_public_visitor_id'));
            if (!value) {{
                if (window.crypto && typeof window.crypto.randomUUID === 'function') {{
                    value = `visitor-${{window.crypto.randomUUID()}}`;
                }} else {{
                    value = `visitor-${{Date.now().toString(36)}}-${{Math.random().toString(36).slice(2, 10)}}`;
                }}
                localStorage.setItem('mim_public_visitor_id', value);
            }}
            return value;
        }}

        function sessionKeyForMode(mode) {{
            return `${{baseVisitorId()}}-${{mode}}`;
        }}

        function applyMode(mode) {{
            localStorage.setItem('mim_public_mode', mode);
            for (const button of modeButtons) {{
                button.classList.toggle('active', button.dataset.mode === mode);
            }}
            const copy = MODE_COPY[mode] || MODE_COPY.mim;
            messageInput.placeholder = copy.placeholder;
        }}

        function escapeHtml(value) {{
            return String(value || '')
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;')
                .replace(/'/g, '&#39;');
        }}

        function visitorFirstName(visitor) {{
            const fullName = safeText(visitor && visitor.name);
            return fullName ? fullName.split(/\\s+/)[0] : '';
        }}

        function firstVisitIntro(mode) {{
            if (mode === 'tod') {{
                return `
                    <div class="message-meta">TOD</div>
                    <div class="message-content intro">
                        <div class="intro-copy">Hi - I'm TOD. I verify execution. If something actually happens, I'm the part of the system that confirms it. MIM coordinates what should happen. I help show what actually did.</div>
                        <div class="intro-copy">You can ask me anything, or try something like:</div>
                        <ul class="intro-list">
                            <li>"What is this system?"</li>
                            <li>"What are you working on right now?"</li>
                            <li>"Show me how you execute a task"</li>
                        </ul>
                        <div class="intro-copy">If something doesn't make sense, I'll try to explain it. If something fails, I'll show you that too.</div>
                    </div>
                `;
            }}
            return `
                <div class="message-meta">MIM</div>
                <div class="message-content intro">
                    <div class="intro-copy">Hi - I'm MIM. I help coordinate what should happen, and I work with TOD to verify what actually does.</div>
                    <div class="intro-copy">You can ask me anything, or try something like:</div>
                    <ul class="intro-list">
                        <li>"What is this system?"</li>
                        <li>"What are you working on right now?"</li>
                        <li>"Show me how you execute a task"</li>
                    </ul>
                    <div class="intro-copy">If something doesn't make sense, I'll try to explain it. If something fails, I'll show you that too.</div>
                    <div class="intro-copy intro-note">TOD is the part of the system that verifies execution. If something actually happens, TOD is the one that confirms it.</div>
                </div>
            `;
        }}

        function returningIntro(visitor, mode) {{
            const firstName = visitorFirstName(visitor);
            const greeting = `Hi${{firstName ? ` ${{escapeHtml(firstName)}}` : ''}} - `;
            const goals = Array.isArray(visitor && visitor.goals) ? visitor.goals : [];
            const leadGoal = safeText(goals[0]);
            const summary = safeText(visitor && visitor.memory_summary);
            const base = mode === 'tod'
                ? 'Want to keep going on that, debug something new, or review a file?'
                : 'What do you want to explore next?';

            if (leadGoal) {{
                return `
                    <div class="message-meta">${{mode === 'tod' ? 'TOD' : 'MIM'}}</div>
                    <div class="message-content intro">
                        <div class="intro-copy">${{greeting}}last time we chatted you were focused on ${{escapeHtml(leadGoal)}}.</div>
                        <div class="intro-copy">${{base}}</div>
                    </div>
                `;
            }}

            if (summary) {{
                return `
                    <div class="message-meta">${{mode === 'tod' ? 'TOD' : 'MIM'}}</div>
                    <div class="message-content intro">
                        <div class="intro-copy">${{greeting}}last time we chatted, we left off with some context I still have in view.</div>
                        <div class="intro-copy">${{escapeHtml(summary)}}</div>
                        <div class="intro-copy">${{base}}</div>
                    </div>
                `;
            }}

            return `
                <div class="message-meta">${{mode === 'tod' ? 'TOD' : 'MIM'}}</div>
                <div class="message-content intro">
                    <div class="intro-copy">${{greeting}}good to see you again.</div>
                    <div class="intro-copy">${{base}}</div>
                </div>
            `;
        }}

        function emptyStateMarkup(visitor, mode) {{
            const visitCount = Number((visitor && visitor.visit_count) || 0);
            if (visitCount > 1) {{
                return returningIntro(visitor || {{}}, mode);
            }}
            return firstVisitIntro(mode);
        }}

        function renderMessages(messages, visitor, mode) {{
            messagesEl.innerHTML = '';
            if (!Array.isArray(messages) || !messages.length) {{
                const empty = document.createElement('article');
                empty.className = 'message system';
                empty.innerHTML = emptyStateMarkup(visitor, mode);
                messagesEl.appendChild(empty);
                return;
            }}
            for (const message of messages) {{
                const role = safeText(message.role, 'mim').toLowerCase();
                const article = document.createElement('article');
                article.className = `message ${{role === 'visitor' || role === 'operator' ? 'user' : role === 'system' ? 'system' : ''}}`.trim();
                const meta = document.createElement('div');
                meta.className = 'message-meta';
                meta.textContent = `${{safeText(message.role, 'mim')}} Â· ${{safeText(message.created_at, 'now')}}`;
                const content = document.createElement('div');
                content.className = 'message-content';
                content.textContent = safeText(message.content, '');
                article.appendChild(meta);
                article.appendChild(content);
                if (message.attachment && typeof message.attachment === 'object') {{
                    const attachment = document.createElement('div');
                    attachment.className = 'message-meta';
                    attachment.textContent = `attachment Â· ${{safeText(message.attachment.filename, 'file')}}`;
                    article.appendChild(attachment);
                }}
                messagesEl.appendChild(article);
            }}
            messagesEl.scrollTop = messagesEl.scrollHeight;
        }}

        async function refreshState() {{
            const mode = currentMode();
            const sessionKey = sessionKeyForMode(mode);
            const res = await fetch(`/public/chat/state?session_key=${{encodeURIComponent(sessionKey)}}&mode=${{encodeURIComponent(mode)}}`, {{ cache: 'no-store' }});
            const payload = await res.json();
            applyMode(mode);
            renderMessages(payload.messages || [], payload.visitor || {{}}, mode);
        }}

        async function sendMessage() {{
            const message = safeText(messageInput.value);
            if (!message) return;
            const mode = currentMode();
            const sessionKey = sessionKeyForMode(mode);
            sendBtn.disabled = true;
            try {{
                const res = await fetch('/public/chat/message', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ message, mode, session_key: sessionKey }}),
                }});
                await res.json();
                messageInput.value = '';
                await refreshState();
            }} finally {{
                sendBtn.disabled = false;
            }}
        }}

        async function uploadFile(file) {{
            if (!file) return;
            const mode = currentMode();
            const sessionKey = sessionKeyForMode(mode);
            uploadStatus.textContent = `Uploading ${{file.name}}...`;
            const formData = new FormData();
            formData.append('session_key', sessionKey);
            formData.append('mode', mode);
            formData.append('file', file);
            const res = await fetch('/public/chat/upload', {{ method: 'POST', body: formData }});
            const payload = await res.json();
            uploadStatus.textContent = safeText(payload.summary, `Uploaded ${{file.name}}.`);
            fileInput.value = '';
            await refreshState();
        }}

        modeButtons.forEach((button) => {{
            button.addEventListener('click', async () => {{
                applyMode(button.dataset.mode);
                await refreshState();
            }});
        }});

        starterButtons.forEach((button) => {{
            button.addEventListener('click', () => {{
                messageInput.value = safeText(button.dataset.starter);
                messageInput.focus();
            }});
        }});

        sendBtn.addEventListener('click', sendMessage);
        messageInput.addEventListener('keydown', (event) => {{
            if (event.key === 'Enter' && !event.shiftKey) {{
                event.preventDefault();
                sendMessage();
            }}
        }});
        fileInput.addEventListener('change', (event) => uploadFile(event.target.files && event.target.files[0]));
        dropzone.addEventListener('click', () => fileInput.click());
        dropzone.addEventListener('keydown', (event) => {{
            if (event.key === 'Enter' || event.key === ' ') {{
                event.preventDefault();
                fileInput.click();
            }}
        }});
        ['dragenter', 'dragover'].forEach((eventName) => {{
            dropzone.addEventListener(eventName, (event) => {{
                event.preventDefault();
                dropzone.classList.add('active');
            }});
        }});
        ['dragleave', 'dragend', 'drop'].forEach((eventName) => {{
            dropzone.addEventListener(eventName, (event) => {{
                event.preventDefault();
                dropzone.classList.remove('active');
            }});
        }});
        dropzone.addEventListener('drop', (event) => {{
            const files = event.dataTransfer && event.dataTransfer.files;
            uploadFile(files && files[0]);
        }});

        applyMode(currentMode());
        refreshState();
    </script>
</body>
</html>
                """
        )


@router.get("/public/chat/state")
async def public_chat_state(
    request: Request,
    session_key: str = Query(...),
    mode: str = Query(default="mim"),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    return await _build_public_state(
        session_key=session_key,
        mode=mode,
        request=request,
        db=db,
    )


@router.post("/public/chat/message")
async def public_chat_message(
    payload: PublicChatMessageRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    normalized_mode = _normalize_mode(payload.mode)
    channel_context = _public_channel_context(normalized_mode)
    normalized_session = _normalize_session_key(payload.session_key)
    visitor_key, ip_hash = _visitor_key_from_session(normalized_session, request)
    profile = await _latest_public_profile(visitor_key=visitor_key, ip_hash=ip_hash, db=db)
    profile_updates = _extract_profile_updates(payload.message)
    updated_profile = _merge_profile(profile, profile_updates)
    updated_profile["visit_count"] = max(1, int(profile.get("visit_count") or 0))
    updated_profile["last_seen_at"] = _utc_now_iso()
    recall_summary = _profile_summary(profile)
    session, _ = await _ensure_public_session(
        session_key=normalized_session,
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        mode=normalized_mode,
        db=db,
    )
    session_context = session.context_json if isinstance(getattr(session, "context_json", None), dict) else {}
    active_project_context = session_context.get("active_public_project") if isinstance(session_context.get("active_public_project"), dict) else {}
    incoming_context = payload.context if isinstance(payload.context, dict) else {}
    incoming_research_context = incoming_context if is_research_context(incoming_context) else {}
    session_research_context = _observatory_research_context_from_session_key(normalized_session) if not incoming_research_context else {}
    message_research_context = (
        _observatory_research_context_from_message(payload.message)
        if not incoming_research_context and not session_research_context
        else {}
    )
    if incoming_research_context or session_research_context or message_research_context:
        active_project_context = incoming_research_context or session_research_context or message_research_context
    clear_stored_research_context = (
        bool(active_project_context)
        and not incoming_research_context
        and not session_research_context
        and not message_research_context
        and _is_public_project_planning_request(payload.message)
    )
    if clear_stored_research_context:
        active_project_context = {}
    _, prior_rows = await list_interface_messages(session_key=normalized_session, limit=12, db=db)
    recent_messages = [
        {
            "role": str(item.get("role") or ""),
            "content": str(item.get("content") or ""),
        }
        for item in (_serialize_message(row) for row in reversed(prior_rows))
    ]
    if active_project_context:
        recent_messages.append({
            "role": "context",
            "content": json.dumps(active_project_context, ensure_ascii=True),
        })
    project_context_update: dict[str, Any] = (
        dict(incoming_research_context or session_research_context or message_research_context)
        if (incoming_research_context or session_research_context or message_research_context)
        else {}
    )
    if _has_accounting_receipt_app_context(payload.message):
        project_context_update = {
            "kind": "expense_intelligence_platform",
            "plain_language_name": "receipt-driven expense intelligence platform",
            "signals": ["receipt_capture", "expense_tracking", "reports", "subscriptions", "smart_actions"],
            "last_user_request": _compact_text(payload.message, 700),
            "updated_at": _utc_now_iso(),
        }
    _, inbound = await append_interface_message(
        session_key=normalized_session,
        actor="visitor",
        source="public_chat",
        direction="inbound",
        role="visitor",
        content=str(payload.message).strip(),
        parsed_intent=f"public_{normalized_mode}_chat",
        confidence=1.0,
        requires_approval=False,
        metadata_json={
            "message_type": "visitor_message",
            "mode": normalized_mode,
            "public_guest_chat": True,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
            "incoming_context_kind": str(incoming_context.get("kind") or "") if incoming_context else "",
            "incoming_context_id": str(incoming_context.get("id") or "") if incoming_context else "",
        },
        db=db,
    )
    await _remember_turn(
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        session_key=normalized_session,
        role="visitor",
        mode=normalized_mode,
        content=str(payload.message).strip(),
        db=db,
    )
    block_reason = _public_command_block_reason(payload.message)
    conversation_context_text = " ".join(
        [
            *(str(item.get("content") or "") for item in recent_messages if isinstance(item, dict)),
            json.dumps(active_project_context, ensure_ascii=True) if active_project_context else "",
            str(recall_summary or ""),
        ]
    )
    grounded_research_reply = research_context_reply(
        message=payload.message,
        context=active_project_context,
        recall_summary=recall_summary,
    )
    self_reflection_request = _is_mim_self_reflection_request(payload.message)
    cognitive_interpretation = build_mim_cognitive_interpretation(
        raw_input=str(payload.message).strip(),
        surface="public_chat",
        page_context=f"public_chat:{normalized_mode}",
        metadata={
            "mode": normalized_mode,
            "public_guest_chat": True,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
        },
        recent_messages=recent_messages,
    )
    cognitive_surface_reply = ""
    if (
        normalized_mode == "mim"
        and not block_reason
        and cognitive_interpretation.get("response_mode") == "grounded_bounded_action"
    ):
        cognitive_surface_reply = (
            "I read that as a follow-up asking for one concrete next step. "
            "In public chat I do not have operator task-state access, so I should not pretend I can see the active TOD queue. "
            "Name the project or goal you want to move, and I can turn it into one bounded next action with the proof needed to know it moved."
        )
    enterprise_product_reply = ""
    if normalized_mode == "mim" and not block_reason:
        enterprise_product_reply = _public_enterprise_product_reply(str(payload.message).strip())
    conversation_purpose_reply: dict[str, Any] | None = None
    if (
        normalized_mode == "mim"
        and not block_reason
        and (not active_project_context or self_reflection_request)
        and not cognitive_surface_reply
        and not enterprise_product_reply
    ):
        conversation_purpose_reply = build_conversation_purpose_reply(
            str(payload.message).strip(),
            "public_chat",
            shared_root=Path.cwd() / "runtime" / "shared",
        )
    if cognitive_surface_reply:
        reply_text = cognitive_surface_reply
    elif enterprise_product_reply:
        reply_text = enterprise_product_reply
    elif conversation_purpose_reply:
        reply_text = str(conversation_purpose_reply.get("reply_text") or "").strip()
    elif normalized_mode == "mim" and not block_reason and grounded_research_reply:
        reply_text = grounded_research_reply
    elif (
        normalized_mode == "mim"
        and not block_reason
        and _is_affirmative_continue(payload.message)
        and _has_accounting_receipt_app_context(conversation_context_text)
    ):
        reply_text = _accounting_receipt_platform_reply(recall_summary=recall_summary)
    else:
        reply_text = await _compose_public_reply(
            message=str(payload.message).strip(),
            mode=normalized_mode,
            profile=updated_profile,
            recall_summary=recall_summary,
            recent_messages=recent_messages,
            block_reason=block_reason,
        )
    _, reply = await append_interface_message(
        session_key=normalized_session,
        actor="mim" if normalized_mode == "mim" else "tod",
        source="public_chat",
        direction="outbound",
        role="mim" if normalized_mode == "mim" else "tod",
        content=reply_text,
        parsed_intent="public_chat_reply",
        confidence=1.0,
        requires_approval=False,
        metadata_json={
            "message_type": "assistant_reply",
            "mode": normalized_mode,
            "public_guest_chat": True,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
            "conversation_purpose": (
                conversation_purpose_reply.get("conversation_purpose", {})
                if conversation_purpose_reply
                else {
                    "purpose": "enterprise_product_explanation",
                    "confidence": "high",
                    "signals": ["enterprise", "product_question"],
                    "downstream_policy": "answer_from_enterprise_product_context",
                    "operator_contract_allowed": False,
                } if enterprise_product_reply
                else cognitive_interpretation.get("classifier_purpose", {})
            ),
            "response_mode": (
                str(conversation_purpose_reply.get("response_mode") or "")
                if conversation_purpose_reply
                else "enterprise_product_explanation" if enterprise_product_reply
                else str(cognitive_interpretation.get("response_mode") or "")
            ),
            "mim_cognitive_interpretation": cognitive_interpretation,
            "response_authority": interpretation_response_authority(
                cognitive_interpretation,
                composer_source=(
                    "conversation_purpose_engine"
                    if conversation_purpose_reply
                    else "public_enterprise_product_context"
                    if enterprise_product_reply
                    else "public_chat_composer"
                ),
                wrapper_sources=[],
                prior_fragment_reused=False,
            ),
        },
        db=db,
    )
    await _remember_turn(
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        session_key=normalized_session,
        role="assistant",
        mode=normalized_mode,
        content=reply_text,
        db=db,
    )
    await _remember_profile(visitor_key=visitor_key, ip_hash=ip_hash, profile=updated_profile, db=db)
    if project_context_update or clear_stored_research_context:
        next_context_json = {
            **session_context,
            "public_guest_chat": True,
            "visitor_key": visitor_key,
            "last_mode": normalized_mode,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
        }
        if project_context_update:
            next_context_json["active_public_project"] = project_context_update
        else:
            next_context_json.pop("active_public_project", None)
        await upsert_interface_session(
            session_key=normalized_session,
            actor="visitor",
            source="public_chat",
            channel=str(channel_context["channel"]),
            status="active",
            context_json=next_context_json,
            metadata_json={
                **(session.metadata_json if isinstance(getattr(session, "metadata_json", None), dict) else {}),
                "public_guest_chat": True,
                "visitor_key": visitor_key,
                "ip_hash": ip_hash,
                "last_mode": normalized_mode,
                "public_channel": channel_context["channel"],
                "public_application": channel_context["application_name"],
            },
            db=db,
        )
    await db.commit()
    return {
        "status": "accepted",
        "session": to_interface_session_out(session),
        "message": _serialize_message(inbound),
        "reply": _serialize_message(reply),
        "blocked": bool(block_reason),
        "block_reason": block_reason,
    }


@router.post("/public/chat/upload")
async def public_chat_upload(
    request: Request,
    session_key: str = Form(...),
    mode: str = Form(default="mim"),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
) -> dict[str, Any]:
    normalized_mode = _normalize_mode(mode)
    channel_context = _public_channel_context(normalized_mode)
    normalized_session = _normalize_session_key(session_key)
    visitor_key, ip_hash = _visitor_key_from_session(normalized_session, request)
    profile = await _latest_public_profile(visitor_key=visitor_key, ip_hash=ip_hash, db=db)
    await _ensure_public_session(
        session_key=normalized_session,
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        mode=normalized_mode,
        db=db,
    )
    raw_bytes = await file.read(PUBLIC_CHAT_UPLOAD_LIMIT_BYTES + 1)
    if len(raw_bytes) > PUBLIC_CHAT_UPLOAD_LIMIT_BYTES:
        raise HTTPException(status_code=413, detail="public_upload_too_large")

    filename = str(file.filename or "upload").strip() or "upload"
    content_type = str(file.content_type or "application/octet-stream").strip()
    extension = ("." + filename.rsplit(".", 1)[-1].lower()) if "." in filename else ""
    text_preview = ""
    upload_summary = ""
    attachment = {
        "filename": filename,
        "content_type": content_type,
        "size_bytes": len(raw_bytes),
    }
    if content_type.startswith("text/") or extension in PUBLIC_TEXT_UPLOAD_EXTENSIONS:
        text_preview = raw_bytes.decode("utf-8", errors="replace")[:8000]
        attachment["preview"] = text_preview[:1200]
        upload_summary = _upload_text_summary(filename, content_type, text_preview)
    elif content_type.startswith("image/"):
        upload_summary = _compact_text(
            f"{filename} is an image reference ({content_type or 'image'}). I can help with prompt design, composition, style direction, and critique based on the file you uploaded.",
            220,
        )
    else:
        upload_summary = _compact_text(
            f"{filename} uploaded successfully. I can use the file metadata and any pasted excerpts you provide to discuss it in conversation mode.",
            220,
        )

    inbound_text = f"Uploaded file: {filename}"
    if text_preview:
        inbound_text = f"Uploaded file: {filename}\n\n{text_preview[:2000]}"
    _, inbound = await append_interface_message(
        session_key=normalized_session,
        actor="visitor",
        source="public_chat_upload",
        direction="inbound",
        role="visitor",
        content=inbound_text,
        parsed_intent="public_chat_upload",
        confidence=1.0,
        requires_approval=False,
        metadata_json={
            "message_type": "upload",
            "mode": normalized_mode,
            "attachment": attachment,
            "public_guest_chat": True,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
        },
        db=db,
    )
    reply_text = await _compose_public_reply(
        message=f"uploaded file {filename}",
        mode=normalized_mode,
        profile=profile,
        recall_summary=_profile_summary(profile),
        upload_summary=upload_summary,
    )
    _, reply = await append_interface_message(
        session_key=normalized_session,
        actor="mim" if normalized_mode == "mim" else "tod",
        source="public_chat_upload",
        direction="outbound",
        role="mim" if normalized_mode == "mim" else "tod",
        content=reply_text,
        parsed_intent="public_chat_upload_reply",
        confidence=1.0,
        requires_approval=False,
        metadata_json={
            "message_type": "assistant_reply",
            "mode": normalized_mode,
            "attachment": attachment,
            "public_guest_chat": True,
            "public_channel": channel_context["channel"],
            "public_application": channel_context["application_name"],
        },
        db=db,
    )
    await _remember_turn(
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        session_key=normalized_session,
        role="visitor",
        mode=normalized_mode,
        content=inbound_text,
        db=db,
        attachment=attachment,
    )
    await _remember_turn(
        visitor_key=visitor_key,
        ip_hash=ip_hash,
        session_key=normalized_session,
        role="assistant",
        mode=normalized_mode,
        content=reply_text,
        db=db,
        attachment=attachment,
    )
    await db.commit()
    return {
        "status": "accepted",
        "summary": upload_summary,
        "message": _serialize_message(inbound),
        "reply": _serialize_message(reply),
        "attachment": attachment,
    }
