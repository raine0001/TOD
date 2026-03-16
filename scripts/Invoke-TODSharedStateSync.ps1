param(
    [string]$SharedStateDir = "shared_state",
    [string]$TodScriptPath = "scripts/TOD.ps1",
    [string]$TodConfigPath = "tod/config/tod-config.json",
    [string]$StatePath = "tod/data/state.json",
    [string]$TestSummaryPath = "tod/out/training/test-summary.json",
    [string]$SmokeSummaryPath = "tod/out/training/smoke-summary.json",
    [string]$QualityGatePath = "tod/out/training/quality-gate-summary.json",
    [string]$ApprovalReductionPath = "shared_state/approval_reduction_summary.json",
    [string]$ManifestPath = "tod/data/sample-manifest.json",
    [string]$MimContextExportPath = "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.json",
    [string]$MimContextExportYamlPath = "tod/out/context-sync/MIM_CONTEXT_EXPORT.latest.yaml",
    [string]$MimManifestPath = "tod/out/context-sync/MIM_MANIFEST.latest.json",
    [string]$MimSharedContextExportPath = "",
    [string]$MimSharedContextExportYamlPath = "",
    [string]$MimSharedManifestPath = "",
    [string]$MimSharedExportRoot = "",
    [switch]$RefreshMimContextFromShared,
    [switch]$RefreshMimContextFromSsh,
    [string]$MimSshHost = "mim",
    [string]$MimSshUser = "",
    [int]$MimSshPort = 0,
    [string]$MimSshPassword = "",
    [string]$MimSshSharedRoot = "/home/testpilot/mim/runtime/shared",
    [string]$MimSshStagingRoot = "tod/out/context-sync/ssh-shared",
    [switch]$AllowInteractiveSshPrompt,
    [string]$DotEnvPath = ".env",
    [string]$ScpCommand = "scp",
    [string]$ContextSyncInboxPath = "tod/inbox/context-sync/updates",
    [double]$MimStatusStaleAfterHours = 6,
    [string]$ReleaseTagOverride,
    [string]$NextProposedObjective = "TOD-17"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Get-JsonFileContent {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) { throw "File not found: $resolved" }
    return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
}

function Get-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $resolved = Get-LocalPath -PathValue $PathValue
    if (-not (Test-Path -Path $resolved)) { return $null }
    try {
        return (Get-Content -Path $resolved -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Normalize-ObjectiveIdText {
    param([string]$Value)

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    $match = [regex]::Match($text, '(?i)(?:^objective-(?<objective>\d+)$|^(?<objective>\d+)$)')
    if ($match.Success) {
        return [string]$match.Groups['objective'].Value
    }

    return $text
}

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $normalized = ([string]$Content) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $json = $Payload | ConvertTo-Json -Depth $Depth
    Write-Utf8NoBomText -Path $Path -Content $json
}

function Append-Utf8NoBomJsonLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $line = (($Payload | ConvertTo-Json -Depth $Depth -Compress) + "`n")
    [System.IO.File]::AppendAllText($Path, $line, $utf8NoBom)
}

function Get-TodPayload {
    param(
        [Parameter(Mandatory = $true)][string]$TodScript,
        [Parameter(Mandatory = $true)][string]$TodConfig,
        [Parameter(Mandatory = $true)][string]$ActionName
    )

    try {
        $raw = & $TodScript -Action $ActionName -ConfigPath $TodConfig -Top 10
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-GitValue {
    param([Parameter(Mandatory = $true)][string]$CommandText)

    try {
        $value = Invoke-Expression $CommandText
        if ($null -eq $value) { return "" }
        return ([string]$value).Trim()
    }
    catch {
        return ""
    }
}

function Get-IdNumber {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return -1 }
    $digits = [regex]::Match($Value, "\d+")
    if (-not $digits.Success) { return -1 }
    return [int]$digits.Value
}

function Convert-ToStringList {
    param($Value)

    if ($null -eq $Value) { return @() }

    $items = @()
    if ($Value -is [System.Array]) {
        $items = @($Value)
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @($Value)
    }
    else {
        $items = @($Value)
    }

    $normalized = @()
    foreach ($item in $items) {
        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $normalized += $text
        }
    }

    return @($normalized)
}

function Convert-ToUtcDateOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        return ([datetime]$Value).ToUniversalTime()
    }
    catch {
        return $null
    }
}

function Resolve-ReliabilityAlertState {
    param(
        [string]$RawState,
        [string]$Trend,
        [int]$PendingApprovals,
        [bool]$RegressionPassed,
        [bool]$QualityGatePassed
    )

    $normalized = if ([string]::IsNullOrWhiteSpace($RawState)) { "" } else { $RawState.Trim().ToLowerInvariant() }
    if ($normalized -in @("stable", "warning", "degraded", "critical")) {
        return $normalized
    }

    $trendNorm = if ([string]::IsNullOrWhiteSpace($Trend)) { "unknown" } else { $Trend.Trim().ToLowerInvariant() }
    if (-not $RegressionPassed -and -not $QualityGatePassed) {
        return "critical"
    }
    if (-not $RegressionPassed -or $PendingApprovals -ge 100) {
        return "degraded"
    }
    if ($trendNorm -in @("declining", "watch", "warning") -or $PendingApprovals -gt 0) {
        return "warning"
    }

    return "stable"
}

function Get-ApprovalBacklogSnapshot {
    param(
        [Parameter(Mandatory = $true)]$State,
        [int]$StaleHours = 72
    )

    $records = @()
    if ($State.PSObject.Properties["engineering_loop"] -and $State.engineering_loop -and $State.engineering_loop.PSObject.Properties["cycle_records"]) {
        $records = @($State.engineering_loop.cycle_records)
    }

    $pending = @($records | Where-Object {
            ($_.PSObject.Properties["approval_pending"] -and [bool]$_.approval_pending) -or
            ($_.PSObject.Properties["approval_status"] -and ([string]$_.approval_status).ToLowerInvariant() -eq "pending_apply")
        })

    $now = (Get-Date).ToUniversalTime()
    $ageBuckets = [ordered]@{
        "lt_24h" = 0
        "h24_to_h72" = 0
        "gt_72h" = 0
        "unknown" = 0
    }

    $statusCounts = [ordered]@{}
    $sourceCounts = [ordered]@{}
    $promotable = @()
    $stale = @()
    $lowValue = @()

    foreach ($item in $pending) {
        $statusValue = if ($item.PSObject.Properties["approval_status"]) { [string]$item.approval_status } else { "pending_apply" }
        if ([string]::IsNullOrWhiteSpace($statusValue)) { $statusValue = "pending_apply" }
        $statusKey = $statusValue.Trim().ToLowerInvariant()
        if (-not $statusCounts.Contains($statusKey)) {
            $statusCounts[$statusKey] = 0
        }
        $statusCounts[$statusKey] = [int]$statusCounts[$statusKey] + 1

        $sourceKey = "engineering_loop"
        if ($item.PSObject.Properties["task_category"] -and -not [string]::IsNullOrWhiteSpace([string]$item.task_category)) {
            $sourceKey = "task_category:{0}" -f ([string]$item.task_category)
        }
        elseif ($item.PSObject.Properties["objective_id"] -and -not [string]::IsNullOrWhiteSpace([string]$item.objective_id)) {
            $sourceKey = "objective:{0}" -f ([string]$item.objective_id)
        }
        if (-not $sourceCounts.Contains($sourceKey)) {
            $sourceCounts[$sourceKey] = 0
        }
        $sourceCounts[$sourceKey] = [int]$sourceCounts[$sourceKey] + 1

        $createdAtRaw = if ($item.PSObject.Properties["created_at"]) { [string]$item.created_at } else { "" }
        $updatedAtRaw = if ($item.PSObject.Properties["updated_at"]) { [string]$item.updated_at } else { "" }
        $createdAtUtc = Convert-ToUtcDateOrNull -Value $createdAtRaw
        $updatedAtUtc = Convert-ToUtcDateOrNull -Value $updatedAtRaw
        $anchor = if ($null -ne $createdAtUtc) { $createdAtUtc } else { $updatedAtUtc }

        $ageHours = $null
        if ($null -eq $anchor) {
            $ageBuckets["unknown"] = [int]$ageBuckets["unknown"] + 1
        }
        else {
            $ageHours = [math]::Round(($now - $anchor).TotalHours, 2)
            if ($ageHours -lt 24) {
                $ageBuckets["lt_24h"] = [int]$ageBuckets["lt_24h"] + 1
            }
            elseif ($ageHours -le 72) {
                $ageBuckets["h24_to_h72"] = [int]$ageBuckets["h24_to_h72"] + 1
            }
            else {
                $ageBuckets["gt_72h"] = [int]$ageBuckets["gt_72h"] + 1
            }
        }

        $score = $null
        if ($item.PSObject.Properties["score_snapshot"] -and $item.score_snapshot -and $item.score_snapshot.PSObject.Properties["overall"] -and $item.score_snapshot.overall.PSObject.Properties["score"]) {
            $score = [double]$item.score_snapshot.overall.score
        }

        $maturityBand = if ($item.PSObject.Properties["maturity_band"]) { ([string]$item.maturity_band).ToLowerInvariant() } else { "" }
        $recordId = if ($item.PSObject.Properties["cycle_id"]) { [string]$item.cycle_id } elseif ($item.PSObject.Properties["run_id"]) { [string]$item.run_id } else { "unknown" }

        $summaryRow = [pscustomobject]@{
            id = $recordId
            objective_id = if ($item.PSObject.Properties["objective_id"]) { [string]$item.objective_id } else { "" }
            task_id = if ($item.PSObject.Properties["task_id"]) { [string]$item.task_id } else { "" }
            status = $statusKey
            source = $sourceKey
            age_hours = $ageHours
            maturity_band = $maturityBand
            score = if ($null -ne $score) { [math]::Round($score, 4) } else { $null }
        }

        if ($null -ne $ageHours -and $ageHours -ge $StaleHours) {
            $stale += $summaryRow
        }

        if ($maturityBand -in @("good", "strong") -and $null -ne $score -and $score -ge 0.65) {
            $promotable += $summaryRow
        }

        if ($maturityBand -in @("emerging", "early") -or ($null -ne $score -and $score -lt 0.45)) {
            $lowValue += $summaryRow
        }
    }

    return [pscustomobject]@{
        generated_at = $now.ToString("o")
        total_pending = @($pending).Count
        by_type = [pscustomobject]$statusCounts
        by_age = [pscustomobject]$ageBuckets
        by_source = [pscustomobject]$sourceCounts
        stale_count = @($stale).Count
        low_value_count = @($lowValue).Count
        promotable_count = @($promotable).Count
        stale = @($stale | Select-Object -First 10)
        low_value = @($lowValue | Select-Object -First 10)
        promotable = @($promotable | Select-Object -First 10)
    }
}

function Get-ObjectiveByStatusOrder {
    param(
        [Parameter(Mandatory = $true)]$Objectives,
        [Parameter(Mandatory = $true)][string[]]$Statuses
    )

    $statusSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($statusItem in @($Statuses)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$statusItem)) {
            [void]$statusSet.Add(([string]$statusItem).ToLowerInvariant())
        }
    }

    $objectiveHits = @()
    foreach ($objectiveItem in @($Objectives)) {
        $statusText = ""
        if ($objectiveItem.PSObject.Properties["status"]) {
            $statusText = ([string]$objectiveItem.status).ToLowerInvariant()
        }
        if ($statusSet.Contains($statusText)) {
            $objectiveHits += $objectiveItem
        }
    }

    if (@($objectiveHits).Count -eq 0) { return $null }

    $ordered = @($objectiveHits | Sort-Object @{ Expression = { Get-IdNumber -Value ([string]$_.id) }; Descending = $true })
    return $ordered[0]
}

function Get-MimSchemaVersionFromContextExport {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue
    )

    $doc = Get-JsonFileIfExists -PathValue $PathValue
    if ($null -eq $doc) { return "" }

    if ($doc.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$doc.schema_version)) {
        return [string]$doc.schema_version
    }

    if ($doc.PSObject.Properties["status"] -and $doc.status -and $doc.status.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$doc.status.schema_version)) {
        return [string]$doc.status.schema_version
    }

    if ($doc.PSObject.Properties["contract_version"] -and -not [string]::IsNullOrWhiteSpace([string]$doc.contract_version)) {
        return [string]$doc.contract_version
    }

    return ""
}

function Ensure-ParentDirectoryForFile {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-DotEnvValue {
    param(
        [string]$Path,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }
    if (-not (Test-Path -Path $Path)) {
        return ""
    }

    $line = Get-Content -Path $Path | Where-Object {
        $_ -match ("^\s*{0}\s*=" -f [regex]::Escape($Name))
    } | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace([string]$line)) {
        return ""
    }

    return ([string]($line -replace ("^\s*{0}\s*=\s*" -f [regex]::Escape($Name)), "")).Trim()
}

function Resolve-MimSshSettingValue {
    param(
        [string]$ExplicitValue,
        [string]$EnvVarName,
        [string]$DotEnvPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return [string]$ExplicitValue
    }

    if (-not [string]::IsNullOrWhiteSpace($EnvVarName)) {
        $fromEnv = [string][Environment]::GetEnvironmentVariable($EnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            return $fromEnv
        }

        $fromDotEnv = Get-DotEnvValue -Path $DotEnvPath -Name $EnvVarName
        if (-not [string]::IsNullOrWhiteSpace($fromDotEnv)) {
            return $fromDotEnv
        }
    }

    return ""
}

function Resolve-SshHostAlias {
    param([string]$RemoteHost)

    if ([string]::IsNullOrWhiteSpace($RemoteHost)) {
        return ""
    }

    # If this is already an IP or contains a dot, treat it as concrete hostname.
    if ($RemoteHost -match "^\d{1,3}(?:\.\d{1,3}){3}$" -or $RemoteHost -match "\.") {
        return $RemoteHost
    }

    $sshConfigPath = Join-Path $HOME ".ssh/config"
    if (-not (Test-Path -Path $sshConfigPath)) {
        return $RemoteHost
    }

    $inHostBlock = $false
    $matchedHost = $false
    $resolvedHostName = ""

    foreach ($rawLine in (Get-Content -Path $sshConfigPath)) {
        $line = [string]$rawLine
        $trim = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim) -or $trim.StartsWith("#")) {
            continue
        }

        if ($trim -match "^(?i)Host\s+(.+)$") {
            $inHostBlock = $true
            $matchedHost = $false
            $resolvedHostName = ""

            $hostTokens = @($matches[1] -split "\s+")
            foreach ($token in $hostTokens) {
                if ([string]::Equals([string]$token, $RemoteHost, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedHost = $true
                    break
                }
            }
            continue
        }

        if ($inHostBlock -and $matchedHost -and $trim -match "^(?i)HostName\s+(.+)$") {
            $resolvedHostName = [string]$matches[1]
            break
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedHostName)) {
        return $resolvedHostName
    }

    return $RemoteHost
}

function Copy-IfSourceExists {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath) -or [string]::IsNullOrWhiteSpace($DestinationPath)) {
        return $false
    }

    $srcAbs = Get-LocalPath -PathValue $SourcePath
    $dstAbs = Get-LocalPath -PathValue $DestinationPath
    if (-not (Test-Path -Path $srcAbs)) {
        return $false
    }

    $srcFull = [System.IO.Path]::GetFullPath($srcAbs)
    $dstFull = [System.IO.Path]::GetFullPath($dstAbs)
    if ([string]::Equals($srcFull, $dstFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    Ensure-ParentDirectoryForFile -FilePath $dstAbs
    Copy-Item -Path $srcAbs -Destination $dstAbs -Force
    return $true
}

function Copy-FromSshIfAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Scp,
        [Parameter(Mandatory = $true)][string]$RemoteHost,
        [int]$RemotePort = 22,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [switch]$NonInteractive,
        [switch]$Required
    )

    $result = [pscustomobject]@{
        ok = $false
        remote_path = $RemotePath
        local_path = $LocalPath
        required = [bool]$Required
        error = ""
    }

    try {
        Ensure-ParentDirectoryForFile -FilePath $LocalPath

        $args = @()
        if ($NonInteractive) {
            $args += @("-o", "BatchMode=yes")
            $args += @("-o", "ConnectTimeout=10")
        }
        if ($RemotePort -gt 0) {
            $args += @("-P", [string]$RemotePort)
        }
        $args += @(("{0}:{1}" -f $RemoteHost, $RemotePath), $LocalPath)

        & $Scp @args 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -Path $LocalPath -PathType Leaf)) {
            $result.ok = $true
            return $result
        }

        if ($Required) {
            $result.error = "scp_failed"
        }
        else {
            $result.error = "optional_missing"
        }
    }
    catch {
        $result.error = [string]$_.Exception.Message
    }

    return $result
}

function Copy-FromSftpIfAvailable {
    param(
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath,
        [switch]$Required
    )

    $result = [pscustomobject]@{
        ok = $false
        remote_path = $RemotePath
        local_path = $LocalPath
        required = [bool]$Required
        error = ""
    }

    try {
        Ensure-ParentDirectoryForFile -FilePath $LocalPath
        $destinationDir = Split-Path -Parent $LocalPath
        if ([string]::IsNullOrWhiteSpace($destinationDir)) {
            $destinationDir = Get-Location
        }
        Get-SFTPItem -SessionId $SessionId -Path $RemotePath -Destination $destinationDir -Force -ErrorAction Stop | Out-Null
        if (Test-Path -Path $LocalPath -PathType Leaf) {
            $result.ok = $true
            return $result
        }

        if ($Required) {
            $result.error = "sftp_failed"
        }
        else {
            $result.error = "optional_missing"
        }
    }
    catch {
        $errorText = [string]$_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($errorText)) {
            $errorText = if ($Required) { "sftp_failed" } else { "optional_missing" }
        }
        if ($Required) {
            $result.error = $errorText
        }
        else {
            $result.error = $errorText
        }
    }

    return $result
}

function Invoke-MimSshRefresh {
    param(
        [Parameter(Mandatory = $true)][string]$Scp,
        [Parameter(Mandatory = $true)][string]$RemoteHost,
        [string]$RemoteUser,
        [int]$RemotePort,
        [string]$RemotePassword,
        [Parameter(Mandatory = $true)][string]$RemoteRoot,
        [Parameter(Mandatory = $true)][string]$StageRoot,
        [string]$DotEnvPath,
        [switch]$AllowInteractiveSshPrompt
    )

    $stageAbs = Get-LocalPath -PathValue $StageRoot
    New-DirectoryIfMissing -PathValue $stageAbs

    $jsonRemote = ("{0}/MIM_CONTEXT_EXPORT.latest.json" -f $RemoteRoot.TrimEnd('/'))
    $yamlRemote = ("{0}/MIM_CONTEXT_EXPORT.latest.yaml" -f $RemoteRoot.TrimEnd('/'))
    $manifestRemote = ("{0}/MIM_MANIFEST.latest.json" -f $RemoteRoot.TrimEnd('/'))
    $packetRemote = ("{0}/MIM_TOD_HANDSHAKE_PACKET.latest.json" -f $RemoteRoot.TrimEnd('/'))

    $jsonLocal = Join-Path $stageAbs "MIM_CONTEXT_EXPORT.latest.json"
    $yamlLocal = Join-Path $stageAbs "MIM_CONTEXT_EXPORT.latest.yaml"
    $manifestLocal = Join-Path $stageAbs "MIM_MANIFEST.latest.json"
    $packetLocal = Join-Path $stageAbs "MIM_TOD_HANDSHAKE_PACKET.latest.json"

    $dotEnvAbs = ""
    if (-not [string]::IsNullOrWhiteSpace($DotEnvPath)) {
        $dotEnvAbs = Get-LocalPath -PathValue $DotEnvPath
    }

    $sshUser = Resolve-MimSshSettingValue -ExplicitValue $RemoteUser -EnvVarName "MIM_SSH_USER" -DotEnvPath $dotEnvAbs
    if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = "testpilot" }

    $sshPortValue = ""
    if ($RemotePort -gt 0) {
        $sshPortValue = [string]$RemotePort
    }
    $sshPortText = Resolve-MimSshSettingValue -ExplicitValue $sshPortValue -EnvVarName "MIM_SSH_PORT" -DotEnvPath $dotEnvAbs
    $sshPort = 22
    if (-not [string]::IsNullOrWhiteSpace($sshPortText)) {
        $parsedPort = 0
        if ([int]::TryParse($sshPortText, [ref]$parsedPort) -and $parsedPort -gt 0) {
            $sshPort = $parsedPort
        }
    }

    $sshPassword = Resolve-MimSshSettingValue -ExplicitValue $RemotePassword -EnvVarName "MIM_SSH_PASSWORD" -DotEnvPath $dotEnvAbs
    $canUsePassword = (-not [string]::IsNullOrWhiteSpace($sshPassword)) -and ($sshPassword -ne "CHANGE_ME")
    $nonInteractiveScp = (-not [bool]$AllowInteractiveSshPrompt)
    $resolvedSftpHost = Resolve-SshHostAlias -RemoteHost $RemoteHost

    $jsonPull = $null
    $yamlPull = $null
    $manifestPull = $null
    $packetPull = $null
    $authMode = "scp"

    if ($canUsePassword -and (Get-Module -ListAvailable -Name Posh-SSH)) {
        $authMode = "sftp_password"
        Import-Module Posh-SSH -ErrorAction Stop | Out-Null

        $securePassword = ConvertTo-SecureString $sshPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential ($sshUser, $securePassword)

        $session = $null
        try {
            $session = New-SFTPSession -ComputerName $resolvedSftpHost -Port $sshPort -Credential $credential -AcceptKey -ConnectionTimeout 30000
            $jsonPull = Copy-FromSftpIfAvailable -SessionId ([int]$session.SessionId) -RemotePath $jsonRemote -LocalPath $jsonLocal -Required
            $yamlPull = Copy-FromSftpIfAvailable -SessionId ([int]$session.SessionId) -RemotePath $yamlRemote -LocalPath $yamlLocal -Required
            $manifestPull = Copy-FromSftpIfAvailable -SessionId ([int]$session.SessionId) -RemotePath $manifestRemote -LocalPath $manifestLocal
            $packetPull = Copy-FromSftpIfAvailable -SessionId ([int]$session.SessionId) -RemotePath $packetRemote -LocalPath $packetLocal
        }
        catch {
            $authMode = "scp"
        }
        finally {
            if ($null -ne $session) {
                Remove-SFTPSession -SessionId ([int]$session.SessionId) | Out-Null
            }
        }
    }

    if ($null -eq $jsonPull -or $null -eq $yamlPull -or $null -eq $manifestPull -or $null -eq $packetPull) {
        $scpTarget = $RemoteHost
        if ($scpTarget -notmatch "@") {
            $scpTarget = ("{0}@{1}" -f $sshUser, $scpTarget)
        }

        $jsonPull = Copy-FromSshIfAvailable -Scp $Scp -RemoteHost $scpTarget -RemotePort $sshPort -RemotePath $jsonRemote -LocalPath $jsonLocal -NonInteractive:$nonInteractiveScp -Required
        $yamlPull = Copy-FromSshIfAvailable -Scp $Scp -RemoteHost $scpTarget -RemotePort $sshPort -RemotePath $yamlRemote -LocalPath $yamlLocal -NonInteractive:$nonInteractiveScp -Required
        $manifestPull = Copy-FromSshIfAvailable -Scp $Scp -RemoteHost $scpTarget -RemotePort $sshPort -RemotePath $manifestRemote -LocalPath $manifestLocal -NonInteractive:$nonInteractiveScp
        $packetPull = Copy-FromSshIfAvailable -Scp $Scp -RemoteHost $scpTarget -RemotePort $sshPort -RemotePath $packetRemote -LocalPath $packetLocal -NonInteractive:$nonInteractiveScp
    }

    return [pscustomobject]@{
        ok = ([bool]$jsonPull.ok -and [bool]$yamlPull.ok)
        stage_root = $StageRoot
        stage_root_abs = $stageAbs
        resolved_sftp_host = $resolvedSftpHost
        source_json = $jsonLocal
        source_yaml = $yamlLocal
        source_manifest = $manifestLocal
        source_handshake_packet = $packetLocal
        auth_mode = $authMode
        non_interactive_scp = [bool]$nonInteractiveScp
        pulls = [pscustomobject]@{
            json = $jsonPull
            yaml = $yamlPull
            manifest = $manifestPull
            handshake_packet = $packetPull
        }
    }
}

function Get-MimSharedSourceCandidates {
    param(
        [string]$ExplicitJsonPath,
        [string]$ExplicitYamlPath,
        [string]$ExplicitManifestPath,
        [string]$PreferredRoot,
        [string]$EnvRoot
    )

    $candidates = @()

    if ((-not [string]::IsNullOrWhiteSpace($ExplicitJsonPath)) -or (-not [string]::IsNullOrWhiteSpace($ExplicitYamlPath)) -or (-not [string]::IsNullOrWhiteSpace($ExplicitManifestPath))) {
        $explicitRoot = ""
        if (-not [string]::IsNullOrWhiteSpace($ExplicitJsonPath)) {
            $explicitRoot = Split-Path -Parent $ExplicitJsonPath
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ExplicitYamlPath)) {
            $explicitRoot = Split-Path -Parent $ExplicitYamlPath
        }
        elseif (-not [string]::IsNullOrWhiteSpace($ExplicitManifestPath)) {
            $explicitRoot = Split-Path -Parent $ExplicitManifestPath
        }

        $candidates += [pscustomobject]@{
            root = $explicitRoot
            source_json = $ExplicitJsonPath
            source_yaml = $ExplicitYamlPath
            source_manifest = $ExplicitManifestPath
        }
    }

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($PreferredRoot)) { $roots += $PreferredRoot }
    if (-not [string]::IsNullOrWhiteSpace($EnvRoot)) { $roots += $EnvRoot }
    $roots += "../MIM/runtime/shared"
    $roots += "../mim/runtime/shared"
    $roots += "/shared_state"

    $seen = @{}
    foreach ($root in $roots) {
        $rootText = [string]$root
        if ([string]::IsNullOrWhiteSpace($rootText)) { continue }
        if ($seen.ContainsKey($rootText)) { continue }
        $seen[$rootText] = $true

        $candidates += [pscustomobject]@{
            root = $rootText
            source_json = (Join-Path $rootText "MIM_CONTEXT_EXPORT.latest.json")
            source_yaml = (Join-Path $rootText "MIM_CONTEXT_EXPORT.latest.yaml")
            source_manifest = (Join-Path $rootText "MIM_MANIFEST.latest.json")
        }
    }

    return @($candidates)
}

function Resolve-MimSharedSourceCandidate {
    param([Parameter(Mandatory = $true)]$Candidates)

    $candidatePathsTried = @()
    $permissionDenied = $false
    $badFilename = $false

    foreach ($candidate in @($Candidates)) {
        $jsonPath = [string]$candidate.source_json
        $yamlPath = [string]$candidate.source_yaml
        $manifestPath = [string]$candidate.source_manifest
        $paths = @($jsonPath, $yamlPath, $manifestPath)

        foreach ($path in $paths) {
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                $candidatePathsTried += $path
            }
        }

        if ([string]::IsNullOrWhiteSpace($jsonPath) -or [string]::IsNullOrWhiteSpace($yamlPath)) {
            $badFilename = $true
            continue
        }

        try {
            $rootPath = [string]$candidate.root
            if ([string]::IsNullOrWhiteSpace($rootPath)) {
                $rootPath = Split-Path -Parent ([string]$candidate.source_json)
            }

            $rootAbs = Get-LocalPath -PathValue $rootPath
            if (-not (Test-Path -Path $rootAbs)) {
                continue
            }

            $jsonAbs = Get-LocalPath -PathValue $jsonPath
            $yamlAbs = Get-LocalPath -PathValue $yamlPath
            $manifestAbs = if ([string]::IsNullOrWhiteSpace($manifestPath)) { "" } else { Get-LocalPath -PathValue $manifestPath }

            $hasJson = Test-Path -Path $jsonAbs -PathType Leaf
            $hasYaml = Test-Path -Path $yamlAbs -PathType Leaf
            $hasManifest = if ([string]::IsNullOrWhiteSpace($manifestAbs)) { $false } else { Test-Path -Path $manifestAbs -PathType Leaf }

            if ($hasJson -and $hasYaml) {
                return [pscustomobject]@{
                    resolved = $true
                    candidate = $candidate
                    candidate_paths_tried = @($candidatePathsTried)
                    failure_reason = ""
                }
            }

            $badFilename = $true
        }
        catch [System.UnauthorizedAccessException] {
            $permissionDenied = $true
        }
        catch {
            $badFilename = $true
        }
    }

    $reason = "path_not_found"
    if ($permissionDenied) {
        $reason = "permission_denied"
    }
    elseif ($badFilename) {
        $reason = "bad_filename"
    }

    return [pscustomobject]@{
        resolved = $false
        candidate = $null
        candidate_paths_tried = @($candidatePathsTried)
        failure_reason = $reason
    }
}

function Get-MimStatusSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [double]$StaleAfterHours = 6
    )

    $doc = Get-JsonFileIfExists -PathValue $PathValue
    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            source_path = $PathValue
            generated_at = ""
            age_hours = $null
            stale_after_hours = $StaleAfterHours
            is_stale = $true
            objective_active = ""
            phase = ""
            blockers = ""
        }
    }

    $generatedAt = ""
    if ($doc.PSObject.Properties["generated_at"]) {
        $generatedAt = [string]$doc.generated_at
    }
    elseif ($doc.PSObject.Properties["exported_at"]) {
        $generatedAt = [string]$doc.exported_at
    }

    $objectiveActive = ""
    $phase = ""
    $blockers = ""
    if ($doc.PSObject.Properties["status"] -and $doc.status) {
        if ($doc.status.PSObject.Properties["objective_active"]) { $objectiveActive = [string]$doc.status.objective_active }
        if ($doc.status.PSObject.Properties["phase"]) { $phase = [string]$doc.status.phase }
        if ($doc.status.PSObject.Properties["blockers"]) { $blockers = [string]$doc.status.blockers }
    }
    else {
        if ($doc.PSObject.Properties["objective_active"]) { $objectiveActive = [string]$doc.objective_active }
        if ($doc.PSObject.Properties["phase"]) { $phase = [string]$doc.phase }
        if ($doc.PSObject.Properties["blockers"]) {
            $rawBlockers = $doc.blockers
            if ($rawBlockers -is [System.Array] -or ($rawBlockers -is [System.Collections.IEnumerable] -and -not ($rawBlockers -is [string]))) {
                $blockerItems = @($rawBlockers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                $blockers = (@($blockerItems) -join "; ")
            }
            else {
                $blockers = [string]$rawBlockers
            }
        }
    }

    $ageHours = $null
    $isStale = $true
    $generatedUtc = Convert-ToUtcDateOrNull -Value $generatedAt
    if ($null -ne $generatedUtc) {
        $ageHours = [math]::Round(((Get-Date).ToUniversalTime() - $generatedUtc).TotalHours, 2)
        $isStale = ($ageHours -gt $StaleAfterHours)
    }

    return [pscustomobject]@{
        available = $true
        source_path = $PathValue
        generated_at = $generatedAt
        age_hours = $ageHours
        stale_after_hours = $StaleAfterHours
        is_stale = [bool]$isStale
        objective_active = $objectiveActive
        phase = $phase
        blockers = $blockers
    }
}

function Get-MimHandshakePacketSnapshot {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return [pscustomobject]@{
            available = $false
            source_path = ""
            generated_at = ""
            handshake_version = ""
            objective_active = ""
            latest_completed_objective = ""
            current_next_objective = ""
            schema_version = ""
            release_tag = ""
            regression_status = ""
            regression_tests = ""
            prod_promotion_status = ""
            prod_smoke_status = ""
            blockers = @()
        }
    }

    $doc = Get-JsonFileIfExists -PathValue $PathValue
    if ($null -eq $doc) {
        return [pscustomobject]@{
            available = $false
            source_path = $PathValue
            generated_at = ""
            handshake_version = ""
            objective_active = ""
            latest_completed_objective = ""
            current_next_objective = ""
            schema_version = ""
            release_tag = ""
            regression_status = ""
            regression_tests = ""
            prod_promotion_status = ""
            prod_smoke_status = ""
            blockers = @()
        }
    }

    $truth = $null
    if ($doc.PSObject.Properties["truth"] -and $doc.truth) {
        $truth = $doc.truth
    }
    else {
        $truth = $doc
    }

    $blockers = @()
    if ($truth.PSObject.Properties["blockers"] -and $null -ne $truth.blockers) {
        $blockers = Convert-ToStringList -Value $truth.blockers
    }

    return [pscustomobject]@{
        available = $true
        source_path = $PathValue
        generated_at = if ($doc.PSObject.Properties["generated_at"]) { [string]$doc.generated_at } else { "" }
        handshake_version = if ($doc.PSObject.Properties["handshake_version"]) { [string]$doc.handshake_version } else { "" }
        objective_active = if ($truth.PSObject.Properties["objective_active"]) { [string]$truth.objective_active } else { "" }
        latest_completed_objective = if ($truth.PSObject.Properties["latest_completed_objective"]) { [string]$truth.latest_completed_objective } else { "" }
        current_next_objective = if ($truth.PSObject.Properties["current_next_objective"]) { [string]$truth.current_next_objective } else { "" }
        schema_version = if ($truth.PSObject.Properties["schema_version"]) { [string]$truth.schema_version } else { "" }
        release_tag = if ($truth.PSObject.Properties["release_tag"]) { [string]$truth.release_tag } else { "" }
        regression_status = if ($truth.PSObject.Properties["regression_status"]) { [string]$truth.regression_status } else { "" }
        regression_tests = if ($truth.PSObject.Properties["regression_tests"]) { [string]$truth.regression_tests } else { "" }
        prod_promotion_status = if ($truth.PSObject.Properties["prod_promotion_status"]) { [string]$truth.prod_promotion_status } else { "" }
        prod_smoke_status = if ($truth.PSObject.Properties["prod_smoke_status"]) { [string]$truth.prod_smoke_status } else { "" }
        blockers = @($blockers)
    }
}

function Get-ObjectiveAlignment {
    param(
        [Parameter(Mandatory = $true)][string]$TodObjective,
        [string]$MimObjectiveActive,
        [string]$MimObjectiveSource
    )

    $todNumber = Get-IdNumber -Value $TodObjective
    $mimObjectiveRaw = if ([string]::IsNullOrWhiteSpace($MimObjectiveActive)) { "" } else { [string]$MimObjectiveActive }
    $mimNumber = Get-IdNumber -Value $mimObjectiveRaw

    $alignmentStatus = "unknown"
    $aligned = $false
    $delta = $null
    if ($todNumber -ge 0 -and $mimNumber -ge 0) {
        $aligned = ($todNumber -eq $mimNumber)
        $delta = ($todNumber - $mimNumber)
        $alignmentStatus = if ($aligned) { "in_sync" } else { "mismatch" }
    }

    return [pscustomobject]@{
        status = $alignmentStatus
        aligned = [bool]$aligned
        tod_current_objective = $TodObjective
        mim_objective_active = $mimObjectiveRaw
        mim_objective_source = if ([string]::IsNullOrWhiteSpace($MimObjectiveSource)) { "unknown" } else { $MimObjectiveSource }
        delta = $delta
    }
}

$sharedDirAbs = Get-LocalPath -PathValue $SharedStateDir
New-DirectoryIfMissing -PathValue $sharedDirAbs

$mimRefresh = [pscustomobject]@{
    attempted = ([bool]$RefreshMimContextFromShared -or [bool]$RefreshMimContextFromSsh)
    copied_json = $false
    copied_yaml = $false
    copied_manifest = $false
    source_json = $MimSharedContextExportPath
    source_yaml = $MimSharedContextExportYamlPath
    source_manifest = $MimSharedManifestPath
    source_handshake_packet = ""
    resolved_source_root = ""
    candidate_paths_tried = @()
    failure_reason = ""
    ssh_attempted = [bool]$RefreshMimContextFromSsh
    ssh_host = ""
    ssh_resolved_host = ""
    ssh_remote_root = ""
    ssh_stage_root = ""
    ssh_auth_mode = ""
    ssh_pull = $null
}

if ($RefreshMimContextFromSsh) {
    $mimRefresh.ssh_host = $MimSshHost
    $mimRefresh.ssh_remote_root = $MimSshSharedRoot
    $mimRefresh.ssh_stage_root = $MimSshStagingRoot

    $sshRefresh = Invoke-MimSshRefresh -Scp $ScpCommand -RemoteHost $MimSshHost -RemoteUser $MimSshUser -RemotePort $MimSshPort -RemotePassword $MimSshPassword -RemoteRoot $MimSshSharedRoot -StageRoot $MimSshStagingRoot -DotEnvPath $DotEnvPath -AllowInteractiveSshPrompt:$AllowInteractiveSshPrompt
    $mimRefresh.ssh_pull = $sshRefresh.pulls
    $mimRefresh.ssh_resolved_host = [string]$sshRefresh.resolved_sftp_host
    $mimRefresh.ssh_auth_mode = [string]$sshRefresh.auth_mode
    if ($sshRefresh.ok) {
        $MimSharedExportRoot = $MimSshStagingRoot
        $MimSharedContextExportPath = $sshRefresh.source_json
        $MimSharedContextExportYamlPath = $sshRefresh.source_yaml
        $MimSharedManifestPath = $sshRefresh.source_manifest
        $mimRefresh.source_handshake_packet = $sshRefresh.source_handshake_packet
    }
    else {
        $mimRefresh.failure_reason = "ssh_pull_failed"
    }
}

if ($RefreshMimContextFromShared -or $RefreshMimContextFromSsh) {
    $envSharedRoot = [string]$env:MIM_SHARED_EXPORT_ROOT
    $sharedCandidates = Get-MimSharedSourceCandidates -ExplicitJsonPath $MimSharedContextExportPath -ExplicitYamlPath $MimSharedContextExportYamlPath -ExplicitManifestPath $MimSharedManifestPath -PreferredRoot $MimSharedExportRoot -EnvRoot $envSharedRoot
    $resolvedShared = Resolve-MimSharedSourceCandidate -Candidates $sharedCandidates
    $mimRefresh.candidate_paths_tried = @($resolvedShared.candidate_paths_tried)
    if ([string]::IsNullOrWhiteSpace([string]$mimRefresh.failure_reason)) {
        $mimRefresh.failure_reason = [string]$resolvedShared.failure_reason
    }

    if ($resolvedShared.resolved -and $null -ne $resolvedShared.candidate) {
        $selected = $resolvedShared.candidate
        $mimRefresh.source_json = [string]$selected.source_json
        $mimRefresh.source_yaml = [string]$selected.source_yaml
        $mimRefresh.source_manifest = [string]$selected.source_manifest
        $mimRefresh.resolved_source_root = [string]$selected.root

        try {
            $mimRefresh.copied_json = [bool](Copy-IfSourceExists -SourcePath ([string]$selected.source_json) -DestinationPath $MimContextExportPath)
            $mimRefresh.copied_yaml = [bool](Copy-IfSourceExists -SourcePath ([string]$selected.source_yaml) -DestinationPath $MimContextExportYamlPath)
            $mimRefresh.copied_manifest = [bool](Copy-IfSourceExists -SourcePath ([string]$selected.source_manifest) -DestinationPath $MimManifestPath)
            if ($mimRefresh.copied_json -and $mimRefresh.copied_yaml) {
                $mimRefresh.failure_reason = ""
            }
            else {
                $mimRefresh.failure_reason = "copy_incomplete"
            }
        }
        catch [System.UnauthorizedAccessException] {
            $mimRefresh.failure_reason = "permission_denied"
        }
        catch {
            $mimRefresh.failure_reason = "copy_failed"
        }
    }
}

$currentBuildStatePath = Join-Path $sharedDirAbs "current_build_state.json"
$objectivesPath = Join-Path $sharedDirAbs "objectives.json"
$contractsPath = Join-Path $sharedDirAbs "contracts.json"
$nextActionsPath = Join-Path $sharedDirAbs "next_actions.json"
$devJournalPath = Join-Path $sharedDirAbs "dev_journal.jsonl"
$latestSummaryPath = Join-Path $sharedDirAbs "latest_summary.md"
$chatgptUpdatePath = Join-Path $sharedDirAbs "chatgpt_update.md"
$chatgptUpdateJsonPath = Join-Path $sharedDirAbs "chatgpt_update.json"
$sharedDevLogPlanPath = Join-Path $sharedDirAbs "shared_development_log_plan.json"
$integrationStatusPath = Join-Path $sharedDirAbs "integration_status.json"
$executionEvidencePath = Join-Path $sharedDirAbs "execution_evidence.json"
$objectiveRoadmapPath = Join-Path $sharedDirAbs "tod_objective_roadmap.json"

$todScriptAbs = Get-LocalPath -PathValue $TodScriptPath
$todConfigAbs = Get-LocalPath -PathValue $TodConfigPath
$stateAbs = Get-LocalPath -PathValue $StatePath

if (-not (Test-Path -Path $todScriptAbs)) { throw "TOD script not found: $todScriptAbs" }
if (-not (Test-Path -Path $todConfigAbs)) { throw "TOD config not found: $todConfigAbs" }
if (-not (Test-Path -Path $stateAbs)) { throw "TOD state not found: $stateAbs" }

$state = $null
$stateLoadWarning = ""
$maxStateReadBytes = 256MB
$skipFullStateRead = $false

try {
    $stateFileInfo = Get-Item -Path $stateAbs -ErrorAction Stop
    if ($stateFileInfo.Length -gt $maxStateReadBytes) {
        $stateLoadWarning = ("state.json too large for safe full load ({0} MiB > {1} MiB); using objectives ledger fallback" -f [math]::Round(($stateFileInfo.Length / 1MB), 2), [math]::Round(($maxStateReadBytes / 1MB), 2))
        $skipFullStateRead = $true
    }
}
catch {
    $stateLoadWarning = [string]$_.Exception.Message
    $skipFullStateRead = $true
}

if (-not $skipFullStateRead) {
    try {
        $state = Get-JsonFileContent -PathValue $StatePath
    }
    catch {
        $stateLoadWarning = [string]$_.Exception.Message
    }
}

if (-not [string]::IsNullOrWhiteSpace($stateLoadWarning)) {
    Write-Warning ("[TOD-SHARED-SYNC] Unable to load full TOD state; using objectives ledger fallback: {0}" -f $stateLoadWarning)
}

if (-not $state) {
    $state = [pscustomobject]@{}
}
$testSummary = Get-JsonFileIfExists -PathValue $TestSummaryPath
$smokeSummary = Get-JsonFileIfExists -PathValue $SmokeSummaryPath
$qualityGate = Get-JsonFileIfExists -PathValue $QualityGatePath
$approvalReduction = Get-JsonFileIfExists -PathValue $ApprovalReductionPath
$manifest = Get-JsonFileIfExists -PathValue $ManifestPath

$capabilities = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "get-capabilities"
$engineeringSignal = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "get-engineering-signal"
$reliabilityPayload = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "get-reliability"
$reliabilityDashboard = Get-TodPayload -TodScript $todScriptAbs -TodConfig $todConfigAbs -ActionName "show-reliability-dashboard"

$branch = Get-GitValue -CommandText "git rev-parse --abbrev-ref HEAD"
$commitSha = Get-GitValue -CommandText "git rev-parse HEAD"
$releaseTag = if (-not [string]::IsNullOrWhiteSpace($ReleaseTagOverride)) { $ReleaseTagOverride } else { Get-GitValue -CommandText "git describe --tags --abbrev=0 2>$null" }

$objectives = @()
if ($state -and $state.PSObject.Properties["objectives"]) {
    $objectives = @($state.objectives)
}
elseif (Test-Path -Path $objectivesPath) {
    try {
        $fallbackLedger = Get-Content -Path $objectivesPath -Raw | ConvertFrom-Json
        if ($fallbackLedger -and $fallbackLedger.PSObject.Properties["objectives"]) {
            $objectives = @($fallbackLedger.objectives | ForEach-Object {
                    [pscustomobject]@{
                        id = if ($_.PSObject.Properties["objective_id"]) { Normalize-ObjectiveIdText -Value ([string]$_.objective_id) } elseif ($_.PSObject.Properties["id"]) { Normalize-ObjectiveIdText -Value ([string]$_.id) } else { "" }
                        title = if ($_.PSObject.Properties["title"]) { [string]$_.title } else { "" }
                        status = if ($_.PSObject.Properties["status"]) { [string]$_.status } else { "open" }
                    }
                })
        }
    }
    catch {
        $objectives = @()
    }
}
$latestCompleted = Get-ObjectiveByStatusOrder -Objectives $objectives -Statuses @("completed", "closed", "done", "reviewed_pass")
$currentInProgress = Get-ObjectiveByStatusOrder -Objectives $objectives -Statuses @("in_progress", "open", "planned")

$latestCompletedObjective = if ($null -ne $latestCompleted) { Normalize-ObjectiveIdText -Value ([string]$latestCompleted.id) } else { "none" }
$currentObjective = if ($null -ne $currentInProgress) { Normalize-ObjectiveIdText -Value ([string]$currentInProgress.id) } else { "none" }

$schemaVersion = if ($manifest -and $manifest.PSObject.Properties["schema_version"]) { [string]$manifest.schema_version } else { "unknown" }
$currentProdTestStatus = [pscustomobject]@{
    tests = [pscustomobject]@{
        available = ($null -ne $testSummary)
        passed_all = if ($testSummary -and $testSummary.PSObject.Properties["passed_all"]) { [bool]$testSummary.passed_all } else { $false }
        passed = if ($testSummary -and $testSummary.PSObject.Properties["passed"]) { [int]$testSummary.passed } else { 0 }
        failed = if ($testSummary -and $testSummary.PSObject.Properties["failed"]) { [int]$testSummary.failed } else { 0 }
        total = if ($testSummary -and $testSummary.PSObject.Properties["total"]) { [int]$testSummary.total } else { 0 }
        generated_at = if ($testSummary -and $testSummary.PSObject.Properties["generated_at"]) { [string]$testSummary.generated_at } else { "" }
    }
    smoke = [pscustomobject]@{
        available = ($null -ne $smokeSummary)
        passed_all = if ($smokeSummary -and $smokeSummary.PSObject.Properties["passed_all"]) { [bool]$smokeSummary.passed_all } else { $false }
        generated_at = if ($smokeSummary -and $smokeSummary.PSObject.Properties["generated_at"]) { [string]$smokeSummary.generated_at } else { "" }
    }
}

$activeCapabilities = @()
if ($capabilities) {
    if ($capabilities.PSObject.Properties["execution"] -and $capabilities.execution.PSObject.Properties["engines"]) {
        foreach ($e in @($capabilities.execution.engines)) {
            $activeCapabilities += "engine:$([string]$e)"
        }
    }
    if ($capabilities.PSObject.Properties["endpoints"]) {
        foreach ($ep in @($capabilities.endpoints)) {
            $activeCapabilities += "endpoint:$([string]$ep)"
        }
    }
}
$activeCapabilities = @($activeCapabilities | Sort-Object -Unique)

$lastRegressionResult = [pscustomobject]@{
    passed_all = if ($testSummary -and $testSummary.PSObject.Properties["passed_all"]) { [bool]$testSummary.passed_all } else { $false }
    passed = if ($testSummary -and $testSummary.PSObject.Properties["passed"]) { [int]$testSummary.passed } else { 0 }
    failed = if ($testSummary -and $testSummary.PSObject.Properties["failed"]) { [int]$testSummary.failed } else { 0 }
    total = if ($testSummary -and $testSummary.PSObject.Properties["total"]) { [int]$testSummary.total } else { 0 }
    generated_at = if ($testSummary -and $testSummary.PSObject.Properties["generated_at"]) { [string]$testSummary.generated_at } else { "" }
}

$lastPromotionResult = [pscustomobject]@{
    available = ($null -ne $qualityGate)
    gate_ok = if ($qualityGate -and $qualityGate.PSObject.Properties["ok"]) { [bool]$qualityGate.ok } else { $false }
    run_success_rate = if ($qualityGate -and $qualityGate.PSObject.Properties["summary"] -and $qualityGate.summary.PSObject.Properties["run_success_rate"]) { [double]$qualityGate.summary.run_success_rate } else { 0.0 }
    deterministic_failure_runs = if ($qualityGate -and $qualityGate.PSObject.Properties["summary"] -and $qualityGate.summary.PSObject.Properties["deterministic_failure_runs"]) { [int]$qualityGate.summary.deterministic_failure_runs } else { 0 }
    transient_lock_failure_runs = if ($qualityGate -and $qualityGate.PSObject.Properties["summary"] -and $qualityGate.summary.PSObject.Properties["transient_lock_failure_runs"]) { [int]$qualityGate.summary.transient_lock_failure_runs } else { 0 }
    generated_at = if ($qualityGate -and $qualityGate.PSObject.Properties["generated_at"]) { [string]$qualityGate.generated_at } else { "" }
}

$approvalBacklog = Get-ApprovalBacklogSnapshot -State $state
$reliabilityAlertRaw = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["current_alert_state"]) { [string]$reliabilityPayload.current_alert_state } else { "" }
$trendForNormalization = if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["trend_direction"]) { [string]$engineeringSignal.trend_direction } else { "unknown" }
$reliabilityAlertNormalized = Resolve-ReliabilityAlertState -RawState $reliabilityAlertRaw -Trend $trendForNormalization -PendingApprovals ([int]$approvalBacklog.total_pending) -RegressionPassed ([bool]$lastRegressionResult.passed_all) -QualityGatePassed ([bool]$lastPromotionResult.gate_ok)

$knownLocalDrift = [pscustomobject]@{
    trend = if ($engineeringSignal -and $engineeringSignal.PSObject.Properties["trend_direction"]) { [string]$engineeringSignal.trend_direction } else { "unknown" }
    reliability_alert_state = $reliabilityAlertNormalized
    reliability_alert_state_raw = if ([string]::IsNullOrWhiteSpace($reliabilityAlertRaw)) { "unknown" } else { $reliabilityAlertRaw }
    pending_approvals = [int]$approvalBacklog.total_pending
}

$todCatchupRoadmap = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-catchup-roadmap-v1"
    anchor = [pscustomobject]@{
        current_objective = $currentObjective
        next_objective = $NextProposedObjective
    }
    objectives = @(
        [pscustomobject]@{ id = "TOD-17"; title = "Execution reliability stabilization"; status = if ($NextProposedObjective -eq "TOD-17") { "next" } else { "planned" } }
        [pscustomobject]@{ id = "TOD-18"; title = "Constraint evaluation integration"; status = "planned" }
        [pscustomobject]@{ id = "TOD-19"; title = "Autonomy boundary awareness"; status = "planned" }
        [pscustomobject]@{ id = "TOD-20"; title = "Cross-domain execution coordination"; status = "planned" }
        [pscustomobject]@{ id = "TOD-21"; title = "Perception event handling"; status = "planned" }
        [pscustomobject]@{ id = "TOD-22"; title = "Inquiry-driven execution pause/resume"; status = "planned" }
    )
}
Write-Utf8NoBomJson -Path $objectiveRoadmapPath -Payload $todCatchupRoadmap -Depth 12

$mimSchemaVersion = Get-MimSchemaVersionFromContextExport -PathValue $MimContextExportPath
if ([string]::IsNullOrWhiteSpace($mimSchemaVersion)) {
    $mimSchemaVersion = Get-MimSchemaVersionFromContextExport -PathValue $MimManifestPath
}
$mimManifestDoc = Get-JsonFileIfExists -PathValue $MimManifestPath
$mimContextDoc = Get-JsonFileIfExists -PathValue $MimContextExportPath

$mimContractVersion = ""
if ($mimManifestDoc -and $mimManifestDoc.PSObject.Properties["contract_version"] -and -not [string]::IsNullOrWhiteSpace([string]$mimManifestDoc.contract_version)) {
    $mimContractVersion = [string]$mimManifestDoc.contract_version
}
elseif ($mimManifestDoc -and $mimManifestDoc.PSObject.Properties["manifest"] -and $mimManifestDoc.manifest -and $mimManifestDoc.manifest.PSObject.Properties["contract_version"] -and -not [string]::IsNullOrWhiteSpace([string]$mimManifestDoc.manifest.contract_version)) {
    $mimContractVersion = [string]$mimManifestDoc.manifest.contract_version
}
elseif ($mimContextDoc -and $mimContextDoc.PSObject.Properties["contract_version"] -and -not [string]::IsNullOrWhiteSpace([string]$mimContextDoc.contract_version)) {
    $mimContractVersion = [string]$mimContextDoc.contract_version
}

$mimStatus = Get-MimStatusSnapshot -PathValue $MimContextExportPath -StaleAfterHours $MimStatusStaleAfterHours
$handshakeCandidatePaths = @()
if (-not [string]::IsNullOrWhiteSpace([string]$mimRefresh.source_handshake_packet)) {
    $handshakeCandidatePaths += [string]$mimRefresh.source_handshake_packet
}
if (-not [string]::IsNullOrWhiteSpace([string]$mimRefresh.resolved_source_root)) {
    $handshakeCandidatePaths += (Join-Path ([string]$mimRefresh.resolved_source_root) "MIM_TOD_HANDSHAKE_PACKET.latest.json")
}
if (-not [string]::IsNullOrWhiteSpace([string]$MimSharedExportRoot)) {
    $handshakeCandidatePaths += (Join-Path $MimSharedExportRoot "MIM_TOD_HANDSHAKE_PACKET.latest.json")
}

$resolvedHandshakePath = ""
foreach ($candidate in @($handshakeCandidatePaths | Select-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
    $candidateAbs = Get-LocalPath -PathValue ([string]$candidate)
    if (Test-Path -Path $candidateAbs -PathType Leaf) {
        $resolvedHandshakePath = [string]$candidate
        break
    }
}

$mimHandshake = Get-MimHandshakePacketSnapshot -PathValue $resolvedHandshakePath
if ([string]::IsNullOrWhiteSpace($mimSchemaVersion) -and [bool]$mimHandshake.available -and -not [string]::IsNullOrWhiteSpace([string]$mimHandshake.schema_version)) {
    $mimSchemaVersion = [string]$mimHandshake.schema_version
}

$mimObjectiveForAlignment = [string]$mimStatus.objective_active
$mimObjectiveSource = "context_export"
if ([bool]$mimHandshake.available -and -not [string]::IsNullOrWhiteSpace([string]$mimHandshake.objective_active)) {
    $mimObjectiveForAlignment = [string]$mimHandshake.objective_active
    $mimObjectiveSource = "handshake_packet"
}

$allCopied = [bool]$mimRefresh.copied_json -and [bool]$mimRefresh.copied_yaml
if ($RefreshMimContextFromShared -and $allCopied -and [bool]$mimStatus.is_stale) {
    $mimRefresh.failure_reason = "stale_export"
}
$objectiveAlignment = Get-ObjectiveAlignment -TodObjective $currentObjective -MimObjectiveActive $mimObjectiveForAlignment -MimObjectiveSource $mimObjectiveSource
$todContractVersion = if ($manifest -and $manifest.PSObject.Properties["contract_version"] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.contract_version)) {
    [string]$manifest.contract_version
}
elseif ($manifest -and $manifest.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.schema_version)) {
    [string]$manifest.schema_version
}
else {
    ""
}

$schemaCompatible = (-not [string]::IsNullOrWhiteSpace($mimSchemaVersion)) -and ($manifest -and $manifest.PSObject.Properties["schema_version"] -and -not [string]::IsNullOrWhiteSpace([string]$manifest.schema_version)) -and ([string]$mimSchemaVersion -eq [string]$manifest.schema_version)
$contractCompatible = (-not [string]::IsNullOrWhiteSpace($mimContractVersion)) -and (-not [string]::IsNullOrWhiteSpace($todContractVersion)) -and ([string]$mimContractVersion -eq [string]$todContractVersion)
$compatibility = [bool]($contractCompatible -or $schemaCompatible)

$compatibilityReason = if ($contractCompatible) {
    "contract_version_match"
}
elseif ($schemaCompatible) {
    "schema_version_match"
}
else {
    "no_contract_or_schema_match"
}

$integrationStatus = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-integration-status-v1"
    mim_schema = if ([string]::IsNullOrWhiteSpace($mimSchemaVersion)) { "unknown" } else { $mimSchemaVersion }
    tod_contract = if ([string]::IsNullOrWhiteSpace($todContractVersion)) { "unknown" } else { $todContractVersion }
    mim_contract = if ([string]::IsNullOrWhiteSpace($mimContractVersion)) { "unknown" } else { $mimContractVersion }
    compatible = [bool]$compatibility
    compatibility_reason = $compatibilityReason
    mim_status = $mimStatus
    mim_handshake = $mimHandshake
    mim_refresh = $mimRefresh
    objective_alignment = $objectiveAlignment
}
Write-Utf8NoBomJson -Path $integrationStatusPath -Payload $integrationStatus -Depth 8

$retryTrendRows = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["retry_trend"] -and $null -ne $reliabilityPayload.retry_trend) { @($reliabilityPayload.retry_trend) } else { @() }
$executionEvidence = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-execution-evidence-v1"
    execution_reliability = [pscustomobject]@{
        current_alert_state = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["current_alert_state"]) { [string]$reliabilityPayload.current_alert_state } else { "unknown" }
        reliability_alert_reasons = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["reliability_alert_reasons"]) { @($reliabilityPayload.reliability_alert_reasons) } else { @() }
        engine_reliability_score = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["engine_reliability_score"]) { $reliabilityPayload.engine_reliability_score } else { $null }
    }
    constraint_evaluation_outcomes = [pscustomobject]@{
        drift_warnings = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["drift_warnings"]) { @($reliabilityPayload.drift_warnings) } else { @() }
        guardrail_trend = if ($reliabilityPayload -and $reliabilityPayload.PSObject.Properties["guardrail_trend"]) { $reliabilityPayload.guardrail_trend } else { $null }
    }
    retry_fallback_metrics = @($retryTrendRows | ForEach-Object {
            [pscustomobject]@{
                engine = if ($_.PSObject.Properties["engine"]) { [string]$_.engine } else { "unknown" }
                recent_retry_rate = if ($_.PSObject.Properties["recent_retry_rate"]) { [double]$_.recent_retry_rate } else { 0.0 }
                baseline_retry_rate = if ($_.PSObject.Properties["baseline_retry_rate"]) { [double]$_.baseline_retry_rate } else { 0.0 }
                recent_fallback_rate = if ($_.PSObject.Properties["recent_fallback_rate"]) { [double]$_.recent_fallback_rate } else { 0.0 }
                baseline_fallback_rate = if ($_.PSObject.Properties["baseline_fallback_rate"]) { [double]$_.baseline_fallback_rate } else { 0.0 }
            }
        })
    performance_deltas = @($retryTrendRows | ForEach-Object {
            $recentScore = if ($_.PSObject.Properties["recent_engine_score"]) { [double]$_.recent_engine_score } else { 0.0 }
            $baselineScore = if ($_.PSObject.Properties["baseline_engine_score"]) { [double]$_.baseline_engine_score } else { 0.0 }
            [pscustomobject]@{
                engine = if ($_.PSObject.Properties["engine"]) { [string]$_.engine } else { "unknown" }
                engine_score_recent = $recentScore
                engine_score_baseline = $baselineScore
                engine_score_delta = ($recentScore - $baselineScore)
            }
        })
}
Write-Utf8NoBomJson -Path $executionEvidencePath -Payload $executionEvidence -Depth 20

$currentBuildState = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    machine = $env:COMPUTERNAME
    repo = [pscustomobject]@{
        name = "TOD"
        root = $repoRoot
        branch = $branch
        latest_commit_sha = $commitSha
    }
    latest_objective_completed = $latestCompletedObjective
    current_schema_version = $schemaVersion
    current_release_tag = $releaseTag
    current_prod_test_status = $currentProdTestStatus
    active_capabilities = @($activeCapabilities)
    known_local_drift = $knownLocalDrift
    last_regression_result = $lastRegressionResult
    last_promotion_result = $lastPromotionResult
}

Write-Utf8NoBomJson -Path $currentBuildStatePath -Payload $currentBuildState -Depth 20

$existingObjectives = @()
if (Test-Path -Path $objectivesPath) {
    try {
        $existingObjDoc = Get-Content -Path $objectivesPath -Raw | ConvertFrom-Json
        if ($existingObjDoc -and $existingObjDoc.PSObject.Properties["objectives"]) {
            $existingObjectives = @($existingObjDoc.objectives)
        }
    }
    catch {
        $existingObjectives = @()
    }
}

$existingMap = @{}
foreach ($eo in $existingObjectives) {
    if ($eo.PSObject.Properties["objective_id"]) {
        $existingMap[[string]$eo.objective_id] = $eo
    }
}

$objectiveRecords = @()
foreach ($obj in $objectives) {
    $oid = [string]$obj.id
    $prior = if ($existingMap.ContainsKey($oid)) { $existingMap[$oid] } else { $null }

    $priorDocsRaw = $null
    if ($prior -and $prior.PSObject.Properties["docs_paths"]) {
        $priorDocsRaw = $prior.docs_paths
    }
    $normalizedDocsPaths = @(Convert-ToStringList -Value $priorDocsRaw)

    $priorCapabilitiesRaw = $null
    if ($prior -and $prior.PSObject.Properties["notable_capabilities_added"]) {
        $priorCapabilitiesRaw = $prior.notable_capabilities_added
    }
    $normalizedNotableCapabilities = @(Convert-ToStringList -Value $priorCapabilitiesRaw)

    $objectiveRecords += [pscustomobject]@{
        objective_number = Get-IdNumber -Value $oid
        objective_id = $oid
        title = if ($obj.PSObject.Properties["title"]) { [string]$obj.title } else { "" }
        status = if ($obj.PSObject.Properties["status"]) { [string]$obj.status } else { "unknown" }
        focused_gate_result = if ($qualityGate -and $qualityGate.PSObject.Properties["ok"]) { if ([bool]$qualityGate.ok) { "pass" } else { "attention" } } else { "unknown" }
        full_regression_result = if ($testSummary -and $testSummary.PSObject.Properties["passed_all"]) { if ([bool]$testSummary.passed_all) { "pass" } else { "attention" } } else { "unknown" }
        promoted = if ($prior -and $prior.PSObject.Properties["promoted"]) { [bool]$prior.promoted } else { $false }
        prod_verified = if ($prior -and $prior.PSObject.Properties["prod_verified"]) { [bool]$prior.prod_verified } else { $false }
        docs_paths = @($normalizedDocsPaths)
        notable_capabilities_added = @($normalizedNotableCapabilities)
        machine_repo_primarily_affected = if ($prior -and $prior.PSObject.Properties["machine_repo_primarily_affected"]) { [string]$prior.machine_repo_primarily_affected } else { ("{0}:TOD" -f $env:COMPUTERNAME) }
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
    }
}

$objectiveLedger = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    objective_count = @($objectiveRecords).Count
    objectives = @($objectiveRecords | Sort-Object objective_number)
}
Write-Utf8NoBomJson -Path $objectivesPath -Payload $objectiveLedger -Depth 20

$contracts = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    manifest_schema_versions = [pscustomobject]@{
        sample_manifest_contract_version = if ($manifest -and $manifest.PSObject.Properties["contract_version"]) { [string]$manifest.contract_version } else { "unknown" }
        sample_manifest_schema_version = if ($manifest -and $manifest.PSObject.Properties["schema_version"]) { [string]$manifest.schema_version } else { "unknown" }
        tod_mim_shared_contract_doc = "v1"
        execution_feedback_contract_doc = "v1"
        shared_development_log_contract_doc = "v1"
    }
    shared_development_log = [pscustomobject]@{
        contract_doc = "docs/tod-shared-development-log-contract-v1.md"
        plan_file = "shared_state/shared_development_log_plan.json"
    }
    exposed_capabilities = @($activeCapabilities)
    important_endpoints = if ($capabilities -and $capabilities.PSObject.Properties["endpoints"]) { @($capabilities.endpoints) } else { @() }
    shared_models = @("Objective", "Task", "Result", "Review", "JournalEntry", "Manifest")
    interoperability_expectations = @(
        "TOD plans and executes within policy boundaries.",
        "MIM persists shared operational memory and lifecycle feedback.",
        "Execution feedback uses execution_id correlation and terminal status mapping.",
        "Shared-state files in shared_state are canonical sync layer for parallel sessions."
    )
}
Write-Utf8NoBomJson -Path $contractsPath -Payload $contracts -Depth 20

$pendingInboxCount = 0
$contextInbox = Get-LocalPath -PathValue $ContextSyncInboxPath
if (Test-Path -Path $contextInbox) {
    $pendingInboxCount = @((Get-ChildItem -Path $contextInbox -File -Filter "*.json")).Count
}

$blockers = @()
if ($knownLocalDrift.pending_approvals -gt 0) {
    $blockers += ("pending approvals ({0})" -f $knownLocalDrift.pending_approvals)
}
if ($pendingInboxCount -gt 0) {
    $blockers += ("context updates pending ingest ({0})" -f $pendingInboxCount)
}
if ($mimStatus.is_stale) {
    $mimAgeForBlocker = "unknown"
    if ($null -ne $mimStatus.age_hours) {
        $mimAgeForBlocker = [string]$mimStatus.age_hours
    }
    $blockers += ("mim status stale ({0}h > {1}h)" -f $mimAgeForBlocker, [string]$mimStatus.stale_after_hours)
}
if ([string]$objectiveAlignment.status -eq "mismatch") {
    $blockers += ("objective mismatch tod={0} mim={1}" -f [string]$objectiveAlignment.tod_current_objective, [string]$objectiveAlignment.mim_objective_active)
}
if (@($blockers).Count -eq 0) {
    $blockers += "none"
}

$failedRegressionTestNames = @()
if ($testSummary -and $testSummary.PSObject.Properties["failed_tests"] -and $null -ne $testSummary.failed_tests) {
    $failedRegressionTestNames = @($testSummary.failed_tests | ForEach-Object {
            if ($_.PSObject.Properties["name"]) { [string]$_.name } else { "" }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

$nextActions = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    current_objective_in_progress = $currentObjective
    next_proposed_objective = $NextProposedObjective
    blockers = @($blockers)
    required_verification = @(
        "focused quality gate",
        "full regression suite",
        "smoke and health checks",
        "context exchange export + ingest status"
    )
    integration_work_pending_across_boxes = @(
        "MIM consumes latest shared_state/current_build_state.json",
        "Collaborators drop updates into tod/inbox/context-sync/updates",
        "TOD ingests updates and records them in context-updates-log"
    )
    failing_regression_tests = @($failedRegressionTestNames)
    approval_backlog_snapshot = $approvalBacklog
    integration_status = $integrationStatus
    tod_catchup_roadmap = @($todCatchupRoadmap.objectives)
    approval_reduction_summary = if ($approvalReduction) {
        [pscustomobject]@{
            generated_at = if ($approvalReduction.PSObject.Properties["generated_at"]) { [string]$approvalReduction.generated_at } else { "" }
            source = if ($approvalReduction.PSObject.Properties["source"]) { [string]$approvalReduction.source } else { "" }
            totals = if ($approvalReduction.PSObject.Properties["totals"]) { $approvalReduction.totals } else { $null }
            queue_sizes = if ($approvalReduction.PSObject.Properties["queues"] -and $approvalReduction.queues) {
                [pscustomobject]@{
                    promotable_first = if ($approvalReduction.queues.PSObject.Properties["promotable_first"]) { [int]@($approvalReduction.queues.promotable_first).Count } else { 0 }
                    low_value_review = if ($approvalReduction.queues.PSObject.Properties["low_value_review"]) { [int]@($approvalReduction.queues.low_value_review).Count } else { 0 }
                    duplicate_groups = if ($approvalReduction.queues.PSObject.Properties["duplicate_groups"]) { [int]@($approvalReduction.queues.duplicate_groups).Count } else { 0 }
                    duplicate_suppression_candidates = if ($approvalReduction.queues.PSObject.Properties["duplicate_suppression_candidates"]) { [int]@($approvalReduction.queues.duplicate_suppression_candidates).Count } else { 0 }
                }
            }
            else {
                $null
            }
        }
    }
    else {
        $null
    }
}
Write-Utf8NoBomJson -Path $nextActionsPath -Payload $nextActions -Depth 20

$sharedDevLogPlan = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    contract_version = "tod-shared-development-log-contract-v1"
    purpose = "Shared development logging and handoff protocol between TOD, MIM, and collaborators."
    ownership = [pscustomobject]@{
        tod = @(
            "Publish canonical build/objective state snapshots.",
            "Ingest collaborator updates from context inbox.",
            "Append objective-level sync events to dev journal."
        )
        mim = @(
            "Consume shared_state updates for planning and memory persistence.",
            "Publish structured planning/status updates to TOD context inbox.",
            "Correlate execution lifecycle feedback with objective state."
        )
        collaborators = @(
            "Submit structured updates with source, summary, and project scope.",
            "Use canonical shared_state files as source-of-truth during parallel work.",
            "Avoid direct edits to canonical state artifacts."
        )
    }
    cadence = [pscustomobject]@{
        event_driven = @(
            "after focused quality gate",
            "after full regression",
            "after context ingest/export cycle",
            "after objective transition"
        )
        periodic = [pscustomobject]@{
            minimum = "daily"
            recommended = "per active development session"
        }
    }
    mim_charter = [pscustomobject]@{
        identity = @(
            "Space-aware and intention-driven",
            "Inquisitive and exploratory",
            "Controls its own space, systems, and development",
            "Improves itself through experience, exploration, and concept formation"
        )
        boundaries = [pscustomobject]@{
            hard_stops = @(
                "human safety",
                "ordinary wrongdoing",
                "self-destruction"
            )
            soft_boundaries = @(
                "exploration",
                "trial-and-error",
                "questioning assumptions",
                "testing policy edges in observable and recoverable ways"
            )
        }
    }
    channels = [pscustomobject]@{
        canonical_state_files = @(
            "shared_state/current_build_state.json",
            "shared_state/objectives.json",
            "shared_state/contracts.json",
            "shared_state/next_actions.json",
            "shared_state/shared_development_log_plan.json"
        )
        append_only_logs = @(
            "shared_state/dev_journal.jsonl",
            "tod/out/context-sync/context-updates-log.jsonl"
        )
        handoff_snapshots = @(
            "shared_state/chatgpt_update.md",
            "shared_state/chatgpt_update.json",
            "shared_state/latest_summary.md"
        )
        inbox = "tod/inbox/context-sync/updates"
        processed_updates = "tod/out/context-sync/processed"
    }
    merge_rules = @(
        "append-only for journal and context update logs",
        "use UTC ISO-8601 timestamps in all entries",
        "never overwrite canonical snapshot files manually",
        "prefer objective-scoped summaries over freeform notes",
        "ingested updates must preserve original payload in log record"
    )
}
Write-Utf8NoBomJson -Path $sharedDevLogPlanPath -Payload $sharedDevLogPlan -Depth 20

$journalEntry = [pscustomobject]@{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    machine = $env:COMPUTERNAME
    repo = "TOD"
    objective = $currentObjective
    action = "shared_state_sync"
    summary = "Regenerated shared_state snapshots and contracts; objective ledger refreshed."
    commit_sha = $commitSha
    validation_result = [pscustomobject]@{
        regression_passed = [bool]$lastRegressionResult.passed_all
        quality_gate_ok = [bool]$lastPromotionResult.gate_ok
        smoke_passed = if ($smokeSummary -and $smokeSummary.PSObject.Properties["passed_all"]) { [bool]$smokeSummary.passed_all } else { $false }
    }
}
Append-Utf8NoBomJsonLine -Path $devJournalPath -Payload $journalEntry -Depth 12

$summaryLines = @()
$summaryLines += "# Shared State Summary"
$summaryLines += ""
$summaryLines += "Generated: $($currentBuildState.generated_at)"
$summaryLines += "Machine: $($env:COMPUTERNAME)"
$summaryLines += "Repo: TOD"
$summaryLines += "Branch: $branch"
$summaryLines += "Commit: $commitSha"
$summaryLines += "Release tag: $releaseTag"
$summaryLines += ""
$summaryLines += "## Build State"
$summaryLines += "- Latest objective completed: $latestCompletedObjective"
$summaryLines += "- Current objective in progress: $currentObjective"
$summaryLines += "- Test status: passed=$($lastRegressionResult.passed) failed=$($lastRegressionResult.failed) total=$($lastRegressionResult.total)"
$summaryLines += "- Quality gate ok: $([bool]$lastPromotionResult.gate_ok)"
$summaryLines += "- Drift trend: $($knownLocalDrift.trend)"
$summaryLines += "- Objective alignment source: $($objectiveAlignment.mim_objective_source)"
$summaryLines += "- Handshake truth available: $([bool]$mimHandshake.available)"
if ([bool]$mimHandshake.available) {
    $summaryLines += "- Handshake objective_active: $($mimHandshake.objective_active)"
    $summaryLines += "- Handshake latest_completed: $($mimHandshake.latest_completed_objective)"
    $summaryLines += "- Handshake next_objective: $($mimHandshake.current_next_objective)"
    $summaryLines += "- Handshake release_tag: $($mimHandshake.release_tag)"
    $summaryLines += "- Handshake regression: $($mimHandshake.regression_status)"
    $summaryLines += "- Handshake prod_promotion: $($mimHandshake.prod_promotion_status)"
    $summaryLines += "- Handshake prod_smoke: $($mimHandshake.prod_smoke_status)"
}
$summaryLines += ""
$summaryLines += "## Next Actions"
foreach ($item in @($nextActions.required_verification)) {
    $summaryLines += "- $item"
}
$summaryLines += ""
$summaryLines += "## Canonical Files"
$summaryLines += "- current_build_state.json"
$summaryLines += "- objectives.json"
$summaryLines += "- contracts.json"
$summaryLines += "- next_actions.json"
$summaryLines += "- shared_development_log_plan.json"
$summaryLines += "- dev_journal.jsonl"
$summaryLines += "- latest_summary.md"

$summaryLines -join [Environment]::NewLine | Set-Content -Path $latestSummaryPath

$chatgptSnapshot = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = "tod-shared-state-sync-v1"
    objective = [pscustomobject]@{
        current_in_progress = $currentObjective
        latest_completed = $latestCompletedObjective
        next_proposed = $NextProposedObjective
        objective_count = @($objectiveRecords).Count
    }
    repo = [pscustomobject]@{
        root = $repoRoot
        branch = $branch
        commit = $commitSha
        release_tag = $releaseTag
    }
    validation = [pscustomobject]@{
        regression = $lastRegressionResult
        quality_gate = $lastPromotionResult
        smoke = $currentProdTestStatus.smoke
    }
    handshake_truth_summary = [pscustomobject]@{
        available = [bool]$mimHandshake.available
        source_path = [string]$mimHandshake.source_path
        generated_at = [string]$mimHandshake.generated_at
        objective_active = [string]$mimHandshake.objective_active
        latest_completed_objective = [string]$mimHandshake.latest_completed_objective
        current_next_objective = [string]$mimHandshake.current_next_objective
        schema_version = [string]$mimHandshake.schema_version
        release_tag = [string]$mimHandshake.release_tag
        regression_status = [string]$mimHandshake.regression_status
        regression_tests = [string]$mimHandshake.regression_tests
        prod_promotion_status = [string]$mimHandshake.prod_promotion_status
        prod_smoke_status = [string]$mimHandshake.prod_smoke_status
        blockers = @($mimHandshake.blockers)
        alignment_source = [string]$objectiveAlignment.mim_objective_source
    }
    drift = $knownLocalDrift
    blockers = @($blockers)
    capabilities = @($activeCapabilities)
    important_files = [pscustomobject]@{
        current_build_state = $currentBuildStatePath
        objectives = $objectivesPath
        contracts = $contractsPath
        next_actions = $nextActionsPath
        integration_status = $integrationStatusPath
        execution_evidence = $executionEvidencePath
        tod_objective_roadmap = $objectiveRoadmapPath
        approval_reduction_summary = if ($approvalReduction) { (Get-LocalPath -PathValue $ApprovalReductionPath) } else { "" }
        shared_development_log_plan = $sharedDevLogPlanPath
        dev_journal = $devJournalPath
        latest_summary = $latestSummaryPath
        chatgpt_update = $chatgptUpdatePath
        chatgpt_update_json = $chatgptUpdateJsonPath
    }
}

Write-Utf8NoBomJson -Path $chatgptUpdateJsonPath -Payload $chatgptSnapshot -Depth 20

$chatgptLines = @()
$chatgptLines += "# TOD ChatGPT Development Update"
$chatgptLines += ""
$chatgptLines += "Generated: $($chatgptSnapshot.generated_at)"
$chatgptLines += ""
$chatgptLines += "## Objective Status"
$chatgptLines += "- Current objective in progress: $currentObjective"
$chatgptLines += "- Latest completed objective: $latestCompletedObjective"
$chatgptLines += "- Next proposed objective: $NextProposedObjective"
$chatgptLines += "- Total objectives tracked: $(@($objectiveRecords).Count)"
$chatgptLines += ""
$chatgptLines += "## Build + Repo"
$chatgptLines += "- Branch: $branch"
$chatgptLines += "- Commit: $commitSha"
$chatgptLines += "- Release tag: $releaseTag"
$chatgptLines += ""
$chatgptLines += "## Validation"
$chatgptLines += "- Regression passed: $([bool]$lastRegressionResult.passed_all) (passed=$($lastRegressionResult.passed), failed=$($lastRegressionResult.failed), total=$($lastRegressionResult.total))"
$chatgptLines += "- Quality gate ok: $([bool]$lastPromotionResult.gate_ok)"
$chatgptLines += "- Smoke passed: $([bool]$currentProdTestStatus.smoke.passed_all)"
$chatgptLines += ""
$chatgptLines += "## Drift + Blockers"
$chatgptLines += "- Trend: $($knownLocalDrift.trend)"
$chatgptLines += "- Reliability alert: $($knownLocalDrift.reliability_alert_state)"
$chatgptLines += "- Pending approvals: $($knownLocalDrift.pending_approvals)"
foreach ($item in @($blockers)) {
    $chatgptLines += "- Blocker: $item"
}
$chatgptLines += "- Approval triage by type: $(($approvalBacklog.by_type | ConvertTo-Json -Compress))"
$chatgptLines += "- Approval triage by age: $(($approvalBacklog.by_age | ConvertTo-Json -Compress))"
$chatgptLines += "- Approval triage by source: $(($approvalBacklog.by_source | ConvertTo-Json -Compress))"
$chatgptLines += "- Approval triage counts: stale=$($approvalBacklog.stale_count) low_value=$($approvalBacklog.low_value_count) promotable=$($approvalBacklog.promotable_count)"
$chatgptLines += "- Integration status: mim_schema=$($integrationStatus.mim_schema) tod_contract=$($integrationStatus.tod_contract) compatible=$([bool]$integrationStatus.compatible)"
$chatgptLines += "- MIM freshness: available=$([bool]$integrationStatus.mim_status.available) stale=$([bool]$integrationStatus.mim_status.is_stale) age_hours=$($integrationStatus.mim_status.age_hours)"
$chatgptLines += "- Objective alignment: status=$($integrationStatus.objective_alignment.status) tod=$($integrationStatus.objective_alignment.tod_current_objective) mim=$($integrationStatus.objective_alignment.mim_objective_active)"
$chatgptLines += "- Objective alignment source: $($integrationStatus.objective_alignment.mim_objective_source)"
$chatgptLines += "- Handshake truth available: $([bool]$mimHandshake.available)"
if ([bool]$mimHandshake.available) {
    $chatgptLines += "- Handshake objective_active: $($mimHandshake.objective_active)"
    $chatgptLines += "- Handshake latest_completed_objective: $($mimHandshake.latest_completed_objective)"
    $chatgptLines += "- Handshake current_next_objective: $($mimHandshake.current_next_objective)"
    $chatgptLines += "- Handshake schema_version: $($mimHandshake.schema_version)"
    $chatgptLines += "- Handshake release_tag: $($mimHandshake.release_tag)"
    $chatgptLines += "- Handshake regression: $($mimHandshake.regression_status) ($($mimHandshake.regression_tests))"
    $chatgptLines += "- Handshake prod promotion: $($mimHandshake.prod_promotion_status)"
    $chatgptLines += "- Handshake prod smoke: $($mimHandshake.prod_smoke_status)"
    $chatgptLines += "- Handshake blockers: $(if (@($mimHandshake.blockers).Count -gt 0) { (@($mimHandshake.blockers) -join '; ') } else { 'none' })"
}
$chatgptLines += "- Catch-up roadmap: $(($todCatchupRoadmap.objectives | ForEach-Object { [string]$_.id }) -join ', ')"
$chatgptLines += "- Approval reduction snapshot present: $(if ($approvalReduction) { 'true' } else { 'false' })"
if ($approvalReduction -and $approvalReduction.PSObject.Properties["totals"]) {
    $chatgptLines += "- Approval reduction totals: $(($approvalReduction.totals | ConvertTo-Json -Compress))"
}
$chatgptLines += "- Failing regression tests: $(if (@($failedRegressionTestNames).Count -gt 0) { (@($failedRegressionTestNames) -join '; ') } else { 'none' })"
$chatgptLines += ""
$chatgptLines += "## Canonical Shared State Files"
$chatgptLines += "- $currentBuildStatePath"
$chatgptLines += "- $objectivesPath"
$chatgptLines += "- $contractsPath"
$chatgptLines += "- $nextActionsPath"
$chatgptLines += "- $sharedDevLogPlanPath"
$chatgptLines += "- $devJournalPath"
$chatgptLines += "- $latestSummaryPath"
$chatgptLines += "- $chatgptUpdateJsonPath"

$chatgptLines -join [Environment]::NewLine | Set-Content -Path $chatgptUpdatePath

$result = [pscustomobject]@{
    ok = $true
    source = "tod-shared-state-sync-v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    output_dir = $sharedDirAbs
    files = [pscustomobject]@{
        current_build_state = $currentBuildStatePath
        objectives = $objectivesPath
        contracts = $contractsPath
        next_actions = $nextActionsPath
        integration_status = $integrationStatusPath
        execution_evidence = $executionEvidencePath
        tod_objective_roadmap = $objectiveRoadmapPath
        shared_development_log_plan = $sharedDevLogPlanPath
        dev_journal = $devJournalPath
        latest_summary = $latestSummaryPath
        chatgpt_update = $chatgptUpdatePath
        chatgpt_update_json = $chatgptUpdateJsonPath
    }
    quick_status = [pscustomobject]@{
        branch = $branch
        commit = $commitSha
        current_objective_in_progress = $currentObjective
        regression_passed = [bool]$lastRegressionResult.passed_all
        quality_gate_ok = [bool]$lastPromotionResult.gate_ok
    }
}

$result | ConvertTo-Json -Depth 12 | Write-Output
