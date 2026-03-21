#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="${TOD_VENV_PATH:-/root/tod-venv}"
SADTALKER_PATH="/workspace/SadTalker"
PIP_CACHE_DIR="${TOD_PIP_CACHE_DIR:-/root/.cache/pip}"
TMPDIR="${TOD_TMPDIR:-/tmp}"

echo "Repo root: ${REPO_ROOT}"
echo "Venv path: ${VENV_PATH}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required on the pod" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required on the pod" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg
  else
    echo "ffmpeg is required on the pod and could not be installed automatically" >&2
    exit 1
  fi
fi

mkdir -p "${PIP_CACHE_DIR}" "${TMPDIR}"
export PIP_CACHE_DIR
export TMPDIR
export PIP_NO_CACHE_DIR=1
export SADTALKER_PATH

if [ ! -d "${VENV_PATH}" ]; then
  python3 -m venv "${VENV_PATH}"
fi

source "${VENV_PATH}/bin/activate"

python -m pip install --upgrade pip wheel "setuptools<81"
python -m pip install edge-tts Pillow requests numpy soundfile

if ! python -m pip install onnxruntime-gpu; then
  python -m pip install onnxruntime
fi

if ! python -m pip install "rembg[gpu]"; then
  python -m pip install rembg
fi

python -m pip install gfpgan basicsr

if [ ! -d "${SADTALKER_PATH}" ]; then
  git clone --depth 1 https://github.com/OpenTalker/SadTalker "${SADTALKER_PATH}"
fi

python -m pip install -r "${SADTALKER_PATH}/requirements.txt"

python - <<'PY'
from pathlib import Path
import inspect
import torchvision.transforms as transforms

transforms_dir = Path(inspect.getfile(transforms)).resolve().parent
legacy_path = transforms_dir / "functional_tensor.py"
modern_path = transforms_dir / "_functional_tensor.py"

if modern_path.exists() and not legacy_path.exists():
  legacy_path.write_text("from ._functional_tensor import *\n", encoding="utf-8")
  print(f"Created torchvision compatibility shim: {legacy_path}")
PY

python - <<'PY'
from pathlib import Path
import os

animate_path = Path(os.environ["SADTALKER_PATH"]) / "src" / "facerender" / "animate.py"
content = animate_path.read_text(encoding="utf-8")

helper = '''def _write_mp4(path, frames, fps):
  if not frames:
    raise ValueError("No frames to write")
  first_frame = frames[0]
  height, width = first_frame.shape[:2]
  writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), float(fps), (width, height))
  if not writer.isOpened():
    raise RuntimeError(f"Failed to open video writer for {path}")
  try:
    for frame in frames:
      writer.write(cv2.cvtColor(np.asarray(frame), cv2.COLOR_RGB2BGR))
  finally:
    writer.release()

'''

if "def _write_mp4(path, frames, fps):" not in content:
  marker = "class AnimateFromCoeff():\n"
  if marker not in content:
    raise RuntimeError(f"Unexpected SadTalker animate.py structure: {animate_path}")
  content = content.replace(marker, helper + marker, 1)

content = content.replace("import imageio\n", "")
content = content.replace("        imageio.mimsave(path, result,  fps=float(25))\n", "        _write_mp4(path, result, fps=float(25))\n")
content = content.replace("                imageio.mimsave(enhanced_path, enhanced_images_gen_with_len, fps=float(25))\n", "                _write_mp4(enhanced_path, enhanced_images_gen_with_len, fps=float(25))\n")

animate_path.write_text(content, encoding="utf-8")
print(f"Patched SadTalker video writer: {animate_path}")
PY

if [ ! -d "${SADTALKER_PATH}/checkpoints" ] || [ -z "$(find "${SADTALKER_PATH}/checkpoints" -type f 2>/dev/null)" ]; then
  echo "Downloading SadTalker checkpoints..."
  (
    cd "${SADTALKER_PATH}"
    bash scripts/download_models.sh
  )
fi

echo "Bootstrap complete."
echo "Next command:"
echo "  cd ${REPO_ROOT} && source ${VENV_PATH}/bin/activate"