<#
.SYNOPSIS
    Registers a PowerShell profile function for RunPod Gloria renders.

.DESCRIPTION
    Adds/updates a managed block in the current user's PowerShell profile that
    exposes:
      - goTODRunPodGloria

    The function forwards parameters to scripts/goTODRunPodGloria.ps1.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$launcherPath = Join-Path $PSScriptRoot "goTODRunPodGloria.ps1"
if (-not (Test-Path $launcherPath)) {
    throw "Launcher script not found: $launcherPath"
}

$startMarker = "# >>> TOD RUNPOD GLORIA START >>>"
$endMarker = "# <<< TOD RUNPOD GLORIA END <<<"

$managedBlock = @"
$startMarker
function goTODRunPodGloria {
    [CmdletBinding()]
    param(
        [string]`$RunPodHost = "",
        [string]`$RunPodUser = "root",
        [int]`$RunPodPort = 22,
        [string]`$RunPodKeyPath = "",
        [string]`$RemoteRepoPath = "",
        [string]`$RemoteSadTalkerPath = "",
        [string]`$RemotePythonExe = "",
        [string]`$OutputPath = "",
        [switch]`$SkipSmoothing,
        [switch]`$DryRun
    )

    & "$launcherPath" @PSBoundParameters
}
$endMarker
"@

function Update-ProfileFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Block,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }

    $text = Get-Content -Path $Path -Raw
    $pattern = [regex]::Escape($Start) + ".*?" + [regex]::Escape($End)
    if ($text -match $pattern) {
        $updated = [regex]::Replace($text, $pattern, $Block, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
        $newline = if ([string]::IsNullOrWhiteSpace($text)) { "" } else { [Environment]::NewLine + [Environment]::NewLine }
        $updated = $text + $newline + $Block
    }

    Set-Content -Path $Path -Value $updated -Encoding UTF8
}

$documents = [Environment]::GetFolderPath("MyDocuments")
$candidateProfiles = @(
    if ($PROFILE -is [string]) { $PROFILE } else { $PROFILE.CurrentUserCurrentHost },
    (Join-Path $documents "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
    (Join-Path $documents "PowerShell\Microsoft.PowerShell_profile.ps1")
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

foreach ($path in $candidateProfiles) {
    Update-ProfileFile -Path $path -Block $managedBlock -Start $startMarker -End $endMarker
}

Write-Host "Registered goTODRunPodGloria in profiles:" -ForegroundColor Green
foreach ($path in $candidateProfiles) {
    Write-Host "  $path" -ForegroundColor DarkGray
}
Write-Host "Reload with: . `$PROFILE" -ForegroundColor DarkGray
