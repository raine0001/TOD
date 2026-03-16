param(
    [Parameter(Mandatory = $true)][string]$RequestId,
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$GoOrderPath,
    [Parameter(Mandatory = $true)][string]$ReviewDecisionPath,
    [Parameter(Mandatory = $true)][string]$IntegrationStatusPath,
    [Parameter(Mandatory = $true)][string]$ResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-Json {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) {
        throw "Required JSON file not found: $PathValue"
    }
    return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
}

function Test-AlignmentEquivalent {
    param(
        [string]$Actual,
        [string]$Expected
    )

    $actualNorm = ([string]$Actual).Trim().ToLowerInvariant()
    $expectedNorm = ([string]$Expected).Trim().ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($expectedNorm)) { return $true }
    if ($actualNorm -eq $expectedNorm) { return $true }
    if ($expectedNorm -eq "aligned" -and @("aligned", "in_sync") -contains $actualNorm) { return $true }
    return $false
}

function Get-ExpectedObjectiveFromRequest {
    param($Request)

    if ($null -eq $Request) { return "" }
    if ($Request.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.objective_id)) {
        $objectiveText = ([string]$Request.objective_id).Trim()
        $numericObjective = [regex]::Match($objectiveText, '(?i)(?:^objective-(?<objective>\d+)$|^(?<objective>\d+)$)')
        if ($numericObjective.Success) {
            return [string]$numericObjective.Groups['objective'].Value
        }
        return $objectiveText
    }
    if ($Request.PSObject.Properties["task_id"] -and -not [string]::IsNullOrWhiteSpace([string]$Request.task_id)) {
        $match = [regex]::Match([string]$Request.task_id, '^objective-(?<objective>\d+)-task-\d+$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return [string]$match.Groups['objective'].Value
        }
    }
    return ""
}

$request = Read-Json -PathValue $RequestPath
$goOrder = Read-Json -PathValue $GoOrderPath
$reviewDecision = Read-Json -PathValue $ReviewDecisionPath
$integration = Read-Json -PathValue $IntegrationStatusPath

if (-not [string]::Equals([string]$RequestId, [string]$request.task_id, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "RequestId mismatch: expected '$RequestId' got '$($request.task_id)'"
}

$expectedCompatible = $true
$expectedAlignment = "aligned"
$expectedObjective = Get-ExpectedObjectiveFromRequest -Request $request
$expectedTod = $expectedObjective
$expectedMim = $expectedObjective

if ($goOrder.PSObject.Properties["success_gate"]) {
    $gate = $goOrder.success_gate
    if ($gate.PSObject.Properties["compatible"]) { $expectedCompatible = [bool]$gate.compatible }
    if ($gate.PSObject.Properties["objective_alignment_status"]) { $expectedAlignment = [string]$gate.objective_alignment_status }
    if ($gate.PSObject.Properties["tod_current_objective"]) { $expectedTod = [string]$gate.tod_current_objective }
    if ($gate.PSObject.Properties["mim_objective_active"]) { $expectedMim = [string]$gate.mim_objective_active }
}

$actualCompatible = [bool]$integration.compatible
$actualAlignment = [string]$integration.objective_alignment.status
$actualTod = [string]$integration.objective_alignment.tod_current_objective
$actualMim = [string]$integration.objective_alignment.mim_objective_active
$refreshFailure = if ($integration.PSObject.Properties["mim_refresh"] -and $integration.mim_refresh.PSObject.Properties["failure_reason"]) { [string]$integration.mim_refresh.failure_reason } else { "missing" }

$checks = @(
    [pscustomobject]@{ name = "compatible"; passed = ($actualCompatible -eq $expectedCompatible); actual = $actualCompatible; expected = $expectedCompatible },
    [pscustomobject]@{ name = "objective_alignment"; passed = (Test-AlignmentEquivalent -Actual $actualAlignment -Expected $expectedAlignment); actual = $actualAlignment; expected = $expectedAlignment },
    [pscustomobject]@{ name = "tod_current_objective"; passed = ([string]$actualTod -eq [string]$expectedTod); actual = $actualTod; expected = $expectedTod },
    [pscustomobject]@{ name = "mim_objective_active"; passed = ([string]$actualMim -eq [string]$expectedMim); actual = $actualMim; expected = $expectedMim },
    [pscustomobject]@{ name = "mim_refresh_failure_reason_empty"; passed = ([string]::IsNullOrWhiteSpace($refreshFailure)); actual = $refreshFailure; expected = "" }
)

$failed = @($checks | Where-Object { -not [bool]$_.passed })

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    request_id = $RequestId
    review_decision = if ($reviewDecision.PSObject.Properties["decision"]) { [string]$reviewDecision.decision } else { "" }
    checks = @($checks)
    passed = (@($failed).Count -eq 0)
}

$resultJson = ($result | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ResultPath, $resultJson, $utf8NoBom)

if (@($failed).Count -gt 0) {
    $failedNames = (@($failed | ForEach-Object { [string]$_.name }) -join ", ")
    throw "Validator failed checks: $failedNames"
}

$result | ConvertTo-Json -Depth 10 | Write-Output
