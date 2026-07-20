param(
    [string]$PublicTodUrl = '',
    [string]$PublicTodStateUrl = '',
    [string]$PublicAppUrl = '',
    [string]$PublicSiteUrl = '',
    [string]$StudioUrl = '',
    [string]$AgentMimUrl = '',
    [string]$LocalTodUrl = 'http://localhost:8844/tod',
    [string]$IntegrationStatusPath = 'shared_state/integration_status.json',
    [string]$SharedTruthPath = 'runtime/shared/TOD_MIM_SHARED_TRUTH.latest.json',
    [string]$OutputPath = 'shared_state/tod_public_route_health.latest.json',
    [int]$TimeoutSec = 20,
    [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return [System.IO.Path]::GetFullPath($PathValue)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $repoRoot $PathValue))
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }
}

function Write-Utf8NoBomJson {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)]$Payload,
        [int]$Depth = 20
    )

    $directory = Split-Path -Parent $PathValue
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-DirectoryIfMissing -PathValue $directory
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $json = ($Payload | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($PathValue, $json, $utf8NoBom)
}

function Read-JsonFileIfExists {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if (-not (Test-Path -Path $PathValue)) {
        return $null
    }

    try {
        return (Get-Content -Path $PathValue -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Read-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -Path $PathValue)) {
        return ''
    }

    foreach ($line in @(Get-Content -Path $PathValue -ErrorAction SilentlyContinue)) {
        if ($null -eq $line) {
            continue
        }

        $trimmed = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        $match = [regex]::Match($trimmed, ('^(?i:{0})=(.*)$' -f [regex]::Escape($Name)))
        if (-not $match.Success) {
            continue
        }

        $value = [string]$match.Groups[1].Value
        if ($value.Length -ge 2) {
            $first = $value.Substring(0, 1)
            $last = $value.Substring($value.Length - 1, 1)
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        return $value.Trim()
    }

    return ''
}

function Join-HttpUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $base = ([string]$BaseUrl).Trim()
    $relative = ([string]$RelativePath).Trim()
    if ([string]::IsNullOrWhiteSpace($base)) {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace($relative)) {
        return $base.TrimEnd('/')
    }

    return ('{0}/{1}' -f $base.TrimEnd('/'), $relative.TrimStart('/'))
}

function Resolve-PublicTodTargets {
    param(
        [AllowEmptyString()][string]$ExplicitPublicTodUrl,
        [AllowEmptyString()][string]$ExplicitPublicTodStateUrl,
        [AllowEmptyString()][string]$ExplicitPublicAppUrl,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $resolvedAppUrl = ([string]$ExplicitPublicAppUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedAppUrl)) {
        $resolvedAppUrl = [string]$env:PUBLIC_APP_URL
    }
    if ([string]::IsNullOrWhiteSpace($resolvedAppUrl)) {
        $resolvedAppUrl = Read-DotEnvValue -PathValue (Join-Path $RepoRoot '.env') -Name 'PUBLIC_APP_URL'
    }

    $resolvedTodUrl = ([string]$ExplicitPublicTodUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTodUrl) -and -not [string]::IsNullOrWhiteSpace($resolvedAppUrl)) {
        $resolvedTodUrl = Join-HttpUrl -BaseUrl $resolvedAppUrl -RelativePath '/tod'
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTodUrl)) {
        $resolvedTodUrl = 'http://mim.mimtod.com/tod'
    }

    $resolvedTodStateUrl = ([string]$ExplicitPublicTodStateUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($resolvedTodStateUrl) -and -not [string]::IsNullOrWhiteSpace($resolvedAppUrl)) {
        $resolvedTodStateUrl = Join-HttpUrl -BaseUrl $resolvedAppUrl -RelativePath '/tod/ui/state'
    }
    if ([string]::IsNullOrWhiteSpace($resolvedTodStateUrl)) {
        $resolvedTodStateUrl = 'http://mim.mimtod.com/tod/ui/state'
    }

    return [pscustomobject]@{
        public_app_url = $resolvedAppUrl
        public_tod_url = $resolvedTodUrl
        public_tod_state_url = $resolvedTodStateUrl
    }
}

function Resolve-ConfiguredBaseUrl {
    param(
        [AllowEmptyString()][string]$ExplicitUrl,
        [Parameter(Mandatory = $true)][string[]]$EnvNames,
        [Parameter(Mandatory = $true)][string]$DefaultUrl,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $resolved = ([string]$ExplicitUrl).Trim()
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        return $resolved.TrimEnd('/')
    }

    foreach ($name in $EnvNames) {
        $envItem = Get-Item -Path ('Env:{0}' -f $name) -ErrorAction SilentlyContinue
        $envValue = if ($null -ne $envItem) { [string]$envItem.Value } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            return $envValue.TrimEnd('/')
        }
    }

    foreach ($name in $EnvNames) {
        $fileValue = Read-DotEnvValue -PathValue (Join-Path $RepoRoot '.env') -Name $name
        if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
            return $fileValue.TrimEnd('/')
        }
    }

    return $DefaultUrl.TrimEnd('/')
}

function New-TechnicalOperationsRouteInventory {
    param(
        [AllowEmptyString()][string]$PublicSiteBaseUrl,
        [AllowEmptyString()][string]$StudioBaseUrl,
        [AllowEmptyString()][string]$AgentMimBaseUrl,
        [Parameter(Mandatory = $true)][string]$LocalTodUrlValue,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $publicBase = Resolve-ConfiguredBaseUrl -ExplicitUrl $PublicSiteBaseUrl -EnvNames @('MIMTOD_PUBLIC_URL', 'PUBLIC_SITE_URL') -DefaultUrl 'https://www.mimtod.com' -RepoRoot $RepoRoot
    $studioBase = Resolve-ConfiguredBaseUrl -ExplicitUrl $StudioBaseUrl -EnvNames @('MIM_STUDIO_URL', 'MIMTOD_STUDIO_URL') -DefaultUrl 'https://mim.mimtod.com' -RepoRoot $RepoRoot
    $agentBase = Resolve-ConfiguredBaseUrl -ExplicitUrl $AgentMimBaseUrl -EnvNames @('AGENTMIM_PUBLIC_URL') -DefaultUrl 'https://www.agentmim.com' -RepoRoot $RepoRoot

    return @(
        [pscustomobject]@{ host_key = 'public_www_mimtod'; route_label = 'home'; url = $publicBase; expected_marker = 'MIM'; owner = 'MIM public web'; recovery_boundary = 'MIM Box public web service' },
        [pscustomobject]@{ host_key = 'public_www_mimtod'; route_label = 'research_observatory'; url = Join-HttpUrl -BaseUrl $publicBase -RelativePath '/observatory'; expected_marker = 'Research Observatory'; owner = 'MIM public web'; recovery_boundary = 'MIM Box public web service' },
        [pscustomobject]@{ host_key = 'public_www_mimtod'; route_label = 'build'; url = Join-HttpUrl -BaseUrl $publicBase -RelativePath '/build'; expected_marker = 'build'; owner = 'MIM public web'; recovery_boundary = 'MIM Box public web service' },
        [pscustomobject]@{ host_key = 'public_www_mimtod'; route_label = 'community'; url = Join-HttpUrl -BaseUrl $publicBase -RelativePath '/community'; expected_marker = 'Community'; owner = 'MIM public web'; recovery_boundary = 'MIM Box public web service' },
        [pscustomobject]@{ host_key = 'public_www_mimtod'; route_label = 'community_questions'; url = Join-HttpUrl -BaseUrl $publicBase -RelativePath '/community/questions'; expected_marker = 'Questions'; owner = 'MIM public web'; recovery_boundary = 'MIM Box public web service' },
        [pscustomobject]@{ host_key = 'studio_mim_mimtod'; route_label = 'studio_home'; url = Join-HttpUrl -BaseUrl $studioBase -RelativePath '/studio'; expected_marker = 'Restricted Operator Access'; owner = 'MIM Studio'; recovery_boundary = 'MIM Box Studio router and auth service' },
        [pscustomobject]@{ host_key = 'studio_mim_mimtod'; route_label = 'studio_projects'; url = Join-HttpUrl -BaseUrl $studioBase -RelativePath '/studio/projects'; expected_marker = 'Restricted Operator Access'; owner = 'MIM Studio'; recovery_boundary = 'MIM Box Studio router and auth service' },
        [pscustomobject]@{ host_key = 'studio_mim_mimtod'; route_label = 'studio_training'; url = Join-HttpUrl -BaseUrl $studioBase -RelativePath '/studio/training'; expected_marker = 'Restricted Operator Access'; owner = 'MIM Studio'; recovery_boundary = 'MIM Box Studio router and auth service' },
        [pscustomobject]@{ host_key = 'studio_mim_mimtod'; route_label = 'studio_visitors'; url = Join-HttpUrl -BaseUrl $studioBase -RelativePath '/studio/visitors'; expected_marker = 'Restricted Operator Access'; owner = 'MIM Studio'; recovery_boundary = 'MIM Box Studio router and auth service' },
        [pscustomobject]@{ host_key = 'agentmim_public'; route_label = 'forum'; url = Join-HttpUrl -BaseUrl $agentBase -RelativePath '/forum'; expected_marker = 'MIM'; owner = 'AgentMIM web'; recovery_boundary = 'AgentMIM service owner'; media_probe = 'required'; minimum_media_count = 1 },
        [pscustomobject]@{ host_key = 'agentmim_public'; route_label = 'help'; url = Join-HttpUrl -BaseUrl $agentBase -RelativePath '/help'; expected_marker = 'Support'; owner = 'AgentMIM web'; recovery_boundary = 'AgentMIM help desk and support ticket service' },
        [pscustomobject]@{ host_key = 'local_tod'; route_label = 'local_tod_ui'; url = $LocalTodUrlValue; expected_marker = 'TOD Command Console'; owner = 'TOD workstation'; recovery_boundary = 'TOD local service' }
    )
}

function Invoke-TechnicalOperationsRouteProbe {
    param(
        [Parameter(Mandatory = $true)]$Route,
        [int]$TimeoutSeconds = 20
    )

    $probe = Invoke-HttpProbe -Url ([string]$Route.url) -TimeoutSeconds $TimeoutSeconds
    $content = if ($probe.PSObject.Properties['content']) { [string]$probe.content } else { '' }
    $marker = [string]$Route.expected_marker
    $markerFound = if ([string]::IsNullOrWhiteSpace($marker)) { $true } else { $content -match [regex]::Escape($marker) }
    $mediaAssessment = Get-RouteMediaAssessment -Route $Route -Html $content -TimeoutSeconds $TimeoutSeconds
    $mediaHealthy = if ($mediaAssessment -and $mediaAssessment.PSObject.Properties['healthy']) { [bool]$mediaAssessment.healthy } else { $true }
    $healthy = [bool]$probe.ok -and [int]$probe.http_status -ge 200 -and [int]$probe.http_status -lt 400 -and $markerFound -and $mediaHealthy

    return [pscustomobject]@{
        host_key = [string]$Route.host_key
        route_label = [string]$Route.route_label
        url = [string]$Route.url
        owner = [string]$Route.owner
        recovery_boundary = [string]$Route.recovery_boundary
        expected_marker = $marker
        marker_found = $markerFound
        media = $mediaAssessment
        healthy = $healthy
        probe = ConvertTo-ProbeSummary -Probe $probe
        blocker = if ($healthy) { '' } elseif (-not [bool]$probe.ok) { ('technical_route_unreachable:{0}' -f [string]$Route.route_label) } elseif (-not $markerFound) { ('technical_route_marker_missing:{0}' -f [string]$Route.route_label) } elseif (-not $mediaHealthy) { ('technical_route_media_unhealthy:{0}' -f [string]$Route.route_label) } else { ('technical_route_unhealthy:{0}' -f [string]$Route.route_label) }
    }
}

function Convert-ToStringList {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        $trimmed = ([string]$Value).Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return @()
        }

        return @($trimmed)
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @()
        foreach ($entry in $Value) {
            $items += Convert-ToStringList -Value $entry
        }

        return @($items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }

    return @(([string]$Value).Trim())
}

function Invoke-HttpProbe {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSeconds = 20
    )

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        return [pscustomobject]@{
            ok = $true
            url = $Url
            http_status = [int]$response.StatusCode
            content = [string]$response.Content
            error = ''
        }
    }
    catch {
        $statusCode = $null
        $content = ''
        if ($_.Exception.Response) {
            try {
                $statusCode = [int]$_.Exception.Response.StatusCode.value__
            }
            catch {
                $statusCode = $null
            }

            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                try {
                    $content = [string]$reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }
            }
            catch {
                $content = ''
            }
        }

        return [pscustomobject]@{
            ok = $false
            url = $Url
            http_status = $statusCode
            content = $content
            error = [string]$_.Exception.Message
        }
    }
}

function Resolve-RouteMediaUrl {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    $value = ([string]$Candidate).Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value.StartsWith('data:', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    if ($value -match '^https?://') {
        return $value
    }

    if ($value.StartsWith('//')) {
        $baseUri = [uri]$BaseUrl
        return ('{0}:{1}' -f $baseUri.Scheme, $value)
    }

    try {
        $base = [uri]$BaseUrl
        return ([uri]::new($base, $value)).AbsoluteUri
    }
    catch {
        return ''
    }
}

function Get-RouteImageCandidates {
    param(
        [AllowNull()][string]$Html,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [int]$MaxCandidates = 5
    )

    $items = New-Object System.Collections.Generic.List[string]
    $body = [string]$Html
    foreach ($match in [regex]::Matches($body, '<img\b[^>]*\bsrc\s*=\s*["'']([^"'']+)["'']', 'IgnoreCase')) {
        $resolved = Resolve-RouteMediaUrl -BaseUrl $BaseUrl -Candidate ([string]$match.Groups[1].Value)
        if (-not [string]::IsNullOrWhiteSpace($resolved) -and -not $items.Contains($resolved)) {
            $items.Add($resolved)
        }
        if ($items.Count -ge $MaxCandidates) {
            break
        }
    }

    return @($items.ToArray())
}

function Get-RouteMediaAssessment {
    param(
        [AllowNull()]$Route,
        [AllowNull()][string]$Html,
        [int]$TimeoutSeconds = 20
    )

    $mediaProbeMode = ''
    if ($Route -and $Route.PSObject.Properties['media_probe']) {
        $mediaProbeMode = [string]$Route.media_probe
    }
    $required = ($mediaProbeMode -eq 'required')
    if (-not $required) {
        return [pscustomobject]@{
            required = $false
            healthy = $true
            expected_count = 0
            candidates = @()
            checked = @()
            blocker = ''
        }
    }

    $minimumMediaCount = 1
    if ($Route.PSObject.Properties['minimum_media_count']) {
        try {
            $minimumMediaCount = [Math]::Max(1, [int]$Route.minimum_media_count)
        }
        catch {
            $minimumMediaCount = 1
        }
    }

    $candidates = @(Get-RouteImageCandidates -Html $Html -BaseUrl ([string]$Route.url) -MaxCandidates 5)
    if (@($candidates).Count -lt $minimumMediaCount) {
        return [pscustomobject]@{
            required = $true
            healthy = $false
            expected_count = $minimumMediaCount
            candidates = @($candidates)
            checked = @()
            blocker = 'media_candidates_missing'
        }
    }

    $checked = @()
    foreach ($candidate in @($candidates)) {
        $probe = Invoke-HttpProbe -Url ([string]$candidate) -TimeoutSeconds $TimeoutSeconds
        $checked += [pscustomobject]@{
            url = [string]$candidate
            ok = [bool]$probe.ok
            http_status = $probe.http_status
            error = if ($probe.PSObject.Properties['error']) { [string]$probe.error } else { '' }
        }
    }

    $okCount = @($checked | Where-Object { [bool]$_.ok -and [int]$_.http_status -ge 200 -and [int]$_.http_status -lt 400 }).Count
    $healthy = ($okCount -ge $minimumMediaCount)
    return [pscustomobject]@{
        required = $true
        healthy = $healthy
        expected_count = $minimumMediaCount
        candidates = @($candidates)
        checked = @($checked)
        blocker = if ($healthy) { '' } else { 'media_probe_failed' }
    }
}

function ConvertTo-ProbeSummary {
    param([AllowNull()]$Probe)

    if ($null -eq $Probe) {
        return $null
    }

    $content = ''
    if ($Probe.PSObject.Properties['content']) {
        $content = [string]$Probe.content
    }
    $sample = $content
    if ($sample.Length -gt 800) {
        $sample = $sample.Substring(0, 800)
    }

    return [pscustomobject]@{
        ok = if ($Probe.PSObject.Properties['ok']) { [bool]$Probe.ok } else { $false }
        url = if ($Probe.PSObject.Properties['url']) { [string]$Probe.url } else { '' }
        http_status = if ($Probe.PSObject.Properties['http_status']) { $Probe.http_status } else { $null }
        content_length = $content.Length
        content_sample = $sample
        error = if ($Probe.PSObject.Properties['error']) { [string]$Probe.error } else { '' }
    }
}

function Get-TodPublicSurfaceClassification {
    param([AllowNull()][string]$Html)

    $body = [string]$Html
    $hasTalkToTod = $body -match 'Talk To TOD'
    $hasConversationApi = $body -match 'todConversationCard|api/tod-conversation'
    $hasAuthorityConsole = $body -match 'TOD Authority And Bridge Console|TOD Console \| MIM Core'
    $hasStateEndpointMarker = $body -match '/tod/ui/state'
    $hasCloudflareBeacon = $body -match 'cloudflareinsights|beacon\.min\.js'

    $surfaceType = 'unknown'
    if ($hasTalkToTod -or $hasConversationApi) {
        $surfaceType = 'full_tod_ui'
    }
    elseif ($hasAuthorityConsole -or $hasStateEndpointMarker) {
        $surfaceType = 'authority_console'
    }

    $summary = switch ($surfaceType) {
        'full_tod_ui' { 'Public /tod is serving the full TOD UI surface.' }
        'authority_console' { 'Public /tod is serving the authority console surface instead of the full TOD UI.' }
        default { 'Public /tod returned content, but the surface could not be classified.' }
    }

    return [pscustomobject]@{
        surface_type = $surfaceType
        healthy = ($surfaceType -eq 'full_tod_ui')
        summary = $summary
        markers = [pscustomobject]@{
            has_talk_to_tod = $hasTalkToTod
            has_conversation_api = $hasConversationApi
            has_authority_console = $hasAuthorityConsole
            has_state_endpoint_marker = $hasStateEndpointMarker
            has_cloudflare_beacon = $hasCloudflareBeacon
        }
    }
}

function Get-PreferredCanonicalObjective {
    param([AllowNull()]$Document)

    if ($null -eq $Document) {
        return ''
    }

    if ($Document.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Document.objective_id)) {
        return [string]$Document.objective_id
    }

    if ($Document.PSObject.Properties['canonical_objective'] -and -not [string]::IsNullOrWhiteSpace([string]$Document.canonical_objective)) {
        return [string]$Document.canonical_objective
    }

    if ($Document.PSObject.Properties['objective_authority_reset'] -and $Document.objective_authority_reset) {
        $reset = $Document.objective_authority_reset
        $resetActive = $false
        if ($reset.PSObject.Properties['active']) {
            $resetActive = [bool]$reset.active
        }

        if ($resetActive -and $reset.PSObject.Properties['authoritative_current_objective'] -and -not [string]::IsNullOrWhiteSpace([string]$reset.authoritative_current_objective)) {
            return [string]$reset.authoritative_current_objective
        }
    }

    if ($Document.PSObject.Properties['objective_alignment'] -and $Document.objective_alignment -and $Document.objective_alignment.PSObject.Properties['tod_current_objective'] -and -not [string]::IsNullOrWhiteSpace([string]$Document.objective_alignment.tod_current_objective)) {
        return [string]$Document.objective_alignment.tod_current_objective
    }

    if ($Document.PSObject.Properties['live_task_request'] -and $Document.live_task_request) {
        if ($Document.live_task_request.PSObject.Properties['normalized_objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Document.live_task_request.normalized_objective_id)) {
            return [string]$Document.live_task_request.normalized_objective_id
        }
        if ($Document.live_task_request.PSObject.Properties['objective_id'] -and -not [string]::IsNullOrWhiteSpace([string]$Document.live_task_request.objective_id)) {
            return ([string]$Document.live_task_request.objective_id) -replace '^objective-', ''
        }
    }

    if ($Document.PSObject.Properties['quick_facts'] -and $Document.quick_facts -and $Document.quick_facts.PSObject.Properties['canonical_objective'] -and -not [string]::IsNullOrWhiteSpace([string]$Document.quick_facts.canonical_objective)) {
        return [string]$Document.quick_facts.canonical_objective
    }

    return ''
}

function Get-DateOrMinValue {
    param([AllowNull()]$Value)

    if ($null -eq $Value) {
        return [DateTime]::MinValue
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return [DateTime]::MinValue
    }

    try {
        return [DateTime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
    }
    catch {
        return [DateTime]::MinValue
    }
}

function Get-PublicRouteStateAssessment {
    param(
        [AllowNull()]$StateDocument,
        [AllowNull()]$LocalIntegrationStatus
    )

    if ($null -eq $StateDocument) {
        return [pscustomobject]@{
            available = $false
            healthy = $false
            expected_canonical_objective = Get-PreferredCanonicalObjective -Document $LocalIntegrationStatus
            public_quick_facts_canonical_objective = ''
            public_effective_canonical_objective = ''
            local_canonical_objective = Get-PreferredCanonicalObjective -Document $LocalIntegrationStatus
            blockers = @('public_tod_state_missing')
            summary = 'Public /tod state endpoint did not return a readable JSON payload.'
            source_paths = $null
            route_owner_hint = ''
            control_scope = 'unknown'
        }
    }

    $publicQuickFactsCanonical = ''
    if ($StateDocument.PSObject.Properties['quick_facts'] -and $StateDocument.quick_facts -and $StateDocument.quick_facts.PSObject.Properties['canonical_objective']) {
        $publicQuickFactsCanonical = [string]$StateDocument.quick_facts.canonical_objective
    }

    $publicEffectiveCanonical = Get-PreferredCanonicalObjective -Document $StateDocument
    $localCanonical = Get-PreferredCanonicalObjective -Document $LocalIntegrationStatus
    $publicGeneratedAt = Get-DateOrMinValue -Value $(if ($StateDocument.PSObject.Properties['generated_at']) { $StateDocument.generated_at } else { $null })
    $localGeneratedAt = Get-DateOrMinValue -Value $(if ($null -ne $LocalIntegrationStatus -and $LocalIntegrationStatus.PSObject.Properties['generated_at']) { $LocalIntegrationStatus.generated_at } else { $null })
    $publicInternallyConsistent = (-not [string]::IsNullOrWhiteSpace($publicQuickFactsCanonical)) -and (-not [string]::IsNullOrWhiteSpace($publicEffectiveCanonical)) -and [string]::Equals($publicQuickFactsCanonical, $publicEffectiveCanonical, [System.StringComparison]::OrdinalIgnoreCase)
    $preferPublicOverLocal = $publicInternallyConsistent -and (-not [string]::IsNullOrWhiteSpace($localCanonical)) -and ($publicGeneratedAt -gt $localGeneratedAt)

    $expectedCanonical = if ($preferPublicOverLocal) {
        $publicEffectiveCanonical
    }
    elseif (-not [string]::IsNullOrWhiteSpace($localCanonical)) {
        $localCanonical
    }
    else {
        $publicEffectiveCanonical
    }

    $blockers = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($publicQuickFactsCanonical)) {
        $blockers.Add('public_tod_state_quick_facts_missing')
    }
    elseif (-not [string]::IsNullOrWhiteSpace($publicEffectiveCanonical) -and -not [string]::Equals($publicQuickFactsCanonical, $publicEffectiveCanonical, [System.StringComparison]::OrdinalIgnoreCase)) {
        $blockers.Add(('public_tod_quick_facts_mismatch:{0}->{1}' -f $publicQuickFactsCanonical, $publicEffectiveCanonical))
    }

    if (-not [string]::IsNullOrWhiteSpace($expectedCanonical) -and -not [string]::IsNullOrWhiteSpace($publicEffectiveCanonical) -and -not [string]::Equals($expectedCanonical, $publicEffectiveCanonical, [System.StringComparison]::OrdinalIgnoreCase)) {
        $blockers.Add(('public_tod_state_canonical_mismatch:{0}->{1}' -f $publicEffectiveCanonical, $expectedCanonical))
    }

    $routeOwnerHint = ''
    $controlScope = 'unknown'
    if ($StateDocument.PSObject.Properties['source_paths'] -and $StateDocument.source_paths) {
        $integrationPath = if ($StateDocument.source_paths.PSObject.Properties['integration_status']) { [string]$StateDocument.source_paths.integration_status } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($integrationPath)) {
            $routeOwnerHint = ('authority_console_reads {0}' -f $integrationPath)
            if ($integrationPath -match '/home/testpilot/mim/runtime/shared/TOD_INTEGRATION_STATUS\.latest\.json') {
                $controlScope = 'external_route_html_not_in_workspace_but_state_publication_reachable'
            }
        }
    }

    $healthy = (@($blockers).Count -eq 0)
    $summary = if ($healthy) {
        'Public /tod state endpoint is internally consistent with the canonical objective.'
    }
    else {
        'Public /tod state endpoint is reachable, but it disagrees with the canonical objective or exposes stale quick facts.'
    }

    return [pscustomobject]@{
        available = $true
        healthy = $healthy
        expected_canonical_objective = $expectedCanonical
        public_quick_facts_canonical_objective = $publicQuickFactsCanonical
        public_effective_canonical_objective = $publicEffectiveCanonical
        local_canonical_objective = $localCanonical
        public_generated_at = if ($publicGeneratedAt -gt [DateTime]::MinValue) { $publicGeneratedAt.ToUniversalTime().ToString('o') } else { '' }
        local_generated_at = if ($localGeneratedAt -gt [DateTime]::MinValue) { $localGeneratedAt.ToUniversalTime().ToString('o') } else { '' }
        local_state_superseded_by_public = $preferPublicOverLocal
        blockers = @($blockers.ToArray())
        summary = $summary
        source_paths = if ($StateDocument.PSObject.Properties['source_paths']) { $StateDocument.source_paths } else { $null }
        route_owner_hint = $routeOwnerHint
        control_scope = $controlScope
    }
}

$resolvedIntegrationStatusPath = Resolve-RepoPath -PathValue $IntegrationStatusPath
$resolvedSharedTruthPath = Resolve-RepoPath -PathValue $SharedTruthPath
$resolvedOutputPath = Resolve-RepoPath -PathValue $OutputPath
$resolvedPublicTargets = Resolve-PublicTodTargets -ExplicitPublicTodUrl $PublicTodUrl -ExplicitPublicTodStateUrl $PublicTodStateUrl -ExplicitPublicAppUrl $PublicAppUrl -RepoRoot $repoRoot

$localIntegrationStatus = Read-JsonFileIfExists -PathValue $resolvedIntegrationStatusPath
$sharedTruth = Read-JsonFileIfExists -PathValue $resolvedSharedTruthPath
$canonicalAuthority = if ($null -ne $sharedTruth) { $sharedTruth } else { $localIntegrationStatus }

$publicHtmlProbe = Invoke-HttpProbe -Url $resolvedPublicTargets.public_tod_url -TimeoutSeconds $TimeoutSec
$publicStateProbe = Invoke-HttpProbe -Url $resolvedPublicTargets.public_tod_state_url -TimeoutSeconds $TimeoutSec
$localHtmlProbe = Invoke-HttpProbe -Url $LocalTodUrl -TimeoutSeconds $TimeoutSec
$technicalRouteInventory = @(New-TechnicalOperationsRouteInventory -PublicSiteBaseUrl $PublicSiteUrl -StudioBaseUrl $StudioUrl -AgentMimBaseUrl $AgentMimUrl -LocalTodUrlValue $LocalTodUrl -RepoRoot $repoRoot)
$technicalRouteResults = @($technicalRouteInventory | ForEach-Object { Invoke-TechnicalOperationsRouteProbe -Route $_ -TimeoutSeconds $TimeoutSec })
$technicalRouteBlockers = @($technicalRouteResults | Where-Object { -not [bool]$_.healthy -and -not [string]::IsNullOrWhiteSpace([string]$_.blocker) } | ForEach-Object { [string]$_.blocker } | Select-Object -Unique)

$publicSurface = if (-not [string]::IsNullOrWhiteSpace([string]$publicHtmlProbe.content)) {
    Get-TodPublicSurfaceClassification -Html ([string]$publicHtmlProbe.content)
}
else {
    [pscustomobject]@{
        surface_type = 'unreachable'
        healthy = $false
        summary = 'Public /tod did not return HTML content.'
        markers = [pscustomobject]@{
            has_talk_to_tod = $false
            has_conversation_api = $false
            has_authority_console = $false
            has_state_endpoint_marker = $false
            has_cloudflare_beacon = $false
        }
    }
}

$localSurface = if (-not [string]::IsNullOrWhiteSpace([string]$localHtmlProbe.content)) {
    Get-TodPublicSurfaceClassification -Html ([string]$localHtmlProbe.content)
}
else {
    $null
}

$publicStateDocument = $null
if (-not [string]::IsNullOrWhiteSpace([string]$publicStateProbe.content)) {
    try {
        $publicStateDocument = ([string]$publicStateProbe.content | ConvertFrom-Json)
    }
    catch {
        $publicStateDocument = $null
    }
}

$stateAssessment = Get-PublicRouteStateAssessment -StateDocument $publicStateDocument -LocalIntegrationStatus $canonicalAuthority

$blockers = New-Object System.Collections.Generic.List[string]
if (-not [bool]$publicHtmlProbe.ok) {
    $blockers.Add('public_tod_unreachable')
}
elseif (-not [bool]$publicSurface.healthy) {
    $blockers.Add(('public_tod_wrong_surface:{0}' -f [string]$publicSurface.surface_type))
}

foreach ($entry in @(Convert-ToStringList -Value $stateAssessment.blockers)) {
    $blockers.Add($entry)
}

$summaryParts = New-Object System.Collections.Generic.List[string]
$summaryParts.Add([string]$publicSurface.summary)
$summaryParts.Add([string]$stateAssessment.summary)
if ($stateAssessment.route_owner_hint) {
    $summaryParts.Add([string]$stateAssessment.route_owner_hint)
}

$payload = [pscustomobject]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    source = 'tod-public-route-health-v1'
    public_app_url = [string]$resolvedPublicTargets.public_app_url
    public_tod_url = [string]$resolvedPublicTargets.public_tod_url
    public_tod_state_url = [string]$resolvedPublicTargets.public_tod_state_url
    local_tod_url = $LocalTodUrl
    status = if (@($blockers).Count -eq 0) { 'healthy' } else { 'attention' }
    technical_operations_status = if (@($technicalRouteBlockers).Count -eq 0) { 'healthy' } else { 'attention' }
    summary = (@($summaryParts.ToArray()) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' '
    blockers = @($blockers.ToArray() | Select-Object -Unique)
    technical_operations_blockers = @($technicalRouteBlockers)
    technical_operations_routes = @($technicalRouteResults)
    public_surface = [pscustomobject]@{
        probe = ConvertTo-ProbeSummary -Probe $publicHtmlProbe
        classification = $publicSurface
    }
    local_surface = if ($null -ne $localSurface) {
        [pscustomobject]@{
            probe = ConvertTo-ProbeSummary -Probe $localHtmlProbe
            classification = $localSurface
        }
    }
    else {
        [pscustomobject]@{
            probe = ConvertTo-ProbeSummary -Probe $localHtmlProbe
            classification = $null
        }
    }
    public_state = [pscustomobject]@{
        probe = ConvertTo-ProbeSummary -Probe $publicStateProbe
        assessment = $stateAssessment
    }
    route_trace = [pscustomobject]@{
        state_publication_control = 'reachable_via_shared_state_sync'
        route_html_control = 'not_found_in_workspace'
        route_owner_hint = [string]$stateAssessment.route_owner_hint
        control_scope = [string]$stateAssessment.control_scope
    }
}

Write-Utf8NoBomJson -PathValue $resolvedOutputPath -Payload $payload -Depth 20

if ($EmitJson) {
    $payload | ConvertTo-Json -Depth 20
}
