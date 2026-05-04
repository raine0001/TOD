Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'
$uiScript = Join-Path $repoRoot 'scripts/Start-TOD-UI.ps1'

function Import-FunctionFromFile {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $FilePath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $FilePath"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

function Write-RemoteFileFromText {
    param(
        $Connections,
        [string]$RemotePath,
        [string]$Content
    )

    $script:lastRemoteWrite = [pscustomobject]@{
        Connections = $Connections
        RemotePath = $RemotePath
        Content = $Content
    }
}

function Read-JsonFileIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Get-IsoAgeSeconds {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return -1
    }

    try {
        $timestamp = [DateTime]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        return [int][Math]::Floor(((Get-Date).ToUniversalTime() - $timestamp.ToUniversalTime()).TotalSeconds)
    }
    catch {
        return -1
    }
}

function Get-DialogSessionsPayload {
    param(
        [int]$Limit = 6,
        [string]$Actor = 'TOD'
    )

    return [pscustomobject]@{
        available = $true
        open_count = 0
        timed_out_count = 0
        closed_count = 0
        total_count = 0
        sessions = @()
    }
}

Describe 'TOD coordination emergency protocol' {
    BeforeAll {
        Import-FunctionFromFile -FilePath $listenerScript -Name 'Get-DateOrMinValue'
        Import-FunctionFromFile -FilePath $listenerScript -Name 'New-CoordinationEscalationState'
        Import-FunctionFromFile -FilePath $listenerScript -Name 'Publish-EmergencyCoordinationRequest'
        Import-FunctionFromFile -FilePath $listenerScript -Name 'Publish-ResolvedEmergencyCoordination'
        Import-FunctionFromFile -FilePath $uiScript -Name 'Get-CommunicationHealth'
    }

    It 'publishes an emergency request when coordination misses its SLA' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/coordination-emergency-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $statePath = Join-Path $fixture 'state.json'
            $emergencyPath = Join-Path $fixture 'TOD_MIM_EMERGENCY_REQUEST.latest.json'
            $state = New-CoordinationEscalationState -ExistingState $null

            $request = Publish-EmergencyCoordinationRequest -CoordinationEscalationState $state -CoordinationEscalationStatePath $statePath -LocalEmergencyRequestPath $emergencyPath -RemoteEmergencyRequestPath '/remote/TOD_MIM_EMERGENCY_REQUEST.latest.json' -Connections ([pscustomobject]@{ session = 'mock' }) -ParentRequestId 'objective-115-task-mim-arm-capture-frame-20260407033825' -ObjectiveId 'objective-122' -IssueCode 'publication_surface_divergence' -IssueSummary 'Canonical export is ahead of live publication.' -AckStatus 'pending' -AckDecision '' -AckReason '' -CoordinationTimeoutSeconds 60 -ElapsedSeconds 180 -CoordinationRequest ([pscustomobject]@{ request_id = 'coord-1' }) -BridgeRuntime ([pscustomobject]@{ status = 'warning' })

            [string]$request.source | Should Be 'tod-mim-emergency-request-v1'
            [string]$request.status | Should Be 'active'
            [string]$request.issue_code | Should Be 'publication_surface_divergence_emergency'
            [string]$request.parent_request_id | Should Be 'objective-115-task-mim-arm-capture-frame-20260407033825'
            [string]$request.required_ack.ack_file | Should Be 'MIM_TOD_EMERGENCY_ACK.latest.json'
            (Test-Path -Path $emergencyPath) | Should Be $true
            [string]$state.pending_emergency_request_id | Should Not BeNullOrEmpty
            [string]$state.pending_emergency_issue_code | Should Be 'publication_surface_divergence_emergency'
            [int]$state.emergency_emit_count | Should Be 1
            [string]$script:lastRemoteWrite.RemotePath | Should Be '/remote/TOD_MIM_EMERGENCY_REQUEST.latest.json'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'promotes active emergency coordination to critical communication health' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/coordination-emergency-ui-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $script:coordinationEscalationPath = Join-Path $fixture 'coordination.json'
            $script:dialogDirPath = Join-Path $fixture 'dialog'
            $script:listenerEmergencyRequestPath = Join-Path $fixture 'TOD_MIM_EMERGENCY_REQUEST.latest.json'
            $script:listenerEmergencyAckPath = Join-Path $fixture 'MIM_TOD_EMERGENCY_ACK.latest.json'

            Write-JsonFile -PathValue $script:listenerEmergencyRequestPath -Payload ([pscustomobject]@{
                generated_at = (Get-Date).ToUniversalTime().AddSeconds(-45).ToString('o')
                source = 'tod-mim-emergency-request-v1'
                status = 'active'
                request_id = 'tod-emergency-objective-115-publication_surface_divergence'
                issue_code = 'publication_surface_divergence_emergency'
                issue_summary = 'Canonical export is ahead of live publication.'
            })

            $health = Get-CommunicationHealth -ListenerActivity ([pscustomobject]@{
                    latest_request_id = 'objective-115-task-mim-arm-capture-frame-20260407033825'
                    latest_execution_status = 'completed'
                }) -BridgeStatus ([pscustomobject]@{
                    available = $true
                    status = 'ok'
                    canonical_mim_objective_id = 'objective-122'
                    task_request_objective_id = 'objective-115'
                    objective_mismatch = $true
                    objective_mismatch_detail = 'Canonical export shows objective 122 while live task-request publication remains objective 115.'
                }) -RecoveryWatchdog ([pscustomobject]@{
                    last_issue = 'publication_surface_divergence'
                })

            [string]$health.status | Should Be 'critical'
            [string]$health.emergency_status | Should Be 'pending'
            [string]$health.emergency_issue_code | Should Be 'publication_surface_divergence_emergency'
            [string]$health.summary | Should Match 'Emergency coordination is active'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}
