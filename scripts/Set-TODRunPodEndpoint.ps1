[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunPodHost,

    [Parameter(Mandatory = $true)]
    [int]$Port,

    [string]$User = "root",
    [string]$PythonExe = "/root/tod-venv/bin/python",
    [string]$RepoPath = "/workspace/TOD",
    [string]$SadTalkerPath = "/workspace/SadTalker",
    [string]$EnvFile = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repoRoot $EnvFile }

if (-not (Test-Path $envPath)) {
    throw ".env file not found: $envPath"
}

$content = Get-Content -Path $envPath -Raw

function Set-OrAppendEnvValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $escapedName = [regex]::Escape($Name)
    $pattern = "(?m)^$escapedName=.*$"
    $replacement = "$Name=$Value"

    if ($script:content -match $pattern) {
        $script:content = [regex]::Replace($script:content, $pattern, $replacement)
    }
    else {
        if (-not $script:content.EndsWith("`n")) {
            $script:content += "`r`n"
        }
        $script:content += "$replacement`r`n"
    }
}

Set-OrAppendEnvValue -Name "RUNPOD_SSH_HOST" -Value $RunPodHost
Set-OrAppendEnvValue -Name "RUNPOD_SSH_PORT" -Value ([string]$Port)
Set-OrAppendEnvValue -Name "RUNPOD_SSH_USER" -Value $User
Set-OrAppendEnvValue -Name "RUNPOD_PYTHON_EXE" -Value $PythonExe
Set-OrAppendEnvValue -Name "RUNPOD_REPO_PATH" -Value $RepoPath
Set-OrAppendEnvValue -Name "RUNPOD_SADTALKER_PATH" -Value $SadTalkerPath

Set-Content -Path $envPath -Value $content -Encoding UTF8

Write-Host "Updated RunPod endpoint in .env:" -ForegroundColor Green
Write-Host "  Host        : $RunPodHost" -ForegroundColor DarkGray
Write-Host "  Port        : $Port" -ForegroundColor DarkGray
Write-Host "  User        : $User" -ForegroundColor DarkGray
Write-Host "  Python      : $PythonExe" -ForegroundColor DarkGray
Write-Host "  Repo path   : $RepoPath" -ForegroundColor DarkGray
Write-Host "  SadTalker   : $SadTalkerPath" -ForegroundColor DarkGray