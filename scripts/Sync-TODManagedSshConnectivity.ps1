[CmdletBinding()]
param(
    [string]$RegistryPath = '',
    [string]$ReportPath = '',
    [switch]$SkipConfigWrite
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $repoRoot 'tod\config\managed-host-connections.json' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $repoRoot 'tod\state\managed_ssh_connectivity.latest.json' }

function Get-KeyFingerprint {
    param([Parameter(Mandatory)][string]$Path)
    $line = [string](& ssh-keygen -lf $Path 2>&1 | Where-Object { [string]$_ -match '^\d+\s+SHA256:' } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "Unable to fingerprint SSH key: $Path"
    }
    $parts = @($line -split '\s+')
    if ($parts.Count -lt 2) { throw "Unexpected ssh-keygen output for $Path" }
    return $parts[1]
}

function Write-AtomicUtf8 {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, $Content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Set-DotEnvAuthorityValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Managed dotenv consumer is missing: $Path" }
    $content = Get-Content -LiteralPath $Path -Raw
    $pattern = '(?m)^' + [regex]::Escape($Key) + '=.*$'
    if ($content -notmatch $pattern) { throw "Managed dotenv key is missing: $Key in $Path" }
    $updated = [regex]::new($pattern).Replace($content, ($Key + '=' + $Value), 1)
    if ($updated -ne $content) { Write-AtomicUtf8 -Path $Path -Content $updated }
}

$registryFull = (Resolve-Path -LiteralPath $RegistryPath).Path
$registry = Get-Content -LiteralPath $registryFull -Raw | ConvertFrom-Json
if ($registry.managed_by -ne 'TOD' -or [int]$registry.schema_version -ne 1) {
    throw 'The managed-host registry is not a supported TOD authority document.'
}

$sshRoot = Join-Path $env:USERPROFILE '.ssh'
$managedConfig = Join-Path $sshRoot 'tod-managed.conf'
$managedKnownHosts = Join-Path $sshRoot 'tod-managed-known_hosts'
$mainConfig = Join-Path $sshRoot 'config'
New-Item -ItemType Directory -Path $sshRoot -Force | Out-Null

$configLines = @('# Generated from tod/config/managed-host-connections.json. Do not edit by hand.')
$knownHostLines = @()
$results = @()

foreach ($property in $registry.hosts.PSObject.Properties) {
    $name = [string]$property.Name
    $hostSpec = $property.Value
    $identityPath = if ([IO.Path]::IsPathRooted([string]$hostSpec.identity_file)) {
        [string]$hostSpec.identity_file
    } else {
        Join-Path $env:USERPROFILE ([string]$hostSpec.identity_file)
    }
    $identityPublic = "$identityPath.pub"
    $identityFingerprint = if (Test-Path -LiteralPath $identityPublic) { Get-KeyFingerprint $identityPublic } else { '' }
    $identityOk = $identityFingerprint -eq [string]$hostSpec.expected_identity_fingerprint

    $scanLine = ''
    $observedHostFingerprint = ''
    $directLoginOk = $false
    try {
        $priorErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $destination = '{0}@{1}' -f $hostSpec.user, $hostSpec.address
        $probe = @(& ssh -vv -p ([int]$hostSpec.port) -i $identityPath -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $destination exit 2>&1)
        $directLoginOk = $LASTEXITCODE -eq 0
        $ErrorActionPreference = $priorErrorActionPreference
        $hostKeyEvidence = [string]($probe | ForEach-Object { [string]$_ } | Where-Object { $_ -match 'Server host key: ssh-ed25519 (SHA256:\S+)' } | Select-Object -First 1)
        if ($hostKeyEvidence -match 'Server host key: ssh-ed25519 (SHA256:\S+)') {
            $observedHostFingerprint = $matches[1]
        }
        if ($directLoginOk -and $observedHostFingerprint -eq [string]$hostSpec.expected_host_ed25519_fingerprint) {
            $ErrorActionPreference = 'Continue'
            $scanLine = [string](& ssh -p ([int]$hostSpec.port) -i $identityPath -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL $destination 'cat /etc/ssh/ssh_host_ed25519_key.pub' 2>$null | Select-Object -First 1)
            $ErrorActionPreference = $priorErrorActionPreference
        }
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    $hostIdentityOk = $observedHostFingerprint -eq [string]$hostSpec.expected_host_ed25519_fingerprint

    if ($identityOk -and $hostIdentityOk) {
        $fields = @($scanLine -split '\s+')
        if ($fields.Count -lt 2 -or $fields[0] -ne 'ssh-ed25519') { throw "Unable to retrieve verified ED25519 host key for $name" }
        $knownHostLines += ('{0} {1} {2}' -f $name, $fields[0], $fields[1])
    }

    $aliases = @($hostSpec.aliases | ForEach-Object { [string]$_ })
    $configLines += ''
    $configLines += ('Host {0}' -f ($aliases -join ' '))
    $configLines += ('    HostName {0}' -f $hostSpec.address)
    $configLines += ('    User {0}' -f $hostSpec.user)
    $configLines += ('    Port {0}' -f $hostSpec.port)
    $configLines += ('    IdentityFile "{0}"' -f ($identityPath -replace '\\','/'))
    $configLines += '    IdentitiesOnly yes'
    $configLines += ('    HostKeyAlias {0}' -f $name)
    $configLines += ('    UserKnownHostsFile "{0}"' -f ($managedKnownHosts -replace '\\','/'))
    $configLines += '    StrictHostKeyChecking yes'
    $configLines += '    ServerAliveInterval 30'
    $configLines += '    ServerAliveCountMax 3'
    $configLines += '    ConnectTimeout 10'

    $results += [ordered]@{
        host = $name
        role = [string]$hostSpec.role
        aliases = $aliases
        address = [string]$hostSpec.address
        user = [string]$hostSpec.user
        port = [int]$hostSpec.port
        address_policy = [string]$hostSpec.address_policy
        identity_fingerprint = $identityFingerprint
        identity_matches_authority = $identityOk
        observed_host_fingerprint = $observedHostFingerprint
        host_identity_matches_authority = $hostIdentityOk
        key_login_ok = $false
        error = if (-not $identityOk) { 'client_identity_mismatch_or_missing' } elseif (-not $hostIdentityOk) { 'server_host_identity_mismatch_or_unreachable' } else { $null }
    }
}

if (-not $SkipConfigWrite) {
    $unsafe = @($results | Where-Object { -not $_.identity_matches_authority -or -not $_.host_identity_matches_authority })
    if ($unsafe.Count -gt 0) {
        throw ('Refusing SSH config update because authority verification failed for: {0}' -f (($unsafe.host) -join ', '))
    }
    Write-AtomicUtf8 -Path $managedKnownHosts -Content (($knownHostLines -join "`n") + "`n")
    Write-AtomicUtf8 -Path $managedConfig -Content (($configLines -join "`n") + "`n")
    $includeLine = 'Include ~/.ssh/tod-managed.conf'
    $existing = if (Test-Path -LiteralPath $mainConfig) { Get-Content -LiteralPath $mainConfig -Raw } else { '' }
    if ($existing -notmatch '(?im)^\s*Include\s+~/.ssh/tod-managed\.conf\s*$') {
        Write-AtomicUtf8 -Path $mainConfig -Content ($includeLine + "`n" + $existing.TrimStart())
    }
    foreach ($property in $registry.hosts.PSObject.Properties) {
        $hostSpec = $property.Value
        foreach ($consumer in @($hostSpec.managed_consumers)) {
            if ($null -eq $consumer -or [string]$consumer.type -ne 'dotenv') { continue }
            $consumerPath = if ([IO.Path]::IsPathRooted([string]$consumer.path)) { [string]$consumer.path } else { Join-Path $repoRoot ([string]$consumer.path) }
            Set-DotEnvAuthorityValue -Path $consumerPath -Key ([string]$consumer.key) -Value ([string]$hostSpec.address)
        }
    }
}

foreach ($result in $results) {
    if (-not $result.identity_matches_authority -or -not $result.host_identity_matches_authority) { continue }
    $output = @(& ssh -o BatchMode=yes -o ConnectTimeout=10 ([string]$result.host) 'hostname; id -un' 2>&1)
    $result.key_login_ok = $LASTEXITCODE -eq 0
    if (-not $result.key_login_ok) { $result.error = (($output -join ' ') | Select-Object -First 1) }
    else { $result.remote_hostname = [string]$output[0]; $result.remote_user = [string]$output[1] }
}

$allHealthy = @($results | Where-Object { -not $_.key_login_ok }).Count -eq 0
$report = [ordered]@{
    schema_version = 1
    generated_at = [DateTime]::UtcNow.ToString('o')
    owner = 'TOD'
    authority_registry = $registryFull
    verification_interval_minutes = [int]$registry.verification_interval_minutes
    all_hosts_key_accessible = $allHealthy
    hosts = $results
}
Write-AtomicUtf8 -Path $ReportPath -Content (($report | ConvertTo-Json -Depth 8) + "`n")
$report | ConvertTo-Json -Depth 8
if (-not $allHealthy) { exit 1 }
