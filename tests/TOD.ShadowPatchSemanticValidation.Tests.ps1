Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$engineScript = Join-Path $repoRoot 'scripts/engines/LocalExecutionEngine.ps1'

Describe 'TOD shadow patch semantic validation' {
    BeforeAll {
        . $engineScript
    }

    It 'accepts an asserted literal candidate only in the temporary workspace' {
        $fixtureRel = 'tod/out/tests/semantic-gate-literal-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "Write-Output 'before'`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        $validation = 'powershell -NoProfile -Command ''$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "{0}"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}}''' -f $fixtureRel

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "Write-Output 'before'" `
                -NewText "Write-Output 'after'" `
                -ValidationCommand $validation `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'text_invariants'
                    required_contains = @("Write-Output 'after'")
                    forbidden_contains = @("Write-Output 'before'")
                })

            [string]$semantic.semantic_verdict | Should Be 'reject'
            [bool]$semantic.behavior_test_passed | Should Be $false
            (@($semantic.reason_codes) -contains 'text_invariants_not_executable_behavior_evidence') | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'adapts an LF candidate to a CRLF source without mutating production' {
        $fixtureRel = 'tod/out/tests/semantic-gate-crlf-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "function Test-One {`r`n    Write-Output 'before'`r`n}`r`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        $validation = 'powershell -NoProfile -Command ''$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "{0}"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}}''' -f $fixtureRel

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "function Test-One {`n    Write-Output 'before'`n}" `
                -NewText "function Test-One {`n    Write-Output 'after'`n}" `
                -ValidationCommand $validation `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'text_invariants'
                    required_contains = @("Write-Output 'after'")
                    forbidden_contains = @("Write-Output 'before'")
                })

            [string]$semantic.semantic_verdict | Should Be 'reject'
            [int]$semantic.anchor_match_count | Should Be 1
            [string]$semantic.resulting_diff.old_text | Should Match "`r`n"
            [string]$semantic.resulting_diff.new_text | Should Match "`r`n"
            [bool]$semantic.behavior_test_passed | Should Be $false
            (@($semantic.reason_codes) -contains 'text_invariants_not_executable_behavior_evidence') | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a focused Pester command as behavioral evidence' {
        $fixtureRel = 'tod/out/tests/semantic-gate-focused-' + [guid]::NewGuid().ToString('N') + '.Tests.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "function Get-SemanticGateValue {`r`n    'before'`r`n}`r`n`r`nDescribe 'semantic gate fixture' {`r`n    It 'returns before' {`r`n        Get-SemanticGateValue | Should Be 'before'`r`n    }`r`n}`r`n"
        $replacement = "function Get-SemanticGateValue {`n    'after'`n}`n`nDescribe 'semantic gate fixture' {`n    It 'returns after' {`n        Get-SemanticGateValue | Should Be 'after'`n    }`n}"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        $validation = 'Invoke-Pester -Script "{0}"' -f $fixtureRel

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText ($original -replace "`r`n", "`n") `
                -NewText $replacement `
                -ValidationCommand $validation

            if (-not [string]::Equals([string]$semantic.semantic_verdict, 'accept', [System.StringComparison]::Ordinal)) {
                throw ($semantic | ConvertTo-Json -Depth 12)
            }
            [string]$semantic.semantic_verdict | Should Be 'accept'
            [string]$semantic.behavior_test | Should Be 'focused_validation_command'
            [bool]$semantic.behavior_test_passed | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'stages and runs a separate focused Pester test against the temporary source tree' {
        $fixtureRootRel = 'tod/out/tests/semantic-gate-pester-' + [guid]::NewGuid().ToString('N')
        $fixtureRootAbs = Join-Path $repoRoot ($fixtureRootRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $fixtureRel = $fixtureRootRel + '/source.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $testRel = $fixtureRootRel + '/tests/source.Tests.ps1'
        $testAbs = Join-Path $repoRoot ($testRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "function Get-SemanticGateValue {`n    'before'`n}`n"
        $testBody = "`$source = Join-Path (Split-Path -Parent `$PSScriptRoot) 'source.ps1'`n. `$source`nDescribe 'separate semantic gate fixture' {`n    It 'uses the temporary patched source' {`n        Get-SemanticGateValue | Should Be 'after'`n    }`n}`n"
        New-Item -ItemType Directory -Path (Split-Path -Parent $testAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($testAbs, $testBody, [System.Text.UTF8Encoding]::new($false))
        $testHashBefore = [string](Get-FileHash -LiteralPath $testAbs -Algorithm SHA256).Hash

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "'before'" `
                -NewText "'after'" `
                -ValidationCommand ('Invoke-Pester -Path "{0}"' -f $testRel)

            if (-not [string]::Equals([string]$semantic.semantic_verdict, 'accept', [System.StringComparison]::Ordinal)) {
                throw ($semantic | ConvertTo-Json -Depth 12)
            }
            [string]$semantic.semantic_verdict | Should Be 'accept'
            [bool]$semantic.behavior_test_passed | Should Be $true
            @($semantic.support_files_staged) | Should Be @($testRel)
            [bool]$semantic.support_files_unchanged | Should Be $true
            @($semantic.changed_files) | Should Be @($fixtureRel)
            @($semantic.unexpected_files).Count | Should Be 0
            [bool]$semantic.production_source_unchanged | Should Be $true
            [string](Get-FileHash -LiteralPath $testAbs -Algorithm SHA256).Hash | Should Be $testHashBefore
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureRootAbs -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects an unsafe separate Pester path before execution' {
        $fixtureRel = 'tod/out/tests/semantic-gate-pester-unsafe-' + [guid]::NewGuid().ToString('N') + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "Write-Output 'before'`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "Write-Output 'before'" `
                -NewText "Write-Output 'after'" `
                -ValidationCommand 'Invoke-Pester -Path "../outside.Tests.ps1"'

            [string]$semantic.semantic_verdict | Should Be 'reject'
            (@($semantic.reason_codes) -contains 'focused_behavior_test_path_unsafe') | Should Be $true
            [bool]$semantic.mutation_authority_allowed | Should Be $false
            [bool]$semantic.production_source_unchanged | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'stages and runs an explicit non-adjacent focused pytest path' {
        $fixtureRootRel = 'tod/out/tests/semantic-gate-python-' + [guid]::NewGuid().ToString('N')
        $fixtureRootAbs = Join-Path $repoRoot ($fixtureRootRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $fixtureRel = $fixtureRootRel + '/module.py'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $testRel = $fixtureRootRel + '/tests/test_module.py'
        $testAbs = Join-Path $repoRoot ($testRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "def value():`n    return 'before'`n"
        $replacement = "def value():`n    return 'after'`n"
        $testBody = "import sys`nfrom pathlib import Path`nsys.path.insert(0, str(Path(__file__).resolve().parents[1]))`nfrom module import value`n`ndef test_value():`n    assert value() == 'after'`n"
        New-Item -ItemType Directory -Path (Split-Path -Parent $testAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($testAbs, $testBody, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "return 'before'" `
                -NewText "return 'after'" `
                -ValidationCommand ('python -m pytest -q "{0}"' -f $testRel)

            if (-not [string]::Equals([string]$semantic.semantic_verdict, 'accept', [System.StringComparison]::Ordinal)) {
                throw ($semantic | ConvertTo-Json -Depth 12)
            }
            [string]$semantic.semantic_verdict | Should Be 'accept'
            [bool]$semantic.behavior_test_passed | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureRootAbs -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'runs a focused pytest candidate when the changed file is the test target' {
        $fixtureRel = 'tod/out/tests/test_semantic-gate-self-' + [guid]::NewGuid().ToString('N') + '.py'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "def value():`n    return 'before'`n`ndef test_value():`n    assert value() == 'after'`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "return 'before'" `
                -NewText "return 'after'" `
                -ValidationCommand ('python -m pytest -q "{0}"' -f $fixtureRel)

            if (-not [string]::Equals([string]$semantic.semantic_verdict, 'accept', [System.StringComparison]::Ordinal)) {
                throw ($semantic | ConvertTo-Json -Depth 12)
            }
            [string]$semantic.semantic_verdict | Should Be 'accept'
            [bool]$semantic.behavior_test_passed | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepts a trusted expected-red pytest result only for a test-file mutation' {
        $fixtureRel = 'tod/out/tests/test_expected-red-' + [guid]::NewGuid().ToString('N') + '.py'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "def test_expected_red():`n    assert True`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText 'assert True' `
                -NewText "assert False, 'expected red marker'" `
                -ValidationCommand ('python -m pytest -q "{0}"' -f $fixtureRel) `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'expected_red_pytest'
                    expected_exit_code = 1
                    required_stdout_contains = @('failed', 'AssertionError')
                    forbidden_output_contains = @('SyntaxError', 'ImportError', 'ModuleNotFoundError')
                    mutation_scope = 'test_only'
                })

            if (-not [string]::Equals([string]$semantic.semantic_verdict, 'accept', [System.StringComparison]::Ordinal)) {
                throw ($semantic | ConvertTo-Json -Depth 12)
            }
            [string]$semantic.semantic_verdict | Should Be 'accept'
            [bool]$semantic.behavior_test_results[0].normal_success | Should Be $false
            [bool]$semantic.behavior_test_results[0].expected_red | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
            [bool]$semantic.cleanup_passed | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects the same failing pytest result without trusted expected-red authority' {
        $fixtureRel = 'tod/out/tests/test_untrusted-red-' + [guid]::NewGuid().ToString('N') + '.py'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "def test_untrusted_red():`n    assert True`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText 'assert True' `
                -NewText "assert False, 'untrusted red marker'" `
                -ValidationCommand ('python -m pytest -q "{0}"' -f $fixtureRel)

            [string]$semantic.semantic_verdict | Should Be 'reject'
            [bool]$semantic.behavior_test_passed | Should Be $false
            [bool]$semantic.mutation_authority_allowed | Should Be $false
            [bool]$semantic.production_source_unchanged | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects expected-red authority when forbidden infrastructure output is observed' {
        $fixtureRel = 'tod/out/tests/test_forbidden-red-' + [guid]::NewGuid().ToString('N') + '.py'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "def test_forbidden_red():`n    assert True`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText 'assert True' `
                -NewText "assert False, 'expected red marker'" `
                -ValidationCommand ('python -m pytest -q "{0}"' -f $fixtureRel) `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'expected_red_pytest'
                    expected_exit_code = 1
                    required_stdout_contains = @('failed')
                    forbidden_output_contains = @('AssertionError')
                    mutation_scope = 'test_only'
                })

            [string]$semantic.semantic_verdict | Should Be 'reject'
            [bool]$semantic.behavior_test_passed | Should Be $false
            (@($semantic.reason_codes) -contains 'focused_behavior_test_failed') | Should Be $true
            [bool]$semantic.production_source_unchanged | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects inert text-only behavior evidence' {
        $fixtureId = [guid]::NewGuid().ToString('N')
        $fixtureRel = 'tod/out/tests/semantic_gate_inert_' + $fixtureId + '.ps1'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "Write-Output 'before'`n"
        $replacement = "if ($false) { Write-Output 'after' }`n"
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        try {
            $validation = 'powershell -NoProfile -Command ''$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "{0}"),[ref]$tokens,[ref]$errors)>$null;if($errors.Count){{throw ($errors | Out-String)}}''' -f $fixtureRel
            $semantic = Invoke-TODShadowPatchSemanticValidation -TargetFile $fixtureRel -OldText $original -NewText $replacement -ValidationCommand $validation -BehaviorAssertion ([pscustomobject]@{ type='text_invariants'; required_contains=@("Write-Output 'after'"); forbidden_contains=@("Write-Output 'before'") })
            [string]$semantic.semantic_verdict | Should Be 'reject'
            [bool]$semantic.behavior_test_passed | Should Be $false
            [bool]$semantic.mutation_authority_allowed | Should Be $false
            [bool]$semantic.production_source_unchanged | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
        }
    }
    It 'does not grant expected-red authority to an implementation source patch' {
        $fixtureId = [guid]::NewGuid().ToString('N')
        $fixtureRel = 'tmp_remote_mim/core/semantic_gate_source_red_' + $fixtureId + '.py'
        $fixtureAbs = Join-Path $repoRoot ($fixtureRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $testRel = 'tmp_remote_mim/tests/test_semantic_gate_source_red_' + $fixtureId + '.py'
        $testAbs = Join-Path $repoRoot ($testRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $original = "def value():`n    return 'before'`n"
        $testBody = "from pathlib import Path`n`ndef test_value():`n    assert `"return 'before'`" in Path('$fixtureRel').read_text()`n"
        New-Item -ItemType Directory -Path (Split-Path -Parent $fixtureAbs) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $testAbs) -Force | Out-Null
        [System.IO.File]::WriteAllText($fixtureAbs, $original, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($testAbs, $testBody, [System.Text.UTF8Encoding]::new($false))

        try {
            $semantic = Invoke-TODShadowPatchSemanticValidation `
                -TargetFile $fixtureRel `
                -OldText "return 'before'" `
                -NewText "return 'after'" `
                -ValidationCommand ('python -m pytest -q "{0}"' -f $testRel) `
                -BehaviorAssertion ([pscustomobject]@{
                    type = 'expected_red_pytest'
                    expected_exit_code = 1
                    required_stdout_contains = @('failed', 'AssertionError')
                    forbidden_output_contains = @('SyntaxError', 'ImportError', 'ModuleNotFoundError')
                    mutation_scope = 'test_only'
                })

            [string]$semantic.semantic_verdict | Should Be 'reject'
            [bool]$semantic.behavior_test_passed | Should Be $false
            [bool]$semantic.mutation_authority_allowed | Should Be $false
            if (-not [bool]$semantic.production_source_unchanged) {
                throw ($semantic | ConvertTo-Json -Depth 12)
            }
            [bool]$semantic.production_source_unchanged | Should Be $true
            [System.IO.File]::ReadAllText($fixtureAbs) | Should Be $original
        }
        finally {
            Remove-Item -LiteralPath $fixtureAbs -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $testAbs -Force -ErrorAction SilentlyContinue
        }
    }
}
