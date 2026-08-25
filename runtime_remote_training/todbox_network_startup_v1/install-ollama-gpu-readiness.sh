#!/usr/bin/env bash
set -euo pipefail

EXPECTED_HOST="tod-ai-01"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash $0" >&2
  exit 2
fi
if [[ "$(hostname)" != "${EXPECTED_HOST}" ]]; then
  echo "Refusing wrong host: expected ${EXPECTED_HOST}, got $(hostname)" >&2
  exit 3
fi

install -o root -g root -m 755 "${SOURCE_DIR}/mim-ollama-gpu-readiness.py" /usr/local/sbin/mim-ollama-gpu-readiness
install -o root -g root -m 644 "${SOURCE_DIR}/mim-ollama-gpu-readiness.service" /etc/systemd/system/mim-ollama-gpu-readiness.service
install -o root -g root -m 644 "${SOURCE_DIR}/mim-ollama-gpu-readiness.timer" /etc/systemd/system/mim-ollama-gpu-readiness.timer
install -d -o root -g root -m 755 /etc/systemd/system/mim-creative-worker.service.d
install -o root -g root -m 644 "${SOURCE_DIR}/20-ollama-gpu-readiness.conf" /etc/systemd/system/mim-creative-worker.service.d/20-ollama-gpu-readiness.conf
install -d -o root -g root -m 755 /etc/systemd/system/todbox-startup-connectivity-verify.service.d
install -o root -g root -m 644 "${SOURCE_DIR}/20-ollama-gpu-readiness.conf" /etc/systemd/system/todbox-startup-connectivity-verify.service.d/20-ollama-gpu-readiness.conf

systemctl daemon-reload
systemctl enable mim-ollama-gpu-readiness.service mim-ollama-gpu-readiness.timer
systemctl restart mim-ollama-gpu-readiness.service
systemctl restart mim-creative-worker.service
systemctl restart mim-ollama-gpu-readiness.timer

systemctl is-active --quiet mim-creative-worker.service
python3 - <<'PY'
import json
from pathlib import Path
evidence = json.loads(Path('/var/lib/todbox-connectivity/ollama-gpu-readiness.latest.json').read_text())
if not evidence.get('ok') or int(evidence.get('model_size_vram') or 0) <= 0:
    raise SystemExit('Ollama GPU readiness evidence did not pass')
print(json.dumps(evidence, indent=2, sort_keys=True))
PY
