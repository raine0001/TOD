param(
    [string]$StatePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedStatePath = if ([string]::IsNullOrWhiteSpace($StatePath)) {
    Join-Path $repoRoot "tod/data/state.json"
}
elseif ([System.IO.Path]::IsPathRooted($StatePath)) {
    $StatePath
}
else {
    Join-Path $repoRoot $StatePath
}

if (-not (Test-Path -Path $resolvedStatePath)) {
    throw "State file not found: $resolvedStatePath"
}

function Set-BlockTrailingComma {
    param(
        [Parameter(Mandatory = $true)][string]$Block,
        [bool]$EnsureTrailingComma
    )

    $lines = @($Block -split "`r?`n")
    for ($index = $lines.Length - 1; $index -ge 0; $index--) {
        if ([string]::IsNullOrWhiteSpace($lines[$index])) {
            continue
        }

        if ($EnsureTrailingComma) {
            if ($lines[$index] -notmatch ',\s*$') {
                $lines[$index] = $lines[$index] + ','
            }
        }
        else {
            $lines[$index] = ($lines[$index] -replace ',\s*$', '')
        }
        break
    }

    return ($lines -join "`n")
}

function Get-ReplacementLine {
    param(
        [Parameter(Mandatory = $true)][string]$PropertyLine,
        [bool]$TrailingComma
    )

    if ($PropertyLine -match '^(?<prefix>\s+"[^"]+":\s+)\[$') {
        return ($Matches.prefix + '[]' + $(if ($TrailingComma) { ',' } else { '' }))
    }

    throw "Cannot rewrite property line: $PropertyLine"
}

function Write-StreamLine {
    param(
        [Parameter(Mandatory = $true)][System.IO.StreamWriter]$Writer,
        [AllowNull()][string]$Line
    )

    if ($null -eq $Line) {
        $Writer.WriteLine()
    }
    else {
        $Writer.WriteLine($Line)
    }
}

function Get-StructuralDelta {
    param(
        [AllowNull()][string]$Line
    )

    if ([string]::IsNullOrEmpty($Line)) {
        return 0
    }

    $openCount = ([regex]::Matches($Line, '[\[{]')).Count
    $closeCount = ([regex]::Matches($Line, '[\]}]')).Count
    return ($openCount - $closeCount)
}

$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$utcNow = (Get-Date).ToUniversalTime().ToString('o')
$tempPath = "$resolvedStatePath.rewriting"
$backupPath = Join-Path (Split-Path -Parent $resolvedStatePath) ("state.rewrite-{0}.json.bak" -f $timestamp)
$originalBytes = (Get-Item -Path $resolvedStatePath).Length

$journalPath = [System.IO.Path]::ChangeExtension($resolvedStatePath, 'journal-history.json')
$executionPath = [System.IO.Path]::ChangeExtension($resolvedStatePath, 'execution-history.json')
$reliabilityPath = [System.IO.Path]::ChangeExtension($resolvedStatePath, 'reliability-history.json')

$captured = @{}
$rewrittenSections = @()

$reader = $null
$writer = $null
$currentTopArray = $null
$currentTopObject = $null
$currentNestedArray = $null

try {
    $reader = [System.IO.File]::OpenText($resolvedStatePath)
    $writer = New-Object System.IO.StreamWriter($tempPath, $false, ([System.Text.UTF8Encoding]::new($false)))

    while (($line = $reader.ReadLine()) -ne $null) {
        if ($null -ne $currentTopArray) {
            $currentTopArray.lines.Add($line)
            $currentTopArray.depth += Get-StructuralDelta -Line $line
            if ($currentTopArray.depth -le 0) {
                $captured[$currentTopArray.name] = ($currentTopArray.lines -join "`n")
                $rewrittenSections += [string]$currentTopArray.name
                Write-StreamLine -Writer $writer -Line (Get-ReplacementLine -PropertyLine $currentTopArray.startLine -TrailingComma:($line -match ',\s*$'))
                $currentTopArray = $null
            }
            continue
        }

        if ($null -ne $currentTopObject) {
            $currentTopObject.lines.Add($line)
            $currentTopObject.depth += Get-StructuralDelta -Line $line

            if ($null -ne $currentNestedArray) {
                $currentNestedArray.depth += Get-StructuralDelta -Line $line
                if ($currentNestedArray.depth -le 0) {
                    $rewrittenSections += ("{0}.{1}" -f $currentTopObject.name, $currentNestedArray.name)
                    Write-StreamLine -Writer $writer -Line (Get-ReplacementLine -PropertyLine $currentNestedArray.startLine -TrailingComma:($line -match ',\s*$'))
                    $currentNestedArray = $null
                }

                if ($null -eq $currentNestedArray -and $currentTopObject.depth -le 0) {
                    $captured[$currentTopObject.name] = ($currentTopObject.lines -join "`n")
                    $currentTopObject = $null
                }
                continue
            }

            $nestedTargets = switch ($currentTopObject.name) {
                'routing_decisions' { @('records') }
                'engine_performance' { @('records') }
                default { @() }
            }

            if (@($nestedTargets).Count -gt 0 -and $line -match '^(?<indent>\s+)"(?<name>[^"]+)":\s+\[$' -and $nestedTargets -contains $Matches.name) {
                $currentNestedArray = [pscustomobject]@{
                    name = [string]$Matches.name
                    startLine = $line
                    depth = 1
                }
                continue
            }

            Write-StreamLine -Writer $writer -Line $line
            if ($currentTopObject.depth -le 0) {
                $captured[$currentTopObject.name] = ($currentTopObject.lines -join "`n")
                $currentTopObject = $null
            }
            continue
        }

        if ($line -match '^(?<indent>\s{4})"(?<name>journal|execution_results|review_decisions)":\s+\[$') {
            $currentTopArray = [pscustomobject]@{
                name = [string]$Matches.name
                startLine = $line
                lines = [System.Collections.Generic.List[string]]::new()
                depth = 1
            }
            $currentTopArray.lines.Add($line)
            continue
        }

        if ($line -match '^(?<indent>\s{4})"(?<name>routing_decisions|engine_performance)":\s+\{$') {
            $currentTopObject = [pscustomobject]@{
                name = [string]$Matches.name
                lines = [System.Collections.Generic.List[string]]::new()
                depth = 1
            }
            $currentTopObject.lines.Add($line)
            Write-StreamLine -Writer $writer -Line $line
            continue
        }

        Write-StreamLine -Writer $writer -Line $line
    }
}
catch {
    if (Test-Path -Path $tempPath) {
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
    }
    throw
}
finally {
    if ($writer) { $writer.Dispose() }
    if ($reader) { $reader.Dispose() }
}

if ($null -ne $currentTopArray -or $null -ne $currentTopObject -or $null -ne $currentNestedArray) {
    if (Test-Path -Path $tempPath) {
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
    }
    throw 'State rewrite ended with an incomplete capture; aborting without replacing the original state file.'
}

if ($captured.ContainsKey('journal')) {
    $journalBlock = Set-BlockTrailingComma -Block $captured['journal'] -EnsureTrailingComma $true
    $journalContent = @"
{
$journalBlock
    "updated_at":  "$utcNow"
}
"@
    Set-Content -Path $journalPath -Value $journalContent -Encoding utf8
}

if ($captured.ContainsKey('execution_results') -or $captured.ContainsKey('review_decisions')) {
    $blocks = @()
    if ($captured.ContainsKey('execution_results')) {
        $blocks += (Set-BlockTrailingComma -Block $captured['execution_results'] -EnsureTrailingComma:($captured.ContainsKey('review_decisions')))
    }
    if ($captured.ContainsKey('review_decisions')) {
        $blocks += (Set-BlockTrailingComma -Block $captured['review_decisions'] -EnsureTrailingComma $false)
    }
    $executionContent = @"
{
$($blocks -join "`n")
}
"@
    Set-Content -Path $executionPath -Value $executionContent -Encoding utf8
}

if ($captured.ContainsKey('engine_performance') -or $captured.ContainsKey('routing_decisions')) {
    $blocks = @()
    if ($captured.ContainsKey('engine_performance')) {
        $blocks += (Set-BlockTrailingComma -Block $captured['engine_performance'] -EnsureTrailingComma:($captured.ContainsKey('routing_decisions')))
    }
    if ($captured.ContainsKey('routing_decisions')) {
        $blocks += (Set-BlockTrailingComma -Block $captured['routing_decisions'] -EnsureTrailingComma $false)
    }
    $reliabilityContent = @"
{
$($blocks -join "`n")
}
"@
    Set-Content -Path $reliabilityPath -Value $reliabilityContent -Encoding utf8
}

Move-Item -Path $resolvedStatePath -Destination $backupPath -Force
Move-Item -Path $tempPath -Destination $resolvedStatePath -Force

$rewrittenBytes = (Get-Item -Path $resolvedStatePath).Length

[pscustomobject]@{
    state_path = $resolvedStatePath
    backup_path = $backupPath
    original_bytes = [int64]$originalBytes
    rewritten_bytes = [int64]$rewrittenBytes
    bytes_removed = [int64]($originalBytes - $rewrittenBytes)
    rewritten_sections = @($rewrittenSections | Select-Object -Unique)
    sidecars = [pscustomobject]@{
        journal = if (Test-Path -Path $journalPath) { $journalPath } else { $null }
        execution = if (Test-Path -Path $executionPath) { $executionPath } else { $null }
        reliability = if (Test-Path -Path $reliabilityPath) { $reliabilityPath } else { $null }
    }
}
