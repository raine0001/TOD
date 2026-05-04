param(
    [string]$DotEnvPath = '.env',
    [string]$ContractAcceptanceScriptPath = 'scripts/Invoke-TODMimContractAcceptance.ps1',
    [string]$DialogScriptPath = 'scripts/Invoke-TODMimDialog.ps1',
    [string]$AgreementOutputPath = 'shared_state/TOD_MIM_CONTRACT_FORMAL_AGREEMENT.latest.json',
    [string]$RemoteReceiptPath = '/home/testpilot/mim/runtime/shared/TOD_MIM_CONTRACT_RECEIPT.latest.json',
    [string]$RemoteActivationReportPath = '/home/testpilot/mim/runtime/shared/TOD_MIM_CONTRACT_ACTIVATION_REPORT.latest.json',
    [string]$RemoteLockPath = '/home/testpilot/mim/runtime/shared/TOD_MIM_CONTRACT_LOCK.latest.json',
    [string]$RemoteValidationFailurePath = '/home/testpilot/mim/runtime/shared/TOD_MIM_CONTRACT_VALIDATION_FAILURE.latest.json',
    [int]$ActivationPollSeconds = 15,
    [int]$PollIntervalSeconds = 3,
    [switch]$PublishDialogRemote,
    [switch]$EmitJson,
    [switch]$FailOnNotAgreed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Get-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $Path)) {
        return ''
    }

    $line = Get-Content -Path $Path | Where-Object { $_ -match "^\s*$Name\s*=" } | Select-Object -First 1
    if (-not $line) {
        return ''
    }

    return (($line -replace "^\s*$Name\s*=\s*", '').Trim().Trim('"').Trim("'"))
}

function Get-DateOrMinValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    try {
        return [datetime]::Parse([string]$Value).ToUniversalTime()
    }
    catch {
        return [datetime]::MinValue
    }
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
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

function Copy-RemoteFileToLocalIfPresent {
    param(
        [Parameter(Mandatory = $true)][int]$SessionId,
        [Parameter(Mandatory = $true)][string]$RemotePath,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )

    $destinationDir = Split-Path -Parent $LocalPath
    Ensure-Directory -PathValue $destinationDir

    try {
        Get-SFTPItem -SessionId $SessionId -Path $RemotePath -Destination $destinationDir -Force -ErrorAction Stop | Out-Null
    }
    catch {
        return $null
    }

    $downloadedPath = Join-Path $destinationDir ([System.IO.Path]::GetFileName($RemotePath))
    if ((Test-Path -Path $downloadedPath -PathType Leaf) -and ($downloadedPath -ne $LocalPath)) {
        Move-Item -Path $downloadedPath -Destination $LocalPath -Force
    }

    if (-not (Test-Path -Path $LocalPath -PathType Leaf)) {
        return $null
    }

    return (Read-JsonFileIfExists -PathValue $LocalPath)
}

function Get-RemoteContractArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ActivationReportPath,
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][string]$ValidationFailurePath
    )

    $connections = $null
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tod-mim-contract-' + [guid]::NewGuid().ToString('N'))
    Ensure-Directory -PathValue $tempRoot
    try {
        $connections = New-SshConnections -HostName $HostName -UserName $UserName -Port $Port -Password $Password
        return [pscustomobject]@{
            receipt = Copy-RemoteFileToLocalIfPresent -SessionId ([int]$connections.sftp.SessionId) -RemotePath $ReceiptPath -LocalPath (Join-Path $tempRoot 'receipt.json')
            activation_report = Copy-RemoteFileToLocalIfPresent -SessionId ([int]$connections.sftp.SessionId) -RemotePath $ActivationReportPath -LocalPath (Join-Path $tempRoot 'activation.json')
            lock = Copy-RemoteFileToLocalIfPresent -SessionId ([int]$connections.sftp.SessionId) -RemotePath $LockPath -LocalPath (Join-Path $tempRoot 'lock.json')
            validation_failure = Copy-RemoteFileToLocalIfPresent -SessionId ([int]$connections.sftp.SessionId) -RemotePath $ValidationFailurePath -LocalPath (Join-Path $tempRoot 'validation-failure.json')
        }
    }
    finally {
        Close-SshConnections -Connections $connections
        if (Test-Path -Path $tempRoot) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-FormalAgreementAssessment {
    param(
        [AllowNull()]$AcceptanceSummary,
        [AllowNull()]$RemoteReceipt,
        [AllowNull()]$RemoteLock,
        [AllowNull()]$ActivationReport,
        [AllowNull()]$ValidationFailure
    )

    $todAccepted = [bool]($AcceptanceSummary -and $AcceptanceSummary.PSObject.Properties['accepted'] -and $AcceptanceSummary.accepted)
    $todChecksum = if ($AcceptanceSummary -and $AcceptanceSummary.PSObject.Properties['validation'] -and $AcceptanceSummary.validation -and $AcceptanceSummary.validation.PSObject.Properties['actual_sha256']) { [string]$AcceptanceSummary.validation.actual_sha256 } else { '' }
    $todVersion = if ($AcceptanceSummary -and $AcceptanceSummary.PSObject.Properties['validation'] -and $AcceptanceSummary.validation -and $AcceptanceSummary.validation.PSObject.Properties['contract_version']) { [string]$AcceptanceSummary.validation.contract_version } else { '' }

    $remoteReceiptPresent = $null -ne $RemoteReceipt
    $remoteReceiptAccepted = [bool]($remoteReceiptPresent -and $RemoteReceipt.PSObject.Properties['acceptance_status'] -and [string]::Equals([string]$RemoteReceipt.acceptance_status, 'accepted', [System.StringComparison]::OrdinalIgnoreCase))
    $remoteReceiptChecksum = if ($remoteReceiptPresent -and $RemoteReceipt.PSObject.Properties['checksum_sha256']) { [string]$RemoteReceipt.checksum_sha256 } else { '' }
    $remoteReceiptVersion = if ($remoteReceiptPresent -and $RemoteReceipt.PSObject.Properties['contract_version']) { [string]$RemoteReceipt.contract_version } else { '' }

    $mimLockActive = [bool]($RemoteLock -and $RemoteLock.PSObject.Properties['runtime_lock'] -and [string]::Equals([string]$RemoteLock.runtime_lock, 'active', [System.StringComparison]::OrdinalIgnoreCase))
    $mimLockChecksum = if ($RemoteLock -and $RemoteLock.PSObject.Properties['sha256']) { [string]$RemoteLock.sha256 } else { '' }
    $mimLockVersion = if ($RemoteLock -and $RemoteLock.PSObject.Properties['contract_version']) { [string]$RemoteLock.contract_version } else { '' }

    $checksumAligned =
        (-not [string]::IsNullOrWhiteSpace($todChecksum)) -and
        [string]::Equals($todChecksum, $remoteReceiptChecksum, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($todChecksum, $mimLockChecksum, [System.StringComparison]::OrdinalIgnoreCase)
    $versionAligned =
        (-not [string]::IsNullOrWhiteSpace($todVersion)) -and
        [string]::Equals($todVersion, $remoteReceiptVersion, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($todVersion, $mimLockVersion, [System.StringComparison]::OrdinalIgnoreCase)

    $formalAgreementReached = $todAccepted -and $remoteReceiptAccepted -and $mimLockActive -and $checksumAligned -and $versionAligned

    $activationGeneratedAt = if ($ActivationReport -and $ActivationReport.PSObject.Properties['generated_at']) { [string]$ActivationReport.generated_at } else { '' }
    $activationGeneratedUtc = Get-DateOrMinValue -Value $activationGeneratedAt
    $remoteReceiptGeneratedAt = if ($RemoteReceipt -and $RemoteReceipt.PSObject.Properties['generated_at']) { [string]$RemoteReceipt.generated_at } else { '' }
    $remoteReceiptGeneratedUtc = Get-DateOrMinValue -Value $remoteReceiptGeneratedAt
    $activationReceiptPresent = [bool]($ActivationReport -and $ActivationReport.PSObject.Properties['tod_receipt_status'] -and $ActivationReport.tod_receipt_status -and $ActivationReport.tod_receipt_status.PSObject.Properties['receipt_present'] -and $ActivationReport.tod_receipt_status.receipt_present)
    $activationChecksumMatch = [bool]($ActivationReport -and $ActivationReport.PSObject.Properties['tod_receipt_status'] -and $ActivationReport.tod_receipt_status -and $ActivationReport.tod_receipt_status.PSObject.Properties['checksum_match'] -and $ActivationReport.tod_receipt_status.checksum_match)
    $activationReady = [bool]($ActivationReport -and $ActivationReport.PSObject.Properties['cutover_readiness'] -and $ActivationReport.cutover_readiness -and $ActivationReport.cutover_readiness.PSObject.Properties['ready'] -and $ActivationReport.cutover_readiness.ready)
    $activationReportState = 'missing'
    if ($null -ne $ActivationReport) {
        $activationReportState = 'pending'
        if ($activationReceiptPresent -and $activationChecksumMatch) {
            $activationReportState = if ($activationReady) { 'confirmed' } else { 'receipt_seen_not_ready' }
        }
        elseif ($formalAgreementReached -and $remoteReceiptGeneratedUtc -ne [datetime]::MinValue -and $activationGeneratedUtc -lt $remoteReceiptGeneratedUtc) {
            $activationReportState = 'stale_pending_refresh'
        }
    }

    $validationState = 'clear'
    if ($null -ne $ValidationFailure) {
        $validationGeneratedUtc = if ($ValidationFailure.PSObject.Properties['generated_at']) { Get-DateOrMinValue -Value ([string]$ValidationFailure.generated_at) } else { [datetime]::MinValue }
        if ($formalAgreementReached -and $remoteReceiptGeneratedUtc -ne [datetime]::MinValue -and $validationGeneratedUtc -lt $remoteReceiptGeneratedUtc) {
            $validationState = 'stale_pre_agreement'
        }
        else {
            $validationState = 'active'
        }
    }

    $summary = if ($formalAgreementReached) {
        'TOD and MIM are formally aligned on the communication contract through a matching TOD acceptance receipt and an active MIM contract lock.'
    }
    else {
        'Formal TOD-MIM contract agreement is not complete yet.'
    }

    return [pscustomobject]@{
        agreement_status = if ($formalAgreementReached) { 'agreed' } else { 'not_agreed' }
        formal_agreement_reached = $formalAgreementReached
        tod_acceptance_status = if ($todAccepted) { 'accepted' } else { 'not_accepted' }
        remote_receipt_status = if ($remoteReceiptAccepted) { 'accepted' } elseif ($remoteReceiptPresent) { 'present_not_accepted' } else { 'missing' }
        mim_lock_status = if ($mimLockActive) { 'active' } else { 'inactive' }
        checksum_aligned = $checksumAligned
        version_aligned = $versionAligned
        activation_report_state = $activationReportState
        validation_failure_state = $validationState
        summary = $summary
    }
}

function Publish-ActivationRefreshRequest {
    param(
        [Parameter(Mandatory = $true)][string]$DialogScriptAbs,
        [Parameter(Mandatory = $true)][string]$DotEnvAbs,
        [Parameter(Mandatory = $true)][string]$Checksum,
        [Parameter(Mandatory = $true)][string]$ContractVersion,
        [Parameter(Mandatory = $true)][string]$ActivationReportState,
        [Parameter(Mandatory = $true)][string]$ValidationFailureState,
        [switch]$PublishRemote
    )

    if (-not (Test-Path -Path $DialogScriptAbs -PathType Leaf)) {
        return $null
    }

    $sessionId = ('contract-agreement-' + $ContractVersion + '-' + $Checksum.Substring(0, [Math]::Min(8, $Checksum.Length))) -replace '[^a-zA-Z0-9._-]', '_'
    $payload = [pscustomobject]@{
        source = 'tod-mim-contract-formal-agreement-v1'
        contract_version = $ContractVersion
        checksum_sha256 = $Checksum
        activation_report_state = $ActivationReportState
        validation_failure_state = $ValidationFailureState
        requested_action = 'Refresh the contract activation report so it reflects the accepted TOD receipt, and clear or supersede any stale pre-agreement validation failure artifacts.'
    }

    try {
        $args = @{
            Action = 'send'
            DialogDir = 'shared_state/dialog'
            SessionId = $sessionId
            Actor = 'TOD'
            PeerActor = 'MIM'
            MessageType = 'status_request'
            Intent = 'contract_agreement_refresh'
            TaskId = 'TOD_MIM_COMMUNICATION_CONTRACT.v1'
            CorrelationId = $Checksum
            Summary = 'TOD and MIM now share the same accepted contract checksum. Please refresh MIM contract-state projections so the agreement is visible on both sides.'
            PayloadJson = ($payload | ConvertTo-Json -Depth 12 -Compress)
            RequiresReply = $true
            DotEnvPath = $DotEnvAbs
            EmitJson = $true
        }
        if ($PublishRemote) {
            $args.PublishRemote = $true
        }
        return (& $DialogScriptAbs @args | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            ok = $false
            error = [string]$_.Exception.Message
            session_id = $sessionId
        }
    }
}

$dotEnvAbs = Resolve-LocalPath -PathValue $DotEnvPath
$agreementOutputAbs = Resolve-LocalPath -PathValue $AgreementOutputPath
$contractAcceptanceAbs = Resolve-LocalPath -PathValue $ContractAcceptanceScriptPath
$dialogScriptAbs = Resolve-LocalPath -PathValue $DialogScriptPath

$contractHost = Get-DotEnvValue -Path $dotEnvAbs -Name 'MIM_SSH_HOST'
$contractUser = Get-DotEnvValue -Path $dotEnvAbs -Name 'MIM_SSH_USER'
$contractPortValue = Get-DotEnvValue -Path $dotEnvAbs -Name 'MIM_SSH_PORT'
$contractPassword = Get-DotEnvValue -Path $dotEnvAbs -Name 'MIM_SSH_PASSWORD'
if ([string]::IsNullOrWhiteSpace($contractHost) -or [string]::IsNullOrWhiteSpace($contractUser) -or [string]::IsNullOrWhiteSpace($contractPortValue) -or [string]::IsNullOrWhiteSpace($contractPassword)) {
    throw 'missing_mim_ssh_configuration'
}

$acceptanceSummary = (& $contractAcceptanceAbs | Out-String | ConvertFrom-Json)
$contractPort = [int]$contractPortValue

$pollDeadline = (Get-Date).ToUniversalTime().AddSeconds([Math]::Max(0, $ActivationPollSeconds))
$remoteArtifacts = $null
do {
    $remoteArtifacts = Get-RemoteContractArtifacts -HostName $contractHost -UserName $contractUser -Port $contractPort -Password $contractPassword -ReceiptPath $RemoteReceiptPath -ActivationReportPath $RemoteActivationReportPath -LockPath $RemoteLockPath -ValidationFailurePath $RemoteValidationFailurePath
    $assessment = Get-FormalAgreementAssessment -AcceptanceSummary $acceptanceSummary -RemoteReceipt $remoteArtifacts.receipt -RemoteLock $remoteArtifacts.lock -ActivationReport $remoteArtifacts.activation_report -ValidationFailure $remoteArtifacts.validation_failure
    if ($assessment.formal_agreement_reached -and $assessment.activation_report_state -ne 'pending') {
        break
    }
    if ((Get-Date).ToUniversalTime() -ge $pollDeadline) {
        break
    }
    Start-Sleep -Seconds ([Math]::Max(1, $PollIntervalSeconds))
} while ($true)

$dialogResult = $null
if ($assessment.formal_agreement_reached -and @('stale_pending_refresh', 'pending', 'receipt_seen_not_ready') -contains [string]$assessment.activation_report_state) {
    $checksum = if ($acceptanceSummary.validation -and $acceptanceSummary.validation.PSObject.Properties['actual_sha256']) { [string]$acceptanceSummary.validation.actual_sha256 } else { '' }
    $version = if ($acceptanceSummary.validation -and $acceptanceSummary.validation.PSObject.Properties['contract_version']) { [string]$acceptanceSummary.validation.contract_version } else { 'v1' }
    if (-not [string]::IsNullOrWhiteSpace($checksum)) {
        $dialogResult = Publish-ActivationRefreshRequest -DialogScriptAbs $dialogScriptAbs -DotEnvAbs $dotEnvAbs -Checksum $checksum -ContractVersion $version -ActivationReportState ([string]$assessment.activation_report_state) -ValidationFailureState ([string]$assessment.validation_failure_state) -PublishRemote:$PublishDialogRemote
    }
}

$report = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-mim-formal-contract-agreement-v1'
    agreement = $assessment
    tod_acceptance = $acceptanceSummary
    remote = [pscustomobject]@{
        contract_receipt = $remoteArtifacts.receipt
        contract_lock = $remoteArtifacts.lock
        contract_activation_report = $remoteArtifacts.activation_report
        contract_validation_failure = $remoteArtifacts.validation_failure
    }
    follow_up = [pscustomobject]@{
        dialog_refresh_requested = [bool]($null -ne $dialogResult)
        dialog_result = $dialogResult
    }
}

Write-Utf8NoBomJson -PathValue $agreementOutputAbs -Payload $report -Depth 30

if ($EmitJson) {
    $report | ConvertTo-Json -Depth 20 | Write-Output
}
else {
    $report
}

if ($FailOnNotAgreed -and -not [bool]$assessment.formal_agreement_reached) {
    throw 'tod_mim_formal_contract_agreement_not_reached'
}