import json
from pathlib import Path

import paramiko


HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"

FILES = {
    "/home/testpilot/mim_arm/voice_routes.py": Path(r"e:\MIM Robotics\MIM_ARM\voice_routes.live.py"),
    "/home/testpilot/mim_arm/command_processor.py": Path(r"e:\MIM Robotics\MIM_ARM\command_processor.live.py"),
    "/home/testpilot/mim_arm/routes.py": Path(r"e:\MIM Robotics\MIM_ARM\routes.live.py"),
}

TEMPLATE_OUT = Path(r"e:\MIM Robotics\MIM_ARM\templates.live.json")
EXPLORE_PROBE_OUT = Path(r"e:\MIM Robotics\MIM_ARM\explore_action_script_probe.txt")


def run_command(client: paramiko.SSHClient, command: str) -> str:
    stdin, stdout, stderr = client.exec_command(command)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    if exit_code != 0:
        raise RuntimeError(f"command failed: {command}\n{err or out}")
    return out


def main() -> None:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        hostname=HOST,
        username=USER,
        password=PASSWORD,
        timeout=15,
        allow_agent=False,
        look_for_keys=False,
    )
    sftp = client.open_sftp()
    try:
        for remote_path, local_path in FILES.items():
            local_path.parent.mkdir(parents=True, exist_ok=True)
            with sftp.open(remote_path, "r") as src:
                data = src.read().decode("utf-8", errors="replace")
            local_path.write_text(data, encoding="utf-8")

        templates = run_command(client, "find /home/testpilot/mim_arm/templates -maxdepth 1 -type f | sort")
        TEMPLATE_OUT.write_text(json.dumps(templates.splitlines(), indent=2), encoding="utf-8")

        explore_probe = run_command(
            client,
            "bash -lc 'find /home/testpilot/mim_arm -maxdepth 2 -type f | grep explore_action_script || true'",
        )
        EXPLORE_PROBE_OUT.write_text(explore_probe, encoding="utf-8")
    finally:
        sftp.close()
        client.close()


if __name__ == "__main__":
    main()