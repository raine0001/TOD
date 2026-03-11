param(
    [int]$Port = 8844
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $repoRoot "ui"
$indexPath = Join-Path $uiRoot "index.html"
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"
$defaultLogPath = Join-Path $repoRoot "tod/out/mim-http.log"
$statePath = Join-Path $repoRoot "tod/data/state.json"

if (-not (Test-Path -Path $indexPath)) {
    throw "UI file not found at $indexPath"
}
if (-not (Test-Path -Path $todScript)) {
    throw "TOD script not found at $todScript"
}

$listener = $null
$activePort = $Port
$maxPortAttempts = 15
$started = $false

for ($i = 0; $i -lt $maxPortAttempts; $i++) {
    $candidatePort = $Port + $i
    $candidate = New-Object System.Net.HttpListener
    $candidate.Prefixes.Add("http://localhost:$candidatePort/")

    try {
        $candidate.Start()
        $listener = $candidate
        $activePort = $candidatePort
        $started = $true
        break
    }
    catch {
        $candidate.Close()
        if ($i -eq ($maxPortAttempts - 1)) {
            throw
        }
    }
}

if (-not $started -or $null -eq $listener) {
    throw "Failed to start TOD UI listener."
}

if ($activePort -ne $Port) {
    Write-Host "Requested port $Port was unavailable; using $activePort instead."
}

Write-Host "TOD UI running at http://localhost:$activePort/"
Write-Host "Press Ctrl+C to stop."

function Write-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $bytes.LongLength
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

function Get-RecentLogLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [int]$Tail = 80
    )

    if (-not (Test-Path -Path $LogPath)) {
        return @()
    }

    $safeTail = if ($Tail -lt 1) { 1 } elseif ($Tail -gt 500) { 500 } else { $Tail }
    return @(Get-Content -Path $LogPath -Tail $safeTail -ErrorAction SilentlyContinue)
}

function Get-TaskProgressWeight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    $normalized = $Status.Trim().ToLowerInvariant()
    switch ($normalized) {
        "pass" { return 1.0 }
        "reviewed_pass" { return 1.0 }
        "done" { return 1.0 }
        "completed" { return 1.0 }
        "implemented" { return 0.75 }
        "in_progress" { return 0.5 }
        "active" { return 0.5 }
        "revise" { return 0.35 }
        "planned" { return 0.15 }
        "open" { return 0.1 }
        default { return 0.0 }
    }
}

function Get-ProjectStatusPayload {
    param([string]$ObjectiveId)

    if (-not (Test-Path -Path $statePath)) {
        return [pscustomobject]@{
            ok = $true
            marker = $null
            objective_options = @()
            selected_objective_id = ""
            task_funnel = [pscustomobject]@{ total = 0; by_status = @{} }
            progress = [pscustomobject]@{
                percent = 0
                completed_equivalent = 0
                task_count = 0
                summary = "No state file found"
            }
        }
    }

    $rawState = Get-Content -Path $statePath -Raw
    $state = $rawState | ConvertFrom-Json
    $objectives = @($state.objectives)
    $tasks = @($state.tasks)

    $objectiveOptions = @($objectives | Sort-Object created_at -Descending | ForEach-Object {
            [pscustomobject]@{
                objective_id = [string]$_.id
                title = [string]$_.title
                status = [string]$_.status
                priority = [string]$_.priority
            }
        })

    if (@($objectiveOptions).Count -eq 0) {
        return [pscustomobject]@{
            ok = $true
            marker = $null
            objective_options = @()
            selected_objective_id = ""
            task_funnel = [pscustomobject]@{ total = 0; by_status = @{} }
            progress = [pscustomobject]@{
                percent = 0
                completed_equivalent = 0
                task_count = 0
                summary = "No objectives yet"
            }
        }
    }

    $marker = $null
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $selected = @($objectives | Where-Object { [string]$_.id -eq [string]$ObjectiveId } | Select-Object -First 1)
        if (@($selected).Count -gt 0) {
            $marker = $selected[0]
        }
    }
    if ($null -eq $marker) {
        $marker = @($objectives | Sort-Object created_at -Descending | Select-Object -First 1)[0]
    }

    $objectiveId = [string]$marker.id
    $objectiveTasks = @($tasks | Where-Object { [string]$_.objective_id -eq $objectiveId })
    $taskCount = @($objectiveTasks).Count

    $statusBreakdown = @{}
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "unknown" }
        $key = if ([string]::IsNullOrWhiteSpace($statusValue)) { "unknown" } else { $statusValue.Trim().ToLowerInvariant() }
        if (-not $statusBreakdown.ContainsKey($key)) {
            $statusBreakdown[$key] = 0
        }
        $statusBreakdown[$key] = [int]$statusBreakdown[$key] + 1
    }

    $progressUnits = 0.0
    foreach ($task in $objectiveTasks) {
        $statusValue = if ($task.PSObject.Properties["status"]) { [string]$task.status } else { "" }
        $progressUnits += (Get-TaskProgressWeight -Status $statusValue)
    }

    $percent = if ($taskCount -gt 0) {
        [int][math]::Round(($progressUnits / [double]$taskCount) * 100)
    }
    else {
        if (([string]$marker.status).ToLowerInvariant() -eq "open") { 0 } else { 100 }
    }

    $engineeringSignal = $null
    try {
        $signalRaw = & $todScript -Action "get-engineering-signal" -ConfigPath $configPath -Top 10
        $engineeringSignal = $signalRaw | ConvertFrom-Json
    }
    catch {
        $engineeringSignal = [pscustomobject]@{
            available = $false
            error = $_.Exception.Message
        }
    }

    return [pscustomobject]@{
        ok = $true
        objective_options = @($objectiveOptions)
        selected_objective_id = $objectiveId
        marker = [pscustomobject]@{
            objective_id = $objectiveId
            remote_objective_id = if ($marker.PSObject.Properties["remote_objective_id"]) { [string]$marker.remote_objective_id } else { "" }
            title = [string]$marker.title
            status = [string]$marker.status
            priority = [string]$marker.priority
            updated_at = if ($marker.PSObject.Properties["updated_at"]) { [string]$marker.updated_at } else { "" }
        }
        task_funnel = [pscustomobject]@{
            total = $taskCount
            by_status = [pscustomobject]$statusBreakdown
        }
        progress = [pscustomobject]@{
            percent = $percent
            completed_equivalent = [math]::Round($progressUnits, 2)
            task_count = $taskCount
            summary = "Objective ${objectiveId}: $percent%"
        }
        engineering_signal = $engineeringSignal
    }
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $path = $request.Url.AbsolutePath

        if ($request.HttpMethod -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html")) {
            $html = Get-Content -Path $indexPath -Raw
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $response.StatusCode = 200
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        if ($request.HttpMethod -eq "POST" -and $path -eq "/api/run") {
            try {
                $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $bodyRaw = $reader.ReadToEnd()
                $payload = if ([string]::IsNullOrWhiteSpace($bodyRaw)) { @{} } else { $bodyRaw | ConvertFrom-Json }

                $action = [string]$payload.action
                if ([string]::IsNullOrWhiteSpace($action)) {
                    throw "action is required"
                }

                $invokeParams = @{
                    Action = $action
                }

                if ($payload.PSObject.Properties["top"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.top)) {
                    $invokeParams.Top = [int]$payload.top
                }
                if ($payload.PSObject.Properties["category"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.category)) {
                    $invokeParams.Category = [string]$payload.category
                }
                if ($payload.PSObject.Properties["engine"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.engine)) {
                    $invokeParams.Engine = [string]$payload.engine
                }
                if ($payload.PSObject.Properties["configPath"] -and -not [string]::IsNullOrWhiteSpace([string]$payload.configPath)) {
                    $invokeParams.ConfigPath = [string]$payload.configPath
                }

                $output = & $todScript @invokeParams
                $parsed = $null
                try {
                    $parsed = $output | ConvertFrom-Json
                }
                catch {
                    $parsed = [pscustomobject]@{ raw = [string]$output }
                }

                $result = [pscustomobject]@{
                    ok = $true
                    result = $parsed
                }
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($result | ConvertTo-Json -Depth 22)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/logs") {
            try {
                $tailRaw = [string]$request.QueryString["tail"]
                $tail = 80
                if (-not [string]::IsNullOrWhiteSpace($tailRaw)) {
                    $parsedTail = 0
                    if ([int]::TryParse($tailRaw, [ref]$parsedTail)) {
                        $tail = $parsedTail
                    }
                }

                $lines = Get-RecentLogLines -LogPath $defaultLogPath -Tail $tail
                $entries = @()
                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) {
                        continue
                    }

                    try {
                        $entries += @($line | ConvertFrom-Json)
                    }
                    catch {
                        $entries += @([pscustomobject]@{ raw = [string]$line })
                    }
                }

                $payload = [pscustomobject]@{
                    ok = $true
                    log_path = $defaultLogPath
                    count = @($entries).Count
                    entries = @($entries)
                }
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 20)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        if ($request.HttpMethod -eq "GET" -and $path -eq "/api/project-status") {
            try {
                $objectiveId = [string]$request.QueryString["objective_id"]
                $payload = Get-ProjectStatusPayload -ObjectiveId $objectiveId
                Write-JsonResponse -Response $response -StatusCode 200 -Json ($payload | ConvertTo-Json -Depth 12)
            }
            catch {
                $errorPayload = [pscustomobject]@{
                    ok = $false
                    error = $_.Exception.Message
                }
                Write-JsonResponse -Response $response -StatusCode 400 -Json ($errorPayload | ConvertTo-Json -Depth 6)
            }
            continue
        }

        $response.StatusCode = 404
        $response.ContentType = "text/plain; charset=utf-8"
        $notFound = [System.Text.Encoding]::UTF8.GetBytes("Not found")
        $response.ContentLength64 = $notFound.LongLength
        $response.OutputStream.Write($notFound, 0, $notFound.Length)
        $response.Close()
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }
    $listener.Close()
}
