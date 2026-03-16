param(
    [string]$TaskName = "TOD-MimListener-Startup"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

$scriptPath = $MyInvocation.MyCommand.Path
if (-not (Test-IsAdmin)) {
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$scriptPath`"",
        "-TaskName", "`"$TaskName`""
    )

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList | Out-Null

    [pscustomobject]@{
        ok = $false
        requires_elevation = $true
        task_name = $TaskName
        message = "Elevation requested. Accept UAC prompt to complete SYSTEM startup task registration."
    } | ConvertTo-Json -Depth 6 | Write-Output
    return
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrap = Join-Path $PSScriptRoot "Start-TODMimListenerStartup.ps1"
if (-not (Test-Path -Path $bootstrap)) {
    throw "Missing bootstrap script: $bootstrap"
}

$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap"
$createOut = schtasks /Create /TN $TaskName /TR $tr /SC ONSTART /RU SYSTEM /RL HIGHEST /F 2>&1
$queryOut = schtasks /Query /TN $TaskName /V /FO LIST 2>&1

[pscustomobject]@{
    ok = $true
    task_name = $TaskName
    created_with = "SYSTEM_ONSTART"
    create_output = ($createOut | Out-String).Trim()
    query_output = ($queryOut | Out-String).Trim()
} | ConvertTo-Json -Depth 8 | Write-Output
