Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. "$PSScriptRoot/mim_api_helpers.ps1"

function Get-MimHealth {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [int]$TimeoutSeconds = 15)
    return Invoke-MimApi -BaseUrl $BaseUrl -Method GET -Path "/health" -TimeoutSeconds $TimeoutSeconds
}

function Get-MimStatus {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [int]$TimeoutSeconds = 15)
    return Invoke-MimApi -BaseUrl $BaseUrl -Method GET -Path "/status" -TimeoutSeconds $TimeoutSeconds
}

function Get-MimManifest {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [int]$TimeoutSeconds = 15)
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method GET -Path "/manifest" -TimeoutSeconds $TimeoutSeconds
    return Normalize-MimManifestResponse -InputObject $response
}

function New-MimObjective {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [Parameter(Mandatory = $true)]$Objective, [int]$TimeoutSeconds = 15)
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method POST -Path "/objectives" -TimeoutSeconds $TimeoutSeconds -Body (Convert-ToMimObjective -Objective $Objective)
    return Normalize-MimObjectiveResponse -InputObject $response
}

function Get-MimObjectives {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [int]$TimeoutSeconds = 15)
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method GET -Path "/objectives" -TimeoutSeconds $TimeoutSeconds
    return @($response | ForEach-Object { Normalize-MimObjectiveResponse -InputObject $_ })
}

function New-MimTask {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)]$Task,
        [Nullable[int]]$RemoteObjectiveId = $null,
        [int]$TimeoutSeconds = 15
    )
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method POST -Path "/tasks" -TimeoutSeconds $TimeoutSeconds -Body (Convert-ToMimTask -Task $Task -RemoteObjectiveId $RemoteObjectiveId)
    return Normalize-MimTaskResponse -InputObject $response
}

function Get-MimTasks {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [string]$ObjectiveId, [int]$TimeoutSeconds = 15)

    $path = "/tasks"
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveId)) {
        $path = "/tasks?objective_id=$ObjectiveId"
    }

    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method GET -Path $path -TimeoutSeconds $TimeoutSeconds
    return @($response | ForEach-Object { Normalize-MimTaskResponse -InputObject $_ })
}

function New-MimResult {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$RemoteTaskId,
        [int]$TimeoutSeconds = 15
    )
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method POST -Path "/results" -TimeoutSeconds $TimeoutSeconds -Body (Convert-ToMimResult -Result $Result -RemoteTaskId $RemoteTaskId)
    return Normalize-MimResultResponse -InputObject $response
}

function New-MimReview {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)]$Review,
        [Parameter(Mandatory = $true)][int]$RemoteTaskId,
        [int]$TimeoutSeconds = 15
    )
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method POST -Path "/reviews" -TimeoutSeconds $TimeoutSeconds -Body (Convert-ToMimReview -Review $Review -RemoteTaskId $RemoteTaskId)
    return Normalize-MimReviewResponse -InputObject $response
}

function New-MimJournalEntry {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)]$Entry,
        [int]$TimeoutSeconds = 15
    )
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method POST -Path "/journal" -TimeoutSeconds $TimeoutSeconds -Body (Convert-ToMimJournalEntry -Entry $Entry)
    return Normalize-MimJournalResponse -InputObject $response
}

function Get-MimJournal {
    param([Parameter(Mandatory = $true)][string]$BaseUrl, [int]$Top = 25, [int]$TimeoutSeconds = 15)
    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method GET -Path "/journal?top=$Top" -TimeoutSeconds $TimeoutSeconds
    return @($response | ForEach-Object { Normalize-MimJournalResponse -InputObject $_ })
}

function New-MimExecutionFeedback {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ExecutionId,
        [Parameter(Mandatory = $true)][ValidateSet("accepted", "running", "succeeded", "failed", "blocked")][string]$Status,
        [string]$Source = "tod",
        [string]$TaskId = "",
        $Details,
        [string]$AuthToken,
        [int]$TimeoutSeconds = 15
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($AuthToken)) {
        $headers["Authorization"] = "Bearer $AuthToken"
    }

    $payload = [pscustomobject]@{
        status = [string]$Status
        source = [string]$Source
        task_id = [string]$TaskId
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        details = if ($null -ne $Details) { $Details } else { [pscustomobject]@{} }
    }

    $response = Invoke-MimApi -BaseUrl $BaseUrl -Method POST -Path "/gateway/capabilities/executions/$ExecutionId/feedback" -TimeoutSeconds $TimeoutSeconds -Body $payload -AdditionalHeaders $headers
    return $response
}
