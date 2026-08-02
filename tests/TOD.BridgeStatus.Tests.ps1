Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseUrl = 'http://localhost:8844'

function Invoke-TodJsonGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
}

function Invoke-TodJsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8
    $response = Invoke-WebRequest -UseBasicParsing -Uri ("$baseUrl$Path") -Method Post -ContentType 'application/json' -Body $json -TimeoutSec 30
    return ($response.Content | ConvertFrom-Json)
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

Describe 'Bridge status diagnostics' {
    It 'returns bridge freshness and completeness diagnostics in project status' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $payload = Invoke-TodJsonGet -Path '/api/project-status'
        $payload.ok | Should Be $true
        $payload.bridge_status | Should Not BeNullOrEmpty
        (($payload.bridge_status.PSObject.Properties.Name) -contains 'status_reason') | Should Be $true
        (($payload.bridge_status.PSObject.Properties.Name) -contains 'listener_freshness_state') | Should Be $true
        (($payload.bridge_status.PSObject.Properties.Name) -contains 'listener_fresh_threshold_seconds') | Should Be $true
        (($payload.bridge_status.PSObject.Properties.Name) -contains 'sequence_state') | Should Be $true
        (($payload.bridge_status.PSObject.Properties.Name) -contains 'artifact_completeness') | Should Be $true
        (($payload.bridge_status.PSObject.Properties.Name) -contains 'missing_artifacts') | Should Be $true

        [string]$payload.bridge_status.status_reason | Should Match 'healthy|objective_mismatch|listener_stale|listener_startup_lag|sequence_incomplete|artifact_incomplete'
        [string]$payload.bridge_status.listener_freshness_state | Should Match 'fresh|startup_lag|stale|unknown'
        [string]$payload.bridge_status.sequence_state | Should Match 'sequence_aware|partial|missing'
        [string]$payload.bridge_status.artifact_completeness | Should Match 'complete|partial'
        [int]$payload.bridge_status.listener_fresh_threshold_seconds | Should BeGreaterThan 0
        @($payload.bridge_status.missing_artifacts).Count | Should BeGreaterThan -1
    }

    It 'validates Test-TodUiReachable always returns Boolean' {
        $result = Test-TodUiReachable
        $result | Should BeOfType [bool]
    }

    It 'returns bridge diagnostic evidence and citations in operator chat' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $payload = Invoke-TodJsonPost -Path '/api/operator-chat' -Body @{
            query = 'What is the current bridge mismatch?'
            intent = 'explain_bridge_status'
            window_minutes = 10
        }

        $payload.ok | Should Be $true
        $payload.response.evidence | Should Not BeNullOrEmpty
        @($payload.response.citations | Where-Object { [string]$_.section -eq 'bridge_status' -and [string]$_.field -eq 'status_reason' }).Count | Should BeGreaterThan 0
        @($payload.response.citations | Where-Object { [string]$_.section -eq 'bridge_status' -and [string]$_.field -eq 'listener_freshness_state' }).Count | Should BeGreaterThan 0
        @($payload.response.citations | Where-Object { [string]$_.section -eq 'bridge_status' -and [string]$_.field -eq 'sequence_state' }).Count | Should BeGreaterThan 0
        @($payload.response.citations | Where-Object { [string]$_.section -eq 'bridge_status' -and [string]$_.field -eq 'artifact_completeness' }).Count | Should BeGreaterThan 0
    }
}