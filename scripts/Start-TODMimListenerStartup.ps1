Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$listenerScript = Join-Path $scriptRoot "Start-TODMimPacketListener.ps1"

if (-not (Test-Path -Path $listenerScript)) {
    throw "Missing listener script: $listenerScript"
}

& $listenerScript -PollSeconds 2 -RegressionNoDeltaThreshold 4 -EnvFile ".env" -RemoteRoot "/home/testpilot/mim/runtime/shared" -StageDir "tod/out/context-sync/listener" -PublishIntegrationStatus
