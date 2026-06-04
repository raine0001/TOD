param(
    [string]$SharedRoot = 'runtime/shared',
    [string]$OutputPath = 'runtime/shared/MIM_TOD_HOURLY_REFLECTION.latest.json',
    [string]$MarkdownPath = 'runtime/shared/MIM_TOD_HOURLY_REFLECTION.latest.md',
    [string]$DotEnvPath = '.env',
    [string]$RemoteSharedRoot = '/home/testpilot/mim/runtime/shared',
    [int]$FreshMinutes = 90,
    [switch]$NoRemote,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -LiteralPath $PathValue)) { return $null }
    try {
        return Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $PathValue)) { return $null }
    $line = Get-Content -LiteralPath $PathValue | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
    if (-not $line) { return $null }
    return ($line -replace "^\s*$Name\s*=\s*", '').Trim()
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Text
    )
    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($PathValue, $Text, $utf8NoBom)
}

function Convert-ToIsoUtc {
    param([DateTime]$Value)
    return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-ArtifactInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $path = Join-Path $Root $Name
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    $json = if ($item) { Read-JsonFileIfExists -PathValue $item.FullName } else { $null }
    $ageMinutes = if ($item) { [Math]::Round(((Get-Date) - $item.LastWriteTime).TotalMinutes, 1) } else { $null }
    return [pscustomobject]@{
        name = $Name
        path = $path
        exists = [bool]$item
        last_write_utc = if ($item) { Convert-ToIsoUtc -Value $item.LastWriteTime } else { '' }
        age_minutes = $ageMinutes
        fresh = ($item -and $ageMinutes -le $FreshMinutes)
        json = $json
    }
}

function New-MimSshSessionIfAvailable {
    param([string]$EnvPath)
    if ($NoRemote) { return $null }
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) { return $null }
    if (-not (Test-Path -LiteralPath $EnvPath)) { return $null }

    $hostName = Get-DotEnvValue -PathValue $EnvPath -Name 'MIM_SSH_HOST'
    $userName = Get-DotEnvValue -PathValue $EnvPath -Name 'MIM_SSH_USER'
    $port = Get-DotEnvValue -PathValue $EnvPath -Name 'MIM_SSH_PORT'
    $password = Get-DotEnvValue -PathValue $EnvPath -Name 'MIM_SSH_PASSWORD'
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = '192.168.1.120' }
    if ([string]::IsNullOrWhiteSpace($userName)) { $userName = 'testpilot' }
    if ([string]::IsNullOrWhiteSpace($port)) { $port = '22' }
    if ([string]::IsNullOrWhiteSpace($password) -or $password -eq 'CHANGE_ME') { return $null }

    try {
        Import-Module Posh-SSH -ErrorAction Stop
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new($userName, $securePassword)
        return New-SSHSession -ComputerName $hostName -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 8000 -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-RemoteArtifactInfo {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $remotePath = ($Root.TrimEnd('/') + '/' + $Name)
    $command = @"
python3 - <<'PY'
import json, pathlib, time
p = pathlib.Path('$remotePath')
if not p.exists():
    print(json.dumps({"exists": False}))
else:
    txt = p.read_text(errors="replace")
    try:
        payload = json.loads(txt)
    except Exception:
        payload = None
    print(json.dumps({
        "exists": True,
        "mtime": p.stat().st_mtime,
        "last_write_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(p.stat().st_mtime)),
        "json": payload,
    }))
PY
"@
    try {
        $result = Invoke-SSHCommand -SessionId $Session.SessionId -Command $command -TimeOut 15 -ErrorAction Stop
        $text = @($result.Output) -join "`n"
        $payload = $text | ConvertFrom-Json
        $ageMinutes = if ([bool]$payload.exists) { [Math]::Round(((Get-Date).ToUniversalTime() - ([DateTime]::Parse([string]$payload.last_write_utc).ToUniversalTime())).TotalMinutes, 1) } else { $null }
        return [pscustomobject]@{
            name = $Name
            path = $remotePath
            source = 'remote_mim'
            exists = [bool]$payload.exists
            last_write_utc = if ([bool]$payload.exists) { [string]$payload.last_write_utc } else { '' }
            age_minutes = $ageMinutes
            fresh = ([bool]$payload.exists -and $ageMinutes -le $FreshMinutes)
            json = if ([bool]$payload.exists) { $payload.json } else { $null }
        }
    }
    catch {
        return [pscustomobject]@{
            name = $Name
            path = $remotePath
            source = 'remote_mim_error'
            exists = $false
            last_write_utc = ''
            age_minutes = $null
            fresh = $false
            json = $null
        }
    }
}

function Get-ObjectiveItems {
    param($StatusJson)
    if ($null -eq $StatusJson -or -not $StatusJson.PSObject.Properties['objectives']) { return @() }
    $raw = $StatusJson.objectives
    if ($raw -is [System.Array]) { return @($raw) }
    if ($raw -is [System.Management.Automation.PSCustomObject]) {
        return @($raw.PSObject.Properties | ForEach-Object { $_.Value })
    }
    return @()
}

function Is-BlockedStatus {
    param($Objective)
    $status = if ($Objective.PSObject.Properties['status']) { [string]$Objective.status } else { '' }
    $reason = if ($Objective.PSObject.Properties['reason_code']) { [string]$Objective.reason_code } else { '' }
    $next = if ($Objective.PSObject.Properties['next_recovery_action']) { [string]$Objective.next_recovery_action } else { '' }
    $joined = ($status + ' ' + $reason + ' ' + $next).ToLowerInvariant()
    if ($status.ToLowerInvariant().Contains('complete') -and -not $status.ToLowerInvariant().Contains('block')) {
        return $false
    }
    return ($joined -match 'block|missing|not_bound|not bound|unresolved')
}

function Get-Prop {
    param($Object, [string]$Name, [string]$Default = '')
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) {
        return [string]$Object.$Name
    }
    return $Default
}

function Convert-ToNullableUtcDate {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return ([DateTime]::Parse($text)).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Get-JsonDateValue {
    param(
        [AllowNull()]$Object,
        [string[]]$PathCandidates = @()
    )

    foreach ($path in @($PathCandidates)) {
        if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($path)) { continue }
        $cursor = $Object
        $missing = $false
        foreach ($segment in @($path.Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            if ($null -eq $cursor -or -not $cursor.PSObject.Properties[$segment]) {
                $missing = $true
                break
            }
            $cursor = $cursor.$segment
        }
        if (-not $missing) {
            $dateValue = Convert-ToNullableUtcDate -Value $cursor
            if ($null -ne $dateValue) { return $dateValue }
        }
    }

    return $null
}

function Get-JsonStringValue {
    param(
        [AllowNull()]$Object,
        [string[]]$PathCandidates = @()
    )

    foreach ($path in @($PathCandidates)) {
        if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($path)) { continue }
        $cursor = $Object
        $missing = $false
        foreach ($segment in @($path.Split('.') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            if ($null -eq $cursor -or -not $cursor.PSObject.Properties[$segment]) {
                $missing = $true
                break
            }
            $cursor = $cursor.$segment
        }
        if (-not $missing -and $null -ne $cursor -and -not [string]::IsNullOrWhiteSpace([string]$cursor)) {
            return [string]$cursor
        }
    }

    return ''
}

function New-FreshnessProvenanceItem {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Info,
        [Parameter(Mandatory = $true)][DateTime]$NowUtc
    )

    $json = $Info.json
    $artifactGeneratedAt = Get-JsonDateValue -Object $json -PathCandidates @('generated_at', 'updated_at', 'completed_at', 'latest_execution_at')
    $sourceGeneratedAt = Get-JsonDateValue -Object $json -PathCandidates @(
        'source_artifact_generated_at',
        'latest_action.generated_at',
        'latest_action.completed_at',
        'summary.latest_execution_at',
        'execution_evidence.generated_at',
        'dispatch_result.generated_at'
    )
    $sourceField = ''
    if ($null -ne $sourceGeneratedAt) {
        $sourceField = 'embedded_source'
    }
    elseif ($null -ne $artifactGeneratedAt) {
        $sourceGeneratedAt = $artifactGeneratedAt
        $sourceField = 'artifact_generated_at'
    }
    else {
        $sourceField = 'file_mtime_only'
    }

    $artifactAgeMinutes = if ($null -ne $artifactGeneratedAt) { [Math]::Round(($NowUtc - $artifactGeneratedAt).TotalMinutes, 1) } else { $Info.age_minutes }
    $sourceAgeMinutes = if ($null -ne $sourceGeneratedAt) { [Math]::Round(($NowUtc - $sourceGeneratedAt).TotalMinutes, 1) } else { $null }
    $evidenceKind = Get-JsonStringValue -Object $json -PathCandidates @('evidence_kind', 'packet_type', 'source', 'execution_state', 'completion_status')
    $trustRank = Get-JsonStringValue -Object $json -PathCandidates @('evidence_trust_rank', 'trust_rank', 'lineage.trust_rank')
    if ([string]::IsNullOrWhiteSpace($trustRank)) {
        if ($Name -match 'EXECUTION_RESULT|TASK_RESULT|VALIDATION|TRUTH') { $trustRank = 'execution_evidence' }
        elseif ($Name -match 'STATUS|SUMMARY|REFLECTION') { $trustRank = 'summary_wrapper' }
        else { $trustRank = 'unknown' }
    }

    $staleUnderFreshWrapper = ([bool]$Info.fresh -and $null -ne $sourceAgeMinutes -and $sourceAgeMinutes -gt $FreshMinutes)
    $freshnessWrapperOnly = ([bool]$Info.fresh -and [string]::Equals($sourceField, 'file_mtime_only', [System.StringComparison]::OrdinalIgnoreCase) -and $Name -match 'STATUS|SUMMARY|REFLECTION')

    return [pscustomobject]@{
        name = $Name
        source = $Info.source
        exists = [bool]$Info.exists
        wrapper_age_minutes = $Info.age_minutes
        artifact_generated_at = if ($null -ne $artifactGeneratedAt) { Convert-ToIsoUtc -Value $artifactGeneratedAt } else { '' }
        artifact_age_minutes = $artifactAgeMinutes
        source_generated_at = if ($null -ne $sourceGeneratedAt) { Convert-ToIsoUtc -Value $sourceGeneratedAt } else { '' }
        source_age_minutes = $sourceAgeMinutes
        source_field = $sourceField
        evidence_kind = $evidenceKind
        evidence_trust_rank = $trustRank
        stale_under_fresh_wrapper = $staleUnderFreshWrapper
        freshness_wrapper_only = $freshnessWrapperOnly
    }
}

$sharedAbs = Resolve-RepoPath -PathValue $SharedRoot
$outputAbs = Resolve-RepoPath -PathValue $OutputPath
$markdownAbs = Resolve-RepoPath -PathValue $MarkdownPath
$envAbs = Resolve-RepoPath -PathValue $DotEnvPath
$generatedAt = Convert-ToIsoUtc -Value (Get-Date)

$artifactNames = @(
    'MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json',
    'MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json',
    'MIM_TOD_NEXT_OBJECTIVE.latest.json',
    'MIM_TOD_MORNING_OPERATOR_SUMMARY.latest.json',
    'TOD_PROACTIVE_AUTONOMY.latest.json',
    'TOD_PROACTIVE_TASK.latest.json',
    'TOD_EXECUTION_LOCK.latest.json',
    'MIM_READY_TASK_DISPATCHER_STATUS.latest.json',
    'TOD_EXECUTION_RESULT.latest.json',
    'TOD_VALIDATION_RESULT.latest.json',
    'TOD_MATERIAL_IMPLEMENTATION_PROOF_POLICY.latest.json',
    'TOD_MATERIAL_IMPLEMENTATION_PROOF_STATUS.latest.json',
    'MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json',
    'MIM_TOD_FRESHNESS_PROVENANCE_POLICY.latest.json',
    'MIM_TOD_CONTINUITY_MEMORY.latest.json',
    'MIM_TOD_CANONICAL_AUTHORITY_REGISTRY.latest.json',
    'TOD_MIM_TASK_RESULT.latest.json',
    'TOD_MIM_COMMAND_STATUS.latest.json',
    'TOD_EXECUTION_TRUTH.latest.json'
)

$durableReferenceArtifactNames = @(
    'MIM_TOD_CANONICAL_AUTHORITY_REGISTRY.latest.json',
    'TOD_MATERIAL_IMPLEMENTATION_PROOF_POLICY.latest.json',
    'MIM_TOD_CONTINUITY_MEMORY.latest.json',
    'MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json',
    'TOD_MATERIAL_IMPLEMENTATION_PROOF_STATUS.latest.json',
    'MIM_TOD_FRESHNESS_PROVENANCE_POLICY.latest.json'
)

$artifactSupersessionMap = @{
    'TOD_EXECUTION_RESULT.latest.json' = @('TOD_MIM_TASK_RESULT.latest.json', 'TOD_EXECUTION_TRUTH.latest.json')
    'TOD_VALIDATION_RESULT.latest.json' = @('TOD_MIM_TASK_RESULT.latest.json', 'TOD_MIM_COMMAND_STATUS.latest.json')
}

$artifacts = @{}
$sshSession = New-MimSshSessionIfAvailable -EnvPath $envAbs
foreach ($name in $artifactNames) {
    $remoteInfo = if ($sshSession) { Get-RemoteArtifactInfo -Session $sshSession -Root $RemoteSharedRoot -Name $name } else { $null }
    if ($remoteInfo -and $remoteInfo.exists) {
        $artifacts[$name] = $remoteInfo
    }
    else {
        $localInfo = Get-ArtifactInfo -Root $sharedAbs -Name $name
        $localInfo | Add-Member -NotePropertyName source -NotePropertyValue 'local' -Force
        $artifacts[$name] = $localInfo
    }
}
if ($sshSession) {
    Remove-SSHSession -SessionId $sshSession.SessionId | Out-Null
}

$objectiveStatus = $artifacts['MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json'].json
$objectiveItems = @(Get-ObjectiveItems -StatusJson $objectiveStatus)
$blocked = @($objectiveItems | Where-Object { Is-BlockedStatus -Objective $_ })
$running = @($objectiveItems | Where-Object { (Get-Prop $_ 'status').ToLowerInvariant() -match 'running|progress|active' })
$completed = @($objectiveItems | Where-Object { (Get-Prop $_ 'status').ToLowerInvariant() -match 'complete' -and -not (Is-BlockedStatus -Objective $_) })

$followon = $artifacts['MIM_TOD_BLOCKER_FOLLOWON_OBJECTIVES.latest.json'].json
$followonCount = if ($followon -and $followon.PSObject.Properties['objective_count']) { [int]$followon.objective_count } else { 0 }
$nextObjective = $artifacts['MIM_TOD_NEXT_OBJECTIVE.latest.json'].json
$proactive = $artifacts['TOD_PROACTIVE_AUTONOMY.latest.json'].json

$freshArtifactNames = @($artifacts.GetEnumerator() | Where-Object { $_.Value.exists -and $_.Value.fresh } | ForEach-Object { $_.Key })
$missingArtifactNames = @($artifacts.GetEnumerator() | Where-Object { -not $_.Value.exists } | ForEach-Object { $_.Key })
$durableCurrentArtifactNames = @($artifacts.GetEnumerator() | Where-Object {
    $_.Value.exists -and (-not $_.Value.fresh) -and ($durableReferenceArtifactNames -contains $_.Key)
} | ForEach-Object { $_.Key })
$supersededCurrentItems = @($artifactSupersessionMap.GetEnumerator() | ForEach-Object {
    $artifactName = [string]$_.Key
    $artifactInfo = $artifacts[$artifactName]
    if (-not $artifactInfo -or -not $artifactInfo.exists -or $artifactInfo.fresh) { return }
    $freshReplacements = @($_.Value | Where-Object {
        $replacementInfo = $artifacts[[string]$_]
        $replacementInfo -and $replacementInfo.exists -and $replacementInfo.fresh
    })
    if (@($freshReplacements).Count -gt 0) {
        [pscustomobject]@{
            artifact = $artifactName
            current_by = 'superseded_by_fresh_successor'
            replacements = @($freshReplacements)
        }
    }
})
$supersededCurrentArtifactNames = @($supersededCurrentItems | ForEach-Object { $_.artifact })
$currentArtifactNames = @($freshArtifactNames + $durableCurrentArtifactNames + $supersededCurrentArtifactNames | Select-Object -Unique)
$freshArtifactCount = @($currentArtifactNames).Count
$staleArtifactNames = @($artifacts.GetEnumerator() | Where-Object {
    $_.Value.exists -and ($currentArtifactNames -notcontains $_.Key)
} | ForEach-Object { $_.Key })
$freshnessProvenance = @($artifacts.GetEnumerator() | ForEach-Object {
    New-FreshnessProvenanceItem -Name $_.Key -Info $_.Value -NowUtc (Get-Date).ToUniversalTime()
})
$staleWrapperItems = @($freshnessProvenance | Where-Object { [bool]$_.stale_under_fresh_wrapper })
$wrapperOnlyFreshnessItems = @($freshnessProvenance | Where-Object { [bool]$_.freshness_wrapper_only })
$truthIntegrityReasonCodes = @()
if (@($staleWrapperItems).Count -gt 0) { $truthIntegrityReasonCodes += 'stale_under_fresh_wrapper' }
if (@($wrapperOnlyFreshnessItems).Count -gt 0) { $truthIntegrityReasonCodes += 'freshness_wrapper_only' }
$materialPolicyArtifact = $artifacts['TOD_MATERIAL_IMPLEMENTATION_PROOF_POLICY.latest.json']
if (-not $materialPolicyArtifact.exists) { $truthIntegrityReasonCodes += 'material_proof_policy_missing' }
$materialProofStatusArtifact = $artifacts['TOD_MATERIAL_IMPLEMENTATION_PROOF_STATUS.latest.json']
if (-not $materialProofStatusArtifact.exists) { $truthIntegrityReasonCodes += 'material_proof_status_missing' }
$responseSynthesisArtifact = $artifacts['MIM_OPERATOR_RESPONSE_SYNTHESIS_ENFORCEMENT_STATUS.latest.json']
if (-not $responseSynthesisArtifact.exists) { $truthIntegrityReasonCodes += 'operator_response_synthesis_status_missing' }
$freshnessPolicyArtifact = $artifacts['MIM_TOD_FRESHNESS_PROVENANCE_POLICY.latest.json']
if (-not $freshnessPolicyArtifact.exists) { $truthIntegrityReasonCodes += 'freshness_provenance_policy_missing' }

$blockerFollowonHealthy = (@($blocked).Count -eq 0) -or ($followonCount -ge @($blocked).Count)
$nextObjectiveText = Get-Prop $nextObjective 'objective_id'
$nextActionText = Get-Prop $nextObjective 'next_safe_action'
if ([string]::IsNullOrWhiteSpace($nextActionText)) {
    $nextActionText = Get-Prop $nextObjective 'goal'
}

$assessment = if (@($blocked).Count -eq 0 -and $freshArtifactCount -ge 4) {
    'healthy'
}
elseif ($blockerFollowonHealthy -and $freshArtifactCount -ge 3) {
    'improving_with_known_blockers'
}
else {
    'needs_attention'
}

$recommendations = New-Object System.Collections.Generic.List[string]
if (-not $blockerFollowonHealthy) {
    $recommendations.Add('Run blocker-to-objective synthesis because at least one blocker does not have a follow-on objective.')
}
if (@($staleArtifactNames).Count -gt 0) {
    $recommendations.Add('Refresh stale reflection inputs: ' + (@($staleArtifactNames) -join ', '))
}
if (@($staleWrapperItems).Count -gt 0) {
    $recommendations.Add('Do not trust fresh wrappers around stale source truth: ' + (@($staleWrapperItems | Select-Object -ExpandProperty name) -join ', '))
}
if (@($wrapperOnlyFreshnessItems).Count -gt 0) {
    $recommendations.Add('Require embedded source provenance for wrapper artifacts: ' + (@($wrapperOnlyFreshnessItems | Select-Object -ExpandProperty name) -join ', '))
}
if (-not $materialProofStatusArtifact.exists) {
    $recommendations.Add('Run scripts/Test-TODMaterialImplementationProof.ps1 so TOD has a live material-proof status, not just a policy.')
}
if (-not $responseSynthesisArtifact.exists) {
    $recommendations.Add('Run scripts/Test-MIMOperatorResponseSynthesis.ps1 against live MIM replies to enforce human-facing response quality.')
}
if ([string]::IsNullOrWhiteSpace($nextObjectiveText)) {
    $recommendations.Add('Publish a next objective so MIM/TOD have a single active target.')
}
if ($recommendations.Count -eq 0) {
    $recommendations.Add('Continue current objective and keep publishing concise progress summaries.')
}

$blockedSummaries = @($blocked | ForEach-Object {
    [pscustomobject]@{
        objective_id = Get-Prop $_ 'objective_id'
        title = Get-Prop $_ 'title'
        status = Get-Prop $_ 'status'
        reason_code = Get-Prop $_ 'reason_code'
        next_recovery_action = Get-Prop $_ 'next_recovery_action'
    }
})

$payload = [ordered]@{
    packet_type = 'mim-tod-hourly-reflection-v1'
    generated_at = $generatedAt
    source = 'Invoke-MIMTODHourlyReflection'
    cadence = 'hourly'
    assessment = $assessment
    are_they_improving = ($assessment -in @('healthy', 'improving_with_known_blockers'))
    are_they_creating_new_objectives = ($followonCount -gt 0)
    objective_counts = [ordered]@{
        total = @($objectiveItems).Count
        completed = @($completed).Count
        running = @($running).Count
        blocked = @($blocked).Count
        blocker_followons = $followonCount
    }
    freshness = [ordered]@{
        fresh_minutes = $FreshMinutes
        fresh_artifact_count = $freshArtifactCount
        fresh_artifacts = @($freshArtifactNames)
        durable_reference_artifacts_current = @($durableCurrentArtifactNames)
        superseded_artifacts_current = @($supersededCurrentItems)
        missing_artifacts = @($missingArtifactNames)
        stale_artifacts = @($staleArtifactNames)
        sources = @($artifacts.GetEnumerator() | ForEach-Object {
            $currentReason = if ($_.Value.fresh) { 'fresh' }
            elseif ($durableCurrentArtifactNames -contains $_.Key) { 'durable_reference' }
            elseif ($supersededCurrentArtifactNames -contains $_.Key) { 'superseded_by_fresh_successor' }
            else { 'stale' }
            [pscustomobject]@{
                name = $_.Key
                source = $_.Value.source
                fresh = $_.Value.fresh
                current = ($currentArtifactNames -contains $_.Key)
                current_reason = $currentReason
                age_minutes = $_.Value.age_minutes
            }
        })
    }
    freshness_provenance = @($freshnessProvenance)
    truth_integrity = [ordered]@{
        status = if (@($truthIntegrityReasonCodes).Count -eq 0) { 'healthy' } else { 'needs_attention' }
        reason_codes = @($truthIntegrityReasonCodes | Select-Object -Unique)
        stale_under_fresh_wrapper = @($staleWrapperItems | Select-Object -ExpandProperty name)
        freshness_wrapper_only = @($wrapperOnlyFreshnessItems | Select-Object -ExpandProperty name)
        material_proof_policy_available = [bool]$materialPolicyArtifact.exists
        material_proof_status_available = [bool]$materialProofStatusArtifact.exists
        operator_response_synthesis_status_available = [bool]$responseSynthesisArtifact.exists
        freshness_provenance_policy_available = [bool]$freshnessPolicyArtifact.exists
    }
    current_next_objective = [ordered]@{
        objective_id = $nextObjectiveText
        status = Get-Prop $nextObjective 'status'
        next_action = $nextActionText
        problem_class = Get-Prop $nextObjective 'problem_class'
    }
    blockers = @($blockedSummaries)
    blocker_followon_healthy = [bool]$blockerFollowonHealthy
    proactive_autonomy = [ordered]@{
        status = Get-Prop $proactive 'completion_status'
        selected_task = Get-Prop $proactive 'selected_task'
        idle_autonomy_triggered = if ($proactive -and $proactive.PSObject.Properties['idle_autonomy_triggered']) { [bool]$proactive.idle_autonomy_triggered } else { $false }
    }
    recommendations = @($recommendations)
    operator_summary = ''
}

$summaryBits = New-Object System.Collections.Generic.List[string]
$summaryBits.Add("MIM/TOD assessment: $assessment.")
$summaryBits.Add("Objectives: $(@($completed).Count) complete, $(@($running).Count) running, $(@($blocked).Count) blocked, $followonCount blocker follow-on objective(s).")
if (-not [string]::IsNullOrWhiteSpace($nextObjectiveText)) {
    $summaryBits.Add("Next: $nextObjectiveText.")
}
if (@($blocked).Count -gt 0) {
    $firstBlocker = $blockedSummaries[0]
    $summaryBits.Add("Top blocker: $($firstBlocker.reason_code); $($firstBlocker.next_recovery_action)")
}
if (@($truthIntegrityReasonCodes).Count -gt 0) {
    $summaryBits.Add("Truth integrity needs attention: $((@($truthIntegrityReasonCodes | Select-Object -Unique)) -join ', ').")
}
$payload.operator_summary = ($summaryBits -join ' ')

$json = ($payload | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
Write-Utf8NoBomText -PathValue $outputAbs -Text ($json + "`n")

$mdLines = @(
    '# MIM/TOD Hourly Reflection',
    '',
    $payload.operator_summary,
    '',
    '## Counts',
    "- Completed: $(@($completed).Count)",
    "- Running: $(@($running).Count)",
    "- Blocked: $(@($blocked).Count)",
    "- Blocker follow-ons: $followonCount",
    "- Truth integrity: $($payload.truth_integrity.status)",
    '',
    '## Next',
    "- Objective: $nextObjectiveText",
    "- Action: $nextActionText",
    '',
    '## Recommendations'
)
foreach ($rec in @($recommendations)) {
    $mdLines += "- $rec"
}
Write-Utf8NoBomText -PathValue $markdownAbs -Text (($mdLines -join "`n") + "`n")

$publishSession = New-MimSshSessionIfAvailable -EnvPath $envAbs
if ($publishSession) {
    try {
        Invoke-SSHCommand -SessionId $publishSession.SessionId -Command "mkdir -p '$($RemoteSharedRoot.TrimEnd('/'))'" -TimeOut 15 | Out-Null
        $hostName = Get-DotEnvValue -PathValue $envAbs -Name 'MIM_SSH_HOST'
        $userName = Get-DotEnvValue -PathValue $envAbs -Name 'MIM_SSH_USER'
        $port = Get-DotEnvValue -PathValue $envAbs -Name 'MIM_SSH_PORT'
        $password = Get-DotEnvValue -PathValue $envAbs -Name 'MIM_SSH_PASSWORD'
        if ([string]::IsNullOrWhiteSpace($port)) { $port = '22' }
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new($userName, $securePassword)
        Set-SCPItem -ComputerName $hostName -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30 -Path $outputAbs -Destination $RemoteSharedRoot -Force | Out-Null
        Set-SCPItem -ComputerName $hostName -Port ([int]$port) -Credential $credential -AcceptKey -ConnectionTimeout 30 -Path $markdownAbs -Destination $RemoteSharedRoot -Force | Out-Null
    }
    catch {
        $logRoot = Resolve-RepoPath -PathValue 'runtime/logs'
        if (-not (Test-Path -LiteralPath $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        }
        $message = "Hourly reflection publish failed: $([string]::Join(' ', @($_.Exception.Message -split '\s+')))"
        Add-Content -LiteralPath (Join-Path $logRoot 'mim_tod_hourly_reflection.publish_failed.log') -Value $message
    }
    finally {
        Remove-SSHSession -SessionId $publishSession.SessionId | Out-Null
    }
}

if ($EmitJson) {
    $json | Write-Output
}
