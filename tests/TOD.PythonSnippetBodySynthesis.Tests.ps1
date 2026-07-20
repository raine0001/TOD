Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'scripts/engines/ExecutionEngine.ps1')
. (Join-Path $repoRoot 'scripts/engines/LocalExecutionEngine.ps1')

function New-TestPromptFile {
    param([Parameter(Mandatory = $true)][string]$Content)

    $dir = Join-Path $repoRoot ('tod/out/tests/python-snippet-body-synthesis-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'task.md'
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

Describe 'TOD Python snippet body synthesis' {
    It 'creates a packet candidate from a source anchor without editing source files' {
        $sourceRel = ('tod/out/tests/python-snippet-target-{0}.py' -f [guid]::NewGuid().ToString('N'))
        $anchorRel = ('runtime_remote_training/read_only_audit_artifacts/PYTHON_SNIPPET_ANCHOR_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $packetRel = ('runtime_remote_training/tod_independent_resolution_attempts/PYTHON_SNIPPET_PACKET_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $sourcePath = Join-Path $repoRoot ($sourceRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $anchorPath = Join-Path $repoRoot ($anchorRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $packetPath = Join-Path $repoRoot ($packetRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        $sourceText = @'
class ExistingModel:
    id = 1


class LaterModel:
    id = 2
'@
        New-Item -ItemType Directory -Path (Split-Path -Parent $sourcePath) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $anchorPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($sourcePath, $sourceText, (New-Object System.Text.UTF8Encoding($false)))
        $anchor = [ordered]@{
            artifact_type = 'tod_source_anchor_observation'
            generated_at = '2026-07-17T00:00:00Z'
            source = 'test'
            objective_id = 'OBJ-PY-SNIPPET'
            task_id = 'TSK-PY-SNIPPET'
            source_file = $sourceRel
            anchor_pattern = 'class LaterModel:'
            matched = $true
            start_line = 1
            end_line = 6
            line_count = 6
            exact_text = $sourceText
            no_code_changes = $true
            validation = [ordered]@{ artifact_path = $anchorRel; source_read = $true; anchor_found = $true; exact_text_nonempty = $true; source_edits = @() }
            continuation_action = 'Use exact_text as old_text.'
        }
        [System.IO.File]::WriteAllText($anchorPath, ($anchor | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))

        $snippet = @'
class Enterprise:
    id = 3
'@
        $promptText = @"
Python snippet body synthesis.
Input Artifact: $anchorRel
Output artifact: $packetRel
Target File: $packetRel
Edit Mode: artifact_write
Packet Source Target: $sourceRel
Insert Before Pattern: class LaterModel:
Snippet:
$snippet
Validation Command: python -m py_compile $sourceRel
Validation Pattern: class Enterprise
Closure Evidence: Packet candidate includes byte-current old_text and synthesized new_text.
Prevention Lesson: TOD must synthesize Python class packets from source-anchor evidence before implementation.
Dave Needed: no
"@
        $promptPath = New-TestPromptFile -Content $promptText
        $context = [pscustomobject]@{
            task_id = 'TSK-PYTHON-SNIPPET-BODY-SYNTHESIS'
            objective_id = 'OBJ-PYTHON-SNIPPET-BODY-SYNTHESIS'
            title = 'Python snippet body synthesis packet'
            scope = $promptText
            prompt_path = $promptPath
            task_category = 'packet_formation'
            allowed_files = @()
            validation_commands = @()
            metadata = @{ task_category = 'packet_formation' }
        }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $packetArtifact = Get-Content -Path $packetPath -Raw | ConvertFrom-Json
            $sourceAfter = Get-Content -Path $sourcePath -Raw

            [string]$result.status | Should Be 'completed'
            [string]$packetArtifact.artifact_type | Should Be 'tod_python_snippet_body_synthesis_artifact'
            [bool]$packetArtifact.packet_candidate_ready | Should Be $true
            [string]$packetArtifact.packet.target_file | Should Be $sourceRel
            [string]$packetArtifact.packet.intended_edit_mode | Should Be 'replace_exact_text'
            [string]$packetArtifact.packet.old_text | Should Be $sourceText
            [string]$packetArtifact.packet.new_text | Should Match 'class Enterprise'
            [string]$packetArtifact.packet.new_text | Should Match 'class LaterModel'
            [string]$sourceAfter | Should Be $sourceText
            @($result.files_changed) -contains $packetRel | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $sourcePath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $anchorPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $packetPath -Force -ErrorAction SilentlyContinue
        }
    }
}
