import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


_STUDIO_MODULE = None


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

    core_config_module = types.ModuleType("core.config")
    core_config_module.settings = types.SimpleNamespace()
    core_db_module = types.ModuleType("core.db")
    core_db_module.get_db = lambda: None
    core_auth_module = types.ModuleType("core.mim_ui_auth")
    core_auth_module.ensure_authenticated_mimtod_api_request = lambda *_args, **_kwargs: None
    core_auth_module.maybe_require_mimtod_page_login = lambda *_args, **_kwargs: None
    core_auth_module.request_has_valid_mim_studio_test_auth = lambda *_args, **_kwargs: False
    core_models_module = types.ModuleType("core.models")
    for name in (
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
            "core.config": core_config_module,
            "core.db": core_db_module,
            "core.mim_ui_auth": core_auth_module,
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
        self.assertIn("tod_result_artifacts + tod/data/state.json", html)

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
        self.assertIn("attachmentPromptText", html)
        self.assertIn("setAttachmentFromFile", html)
        self.assertIn('id="chatPresenceIndicator"', html)
        self.assertIn('id="chatActivityStream"', html)
        self.assertIn('id="voiceChat"', html)
        self.assertIn('aria-label="Add attachment"', html)
        self.assertIn('aria-label="Voice input"', html)
        self.assertIn('aria-label="Send"', html)
        self.assertIn("autoSizeChatInput", html)
        self.assertIn('id="chatFileDrop" class="chat-file-drop" role="button" tabindex="0" hidden', html)
        self.assertNotIn("Drop a file here, or attach text, code, JSON, markdown, or an image reference.", html)

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
        self.assertIn("TOD real movement is the current blocker", reply)
        self.assertIn("selected a live-code candidate", reply)
        self.assertIn("implementation and validation are still pending", reply)
        self.assertIn("The next move I recommend is", reply)
        self.assertLess(reply.find("My judgment-mode"), reply.find("TOD real movement"))

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
        self.assertIn("TOD selected a live-code candidate", reply)
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
        self.assertIn("selected live-code candidate", blockers)
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
        self.assertIn("TOD selected a live-code candidate", reply)
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


if __name__ == "__main__":
    unittest.main()
