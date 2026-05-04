Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TodUiBaseUrl {
    $candidates = @()

    if ($env:TOD_UI_BASE_URL) {
        $candidates += [string]$env:TOD_UI_BASE_URL
    }

    $candidates += @(
        'http://localhost:18846',
        'http://localhost:8844'
    )

    foreach ($candidate in $candidates | Select-Object -Unique) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri ("$candidate/api/mim-command") -Method Post -ContentType 'application/json' -Body '{}' -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return $candidate
            }
        }
        catch {
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -ne 404) {
                    return $candidate
                }
            }
        }
    }

    return 'http://localhost:18846'
}

$baseUrl = Get-TodUiBaseUrl

function Invoke-TodJsonPost {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 10
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

Describe 'MIM command panel backend contract' {
    It 'returns a structured MIM-first reply contract with session and request ids' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $payload = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Summarize the current operating state for the human.'
            intent = 'summarize_status'
            window_minutes = 10
        }

        $payload.ok | Should Be $true
        [string]$payload.session_id | Should Not BeNullOrEmpty
        [string]$payload.request_id | Should Not BeNullOrEmpty
        $payload.result | Should Not BeNullOrEmpty
        [string]$payload.result.source_label | Should Be 'MIM'
        [string]$payload.result.session_id | Should Be ([string]$payload.session_id)
        [string]$payload.result.contract.request_id | Should Not BeNullOrEmpty
        [string]$payload.result.contract.summary | Should Not BeNullOrEmpty
        [string]$payload.result.contract.understanding | Should Not BeNullOrEmpty
        [string]$payload.result.contract.next_action | Should Not BeNullOrEmpty
        ((@('doing', 'blocked', 'deferred', 'done') -contains [string]$payload.result.contract.execution_state)) | Should Be $true
    }

    It 'reuses the same dialog session across multiple turns when session_id is supplied' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $first = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Summarize the current operating state for the human.'
            intent = 'summarize_status'
            window_minutes = 10
        }

        if (-not $first.ok -or [string]::IsNullOrWhiteSpace([string]$first.session_id)) {
            return
        }

        $second = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Choose the next bounded action and explain why.'
            intent = 'suggest_next_action'
            window_minutes = 10
            session_id = [string]$first.session_id
        }

        $second.ok | Should Be $true
        [string]$second.session_id | Should Be ([string]$first.session_id)
        [string]$second.result.session_id | Should Be ([string]$first.session_id)
        [string]$second.request_id | Should Not BeNullOrEmpty
        [string]$second.result.contract.request_id | Should Not BeNullOrEmpty
        [string]$second.result.contract.summary | Should Not BeNullOrEmpty
    }

    It 'returns a blocked reply contract on the same session flow when the blocked harness is active' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $first = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Summarize the current operating state for the human.'
            intent = 'summarize_status'
            window_minutes = 10
            validation_harness = 'blocked_mim_command'
        }

        $second = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'What is blocked right now and why?'
            intent = 'explain_warning'
            window_minutes = 10
            validation_harness = 'blocked_mim_command'
            session_id = [string]$first.session_id
        }

        $second.ok | Should Be $true
        [string]$second.session_id | Should Be ([string]$first.session_id)
        [string]$second.result.contract.execution_state | Should Be 'blocked'
        [string]$second.result.contract.blocker | Should Not BeNullOrEmpty
        [string]$second.result.contract.summary | Should Match 'Blocked by validation harness'
    }

    It 'returns a doing reply contract on the same session flow when the doing harness is active' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $first = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Summarize the current operating state for the human.'
            intent = 'summarize_status'
            window_minutes = 10
            validation_harness = 'doing_mim_command'
        }

        $second = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Choose the next bounded action and explain why.'
            intent = 'suggest_next_action'
            window_minutes = 10
            validation_harness = 'doing_mim_command'
            session_id = [string]$first.session_id
        }

        $second.ok | Should Be $true
        [string]$second.session_id | Should Be ([string]$first.session_id)
        [string]$second.result.contract.execution_state | Should Be 'doing'
        [string]$second.result.contract.result | Should Not BeNullOrEmpty
        [string]$second.result.contract.next_action | Should Not BeNullOrEmpty
        [string]$second.result.contract.summary | Should Match 'Doing by validation harness'
    }

    It 'returns a done reply contract on the same session flow when the done harness is active' {
        if (-not (Test-TodUiReachable)) {
            return
        }

        $first = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Summarize the current operating state for the human.'
            intent = 'summarize_status'
            window_minutes = 10
            validation_harness = 'done_mim_command'
        }

        $second = Invoke-TodJsonPost -Path '/api/mim-command' -Body @{
            query = 'Summarize the current objective completion and final result.'
            intent = 'summarize_current_objective'
            window_minutes = 10
            validation_harness = 'done_mim_command'
            session_id = [string]$first.session_id
        }

        $second.ok | Should Be $true
        [string]$second.session_id | Should Be ([string]$first.session_id)
        [string]$second.result.contract.execution_state | Should Be 'done'
        [string]$second.result.contract.result | Should Not BeNullOrEmpty
        [string]$second.result.contract.next_action | Should Not BeNullOrEmpty
        [string]$second.result.contract.summary | Should Match 'Done by validation harness'
    }
}
