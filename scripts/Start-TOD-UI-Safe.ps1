param(
    [int]$PreferredPort = 8844,
    [int]$MaxPortSearch = 30,
    [switch]$OpenAppWindow,
    [switch]$NoAutoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

$startScript = Join-Path $PSScriptRoot "Start-TOD-UI.ps1"
if (-not (Test-Path -Path $startScript)) {
    throw "Missing script: $startScript"
}

$selectedPort = Find-FreePort -Start $PreferredPort -MaxAttempts $MaxPortSearch
Write-Host "Launching TOD UI on port $selectedPort"
Write-Host "URL: http://localhost:$selectedPort/"

$invokeArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $startScript,
    "-Port", "$selectedPort"
)

if ($OpenAppWindow) {
    $invokeArgs += "-OpenAppWindow"
}
if ($NoAutoOpen) {
    $invokeArgs += "-NoAutoOpen"
}

powershell @invokeArgs
