param(
    [Parameter(Mandatory = $true)][string]$PrototypePath,
    [Parameter(Mandatory = $true)][string]$OutputManifestPath,
    [AllowEmptyString()][string]$Source
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = "tod-local-app-publish-preview-factory"
}

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

function Convert-ToSlug {
    param([Parameter(Mandatory = $true)][string]$Text)

    $slug = ([string]$Text).Trim().ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "_"
    $slug = $slug.Trim("_")
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "user_app"
    }
    return $slug
}

function ConvertTo-HtmlText {
    param($Value)
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

$resolvedPrototypePath = Convert-ToRepoPath -PathValue $PrototypePath
$resolvedManifestPath = Convert-ToRepoPath -PathValue $OutputManifestPath

if (-not (Test-Path -Path $resolvedPrototypePath -PathType Leaf)) {
    throw "Prototype file was not found: $PrototypePath"
}

$artifact = Get-Content -Path $resolvedPrototypePath -Raw | ConvertFrom-Json
$appName = [string]$artifact.app_name
if ([string]::IsNullOrWhiteSpace($appName)) {
    $appName = "User App"
}
$slug = Convert-ToSlug -Text $appName
$outputDir = Split-Path -Parent $resolvedManifestPath
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$now = (Get-Date).ToUniversalTime().ToString("o")
$screens = @($artifact.screens | ForEach-Object {
        [ordered]@{
            key = [string]$_.key
            title = [string]$_.title
            purpose = [string]$_.purpose
            features = @($_.features | ForEach-Object { [string]$_ })
        }
    })
$workflows = @($artifact.workflows | ForEach-Object { [string]$_ })
$sampleRecords = @($artifact.sample_records)
$acceptance = @($artifact.acceptance_checklist | ForEach-Object { [string]$_ })
$previewUi = if ($artifact.preview_ui) { $artifact.preview_ui } else { [pscustomobject]@{} }
$style = if ($previewUi.PSObject.Properties["style_preset"]) { [string]$previewUi.style_preset } else { "clean_saas" }
$background = if ($previewUi.PSObject.Properties["background"]) { [string]$previewUi.background } else { "#071019" }
$panel = if ($previewUi.PSObject.Properties["panel"]) { [string]$previewUi.panel } else { "#101b29" }
$ink = if ($previewUi.PSObject.Properties["ink"]) { [string]$previewUi.ink } else { "#eef7ff" }
$muted = if ($previewUi.PSObject.Properties["muted"]) { [string]$previewUi.muted } else { "#a9c1d9" }
$accent = if ($previewUi.PSObject.Properties["accent"]) { [string]$previewUi.accent } else { "#65e4d3" }
$accent2 = if ($previewUi.PSObject.Properties["accent_2"]) { [string]$previewUi.accent_2 } else { "#9ad0ff" }
$fontStack = if ($previewUi.PSObject.Properties["font_stack"]) { [string]$previewUi.font_stack } else { "Inter, Segoe UI, Arial, sans-serif" }
$bannerPrompt = if ($previewUi.PSObject.Properties["banner_prompt"]) { [string]$previewUi.banner_prompt } else { "clean app dashboard with product cards and workflow highlights" }

function Get-AppDesignSpec {
    param(
        [Parameter(Mandatory = $true)][string]$Slug,
        [Parameter(Mandatory = $true)][string]$Name
    )

    switch -Regex ($Slug) {
        "incoming|call|screen" {
            return [ordered]@{
                layout = "design-call-guard"
                form = "mobile"
                hero = "<div class='call-guard-visual'><div class='call-phone'><div class='caller-dot'></div><div class='call-wave'><i></i><i></i><i></i><i></i></div><div class='call-card danger'></div><div class='call-card'></div><div class='call-actions'><span></span><span></span></div></div><div class='summary-card'><b></b><span></span><span></span><span class='hot'></span></div></div>"
                focus = "mobile call screening, voice response rules, recorded summaries, and user notification cards"
            }
        }
        "chef|recipe" {
            return [ordered]@{
                layout = "design-chef"
                form = "mobile_desktop"
                hero = "<div class='chef-visual'><div class='recipe-card'><div class='plate'></div><span></span><span></span><div class='nutrition-row'><i></i><i></i><i></i></div></div><div class='pantry-card'><b></b><span></span><span></span><span></span></div><div class='camera-card'></div></div>"
                focus = "personal recipe recommendations, pantry-aware options, nutrition facts, feedback, and dish recreation"
            }
        }
        "meal" {
            return [ordered]@{
                layout = "design-receipt"
                form = "desktop"
                hero = "<div class='receipt-visual'><div class='receipt-paper'><small>BUSINESS LUNCH</small><strong>`$84.26</strong><span>Missing: attendees</span><span>Ready: itemized receipt</span></div><div class='audit-stack'><b>Audit checklist</b><span class='ok'>Receipt</span><span class='warn'>Purpose</span><span class='warn'>Who</span></div></div>"
                focus = "receipt capture, substantiation checklist, and audit-ready meal records"
            }
        }
        "document" {
            return [ordered]@{
                layout = "design-portal"
                form = "desktop"
                hero = "<div class='portal-visual'><div class='folder-card active'>Client Packet</div><div class='folder-card'>W-9</div><div class='folder-card'>Agreement</div><div class='upload-drop'>Drop files here</div></div>"
                focus = "document packet collection with missing-item tracking"
            }
        }
        "content" {
            return [ordered]@{
                layout = "design-editorial"
                form = "desktop"
                hero = "<div class='calendar-visual'><span>Mon</span><span class='hot'>Idea</span><span>Wed</span><span class='draft'>Draft</span><span>Fri</span><span class='live'>Live</span></div>"
                focus = "editorial calendar cards, channel color, and publishing rhythm"
            }
        }
        "crm" {
            return [ordered]@{
                layout = "design-crm"
                form = "desktop"
                hero = "<div class='crm-visual'><aside>Companies<br>Contacts<br>Deals</aside><main><b>Today</b><div>Call Morgan Agency</div><div>Email Carter Benefits</div><div class='metric'>Pipeline `$42.8k</div></main></div>"
                focus = "relationship dashboard with activity, reminders, and company/contact context"
            }
        }
        "task" {
            return [ordered]@{
                layout = "design-kanban"
                form = "desktop"
                hero = "<div class='kanban-visual'><div><b>To do</b><span>Prepare quote</span></div><div><b>Doing</b><span>Review file</span></div><div><b>Done</b><span>Send recap</span></div></div>"
                focus = "team board lanes with blockers, owners, and due dates"
            }
        }
        "pipeline" {
            return [ordered]@{
                layout = "design-sales"
                form = "desktop"
                hero = "<div class='pipeline-visual'><div style='height:36%'></div><div style='height:62%'></div><div style='height:84%'></div><div style='height:52%'></div><div style='height:72%'></div></div>"
                focus = "sales pipeline movement, value cards, and next-action pressure"
            }
        }
        "ticket" {
            return [ordered]@{
                layout = "design-support"
                form = "desktop"
                hero = "<div class='support-visual'><div class='ticket urgent'>Printer down</div><div class='ticket'>Login issue</div><div class='ticket done'>Closed refund</div></div>"
                focus = "support queue triage with priority and resolution notes"
            }
        }
        "receipt" {
            return [ordered]@{
                layout = "design-expense"
                form = "mobile"
                hero = "<div class='phone-visual'><div class='phone-bar'></div><h3>Scan Receipt</h3><div class='scan-box'></div><div class='phone-pill'>Categorize</div><div class='phone-pill alt'>Export</div></div>"
                focus = "mobile-first receipt scan, categorization, and monthly totals"
            }
        }
        "inventory" {
            return [ordered]@{
                layout = "design-inventory"
                form = "desktop"
                hero = "<div class='inventory-visual'><div>SKU</div><div>Stock</div><div>Reorder</div><span></span><span class='low'></span><span></span><span></span><span></span><span class='low'></span></div>"
                focus = "compact inventory grid with reorder thresholds and low-stock warnings"
            }
        }
        "appointment" {
            return [ordered]@{
                layout = "design-mobile-calendar"
                form = "mobile"
                hero = "<div class='phone-visual calendar-phone'><div class='phone-bar'></div><h3>June 2026</h3><div class='date-grid'><span>10</span><span class='selected'>11</span><span>12</span><span>13</span></div><div class='phone-pill'>Google Sync</div><div class='phone-pill alt'>Send Invite</div></div>"
                focus = "mobile calendar scheduling with invites, reminders, and sync"
            }
        }
        default {
            return [ordered]@{
                layout = "design-saas"
                form = "desktop"
                hero = "<div class='saas-visual'><div></div><div></div><div></div></div>"
                focus = "clean SaaS dashboard with primary workflow and status cards"
            }
        }
    }
}

$design = Get-AppDesignSpec -Slug $slug -Name $appName
$layoutClass = [string]$design.layout
$deviceClass = [string]$design.form
$heroVisual = [string]$design.hero
$designFocus = [string]$design.focus

$workflowHtml = ($workflows | ForEach-Object { "<span class='pill'>" + (ConvertTo-HtmlText $_) + "</span>" }) -join "`n"
if ([string]::IsNullOrWhiteSpace($workflowHtml)) {
    $workflowHtml = "<span class='pill'>Primary workflow pending</span>"
}
$workflowButtons = ($workflows | Select-Object -First 6 | ForEach-Object {
        "<button class='button workflow-action' type='button' data-action='" + (ConvertTo-HtmlText $_) + "'>" + (ConvertTo-HtmlText $_) + "</button>"
    }) -join "`n"
if ([string]::IsNullOrWhiteSpace($workflowButtons)) {
    $workflowButtons = "<button class='button workflow-action' type='button' data-action='create sample record'>Create sample record</button>"
}

$screenHtml = ($screens | ForEach-Object {
        $featureHtml = ($_.features | ForEach-Object { "<li>" + (ConvertTo-HtmlText $_) + "</li>" }) -join ""
        "<article class='card'><small>" + (ConvertTo-HtmlText $_.key) + "</small><h2>" + (ConvertTo-HtmlText $_.title) + "</h2><p>" + (ConvertTo-HtmlText $_.purpose) + "</p><ul>$featureHtml</ul></article>"
    }) -join "`n"

$recordRows = ($sampleRecords | ForEach-Object {
        if ($_ -isnot [psobject]) { return "" }
        $name = if ($_.PSObject.Properties["contact"]) { [string]$_.contact } elseif ($_.PSObject.Properties["name"]) { [string]$_.name } else { "Sample Record" }
        $status = if ($_.PSObject.Properties["status"]) { [string]$_.status } else { "active" }
        $note = if ($_.PSObject.Properties["latest_note"]) { [string]$_.latest_note } elseif ($_.PSObject.Properties["note"]) { [string]$_.note } else { "" }
        "<tr><td>" + (ConvertTo-HtmlText $name) + "</td><td>" + (ConvertTo-HtmlText $status) + "</td><td>" + (ConvertTo-HtmlText $note) + "</td></tr>"
    }) -join "`n"
if ([string]::IsNullOrWhiteSpace($recordRows)) {
    $recordRows = "<tr><td colspan='3'>No sample records published.</td></tr>"
}

$helpQuestions = @()
if ($artifact.mim_help -and $artifact.mim_help.PSObject.Properties["sample_questions"]) {
    $helpQuestions = @($artifact.mim_help.sample_questions | ForEach-Object { [string]$_ })
}
if (@($helpQuestions).Count -eq 0) {
    $helpQuestions = @("How do I use this app?", "What can MIM help with?", "What still needs setup before publishing?")
}
$helpHtml = ($helpQuestions | ForEach-Object { "<li>" + (ConvertTo-HtmlText $_) + "</li>" }) -join ""

$completion = if ($artifact.completion_summary) { $artifact.completion_summary } else { [pscustomobject]@{ status = "prototype_artifact_ready"; summary = "Completion summary pending." } }
$knownLimitations = if ($artifact.PSObject.Properties["known_limitations"]) { @($artifact.known_limitations | ForEach-Object { [string]$_ }) } else { @() }
if (@($knownLimitations).Count -eq 0) {
    $knownLimitations = @("No build boundaries were published for this preview.")
}
$limitationsHtml = ($knownLimitations | ForEach-Object { "<li>" + (ConvertTo-HtmlText $_) + "</li>" }) -join ""
$lastMinuteChange = if ($artifact.presentation_walkthrough -and $artifact.presentation_walkthrough.PSObject.Properties["last_minute_change_request"]) { [string]$artifact.presentation_walkthrough.last_minute_change_request } else { "No last-minute change request recorded." }
$previewHtml = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$((ConvertTo-HtmlText $appName))</title>
  <style>
    :root { color-scheme: light dark; --bg:$background; --panel:$panel; --ink:$ink; --muted:$muted; --line:color-mix(in srgb, $accent 30%, #2c3b4d); --accent:$accent; --accent2:$accent2; --font:$fontStack; }
    * { box-sizing:border-box; }
    body { margin:0; font-family:var(--font); background:var(--bg); color:var(--ink); }
    body.design-receipt { --bg:#f7f0e6; --panel:#fffaf2; --ink:#272017; --muted:#715f4d; --line:#e3caa5; --accent:#d97706; --accent2:#167a4a; }
    body.design-portal { --bg:#eef5ff; --panel:#ffffff; --ink:#172033; --muted:#526278; --line:#c9d8ee; --accent:#2563eb; --accent2:#0f766e; }
    body.design-editorial { --bg:#fbf7ff; --panel:#ffffff; --ink:#25133d; --muted:#6b5a7e; --line:#ead8ff; --accent:#d946ef; --accent2:#06b6d4; }
    body.design-crm { --bg:#f6f7fb; --panel:#ffffff; --ink:#151922; --muted:#6b7280; --line:#dde3ef; --accent:#ef5f4c; --accent2:#111827; }
    body.design-kanban { --bg:#f5f7ff; --panel:#ffffff; --ink:#172033; --muted:#65748b; --line:#dce4ff; --accent:#6366f1; --accent2:#f97316; }
    body.design-sales { --bg:#f7f5ff; --panel:#ffffff; --ink:#17122b; --muted:#6b6290; --line:#ddd6fe; --accent:#4f46e5; --accent2:#22c55e; }
    body.design-support { --bg:#f8fbfc; --panel:#ffffff; --ink:#101820; --muted:#58707f; --line:#d7e5eb; --accent:#0891b2; --accent2:#f43f5e; }
    body.design-expense { --bg:#101010; --panel:#f8f4ec; --ink:#121212; --muted:#62615e; --line:#ded6ca; --accent:#111111; --accent2:#9f7aea; }
    body.design-inventory { --bg:#f1f8f3; --panel:#ffffff; --ink:#102016; --muted:#597065; --line:#cfe7d7; --accent:#16a34a; --accent2:#f59e0b; }
    body.design-mobile-calendar { --bg:#08080b; --panel:#ffffff; --ink:#151515; --muted:#666; --line:#e6e6e6; --accent:#111111; --accent2:#b6f26b; }
    body.design-call-guard { --bg:#050816; --panel:#101528; --ink:#f7fbff; --muted:#aeb9d4; --line:#24304f; --accent:#22d3ee; --accent2:#f43f5e; }
    body.design-chef { --bg:#fff7ed; --panel:#ffffff; --ink:#2b2118; --muted:#7a6655; --line:#f1d5b8; --accent:#f97316; --accent2:#16a34a; }
    header { padding:28px; border-bottom:1px solid var(--line); background:radial-gradient(circle at 20% 10%, color-mix(in srgb, var(--accent) 24%, transparent), transparent 34%), linear-gradient(135deg,color-mix(in srgb, var(--accent) 12%, var(--panel)),color-mix(in srgb, var(--accent2) 10%, var(--bg))); }
    body.design-expense header, body.design-mobile-calendar header { background:#050507; color:#fff; border-color:#252525; }
    .hero { display:grid; grid-template-columns:minmax(0,1fr) minmax(280px,440px); gap:24px; align-items:center; max-width:1220px; margin:0 auto; }
    main { padding:20px; max-width:1220px; margin:0 auto; }
    h1 { margin:0; font-size:clamp(30px,5vw,60px); letter-spacing:0; }
    h2 { margin:8px 0; }
    p { color:var(--muted); line-height:1.5; }
    .grid { display:grid; gap:14px; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); }
    .card { border:1px solid var(--line); background:var(--panel); border-radius:8px; padding:16px; box-shadow:0 16px 40px rgba(15,23,42,.06); }
    .pill { display:inline-block; border:1px solid var(--line); border-radius:999px; padding:7px 10px; margin:3px; color:var(--accent); background:color-mix(in srgb, var(--panel) 84%, var(--accent)); font-weight:700; }
    small { color:var(--accent2); text-transform:uppercase; font-weight:800; }
    table { width:100%; border-collapse:collapse; }
    th,td { border-bottom:1px solid var(--line); padding:10px; text-align:left; }
    .button { border:0; border-radius:7px; padding:10px 13px; background:var(--accent); color:#031018; font-weight:800; cursor:pointer; }
    body.design-expense .button, body.design-mobile-calendar .button { color:#fff; }
    .button.secondary { background:transparent; color:var(--ink); border:1px solid var(--line); }
    textarea,input { width:100%; border:1px solid var(--line); background:color-mix(in srgb, var(--panel) 92%, #000); color:var(--ink); border-radius:7px; padding:10px; }
    .status-line { margin-top:10px; padding:10px; border:1px solid var(--line); border-radius:7px; color:var(--muted); background:color-mix(in srgb, var(--panel) 85%, var(--accent)); }
    .action-log { max-height:160px; overflow:auto; }
    .showcase { min-height:260px; border:1px solid var(--line); background:color-mix(in srgb, var(--panel) 92%, var(--accent)); border-radius:8px; padding:16px; display:grid; place-items:center; overflow:hidden; }
    .receipt-visual { display:grid; grid-template-columns:1fr 1fr; gap:12px; width:100%; }
    .receipt-paper, .audit-stack, .folder-card, .upload-drop, .ticket, .crm-visual main, .crm-visual aside { background:#fff; border:1px solid var(--line); border-radius:8px; padding:14px; color:var(--ink); }
    .receipt-paper { display:grid; gap:10px; box-shadow:0 18px 0 -8px #f1dfc8; }
    .receipt-paper strong { font-size:42px; }
    .audit-stack { display:grid; gap:8px; align-content:start; }
    .ok, .live { color:#15803d; font-weight:800; }
    .warn, .hot { color:#b45309; font-weight:800; }
    .portal-visual { display:grid; gap:12px; width:100%; }
    .folder-card.active { background:#dbeafe; border-color:#2563eb; }
    .upload-drop { border-style:dashed; min-height:88px; display:grid; place-items:center; }
    .calendar-visual { display:grid; grid-template-columns:repeat(6,1fr); gap:8px; width:100%; }
    .calendar-visual span { background:#fff; border:1px solid var(--line); border-radius:8px; min-height:70px; padding:10px; }
    .calendar-visual .draft { color:#9333ea; font-weight:800; }
    .crm-visual { display:grid; grid-template-columns:120px 1fr; gap:12px; width:100%; }
    .crm-visual main { display:grid; gap:10px; }
    .metric { background:#ffe7df; border-radius:8px; padding:12px; font-weight:900; }
    .kanban-visual { display:grid; grid-template-columns:repeat(3,1fr); gap:10px; width:100%; }
    .kanban-visual div { background:#fff; border:1px solid var(--line); border-radius:8px; padding:10px; min-height:160px; }
    .kanban-visual span { display:block; margin-top:12px; padding:10px; border-radius:8px; background:#eef2ff; }
    .pipeline-visual { display:flex; align-items:end; gap:12px; height:220px; width:100%; padding:12px; }
    .pipeline-visual div { flex:1; background:linear-gradient(#818cf8,#4f46e5); border-radius:8px 8px 0 0; }
    .support-visual { display:grid; gap:10px; width:100%; }
    .ticket.urgent { border-color:#f43f5e; background:#fff1f2; }
    .ticket.done { border-color:#22c55e; background:#f0fdf4; }
    .phone-visual { width:min(260px,100%); min-height:430px; border-radius:28px; background:#fff; color:#111; padding:18px; box-shadow:0 0 0 8px #202024, 0 24px 60px rgba(0,0,0,.25); display:grid; gap:14px; align-content:start; }
    .phone-bar { width:80px; height:8px; border-radius:999px; background:#111; margin:0 auto 8px; opacity:.18; }
    .scan-box { height:150px; border:2px dashed #111; border-radius:12px; background:linear-gradient(135deg,#f9fafb,#ede9fe); }
    .phone-pill { padding:12px; border-radius:16px; background:#111; color:#fff; font-weight:800; }
    .phone-pill.alt { background:var(--accent2); color:#111; }
    .date-grid { display:grid; grid-template-columns:repeat(4,1fr); gap:8px; }
    .date-grid span { padding:12px 0; text-align:center; border-radius:12px; background:#f3f4f6; }
    .date-grid .selected { background:#111; color:#fff; }
    .inventory-visual { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; width:100%; }
    .inventory-visual div, .inventory-visual span { background:#fff; border:1px solid var(--line); border-radius:7px; min-height:56px; padding:10px; }
    .inventory-visual .low { background:#fef3c7; border-color:#f59e0b; }
    .saas-visual { display:grid; grid-template-columns:1fr 1fr; gap:12px; width:100%; }
    .saas-visual div { min-height:110px; border-radius:8px; background:#fff; border:1px solid var(--line); }
    .call-guard-visual { width:100%; display:grid; grid-template-columns:minmax(180px,260px) 1fr; gap:18px; align-items:center; }
    .call-phone { min-height:430px; border-radius:34px; background:linear-gradient(180deg,#0b1224,#111827); box-shadow:0 0 0 8px #020617,0 26px 60px rgba(0,0,0,.35); padding:26px; display:grid; gap:18px; align-content:start; }
    .caller-dot { width:72px; height:72px; border-radius:50%; background:linear-gradient(135deg,var(--accent),#a5f3fc); margin:0 auto; box-shadow:0 0 0 12px rgba(34,211,238,.12); }
    .call-wave { display:flex; gap:8px; align-items:end; justify-content:center; height:80px; }
    .call-wave i { width:12px; border-radius:999px; background:var(--accent); display:block; }
    .call-wave i:nth-child(1) { height:32px; } .call-wave i:nth-child(2) { height:66px; } .call-wave i:nth-child(3) { height:48px; } .call-wave i:nth-child(4) { height:74px; background:var(--accent2); }
    .call-card { min-height:56px; border-radius:18px; background:#1f2a44; border:1px solid #314363; }
    .call-card.danger { background:color-mix(in srgb,var(--accent2) 22%,#1f2a44); }
    .call-actions { display:grid; grid-template-columns:1fr 1fr; gap:10px; }
    .call-actions span { height:48px; border-radius:999px; background:var(--accent); }
    .call-actions span + span { background:var(--accent2); }
    .summary-card { min-height:230px; border-radius:22px; background:#fff; color:#101827; border:1px solid var(--line); padding:24px; display:grid; gap:16px; align-content:start; }
    .summary-card b, .summary-card span { display:block; border-radius:999px; background:#dbeafe; min-height:18px; }
    .summary-card b { width:55%; background:#94a3b8; }
    .summary-card span { width:88%; }
    .summary-card .hot { width:45%; background:#fecdd3; }
    .chef-visual { width:100%; display:grid; grid-template-columns:1.1fr .9fr; gap:16px; align-items:stretch; }
    .recipe-card, .pantry-card, .camera-card { border:1px solid var(--line); border-radius:24px; background:#fffaf4; color:#2b2118; padding:18px; box-shadow:0 16px 34px rgba(124,45,18,.10); }
    .recipe-card { display:grid; gap:14px; }
    .plate { width:150px; height:150px; border-radius:50%; background:radial-gradient(circle at 45% 42%,#fee2b6 0 24%,#fb923c 25% 42%,#fef3c7 43% 60%,#fff 61%); box-shadow:0 0 0 12px #fff,0 0 0 14px var(--line); margin:4px auto; }
    .recipe-card span, .pantry-card span, .pantry-card b { display:block; border-radius:999px; min-height:16px; background:#fed7aa; }
    .recipe-card span:nth-child(3), .pantry-card span:nth-child(3) { width:72%; background:#bbf7d0; }
    .nutrition-row { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; }
    .nutrition-row i { min-height:54px; border-radius:16px; background:color-mix(in srgb,var(--accent) 26%,#fff); }
    .pantry-card { display:grid; gap:14px; align-content:start; }
    .pantry-card b { width:52%; background:#fdba74; }
    .camera-card { min-height:140px; background:linear-gradient(135deg,#fff7ed,#dcfce7); position:relative; }
    .camera-card:after { content:""; position:absolute; inset:34px; border:2px dashed #f97316; border-radius:18px; }
    .app-shell { display:grid; grid-template-columns:260px 1fr; gap:14px; align-items:start; }
    .desktop .screen-list { grid-column:1 / -1; }
    .mobile .screen-list { max-width:430px; margin:0 auto; }
    @media (max-width:760px) {
      .hero, .app-shell { grid-template-columns:1fr; }
      .kanban-visual, .receipt-visual, .crm-visual, .call-guard-visual, .chef-visual { grid-template-columns:1fr; }
    }
  </style>
</head>
<body class="$layoutClass $deviceClass">
  <header>
    <div class="hero">
      <div>
        <small>Published Workbench Preview / $((ConvertTo-HtmlText $style))</small>
        <h1>$((ConvertTo-HtmlText $appName))</h1>
        <p>$((ConvertTo-HtmlText $artifact.summary))</p>
        <p><strong>Visual direction:</strong> $((ConvertTo-HtmlText $designFocus))</p>
      </div>
      <div class="showcase">$heroVisual</div>
    </div>
  </header>
  <main>
    <section class="card">
      <small>Presentation Walkthrough</small>
      <h2>What this app includes</h2>
      <div>$workflowHtml</div>
    </section>
    <section class="card" style="margin-top:14px;">
      <small>Interactive Workflow Preview</small>
      <h2>Try the app flow</h2>
      <p>This is a browser-local training preview. Click workflow actions to simulate app behavior, update the sample table, and record change-log evidence.</p>
      <div>$workflowButtons</div>
      <div class="status-line" id="interactionStatus">Ready for a workflow action.</div>
    </section>
    <section class="grid" style="margin-top:14px;">$screenHtml</section>
    <section class="card" style="margin-top:14px;">
      <small>Sample Data</small>
      <h2>Preview Records</h2>
      <table><thead><tr><th>Name</th><th>Status</th><th>Note</th></tr></thead><tbody id="recordRows">$recordRows</tbody></table>
    </section>
    <section class="grid" style="margin-top:14px;">
      <article class="card">
        <small>MIM Help</small>
        <h2>App-specific support</h2>
        <ul>$helpHtml</ul>
        <input id="mimHelpQuestion" placeholder="Ask MIM how to use this app preview">
        <button class="button secondary" id="mimHelpButton" type="button" style="margin-top:8px;">Ask App Help</button>
        <div class="status-line" id="mimHelpAnswer">MIM Help is scoped to this app only.</div>
      </article>
      <article class="card">
        <small>Completion Summary</small>
        <h2>$((ConvertTo-HtmlText $completion.status))</h2>
        <p>$((ConvertTo-HtmlText $completion.summary))</p>
      </article>
      <article class="card">
        <small>Build Boundaries</small>
        <h2>Not production-claimed</h2>
        <ul>$limitationsHtml</ul>
      </article>
    </section>
    <section class="grid" style="margin-top:14px;">
      <article class="card">
        <small>Last-Minute Change</small>
        <h2>Adjustment handled</h2>
        <p>$((ConvertTo-HtmlText $lastMinuteChange))</p>
      </article>
      <article class="card">
        <small>Change Log</small>
        <h2>Preview actions</h2>
        <div class="action-log" id="actionLog">No preview actions yet.</div>
      </article>
    </section>
  </main>
  <script>
    (() => {
      const appName = $((ConvertTo-Json $appName));
      const status = document.getElementById('interactionStatus');
      const rows = document.getElementById('recordRows');
      const log = document.getElementById('actionLog');
      const helpQuestion = document.getElementById('mimHelpQuestion');
      const helpAnswer = document.getElementById('mimHelpAnswer');
      const addLog = (message) => {
        const stamp = new Date().toLocaleTimeString();
        const line = document.createElement('div');
        line.textContent = '[' + stamp + '] ' + message;
        if (log.textContent === 'No preview actions yet.') log.textContent = '';
        log.prepend(line);
      };
      document.querySelectorAll('.workflow-action').forEach((button) => {
        button.addEventListener('click', () => {
          const action = button.dataset.action || 'workflow action';
          const row = document.createElement('tr');
          row.innerHTML = '<td>' + action + '</td><td>simulated</td><td>' + appName + ' preview handled: ' + action + '</td>';
          rows.prepend(row);
          status.textContent = 'Simulated "' + action + '". In a production build, MIM would dispatch TOD to implement this workflow against the app data model.';
          addLog('Workflow simulated: ' + action);
        });
      });
      document.getElementById('mimHelpButton')?.addEventListener('click', () => {
        const q = (helpQuestion.value || '').toLowerCase();
        let answer = 'MIM Help for ' + appName + ': use the workflow buttons to review the app planned behavior, then request changes from the Workbench.';
        if (q.includes('add') || q.includes('create')) answer = 'To add something in ' + appName + ', open the primary workflow screen and use the create/add action. This preview simulates the flow and records it in the action log.';
        if (q.includes('publish') || q.includes('deploy')) answer = 'Publishing ' + appName + ' still requires a deploy target. The preview package is ready, but production deploy is intentionally gated.';
        helpAnswer.textContent = answer;
        addLog('MIM Help answered: ' + (helpQuestion.value || 'general help'));
      });
    })();
  </script>
</body>
</html>
"@

$previewPath = Join-Path $outputDir "preview.html"
$summaryPath = Join-Path $outputDir "completion_summary.json"
$readmePath = Join-Path $outputDir "README.md"

$manifest = [ordered]@{
    artifact_type = "user_app_published_preview_manifest_v1"
    app_name = $appName
    slug = $slug
    source = $Source
    generated_at = $now
    style_preset = $style
    visual_theme = [ordered]@{
        background = $background
        panel = $panel
        ink = $ink
        muted = $muted
        accent = $accent
        accent_2 = $accent2
        font_stack = $fontStack
        banner_prompt = $bannerPrompt
    }
    prototype_path = (Convert-ToRepoRelativePath -PathValue $resolvedPrototypePath)
    output_manifest_path = (Convert-ToRepoRelativePath -PathValue $resolvedManifestPath)
    preview_path = (Convert-ToRepoRelativePath -PathValue $previewPath)
    completion_summary_path = (Convert-ToRepoRelativePath -PathValue $summaryPath)
    readme_path = (Convert-ToRepoRelativePath -PathValue $readmePath)
    status = "published_preview_ready"
    gates = [ordered]@{
        workbench_artifact = "ready"
        presentation_walkthrough = if ($artifact.PSObject.Properties["presentation_walkthrough"]) { "ready" } else { "missing" }
        mim_help = if ($artifact.PSObject.Properties["mim_help"]) { "ready" } else { "missing" }
        completion_summary = if ($artifact.PSObject.Properties["completion_summary"]) { "ready" } else { "missing" }
        interactive_workflow_preview = "ready"
        last_minute_change_visible = "ready"
        production_deploy = "not_selected"
    }
    acceptance_evidence = @(
        "preview.html generated",
        "interactive workflow simulator generated",
        "MIM app help interaction generated",
        "last-minute change section generated",
        "package.manifest.json generated",
        "completion_summary.json generated",
        "README.md generated",
        "source prototype retained"
    )
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($previewPath, $previewHtml, $utf8NoBom)
[System.IO.File]::WriteAllText($resolvedManifestPath, ($manifest | ConvertTo-Json -Depth 30), $utf8NoBom)
[System.IO.File]::WriteAllText($summaryPath, ($completion | ConvertTo-Json -Depth 30), $utf8NoBom)
[System.IO.File]::WriteAllText($readmePath, ("# $appName`n`nPublished Workbench preview generated from `$PrototypePath`.`n`nOpen `preview.html` to review the app presentation, sample data, MIM help, and completion summary.`n"), $utf8NoBom)

[pscustomobject]@{
    status = "published_preview_ready"
    app_name = $appName
    manifest = (Convert-ToRepoRelativePath -PathValue $resolvedManifestPath)
    preview = (Convert-ToRepoRelativePath -PathValue $previewPath)
} | ConvertTo-Json -Depth 8
