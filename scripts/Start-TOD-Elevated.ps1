param(
    [string]$WorkspacePath = '',
    [string]$CodePath = '',
    [string]$StatusPath = '',
    [switch]$ReuseWindow,
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 10
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Resolve-CodePath {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "VS Code executable not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $candidates = @()
    $command = Get-Command code -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        $commandPath = $command.Source
        if ([System.IO.Path]::GetExtension($commandPath).Equals('.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
            $commandDirectory = Split-Path -Parent $commandPath
            $commandParent = Split-Path -Parent $commandDirectory
            $exeCandidate = Join-Path $commandParent 'Code.exe'
            $candidates += $exeCandidate
        }
        $candidates += $commandPath
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidates += (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe')
    }
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Unable to locate Code.exe. Pass -CodePath explicitly.'
}

function Resolve-WorkspacePath {
    param([string]$ExplicitPath)

    $repoRoot = Split-Path -Parent $PSScriptRoot
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if ([System.IO.Path]::IsPathRooted($ExplicitPath)) {
            return $ExplicitPath
        }
        return (Join-Path $repoRoot $ExplicitPath)
    }

    $workspaceCandidate = Join-Path $repoRoot 'TOD.code-workspace'
    if (Test-Path -LiteralPath $workspaceCandidate -PathType Leaf) {
        return $workspaceCandidate
    }

    return $repoRoot
}

function Resolve-StatusPath {
    param([string]$ExplicitPath)

    $repoRoot = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ExplicitPath)) {
        return (Join-Path $repoRoot 'tod/out/startup/tod_elevated_launch.latest.json')
    }

    if ([System.IO.Path]::IsPathRooted($ExplicitPath)) {
        return $ExplicitPath
    }

    return (Join-Path $repoRoot $ExplicitPath)
}

$resolvedCodePath = Resolve-CodePath -ExplicitPath $CodePath
$resolvedWorkspacePath = Resolve-WorkspacePath -ExplicitPath $WorkspacePath
$resolvedStatusPath = Resolve-StatusPath -ExplicitPath $StatusPath

if (-not (Test-Path -LiteralPath $resolvedWorkspacePath)) {
    throw "Workspace target not found: $resolvedWorkspacePath"
}

$codeArgs = @()
if (-not $ReuseWindow.IsPresent) {
    $codeArgs += '--new-window'
}
$codeArgs += $resolvedWorkspacePath

if ($NoLaunch.IsPresent) {
    $statusPayload = [pscustomobject]@{
        is_admin = Test-IsAdministrator
        code_path = $resolvedCodePath
        workspace_path = $resolvedWorkspacePath
        status_path = $resolvedStatusPath
        code_args = $codeArgs
    }
    Write-JsonFile -PathValue $resolvedStatusPath -Payload $statusPayload
    $statusPayload | ConvertTo-Json -Depth 4
    return
}

if (-not (Test-IsAdministrator)) {
    $selfArgs = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $PSCommandPath)
        '-CodePath'
        ('"{0}"' -f $resolvedCodePath)
        '-WorkspacePath'
        ('"{0}"' -f $resolvedWorkspacePath)
        '-StatusPath'
        ('"{0}"' -f $resolvedStatusPath)
    )
    if ($ReuseWindow.IsPresent) {
        $selfArgs += '-ReuseWindow'
    }

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $selfArgs | Out-Null
    return
}

Write-JsonFile -PathValue $resolvedStatusPath -Payload ([pscustomobject]@{
    launched_at = (Get-Date).ToUniversalTime().ToString('o')
    is_admin = $true
    code_path = $resolvedCodePath
    workspace_path = $resolvedWorkspacePath
    status_path = $resolvedStatusPath
    code_args = $codeArgs
    starter_pid = $PID
})

Start-Process -FilePath $resolvedCodePath -ArgumentList $codeArgs | Out-Null
