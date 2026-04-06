import json
from datetime import datetime, timezone
from pathlib import Path

import paramiko

HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"
RECEIPT_DIR = Path("tod") / "out" / "smoke"


def run_remote(client: paramiko.SSHClient, command: str, timeout: int = 120) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace").rstrip()
    err = stderr.read().decode("utf-8", errors="replace").rstrip()
    if err:
        print("===STDERR===")
        print(err)
    return out


def fetch_json(client: paramiko.SSHClient, endpoint: str) -> dict:
    raw = run_remote(client, f"bash -lc \"curl -fsS http://127.0.0.1:5000{endpoint}\"")
    return json.loads(raw)


def main() -> None:
    now = datetime.now(timezone.utc)
    stamp = now.strftime("%Y%m%d-%H%M%S")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=HOST,
        username=USER,
        password=PASSWORD,
        timeout=20,
        allow_agent=False,
        look_for_keys=False,
    )
    try:
        status_payload = fetch_json(client, "/status")
        ping_payload = fetch_json(client, "/ping")
        serial_payload = fetch_json(client, "/serial_health")
        arm_state_payload = fetch_json(client, "/arm_state")

        print("===SERIAL_HEALTH_JSON===")
        print(json.dumps(serial_payload, indent=2, sort_keys=True))
        print("===ARM_STATE_JSON===")
        print(json.dumps(arm_state_payload, indent=2, sort_keys=True))

        receipt = {
            "captured_at_utc": now.isoformat(),
            "target": {
                "host": HOST,
                "endpoint_base": "http://127.0.0.1:5000",
            },
            "status": status_payload,
            "ping": ping_payload,
            "serial_health": serial_payload,
            "arm_state": arm_state_payload,
        }

        RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        receipt_path = RECEIPT_DIR / f"serial_health_smoke_{stamp}.json"
        latest_path = RECEIPT_DIR / "serial_health_smoke.latest.json"
        payload = json.dumps(receipt, indent=2, sort_keys=True)
        receipt_path.write_text(payload, encoding="utf-8")
        latest_path.write_text(payload, encoding="utf-8")
        print(f"===RECEIPT_WRITTEN===\n{receipt_path}")
    finally:
        client.close()


if __name__ == "__main__":
    main()
