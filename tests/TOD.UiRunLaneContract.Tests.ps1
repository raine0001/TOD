Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$baseUrl = if ([string]::IsNullOrWhiteSpace($env:TOD_UI_BASE_URL)) { 'http://localhost:8844' } else { [string]$env:TOD_UI_BASE_URL.TrimEnd('/') }
$listenerRequestPath = Join-Path $repoRoot 'tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json'
$configPath = Join-Path $repoRoot 'tod/config/tod-config.json'

function Invoke-TodJsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TodJsonPostAllowError {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 30
        return [pscustomobject]@{
            status_code = [int]$response.StatusCode
            content = [string]$response.Content
        }
    }
    catch [System.Net.WebException] {
        if ($null -eq $_.Exception.Response) {
            throw
        }

        $response = $_.Exception.Response
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try {
            return [pscustomobject]@{
                status_code = [int]$response.StatusCode
                content = $reader.ReadToEnd()
            }
        }
        finally {
            $reader.Dispose()
            $response.Dispose()
        }
    }
}

function Test-TodUiReachable {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/api/project-status" -TimeoutSec 5
        return $response.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

function Backup-PathContent {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    return [pscustomobject]@{
        path = $PathValue
        exists = (Test-Path -Path $PathValue -PathType Leaf)
        content = if (Test-Path -Path $PathValue -PathType Leaf) { [string](Get-Content -Path $PathValue -Raw) } else { '' }
    }
}

function Restore-PathContent {
    param([Parameter(Mandatory = $true)]$Backup)

    if ([bool]$Backup.exists) {
        $directory = Split-Path -Parent ([string]$Backup.path)
        if (-not (Test-Path -Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText([string]$Backup.path, [string]$Backup.content, $utf8NoBom)
    }
    elseif (Test-Path -Path ([string]$Backup.path)) {
        Remove-Item -Path ([string]$Backup.path) -Force
    }
}

Describe 'TOD /api/run lane contract' {
    It 'executes bridge requests through run-bridge-request and rejects mixed-lane payloads' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $requestBackup = Backup-PathContent -PathValue $listenerRequestPath
        try {
            Write-JsonNoBom -PathValue $listenerRequestPath -Payload ([pscustomobject]@{
                request_id = 'objective-500-task-001'
                task_id = 'objective-500-task-001'
                objective_id = 'objective-500'
                target = 'TOD'
                tod_action = 'get-state-bus'
                generated_at = (Get-Date).ToUniversalTime().ToString('o')
            })

            $bridgePayload = Invoke-TodJsonPost -Path '/api/run' -Body @{
                action = 'run-bridge-request'
                requestId = 'objective-500-task-001'
                configPath = $configPath
            }

            $bridgePayload.ok | Should Be $true
            [string]$bridgePayload.result.request_id | Should Be 'objective-500-task-001'
            [string]$bridgePayload.result.execution_lane | Should Be 'bridge_request'
            [bool]$bridgePayload.result.mim_task_lookup_used | Should Be $false
            [string]$bridgePayload.result.execution.action | Should Be 'get-state-bus'

            $mixedRunTask = Invoke-TodJsonPostAllowError -Path '/api/run' -Body @{
                action = 'run-task'
                taskId = '45'
                requestId = 'objective-500-task-001'
                configPath = $configPath
            }

            [int]$mixedRunTask.status_code | Should Be 400

            $mixedBridgeRun = Invoke-TodJsonPostAllowError -Path '/api/run' -Body @{
                action = 'run-bridge-request'
                taskId = '45'
                requestId = 'objective-500-task-001'
                configPath = $configPath
            }

            [int]$mixedBridgeRun.status_code | Should Be 400
        }
        finally {
            Restore-PathContent -Backup $requestBackup
        }
    }
}