param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [int]$Port = 3125,

    [string[]]$Routes = @("/", "/login", "/dashboard", "/settings", "/help"),

    [string]$OutputRoot = "runtime/shared/user_app_runtime_acceptance"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot

function Resolve-WorkspacePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -Path $Path).Path
    }
    return (Resolve-Path -Path (Join-Path $workspaceRoot ($Path -replace '/', [System.IO.Path]::DirectorySeparatorChar))).Path
}

function ConvertTo-WorkspaceRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($workspaceRoot).TrimEnd('\') + '\'
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return (($full.Substring($root.Length)) -replace '\\', '/')
    }
    return $full
}

function Test-PortOpen {
    param([Parameter(Mandatory = $true)][int]$LocalPort)
    return ($null -ne (Get-NetTCPConnection -LocalPort $LocalPort -ErrorAction SilentlyContinue))
}

$repoAbs = Resolve-WorkspacePath -Path $RepoRoot
$manifestPath = Join-Path $repoAbs "repo.manifest.json"
if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
    throw "Repo manifest not found: $manifestPath"
}
$manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
$slug = [string]$manifest.slug
if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = Split-Path -Leaf $repoAbs
}
$appName = [string]$manifest.app_name
if ([string]::IsNullOrWhiteSpace($appName)) {
    $appName = ($slug -replace '_', ' ')
}

while (Test-PortOpen -LocalPort $Port) {
    $Port++
}

$outputDir = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    Join-Path $OutputRoot $slug
}
else {
    Join-Path $workspaceRoot (($OutputRoot + "/" + $slug) -replace '/', [System.IO.Path]::DirectorySeparatorChar)
}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$screenshotsDir = Join-Path $outputDir "screenshots"
New-Item -ItemType Directory -Path $screenshotsDir -Force | Out-Null
$acceptancePath = Join-Path $outputDir "runtime.acceptance.json"
if (-not (Test-Path -Path $acceptancePath -PathType Leaf)) {
    throw "Runtime acceptance result not found: $acceptancePath"
}

$serverOut = Join-Path $outputDir "visual-server.out.log"
$serverErr = Join-Path $outputDir "visual-server.err.log"
$server = $null
$baseUrl = "http://localhost:$Port"
$runnerPath = Join-Path $outputDir "visual-acceptance-runner.cjs"

$runner = @'
const fs = require("fs");
const path = require("path");
const repoRoot = process.env.MIMTOD_REPO_ROOT;
const { chromium } = require(require.resolve("playwright", { paths: [repoRoot] }));

async function main() {
  const appName = process.env.MIMTOD_APP_NAME;
  const baseUrl = process.env.MIMTOD_BASE_URL;
  const routes = JSON.parse(process.env.MIMTOD_ROUTES_JSON);
  const screenshotDir = process.env.MIMTOD_SCREENSHOT_DIR;
  const results = [];
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
  const consoleErrors = [];
  const pageErrors = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  page.on("pageerror", (error) => pageErrors.push(error.message));
  for (const route of routes) {
    const url = baseUrl.replace(/\/$/, "") + route;
    const safeRoute = route === "/" ? "home" : route.replace(/^\//, "").replace(/[^\w-]+/g, "_");
    const screenshotPath = path.join(screenshotDir, `${safeRoute}.png`);
    const response = await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
    const statusCode = response ? response.status() : 0;
    const bodyText = await page.locator("body").innerText({ timeout: 10000 });
    await page.screenshot({ path: screenshotPath, fullPage: true });
    const hasExpectedText = bodyText.includes(appName) || bodyText.includes("Dashboard") || bodyText.includes("Login") || bodyText.includes("Settings") || bodyText.includes("Help");
    results.push({
      route,
      url,
      status_code: statusCode,
      title: await page.title(),
      screenshot_path: screenshotPath,
      body_text_length: bodyText.length,
      has_expected_text: hasExpectedText,
      passed: statusCode >= 200 && statusCode < 400 && hasExpectedText && fs.existsSync(screenshotPath)
    });
  }
  await browser.close();
  const passed = results.every((item) => item.passed) && pageErrors.length === 0;
  process.stdout.write(JSON.stringify({
    checked_at: new Date().toISOString(),
    app_name: appName,
    base_url: baseUrl,
    method: "playwright_chromium_screenshot",
    browser_visual_check: "passed",
    routes: results,
    console_errors: consoleErrors,
    page_errors: pageErrors,
    passed
  }, null, 2));
}

main().catch((error) => {
  process.stdout.write(JSON.stringify({
    checked_at: new Date().toISOString(),
    method: "playwright_chromium_screenshot",
    browser_visual_check: "failed",
    passed: false,
    error: error.message,
    stack: error.stack
  }, null, 2));
  process.exit(1);
});
'@
Set-Content -Path $runnerPath -Value $runner -Encoding UTF8

try {
    $server = Start-Process -FilePath "npm.cmd" -ArgumentList @("run", "dev", "--", "--port", "$Port") -WorkingDirectory $repoAbs -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr -WindowStyle Hidden -PassThru
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 1
        try {
            Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -TimeoutSec 5 | Out-Null
            $ready = $true
            break
        }
        catch {}
    }
    if (-not $ready) {
        throw "Preview server did not become reachable on $baseUrl"
    }

    $env:MIMTOD_APP_NAME = $appName
    $env:MIMTOD_BASE_URL = $baseUrl
    $env:MIMTOD_ROUTES_JSON = ($Routes | ConvertTo-Json -Compress)
    $env:MIMTOD_SCREENSHOT_DIR = $screenshotsDir
    $env:MIMTOD_REPO_ROOT = $repoAbs
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $jsonText = & node $runnerPath 2>&1 | Out-String
    $ErrorActionPreference = $previousErrorActionPreference
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $visual = $jsonText.Trim() | ConvertFrom-Json
    if ($exitCode -ne 0 -and -not $visual) {
        throw "Visual acceptance runner failed: $jsonText"
    }

    $acceptance = Get-Content -Path $acceptancePath -Raw | ConvertFrom-Json
    $acceptance | Add-Member -NotePropertyName visual_acceptance -NotePropertyValue $visual -Force
    if ([bool]$visual.passed) {
        $acceptance.gates.local_preview = "visual_acceptance_passed"
        $acceptance | Add-Member -NotePropertyName status -NotePropertyValue "visual_acceptance_passed" -Force
        $acceptance.tod_next_action = "Select a real preview deploy target or run app-specific interaction tests before production packaging."
    }
    else {
        $acceptance.gates.local_preview = "visual_acceptance_failed"
        $acceptance.tod_next_action = "Inspect screenshot and route errors, make the smallest UI/runtime repair, and rerun visual acceptance."
    }
    Set-Content -Path $acceptancePath -Value ($acceptance | ConvertTo-Json -Depth 30) -Encoding UTF8

    if (-not [bool]$visual.passed) {
        Write-Error ("Visual acceptance failed for {0}. Evidence: {1}" -f $slug, (ConvertTo-WorkspaceRelativePath -Path $acceptancePath))
    }

    [pscustomobject]@{
        status = if ([bool]$visual.passed) { "visual_acceptance_passed" } else { "visual_acceptance_failed" }
        app_name = $appName
        slug = $slug
        port = $Port
        routes = @($visual.routes).Count
        output_path = ConvertTo-WorkspaceRelativePath -Path $acceptancePath
        screenshots = ConvertTo-WorkspaceRelativePath -Path $screenshotsDir
    }
}
finally {
    Remove-Item Env:MIMTOD_APP_NAME -ErrorAction SilentlyContinue
    Remove-Item Env:MIMTOD_BASE_URL -ErrorAction SilentlyContinue
    Remove-Item Env:MIMTOD_ROUTES_JSON -ErrorAction SilentlyContinue
    Remove-Item Env:MIMTOD_SCREENSHOT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:MIMTOD_REPO_ROOT -ErrorAction SilentlyContinue
    if ($server -and (Get-Process -Id $server.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
    $conns = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
    foreach ($conn in $conns) {
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
    }
}
