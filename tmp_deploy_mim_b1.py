from pathlib import Path
import time

import paramiko

HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"
STAMP = time.strftime("%Y%m%d-%H%M%S")

FILES = {
    Path(r"e:\MIM Robotics\MIM_ARM\config_paths.live.py"): "/home/testpilot/mim_arm/config_paths.py",
    Path(r"e:\MIM Robotics\MIM_ARM\settings_routes.live.py"): "/home/testpilot/mim_arm/settings_routes.py",
    Path(r"e:\MIM Robotics\MIM_ARM\model_loader.live.py"): "/home/testpilot/mim_arm/model_loader.py",
    Path(r"e:\MIM Robotics\MIM_ARM\routes.live.py"): "/home/testpilot/mim_arm/routes.py",
    Path(r"e:\MIM Robotics\MIM_ARM\app.live.py"): "/home/testpilot/mim_arm/app.py",
}

PY_COMPILE_COMMAND = (
    "cd /home/testpilot/mim_arm && "
    "python3 -m py_compile config_paths.py settings_routes.py model_loader.py routes.py app.py"
)


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
        for local_path, remote_path in FILES.items():
            if remote_path.endswith(".py") and not remote_path.endswith("config_paths.py"):
                backup_path = f"{remote_path}.bak-{STAMP}"
                out, err, code = run_command(client, f"cp {remote_path} {backup_path}")
                print(f"BACKUP {remote_path} -> {backup_path} [{code}]")
                if out:
                    print(out)
                if err:
                    print(err)
            sftp.put(str(local_path), remote_path)
            print(f"UPLOADED {local_path} -> {remote_path}")

        out, err, code = run_command(client, PY_COMPILE_COMMAND)
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
