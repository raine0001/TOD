from __future__ import annotations

import json
import os
import platform
import socket
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def run_shell(command: str) -> dict[str, object]:
    completed = subprocess.run(
        ["bash", "-lc", command],
        text=True,
        capture_output=True,
        check=False,
    )
    return {
        "command": command,
        "exit_code": completed.returncode,
        "stdout": completed.stdout.strip(),
        "stderr": completed.stderr.strip(),
    }


def file_snapshot(path_text: str) -> dict[str, object]:
    path = Path(path_text)
    snapshot: dict[str, object] = {"path": str(path), "exists": path.exists()}
    if not path.exists():
        return snapshot
    stat_result = path.stat()
    snapshot["size"] = stat_result.st_size
    snapshot["mtime_utc"] = datetime.fromtimestamp(stat_result.st_mtime, tz=timezone.utc).isoformat()
    try:
        snapshot["preview"] = path.read_text(encoding="utf-8", errors="replace")[:2000]
    except OSError as exc:
        snapshot["preview_error"] = str(exc)
    return snapshot


def main() -> int:
    payload = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "cwd": os.getcwd(),
        "whoami": run_shell("whoami"),
        "uptime": run_shell("uptime"),
        "mim_services": run_shell("systemctl --user list-units --type=service --all --no-pager | grep -Ei 'mim|tod|watchdog|listener|mobile-web' || true"),
        "mim_processes": run_shell("ps -ef | grep -Ei 'mim|tod|watchdog|listener|objective|training' | grep -v grep || true"),
        "shared_root": run_shell("ls -la /home/testpilot/mim/runtime/shared 2>/dev/null | sed -n '1,120p' || true"),
        "arm_shared_root": run_shell("ls -la /home/testpilot/mim_arm/runtime/shared 2>/dev/null | sed -n '1,120p' || true"),
        "task_request_stat": run_shell("stat /home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json 2>/dev/null || true"),
        "task_request_writer_refs": run_shell(
            "grep -R -n -E 'MIM_TOD_TASK_REQUEST\\.latest\\.json|MIM_TO_TOD_TRIGGER|shared_trigger' "
            "/home/testpilot/mim/scripts /home/testpilot/mim/core 2>/dev/null | sed -n '1,200p' || true"
        ),
        "training_status": file_snapshot("/home/testpilot/mim/runtime/shared/TOD_TRAINING_STATUS.latest.json"),
        "integration_status": file_snapshot("/home/testpilot/mim/runtime/shared/TOD_INTEGRATION_STATUS.latest.json"),
        "task_request": file_snapshot("/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json"),
        "context_export": file_snapshot("/home/testpilot/mim/runtime/shared/MIM_CONTEXT_EXPORT.latest.json"),
        "handshake_packet": file_snapshot("/home/testpilot/mim/runtime/shared/MIM_TOD_HANDSHAKE_PACKET.latest.json"),
        "initiative_status": file_snapshot("/home/testpilot/mim/runtime/shared/initiative_status.json"),
        "initiative_heartbeat": file_snapshot("/home/testpilot/mim/runtime/shared/initiative_heartbeat.json"),
    }
    json.dump(payload, fp=os.sys.stdout, indent=2)
    os.sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())