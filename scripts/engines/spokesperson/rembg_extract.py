"""
rembg_extract.py — GPU-accelerated background removal for avatar isolation.

Removes the background from a portrait photo using the u2net model (rembg).
Outputs a PNG with alpha channel (transparency where background was).

Usage:
    python rembg_extract.py --input portrait.jpg --output avatar_nobg.png \
                            --model u2net --post-process

Exit 0 on success, 1 on failure.
"""
import argparse
import os
import sys


def parse_args():
    p = argparse.ArgumentParser(description="Background removal via rembg")
    p.add_argument("--input",           required=True, help="Input portrait image (JPG/PNG)")
    p.add_argument("--output",          required=True, help="Output PNG with alpha")
    p.add_argument("--model",           default="u2net", choices=["u2net", "u2net_human_seg", "isnet-general-use", "birefnet-general"],
                   help="rembg model. u2net_human_seg or birefnet-general for best portrait results")
    p.add_argument("--post-process",    action="store_true", help="Apply alpha matting post-process for cleaner edges")
    p.add_argument("--foreground-threshold", type=int, default=240, help="Alpha matting foreground threshold")
    p.add_argument("--background-threshold", type=int, default=10,  help="Alpha matting background threshold")
    p.add_argument("--erode-size",       type=int, default=10,  help="Alpha matting erode size")
    return p.parse_args()


def main():
    args = parse_args()

    if not os.path.exists(args.input):
        print(f"ERROR: Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    try:
        from rembg import remove, new_session
    except ImportError:
        print("ERROR: rembg not installed. Run: pip install rembg[gpu] onnxruntime-gpu", file=sys.stderr)
        sys.exit(1)

    try:
        from PIL import Image
    except ImportError:
        print("ERROR: Pillow not installed. Run: pip install Pillow", file=sys.stderr)
        sys.exit(1)

    print(f"  Loading model: {args.model}")
    # birefnet-general gives best portrait edge quality if available
    model_name = args.model
    try:
        session = new_session(model_name)
    except Exception as e:
        print(f"  WARN: Could not load model '{model_name}': {e}. Falling back to u2net.", file=sys.stderr)
        session = new_session("u2net")

    print(f"  Processing: {args.input}")
    with open(args.input, "rb") as f:
        img_data = f.read()

    remove_kwargs = {
        "session": session,
        "alpha_matting": args.post_process,
    }
    if args.post_process:
        remove_kwargs["alpha_matting_foreground_threshold"] = args.foreground_threshold
        remove_kwargs["alpha_matting_background_threshold"] = args.background_threshold
        remove_kwargs["alpha_matting_erode_size"] = args.erode_size

    result_bytes = remove(img_data, **remove_kwargs)

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "wb") as f:
        f.write(result_bytes)

    # Verify result
    img = Image.open(args.output)
    has_alpha = img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info)
    size_kb = os.path.getsize(args.output) / 1024

    print(f"  Mode: {img.mode}  Size: {img.size}  Alpha: {has_alpha}")
    print(f"OK output={args.output} size={size_kb:.0f}KB alpha={has_alpha}")

    if not has_alpha:
        print("WARN: Output has no alpha channel — background removal may have failed", file=sys.stderr)


if __name__ == "__main__":
    main()
