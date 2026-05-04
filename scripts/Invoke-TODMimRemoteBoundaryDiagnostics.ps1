param(
    [string]$DotEnvPath = ".env",
    [string]$ProbeScriptPath = "probe_canonical_task_request.py",
    [string]$RemoteRoot = "/home/testpilot/mim/runtime/shared",
    [string]$RemoteRequestPath = "/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
    [string]$OutputPath = "shared_state/TOD_MIM_REMOTE_BOUNDARY_DIAGNOSTIC.latest.json",
    [string]$ProbeOutputPath = "shared_state/TOD_MIM_REMOTE_REQUEST_PROBE.latest.json",
    [int]$Samples = 3,
    [double]$IntervalSeconds = 1,
    [int]$RecentSeconds = 1800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$authoritativeCommunicationHost = '192.168.1.120'
$authoritativeCommunicationRoot = '/home/testpilot/mim/runtime/shared'

function New-CommunicationAuthorityDescriptor {
    param(
        [Parameter(Mandatory = $true)][string]$ConfiguredHost,
        [Parameter(Mandatory = $true)][string]$ConfiguredRoot
    )

    return [pscustomobject]@{
        host = $authoritativeCommunicationHost
        path = $authoritativeCommunicationRoot
        role = 'communication_authority'
        configured_host = $ConfiguredHost
        configured_root = $ConfiguredRoot
        configured_host_matches_policy = [string]::Equals($ConfiguredHost, $authoritativeCommunicationHost, [System.StringComparison]::OrdinalIgnoreCase)
        configured_root_matches_policy = [string]::Equals($ConfiguredRoot, $authoritativeCommunicationRoot, [System.StringComparison]::OrdinalIgnoreCase)
        non_authoritative_surfaces = @(
            [pscustomobject]@{ host = '192.168.1.90'; path = '/home/testpilot/mim/runtime/shared'; role = 'arm-side runtime/telemetry'; authoritative_for_communication = $false },
            [pscustomobject]@{ host = '192.168.1.90'; path = '/home/testpilot/mim_arm/runtime/shared'; role = 'arm-side runtime/telemetry'; authoritative_for_communication = $false },
            [pscustomobject]@{ host = 'local'; path = 'tod/out/context-sync/*'; role = 'local mirrors'; authoritative_for_communication = $false }
        )
    }
}

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 24
    )

    $resolved = Resolve-LocalPath -PathValue $PathValue
    $dir = Split-Path -Parent $resolved
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($resolved, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Get-DotEnvMap {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    $resolved = Resolve-LocalPath -PathValue $PathValue
    $map = @{}
    if (-not (Test-Path -Path $resolved -PathType Leaf)) {
        return $map
    }

    foreach ($rawLine in Get-Content -Path $resolved) {
        $line = ([string]$rawLine).Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#') -or -not $line.Contains('=')) {
            continue
        }

        $parts = $line.Split('=', 2)
        if ($parts.Count -ne 2) {
            continue
        }

        $key = ([string]$parts[0]).Trim()
        $value = ([string]$parts[1]).Trim().Trim('"').Trim("'")
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $map.ContainsKey($key)) {
            $map[$key] = $value
        }
    }

    return $map
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Map,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Default = ""
    )

    if ($Map.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$Name])) {
        return [string]$Map[$Name]
    }

    return $Default
}

function Get-PythonCommand {
    $venvPython = Join-Path $repoRoot ".venv/Scripts/python.exe"
    if (Test-Path -Path $venvPython -PathType Leaf) {
        return $venvPython
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return $pythonCmd.Source
    }

    throw "python_not_found"
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory = $true)][string]$PythonCommand,
        [Parameter(Mandatory = $true)][string]$ProbeScript,
        [Parameter(Mandatory = $true)][string]$RemoteHostValue,
        [Parameter(Mandatory = $true)][string]$RemoteUserValue,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][int]$ProbeSamples,
        [Parameter(Mandatory = $true)][double]$ProbeIntervalSeconds,
        [Parameter(Mandatory = $true)][string]$ArtifactPath
    )

    $raw = & $PythonCommand $ProbeScript --host $RemoteHostValue --user $RemoteUserValue --port $Port --path $RemotePath --samples $ProbeSamples --interval-seconds $ProbeIntervalSeconds
    if ($LASTEXITCODE -ne 0) {
        throw ("remote_probe_failed: {0}" -f (($raw | Out-String).Trim()))
    }

    $doc = ($raw | Out-String | ConvertFrom-Json)
    Write-JsonFile -PathValue $ArtifactPath -Payload $doc -Depth 20
    return $doc
}

function Resolve-RemoteHostClassification {
    param(
        [Parameter(Mandatory = $true)][string[]]$Directories,
        [Parameter(Mandatory = $true)]$Services,
        [Parameter(Mandatory = $true)][string[]]$Processes,
        [Parameter(Mandatory = $true)]$Artifacts,
        [int]$StaleAfterSeconds = 1800
    )

    $dirSet = @($Directories | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $isMinimalRuntimeTree = ($dirSet.Count -le 4) -and ($dirSet -contains '/home/testpilot/mim/runtime/shared')
    $mimServiceActive = $false
    foreach ($svc in @($Services)) {
        if ($svc.name -eq 'mim.service' -and $svc.active_state -eq 'active') {
            $mimServiceActive = $true
            break
        }
    }

    $publisherProcessActive = $false
    foreach ($procLine in @($Processes)) {
        if ([string]$procLine -match '/home/testpilot/mim/' -and [string]$procLine -notmatch '/home/testpilot/mim_arm/') {
            $publisherProcessActive = $true
            break
        }
    }

    $exportArtifact = @($Artifacts | Where-Object { [string]$_.path -eq '/home/testpilot/mim/runtime/shared/MIM_CONTEXT_EXPORT.latest.json' } | Select-Object -First 1)[0]
    $requestArtifact = @($Artifacts | Where-Object { [string]$_.path -eq '/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json' } | Select-Object -First 1)[0]

    $exportAgeSeconds = $null
    if ($exportArtifact -and $exportArtifact.exists -and $exportArtifact.mtime_epoch) {
        $exportTimestamp = (Get-Date '1970-01-01T00:00:00Z').ToUniversalTime().AddSeconds([double]$exportArtifact.mtime_epoch)
        $exportAgeSeconds = [int][math]::Floor(([datetime]::UtcNow - $exportTimestamp).TotalSeconds)
    }

    $requestAgeSeconds = $null
    if ($requestArtifact -and $requestArtifact.exists -and $requestArtifact.mtime_epoch) {
        $requestTimestamp = (Get-Date '1970-01-01T00:00:00Z').ToUniversalTime().AddSeconds([double]$requestArtifact.mtime_epoch)
        $requestAgeSeconds = [int][math]::Floor(([datetime]::UtcNow - $requestTimestamp).TotalSeconds)
    }

    $classification = 'unknown'
    $recommendation = 'keep_current_boundary'
    $reason = 'insufficient_remote_boundary_evidence'

    $configuredCanonicalSurface = $false
    if ($requestArtifact -and $requestArtifact.exists -and $exportArtifact -and $exportArtifact.exists) {
        $configuredCanonicalSurface = $true
    }

    $freshCanonicalArtifacts = $false
    if ($exportAgeSeconds -ne $null -and $requestAgeSeconds -ne $null -and $exportAgeSeconds -le $StaleAfterSeconds -and $requestAgeSeconds -le $StaleAfterSeconds) {
        $freshCanonicalArtifacts = $true
    }

    if ($configuredCanonicalSurface -and $publisherProcessActive -and $freshCanonicalArtifacts) {
        $classification = 'canonical_publish_surface_healthy'
        $recommendation = 'keep_current_boundary'
        $reason = 'fresh_canonical_artifacts_with_active_publisher'
    }

    if ($isMinimalRuntimeTree -and -not $mimServiceActive -and -not $publisherProcessActive) {
        $classification = 'noncanonical_remote_surface'
        $recommendation = 'repair_current_boundary'
        $reason = 'remote_runtime_tree_has_no_visible_repo_checkout_or_active_publisher'
    }

    if ($classification -eq 'noncanonical_remote_surface' -and $exportAgeSeconds -ne $null -and $requestAgeSeconds -ne $null -and $exportAgeSeconds -gt $StaleAfterSeconds -and $requestAgeSeconds -le $StaleAfterSeconds) {
        $reason = 'remote_runtime_tree_is_partially_refreshed_with_stale_context_export_and_no_active_publisher'
    }

    return [pscustomobject]@{
        classification = $classification
        recommendation = $recommendation
        reason = $reason
        configured_canonical_surface = [bool]$configuredCanonicalSurface
        fresh_canonical_artifacts = [bool]$freshCanonicalArtifacts
        is_minimal_runtime_tree = [bool]$isMinimalRuntimeTree
        mim_service_active = [bool]$mimServiceActive
        publisher_process_active = [bool]$publisherProcessActive
        request_age_seconds = $requestAgeSeconds
        export_age_seconds = $exportAgeSeconds
    }
}

function New-RemoteStructuredCommand {
    return @'
python3 - <<'PY'
import json
import pathlib

root = pathlib.Path('/home/testpilot/mim/runtime/shared')
paths = [
    root / 'MIM_TOD_TASK_REQUEST.latest.json',
    root / 'MIM_TOD_TASK_REQUEST.json',
    root / 'MIM_CONTEXT_EXPORT.latest.json',
    root / 'MIM_TOD_HANDSHAKE_PACKET.latest.json',
    root / 'MIM_TO_TOD_TRIGGER.latest.json',
    root / 'TOD_INTEGRATION_STATUS.latest.json',
]
out = []
for path in paths:
    item = {'path': str(path), 'exists': path.exists()}
    if path.exists():
        stat = path.stat()
        item['size'] = stat.st_size
        item['mtime_epoch'] = stat.st_mtime
        item['inode'] = stat.st_ino
    out.append(item)
print(json.dumps(out))
PY
'@
}

$dotEnv = Get-DotEnvMap -PathValue $DotEnvPath
$remoteHost = Get-DotEnvValue -Map $dotEnv -Name 'MIM_SSH_HOST' -Default 'mim'
$remoteUser = Get-DotEnvValue -Map $dotEnv -Name 'MIM_SSH_USER' -Default 'testpilot'
$remotePassword = Get-DotEnvValue -Map $dotEnv -Name 'MIM_SSH_PASSWORD'
$portText = Get-DotEnvValue -Map $dotEnv -Name 'MIM_SSH_PORT' -Default '22'
$remotePort = 22
[void][int]::TryParse($portText, [ref]$remotePort)

$probeScriptAbs = Resolve-LocalPath -PathValue $ProbeScriptPath
if (-not (Test-Path -Path $probeScriptAbs -PathType Leaf)) {
    throw ("Missing probe script: {0}" -f $probeScriptAbs)
}

$pythonCommand = Get-PythonCommand
$remoteProbe = Invoke-Probe -PythonCommand $pythonCommand -ProbeScript $probeScriptAbs -RemoteHostValue $remoteHost -RemoteUserValue $remoteUser -Port $remotePort -RemotePath $RemoteRequestPath -ProbeSamples $Samples -ProbeIntervalSeconds $IntervalSeconds -ArtifactPath $ProbeOutputPath

if ([string]::IsNullOrWhiteSpace($remotePassword) -or $remotePassword -eq 'CHANGE_ME') {
    throw 'ssh_password_not_set'
}

Import-Module Posh-SSH -ErrorAction Stop | Out-Null
$securePassword = ConvertTo-SecureString $remotePassword -AsPlainText -Force
$credential = [pscredential]::new($remoteUser, $securePassword)
$session = New-SSHSession -ComputerName $remoteHost -Port $remotePort -Credential $credential -AcceptKey -ConnectionTimeout 20000

try {
    $hostInfoRaw = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command "hostname; echo '===NS==='; readlink /proc/self/ns/mnt; readlink /proc/self/ns/pid; readlink /proc/self/ns/uts; echo '===SERVICES==='; systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -Ei 'mim|tod|reissue|overnight|watcher|runtime' || true; echo '===TIMERS==='; systemctl list-timers --all --no-pager 2>/dev/null | grep -Ei 'mim|tod|reissue|overnight|watcher|runtime' || true; echo '===CRONTAB==='; crontab -l 2>/dev/null || true" -TimeOut 120
    $dirLayoutRaw = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command "find /home/testpilot/mim -maxdepth 3 -type d | sort | sed -n '1,200p'" -TimeOut 120
    $artifactRaw = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command (New-RemoteStructuredCommand) -TimeOut 120
    $processRaw = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command "ps -ef | grep -Ei 'mim|tod|reissue|overnight|runtime/shared|objective-75|objective-97' | grep -v grep || true" -TimeOut 120
    $treeRaw = Invoke-SSHCommand -SessionId ([int]$session.SessionId) -Command "ls -la /home/testpilot/mim/runtime/shared | sed -n '1,120p'; echo '===DIALOG==='; ls -la /home/testpilot/mim/runtime/shared/dialog | sed -n '1,80p'" -TimeOut 120
}
finally {
    Remove-SSHSession -SessionId ([int]$session.SessionId) | Out-Null
}

$hostInfoLines = @($hostInfoRaw.Output | ForEach-Object { [string]$_ })
$directories = @($dirLayoutRaw.Output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$processLines = @($processRaw.Output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$treeLines = @($treeRaw.Output | ForEach-Object { [string]$_ })
$artifactDoc = $null
try {
    $artifactDoc = (($artifactRaw.Output | Out-String).Trim() | ConvertFrom-Json)
}
catch {
    $artifactDoc = @()
}

$services = @()
$timers = @()
$crontab = @()
$section = ''
foreach ($line in @($hostInfoLines)) {
    if ($line -eq '===NS===') { $section = 'ns'; continue }
    if ($line -eq '===SERVICES===') { $section = 'services'; continue }
    if ($line -eq '===TIMERS===') { $section = 'timers'; continue }
    if ($line -eq '===CRONTAB===') { $section = 'crontab'; continue }

    switch ($section) {
        'services' {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $parts = @($line -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($parts.Count -ge 4) {
                    $services += [pscustomobject]@{
                        name = $parts[0]
                        load_state = $parts[1]
                        active_state = $parts[2]
                        sub_state = $parts[3]
                        raw = $line.Trim()
                    }
                }
            }
        }
        'timers' {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $timers += $line.Trim() }
        }
        'crontab' {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $crontab += $line.Trim() }
        }
    }
}

$remoteAssessment = Resolve-RemoteHostClassification -Directories $directories -Services $services -Processes $processLines -Artifacts $artifactDoc -StaleAfterSeconds $RecentSeconds
$communicationAuthority = New-CommunicationAuthorityDescriptor -ConfiguredHost $remoteHost -ConfiguredRoot $RemoteRoot

if (-not [bool]$communicationAuthority.configured_host_matches_policy) {
    $remoteAssessment = [pscustomobject]@{
        classification = 'communication_authority_misconfigured'
        recommendation = 'restore_server_authority_host'
        reason = 'configured_host_does_not_match_192.168.1.120_communication_authority'
        is_minimal_runtime_tree = if ($remoteAssessment.PSObject.Properties['is_minimal_runtime_tree']) { [bool]$remoteAssessment.is_minimal_runtime_tree } else { $false }
        mim_service_active = if ($remoteAssessment.PSObject.Properties['mim_service_active']) { [bool]$remoteAssessment.mim_service_active } else { $false }
        publisher_process_active = if ($remoteAssessment.PSObject.Properties['publisher_process_active']) { [bool]$remoteAssessment.publisher_process_active } else { $false }
        request_age_seconds = if ($remoteAssessment.PSObject.Properties['request_age_seconds']) { $remoteAssessment.request_age_seconds } else { $null }
        export_age_seconds = if ($remoteAssessment.PSObject.Properties['export_age_seconds']) { $remoteAssessment.export_age_seconds } else { $null }
    }
}

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-remote-boundary-diagnostic-v1'
    remote_host = $remoteHost
    remote_user = $remoteUser
    remote_port = $remotePort
    remote_root = $RemoteRoot
    remote_request_path = $RemoteRequestPath
    communication_authority = $communicationAuthority
    request_probe_path = (Resolve-LocalPath -PathValue $ProbeOutputPath)
    request_probe = $remoteProbe
    remote_boundary = $remoteAssessment
    remote_host_evidence = [pscustomobject]@{
        directories = @($directories)
        services = @($services)
        timers = @($timers)
        crontab = @($crontab)
        active_processes = @($processLines)
        artifacts = @($artifactDoc)
        tree_listing = @($treeLines)
    }
}

Write-JsonFile -PathValue $OutputPath -Payload $result -Depth 24
$result | ConvertTo-Json -Depth 24 | Write-Output