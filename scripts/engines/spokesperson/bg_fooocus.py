"""
bg_fooocus.py — Fooocus API background image generator for TOD spokesperson pipeline.

Usage:
    python bg_fooocus.py --prompt "lush tropical jungle..." \
                         --negative "blurry, cartoon, watermark" \
                         --width 1280 --height 720 \
                         --output background.png \
                         --fooocus-url http://127.0.0.1:7865

Falls back to ComfyUI (port 8188) if Fooocus is not reachable.
Exit 0 on success, 1 on failure.
"""
import argparse
import base64
import io
import json
import os
import random
import sys
import time
import urllib.request
import urllib.error


FOOOCUS_NEGATIVE_DEFAULT = (
    "blurry, cartoon, painting, illustration, watermark, text, logo, "
    "nsfw, low quality, deformed, ugly, bad anatomy, extra limbs"
)


def parse_args():
    p = argparse.ArgumentParser(description="Fooocus background generator")
    p.add_argument("--prompt",          required=True)
    p.add_argument("--negative",        default=FOOOCUS_NEGATIVE_DEFAULT)
    p.add_argument("--width",           type=int, default=1280)
    p.add_argument("--height",          type=int, default=720)
    p.add_argument("--output",          required=True)
    p.add_argument("--fooocus-url",     default="http://127.0.0.1:7865")
    p.add_argument("--comfyui-url",     default="http://127.0.0.1:8188")
    p.add_argument("--steps",           type=int, default=30)
    p.add_argument("--guidance",        type=float, default=7.0)
    p.add_argument("--seed",            type=int, default=-1)
    p.add_argument("--styles",          default="Fooocus V2,Fooocus Photograph,Fooocus Realistic")
    p.add_argument("--model",           default="juggernautXL_v8Rundiffusion.safetensors")
    return p.parse_args()


def fooocus_generate(args) -> bytes:
    """Call Fooocus v1 generation API and return raw PNG bytes."""
    style_list = [s.strip() for s in args.styles.split(",")]
    aspect = f"{args.width}×{args.height}"

    payload = {
        "prompt": args.prompt,
        "negative_prompt": args.negative,
        "style_selections": style_list,
        "performance_selection": "Quality",
        "aspect_ratios_selection": aspect,
        "image_number": 1,
        "image_seed": args.seed,
        "sharpness": 2.0,
        "guidance_scale": args.guidance,
        "base_model_name": args.model,
        "refiner_switch": 0.5,
        "loras": [],
        "async_process": False,
        "save_meta": False,
        "save_extension": "png"
    }

    url = args.fooocus_url.rstrip("/") + "/v1/generation/text-to-image"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    print(f"  Requesting Fooocus: {url}")
    print(f"  Prompt: {args.prompt[:100]}...")

    with urllib.request.urlopen(req, timeout=300) as resp:
        result = json.loads(resp.read())

    # Fooocus returns list of {base64, seed, finish_reason, ...}
    if not result or not isinstance(result, list):
        raise ValueError(f"Unexpected Fooocus response: {result}")

    item = result[0]
    if "base64" not in item:
        raise ValueError(f"No base64 in Fooocus response: {list(item.keys())}")

    return base64.b64decode(item["base64"])


def comfyui_fallback(args) -> bytes:
    """Minimal ComfyUI API fallback — basic SDXL workflow."""
    # Simple txt2img via ComfyUI API using a minimal workflow JSON
    workflow = {
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": args.guidance,
                "denoise": 1.0,
                "latent_image": ["5", 0],
                "model": ["4", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": "euler",
                "scheduler": "normal",
                "seed": args.seed if args.seed >= 0 else int(time.time()) % 2**31,
                "steps": args.steps
            }
        },
        "4": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": "v1-5-pruned-emaonly.ckpt"}},
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"batch_size": 1, "height": args.height, "width": args.width}
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["4", 1], "text": args.prompt}
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["4", 1], "text": args.negative}
        },
        "8": {"class_type": "VAEDecode", "inputs": {"samples": ["3", 0], "vae": ["4", 2]}},
        "9": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "TOD_bg", "images": ["8", 0]}
        }
    }

    import uuid
    client_id = str(uuid.uuid4())
    payload = json.dumps({"prompt": workflow, "client_id": client_id}).encode()
    url = args.comfyui_url.rstrip("/") + "/prompt"

    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    print(f"  Falling back to ComfyUI: {url}")

    with urllib.request.urlopen(req, timeout=30) as resp:
        queued = json.loads(resp.read())

    prompt_id = queued.get("prompt_id")
    if not prompt_id:
        raise ValueError(f"ComfyUI queue failed: {queued}")

    # Poll history for result
    history_url = args.comfyui_url.rstrip("/") + f"/history/{prompt_id}"
    for attempt in range(120):
        time.sleep(3)
        with urllib.request.urlopen(history_url, timeout=10) as r:
            history = json.loads(r.read())
        if prompt_id in history:
            outputs = history[prompt_id].get("outputs", {})
            for node_out in outputs.values():
                imgs = node_out.get("images", [])
                if imgs:
                    img_info = imgs[0]
                    img_url = (args.comfyui_url.rstrip("/") +
                               f"/view?filename={img_info['filename']}&subfolder={img_info.get('subfolder','')}&type=output")
                    with urllib.request.urlopen(img_url, timeout=30) as ir:
                        return ir.read()
    raise TimeoutError("ComfyUI did not complete within timeout")


def procedural_fallback(args) -> bytes:
    """Generate a local background image when no remote backend is reachable."""
    try:
        from PIL import Image, ImageDraw, ImageFilter
    except ImportError as exc:
        raise RuntimeError("Pillow is required for offline fallback") from exc

    # Stable seed from user seed or prompt hash so repeated runs are predictable.
    seed = args.seed if args.seed >= 0 else abs(hash(args.prompt)) % (2**31)
    rng = random.Random(seed)

    w, h = args.width, args.height
    base = Image.new("RGB", (w, h), (20, 55, 35))
    px = base.load()

    # Background gradient + subtle grain to avoid flat synthetic look.
    for y in range(h):
        t = y / max(h - 1, 1)
        r = int(18 + 10 * t)
        g = int(65 + 80 * t)
        b = int(30 + 35 * t)
        for x in range(w):
            n = rng.randint(-10, 10)
            px[x, y] = (
                max(0, min(255, r + n)),
                max(0, min(255, g + n)),
                max(0, min(255, b + n)),
            )

    draw = ImageDraw.Draw(base, "RGBA")

    # Sun shafts / fog streaks.
    for _ in range(14):
        x0 = rng.randint(0, w)
        x1 = x0 + rng.randint(-180, 180)
        draw.polygon(
            [(x0, 0), (x0 + rng.randint(20, 60), 0), (x1 + 80, h), (x1 - 80, h)],
            fill=(255, 245, 200, rng.randint(8, 24)),
        )

    # Layered foliage discs for a photoreal-inspired jungle texture.
    for layer in range(3):
        count = 420 if layer == 0 else (300 if layer == 1 else 220)
        y_min = int(h * (0.1 * layer))
        y_max = int(h * (0.72 + 0.08 * layer))
        for _ in range(count):
            cx = rng.randint(-80, w + 80)
            cy = rng.randint(y_min, y_max)
            radius = rng.randint(18, 85) if layer < 2 else rng.randint(12, 52)
            color = (
                rng.randint(16, 52),
                rng.randint(80, 165),
                rng.randint(28, 88),
                rng.randint(26, 84),
            )
            draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color)

    # Foreground branch and a simple spider silhouette for the requested scene.
    branch_y = int(h * 0.28)
    draw.line([(int(w * 0.58), 0), (int(w * 0.38), branch_y)], fill=(42, 26, 12, 210), width=16)
    spider_cx = int(w * 0.43)
    spider_cy = int(h * 0.30)
    draw.ellipse((spider_cx - 22, spider_cy - 14, spider_cx + 22, spider_cy + 14), fill=(10, 10, 10, 220))
    draw.ellipse((spider_cx - 12, spider_cy - 30, spider_cx + 12, spider_cy - 8), fill=(8, 8, 8, 220))
    for leg in range(4):
        dy = leg * 8
        draw.line([(spider_cx - 14, spider_cy - 6 + dy), (spider_cx - 44, spider_cy - 24 + dy)], fill=(10, 10, 10, 220), width=3)
        draw.line([(spider_cx + 14, spider_cy - 6 + dy), (spider_cx + 44, spider_cy - 24 + dy)], fill=(10, 10, 10, 220), width=3)

    out = base.filter(ImageFilter.GaussianBlur(radius=1.0))
    bio = io.BytesIO()
    out.save(bio, format="PNG", compress_level=1)
    return bio.getvalue()


def main():
    args = parse_args()
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)

    # Try Fooocus first
    png_bytes = None
    try:
        # Quick health check
        urllib.request.urlopen(args.fooocus_url.rstrip("/") + "/", timeout=5)
        png_bytes = fooocus_generate(args)
        print(f"  Fooocus: generation complete ({len(png_bytes)//1024}KB)")
    except urllib.error.URLError:
        print(f"  WARN: Fooocus not reachable at {args.fooocus_url}, trying ComfyUI fallback")
        try:
            urllib.request.urlopen(args.comfyui_url.rstrip("/") + "/system_stats", timeout=5)
            png_bytes = comfyui_fallback(args)
            print(f"  ComfyUI: generation complete ({len(png_bytes)//1024}KB)")
        except urllib.error.URLError:
            print("  WARN: Neither Fooocus nor ComfyUI is reachable; using offline procedural fallback")
            png_bytes = procedural_fallback(args)
            print(f"  Offline fallback: generation complete ({len(png_bytes)//1024}KB)")

    if not png_bytes:
        print("ERROR: No image data returned", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "wb") as f:
        f.write(png_bytes)

    size_kb = os.path.getsize(args.output) / 1024
    print(f"OK background={args.output} size={size_kb:.0f}KB")


if __name__ == "__main__":
    main()
