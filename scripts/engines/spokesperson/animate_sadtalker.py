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


def collect_ffmpeg_dirs() -> list[str]:
    """Collect likely ffmpeg/ffprobe directories on Windows and current PATH."""
    dirs: list[str] = []

    def add_dir(path_value: str):
        if path_value and os.path.isdir(path_value) and path_value not in dirs:
            dirs.append(path_value)

    # Current PATH entries first.
    for entry in os.environ.get("PATH", "").split(os.pathsep):
        add_dir(entry)

    # Common locations.
    add_dir(r"C:\Program Files\FFmpeg\bin")

    # WinGet package location used on this machine.
    winget_glob = glob.glob(
        os.path.expandvars(
            r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-*\bin"
        )
    )
    for candidate in winget_glob:
        add_dir(candidate)

    return dirs


def find_executable(exe_name: str, search_dirs: list[str]) -> str | None:
    for directory in search_dirs:
        candidate = os.path.join(directory, exe_name)
        if os.path.isfile(candidate):
            return candidate
    return shutil.which(exe_name)


def with_ffmpeg_env(base_env: dict[str, str]) -> dict[str, str]:
    """Return env with discovered ffmpeg directories prepended to PATH."""
    env = dict(base_env)
    ffmpeg_dirs = collect_ffmpeg_dirs()
    if ffmpeg_dirs:
        existing_path = env.get("PATH", "")
        env["PATH"] = os.pathsep.join(ffmpeg_dirs + [existing_path]) if existing_path else os.pathsep.join(ffmpeg_dirs)
    return env


def mux_with_ffmpeg(video_path: str, audio_path: str, output_path: str, env: dict[str, str]) -> bool:
    ffmpeg_exe = find_executable("ffmpeg.exe", collect_ffmpeg_dirs())
    if not ffmpeg_exe:
        return False

    cmd = [
        ffmpeg_exe,
        "-y",
        "-i", video_path,
        "-i", audio_path,
        "-c:v", "copy",
        "-c:a", "aac",
        "-shortest",
        output_path,
    ]
    print(f"  Recovery mux: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=False, text=True, env=env)
    return result.returncode == 0 and os.path.exists(output_path)


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

    run_env = with_ffmpeg_env(os.environ)
    result = subprocess.run(
        cmd,
        cwd=args.sadtalker_path,
        capture_output=False,   # Let SadTalker print progress to console
        text=True,
        env=run_env,
    )

    if result.returncode != 0:
        # Recovery path: SadTalker sometimes fails only during final audio mux when ffmpeg is missing,
        # while rendered silent video already exists in result_dir.
        recovery_candidates = sorted(
            glob.glob(os.path.join(args.output_dir, "**", "temp_*.mp4"), recursive=True),
            key=os.path.getmtime,
            reverse=True,
        )
        target = os.path.join(args.output_dir, args.output_name)
        if recovery_candidates and os.path.exists(args.driven_audio):
            recovered = mux_with_ffmpeg(
                video_path=recovery_candidates[0],
                audio_path=os.path.abspath(args.driven_audio),
                output_path=target,
                env=run_env,
            )
            if recovered:
                size_mb = os.path.getsize(target) / (1024 * 1024)
                print(f"WARN: SadTalker exited with code {result.returncode}, but recovered output via ffmpeg mux")
                print(f"OK output={target} size={size_mb:.1f}MB")
                return target

        print(f"ERROR: SadTalker exited with code {result.returncode}", file=sys.stderr)
        sys.exit(result.returncode)

    # SadTalker saves both temp and final mp4 files; prefer non-temp outputs.
    all_mp4_files = sorted(
        glob.glob(os.path.join(args.output_dir, "**/*.mp4"), recursive=True),
        key=os.path.getmtime,
        reverse=True
    )

    mp4_files = [
        f for f in all_mp4_files
        if not os.path.basename(f).lower().startswith("temp_")
    ]

    if not mp4_files:
        mp4_files = all_mp4_files

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
