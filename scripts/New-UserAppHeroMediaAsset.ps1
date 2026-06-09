param(
    [Parameter(Mandatory = $true)][string]$AppSlug,
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$PublishedRoot = "runtime/shared/user_app_published",
    [string]$OutputFileName = "hero.png",
    [string]$Source = "tod-user-app-hero-media-generator-v1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Convert-ToRepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Convert-ToRepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $fullPath = [System.IO.Path]::GetFullPath((Convert-ToRepoPath -PathValue $PathValue))
    $root = [System.IO.Path]::GetFullPath($repoRoot)
    if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside repo root: $PathValue"
    }
    return ($fullPath.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/')
}

function Convert-ToSlug {
    param([Parameter(Mandatory = $true)][string]$Text)
    $slug = ([string]$Text).Trim().ToLowerInvariant() -replace "[^a-z0-9]+", "_"
    $slug = $slug.Trim("_")
    if ([string]::IsNullOrWhiteSpace($slug)) { return "user_app" }
    return $slug
}

$safeSlug = Convert-ToSlug -Text $AppSlug
$appDir = Convert-ToRepoPath -PathValue (Join-Path $PublishedRoot $safeSlug)
$manifestPath = Join-Path $appDir "package.manifest.json"
$previewPath = Join-Path $appDir "preview.html"
$mediaDir = Join-Path $appDir "media"
$assetPath = Join-Path $mediaDir $OutputFileName
$mediaManifestPath = Join-Path $mediaDir "media.manifest.json"

if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Published app manifest not found: $manifestPath"
}
if (-not (Test-Path -Path $previewPath -PathType Leaf)) {
    throw "Published app preview not found: $previewPath"
}

New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null

$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$appName = if ($manifest.PSObject.Properties["app_name"]) { [string]$manifest.app_name } else { $safeSlug.Replace("_", " ") }
$stylePreset = if ($manifest.PSObject.Properties["style_preset"]) { [string]$manifest.style_preset } else { "app_preview" }
$visualPrompt = if ($manifest.PSObject.Properties["visual_theme"] -and $manifest.visual_theme.PSObject.Properties["banner_prompt"]) { [string]$manifest.visual_theme.banner_prompt } else { $Prompt }

$python = @'
import argparse
import hashlib
import math
import os
import random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def color_from_seed(seed, offset):
    rng = random.Random(seed + offset)
    return (rng.randint(24, 230), rng.randint(42, 230), rng.randint(70, 240))

def fit_text(draw, text, max_width, font):
    words = text.split()
    lines = []
    current = ""
    for word in words:
        test = (current + " " + word).strip()
        box = draw.textbbox((0, 0), test, font=font)
        if box[2] <= max_width or not current:
            current = test
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines[:4]

parser = argparse.ArgumentParser()
parser.add_argument("--output", required=True)
parser.add_argument("--app-name", required=True)
parser.add_argument("--prompt", required=True)
parser.add_argument("--style", required=True)
args = parser.parse_args()

seed = int(hashlib.sha256((args.app_name + args.prompt + args.style).encode("utf-8")).hexdigest()[:12], 16)
rng = random.Random(seed)
w, h = 1440, 900
base_a = color_from_seed(seed, 1)
base_b = color_from_seed(seed, 2)
accent = color_from_seed(seed, 3)
img = Image.new("RGB", (w, h), base_a)
px = img.load()
for y in range(h):
    t = y / max(h - 1, 1)
    for x in range(w):
        s = (math.sin((x / w) * math.pi) + 1) / 2
        mix = (t * 0.72) + (s * 0.28)
        noise = rng.randint(-4, 4)
        px[x, y] = tuple(max(0, min(255, int(base_a[i] * (1 - mix) + base_b[i] * mix + noise))) for i in range(3))

draw = ImageDraw.Draw(img, "RGBA")
for _ in range(26):
    cx = rng.randint(-100, w + 100)
    cy = rng.randint(-80, h + 80)
    rw = rng.randint(120, 360)
    rh = rng.randint(80, 280)
    color = (*color_from_seed(seed, rng.randint(10, 500)), rng.randint(28, 78))
    draw.rounded_rectangle((cx, cy, cx + rw, cy + rh), radius=rng.randint(18, 48), fill=color)

panel = (255, 255, 255, 214)
shadow = (0, 0, 0, 64)
draw.rounded_rectangle((112, 116, 1328, 784), radius=44, fill=shadow)
draw.rounded_rectangle((92, 92, 1308, 760), radius=44, fill=panel)

style_key = (args.style + " " + args.prompt).lower()

def line_bar(x, y, width, color=(96, 112, 138, 150)):
    draw.rounded_rectangle((x, y, x + width, y + 12), radius=6, fill=color)

def mini_card(x, y, width, height, color=None):
    fill = color or (248, 250, 252, 236)
    draw.rounded_rectangle((x, y, x + width, y + height), radius=20, fill=fill, outline=(224, 232, 240, 230), width=2)

def draw_dashboard():
    for i in range(3):
        mini_card(150 + i * 220, 150, 180, 118, (250, 252, 255, 238))
        draw.ellipse((175 + i * 220, 178, 217 + i * 220, 220), fill=(*color_from_seed(seed, 30 + i), 230))
        line_bar(235 + i * 220, 180, 70 + i * 18)
        line_bar(235 + i * 220, 212, 98 - i * 12, (*accent, 150))
    for i in range(7):
        x = 158 + i * 58
        bar_h = rng.randint(55, 210)
        draw.rounded_rectangle((x, 560 - bar_h, x + 34, 560), radius=12, fill=(*color_from_seed(seed, 70 + i), 210))
    mini_card(650, 318, 240, 242, (255, 255, 255, 226))
    for i in range(5):
        line_bar(684, 350 + i * 38, rng.randint(88, 165), (*color_from_seed(seed, 92 + i), 150))

def draw_mobile_pair():
    for i, x in enumerate([185, 480]):
        draw.rounded_rectangle((x, 135, x + 210, 590), radius=34, fill=(20, 27, 42, 232))
        draw.rounded_rectangle((x + 16, 156, x + 194, 568), radius=26, fill=(250, 252, 255, 245))
        draw.ellipse((x + 82, 180, x + 128, 226), fill=(*color_from_seed(seed, 110 + i), 220))
        for row in range(5):
            line_bar(x + 42, 260 + row * 48, rng.randint(82, 132), (88, 103, 128, 132))
            draw.rounded_rectangle((x + 42, 280 + row * 48, x + rng.randint(116, 172), 290 + row * 48), radius=5, fill=(*accent, 130))

def draw_calendar():
    mini_card(150, 145, 520, 420, (255, 255, 255, 236))
    for i in range(7):
        draw.rounded_rectangle((180 + i * 64, 188, 218 + i * 64, 226), radius=9, fill=(*color_from_seed(seed, 140 + i), 155))
    for row in range(4):
        for col in range(7):
            x = 180 + col * 64
            y = 260 + row * 62
            fill = (*accent, 210) if (row, col) in [(1, 2), (2, 4)] else (229, 236, 245, 210)
            draw.rounded_rectangle((x, y, x + 42, y + 42), radius=10, fill=fill)
    for i in range(3):
        mini_card(730, 175 + i * 122, 330, 82, (250, 252, 255, 238))
        draw.ellipse((758, 196 + i * 122, 796, 234 + i * 122), fill=(*color_from_seed(seed, 155 + i), 230))
        line_bar(820, 200 + i * 122, 176, (92, 110, 134, 145))
        line_bar(820, 226 + i * 122, 126, (*accent, 160))

def draw_cards_and_table():
    for i in range(4):
        mini_card(150, 150 + i * 98, 420, 72, (252, 252, 253, 232))
        draw.ellipse((176, 168 + i * 98, 212, 204 + i * 98), fill=(*color_from_seed(seed, 190 + i), 220))
        line_bar(236, 174 + i * 98, 230, (88, 104, 128, 142))
        line_bar(236, 198 + i * 98, 150 + i * 16, (*accent, 150))
    mini_card(650, 150, 445, 370, (255, 255, 255, 226))
    for row in range(6):
        y = 185 + row * 48
        line_bar(690, y, 86, (90, 104, 126, 120))
        line_bar(815, y, 116, (*color_from_seed(seed, 220 + row), 130))
        line_bar(966, y, 82, (90, 104, 126, 120))

def draw_call_guard():
    draw.rounded_rectangle((180, 120, 480, 680), radius=46, fill=(16, 24, 48, 235))
    draw.rounded_rectangle((205, 152, 455, 650), radius=34, fill=(8, 14, 30, 245))
    draw.ellipse((295, 195, 365, 265), fill=(*color_from_seed(seed, 260), 230))
    for i, height in enumerate([48, 92, 70, 118, 62]):
        x = 260 + i * 32
        draw.rounded_rectangle((x, 382 - height, x + 18, 382), radius=9, fill=(*color_from_seed(seed, 270 + i), 230))
    for i in range(3):
        mini_card(245, 430 + i * 56, 170, 34, (31, 42, 68, 238))
    mini_card(610, 170, 430, 330, (255, 255, 255, 228))
    for i in range(5):
        line_bar(660, 220 + i * 48, rng.randint(150, 295), (*color_from_seed(seed, 300 + i), 150))
    draw.rounded_rectangle((660, 500, 820, 552), radius=24, fill=(*color_from_seed(seed, 330), 210))

def draw_chef_recipe():
    mini_card(150, 132, 430, 470, (255, 250, 244, 238))
    draw.ellipse((265, 178, 465, 378), fill=(255, 255, 255, 255), outline=(237, 198, 160, 255), width=8)
    draw.ellipse((315, 228, 415, 328), fill=(*color_from_seed(seed, 360), 230))
    for i in range(4):
        line_bar(210, 420 + i * 34, rng.randint(180, 300), (*color_from_seed(seed, 370 + i), 145))
    for i in range(3):
        draw.rounded_rectangle((210 + i * 108, 545, 290 + i * 108, 590), radius=16, fill=(*color_from_seed(seed, 390 + i), 190))
    mini_card(660, 150, 340, 220, (255, 255, 255, 232))
    for i in range(5):
        line_bar(710, 195 + i * 30, rng.randint(120, 230), (*color_from_seed(seed, 410 + i), 150))
    mini_card(700, 425, 250, 160, (236, 253, 245, 228))
    draw.rounded_rectangle((742, 464, 908, 548), radius=18, outline=(*color_from_seed(seed, 430), 210), width=5)

if "call" in style_key or "phone" in style_key or "spam" in style_key or "voice" in style_key:
    draw_call_guard()
elif "chef" in style_key or "recipe" in style_key or "pantry" in style_key or "nutrition" in style_key or "cook" in style_key:
    draw_chef_recipe()
elif "calendar" in style_key or "appointment" in style_key or "schedule" in style_key:
    draw_calendar()
elif "mobile" in style_key or "receipt" in style_key or "meal" in style_key:
    draw_mobile_pair()
elif "chart" in style_key or "pipeline" in style_key or "content" in style_key:
    draw_dashboard()
else:
    draw_cards_and_table()

for i in range(4):
    x = 154 + i * 144
    draw.rounded_rectangle((x, 635, x + 118, 688), radius=18, fill=(*accent, 218))
    draw.rounded_rectangle((x + 30, 654, x + 88, 668), radius=7, fill=(255, 255, 255, 182))

img = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=105, threshold=3))
os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
img.save(args.output, "PNG", optimize=True)
'@

$tmpPy = Join-Path $env:TEMP ("user_app_hero_media_{0}.py" -f ([guid]::NewGuid().ToString("N")))
[System.IO.File]::WriteAllText($tmpPy, $python, [System.Text.UTF8Encoding]::new($false))
try {
    & python $tmpPy --output $assetPath --app-name $appName --prompt $visualPrompt --style $stylePreset
    if ($LASTEXITCODE -ne 0) { throw "Hero media generation failed with exit code $LASTEXITCODE" }
}
finally {
    Remove-Item -Path $tmpPy -Force -ErrorAction SilentlyContinue
}

$assetRel = Convert-ToRepoRelativePath -PathValue $assetPath
$mediaManifestRel = Convert-ToRepoRelativePath -PathValue $mediaManifestPath
$previewRel = Convert-ToRepoRelativePath -PathValue $previewPath
$assetSize = (Get-Item -Path $assetPath).Length

$mediaPayload = [ordered]@{
    artifact_type = "user_app_hero_media_asset_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = $Source
    app_name = $appName
    slug = $safeSlug
    prompt = $Prompt
    visual_prompt = $visualPrompt
    style_preset = $stylePreset
    asset_path = $assetRel
    asset_kind = "hero_png"
    width = 1440
    height = 900
    bytes = $assetSize
    usage = "hero/background image for published Workbench preview"
}

$previewHtml = Get-Content -Path $previewPath -Raw
$relativeAssetForHtml = "media/$OutputFileName"
if ($previewHtml -notmatch [regex]::Escape($relativeAssetForHtml)) {
    $imgHtml = "<img class=`"hero-media-img`" src=`"$relativeAssetForHtml`" alt=`"$([System.Net.WebUtility]::HtmlEncode($appName)) hero image generated by TOD`">"
    $previewHtml = $previewHtml -replace '(<div class="showcase">)', "`$1$imgHtml"
}
if ($previewHtml -notmatch 'hero-media-img') {
    throw "Preview hero image injection failed."
}
if ($previewHtml -notmatch '\.hero-media-img') {
    $previewHtml = $previewHtml -replace '(\.showcase \{[^\}]+\})', "`$1`n    .hero-media-img { width:100%; max-height:210px; object-fit:cover; border-radius:8px; border:1px solid var(--line); margin-bottom:12px; box-shadow:0 18px 38px rgba(15,23,42,.14); }"
}

if (-not $manifest.PSObject.Properties["media_assets"]) {
    $manifest | Add-Member -NotePropertyName media_assets -NotePropertyValue @()
}
$existingAssets = @($manifest.media_assets | Where-Object { [string]$_.asset_kind -ne "hero_png" })
$manifest.media_assets = @($existingAssets + @([pscustomobject]$mediaPayload))
if (-not $manifest.PSObject.Properties["hero_media_status"]) {
    $manifest | Add-Member -NotePropertyName hero_media_status -NotePropertyValue "hero_png_attached"
}
else {
    $manifest.hero_media_status = "hero_png_attached"
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($previewPath, $previewHtml, $utf8NoBom)
[System.IO.File]::WriteAllText($mediaManifestPath, ($mediaPayload | ConvertTo-Json -Depth 20), $utf8NoBom)
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 40), $utf8NoBom)

[pscustomobject]@{
    status = "hero_media_ready"
    app_name = $appName
    slug = $safeSlug
    asset_path = $assetRel
    media_manifest_path = $mediaManifestRel
    preview_path = $previewRel
    bytes = $assetSize
} | ConvertTo-Json -Depth 8
