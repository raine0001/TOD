from pathlib import Path


def test_cross_surface_scorer_supports_test_auth_without_chrome_cookie_reuse():
    source = Path("tools/score_mim_structural_reasoning_cross_surface.py").read_text(encoding="utf-8")

    assert "agentmim_test_auth_token" in source
    assert 'os.getenv("AGENTMIM_TEST_AUTH_TOKEN")' in source
    assert "studio_test_token" in source
    assert 'os.getenv("MIM_STUDIO_TEST_TOKEN")' in source
    assert "studio_username" in source
    assert 'os.getenv("MIMTOD_USER")' in source
    assert 'os.getenv("MIMTOD_PASSWORD")' in source
    assert "Basic {token}" in source
    assert 'load_dotenv_file(ROOT / "tmp_remote_mim" / ".env")' in source
    assert "auth_error:HTTPError_" in source
    assert "auth_surface_groups" in source


def test_universal_customer_smoke_supports_agentmim_test_auth_token():
    source = Path("tools/run_universal_mim_customer_conversation_smoke.py").read_text(encoding="utf-8")

    assert "agentmim_test_auth_token" in source
    assert '"/agent/test_auth/session"' in source
    assert '"Authorization": f"Bearer {self.agentmim_test_auth_token}"' in source
    assert "test_auth_session_created" in source
