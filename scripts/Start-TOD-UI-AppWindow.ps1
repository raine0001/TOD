param(
    [int]$PreferredPort = 8844,
    [int]$MaxPortSearch = 30,
    [switch]$HideMenuBar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$startUiScript = Join-Path $PSScriptRoot "Start-TOD-UI.ps1"

if (-not (Test-Path -Path $startUiScript)) {
    throw "Missing script: $startUiScript"
}

function Test-PortFree {
    param([int]$Port)

    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        return ($null -eq $conn)
    }
    catch {
        return $true
    }
}

function Find-FreePort {
    param(
        [int]$Start,
        [int]$MaxAttempts
    )

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        $candidate = $Start + $i
        if (Test-PortFree -Port $candidate) {
            return $candidate
        }
    }

    throw "No free port found from $Start to $($Start + $MaxAttempts - 1)."
}

$port = Find-FreePort -Start $PreferredPort -MaxAttempts $MaxPortSearch
$url = "http://localhost:$port/"

Write-Host "Starting TOD UI server on $url" -ForegroundColor Cyan

$serverArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $startUiScript,
    "-Port", "$port",
    "-NoAutoOpen"
)

$serverProc = Start-Process -FilePath "powershell" -ArgumentList $serverArgs -PassThru -WindowStyle Normal

$ready = $false
for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 250
    try {
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) {
            $ready = $true
            break
        }
    }
    catch {
    }
}

if (-not $ready) {
    if ($serverProc -and -not $serverProc.HasExited) {
        Stop-Process -Id $serverProc.Id -Force
    }
    throw "TOD UI server did not become ready at $url"
}

Write-Host "Opening TOD app window..." -ForegroundColor Green

$form = New-Object System.Windows.Forms.Form
$form.Text = "TOD Command Console"
$form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = [System.Drawing.Color]::Black
$form.KeyPreview = $true

$browser = New-Object System.Windows.Forms.WebBrowser
$browser.Dock = [System.Windows.Forms.DockStyle]::Fill
$browser.ScriptErrorsSuppressed = $true
$browser.Url = $url
$form.Controls.Add($browser)

if ($HideMenuBar) {
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    $form.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $form.Close()
        }
    })
}

$form.Add_FormClosed({
    if ($serverProc -and -not $serverProc.HasExited) {
        Stop-Process -Id $serverProc.Id -Force
    }
})

[void]$form.ShowDialog()
