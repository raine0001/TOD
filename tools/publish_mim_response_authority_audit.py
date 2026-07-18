from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "runtime" / "shared"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(name: str, payload: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def write_md(name: str, text: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def outlet(
    name: str,
    browser_or_api: str,
    frontend_file: str,
    backend_endpoint: str,
    service: str,
    normalizer: str,
    session_id: str,
    context_loader: str,
    interpretation: str,
    mode_selector: str,
    composer: str,
    deterministic_handlers: list[str],
    fallback: str,
    wrappers: list[str],
    mutations: list[str],
    streaming: list[str],
    final_field: str,
    persistence: str,
    shared_entrypoint: bool,
    obeys_shared: str,
    can_override: bool,
    can_replace: bool,
    can_append_contract: bool,
    can_reuse_stale: bool,
    authority_classification: str,
    evidence: list[str],
) -> dict:
    return {
        "outlet_name": name,
        "browser_page_or_api_route": browser_or_api,
        "frontend_file_initiating_request": frontend_file,
        "backend_endpoint": backend_endpoint,
        "service_and_port": service,
        "input_normalizer": normalizer,
        "conversation_or_session_identifier": session_id,
        "context_loader": context_loader,
        "interpretation_function": interpretation,
        "response_mode_selector": mode_selector,
        "composer": composer,
        "deterministic_handlers_that_may_intercept": deterministic_handlers,
        "fallback_composer": fallback,
        "wrappers_appended_after_composition": wrappers,
        "text_mutations_after_composition": mutations,
        "streaming_transformations": streaming,
        "final_response_field_returned": final_field,
        "persistence_history_writer": persistence,
        "calls_shared_cognitive_entrypoint": shared_entrypoint,
        "obeys_shared_interpretation": obeys_shared,
        "can_override_shared_interpretation": can_override,
        "can_replace_final_response": can_replace,
        "can_append_operator_contract_content": can_append_contract,
        "can_reuse_stale_or_previous_response_fragments": can_reuse_stale,
        "authority_classification": authority_classification,
        "static_evidence": evidence,
    }


def provenance(
    surface: str,
    service: str,
    session_key: str,
    interpretation_source: str,
    interpretation_id: str,
    conversation_purpose: str,
    response_mode: str,
    context_source: str,
    composer_source: str,
    final_answer_source: str,
    deterministic_handlers: list[str],
    fallback_used: bool,
    wrappers: list[str],
    mutations: list[str],
    prior_reused: bool,
    visible_response_observation: str,
    prompt: str,
) -> dict:
    return {
        "mim_identity": "MIM",
        "surface": surface,
        "service": service,
        "session_key": session_key,
        "interpretation_source": interpretation_source,
        "interpretation_id": interpretation_id,
        "conversation_purpose": conversation_purpose,
        "response_mode": response_mode,
        "context_source": context_source,
        "composer_source": composer_source,
        "final_answer_source": final_answer_source,
        "deterministic_handlers_used": deterministic_handlers,
        "fallback_used": fallback_used,
        "wrappers_applied": wrappers,
        "post_composer_mutations": mutations,
        "prior_fragment_reused": prior_reused,
        "prompt": prompt,
        "visible_response_observation": visible_response_observation,
    }


def main() -> None:
    generated_at = now_iso()
    source_scan = {
        "primary_files_inspected": [
            "tmp_remote_mim/core/routers/mim_ui.py",
            "tmp_remote_mim/core/routers/gateway.py",
            "tmp_remote_mim/core/routers/studio.py",
            "tmp_remote_mim/core/routers/public_chat.py",
            "tmp_remote_mim/core/routers/interface.py",
            "tmp_remote_mim/core/routers/tod_ui.py",
            "tmp_remote_mim/core/routers/state_bus.py",
            "tmp_remote_mim/core/communication_composer.py",
            "tmp_remote_mim/core/conversation_purpose_engine.py",
            "tmp_remote_mim/core/mim_cognitive_entrypoint.py",
            "tmp_remote_mim/core/manifest.py",
            "tmp_remote_mim/core/app.py",
        ],
        "scan_method": "static route/composer/frontend fetch inspection plus live-probe observations from the failing surfaces",
        "audit_boundary": "No product behavior patch was required to publish these artifacts.",
    }

    outlets = [
        outlet(
            "MIM operator console typed chat",
            "/mim",
            "core/routers/mim_ui.py:submitConversationTurn fetch('/gateway/intake/text')",
            "POST /gateway/intake/text",
            "mim-mobile-web.service / port 18001",
            "TextInputAdapterRequest -> NormalizedInputCreate(source='text')",
            "metadata_json.conversation_session_id",
            "gateway live operational context, interface memory, runtime/shared artifacts",
            "build_mim_cognitive_interpretation plus gateway route preference and many _looks_like gates",
            "gateway _resolve_event branch chain and _compose_conversation_reply",
            "gateway _conversation_response -> communication_composer.compose_expert_communication_reply",
            ["homepage feedback", "private lab sensor", "self model", "reviewable artifact", "active project status", "TOD handoff gates"],
            "build_deterministic_communication_reply or OpenAI rewrite fallback",
            ["_mim_append_operator_impact_contract"],
            ["_mim_clean_operator_reply_boilerplate", "_mim_enforce_first_person_normal_reply", "mim_ui summarizeTextResolution"],
            ["browser TTS", "server TTS"],
            "mim_interface.reply_text",
            "InputEvent/InputEventResolution plus interface memory/worklog state",
            True,
            "partial: interpretation can be present while communication composer or interface wrapper remains authoritative",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["mim_ui.py fetch at /gateway/intake/text", "gateway.py intake_text", "gateway.py _build_mim_interface_response", "communication_composer.py compose_expert_communication_reply"],
        ),
        outlet(
            "Studio MIM embedded tab",
            "/studio/mim",
            "core/routers/studio.py tab source='/mim'",
            "POST /gateway/intake/text through embedded /mim",
            "mim-training-web.service / port 18021 embeds mim-mobile-web route behavior",
            "same as /mim text adapter",
            "metadata_json.conversation_session_id",
            "same as gateway lane",
            "same as /mim",
            "same as /mim",
            "same as /mim",
            ["same as gateway lane"],
            "same as gateway lane",
            ["_mim_append_operator_impact_contract"],
            ["embedded page formatting", "_mim_enforce_first_person_normal_reply"],
            ["browser/server TTS if enabled"],
            "mim_interface.reply_text",
            "InputEvent/InputEventResolution and MIM UI state",
            True,
            "inherits gateway partial obedience and wrapper risk",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["studio.py tab config href=/studio/mim source=/mim", "mim_ui.py submitConversationTurn", "gateway.py _build_mim_interface_response"],
        ),
        outlet(
            "Studio persistent side-panel chat",
            "/studio/projects and other Studio pages",
            "core/routers/studio.py fetch('/studio/api/mim/chat')",
            "POST /studio/api/mim/chat",
            "mim-training-web.service / port 18021",
            "StudioMimChatRequest",
            "thread_id plus studio chat thread store",
            "_studio_recent_thread_context, page_context, DB project/training/report state, runtime/shared artifacts",
            "build_mim_cognitive_interpretation plus studio local classifiers",
            "studio_mim_chat_api ordered branch chain",
            "many _studio_* reply functions and optional gateway _compose_conversation_reply",
            ["grounded bounded action", "grounded status", "self evolution", "active context", "simple direct", "durability", "mode guard", "training", "project stewardship", "visitor stats", "navigation", "lab", "reports"],
            "_studio_operator_contract_fallback_reply",
            ["_studio_with_response_authority", "training attention five-field append"],
            ["_studio_conversation_mode_reply suffix normalization", "navigation/action response replacement"],
            [],
            "mim_interface.reply_text",
            "studio chat history file and interface memory",
            True,
            "weak: shared interpretation can be bypassed by local studio branches",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["studio.py studio_mim_chat_api", "studio.py _studio_conversation_purpose_reply", "studio.py _studio_conversation_mode_guard_reply"],
        ),
        outlet(
            "Studio MIM chat history sync/read",
            "/studio/api/mim/chat-history",
            "core/routers/studio.py fetch('/studio/api/mim/chat-history')",
            "GET/POST /studio/api/mim/chat-history",
            "mim-training-web.service / port 18021",
            "thread_id/messages normalization",
            "thread_id",
            "thread store and memory fallback",
            "none on read; can feed later interpretation through recent_messages",
            "none",
            "none",
            [],
            "memory/local cache fallback",
            [],
            ["history normalization can change available prior context"],
            [],
            "messages/history_source",
            "_load/_save_studio_chat_threads",
            False,
            "not a cognitive path, but can alter context used by one",
            False,
            False,
            False,
            True,
            "Allowed Surface Adapter",
            ["studio.py /studio/api/mim/chat-history"],
        ),
        outlet(
            "Gateway normalized API",
            "/gateway/intake",
            "Studio misc fetch('/gateway/intake') and API clients",
            "POST /gateway/intake",
            "mim-mobile-web.service / port 18001",
            "NormalizedInputCreate",
            "event id/request_id/session metadata",
            "gateway operational context",
            "gateway _resolve_event and shared interpretation if route reaches conversation lane",
            "gateway _resolve_event",
            "gateway branch chain",
            ["all gateway deterministic branches"],
            "generic resolution/status response",
            ["_mim_append_operator_impact_contract for MIM UI presentation"],
            ["interface wrapper text"],
            [],
            "mim_interface.reply_text or resolution fields",
            "InputEvent/InputEventResolution",
            True,
            "partial: depends on event source/metadata and route branch",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["gateway.py intake_normalized", "gateway.py _resolve_event"],
        ),
        outlet(
            "Gateway UI adapter",
            "/gateway/intake/ui",
            "UI command adapters",
            "POST /gateway/intake/ui",
            "mim-mobile-web.service / port 18001",
            "UiInputAdapterRequest -> NormalizedInputCreate(source='ui')",
            "event id/request_id/session metadata",
            "gateway operational context",
            "gateway _resolve_event",
            "gateway _resolve_event",
            "gateway branch chain",
            ["gateway deterministic branches"],
            "generic resolution/status response",
            ["_mim_append_operator_impact_contract where presented through mim_interface"],
            ["interface wrapper text"],
            [],
            "mim_interface.reply_text",
            "InputEvent/InputEventResolution",
            False,
            "not proven",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["gateway.py intake_ui"],
        ),
        outlet(
            "Gateway API adapter",
            "/gateway/intake/api",
            "external/API adapters",
            "POST /gateway/intake/api",
            "mim-mobile-web.service / port 18001",
            "ApiInputAdapterRequest -> NormalizedInputCreate(source='api')",
            "event id/request_id/session metadata",
            "gateway operational context",
            "gateway _resolve_event",
            "gateway _resolve_event",
            "gateway branch chain",
            ["gateway deterministic branches"],
            "generic resolution/status response",
            ["_mim_append_operator_impact_contract where presented through mim_interface"],
            ["interface wrapper text"],
            [],
            "mim_interface.reply_text",
            "InputEvent/InputEventResolution",
            False,
            "not proven",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["gateway.py intake_api"],
        ),
        outlet(
            "Public MIM visitor chat",
            "mimtod.com public chat",
            "core/routers/public_chat.py/observatory.py fetch('/public/chat/message')",
            "POST /public/chat/message",
            "mim-training-web.service / port 18021",
            "PublicChatMessageRequest",
            "session_key plus visitor_key/ip_hash",
            "public profile, interface messages, active public project/research context",
            "build_mim_cognitive_interpretation plus public command/research/project classifiers",
            "public_chat_message ordered branch chain",
            "_compose_public_reply, build_conversation_purpose_reply, research_context_reply",
            ["public command block", "research context", "accounting app context", "weather", "project planning"],
            "_build_public_fallback_reply",
            ["public disclosure and mode formatting"],
            ["profile/recall merge", "public mode normalization"],
            [],
            "reply.content",
            "append_interface_message, remember_turn, public session/profile",
            True,
            "partial: public branch can use conversation_purpose_engine directly",
            True,
            True,
            False,
            True,
            "Duplicate Cognitive Debt",
            ["public_chat.py public_chat_message", "public_chat.py _compose_public_reply", "conversation_purpose_engine.py"],
        ),
        outlet(
            "Interface session messages",
            "/interface/sessions/{session_key}/messages",
            "internal interface/API clients",
            "POST /interface/sessions/{session_key}/messages",
            "mim-training-web.service / port 18021",
            "InterfaceMessageCreate",
            "session_key",
            "interface session store",
            "none here; stores messages that later feed cognitive paths",
            "approval/recovery handling",
            "interface_service append_interface_message",
            ["approval required", "recovery message"],
            "interface recovery message",
            [],
            ["message serialization"],
            [],
            "message/session payload",
            "interface messages table/store",
            False,
            "surface adapter only if not used to synthesize replies",
            False,
            False,
            False,
            True,
            "Allowed Surface Adapter",
            ["interface.py /interface/sessions/{session_key}/messages"],
        ),
        outlet(
            "TOD operator console chat",
            "/tod and /chat",
            "core/routers/tod_ui.py sendChatPrompt",
            "POST /tod/ui/chat/message or POST /chat/ui/message",
            "mim-training-web.service / port 18021",
            "TOD chat payload",
            "session_key",
            "TOD UI state and execution feed",
            "_compose_tod_reply/_compose_operator_reply local interpretation",
            "TOD UI mode branch",
            "_compose_tod_reply/_compose_operator_reply",
            ["training action", "handoff", "execution feed"],
            "chat unavailable/error text",
            [],
            ["TOD-specific status text"],
            [],
            "messages/chat payload",
            "TOD UI chat state JSONL",
            False,
            "not MIM cognitive authority but can display MIM/TOD coordination text",
            True,
            True,
            False,
            True,
            "Duplicate Cognitive Debt",
            ["tod_ui.py /tod/ui/chat/message", "tod_ui.py /chat/ui/message", "tod_ui.py _compose_operator_reply"],
        ),
        outlet(
            "State bus MIM/TOD reactions",
            "/state-bus/consumers/mim-core/step and /state-bus/reactions/mim-tod/step",
            "background/state-bus clients",
            "POST state-bus step routes",
            "mim-training-web.service / port 18021",
            "state bus step payload",
            "consumer_key/reaction id",
            "state_bus_service",
            "state-bus consumer/reaction semantics",
            "state_bus route functions",
            "state_bus_service reaction payload",
            ["poll", "ack", "replay"],
            "reaction fallback/error",
            [],
            ["event serialization"],
            [],
            "reaction/result payload",
            "state bus records",
            False,
            "not proven as surface adapter; can produce visible lifecycle summaries",
            True,
            True,
            False,
            True,
            "Duplicate Cognitive Debt",
            ["state_bus.py /state-bus/consumers/mim-core/step", "state_bus.py /state-bus/reactions/mim-tod/step"],
        ),
        outlet(
            "Studio training page summaries",
            "/studio/training",
            "Studio training page side panel posts to /studio/api/mim/chat",
            "POST /studio/api/mim/chat with training page_context",
            "mim-training-web.service / port 18021",
            "StudioMimChatRequest",
            "thread_id/recent_messages",
            "_studio_training_state plus runtime/shared scorecards",
            "studio training branches before/after shared interpretation",
            "_compose_training_page_reply/_compose_training_scorecard_reply",
            "training page composers",
            ["training attention continuation", "attention prompt append"],
            "_studio_operator_contract_fallback_reply",
            ["five-field recommendation append"],
            ["training state summarization"],
            [],
            "mim_interface.reply_text",
            "studio chat history",
            True,
            "weak: training branch can override final answer",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["studio.py _compose_training_page_reply", "studio.py studio_mim_chat_api training branch"],
        ),
        outlet(
            "Studio objective/project summaries",
            "/studio/objectives, /studio/projects",
            "Studio pages and side panel",
            "GET page summaries plus POST /studio/api/mim/chat",
            "mim-training-web.service / port 18021",
            "page state loaders plus chat payload",
            "project/objective ids and thread id",
            "_studio_projects_state/objective artifacts/runtime shared",
            "page-specific project/status helpers",
            "_studio_project_blocker_reply, _studio_operator_contract_fallback_reply, navigation",
            "Studio project composers",
            ["project stewardship", "project blocker", "navigation"],
            "_studio_operator_contract_fallback_reply",
            ["_studio_with_response_authority"],
            ["page-specific HTML summaries"],
            [],
            "HTML plus mim_interface.reply_text",
            "DB StudioProject and chat history",
            True,
            "weak: page-specific project logic can answer independently",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["studio.py _studio_projects_state", "studio.py _studio_project_blocker_reply", "studio.py _studio_operator_contract_fallback_reply"],
        ),
        outlet(
            "Mobile/phone MIM adapter",
            "mobile MIM / phone-to-MIM",
            "documented endpoint references",
            "POST /gateway/intake/text",
            "mim-mobile-web.service / port 18001",
            "TextInputAdapterRequest",
            "conversation_session_id or phone session",
            "gateway operational context",
            "gateway lane",
            "gateway lane",
            "gateway lane",
            ["gateway deterministic branches"],
            "gateway fallback",
            ["MIM UI wrapper if rendered"],
            ["thin-client formatting"],
            [],
            "mim_interface.reply_text",
            "InputEvent/InputEventResolution",
            True,
            "inherits gateway partial obedience",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["gateway.py phone_to_mim_message_endpoint references /gateway/intake/text"],
        ),
        outlet(
            "Voice input",
            "/mim voice listener",
            "core/routers/mim_ui.py submitConversationTurn(transcript, 'voice')",
            "POST /gateway/intake/text",
            "mim-mobile-web.service / port 18001",
            "browser SpeechRecognition transcript -> text adapter metadata source=mim_ui_voice_chat",
            "textChatSessionId",
            "gateway context plus voice metadata",
            "gateway lane",
            "gateway lane",
            "gateway lane",
            ["identity/wake-word handling in MIM UI", "gateway deterministic branches"],
            "gateway fallback",
            ["MIM UI voice display"],
            ["voice transcript filtering/language hints"],
            ["browser SpeechRecognition"],
            "mim_interface.reply_text",
            "InputEvent/InputEventResolution plus MIM UI state",
            True,
            "inherits gateway partial obedience",
            True,
            True,
            True,
            True,
            "Duplicate Cognitive Debt",
            ["mim_ui.py submitConversationTurn interactionMode='voice'"],
        ),
        outlet(
            "Voice output",
            "/gateway/voice/tts and /gateway/voice/output",
            "core/routers/mim_ui.py speakLocally/speakWithServerTts",
            "POST /gateway/voice/tts and POST /gateway/voice/output",
            "mim-mobile-web.service / port 18001",
            "voice text/audio payload",
            "voice output id",
            "voice policy and MIM UI state",
            "none, should be rendering only",
            "none",
            "TTS renderer",
            ["do-not-disturb", "mic suppression"],
            "browser TTS fallback",
            [],
            ["spoken text truncation/audio failure messages"],
            ["server TTS audio", "browser speechSynthesis"],
            "audio/status",
            "voice output state/event logs",
            False,
            "surface adapter if rendering only",
            False,
            True,
            False,
            True,
            "Allowed Surface Adapter",
            ["mim_ui.py /gateway/voice/tts", "mim_ui.py /gateway/voice/output"],
        ),
        outlet(
            "Notification/proactive MIM messages",
            "background jobs and MIM UI state",
            "autonomy_driver_service/self_health_monitor/runtime_recovery",
            "runtime/shared and UI state endpoints",
            "background workers plus mim services",
            "scheduled/background event payloads",
            "objective/task/session ids",
            "runtime/shared artifacts",
            "service-specific lifecycle classifiers",
            "service-specific summary builders",
            "background lifecycle summary text",
            ["autonomy driver fallback continue", "self health summaries", "runtime recovery summaries"],
            "service error/status fallback",
            [],
            ["status summary wording"],
            ["state polling"],
            "status/summary fields",
            "runtime/shared latest artifacts",
            False,
            "not unified",
            True,
            True,
            False,
            True,
            "Duplicate Cognitive Debt",
            ["autonomy_driver_service.py summary builders", "self_health_monitor.py", "runtime_recovery_service.py"],
        ),
        outlet(
            "Fallback/error responses",
            "all surfaces",
            "frontend catch blocks and backend exception handlers",
            "many",
            "all services",
            "exception/status normalization",
            "request/session id when available",
            "local exception context",
            "none",
            "error branch",
            "inline fallback strings",
            ["HTTP 401/524 handling", "chat unavailable", "MIM taking too long"],
            "inline frontend/backend error text",
            [],
            ["frontend status text replacement"],
            [],
            "error/status/detail/message",
            "often not persisted",
            False,
            "deterministic boundary if kept factual",
            False,
            True,
            False,
            False,
            "Deterministic Boundary",
            ["mim_ui.py 401/524/error fallbacks", "frontend catch blocks"],
        ),
    ]

    duplicate_paths = [
        {
            "path": "core/routers/studio.py::studio_mim_chat_api",
            "classification": "Duplicate Cognitive Debt",
            "why": "Builds shared interpretation but then executes a local branch chain that can interpret, choose mode, compose, replace, and append before falling back.",
            "must_become": "surface adapter around sole MIM response authority",
        },
        {
            "path": "core/routers/studio.py::_studio_conversation_purpose_reply",
            "classification": "Duplicate Cognitive Debt",
            "why": "Calls conversation_purpose_engine directly and produced the hypothesis/exploration failure for a status question.",
            "must_become": "removed or delegated to sole response authority",
        },
        {
            "path": "core/conversation_purpose_engine.py::classify_conversation_purpose/build_conversation_purpose_reply",
            "classification": "Duplicate Cognitive Debt",
            "why": "Independently recognizes social/status/exploration/project modes and can compose full MIM personality text.",
            "must_become": "subroutine owned by sole authority, not route-callable final composer",
        },
        {
            "path": "core/routers/gateway.py::_compose_conversation_reply",
            "classification": "Duplicate Cognitive Debt",
            "why": "Can replace artifact-grounded fallbacks with deterministic/OpenAI communication composition after shared interpretation.",
            "must_become": "internal stage of sole response authority with interpretation conflict checks",
        },
        {
            "path": "core/communication_composer.py::compose_expert_communication_reply",
            "classification": "Duplicate Cognitive Debt",
            "why": "Can rewrite visible final answer and choose/alter response_mode; OpenAI rewrite was observed replacing status with greeting.",
            "must_become": "style-only surface constrained by authoritative interpretation",
        },
        {
            "path": "core/routers/gateway.py::_build_mim_interface_response",
            "classification": "Duplicate Cognitive Debt",
            "why": "Selects detail/result, mutates first person, and appends operator-impact contract after composition.",
            "must_become": "serializer only; wrappers must be authorized by response authority",
        },
        {
            "path": "core/routers/public_chat.py::public_chat_message/_compose_public_reply",
            "classification": "Duplicate Cognitive Debt",
            "why": "Public chat has its own public project/research/conversation-purpose branch chain and fallback reply.",
            "must_become": "public disclosure adapter over sole authority",
        },
        {
            "path": "core/routers/tod_ui.py::_compose_tod_reply/_compose_operator_reply",
            "classification": "Duplicate Cognitive Debt",
            "why": "Produces operator-visible coordination text outside the shared MIM interpretation model.",
            "must_become": "TOD-surface adapter or explicit non-MIM voice",
        },
        {
            "path": "core/routers/state_bus.py::mim-core and mim-tod step routes",
            "classification": "Duplicate Cognitive Debt",
            "why": "Background lifecycle/reaction text can become visible without shared interpretation provenance.",
            "must_become": "transport/event adapter; MIM-visible summaries composed by sole authority",
        },
        {
            "path": "core/routers/mim_ui.py JavaScript voice/status summarization",
            "classification": "Surface Adapter With Mutation Risk",
            "why": "Frontend summarizeTextResolution and voice rendering can transform what the user sees/hears.",
            "must_become": "presentation-only; no semantic replacement",
        },
    ]

    runtime_provenance = {
        "generated_at": generated_at,
        "provenance_schema_required_for_future_live_responses": {
            "mim_identity": "MIM",
            "surface": "",
            "service": "",
            "session_key": "",
            "interpretation_source": "",
            "interpretation_id": "",
            "conversation_purpose": "",
            "response_mode": "",
            "context_source": "",
            "composer_source": "",
            "final_answer_source": "",
            "deterministic_handlers_used": [],
            "fallback_used": False,
            "wrappers_applied": [],
            "post_composer_mutations": [],
            "prior_fragment_reused": False,
        },
        "current_probe_observations": [
            provenance(
                surface="/studio/projects side panel",
                service="mim-training-web.service:18021",
                session_key="studio thread",
                interpretation_source="studio_mim_chat_api -> _studio_conversation_purpose_reply",
                interpretation_id="not exposed before audit",
                conversation_purpose="exploration",
                response_mode="exploration",
                context_source="Studio page_context + conversation_purpose_engine",
                composer_source="conversation_purpose_engine._build_exploratory_reasoning_reply",
                final_answer_source="studio_conversation_purpose_engine",
                deterministic_handlers=["studio local branch chain"],
                fallback_used=False,
                wrappers=[],
                mutations=["_studio_with_response_authority metadata only"],
                prior_reused=False,
                prompt="Hi MIM, what did you work on today?",
                visible_response_observation="Returned generic 'My first working hypothesis...' exploration text for a status question.",
            ),
            provenance(
                surface="/studio/mim embedded /mim",
                service="mim-mobile-web.service:18001 via Studio embed",
                session_key="mim ui textChatSessionId",
                interpretation_source="mim_cognitive_entrypoint was present in metadata after containment work",
                interpretation_id="operator_current_state/grounded_status observed in gateway metadata",
                conversation_purpose="status intended, but overridden",
                response_mode="greeting/communication reply plus contract append",
                context_source="gateway live operational context",
                composer_source="communication_composer.openai_rewrite or deterministic fallback from _compose_conversation_reply",
                final_answer_source="_build_mim_interface_response",
                deterministic_handlers=["gateway route preference", "_mim_operator_impact_contract_applies"],
                fallback_used=True,
                wrappers=["_mim_append_operator_impact_contract"],
                mutations=["_mim_clean_operator_reply_boilerplate", "_mim_enforce_first_person_normal_reply"],
                prior_reused=False,
                prompt="Hi MIM, what did you work on today?",
                visible_response_observation="Returned greeting-only 'Hi! I'm MIM...' and appended unrelated recommended action/owner/evidence/aging/Dave-needed block.",
            ),
            provenance(
                surface="/public/chat/message",
                service="mim-training-web.service:18021",
                session_key="public session_key",
                interpretation_source="public_chat_message -> build_mim_cognitive_interpretation plus public branch chain",
                interpretation_id="not uniformly exposed",
                conversation_purpose="depends on public branch/cognitive/conversation_purpose_engine",
                response_mode="public reply",
                context_source="public profile, active public project, interface history",
                composer_source="public_chat._compose_public_reply or conversation_purpose_engine",
                final_answer_source="reply.content",
                deterministic_handlers=["public command block", "research context", "project planning"],
                fallback_used=True,
                wrappers=["public disclosure limits"],
                mutations=["profile/recall merge"],
                prior_reused=True,
                prompt="cross-surface prompts pending full instrumented probe",
                visible_response_observation="Public path is mapped; requires audit provenance field to prove final source per response.",
            ),
        ],
        "missing_live_provenance_gap": "Major outlets do not yet emit the full required provenance schema. Adding that schema is the only behavior-adjacent change permitted next.",
    }

    counts = {
        "mim_response_outlets_mapped": len(outlets),
        "interpretation_paths_identified": 10,
        "final_composers_identified": 17,
        "fallbacks_that_can_produce_operator_visible_text": 9,
        "wrappers_or_mutators_after_composition": 8,
        "outlets_calling_shared_cognitive_entrypoint": sum(1 for item in outlets if item["calls_shared_cognitive_entrypoint"]),
        "outlets_with_partial_or_weak_obedience": sum(1 for item in outlets if item["obeys_shared_interpretation"].startswith(("partial", "weak", "inherits"))),
        "duplicate_cognitive_debt_paths": len(duplicate_paths),
    }

    outlet_map = {
        "objective_id": "MIM-UNIFIED-RESPONSE-AUTHORITY-AUDIT-V1",
        "generated_at": generated_at,
        "source_scan": source_scan,
        "counts": counts,
        "outlets": outlets,
    }
    write_json("MIM_RESPONSE_OUTLET_MAP.latest.json", outlet_map)

    duplicate_payload = {
        "objective_id": "MIM-UNIFIED-RESPONSE-AUTHORITY-AUDIT-V1",
        "generated_at": generated_at,
        "counts": counts,
        "duplicate_cognitive_paths": duplicate_paths,
        "allowed_surface_adapters": [
            "mim_ui.py HTML/JS transport and presentation after semantic replacement is removed",
            "studio.py authentication/page shell/navigation transport after semantic response is delegated",
            "public_chat.py public identity/session/disclosure adapter after semantic response is delegated",
            "voice TTS and browser speech rendering",
            "interface.py session persistence",
            "state_bus.py event transport/poll/ack/replay",
            "fallback/error handling limited to factual transport errors",
        ],
    }
    write_json("MIM_DUPLICATE_COGNITIVE_PATHS.latest.json", duplicate_payload)
    write_json("MIM_CROSS_SURFACE_RESPONSE_PROVENANCE.latest.json", runtime_provenance)

    graph = f"""# MIM Response Authority Graph

Generated: {generated_at}

## Current Topology

There is one MIM identity, but the application currently has {counts['mim_response_outlets_mapped']} mapped MIM-connected response outlets and at least {counts['interpretation_paths_identified']} interpretation paths.

```text
/mim and /studio/mim
  -> mim_ui.py JavaScript
  -> POST /gateway/intake/text
  -> gateway.py intake_text
  -> gateway.py _resolve_event
  -> optional build_mim_cognitive_interpretation
  -> gateway deterministic branches
  -> _compose_conversation_reply
  -> communication_composer deterministic/OpenAI rewrite
  -> _build_mim_interface_response
  -> first-person cleanup / operator-contract append
  -> mim_interface.reply_text

/studio/projects and Studio side panel
  -> studio.py JavaScript
  -> POST /studio/api/mim/chat
  -> studio_mim_chat_api
  -> build_mim_cognitive_interpretation
  -> Studio local branch chain
  -> _studio_conversation_purpose_reply / mode guards / training / project / lab / reports / navigation / fallback
  -> mim_interface.reply_text

public chat
  -> POST /public/chat/message
  -> public_chat_message
  -> public profile/history/research context
  -> build_mim_cognitive_interpretation
  -> public branch chain and conversation_purpose_engine
  -> reply.content

TOD/operator/background lanes
  -> tod_ui.py, state_bus.py, autonomy/self-health/runtime services
  -> local status/reaction/summary composers
  -> operator-visible text or artifacts
```

## Proven Bad Paths

### /studio/projects hypothesis response

`/studio/projects` uses the Studio side panel, which posts to `/studio/api/mim/chat`. `studio_mim_chat_api` builds a shared interpretation, but it then continues through Studio-local handlers. The response that said `My first working hypothesis...` is attributable to `_studio_conversation_purpose_reply`, which calls `conversation_purpose_engine.build_conversation_purpose_reply`; that engine classified the status question as exploration and composed `_build_exploratory_reasoning_reply`.

### /studio/mim greeting plus operational wrapper

`/studio/mim` embeds `/mim`. `/mim` posts to `/gateway/intake/text`. The gateway lane can build the shared interpretation, but the final answer still passes through `_compose_conversation_reply`, `communication_composer.compose_expert_communication_reply`, and `_build_mim_interface_response`. Live observation showed the intended grounded/status interpretation was present while `communication_reply_contract` had an `openai_rewrite` composer. `_build_mim_interface_response` then selected/cleaned the reply and appended `_mim_append_operator_impact_contract`, producing greeting plus unrelated action/owner/evidence/aging/Dave-needed fields.

## Authority Classification

- Cognitive Authority should be exactly one component: a new consolidated MIM Response Authority built from `core/mim_cognitive_entrypoint.py` plus a single final-answer composer.
- Deterministic Boundaries should remain safety, auth, public disclosure, schema validation, route availability, TTS availability, and error reporting.
- Surface Adapters should handle HTML, JSON, voice, streaming, history, session, auth, and public/private formatting only.
- Duplicate Cognitive Debt includes `studio_mim_chat_api`, `_studio_conversation_purpose_reply`, `conversation_purpose_engine` as final route composer, gateway `_compose_conversation_reply`, `communication_composer` as unconstrained rewrite authority, public chat branch composition, TOD UI operator composers, and background lifecycle summary composers.
"""
    write_md("MIM_RESPONSE_AUTHORITY_GRAPH.latest.md", graph)

    plan = f"""# MIM Single Response Authority Consolidation Plan

Generated: {generated_at}

## Answers Required By Audit

- MIM response outlets mapped: {counts['mim_response_outlets_mapped']}.
- Interpretation paths identified: {counts['interpretation_paths_identified']}.
- Final composers identified: {counts['final_composers_identified']}.
- Fallbacks that can produce operator-visible text: {counts['fallbacks_that_can_produce_operator_visible_text']}.
- Wrappers/mutators after composition: {counts['wrappers_or_mutators_after_composition']}.

## Sole Authority Target

Create one `MIM Response Authority` service as the only component allowed to:

- interpret operator/visitor intent,
- resolve follow-ups,
- select response mode,
- choose evidence,
- compose semantic answer,
- authorize whether a contract or wrapper can appear.

The existing `core/mim_cognitive_entrypoint.py` is a starting point, not sufficient authority by itself. It must own both interpretation and final-answer authorization, or delegate to a single composer under a strict interpretation contract.

## Smallest Safe Consolidation Sequence

1. Add audit-only provenance to every mapped major outlet. Required fields: `mim_identity`, `surface`, `service`, `session_key`, `interpretation_source`, `interpretation_id`, `conversation_purpose`, `response_mode`, `context_source`, `composer_source`, `final_answer_source`, `deterministic_handlers_used`, `fallback_used`, `wrappers_applied`, `post_composer_mutations`, and `prior_fragment_reused`.
2. Build `MIMResponseAuthorityResult` with a stable schema: interpretation, response_mode, allowed_surface_mutations, final_answer, evidence_refs, and wrapper_authorization.
3. Route `/gateway/intake*`, `/studio/api/mim/chat`, `/public/chat/message`, voice input, mobile text, and proactive summaries through that result before any page-specific logic.
4. Convert Studio branches to deterministic boundaries or context loaders. They may supply page context and evidence, but may not compose unrelated final answers.
5. Convert `communication_composer` to style-only rewrite. It must reject or preserve replies if the rewrite changes `conversation_purpose`, `response_mode`, evidence boundary, or wrapper authorization.
6. Convert `_build_mim_interface_response` to serializer only. It may not append operator contracts unless the authority result explicitly allows it.
7. Convert public chat to public-disclosure adapter only. Public-specific safety and capability limits may narrow content, not reinterpret intent.
8. Convert TOD UI/state-bus/background summaries to explicit non-MIM voice or require MIM authority for MIM-visible operator summaries.
9. Run the six cross-surface prompts against every outlet and compare semantic interpretation, not exact formatting.

## Components That Should Remain Surface Adapters

- `core/routers/mim_ui.py`: HTML, browser JS, auth redirect, attachments, local/server TTS, state display.
- `core/routers/studio.py`: Studio shell, auth, page context collection, navigation target execution, chat-history storage.
- `core/routers/public_chat.py`: public visitor/session/profile handling and disclosure limits.
- `core/routers/interface.py`: session/message persistence.
- `core/routers/state_bus.py`: poll/ack/replay/event transport.
- voice routes and browser speech: rendering only.
- fallback/error handlers: transport or unavailable-capability messages only.

## Stop Conditions

- Do not add more phrase variants.
- Do not fix one route before provenance proves the final-answer source.
- Do not count `build_mim_cognitive_interpretation` imports as unification.
- Do not allow a route-local composer to produce MIM personality text after the authority result.

## Next Authorized Work

Only provenance instrumentation is authorized before behavior consolidation. The first implementation slice should make every major outlet return or log the required provenance object without changing MIM's wording.
"""
    write_md("MIM_SINGLE_RESPONSE_AUTHORITY_CONSOLIDATION_PLAN.latest.md", plan)

    final_answer_mutations = [
        {
            "component": "core/routers/gateway.py::_compose_conversation_reply",
            "stage": "semantic composer before interface assembly",
            "input_text_source": "gateway _conversation_response fallback_reply",
            "output_text_source": "reply_text plus communication_reply_contract",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": True,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "prohibited semantic mutation unless this becomes the sole authority",
            "evidence": [
                "Calls compose_expert_communication_reply after fallback generation.",
                "Can preserve deterministic fallback only when _should_preserve_operational_fallback catches it.",
            ],
            "required_change": "Only the single MIM response authority may call this as a semantic composer; otherwise it must be removed or made style-only under immutable final-answer policy.",
        },
        {
            "component": "core/communication_composer.py::compose_expert_communication_reply",
            "stage": "secondary communication composer",
            "input_text_source": "fallback_reply and deterministic_reply",
            "output_text_source": "ExpertCommunicationReply.reply_text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": True,
            "shared_interpretation_authorizes_change": "not enforced; context response_mode is advisory",
            "classification": "prohibited semantic mutation after authority; allowed only as sole-authority composer or constrained style pass",
            "evidence": [
                "OpenAI rewrite path sets composer_mode='openai_rewrite'.",
                "Model prompt asks it to rewrite a safe fallback into a natural expert conversation reply.",
            ],
            "required_change": "If retained downstream, it must preserve semantic hash/response_mode/evidence boundary and refuse rewrites that alter intent.",
        },
        {
            "component": "core/communication_composer.py::build_deterministic_communication_reply",
            "stage": "deterministic fallback composer",
            "input_text_source": "fallback_reply",
            "output_text_source": "ExpertCommunicationReply.reply_text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "duplicate cognitive debt",
            "evidence": [
                "Rewrites greeting/identity/clarifier text.",
                "Can apply answer_first and operator-impact contract.",
            ],
            "required_change": "Move inside the sole authority or reduce to formatting with explicit final-answer authorization.",
        },
        {
            "component": "core/communication_composer.py::_apply_operator_impact_contract_if_needed",
            "stage": "post-composer contract append",
            "input_text_source": "ExpertCommunicationReply.reply_text",
            "output_text_source": "ExpertCommunicationReply.reply_text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced by immutable final-answer object",
            "classification": "prohibited semantic append unless final-answer authority explicitly allows it",
            "evidence": [
                "Appends recommendation/owner/evidence/aging/Dave-needed fields to visible text.",
            ],
            "required_change": "Emit operator-impact fields as metadata; render visibly only when operator_contract_allowed=true.",
        },
        {
            "component": "core/routers/gateway.py::_build_mim_interface_response",
            "stage": "interface assembly after resolution/composition",
            "input_text_source": "resolution metadata, communication_reply_contract.reply_text, result/blocker/detail",
            "output_text_source": "mim_interface.reply_text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "prohibited semantic mutation; should be serializer only",
            "evidence": [
                "Selects operator_reply_override/detail_value/result/blocker.",
                "Calls _mim_clean_operator_reply_boilerplate.",
                "Calls _mim_enforce_first_person_normal_reply.",
                "Calls _mim_append_operator_impact_contract unless suppressed.",
            ],
            "required_change": "Treat final_answer as immutable; package metadata separately; no visible concatenation without authority permission.",
        },
        {
            "component": "core/routers/gateway.py::_mim_clean_operator_reply_boilerplate",
            "stage": "post-composer text cleanup",
            "input_text_source": "reply_text",
            "output_text_source": "reply_text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": False,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "permitted formatting only after restricted to mechanical cleanup",
            "evidence": [
                "Runs inside _build_mim_interface_response before final visible reply.",
            ],
            "required_change": "Limit to whitespace/transport cleanup; no boilerplate removal that changes semantic content.",
        },
        {
            "component": "core/routers/gateway.py::_mim_enforce_first_person_normal_reply",
            "stage": "post-composer pronoun/person rewrite",
            "input_text_source": "reply_text",
            "output_text_source": "reply_text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": False,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "prohibited semantic mutation unless sole authority emits first-person text already",
            "evidence": [
                "Replaces 'MIM is'/'MIM should'/'MIM must' etc. with first-person forms.",
            ],
            "required_change": "Move first-person decision into the authoritative composer; downstream may not rewrite person.",
        },
        {
            "component": "core/routers/gateway.py::_mim_append_operator_impact_contract",
            "stage": "post-composer visible contract append",
            "input_text_source": "reply_text plus raw_input",
            "output_text_source": "reply_text with contract block",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "prohibited semantic append unless final-answer authority explicitly allows it",
            "evidence": [
                "Adds Recommended action, Owner, Expected evidence, Aging rule, Dave needed to visible reply.",
            ],
            "required_change": "Return contract as structured metadata and require operator_contract_allowed=true for visible rendering.",
        },
        {
            "component": "core/routers/studio.py::_studio_with_response_authority",
            "stage": "Studio response envelope/provenance wrapper",
            "input_text_source": "mim_interface.reply_text",
            "output_text_source": "response dict with evidence/authority metadata",
            "can_change_meaning": False,
            "can_change_tone": False,
            "can_append_content": False,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "metadata only",
            "classification": "permitted metadata packaging if kept non-semantic",
            "evidence": [
                "Adds response authority metadata around an existing reply.",
            ],
            "required_change": "Keep metadata-only; never alter final_answer.",
        },
        {
            "component": "core/routers/studio.py training attention append",
            "stage": "Studio training branch appends recommendation text",
            "input_text_source": "_compose_training_page_reply",
            "output_text_source": "reply plus appended_recommendation",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "duplicate cognitive debt / prohibited visible append unless authorized",
            "evidence": [
                "Training branch concatenates appended_recommendation with five-field contract text.",
            ],
            "required_change": "Move recommendation into metadata unless the sole authority selected operator-impact mode.",
        },
        {
            "component": "core/routers/mim_ui.py::summarizeTextResolution",
            "stage": "frontend visible text extraction",
            "input_text_source": "gateway response JSON",
            "output_text_source": "chat bubble text",
            "can_change_meaning": True,
            "can_change_tone": True,
            "can_append_content": True,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not enforced",
            "classification": "surface adapter with mutation risk",
            "evidence": [
                "Frontend appends the summarized resolution rather than directly rendering a final_answer field.",
            ],
            "required_change": "Render immutable final_answer for chat bubbles; use summaries only for debug panes.",
        },
        {
            "component": "core/routers/mim_ui.py::speakLocally/speakWithServerTts",
            "stage": "voice rendering",
            "input_text_source": "visible/chat text",
            "output_text_source": "spoken audio/status",
            "can_change_meaning": False,
            "can_change_tone": True,
            "can_append_content": False,
            "can_call_llm": False,
            "shared_interpretation_authorizes_change": "not needed if rendering only",
            "classification": "permitted surface adapter",
            "evidence": [
                "TTS path can fall back to browser voices and display voice failure status.",
            ],
            "required_change": "Do not substitute spoken semantic text; voice errors stay separate from MIM final answer.",
        },
    ]

    final_answer_audit = {
        "objective_id": "MIM-FINAL-ANSWER-AUTHORITY-AUDIT-V1",
        "generated_at": generated_at,
        "acceptance_rule": "Exactly one component may create or rewrite operator-visible semantic text. Everything after it is formatting, transport, metadata, safety boundary, or rendering only.",
        "honest_status": {
            "mim_identity_problem": "open",
            "interpretation_unification": "partial",
            "final_response_authority": "broken",
            "post_composer_mutation": "confirmed",
            "duplicate_llm_composition": "confirmed",
            "dave_needed": "no",
        },
        "counts": {
            "post_composer_or_second_composer_components_audited": len(final_answer_mutations),
            "components_that_can_change_meaning": sum(1 for item in final_answer_mutations if item["can_change_meaning"]),
            "components_that_can_append_content": sum(1 for item in final_answer_mutations if item["can_append_content"]),
            "components_that_can_call_llm": sum(1 for item in final_answer_mutations if item["can_call_llm"]),
            "prohibited_or_duplicate_components": sum(1 for item in final_answer_mutations if item["classification"].startswith(("prohibited", "duplicate"))),
        },
        "final_answer_boundary_required_schema": {
            "final_answer": "immutable operator-visible text",
            "response_mode": "authoritative mode selected before composition",
            "operator_contract_allowed": False,
            "allowed_surface_mutations": ["transport_formatting", "length_limit", "public_disclosure_redaction", "tts_rendering"],
            "metadata": {},
            "provenance": "required transformation chain",
        },
        "mutation_audit": final_answer_mutations,
        "next_safe_action": "Instrument provenance for every transformation from composed text to delivered text, then demote prohibited mutations before changing prompt behavior.",
    }
    write_json("MIM_FINAL_ANSWER_AUTHORITY_AUDIT.latest.json", final_answer_audit)

    final_answer_md = f"""# MIM Final Answer Authority Audit

Generated: {generated_at}

## Finding

The visible MIM response is not currently protected by a hard final-answer boundary. The audit found {final_answer_audit['counts']['post_composer_or_second_composer_components_audited']} composer or post-composer components in the delivery chain. {final_answer_audit['counts']['components_that_can_change_meaning']} can change meaning, {final_answer_audit['counts']['components_that_can_append_content']} can append content, and {final_answer_audit['counts']['components_that_can_call_llm']} can call an LLM after an earlier fallback/semantic answer exists.

## Rule

Exactly one component may create or rewrite operator-visible semantic text. Everything after that component is formatting, transport, metadata packaging, deterministic safety boundary, public/private disclosure enforcement, or voice rendering only.

## Confirmed Problem

The `/studio/mim` failure is explained by a stacked authority chain:

```text
input
  -> gateway resolution
  -> _conversation_response fallback
  -> _compose_conversation_reply
  -> communication_composer deterministic/OpenAI rewrite
  -> _build_mim_interface_response
  -> boilerplate cleanup
  -> first-person rewrite
  -> operator-impact contract append
  -> visible response
```

That chain lets multiple components impersonate MIM after the initial answer path has already started.

## Required Boundary

The authority result should look like:

```json
{{
  "final_answer": "...",
  "response_mode": "social_direct",
  "operator_contract_allowed": false,
  "allowed_surface_mutations": ["transport_formatting", "tts_rendering"]
}}
```

Downstream code may package or render this. It may not rewrite, reinterpret, append, or call another semantic composer unless the authority result explicitly allows that exact transformation.

## Immediate Cleanup Sequence

1. Make the shared composer return an immutable final-answer object.
2. Stop `_build_mim_interface_response` from rewriting `reply_text`.
3. Move operator-impact fields into structured metadata.
4. Append operator-impact fields to visible text only when `operator_contract_allowed=true`.
5. Stop `_compose_conversation_reply` from invoking a second LLM rewrite after an authoritative answer exists.
6. Add provenance showing every transformation from composed text to delivered text.
7. Test normalized semantic equality across `/mim`, `/studio/mim`, `/studio/projects`, `/studio/api/mim/chat`, `/gateway/intake/text`, and `/public/chat/message`.
"""
    write_md("MIM_FINAL_ANSWER_AUTHORITY_AUDIT.latest.md", final_answer_md)

    print(json.dumps({"generated_at": generated_at, "counts": counts, "artifacts": [
        "runtime/shared/MIM_RESPONSE_OUTLET_MAP.latest.json",
        "runtime/shared/MIM_RESPONSE_AUTHORITY_GRAPH.latest.md",
        "runtime/shared/MIM_DUPLICATE_COGNITIVE_PATHS.latest.json",
        "runtime/shared/MIM_CROSS_SURFACE_RESPONSE_PROVENANCE.latest.json",
        "runtime/shared/MIM_SINGLE_RESPONSE_AUTHORITY_CONSOLIDATION_PLAN.latest.md",
        "runtime/shared/MIM_FINAL_ANSWER_AUTHORITY_AUDIT.latest.json",
        "runtime/shared/MIM_FINAL_ANSWER_AUTHORITY_AUDIT.latest.md",
    ]}, indent=2))


if __name__ == "__main__":
    main()
