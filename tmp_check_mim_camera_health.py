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


def parse_headers(raw_headers: str) -> dict:
    parsed = {}
    for line in raw_headers.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        parsed[key.strip().lower()] = value.strip()
    return parsed


def main() -> None:
    now = datetime.now(timezone.utc)
    receipt_timestamp = now.strftime("%Y%m%d-%H%M%S")

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
        run_remote(
            client,
            "bash -lc \"curl -s http://127.0.0.1:5000/camera_feed --max-time 3 > /tmp/mim_camera_health_warmup.bin || true\"",
        )
        health_raw = run_remote(client, "bash -lc \"curl -fsS http://127.0.0.1:5000/camera_health\"")
        health = json.loads(health_raw)
        print("===CAMERA_HEALTH_JSON===")
        print(json.dumps(health, indent=2, sort_keys=True))

        command = "bash -lc \"curl -I -s http://127.0.0.1:5000/camera_feed | head -n 20\""
        headers = run_remote(client, command)
        print("===CAMERA_FEED_HEADERS===")
        print(headers)

        receipt = {
            "captured_at_utc": now.isoformat(),
            "target": {
                "host": HOST,
                "endpoint_base": "http://127.0.0.1:5000",
            },
            "camera_health": health,
            "camera_feed_headers": {
                "raw": headers,
                "parsed": parse_headers(headers),
            },
        }

        RECEIPT_DIR.mkdir(parents=True, exist_ok=True)
        receipt_path = RECEIPT_DIR / f"camera_health_smoke_{receipt_timestamp}.json"
        receipt_path.write_text(json.dumps(receipt, indent=2, sort_keys=True), encoding="utf-8")
        latest_path = RECEIPT_DIR / "camera_health_smoke.latest.json"
        latest_path.write_text(json.dumps(receipt, indent=2, sort_keys=True), encoding="utf-8")
        print(f"===RECEIPT_WRITTEN===\n{receipt_path}")
    finally:
        client.close()


if __name__ == "__main__":
    main()
