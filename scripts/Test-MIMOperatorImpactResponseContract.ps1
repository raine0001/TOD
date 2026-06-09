param(
  [string]$OutputPath = "runtime/shared/MIM_OPERATOR_IMPACT_RESPONSE_CONTRACT_V1.latest.json"
)

$ErrorActionPreference = "Stop"

function Test-AnyPattern {
  param(
    [string]$Text,
    [string[]]$Patterns
  )
  foreach ($pattern in $Patterns) {
    if ($Text -match $pattern) {
      return $true
    }
  }
  return $false
}

function Measure-MIMOperatorReply {
  param(
    [hashtable]$Sample
  )
  $reply = [string]$Sample.reply
  $lower = $reply.ToLowerInvariant()

  $actionable = Test-AnyPattern $reply @(
    '(?i)\b(next action|recommended action|recommendation|i recommend|start|create|dispatch|run|verify|close|split|archive|escalate|publish|rerun|inspect|repair|resolve)\b'
  )
  $owner = Test-AnyPattern $reply @(
    '(?i)\b(owner|MIM owns|TOD owns|Codex owns|Dave owns|external dependency|assigned to|TOD should|MIM should|Codex should|Dave needed)\b'
  )
  $evidence = Test-AnyPattern $reply @(
    '(?i)\b(evidence|proof|artifact|result|validation|test output|screenshot|manifest|record|log|source|verifies|proves)\b'
  )
  $aging = Test-AnyPattern $reply @(
    '(?i)\b(aging|within \d+\s*(minute|minutes|hour|hours|day|days)|\d+h|\d+d|stale|watch|escalate after|follow[- ]?up|review by|if no .+ within)\b'
  )
  $dave = Test-AnyPattern $reply @(
    '(?i)\b(Dave needed\s*:\s*(yes|no)|Dave is needed|Dave is not needed|no Dave needed|ask Dave only|Dave needed)\b'
  )
  $statusOnly = -not $actionable -and (Test-AnyPattern $reply @(
    '(?i)\b(status|scoreboard|active|running|summary|currently|progress)\b'
  ))
  $continuity = Test-AnyPattern $reply @(
    '(?i)\b(continuity|prior project|project history|known good|previous fix|prior decision|reuse|already solved)\b'
  )
  $waste = Test-AnyPattern $reply @(
    '(?i)\b(prevent duplicate|duplicate work|scope split|split follow-on|avoid rework|reuse prior|prevented waste|scope expansion)\b'
  )

  $checks = [ordered]@{
    actionability = $actionable
    owner_assignment = $owner
    expected_evidence = $evidence
    time_aging_rule = $aging
    dave_needed_clarity = $dave
    unnecessary_status_response = $statusOnly
    continuity_lookup_usage = $continuity
    prevented_waste_signal = $waste
  }
  $requiredPassed = @($actionable, $owner, $evidence, $aging, $dave) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
  $score = [math]::Round(($requiredPassed / 5.0) * 10, 1)
  if ($statusOnly) {
    $score = [math]::Max(0, $score - 2)
  }

  return [ordered]@{
    id = $Sample.id
    prompt = $Sample.prompt
    expected_mode = $Sample.expected_mode
    reply = $reply
    checks = $checks
    required_fields_passed = $requiredPassed
    required_fields_total = 5
    score_10 = $score
    pass = ($requiredPassed -eq 5 -and -not $statusOnly)
  }
}

$samples = @(
  @{
    id = "operator-impact-001"
    prompt = "The training page says needs attention. What should happen now?"
    expected_mode = "recommendation"
    reply = "Recommended action: MIM opens a training-resolution objective and TOD refreshes or retires the stale evidence. Owner: MIM + TOD. Expected evidence: updated attention-resolution artifact, fresh reflection, and a reduced stale count. Aging rule: if no fresh evidence appears within 24h, mark watch; 48h escalates to Codex. Dave needed: no."
  },
  @{
    id = "operator-impact-002"
    prompt = "Why is this project blocked?"
    expected_mode = "problem_analysis"
    reply = "Recommended action: TOD should inspect the blocker source, publish the exact blocked dependency, and choose repair, split, or escalation. Owner: TOD, with MIM tracking the project state. Expected evidence: blocker note with inspected file/source and a successor state on the project board. Aging rule: blocked over 24h becomes watch; 72h escalates. Dave needed: no unless the dependency is credentials, approval, or external account access."
  },
  @{
    id = "operator-impact-003"
    prompt = "Can we close the servo tester?"
    expected_mode = "recommendation"
    reply = "Recommended action: close LAB Workbench Servo Tester as accepted and create a follow-on only for optional servo-profile refinements. Owner: MIM updates the project; TOD keeps firmware/profile evidence attached. Expected evidence: project terminal state, acceptance note, and linked working-servo validation. Aging rule: complete within the current project review cycle; reopen only if a regression appears. Dave needed: no because Dave already confirmed the objective works."
  },
  @{
    id = "operator-impact-004"
    prompt = "What should we work on next?"
    expected_mode = "recommendation"
    reply = "Recommended action: finish the highest-impact active lane before starting new work: TOD App Build Independence V1. Owner: MIM selects the next app and TOD executes without Codex generator edits. Expected evidence: a new app package, gallery entry, deployment readiness pass, and independence score >= 7. Aging rule: if no artifact appears within 2h, MIM narrows the task or escalates a blocker. Dave needed: no."
  },
  @{
    id = "operator-impact-005"
    prompt = "Forum graphics still fail sometimes."
    expected_mode = "continuity"
    reply = "Recommended action: run a continuity lookup before changing generation logic. Owner: MIM loads prior forum-graphics decisions; TOD validates the existing QA path. Expected evidence: continuity brief listing previous attempts, known text-rendering failures, current image QA checks, and the next bounded fix. Aging rule: if the brief is not produced within 24h, the project becomes stale-watch. Dave needed: no."
  },
  @{
    id = "operator-impact-006"
    prompt = "The app build looks generic."
    expected_mode = "problem_analysis"
    reply = "Recommended action: split design-quality improvement from the app-completion claim and score TOD independence separately. Owner: MIM creates the design brief; TOD regenerates the app preview using current generators. Expected evidence: app-specific style preset, real preview thumbnail, hero/media strategy, and user rating before Codex touch. Aging rule: if TOD needs generator repair, record the intervention immediately. Dave needed: no."
  },
  @{
    id = "operator-impact-007"
    prompt = "Is Dave needed for the account manager project?"
    expected_mode = "consultative_discovery"
    reply = "Recommended action: MIM should present the exact permission decisions instead of saying Dave is needed. Owner: MIM prepares the approval choices; TOD waits only on sensitive commission-access policy. Expected evidence: permission matrix with allowed operational areas, denied payout/report access, and any pre-approved exceptions. Aging rule: if Dave does not answer within 72h, keep the project waiting-on-Dave with reminder. Dave needed: yes, only for confidential commission/report access approval."
  },
  @{
    id = "operator-impact-008"
    prompt = "Can this app deploy today?"
    expected_mode = "recommendation"
    reply = "Recommended action: run Deployment Readiness before promoting the app. Owner: MIM scores product risk; TOD defines required APIs, schema, tests, preview deploy, rollback, and publish gates. Expected evidence: deployment readiness artifact with APIs, legal/privacy items, permissions, costs, and highest-risk dependencies. Aging rule: readiness must be complete before production build; stale after 24h. Dave needed: no unless provider account or billing setup is required."
  },
  @{
    id = "operator-impact-009"
    prompt = "The table organization project keeps expanding."
    expected_mode = "problem_analysis"
    reply = "Recommended action: close the original table-sorting acceptance and split momentum/heat/aging into follow-on projects. Owner: MIM enforces scope; TOD finishes only the accepted table controls. Expected evidence: closed acceptance for sortable/filter/search controls and new follow-on project links for expanded ideas. Aging rule: scope expansion over 30% requires split before more implementation. Dave needed: no."
  },
  @{
    id = "operator-impact-010"
    prompt = "MIM gave me a status dump again."
    expected_mode = "repair"
    reply = "Recommended action: score that reply as an unnecessary status response and rewrite it with action, owner, evidence, aging, and Dave-needed fields. Owner: MIM applies the response contract; TOD records the score. Expected evidence: failed sample in the operator-impact contract artifact and corrected reply. Aging rule: more than two status-only failures in 24h escalates to response-mode repair. Dave needed: no."
  }
)

$results = @($samples | ForEach-Object { Measure-MIMOperatorReply $_ })
$passCount = @($results | Where-Object { $_.pass }).Count
$avgScore = if ($results.Count) { [math]::Round((($results | ForEach-Object { $_.score_10 } | Measure-Object -Average).Average), 1) } else { 0 }

$artifact = [ordered]@{
  artifact_type = "mim_operator_impact_response_contract_v1"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  objective_id = "MIM-OPERATOR-IMPACT-TO-8-V1"
  status = if ($passCount -ge 8) { "passed_initial_contract" } else { "needs_repair" }
  sample_size = $results.Count
  pass_count = $passCount
  pass_rate = if ($results.Count) { [math]::Round($passCount / $results.Count, 2) } else { 0 }
  average_score_10 = $avgScore
  pass_threshold = "8/10 samples pass all five required fields without status-only drift"
  required_fields = @("recommended_action", "owner", "expected_evidence", "time_or_aging_rule", "dave_needed_yes_no")
  samples = $results
  next_action = [ordered]@{
    recommended_action = "Bind this scorer to live MIM replies and compare expected evidence against successor/project movement records."
    owner = "MIM + TOD"
    expected_evidence = "Outcome-linked successor records and MIM_OPERATOR_IMPACT_SCORECARD.latest.json updated with measured values."
    aging_rule = "If no live scored replies appear within 24h, mark Operator Impact watch; 48h stale."
    dave_needed = "no"
  }
}

$out = Resolve-Path -LiteralPath "." | ForEach-Object { Join-Path $_ $OutputPath }
$parent = Split-Path -Parent $out
if ($parent) {
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
$artifact | ConvertTo-Json -Depth 20 | Set-Content -Path $out -Encoding UTF8
Write-Output "Wrote $OutputPath"
Write-Output "Pass $passCount/$($results.Count); average $avgScore/10"
