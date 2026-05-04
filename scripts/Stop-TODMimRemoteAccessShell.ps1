param(
    [string]$StatusPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = Join-Path $repoRoot 'tod/out/remote-access/mim-shell/mim-remote-access-shell.pid.json'
}

if (-not (Test-Path -LiteralPath $StatusPath)) {
    throw ("Remote access shell pid file not found at {0}" -f $StatusPath)
}

$pidState = (Get-Content -LiteralPath $StatusPath -Raw | ConvertFrom-Json)
foreach ($id in @([int]$pidState.tunnel_process_id, [int]$pidState.ui_process_id)) {
    if ($id -gt 0) {
        $null = Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', $id.ToString(), '/T', '/F') -WindowStyle Hidden -Wait -PassThru -ErrorAction SilentlyContinue
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ('Stopped TOD MIM remote access shell processes from {0}.' -f $StatusPath)