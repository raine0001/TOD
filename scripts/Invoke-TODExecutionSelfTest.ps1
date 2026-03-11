param(
    [string]$TaskId = "45",
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScript = Join-Path $PSScriptRoot "TOD.ps1"
$configPath = Join-Path $repoRoot "tod/config/tod-config.json"

if (-not (Test-Path -Path $todScript)) {
    throw "Missing TOD script: $todScript"
}

if (-not (Test-Path -Path $configPath)) {
    throw "Missing config file: $configPath"
}

$cfg = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$cfg.mode = "local"
$cfg.fallback_to_local = $true
$cfg.execution_engine.active = "codex"
$cfg.execution_engine.fallback = "local"
$cfg.execution_engine.allow_fallback = $true

$tempConfigPath = Join-Path $repoRoot ("tod/config/tod-config.exec-selftest-{0}.json" -f ([guid]::NewGuid().ToString("N")))
$cfg | ConvertTo-Json -Depth 30 | Set-Content -Path $tempConfigPath

try {
    $null = & $todScript -Action package-task -TaskId $TaskId -ConfigPath $tempConfigPath

    $runRaw = & $todScript -Action run-task -TaskId $TaskId -ConfigPath $tempConfigPath -ForceConfiguredEngine
    $run = $runRaw | ConvertFrom-Json

    $packagePath = if ($run.PSObject.Properties["package_path"]) { [string]$run.package_path } else { "" }
    $engineName = if ($run.PSObject.Properties["engine_invocation"] -and $run.engine_invocation -and $run.engine_invocation.PSObject.Properties["active_engine"]) { [string]$run.engine_invocation.active_engine } else { "" }
    $resultPayload = if ($run.PSObject.Properties["engine_invocation"] -and $run.engine_invocation -and $run.engine_invocation.PSObject.Properties["result"]) { $run.engine_invocation.result } else { $null }

    $filesChanged = @()
    if ($null -ne $resultPayload -and $resultPayload.PSObject.Properties["files_changed"]) {
        $filesChanged = @($resultPayload.files_changed | ForEach-Object { [string]$_ })
    }

    $checks = [pscustomobject]@{
        package_exists = (-not [string]::IsNullOrWhiteSpace($packagePath) -and (Test-Path -Path $packagePath))
        engine_invoked = (-not [string]::IsNullOrWhiteSpace($engineName))
        envelope_present = ($null -ne $resultPayload)
        add_result_recorded = ($run.PSObject.Properties["add_result_response"] -and $null -ne $run.add_result_response -and -not [string]::IsNullOrWhiteSpace([string]$run.add_result_response.id))
        review_recorded = ($run.PSObject.Properties["review_response"] -and $null -ne $run.review_response -and -not [string]::IsNullOrWhiteSpace([string]$run.review_response.id))
    }

    $passedAll = [bool]($checks.package_exists -and $checks.engine_invoked -and $checks.envelope_present -and $checks.add_result_recorded -and $checks.review_recorded)

    $summary = [pscustomobject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        source = "tod-execution-selftest"
        task_id = [string]$TaskId
        passed_all = $passedAll
        checks = $checks
        facts = [pscustomobject]@{
            package_path = $packagePath
            active_engine = $engineName
            decision = if ($run.PSObject.Properties["decision"]) { [string]$run.decision } else { "" }
            files_changed_count = @($filesChanged).Count
            files_changed = @($filesChanged)
        }
    }

    $json = $summary | ConvertTo-Json -Depth 10
    Write-Output $json

    if ($FailOnError -and -not $passedAll) {
        throw "TOD execution self-test failed one or more checks."
    }
}
finally {
    if (Test-Path -Path $tempConfigPath) {
        Remove-Item -Path $tempConfigPath -Force -ErrorAction SilentlyContinue
    }
}
