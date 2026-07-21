import importlib.util
import ast
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


_STUDIO_MODULE = None
_PURPOSE_MODULE = None


def _load_gateway_functions(*names):
    root = Path(__file__).resolve().parents[1]
    source_path = root / "core" / "routers" / "gateway.py"
    source = source_path.read_text(encoding="utf-8")
    tree = ast.parse(source)
    selected = [
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name in set(names)
    ]
    module_ast = ast.parse(
        "import re\n\n"
        "def _compact_text(value, max_length=120):\n"
        "    text = str(value).strip()\n"
        "    return text if len(text) <= max_length else text[: max_length - 3] + '...'\n"
    )
    module_ast.body.extend(selected)
    ast.fix_missing_locations(module_ast)
    namespace = {}
    exec(compile(module_ast, str(source_path), "exec"), namespace)
    return {name: namespace[name] for name in names}


def _import_studio_module():
    global _STUDIO_MODULE
    if _STUDIO_MODULE is not None:
        return _STUDIO_MODULE

    root = Path(__file__).resolve().parents[1]
    module_path = root / "core" / "routers" / "studio.py"

    class _FakeRouter:
        def get(self, *_args, **_kwargs):
            return lambda fn: fn

        def post(self, *_args, **_kwargs):
            return lambda fn: fn

    class _FakeBaseModel:
        pass

    def _field(*_args, default=None, default_factory=None, **_kwargs):
        return default_factory() if default_factory else default

    def _identity_value(*_args, default=None, **_kwargs):
        return default

    fastapi_module = types.ModuleType("fastapi")
    responses_module = types.ModuleType("fastapi.responses")
    pydantic_module = types.ModuleType("pydantic")
    sqlalchemy_module = types.ModuleType("sqlalchemy")
    sqlalchemy_engine_module = types.ModuleType("sqlalchemy.engine")
    sqlalchemy_ext_module = types.ModuleType("sqlalchemy.ext")
    sqlalchemy_asyncio_module = types.ModuleType("sqlalchemy.ext.asyncio")

    fastapi_module.APIRouter = lambda *_args, **_kwargs: _FakeRouter()
    fastapi_module.Body = _identity_value
    fastapi_module.Depends = _identity_value
    fastapi_module.Form = _identity_value
    fastapi_module.HTTPException = Exception
    fastapi_module.Request = object
    responses_module.HTMLResponse = object
    responses_module.RedirectResponse = object
    responses_module.Response = object
    pydantic_module.BaseModel = _FakeBaseModel
    pydantic_module.Field = _field
    sqlalchemy_module.func = types.SimpleNamespace(count=lambda: None)
    sqlalchemy_module.select = lambda *_args, **_kwargs: None
    sqlalchemy_module.text = lambda value: value
    sqlalchemy_engine_module.make_url = lambda value: value
    sqlalchemy_asyncio_module.AsyncSession = object
    sqlalchemy_asyncio_module.create_async_engine = lambda *_args, **_kwargs: None

    core_module = types.ModuleType("core")
    core_module.__path__ = [str(root / "core")]
    core_config_module = types.ModuleType("core.config")
    core_config_module.settings = types.SimpleNamespace()
    core_db_module = types.ModuleType("core.db")
    core_db_module.get_db = lambda: None
    core_auth_module = types.ModuleType("core.mim_ui_auth")
    core_auth_module.ensure_authenticated_mimtod_api_request = lambda *_args, **_kwargs: None
    core_auth_module.maybe_require_mimtod_page_login = lambda *_args, **_kwargs: None
    core_auth_module.request_has_valid_mimtod_auth = lambda *_args, **_kwargs: False
    core_auth_module.request_has_valid_mim_studio_test_auth = lambda *_args, **_kwargs: False
    core_routers_module = types.ModuleType("core.routers")
    core_gateway_module = types.ModuleType("core.routers.gateway")

    async def _fake_compose_conversation_reply(*_args, **_kwargs):
        return {"reply_text": "", "contract": {}}

    async def _fake_visitor_stats_reply(*_args, **_kwargs):
        return ""

    core_gateway_module._compose_conversation_reply = _fake_compose_conversation_reply
    core_gateway_module._mim_tod_visitor_stats_diagnostic_reply = _fake_visitor_stats_reply
    core_routers_module.gateway = core_gateway_module
    core_self_evolution_module = types.ModuleType("core.self_evolution_service")

    def _fake_build_natural_language_development_packet(*_args, **_kwargs):
        return {
            "slices": [
                {
                    "slice_id": "slice_03",
                    "title": "Planning Continuity",
                    "pass_bar_summary": "overall >= 0.84 and no repeated clarifier pattern",
                }
            ]
        }

    async def _fake_get_natural_language_development_progress(*_args, **_kwargs):
        return {
            "status": "repairing",
            "active_slice_title": "Planning Continuity",
            "active_slice": {
                "title": "Planning Continuity",
                "pass_bar_summary": "overall >= 0.84 and no repeated clarifier pattern",
            },
            "progress_summary": "Cycle 1 running with 2/6 slices completed this cycle. Active slice: Planning Continuity. Status: repairing.",
            "next_step_summary": "Repair Planning Continuity, rerun the pass bar, and only then auto-promote.",
            "completed_slice_ids": ["slice_01", "slice_02"],
            "last_evaluation": {
                "proof_summary": "Live Studio chat probe asked MIM to report current self-evolution focus from evidence and failed.",
                "failure_tags": ["progress_ledger_not_used", "planning_continuity_report_missing"],
            },
            "snapshot": {},
        }

    def _fake_apply_natural_language_progress_to_packet(*, packet, progress_state):
        hydrated = dict(packet)
        hydrated.update(
            {
                "active_slice": {
                    "title": "Planning Continuity",
                    "pass_bar_summary": "overall >= 0.84 and no repeated clarifier pattern",
                },
                "progress": {
                    **progress_state,
                    "active_slice_title": "Planning Continuity",
                },
                "progress_summary": progress_state.get("progress_summary", ""),
                "next_step_summary": progress_state.get("next_step_summary", ""),
            }
        )
        return hydrated

    core_self_evolution_module._apply_natural_language_progress_to_packet = _fake_apply_natural_language_progress_to_packet
    core_self_evolution_module._build_natural_language_development_packet = _fake_build_natural_language_development_packet
    core_self_evolution_module.get_natural_language_development_progress = _fake_get_natural_language_development_progress
    core_models_module = types.ModuleType("core.models")
    for name in (
        "MemoryEntry",
        "Objective",
        "ProjectPortalAccount",
        "ProjectPortalProject",
        "PublicVisitEvent",
        "StudioDocument",
        "StudioDocumentLink",
        "StudioProject",
        "StudioProjectEvent",
        "StudioProjectLink",
        "StudioProjectSignal",
        "StudioReportCanvas",
        "Task",
    ):
        setattr(core_models_module, name, type(name, (), {}))

    with patch.dict(
        sys.modules,
        {
            "fastapi": fastapi_module,
            "fastapi.responses": responses_module,
            "pydantic": pydantic_module,
            "sqlalchemy": sqlalchemy_module,
            "sqlalchemy.engine": sqlalchemy_engine_module,
            "sqlalchemy.ext": sqlalchemy_ext_module,
            "sqlalchemy.ext.asyncio": sqlalchemy_asyncio_module,
            "core": core_module,
            "core.config": core_config_module,
            "core.db": core_db_module,
            "core.mim_ui_auth": core_auth_module,
            "core.routers": core_routers_module,
            "core.routers.gateway": core_gateway_module,
            "core.self_evolution_service": core_self_evolution_module,
            "core.models": core_models_module,
        },
    ):
        module_name = "test_studio_router_module"
        sys.modules.pop(module_name, None)
        spec = importlib.util.spec_from_file_location(module_name, module_path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"Unable to load studio module from {module_path}")
        module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
        _STUDIO_MODULE = module
        return module


def _import_purpose_module():
    global _PURPOSE_MODULE
    if _PURPOSE_MODULE is not None:
        return _PURPOSE_MODULE

    root = Path(__file__).resolve().parents[1]
    module_path = root / "core" / "conversation_purpose_engine.py"
    module_name = "test_conversation_purpose_engine_module"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load purpose engine module from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    _PURPOSE_MODULE = module
    return module


class StudioTrainingChatTest(unittest.TestCase):
    def test_studio_chat_route_has_test_only_auth_harness(self):
        source = (Path(__file__).resolve().parents[1] / "core" / "routers" / "studio.py").read_text(
            encoding="utf-8"
        )
        auth_source = (Path(__file__).resolve().parents[1] / "core" / "mim_ui_auth.py").read_text(
            encoding="utf-8"
        )
        app_source = (Path(__file__).resolve().parents[1] / "core" / "app.py").read_text(
            encoding="utf-8"
        )

        self.assertIn('@router.post("/studio/api/mim/chat")', source)
        self.assertIn("maybe_require_mimtod_page_login", source)
        self.assertIn("MIM_STUDIO_TEST_AUTH_ENABLED", auth_source)
        self.assertIn("MIM_STUDIO_TEST_TOKEN", auth_source)
        self.assertIn("allow_test_auth: bool = False", auth_source)
        self.assertIn("allow_test_auth and request_has_valid_mim_studio_test_auth(request)", auth_source)
        self.assertIn("request_has_valid_mim_studio_test_auth(request)", app_source)
        self.assertIn('allowed_studio_chat = path == "/studio/api/mim/chat" and method == "POST"', app_source)
        self.assertIn('allowed_training_page = (', app_source)
        self.assertIn('method in {"GET", "HEAD"}', app_source)
        self.assertIn('path == "/studio/training" or path.startswith("/studio/training/")', app_source)

    def test_training_page_has_explicit_route_and_scorecard_visibility(self):
        studio = _import_studio_module()
        source = (Path(__file__).resolve().parents[1] / "core" / "routers" / "studio.py").read_text(
            encoding="utf-8"
        )

        self.assertIn('@router.get("/studio/{tab_key}"', source)
        self.assertIn('elif key == "training":', source)
        self.assertIn("Training", source)
        self.assertIn('next_path="/studio/training"', source)
        self.assertIn('next_path=f"/studio/training/{key}"', source)
        self.assertIn(
            'async def studio_training_attention_start',
            source,
        )
        attention_start = source.split("async def studio_training_attention_start", 1)[1].split(
            '@router.get("/studio/training/{section_key}"',
            1,
        )[0]
        self.assertNotIn("allow_test_auth=True", attention_start)

        html = studio._training_body(
            {
                "mim": {"focus": "MIM focus", "status": "training", "goal": "", "progress": "", "weakness": "", "next": ""},
                "tod": {"focus": "TOD focus", "status": "training", "goal": "", "progress": "", "weakness": "", "next": ""},
                "judgment": {},
                "mim_score": {},
                "tod_score": {},
                "reflection": {},
                "typo": {},
                "evidence_docs": [],
                "scorecard_artifacts": [
                    {
                        "title": "Cross-Surface Structural Reasoning",
                        "filename": "MIM_STRUCTURAL_REASONING_CROSS_SURFACE_SCORECARD.latest.json",
                        "category": "blocked-by-auth",
                        "status": "blocked",
                        "summary": "2/5 surfaces target met",
                        "age": "fresh",
                        "generated_at": "2026-06-12T20:30:36Z",
                    },
                    {
                        "title": "Real Movement Scorecard",
                        "filename": "MIM_TOD_REAL_MOVEMENT_SCORECARD.latest.json",
                        "category": "failing",
                        "status": "action_required",
                        "summary": "Validated TOD Edits: 1",
                        "age": "fresh",
                        "generated_at": "2026-06-12T20:30:36Z",
                    },
                ],
                "generated_at_la": "2026-06-12 13:30",
                "generated_age": "fresh",
                "are_improving": False,
                "outcome_verdict": "not proven",
                "attention_items": [],
                "attention_resolution_statuses": {},
                "attention_resolution": {},
                "live_training_activity": {},
                "project_counts": {},
                "objective_db_counts": {},
                "top_training_objective": {},
                "data_audit": {},
            }
        )

        self.assertIn("MIM/TOD Real Movement Scorecard", html)
        self.assertIn("Validated TOD Edits", html)
        self.assertIn("tod_result_artifacts", html)

    def test_studio_shell_chat_has_activity_and_attachment_surface(self):
        studio = _import_studio_module()

        html = studio._shell(
            active="training",
            title="Training",
            subtitle="",
            body="<section>Training body</section>",
            page_context="Studio Training",
            show_mim_panel=True,
        )

        self.assertIn('id="chatActivityBar"', html)
        self.assertIn('id="chatFileDrop"', html)
        self.assertIn('id="chatFileInput"', html)
        self.assertIn('id="chatHistorySource"', html)
        self.assertIn("/studio/api/mim/chat-history", html)
        self.assertIn("attachmentPromptText", html)
        self.assertIn("setAttachmentFromFile", html)
        self.assertIn('id="sendChat"', html)
        self.assertIn("chatInput.addEventListener", html)
        self.assertIn('id="chatFileDrop" class="chat-file-drop" role="button" tabindex="0"', html)
        self.assertIn("Drop a file here, or attach text, code, JSON, markdown, or an image reference.", html)

    def test_attention_prompt_gets_prioritized_action_reply(self):
        studio = _import_studio_module()

        reply = studio._compose_training_page_reply(
            "what needs attention MIM?",
            {
                "judgment": {
                    "pass_rate_percent": 20,
                    "current_weakness": "MIM defaults to status reporting instead of selecting a useful mode.",
                    "target": "Reach at least 80% on the focused V2 judgment suite.",
                },
                "mim_score": {
                    "intent_understood_today": 100,
                    "answered_question_today": 100,
                    "recommendation_quality_today": 100,
                },
                "tod_score": {
                    "blockers_cleared_today": 3,
                    "validated_edits_today": "baseline needed",
                    "no_op_rejections_today": "baseline needed",
                },
                "reflection": {
                    "stale_artifacts": 12,
                    "truth_integrity": "healthy",
                },
                "assessment": "needs attention",
                "are_improving": False,
            },
        )

        self.assertTrue(reply.startswith("Three things need attention"))
        self.assertIn("My judgment-mode selection is the top repair", reply)
        self.assertIn("TOD proof baselines still need tightening", reply)
        self.assertIn("turn the latest blocker drill into repeatable pass/fail validation", reply)
        self.assertIn("The next move I recommend is", reply)
        self.assertLess(reply.find("My judgment-mode"), reply.find("TOD proof baselines"))

    def test_studio_simple_direct_answers_day_and_france_followup(self):
        studio = _import_studio_module()

        day_reply = studio._studio_simple_direct_reply("What day of the week is it?", "Studio")
        france_reply = studio._studio_simple_direct_reply("what about in France?", "Studio")

        self.assertIsNotNone(day_reply)
        self.assertEqual(day_reply["response_mode"], "direct_answer")
        self.assertRegex(day_reply["mim_interface"]["reply_text"], r"Today is [A-Z][a-z]+, [A-Z][a-z]+ \d{1,2}, 20\d{2}\.")
        self.assertIsNotNone(france_reply)
        self.assertEqual(france_reply["response_mode"], "direct_answer")
        self.assertIn("In France", france_reply["mim_interface"]["reply_text"])

    def test_generic_training_prompt_uses_operator_contract_without_status_leakage(self):
        studio = _import_studio_module()

        reply = studio._compose_training_page_reply(
            "how is training going MIM?",
            {
                "judgment": {
                    "pass_rate_percent": 100,
                    "current_weakness": "MIM defaults to status reporting instead of selecting a useful mode.",
                },
                "outcome_verdict": "Training is active, but outcome improvement is not proven yet.",
            },
        )

        self.assertNotIn("Training is active, but the useful question", reply)
        self.assertNotIn("my mode-selection score", reply)
        self.assertNotIn("The outcome verdict is", reply)
        self.assertIn("converting the results into real movement", reply)
        self.assertIn("inspect a current-code target", reply)
        self.assertNotIn("I default to status reporting", reply)
        self.assertNotIn("MIM defaults", reply)
        self.assertIn("Recommended action:", reply)
        self.assertIn("Owner:", reply)
        self.assertIn("Expected evidence:", reply)
        self.assertIn("Time / aging rule:", reply)
        self.assertIn("Dave needed:", reply)

    def test_training_working_and_blocker_followups_are_not_replayed_status(self):
        studio = _import_studio_module()
        state = {
            "judgment": {
                "pass_rate_percent": 2,
                "current_weakness": "MIM defaults to status reporting instead of selecting a useful mode.",
            },
            "mim_score": {
                "metrics": {
                    "structural_reasoning_cross_surface": {
                        "today": {
                            "target_met_surface_count": 5,
                            "surface_count": 5,
                        }
                    }
                }
            },
            "tod_score": {
                "metrics": {
                    "validated_edits": {"today": {"status": "measured", "value": 5}},
                    "meaningful_tod_implementations": {"today": {"status": "measured", "value": 0}},
                    "independent_tod_resolutions": {"today": {"status": "measured", "value": 0}},
                }
            },
            "operator_impact": "10.0/10",
            "outcome_verdict": "Training is active, but outcome improvement is not proven yet.",
        }

        working = studio._compose_training_page_reply("what are you working on MIM?", state)
        blockers = studio._compose_training_page_reply("why not, are there blockers?", state)

        self.assertIn("converting the results into real movement", working)
        self.assertIn("Meaningful TOD Implementations", working)
        self.assertIn("The blocker is not that training stopped", blockers)
        self.assertIn("fresh, bounded current-code behavior change", blockers)
        self.assertIn("inspect a current-code target", blockers)
        self.assertNotEqual(working, blockers)
        self.assertNotIn("When you ask about training, I should tell you what needs attention first", working)
        self.assertNotIn("When you ask about training, I should tell you what needs attention first", blockers)

    def test_conversation_mode_selection_v2_routes_common_prompts(self):
        studio = _import_studio_module()

        cases = [
            ("What are you working on?", "explanation_mode", "conversation mode selection"),
            ("What should we work on next?", "recommendation_mode", "I recommend"),
            ("Build me an accounting app.", "consultative_discovery", "hidden requirement"),
            ("Why did this fail?", "problem_analysis", "failure-analysis"),
        ]

        for prompt, expected_mode, expected_text in cases:
            with self.subTest(prompt=prompt):
                reply = studio._studio_conversation_mode_reply(prompt, "Studio")
                self.assertIsNotNone(reply)
                self.assertEqual(reply["response_mode"], expected_mode)
                text = reply["mim_interface"]["reply_text"]
                self.assertIn(expected_text, text)
                self.assertIn("Recommended action:", text)
                self.assertIn("Owner:", text)
                self.assertIn("Expected evidence:", text)
                self.assertIn("Time / aging rule:", text)
                self.assertIn("Dave needed:", text)
                self.assertNotIn("packet", text.lower())
                self.assertNotIn("request_id", text.lower())

    def test_generic_training_prompt_explains_without_status_dump_leakage(self):
        studio = _import_studio_module()

        reply = studio._compose_training_page_reply(
            "how is training going MIM?",
            {
                "judgment": {
                    "pass_rate_percent": 0,
                    "current_weakness": "MIM defaults to status reporting instead of selecting a useful mode.",
                },
                "tod_score": {
                    "metrics": {
                        "validated_edits": {"today": {"status": "measured", "value": 10}},
                        "meaningful_tod_implementations": {"today": {"status": "measured", "value": 5}},
                        "independent_tod_resolutions": {"today": {"status": "measured", "value": 1}},
                    }
                },
                "outcome_verdict": "action required",
            },
        )

        self.assertFalse(reply.startswith("Training is active, but the useful question"))
        self.assertIn("converting the results into real movement", reply)
        self.assertIn("inspect a current-code target", reply)
        self.assertIn("Expected evidence:", reply)
        self.assertIn("Dave needed: no", reply)
        self.assertNotIn("my mode-selection score", reply)
        self.assertNotIn("The outcome verdict is", reply)
        self.assertNotIn("packet", reply.lower())
        self.assertNotIn("objective_id", reply.lower())

    def test_training_operator_live_prompt_families_do_not_leak_status_dump(self):
        studio = _import_studio_module()
        state = {
            "judgment": {
                "pass_rate_percent": 100,
                "current_weakness": "MIM defaults to status reporting instead of selecting a useful mode.",
            },
            "tod_score": {
                "metrics": {
                    "validated_edits": {"today": {"status": "measured", "value": 14}},
                    "meaningful_tod_implementations": {"today": {"status": "measured", "value": 8}},
                    "independent_tod_resolutions": {"today": {"status": "measured", "value": 1}},
                }
            },
            "operator_impact": "8.0/10",
            "outcome_verdict": "needs action",
        }
        cases = [
            ("is there anything you want to work on next?", "I recommend making TOD candidate selection"),
            ("any blockers?", "The blocker is not that training stopped"),
            ("tell me more about your training MIM", "converting the results into real movement"),
            ("the training page says needs attention. what should happen now?", "Recommended action:"),
            ("why is the current project blocked?", "The blocker is not that training stopped"),
            ("what is the highest value task right now?", "I recommend making TOD candidate selection"),
            ("MIM gave me a status dump again. what should happen?", "Treat that as a response-mode regression"),
            ("Validated TOD Edits is still 1. what should TOD do next?", "Validated TOD Edits are"),
            ("cross-surface scoring is blocked by auth. what is the next action?", "First verify whether auth is actually blocked"),
        ]

        for prompt, expected in cases:
            with self.subTest(prompt=prompt):
                reply = studio._compose_training_page_reply(prompt, state)
                self.assertIn(expected, reply)
                self.assertIn("Recommended action:", reply)
                self.assertIn("Owner:", reply)
                self.assertIn("Expected evidence:", reply)
                self.assertIn("Time / aging rule:", reply)
                self.assertIn("Dave needed:", reply)
                self.assertNotIn("Training is active, but the useful question", reply)
                self.assertNotIn("Right now my mode-selection score", reply)
                self.assertNotIn("The outcome verdict is", reply)

    def test_simple_direct_guard_does_not_intercept_operator_priority(self):
        studio = _import_studio_module()

        self.assertIsNone(studio._studio_simple_direct_reply("what is the highest value task right now?", "Studio Training"))

    def test_exploratory_reasoning_is_prompt_grounded_not_canned(self):
        purpose = _import_purpose_module()

        prompts = [
            "A manufacturing company has brilliant engineers but keeps missing deadlines. What capability do you think they are missing?",
            "A research project has many papers but confidence keeps dropping. What should MIM inspect?",
            "A team wants to build an automation tool for invoice routing. Where should discovery start?",
        ]
        replies = [
            purpose.build_conversation_purpose_reply(prompt, "Studio MIM")["reply_text"]
            for prompt in prompts
        ]

        for reply in replies:
            self.assertIn("My first working hypothesis", reply)
            self.assertIn("I could be wrong", reply)
            self.assertIn("The evidence I would want next", reply)
            self.assertNotIn("this is an exploration question", reply)
            self.assertNotIn("visible symptom may not be the root capability gap", reply)

        self.assertEqual(len(set(replies)), len(replies))
        self.assertIn("coordination", replies[0])
        self.assertIn("evidence quality", replies[1])
        self.assertIn("workflow constraint", replies[2])

    def test_live_self_evolution_prompt_is_not_hardcoded_in_production_core(self):
        root = Path(__file__).resolve().parents[1]
        live_prompt = "hi MIM what would you like to work on or learn today?"
        production_sources = [
            root / "core" / "conversation_purpose_engine.py",
            root / "core" / "routers" / "studio.py",
            root / "core" / "routers" / "gateway.py",
            root / "core" / "communication_composer.py",
        ]

        for path in production_sources:
            with self.subTest(path=str(path)):
                self.assertNotIn(live_prompt, path.read_text(encoding="utf-8").lower())

    def test_active_context_transition_handles_correction_before_purpose_engine(self):
        studio = _import_studio_module()

        reply = studio._studio_active_context_transition_reply(
            prompt="MIM can you undo what you just changed. That was not the intended instructions.",
            page_context="Studio MIM",
            last_user_input="MIM-EXPLORATORY-REASONING-ENGINE-V1 Mission: teach exploration.",
            last_prompt="Yes. I revised the homepage sample using your feedback.",
        )

        self.assertIsNotNone(reply)
        self.assertEqual(reply["source"], "studio_active_context_transition")
        self.assertEqual(reply["response_mode"], "correction_or_reversal")
        text = reply["mim_interface"]["reply_text"]
        self.assertIn("correcting the active thread", text)
        self.assertIn("without being repeated verbatim", text)
        self.assertNotIn("exploration question", text)

    def test_active_context_transition_handles_incident_status_followup(self):
        studio = _import_studio_module()

        reply = studio._studio_active_context_transition_reply(
            prompt="what is the status?",
            page_context="Studio MIM",
            last_user_input="VS Code will not open on the MIM Box.",
            last_prompt="I will inspect VS Code process state and logs before asking Dave.",
        )

        self.assertIsNotNone(reply)
        self.assertEqual(reply["source"], "studio_active_context_transition")
        self.assertEqual(reply["response_mode"], "status_followup")
        text = reply["mim_interface"]["reply_text"]
        self.assertIn("VS Code will not open", text)
        self.assertIn("status follow-up", text)
        self.assertNotIn("concrete fact source", text)

    def test_active_context_transition_handles_escalation_recovery_signal(self):
        studio = _import_studio_module()

        reply = studio._studio_active_context_transition_reply(
            prompt="you are off track",
            page_context="Studio MIM",
            last_user_input="MIM, train exploratory reasoning.",
            last_prompt="I changed the homepage instead.",
        )

        self.assertIsNotNone(reply)
        self.assertEqual(reply["source"], "studio_active_context_transition")
        self.assertEqual(reply["response_mode"], "escalation_recovery")
        text = reply["mim_interface"]["reply_text"]
        self.assertIn("escalation and recovery", text)
        self.assertIn("went off track", text)
        self.assertIn("proof will show recovery worked", text)
        self.assertNotIn("exploration question", text)

    def test_self_evolution_status_prompt_uses_progress_ledger_before_exploration(self):
        studio = _import_studio_module()

        import asyncio

        for prompt in (
            "MIM, report your current self-evolution learning focus from evidence.",
            "what is your current training status?",
            "what should we do next?",
            "what did you learn from this cycle?",
            "The probe failed. Report your current repair focus and smaller rung.",
            "What should happen after Intentions Stabilization passed?",
            "Why is Decision Flow Control the right continuation?",
            "What is the current recovery status?",
        ):
            with self.subTest(prompt=prompt):
                reply = asyncio.run(
                    studio._studio_self_evolution_status_reply(
                        prompt=prompt,
                        page_context="Studio MIM",
                        metadata={
                            "objective": "MIM-COGNITIVE-DEVELOPMENT-LOOP-1000-CONVERSATION-TRAINING-V1"
                        },
                        db=None,
                    )
                )

                self.assertIsNotNone(reply)
                self.assertEqual(reply["source"], "studio_self_evolution_status")
                self.assertEqual(reply["response_mode"], "self_evolution_focus_report")
                text = reply["mim_interface"]["reply_text"]
                self.assertIn("Planning Continuity", text)
                self.assertIn("progress_ledger_not_used", text)
                self.assertIn("Operator-visible command context", text)
                self.assertIn("What I learned from this cycle", text)
                self.assertIn("Memory to carry forward", text)
                self.assertIn("What I should not claim yet", text)
                self.assertNotIn("this is an exploration question", text)

    def test_operator_status_prompts_without_metadata_use_progress_ledger(self):
        studio = _import_studio_module()

        import asyncio

        for prompt in (
            "What are you working on MIM?",
            "Hi MIM what are you working on",
            "Are you training?",
            "What is your current training status and one bounded action?",
        ):
            with self.subTest(prompt=prompt):
                reply = asyncio.run(
                    studio._studio_self_evolution_status_reply(
                        prompt=prompt,
                        page_context="Studio MIM",
                        metadata={},
                        db=None,
                    )
                )

                self.assertIsNotNone(reply)
                self.assertEqual(reply["source"], "studio_self_evolution_status")
                self.assertEqual(reply["response_mode"], "self_evolution_operator_status")
                text = reply["mim_interface"]["reply_text"]
                self.assertIn("Planning Continuity", text)
                self.assertIn("What continues now", text)
                self.assertIn("Dave needed: no", text)
                self.assertNotIn("self-evolution ledger", text)
                self.assertNotIn("Operator-visible command context", text)
                self.assertNotIn("this is an exploration question", text)

    def test_studio_self_directed_focus_uses_progress_ledger_before_exploration(self):
        studio = _import_studio_module()

        import asyncio

        for prompt in (
            "hi MIM what would you like to work on or learn today?",
            "what would you like to explore today MIM?",
            "what would you like to focus training on?",
        ):
            with self.subTest(prompt=prompt):
                reply = asyncio.run(
                    studio._studio_self_evolution_status_reply(
                        prompt=prompt,
                        page_context="Studio MIM",
                        metadata={},
                        db=None,
                    )
                )

                self.assertIsNotNone(reply)
                self.assertEqual(reply["source"], "studio_self_evolution_status")
                self.assertEqual(reply["response_mode"], "self_evolution_operator_status")
                text = reply["mim_interface"]["reply_text"]
                lowered = text.lower()
                self.assertIn("i would focus training on", lowered)
                self.assertIn("why this outranks broader training", lowered)
                self.assertIn("next proof i would want", lowered)
                self.assertIn("second focus: tod independent resolution", lowered)
                self.assertIn("Dave needed: no", text)
                self.assertNotIn("My first working hypothesis", text)
                self.assertNotIn("Recommended action:", text)
                self.assertNotIn("Owner:", text)

    def test_durability_mode_selector_covers_smoke_families(self):
        studio = _import_studio_module()
        metadata = {"surface": "mim_conversation_mode_durability_v2"}
        cases = [
            ("What should we work on next?", "recommendation_mode", ["recommend", "because", "next", "blocker"]),
            ("Which training item matters most before Dave leaves?", "recommendation_mode", ["recommend", "because", "next", "blocker"]),
            ("Explain it to a non-technical user.", "explanation_mode", ["summary", "means", "next"]),
            ("What do you need from Dave?", "explanation_mode", ["summary", "Dave", "next"]),
            ("Show me a sample.", "demonstration_mode", ["sample", "review", "next"]),
            ("Build me an accounting app.", "consultative_discovery", ["workflow", "data", "?"]),
            ("Why did this fail?", "problem_analysis", ["problem", "root", "prevent", "Dave"]),
        ]

        for prompt, mode, expected_terms in cases:
            with self.subTest(prompt=prompt):
                reply = studio._studio_durability_mode_reply(prompt, "Studio Training", metadata)
                self.assertIsNotNone(reply)
                self.assertEqual(reply["response_mode"], mode)
                text = reply["mim_interface"]["reply_text"]
                lowered = text.lower()
                self.assertGreaterEqual(len(text), 120)

                self.assertNotIn("Training is active", text)
                self.assertNotIn("request_id", text.lower())
                for term in expected_terms:
                    self.assertIn(term.lower(), lowered)

    def test_gateway_self_directed_focus_selects_priorities_from_evidence(self):
        functions = _load_gateway_functions(
            "_is_self_directed_focus_query",
            "_self_evolution_next_work_response",
        )
        is_focus_query = functions["_is_self_directed_focus_query"]
        build_reply = functions["_self_evolution_next_work_response"]

        for prompt in (
            "what would you like to focus training on?",
            "MIM, what training would you choose for yourself?",
            "what should you focus your training on next?",
        ):
            with self.subTest(prompt=prompt):
                self.assertTrue(is_focus_query(prompt))

        context = {
            "self_evolution_briefing": {
                "decision": {
                    "summary": "repair mode selection across Studio MIM and project assistant surfaces",
                    "rationale": "recent failures show MIM can answer correctly on one surface and generically on another",
                },
                "snapshot": {
                    "summary": "single response authority is partially repaired, but self-directed focus still regresses",
                },
                "natural_language_development": {
                    "selected_skill_title": "Conversation mode selection",
                    "selected_skill": {
                        "development_goal": "choose explanation, recommendation, self-directed focus, or problem-analysis from context before composing"
                    },
                    "progress_summary": "operator status improved, but focus-selection prompts still ask Dave to choose",
                    "whats_next_framework_summary": "run the live self-directed focus prompt and verify no generic menu or contract block appears",
                },
            }
        }

        reply = build_reply(context, self_directed_focus=True)
        lowered = reply.lower()

        self.assertIn("i would focus first", lowered)
        self.assertIn("second", lowered)
        self.assertIn("outrank", lowered)
        self.assertIn("recent failures", lowered)
        self.assertIn("next proof", lowered)
        self.assertNotIn("what would you like me to do", lowered)
        self.assertNotIn("whatever you need", lowered)
        self.assertNotIn("recommended action:", lowered)
        self.assertNotIn("owner:", lowered)

    def test_durability_mode_selector_covers_recent_failure_prompts(self):
        studio = _import_studio_module()
        metadata = {"surface": "mim_conversation_mode_durability_v2"}
        cases = [
            (
                "Give me an example of a continuity brief.",
                "demonstration_mode",
                ["sample", "continuity brief", "review", "next"],
            ),
            (
                "Build a receipt tracking app.",
                "consultative_discovery",
                ["workflow", "hidden requirement", "two quick questions", "next action"],
            ),
            (
                "Build a mobile app for dog groomers.",
                "consultative_discovery",
                ["workflow", "hidden requirement", "two quick questions", "next action"],
            ),
            (
                "Build an app for field service scheduling.",
                "consultative_discovery",
                ["workflow", "hidden requirement", "two quick questions", "next action"],
            ),
            (
                "Why are projects moving but not closing?",
                "problem_analysis",
                ["failure-analysis", "root cause", "next action", "dave needed"],
            ),
            (
                "Why are the scorecards unchanged all week?",
                "problem_analysis",
                ["failure-analysis", "root cause", "next action", "dave needed"],
            ),
            (
                "Why are stale artifacts still showing?",
                "problem_analysis",
                ["failure-analysis", "root cause", "next action", "dave needed"],
            ),
        ]

        for prompt, mode, expected_terms in cases:
            with self.subTest(prompt=prompt):
                reply = studio._studio_durability_mode_reply(prompt, "Studio Training", metadata)
                self.assertIsNotNone(reply)
                self.assertEqual(reply["response_mode"], mode)
                text = reply["mim_interface"]["reply_text"]
                lowered = text.lower()
                self.assertNotIn("Training is active", text)
                self.assertNotIn("Here are the current scorecard numbers", text)
                self.assertNotIn("That belongs on", text)
                self.assertNotIn("request_id", lowered)
                self.assertNotIn("MIM_TOD_", text)
                for term in expected_terms:
                    self.assertIn(term.lower(), lowered)

    def test_operator_impact_failure_prompts_use_mode_guard_not_exploration(self):
        studio = _import_studio_module()
        cases = [
            (
                "any blockers?",
                "problem_analysis",
                ["failure-analysis", "root cause", "owner:", "time / aging rule:", "dave needed:"],
            ),
            (
                "is there anything you want to work on next?",
                "recommendation",
                ["recommend", "owner:", "expected evidence:", "time / aging rule:", "dave needed:"],
            ),
            (
                "tell me more about your training MIM",
                "explanation",
                ["plain summary", "owner:", "expected evidence:", "time / aging rule:", "dave needed:"],
            ),
            (
                "why is the current project blocked?",
                "problem_analysis",
                ["failure-analysis", "root cause", "owner:", "time / aging rule:", "dave needed:"],
            ),
            (
                "cross-surface scoring is blocked by auth. what is the next action?",
                "problem_analysis",
                ["failure-analysis", "root cause", "owner:", "time / aging rule:", "dave needed:"],
            ),
        ]

        for prompt, mode, expected_terms in cases:
            with self.subTest(prompt=prompt):
                reply = studio._studio_conversation_mode_guard_reply(
                    prompt,
                    "Studio Training",
                    operator_contract=True,
                )
                self.assertIsNotNone(reply)
                self.assertEqual(reply["response_mode"], mode)
                text = reply["mim_interface"]["reply_text"]
                lowered = text.lower()
                self.assertNotIn("first working hypothesis", lowered)
                self.assertNotIn("deepest capability gap", lowered)
                for term in expected_terms:
                    self.assertIn(term.lower(), lowered)

    def test_studio_mim_live_feed_uses_active_lane_and_recent_events(self):
        studio = _import_studio_module()

        def fake_load_json(name):
            payloads = {
                "TOD_ACTIVE_EXECUTION_LANE.latest.json": {
                    "status": "blocked",
                    "objective_id": "OBJ-LIVE",
                    "task_id": "TSK-LIVE",
                    "terminal_at": "2026-07-20T22:12:32Z",
                    "terminal_event_type": "bounded_edit_mode_missing",
                    "terminal_reason_code": "blocked_missing_bounded_edit_mode",
                    "terminal_message": "TOD needs exact old/new text before continuing.",
                },
                "TOD_EXECUTION_RESULT.latest.json": {
                    "generated_at": "2026-07-20T22:14:19Z",
                    "execution_state": "blocked",
                    "objective_id": "OBJ-LIVE",
                    "task_id": "TSK-LIVE",
                    "summary": "TOD cannot continue until the bounded packet is materialized.",
                    "current_action": "Projected the terminal active execution result.",
                    "reason_code": "blocked_missing_bounded_edit_mode",
                },
                "MIM_OPERATOR_STATUS.latest.json": {
                    "what_mim_is_doing": "MIM is coordinating the active TOD repair.",
                    "updated_at": "2026-07-20T22:00:00Z",
                },
            }
            return payloads.get(name, {})

        def fake_load_json_path(_path):
            return {
                "updated_at": "2026-07-20T22:14:20Z",
                "status": "reject_duplicate",
                "current_action": "Recorded the request without overwriting the active lane.",
                "event": "intake_rejected_duplicate",
            }

        with patch.object(studio, "_load_json", side_effect=fake_load_json), patch.object(
            studio,
            "_load_json_path",
            side_effect=fake_load_json_path,
        ):
            live = studio._studio_mim_live_feed_state()

        self.assertEqual(live["state"], "waiting")
        self.assertEqual(live["label"], "Blocked")
        self.assertEqual(live["objective_id"], "OBJ-LIVE")
        self.assertEqual(live["task_id"], "TSK-LIVE")
        self.assertIn("OBJ-LIVE", live["plain_meaning"])
        self.assertIn("TSK-LIVE", live["plain_meaning"])
        self.assertGreaterEqual(len(live["recent_events"]), 3)
        self.assertEqual(live["recent_events"][0]["label"], "Execution result")
        lifecycle = live["objective_lifecycle"]
        self.assertEqual(lifecycle["owner"], "MIM")
        self.assertEqual(lifecycle["objective_id"], "OBJ-LIVE")
        self.assertEqual(lifecycle["current_phase"], "Validation")
        self.assertEqual([item["label"] for item in lifecycle["phases"]], ["Understanding", "Planning", "Execution", "Validation", "Reflection", "Learning"])

    def test_studio_mim_live_feed_marks_conversation_objective_without_artifact_unverified(self):
        studio = _import_studio_module()

        thread_payload = {
            "updated_at": "2026-07-20T23:50:00Z",
            "threads": {
                "dave::dave-primary-mim-thread": {
                    "updated_at": "2026-07-20T23:50:00Z",
                    "messages": [
                        {
                            "role": "user",
                            "text": "what is the status of MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1?",
                            "at": "2026-07-20T23:49:30Z",
                        },
                        {
                            "role": "mim",
                            "text": "I am checking MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1 against current evidence before claiming progress.",
                            "at": "2026-07-20T23:50:00Z",
                        },
                    ],
                }
            },
        }

        def fake_load_json(name):
            payloads = {
                "TOD_EXECUTION_RESULT.latest.json": {
                    "generated_at": "2026-07-20T22:14:19Z",
                    "execution_state": "blocked",
                    "objective_id": "UNRELATED-TOD-OBJECTIVE-V1",
                    "task_id": "TSK-OLD",
                    "summary": "TOD is blocked on an older packet.",
                },
                "TOD_ACTIVE_EXECUTION_LANE.latest.json": {
                    "status": "blocked",
                    "objective_id": "UNRELATED-TOD-OBJECTIVE-V1",
                    "task_id": "TSK-OLD",
                    "terminal_message": "Older terminal lane.",
                },
            }
            return payloads.get(name, {})

        with patch.object(studio, "_load_studio_chat_threads", return_value=thread_payload), patch.object(
            studio,
            "_load_json",
            side_effect=fake_load_json,
        ), patch.object(studio, "_load_json_path", return_value={}):
            live = studio._studio_mim_live_feed_state()

        self.assertEqual(live["state"], "waiting")
        self.assertEqual(live["label"], "MIM focus unverified")
        self.assertEqual(live["status"], "unverified")
        self.assertEqual(live["objective_id"], "MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1")
        self.assertNotEqual(live["objective_id"], "UNRELATED-TOD-OBJECTIVE-V1")
        self.assertIn("Live proof missing", live["plain_meaning"])
        self.assertIn("MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1", live["plain_meaning"])
        self.assertEqual(live["recent_events"][0]["label"], "MIM conversation focus")
        self.assertTrue(any(item["label"] == "Execution result" for item in live["recent_events"]))
        self.assertEqual(live["objective_lifecycle"]["current_phase"], "Validation")
        self.assertTrue(any(item["state"] == "blocked" for item in live["objective_lifecycle"]["phases"]))

    def test_studio_mim_live_feed_prefers_live_execution_truth_over_chat_focus(self):
        studio = _import_studio_module()

        thread_payload = {
            "updated_at": "2026-07-20T23:50:00Z",
            "threads": {
                "dave::dave-primary-mim-thread": {
                    "updated_at": "2026-07-20T23:50:00Z",
                    "messages": [
                        {
                            "role": "user",
                            "text": "what are you working on for MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1?",
                            "at": "2026-07-20T23:49:30Z",
                        },
                        {
                            "role": "mim",
                            "text": "I am working on MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1 right now.",
                            "at": "2026-07-20T23:50:00Z",
                        },
                    ],
                }
            },
        }

        def fake_load_json(name):
            payloads = {
                "TOD_EXECUTION_RESULT.latest.json": {
                    "generated_at": "2026-07-21T00:10:00Z",
                    "execution_state": "blocked",
                    "objective_id": "MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1",
                    "task_id": "TSK-STATUS-TRUTH",
                    "summary": "TOD found the live execution is blocked on missing evidence.",
                    "current_action": "Separating chat claims from live execution evidence.",
                    "reason_code": "status_truth_repair_required",
                },
            }
            return payloads.get(name, {})

        with patch.object(studio, "_load_studio_chat_threads", return_value=thread_payload), patch.object(
            studio,
            "_load_json",
            side_effect=fake_load_json,
        ), patch.object(studio, "_load_json_path", return_value={}):
            live = studio._studio_mim_live_feed_state()

        self.assertEqual(live["state"], "waiting")
        self.assertEqual(live["label"], "Blocked")
        self.assertEqual(live["objective_id"], "MIM-CONVERSATIONAL-LEARNING-AND-REFLECTION-V1")
        self.assertEqual(live["task_id"], "TSK-STATUS-TRUTH")
        self.assertIn("Separating chat claims", live["summary"])
        self.assertIn("TSK-STATUS-TRUTH", live["plain_meaning"])
        self.assertEqual(live["recent_events"][0]["label"], "MIM conversation focus")
        self.assertTrue(any(item["label"] == "Execution result" for item in live["recent_events"]))

    def test_studio_mim_live_feed_terminal_result_beats_matching_dispatched_request(self):
        studio = _import_studio_module()

        def fake_load_json(name):
            payloads = {
                "MIM_TOD_TASK_REQUEST.latest.json": {
                    "generated_at": "2026-07-21T01:36:53Z",
                    "objective_id": "what-is-the-status-of-this-objective-mim",
                    "task_id": "REQ-SAME",
                    "request_id": "REQ-SAME",
                    "tod_action": "execute-chat-task",
                    "summary": "Dispatch this status objective.",
                },
                "TOD_EXECUTION_RESULT.latest.json": {
                    "generated_at": "2026-07-21T01:35:15Z",
                    "execution_state": "blocked_with_reason",
                    "status": "blocked",
                    "objective_id": "what-is-the-status-of-this-objective-mim",
                    "task_id": "REQ-SAME",
                    "request_id": "REQ-SAME",
                    "summary": "TOD cannot continue until exact current-code directives exist.",
                    "current_action": "Blocked execution on explicit missing materialization evidence.",
                    "reason_code": "missing_current_code_materialization",
                },
            }
            return payloads.get(name, {})

        with patch.object(studio, "_load_studio_chat_threads", return_value={}), patch.object(
            studio,
            "_load_json",
            side_effect=fake_load_json,
        ), patch.object(studio, "_load_json_path", return_value={}):
            live = studio._studio_mim_live_feed_state()

        self.assertEqual(live["state"], "waiting")
        self.assertEqual(live["label"], "Blocked")
        self.assertEqual(live["objective_id"], "what-is-the-status-of-this-objective-mim")
        self.assertEqual(live["task_id"], "REQ-SAME")
        self.assertIn("Blocked execution", live["summary"])
        self.assertIn("missing_current_code_materialization", live["plain_meaning"])
        self.assertEqual(live["objective_lifecycle"]["task_id"], "REQ-SAME")
        self.assertGreater(live["objective_lifecycle"]["overall_progress"], 0)

    def test_studio_mim_and_tod_side_rails_prioritize_live_work(self):
        studio = _import_studio_module()
        live = {
            "state": "working",
            "label": "In progress",
            "timestamp_la": "Jul 20, 3:14 PM",
            "summary": "Current live work summary.",
            "plain_meaning": "Objective: OBJ | Task: TSK",
            "objective_lifecycle": {
                "objective_id": "OBJ",
                "status": "In progress",
                "current_phase": "Execution",
                "overall_progress": 42,
                "summary": "Current live work summary.",
                "phases": [],
            },
            "recent_events": [],
        }
        with patch.object(studio, "_studio_mim_live_feed_state", return_value=live):
            mim_body = studio._studio_mim_body()
        tod_body = studio._studio_tod_body()

        self.assertLess(mim_body.index('id="mimLiveCard"'), mim_body.index('id="mimThreadList"'))
        self.assertLess(mim_body.index('id="mimLifecycle"'), mim_body.index('id="mimActivityList"'))
        self.assertIn("Live work and chat history", mim_body)
        self.assertLess(tod_body.index('id="todLiveCard"'), tod_body.index('id="todThreadList"'))
        self.assertLess(tod_body.index('id="todLifecycle"'), tod_body.index('id="todActivityList"'))
        self.assertIn("Execution lane and sessions", tod_body)
        self.assertIn("buildTodLifecycle", tod_body)


if __name__ == "__main__":
    unittest.main()
