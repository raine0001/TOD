param(
    [Parameter(Mandatory = $true)][string]$RepoManifestPath,
    [string]$Source = "CodexSupervised::UserAppPersistenceScaffold"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot

function Convert-ToRepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return (Join-Path $repoRoot $PathValue)
}

function Convert-ToRepoRelativePath {
    param([Parameter(Mandatory = $true)][string]$PathValue)
    $fullPath = [System.IO.Path]::GetFullPath((Convert-ToRepoPath -PathValue $PathValue))
    $root = [System.IO.Path]::GetFullPath($repoRoot)
    if (-not $fullPath.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside repo root: $PathValue"
    }
    return ($fullPath.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/')
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Convert-ToTitle {
    param([Parameter(Mandatory = $true)][string]$Text)
    return (($Text -split '_' | Where-Object { $_ } | ForEach-Object {
                $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant()
            }) -join ' ')
}

$manifestAbs = Convert-ToRepoPath -PathValue $RepoManifestPath
if (-not (Test-Path -Path $manifestAbs -PathType Leaf)) {
    throw "Repo manifest not found: $RepoManifestPath"
}

$repoManifest = Get-Content -Path $manifestAbs -Raw | ConvertFrom-Json
if ([string]$repoManifest.artifact_type -ne "user_app_repo_skeleton_manifest_v1") {
    throw "Unsupported repo manifest artifact type: $($repoManifest.artifact_type)"
}

$repoAbs = Convert-ToRepoPath -PathValue ([string]$repoManifest.repo_root)
$planAbs = Convert-ToRepoPath -PathValue ([string]$repoManifest.source_plan)
$plan = Get-Content -Path $planAbs -Raw | ConvertFrom-Json
$objects = @($plan.proposed_repo.data_objects | ForEach-Object { [string]$_ })
if (@($objects).Count -eq 0) {
    $objects = @("record")
}
$primary = [string]$objects[0]
$primaryTitle = Convert-ToTitle -Text $primary
$appName = [string]$repoManifest.app_name

$modelLines = @($objects | ForEach-Object {
        "  { name: `"$_`", label: `"$(Convert-ToTitle -Text $_)`", fields: [`"id`", `"name`", `"status`", `"createdAt`", `"updatedAt`"] }"
    }) -join ",`n"

$models = @"
export const appModels = [
$modelLines
];

export const primaryModel = "$primary";
"@

$seedRows = @(
    "{ id: `"demo-1`", name: `"$primaryTitle Example 1`", status: `"active`", createdAt: `"2026-06-09`", updatedAt: `"2026-06-09`" }",
    "{ id: `"demo-2`", name: `"$primaryTitle Example 2`", status: `"waiting`", createdAt: `"2026-06-09`", updatedAt: `"2026-06-09`" }"
) -join ",`n  "

$seed = @"
import { primaryModel } from "./models";

export const seedData = {
  [primaryModel]: [
  $seedRows
  ]
};
"@

$adapter = @"
import { seedData } from "./seed";
import { primaryModel } from "./models";

const storageKey = "$($repoManifest.slug):local-persistence-v1";

export function loadAppData() {
  if (typeof window === "undefined") {
    return seedData;
  }
  const raw = window.localStorage.getItem(storageKey);
  return raw ? JSON.parse(raw) : seedData;
}

export function saveAppData(data) {
  if (typeof window === "undefined") {
    return data;
  }
  window.localStorage.setItem(storageKey, JSON.stringify(data));
  return data;
}

export function createPrimaryRecord(name) {
  const data = loadAppData();
  const row = {
    id: primaryModel + "-" + Date.now(),
    name,
    status: "active",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString()
  };
  const next = {
    ...data,
    [primaryModel]: [...(data[primaryModel] || []), row]
  };
  saveAppData(next);
  return row;
}
"@

$exporter = @"
export function exportJson(data) {
  return JSON.stringify(data, null, 2);
}

export function importJson(text) {
  return JSON.parse(text);
}
"@

$persistenceTest = @"
import { test, expect } from '@playwright/test';

test('$appName persistence scaffold is visible', async ({ page }) => {
  await page.goto('/dashboard');
  await expect(page.getByText('Primary Workflow')).toBeVisible();
});
"@

$manifest = [ordered]@{
    artifact_type = "user_app_persistence_scaffold_manifest_v1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source = $Source
    app_name = $appName
    slug = [string]$repoManifest.slug
    source_repo_manifest = Convert-ToRepoRelativePath -PathValue $manifestAbs
    repo_root = Convert-ToRepoRelativePath -PathValue $repoAbs
    primary_model = $primary
    data_objects = @($objects)
    files = @(
        "src/lib/models.ts",
        "src/lib/seed.ts",
        "src/lib/localPersistence.ts",
        "src/lib/exportImport.ts",
        "tests/persistence.spec.ts"
    )
    gates = [ordered]@{
        local_persistence = "ready"
        export_import = "ready"
        backend_database = "not_selected"
        production_deploy = "not_selected"
    }
    dave_needed = "no"
    tod_next_action = "Wire the dashboard to the local persistence adapter, then run acceptance tests against a preview target."
}

Write-Utf8NoBom -Path (Join-Path $repoAbs "src/lib/models.ts") -Content $models
Write-Utf8NoBom -Path (Join-Path $repoAbs "src/lib/seed.ts") -Content $seed
Write-Utf8NoBom -Path (Join-Path $repoAbs "src/lib/localPersistence.ts") -Content $adapter
Write-Utf8NoBom -Path (Join-Path $repoAbs "src/lib/exportImport.ts") -Content $exporter
Write-Utf8NoBom -Path (Join-Path $repoAbs "tests/persistence.spec.ts") -Content $persistenceTest
Write-Utf8NoBom -Path (Join-Path $repoAbs "persistence.manifest.json") -Content ($manifest | ConvertTo-Json -Depth 30)

$manifest | ConvertTo-Json -Depth 12
