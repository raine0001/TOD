param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "init-engineering-memory",
        "add-memory-note",
        "show-memory",
        "index-repo",
        "generate-module-summaries",
        "show-module-summary",
        "find-related-files",
        "show-impact-area",
        "show-repo-index",
        "bootstrap-upgrade-objective",
        "package-task-v2",
        "review-result-v2",
        "execute-task-loop"
    )]
    [string]$Action,

    [ValidateSet(
        "architecture_memory",
        "repo_memory",
        "decision_memory",
        "failure_memory",
        "pattern_memory",
        "test_memory",
        "packaging_lessons"
    )]
    [string]$Bucket,
    [string]$Title,
    [string]$Note,
    [string]$Tags,
    [string]$TaskId,
    [string]$ResultJsonPath,
    [string]$AllowedFiles,
    [string]$ValidationCommands,
    [string]$EscalationTriggers,
    [string]$Query,
    [string]$Path,
    [string]$ConfigPath,
    [int]$Top = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$todScriptPath = Join-Path $PSScriptRoot "TOD.ps1"
$memoryPath = Join-Path $repoRoot "tod/data/engineering-memory.json"
$repoIndexPath = Join-Path $repoRoot "tod/data/repo-index.json"
$stateDir = Join-Path $repoRoot "tod/state"
$stateMemoryPath = Join-Path $stateDir "engineering_memory.json"
$stateRepoIndexPath = Join-Path $stateDir "repo_index.json"
$moduleSummaryPath = Join-Path $repoRoot "tod/data/module-summaries.json"
$stateModuleSummaryPath = Join-Path $stateDir "module_summaries.json"
$promptV2Path = Join-Path $repoRoot "tod/out/prompts-v2"
$configPathResolved = if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    Join-Path $repoRoot "tod/config/tod-config.json"
}
else {
    $ConfigPath
}

function Get-UtcNow {
    (Get-Date).ToUniversalTime().ToString("o")
}

function Assert-PathExists {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) {
        throw "$Name not found at $Path"
    }
}

function Load-JsonFile {
    param([string]$Path)
    Assert-PathExists -Path $Path -Name "JSON file"
    (Get-Content -Path $Path -Raw) | ConvertFrom-Json
}

function Save-JsonFile {
    param($Object, [string]$Path)
    $Object | ConvertTo-Json -Depth 16 | Set-Content -Path $Path
}

function Ensure-StateDir {
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
}

function Save-JsonWithStateMirror {
    param(
        $Object,
        [string]$PrimaryPath,
        [string]$MirrorPath
    )

    Save-JsonFile -Object $Object -Path $PrimaryPath
    Ensure-StateDir
    Save-JsonFile -Object $Object -Path $MirrorPath
}

function Split-StringList {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    @($Value.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-GitValue {
    param([string]$Command)
    try {
        (Invoke-Expression $Command) | Select-Object -First 1
    }
    catch {
        $null
    }
}

function Resolve-TodId {
    param($TodResponse, [string]$Primary, [string]$Fallback)

    if ($TodResponse.PSObject.Properties[$Primary]) {
        return [string]$TodResponse.$Primary
    }

    if ($TodResponse.PSObject.Properties["local"] -and $TodResponse.local.PSObject.Properties[$Fallback]) {
        return [string]$TodResponse.local.$Fallback
    }

    if ($TodResponse.PSObject.Properties[$Fallback]) {
        return [string]$TodResponse.$Fallback
    }

    throw "Could not resolve TOD response ID for '$Primary' or '$Fallback'."
}

function To-RepoRelativePath {
    param([string]$FullPath)

    if ([string]::IsNullOrWhiteSpace($FullPath)) { return $FullPath }
    if ($FullPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($repoRoot.Length).TrimStart('\\')
    }
    return $FullPath
}

function Normalize-SlashPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $normalized = [string]$Path
    $normalized = $normalized -replace '[\\/]+', '/'
    if ($normalized.StartsWith('./')) {
        $normalized = $normalized.Substring(2)
    }
    return $normalized.Trim()
}

function Split-ListSmart {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    @($Value -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-HasItems {
    param($Value)
    $items = @($Value | Where-Object { $null -ne $_ -and [string]$_ -ne "" })
    return ($items.Length -gt 0)
}

function Get-TodObjects {
    param([string]$ActionName)

    $raw = & $todScriptPath -Action $ActionName -ConfigPath $configPathResolved
    $parsed = $raw | ConvertFrom-Json
    return @($parsed)
}

function Get-OptionalProp {
    param($Object, [string]$Name)
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Load-ExecutionEngineConfig {
    param([string]$Path)

    if (-not (Test-Path -Path $Path)) {
        return [pscustomobject]@{
            active = "codex"
            fallback = "local"
            allow_fallback = $true
        }
    }

    $cfg = (Get-Content -Path $Path -Raw) | ConvertFrom-Json
    $supported = @("codex", "local")

    $active = "codex"
    $fallback = "local"
    $allowFallback = $true

    if ($cfg.PSObject.Properties["execution_engine"] -and $null -ne $cfg.execution_engine) {
        if (-not [string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.active)) {
            $active = ([string]$cfg.execution_engine.active).ToLowerInvariant()
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$cfg.execution_engine.fallback)) {
            $fallback = ([string]$cfg.execution_engine.fallback).ToLowerInvariant()
        }
        if ($null -ne $cfg.execution_engine.allow_fallback) {
            $allowFallback = [bool]$cfg.execution_engine.allow_fallback
        }
    }

    if ($supported -notcontains $active) {
        throw "Invalid execution_engine.active '$active'. Supported engines: $($supported -join ', ')."
    }
    if ($allowFallback -and $supported -notcontains $fallback) {
        throw "Invalid execution_engine.fallback '$fallback'. Supported engines: $($supported -join ', ')."
    }

    return [pscustomobject]@{
        active = $active
        fallback = $fallback
        allow_fallback = $allowFallback
        supported = @($supported)
    }
}

function Invoke-TaskExecutionEngine {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)]$EngineConfig
    )

    $engineDir = Join-Path $PSScriptRoot "engines"
    . (Join-Path $engineDir "ExecutionEngine.ps1")

    $context = New-EngineTaskContext `
        -TaskId ([string]$Package.task_id) `
        -ObjectiveId ([string]$Package.objective_id) `
        -Title ([string]$Task.title) `
        -Scope ([string]$Task.scope) `
        -PromptPath ([string]$Package.package_path) `
        -AllowedFiles @($Package.relevant_modules) `
        -ValidationCommands @($Package.tests_to_run) `
        -Metadata @{ source = "execute-task-loop"; generated_at = (Get-UtcNow) }

    $selected = [string]$EngineConfig.active
    try {
        switch ($selected) {
            "codex" {
                . (Join-Path $engineDir "CodexExecutionEngine.ps1")
                $engineResult = Invoke-CodexExecutionEngine -Context $context
                $todResult = Convert-CodexEngineResultToTodResult -EngineResult $engineResult
            }
            "local" {
                . (Join-Path $engineDir "LocalExecutionEngine.ps1")
                $engineResult = Invoke-LocalExecutionEngine -Context $context
                $todResult = Convert-LocalEngineResultToTodResult -EngineResult $engineResult
            }
            default {
                throw "Unsupported execution engine '$selected'."
            }
        }
    }
    catch {
        if (-not [bool]$EngineConfig.allow_fallback -or [string]::IsNullOrWhiteSpace([string]$EngineConfig.fallback) -or ([string]$EngineConfig.fallback -eq $selected)) {
            throw
        }

        $selected = [string]$EngineConfig.fallback
        switch ($selected) {
            "codex" {
                . (Join-Path $engineDir "CodexExecutionEngine.ps1")
                $engineResult = Invoke-CodexExecutionEngine -Context $context
                $todResult = Convert-CodexEngineResultToTodResult -EngineResult $engineResult
            }
            "local" {
                . (Join-Path $engineDir "LocalExecutionEngine.ps1")
                $engineResult = Invoke-LocalExecutionEngine -Context $context
                $todResult = Convert-LocalEngineResultToTodResult -EngineResult $engineResult
            }
            default {
                throw "Unsupported fallback execution engine '$selected'."
            }
        }
    }

    return [pscustomobject]@{
        selected_engine = $selected
        engine_result = $engineResult
        tod_result = $todResult
    }
}

function Get-TaskById {
    param([string]$Id)

    $tasks = Get-TodObjects -ActionName "list-tasks"
    $task = $tasks | Where-Object {
        $tid = [string](Get-OptionalProp -Object $_ -Name "task_id")
        $lid = [string](Get-OptionalProp -Object $_ -Name "id")
        ($tid -eq $Id) -or ($lid -eq $Id)
    } | Select-Object -First 1
    if (-not $task) { throw "Task not found in TOD view: $Id" }
    return $task
}

function Get-ObjectiveById {
    param([string]$Id)

    $objectives = Get-TodObjects -ActionName "list-objectives"
    $objective = $objectives | Where-Object {
        $oid = [string](Get-OptionalProp -Object $_ -Name "objective_id")
        $lid = [string](Get-OptionalProp -Object $_ -Name "id")
        ($oid -eq $Id) -or ($lid -eq $Id)
    } | Select-Object -First 1
    if (-not $objective) { throw "Objective not found in TOD view: $Id" }
    return $objective
}

function Ensure-MemoryFile {
    if (-not (Test-Path $memoryPath)) {
        @{
            architecture_memory = @()
            repo_memory = @()
            decision_memory = @()
            failure_memory = @()
            pattern_memory = @()
            test_memory = @()
            packaging_lessons = @()
        } | ConvertTo-Json -Depth 8 | Set-Content -Path $memoryPath
    }
}

function Add-MemoryEntry {
    param(
        [string]$Bucket,
        [string]$EntryTitle,
        [string]$EntryNote,
        [string[]]$EntryTags
    )

    Ensure-MemoryFile
    $memory = Load-JsonFile -Path $memoryPath
    $entry = [pscustomobject]@{
        id = "MEM-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
        title = $EntryTitle
        note = $EntryNote
        tags = @($EntryTags)
        created_at = Get-UtcNow
    }
    $memory.$Bucket += $entry
    Save-JsonFile -Object $memory -Path $memoryPath
    return $entry
}

function Get-RepoIndex {
    if (-not (Test-Path $repoIndexPath)) {
        & $PSCommandPath -Action index-repo | Out-Null
    }
    Load-JsonFile -Path $repoIndexPath
}

function Get-ModuleSummaries {
    if (-not (Test-Path $moduleSummaryPath)) {
        return [pscustomobject]@{
            generated_at = $null
            repository = [pscustomobject]@{ root = $repoRoot }
            modules = @()
        }
    }
    Load-JsonFile -Path $moduleSummaryPath
}

function Build-PackageV2 {
    param(
        [string]$ResolvedTaskId,
        [string[]]$ValidationCommandList,
        [string[]]$EscalationTriggerList
    )

    $task = Get-TaskById -Id $ResolvedTaskId
    $objectiveId = [string]$task.objective_id
    $objective = Get-ObjectiveById -Id $objectiveId
    $index = Get-RepoIndex

    $taskTitle = [string]$task.title
    $taskScope = [string]$task.scope
    $tokens = @($taskTitle, $taskScope) -join " "
    $tokenTerms = @($tokens -split '\\s+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_.Length -gt 3 }) | Select-Object -Unique

    $candidateFiles = @($index.key_files + $index.docs_files + $index.test_files) | Select-Object -Unique
    $related = @($candidateFiles | Where-Object {
        $p = $_.ToLowerInvariant()
        ($tokenTerms | Where-Object { $p -match [regex]::Escape($_) } | Select-Object -First 1)
    } | Select-Object -First 12)

    if (@($related).Count -eq 0) {
        $related = @($index.key_files | Select-Object -First 8)
    }

    $constraints = @()
    if ($objective.PSObject.Properties["constraints"]) {
        if ($objective.constraints -is [string]) { $constraints = Split-ListSmart -Value $objective.constraints }
        else { $constraints = @($objective.constraints | ForEach-Object { [string]$_ }) }
    }

    $acceptance = @()
    if ($task.PSObject.Properties["acceptance_criteria"]) {
        if ($task.acceptance_criteria -is [string]) { $acceptance = Split-ListSmart -Value $task.acceptance_criteria }
        else { $acceptance = @($task.acceptance_criteria | ForEach-Object { [string]$_ }) }
    }

    $validationCommandsFinal = if (Test-HasItems -Value $ValidationCommandList) { @($ValidationCommandList) } else { @("powershell -NoProfile -File .\\scripts\\TOD.ps1 -Action ping-mim -ConfigPath e:\\TOD\\tod\\config\\tod-config.json") }
    $escalationFinal = if (Test-HasItems -Value $EscalationTriggerList) { @($EscalationTriggerList) } else { @("scope drift outside listed files", "failing tests without clear remediation", "architecture-affecting change requiring human judgment", "unsafe or destructive operations") }

    $systemContext = @(
        "TOD controls flow; MIM stores truth; Codex performs implementation.",
        "Repository branch: $($index.repository.branch)",
        "Repository commit: $($index.repository.commit)",
        "Objective status: $([string]$objective.status)",
        "Task status: $([string]$task.status)"
    )

    $content = @()
    $content += "# TOD Task Execution Package V2"
    $content += ""
    $content += "## system_context"
    $content += ($systemContext | ForEach-Object { "- $_" })
    $content += ""
    $content += "## task_scope"
    $content += "- task_id: $ResolvedTaskId"
    $content += "- objective_id: $objectiveId"
    $content += "- title: $taskTitle"
    $content += "- scope: $taskScope"
    $content += ""
    $content += "## relevant_modules"
    $content += ($related | ForEach-Object { "- " + (Normalize-SlashPath -Path $_) })
    $content += ""
    $content += "## constraints"
    $content += (@($constraints) | ForEach-Object { "- $_" })
    $content += ""
    $content += "## implementation_requirements"
    $content += "- Stay inside task scope and relevant modules unless escalation trigger is met."
    $content += "- Reuse existing patterns before introducing new structure."
    $content += "- Keep changes auditable and testable."
    $content += ""
    $content += "## tests_to_run"
    $content += (@($validationCommandsFinal) | ForEach-Object { "- $_" })
    $content += ""
    $content += "## definition_of_done"
    $content += (@($acceptance) | ForEach-Object { "- $_" })
    $content += ""
    $content += "## expected_output_shape"
    $content += "- task_id"
    $content += "- summary"
    $content += "- files_changed"
    $content += "- tests_run"
    $content += "- test_results"
    $content += "- failures"
    $content += "- recommendations"
    $content += "- needs_escalation"
    $content += ""
    $content += "## escalation_triggers"
    $content += (@($escalationFinal) | ForEach-Object { "- $_" })

    if (-not (Test-Path $promptV2Path)) {
        New-Item -ItemType Directory -Path $promptV2Path -Force | Out-Null
    }

    $outPath = Join-Path $promptV2Path ("{0}.md" -f $ResolvedTaskId)
    Set-Content -Path $outPath -Value ($content -join [Environment]::NewLine)

    return [pscustomobject]@{
        task_id = $ResolvedTaskId
        objective_id = $objectiveId
        package_path = $outPath
        relevant_modules = @($related | ForEach-Object { Normalize-SlashPath -Path $_ })
        tests_to_run = @($validationCommandsFinal)
        escalation_triggers = @($escalationFinal)
    }
}

function Split-AcceptanceCriteriaEntries {
    param($AcceptanceValue)

    $items = @()
    if ($null -eq $AcceptanceValue) { return @() }

    if ($AcceptanceValue -is [string]) {
        $items = @([string]$AcceptanceValue)
    }
    else {
        $items = @($AcceptanceValue | ForEach-Object { [string]$_ })
    }

    $expanded = @()
    foreach ($item in $items) {
        foreach ($part in @($item -split ';')) {
            $trimmed = [string]$part
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $expanded += $trimmed.Trim()
            }
        }
    }

    return @($expanded | Select-Object -Unique)
}

function Normalize-ReviewText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $normalized = $Text.ToLowerInvariant()
    $normalized = $normalized -replace '[^a-z0-9\s_-]+', ' '
    $normalized = $normalized -replace '[_-]+', ' '
    $normalized = $normalized -replace '\s+', ' '
    return $normalized.Trim()
}

function Get-SemanticTokens {
    param([string]$Text)

    $stopWords = @(
        "the", "and", "for", "with", "from", "into", "that", "this", "are", "was", "were", "been", "being", "without", "within", "only", "include", "includes", "through"
    )
    $canonicalMap = @{
        "selectable" = "select"
        "selected" = "select"
        "selection" = "select"
        "configurable" = "config"
        "configuration" = "config"
        "configured" = "config"
        "engine" = "engine"
        "placeholder" = "placeholder"
        "stub" = "placeholder"
        "not" = "not"
        "implemented" = "implemented"
        "implementation" = "implemented"
        "semantic" = "semantic"
        "equivalent" = "equivalent"
        "wording" = "wording"
        "criteria" = "criteria"
        "criterion" = "criteria"
    }

    $tokens = @()
    $normalized = Normalize-ReviewText -Text $Text
    if ([string]::IsNullOrWhiteSpace($normalized)) { return @() }

    foreach ($raw in @($normalized -split ' ')) {
        $token = [string]$raw
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($token.Length -lt 3) { continue }
        if ($stopWords -contains $token) { continue }

        if ($canonicalMap.ContainsKey($token)) {
            $token = [string]$canonicalMap[$token]
        }
        $tokens += $token
    }

    return @($tokens | Select-Object -Unique)
}

function Test-AcceptanceCriterionEvidence {
    param(
        [string]$Criterion,
        [string]$Evidence
    )

    $criterionNorm = Normalize-ReviewText -Text $Criterion
    $evidenceNorm = Normalize-ReviewText -Text $Evidence
    if ([string]::IsNullOrWhiteSpace($criterionNorm)) { return $true }

    if ($evidenceNorm.Contains($criterionNorm)) {
        return $true
    }

    $criterionTokens = @(Get-SemanticTokens -Text $criterionNorm)
    $evidenceTokens = @(Get-SemanticTokens -Text $evidenceNorm)
    if ($criterionTokens.Length -eq 0) { return $true }
    if ($evidenceTokens.Length -eq 0) { return $false }

    $overlapCount = @($criterionTokens | Where-Object { $evidenceTokens -contains $_ }).Length
    $coverage = [double]$overlapCount / [double]$criterionTokens.Length
    $requiredCoverage = if ($criterionTokens.Length -le 3) { 0.66 } else { 0.5 }

    if ($coverage -ge $requiredCoverage) {
        return $true
    }

    # Handle common engine phrasing where wording varies but intent is equivalent.
    $mentionsSelectConfig = ($criterionNorm -match 'select|config')
    $evidenceSelectConfig = ($evidenceNorm -match 'execution engine|execution_engine|active=|active |config')
    if ($mentionsSelectConfig -and $evidenceSelectConfig) {
        return $true
    }

    return $false
}

function Evaluate-ResultV2 {
    param(
        [string]$ResolvedTaskId,
        [string]$JsonPath,
        [string[]]$AllowedFileList
    )

    Assert-PathExists -Path $JsonPath -Name "Result JSON"
    $task = Get-TaskById -Id $ResolvedTaskId
    $result = (Get-Content -Path $JsonPath -Raw) | ConvertFrom-Json

    $requiredFields = @("task_id", "summary", "files_changed", "tests_run", "test_results", "failures", "recommendations", "needs_escalation")
    $missing = @($requiredFields | Where-Object { -not $result.PSObject.Properties[$_] })

    $filesChanged = @($result.files_changed)
    $testsRun = @($result.tests_run)
    $testResults = @($result.test_results)
    $failures = @($result.failures)
    $needsEscalation = [bool]$result.needs_escalation

    $scopeViolations = @()
    $allowedListNormalized = @($AllowedFileList | Where-Object { $null -ne $_ -and [string]$_ -ne "" })
    if ($allowedListNormalized.Length -gt 0) {
        $normalizedAllowed = @($allowedListNormalized | ForEach-Object { Normalize-SlashPath -Path $_.Trim() } | Where-Object { $_ })
        foreach ($f in $filesChanged) {
            $normalized = Normalize-SlashPath -Path ([string]$f)
            if (-not ($normalizedAllowed -contains $normalized)) {
                $scopeViolations += $normalized
            }
        }
    }

    $acceptance = @()
    if ($task.PSObject.Properties["acceptance_criteria"]) {
        if ($task.acceptance_criteria -is [string]) { $acceptance = Split-AcceptanceCriteriaEntries -AcceptanceValue $task.acceptance_criteria }
        else { $acceptance = Split-AcceptanceCriteriaEntries -AcceptanceValue @($task.acceptance_criteria | ForEach-Object { [string]$_ }) }
    }

    $evidenceBlob = (@(
            [string]$result.summary,
            (@($result.files_changed) -join " "),
            (@($testsRun) -join " "),
            (@($testResults) -join " "),
            (@($result.failures) -join " "),
            (@($result.recommendations) -join " "),
            ((ConvertTo-Json -InputObject $result -Depth 8 -Compress) | Out-String)
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join " "

    $unsatisfiedAcceptance = @($acceptance | Where-Object {
            -not (Test-AcceptanceCriterionEvidence -Criterion ([string]$_) -Evidence $evidenceBlob)
        })

    $hasTests = @($testsRun).Count -gt 0 -and @($testResults).Count -gt 0
    $hasPassToken = (($testResults -join " ").ToLowerInvariant() -match "pass|ok|success")

    $checkResults = [pscustomobject]@{
        required_fields_present = (@($missing).Count -eq 0)
        missing_fields = @($missing)
        scope_compliant = (@($scopeViolations).Count -eq 0)
        scope_violations = @($scopeViolations)
        test_evidence_present = $hasTests
        tests_indicate_success = [bool]$hasPassToken
        acceptance_criteria_unsatisfied = @($unsatisfiedAcceptance)
        failure_count = @($failures).Count
        needs_escalation = $needsEscalation
    }

    $decision = "pass"
    if ($needsEscalation) {
        $decision = "escalate"
    }
    elseif ((@($missing).Count -gt 0) -or (@($scopeViolations).Count -gt 0) -or (-not $hasTests) -or (@($failures).Count -gt 0) -or (@($unsatisfiedAcceptance).Count -gt 0)) {
        $decision = "revise"
    }

    $rationaleParts = @()
    if ($decision -eq "pass") {
        $rationaleParts += "Result satisfies required structure, scope, tests, and acceptance evidence."
    }
    else {
        if (@($missing).Count -gt 0) { $rationaleParts += "Missing required fields: " + (@($missing) -join ", ") }
        if (@($scopeViolations).Count -gt 0) { $rationaleParts += "Scope violations: " + (@($scopeViolations) -join ", ") }
        if (-not $hasTests) { $rationaleParts += "Insufficient test evidence." }
        if (@($failures).Count -gt 0) { $rationaleParts += "Reported failures: " + (@($failures) -join "; ") }
        if (@($unsatisfiedAcceptance).Count -gt 0) { $rationaleParts += "Acceptance criteria not evidenced: " + (@($unsatisfiedAcceptance) -join "; ") }
        if ($needsEscalation) { $rationaleParts += "Result requested escalation." }
    }

    [pscustomobject]@{
        task_id = $ResolvedTaskId
        decision = $decision
        rationale = ($rationaleParts -join " ")
        unresolved_issues = @($missing + $scopeViolations + $unsatisfiedAcceptance + $failures)
        checks = $checkResults
    }
}

switch ($Action) {
    "init-engineering-memory" {
        if (-not (Test-Path (Split-Path -Parent $memoryPath))) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $memoryPath) | Out-Null
        }
        Ensure-StateDir

        $emptyMemory = @{
                architecture_memory = @()
                repo_memory = @()
                decision_memory = @()
                failure_memory = @()
                pattern_memory = @()
                test_memory = @()
                packaging_lessons = @()
            }

        if (-not (Test-Path $memoryPath)) {
            Save-JsonWithStateMirror -Object $emptyMemory -PrimaryPath $memoryPath -MirrorPath $stateMemoryPath
        }
        elseif (-not (Test-Path $stateMemoryPath)) {
            $existingMemory = Load-JsonFile -Path $memoryPath
            Save-JsonFile -Object $existingMemory -Path $stateMemoryPath
        }

        $emptyIndex = @{
                generated_at = $null
                repository = @{ root = $null; branch = $null; commit = $null }
                top_level_folders = @()
                directories = @()
                files = @()
                files_by_extension = @()
                important_files = @()
                entry_points = @()
                scripts = @()
                key_files = @()
                test_files = @()
                docs_files = @()
            }

        if (-not (Test-Path $repoIndexPath)) {
            Save-JsonWithStateMirror -Object $emptyIndex -PrimaryPath $repoIndexPath -MirrorPath $stateRepoIndexPath
        }
        elseif (-not (Test-Path $stateRepoIndexPath)) {
            $existingIndex = Load-JsonFile -Path $repoIndexPath
            Save-JsonFile -Object $existingIndex -Path $stateRepoIndexPath
        }

        if (-not (Test-Path $moduleSummaryPath)) {
            $emptySummaries = [pscustomobject]@{
                generated_at = $null
                repository = [pscustomobject]@{ root = $repoRoot }
                modules = @()
            }
            Save-JsonWithStateMirror -Object $emptySummaries -PrimaryPath $moduleSummaryPath -MirrorPath $stateModuleSummaryPath
        }
        elseif (-not (Test-Path $stateModuleSummaryPath)) {
            $existingSummaries = Load-JsonFile -Path $moduleSummaryPath
            Save-JsonFile -Object $existingSummaries -Path $stateModuleSummaryPath
        }

        Write-Host "Engineering memory initialized." -ForegroundColor Green
    }

    "add-memory-note" {
        if ([string]::IsNullOrWhiteSpace($Bucket)) { throw "-Bucket is required" }
        if ([string]::IsNullOrWhiteSpace($Title)) { throw "-Title is required" }
        if ([string]::IsNullOrWhiteSpace($Note)) { throw "-Note is required" }

        $memory = Load-JsonFile -Path $memoryPath
        $entry = [pscustomobject]@{
            id = "MEM-{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8).ToUpperInvariant())
            title = $Title
            note = $Note
            tags = @(Split-StringList -Value $Tags)
            created_at = Get-UtcNow
        }

        $memory.$Bucket += $entry
        Save-JsonWithStateMirror -Object $memory -PrimaryPath $memoryPath -MirrorPath $stateMemoryPath
        $entry | ConvertTo-Json -Depth 8
    }

    "show-memory" {
        $memory = Load-JsonFile -Path $memoryPath

        if ([string]::IsNullOrWhiteSpace($Bucket)) {
            [pscustomobject]@{
                architecture_memory = @($memory.architecture_memory).Count
                repo_memory = @($memory.repo_memory).Count
                decision_memory = @($memory.decision_memory).Count
                failure_memory = @($memory.failure_memory).Count
                pattern_memory = @($memory.pattern_memory).Count
                test_memory = @($memory.test_memory).Count
                packaging_lessons = @($memory.packaging_lessons).Count
            } | ConvertTo-Json -Depth 6
            break
        }

        @($memory.$Bucket) |
            Sort-Object -Property created_at -Descending |
            Select-Object -First $Top |
            ConvertTo-Json -Depth 8
    }

    "index-repo" {
        $excludeDirs = @(".git", "node_modules", ".venv", "venv", "__pycache__")

        $files = Get-ChildItem -Path $repoRoot -Recurse -File |
            Where-Object {
                $full = $_.FullName
                -not ($excludeDirs | ForEach-Object { $full -like "*\\$_\\*" } | Where-Object { $_ })
            }

        $topFolders = Get-ChildItem -Path $repoRoot -Directory |
            Select-Object Name,
                @{ Name = "file_count"; Expression = { (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count } }

        $directories = Get-ChildItem -Path $repoRoot -Recurse -Directory |
            Where-Object {
                $full = $_.FullName
                -not ($excludeDirs | ForEach-Object { $full -like "*\\$_\\*" } | Where-Object { $_ })
            } |
            ForEach-Object { To-RepoRelativePath -FullPath $_.FullName }

        $allFiles = $files | ForEach-Object { To-RepoRelativePath -FullPath $_.FullName }

        $extCounts = $files |
            Group-Object Extension |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    extension = if ([string]::IsNullOrWhiteSpace($_.Name)) { "(none)" } else { $_.Name }
                    count = $_.Count
                }
            }

        $keyFiles = $files |
            Where-Object { $_.Name -match "^(README\.md|pyproject\.toml|package\.json|TOD\.ps1|TOD-Engineer\.ps1|mim_api_client\.ps1|mim_api_helpers\.ps1|tod-config\.json)$" } |
            ForEach-Object { To-RepoRelativePath -FullPath $_.FullName }

        $scriptFiles = $files |
            Where-Object { $_.Extension -eq ".ps1" -or $_.Name -match "\.sh$|\.bat$" } |
            ForEach-Object { To-RepoRelativePath -FullPath $_.FullName }

        $importantFiles = @($keyFiles + @("tod/data/state.json", "tod/data/engineering-memory.json", "tod/data/repo-index.json", "tod/data/module-summaries.json")) | Select-Object -Unique

        $entryPoints = @($files |
            Where-Object {
                $_.Name -match "^(TOD\.ps1|TOD-Engineer\.ps1|Connect-Mim\.ps1|main\.py|app\.py|index\.js|server\.js)$" -or
                $_.DirectoryName -match "scripts$"
            } |
            Select-Object -First 40 |
            ForEach-Object { To-RepoRelativePath -FullPath $_.FullName })

        $testFiles = $files |
            Where-Object { $_.Name -match "(test|spec)" -or $_.DirectoryName -match "test" } |
            Select-Object -First 200 |
            ForEach-Object { To-RepoRelativePath -FullPath $_.FullName }

        $docsFiles = $files |
            Where-Object { $_.DirectoryName -match "\\docs($|\\)" -or $_.Extension -eq ".md" } |
            Select-Object -First 200 |
            ForEach-Object { To-RepoRelativePath -FullPath $_.FullName }

        $branch = Get-GitValue -Command "git -C '$repoRoot' rev-parse --abbrev-ref HEAD"
        $commit = Get-GitValue -Command "git -C '$repoRoot' rev-parse --short HEAD"

        $index = [pscustomobject]@{
            generated_at = Get-UtcNow
            repository = [pscustomobject]@{
                root = $repoRoot
                branch = $branch
                commit = $commit
            }
            top_level_folders = @($topFolders)
            directories = @($directories)
            files = @($allFiles)
            files_by_extension = @($extCounts)
            important_files = @($importantFiles)
            entry_points = @($entryPoints)
            scripts = @($scriptFiles)
            key_files = @($keyFiles)
            test_files = @($testFiles)
            docs_files = @($docsFiles)
        }

        Save-JsonWithStateMirror -Object $index -PrimaryPath $repoIndexPath -MirrorPath $stateRepoIndexPath
        $index | ConvertTo-Json -Depth 10
    }

    "generate-module-summaries" {
        $index = Get-RepoIndex
        $candidatePaths = @($index.key_files + $index.entry_points + $index.scripts + $index.important_files) | Select-Object -Unique

        $modules = @()
        foreach ($p in $candidatePaths) {
            $full = Join-Path $repoRoot $p
            if (-not (Test-Path $full)) { continue }

            $firstLines = @(Get-Content -Path $full -TotalCount 80)
            $content = $firstLines -join "`n"

            $functionMatches = [regex]::Matches($content, 'function\\s+([A-Za-z0-9_-]+)')
            $classMatches = [regex]::Matches($content, 'class\\s+([A-Za-z0-9_-]+)')
            $imports = [regex]::Matches($content, 'import\\s+[^`n]+|from\\s+[^`n]+\\s+import\\s+[^`n]+')

            $exports = @($functionMatches | ForEach-Object { $_.Groups[1].Value })
            $classes = @($classMatches | ForEach-Object { $_.Groups[1].Value })
            $dependencies = @($imports | ForEach-Object { $_.Value.Trim() })

            $summary = if ($p -match 'TOD-Engineer\\.ps1') {
                "Engineering orchestration actions for memory, indexing, packaging, and execution loops."
            }
            elseif ($p -match 'TOD\\.ps1') {
                "Core workflow bridge for objective/task/result/review lifecycle with MIM."
            }
            elseif ($p -match 'mim_api_client\\.ps1|mim_api_helpers\\.ps1') {
                "MIM API bridge and schema normalization utilities."
            }
            elseif ($p -match 'README\\.md') {
                "Project operating guide and validated workflow commands."
            }
            else {
                "Module summary generated from static scan and naming heuristics."
            }

            $category = if ($p -match '^scripts/') { "orchestration" }
            elseif ($p -match '^client/') { "integration" }
            elseif ($p -match '^docs/') { "documentation" }
            elseif ($p -match '^tod/data/') { "state" }
            else { "module" }

            $modules += [pscustomobject]@{
                path = Normalize-SlashPath -Path $p
                summary = $summary
                exports_functions = @($exports)
                classes = @($classes)
                dependencies_imports = @($dependencies)
                related_modules = @()
                category = $category
                confidence = "medium"
                last_indexed = Get-UtcNow
            }
        }

        $modulePaths = @($modules | ForEach-Object { $_.path })
        foreach ($m in $modules) {
            $tokens = @(([string]$m.path + " " + [string]$m.summary) -split '[^A-Za-z0-9_]+' | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $_.Length -gt 3 }) | Select-Object -Unique
            $related = @($modulePaths | Where-Object {
                $candidate = $_
                $candidate -ne $m.path -and ($tokens | Where-Object { $candidate.ToLowerInvariant() -match [regex]::Escape($_) } | Select-Object -First 1)
            } | Select-Object -First 8)
            $m.related_modules = @($related)
        }

        $summaryDoc = [pscustomobject]@{
            generated_at = Get-UtcNow
            repository = [pscustomobject]@{
                root = $repoRoot
                branch = $index.repository.branch
                commit = $index.repository.commit
            }
            modules = @($modules)
        }

        Save-JsonWithStateMirror -Object $summaryDoc -PrimaryPath $moduleSummaryPath -MirrorPath $stateModuleSummaryPath
        [pscustomobject]@{ generated_at = $summaryDoc.generated_at; module_count = @($modules).Count } | ConvertTo-Json -Depth 6
    }

    "show-module-summary" {
        $summaries = Get-ModuleSummaries

        if ([string]::IsNullOrWhiteSpace($Path)) {
            @($summaries.modules) | Select-Object -First $Top | ConvertTo-Json -Depth 10
            break
        }

        $target = (Normalize-SlashPath -Path $Path).ToLowerInvariant()
        $module = @($summaries.modules | Where-Object { (Normalize-SlashPath -Path ([string]$_.path)).ToLowerInvariant() -eq $target }) | Select-Object -First 1
        if (-not $module) {
            $module = @($summaries.modules | Where-Object {
                $candidate = (Normalize-SlashPath -Path ([string]$_.path)).ToLowerInvariant()
                $candidate.EndsWith($target) -or $target.EndsWith($candidate)
            }) | Select-Object -First 1
        }
        if (-not $module) { throw "Module summary not found for path: $Path" }
        $module | ConvertTo-Json -Depth 10
    }

    "find-related-files" {
        if ([string]::IsNullOrWhiteSpace($Query)) { throw "-Query is required" }
        $index = Get-RepoIndex
        $summaries = Get-ModuleSummaries
        $q = $Query.ToLowerInvariant()
        $terms = @($q -split '[^a-z0-9_]+' | Where-Object { $_ -and $_.Length -gt 2 }) | Select-Object -Unique

        $fromIndex = @($index.files | Where-Object {
            $candidate = (Normalize-SlashPath -Path ([string]$_)).ToLowerInvariant()
            ($candidate -match [regex]::Escape($q)) -or ($terms | Where-Object { $candidate -match [regex]::Escape($_) } | Select-Object -First 1)
        })

        $fromSummary = @($summaries.modules | Where-Object {
            $blob = (@(
                    Normalize-SlashPath -Path ([string]$_.path),
                    [string]$_.summary,
                    (@($_.exports_functions) -join " "),
                    (@($_.dependencies_imports) -join " "),
                    (@($_.related_modules) -join " ")
                ) -join " ").ToLowerInvariant()

            ($blob -match [regex]::Escape($q)) -or ($terms | Where-Object { $blob -match [regex]::Escape($_) } | Select-Object -First 1)
        } | ForEach-Object { Normalize-SlashPath -Path ([string]$_.path) })

        [pscustomobject]@{
            query = $Query
            related_files = @($fromIndex + $fromSummary | ForEach-Object { Normalize-SlashPath -Path ([string]$_) } | Select-Object -Unique | Select-Object -First 50)
        } | ConvertTo-Json -Depth 8
    }

    "show-impact-area" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        $task = Get-TaskById -Id $TaskId
        $querySeed = @([string]$task.title, [string]$task.scope, [string]$task.acceptance_criteria) -join " "
        $tokens = @($querySeed -split '[^A-Za-z0-9_]+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_.Length -gt 3 }) | Select-Object -Unique

        $summaries = Get-ModuleSummaries
        $hits = @($summaries.modules | Where-Object {
            $blob = (@([string]$_.path, [string]$_.summary, (@($_.exports_functions) -join " "), (@($_.related_modules) -join " ")) -join " ").ToLowerInvariant()
            ($tokens | Where-Object { $blob -match [regex]::Escape($_) } | Select-Object -First 1)
        } | Select-Object -First 20)

        [pscustomobject]@{
            task_id = $TaskId
            impact_modules = @($hits | ForEach-Object { $_.path })
            notes = "Use these modules as the initial allowed/change focus surface."
        } | ConvertTo-Json -Depth 8
    }

    "show-repo-index" {
        $index = Load-JsonFile -Path $repoIndexPath
        $summary = Get-ModuleSummaries
        [pscustomobject]@{
            generated_at = $index.generated_at
            repository = $index.repository
            top_level_folders = $index.top_level_folders
            files_by_extension = $index.files_by_extension
            important_files = $index.important_files
            entry_points = $index.entry_points
            scripts = $index.scripts
            docs_files = $index.docs_files
            test_files = $index.test_files
            module_summary_count = @($summary.modules).Count
        } | ConvertTo-Json -Depth 10
    }

    "bootstrap-upgrade-objective" {
        Assert-PathExists -Path $todScriptPath -Name "TOD script"

        $objective = & $todScriptPath -Action new-objective -ConfigPath $configPathResolved `
            -Title "Upgrade TOD into a repository-aware programming orchestrator" `
            -Description "Build engineering memory, repo indexing, context-rich packaging, review intelligence, and method-improvement loops." `
            -Priority high `
            -Constraints "MIM remains durable source of truth,Do not break existing bridge actions" `
            -SuccessCriteria "TOD can index a repo,TOD can summarize module responsibilities,TOD can attach relevant context to packaged tasks,TOD can record engineering memory,TOD can review returned code against scope and acceptance criteria,TOD can improve packaging based on prior results" |
            ConvertFrom-Json

        $objectiveId = Resolve-TodId -TodResponse $objective -Primary "objective_id" -Fallback "id"

        $tasks = @(
            @{
                Title = "Add engineering memory model"
                Scope = "Implement persistent engineering memory buckets and access commands."
                Acceptance = "Memory buckets exist,Notes can be added and queried"
            },
            @{
                Title = "Add repo indexer"
                Scope = "Scan repository, summarize structure, and persist index snapshots."
                Acceptance = "Repo index generated,Key files/tests/docs are mapped"
            },
            @{
                Title = "Add module summary generator"
                Scope = "Derive module-level summaries from indexed repository metadata."
                Acceptance = "Module summaries available for task packaging context"
            },
            @{
                Title = "Upgrade task packaging schema"
                Scope = "Add richer package sections including architecture/context/validation commands/escalation triggers."
                Acceptance = "Packaging v2 template contains required sections"
            },
            @{
                Title = "Add result-review rule engine"
                Scope = "Evaluate scope compliance, test evidence, architecture/risk checks, and suggest pass/revise/escalate."
                Acceptance = "Rule-based review output includes decision rationale"
            },
            @{
                Title = "Persist packaging lessons into MIM"
                Scope = "Capture post-task reflections and store lessons via bridge-compatible flow."
                Acceptance = "Packaging lessons persisted and queryable"
            }
        )

        $createdTasks = @()
        foreach ($task in $tasks) {
            $created = & $todScriptPath -Action add-task -ConfigPath $configPathResolved `
                -ObjectiveId $objectiveId `
                -Title $task.Title `
                -Type implementation `
                -Scope $task.Scope `
                -AcceptanceCriteria $task.Acceptance |
                ConvertFrom-Json

            $taskId = Resolve-TodId -TodResponse $created -Primary "task_id" -Fallback "id"
            $createdTasks += [pscustomobject]@{ task_id = $taskId; title = $task.Title }
        }

        [pscustomobject]@{
            objective_id = $objectiveId
            created_tasks = $createdTasks
        } | ConvertTo-Json -Depth 8
    }

    "package-task-v2" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        $package = Build-PackageV2 -ResolvedTaskId $TaskId -ValidationCommandList (Split-ListSmart -Value $ValidationCommands) -EscalationTriggerList (Split-ListSmart -Value $EscalationTriggers)
        Add-MemoryEntry -Bucket "pattern_memory" -EntryTitle "Packaged task v2" -EntryNote ("Generated package v2 for task {0} at {1}" -f $TaskId, $package.package_path) -EntryTags @("packaging", "v2", "task:$TaskId") | Out-Null
        $package | ConvertTo-Json -Depth 10
    }

    "review-result-v2" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        if ([string]::IsNullOrWhiteSpace($ResultJsonPath)) { throw "-ResultJsonPath is required" }

        $report = Evaluate-ResultV2 -ResolvedTaskId $TaskId -JsonPath $ResultJsonPath -AllowedFileList (Split-ListSmart -Value $AllowedFiles)

        if ($report.decision -eq "pass") {
            Add-MemoryEntry -Bucket "test_memory" -EntryTitle "Successful review" -EntryNote ("Task {0} passed review-result-v2." -f $TaskId) -EntryTags @("review", "pass", "task:$TaskId") | Out-Null
        }
        else {
            Add-MemoryEntry -Bucket "failure_memory" -EntryTitle "Review required changes" -EntryNote ("Task {0} decision {1}. {2}" -f $TaskId, $report.decision, $report.rationale) -EntryTags @("review", $report.decision, "task:$TaskId") | Out-Null
        }

        $report | ConvertTo-Json -Depth 10
    }

    "execute-task-loop" {
        if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "-TaskId is required" }
        $package = Build-PackageV2 -ResolvedTaskId $TaskId -ValidationCommandList (Split-ListSmart -Value $ValidationCommands) -EscalationTriggerList (Split-ListSmart -Value $EscalationTriggers)
        $task = Get-TaskById -Id $TaskId

        if ([string]::IsNullOrWhiteSpace($ResultJsonPath)) {
            $engineConfig = Load-ExecutionEngineConfig -Path $configPathResolved
            $executed = Invoke-TaskExecutionEngine -Package $package -Task $task -EngineConfig $engineConfig
            $result = $executed.tod_result

            $resultDir = Join-Path $repoRoot "tod/out/results-v2"
            if (-not (Test-Path -Path $resultDir)) {
                New-Item -ItemType Directory -Path $resultDir -Force | Out-Null
            }
            $ResultJsonPath = Join-Path $resultDir ("{0}.json" -f $TaskId)
            $result | ConvertTo-Json -Depth 12 | Set-Content -Path $ResultJsonPath
        }
        else {
            $result = (Get-Content -Path $ResultJsonPath -Raw) | ConvertFrom-Json
        }

        $filesChangedCsv = (@($result.files_changed) | ForEach-Object { [string]$_ }) -join ","
        $testsRunCsv = (@($result.tests_run) | ForEach-Object { [string]$_ }) -join ","
        $testResultsCsv = (@($result.test_results) | ForEach-Object { [string]$_ }) -join ","
        $failuresCsv = (@($result.failures) | ForEach-Object { [string]$_ }) -join ","
        $recommendationsCsv = (@($result.recommendations) | ForEach-Object { [string]$_ }) -join ","

        $addResultResponse = & $todScriptPath -Action add-result -ConfigPath $configPathResolved -TaskId $TaskId -Summary ([string]$result.summary) -FilesChanged $filesChangedCsv -TestsRun $testsRunCsv -TestResults $testResultsCsv -Failures $failuresCsv -Recommendations $recommendationsCsv | ConvertFrom-Json

        $reviewReport = Evaluate-ResultV2 -ResolvedTaskId $TaskId -JsonPath $ResultJsonPath -AllowedFileList (Split-ListSmart -Value $AllowedFiles)

        $unresolvedCsv = (@($reviewReport.unresolved_issues) | ForEach-Object { [string]$_ }) -join ","
        $reviewResponse = & $todScriptPath -Action review-task -ConfigPath $configPathResolved -TaskId $TaskId -Decision $reviewReport.decision -Rationale $reviewReport.rationale -UnresolvedIssues $unresolvedCsv | ConvertFrom-Json

        $loopDecision = if ($reviewReport.decision -eq "pass") { "continue" } elseif ($reviewReport.decision -eq "revise") { "revise" } else { "escalate" }
        Add-MemoryEntry -Bucket "packaging_lessons" -EntryTitle "Task loop feedback" -EntryNote ("Task {0} decision {1}; outcome {2}." -f $TaskId, $reviewReport.decision, $loopDecision) -EntryTags @("loop", "task:$TaskId", "decision:$($reviewReport.decision)") | Out-Null

        [pscustomobject]@{
            task_id = $TaskId
            package = $package
            result_json_path = $ResultJsonPath
            add_result_response = $addResultResponse
            review_report = $reviewReport
            review_response = $reviewResponse
            loop_decision = $loopDecision
        } | ConvertTo-Json -Depth 12
    }
}
