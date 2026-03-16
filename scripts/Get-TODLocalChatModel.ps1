param(
    [string]$ModelUrl = "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf?download=true",
    [string]$OutPath = "models/tod/Qwen2.5-3B-Instruct-Q4_K_M.gguf",
    [switch]$Force,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-LocalPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $repoRoot $PathValue)
}

function Initialize-ParentDir {
    param([Parameter(Mandatory = $true)][string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$target = Get-LocalPath -PathValue $OutPath
if ((Test-Path -Path $target) -and -not $Force) {
    $payload = [pscustomobject]@{
        ok = $true
        changed = $false
        model_path = $target
        note = "Model already present"
    }
    if ($AsJson) { $payload | ConvertTo-Json -Depth 6 } else { $payload }
    return
}

Initialize-ParentDir -FilePath $target
Invoke-WebRequest -Uri $ModelUrl -OutFile $target -UseBasicParsing -TimeoutSec 0

$payload = [pscustomobject]@{
    ok = $true
    changed = $true
    model_path = $target
    source_url = $ModelUrl
    note = "Starter local chat model downloaded"
}
if ($AsJson) { $payload | ConvertTo-Json -Depth 6 } else { $payload }
