import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


VERIFY = _load("todbox_startup_connectivity_verify", ROOT / "todbox-startup-connectivity-verify.py")
QUERY = _load("todbox_system_inventory_query", ROOT / "todbox-system-inventory-query.py")


def _result():
    return {
        "generated_at": "2026-08-25T17:00:00+00:00",
        "hostname": "tod-ai-01",
        "boot_id": "boot-1",
        "interface": "enp7s0f0",
        "fixed_cidr": "192.168.1.10/24",
        "checks": {
            "fixed_address": {"observed": ["192.168.1.10/24"]},
            "agentmim_readiness": {
                "ok": True,
                "payload": {
                    "checks": {
                        "mim_gateway": {
                            "ok": True,
                            "status": "reachable",
                            "endpoint_host": "mim.mimtod.com",
                            "endpoint_mode": "managed_tunnel",
                            "source_env": "MIM_GATEWAY_TUNNEL_URL",
                        }
                    }
                },
            },
            "mim_gateway_public": {
                "ok": True,
                "payload": {
                    "local_inference": {
                        "lanes": [
                            {"role": "primary", "model": "Qwen3-30B", "status": "reachable"}
                        ]
                    }
                },
            },
        },
    }


def test_inventory_uses_observed_tunnel_hostname_and_does_not_invent_origin(monkeypatch):
    monkeypatch.setattr(
        VERIFY,
        "systemd_service_inventory",
        lambda _name: {
            "observed": True,
            "active_state": "active",
            "unit_file_state": "enabled",
            "fragment_path": "/etc/systemd/system/example.service",
            "fragment_sha256": "a" * 64,
            "after": [],
            "wants": [],
            "requires": [],
        },
    )

    inventory = VERIFY.build_system_inventory(_result())
    gateway = inventory["connections"]["agentmim_mim_gateway"]

    assert gateway["stable_endpoint"] == "https://mim.mimtod.com"
    assert gateway["endpoint_mode"] == "managed_tunnel"
    assert gateway["origin"] == "not_asserted_from_available_evidence"
    assert gateway["origin_mapping_proven"] is False
    assert gateway["operational_owner"] == "TOD"
    assert inventory["authority"]["owner"] == "TOD"
    assert inventory["authority"]["secret_material_included"] is False


def test_inventory_history_is_written_only_for_configuration_change(tmp_path):
    path = tmp_path / "system-inventory.latest.json"
    inventory = {"generated_at": "one", "configuration_fingerprint": "abc", "host": {}, "services": {}, "connections": {}, "models": []}

    first = VERIFY.write_inventory(path, inventory)
    second = VERIFY.write_inventory(path, {**inventory, "generated_at": "two"})
    third = VERIFY.write_inventory(path, {**inventory, "generated_at": "three", "configuration_fingerprint": "def"})

    assert first["changed"] is True
    assert second == {"changed": False, "history_path": ""}
    assert third["changed"] is True
    history = list((tmp_path / "inventory-changes").glob("*.json"))
    assert len(history) == 2
    assert json.loads(history[-1].read_text(encoding="utf-8"))["change_type"] in {"initial_baseline", "configuration_drift"}


def test_query_returns_forum_image_gateway_evidence(monkeypatch):
    monkeypatch.setattr(
        VERIFY,
        "systemd_service_inventory",
        lambda _name: {
            "observed": True,
            "active_state": "active",
            "unit_file_state": "enabled",
            "fragment_path": "",
            "fragment_sha256": "",
            "after": [],
            "wants": [],
            "requires": [],
        },
    )
    inventory = VERIFY.build_system_inventory(_result())

    answer = QUERY.query_inventory(inventory, "forum_image_generation")

    assert answer["owner"] == "TOD"
    assert answer["matches"][0]["stable_endpoint"] == "https://mim.mimtod.com"
    assert answer["matches"][0]["origin"] == "not_asserted_from_available_evidence"
