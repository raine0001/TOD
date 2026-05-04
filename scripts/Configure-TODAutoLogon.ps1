param(
    [string]$UserName = '',
    [string]$Password = '',
    [string]$DomainName = '',
    [switch]$Enable,
    [switch]$Disable,
    [switch]$NoApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Enable.IsPresent -and $Disable.IsPresent) {
    throw 'Choose either -Enable or -Disable, not both.'
}

$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$currentUser = [string](Get-CimInstance Win32_ComputerSystem).UserName
$resolvedUser = $UserName
$resolvedDomain = $DomainName

if ([string]::IsNullOrWhiteSpace($resolvedUser) -and -not [string]::IsNullOrWhiteSpace($currentUser)) {
    $parts = $currentUser -split '\\', 2
    if ($parts.Count -eq 2) {
        if ([string]::IsNullOrWhiteSpace($resolvedDomain)) {
            $resolvedDomain = $parts[0]
        }
        $resolvedUser = $parts[1]
    }
    else {
        $resolvedUser = $currentUser
    }
}

if ([string]::IsNullOrWhiteSpace($resolvedDomain)) {
    $resolvedDomain = $env:COMPUTERNAME
}

$plan = [ordered]@{
    action = if ($Disable.IsPresent) { 'disable' } else { 'enable' }
    user_name = $resolvedUser
    domain_name = $resolvedDomain
    no_apply = [bool]$NoApply.IsPresent
}

if ($NoApply.IsPresent) {
    [pscustomobject]$plan | ConvertTo-Json -Depth 4
    return
}

if ($Disable.IsPresent) {
    Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '0' -Type String
    Remove-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -ErrorAction SilentlyContinue
    [pscustomobject]@{
        action = 'disable'
        applied = $true
        user_name = $resolvedUser
        domain_name = $resolvedDomain
    } | ConvertTo-Json -Depth 4
    return
}

if ([string]::IsNullOrWhiteSpace($resolvedUser)) {
    throw 'User name is required to enable auto-logon.'
}
if ([string]::IsNullOrWhiteSpace($Password)) {
    throw 'Password is required to enable auto-logon.'
}

Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '1' -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultUserName' -Value $resolvedUser -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultDomainName' -Value $resolvedDomain -Type String
Set-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -Value $Password -Type String
Set-ItemProperty -Path $winlogonPath -Name 'ForceAutoLogon' -Value '1' -Type String

[pscustomobject]@{
    action = 'enable'
    applied = $true
    user_name = $resolvedUser
    domain_name = $resolvedDomain
} | ConvertTo-Json -Depth 4
