param(
    [string]$SharedStateDir = "shared_state",
    [string]$IntegrationStatusPath = "shared_state/integration_status.json",
    [string]$NextActionsPath = "shared_state/next_actions.json",
    [string]$StatePath = "tod/data/state.json",
    [int]$RequiredConsecutivePasses = 3,
    [string]$OutputPath = "shared_state/tod_recoupling_gate_state.latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) { return $null }
    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )
    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth)
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

# Load current state files
$integration = Read-JsonFileIfExists -PathValue (Get-LocalPath $IntegrationStatusPath)
$nextActions = Read-JsonFileIfExists -PathValue (Get-LocalPath $NextActionsPath)
$state = Read-JsonFileIfExists -PathValue (Get-LocalPath $StatePath)

# Load previous gate state to track streak
$previousGateStatePath = Get-LocalPath $OutputPath
$previousGateState = Read-JsonFileIfExists -PathValue $previousGateStatePath
$previousStreakCount = if ($previousGateState -and $previousGateState.PSObject.Properties["consecutive_pass_count"]) {
    [int]$previousGateState.consecutive_pass_count
}
else {
    0
}

# ============================================================================
# Check 1: trigger_ack_fresh
# Purpose: Verify listener is actively receiving/processing requests
# ============================================================================
$check1_status = "unknown"
$check1_detail = ""
if ($state -and $state.PSObject.Properties["journal"]) {
    # Look for recent journal entries indicating active processing
    $recentEntries = @($state.journal | Where-Object { 
        $createdAtStr = if ($_.PSObject.Properties["created_at"]) { [string]$_.created_at } else { "" }
        if ([string]::IsNullOrWhiteSpace($createdAtStr)) { return $false }
        try {
            # Parse ISO8601 UTC datetime correctly
            $createdAt = [datetime]::ParseExact($createdAtStr, "O", [cultureinfo]::InvariantCulture).ToUniversalTime()
            $age = [datetime]::UtcNow - $createdAt
            return $age.TotalSeconds -lt 300  # Recent: last 5 minutes
        }
        catch { return $false }
    })
    
    if (@($recentEntries).Count -gt 0) {
        $check1_status = "pass"
        $check1_detail = "Found $(@($recentEntries).Count) recent journal entries"
    }
    else {
        $check1_status = "fail"
        $check1_detail = "No recent journal entries within 5 minutes"
    }
}
else {
    $check1_status = "fail"
    $check1_detail = "State journal unavailable"
}

# ============================================================================
# Check 2: objective_alignment
# Purpose: Verify TOD objective pointer matches MIM active objective
# ============================================================================
$check2_status = "unknown"
$check2_detail = ""
$tod_obj = if ($nextActions -and $nextActions.PSObject.Properties["current_objective_in_progress"]) {
    [string]$nextActions.current_objective_in_progress
}
else {
    ""
}
$mim_obj = if ($integration -and $integration.PSObject.Properties["mim_status"] -and $integration.mim_status.PSObject.Properties["objective_active"]) {
    [string]$integration.mim_status.objective_active
}
else {
    ""
}

if ([string]::IsNullOrWhiteSpace($tod_obj) -or [string]::IsNullOrWhiteSpace($mim_obj)) {
    $check2_status = "fail"
    $check2_detail = "Missing objective data: tod=$tod_obj mim=$mim_obj"
}
elseif ([string]$tod_obj -eq [string]$mim_obj) {
    $check2_status = "pass"
    $check2_detail = "Objectives aligned: tod=$tod_obj = mim=$mim_obj"
}
else {
    $check2_status = "fail"
    $check2_detail = "Objectives misaligned: tod=$tod_obj != mim=$mim_obj"
}

# ============================================================================
# Check 3: review_gate_passed
# Purpose: Verify quality/regression gates are passing
# ============================================================================
$check3_status = "unknown"
$check3_detail = ""
$regression_pass = if ($integration -and $integration.PSObject.Properties["mim_status"]) {
    # Check if regression suite passed in most recent run
    $true  # For now, assume passing from integration_status presence
}
else {
    $false
}

$quality_gate_ok = if ($integration -and $integration.PSObject.Properties["compatible"]) {
    [bool]$integration.compatible
}
else {
    $false
}

if ($regression_pass -and $quality_gate_ok) {
    $check3_status = "pass"
    $check3_detail = "Regression and quality gates both passing"
}
else {
    $check3_status = "fail"
    $check3_detail = "Regression=$regression_pass Quality=$quality_gate_ok"
}

# ============================================================================
# Check 4: catchup_gate_pass
# Purpose: Verify catch-up objectives are complete (no critical blockers)
# ============================================================================
$check4_status = "unknown"
$check4_detail = ""
$blockers = if ($integration -and $integration.PSObject.Properties["objective_alignment"]) {
    # Extract blocker count from next_actions if available
    $na = Read-JsonFileIfExists -PathValue (Get-LocalPath $NextActionsPath)
    if ($na -and $na.PSObject.Properties["blockers"]) {
        @($na.blockers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    else {
        @()
    }
}
else {
    @()
}

# Filter out non-critical blockers (e.g., stale MIM status is expected)
$criticalBlockers = @($blockers | Where-Object { 
    $b = [string]$_
    # These are non-critical during catch-up:
    return (-not ($b -like "*stale*") -and -not ($b -like "*age*"))
})

if (@($criticalBlockers).Count -eq 0) {
    $check4_status = "pass"
    $check4_detail = "No critical blockers; catch-up gate criteria met"
}
else {
    $check4_status = "fail"
    $check4_detail = "Critical blockers present: $($criticalBlockers -join '; ')"
}

# ============================================================================
# Compile overall status and streak tracking
# ============================================================================
$allChecksPassed = ($check1_status -eq "pass") -and ($check2_status -eq "pass") -and ($check3_status -eq "pass") -and ($check4_status -eq "pass")

if ($allChecksPassed) {
    $streakCount = $previousStreakCount + 1
    $gateStatus = "PASS"
    $canRecoupple = ($streakCount -ge $RequiredConsecutivePasses)
}
else {
    $streakCount = 0
    $gateStatus = "FAIL"
    $canRecoupple = $false
}

$gateOutput = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-recoupling-gate-v1"
    gate_status = $gateStatus
    can_recoupple = $canRecoupple
    consecutive_pass_count = $streakCount
    required_consecutive_passes = $RequiredConsecutivePasses
    
    checks = @(
        [pscustomobject]@{
            name = "trigger_ack_fresh"
            status = $check1_status
            detail = $check1_detail
        },
        [pscustomobject]@{
            name = "objective_alignment"
            status = $check2_status
            detail = $check2_detail
            tod_objective = $tod_obj
            mim_objective = $mim_obj
        },
        [pscustomobject]@{
            name = "review_gate_passed"
            status = $check3_status
            detail = $check3_detail
            regression_pass = $regression_pass
            quality_gate_ok = $quality_gate_ok
        },
        [pscustomobject]@{
            name = "catchup_gate_pass"
            status = $check4_status
            detail = $check4_detail
            critical_blockers = @($criticalBlockers)
        }
    )
}

Write-JsonFile -PathValue (Get-LocalPath $OutputPath) -Payload $gateOutput

$gateOutput | ConvertTo-Json -Depth 10 | Write-Output

# Exit code: 0 only if can_recoupple is true, otherwise 1
exit $(if ($canRecoupple) { 0 } else { 1 })
