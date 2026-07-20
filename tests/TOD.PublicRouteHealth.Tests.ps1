Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'scripts/Invoke-TODPublicRouteHealthCheck.ps1'

function Import-PublicRouteHealthFunction {
    param([Parameter(Mandatory = $true)][string]$Name)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "Failed to parse $scriptPath"
    }

    $fnAst = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
    }, $true)

    if ($null -eq $fnAst) {
        throw "Function '$Name' not found in $scriptPath"
    }

    $definition = $fnAst.Extent.Text -replace ("function\s+{0}\b" -f [regex]::Escape($Name)), ("function global:{0}" -f $Name)
    . ([scriptblock]::Create($definition))
}

Describe 'TOD public route health classification' {
    BeforeAll {
        Import-PublicRouteHealthFunction -Name 'Read-DotEnvValue'
        Import-PublicRouteHealthFunction -Name 'Join-HttpUrl'
        Import-PublicRouteHealthFunction -Name 'Resolve-PublicTodTargets'
        Import-PublicRouteHealthFunction -Name 'Resolve-ConfiguredBaseUrl'
        Import-PublicRouteHealthFunction -Name 'New-TechnicalOperationsRouteInventory'
        Import-PublicRouteHealthFunction -Name 'Resolve-RouteMediaUrl'
        Import-PublicRouteHealthFunction -Name 'Get-RouteImageCandidates'
        Import-PublicRouteHealthFunction -Name 'Get-RouteMediaAssessment'
        Import-PublicRouteHealthFunction -Name 'Get-DateOrMinValue'
        Import-PublicRouteHealthFunction -Name 'Get-TodPublicSurfaceClassification'
        Import-PublicRouteHealthFunction -Name 'Get-PreferredCanonicalObjective'
        Import-PublicRouteHealthFunction -Name 'Get-PublicRouteStateAssessment'
    }

    It 'resolves public TOD targets from the configured public app URL' {
        $targets = Resolve-PublicTodTargets -ExplicitPublicTodUrl '' -ExplicitPublicTodStateUrl '' -ExplicitPublicAppUrl 'https://www.agentmim.com' -RepoRoot $repoRoot

        [string]$targets.public_app_url | Should Be 'https://www.agentmim.com'
        [string]$targets.public_tod_url | Should Be 'https://www.agentmim.com/tod'
        [string]$targets.public_tod_state_url | Should Be 'https://www.agentmim.com/tod/ui/state'
    }

    It 'lets explicit public TOD targets override the configured app URL' {
        $targets = Resolve-PublicTodTargets -ExplicitPublicTodUrl 'https://status.example.com/tod' -ExplicitPublicTodStateUrl 'https://status.example.com/tod/ui/state' -ExplicitPublicAppUrl 'https://www.agentmim.com' -RepoRoot $repoRoot

        [string]$targets.public_tod_url | Should Be 'https://status.example.com/tod'
        [string]$targets.public_tod_state_url | Should Be 'https://status.example.com/tod/ui/state'
    }

    It 'classifies the full TOD UI surface from chat markers' {
        $classification = Get-TodPublicSurfaceClassification -Html '<div>Talk To TOD</div><section id="todConversationCard"></section>'

        [string]$classification.surface_type | Should Be 'full_tod_ui'
        [bool]$classification.healthy | Should Be $true
    }

    It 'classifies the authority console surface from console markers' {
        $classification = Get-TodPublicSurfaceClassification -Html '<title>TOD Console | MIM Core</title><div>TOD Authority And Bridge Console</div><footer>/tod/ui/state</footer>'

        [string]$classification.surface_type | Should Be 'authority_console'
        [bool]$classification.healthy | Should Be $false
    }

    It 'prefers authority reset truth and flags mismatched quick facts' {
        $publicState = [pscustomobject]@{
            quick_facts = [pscustomobject]@{ canonical_objective = '153' }
            objective_alignment = [pscustomobject]@{ tod_current_objective = '152' }
            objective_authority_reset = [pscustomobject]@{ active = $true; authoritative_current_objective = '152' }
            source_paths = [pscustomobject]@{ integration_status = '/home/testpilot/mim/runtime/shared/TOD_INTEGRATION_STATUS.latest.json' }
        }
        $localState = [pscustomobject]@{
            objective_alignment = [pscustomobject]@{ tod_current_objective = '152' }
            objective_authority_reset = [pscustomobject]@{ active = $true; authoritative_current_objective = '152' }
        }

        $assessment = Get-PublicRouteStateAssessment -StateDocument $publicState -LocalIntegrationStatus $localState

        [bool]$assessment.healthy | Should Be $false
        [string]$assessment.expected_canonical_objective | Should Be '152'
        [string]$assessment.public_effective_canonical_objective | Should Be '152'
        ((@($assessment.blockers) -contains 'public_tod_quick_facts_mismatch:153->152')) | Should Be $true
        [string]$assessment.control_scope | Should Be 'external_route_html_not_in_workspace_but_state_publication_reachable'
    }

    It 'accepts canonical objective from shared truth style payloads' {
        $sharedTruth = [pscustomobject]@{
            objective_id = '2913'
        }

        [string](Get-PreferredCanonicalObjective -Document $sharedTruth) | Should Be '2913'
    }

    It 'accepts consistent public route state when quick facts match canonical truth' {
        $publicState = [pscustomobject]@{
            quick_facts = [pscustomobject]@{ canonical_objective = '152' }
            objective_alignment = [pscustomobject]@{ tod_current_objective = '152' }
            objective_authority_reset = [pscustomobject]@{ active = $true; authoritative_current_objective = '152' }
        }

        $assessment = Get-PublicRouteStateAssessment -StateDocument $publicState -LocalIntegrationStatus $null

        [bool]$assessment.healthy | Should Be $true
        @($assessment.blockers).Count | Should Be 0
    }

    It 'prefers fresher internally consistent public state over older local integration truth' {
        $publicState = [pscustomobject]@{
            generated_at = '2026-04-26T11:59:57Z'
            quick_facts = [pscustomobject]@{ canonical_objective = '2495' }
            objective_alignment = [pscustomobject]@{ tod_current_objective = '2495' }
            source_paths = [pscustomobject]@{ integration_status = '/home/testpilot/mim/runtime/shared/TOD_INTEGRATION_STATUS.latest.json' }
        }
        $localState = [pscustomobject]@{
            generated_at = '2026-04-26T11:39:32Z'
            objective_alignment = [pscustomobject]@{ tod_current_objective = '2492' }
        }

        $assessment = Get-PublicRouteStateAssessment -StateDocument $publicState -LocalIntegrationStatus $localState

        [bool]$assessment.healthy | Should Be $true
        [bool]$assessment.local_state_superseded_by_public | Should Be $true
        [string]$assessment.expected_canonical_objective | Should Be '2495'
        @($assessment.blockers).Count | Should Be 0
    }

    It 'builds a Technical Operations route inventory for public, Studio, AgentMIM, and local TOD surfaces' {
        $routes = @(New-TechnicalOperationsRouteInventory -PublicSiteBaseUrl 'https://www.mimtod.com' -StudioBaseUrl 'https://mim.mimtod.com' -AgentMimBaseUrl 'https://www.agentmim.com' -LocalTodUrlValue 'http://localhost:8844/tod' -RepoRoot $repoRoot)

        @($routes).Count | Should BeGreaterThan 10
        ((@($routes.route_label) -contains 'research_observatory')) | Should Be $true
        ((@($routes.route_label) -contains 'build')) | Should Be $true
        ((@($routes.route_label) -contains 'studio_projects')) | Should Be $true
        ((@($routes.route_label) -contains 'studio_training')) | Should Be $true
        ((@($routes.route_label) -contains 'forum')) | Should Be $true
        ((@($routes.route_label) -contains 'help')) | Should Be $true
        ((@($routes.route_label) -contains 'local_tod_ui')) | Should Be $true
        $forumRoute = @($routes | Where-Object { [string]$_.route_label -eq 'forum' } | Select-Object -First 1)
        [string]$forumRoute[0].media_probe | Should Be 'required'
        [int]$forumRoute[0].minimum_media_count | Should Be 1
        $helpRoute = @($routes | Where-Object { [string]$_.route_label -eq 'help' } | Select-Object -First 1)
        [string]$helpRoute[0].recovery_boundary | Should Match 'support ticket'
    }

    It 'extracts forum image candidates from route HTML for media patrol' {
        $html = @'
<main>
  <img src="/forum/posts/12/image" alt="first">
  <img src="https://cdn.example.com/forum/13.jpg" alt="second">
  <img src="data:image/png;base64,AAAA" alt="ignored">
</main>
'@
        $candidates = @(Get-RouteImageCandidates -Html $html -BaseUrl 'https://www.agentmim.com/forum' -MaxCandidates 5)

        @($candidates).Count | Should Be 2
        [string]$candidates[0] | Should Be 'https://www.agentmim.com/forum/posts/12/image'
        [string]$candidates[1] | Should Be 'https://cdn.example.com/forum/13.jpg'
    }

    It 'classifies required forum media as unhealthy when no image candidates exist' {
        $route = [pscustomobject]@{
            route_label = 'forum'
            url = 'https://www.agentmim.com/forum'
            media_probe = 'required'
            minimum_media_count = 1
        }

        $assessment = Get-RouteMediaAssessment -Route $route -Html '<main>No images here.</main>' -TimeoutSeconds 1

        [bool]$assessment.required | Should Be $true
        [bool]$assessment.healthy | Should Be $false
        [string]$assessment.blocker | Should Be 'media_candidates_missing'
    }
}
