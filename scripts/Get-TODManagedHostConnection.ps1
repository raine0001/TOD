[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('todbox','mimbox')][string]$HostName,
    [string]$RegistryPath = '',
    [string]$ReportPath = ''
)

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($RegistryPath)) { $RegistryPath = Join-Path $repoRoot 'tod\config\managed-host-connections.json' }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $repoRoot 'tod\state\managed_ssh_connectivity.latest.json' }
$registry = Get-Content -LiteralPath $RegistryPath -Raw | ConvertFrom-Json
$hostSpec = $registry.hosts.$HostName
if ($null -eq $hostSpec) { throw "Unknown TOD-managed host: $HostName" }
$last = $null
if (Test-Path -LiteralPath $ReportPath) {
    $report = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
    $last = @($report.hosts | Where-Object host -eq $HostName | Select-Object -First 1)
}
[ordered]@{
    owner = 'TOD'
    host = $HostName
    role = $hostSpec.role
    connect_command = 'ssh ' + [string]$hostSpec.aliases[0]
    aliases = @($hostSpec.aliases)
    current_address = $hostSpec.address
    address_policy = $hostSpec.address_policy
    user = $hostSpec.user
    port = $hostSpec.port
    key_access_last_verified = if ($last.Count) { [bool]$last[0].key_login_ok } else { $false }
    last_verified_at = if (Test-Path -LiteralPath $ReportPath) { $report.generated_at } else { $null }
    authority_registry = (Resolve-Path -LiteralPath $RegistryPath).Path
} | ConvertTo-Json -Depth 5
