param(
    [string]$PublicTodUrl = '',
    [string]$PublicTodStateUrl = '',
    [string]$PublicAppUrl = '',
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
    summary = (@($summaryParts.ToArray()) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' '
    blockers = @($blockers.ToArray() | Select-Object -Unique)
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
