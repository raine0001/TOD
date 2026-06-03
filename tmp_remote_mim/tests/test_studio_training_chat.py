import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


def _import_studio_module():
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
    sqlalchemy_ext_module = types.ModuleType("sqlalchemy.ext")
    sqlalchemy_asyncio_module = types.ModuleType("sqlalchemy.ext.asyncio")

    fastapi_module.APIRouter = lambda *_args, **_kwargs: _FakeRouter()
    fastapi_module.Body = _identity_value
    fastapi_module.Depends = _identity_value
    fastapi_module.HTTPException = Exception
    fastapi_module.Request = object
    responses_module.HTMLResponse = object
    responses_module.Response = object
    pydantic_module.BaseModel = _FakeBaseModel
    pydantic_module.Field = _field
    sqlalchemy_module.func = types.SimpleNamespace(count=lambda: None)
    sqlalchemy_module.select = lambda *_args, **_kwargs: None
    sqlalchemy_module.text = lambda value: value
    sqlalchemy_asyncio_module.AsyncSession = object

    core_db_module = types.ModuleType("core.db")
    core_db_module.get_db = lambda: None
    core_auth_module = types.ModuleType("core.mim_ui_auth")
    core_auth_module.maybe_require_mimtod_page_login = lambda *_args, **_kwargs: None
    core_models_module = types.ModuleType("core.models")
    for name in (
        "Objective",
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
            "sqlalchemy.ext": sqlalchemy_ext_module,
            "sqlalchemy.ext.asyncio": sqlalchemy_asyncio_module,
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
        spec.loader.exec_module(module)
        return module


class StudioTrainingChatTest(unittest.TestCase):
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
        self.assertIn("MIM judgment mode is the top repair", reply)
        self.assertIn("Outcome reflection is not ready", reply)
        self.assertIn("TOD validation baselines still need tightening", reply)
        self.assertIn("The next move I recommend", reply)
        self.assertLess(reply.find("MIM judgment mode"), reply.find("Outcome reflection"))


if __name__ == "__main__":
    unittest.main()
