param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [int]$Port = 3225,

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
$appName = [string]$manifest.app_name

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

$serverOut = Join-Path $outputDir "interaction-server.out.log"
$serverErr = Join-Path $outputDir "interaction-server.err.log"
$runnerPath = Join-Path $outputDir "interaction-acceptance-runner.cjs"
$baseUrl = "http://localhost:$Port"
$server = $null

$runner = @'
const fs = require("fs");
const path = require("path");
const repoRoot = process.env.MIMTOD_REPO_ROOT;
const { chromium } = require(require.resolve("playwright", { paths: [repoRoot] }));

async function main() {
  const baseUrl = process.env.MIMTOD_BASE_URL;
  const screenshotDir = process.env.MIMTOD_SCREENSHOT_DIR;
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
  const consoleErrors = [];
  const pageErrors = [];
  page.on("console", (message) => {
    if (message.type() === "error") consoleErrors.push(message.text());
  });
  page.on("pageerror", (error) => pageErrors.push(error.message));

  await page.goto(baseUrl.replace(/\/$/, "") + "/dashboard", { waitUntil: "networkidle", timeout: 30000 });
  const initialRows = await page.locator("tbody tr").count();
  await page.locator("button.primary").click();
  await page.locator('[data-testid="workflow-message"]').waitFor({ state: "visible", timeout: 10000 });
  const afterAddRows = await page.locator("tbody tr").count();
  const addMessage = await page.locator('[data-testid="workflow-message"]').innerText();
  await page.getByText("Move to waiting", { exact: true }).click();
  const moveMessage = await page.locator('[data-testid="workflow-message"]').innerText();
  await page.getByText("Complete first", { exact: true }).click();
  const completeMessage = await page.locator('[data-testid="workflow-message"]').innerText();
  const completeCells = await page.locator("td", { hasText: "complete" }).count();
  const screenshotPath = path.join(screenshotDir, "interaction-dashboard.png");
  await page.screenshot({ path: screenshotPath, fullPage: true });
  await browser.close();
  const checks = {
    initial_rows_present: initialRows >= 2,
    add_increased_rows: afterAddRows === initialRows + 1,
    add_message_changed: addMessage.toLowerCase().includes("added"),
    move_message_changed: moveMessage.toLowerCase().includes("waiting"),
    complete_message_changed: completeMessage.toLowerCase().includes("completed"),
    complete_status_visible: completeCells >= 1,
    screenshot_written: fs.existsSync(screenshotPath),
    no_page_errors: pageErrors.length === 0
  };
  const passed = Object.values(checks).every(Boolean);
  process.stdout.write(JSON.stringify({
    checked_at: new Date().toISOString(),
    method: "playwright_dashboard_interaction",
    route: "/dashboard",
    initial_rows: initialRows,
    after_add_rows: afterAddRows,
    messages: { add: addMessage, move: moveMessage, complete: completeMessage },
    checks,
    console_errors: consoleErrors,
    page_errors: pageErrors,
    screenshot_path: screenshotPath,
    passed
  }, null, 2));
}

main().catch((error) => {
  process.stdout.write(JSON.stringify({
    checked_at: new Date().toISOString(),
    method: "playwright_dashboard_interaction",
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

    $env:MIMTOD_BASE_URL = $baseUrl
    $env:MIMTOD_SCREENSHOT_DIR = $screenshotsDir
    $env:MIMTOD_REPO_ROOT = $repoAbs
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $jsonText = & node $runnerPath 2>&1 | Out-String
    $ErrorActionPreference = $previousErrorActionPreference
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    $interaction = $jsonText.Trim() | ConvertFrom-Json
    if ($exitCode -ne 0 -and -not $interaction) {
        throw "Interaction acceptance runner failed: $jsonText"
    }

    $acceptance = Get-Content -Path $acceptancePath -Raw | ConvertFrom-Json
    $acceptance | Add-Member -NotePropertyName interaction_acceptance -NotePropertyValue $interaction -Force
    $interactionPreviewGate = if ([bool]$interaction.passed) { "passed" } else { "failed" }
    $acceptance.gates | Add-Member -NotePropertyName interaction_preview -NotePropertyValue $interactionPreviewGate -Force
    if ([bool]$interaction.passed) {
        $acceptance.status = "interaction_acceptance_passed"
        $acceptance.tod_next_action = "Select a real preview deploy target, then run hosted preview acceptance before production packaging."
    }
    else {
        $acceptance.status = "interaction_acceptance_failed"
        $acceptance.tod_next_action = "Repair dashboard interaction behavior and rerun interaction acceptance."
    }
    Set-Content -Path $acceptancePath -Value ($acceptance | ConvertTo-Json -Depth 30) -Encoding UTF8

    if (-not [bool]$interaction.passed) {
        Write-Error ("Interaction acceptance failed for {0}. Evidence: {1}" -f $slug, (ConvertTo-WorkspaceRelativePath -Path $acceptancePath))
    }

    [pscustomobject]@{
        status = $acceptance.status
        app_name = $appName
        slug = $slug
        port = $Port
        output_path = ConvertTo-WorkspaceRelativePath -Path $acceptancePath
        screenshot = ConvertTo-WorkspaceRelativePath -Path ([string]$interaction.screenshot_path)
    }
}
finally {
    Remove-Item Env:MIMTOD_BASE_URL -ErrorAction SilentlyContinue
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
