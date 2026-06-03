param(
    [int]$IntervalSeconds = 30,
    [switch]$Once
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$EnvPath = Join-Path $Root ".env"
$Destination = Join-Path $Root "tod\out\context-sync"
$RemoteRoot = "/home/testpilot/mim/runtime/shared"
$Files = @(
    "TOD_IDLE_TRAINING_STATUS.latest.json",
    "MIM_READY_TASK_DISPATCHER_STATUS.latest.json"
)

function Read-MIMEnv {
    $items = Get-Content $EnvPath | Where-Object { $_ -match '^(MIM_SSH_HOST|MIM_SSH_USER|MIM_SSH_PASSWORD)=' } | ForEach-Object {
        $p = $_.Split('=', 2)
        [pscustomobject]@{ Key = $p[0]; Value = $p[1] }
    }
    @{
        Host = ($items | Where-Object Key -eq 'MIM_SSH_HOST').Value
        User = ($items | Where-Object Key -eq 'MIM_SSH_USER').Value
        Password = ($items | Where-Object Key -eq 'MIM_SSH_PASSWORD').Value
    }
}

function Write-SyncStatus {
    param(
        [string]$State,
        [string]$Message,
        [string[]]$SyncedFiles = @()
    )
    $payload = [ordered]@{
        state = $State
        message = $Message
        updated_at_local = (Get-Date).ToString("o")
        interval_seconds = $IntervalSeconds
        remote_root = $RemoteRoot
        destination = $Destination
        synced_files = $SyncedFiles
    }
    $path = Join-Path $Destination "MIM_CONTEXT_SYNC_STATUS.latest.json"
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
}

function Sync-Once {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $env = Read-MIMEnv
    $secure = ConvertTo-SecureString $env.Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($env.User, $secure)
    Import-Module Posh-SSH
    $session = New-SFTPSession -ComputerName $env.Host -Credential $credential -AcceptKey -Force
    $synced = @()
    try {
        foreach ($file in $Files) {
            $remotePath = "$RemoteRoot/$file"
            Get-SFTPItem -SessionId $session.SessionId -Path $remotePath -Destination $Destination -Force | Out-Null
            $synced += $file
        }
        Write-SyncStatus -State "ok" -Message "MIM context status files synced." -SyncedFiles $synced
    }
    finally {
        Remove-SFTPSession -SessionId $session.SessionId | Out-Null
    }
}

do {
    try {
        Sync-Once
    }
    catch {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Write-SyncStatus -State "error" -Message $_.Exception.Message
    }
    if (-not $Once) {
        Start-Sleep -Seconds $IntervalSeconds
    }
} while (-not $Once)
