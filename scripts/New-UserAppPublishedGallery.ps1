param(
    [string]$PublishedRoot = "runtime/shared/user_app_published",
    [string]$OutputManifestPath = "runtime/shared/user_app_published/gallery.manifest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Convert-ToRepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
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

function Convert-ToRelativeWebPath {
    param(
        [Parameter(Mandatory = $true)][string]$FromDirectory,
        [Parameter(Mandatory = $true)][string]$ToPath
    )
    $fromUri = [System.Uri]::new(([System.IO.Path]::GetFullPath($FromDirectory).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar))
    $toUri = [System.Uri]::new([System.IO.Path]::GetFullPath((Convert-ToRepoPath -PathValue $ToPath)))
    return [System.Uri]::UnescapeDataString($fromUri.MakeRelativeUri($toUri).ToString())
}

function Html {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

$publishedRootAbs = Convert-ToRepoPath -PathValue $PublishedRoot
if (-not (Test-Path -Path $publishedRootAbs -PathType Container)) {
    throw "Published app root not found: $PublishedRoot"
}

$manifestFiles = @(Get-ChildItem -Path $publishedRootAbs -Recurse -Filter "package.manifest.json" | Sort-Object FullName)
$outputManifestAbs = Convert-ToRepoPath -PathValue $OutputManifestPath
$outputDir = Split-Path -Parent $outputManifestAbs
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$galleryPath = Join-Path $outputDir "gallery.html"

$apps = @()
foreach ($file in $manifestFiles) {
    $manifest = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
    $previewPath = if ($manifest.PSObject.Properties["preview_path"]) { [string]$manifest.preview_path } else { "" }
    $apps += [ordered]@{
        app_name = [string]$manifest.app_name
        slug = [string]$manifest.slug
        status = [string]$manifest.status
        style_preset = [string]$manifest.style_preset
        preview_path = $previewPath
        gallery_href = Convert-ToRelativeWebPath -FromDirectory $outputDir -ToPath $previewPath
        manifest_path = Convert-ToRepoRelativePath -PathValue $file.FullName
        production_deploy = if ($manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.production_deploy } else { "" }
        interactive_workflow_preview = if ($manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.interactive_workflow_preview } else { "" }
        last_minute_change_visible = if ($manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.last_minute_change_visible } else { "" }
        mim_help = if ($manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.mim_help } else { "" }
        presentation_walkthrough = if ($manifest.PSObject.Properties["gates"]) { [string]$manifest.gates.presentation_walkthrough } else { "" }
    }
}

$cards = ($apps | ForEach-Object {
        $preview = Html $_.gallery_href
        @"
        <article class="card">
          <small>$((Html $_.style_preset))</small>
          <h2>$((Html $_.app_name))</h2>
          <p>Status: <strong>$((Html $_.status))</strong></p>
          <p>Deploy: $((Html $_.production_deploy))</p>
          <div class="badges">
            <span>interactive: $((Html $_.interactive_workflow_preview))</span>
            <span>MIM help: $((Html $_.mim_help))</span>
            <span>change: $((Html $_.last_minute_change_visible))</span>
          </div>
          <a class="button" href="$preview">Open preview</a>
        </article>
"@
    }) -join "`n"

$galleryHtml = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MIM/TOD Sample App Training Gallery</title>
  <style>
    :root { color-scheme: dark; --bg:#071019; --panel:#101b29; --ink:#eef7ff; --muted:#a9c1d9; --line:#294056; --accent:#65e4d3; }
    * { box-sizing:border-box; }
    body { margin:0; background:var(--bg); color:var(--ink); font-family:Inter, Segoe UI, Arial, sans-serif; }
    header { padding:28px; border-bottom:1px solid var(--line); background:#0d1825; }
    main { max-width:1180px; margin:0 auto; padding:20px; }
    h1 { margin:0; font-size:clamp(30px,4vw,52px); }
    p { color:var(--muted); }
    .grid { display:grid; gap:14px; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); }
    .card { border:1px solid var(--line); background:var(--panel); border-radius:8px; padding:16px; }
    small { color:var(--accent); text-transform:uppercase; font-weight:800; }
    .badges { display:flex; flex-wrap:wrap; gap:6px; margin:10px 0; }
    .badges span { border:1px solid var(--line); border-radius:999px; padding:5px 8px; color:var(--muted); }
    .button { display:inline-block; margin-top:8px; padding:10px 12px; border-radius:7px; background:var(--accent); color:#031018; font-weight:800; text-decoration:none; }
  </style>
</head>
<body>
  <header>
    <small>MIM/TOD Deep Training Event</small>
    <h1>Sample App Training Gallery</h1>
    <p>TOD-generated app previews with style, presentation, MIM Help, interactive workflow simulation, completion summaries, and honest deploy gates.</p>
  </header>
  <main>
    <section class="grid">
      $cards
    </section>
  </main>
</body>
</html>
"@

$payload = [ordered]@{
    artifact_type = "user_app_published_gallery_manifest_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    app_count = @($apps).Count
    gallery_path = Convert-ToRepoRelativePath -PathValue $galleryPath
    manifest_path = Convert-ToRepoRelativePath -PathValue $outputManifestAbs
    deploy_target = "local_static_preview"
    production_deploy = "not_selected"
    apps = @($apps)
    next_action = "Select a real hosted preview target or use this gallery for MIM/TOD app feedback training."
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($galleryPath, $galleryHtml, $utf8NoBom)
[System.IO.File]::WriteAllText($outputManifestAbs, ($payload | ConvertTo-Json -Depth 30), $utf8NoBom)

$payload | ConvertTo-Json -Depth 12
