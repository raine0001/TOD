param(
    [string]$ContractHost = "192.168.1.120",
    [string]$ContractUser = "testpilot",
    [int]$ContractPort = 22,
    [string]$ContractPassword = "",
    [string]$DotEnvPath = ".env",
    [string]$RemoteContractDir = "/home/testpilot/mim/contracts",
    [string]$RemoteReceiptDir = "/home/testpilot/mim/runtime/shared",
    [string]$LocalContractDir = "tod/out/context-sync/contracts",
    [string]$LocalContractSourceDir = "",
    [string]$ValidatorScriptPath = "scripts/validate_tod_mim_contract.py",
    [string]$ReceiptOutputPath = "tod/out/context-sync/contracts/TOD_MIM_COMMUNICATION_CONTRACT_RECEIPT.v1.json",
    [string]$TransportReceiptOutputPath = "tod/out/context-sync/contracts/TOD_MIM_CONTRACT_RECEIPT.latest.json",
    [string]$RejectionOutputPath = "tod/out/context-sync/contracts/TOD_MIM_COMMUNICATION_CONTRACT_REJECTION.v1.json",
    [string]$SummaryOutputPath = "shared_state/TOD_MIM_CONTRACT_ACCEPTANCE.latest.json",
    [switch]$SkipRemotePublish,
    [switch]$FailOnReject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        Ensure-Directory -PathValue $dir
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, ($Payload | ConvertTo-Json -Depth $Depth), $utf8NoBom)
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        return ""
    }

    $line = Get-Content -Path $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
    if (-not $line) {
        return ""
    }

    return (($line -replace "^\s*$Name\s*=\s*", "").Trim().Trim('"').Trim("'"))
}

function Get-PythonCommand {
    $venvPython = Join-Path $repoRoot ".venv/Scripts/python.exe"
    if (Test-Path -Path $venvPython -PathType Leaf) {
        return $venvPython
    }

    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        return $pythonCmd.Source
    }

    throw "python_not_found"
}

function New-SshConnections {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password
    )

    Import-Module Posh-SSH -ErrorAction Stop | Out-Null
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $credential = [pscredential]::new($UserName, $securePassword)
    return [pscustomobject]@{
        sftp = New-SFTPSession -ComputerName $HostName -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
        ssh = New-SSHSession -ComputerName $HostName -Port $Port -Credential $credential -AcceptKey -ConnectionTimeout 15000
    }
}

function Close-SshConnections {
    param($Connections)

    if ($null -eq $Connections) { return }
    try {
        if ($Connections.sftp) {
            Remove-SFTPSession -SessionId ([int]$Connections.sftp.SessionId) | Out-Null
        }
    }
    catch {
    }
    try {
        if ($Connections.ssh) {
            Remove-SSHSession -SessionId ([int]$Connections.ssh.SessionId) | Out-Null
        }
    }
    catch {
    }
}

function Copy-RemoteFileToLocal {
    param(
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $destinationDir = Split-Path -Parent $LocalPath
    Ensure-Directory -PathValue $destinationDir
    Get-SFTPItem -SessionId $SessionId -Path $RemotePath -Destination $destinationDir -Force -ErrorAction Stop | Out-Null
    if (-not (Test-Path -Path $LocalPath -PathType Leaf)) {
        throw ("download_failed: {0}" -f $RemotePath)
    }
}

function Publish-ReceiptToRemote {
    param(
        [Parameter(Mandatory = $true)]$Connections,
        [Parameter(Mandatory = $true)][string]$RemoteDir,
        [Parameter(Mandatory = $true)][string]$LocalReceiptPath
    )

    $mkdirCommand = "mkdir -p '{0}'" -f $RemoteDir.Replace("'", "'\''")
    Invoke-SSHCommand -SessionId ([int]$Connections.ssh.SessionId) -Command $mkdirCommand -TimeOut 60 | Out-Null
    Set-SFTPItem -SessionId ([int]$Connections.sftp.SessionId) -Path $LocalReceiptPath -Destination $RemoteDir -Force -ErrorAction Stop | Out-Null
}

function Get-ConflictingContractVersions {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    if (-not (Test-Path -Path $DirectoryPath)) {
        return @()
    }

    return @(
        Get-ChildItem -Path $DirectoryPath -File -Filter 'TOD_MIM_COMMUNICATION_CONTRACT.v*.yaml' |
            Where-Object { $_.Name -ne 'TOD_MIM_COMMUNICATION_CONTRACT.v1.yaml' } |
            Select-Object -ExpandProperty FullName
    )
}

$dotEnvAbs = Resolve-LocalPath -PathValue $DotEnvPath
if ([string]::IsNullOrWhiteSpace($ContractPassword)) {
    $ContractPassword = Get-DotEnvValue -Path $dotEnvAbs -Name 'MIM_SSH_PASSWORD'
}

if ([string]::IsNullOrWhiteSpace($ContractPassword)) {
    throw 'missing_contract_password'
}

$localContractDirAbs = Resolve-LocalPath -PathValue $LocalContractDir
Ensure-Directory -PathValue $localContractDirAbs

$receiptOutputAbs = Resolve-LocalPath -PathValue $ReceiptOutputPath
$transportReceiptOutputAbs = Resolve-LocalPath -PathValue $TransportReceiptOutputPath
$rejectionOutputAbs = Resolve-LocalPath -PathValue $RejectionOutputPath
$summaryOutputAbs = Resolve-LocalPath -PathValue $SummaryOutputPath
$validatorScriptAbs = Resolve-LocalPath -PathValue $ValidatorScriptPath
$pythonCommand = Get-PythonCommand

$sourceDirAbs = if ([string]::IsNullOrWhiteSpace($LocalContractSourceDir)) { $localContractDirAbs } else { Resolve-LocalPath -PathValue $LocalContractSourceDir }
$connections = $null

if ([string]::IsNullOrWhiteSpace($LocalContractSourceDir)) {
    $connections = New-SshConnections -HostName $ContractHost -UserName $ContractUser -Port $ContractPort -Password $ContractPassword
    try {
        foreach ($name in @('TOD_MIM_COMMUNICATION_CONTRACT.v1.yaml', 'TOD_MIM_COMMUNICATION_CONTRACT.v1.schema.json', 'TOD_MIM_COMMUNICATION_CONTRACT.v1.signature.json', 'TOD_MIM_COMMUNICATION_CONTRACT.v1.md')) {
            $remotePath = "{0}/{1}" -f $RemoteContractDir.TrimEnd('/'), $name
            $localPath = Join-Path $localContractDirAbs $name
            Copy-RemoteFileToLocal -SessionId ([int]$connections.sftp.SessionId) -RemotePath $remotePath -LocalPath $localPath
        }
    }
    finally {
        Close-SshConnections -Connections $connections
        $connections = $null
    }
}

$yamlPath = Join-Path $sourceDirAbs 'TOD_MIM_COMMUNICATION_CONTRACT.v1.yaml'
$schemaPath = Join-Path $sourceDirAbs 'TOD_MIM_COMMUNICATION_CONTRACT.v1.schema.json'
$signaturePath = Join-Path $sourceDirAbs 'TOD_MIM_COMMUNICATION_CONTRACT.v1.signature.json'

foreach ($requiredPath in @($yamlPath, $schemaPath, $signaturePath)) {
    if (-not (Test-Path -Path $requiredPath -PathType Leaf)) {
        throw ("missing_required_contract_artifact: {0}" -f $requiredPath)
    }
}

$conflictingVersions = @(Get-ConflictingContractVersions -DirectoryPath $sourceDirAbs)
$rawValidation = & $pythonCommand $validatorScriptAbs --yaml $yamlPath --schema $schemaPath --signature $signaturePath
if ($LASTEXITCODE -ne 0) {
    throw 'contract_validator_failed'
}

$validation = ($rawValidation | Out-String | ConvertFrom-Json)
$validationErrors = New-Object System.Collections.Generic.List[string]
foreach ($err in @($validation.errors)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$err)) {
        $validationErrors.Add([string]$err)
    }
}
if (@($conflictingVersions).Count -gt 0) {
    $validationErrors.Add('conflicting_contract_versions_active')
}

$accepted = [bool]$validation.passed -and (@($conflictingVersions).Count -eq 0)
$hostName = if (-not [string]::IsNullOrWhiteSpace([string]$env:COMPUTERNAME)) { [string]$env:COMPUTERNAME } else { [System.Environment]::MachineName }
$userName = if (-not [string]::IsNullOrWhiteSpace([string]$env:USERNAME)) { [string]$env:USERNAME } else { [System.Environment]::UserName }
$instanceId = "{0}:{1}" -f $hostName, $PID
$timestamp = (Get-Date).ToUniversalTime().ToString('o')

$receipt = [pscustomobject]@{
    generated_at = $timestamp
    source = 'tod-mim-contract-acceptance-v1'
    packet_type = 'tod-mim-contract-receipt-v1'
    contract_name = [string]$validation.contract_name
    contract_version = [string]$validation.contract_version
    schema_version = [string]$validation.schema_version
    checksum_sha256 = [string]$validation.actual_sha256
    expected_checksum_sha256 = [string]$validation.expected_sha256
    checksum_match = [bool]$validation.checksum_match
    version_accepted = [bool]$validation.version_ok
    schema_valid = [bool]$validation.schema_valid
    no_reinterpretation_confirmed = $true
    acceptance_status = if ($accepted) { 'accepted' } else { 'rejected' }
    tod_identity = [pscustomobject]@{
        host = $hostName
        user = $userName
        service = 'tod-mim-contract-acceptance'
        instance_id = $instanceId
    }
    remote_contract_host = $ContractHost
    remote_contract_dir = $RemoteContractDir
    remote_receipt_dir = $RemoteReceiptDir
    conflicting_versions = @($conflictingVersions)
}

$summary = [pscustomobject]@{
    generated_at = $timestamp
    source = 'tod-mim-contract-acceptance-v1'
    accepted = [bool]$accepted
    validation = $validation
    conflicting_versions = @($conflictingVersions)
    receipt_path = $receiptOutputAbs
    transport_receipt_path = $transportReceiptOutputAbs
    rejection_path = $rejectionOutputAbs
    remote_publish = [pscustomobject]@{
        attempted = [bool](-not $SkipRemotePublish -and $accepted)
        published = $false
        remote_dir = $RemoteReceiptDir
        remote_file = if ($accepted) { "{0}/TOD_MIM_CONTRACT_RECEIPT.latest.json" -f $RemoteReceiptDir.TrimEnd('/') } else { '' }
        error = ''
    }
}

if ($accepted) {
    Write-Utf8NoBomJson -PathValue $receiptOutputAbs -Payload $receipt
    Write-Utf8NoBomJson -PathValue $transportReceiptOutputAbs -Payload $receipt
    if (-not $SkipRemotePublish) {
        $connections = New-SshConnections -HostName $ContractHost -UserName $ContractUser -Port $ContractPort -Password $ContractPassword
        try {
            Publish-ReceiptToRemote -Connections $connections -RemoteDir $RemoteReceiptDir -LocalReceiptPath $transportReceiptOutputAbs
            $summary.remote_publish.published = $true
        }
        catch {
            $summary.remote_publish.error = [string]$_.Exception.Message
        }
        finally {
            Close-SshConnections -Connections $connections
            $connections = $null
        }
    }
}
else {
    $rejection = [pscustomobject]@{
        generated_at = $timestamp
        source = 'tod-mim-contract-acceptance-v1'
        contract_name = [string]$validation.contract_name
        contract_version = [string]$validation.contract_version
        acceptance_status = 'rejected'
        checksum_sha256 = [string]$validation.actual_sha256
        expected_checksum_sha256 = [string]$validation.expected_sha256
        reason = if (@($validationErrors).Count -gt 0) { [string]$validationErrors[0] } else { 'contract_validation_failed' }
        failed_section = if (@($validationErrors).Count -gt 0) { [string]$validationErrors[0] } else { 'unknown' }
        details = @($validationErrors)
        tod_identity = $receipt.tod_identity
    }
    Write-Utf8NoBomJson -PathValue $rejectionOutputAbs -Payload $rejection
}

Write-Utf8NoBomJson -PathValue $summaryOutputAbs -Payload $summary
$summary | ConvertTo-Json -Depth 20 | Write-Output

if ($FailOnReject -and -not $accepted) {
    throw ('contract_rejected: {0}' -f (@($validationErrors) -join ', '))
}