param(
    [string]$WatchdogScriptPath = "scripts/Start-TODRecoveryWatchdog.ps1",
    [string]$IntegrationStatusPath = "shared_state/integration_status.json",
    [string]$EnvPath = ".env",
    [string]$LocalRepairPacketPath = "shared_state/watchdog-repair/MIM_TOD_TASK_REQUEST.latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return (Join-Path $repoRoot $PathValue)
}

function Import-WatchdogFunction {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse watchdog script: $ScriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $ScriptPath"
    }

    $pattern = ('function\s+{0}\b' -f [regex]::Escape($Name))
    $replacement = ('function global:{0}' -f $Name)
    $definition = $fnAst.Extent.Text -replace $pattern, $replacement
    . ([scriptblock]::Create($definition))
}

$watchdogScriptAbs = Get-RepoPath -PathValue $WatchdogScriptPath
$integrationStatusAbs = Get-RepoPath -PathValue $IntegrationStatusPath
$envAbs = Get-RepoPath -PathValue $EnvPath
$localRepairPacketAbs = Get-RepoPath -PathValue $LocalRepairPacketPath

@(
    'Get-LocalPath',
    'Read-JsonFileIfExists',
    'Write-JsonFile',
    'Get-DotEnvValue',
    'Resolve-SshHostAlias',
    'Normalize-ObjectiveIdentity',
    'Convert-ToObjectiveLabel',
    'Get-CanonicalObjectiveForSelfHeal',
    'Get-CanonicalTaskIdForSelfHeal',
    'New-CanonicalRepublishTaskRequest',
    'Invoke-PublicationSurfaceSelfHeal'
) | ForEach-Object {
    Import-WatchdogFunction -ScriptPath $watchdogScriptAbs -Name $_
}

$result = Invoke-PublicationSurfaceSelfHeal -IntegrationStatusPath $integrationStatusAbs -EnvPath $envAbs -LocalRepairPacketPath $localRepairPacketAbs
$result | ConvertTo-Json -Depth 8