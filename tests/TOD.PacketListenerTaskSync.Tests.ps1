Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$listenerScript = Join-Path $repoRoot 'scripts/Start-TODMimPacketListener.ps1'

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

function Write-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $dir = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, (($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"), $utf8NoBom)
}

Describe 'TOD packet listener task sync' {
    BeforeAll {
        Import-ListenerFunction -Name 'Get-ExpectedObjectiveFromRequest'
        Import-ListenerFunction -Name 'Get-UtcNowString'
        Import-ListenerFunction -Name 'Limit-ListenerStateText'
        Import-ListenerFunction -Name 'Test-StringArrayEquivalent'
        Import-ListenerFunction -Name 'Sync-LocalTaskFromRequest'
    }

    BeforeEach {
        function global:Get-LocalPath {
            param([string]$PathValue)

            switch ($PathValue) {
                'tod/data/state.json' { return $script:StatePath }
                default { return $PathValue }
            }
        }

        function global:Read-JsonFileIfExists {
            param([string]$PathValue)
            if (-not (Test-Path -Path $PathValue)) {
                return $null
            }

            return (Get-Content -Path $PathValue -Raw) | ConvertFrom-Json
        }
    }

    It 'preserves nested bounded-slice target hints when creating a synced task' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/listener-task-sync-' + [guid]::NewGuid().ToString('N'))
        $script:StatePath = Join-Path $fixture 'state.json'

        try {
            Write-JsonFile -PathValue $script:StatePath -Payload ([pscustomobject]@{
                objectives = @()
                tasks = @()
            })

            $request = [pscustomobject]@{
                task_id = 'objective-200-task-300'
                objective_id = 'objective-200'
                title = 'Patch MIM handoff gateway'
                scope = 'Inspect the gateway route and add a bounded behavior fix.'
                bounded_slice = [pscustomobject]@{
                    likely_target_files = @(
                        'core\routers\gateway.py',
                        'tests/integration/test_mim_tod_handoff_gateway.py'
                    )
                }
                metadata_json = [pscustomobject]@{
                    bounded_slice = [pscustomobject]@{
                        likely_target_files = @('unused-from-metadata.py')
                    }
                }
            }

            $result = Sync-LocalTaskFromRequest -Request $request
            $state = (Get-Content -Path $script:StatePath -Raw) | ConvertFrom-Json
            $task = @($state.tasks | Where-Object { [string]$_.id -eq 'objective-200-task-300' } | Select-Object -First 1)[0]

            [bool]$result.changed | Should Be $true
            [bool]$result.created | Should Be $true
            @($task.target_files).Count | Should Be 2
            @($task.target_files)[0] | Should Be 'core/routers/gateway.py'
            @($task.target_files)[1] | Should Be 'tests/integration/test_mim_tod_handoff_gateway.py'
            @($task.allowed_files)[0] | Should Be 'core/routers/gateway.py'
            @($task.files_involved)[1] | Should Be 'tests/integration/test_mim_tod_handoff_gateway.py'
            [string]$task.bounded_slice.likely_target_files[0] | Should Be 'core\routers\gateway.py'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }

    It 'adds target hints to an existing thin synced task' {
        $fixture = Join-Path $repoRoot ('tod/out/tests/listener-task-sync-' + [guid]::NewGuid().ToString('N'))
        $script:StatePath = Join-Path $fixture 'state.json'

        try {
            Write-JsonFile -PathValue $script:StatePath -Payload ([pscustomobject]@{
                objectives = @()
                tasks = @(
                    [pscustomobject]@{
                        id = 'objective-201-task-301'
                        objective_id = '201'
                        title = 'Thin task'
                        scope = 'Old shell task.'
                        status = 'planned'
                    }
                )
            })

            $request = [pscustomobject]@{
                task_id = 'objective-201-task-301'
                objective_id = '201'
                title = 'Thin task'
                scope = 'Old shell task.'
                metadata_json = [pscustomobject]@{
                    bounded_slice = [pscustomobject]@{
                        likely_target_files = @('scripts/TOD.ps1')
                    }
                }
            }

            $result = Sync-LocalTaskFromRequest -Request $request
            $state = (Get-Content -Path $script:StatePath -Raw) | ConvertFrom-Json
            $task = @($state.tasks | Where-Object { [string]$_.id -eq 'objective-201-task-301' } | Select-Object -First 1)[0]

            [bool]$result.changed | Should Be $true
            [bool]$result.created | Should Be $false
            @($task.target_files).Count | Should Be 1
            @($task.target_files)[0] | Should Be 'scripts/TOD.ps1'
            @($task.allowed_files)[0] | Should Be 'scripts/TOD.ps1'
            @($task.files_involved)[0] | Should Be 'scripts/TOD.ps1'
            [string]$task.bounded_slice.likely_target_files[0] | Should Be 'scripts/TOD.ps1'
        }
        finally {
            if (Test-Path -Path $fixture) {
                Remove-Item -Path $fixture -Recurse -Force
            }
        }
    }
}
