Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODMimFormalContractAgreement.ps1'

function Import-AgreementFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw 'Failed to parse ' + $scriptPath
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $scriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ('function\s+{0}\b' -f [regex]::Escape($Name)), ('function global:{0}' -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD MIM formal contract agreement' {
    BeforeAll {
        Import-AgreementFunction -Name 'Get-DateOrMinValue'
        Import-AgreementFunction -Name 'Get-FormalAgreementAssessment'
    }

    It 'marks the contract as agreed when TOD receipt, remote receipt, and MIM lock all match' {
        $acceptance = [pscustomobject]@{
            accepted = $true
            validation = [pscustomobject]@{
                actual_sha256 = 'abc123'
                contract_version = 'v1'
            }
        }
        $remoteReceipt = [pscustomobject]@{
            generated_at = '2026-04-08T14:53:51Z'
            acceptance_status = 'accepted'
            checksum_sha256 = 'abc123'
            contract_version = 'v1'
        }
        $remoteLock = [pscustomobject]@{
            runtime_lock = 'active'
            sha256 = 'abc123'
            contract_version = 'v1'
        }
        $activation = [pscustomobject]@{
            generated_at = '2026-04-08T14:00:00Z'
            tod_receipt_status = [pscustomobject]@{
                receipt_present = $false
                checksum_match = $false
            }
            cutover_readiness = [pscustomobject]@{
                ready = $false
            }
        }
        $validationFailure = [pscustomobject]@{
            generated_at = '2026-04-08T14:00:00Z'
        }

        $result = Get-FormalAgreementAssessment -AcceptanceSummary $acceptance -RemoteReceipt $remoteReceipt -RemoteLock $remoteLock -ActivationReport $activation -ValidationFailure $validationFailure

        [bool]$result.formal_agreement_reached | Should Be $true
        [string]$result.agreement_status | Should Be 'agreed'
        [string]$result.activation_report_state | Should Be 'stale_pending_refresh'
        [string]$result.validation_failure_state | Should Be 'stale_pre_agreement'
    }

    It 'marks the contract as not agreed when the checksum does not align' {
        $acceptance = [pscustomobject]@{
            accepted = $true
            validation = [pscustomobject]@{
                actual_sha256 = 'abc123'
                contract_version = 'v1'
            }
        }
        $remoteReceipt = [pscustomobject]@{
            acceptance_status = 'accepted'
            checksum_sha256 = 'zzz999'
            contract_version = 'v1'
        }
        $remoteLock = [pscustomobject]@{
            runtime_lock = 'active'
            sha256 = 'abc123'
            contract_version = 'v1'
        }

        $result = Get-FormalAgreementAssessment -AcceptanceSummary $acceptance -RemoteReceipt $remoteReceipt -RemoteLock $remoteLock -ActivationReport $null -ValidationFailure $null

        [bool]$result.formal_agreement_reached | Should Be $false
        [string]$result.agreement_status | Should Be 'not_agreed'
        [bool]$result.checksum_aligned | Should Be $false
    }
}