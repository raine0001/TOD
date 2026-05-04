Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$watchdogScript = Join-Path $repoRoot 'scripts/Start-TODRecoveryWatchdog.ps1'

function Import-WatchdogFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($watchdogScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $watchdogScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $watchdogScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD recovery watchdog coordination fallback' {
    BeforeAll {
        Import-WatchdogFunction -Name 'Normalize-ObjectiveIdentity'
        Import-WatchdogFunction -Name 'Convert-ToObjectiveLabel'
        Import-WatchdogFunction -Name 'Test-PublicationSurfaceRecoveryNeeded'
        Import-WatchdogFunction -Name 'New-PublicationSurfaceCoordinationRequest'
        Import-WatchdogFunction -Name 'New-PublicationSurfaceEmergencyRequest'
        Import-WatchdogFunction -Name 'Get-CanonicalObjectiveForSelfHeal'
        Import-WatchdogFunction -Name 'New-CanonicalRepublishTaskRequest'
    }

    It 'prefers authority reset objective when choosing self-heal target' {
        $integrationStatus = [pscustomobject]@{
            objective_authority_reset = [pscustomobject]@{
                active = $true
                authoritative_current_objective = '152'
            }
            objective_alignment = [pscustomobject]@{
                tod_current_objective = '170'
            }
        }
        $bridgeSmoke = [pscustomobject]@{
            canonical_request = [pscustomobject]@{
                expected_objective_id = 'objective-170'
            }
        }

        $canonicalObjective = Get-CanonicalObjectiveForSelfHeal -IntegrationStatus $integrationStatus -BridgeSmoke $bridgeSmoke

        [string]$canonicalObjective | Should Be 'objective-152'
    }

    It 'builds a canonical republish request with objective-scoped task identity' {
        $request = New-CanonicalRepublishTaskRequest -ObjectiveId '152'

        [string]$request.objective_id | Should Be 'objective-152'
        [string]$request.request_id | Should Match '^objective-152-task-\d+$'
        [string]$request.task_id | Should Be ([string]$request.request_id)
        [string]$request.source_service | Should Be 'tod_watchdog_autorepair'
        [int64]$request.sequence | Should BeGreaterThan 0
    }

    It 'keeps publication divergence recovery active after local terminal completion when canonical MIM is ahead' {
        $bridgeSmoke = [pscustomobject]@{
            passed = $false
            classification = 'publication_surface_divergence'
            canonical_request = [pscustomobject]@{
                expected_objective_id = 'objective-170'
                remote_surface = [pscustomobject]@{
                    objective_id = 'objective-152'
                    request_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                    task_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
                }
            }
            local_bridge = [pscustomobject]@{
                request_id = 'objective-152-task-mim-arm-safe-home-20260408160030'
            }
        }

        $needsRecovery = Test-PublicationSurfaceRecoveryNeeded -BridgeSmoke $bridgeSmoke -BridgeFailureModes @('publication_surface_divergence', 'stale_remote_request_identity') -LocalTerminalRequestFinished $true

        $needsRecovery | Should Be $true
    }

    It 'builds a concrete republish coordination request for publication surface divergence' {
        $bridgeSmoke = [pscustomobject]@{
            classification = 'publication_surface_divergence'
            canonical_request = [pscustomobject]@{
                expected_objective_id = 'objective-122'
                remote_surface = [pscustomobject]@{
                    objective_id = 'objective-115'
                    task_id = 'objective-115-task-mim-arm-capture-frame-20260407033825'
                }
            }
            local_bridge = [pscustomobject]@{
                request_id = 'objective-115-task-mim-arm-capture-frame-20260407033825'
            }
            remote_boundary = [pscustomobject]@{
                classification = 'publication_surface_divergence'
            }
        }

        $request = New-PublicationSurfaceCoordinationRequest -IssueCode 'publication_surface_divergence' -IssueDetail 'Remote canonical request surface diverges from the expected live publication boundary.' -AlertSignature 'sig-123' -RequestId 'objective-115-task-mim-arm-capture-frame-20260407033825' -BridgeFailureModes @('publication_surface_divergence', 'stale_remote_request_identity') -BridgeSmoke $bridgeSmoke

        [string]$request.source | Should Be 'tod-mim-coordination-request-v1'
        [string]$request.issue_code | Should Be 'publication_surface_divergence'
        [string]$request.objective_id | Should Be 'objective-122'
        [string]$request.task_id | Should Be 'objective-115-task-mim-arm-capture-frame-20260407033825'
        [string]$request.requested_action | Should Match 'Republish the live task-request surface from the canonical MIM objective'
        [string]$request.evidence.canonical_expected_objective_id | Should Be 'objective-122'
        [string]$request.evidence.stale_live_task_request_objective_id | Should Be 'objective-115'
        @($request.evidence.bridge_failure_modes).Count | Should Be 2
        [string]$request.required_ack.ack_file | Should Be 'MIM_TOD_COORDINATION_ACK.latest.json'
    }

    It 'builds an emergency request when publication divergence remains unresolved' {
        $bridgeSmoke = [pscustomobject]@{
            classification = 'publication_surface_divergence'
            canonical_request = [pscustomobject]@{
                expected_objective_id = 'objective-122'
                remote_surface = [pscustomobject]@{
                    objective_id = 'objective-115'
                    task_id = 'objective-115-task-mim-arm-capture-frame-20260407033825'
                }
            }
        }

        $request = New-PublicationSurfaceEmergencyRequest -IssueCode 'publication_surface_divergence' -IssueDetail 'Remote canonical request surface diverges from the expected live publication boundary.' -ParentRequestId 'objective-115-task-mim-arm-capture-frame-20260407033825' -ElapsedIssueSeconds 240 -BridgeSmoke $bridgeSmoke -CoordinationRequestId 'coordination-objective-115-publication_surface_divergence'

        [string]$request.source | Should Be 'tod-mim-emergency-request-v1'
        [string]$request.status | Should Be 'active'
        [string]$request.issue_code | Should Be 'publication_surface_divergence_emergency'
        [string]$request.objective_id | Should Be 'objective-122'
        [string]$request.parent_request_id | Should Be 'coordination-objective-115-publication_surface_divergence'
        [string]$request.required_ack.ack_file | Should Be 'MIM_TOD_EMERGENCY_ACK.latest.json'
        [string]$request.requested_action | Should Match 'Reply immediately on MIM_TOD_EMERGENCY_ACK.latest.json'
    }
}
