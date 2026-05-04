param(
    [string]$WorkspacePath = '',
    [string]$LauncherScriptPath = '',
    [string]$StatusPath = '',
    [switch]$NoRestart,
    [switch]$ReuseWindow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoPath {
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

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedWorkspacePath = if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    Join-Path $repoRoot 'TOD.code-workspace'
} else {
    Resolve-RepoPath -PathValue $WorkspacePath
}
$resolvedLauncherScriptPath = if ([string]::IsNullOrWhiteSpace($LauncherScriptPath)) {
    Join-Path $repoRoot 'scripts/Start-TOD-Elevated.ps1'
} else {
    Resolve-RepoPath -PathValue $LauncherScriptPath
}
$resolvedStatusPath = if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    Join-Path $repoRoot 'tod/out/startup/tod_watchdog.latest.json'
} else {
    Resolve-RepoPath -PathValue $StatusPath
}

if (-not (Test-Path -LiteralPath $resolvedLauncherScriptPath -PathType Leaf)) {
    throw 'Launcher script not found: ' + $resolvedLauncherScriptPath
}

$workspaceNeedle = [System.IO.Path]::GetFullPath($resolvedWorkspacePath)
$codeProcesses = @(Get-CimInstance Win32_Process -Filter "name = 'Code.exe'" -ErrorAction SilentlyContinue)
$matchingProcesses = @(
    $codeProcesses |
        Where-Object {
            $commandLine = [string]$_.CommandLine
            if ([string]::IsNullOrWhiteSpace($commandLine)) {
                return $false
            }

            if ($commandLine.IndexOf($workspaceNeedle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $true
            }

            $isTypedProcess = ($commandLine.IndexOf('--type=', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            $isExtensionHost = ($commandLine.IndexOf('--extensionHost', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            $isServerShim = ($commandLine.IndexOf('.js', [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            return (-not $isTypedProcess) -and (-not $isExtensionHost) -and (-not $isServerShim)
        }
)

$payload = [ordered]@{
    checked_at = (Get-Date).ToUniversalTime().ToString('o')
    workspace_path = $workspaceNeedle
    launcher_script_path = $resolvedLauncherScriptPath
    code_process_count = @($matchingProcesses).Count
    restarted = $false
    no_restart = [bool]$NoRestart.IsPresent
    process_ids = @($matchingProcesses | ForEach-Object { [int]$_.ProcessId })
}

if ((@($matchingProcesses).Count -eq 0) -and -not $NoRestart.IsPresent) {
    $launchArgs = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        ('"{0}"' -f $resolvedLauncherScriptPath)
        '-WorkspacePath'
        ('"{0}"' -f $workspaceNeedle)
    )
    if ($ReuseWindow.IsPresent) {
        $launchArgs += '-ReuseWindow'
    }

    Start-Process -FilePath 'powershell.exe' -ArgumentList $launchArgs | Out-Null
    $payload.restarted = $true
}

Write-JsonFile -PathValue $resolvedStatusPath -Payload $payload
[pscustomobject]$payload | ConvertTo-Json -Depth 5
