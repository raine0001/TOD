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
    'MIM_READY_TASK_DISPATCHER_STATUS.latest.json'
)

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

$freshArtifactCount = @($artifacts.Values | Where-Object { $_.fresh }).Count
$missingArtifactNames = @($artifacts.GetEnumerator() | Where-Object { -not $_.Value.exists } | ForEach-Object { $_.Key })
$staleArtifactNames = @($artifacts.GetEnumerator() | Where-Object { $_.Value.exists -and -not $_.Value.fresh } | ForEach-Object { $_.Key })

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
        missing_artifacts = @($missingArtifactNames)
        stale_artifacts = @($staleArtifactNames)
        sources = @($artifacts.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{
                name = $_.Key
                source = $_.Value.source
                fresh = $_.Value.fresh
                age_minutes = $_.Value.age_minutes
            }
        })
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
        $json64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json + "`n"))
        $markdownText = (($mdLines -join "`n") + "`n")
        $md64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($markdownText))
        $remoteJsonPath = ($RemoteSharedRoot.TrimEnd('/') + '/MIM_TOD_HOURLY_REFLECTION.latest.json')
        $remoteMdPath = ($RemoteSharedRoot.TrimEnd('/') + '/MIM_TOD_HOURLY_REFLECTION.latest.md')
        $publishCommand = @"
python3 - <<'PY'
import base64, pathlib
files = {
    '$remoteJsonPath': '$json64',
    '$remoteMdPath': '$md64',
}
for path, data in files.items():
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(base64.b64decode(data))
print('hourly_reflection_published')
PY
"@
        Invoke-SSHCommand -SessionId $publishSession.SessionId -Command $publishCommand -TimeOut 15 | Out-Null
    }
    catch {
    }
    finally {
        Remove-SSHSession -SessionId $publishSession.SessionId | Out-Null
    }
}

if ($EmitJson) {
    $json | Write-Output
}
