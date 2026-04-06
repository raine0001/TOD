import paramiko


HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"

COMMANDS = [
    "pwd",
    "ps -ef | grep -E 'python3 .*app.py|python .*app.py' | grep -v grep || true",
    "systemctl list-unit-files --type=service | grep -i mim || true",
    "systemctl list-units --type=service --all | grep -i mim || true",
]


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
    try:
        for command in COMMANDS:
            stdin, stdout, stderr = client.exec_command(command)
            stdout.channel.recv_exit_status()
            out = stdout.read().decode("utf-8", errors="replace").strip()
            err = stderr.read().decode("utf-8", errors="replace").strip()
            print("===CMD===")
            print(command)
            print("===OUT===")
            print(out)
            print("===ERR===")
            print(err)
    finally:
        client.close()


if __name__ == "__main__":
    main()