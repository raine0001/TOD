"""
animate_sadtalker.py — SadTalker inference runner for TOD spokesperson pipeline.

Calls SadTalker's inference.py as a subprocess from its install directory.
SadTalker produces a talking-head MP4 from a still portrait + WAV audio.

Quality flags used for 95% realism:
  --preprocess full       : full face region detection (not cropped-only)
  --still                 : minimal unnecessary head movement
  --enhancer gfpgan       : GFPGAN face enhancement on output (critical for quality)
  --size 512              : higher resolution processing (512 vs default 256)
  --expression_scale 1.0  : natural expression amplitude

Usage:
    python animate_sadtalker.py \
        --source-image composited.jpg \
        --driven-audio audio.wav \
        --output-dir output/ \
        --output-name final.mp4 \
        --sadtalker-path C:/AI/SadTalker \
        --enhancer gfpgan \
        --size 512

Exit 0 on success, 1 on failure.
"""
import argparse
import os
import subprocess
import sys
import glob
import shutil


SADTALKER_DEFAULT_PATH = "C:/AI/SadTalker"


def parse_args():
    p = argparse.ArgumentParser(description="SadTalker talking-head animator")
    p.add_argument("--source-image",    required=True,  help="Composited portrait JPG/PNG")
    p.add_argument("--driven-audio",    required=True,  help="WAV audio file")
    p.add_argument("--output-dir",      required=True,  help="Directory for result MP4")
    p.add_argument("--output-name",     default="spokesperson.mp4")
    p.add_argument("--sadtalker-path",  default=SADTALKER_DEFAULT_PATH,
                   help="Path to SadTalker repo root")
    p.add_argument("--python-exe",      default="python")
    p.add_argument("--enhancer",        default="gfpgan",
                   choices=["gfpgan", "RestoreFormer", "none"],
                   help="Face enhancer: gfpgan delivers best quality")
    p.add_argument("--size",            type=int, default=512,
                   choices=[256, 512],
                   help="Processing size. 512 = higher quality, more VRAM (~12GB+)")
    p.add_argument("--preprocess",      default="full",
                   choices=["crop", "resize", "full", "extcrop", "extfull"])
    p.add_argument("--pose-style",      type=int, default=0,
                   help="Head pose style index 0–45")
    p.add_argument("--expression-scale", type=float, default=1.0)
    p.add_argument("--still",           action="store_true", default=True,
                   help="Use still mode (minimal head drift, more natural for spokesperson)")
    p.add_argument("--face3dvis",       action="store_true", default=False)
    return p.parse_args()


def find_sadtalker(sadtalker_path: str) -> str:
    """Validate SadTalker install and return inference.py path."""
    inference = os.path.join(sadtalker_path, "inference.py")
    if not os.path.exists(inference):
        raise FileNotFoundError(
            f"SadTalker inference.py not found at: {inference}\n"
            f"Install SadTalker: git clone https://github.com/OpenTalker/SadTalker {sadtalker_path}"
        )
    return inference


def run_inference(args) -> str:
    """Run SadTalker inference and return path to output MP4."""
    inference_py = find_sadtalker(args.sadtalker_path)

    os.makedirs(args.output_dir, exist_ok=True)

    cmd = [
        args.python_exe,
        inference_py,
        "--driven_audio",   os.path.abspath(args.driven_audio),
        "--source_image",   os.path.abspath(args.source_image),
        "--result_dir",     os.path.abspath(args.output_dir),
        "--preprocess",     args.preprocess,
        "--size",           str(args.size),
        "--pose_style",     str(args.pose_style),
        "--expression_scale", str(args.expression_scale),
        "--batch_size",     "1",
    ]

    if args.still:
        cmd.append("--still")

    if args.enhancer != "none":
        cmd.extend(["--enhancer", args.enhancer])

    if args.face3dvis:
        cmd.append("--face3dvis")

    print(f"  SadTalker cmd: {' '.join(cmd)}")
    print(f"  Working dir: {args.sadtalker_path}")

    result = subprocess.run(
        cmd,
        cwd=args.sadtalker_path,
        capture_output=False,   # Let SadTalker print progress to console
        text=True
    )

    if result.returncode != 0:
        print(f"ERROR: SadTalker exited with code {result.returncode}", file=sys.stderr)
        sys.exit(result.returncode)

    # SadTalker saves output under result_dir with auto-named file
    # Find the most recent MP4 in output_dir
    mp4_files = sorted(
        glob.glob(os.path.join(args.output_dir, "**/*.mp4"), recursive=True),
        key=os.path.getmtime,
        reverse=True
    )

    if not mp4_files:
        print(f"ERROR: No MP4 found in {args.output_dir} after SadTalker run", file=sys.stderr)
        sys.exit(1)

    latest_mp4 = mp4_files[0]
    target = os.path.join(args.output_dir, args.output_name)

    if os.path.abspath(latest_mp4) != os.path.abspath(target):
        shutil.copy2(latest_mp4, target)

    size_mb = os.path.getsize(target) / (1024 * 1024)
    print(f"OK output={target} size={size_mb:.1f}MB")
    return target


def main():
    args = parse_args()

    for path, label in [(args.source_image, "source-image"), (args.driven_audio, "driven-audio")]:
        if not os.path.exists(path):
            print(f"ERROR: {label} not found: {path}", file=sys.stderr)
            sys.exit(1)

    run_inference(args)


if __name__ == "__main__":
    main()
