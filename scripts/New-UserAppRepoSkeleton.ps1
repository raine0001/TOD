param(
    [Parameter(Mandatory = $true)][string]$PlanPath,
    [string]$OutputRoot = "",
    [string]$Source = "CodexSupervised::UserAppRepoSkeleton"
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

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function To-Pascal {
    param([Parameter(Mandatory = $true)][string]$Text)
    return (($Text -split '[^A-Za-z0-9]+' | Where-Object { $_ } | ForEach-Object {
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant()
            }) -join '')
}

$planAbs = Convert-ToRepoPath -PathValue $PlanPath
if (-not (Test-Path -Path $planAbs -PathType Leaf)) {
    throw "Materialization plan not found: $PlanPath"
}

$plan = Get-Content -Path $planAbs -Raw | ConvertFrom-Json
if ([string]$plan.artifact_type -ne "user_app_materialization_plan_v1") {
    throw "Unsupported plan artifact type: $($plan.artifact_type)"
}

$slug = [string]$plan.slug
$appName = [string]$plan.app_name
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = "runtime/shared/user_app_repos/$slug"
}
$outputAbs = Convert-ToRepoPath -PathValue $OutputRoot
New-Item -ItemType Directory -Path $outputAbs -Force | Out-Null

$componentName = To-Pascal -Text $appName
$dataObjects = @($plan.proposed_repo.data_objects | ForEach-Object { [string]$_ })
if (@($dataObjects).Count -eq 0) {
    $dataObjects = @("item")
}
$primaryObject = [string]$dataObjects[0]
$theme = if ($plan.PSObject.Properties["visual_theme"]) { $plan.visual_theme } else { [pscustomobject]@{} }
$background = if ($theme.PSObject.Properties["background"]) { [string]$theme.background } else { "#f7fafc" }
$panel = if ($theme.PSObject.Properties["panel"]) { [string]$theme.panel } else { "#ffffff" }
$ink = if ($theme.PSObject.Properties["ink"]) { [string]$theme.ink } else { "#102033" }
$muted = if ($theme.PSObject.Properties["muted"]) { [string]$theme.muted } else { "#5a6b7d" }
$accent = if ($theme.PSObject.Properties["accent"]) { [string]$theme.accent } else { "#1d9bf0" }
$accent2 = if ($theme.PSObject.Properties["accent_2"]) { [string]$theme.accent_2 } else { "#16a34a" }
$fontStack = if ($theme.PSObject.Properties["font_stack"]) { [string]$theme.font_stack } else { "Inter, Segoe UI, Arial, sans-serif" }
$stylePreset = if ($plan.PSObject.Properties["style_preset"]) { [string]$plan.style_preset } else { "clean_saas" }

$packageJson = @{
    name = $slug
    version = "0.1.0"
    private = $true
    scripts = @{
        dev = "next dev"
        build = "next build"
        test = "playwright test"
    }
    dependencies = @{
        "@playwright/test" = "^1.44.0"
        "next" = "^14.2.0"
        "react" = "^18.2.0"
        "react-dom" = "^18.2.0"
    }
    mimtod = @{
        generated_from = Convert-ToRepoRelativePath -PathValue $planAbs
        production_deploy = "not_selected"
        dave_needed = "no"
    }
} | ConvertTo-Json -Depth 12

$readme = @"
# $appName

Generated app repo skeleton from the MIM/TOD sample app materialization plan.

## Current state

- Foundation screens are present: front page, login, dashboard, help, settings.
- Primary workflow scaffold is present for `$primaryObject`.
- MIM Help is scoped to this app only.
- Production deploy is not selected.

## Next TOD task

$($plan.tod_next_action)
"@

$globals = @"
:root {
  --background: $background;
  --panel: $panel;
  --ink: $ink;
  --muted: $muted;
  --accent: $accent;
  --accent-2: $accent2;
  --line: color-mix(in srgb, var(--ink) 14%, transparent);
  --shadow: 0 18px 55px color-mix(in srgb, var(--ink) 12%, transparent);
  font-family: $fontStack;
}

* { box-sizing: border-box; }

body {
  margin: 0;
  min-height: 100vh;
  color: var(--ink);
  background:
    radial-gradient(circle at top right, color-mix(in srgb, var(--accent) 18%, transparent), transparent 34rem),
    linear-gradient(135deg, var(--background), color-mix(in srgb, var(--background) 78%, var(--accent-2) 22%));
}

a { color: inherit; text-decoration: none; }

.shell {
  width: min(1120px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 38px 0 56px;
}

.hero {
  display: grid;
  gap: 18px;
  padding: 28px;
  border: 1px solid var(--line);
  border-radius: 22px;
  background: color-mix(in srgb, var(--panel) 88%, transparent);
  box-shadow: var(--shadow);
}

.hero h1, .page-title {
  margin: 0;
  max-width: 780px;
  font-size: clamp(2rem, 5vw, 4.6rem);
  line-height: 0.98;
}

.hero p, .muted { color: var(--muted); }

.nav, .actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.nav a, button, .pill {
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 10px 14px;
  background: var(--panel);
  color: var(--ink);
  font: inherit;
}

button.primary, .nav a:first-child {
  border-color: transparent;
  background: var(--accent);
  color: white;
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
  gap: 14px;
  margin-top: 18px;
}

.card, form, table {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 18px;
  background: color-mix(in srgb, var(--panel) 92%, transparent);
  box-shadow: 0 10px 34px color-mix(in srgb, var(--ink) 8%, transparent);
}

.card, form { padding: 18px; }

label {
  display: grid;
  gap: 6px;
  margin-bottom: 12px;
  font-weight: 700;
}

input, select {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 11px 12px;
  background: color-mix(in srgb, var(--panel) 86%, white 14%);
  color: var(--ink);
  font: inherit;
}

table {
  border-collapse: collapse;
  overflow: hidden;
}

th, td {
  padding: 12px;
  text-align: left;
  border-bottom: 1px solid var(--line);
}

th { color: var(--muted); font-size: 0.78rem; text-transform: uppercase; }

.metric {
  font-size: 2rem;
  font-weight: 900;
}
"@

$layout = @"
import "./globals.css";

export const metadata = { title: "$appName" };

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
"@

$homePage = @"
export default function HomePage() {
  return (
    <main className="shell">
      <section className="hero">
        <span className="pill">$stylePreset</span>
        <h1>$appName</h1>
        <p>A generated app foundation ready for user review, persistence work, and deploy target selection.</p>
      <nav className="nav">
        <a href="/login">Login</a>
        <a href="/dashboard">Dashboard</a>
        <a href="/help">Help</a>
        <a href="/settings">Settings</a>
      </nav>
      </section>
      <section className="grid">
        <article className="card"><strong>Build state</strong><div className="metric">Preview</div><p className="muted">Ready for review and change requests.</p></article>
        <article className="card"><strong>Core object</strong><div className="metric">$primaryObject</div><p className="muted">Primary workflow scaffolded for the first app slice.</p></article>
        <article className="card"><strong>MIM Help</strong><div className="metric">Scoped</div><p className="muted">Help answers stay inside this app.</p></article>
      </section>
    </main>
  );
}
"@

$login = @"
export default function LoginPage() {
  return (
    <main className="shell">
      <h1 className="page-title">Login</h1>
      <p className="muted">Access your $appName workspace.</p>
      <form>
        <label>Email <input name="email" type="email" /></label>
        <label>Password <input name="password" type="password" /></label>
        <button type="submit">Log in</button>
      </form>
      <a href="/forgot-password">Forgot password?</a>
    </main>
  );
}
"@

 $dashboard = @"
import { WorkflowBoard } from "../../components/WorkflowBoard";

export default function DashboardPage() {
  return (
    <main className="shell">
      <h1 className="page-title">$appName Dashboard</h1>
      <p className="muted">Current work, sample records, and next actions for the generated app.</p>
      <section className="grid">
        <article className="card"><strong>Active</strong><div className="metric">1</div></article>
        <article className="card"><strong>Waiting</strong><div className="metric">1</div></article>
        <article className="card"><strong>Ready</strong><div className="metric">2</div></article>
      </section>
      <WorkflowBoard />
    </main>
  );
}
"@

$workflowComponent = @"
"use client";

import { useEffect, useMemo, useState } from "react";

type WorkflowRecord = {
  id: string;
  name: string;
  status: "active" | "waiting" | "complete";
  next: string;
};

const storageKey = "$slug.workflow.records";
const primaryLabel = "$primaryObject";

const seedRecords: WorkflowRecord[] = [
  { id: "seed-1", name: "Sample $primaryObject 1", status: "active", next: "Review" },
  { id: "seed-2", name: "Sample $primaryObject 2", status: "waiting", next: "Follow up" }
];

export function WorkflowBoard() {
  const [records, setRecords] = useState<WorkflowRecord[]>(seedRecords);
  const [message, setMessage] = useState("Ready.");

  useEffect(() => {
    const saved = window.localStorage.getItem(storageKey);
    if (saved) {
      setRecords(JSON.parse(saved));
    }
  }, []);

  useEffect(() => {
    window.localStorage.setItem(storageKey, JSON.stringify(records));
  }, [records]);

  const counts = useMemo(() => ({
    active: records.filter((record) => record.status === "active").length,
    waiting: records.filter((record) => record.status === "waiting").length,
    complete: records.filter((record) => record.status === "complete").length
  }), [records]);

  function addRecord() {
    const nextNumber = records.length + 1;
    const newRecord: WorkflowRecord = {
      id: "record-" + Date.now(),
      name: "New " + primaryLabel + " " + nextNumber,
      status: "active",
      next: "Schedule review"
    };
    setRecords((current) => [newRecord, ...current]);
    setMessage("Added " + newRecord.name + ".");
  }

  function moveFirstWaiting() {
    const target = records.find((record) => record.status === "active");
    if (!target) {
      setMessage("No active " + primaryLabel + " is available.");
      return;
    }
    setRecords((current) => current.map((record) => record.id === target.id ? { ...record, status: "waiting", next: "Waiting on response" } : record));
    setMessage("Moved the first active " + primaryLabel + " to waiting.");
  }

  function completeFirst() {
    const target = records.find((record) => record.status !== "complete");
    if (!target) {
      setMessage("All " + primaryLabel + " records are complete.");
      return;
    }
    setRecords((current) => current.map((record) => record.id === target.id ? { ...record, status: "complete", next: "Closed" } : record));
    setMessage("Completed the first open " + primaryLabel + ".");
  }

  function resetDemo() {
    setRecords(seedRecords);
    setMessage("Demo data reset.");
  }

  function exportJson() {
    const blob = new Blob([JSON.stringify(records, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = "$slug-records.json";
    link.click();
    URL.revokeObjectURL(url);
    setMessage("Exported " + records.length + " records.");
  }

  return (
    <section className="card">
      <h2>Primary Workflow</h2>
      <div className="grid">
        <article className="card"><strong>Active</strong><div className="metric">{counts.active}</div></article>
        <article className="card"><strong>Waiting</strong><div className="metric">{counts.waiting}</div></article>
        <article className="card"><strong>Complete</strong><div className="metric">{counts.complete}</div></article>
      </div>
      <div className="actions">
        <button className="primary" onClick={addRecord}>Add {primaryLabel}</button>
        <button onClick={moveFirstWaiting}>Move to waiting</button>
        <button onClick={completeFirst}>Complete first</button>
        <button onClick={exportJson}>Export JSON</button>
        <button onClick={resetDemo}>Reset demo</button>
      </div>
      <p className="muted" data-testid="workflow-message">{message}</p>
      <table>
        <thead><tr><th>Name</th><th>Status</th><th>Next</th></tr></thead>
        <tbody>{records.map((row) => <tr key={row.id}><td>{row.name}</td><td>{row.status}</td><td>{row.next}</td></tr>)}</tbody>
      </table>
    </section>
  );
}
"@

$help = @"
export default function HelpPage() {
  return (
    <main className="shell">
      <h1 className="page-title">How to use $appName</h1>
      <section className="card">
        <ol>
        <li>Open the dashboard.</li>
        <li>Create or review a $primaryObject record.</li>
        <li>Use status and next-action fields to keep work moving.</li>
      </ol>
      </section>
      <section className="card" aria-label="MIM Help">
        <h2>MIM Help</h2>
        <p>Ask app-specific questions such as: how do I add a ${primaryObject}?</p>
        <input placeholder="Ask MIM about this app..." />
        <button>Ask MIM</button>
      </section>
    </main>
  );
}
"@

$settings = @"
export default function SettingsPage() {
  return (
    <main className="shell">
      <h1 className="page-title">User Settings</h1>
      <p className="muted">Profile, preferences, notifications, and account controls.</p>
      <form>
        <label>Name <input name="name" /></label>
        <label>Email <input name="email" type="email" /></label>
        <label>Notifications <select name="notifications"><option>Email</option><option>Off</option></select></label>
        <button type="submit">Save settings</button>
      </form>
    </main>
  );
}
"@

$auth = @"
export function requireUser() {
  return { id: "demo-user", email: "demo@example.com" };
}

export function canAccessApp() {
  return true;
}
"@

$db = @"
export const schema = {
  objects: $(($dataObjects | ConvertTo-Json -Compress))
};

export function getDatabaseStatus() {
  return { mode: "not_selected", message: "Select a database target before production deploy." };
}
"@

$mimHelp = @"
export function answerAppHelp(question) {
  return {
    scope: "app_specific_help_only",
    answer: "This help surface only answers questions about $appName. Question: " + question
  };
}
"@

$test = @"
import { test, expect } from '@playwright/test';

test('$appName foundation pages exist', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByText('$appName')).toBeVisible();
  await page.goto('/dashboard');
  await expect(page.getByText('Primary Workflow')).toBeVisible();
  await page.goto('/help');
  await expect(page.getByText('MIM Help')).toBeVisible();
});
"@

$files = [ordered]@{
    "README.md" = $readme
    "package.json" = $packageJson
    "src/app/globals.css" = $globals
    "src/app/layout.tsx" = $layout
    "src/app/page.tsx" = $homePage
    "src/app/login/page.tsx" = $login
    "src/app/dashboard/page.tsx" = $dashboard
    "src/app/help/page.tsx" = $help
    "src/app/settings/page.tsx" = $settings
    "src/components/WorkflowBoard.tsx" = $workflowComponent
    "src/lib/auth.ts" = $auth
    "src/lib/db.ts" = $db
    "src/components/MimHelpPanel.tsx" = $mimHelp
    "tests/acceptance.spec.ts" = $test
}

foreach ($entry in $files.GetEnumerator()) {
    Write-Utf8NoBom -Path (Join-Path $outputAbs $entry.Key) -Content ([string]$entry.Value)
}

$manifest = [ordered]@{
    artifact_type = "user_app_repo_skeleton_manifest_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = $Source
    app_name = $appName
    slug = $slug
    source_plan = Convert-ToRepoRelativePath -PathValue $planAbs
    repo_root = Convert-ToRepoRelativePath -PathValue $outputAbs
    file_count = @($files.Keys).Count
    files = @($files.Keys)
    style_preset = $stylePreset
    visual_theme = [ordered]@{
        background = $background
        panel = $panel
        ink = $ink
        muted = $muted
        accent = $accent
        accent_2 = $accent2
        font_stack = $fontStack
    }
    foundation_screens = @("front_page", "login", "dashboard", "help", "settings")
    primary_workflow = "Scaffolded $primaryObject workflow on dashboard."
    gates = [ordered]@{
        repo_skeleton = "ready"
        auth_flow = "scaffolded"
        database = "not_selected"
        acceptance_tests = "scaffolded"
        preview_deploy = "not_selected"
        production_deploy = "not_selected"
    }
    dave_needed = "no"
    tod_next_action = "Implement real persistence for $primaryObject and run the scaffolded acceptance test against a selected preview target."
}

Write-Utf8NoBom -Path (Join-Path $outputAbs "repo.manifest.json") -Content ($manifest | ConvertTo-Json -Depth 30)
$manifest | ConvertTo-Json -Depth 12
