from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


DEFAULT_PATH = "/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json"
REMOTE_CHILD_FLAG = "--remote-execution-child"
STABILITY_FIELDS = (
    "hostname",
    "whoami",
    "absolute_path",
    "realpath",
    "ls_inode",
    "mtime",
    "size",
    "sha256",
    "task_id",
    "request_id",
    "objective_id",
    "correlation_id",
    "generated_at",
    "sequence",
    "source_service",
    "source_instance_id",
)
SUMMARY_FIELDS = (
    "hostname",
    "whoami",
    "absolute_path",
    "realpath",
    "pwd",
    "ls_inode",
    "mtime",
    "size",
    "sha256",
    "task_id",
    "request_id",
    "objective_id",
    "correlation_id",
    "generated_at",
    "emitted_at",
    "sequence",
    "source_service",
    "source_instance_id",
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Probe the canonical MIM task request locally or by running the same script remotely over SSH."
    )
    parser.add_argument("--path", default=DEFAULT_PATH, help="Canonical task request path to sample.")
    parser.add_argument("--samples", type=int, default=1, help="Number of repeated samples to capture.")
    parser.add_argument(
        "--interval-seconds",
        type=float,
        default=0.0,
        help="Delay between repeated samples.",
    )
    parser.add_argument("--host", help="Remote host for SSH execution.")
    parser.add_argument("--user", help="Remote user for SSH execution.")
    parser.add_argument("--port", type=int, help="SSH port override.")
    parser.add_argument("--ssh-key", help="SSH private key path.")
    parser.add_argument("--password", help="SSH password for password-based remote fallback.")
    parser.add_argument(
        "--password-env",
        help="Environment variable name containing the SSH password for password-based remote fallback.",
    )
    parser.add_argument(
        "--ssh-config-host",
        help="SSH config host alias to use instead of composing user@host manually.",
    )
    parser.add_argument(
        "--python-bin",
        default="python3",
        help="Remote Python executable name for SSH mode.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=30.0,
        help="Timeout for remote SSH execution.",
    )
    parser.add_argument(REMOTE_CHILD_FLAG, action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.samples < 1:
        parser.error("--samples must be at least 1")
    if args.interval_seconds < 0:
        parser.error("--interval-seconds must be non-negative")
    if args.port is not None and args.port < 1:
        parser.error("--port must be positive")
    return args


def utc_now_iso() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_dotenv_values() -> dict[str, str]:
    candidates = [Path.cwd() / ".env", Path(__file__).resolve().parent / ".env"]
    values: dict[str, str] = {}
    for candidate in candidates:
        if not candidate.exists():
            continue
        for raw_line in candidate.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            clean_key = key.strip()
            clean_value = value.strip().strip('"').strip("'")
            if clean_key and clean_key not in values:
                values[clean_key] = clean_value
    return values


def first_present(payload: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        value = payload.get(key)
        if value not in (None, ""):
            return value
    return None


def normalize_text(value: Any) -> str | None:
    if value in (None, ""):
        return None
    return str(value)


def normalize_number(value: Any) -> int | float | None:
    if value in (None, ""):
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return value
    text = str(value).strip()
    if not text:
        return None
    try:
        return int(text)
    except ValueError:
        try:
            return float(text)
        except ValueError:
            return None


def read_payload(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = path.read_bytes()
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"Expected JSON object in {path}")
    return payload, raw


def build_sample(path_text: str) -> dict[str, Any]:
    path = Path(path_text)
    absolute_path = os.path.abspath(os.fspath(path))
    real_path = os.path.realpath(absolute_path)
    payload, raw = read_payload(Path(absolute_path))
    stat_result = os.stat(absolute_path)

    sample: dict[str, Any] = {}
    sample["hostname"] = socket.gethostname()
    sample["whoami"] = getpass.getuser()
    sample["absolute_path"] = absolute_path
    sample["realpath"] = real_path
    sample["pwd"] = os.getcwd()
    sample["ls_inode"] = normalize_number(stat_result.st_ino)
    sample["mtime"] = stat_result.st_mtime
    sample["size"] = stat_result.st_size
    sample["sha256"] = hashlib.sha256(raw).hexdigest()
    sample["task_id"] = normalize_text(first_present(payload, "task_id"))
    sample["request_id"] = normalize_text(first_present(payload, "request_id", "task_id"))
    sample["objective_id"] = normalize_text(
        first_present(payload, "objective_id", "objective_active", "current_next_objective")
    )
    sample["correlation_id"] = normalize_text(first_present(payload, "correlation_id"))
    sample["generated_at"] = normalize_text(first_present(payload, "generated_at"))
    sample["emitted_at"] = utc_now_iso()
    sample["sequence"] = normalize_number(first_present(payload, "sequence"))
    sample["source_service"] = normalize_text(first_present(payload, "source_service"))
    sample["source_instance_id"] = normalize_text(first_present(payload, "source_instance_id"))
    return sample


def collect_samples(path_text: str, samples: int, interval_seconds: float) -> list[dict[str, Any]]:
    captured: list[dict[str, Any]] = []
    for index in range(samples):
        captured.append(build_sample(path_text))
        if index + 1 < samples and interval_seconds > 0:
            time.sleep(interval_seconds)
    return captured


def is_stable(samples: list[dict[str, Any]]) -> bool:
    if len(samples) < 2:
        return True
    first = samples[0]
    for sample in samples[1:]:
        for field in STABILITY_FIELDS:
            if sample.get(field) != first.get(field):
                return False
    return True


def build_result(
    samples: list[dict[str, Any]],
    mode: str,
    interval_seconds: float,
    requested_host: str | None = None,
    requested_user: str | None = None,
    ssh_target: str | None = None,
) -> dict[str, Any]:
    lead = samples[0]
    result: dict[str, Any] = {}
    for field in SUMMARY_FIELDS:
        result[field] = lead.get(field)
    result["mode"] = mode
    if requested_host:
        result["requested_host"] = requested_host
    if requested_user:
        result["requested_user"] = requested_user
    if ssh_target:
        result["ssh_target"] = ssh_target
    result["sample_count"] = len(samples)
    result["interval_seconds"] = interval_seconds
    result["stable_across_samples"] = is_stable(samples)
    result["stability_fields"] = list(STABILITY_FIELDS)
    result["samples"] = samples
    return result


def extract_json_document(text: str) -> Any:
    stripped = text.strip()
    if not stripped:
        raise ValueError("Remote execution returned no output")
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass

    for index, char in enumerate(text):
        if char not in "[{":
            continue
        candidate = text[index:].strip()
        if not candidate:
            continue
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    raise ValueError("Unable to parse JSON from remote execution output")


def quote_for_posix(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def powershell_single_quote(text: str) -> str:
    return text.replace("'", "''")


def build_ssh_target(args: argparse.Namespace) -> str:
    if args.ssh_config_host:
        return str(args.ssh_config_host)
    if not args.host:
        raise ValueError("--host or --ssh-config-host is required for remote mode")
    if args.user:
        return f"{args.user}@{args.host}"
    return str(args.host)


def resolve_password(args: argparse.Namespace) -> str | None:
    if args.password:
        return args.password
    if args.password_env:
        value = os.environ.get(args.password_env)
        if value:
            return value

    env_values = load_dotenv_values()
    for key in ("MIM_SSH_PASSWORD", "MIM_ARM_SSH_HOST_PASS"):
        value = os.environ.get(key) or env_values.get(key)
        if value:
            return value
    return None


def build_remote_python_command(args: argparse.Namespace, remote_script_path: str) -> str:
    parts = [
        quote_for_posix(str(args.python_bin)),
        quote_for_posix(remote_script_path),
        REMOTE_CHILD_FLAG,
        "--path",
        quote_for_posix(str(args.path)),
        "--samples",
        quote_for_posix(str(args.samples)),
        "--interval-seconds",
        quote_for_posix(str(args.interval_seconds)),
    ]
    return " ".join(parts)


def run_remote_with_posh_ssh(args: argparse.Namespace, password: str) -> dict[str, Any]:
    host = args.host or args.ssh_config_host
    if not host:
        raise ValueError("A concrete host is required for Posh-SSH fallback")
    user = args.user
    if not user:
        raise ValueError("--user is required for password-based remote fallback")

    local_script_path = str(Path(__file__).resolve())
    remote_script_name = Path(local_script_path).name
    remote_script_dir = "/tmp"
    remote_script_path = f"{remote_script_dir}/{remote_script_name}"
    remote_python_command = build_remote_python_command(args, remote_script_path)
    port = args.port or 22

    ps_script = f"""
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module Posh-SSH -ErrorAction Stop
$password = ConvertTo-SecureString '{powershell_single_quote(password)}' -AsPlainText -Force
$credential = [pscredential]::new('{powershell_single_quote(user)}', $password)
$ssh = $null
$sftp = $null
try {{
    $ssh = New-SSHSession -ComputerName '{powershell_single_quote(host)}' -Port {port} -Credential $credential -AcceptKey
    $sftp = New-SFTPSession -ComputerName '{powershell_single_quote(host)}' -Port {port} -Credential $credential -AcceptKey
    Set-SFTPItem -SessionId $sftp.SessionId -Path '{powershell_single_quote(local_script_path)}' -Destination '{powershell_single_quote(remote_script_dir)}' -Force
    $commandResult = Invoke-SSHCommand -SessionId $ssh.SessionId -Command '{powershell_single_quote(remote_python_command)}'
    if ($commandResult.ExitStatus -ne 0) {{
        $remoteError = (($commandResult.Error | Out-String).Trim())
        if ([string]::IsNullOrWhiteSpace($remoteError)) {{
            $remoteError = (($commandResult.Output | Out-String).Trim())
        }}
        throw $remoteError
    }}
    Write-Output (($commandResult.Output | Out-String).Trim())
}}
finally {{
    if ($ssh) {{
        try {{ Invoke-SSHCommand -SessionId $ssh.SessionId -Command 'rm -f {powershell_single_quote(remote_script_path)}' | Out-Null }} catch {{ }}
        Remove-SSHSession -SessionId $ssh.SessionId | Out-Null
    }}
    if ($sftp) {{
        Remove-SFTPSession -SessionId $sftp.SessionId | Out-Null
    }}
}}
"""
    encoded = base64.b64encode(ps_script.encode("utf-16le")).decode("ascii")
    completed = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-EncodedCommand",
            encoded,
        ],
        text=True,
        capture_output=True,
        timeout=args.timeout_seconds,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "Posh-SSH fallback failed"
        raise RuntimeError(detail)

    remote_result = extract_json_document(completed.stdout)
    if not isinstance(remote_result, dict):
        raise ValueError("Remote probe returned unexpected JSON shape")

    remote_result["mode"] = "remote"
    remote_result["requested_host"] = host
    remote_result["requested_user"] = user
    remote_result["ssh_target"] = f"{user}@{host}"
    remote_result["transport"] = "posh-ssh"
    return remote_result


def run_remote(args: argparse.Namespace) -> dict[str, Any]:
    ssh_target = build_ssh_target(args)
    remote_command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
    ]
    if args.port:
        remote_command.extend(["-p", str(args.port)])
    if args.ssh_key:
        remote_command.extend(["-i", str(args.ssh_key)])
    remote_command.append(ssh_target)
    remote_command.extend(
        [
            str(args.python_bin),
            "-",
            REMOTE_CHILD_FLAG,
            "--path",
            str(args.path),
            "--samples",
            str(args.samples),
            "--interval-seconds",
            str(args.interval_seconds),
        ]
    )

    script_source = Path(__file__).read_text(encoding="utf-8")
    completed = subprocess.run(
        remote_command,
        input=script_source,
        text=True,
        capture_output=True,
        timeout=args.timeout_seconds,
        check=False,
    )
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or f"ssh exited with code {completed.returncode}"
        if "Permission denied" in detail:
            password = resolve_password(args)
            if password:
                return run_remote_with_posh_ssh(args, password)
        raise RuntimeError(detail)

    remote_result = extract_json_document(completed.stdout)
    if not isinstance(remote_result, dict):
        raise ValueError("Remote probe returned unexpected JSON shape")

    remote_result["mode"] = "remote"
    if args.host:
        remote_result["requested_host"] = args.host
    if args.user:
        remote_result["requested_user"] = args.user
    remote_result["ssh_target"] = ssh_target
    remote_result["transport"] = "ssh"
    return remote_result


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if (args.host or args.ssh_config_host) and not args.remote_execution_child:
            result = run_remote(args)
        else:
            samples = collect_samples(args.path, args.samples, args.interval_seconds)
            result = build_result(
                samples,
                mode="local",
                interval_seconds=args.interval_seconds,
            )
        json.dump(result, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    except Exception as exc:
        error_payload = {
            "mode": "remote" if (args.host or args.ssh_config_host) and not args.remote_execution_child else "local",
            "error": str(exc),
            "path": args.path,
        }
        if args.host:
            error_payload["requested_host"] = args.host
        if args.user:
            error_payload["requested_user"] = args.user
        if args.ssh_config_host:
            error_payload["ssh_target"] = args.ssh_config_host
        json.dump(error_payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())