from pathlib import Path
import time

import paramiko

HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"
STAMP = time.strftime("%Y%m%d-%H%M%S")
LOCAL_PATH = Path(r"e:\MIM Robotics\MIM_ARM\routes.live.py")
REMOTE_PATH = "/home/testpilot/mim_arm/routes.py"
COMPILE_COMMAND = "cd /home/testpilot/mim_arm && python3 -m py_compile routes.py"


def run_command(client: paramiko.SSHClient, command: str) -> tuple[str, str, int]:
    stdin, stdout, stderr = client.exec_command(command, timeout=120)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace").strip()
    err = stderr.read().decode("utf-8", errors="replace").strip()
    return out, err, exit_code


def main() -> None:
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
    sftp = client.open_sftp()
    try:
        backup_path = f"{REMOTE_PATH}.bak-{STAMP}"
        out, err, code = run_command(client, f"cp {REMOTE_PATH} {backup_path}")
        print(f"BACKUP {REMOTE_PATH} -> {backup_path} [{code}]")
        if out:
            print(out)
        if err:
            print(err)

        sftp.put(str(LOCAL_PATH), REMOTE_PATH)
        print(f"UPLOADED {LOCAL_PATH} -> {REMOTE_PATH}")

        out, err, code = run_command(client, COMPILE_COMMAND)
        print(f"PY_COMPILE [{code}]")
        if out:
            print(out)
        if err:
            print(err)
        if code != 0:
            raise RuntimeError("remote py_compile failed")
    finally:
        sftp.close()
        client.close()


if __name__ == "__main__":
    main()
