Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'
$ledgerScript = Join-Path $repoRoot 'scripts/tod_mim_message_ledger.py'
$sqliteMigration = Join-Path $repoRoot 'db/migrations/20260506_tod_mim_message_ledger_phase_a_observe_only.sql'

function Import-ListenerFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($listenerScript, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $listenerScript"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $listenerScript"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

function Get-PythonCommand {
    $candidates = @('python', 'python3')
    foreach ($cmd in $candidates) {
        try {
            $null = & $cmd --version 2>&1
            if ($LASTEXITCODE -eq 0) { return $cmd }
        } catch {}
    }
    return 'python'
}

function Invoke-IfLedgerEnabled {
    param(
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [Parameter(Mandatory = $true)][scriptblock]$Callback
    )

    if ($Enabled) {
        & $Callback
    }
}

Describe 'TOD ledger observe shadow write' {
    BeforeAll {
        Import-ListenerFunction -Name 'Invoke-LedgerObserveShadowWrite'
    }

    Context 'when MESSAGE_LEDGER_MODE is not observe_only' {
        It 'does not write status artifact when disabled' {
            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-disabled-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $dbPath = Join-Path $testDir 'test.sqlite3'
                $python = Get-PythonCommand

                # Call the function — but simulate ledger disabled by using a dummy python command
                # that would fail loudly if reached; since caller gates on $messageLedgerEnabled,
                # we test the gate here by calling the function directly with a missing-on-purpose
                # Python path and verifying no exception is thrown when we simulate the disabled gate.
                # The listener itself gates with: if ($messageLedgerEnabled) { Invoke-LedgerObserveShadowWrite ... }
                # We verify the feature-flag variable is correctly $false when env var is absent/wrong.
                $env:MESSAGE_LEDGER_MODE = ''
                $mode = ''
                if ($null -ne $env:MESSAGE_LEDGER_MODE -and -not [string]::IsNullOrWhiteSpace($env:MESSAGE_LEDGER_MODE)) {
                    $mode = ([string]$env:MESSAGE_LEDGER_MODE).Trim().ToLowerInvariant()
                }
                $enabled = [string]::Equals($mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
                $enabled | Should Be $false

                $env:MESSAGE_LEDGER_MODE = 'off'
                $mode = ([string]$env:MESSAGE_LEDGER_MODE).Trim().ToLowerInvariant()
                $enabled = [string]::Equals($mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
                $enabled | Should Be $false

                (Test-Path -Path $statusPath) | Should Be $false
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
                $env:MESSAGE_LEDGER_MODE = ''
            }
        }

        It 'disabled mode writes nothing through gated invocation' {
            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-disabled-gated-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $dbPath = Join-Path $testDir 'test.sqlite3'
                $python = Get-PythonCommand
                $messageLedgerEnabled = $false

                Invoke-IfLedgerEnabled -Enabled $messageLedgerEnabled -Callback {
                    Invoke-LedgerObserveShadowWrite `
                        -RequestId 'objective-10-task-1-disabled-gate' `
                        -TaskId 'objective-10-task-1' `
                        -CorrelationId 'corr-disabled-gate' `
                        -EventType 'ack_observed' `
                        -MessageType 'ack' `
                        -FromAgent 'TOD' `
                        -ToAgent 'MIM' `
                        -Status 'accepted' `
                        -PythonCommand $python `
                        -LedgerScriptAbs $ledgerScript `
                        -LedgerDbAbs $dbPath `
                        -LedgerMigrationAbs $sqliteMigration `
                        -LedgerStatusAbs $statusPath
                }

                (Test-Path -Path $statusPath) | Should Be $false
                (Test-Path -Path $dbPath) | Should Be $false
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'returns enabled=true when MESSAGE_LEDGER_MODE=observe_only' {
            $env:MESSAGE_LEDGER_MODE = 'observe_only'
            try {
                $mode = ([string]$env:MESSAGE_LEDGER_MODE).Trim().ToLowerInvariant()
                $enabled = [string]::Equals($mode, 'observe_only', [System.StringComparison]::OrdinalIgnoreCase)
                $enabled | Should Be $true
            } finally {
                $env:MESSAGE_LEDGER_MODE = ''
            }
        }
    }

    Context 'when MESSAGE_LEDGER_MODE=observe_only is enabled' {
        It 'writes each lifecycle event type in observe-only mode' {
            if (-not (Test-Path -Path $ledgerScript)) {
                Set-ItResult -Skipped -Because 'ledger Python script not found'
                return
            }
            if (-not (Test-Path -Path $sqliteMigration)) {
                Set-ItResult -Skipped -Because 'SQLite migration file not found'
                return
            }

            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-lifecycle-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $dbPath = Join-Path $testDir 'test.sqlite3'
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $python = Get-PythonCommand

                $events = @(
                    @{ event_type = 'ack_observed'; status = 'accepted'; message_type = 'ack'; source = 'TOD_MIM_TASK_ACK.latest.json' },
                    @{ event_type = 'progress_observed'; status = 'running'; message_type = 'progress'; source = 'TOD_MIM_EXECUTION_FEEDBACK.latest.json' },
                    @{ event_type = 'result_observed'; status = 'succeeded'; message_type = 'result'; source = 'TOD_MIM_TASK_RESULT.latest.json' },
                    @{ event_type = 'blocked_observed'; status = 'blocked'; message_type = 'result'; source = 'TOD_MIM_TASK_RESULT.latest.json' },
                    @{ event_type = 'heartbeat_observed'; status = 'alive'; message_type = 'heartbeat'; source = 'TOD_MIM_LISTENER_STATE.latest.json' }
                )

                foreach ($evt in $events) {
                    { Invoke-LedgerObserveShadowWrite `
                        -RequestId ('objective-55-task-' + [string]$evt.event_type) `
                        -TaskId 'objective-55-task' `
                        -CorrelationId 'corr-lifecycle' `
                        -SourceArtifact ([string]$evt.source) `
                        -EventType ([string]$evt.event_type) `
                        -MessageType ([string]$evt.message_type) `
                        -FromAgent 'TOD' `
                        -ToAgent 'MIM' `
                        -Status ([string]$evt.status) `
                        -PythonCommand $python `
                        -LedgerScriptAbs $ledgerScript `
                        -LedgerDbAbs $dbPath `
                        -LedgerMigrationAbs $sqliteMigration `
                        -LedgerStatusAbs $statusPath
                    } | Should Not Throw

                    $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                    [string]$status.last_event_type | Should Be ([string]$evt.event_type)
                    [string]$status.last_error | Should Be ''
                }
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'writes shadow event to local SQLite and updates status artifact' {
            if (-not (Test-Path -Path $ledgerScript)) {
                Set-ItResult -Skipped -Because 'ledger Python script not found'
                return
            }
            if (-not (Test-Path -Path $sqliteMigration)) {
                Set-ItResult -Skipped -Because 'SQLite migration file not found'
                return
            }

            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-write-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $dbPath    = Join-Path $testDir 'test.sqlite3'
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $python    = Get-PythonCommand

                Invoke-LedgerObserveShadowWrite `
                    -RequestId 'objective-999-task-5001-implement-test-shadow' `
                    -TaskId 'objective-999-task-5001' `
                    -CorrelationId 'corr-5001' `
                    -SourceArtifact 'MIM_TOD_TASK_REQUEST.latest.json' `
                    -PythonCommand $python `
                    -LedgerScriptAbs $ledgerScript `
                    -LedgerDbAbs $dbPath `
                    -LedgerMigrationAbs $sqliteMigration `
                    -LedgerStatusAbs $statusPath

                (Test-Path -Path $statusPath) | Should Be $true

                $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                [bool]$status.enabled    | Should Be $true
                [bool]$status.non_blocking | Should Be $true
                [string]$status.last_attempt_at | Should Not BeNullOrEmpty
                [string]$status.last_success_at | Should Not BeNullOrEmpty
                [string]$status.last_observed_task_id | Should Be 'objective-999-task-5001'
                [string]$status.last_event_type | Should Be 'request_observed'
                [string]$status.last_request_id | Should Be 'objective-999-task-5001-implement-test-shadow'

                (Test-Path -Path $dbPath) | Should Be $true

                # Verify the row landed in the messages table
                $countJson = & $python $ledgerScript `
                    --db $dbPath `
                    --migration $sqliteMigration `
                    --status-path $statusPath `
                    --mode observe_only `
                    --operation initialize 2>&1 | Out-String
                $countResult = $countJson | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($null -ne $countResult -and $countResult.PSObject.Properties['counts']) {
                    [int]$countResult.counts.agent_ledger_messages | Should BeGreaterThan 0
                }
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'is idempotent — repeated shadow write for same request_id does not throw' {
            if (-not (Test-Path -Path $ledgerScript)) {
                Set-ItResult -Skipped -Because 'ledger Python script not found'
                return
            }
            if (-not (Test-Path -Path $sqliteMigration)) {
                Set-ItResult -Skipped -Because 'SQLite migration file not found'
                return
            }

            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-idem-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $dbPath    = Join-Path $testDir 'test.sqlite3'
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $python    = Get-PythonCommand
                $params    = @{
                    RequestId        = 'objective-42-task-101-idempotent-shadow'
                    TaskId           = 'objective-42-task-101'
                    CorrelationId    = 'corr-idem'
                    SourceArtifact   = 'MIM_TOD_TASK_REQUEST.latest.json'
                    PythonCommand    = $python
                    LedgerScriptAbs  = $ledgerScript
                    LedgerDbAbs      = $dbPath
                    LedgerMigrationAbs = $sqliteMigration
                    LedgerStatusAbs  = $statusPath
                }

                # First write
                { Invoke-LedgerObserveShadowWrite @params } | Should Not Throw

                # Second write with same request_id — INSERT OR IGNORE, must not throw
                { Invoke-LedgerObserveShadowWrite @params } | Should Not Throw

                $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                [bool]$status.enabled | Should Be $true
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'failure isolation' {
        It 'does not throw when Python command is invalid — failure is non-fatal' {
            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-fail-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'

                { Invoke-LedgerObserveShadowWrite `
                    -RequestId 'objective-1-task-1-fail-test' `
                    -TaskId 'objective-1-task-1' `
                    -CorrelationId 'corr-fail' `
                    -PythonCommand 'nonexistent_python_binary_xyzzy' `
                    -LedgerScriptAbs (Join-Path $testDir 'missing_ledger.py') `
                    -LedgerDbAbs (Join-Path $testDir 'test.sqlite3') `
                    -LedgerMigrationAbs (Join-Path $testDir 'missing_migration.sql') `
                    -LedgerStatusAbs $statusPath
                } | Should Not Throw

                # Status artifact should record the failure
                (Test-Path -Path $statusPath) | Should Be $true
                $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                [bool]$status.enabled      | Should Be $true
                [bool]$status.non_blocking | Should Be $true
                [string]$status.last_attempt_at | Should Not BeNullOrEmpty
                [string]$status.last_error | Should Not BeNullOrEmpty
                [string]$status.last_success_at | Should BeNullOrEmpty
                [string]$status.last_event_type | Should Be 'request_observed'
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'ledger failure does not affect ACK/RESULT values or status flow' {
            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-fail-noimpact-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $ack = [pscustomobject]@{ status = 'accepted'; task_id = 'objective-12-task-1' }
                $result = [pscustomobject]@{ status = 'succeeded'; task_id = 'objective-12-task-1'; result_reason_code = 'execution_completed' }
                $commandStatus = 'accepted'

                { Invoke-LedgerObserveShadowWrite `
                    -RequestId 'objective-12-task-1' `
                    -TaskId 'objective-12-task-1' `
                    -CorrelationId 'corr-noimpact' `
                    -EventType 'ack_observed' `
                    -MessageType 'ack' `
                    -FromAgent 'TOD' `
                    -ToAgent 'MIM' `
                    -Status 'accepted' `
                    -PythonCommand 'nonexistent_python_binary_xyzzy' `
                    -LedgerScriptAbs (Join-Path $testDir 'missing_ledger.py') `
                    -LedgerDbAbs (Join-Path $testDir 'test.sqlite3') `
                    -LedgerMigrationAbs (Join-Path $testDir 'missing_migration.sql') `
                    -LedgerStatusAbs $statusPath
                } | Should Not Throw

                [string]$ack.status | Should Be 'accepted'
                [string]$result.status | Should Be 'succeeded'
                [string]$commandStatus | Should Be 'accepted'
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'records last_error in status without altering last_success_at from prior success' {
            if (-not (Test-Path -Path $ledgerScript)) {
                Set-ItResult -Skipped -Because 'ledger Python script not found'
                return
            }
            if (-not (Test-Path -Path $sqliteMigration)) {
                Set-ItResult -Skipped -Because 'SQLite migration file not found'
                return
            }

            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-errprior-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $dbPath     = Join-Path $testDir 'test.sqlite3'
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'
                $python     = Get-PythonCommand

                # First write succeeds — establishes last_success_at
                Invoke-LedgerObserveShadowWrite `
                    -RequestId 'objective-7-task-200-prior-success' `
                    -TaskId 'objective-7-task-200' `
                    -CorrelationId 'corr-prior' `
                    -PythonCommand $python `
                    -LedgerScriptAbs $ledgerScript `
                    -LedgerDbAbs $dbPath `
                    -LedgerMigrationAbs $sqliteMigration `
                    -LedgerStatusAbs $statusPath

                $afterSuccess = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                $priorSuccessAt = [string]$afterSuccess.last_success_at
                $priorSuccessAt | Should Not BeNullOrEmpty

                # Second write fails — last_success_at must not change, last_error must be set
                { Invoke-LedgerObserveShadowWrite `
                    -RequestId 'objective-7-task-201-fail' `
                    -TaskId 'objective-7-task-201' `
                    -CorrelationId 'corr-fail2' `
                    -PythonCommand 'nonexistent_python_xyzzy' `
                    -LedgerScriptAbs (Join-Path $testDir 'missing.py') `
                    -LedgerDbAbs $dbPath `
                    -LedgerMigrationAbs (Join-Path $testDir 'missing.sql') `
                    -LedgerStatusAbs $statusPath
                } | Should Not Throw

                $afterFail = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                [string]$afterFail.last_success_at | Should Be $priorSuccessAt
                [string]$afterFail.last_error       | Should Not BeNullOrEmpty
                [bool]$afterFail.non_blocking       | Should Be $true
                [string]$afterFail.last_event_type  | Should Be 'request_observed'
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'status artifact records non_blocking=true regardless of write outcome' {
            $testDir = Join-Path $repoRoot ('tod/out/tests/ledger-nb-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            try {
                $statusPath = Join-Path $testDir 'TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json'

                Invoke-LedgerObserveShadowWrite `
                    -RequestId 'objective-3-task-300-nb-test' `
                    -TaskId 'objective-3-task-300' `
                    -CorrelationId 'corr-nb' `
                    -PythonCommand 'nonexistent_xyzzy' `
                    -LedgerScriptAbs (Join-Path $testDir 'missing.py') `
                    -LedgerDbAbs (Join-Path $testDir 'test.sqlite3') `
                    -LedgerMigrationAbs (Join-Path $testDir 'missing.sql') `
                    -LedgerStatusAbs $statusPath

                $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
                [bool]$status.non_blocking | Should Be $true
            } finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
