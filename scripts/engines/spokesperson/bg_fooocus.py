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
import json
import os
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
            print("ERROR: Neither Fooocus nor ComfyUI is reachable. Start one of them first.", file=sys.stderr)
            sys.exit(1)

    if not png_bytes:
        print("ERROR: No image data returned", file=sys.stderr)
        sys.exit(1)

    with open(args.output, "wb") as f:
        f.write(png_bytes)

    size_kb = os.path.getsize(args.output) / 1024
    print(f"OK background={args.output} size={size_kb:.0f}KB")


if __name__ == "__main__":
    main()
