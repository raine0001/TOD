import os
import socket
import time
from pathlib import Path

import paramiko


def load_dotenv(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip().strip('"').strip("'")
    return data


def run_command(client: paramiko.SSHClient, command: str) -> tuple[int, str, str]:
    stdin, stdout, stderr = client.exec_command(command)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    return exit_code, out, err


def verify_target(host: str, user: str, password: str, port: int) -> dict[str, object]:
    result: dict[str, object] = {
        "host": host,
        "port": port,
        "user": user,
        "connected": False,
        "mim_arm_exists": False,
        "read_ok": False,
        "write_ok": False,
        "cleanup_ok": False,
        "error": "",
    }

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    probe_name = f".tod_access_probe_{int(time.time())}.txt"
    probe_path = f"~/mim_arm/{probe_name}"

    try:
        client.connect(
            hostname=host,
            port=port,
            username=user,
            password=password,
            timeout=10,
            banner_timeout=10,
            auth_timeout=10,
            look_for_keys=False,
            allow_agent=False,
        )
        result["connected"] = True

        code, out, err = run_command(client, "cd ~/mim_arm && pwd && ls -ld .")
        result["mim_arm_exists"] = code == 0
        result["read_ok"] = code == 0
        if code != 0:
            result["error"] = (err or out).strip()
            return result

        write_command = (
            f"cd ~/mim_arm && "
            f"printf '%s\n' 'tod-access-probe' > {probe_name} && "
            f"cat {probe_name}"
        )
        code, out, err = run_command(client, write_command)
        result["write_ok"] = code == 0 and "tod-access-probe" in out
        if code != 0:
            result["error"] = (err or out).strip()
            return result

        code, out, err = run_command(client, f"cd ~/mim_arm && rm -f {probe_name} && test ! -e {probe_name}")
        result["cleanup_ok"] = code == 0
        if code != 0:
            result["error"] = (err or out).strip()
            return result
    except (paramiko.SSHException, socket.error, TimeoutError, OSError) as exc:
        result["error"] = str(exc)
    finally:
        client.close()

    return result


def main() -> None:
    env = load_dotenv(Path(".env"))
    env_host = env.get("MIM_SSH_HOST", "")
    user = env.get("MIM_SSH_USER", "")
    port = int(env.get("MIM_SSH_PORT", "22") or "22")
    password = env.get("MIM_ARM_SSH_HOST_PASS") or env.get("MIM_SSH_PASSWORD") or ""

    targets: list[str] = []
    if env_host:
        targets.append(env_host)
    if "192.168.1.90" not in targets:
        targets.append("192.168.1.90")

    print("TOD MIM ARM access probe")
    print(f"Configured host from .env: {env_host or '<missing>'}")
    print(f"Configured user: {user or '<missing>'}")
    print(f"Configured port: {port}")
    print(f"Password variable present: {bool(password)}")
    print()

    if not user or not password:
        print("Missing required SSH user or password in .env")
        raise SystemExit(2)

    for host in targets:
        result = verify_target(host=host, user=user, password=password, port=port)
        print(f"Host: {result['host']}")
        print(f"  connected: {result['connected']}")
        print(f"  mim_arm_exists: {result['mim_arm_exists']}")
        print(f"  read_ok: {result['read_ok']}")
        print(f"  write_ok: {result['write_ok']}")
        print(f"  cleanup_ok: {result['cleanup_ok']}")
        print(f"  error: {result['error']}")
        print()


if __name__ == "__main__":
    main()