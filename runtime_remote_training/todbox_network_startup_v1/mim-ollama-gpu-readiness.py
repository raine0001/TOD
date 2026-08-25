#!/usr/bin/env python3
"""Recover and prove GPU-backed Ollama vision review after host startup."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable


def command(*args: str, timeout: float = 30.0) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "ok": completed.returncode == 0,
            "returncode": completed.returncode,
            "stdout": completed.stdout.strip(),
            "stderr": completed.stderr.strip(),
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "returncode": -1, "stdout": "", "stderr": str(exc)}


def http_json(url: str, payload: dict[str, Any] | None = None, timeout: float = 60.0) -> dict[str, Any]:
    data = None
    headers: dict[str, str] = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - fixed local URL
        return json.loads(response.read().decode("utf-8"))


def model_vram_bytes(payload: object, model: str) -> int:
    if not isinstance(payload, dict):
        return 0
    for item in payload.get("models") or []:
        if not isinstance(item, dict):
            continue
        observed = str(item.get("model") or item.get("name") or "").strip()
        if observed == model:
            try:
                return max(0, int(item.get("size_vram") or 0))
            except (TypeError, ValueError):
                return 0
    return 0


def write_evidence(path: Path, evidence: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def run_gate(
    *,
    container: str,
    model: str,
    base_url: str,
    timeout: float,
    interval: float,
    output: Path,
    command_fn: Callable[..., dict[str, Any]] = command,
    http_fn: Callable[..., dict[str, Any]] = http_json,
    sleep_fn: Callable[[float], None] = time.sleep,
    monotonic_fn: Callable[[], float] = time.monotonic,
) -> tuple[int, dict[str, Any]]:
    started = monotonic_fn()
    deadline = started + max(1.0, timeout)
    restarted = False
    attempt = 0
    last_error = "readiness_not_checked"
    evidence: dict[str, Any] = {}

    while True:
        attempt += 1
        running = command_fn("docker", "inspect", "--format", "{{.State.Running}}", container)
        nvml = command_fn(
            "docker",
            "exec",
            container,
            "nvidia-smi",
            "--query-gpu=name",
            "--format=csv,noheader",
        ) if running.get("ok") and running.get("stdout") == "true" else {"ok": False, "stderr": "container_not_running"}

        if not nvml.get("ok") and not restarted:
            recovery = command_fn("docker", "restart", container, timeout=120.0)
            restarted = True
            last_error = str(nvml.get("stderr") or "nvidia_not_ready")[:240]
            if recovery.get("ok"):
                sleep_fn(max(0.0, interval))
                continue
            last_error = str(recovery.get("stderr") or "container_restart_failed")[:240]

        vram_bytes = 0
        warm_duration_ms = 0
        if nvml.get("ok"):
            warm_started = monotonic_fn()
            try:
                http_fn(
                    f"{base_url.rstrip('/')}/api/generate",
                    {
                        "model": model,
                        "prompt": "Return only OK.",
                        "stream": False,
                        "keep_alive": -1,
                        "options": {"temperature": 0, "num_predict": 4},
                    },
                    timeout=120.0,
                )
                warm_duration_ms = int((monotonic_fn() - warm_started) * 1000)
                vram_bytes = model_vram_bytes(
                    http_fn(f"{base_url.rstrip('/')}/api/ps", timeout=10.0),
                    model,
                )
                last_error = "" if vram_bytes > 0 else "vision_model_loaded_without_gpu_vram"
            except Exception as exc:  # noqa: BLE001 - evidence captures bounded local failure
                last_error = f"{type(exc).__name__}: {exc}"[:240]

        evidence = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "ok": bool(nvml.get("ok") and vram_bytes > 0),
            "attempt": attempt,
            "container": container,
            "container_running": bool(running.get("ok") and running.get("stdout") == "true"),
            "nvidia_ready": bool(nvml.get("ok")),
            "nvidia_devices": [line for line in str(nvml.get("stdout") or "").splitlines() if line.strip()],
            "container_restarted": restarted,
            "model": model,
            "model_size_vram": vram_bytes,
            "warm_duration_ms": warm_duration_ms,
            "error": last_error,
        }
        write_evidence(output, evidence)
        if evidence["ok"]:
            return 0, evidence
        if monotonic_fn() >= deadline:
            return 1, evidence
        sleep_fn(max(0.0, interval))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--container", default="mim-ollama")
    parser.add_argument("--model", default="qwen2.5vl:3b")
    parser.add_argument("--base-url", default="http://127.0.0.1:11434")
    parser.add_argument("--timeout", type=float, default=300.0)
    parser.add_argument("--interval", type=float, default=5.0)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("/var/lib/todbox-connectivity/ollama-gpu-readiness.latest.json"),
    )
    args = parser.parse_args()
    return run_gate(
        container=args.container,
        model=args.model,
        base_url=args.base_url,
        timeout=args.timeout,
        interval=args.interval,
        output=args.output,
    )[0]


if __name__ == "__main__":
    raise SystemExit(main())
