import paramiko

HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"

SCRIPT = r"""
set -e
pkill -f 'python3 .*app.py' || true
sleep 2
cd /home/testpilot/mim_arm
nohup /home/testpilot/mim_arm/mimenv/bin/python3 app.py >/home/testpilot/mim_arm/mim.manual.log 2>&1 </dev/null &
echo NEW_PID=$!
sleep 5
ps -ef | grep -E 'python3 .*app.py' | grep -v grep
"""


def main() -> None:
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(hostname=HOST, username=USER, password=PASSWORD, timeout=20, allow_agent=False, look_for_keys=False)
    try:
        stdin, stdout, stderr = c.exec_command("bash -s", timeout=120)
        stdin.write(SCRIPT)
        stdin.channel.shutdown_write()
        code = stdout.channel.recv_exit_status()
        print("EXIT", code)
        print(stdout.read().decode("utf-8", errors="replace"))
        err = stderr.read().decode("utf-8", errors="replace")
        if err:
            print("STDERR")
            print(err)
    finally:
        c.close()


if __name__ == "__main__":
    main()
