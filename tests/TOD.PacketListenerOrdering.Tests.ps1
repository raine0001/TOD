Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'

function Import-ListenerFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($listenerScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $listenerScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $listenerScript"
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

Describe 'TOD packet listener ordering hardening' {
    BeforeAll {
        Import-ListenerFunction -Name 'Get-UtcNowString'
        Import-ListenerFunction -Name 'Get-ObjectFieldLong'
        Import-ListenerFunction -Name 'Get-TaskOrdinalInfo'
        Import-ListenerFunction -Name 'Get-RequestOrderingInfo'
        Import-ListenerFunction -Name 'Test-RequestOrderingIsStale'
        Import-ListenerFunction -Name 'Update-TaskHighWatermark'
        Import-ListenerFunction -Name 'Get-RetryWeight'
        Import-ListenerFunction -Name 'Update-CadencePlan'
    }

    It 'prefers explicit request sequence over request-id suffix ordering' {
        $state = [pscustomobject]@{
            high_watermark_request_id = ''
            high_watermark_objective_id = ''
            high_watermark_ordinal = 0L
            high_watermark_sequence = 0L
        }

        $olderBySuffix = [pscustomobject]@{
            request_id = 'objective-306-task-mim-arm-safe-home-20260403171131'
            task_id = 'objective-306-task-mim-arm-safe-home-20260403171131'
            sequence = 100
        }
        $newerBySequence = [pscustomobject]@{
            request_id = 'objective-306-task-mim-arm-scan-pose-1775330845'
            task_id = 'objective-306-task-mim-arm-scan-pose-1775330845'
            sequence = 200
        }

        $olderInfo = Get-RequestOrderingInfo -Request $olderBySuffix -RequestId $olderBySuffix.request_id -FallbackObjectiveId '306'
        $highWatermark = Update-TaskHighWatermark -State $state -CandidateInfo $olderInfo
        $newerInfo = Get-RequestOrderingInfo -Request $newerBySequence -RequestId $newerBySequence.request_id -FallbackObjectiveId '306'
        $highWatermark = Update-TaskHighWatermark -State $state -CandidateInfo $newerInfo

        [string]$highWatermark.raw | Should Be 'objective-306-task-mim-arm-scan-pose-1775330845'
        [long]$highWatermark.sequence | Should Be 200
        [string]$highWatermark.source_field | Should Be 'high_watermark_sequence'
        (Test-RequestOrderingIsStale -RequestOrderingInfo $olderInfo -HighWatermark $highWatermark) | Should Be $true
        (Test-RequestOrderingIsStale -RequestOrderingInfo $newerInfo -HighWatermark $highWatermark) | Should Be $false
    }

    It 'treats duplicate-seen cycles as cadence noise without inflating retry streaks' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/packet-listener-ordering-' + [guid]::NewGuid().ToString('N'))
        $statePath = Join-Path $fixture 'listener_state.json'
        $state = [pscustomobject]@{
            cadence_retry_streak = 12
            cadence_backoff_seconds = 18
            cadence_last_success_at = ''
            last_cycle_classification = ''
            last_retry_reason = ''
            cadence_minimum_cycle_seconds = 0
            cadence_planned_sleep_seconds = 0
        }

        $plan = Update-CadencePlan -ListenerState $state -ListenerStatePath $statePath -CycleClassification 'duplicate_seen' -RetryReason 'duplicate_seen' -BasePollSeconds 2

        [int]$plan.retry_streak | Should Be 0
        [int]$plan.backoff_seconds | Should Be 4
        [bool]$plan.cadence_noise | Should Be $true
        [int]$state.cadence_retry_streak | Should Be 0
        [int]$state.cadence_backoff_seconds | Should Be 4
        [string]$state.last_retry_reason | Should Be 'duplicate_seen'
        [string]$state.last_cycle_classification | Should Be 'duplicate_seen'
        ([string]::IsNullOrWhiteSpace([string]$state.cadence_last_success_at)) | Should Be $false
        (Test-Path -Path $statePath) | Should Be $true
    }
}
