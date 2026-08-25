#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT = Path("/var/lib/todbox-connectivity/latest.json")
DEFAULT_INVENTORY_OUTPUT = Path(
    "/var/lib/todbox-connectivity/system-inventory.latest.json"
)
EXPECTED_MODEL = "Qwen3-30B-A3B-Q4_K_M.gguf"
TUNNEL_SERVICE = "cloudflared-todbox-hosting.service"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def command(*args: str, timeout: float = 10.0) -> dict[str, Any]:
    started = time.monotonic()
    try:
        completed = subprocess.run(
            list(args),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "ok": completed.returncode == 0,
            "returncode": completed.returncode,
            "stdout": completed.stdout.strip()[-4000:],
            "stderr": completed.stderr.strip()[-1000:],
            "elapsed_ms": round((time.monotonic() - started) * 1000),
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {
            "ok": False,
            "error_type": type(exc).__name__,
            "elapsed_ms": round((time.monotonic() - started) * 1000),
        }


def tcp_check(host: str, port: int, timeout: float = 3.0) -> dict[str, Any]:
    started = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
        return {"ok": True, "host": host, "port": port, "elapsed_ms": round((time.monotonic() - started) * 1000)}
    except OSError as exc:
        return {
            "ok": False,
            "host": host,
            "port": port,
            "error_type": type(exc).__name__,
            "elapsed_ms": round((time.monotonic() - started) * 1000),
        }


def http_json(url: str, timeout: float = 8.0) -> dict[str, Any]:
    started = time.monotonic()
    request = urllib.request.Request(url, headers={"User-Agent": "TODBOX-Startup-Verification/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            payload = json.loads(body)
            return {
                "ok": 200 <= response.status < 300,
                "status_code": response.status,
                "payload": payload,
                "elapsed_ms": round((time.monotonic() - started) * 1000),
            }
    except (OSError, ValueError, urllib.error.URLError) as exc:
        return {
            "ok": False,
            "error_type": type(exc).__name__,
            "elapsed_ms": round((time.monotonic() - started) * 1000),
        }


def openapi_path_check(url: str, required_path: str) -> dict[str, Any]:
    result = http_json(url)
    payload = result.get("payload") if isinstance(result.get("payload"), dict) else {}
    paths = payload.get("paths") if isinstance(payload.get("paths"), dict) else {}
    result["required_path"] = required_path
    result["required_path_found"] = required_path in paths
    result["ok"] = bool(result.get("ok") and result["required_path_found"])
    result.pop("payload", None)
    return result


def service_check(name: str) -> dict[str, Any]:
    active = command("systemctl", "is-active", name)
    enabled = command("systemctl", "is-enabled", name)
    return {
        "ok": active["ok"] and enabled["ok"],
        "active": active.get("stdout", ""),
        "enabled": enabled.get("stdout", ""),
    }


def systemd_service_inventory(name: str) -> dict[str, Any]:
    properties = command(
        "systemctl",
        "show",
        name,
        "--no-pager",
        "--property=LoadState,ActiveState,SubState,UnitFileState,FragmentPath,After,Wants,Requires",
    )
    values: dict[str, str] = {}
    if properties.get("ok"):
        for line in str(properties.get("stdout") or "").splitlines():
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key] = value
    fragment_value = values.get("FragmentPath") or ""
    fragment = Path(fragment_value) if fragment_value else None
    fragment_sha256 = ""
    if fragment is not None and fragment.is_file():
        try:
            fragment_sha256 = hashlib.sha256(fragment.read_bytes()).hexdigest()
        except OSError:
            fragment_sha256 = ""
    return {
        "observed": bool(properties.get("ok")),
        "load_state": values.get("LoadState", "unknown"),
        "active_state": values.get("ActiveState", "unknown"),
        "sub_state": values.get("SubState", "unknown"),
        "unit_file_state": values.get("UnitFileState", "unknown"),
        "fragment_path": str(fragment) if fragment is not None else "",
        "fragment_sha256": fragment_sha256,
        "after": sorted(filter(None, values.get("After", "").split())),
        "wants": sorted(filter(None, values.get("Wants", "").split())),
        "requires": sorted(filter(None, values.get("Requires", "").split())),
    }


def ssh_access_inventory(user: str = "tod", home: Path | None = None) -> dict[str, Any]:
    """Collect public SSH identity evidence without copying key material."""
    home = home or (Path("/home") / user)
    host_key = Path("/etc/ssh/ssh_host_ed25519_key.pub")
    authorized_keys = home / ".ssh" / "authorized_keys"
    host_result = command("ssh-keygen", "-lf", str(host_key)) if host_key.is_file() else {"ok": False}
    authorized_result = command("ssh-keygen", "-lf", str(authorized_keys)) if authorized_keys.is_file() else {"ok": False}

    def fingerprints(result: dict[str, Any]) -> list[str]:
        values = []
        for line in str(result.get("stdout") or "").splitlines():
            fields = line.split()
            if len(fields) >= 2 and fields[1].startswith("SHA256:"):
                values.append(fields[1])
        return sorted(set(values))

    host_fingerprints = fingerprints(host_result)
    authorized_fingerprints = fingerprints(authorized_result)
    return {
        "user": user,
        "ready": bool(host_fingerprints and authorized_fingerprints),
        "host_ed25519_fingerprints": host_fingerprints,
        "authorized_client_fingerprints": authorized_fingerprints,
        "authorized_keys_path": str(authorized_keys),
        "secret_material_included": False,
    }


def _configuration_view(inventory: dict[str, Any]) -> dict[str, Any]:
    host = inventory.get("host") if isinstance(inventory.get("host"), dict) else {}
    services = inventory.get("services") if isinstance(inventory.get("services"), dict) else {}
    connection = (
        inventory.get("connections", {}).get("agentmim_mim_gateway", {})
        if isinstance(inventory.get("connections"), dict)
        else {}
    )
    ssh_connection = (
        inventory.get("connections", {}).get("todbox_ssh_admin", {})
        if isinstance(inventory.get("connections"), dict)
        else {}
    )
    models = inventory.get("models") if isinstance(inventory.get("models"), list) else []
    return {
        "host": {
            "hostname": host.get("hostname"),
            "interface": host.get("interface"),
            "network_policy": host.get("network_policy"),
            "service_address": host.get("service_address"),
        },
        "services": {
            name: {
                "unit_file_state": service.get("unit_file_state"),
                "fragment_path": service.get("fragment_path"),
                "fragment_sha256": service.get("fragment_sha256"),
                "after": service.get("after"),
                "wants": service.get("wants"),
                "requires": service.get("requires"),
            }
            for name, service in services.items()
            if isinstance(service, dict)
        },
        "agentmim_mim_gateway": {
            "stable_endpoint": connection.get("stable_endpoint"),
            "endpoint_mode": connection.get("endpoint_mode"),
            "owner": connection.get("owner"),
            "operational_owner": connection.get("operational_owner"),
            "tunnel_service": connection.get("tunnel_service"),
            "declared_capabilities": connection.get("declared_capabilities"),
            "origin": connection.get("origin"),
            "origin_mapping_proven": connection.get("origin_mapping_proven"),
        },
        "todbox_ssh_admin": {
            "owner": ssh_connection.get("owner"),
            "user": ssh_connection.get("user"),
            "port": ssh_connection.get("port"),
            "service_address": ssh_connection.get("service_address"),
            "host_ed25519_fingerprints": ssh_connection.get("host_ed25519_fingerprints"),
            "authorized_client_fingerprints": ssh_connection.get("authorized_client_fingerprints"),
        },
        "models": [
            {"role": model.get("role"), "model": model.get("model")}
            for model in models
            if isinstance(model, dict)
        ],
    }


def build_system_inventory(result: dict[str, Any]) -> dict[str, Any]:
    checks = result.get("checks") if isinstance(result.get("checks"), dict) else {}
    agent = checks.get("agentmim_readiness") if isinstance(checks.get("agentmim_readiness"), dict) else {}
    agent_payload = agent.get("payload") if isinstance(agent.get("payload"), dict) else {}
    agent_checks = agent_payload.get("checks") if isinstance(agent_payload.get("checks"), dict) else {}
    gateway = agent_checks.get("mim_gateway") if isinstance(agent_checks.get("mim_gateway"), dict) else {}
    public = checks.get("mim_gateway_public") if isinstance(checks.get("mim_gateway_public"), dict) else {}
    public_payload = public.get("payload") if isinstance(public.get("payload"), dict) else {}
    local_inference = public_payload.get("local_inference") if isinstance(public_payload.get("local_inference"), dict) else {}
    lanes = local_inference.get("lanes") if isinstance(local_inference.get("lanes"), list) else []
    endpoint_host = str(gateway.get("endpoint_host") or "").strip()
    stable_endpoint = f"https://{endpoint_host}" if endpoint_host else ""
    service_names = (
        TUNNEL_SERVICE,
        "mim-llama.service",
        "tod-llama.service",
        "mim-creative-worker.service",
        "mim-ollama-gpu-readiness.service",
        "todbox-startup-connectivity-verify.service",
        "todbox-startup-connectivity-verify.timer",
    )
    services = {name: systemd_service_inventory(name) for name in service_names}
    tunnel = services[TUNNEL_SERVICE]
    ssh_access = ssh_access_inventory("tod")
    tunnel_healthy = bool(
        gateway.get("endpoint_mode") == "managed_tunnel"
        and gateway.get("ok")
        and public.get("ok")
        and tunnel.get("active_state") == "active"
        and tunnel.get("unit_file_state") == "enabled"
    )
    inventory = {
        "schema_version": 1,
        "generated_at": result.get("generated_at") or utc_now(),
        "authority": {
            "owner": "TOD",
            "source": "live_discovery",
            "secret_material_included": False,
            "max_age_seconds": 900,
        },
        "host": {
            "hostname": result.get("hostname"),
            "boot_id": result.get("boot_id"),
            "interface": result.get("interface"),
            "network_policy": "fixed_service_address_plus_dhcp",
            "service_address": result.get("fixed_cidr"),
            "observed_addresses": (
                checks.get("fixed_address", {}).get("observed", [])
                if isinstance(checks.get("fixed_address"), dict)
                else []
            ),
        },
        "services": services,
        "connections": {
            "agentmim_mim_gateway": {
                "owner": "TOD",
                "operational_owner": "TOD",
                "stable_endpoint": stable_endpoint,
                "endpoint_mode": gateway.get("endpoint_mode") or "unknown",
                "source_env": gateway.get("source_env") or "unknown",
                "status": gateway.get("status") or "unknown",
                "tunnel_service": TUNNEL_SERVICE,
                "origin": "not_asserted_from_available_evidence",
                "origin_mapping_proven": False,
                "declared_capabilities": [
                    "conversation",
                    "forum_image_generation",
                    "image_semantic_review",
                    "call_transcription",
                ],
                "dependencies": [
                    TUNNEL_SERVICE,
                    "mim-llama.service",
                    "mim-creative-worker.service",
                    "mim-ollama-gpu-readiness.service",
                ],
                "evidence": {
                    "agentmim_ready": "https://www.agentmim.com/ready",
                    "public_gateway_health": "https://mim.mimtod.com/health",
                    "startup_verifier": str(DEFAULT_OUTPUT),
                },
            },
            "todbox_ssh_admin": {
                "owner": "TOD",
                "operational_owner": "TOD",
                "user": "tod",
                "port": 22,
                "service_address": result.get("fixed_cidr"),
                "address_policy": "fixed_service_address_managed_by_tod",
                "status": "ready" if ssh_access.get("ready") else "degraded",
                "host_ed25519_fingerprints": ssh_access.get("host_ed25519_fingerprints", []),
                "authorized_client_fingerprints": ssh_access.get("authorized_client_fingerprints", []),
                "secret_material_included": False,
                "declared_capabilities": [
                    "ssh",
                    "todbox",
                    "todbox_admin",
                    "tod_migration",
                ],
                "evidence": {
                    "ssh_service": "checks.ssh_service",
                    "ssh_port": "checks.ssh_port",
                    "authorized_keys_path": ssh_access.get("authorized_keys_path"),
                },
            },
        },
        "models": [
            {
                "role": lane.get("role"),
                "model": lane.get("model"),
                "status": lane.get("status"),
            }
            for lane in lanes
            if isinstance(lane, dict)
        ],
        "inferences": {
            "agentmim_gateway_tunnel_healthy": {
                "value": tunnel_healthy,
                "confidence": "high" if tunnel_healthy else "low",
                "basis": [
                    "agentmim_readiness.endpoint_mode",
                    "agentmim_readiness.mim_gateway.status",
                    "mim_gateway_public.health",
                    f"services.{TUNNEL_SERVICE}.active_state",
                ],
            }
        },
    }
    configuration = _configuration_view(inventory)
    inventory["configuration_fingerprint"] = hashlib.sha256(
        json.dumps(configuration, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return inventory


def write_inventory(path: Path, inventory: dict[str, Any]) -> dict[str, Any]:
    previous: dict[str, Any] = {}
    if path.is_file():
        try:
            previous = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            previous = {}
    previous_fingerprint = str(previous.get("configuration_fingerprint") or "")
    current_fingerprint = str(inventory.get("configuration_fingerprint") or "")
    changed = previous_fingerprint != current_fingerprint
    history_path = ""
    path.parent.mkdir(parents=True, exist_ok=True)
    if changed:
        change_dir = path.parent / "inventory-changes"
        change_dir.mkdir(parents=True, exist_ok=True)
        stamp = str(inventory.get("generated_at") or utc_now()).replace(":", "").replace("+00:00", "Z")
        change_path = change_dir / f"{stamp}-{current_fingerprint[:12]}.json"
        change = {
            "schema_version": 1,
            "changed_at": inventory.get("generated_at"),
            "change_type": "initial_baseline" if not previous_fingerprint else "configuration_drift",
            "previous_configuration_fingerprint": previous_fingerprint or None,
            "current_configuration_fingerprint": current_fingerprint,
            "configuration": _configuration_view(inventory),
        }
        change_path.write_text(json.dumps(change, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.chmod(change_path, 0o644)
        history_path = str(change_path)
    drift = {"changed": changed, "history_path": history_path}
    inventory["drift"] = drift
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o644)
    temporary.replace(path)
    return drift


def network_online_check() -> dict[str, Any]:
    # ``networkctl is-online`` is not available on every networkctl release,
    # and this host has both networkd and NetworkManager present.  Verify the
    # portable systemd readiness target plus at least one enabled wait-online
    # implementation instead of reporting a healthy boot as failed.
    target = command("systemctl", "is-active", "network-online.target")
    wait_units = (
        "NetworkManager-wait-online.service",
        "systemd-networkd-wait-online.service",
    )
    waiters = {
        name: command("systemctl", "is-enabled", name)
        for name in wait_units
    }
    enabled_waiters = [
        name
        for name, result in waiters.items()
        if result.get("ok")
    ]
    return {
        "ok": bool(target.get("ok") and enabled_waiters),
        "target_active": target.get("stdout", ""),
        "enabled_waiters": enabled_waiters,
    }


def collect(interface: str, fixed_cidr: str, gateway: str) -> dict[str, Any]:
    carrier_path = Path(f"/sys/class/net/{interface}/carrier")
    carrier = carrier_path.read_text(encoding="utf-8").strip() if carrier_path.exists() else "missing"
    addresses = command("ip", "-j", "address", "show", "dev", interface)
    routes = command("ip", "route", "show")
    route_to_gateway = command("ip", "route", "get", gateway)

    address_payload: list[dict[str, Any]] = []
    if addresses["ok"]:
        try:
            address_payload = json.loads(addresses.get("stdout") or "[]")
        except json.JSONDecodeError:
            address_payload = []
    observed_cidrs = {
        f"{row.get('local')}/{row.get('prefixlen')}"
        for link in address_payload
        for row in link.get("addr_info", [])
        if isinstance(row, dict) and row.get("local") and row.get("prefixlen") is not None
    }

    model = http_json("http://127.0.0.1:8101/v1/models")
    model_payload = model.get("payload") if isinstance(model.get("payload"), dict) else {}
    model_text = json.dumps(model_payload)
    model["expected_model_found"] = EXPECTED_MODEL in model_text
    model["ok"] = bool(model["ok"] and model["expected_model_found"])

    mim_health = http_json("https://mim.mimtod.com/health")
    mim_payload = mim_health.get("payload") if isinstance(mim_health.get("payload"), dict) else {}
    local_inference = mim_payload.get("local_inference") if isinstance(mim_payload.get("local_inference"), dict) else {}
    lanes = local_inference.get("lanes") if isinstance(local_inference.get("lanes"), list) else []
    primary_reachable = any(
        isinstance(lane, dict)
        and lane.get("role") == "primary"
        and lane.get("status") == "reachable"
        for lane in lanes
    )
    mim_health["primary_reachable"] = primary_reachable
    mim_health["ok"] = bool(mim_health["ok"] and local_inference.get("status") == "reachable" and primary_reachable)

    agentmim = http_json("https://www.agentmim.com/ready")
    agent_payload = agentmim.get("payload") if isinstance(agentmim.get("payload"), dict) else {}
    agent_gateway = (agent_payload.get("checks") or {}).get("mim_gateway") if isinstance(agent_payload.get("checks"), dict) else {}
    agent_gateway = agent_gateway if isinstance(agent_gateway, dict) else {}
    agentmim["gateway_reachable"] = bool(agent_gateway.get("ok") and agent_gateway.get("status") == "reachable")
    agentmim["ok"] = bool(agentmim["ok"] and agent_payload.get("status") == "ready" and agentmim["gateway_reachable"])

    checks: dict[str, Any] = {
        "carrier": {"ok": carrier == "1", "observed": carrier},
        "fixed_address": {"ok": fixed_cidr in observed_cidrs, "expected": fixed_cidr, "observed": sorted(observed_cidrs)},
        "default_route": {"ok": routes["ok"] and f"default via {gateway}" in routes.get("stdout", ""), "observed": routes.get("stdout", "")},
        "gateway_route": {"ok": route_to_gateway["ok"] and interface in route_to_gateway.get("stdout", ""), "observed": route_to_gateway.get("stdout", "")},
        "network_online": network_online_check(),
        "ssh_service": service_check("ssh.service"),
        "mim_model_service": service_check("mim-llama.service"),
        "tod_model_service": service_check("tod-llama.service"),
        "creative_worker_service": service_check("mim-creative-worker.service"),
        "ssh_port": tcp_check("127.0.0.1", 22),
        "mim_model_port": tcp_check("127.0.0.1", 8101),
        "creative_worker_port": tcp_check("127.0.0.1", 8110),
        "creative_worker_api": openapi_path_check("http://127.0.0.1:8110/openapi.json", "/v1/images/jobs"),
        "mim_model_api": model,
        "mim_gateway_public": mim_health,
        "agentmim_readiness": agentmim,
    }
    return {
        "ok": all(bool(check.get("ok")) for check in checks.values()),
        "generated_at": utc_now(),
        "hostname": socket.gethostname(),
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text(encoding="utf-8").strip(),
        "interface": interface,
        "fixed_cidr": fixed_cidr,
        "gateway": gateway,
        "checks": checks,
    }


def write_result(path: Path, result: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o644)
    temporary.replace(path)
    boot_path = path.with_name(f"boot-{result['boot_id']}.json")
    boot_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(boot_path, 0o644)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--interface", default="enp7s0f0")
    parser.add_argument("--fixed-cidr", default="192.168.1.10/24")
    parser.add_argument("--gateway", default="192.168.1.1")
    parser.add_argument("--timeout", type=int, default=720)
    parser.add_argument("--interval", type=int, default=10)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--inventory-output",
        type=Path,
        default=DEFAULT_INVENTORY_OUTPUT,
    )
    args = parser.parse_args()

    deadline = time.monotonic() + max(0, args.timeout)
    attempt = 0
    result: dict[str, Any]
    while True:
        attempt += 1
        result = collect(args.interface, args.fixed_cidr, args.gateway)
        result["attempt"] = attempt
        write_result(args.output, result)
        inventory = build_system_inventory(result)
        write_inventory(args.inventory_output, inventory)
        if result["ok"]:
            print(json.dumps({"status": "healthy", "attempt": attempt, "evidence": str(args.output)}))
            return 0
        if time.monotonic() >= deadline:
            failed = [name for name, check in result["checks"].items() if not check.get("ok")]
            print(json.dumps({"status": "failed", "attempt": attempt, "failed_checks": failed, "evidence": str(args.output)}))
            return 1
        time.sleep(max(1, args.interval))


if __name__ == "__main__":
    raise SystemExit(main())
