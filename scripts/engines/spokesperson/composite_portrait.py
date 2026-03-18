"""
composite_portrait.py — Composite avatar (no-bg PNG) onto background scene.

Produces a single composited portrait JPEG that serves as SadTalker source.
Pipeline:
  1. Load background (resize to target frame, e.g. 1280×720)
  2. Load avatar PNG with alpha
  3. Scale avatar to fit left/right panel while preserving aspect ratio
  4. Apply ground shadow under avatar for realism (+depth)
  5. Apply subtle color-temperature matching between avatar and background
  6. Paste composited result
  7. Optional: add scene vignette

Usage:
    python composite_portrait.py \
        --avatar avatar_nobg.png \
        --background jungle.png \
        --output composited.jpg \
        --avatar-height 680 \
        --x-offset 80 \
        --color-match \
        --shadow \
        --vignette
"""
import argparse
import os
import sys


def parse_args():
    p = argparse.ArgumentParser(description="Avatar + background compositor")
    p.add_argument("--avatar",          required=True)
    p.add_argument("--background",      required=True)
    p.add_argument("--output",          required=True)
    p.add_argument("--frame-width",     type=int, default=1280)
    p.add_argument("--frame-height",    type=int, default=720)
    p.add_argument("--avatar-height",   type=int, default=680,
                   help="Avatar height in pixels (width scales proportionally)")
    p.add_argument("--x-offset",        type=int, default=80,
                   help="X position of avatar left edge in the frame")
    p.add_argument("--y-offset",        type=int, default=0,
                   help="Y offset from bottom to place avatar feet (0 = flush bottom)")
    p.add_argument("--color-match",     action="store_true",
                   help="Match avatar color temperature to background")
    p.add_argument("--shadow",          action="store_true",
                   help="Add ground shadow beneath avatar")
    p.add_argument("--vignette",        action="store_true",
                   help="Add cinematic vignette to final frame")
    p.add_argument("--jpeg-quality",    type=int, default=95)
    return p.parse_args()


def match_color_temperature(avatar_rgba, background_rgb):
    """Shift avatar white-balance toward background dominant light color."""
    import numpy as np
    bg_arr = np.array(background_rgb.convert("RGB"), dtype=np.float32)
    av_rgb = np.array(avatar_rgba.convert("RGB"), dtype=np.float32)

    # Background mean color (sample center region, ignore corners)
    h, w = bg_arr.shape[:2]
    center = bg_arr[h//4:3*h//4, w//4:3*w//4]
    bg_mean = center.mean(axis=(0, 1))  # [R, G, B]

    # Avatar mean color
    av_mean = av_rgb.mean(axis=(0, 1))

    # Scale ratio (conservative — only 30% of full adjustment)
    ratio = (bg_mean / (av_mean + 1e-6) - 1.0) * 0.30 + 1.0
    ratio = ratio.clip(0.75, 1.33)

    # Apply to RGBA, preserve alpha
    from PIL import Image
    import numpy as np
    av_arr = np.array(avatar_rgba, dtype=np.float32)
    av_arr[:, :, :3] *= ratio
    av_arr = av_arr.clip(0, 255).astype(np.uint8)
    return Image.fromarray(av_arr, "RGBA")


def add_ground_shadow(canvas, x, y, avatar_w, avatar_h):
    """Draw an elliptical shadow under avatar feet."""
    from PIL import Image, ImageDraw, ImageFilter
    shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow_layer)
    shadow_w = int(avatar_w * 0.85)
    shadow_h = int(avatar_h * 0.045)
    cx = x + avatar_w // 2
    cy = y + avatar_h
    ellipse = [cx - shadow_w//2, cy - shadow_h, cx + shadow_w//2, cy + shadow_h]
    draw.ellipse(ellipse, fill=(0, 0, 0, 90))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=12))
    canvas.alpha_composite(shadow_layer)
    return canvas


def add_vignette(canvas):
    """Add a soft radial vignette (darkens corners)."""
    import numpy as np
    from PIL import Image
    w, h = canvas.size
    arr = np.array(canvas, dtype=np.float32)
    cx, cy = w / 2, h / 2
    Y, X = np.ogrid[:h, :w]
    dist = np.sqrt(((X - cx) / cx) ** 2 + ((Y - cy) / cy) ** 2)
    vignette = 1.0 - np.clip(dist * 0.55, 0, 0.45)
    vignette = vignette[:, :, np.newaxis]
    arr[:, :, :3] = (arr[:, :, :3] * vignette).clip(0, 255)
    return Image.fromarray(arr.astype(np.uint8), canvas.mode)


def main():
    args = parse_args()

    for path in [args.avatar, args.background]:
        if not os.path.exists(path):
            print(f"ERROR: File not found: {path}", file=sys.stderr)
            sys.exit(1)

    try:
        from PIL import Image, ImageFilter
    except ImportError:
        print("ERROR: Pillow not installed. Run: pip install Pillow", file=sys.stderr)
        sys.exit(1)

    print(f"  Loading background: {args.background}")
    bg = Image.open(args.background).convert("RGB")
    bg = bg.resize((args.frame_width, args.frame_height), Image.LANCZOS)

    print(f"  Loading avatar: {args.avatar}")
    av = Image.open(args.avatar).convert("RGBA")

    # Scale avatar to desired height, preserving aspect ratio
    av_orig_w, av_orig_h = av.size
    scale = args.avatar_height / av_orig_h
    av_w = int(av_orig_w * scale)
    av_h = args.avatar_height
    av = av.resize((av_w, av_h), Image.LANCZOS)

    # Color temperature matching
    if args.color_match:
        print("  Applying color temperature matching...")
        av = match_color_temperature(av, bg)

    # Build RGBA canvas from background
    canvas = bg.convert("RGBA")

    # Position: x_offset from left, bottom-flush minus y_offset
    x_pos = args.x_offset
    y_pos = args.frame_height - av_h - args.y_offset

    # Ground shadow (drawn before avatar paste)
    if args.shadow:
        canvas = add_ground_shadow(canvas, x_pos, y_pos, av_w, av_h)

    # Paste avatar with alpha
    canvas.alpha_composite(av, dest=(x_pos, y_pos))

    # Vignette
    if args.vignette:
        canvas = add_vignette(canvas)

    # Save
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    final = canvas.convert("RGB")
    final.save(args.output, "JPEG", quality=args.jpeg_quality, subsampling=0)

    size_kb = os.path.getsize(args.output) / 1024
    print(f"OK composite={args.output} size={size_kb:.0f}KB dims={args.frame_width}x{args.frame_height}")


if __name__ == "__main__":
    main()
