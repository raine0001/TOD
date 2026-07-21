Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'scripts/engines/ExecutionEngine.ps1')
. (Join-Path $repoRoot 'scripts/engines/LocalExecutionEngine.ps1')

function New-TestPromptFile {
    param([Parameter(Mandatory = $true)][string]$Content)

    $dir = Join-Path $repoRoot ('tod/out/tests/read-only-audit-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $path = Join-Path $dir 'task.md'
    [System.IO.File]::WriteAllText($path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

Describe 'TOD read-only audit regression artifact' {
    It 'publishes the TOD capability assessment JSON and Markdown artifacts without source edits' {
        $inputRel = ('tod/out/tests/capability-assessment-source-{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.json'
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $markdownPath = Join-Path $repoRoot 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.md'
        $jsonBackup = if (Test-Path -Path $outputPath -PathType Leaf) { [string](Get-Content -Path $outputPath -Raw) } else { $null }
        $markdownBackup = if (Test-Path -Path $markdownPath -PathType Leaf) { [string](Get-Content -Path $markdownPath -Raw) } else { $null }

        $source = [ordered]@{
            generated_at = '2026-07-17T12:00:00Z'
            metrics = @(
                [ordered]@{ metric = 'Validated TOD Edits'; current = '54'; source = 'tod_result_artifacts + tod/data/state.json' },
                [ordered]@{ metric = 'Meaningful TOD Implementations'; current = '41'; source = 'tod_result_artifacts' },
                [ordered]@{ metric = 'Independent TOD Resolutions'; current = '6'; source = 'tod_result_artifacts' },
                [ordered]@{ metric = 'TOD Selector Field Completeness'; current = 'complete; bounded_fields=8/8'; source = 'TOD_NEXT_TASK_SELECTION.latest.json' },
                [ordered]@{ metric = 'TOD Recovery Packet Regression'; current = 'regressed_to_recovery_packet_no_credit'; source = 'CODEX_TOD_RECOVERY_PACKET_REGRESSION.latest.json' }
            )
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, ($source | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input: $inputRel
Output artifact: $outputRel
Audit Subject: TOD-CAPABILITY-ASSESSMENT-V1
Use the read-only assessment artifact lane.
No source code modifications.
"@
        $promptPath = New-TestPromptFile -Content $promptText
        $context = [pscustomobject]@{
            task_id = 'TSK-TOD-CAPABILITY-ASSESSMENT-V1'
            objective_id = 'TOD-CAPABILITY-ASSESSMENT-V1'
            title = 'TOD capability assessment V1'
            scope = $promptText
            prompt_path = $promptPath
            task_category = 'read_only_assessment'
            allowed_files = @()
            validation_commands = @()
            metadata = @{ task_category = 'read_only_assessment' }
        }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_capability_assessment_v1'
            [string]$artifact.task_mode | Should Be 'read_only_assessment'
            [bool]$artifact.tod_read_only_assessment_completed | Should Be $true
            [bool]$artifact.tod_independent_capability_acquired | Should Be $false
            [bool]$artifact.no_source_code_modified_by_assessment | Should Be $true
            @($artifact.capabilities).Count | Should Be 12
            Test-Path -Path $markdownPath -PathType Leaf | Should Be $true
            (Get-Content -Path $markdownPath -Raw) -match 'TOD Capability Assessment V1' | Should Be $true
            @($result.files_changed) -contains 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.json' | Should Be $true
            @($result.files_changed) -contains 'runtime_remote_training/TOD_CAPABILITY_ASSESSMENT_V1.latest.md' | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
            if ($null -ne $jsonBackup) {
                [System.IO.File]::WriteAllText($outputPath, $jsonBackup, (New-Object System.Text.UTF8Encoding($false)))
            }
            elseif (Test-Path -Path $outputPath) {
                Remove-Item -Path $outputPath -Force
            }
            if ($null -ne $markdownBackup) {
                [System.IO.File]::WriteAllText($markdownPath, $markdownBackup, (New-Object System.Text.UTF8Encoding($false)))
            }
            elseif (Test-Path -Path $markdownPath) {
                Remove-Item -Path $markdownPath -Force
            }
        }
    }

    It 'extracts regression counts and failure families from a test summary' {
        $inputRel = ('tod/out/tests/regression-summary-{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_REGRESSION_AUDIT_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        $summary = [ordered]@{
            generated_at = '2026-07-10T01:00:00Z'
            passed_all = $false
            passed = 410
            failed = 3
            total = 413
            failed_tests = @(
                [ordered]@{ describe = 'TOD local fallback executor'; name = 'first'; message = 'failed'; classification = 'deterministic' },
                [ordered]@{ describe = 'TOD local fallback executor'; name = 'second'; message = 'failed'; classification = 'deterministic' },
                [ordered]@{ describe = 'TOD self-driving next task selection'; name = 'third'; message = 'failed'; classification = 'deterministic' }
            )
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, ($summary | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input: $inputRel
Output artifact: $outputRel
Audit Subject: TOD operations regression snapshot.
Use the read-only audit artifact lane.
No code changes.
"@
        $promptPath = New-TestPromptFile -Content $promptText
        $context = [pscustomobject]@{
            task_id = 'TSK-READ-ONLY-REGRESSION-AUDIT'
            objective_id = 'OBJ-READ-ONLY-AUDIT'
            title = 'Regression snapshot read-only audit artifact'
            scope = $promptText
            prompt_path = $promptPath
            task_category = 'report_only'
            allowed_files = @()
            validation_commands = @()
            metadata = @{ task_category = 'report_only' }
        }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.classification | Should Be 'regression_snapshot_review_required'
        @($artifact.evidence_used[0].fields) -contains 'failed_tests' | Should Be $true
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'regression_snapshot_counts' -and [string]$_.evidence -match 'passed=410; failed=3; total=413' }).Count | Should Be 1
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'regression_failure_families' -and [string]$_.evidence -match 'TOD local fallback executor' }).Count | Should Be 1
        @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'regression_failures' }).Count | Should Be 1
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
    }

    It 'extracts watchdog bridge-smoke divergence from nested evidence' {
        $inputRel = ('tod/out/tests/watchdog-bridge-smoke-{0}.json' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_WATCHDOG_AUDIT_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        $watchdog = [ordered]@{
            generated_at = '2026-07-10T02:00:00Z'
            source = 'tod-recovery-watchdog-v1'
            state = 'error'
            heartbeat_age_seconds = 12
            bridge_smoke = [ordered]@{
                passed = $false
                status = 'fail'
                classification = 'publication_surface_divergence'
                failure_reason = 'publication_surface_divergence'
                failure_modes = @('publication_surface_divergence', 'stale_remote_request_identity', 'canonical_request_mismatch')
                canonical_request = [ordered]@{
                    local_listener_mirror = [ordered]@{
                        task_id = 'task-local'
                        objective_id = 'OBJ-BRIDGE'
                        sha256 = 'local-hash'
                    }
                    remote_surface = [ordered]@{
                        task_id = 'task-remote'
                        objective_id = 'OBJ-BRIDGE'
                        sha256 = 'remote-hash'
                    }
                    canonical_request_mismatch = $true
                    publication_surface_divergence = $true
                    stale_remote_request_identity = $true
                }
                remote_boundary = [ordered]@{
                    available = $true
                    communication_authority = [ordered]@{
                        host = '192.168.1.120'
                        path = '/home/testpilot/mim/runtime/shared'
                    }
                }
            }
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, ($watchdog | ConvertTo-Json -Depth 12), (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input: $inputRel
Output artifact: $outputRel
Audit Subject: TOD recovery watchdog error state.
Use the read-only audit artifact lane.
No code changes.
"@
        $promptPath = New-TestPromptFile -Content $promptText
        $context = [pscustomobject]@{
            task_id = 'TSK-READ-ONLY-WATCHDOG-AUDIT'
            objective_id = 'OBJ-READ-ONLY-AUDIT'
            title = 'Watchdog bridge smoke read-only audit artifact'
            scope = $promptText
            prompt_path = $promptPath
            task_category = 'report_only'
            allowed_files = @()
            validation_commands = @()
            metadata = @{ task_category = 'report_only' }
        }

        $result = Invoke-LocalExecutionEngine -Context $context
        $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

        [string]$result.status | Should Be 'completed'
        [string]$artifact.classification | Should Be 'watchdog_bridge_smoke_review_required'
        @($artifact.evidence_used[0].fields) -contains 'bridge_smoke.failure_modes' | Should Be $true
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'bridge_smoke_failure_modes' -and [string]$_.evidence -match 'publication_surface_divergence' }).Count | Should Be 1
        @($artifact.findings | Where-Object { [string]$_.finding -eq 'canonical_request_identity' -and [string]$_.evidence -match 'task-local' -and [string]$_.evidence -match 'task-remote' }).Count | Should Be 1
        @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'publication_surface_divergence' }).Count | Should Be 1
        @($artifact.blockers | Where-Object { [string]$_.reason_code -eq 'canonical_request_mismatch' }).Count | Should Be 1
        [bool]$artifact.no_code_changes | Should Be $true

        Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
    }

    It 'classifies saved route patch evidence without modifying product source' {
        $inputRel = ('runtime_remote_training/cleanup_holds/route-authority-{0}.patch' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_PATCH_EVIDENCE_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        $patch = @'
diff --git a/tmp_remote_mim/core/routers/studio.py b/tmp_remote_mim/core/routers/studio.py
@@
+def _studio_cognitive_authority_reply(message):
+    return "My first working hypothesis about this request is that the first visible explanation may not be the deepest capability gap."
+    return "Recommended action: Select and execute the next bounded action."
+    return "Dave needed: no."
diff --git a/tmp_remote_mim/core/routers/tod_ui.py b/tmp_remote_mim/core/routers/tod_ui.py
@@
+if "Codex disappeared" in message:
+    return "TOD is blocked."
'@
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, $patch, (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input Patch: $inputRel
Output artifact: $outputRel
Audit Subject: TOD route experiment authority classification.
Classify patch evidence for route-level hardcoded response authority, process support, and learned-capability candidates.
Use the read-only assessment patch evidence artifact lane.
No source code changes.
"@
        $promptPath = New-TestPromptFile -Content $promptText
        $context = [pscustomobject]@{
            task_id = 'TSK-ROUTE-PATCH-EVIDENCE-TEST'
            objective_id = 'TOD-ROUTE-EXPERIMENT-AUTHORITY-CLASSIFICATION-V1'
            title = 'Route patch evidence authority classification'
            scope = $promptText
            prompt_path = $promptPath
            task_category = 'read_only_assessment'
            allowed_files = @()
            validation_commands = @()
            metadata = @{ task_category = 'read_only_assessment' }
        }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_patch_evidence_authority_classification'
            [string]$artifact.task_mode | Should Be 'read_only_assessment'
            [bool]$artifact.no_code_changes | Should Be $true
            [bool]$artifact.no_source_code_modified_by_assessment | Should Be $true
            @($artifact.inspected_files) -contains $inputRel | Should Be $true
            [int]$artifact.patch_summary.route_file_count | Should BeGreaterThan 0
            @($artifact.signals | Where-Object { [string]$_.signal -eq 'visible_reply_authority' }).Count | Should BeGreaterThan 0
            @($artifact.signals | Where-Object { [string]$_.signal -eq 'operator_contract_injection' }).Count | Should BeGreaterThan 0
            @($artifact.signals | Where-Object { [string]$_.signal -eq 'tod_phrase_patch' }).Count | Should BeGreaterThan 0
            @($result.files_changed) -contains $outputRel | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'classifies patch evidence when the chat wrapper leaves task_category as chat_execution' {
        $inputRel = ('runtime_remote_training/cleanup_holds/route-authority-chat-wrapper-{0}.patch' -f [guid]::NewGuid().ToString('N'))
        $outputRel = ('runtime_remote_training/read_only_audit_artifacts/TOD_ROUTE_PATCH_CHAT_WRAPPER_TEST_{0}.json' -f [guid]::NewGuid().ToString('N'))
        $inputPath = Join-Path $repoRoot ($inputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $outputPath = Join-Path $repoRoot ($outputRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        $patch = @'
diff --git a/tmp_remote_mim/core/routers/studio.py b/tmp_remote_mim/core/routers/studio.py
@@
+def _studio_cognitive_authority_reply(message):
+    return "I do not have a specialized handler for this Studio MIM request yet, so I need to provide a useful reply."
'@
        New-Item -ItemType Directory -Path (Split-Path -Parent $inputPath) -Force | Out-Null
        [System.IO.File]::WriteAllText($inputPath, $patch, (New-Object System.Text.UTF8Encoding($false)))

        $promptText = @"
Input Patch: $inputRel
Output artifact: $outputRel
Classify patch evidence for route-level hardcoded response authority. Read-only assessment. No source code changes.
"@
        $promptPath = New-TestPromptFile -Content $promptText
        $context = [pscustomobject]@{
            task_id = 'TSK-ROUTE-PATCH-EVIDENCE-CHAT-WRAPPER-TEST'
            objective_id = 'TOD-ROUTE-EXPERIMENT-AUTHORITY-CLASSIFICATION-V1'
            title = 'Route patch evidence wrapped as chat execution'
            scope = $promptText
            prompt_path = $promptPath
            task_category = 'chat_execution'
            allowed_files = @()
            validation_commands = @()
            metadata = @{ task_category = 'chat_execution'; task_type = 'read_only_assessment' }
        }

        try {
            $result = Invoke-LocalExecutionEngine -Context $context
            $artifact = Get-Content -Path $outputPath -Raw | ConvertFrom-Json

            [string]$result.status | Should Be 'completed'
            [string]$artifact.artifact_type | Should Be 'tod_patch_evidence_authority_classification'
            @($artifact.signals | Where-Object { [string]$_.signal -eq 'visible_reply_authority' }).Count | Should BeGreaterThan 0
            [bool]$artifact.no_code_changes | Should Be $true
            @($result.files_changed) -contains $outputRel | Should Be $true
        }
        finally {
            Remove-Item -Path (Split-Path -Parent $promptPath) -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $inputPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $outputPath -Force -ErrorAction SilentlyContinue
        }
    }
}
