import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from run_universal_mim_customer_conversation_smoke import (  # noqa: E402
    SurfaceClient,
    SurfaceConfig,
    normalize_agentmim_base_url,
)


def test_agentmim_smoke_client_canonicalizes_bare_domain():
    assert normalize_agentmim_base_url("https://agentmim.com") == "https://www.agentmim.com"
    assert normalize_agentmim_base_url("agentmim.com") == "https://www.agentmim.com"
    assert normalize_agentmim_base_url("https://www.agentmim.com") == "https://www.agentmim.com"

    config = SurfaceConfig(
        key="agentmim_public_sales_chat",
        kind="agentmim",
        base_url="https://agentmim.com",
    )
    client = SurfaceClient(config, timeout=5)

    assert client._agentmim_url("/agent/message") == "https://www.agentmim.com/agent/message"
