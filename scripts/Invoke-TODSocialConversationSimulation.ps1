param(
    [int]$ConversationCount = 1000000,
    [int]$CheckpointInterval = 0,
    [int]$HumanCount = 10000,
    [int]$Seed = 86013,
    [string]$DomainCatalogPath = 'tod/conversation_eval/social_domain_catalog.json',
    [string]$OutputRoot = 'shared_state/conversation_eval/social-million',
    [string[]]$IncludeDomains = @(),
    [double]$MinOverallScore = 0.74,
    [double]$MinMemoryScore = 0.73,
    [double]$MinRecognitionScore = 0.72,
    [double]$MinResourceScore = 0.71,
    [double]$MinConsistencyScore = 0.69,
    [double]$MinLearningDelta = 0.015,
    [switch]$EnableLiveFetch,
    [int]$LiveFetchSamplesPerCheckpoint = 3,
    [double]$LiveFetchTimeoutSeconds = 6.0,
    [int]$LiveFetchMaxChars = 20000,
    [double]$MinLiveFetchSuccessRate = 0.66,
    [double]$MinLiveGroundingScore = 0.68,
    [int]$WarmupCheckpoints = 2,
    [switch]$FailOnThreshold,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pythonScript = Join-Path $PSScriptRoot 'tod_social_conversation_simulation.py'

function Resolve-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

if (-not (Test-Path -Path $pythonScript)) {
    throw "Python simulation script not found: $pythonScript"
}

$pythonExe = Join-Path $repoRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -Path $pythonExe)) {
    $pythonExe = 'python'
}

$arguments = @(
    $pythonScript,
    '--conversation-count', [string]$ConversationCount,
    '--checkpoint-interval', [string]$CheckpointInterval,
    '--human-count', [string]$HumanCount,
    '--seed', [string]$Seed,
    '--domain-catalog', (Resolve-LocalPath -PathValue $DomainCatalogPath),
    '--output-root', (Resolve-LocalPath -PathValue $OutputRoot),
    '--min-overall-score', [string]$MinOverallScore,
    '--min-memory-score', [string]$MinMemoryScore,
    '--min-recognition-score', [string]$MinRecognitionScore,
    '--min-resource-score', [string]$MinResourceScore,
    '--min-consistency-score', [string]$MinConsistencyScore,
    '--min-learning-delta', [string]$MinLearningDelta,
    '--live-fetch-samples-per-checkpoint', [string]$LiveFetchSamplesPerCheckpoint,
    '--live-fetch-timeout-seconds', [string]$LiveFetchTimeoutSeconds,
    '--live-fetch-max-chars', [string]$LiveFetchMaxChars,
    '--min-live-fetch-success-rate', [string]$MinLiveFetchSuccessRate,
    '--min-live-grounding-score', [string]$MinLiveGroundingScore,
    '--warmup-checkpoints', [string]$WarmupCheckpoints
)

if (@($IncludeDomains).Count -gt 0) {
    $arguments += '--include-domains'
    $arguments += @($IncludeDomains)
}

if ($EnableLiveFetch) {
    $arguments += '--enable-live-fetch'
}
if ($FailOnThreshold) {
    $arguments += '--fail-on-threshold'
}
if ($EmitJson) {
    $arguments += '--emit-json'
}

& $pythonExe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "TOD social conversation simulation failed with exit code $LASTEXITCODE"
}