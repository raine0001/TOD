param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,
    [string]$Branch = "main",
    [string]$RequiredCheck = "TOD Tests / test"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ghCandidates = @(
    "gh",
    "C:\Program Files\GitHub CLI\gh.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\GitHub CLI\gh.exe")
)

$ghPath = $null
foreach ($candidate in $ghCandidates) {
    try {
        if ($candidate -eq "gh") {
            $cmd = Get-Command gh -ErrorAction SilentlyContinue
            if ($cmd) { $ghPath = $cmd.Source; break }
        }
        elseif (Test-Path -Path $candidate) {
            $ghPath = $candidate
            break
        }
    }
    catch {
    }
}

if (-not $ghPath) {
    throw "GitHub CLI (gh) not found. Install it first, then run: gh auth login"
}

$null = & $ghPath auth status

$normalizedBranch = ([string]$Branch).Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($normalizedBranch)) {
    $normalizedBranch = "main"
}

$payload = [ordered]@{
    required_status_checks = [ordered]@{
        strict = $true
        contexts = @($RequiredCheck)
    }
    enforce_admins = $true
    required_pull_request_reviews = [ordered]@{
        required_approving_review_count = 1
        dismiss_stale_reviews = $true
        require_code_owner_reviews = $false
        require_last_push_approval = $false
    }
    restrictions = $null
    allow_force_pushes = $false
    allow_deletions = $false
    block_creations = $false
    required_conversation_resolution = $true
    lock_branch = $false
    allow_fork_syncing = $true
}

$tempFile = New-TemporaryFile
try {
    $payload | ConvertTo-Json -Depth 12 | Set-Content -Path $tempFile
    & $ghPath api --method PUT -H "Accept: application/vnd.github+json" "repos/$Repository/branches/$normalizedBranch/protection" --input $tempFile
    Write-Host "Branch protection applied for $Repository:$normalizedBranch" -ForegroundColor Green
}
finally {
    if (Test-Path -Path $tempFile) {
        Remove-Item -Path $tempFile -Force
    }
}
