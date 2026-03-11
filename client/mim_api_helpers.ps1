Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:MimApiDebugEnabled = $false
$script:MimApiDebugLogPath = Join-Path (Split-Path -Parent $PSScriptRoot) "tod/out/mim-http.log"

function Set-MimApiDebugLogging {
    param(
        [bool]$Enabled = $false,
        [string]$LogPath
    )

    $script:MimApiDebugEnabled = [bool]$Enabled
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $script:MimApiDebugLogPath = $LogPath
    }
}

function Convert-MimResponseToLogValue {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    try {
        return (($Value | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json)
    }
    catch {
        return [string]$Value
    }
}

function Get-MimHttpErrorBody {
    param([Parameter(Mandatory = $true)]$Exception)

    $stream = $null
    try {
        if ($Exception.PSObject.Properties["Response"] -and $null -ne $Exception.Response -and $Exception.Response.GetResponseStream) {
            $stream = $Exception.Response.GetResponseStream()
            if ($null -ne $stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $text = $reader.ReadToEnd()
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    return $text
                }
            }
        }
    }
    catch {
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    return ""
}

function Write-MimApiDebugLog {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Entry
    )

    if (-not $script:MimApiDebugEnabled) {
        return
    }

    $line = $null
    try {
        $line = ($Entry | ConvertTo-Json -Depth 20 -Compress)
    }
    catch {
        return
    }

    $logDir = Split-Path -Parent $script:MimApiDebugLogPath
    if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Add-Content -Path $script:MimApiDebugLogPath -Value $line
}

function Normalize-MimBaseUrl {
    param([Parameter(Mandatory = $true)][string]$BaseUrl)
    return $BaseUrl.TrimEnd("/")
}

function New-MimRequestHeaders {
    return @{ "Content-Type" = "application/json" }
}

function Invoke-MimApi {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 15,
        $Body,
        [hashtable]$AdditionalHeaders
    )

    $base = Normalize-MimBaseUrl -BaseUrl $BaseUrl
    $uri = "{0}{1}" -f $base, $Path
    $headers = New-MimRequestHeaders
    if ($null -ne $AdditionalHeaders) {
        foreach ($key in $AdditionalHeaders.Keys) {
            $headers[[string]$key] = [string]$AdditionalHeaders[$key]
        }
    }

    $jsonBody = $null
    if ($null -ne $Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 12
    }

    $start = Get-Date
    try {
        $response = $null
        if ($Method -eq "GET") {
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -TimeoutSec $TimeoutSeconds
        }
        else {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -TimeoutSec $TimeoutSeconds -Body $jsonBody
        }

        Write-MimApiDebugLog -Entry @{
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            request = @{
                method = $Method
                uri = $uri
                timeout_seconds = $TimeoutSeconds
                body = if ($null -ne $jsonBody) { $jsonBody } else { $null }
            }
            response = @{
                status_code = 200
                body = Convert-MimResponseToLogValue -Value $response
            }
            elapsed_ms = [int]((Get-Date) - $start).TotalMilliseconds
        }

        return $response
    }
    catch {
        $statusCode = $null
        if ($_.Exception.PSObject.Properties["Response"] -and $null -ne $_.Exception.Response -and $_.Exception.Response.PSObject.Properties["StatusCode"]) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        Write-MimApiDebugLog -Entry @{
            timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
            request = @{
                method = $Method
                uri = $uri
                timeout_seconds = $TimeoutSeconds
                body = if ($null -ne $jsonBody) { $jsonBody } else { $null }
            }
            response = @{
                status_code = $statusCode
                error = $_.Exception.Message
                error_body = (Get-MimHttpErrorBody -Exception $_.Exception)
            }
            elapsed_ms = [int]((Get-Date) - $start).TotalMilliseconds
        }

        throw
    }
}

function Convert-ToMimObjective {
    param([Parameter(Mandatory = $true)]$Objective)

    return [pscustomobject]@{
        title = $Objective.title
        description = $Objective.description
        priority = $Objective.priority
        constraints = @($Objective.constraints)
        success_criteria = (@($Objective.success_criteria) -join "; ")
        status = $Objective.status
    }
}

function Convert-ToIntList {
    param($Values)

    $result = @()
    foreach ($value in (Convert-ToArray -Value $Values)) {
        $parsed = 0
        if ([int]::TryParse([string]$value, [ref]$parsed)) {
            $result += $parsed
        }
    }
    return @($result)
}

function Convert-ToMimTask {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Nullable[int]]$RemoteObjectiveId = $null
    )

    return [pscustomobject]@{
        title = $Task.title
        scope = $Task.scope
        dependencies = @(Convert-ToIntList -Values $Task.dependencies)
        acceptance_criteria = (@($Task.acceptance_criteria) -join "; ")
        status = $Task.status
        assigned_to = $Task.assigned_executor
        objective_id = $RemoteObjectiveId
    }
}

function Convert-ToMimResult {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$RemoteTaskId
    )

    return [pscustomobject]@{
        task_id = $RemoteTaskId
        summary = $Result.summary
        files_changed = @($Result.files_changed)
        tests_run = @($Result.tests_run)
        test_results = (@($Result.test_results) -join "; ")
        failures = @($Result.failures)
        recommendations = (@($Result.recommendations) -join "; ")
    }
}

function Convert-ToMimReview {
    param(
        [Parameter(Mandatory = $true)]$Review,
        [Parameter(Mandatory = $true)][int]$RemoteTaskId
    )

    return [pscustomobject]@{
        task_id = $RemoteTaskId
        decision = $Review.decision
        rationale = $Review.rationale
        continue_allowed = ($Review.decision -eq "pass")
        escalate_to_user = ($Review.decision -eq "escalate")
    }
}

function Convert-ToMimJournalEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    return [pscustomobject]@{
        actor = [string](Get-OptionalProperty -Object $Entry -Name "actor" -Default "tod")
        action = [string](Get-OptionalProperty -Object $Entry -Name "action" -Default "sync_mim")
        target_type = [string](Get-OptionalProperty -Object $Entry -Name "target_type" -Default "sync_state")
        target_id = [string](Get-OptionalProperty -Object $Entry -Name "target_id" -Default "sync_state")
        summary = [string](Get-OptionalProperty -Object $Entry -Name "summary" -Default "")
    }
}

function Convert-ToArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return @($Value) }
    return @($Value)
}

function Get-OptionalProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) {
        return $prop.Value
    }
    return $Default
}

function Normalize-MimObjectiveResponse {
    param([Parameter(Mandatory = $true)]$InputObject)

    $objectiveId = Get-OptionalProperty -Object $InputObject -Name "objective_id" -Default (Get-OptionalProperty -Object $InputObject -Name "id" -Default "")
    $priority = Get-OptionalProperty -Object $InputObject -Name "priority" -Default "unknown"
    $constraints = Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "constraints" -Default @())
    $successCriteria = Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "success_criteria" -Default @())
    $status = Get-OptionalProperty -Object $InputObject -Name "status" -Default (Get-OptionalProperty -Object $InputObject -Name "state" -Default "unknown")

    return [pscustomobject]@{
        objective_id = [string]$objectiveId
        title = [string](Get-OptionalProperty -Object $InputObject -Name "title" -Default "")
        description = [string](Get-OptionalProperty -Object $InputObject -Name "description" -Default "")
        priority = [string]$priority
        constraints = @($constraints)
        success_criteria = @($successCriteria)
        status = [string]$status
        created_at = [string](Get-OptionalProperty -Object $InputObject -Name "created_at" -Default "")
    }
}

function Normalize-MimTaskResponse {
    param([Parameter(Mandatory = $true)]$InputObject)

    $taskId = Get-OptionalProperty -Object $InputObject -Name "task_id" -Default (Get-OptionalProperty -Object $InputObject -Name "id" -Default "")
    $status = Get-OptionalProperty -Object $InputObject -Name "status" -Default (Get-OptionalProperty -Object $InputObject -Name "state" -Default "unknown")
    $assignedTo = Get-OptionalProperty -Object $InputObject -Name "assigned_to" -Default (Get-OptionalProperty -Object $InputObject -Name "assigned_executor" -Default "")

    return [pscustomobject]@{
        task_id = [string]$taskId
        objective_id = [string](Get-OptionalProperty -Object $InputObject -Name "objective_id" -Default "")
        title = [string](Get-OptionalProperty -Object $InputObject -Name "title" -Default "")
        scope = [string](Get-OptionalProperty -Object $InputObject -Name "scope" -Default "")
        dependencies = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "dependencies" -Default @()))
        acceptance_criteria = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "acceptance_criteria" -Default @()))
        status = [string]$status
        assigned_to = [string]$assignedTo
    }
}

function Normalize-MimResultResponse {
    param([Parameter(Mandatory = $true)]$InputObject)

    $resultId = Get-OptionalProperty -Object $InputObject -Name "result_id" -Default (Get-OptionalProperty -Object $InputObject -Name "id" -Default "")

    return [pscustomobject]@{
        result_id = [string]$resultId
        task_id = [string](Get-OptionalProperty -Object $InputObject -Name "task_id" -Default "")
        summary = [string](Get-OptionalProperty -Object $InputObject -Name "summary" -Default "")
        files_changed = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "files_changed" -Default @()))
        tests_run = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "tests_run" -Default @()))
        test_results = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "test_results" -Default @()))
        failures = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "failures" -Default @()))
        recommendations = @(Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "recommendations" -Default @()))
        engine_metadata = Get-OptionalProperty -Object $InputObject -Name "engine_metadata" -Default $null
        created_at = [string](Get-OptionalProperty -Object $InputObject -Name "created_at" -Default "")
    }
}

function Normalize-MimReviewResponse {
    param([Parameter(Mandatory = $true)]$InputObject)

    $reviewId = Get-OptionalProperty -Object $InputObject -Name "review_id" -Default (Get-OptionalProperty -Object $InputObject -Name "id" -Default "")
    $decision = [string](Get-OptionalProperty -Object $InputObject -Name "decision" -Default "")
    $continueAllowed = Get-OptionalProperty -Object $InputObject -Name "continue_allowed" -Default ($decision -eq "pass")
    $escalateToUser = Get-OptionalProperty -Object $InputObject -Name "escalate_to_user" -Default ($decision -eq "escalate")

    return [pscustomobject]@{
        review_id = [string]$reviewId
        task_id = [string](Get-OptionalProperty -Object $InputObject -Name "task_id" -Default "")
        decision = $decision
        rationale = [string](Get-OptionalProperty -Object $InputObject -Name "rationale" -Default "")
        continue_allowed = [bool]$continueAllowed
        escalate_to_user = [bool]$escalateToUser
        created_at = [string](Get-OptionalProperty -Object $InputObject -Name "created_at" -Default "")
    }
}

function Normalize-MimJournalResponse {
    param([Parameter(Mandatory = $true)]$InputObject)

    $entryId = Get-OptionalProperty -Object $InputObject -Name "entry_id" -Default (Get-OptionalProperty -Object $InputObject -Name "id" -Default "")
    $targetType = Get-OptionalProperty -Object $InputObject -Name "target_type" -Default (Get-OptionalProperty -Object $InputObject -Name "entity_type" -Default "")
    $targetId = Get-OptionalProperty -Object $InputObject -Name "target_id" -Default (Get-OptionalProperty -Object $InputObject -Name "entity_id" -Default "")
    $timestamp = Get-OptionalProperty -Object $InputObject -Name "timestamp" -Default (Get-OptionalProperty -Object $InputObject -Name "created_at" -Default "")

    return [pscustomobject]@{
        entry_id = [string]$entryId
        actor = [string](Get-OptionalProperty -Object $InputObject -Name "actor" -Default "")
        action = [string](Get-OptionalProperty -Object $InputObject -Name "action" -Default "")
        target_type = [string]$targetType
        target_id = [string]$targetId
        summary = [string](Get-OptionalProperty -Object $InputObject -Name "summary" -Default "")
        timestamp = [string]$timestamp
    }
}

function Normalize-MimManifestResponse {
    param([Parameter(Mandatory = $true)]$InputObject)

    $capabilities = Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "capabilities" -Default @())
    $recentChanges = Convert-ToArray -Value (Get-OptionalProperty -Object $InputObject -Name "recent_changes" -Default @())

    return [pscustomobject]@{
        system_name = [string](Get-OptionalProperty -Object $InputObject -Name "system_name" -Default "")
        system_version = [string](Get-OptionalProperty -Object $InputObject -Name "system_version" -Default "")
        contract_version = [string](Get-OptionalProperty -Object $InputObject -Name "contract_version" -Default "")
        schema_version = [string](Get-OptionalProperty -Object $InputObject -Name "schema_version" -Default "")
        repo_signature = [string](Get-OptionalProperty -Object $InputObject -Name "repo_signature" -Default "")
        capabilities = @($capabilities)
        recent_changes = @($recentChanges)
        last_updated_at = [string](Get-OptionalProperty -Object $InputObject -Name "last_updated_at" -Default "")
        generated_at = [string](Get-OptionalProperty -Object $InputObject -Name "generated_at" -Default "")
    }
}
