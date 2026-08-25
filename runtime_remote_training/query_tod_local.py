import json
import os
import shlex
import sys
import urllib.request
from pathlib import Path

import paramiko


TODBOX_CONNECTION_AUTHORITY = Path(r"E:\TOD\tod\config\todbox-connection.json")
MANAGED_HOST_AUTHORITY = Path(r"E:\TOD\tod\config\managed-host-connections.json")
MANAGED_HOST_REPORT = Path(r"E:\TOD\tod\state\managed_ssh_connectivity.latest.json")
REMOTE_SYSTEM_INVENTORY = "/var/lib/todbox-connectivity/system-inventory.latest.json"


def load_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.lstrip().startswith("#"):
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def load_connection_authority(path: Path = TODBOX_CONNECTION_AUTHORITY) -> dict[str, object]:
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return payload if isinstance(payload, dict) else {}


def load_json_authority(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return payload if isinstance(payload, dict) else {}


def read_system_inventory(sftp: paramiko.SFTPClient) -> dict[str, object]:
    try:
        with sftp.open(REMOTE_SYSTEM_INVENTORY, "r") as handle:
            payload = json.loads(handle.read().decode())
    except (OSError, ValueError):
        return {}
    if not isinstance(payload, dict):
        return {}
    return {
        key: payload.get(key)
        for key in (
            "schema_version",
            "generated_at",
            "authority",
            "host",
            "services",
            "connections",
            "models",
            "inferences",
            "configuration_fingerprint",
            "drift",
        )
    }


def main() -> int:
    prompt = sys.stdin.read()
    values = load_env(Path(r"E:\TOD\tmp_remote_mim\.env"))
    authority = load_connection_authority()
    managed_hosts = load_json_authority(MANAGED_HOST_AUTHORITY)
    managed_todbox = (
        managed_hosts.get("hosts", {}).get("todbox", {})
        if isinstance(managed_hosts.get("hosts"), dict)
        else {}
    )
    tod_host = (
        os.environ.get("TOD_SERVER_HOST")
        or values.get("TOD_SERVER_HOST")
        or str(managed_todbox.get("address") or "")
        or str(authority.get("ssh_host") or "")
    ).strip()
    if not tod_host:
        raise RuntimeError("TOD server host is absent from TOD-managed connection authority")
    tod_api_port = int(
        os.environ.get("TOD_API_PORT")
        or values.get("TOD_API_PORT")
        or authority.get("api_port")
        or "8102"
    )
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        tod_host,
        username=values["TOD_SERVER_USERNAME"],
        password=values["TOD_SERVER_PASSWORD"],
        timeout=15,
    )
    _, stdout, _ = client.exec_command(
        "systemctl show tod-llama.service -p MainPID --value", timeout=15
    )
    pid = stdout.read().decode().strip()
    if not pid:
        raise RuntimeError("TOD llama process not found")
    sftp = client.open_sftp()
    with sftp.open(f"/proc/{pid}/cmdline", "rb") as handle:
        args = handle.read().decode(errors="replace").split("\0")
    key_flag_index = next(
        (index for index, value in enumerate(args) if "api-key" in value), None
    )
    if key_flag_index is None or key_flag_index + 1 >= len(args):
        raise RuntimeError("TOD API key argument not found")
    key_value = args[key_flag_index + 1]
    if args[key_flag_index].endswith("-file"):
        with sftp.open(key_value, "r") as handle:
            key = handle.read().decode().strip()
    else:
        key = key_value
    inventory = read_system_inventory(sftp)
    sftp.close()
    client.close()

    messages = []
    managed_host_report = load_json_authority(MANAGED_HOST_REPORT)
    if managed_hosts:
        messages.append(
            {
                "role": "system",
                "content": (
                    "Use this TOD-managed SSH host registry and latest client proof when asked how to "
                    "connect to TODBOX or MIMBOX. Prefer the alias command, report whether key login "
                    "was actually proven, and never expose or request a password or private key.\n"
                    + json.dumps(
                        {"registry": managed_hosts, "latest_proof": managed_host_report},
                        sort_keys=True,
                    )
                ),
            }
        )
    if inventory:
        messages.append(
            {
                "role": "system",
                "content": (
                    "Use this live TOD-owned system inventory as the authority for infrastructure facts. "
                    "Distinguish observed facts from inferences, do not invent missing origin mappings, "
                    "and name the generated_at timestamp when freshness matters.\n"
                    + json.dumps(inventory, sort_keys=True)
                ),
            }
        )
    messages.append({"role": "user", "content": prompt})
    payload = {
        "model": "tod-local",
        "messages": messages,
        "temperature": 0.1,
        "max_tokens": 1800,
    }
    request = urllib.request.Request(
        f"http://{tod_host}:{tod_api_port}/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        result = json.load(response)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(result["choices"][0]["message"]["content"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
