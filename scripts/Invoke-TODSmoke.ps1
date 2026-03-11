param(
    [int]$PreferredPort = 8844,
    [int]$MaxPortSearch = 30,
    [int]$Top = 10,
    [switch]$FailOnError
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

function Invoke-Json {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$Body
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return Invoke-RestMethod -Uri $Uri -Method $Method -TimeoutSec 20
    }

    return Invoke-RestMethod -Uri $Uri -Method $Method -ContentType "application/json" -Body $Body -TimeoutSec 20
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiScript = Join-Path $PSScriptRoot "Start-TOD-UI.ps1"
if (-not (Test-Path -Path $uiScript)) {
    throw "Missing UI script: $uiScript"
}

$port = Find-FreePort -Start $PreferredPort -MaxAttempts $MaxPortSearch
$baseUrl = "http://localhost:$port"
$server = $null

try {
    $server = Start-Process -FilePath powershell -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $uiScript,
        "-Port", [string]$port
    ) -PassThru

    Start-Sleep -Seconds 2

    $project = Invoke-Json -Uri "$baseUrl/api/project-status" -Method "Get" -Body ""
    $bus = Invoke-Json -Uri "$baseUrl/api/run" -Method "Post" -Body (@{ action = "get-state-bus"; top = $Top } | ConvertTo-Json -Depth 5)
    $reliability = Invoke-Json -Uri "$baseUrl/api/run" -Method "Post" -Body (@{ action = "get-reliability"; top = $Top } | ConvertTo-Json -Depth 5)
    $logs = Invoke-Json -Uri "$baseUrl/api/logs?tail=5" -Method "Get" -Body ""

    $result = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-smoke"
        port = $port
        base_url = $baseUrl
        checks = [pscustomobject]@{
            project_status_ok = [bool]$project.ok
            state_bus_ok = [bool]$bus.ok
            reliability_ok = [bool]$reliability.ok
            logs_ok = [bool]$logs.ok
        }
        facts = [pscustomobject]@{
            objective_count = if ($project.PSObject.Properties["objective_options"] -and $null -ne $project.objective_options) { [int]@($project.objective_options).Count } else { 0 }
            current_alert_state = if ($bus.PSObject.Properties["result"] -and $bus.result -and $bus.result.PSObject.Properties["system_posture"]) { [string]$bus.result.system_posture.current_alert_state } else { "unknown" }
            logs_tail_count = if ($logs.PSObject.Properties["count"]) { [int]$logs.count } else { 0 }
        }
    }

    $allOk = [bool]($result.checks.project_status_ok -and $result.checks.state_bus_ok -and $result.checks.reliability_ok -and $result.checks.logs_ok)
    $result | Add-Member -NotePropertyName passed_all -NotePropertyValue $allOk

    $json = $result | ConvertTo-Json -Depth 8
    Write-Output $json

    if ($FailOnError -and -not $allOk) {
        throw "TOD smoke checks reported one or more failures."
    }
}
finally {
    if ($null -ne $server) {
        try {
            Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        }
        catch {
        }
    }
}
