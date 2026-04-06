import paramiko

HOST = "192.168.1.90"
USER = "testpilot"
PASSWORD = "dontcrash"

RESTART_COMMAND = r"""
set -e
old_pid=$(ps -ef | awk '/python3 app.py|python app.py/ && !/awk/ {print $2; exit}')
echo OLD_PID=$old_pid
if [ -n "$old_pid" ]; then
  kill -TERM "$old_pid"
  for i in $(seq 1 30); do
    if kill -0 "$old_pid" 2>/dev/null; then
      sleep 1
    else
      echo STOPPED_AFTER=${i}s
      break
    fi
  done
  if kill -0 "$old_pid" 2>/dev/null; then
    echo OLD_PROCESS_STILL_RUNNING=1
    exit 1
  fi
fi
cd /home/testpilot/mim_arm
export VIRTUAL_ENV=/home/testpilot/mim_arm/mimenv
export PATH=/home/testpilot/mim_arm/mimenv/bin:$PATH
nohup /home/testpilot/mim_arm/mimenv/bin/python3 app.py >/home/testpilot/mim_arm/mim.manual.log 2>&1 </dev/null &
new_pid=$!
echo NEW_PID=$new_pid
sleep 6
ps -fp "$new_pid" -o pid,ppid,tty,stat,lstart,cmd
"""

SMOKE_COMMAND = r"""
set -e
cd /home/testpilot/mim_arm
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:5000/status >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
printf '===STATUS===\n'
curl -fsS http://127.0.0.1:5000/status
printf '\n===SETTINGS===\n'
curl -fsS http://127.0.0.1:5000/get_settings
printf '\n===TEST===\n'
curl -i -s http://127.0.0.1:5000/test | head -n 20
printf '\n===VOICE_DASHBOARD===\n'
curl -i -s http://127.0.0.1:5000/voice_dashboard | head -n 20
printf '\n===PROCESS===\n'
ps -ef | grep -E 'python3 .*app.py|python .*app.py' | grep -v grep
"""


def run_command(client: paramiko.SSHClient, command: str, use_bash: bool = False) -> tuple[str, str, int]:
  remote_command = "bash -s" if use_bash else command
  stdin, stdout, stderr = client.exec_command(remote_command, timeout=120)
  if use_bash:
    stdin.write(command)
    stdin.channel.shutdown_write()
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
    try:
        out, err, code = run_command(client, RESTART_COMMAND, use_bash=True)
        print("===RESTART_CODE===")
        print(code)
        print("===RESTART_OUT===")
        print(out)
        print("===RESTART_ERR===")
        print(err)

        out, err, code = run_command(client, SMOKE_COMMAND, use_bash=True)
        print("===SMOKE_CODE===")
        print(code)
        print("===SMOKE_OUT===")
        print(out)
        print("===SMOKE_ERR===")
        print(err)
    finally:
        client.close()


if __name__ == "__main__":
    main()
