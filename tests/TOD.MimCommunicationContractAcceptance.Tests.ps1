Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODMimContractAcceptance.ps1'

function Write-JsonNoBom {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function New-ContractFixture {
    param([switch]$ChecksumMismatch)

    $base = Join-Path $repoRoot ('tod/out/tests/contract-acceptance-' + [guid]::NewGuid().ToString('N'))
    $sourceDir = Join-Path $base 'source'
    New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null

    $yamlPath = Join-Path $sourceDir 'TOD_MIM_COMMUNICATION_CONTRACT.v1.yaml'
    $schemaPath = Join-Path $sourceDir 'TOD_MIM_COMMUNICATION_CONTRACT.v1.schema.json'
    $signaturePath = Join-Path $sourceDir 'TOD_MIM_COMMUNICATION_CONTRACT.v1.signature.json'
    $markdownPath = Join-Path $sourceDir 'TOD_MIM_COMMUNICATION_CONTRACT.v1.md'

    $yamlContent = @'
contract_name: TOD_MIM_COMMUNICATION_CONTRACT
contract_version: v1
schema_version: 2026-04-02-communication-contract-v1
'@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($yamlPath, $yamlContent, $utf8NoBom)
    [System.IO.File]::WriteAllText($markdownPath, "contract", $utf8NoBom)

    $schema = [pscustomobject]@{
        '$schema' = 'https://json-schema.org/draft/2020-12/schema'
        type = 'object'
        additionalProperties = $false
        required = @('contract_name', 'contract_version', 'schema_version')
        properties = [pscustomobject]@{
            contract_name = [pscustomobject]@{ type = 'string' }
            contract_version = [pscustomobject]@{ type = 'string' }
            schema_version = [pscustomobject]@{ type = 'string' }
        }
    }
    Write-JsonNoBom -PathValue $schemaPath -Payload $schema

    $hash = [string](Get-FileHash -Path $yamlPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ChecksumMismatch) {
        $hash = ('f' * 64)
    }

    $signature = [pscustomobject]@{
        contract_id = 'TOD_MIM_COMMUNICATION_CONTRACT.v1'
        schema_version = '2026-04-02-communication-contract-v1'
        sha256 = $hash
        source = 'MIM'
        timestamp = '2026-04-03T03:21:11Z'
        version = 'v1'
    }
    Write-JsonNoBom -PathValue $signaturePath -Payload $signature

    return [pscustomobject]@{
        Base = $base
        SourceDir = $sourceDir
        ReceiptPath = (Join-Path $base 'TOD_MIM_COMMUNICATION_CONTRACT_RECEIPT.v1.json')
        TransportReceiptPath = (Join-Path $base 'TOD_MIM_CONTRACT_RECEIPT.latest.json')
        RejectionPath = (Join-Path $base 'TOD_MIM_COMMUNICATION_CONTRACT_REJECTION.v1.json')
        SummaryPath = (Join-Path $base 'TOD_MIM_CONTRACT_ACCEPTANCE.latest.json')
    }
}

function Remove-TestFixturePath {
    param([string]$PathValue)
    if (-not [string]::IsNullOrWhiteSpace($PathValue) -and (Test-Path -Path $PathValue)) {
        Remove-Item -Path $PathValue -Recurse -Force
    }
}

Describe 'TOD MIM contract acceptance' {
    It 'accepts a checksum-matching schema-valid v1 contract and emits the receipt artifacts' {
        $fixture = New-ContractFixture
        try {
            $raw = & $scriptPath -LocalContractSourceDir $fixture.SourceDir -ReceiptOutputPath $fixture.ReceiptPath -TransportReceiptOutputPath $fixture.TransportReceiptPath -RejectionOutputPath $fixture.RejectionPath -SummaryOutputPath $fixture.SummaryPath -SkipRemotePublish
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.accepted | Should Be $true
            (Test-Path -Path $fixture.ReceiptPath) | Should Be $true
            (Test-Path -Path $fixture.TransportReceiptPath) | Should Be $true
            (Test-Path -Path $fixture.RejectionPath) | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }

    It 'rejects a checksum-mismatched contract and emits a rejection artifact' {
        $fixture = New-ContractFixture -ChecksumMismatch
        try {
            $raw = & $scriptPath -LocalContractSourceDir $fixture.SourceDir -ReceiptOutputPath $fixture.ReceiptPath -TransportReceiptOutputPath $fixture.TransportReceiptPath -RejectionOutputPath $fixture.RejectionPath -SummaryOutputPath $fixture.SummaryPath -SkipRemotePublish
            $doc = ($raw | Out-String | ConvertFrom-Json)
            [bool]$doc.accepted | Should Be $false
            (Test-Path -Path $fixture.RejectionPath) | Should Be $true
            (Test-Path -Path $fixture.ReceiptPath) | Should Be $false
        }
        finally {
            Remove-TestFixturePath -PathValue $(if ($fixture) { [string]$fixture.Base } else { '' })
        }
    }
}