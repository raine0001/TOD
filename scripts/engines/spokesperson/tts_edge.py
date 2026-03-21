"""
tts_edge.py — edge-tts wrapper for TOD spokesperson pipeline.

Usage:
    python tts_edge.py --text "Hello world" --voice en-US-GuyNeural \
                       --rate +0% --output audio.wav

Output: WAV file at --output path.
Exit 0 on success, 1 on failure (error to stderr).
"""
import argparse
import asyncio
import sys
import os
import tempfile


def parse_args():
    p = argparse.ArgumentParser(description="edge-tts TTS generator")
    p.add_argument("--text",    required=True,  help="Script text to speak")
    p.add_argument("--voice",   default="en-US-GuyNeural", help="edge-tts voice name")
    p.add_argument("--rate",    default="+0%",  help="Speech rate delta e.g. +10% -5%")
    p.add_argument("--pitch",   default="+0Hz", help="Pitch delta e.g. +5Hz -3Hz")
    p.add_argument("--volume",  default="+0%",  help="Volume delta e.g. +0%")
    p.add_argument("--output",  required=True,  help="Output WAV path")
    return p.parse_args()


async def generate(text: str, voice: str, rate: str, pitch: str, volume: str, out_path: str):
    try:
        import edge_tts
    except ImportError:
        print("ERROR: edge-tts not installed. Run: pip install edge-tts", file=sys.stderr)
        sys.exit(1)

    # edge-tts outputs MP3 — convert to WAV via pydub/soundfile if needed
    # Most downstream tools (SadTalker) accept both; we output MP3 renamed .wav or
    # convert inline. SadTalker reads wav via librosa which handles mp3 too.
    mp3_path = out_path.rsplit(".", 1)[0] + ".mp3"

    communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch, volume=volume)
    await communicate.save(mp3_path)

    # Convert MP3 → WAV (16-bit, 16kHz mono — optimal for SadTalker)
    converted = False
    try:
        import subprocess
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", mp3_path,
             "-ar", "16000", "-ac", "1", "-sample_fmt", "s16", out_path],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            os.remove(mp3_path)
            converted = True
        else:
            print(f"WARN: ffmpeg conversion failed: {result.stderr}")
    except FileNotFoundError:
        print("WARN: ffmpeg not in PATH, keeping MP3 output")

    if not converted:
        # Rename mp3 as wav — SadTalker/librosa will handle it
        if os.path.exists(mp3_path) and mp3_path != out_path:
            if os.path.exists(out_path):
                os.remove(out_path)
            os.replace(mp3_path, out_path)

    if not os.path.exists(out_path):
        print(f"ERROR: output file not created: {out_path}", file=sys.stderr)
        sys.exit(1)

    size_kb = os.path.getsize(out_path) / 1024
    print(f"OK voice={voice} size={size_kb:.1f}KB output={out_path}")


def main():
    args = parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    asyncio.run(generate(args.text, args.voice, args.rate, args.pitch, args.volume, args.output))


if __name__ == "__main__":
    main()
