import paramiko


HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"

CHECKS = [
    ("/home/testpilot/mim_arm/voice_routes.py", '"message": f"Missing template: {VOICE_DASHBOARD_TEMPLATE}"'),
    ("/home/testpilot/mim_arm/command_processor.py", 'print("⚠️ Explore mode unavailable: missing explore_action_script.py")'),
    ("/home/testpilot/mim_arm/routes.py", "return render_known_template('test.html')"),
]


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
    try:
        for remote_path, marker in CHECKS:
            stdin, stdout, stderr = client.exec_command("cat " + remote_path)
            stdout.channel.recv_exit_status()
            text = stdout.read().decode("utf-8", errors="replace")
            print(remote_path + "=" + ("present" if marker in text else "missing"))
    finally:
        client.close()


if __name__ == "__main__":
    main()