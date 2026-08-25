import importlib.util
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "mim-ollama-gpu-readiness.py"
SPEC = importlib.util.spec_from_file_location("mim_ollama_gpu_readiness", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def test_model_vram_bytes_matches_exact_model():
    payload = {
        "models": [
            {"name": "other:latest", "size_vram": 99},
            {"model": "qwen2.5vl:3b", "size_vram": 4096},
        ]
    }
    assert MODULE.model_vram_bytes(payload, "qwen2.5vl:3b") == 4096


def test_gate_restarts_after_nvml_failure_then_proves_gpu(tmp_path):
    nvml_attempts = 0
    commands = []

    def fake_command(*args, **_kwargs):
        nonlocal nvml_attempts
        commands.append(args)
        if args[:2] == ("docker", "inspect"):
            return {"ok": True, "stdout": "true", "stderr": ""}
        if args[:3] == ("docker", "exec", "mim-ollama"):
            nvml_attempts += 1
            if nvml_attempts == 1:
                return {"ok": False, "stdout": "", "stderr": "Failed to initialize NVML"}
            return {"ok": True, "stdout": "Tesla PG500-216", "stderr": ""}
        if args[:3] == ("docker", "restart", "mim-ollama"):
            return {"ok": True, "stdout": "mim-ollama", "stderr": ""}
        raise AssertionError(args)

    def fake_http(url, payload=None, **_kwargs):
        if url.endswith("/api/generate"):
            assert payload["model"] == "qwen2.5vl:3b"
            return {"done": True, "response": "OK"}
        return {"models": [{"model": "qwen2.5vl:3b", "size_vram": 4098380267}]}

    rc, evidence = MODULE.run_gate(
        container="mim-ollama",
        model="qwen2.5vl:3b",
        base_url="http://127.0.0.1:11434",
        timeout=10,
        interval=0,
        output=tmp_path / "evidence.json",
        command_fn=fake_command,
        http_fn=fake_http,
        sleep_fn=lambda _seconds: None,
        monotonic_fn=lambda: 0.0,
    )

    assert rc == 0
    assert evidence["ok"] is True
    assert evidence["container_restarted"] is True
    assert evidence["model_size_vram"] == 4098380267
    assert ("docker", "restart", "mim-ollama") in commands


def test_gate_fails_when_model_remains_cpu_only(tmp_path):
    ticks = iter([0.0, 0.1, 0.2, 2.0])

    def fake_command(*args, **_kwargs):
        if args[:2] == ("docker", "inspect"):
            return {"ok": True, "stdout": "true", "stderr": ""}
        return {"ok": True, "stdout": "Tesla PG500-216", "stderr": ""}

    def fake_http(url, payload=None, **_kwargs):
        if url.endswith("/api/generate"):
            return {"done": True}
        return {"models": [{"model": "qwen2.5vl:3b", "size_vram": 0}]}

    rc, evidence = MODULE.run_gate(
        container="mim-ollama",
        model="qwen2.5vl:3b",
        base_url="http://127.0.0.1:11434",
        timeout=1,
        interval=0,
        output=tmp_path / "evidence.json",
        command_fn=fake_command,
        http_fn=fake_http,
        sleep_fn=lambda _seconds: None,
        monotonic_fn=lambda: next(ticks),
    )

    assert rc == 1
    assert evidence["ok"] is False
    assert evidence["error"] == "vision_model_loaded_without_gpu_vram"
