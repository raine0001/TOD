
    const runBtn = document.getElementById('runBtn');
    const refreshBtn = document.getElementById('refreshBtn');
    const loadLogsBtn = document.getElementById('loadLogsBtn');
    const objectiveSelectEl = document.getElementById('objectiveSelect');
    const statusEl = document.getElementById('status');
    const refreshShareBtn = document.getElementById('refreshShareBtn');
    const shareMetaEl = document.getElementById('shareMeta');
    const shareLinksEl = document.getElementById('shareLinks');
    const actionLiveStatusEl = document.getElementById('actionLiveStatus');
    const actionTimelineEl = document.getElementById('actionTimeline');
    const actionPendingEl = document.getElementById('actionPending');
    const uiBuildChipEl = document.getElementById('uiBuildChip');
    const uiSinceChipEl = document.getElementById('uiSinceChip');
    const uiPortChipEl = document.getElementById('uiPortChip');
    const cadenceHealthChipEl = document.getElementById('cadenceHealthChip');
    const steadyStateChipEl = document.getElementById('steadyStateChip');
    const regressionChipEl = document.getElementById('regressionChip');
    const requestChipEl = document.getElementById('requestChip');
    const voiceChipEl = document.getElementById('voiceChip');
    const voiceAdapterPanelEl = document.getElementById('voiceAdapterPanel');
    const uiHelpBtnEl = document.getElementById('uiHelpBtn');
    const uiSettingsBtnEl = document.getElementById('uiSettingsBtn');
    const uiSettingsPanelEl = document.getElementById('uiSettingsPanel');
    const settingsRefreshBtnEl = document.getElementById('settingsRefreshBtn');
    const settingsHelpBtnEl = document.getElementById('settingsHelpBtn');
    const settingsLogsToggleEl = document.getElementById('settingsLogsToggle');
    const settingsProjectToggleEl = document.getElementById('settingsProjectToggle');
    const settingsPresetFullEl = document.getElementById('settingsPresetFull');
    const settingsPresetMimEl = document.getElementById('settingsPresetMim');
    const settingsPresetOpsEl = document.getElementById('settingsPresetOps');
    const uiHelpModalEl = document.getElementById('uiHelpModal');
    const uiHelpCloseBtnEl = document.getElementById('uiHelpCloseBtn');
    const uiHelpMetaEl = document.getElementById('uiHelpMeta');
    const uiChangelogEl = document.getElementById('uiChangelog');
    const outputEl = document.getElementById('output');
    const loadBusBtn = document.getElementById('loadBusBtn');
    const busMetaEl = document.getElementById('busMeta');
    const busModeEl = document.getElementById('busMode');
    const busEngineEl = document.getElementById('busEngine');
    const busAlertEl = document.getElementById('busAlert');
    const busEngineeringStatusEl = document.getElementById('busEngineeringStatus');
    const busObjectiveEl = document.getElementById('busObjective');
    const busTaskTotalEl = document.getElementById('busTaskTotal');
    const busPendingReviewEl = document.getElementById('busPendingReview');
    const busExecutionsEl = document.getElementById('busExecutions');
    const busEngineerRunsEl = document.getElementById('busEngineerRuns');
    const busScorecardsEl = document.getElementById('busScorecards');
    const busLatestScoreEl = document.getElementById('busLatestScore');
    const busScoreTrendEl = document.getElementById('busScoreTrend');
    const busWarningsEl = document.getElementById('busWarnings');
    const busBlocksEl = document.getElementById('busBlocks');
    const busWorldSourceEl = document.getElementById('busWorldSource');
    const busExecutionSourceEl = document.getElementById('busExecutionSource');
    const busReliabilitySourceEl = document.getElementById('busReliabilitySource');
    const busConfWorldEl = document.getElementById('busConfWorld');
    const busConfExecutionEl = document.getElementById('busConfExecution');
    const busConfReliabilityEl = document.getElementById('busConfReliability');
    const busUncertaintiesEl = document.getElementById('busUncertainties');
    const busRoutingEl = document.getElementById('busRouting');
    const busEngineerRunHistoryEl = document.getElementById('busEngineerRunHistory');
    const busScoreSparklineEl = document.getElementById('busScoreSparkline');
    const busScoreHistoryEl = document.getElementById('busScoreHistory');
    const postureAgentEl = document.getElementById('postureAgent');
    const postureAlertEl = document.getElementById('postureAlert');
    const postureGoalsEl = document.getElementById('postureGoals');
    const postureExecutionsEl = document.getElementById('postureExecutions');
    const posturePendingEl = document.getElementById('posturePending');
    const postureBlockedEl = document.getElementById('postureBlocked');
    const postureCapabilitiesEl = document.getElementById('postureCapabilities');
    const postureHealthEl = document.getElementById('postureHealth');
    const postureSummaryEl = document.getElementById('postureSummary');
    const postureLegendEl = document.getElementById('postureLegend');
    const loopCurrentRunEl = document.getElementById('loopCurrentRun');
    const loopLastCycleEl = document.getElementById('loopLastCycle');
    const loopThresholdStateEl = document.getElementById('loopThresholdState');
    const loopMaturityBandEl = document.getElementById('loopMaturityBand');
    const loopApprovalPendingEl = document.getElementById('loopApprovalPending');
    const loopApprovalCountEl = document.getElementById('loopApprovalCount');
    const loopTopPenaltiesEl = document.getElementById('loopTopPenalties');
    const loopPhaseTrendsEl = document.getElementById('loopPhaseTrends');
    const logsEl = document.getElementById('logs');
    const logMetaEl = document.getElementById('logMeta');
    const tailEl = document.getElementById('tail');
    const autoRefreshEl = document.getElementById('autoRefresh');
    const progressRingEl = document.getElementById('progressRing');
    const progressPctEl = document.getElementById('progressPct');
    const baseProgressFillEl = document.getElementById('baseProgressFill');
    const baseProgressLabelEl = document.getElementById('baseProgressLabel');
    const liveThroughputFillEl = document.getElementById('liveThroughputFill');
    const liveThroughputLabelEl = document.getElementById('liveThroughputLabel');
    const projectMetaEl = document.getElementById('projectMeta');
    const todExecutiveSummaryEl = document.getElementById('todExecutiveSummary');
    const engineeringSignalMetaEl = document.getElementById('engineeringSignalMeta');
    const objectiveMarkerIdEl = document.getElementById('objectiveMarkerId');
    const objectiveMarkerStatusEl = document.getElementById('objectiveMarkerStatus');
    const objectiveMarkerTitleEl = document.getElementById('objectiveMarkerTitle');
    const objectiveMarkerProgressSourceEl = document.getElementById('objectiveMarkerProgressSource');
    const cadenceSeverityDetailEl = document.getElementById('cadenceSeverityDetail');
    const cadenceGovernanceSeverityDetailEl = document.getElementById('cadenceGovernanceSeverityDetail');
    const cadenceIdleDetailEl = document.getElementById('cadenceIdleDetail');
    const cadenceP95DetailEl = document.getElementById('cadenceP95Detail');
    const cadenceRetryDetailEl = document.getElementById('cadenceRetryDetail');
    const bridgeStatusSummaryEl = document.getElementById('bridgeStatusSummary');
    const bridgeStatusMetaEl = document.getElementById('bridgeStatusMeta');
    const bridgeObjectiveDetailEl = document.getElementById('bridgeObjectiveDetail');
    const bridgeHealthEl = document.getElementById('bridgeHealth');
    const bridgeTriggerTypeEl = document.getElementById('bridgeTriggerType');
    const bridgeTriggerSequenceEl = document.getElementById('bridgeTriggerSequence');
    const bridgeAckSequenceEl = document.getElementById('bridgeAckSequence');
    const bridgeTaskEl = document.getElementById('bridgeTask');
    const bridgeCanonicalObjectiveEl = document.getElementById('bridgeCanonicalObjective');
    const bridgeLiveObjectiveEl = document.getElementById('bridgeLiveObjective');
    const bridgeObjectiveSyncEl = document.getElementById('bridgeObjectiveSync');
    const bridgeConsumerEl = document.getElementById('bridgeConsumer');
    const bridgePathEl = document.getElementById('bridgePath');
    const bridgeHeartbeatEl = document.getElementById('bridgeHeartbeat');
    const maintenanceSummaryEl = document.getElementById('maintenanceSummary');
    const maintenanceStatusEl = document.getElementById('maintenanceStatus');
    const maintenanceSeverityEl = document.getElementById('maintenanceSeverity');
    const maintenanceReasonEl = document.getElementById('maintenanceReason');
    const maintenanceInvocationEl = document.getElementById('maintenanceInvocation');
    const maintenanceScheduledFallbackEl = document.getElementById('maintenanceScheduledFallback');
    const maintenanceThresholdWindowEl = document.getElementById('maintenanceThresholdWindow');
    const maintenanceSourceSeverityEl = document.getElementById('maintenanceSourceSeverity');
    const maintenanceGeneratedAtEl = document.getElementById('maintenanceGeneratedAt');
    const maintenanceMetaEl = document.getElementById('maintenanceMeta');
    const operatorChatFormEl = document.getElementById('operatorChatForm');
    const operatorChatInputEl = document.getElementById('operatorChatInput');
    const operatorChatSubmitEl = document.getElementById('operatorChatSubmit');
    const operatorChatMetaEl = document.getElementById('operatorChatMeta');
    const operatorChatAuditMetaEl = document.getElementById('operatorChatAuditMeta');
    const operatorChatAuditListEl = document.getElementById('operatorChatAuditList');
    const operatorChatAuditRefreshBtnEl = document.getElementById('operatorChatAuditRefreshBtn');
    const operatorChatAuditSearchEl = document.getElementById('operatorChatAuditSearch');
    const operatorChatAuditActionFilterEl = document.getElementById('operatorChatAuditActionFilter');
    const operatorChatAuditOutcomeFilterEl = document.getElementById('operatorChatAuditOutcomeFilter');
    const operatorChatAuditPhaseFilterEl = document.getElementById('operatorChatAuditPhaseFilter');
    const operatorChatAuditClearBtnEl = document.getElementById('operatorChatAuditClearBtn');
    const operatorChatCommitmentMetaEl = document.getElementById('operatorChatCommitmentMeta');
    const operatorChatCommitmentListEl = document.getElementById('operatorChatCommitmentList');
    const operatorChatCommitmentRefreshBtnEl = document.getElementById('operatorChatCommitmentRefreshBtn');
    const operatorChatTrustChainMetaEl = document.getElementById('operatorChatTrustChainMeta');
    const operatorChatTrustChainDetailEl = document.getElementById('operatorChatTrustChainDetail');
    const operatorChatTrustChainClearBtnEl = document.getElementById('operatorChatTrustChainClearBtn');
    const operatorChatThreadEl = document.getElementById('operatorChatThread');
    const operatorChatPresetEls = document.querySelectorAll('.operator-chat-preset');
    const taskFunnelEl = document.getElementById('taskFunnel');
    const callsBodyEl = document.getElementById('callsBody');
    const mimIndicatorEl = document.getElementById('mimIndicator');
    const mimIndicatorTextEl = document.getElementById('mimIndicatorText');
    const todIndicatorEl = document.getElementById('todIndicator');
    const todIndicatorTextEl = document.getElementById('todIndicatorText');
    const loopIndicatorEl = document.getElementById('loopIndicator');
    const loopIndicatorTextEl = document.getElementById('loopIndicatorText');
    const probeBtn = document.getElementById('probeBtn');
    const probeReadoutEl = document.getElementById('probeReadout');
    const reqPerMinEl = document.getElementById('reqPerMin');
    const avgLatencyEl = document.getElementById('avgLatency');
    const err5mEl = document.getElementById('err5m');
    const slow5mEl = document.getElementById('slow5m');
    const execEventsEl = document.getElementById('execEvents');
    const compactFullBtn = document.getElementById('compactFullBtn');
    const compactMimBtn = document.getElementById('compactMimBtn');
    const compactOpsBtn = document.getElementById('compactOpsBtn');
    const quickShareBtn = document.getElementById('quickShareBtn');
    const actionWorkspaceEl = document.getElementById('actionWorkspace');
    const actionWorkspaceCardEl = document.getElementById('actionWorkspaceCard');
    const actionSplitterEl = document.getElementById('actionSplitter');
    const toggleOutputBtn = document.getElementById('toggleOutputBtn');
    const togglePromptBtn = document.getElementById('togglePromptBtn');
    const mimTelemetryCardEl = document.getElementById('mimTelemetryCard');
    const armIndicatorEl = document.getElementById('armIndicator');
    const armIndicatorTextEl = document.getElementById('armIndicatorText');
    const armStatusBadgeEl = document.getElementById('armStatusBadge');
    const armStatusTextEl = document.getElementById('armStatusText');
    const armActiveLightEl = document.getElementById('armActiveLightEl');
    const armActiveLightTextEl = document.getElementById('armActiveLightText');
    const armHealthSummaryEl = document.getElementById('armHealthSummary');
    const armStatusDetailEl = document.getElementById('armStatusDetail');
    const armLastPingEl = document.getElementById('armLastPing');
    const armLastMoveEl = document.getElementById('armLastMove');
    const armMoves5mEl = document.getElementById('armMoves5m');
    const armCmdListEl = document.getElementById('armCmdList');

    let logsTimer = null;
    let projectTimer = null;
    let previousProjectPercent = null;
    let selectedObjectiveId = '';
    let lastSeenLogKey = '';
    let mimActiveUntilMs = 0;
    let todActiveUntilMs = 0;
    let armActiveUntilMs = 0;
    let compactModeEnabled = false;
    let compactProfile = 'mim';
    let projectAutoRefreshEnabled = true;
    let actionPaneState = 'expanded';
    let actionPaneStateBeforeCompact = 'expanded';
    let lastKnownTaskState = 'idle';
    let operatorChatPending = false;
    let operatorChatActionPending = false;
    let operatorChatAuditPending = false;
    let operatorChatCommitmentPending = false;
    let operatorChatTrustChainPending = false;
    const operatorChatActionPreviews = new Map();
    const OPERATOR_CHAT_ACTOR_ID = 'local-operator';
    const OPERATOR_CHAT_AUDIT_LIMIT = 6;
    const OPERATOR_CHAT_COMMITMENT_LIMIT = 4;
    let operatorChatTrustChainSelection = { auditId: '', previewId: '', bundleId: '', commitmentId: '' };
    let operatorChatAuditLoadToken = 0;
    const OPERATOR_CHAT_AUDIT_DEFAULT_FILTERS = Object.freeze({
      limit: OPERATOR_CHAT_AUDIT_LIMIT,
      previewId: '',
      action: '',
      outcomeStatus: '',
      phase: '',
      search: ''
    });
    let operatorChatAuditFilters = { ...OPERATOR_CHAT_AUDIT_DEFAULT_FILTERS };
    const UI_BUILD_VERSION = '2026.03.24-b26';
    const OPERATOR_CHAT_VALIDATION_HARNESS = new URLSearchParams(window.location.search).get('validation_harness') || '';
    let operatorChatLastRequest = { query: '', intent: '', windowMinutes: 10 };
    const OPERATOR_CHAT_ACTION_REFRESH_PLAN = Object.freeze({
      'refresh-share-links': [() => loadShareArtifacts(), () => loadOperatorChatActionAudit()],
      'refresh-project-status': [() => loadProjectStatus(), () => loadOperatorChatActionAudit()],
      'recheck-bridge-diagnostics': [() => loadProjectStatus(), () => loadOperatorChatActionAudit()],
      'quick-refresh-reliability': [() => Promise.all([loadProjectStatus(), loadLogs(), loadShareArtifacts()]), () => loadOperatorChatActionAudit()],
      'get-state-bus': [() => loadStateBus(), () => loadOperatorChatActionAudit()],
      'get-engineering-loop-summary': [() => run({ action: 'get-engineering-loop-summary', top: document.getElementById('top').value, category: document.getElementById('category').value, engine: document.getElementById('engine').value, configPath: document.getElementById('configPath').value }), () => loadOperatorChatActionAudit()],
      'get-engineering-signal': [() => run({ action: 'get-engineering-signal', top: document.getElementById('top').value, category: document.getElementById('category').value, engine: document.getElementById('engine').value, configPath: document.getElementById('configPath').value }), () => loadOperatorChatActionAudit()],
      'get-reliability': [() => run({ action: 'get-reliability', top: document.getElementById('top').value, category: document.getElementById('category').value, engine: document.getElementById('engine').value, configPath: document.getElementById('configPath').value }), () => loadOperatorChatActionAudit()],
      'show-reliability-dashboard': [() => run({ action: 'show-reliability-dashboard', top: document.getElementById('top').value, category: document.getElementById('category').value, engine: document.getElementById('engine').value, configPath: document.getElementById('configPath').value }), () => loadOperatorChatActionAudit()],
      'refresh-governance-snapshot': [() => Promise.all([loadProjectStatus(), loadShareArtifacts(), loadStateBus()]), () => loadOperatorChatActionAudit()],
      'refresh-bridge-alignment-bundle': [() => Promise.all([loadProjectStatus(), loadShareArtifacts(), loadStateBus()]), () => loadOperatorChatActionAudit()],
      default: [() => loadProjectStatus(), () => loadOperatorChatActionAudit()]
    });
    const UI_CHANGELOG = [
      {
        version: '2026.03.24-b26',
        notes: [
          'Added MIM ARM Health card showing ARM online/degraded/offline status derived from /ping and /move endpoint telemetry.',
          'Added ARM utilization active-light that pulses cyan when /move commands are detected in the last 30 seconds.',
          'Added ARM Idle/Active indicator pill in the header bar that reflects real-time command activity and ARM health state.'
        ]
      },
      {
        version: '2026.03.24-b21',
        notes: [
          'Objective 87 expands commitments with timeboxed and evidence-bound states instead of only manual commit or clear.',
          'Operator Chat now suppresses duplicate action churn, warns on expiring commitments, and forces revalidation when evidence changes under a commitment.',
          'A compact Trust Chain Inspector now opens audit, reasoning, and linked evidence together from governed action and commitment rows.'
        ]
      },
      {
        version: '2026.03.24-b19',
        notes: [
          'Objective 86 closes as a trusted layer with durable reasoning bundles linked from every governed audit event.',
          'Operator Chat now exposes an Objective 87 commitment loop so operators can commit to a proposed action before execution and TOD can adapt recommendations to that commitment.',
          'Prod-like validation now covers preview, audit, reasoning linkage, commitment capture, and documented failure modes.'
        ]
      },
      {
        version: '2026.03.24-b18',
        notes: [
          'Governed Action Audit now supports inline search and action, outcome, and phase filters against the live audit endpoint.',
          'Objective 86 safely expands the governed allowlist with Engineering Loop Summary and Engineering Signal read-only diagnostics.',
          'Operator sweep coverage now validates the new engineering governed actions and filtered audit endpoint behavior.'
        ]
      },
      {
        version: '2026.03.24-b17',
        notes: [
          'Objective 86 hardening adds server-side preview expiry and replay protection for governed actions.',
          'Operator Chat now exposes governed action audit history, preview expiry, audit IDs, and structured safe alternatives for blocked cases.',
          'Governed validation sweep now covers the allowlist, invalid preview paths, and audit inspection.'
        ]
      },
      {
        version: '2026.03.24-b16',
        notes: [
          'Objective 86 adds governed operator action preview and confirmation inside TOD Operator Chat.',
          'Chat actions now show allow or block reasoning, require explicit confirmation, and return audited outcomes.',
          'Governed actions reuse bounded read-only control paths and preserve observe-before-act discipline.'
        ]
      },
      {
        version: '2026.03.24-b15',
        notes: [
          'Added explicit current-objective and cadence detail surfaces so operator chat citations can land on exact fields.',
          'Bridge Status now exposes objective mismatch detail directly, not only as tooltip text.',
          'Operator chat now renders evidence posture, staleness guidance, and row-level evidence citations.'
        ]
      },
      {
        version: '2026.03.24-b12',
        notes: [
          'Added TOD Operator Chat as a read-only operational console over live dashboard state.',
          'Operator Chat supports constrained intents for status, warnings, bridge, cadence, maintenance, current objective, recent changes, and next-step suggestions.',
          'Suggested actions stay bounded to existing safe UI action paths instead of freeform command execution.'
        ]
      },
      {
        version: '2026.03.24-b11',
        notes: [
          'Added Maintenance Status panel sourced from shared_state/TOD_SELF_HEALTH_RUN.latest.json.',
          'Maintenance panel shows operational severity, raw source severity, severity_reason, and invocation mode.',
          'Dashboard now exposes scheduled fallback history and threshold state for self-health maintenance.'
        ]
      },
      {
        version: '2026.03.23-b10',
        notes: [
          'Added Bridge Status panel sourced from live trigger ACK, liveness response, and listener heartbeat artifacts.',
          'Bridge panel shows trigger type, trigger/ACK sequence, current task, consumer identity, shared path class, and listener freshness.',
          'Dashboard now exposes bridge truth directly instead of relying only on cadence/task-derived summaries.'
        ]
      },
      {
        version: '2026.03.14-b5',
        notes: [
          'Added server-side cadence health telemetry (severity, idle time, p50/p95 cycle time, retry rate) to /api/project-status.',
          'Action Live Status now includes cadence health signal for faster slow-vs-normal diagnosis while TOD is running.',
          'Project Marker now shows Cadence Health line with severity, p95 cycle, idle seconds, and retry percent.'
        ]
      },
      {
        version: '2026.03.13-b4',
        notes: [
          'Live cadence visibility: detects TOD activity beyond the 200-entry journal funnel and surfaces it in executive summary and project meta.',
          'MIM/TOD sync signal: compares latest MIM task request ID against TOD result ID; shows sync aligned or sync pending (N) in live status bar and pending queue.',
          'Stability: fixed Write-JsonResponse ContentLength64 crash on committed responses; suppressed engineering-signal call in listener-only mode to prevent OutOfMemoryException on large state.json.'
        ]
      },
      {
        version: '2026.03.13-b3',
        notes: [
          'Replaced empty System Posture card with TOD Query Console (REL, LOOP, RCH, JRNL, CAP, VER presets).',
          'System Posture moved inside Shared State Bus â€” populates on Refresh State Bus.',
          'Query Console uses compact vertical icon rail + side results panel to minimize footprint.'
        ]
      },
      {
        version: '2026.03.13-b2',
        notes: [
          'Added in-app UI Help modal with panel-by-panel semantics.',
          'Added header chips for active UI build and runtime port.',
          'Added this changelog block for at-a-glance release deltas.'
        ]
      },
      {
        version: '2026.03.13-b1',
        notes: [
          'Action timeline switched to newest-first ordering.',
          'Added pending queue under Action Output.',
          'Made Quick Refresh Reliability run safe dashboard refresh instead of heavy action execution.',
          'Added executive summary and state-bus refresh confirmation.',
          'Fixed share Open links by adding inline preview endpoint.'
        ]
      }
    ];

    function renderUiChangelog() {
      if (!uiChangelogEl) {
        return;
      }
      const previousEntry = UI_CHANGELOG.length > 1 ? UI_CHANGELOG[1] : null;
      const previousNotes = new Set(Array.isArray(previousEntry && previousEntry.notes) ? previousEntry.notes.map(item => String(item)) : []);
      const rows = UI_CHANGELOG.map((item, idx) => {
        const notes = Array.isArray(item.notes) ? item.notes : [];
        const safeVersion = escapeHtml(item.version || 'unknown');
        const noteRows = notes.map(note => {
          const text = String(note);
          const isNew = idx === 0 && !previousNotes.has(text);
          return `<span class="changelog-note${isNew ? ' new' : ''}">- ${escapeHtml(text)}${isNew ? ' <span class="since-count">new</span>' : ''}</span>`;
        }).join('');
        return `<div style="margin-bottom:8px;"><span class="changelog-version">${safeVersion}</span>${noteRows}</div>`;
      });
      uiChangelogEl.innerHTML = rows.join('');
    }

    function computeSinceLastBuildDelta() {
      const current = UI_CHANGELOG.length > 0 ? UI_CHANGELOG[0] : null;
      const previous = UI_CHANGELOG.length > 1 ? UI_CHANGELOG[1] : null;
      const currentNotes = Array.isArray(current && current.notes) ? current.notes.map(item => String(item)) : [];
      const previousSet = new Set(Array.isArray(previous && previous.notes) ? previous.notes.map(item => String(item)) : []);
      const added = currentNotes.filter(note => !previousSet.has(note));
      return {
        addedCount: added.length,
        hasPrevious: Boolean(previous)
      };
    }

    function initUiBuildMeta() {
      const port = window.location && window.location.port ? window.location.port : '--';
      if (uiBuildChipEl) {
        uiBuildChipEl.textContent = `UI build: ${UI_BUILD_VERSION}`;
      }
      if (uiSinceChipEl) {
        const delta = computeSinceLastBuildDelta();
        if (!delta.hasPrevious) {
          uiSinceChipEl.textContent = 'Since last build: baseline';
        } else {
          uiSinceChipEl.innerHTML = `Since last build: <span class="since-count">${delta.addedCount}</span> new`;
        }
      }
      if (uiPortChipEl) {
        uiPortChipEl.textContent = `Port: ${port}`;
      }
      if (cadenceHealthChipEl) {
        cadenceHealthChipEl.textContent = 'Cadence: loading';
        cadenceHealthChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      }
      if (steadyStateChipEl) {
        steadyStateChipEl.textContent = 'Steady: loading';
        steadyStateChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      }
      if (regressionChipEl) {
        regressionChipEl.textContent = 'Regression: --';
        regressionChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      }
      if (requestChipEl) {
        requestChipEl.textContent = 'Latest Req: --';
        requestChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      }
      if (voiceChipEl) {
        voiceChipEl.classList.remove('health-ok', 'health-warning', 'health-scaffold');
        voiceChipEl.classList.add('health-scaffold');
        voiceChipEl.textContent = 'Voice: --';
      }
      if (uiHelpMetaEl) {
        uiHelpMetaEl.textContent = `TOD Command Console build ${UI_BUILD_VERSION} on localhost:${port}.`; 
      }
      renderUiChangelog();
    }

    function renderCadenceHealthChip(cadenceHealth) {
      if (!cadenceHealthChipEl) {
        return;
      }

      const severityRaw = cadenceHealth && cadenceHealth.available
        ? String(cadenceHealth.severity || 'unknown').toLowerCase()
        : 'unknown';
      const severity = ['ok', 'warning', 'critical'].includes(severityRaw) ? severityRaw : 'unknown';

      cadenceHealthChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      cadenceHealthChipEl.classList.add(`health-${severity}`);

      const p95 = cadenceHealth && cadenceHealth.cadence && Number.isFinite(Number(cadenceHealth.cadence.p95_sec))
        ? `${Number(cadenceHealth.cadence.p95_sec)}s`
        : '-';

      cadenceHealthChipEl.textContent = `Cadence: ${severity.toUpperCase()} p95:${p95}`;
    }

    function renderObjectiveDetailSurface(marker, progress) {
      const setValue = (el, value) => {
        if (el) {
          el.textContent = value;
        }
      };

      if (!marker) {
        setValue(objectiveMarkerIdEl, '-');
        setValue(objectiveMarkerStatusEl, '-');
        setValue(objectiveMarkerTitleEl, '-');
        setValue(objectiveMarkerProgressSourceEl, '-');
        return;
      }

      setValue(objectiveMarkerIdEl, String(marker.objective_id || '-'));
      setValue(objectiveMarkerStatusEl, String(marker.status || '-').toUpperCase());
      setValue(objectiveMarkerTitleEl, String(marker.title || '(untitled objective)'));
      setValue(objectiveMarkerProgressSourceEl, String(progress && progress.source ? progress.source : '-'));
    }

    function renderCadenceDetailSurface(cadenceHealth) {
      const setValue = (el, value) => {
        if (el) {
          el.textContent = value;
        }
      };

      if (!cadenceHealth || !cadenceHealth.available) {
        setValue(cadenceSeverityDetailEl, '-');
        setValue(cadenceGovernanceSeverityDetailEl, '-');
        setValue(cadenceIdleDetailEl, '-');
        setValue(cadenceP95DetailEl, '-');
        setValue(cadenceRetryDetailEl, '-');
        return;
      }

      const governanceSeverity = cadenceHealth.governance && cadenceHealth.governance.adjusted_severity
        ? String(cadenceHealth.governance.adjusted_severity)
        : String(cadenceHealth.severity || '-');
      const idleText = cadenceHealth.stream && Number.isFinite(Number(cadenceHealth.stream.loop_idle_sec))
        ? `${Number(cadenceHealth.stream.loop_idle_sec)}s`
        : '-';
      const p95Text = cadenceHealth.cadence && Number.isFinite(Number(cadenceHealth.cadence.p95_sec))
        ? `${Number(cadenceHealth.cadence.p95_sec)}s`
        : '-';
      const retryText = cadenceHealth.cadence && Number.isFinite(Number(cadenceHealth.cadence.retry_rate))
        ? `${Math.round(Number(cadenceHealth.cadence.retry_rate) * 100)}%`
        : '-';

      setValue(cadenceSeverityDetailEl, String(cadenceHealth.severity || '-').toUpperCase());
      setValue(cadenceGovernanceSeverityDetailEl, governanceSeverity.toUpperCase());
      setValue(cadenceIdleDetailEl, idleText);
      setValue(cadenceP95DetailEl, p95Text);
      setValue(cadenceRetryDetailEl, retryText);
    }

    function renderSteadyStateChip(steadyState) {
      if (!steadyStateChipEl) {
        return;
      }

      const statusRaw = steadyState && steadyState.available
        ? String(steadyState.status || 'unknown').toLowerCase()
        : 'unknown';
      const status = ['ok', 'warning', 'critical'].includes(statusRaw) ? statusRaw : 'unknown';
      const passed = Number(steadyState && steadyState.passed);
      const total = Number(steadyState && steadyState.total);
      const score = Number.isFinite(passed) && Number.isFinite(total) && total > 0
        ? `${passed}/${total}`
        : '--';

      steadyStateChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      steadyStateChipEl.classList.add(`health-${status}`);
      steadyStateChipEl.textContent = `Steady: ${status.toUpperCase()} ${score}`;
      steadyStateChipEl.title = steadyState && steadyState.summary ? String(steadyState.summary) : 'Steady-state signal unavailable';
    }

    function renderRegressionChip(steadyState) {
      if (!regressionChipEl) {
        return;
      }

      const available = Boolean(steadyState && steadyState.available);
      const passed = Number(steadyState && steadyState.passed);
      const total = Number(steadyState && steadyState.total);
      const failed = Number(steadyState && steadyState.failed);
      const hasScore = available && Number.isFinite(passed) && Number.isFinite(total) && total > 0;
      const status = hasScore
        ? (Number.isFinite(failed) && failed <= 0 ? 'ok' : 'critical')
        : 'unknown';

      regressionChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      regressionChipEl.classList.add(`health-${status}`);
      regressionChipEl.textContent = hasScore ? `Regression: ${passed}/${total}` : 'Regression: --';
      const generatedAt = steadyState && steadyState.regression_generated_at
        ? formatRelativeAge(String(steadyState.regression_generated_at))
        : 'n/a';
      regressionChipEl.title = hasScore
        ? `Failed: ${Number.isFinite(failed) ? failed : '-'} | generated ${generatedAt}`
        : 'Regression score unavailable';
    }

    function renderRequestChip(listenerActivity) {
      if (!requestChipEl) {
        return;
      }

      const latestRequest = listenerActivity && listenerActivity.latest_request_id
        ? String(listenerActivity.latest_request_id)
        : '';
      const isAvailable = latestRequest.length > 0;

      requestChipEl.classList.remove('health-ok', 'health-warning', 'health-critical', 'health-unknown');
      requestChipEl.classList.add(isAvailable ? 'health-ok' : 'health-unknown');
      requestChipEl.textContent = isAvailable ? `Latest Req: ${latestRequest}` : 'Latest Req: --';

      const latestAge = listenerActivity && listenerActivity.latest_timestamp
        ? formatRelativeAge(String(listenerActivity.latest_timestamp))
        : 'n/a';
      requestChipEl.title = isAvailable
        ? `Last update: ${latestAge}`
        : 'No listener request id available';
    }

    function renderBridgeStatus(bridgeStatus) {
      if (!bridgeStatusSummaryEl || !bridgeStatusMetaEl) {
        return;
      }

      const setValue = (el, value) => {
        if (el) {
          el.textContent = value;
        }
      };

      if (!bridgeStatus || !bridgeStatus.available) {
        bridgeStatusSummaryEl.textContent = 'Bridge status unavailable.';
        bridgeStatusMetaEl.textContent = 'Waiting for trigger ACK, liveness response, and listener heartbeat artifacts.';
        if (bridgeObjectiveDetailEl) {
          bridgeObjectiveDetailEl.textContent = 'Objective sync detail unavailable.';
        }
        setValue(bridgeHealthEl, '-');
        setValue(bridgeTriggerTypeEl, '-');
        setValue(bridgeTriggerSequenceEl, '-');
        setValue(bridgeAckSequenceEl, '-');
        setValue(bridgeTaskEl, '-');
        setValue(bridgeCanonicalObjectiveEl, '-');
        setValue(bridgeLiveObjectiveEl, '-');
        setValue(bridgeObjectiveSyncEl, '-');
        setValue(bridgeConsumerEl, '-');
        setValue(bridgePathEl, '-');
        setValue(bridgeHeartbeatEl, '-');
        return;
      }

      const status = String(bridgeStatus.status || 'unknown').toUpperCase();
      const triggerType = String(bridgeStatus.latest_trigger_type || '-');
      const triggerSequence = Number.isFinite(Number(bridgeStatus.latest_trigger_sequence)) && Number(bridgeStatus.latest_trigger_sequence) > 0
        ? String(bridgeStatus.latest_trigger_sequence)
        : '-';
      const ackSequence = Number.isFinite(Number(bridgeStatus.latest_ack_sequence)) && Number(bridgeStatus.latest_ack_sequence) > 0
        ? String(bridgeStatus.latest_ack_sequence)
        : '-';
      const currentTask = String(bridgeStatus.current_task_id || '-');
      const canonicalObjective = String(bridgeStatus.canonical_mim_objective_id || '-');
      const liveObjective = String(bridgeStatus.task_request_objective_id || '-');
      const objectiveMismatch = Boolean(bridgeStatus.objective_mismatch);
      const objectiveMismatchDetail = String(bridgeStatus.objective_mismatch_detail || '').trim();
      const objectiveSync = objectiveMismatch ? 'MISMATCH' : 'ALIGNED';
      const consumerHost = String(bridgeStatus.consumer_host || '-');
      const consumerService = String(bridgeStatus.consumer_service || '-');
      const sharedPath = String(bridgeStatus.shared_path_kind || '-');
      const pollSeconds = Number.isFinite(Number(bridgeStatus.poll_interval_seconds)) && Number(bridgeStatus.poll_interval_seconds) > 0
        ? `${Number(bridgeStatus.poll_interval_seconds)}s`
        : '-';
      const heartbeatAge = Number.isFinite(Number(bridgeStatus.listener_cycle_age_seconds)) && Number(bridgeStatus.listener_cycle_age_seconds) >= 0
        ? `${Math.round(Number(bridgeStatus.listener_cycle_age_seconds))}s ago`
        : 'unknown';
      const freshnessState = String(bridgeStatus.listener_freshness_state || 'unknown');
      const freshnessThreshold = Number.isFinite(Number(bridgeStatus.listener_fresh_threshold_seconds)) && Number(bridgeStatus.listener_fresh_threshold_seconds) > 0
        ? `${Number(bridgeStatus.listener_fresh_threshold_seconds)}s`
        : '-';
      const statusReason = String(bridgeStatus.status_reason || 'unknown');
      const sequenceState = String(bridgeStatus.sequence_state || 'unknown');
      const artifactCompleteness = String(bridgeStatus.artifact_completeness || 'unknown');
      const missingArtifacts = Array.isArray(bridgeStatus.missing_artifacts) && bridgeStatus.missing_artifacts.length > 0
        ? bridgeStatus.missing_artifacts.map(item => String(item)).join(', ')
        : 'none';
      const triggerAckAge = bridgeStatus.trigger_ack && bridgeStatus.trigger_ack.generated_at
        ? formatRelativeAge(String(bridgeStatus.trigger_ack.generated_at))
        : 'n/a';
      const pingAge = bridgeStatus.ping_response && bridgeStatus.ping_response.generated_at
        ? formatRelativeAge(String(bridgeStatus.ping_response.generated_at))
        : 'n/a';
      const listenerCycleAge = bridgeStatus.listener && bridgeStatus.listener.last_cycle_at
        ? formatRelativeAge(String(bridgeStatus.listener.last_cycle_at))
        : 'n/a';
      const lastOutboundSequence = bridgeStatus.listener && Number.isFinite(Number(bridgeStatus.listener.last_outbound_sequence))
        ? String(bridgeStatus.listener.last_outbound_sequence)
        : '-';

      bridgeStatusSummaryEl.textContent = String(bridgeStatus.summary || 'Bridge status available.');
      bridgeStatusMetaEl.textContent = `ACK ${triggerAckAge} ago | Ping ${pingAge} ago | Listener cycle ${listenerCycleAge} ago | Freshness ${freshnessState}/${freshnessThreshold} | Sequence ${sequenceState} | Artifacts ${artifactCompleteness} (${missingArtifacts}) | Poll ${pollSeconds} | Last outbound seq ${lastOutboundSequence}`;
      if (bridgeObjectiveDetailEl) {
        bridgeObjectiveDetailEl.textContent = objectiveMismatchDetail || (objectiveMismatch
          ? 'Canonical and live task objectives do not match.'
          : `Canonical and live task objectives are aligned. Status reason: ${statusReason}.`);
      }
      setValue(bridgeHealthEl, status);
      setValue(bridgeTriggerTypeEl, triggerType);
      setValue(bridgeTriggerSequenceEl, triggerSequence);
      setValue(bridgeAckSequenceEl, ackSequence);
      setValue(bridgeTaskEl, currentTask);
      setValue(bridgeCanonicalObjectiveEl, canonicalObjective);
      setValue(bridgeLiveObjectiveEl, liveObjective);
      setValue(bridgeObjectiveSyncEl, objectiveSync);
      if (bridgeObjectiveSyncEl) {
        bridgeObjectiveSyncEl.title = objectiveMismatchDetail || (objectiveMismatch ? 'Canonical and live task objectives do not match.' : 'Canonical and live task objectives are aligned.');
      }
      setValue(bridgeConsumerEl, `${consumerHost} / ${consumerService}`);
      setValue(bridgePathEl, `${sharedPath} @ ${pollSeconds}`);
      setValue(bridgeHeartbeatEl, `${heartbeatAge} (${freshnessState})`);
    }

    function renderMaintenanceStatus(maintenance) {
      if (!maintenanceSummaryEl || !maintenanceMetaEl) {
        return;
      }

      const setValue = (el, value) => {
        if (el) {
          el.textContent = value;
        }
      };

      if (!maintenance || !maintenance.available) {
        maintenanceSummaryEl.textContent = 'Self-health maintenance report unavailable.';
        maintenanceMetaEl.textContent = 'Waiting for shared_state/TOD_SELF_HEALTH_RUN.latest.json.';
        setValue(maintenanceStatusEl, '-');
        setValue(maintenanceSeverityEl, '-');
        setValue(maintenanceReasonEl, '-');
        setValue(maintenanceInvocationEl, '-');
        setValue(maintenanceScheduledFallbackEl, '-');
        setValue(maintenanceThresholdWindowEl, '-');
        setValue(maintenanceSourceSeverityEl, '-');
        setValue(maintenanceGeneratedAtEl, '-');
        return;
      }

      const history = maintenance.history || {};
      const scheduledFallbackCount = Number.isFinite(Number(history.scheduled_fallback_runs_including_current))
        ? Number(history.scheduled_fallback_runs_including_current)
        : 0;
      const thresholdRuns = Number.isFinite(Number(history.threshold_runs))
        ? Number(history.threshold_runs)
        : 0;
      const windowHours = Number.isFinite(Number(history.window_hours))
        ? Number(history.window_hours)
        : 0;
      const generatedAtText = maintenance.generated_at
        ? formatRelativeAge(String(maintenance.generated_at))
        : 'n/a';
      const durationText = Number.isFinite(Number(maintenance.duration_seconds)) && Number(maintenance.duration_seconds) >= 0
        ? `${Number(maintenance.duration_seconds).toFixed(1)}s`
        : '-';
      const thresholdState = history.threshold_exceeded ? 'threshold exceeded' : 'below threshold';

      maintenanceSummaryEl.textContent = String(maintenance.summary || 'Maintenance report available.');
      maintenanceMetaEl.textContent = `${String(maintenance.recommendation || 'No recommendation recorded.')} | generated ${generatedAtText} | duration ${durationText}`;
      setValue(maintenanceStatusEl, String(maintenance.overall_status || '-').toUpperCase());
      setValue(maintenanceSeverityEl, String(maintenance.overall_severity || '-').toUpperCase());
      setValue(maintenanceReasonEl, String(maintenance.severity_reason || '-'));
      setValue(maintenanceInvocationEl, String(maintenance.invocation_mode || '-'));
      setValue(maintenanceScheduledFallbackEl, `${scheduledFallbackCount}/${thresholdRuns || '-'}`);
      setValue(maintenanceThresholdWindowEl, windowHours > 0 ? `${windowHours}h | ${thresholdState}` : thresholdState);
      setValue(maintenanceSourceSeverityEl, String(maintenance.source_severity || '-').toUpperCase());
      setValue(maintenanceGeneratedAtEl, generatedAtText);
    }

    function renderVoiceChip(voiceAdapter) {
      if (!voiceChipEl) return;
      const available = voiceAdapter && voiceAdapter.available;
      const enabled = available && voiceAdapter.enabled;
      const micActive = enabled && voiceAdapter.microphone_active;
      const mode = voiceAdapter && voiceAdapter.mode ? voiceAdapter.mode : 'dry_run';
      voiceChipEl.classList.remove('health-ok', 'health-warning', 'health-scaffold');
      if (!available) {
        voiceChipEl.classList.add('health-scaffold');
        voiceChipEl.textContent = 'Voice: --';
      } else if (!enabled) {
        voiceChipEl.classList.add('health-scaffold');
        voiceChipEl.textContent = `Voice: ${mode}`;
      } else if (micActive) {
        voiceChipEl.classList.add('health-ok');
        voiceChipEl.textContent = 'Voice: LIVE';
      } else {
        voiceChipEl.classList.add('health-ok');
        voiceChipEl.textContent = 'Voice: ON (start listener)';
      }
    }

    function renderVoiceAdapterPanel(voiceAdapter) {
      if (!voiceAdapterPanelEl) return;
      if (!voiceAdapter || !voiceAdapter.available) {
        voiceAdapterPanelEl.innerHTML = '<span class="voice-key">Voice Adapter</span> <span class="voice-val voice-disabled">scaffold unavailable</span>';
        return;
      }
      const mode = voiceAdapter.mode || 'dry_run';
      const enabledLabel = voiceAdapter.enabled ? 'enabled' : 'scaffold (disabled)';
      const microphone = voiceAdapter.microphone_active
        ? 'LIVE'
        : (voiceAdapter.allow_microphone ? 'ready (start listener)' : 'locked');
      const camera = voiceAdapter.allow_camera
        ? (voiceAdapter.camera_active ? 'active' : 'allowed')
        : 'locked';
      const ptt = voiceAdapter.require_push_to_talk ? 'PTT:required' : 'PTT:off';
      const wake = voiceAdapter.wake_phrase ? `wake:"${escapeHtml(voiceAdapter.wake_phrase)}"` : '';
      const queued = Number(voiceAdapter.queued_events) || 0;
      const lastIntent = voiceAdapter.last_intent ? `last-intent:${escapeHtml(voiceAdapter.last_intent)}` : 'last-intent:none';
      const lastTranscript = voiceAdapter.last_transcript ? `"${escapeHtml(voiceAdapter.last_transcript)}"` : '';
      const micClass = voiceAdapter.allow_microphone ? 'voice-val' : 'voice-val voice-locked';
      const camClass = voiceAdapter.allow_camera ? 'voice-val' : 'voice-val voice-locked';
      voiceAdapterPanelEl.innerHTML =
        `<div class="voice-row">` +
        `<span class="voice-key">Voice Adapter</span>` +
        `<span class="voice-val ${voiceAdapter.enabled ? 'voice-enabled' : 'voice-disabled'}">${escapeHtml(enabledLabel)}</span>` +
        `<span class="voice-val">mode:${escapeHtml(mode)}</span>` +
        `<span class="${micClass}">mic:${escapeHtml(microphone)}</span>` +
        `<span class="${camClass}">cam:${escapeHtml(camera)}</span>` +
        `<span class="voice-val">${ptt}</span>` +
        (wake ? `<span class="voice-val">${wake}</span>` : '') +
        `<span class="voice-val">queued:${queued}</span>` +
        `<span class="voice-val">${lastIntent}</span>` +
        (lastTranscript ? `<span class="voice-val">${lastTranscript}</span>` : '') +
        `</div>`;
    }

    function openUiHelp() {
      if (!uiHelpModalEl) {
        return;
      }
      uiHelpModalEl.classList.add('open');
      uiHelpModalEl.setAttribute('aria-hidden', 'false');
    }

    function closeUiHelp() {
      if (!uiHelpModalEl) {
        return;
      }
      uiHelpModalEl.classList.remove('open');
      uiHelpModalEl.setAttribute('aria-hidden', 'true');
    }

    function syncSettingsPanelState() {
      if (settingsLogsToggleEl && autoRefreshEl) {
        settingsLogsToggleEl.checked = String(autoRefreshEl.value || 'on') === 'on';
      }
      if (settingsProjectToggleEl) {
        settingsProjectToggleEl.checked = projectAutoRefreshEnabled;
      }
      if (settingsPresetFullEl) {
        settingsPresetFullEl.classList.toggle('active', !compactModeEnabled);
      }
      if (settingsPresetMimEl) {
        settingsPresetMimEl.classList.toggle('active', compactModeEnabled && compactProfile === 'mim');
      }
      if (settingsPresetOpsEl) {
        settingsPresetOpsEl.classList.toggle('active', compactModeEnabled && compactProfile === 'ops');
      }
    }

    function openSettingsPanel() {
      if (!uiSettingsPanelEl || !uiSettingsBtnEl) {
        return;
      }
      syncSettingsPanelState();
      uiSettingsPanelEl.classList.add('open');
      uiSettingsPanelEl.setAttribute('aria-hidden', 'false');
      uiSettingsBtnEl.classList.add('active');
      uiSettingsBtnEl.setAttribute('aria-expanded', 'true');
    }

    function closeSettingsPanel() {
      if (!uiSettingsPanelEl || !uiSettingsBtnEl) {
        return;
      }
      uiSettingsPanelEl.classList.remove('open');
      uiSettingsPanelEl.setAttribute('aria-hidden', 'true');
      uiSettingsBtnEl.classList.remove('active');
      uiSettingsBtnEl.setAttribute('aria-expanded', 'false');
    }

    function toggleSettingsPanel() {
      if (!uiSettingsPanelEl || !uiSettingsBtnEl) {
        return;
      }
      if (uiSettingsPanelEl.classList.contains('open')) {
        closeSettingsPanel();
        return;
      }
      openSettingsPanel();
    }

    function setLogsAutoRefreshPreference(enabled, persist = true) {
      if (autoRefreshEl) {
        autoRefreshEl.value = enabled ? 'on' : 'off';
      }
      if (persist) {
        try {
          localStorage.setItem('tod.logsAutoRefresh', enabled ? 'on' : 'off');
        } catch {
        }
      }
      setLogsAutoRefresh();
      syncSettingsPanelState();
    }

    function setProjectAutoRefreshPreference(enabled, persist = true) {
      projectAutoRefreshEnabled = enabled === true;
      if (persist) {
        try {
          localStorage.setItem('tod.projectAutoRefresh', projectAutoRefreshEnabled ? 'on' : 'off');
        } catch {
        }
      }
      setProjectAutoRefresh();
      syncSettingsPanelState();
    }

    function initializeConsoleSettings() {
      try {
        const savedLogs = localStorage.getItem('tod.logsAutoRefresh');
        if (savedLogs === 'on' || savedLogs === 'off') {
          setLogsAutoRefreshPreference(savedLogs === 'on', false);
        }
      } catch {
      }

      try {
        const savedProject = localStorage.getItem('tod.projectAutoRefresh');
        if (savedProject === 'off') {
          projectAutoRefreshEnabled = false;
        }
      } catch {
      }

      syncSettingsPanelState();
    }

    function focusMimTelemetryCard() {
      if (!mimTelemetryCardEl || window.innerWidth > 980) {
        return;
      }
      const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      mimTelemetryCardEl.scrollIntoView({
        behavior: reduceMotion ? 'auto' : 'smooth',
        block: 'start'
      });
    }

    function focusActionWorkspaceCard() {
      if (!actionWorkspaceCardEl || window.innerWidth > 980) {
        return;
      }
      const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      actionWorkspaceCardEl.scrollIntoView({
        behavior: reduceMotion ? 'auto' : 'smooth',
        block: 'start'
      });
    }

    function jumpToShareArtifacts() {
      if (actionPaneState === 'collapsed-left') {
        actionPaneState = 'expanded';
        updateActionWorkspaceControls();
      }

      const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      const target = shareLinksEl || actionWorkspaceCardEl;
      if (target && typeof target.scrollIntoView === 'function') {
        target.scrollIntoView({
          behavior: reduceMotion ? 'auto' : 'smooth',
          block: 'center'
        });
      }

      if (shareLinksEl) {
        shareLinksEl.classList.remove('flash-highlight');
        // Triggering layout ensures repeated clicks replay the highlight animation.
        void shareLinksEl.offsetWidth;
        shareLinksEl.classList.add('flash-highlight');
        window.setTimeout(() => {
          shareLinksEl.classList.remove('flash-highlight');
        }, 1800);
      }
    }

    function flashDashboardTarget(target) {
      if (!target) {
        return;
      }

      target.classList.remove('flash-highlight');
      void target.offsetWidth;
      target.classList.add('flash-highlight');
      window.setTimeout(() => {
        target.classList.remove('flash-highlight');
      }, 1200);
    }

    function focusDashboardCardById(cardId) {
      const targetId = String(cardId || '').trim();
      if (!targetId) {
        return;
      }

      const target = document.getElementById(targetId);
      if (!target || typeof target.scrollIntoView !== 'function') {
        return;
      }

      const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      target.scrollIntoView({
        behavior: reduceMotion ? 'auto' : 'smooth',
        block: 'start'
      });

      flashDashboardTarget(target);
      const card = target.classList && target.classList.contains('card')
        ? target
        : (target.closest ? target.closest('.card') : null);
      if (card && card !== target) {
        flashDashboardTarget(card);
      }
    }

    function applyCompactProfileClass() {
      document.body.classList.remove('compact-profile-mim', 'compact-profile-ops');
      if (!compactModeEnabled) {
        return;
      }
      document.body.classList.add(compactProfile === 'ops' ? 'compact-profile-ops' : 'compact-profile-mim');
    }

    function updateCompactPresetButtons() {
      compactFullBtn.classList.toggle('active', !compactModeEnabled);
      compactMimBtn.classList.toggle('active', compactModeEnabled && compactProfile === 'mim');
      compactOpsBtn.classList.toggle('active', compactModeEnabled && compactProfile === 'ops');
      compactFullBtn.setAttribute('aria-pressed', compactModeEnabled ? 'false' : 'true');
      compactMimBtn.setAttribute('aria-pressed', compactModeEnabled && compactProfile === 'mim' ? 'true' : 'false');
      compactOpsBtn.setAttribute('aria-pressed', compactModeEnabled && compactProfile === 'ops' ? 'true' : 'false');
    }

    function setAlertTone(alertState) {
      const value = String(alertState || '').toLowerCase();
      document.body.classList.remove('tone-warning', 'tone-degraded', 'tone-critical');
      if (value === 'warning' || value === 'watch') {
        document.body.classList.add('tone-warning');
        return;
      }
      if (value === 'degraded') {
        document.body.classList.add('tone-degraded');
        return;
      }
      if (value === 'critical') {
        document.body.classList.add('tone-critical');
      }
    }

    function setLoopIndicator(status, latestScore, trendDirection) {
      if (!loopIndicatorEl || !loopIndicatorTextEl) {
        return;
      }

      const resolvedStatus = String(status || 'idle').toLowerCase();
      loopIndicatorEl.classList.remove('is-strong', 'is-active', 'is-warming', 'is-idle', 'is-degraded');

      let statusClass = 'is-idle';
      if (resolvedStatus === 'strong') {
        statusClass = 'is-strong';
      } else if (resolvedStatus === 'active') {
        statusClass = 'is-active';
      } else if (resolvedStatus === 'warming') {
        statusClass = 'is-warming';
      } else if (resolvedStatus === 'degraded' || resolvedStatus === 'critical') {
        statusClass = 'is-degraded';
      }

      loopIndicatorEl.classList.add(statusClass);

      const scoreText = Number.isFinite(Number(latestScore)) ? Number(latestScore).toFixed(2) : '-';
      const trendText = String(trendDirection || 'flat').toLowerCase();
      loopIndicatorTextEl.textContent = `Loop: ${resolvedStatus} | score ${scoreText} | trend ${trendText}`;
    }

    function isTypingTarget(element) {
      if (!element) {
        return false;
      }
      const tag = String(element.tagName || '').toLowerCase();
      if (tag === 'input' || tag === 'select' || tag === 'textarea') {
        return true;
      }
      if (element.isContentEditable) {
        return true;
      }
      return Boolean(element.closest && element.closest('input, select, textarea, [contenteditable="true"]'));
    }

    function handleKeyboardShortcuts(evt) {
      if (evt.defaultPrevented || evt.ctrlKey || evt.metaKey || evt.altKey) {
        return;
      }
      if (String(evt.key || '') === 'Escape' && uiSettingsPanelEl && uiSettingsPanelEl.classList.contains('open')) {
        evt.preventDefault();
        closeSettingsPanel();
        return;
      }
      if (String(evt.key || '') === 'Escape' && uiHelpModalEl && uiHelpModalEl.classList.contains('open')) {
        evt.preventDefault();
        closeUiHelp();
        return;
      }
      if (isTypingTarget(evt.target)) {
        return;
      }

      const key = String(evt.key || '').toLowerCase();
      if (key === 'f') {
        evt.preventDefault();
        applyCompactPreset('off');
        return;
      }
      if (key === 'm') {
        evt.preventDefault();
        applyCompactPreset('mim');
        return;
      }
      if (key === 'o') {
        evt.preventDefault();
        applyCompactPreset('ops');
      }
    }

    function setCompactMode(enabled) {
      compactModeEnabled = enabled === true;
      document.body.classList.toggle('compact-mode', compactModeEnabled);
      try {
        localStorage.setItem('tod.compactMode', compactModeEnabled ? 'on' : 'off');
      } catch {
        // Ignore localStorage failures.
      }

      if (compactModeEnabled) {
        if (actionPaneState !== 'collapsed-right') {
          actionPaneStateBeforeCompact = actionPaneState;
          actionPaneState = 'collapsed-right';
        }
        window.setTimeout(() => {
          if (compactProfile === 'ops') {
            focusActionWorkspaceCard();
            return;
          }
          focusMimTelemetryCard();
        }, 80);
      } else if (actionPaneState === 'collapsed-right' && actionPaneStateBeforeCompact !== 'collapsed-right') {
        actionPaneState = actionPaneStateBeforeCompact || 'expanded';
      }

      applyCompactProfileClass();
      updateCompactPresetButtons();
      updateActionWorkspaceControls();
    }

    function setCompactProfile(profile) {
      compactProfile = profile === 'ops' ? 'ops' : 'mim';
      try {
        localStorage.setItem('tod.compactProfile', compactProfile);
      } catch {
        // Ignore localStorage failures.
      }
      applyCompactProfileClass();
      updateCompactPresetButtons();
      syncSettingsPanelState();
    }

    function applyCompactPreset(preset) {
      if (preset === 'off') {
        setCompactMode(false);
        return;
      }
      setCompactProfile(preset);
      setCompactMode(true);
    }

    function initializeCompactMode() {
      try {
        const saved = localStorage.getItem('tod.compactMode');
        const savedProfile = localStorage.getItem('tod.compactProfile');
        if (savedProfile === 'ops') {
          compactProfile = 'ops';
        }
        if (saved === 'on') {
          setCompactMode(true);
          return;
        }
        if (saved === 'off') {
          setCompactMode(false);
          return;
        }
      } catch {
        // Fall through to viewport heuristic.
      }

      setCompactMode(window.innerWidth <= 760);
    }

    function updateActionWorkspaceControls() {
      if (actionPaneState === 'collapsed-right') {
        actionWorkspaceEl.classList.add('collapsed-right');
        actionWorkspaceEl.classList.remove('collapsed-left');
        toggleOutputBtn.textContent = 'Show Output';
        togglePromptBtn.textContent = 'Hide Prompt';
        return;
      }

      if (actionPaneState === 'collapsed-left') {
        actionWorkspaceEl.classList.add('collapsed-left');
        actionWorkspaceEl.classList.remove('collapsed-right');
        togglePromptBtn.textContent = 'Show Prompt';
        toggleOutputBtn.textContent = 'Hide Output';
        return;
      }

      actionWorkspaceEl.classList.remove('collapsed-left', 'collapsed-right');
      toggleOutputBtn.textContent = 'Hide Output';
      togglePromptBtn.textContent = 'Hide Prompt';
    }

    function setActionSplitRatio(percent) {
      const min = 25;
      const max = 75;
      const bounded = Math.max(min, Math.min(max, Number(percent) || 38));
      actionWorkspaceEl.style.setProperty('--action-pane-width', `${bounded}%`);
      try {
        localStorage.setItem('tod.actionPaneWidth', String(Math.round(bounded)));
      } catch {
        // Ignore localStorage failures.
      }
    }

    function initializeActionWorkspaceSplit() {
      try {
        const saved = Number(localStorage.getItem('tod.actionPaneWidth'));
        if (Number.isFinite(saved)) {
          setActionSplitRatio(saved);
        }
      } catch {
        setActionSplitRatio(38);
      }

      let dragging = false;

      const onPointerMove = (evt) => {
        if (!dragging || window.innerWidth <= 980 || actionPaneState !== 'expanded') {
          return;
        }
        const rect = actionWorkspaceEl.getBoundingClientRect();
        if (!rect || rect.width <= 0) {
          return;
        }
        const ratio = ((evt.clientX - rect.left) / rect.width) * 100;
        setActionSplitRatio(ratio);
      };

      const stopDragging = () => {
        dragging = false;
        document.body.style.cursor = '';
        document.body.style.userSelect = '';
      };

      actionSplitterEl.addEventListener('pointerdown', (evt) => {
        if (window.innerWidth <= 980 || actionPaneState !== 'expanded') {
          return;
        }
        evt.preventDefault();
        dragging = true;
        document.body.style.cursor = 'col-resize';
        document.body.style.userSelect = 'none';
      });

      window.addEventListener('pointermove', onPointerMove);
      window.addEventListener('pointerup', stopDragging);
      window.addEventListener('pointercancel', stopDragging);

      toggleOutputBtn.addEventListener('click', () => {
        actionPaneState = actionPaneState === 'collapsed-right' ? 'expanded' : 'collapsed-right';
        updateActionWorkspaceControls();
      });

      togglePromptBtn.addEventListener('click', () => {
        actionPaneState = actionPaneState === 'collapsed-left' ? 'expanded' : 'collapsed-left';
        updateActionWorkspaceControls();
      });

      window.addEventListener('resize', () => {
        if (window.innerWidth <= 980 && compactModeEnabled && actionPaneState !== 'collapsed-right') {
          actionPaneState = 'collapsed-right';
        }
        updateActionWorkspaceControls();
      });

      updateActionWorkspaceControls();
    }

    function setStatus(message, isError = false) {
      statusEl.textContent = message;
      statusEl.classList.toggle('error', isError);
    }

    function escapeHtml(value) {
      return String(value || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    }

    function resolveRingColor(percent, status) {
      const safe = Math.max(0, Math.min(100, Number(percent) || 0));
      const normalizedStatus = String(status || '').toLowerCase();

      if (normalizedStatus === 'escalate') return 'var(--danger)';
      if (normalizedStatus === 'revise') return 'var(--warn)';
      if (safe >= 80) return 'var(--neon)';
      if (safe >= 45) return 'var(--warn)';
      return 'var(--danger)';
    }

    function setProgressRing(percent, status, cadence = null) {
      const safe = Math.max(0, Math.min(100, Number(percent) || 0));
      const cadenceLive = Boolean(cadence && cadence.beyondFunnel && cadence.recent);
      if (cadenceLive) {
        const phase = (Date.now() / 1000) % 6;
        const livePercent = Math.round(92 + ((phase / 6) * 6));
        const deg = Math.round((livePercent / 100) * 360);
        progressRingEl.classList.add('live');
        progressRingEl.style.background = `conic-gradient(var(--neon) ${deg}deg, rgba(90,180,140,0.2) ${deg}deg 360deg)`;
        progressPctEl.textContent = 'LIVE';
        progressPctEl.title = `Base funnel complete at ${safe}%. Autonomous listener cadence active.`;
        return;
      }

      const deg = Math.round((safe / 100) * 360);
      const color = resolveRingColor(safe, status);
      progressRingEl.classList.remove('live');
      progressRingEl.style.background = `conic-gradient(${color} ${deg}deg, rgba(90,180,140,0.2) ${deg}deg 360deg)`;
      progressPctEl.textContent = `${safe}%`;
      progressPctEl.title = '';
    }

    function formatTrend(percent) {
      if (previousProjectPercent === null) {
        previousProjectPercent = percent;
        return '<span class="trend flat">-> baseline</span>';
      }

      const delta = percent - previousProjectPercent;
      previousProjectPercent = percent;
      if (delta > 0) return `<span class="trend up">^ +${delta}%</span>`;
      if (delta < 0) return `<span class="trend down">v ${delta}%</span>`;
      return '<span class="trend flat">-> no change</span>';
    }

    function formatRelativeAge(isoText) {
      if (!isoText) return 'n/a';
      const ts = Date.parse(isoText);
      if (!Number.isFinite(ts)) return 'n/a';
      const ageSec = Math.max(0, Math.round((Date.now() - ts) / 1000));
      if (ageSec < 60) return `${ageSec}s ago`;
      return `${Math.round(ageSec / 60)}m ago`;
    }

    function computeLiveThroughput(listenerActivity, objectiveId) {
      const entries = listenerActivity && Array.isArray(listenerActivity.recent_entries)
        ? listenerActivity.recent_entries
        : [];
      if (!entries.length) {
        return null;
      }

      const objectiveDigits = String(objectiveId || '').match(/(\d+)/);
      const objectiveToken = objectiveDigits ? objectiveDigits[1] : '';
      const now = Date.now();
      const cutoff = now - (30 * 60 * 1000);

      const done = entries
        .filter(item => {
          if (!item || String(item.execution_status || '').toLowerCase() !== 'completed') {
            return false;
          }
          if (objectiveToken && String(item.objective_id || '') !== objectiveToken) {
            return false;
          }
          const ts = Date.parse(String(item.timestamp || ''));
          return Number.isFinite(ts) && ts >= cutoff;
        })
        .slice()
        .sort((a, b) => Date.parse(String(a.timestamp || '')) - Date.parse(String(b.timestamp || '')));

      if (!done.length) {
        return { perHour: 0, utilizationPct: 0 };
      }

      const seen = new Set();
      let uniqueCount = 0;
      for (const item of done) {
        const rid = String(item.request_id || '');
        if (!rid || seen.has(rid)) {
          continue;
        }
        seen.add(rid);
        uniqueCount += 1;
      }

      const perHour = Math.round(uniqueCount * 2);
      const utilizationPct = Math.max(0, Math.min(100, Math.round((perHour / 30) * 100)));
      return { perHour, utilizationPct };
    }

    function renderProgressDual(progress, cadence, listenerActivity, objectiveId) {
      const basePct = Math.max(0, Math.min(100, Number(progress && progress.percent) || 0));
      if (baseProgressFillEl) {
        baseProgressFillEl.style.width = `${basePct}%`;
      }
      if (baseProgressLabelEl) {
        const total = Number(progress && progress.task_count) || 0;
        const done = Math.min(total, Math.max(0, Number(progress && progress.completed_equivalent) || 0));
        baseProgressLabelEl.textContent = total > 0 ? `${done.toFixed(0)}/${total} (${basePct}%)` : `${basePct}%`;
      }

      const tp = computeLiveThroughput(listenerActivity, objectiveId);
      if (liveThroughputFillEl) {
        const tpPct = cadence && cadence.beyondFunnel && cadence.recent
          ? (tp ? tp.utilizationPct : 20)
          : (tp ? Math.min(35, tp.utilizationPct) : 0);
        liveThroughputFillEl.style.width = `${tpPct}%`;
      }
      if (liveThroughputLabelEl) {
        if (!tp) {
          liveThroughputLabelEl.textContent = '--';
        } else {
          const liveTag = cadence && cadence.beyondFunnel && cadence.recent ? 'live' : 'baseline';
          liveThroughputLabelEl.textContent = `${tp.perHour}/hr (${liveTag})`;
        }
      }
    }

    function getIsoAgeSeconds(isoText) {
      if (!isoText) return NaN;
      const ts = Date.parse(isoText);
      if (!Number.isFinite(ts)) return NaN;
      return Math.max(0, Math.round((Date.now() - ts) / 1000));
    }

    function parseRequestTaskInfo(requestId) {
      const raw = String(requestId || '');
      const match = raw.match(/objective-(\d+)-task-(\d+)/i);
      if (!match) {
        return null;
      }
      return {
        objective: match[1],
        taskNumber: Number.parseInt(match[2], 10)
      };
    }

    function synthesizeMarkerFromListener(marker, listenerActivity, selectedObjectiveId, bridgeStatus) {
      if (marker) {
        return marker;
      }

      const bridgeObjective = bridgeStatus && bridgeStatus.task_request_objective_id
        ? String(bridgeStatus.task_request_objective_id)
        : '';
      const selectedObjective = selectedObjectiveId ? String(selectedObjectiveId) : '';
      const taskObjective = parseRequestTaskInfo(listenerActivity && listenerActivity.latest_request_id);
      const taskObjectiveId = taskObjective && taskObjective.objective
        ? `objective-${taskObjective.objective}`
        : '';
      const fallbackObjectiveId = bridgeObjective || selectedObjective || taskObjectiveId;

      if (!fallbackObjectiveId) {
        return null;
      }

      return {
        objective_id: fallbackObjectiveId,
        remote_objective_id: fallbackObjectiveId,
        title: `Listener Objective ${fallbackObjectiveId}`,
        status: listenerActivity && listenerActivity.latest_execution_status
          ? String(listenerActivity.latest_execution_status)
          : 'listener',
        priority: 'listener',
        updated_at: listenerActivity && listenerActivity.latest_timestamp
          ? String(listenerActivity.latest_timestamp)
          : ''
      };
    }

    function buildCadenceSnapshot(listenerActivity, totalTasks) {
      if (!listenerActivity) {
        return null;
      }

      const taskId = listenerActivity.request_task_id || listenerActivity.latest_request_id || listenerActivity.result_request_id || '';
      const info = parseRequestTaskInfo(taskId);
      if (!info) {
        return null;
      }

      const requestAgeSec = getIsoAgeSeconds(listenerActivity.request_generated_at || listenerActivity.latest_timestamp);
      const resultAgeSec = getIsoAgeSeconds(listenerActivity.result_generated_at || listenerActivity.latest_timestamp);
      const freshestAgeSec = [requestAgeSec, resultAgeSec].filter(Number.isFinite).sort((a, b) => a - b)[0];
      const recent = Number.isFinite(freshestAgeSec) ? freshestAgeSec <= 300 : false;
      const beyondFunnel = Number.isFinite(Number(totalTasks)) && Number(totalTasks) > 0 && info.taskNumber > Number(totalTasks);
      const syncPending = Boolean(listenerActivity.sync && listenerActivity.sync.is_mim_ahead);

      return {
        taskId,
        taskNumber: info.taskNumber,
        objective: info.objective,
        recent,
        beyondFunnel,
        syncPending,
        requestAgeText: formatRelativeAge(listenerActivity.request_generated_at || listenerActivity.latest_timestamp),
        resultAgeText: formatRelativeAge(listenerActivity.result_generated_at || listenerActivity.latest_timestamp)
      };
    }

    function estimateMinutesRemaining(entries, totalTasks, completedEquivalent) {
      const total = Number(totalTasks);
      const done = Number(completedEquivalent);
      if (!Number.isFinite(total) || total <= 0 || !Number.isFinite(done)) {
        return null;
      }

      const remaining = Math.max(0, total - done);
      if (remaining === 0) {
        return 0;
      }

      const list = Array.isArray(entries) ? entries : [];
      const completed = list
        .filter(item => String(item && item.execution_status || '').toLowerCase() === 'completed' && item && item.timestamp)
        .slice()
        .sort((a, b) => Date.parse(a.timestamp || '') - Date.parse(b.timestamp || ''));

      const uniqueTimestamps = [];
      const seenRequestIds = new Set();
      for (const item of completed) {
        const rid = String(item.request_id || '');
        if (!rid || seenRequestIds.has(rid)) {
          continue;
        }
        const ts = Date.parse(item.timestamp || '');
        if (!Number.isFinite(ts)) {
          continue;
        }
        seenRequestIds.add(rid);
        uniqueTimestamps.push(ts);
      }

      if (uniqueTimestamps.length < 2) {
        return null;
      }

      const deltas = [];
      for (let i = 1; i < uniqueTimestamps.length; i += 1) {
        const deltaSec = Math.max(0, (uniqueTimestamps[i] - uniqueTimestamps[i - 1]) / 1000);
        if (deltaSec > 0) {
          deltas.push(deltaSec);
        }
      }
      if (deltas.length === 0) {
        return null;
      }

      const avgSec = deltas.reduce((sum, v) => sum + v, 0) / deltas.length;
      if (!Number.isFinite(avgSec) || avgSec <= 0) {
        return null;
      }
      return Math.max(1, Math.round((remaining * avgSec) / 60));
    }

    function renderPendingQueue(listenerActivity, progress, objectiveId, syncStatus = null, cadence = null) {
      if (!actionPendingEl) {
        return;
      }

      const total = Number(progress && progress.task_count);
      if (!Number.isFinite(total) || total <= 0) {
        actionPendingEl.textContent = 'Pending queue unavailable (task count unknown).';
        return;
      }

      const isMimAhead = Boolean(syncStatus && syncStatus.is_mim_ahead === true);
      if (isMimAhead) {
        const pendingSync = Number(syncStatus && syncStatus.pending_request_count);
        const requestTaskId = syncStatus && syncStatus.request_task_id ? String(syncStatus.request_task_id) : 'unknown';
        const resultReqId = syncStatus && syncStatus.result_request_id ? String(syncStatus.result_request_id) : 'unknown';
        const pendingLabel = Number.isFinite(pendingSync) && pendingSync > 0 ? pendingSync : 1;
        actionPendingEl.innerHTML =
          `<div class="action-pending-meta">Pending sync ${pendingLabel}: MIM has newer task requests not yet reflected in TOD results.</div>` +
          `<div class="action-pending-row">latest-mim-request: ${escapeHtml(requestTaskId)}</div>` +
          `<div class="action-pending-row">latest-tod-result: ${escapeHtml(resultReqId)}</div>`;
        return;
      }

      const completedEquivalent = Math.max(0, Number(progress && progress.completed_equivalent) || 0);
      const percent = Math.max(0, Math.min(100, Number(progress && progress.percent) || 0));
      const progressIndicatesDone = completedEquivalent >= total || percent >= 100;
      if (progressIndicatesDone) {
        if (cadence && cadence.beyondFunnel && cadence.recent) {
          actionPendingEl.innerHTML =
            `<div class="action-pending-meta">Base funnel complete (${Math.min(completedEquivalent, total)} / ${total}). Autonomous listener cadence still active.</div>` +
            `<div class="action-pending-row">latest cadence task: ${escapeHtml(cadence.taskId)}</div>` +
            `<div class="action-pending-row">MIM request: ${escapeHtml(cadence.requestAgeText)} ago &nbsp;|&nbsp; TOD result: ${escapeHtml(cadence.resultAgeText)} ago</div>`;
        } else {
          actionPendingEl.textContent = `No pending tasks in queue (objective complete: ${Math.min(completedEquivalent, total)} / ${total}).`;
        }
        return;
      }

      const all = listenerActivity && Array.isArray(listenerActivity.recent_entries)
        ? listenerActivity.recent_entries
        : [];

      const objectiveDigits = String(objectiveId || '').match(/(\d+)/);
      const objectiveToken = objectiveDigits ? objectiveDigits[1] : '';
      const scoped = objectiveToken
        ? all.filter(item => String(item && item.objective_id || '') === objectiveToken)
        : all;

      let latestTaskNumber = NaN;
      const latestInfo = parseRequestTaskInfo(listenerActivity && listenerActivity.latest_request_id);
      if (latestInfo && Number.isFinite(latestInfo.taskNumber)) {
        if (!objectiveToken || latestInfo.objective === objectiveToken) {
          latestTaskNumber = latestInfo.taskNumber;
        }
      }

      if (!Number.isFinite(latestTaskNumber)) {
        const taskNums = scoped
          .map(item => parseRequestTaskInfo(item && item.request_id))
          .filter(info => info && Number.isFinite(info.taskNumber) && (!objectiveToken || info.objective === objectiveToken))
          .map(info => info.taskNumber);
        if (taskNums.length > 0) {
          latestTaskNumber = Math.max(...taskNums);
        }
      }

      if (!Number.isFinite(latestTaskNumber)) {
        actionPendingEl.textContent = 'Pending queue will appear after first recognized task id (objective-XX-task-NNN).';
        return;
      }

      const start = latestTaskNumber + 1;
      if (start > total) {
        actionPendingEl.textContent = `No pending tasks in queue (last completed task ${latestTaskNumber} / ${total}).`;
        return;
      }

      const queue = [];
      const maxRows = 24;
      for (let i = start; i <= total && queue.length < maxRows; i += 1) {
        const taskNumText = String(i).padStart(3, '0');
        const prefix = objectiveToken ? `objective-${objectiveToken}` : 'objective-?';
        queue.push(`${prefix}-task-${taskNumText}`);
      }

      const pendingFromTaskIds = total - latestTaskNumber;
      const pendingFromProgress = Math.max(0, total - completedEquivalent);
      const pendingTotal = Math.min(pendingFromTaskIds, pendingFromProgress);
      if (pendingTotal <= 0) {
        actionPendingEl.textContent = `No pending tasks in queue (objective complete: ${Math.min(completedEquivalent, total)} / ${total}).`;
        return;
      }
      const hidden = Math.max(0, pendingTotal - queue.length);
      const metaText = hidden > 0
        ? `Pending ${pendingTotal}. Showing next ${queue.length}; ${hidden} additional tasks queued.`
        : `Pending ${pendingTotal}. Tasks are removed automatically as completions arrive.`;

      actionPendingEl.innerHTML = `<div class="action-pending-meta">${escapeHtml(metaText)}</div>` +
        queue.map(item => `<div class="action-pending-row">${escapeHtml(item)}</div>`).join('');
    }

    function renderExecutiveSummary(marker, progress, listenerActivity, recoveryWatchdog, syncStatus = null) {
      if (!todExecutiveSummaryEl) {
        return;
      }

      if (!marker) {
        const latestReq = listenerActivity && listenerActivity.latest_request_id
          ? String(listenerActivity.latest_request_id)
          : '';
        const latestExec = listenerActivity && listenerActivity.latest_execution_status
          ? String(listenerActivity.latest_execution_status)
          : 'unknown';
        const latestAge = listenerActivity && listenerActivity.latest_timestamp
          ? formatRelativeAge(String(listenerActivity.latest_timestamp))
          : 'n/a';
        if (latestReq) {
          todExecutiveSummaryEl.textContent = `Listener telemetry is active. Latest request ${latestReq} is ${latestExec} (updated ${latestAge}). Waiting for objective marker hydration from project state.`;
        } else {
          todExecutiveSummaryEl.textContent = 'Waiting for objective marker to build live summary.';
        }
        return;
      }

      const objectiveId = marker.objective_id || '?';
      const title = String(marker.title || '').trim();
      const percent = Math.max(0, Math.min(100, Number(progress && progress.percent) || 0));
      const totalTasks = Number(progress && progress.task_count) || 0;
      const completedEq = Number(progress && progress.completed_equivalent) || 0;
      const remaining = Math.max(0, totalTasks - completedEq);
      const cadence = buildCadenceSnapshot(listenerActivity, totalTasks);
      const scopedEntries = listenerActivity && Array.isArray(listenerActivity.recent_entries)
        ? listenerActivity.recent_entries.filter(item => String(item.objective_id || '') === String(objectiveId))
        : [];
      const etaMinutes = estimateMinutesRemaining(scopedEntries, totalTasks, completedEq);
      const etaText = etaMinutes === null
        ? 'ETA is stabilizing as more completions are sampled.'
        : (etaMinutes === 0
          ? 'ETA: objective queue is complete.'
          : `ETA: about ${etaMinutes} minute${etaMinutes === 1 ? '' : 's'} to finish at current pace.`);

      const resultStatus = String(listenerActivity && (listenerActivity.result_status || listenerActivity.latest_execution_status) || '').toLowerCase();
      const resultRequestId = String(listenerActivity && (listenerActivity.result_request_id || listenerActivity.latest_request_id) || '').trim();
      const resultGatePassed = listenerActivity && listenerActivity.result_review_gate_passed;
      const resultValidatorPassed = listenerActivity && listenerActivity.result_validator_passed;
      const integrationAlignment = String(listenerActivity && listenerActivity.result_integration_alignment_status || '').toLowerCase();
      const todObjective = String(listenerActivity && listenerActivity.result_tod_current_objective || '').trim();
      const mimObjective = String(listenerActivity && listenerActivity.result_mim_objective_active || '').trim();
      const validatorDetail = String(listenerActivity && (listenerActivity.result_validator_output || listenerActivity.result_validator_message) || '').trim();

      const watchdogState = String(recoveryWatchdog && recoveryWatchdog.state || 'unknown').toLowerCase();
      const healthText = resultStatus === 'failed'
        ? 'Reliability attention is required because the latest execution failed.'
        : (watchdogState === 'healthy'
          ? 'No reliability issues are currently detected.'
          : `Watchdog state is ${watchdogState}; monitoring for recovery actions.`);
      const purpose = title && title !== '(untitled objective)'
        ? `Project purpose: ${title}.`
        : 'Project purpose text is not populated for this objective yet.';

      if (resultStatus === 'failed') {
        const gateText = resultGatePassed === false ? 'Review gate failed.' : '';
        const validatorText = resultValidatorPassed === false ? 'Validator failed.' : '';
        const mismatchText = integrationAlignment === 'mismatch' && todObjective && mimObjective
          ? `Root cause: TOD reported objective ${todObjective} while MIM was on ${mimObjective}, so alignment checks failed.`
          : '';
        const validatorTextDetail = !mismatchText && validatorDetail
          ? `Detail: ${validatorDetail}.`
          : '';
        const fallbackText = !mismatchText && !validatorTextDetail
          ? 'Latest review-gate or validator checks failed for the current request.'
          : '';
        const requestText = resultRequestId
          ? `Latest request ${resultRequestId} failed.`
          : `Latest execution for objective ${objectiveId} failed.`;

        todExecutiveSummaryEl.textContent = [requestText, gateText, validatorText, mismatchText, validatorTextDetail, fallbackText, purpose, healthText]
          .filter(Boolean)
          .join(' ');
        return;
      }

      if (cadence && cadence.beyondFunnel && cadence.recent) {
        const syncText = syncStatus && syncStatus.is_mim_ahead
          ? `MIM is ahead by ${String(syncStatus.pending_request_count || 1)} task${Number(syncStatus.pending_request_count || 1) === 1 ? '' : 's'}.`
          : 'MIM and TOD are aligned on the latest cadence task.';
        todExecutiveSummaryEl.textContent = `Objective ${objectiveId} base funnel is complete, but autonomous listener cadence is still active. Latest task is ${cadence.taskId}; MIM request ${cadence.requestAgeText}; TOD result ${cadence.resultAgeText}. ${syncText} ${purpose} ${healthText}`;
        return;
      }

      todExecutiveSummaryEl.textContent = `TOD is working objective ${objectiveId} assigned by MIM. Progress is ${percent}% with ${remaining} tasks remaining out of ${totalTasks}. ${etaText} ${purpose} ${healthText}`;
    }

    function renderActionLiveStatus(listenerActivity, progress, recoveryWatchdog, syncStatus = null, cadenceHealth = null, mimProposal = null, mimProposalConflict = null, mimProposalArbitration = null, mimProposalMergePolicy = null, mimProposalAcknowledgment = null, mimProposalClosure = null) {
      if (!actionLiveStatusEl) return;

      const req = listenerActivity && listenerActivity.latest_request_id ? String(listenerActivity.latest_request_id) : '-';
      const exec = listenerActivity && listenerActivity.latest_execution_status ? String(listenerActivity.latest_execution_status) : '-';
      const gate = listenerActivity && listenerActivity.latest_review_gate_passed !== null && listenerActivity.latest_review_gate_passed !== undefined
        ? String(listenerActivity.latest_review_gate_passed)
        : '-';
      const validator = listenerActivity && listenerActivity.latest_validator_passed !== null && listenerActivity.latest_validator_passed !== undefined
        ? String(listenerActivity.latest_validator_passed)
        : '-';
      const age = listenerActivity ? formatRelativeAge(listenerActivity.latest_timestamp) : 'n/a';
      const source = progress && progress.source ? String(progress.source) : 'objective_status';
      const watchdog = recoveryWatchdog && recoveryWatchdog.available
        ? `${String(recoveryWatchdog.state || 'unknown')}`
        : 'n/a';
      const taskState = recoveryWatchdog && recoveryWatchdog.task_state
        ? String(recoveryWatchdog.task_state)
        : 'idle';
      const classification = recoveryWatchdog && recoveryWatchdog.progress_classification
        ? String(recoveryWatchdog.progress_classification)
        : 'no_progress_but_heartbeats_present';
      const hbAge = recoveryWatchdog && Number.isFinite(Number(recoveryWatchdog.heartbeat_age_seconds))
        ? String(recoveryWatchdog.heartbeat_age_seconds)
        : '-';
      const stallSec = recoveryWatchdog && Number.isFinite(Number(recoveryWatchdog.stall_threshold_seconds))
        ? String(recoveryWatchdog.stall_threshold_seconds)
        : '-';
      const ageSec = listenerActivity ? getIsoAgeSeconds(listenerActivity.latest_timestamp) : NaN;
      const stallThreshold = recoveryWatchdog && Number.isFinite(Number(recoveryWatchdog.stall_threshold_seconds))
        ? Number(recoveryWatchdog.stall_threshold_seconds)
        : NaN;
      const commState = Number.isFinite(ageSec) && Number.isFinite(stallThreshold)
        ? (ageSec > stallThreshold ? 'frozen' : 'active')
        : 'unknown';
      const syncText = syncStatus && syncStatus.is_mim_ahead
        ? `pending (${String(syncStatus.pending_request_count || 1)})`
        : 'aligned';
      const cadenceSeverity = cadenceHealth && cadenceHealth.available
        ? String(cadenceHealth.severity || 'unknown')
        : 'n/a';
      const cadenceP95 = cadenceHealth && cadenceHealth.available && cadenceHealth.cadence && Number.isFinite(Number(cadenceHealth.cadence.p95_sec))
        ? String(cadenceHealth.cadence.p95_sec)
        : '-';
      const cadenceRetryPct = cadenceHealth && cadenceHealth.available && cadenceHealth.cadence && Number.isFinite(Number(cadenceHealth.cadence.retry_rate))
        ? String(Math.round(Number(cadenceHealth.cadence.retry_rate) * 100))
        : '-';
      const proposalText = mimProposal && mimProposal.available
        ? ` | MIM ${String(mimProposal.priority || 'proposal')} ${String(mimProposal.task_id || '-')}: ${String(mimProposal.title || 'untitled proposal')}`
        : '';
      const proposalConflictText = mimProposalConflict && mimProposalConflict.available
        ? ` | proposal-${mimProposalConflict.conflict_detected ? 'conflict' : 'alignment'} ${String(mimProposalConflict.status || 'unknown')}: ${String(mimProposalConflict.summary || '-')}`
        : '';
      const proposalArbitrationText = mimProposalArbitration && mimProposalArbitration.available
        ? ` | arbitration ${String(mimProposalArbitration.status || 'unknown')} winner:${String(mimProposalArbitration.winner || 'unknown')}: ${String(mimProposalArbitration.summary || '-')}`
        : '';
      const proposalMergePolicyText = mimProposalMergePolicy && mimProposalMergePolicy.available
        ? ` | merge ${String(mimProposalMergePolicy.status || 'unknown')} mode:${String(mimProposalMergePolicy.mode || 'unknown')}: ${String(mimProposalMergePolicy.summary || '-')}`
        : '';
      const proposalAcknowledgmentText = mimProposalAcknowledgment && mimProposalAcknowledgment.available
        ? ` | ack ${String(mimProposalAcknowledgment.status || 'unknown')} disposition:${String(mimProposalAcknowledgment.disposition || 'unknown')}: ${String(mimProposalAcknowledgment.summary || '-')}`
        : '';
      const proposalClosureText = mimProposalClosure && mimProposalClosure.available
        ? ` | closure ${String(mimProposalClosure.status || 'unknown')} disposition:${String(mimProposalClosure.disposition || 'unknown')}: ${String(mimProposalClosure.summary || '-')}`
        : '';

      actionLiveStatusEl.textContent = `Live | comms ${commState} | state ${taskState} | class ${classification} | req ${req} | exec ${exec} | gate ${gate} | validator ${validator} | sync ${syncText} | cadence ${cadenceSeverity} p95:${cadenceP95}s retry:${cadenceRetryPct}% | update ${age} | hb ${hbAge}s/${stallSec}s | source ${source} | watchdog ${watchdog}${proposalText}${proposalConflictText}${proposalArbitrationText}${proposalMergePolicyText}${proposalAcknowledgmentText}${proposalClosureText}`;
    }

    function renderActionTimeline(listenerActivity, objectiveId) {
      if (!actionTimelineEl) return;

      const all = listenerActivity && Array.isArray(listenerActivity.recent_entries)
        ? listenerActivity.recent_entries
        : [];

      const scoped = objectiveId
        ? all.filter(e => String(e.objective_id || '') === String(objectiveId))
        : all;

      const items = scoped
        .slice()
        .sort((a, b) => Date.parse(b.timestamp || '') - Date.parse(a.timestamp || ''))
        .slice(0, 12);
      if (items.length === 0) {
        actionTimelineEl.textContent = 'No recent listener timeline yet.';
        return;
      }

      actionTimelineEl.innerHTML = items.map(item => {
        const ts = item.timestamp ? new Date(item.timestamp).toLocaleTimeString() : '--:--:--';
        const rid = escapeHtml(item.request_id || '-');
        const status = escapeHtml(item.execution_status || 'unknown');
        const gate = item.review_gate_passed === null || item.review_gate_passed === undefined ? '-' : String(item.review_gate_passed);
        const validator = item.validator_passed === null || item.validator_passed === undefined ? '-' : String(item.validator_passed);
        return `<div class="action-timeline-row"><span class="action-timeline-time">${ts}</span><span>${rid} | ${status} | gate:${gate} | validator:${validator}</span></div>`;
      }).join('');
    }

    async function fetchJsonSafe(url, options = undefined) {
      const res = await fetch(url, options);
      const raw = await res.text();
      let data = null;
      try {
        data = raw ? JSON.parse(raw) : {};
      } catch {
        data = { ok: false, error: raw || `Request failed (${res.status})` };
      }
      markTodActivity();
      return { res, data };
    }

    function buildPayload(forceReliability = false) {
      const action = forceReliability ? 'get-reliability' : document.getElementById('action').value;
      return {
        action,
        top: document.getElementById('top').value,
        category: document.getElementById('category').value,
        engine: document.getElementById('engine').value,
        configPath: document.getElementById('configPath').value
      };
    }

    function renderObjectiveOptions(options, selectedId) {
      const currentValue = objectiveSelectEl.value;
      objectiveSelectEl.innerHTML = '';

      const list = Array.isArray(options) ? options : [];
      if (list.length === 0) {
        const opt = document.createElement('option');
        opt.value = '';
        opt.textContent = 'No objectives';
        objectiveSelectEl.appendChild(opt);
        objectiveSelectEl.disabled = true;
        return;
      }

      objectiveSelectEl.disabled = false;
      for (const item of list) {
        const id = item.objective_id || '';
        const title = item.title || '(untitled)';
        const status = item.status || 'unknown';
        const opt = document.createElement('option');
        opt.value = id;
        opt.textContent = `${id} | ${title} [${status}]`;
        objectiveSelectEl.appendChild(opt);
      }

      const desired = selectedObjectiveId || selectedId || currentValue;
      if (desired && list.some(o => (o.objective_id || '') === desired)) {
        objectiveSelectEl.value = desired;
      } else {
        objectiveSelectEl.selectedIndex = 0;
      }
      selectedObjectiveId = objectiveSelectEl.value;
    }

    function renderTaskFunnel(funnel) {
      taskFunnelEl.innerHTML = '';
      const byStatus = funnel && funnel.by_status ? funnel.by_status : {};
      const total = funnel && Number.isFinite(Number(funnel.total)) ? Number(funnel.total) : 0;

      const header = document.createElement('span');
      header.className = 'pill';
      header.textContent = `total:${total}`;
      taskFunnelEl.appendChild(header);

      const keys = Object.keys(byStatus).sort();
      for (const key of keys) {
        const val = byStatus[key];
        const pill = document.createElement('span');
        pill.className = 'pill';
        pill.textContent = `${key}:${val}`;
        taskFunnelEl.appendChild(pill);
      }
    }

    async function loadProjectStatus() {
      try {
        const params = appendOperatorChatValidationHarness(new URLSearchParams());
        if (selectedObjectiveId) {
          params.set('objective_id', selectedObjectiveId);
        }
        const query = params.toString();
        const { res, data } = await fetchJsonSafe(`/api/project-status${query ? `?${query}` : ''}`);
        if (!res.ok || !data.ok) {
          if (res.status === 404) {
            throw new Error('Project status endpoint not found. Restart .\\scripts\\Start-TOD-UI.ps1 to load latest routes.');
          }
          throw new Error(data.error || `Project status request failed (${res.status})`);
        }

        renderObjectiveOptions(data.objective_options, data.selected_objective_id);
        renderTaskFunnel(data.task_funnel);

        const marker = synthesizeMarkerFromListener(
          data.marker || null,
          data.listener_activity || null,
          data.selected_objective_id || '',
          data.bridge_status || null
        );
        const progress = data.progress || {};
        const listenerActivity = data.listener_activity || null;
        const syncStatus = listenerActivity && listenerActivity.sync ? listenerActivity.sync : null;
        const recoveryWatchdog = data.recovery_watchdog || null;
        const cadenceHealth = data.cadence_health || null;
        const bridgeStatus = data.bridge_status || null;
        const selfHealthMaintenance = data.self_health_maintenance || null;
        const engineeringSignal = data.engineering_signal || null;
        const steadyState = data.steady_state || null;
        const dataSources = data.data_sources || null;
        const voiceAdapter = data.voice_adapter || null;
        const mimProposal = data.mim_proposal || null;
        const mimProposalConflict = data.mim_proposal_conflict || null;
        const mimProposalArbitration = data.mim_proposal_arbitration || null;
        const mimProposalMergePolicy = data.mim_proposal_merge_policy || null;
        const mimProposalAcknowledgment = data.mim_proposal_acknowledgment || null;
        const mimProposalClosure = data.mim_proposal_closure || null;
        renderCadenceHealthChip(cadenceHealth);
        renderCadenceDetailSurface(cadenceHealth);
        renderSteadyStateChip(steadyState);
        renderRegressionChip(steadyState);
        renderRequestChip(listenerActivity);
        renderBridgeStatus(bridgeStatus);
        renderMaintenanceStatus(selfHealthMaintenance);
        renderVoiceChip(voiceAdapter);
        renderVoiceAdapterPanel(voiceAdapter);
        lastKnownTaskState = recoveryWatchdog && recoveryWatchdog.task_state
          ? String(recoveryWatchdog.task_state)
          : 'idle';
        renderActionLiveStatus(listenerActivity, progress, recoveryWatchdog, syncStatus, cadenceHealth, mimProposal, mimProposalConflict, mimProposalArbitration, mimProposalMergePolicy, mimProposalAcknowledgment, mimProposalClosure);
        const percent = Number(progress.percent) || 0;
        const status = marker && marker.status ? marker.status : 'unknown';
        const objectiveId = marker && marker.objective_id ? marker.objective_id : '';
        const taskCount = Number(progress.task_count) || 0;
        const cadence = buildCadenceSnapshot(listenerActivity, taskCount);
        renderProgressDual(progress, cadence, listenerActivity, objectiveId);
        renderObjectiveDetailSurface(marker, progress);
        renderActionTimeline(listenerActivity, objectiveId);
        renderPendingQueue(listenerActivity, progress, objectiveId, syncStatus, cadence);
        setProgressRing(percent, status, cadence);
        const trendHtml = formatTrend(percent);
        renderExecutiveSummary(marker, progress, listenerActivity, recoveryWatchdog, syncStatus);

        if (engineeringSignal && engineeringSignal.current_engineering_loop_status) {
          const approval = engineeringSignal.pending_approval_state || {};
          const pendingLabel = approval.pending ? `pending:${Number(approval.count) || 0}` : 'pending:0';
          const stopReason = engineeringSignal.stop_reason || 'none';
          const topPenalty = Array.isArray(engineeringSignal.top_penalties) && engineeringSignal.top_penalties.length > 0
            ? (engineeringSignal.top_penalties[0].name || engineeringSignal.top_penalties[0].code || 'penalty')
            : 'none';
          engineeringSignalMetaEl.textContent = `Engineering signal | status:${engineeringSignal.current_engineering_loop_status} | band:${engineeringSignal.latest_maturity_band || 'early'} | trend:${engineeringSignal.trend_direction || 'flat'} | ${pendingLabel} | stop:${stopReason} | top-penalty:${topPenalty}`;
        } else {
          engineeringSignalMetaEl.textContent = 'Engineering signal unavailable';
        }

        if (!marker) {
          projectMetaEl.innerHTML = `No current objective marker available. ${trendHtml}`;
          return;
        }

        const title = marker.title || '(untitled objective)';
        const remoteId = marker.remote_objective_id ? ` | MIM ${marker.remote_objective_id}` : '';
        const syncLine = syncStatus && syncStatus.is_mim_ahead
          ? `<br>Sync: pending (${escapeHtml(String(syncStatus.pending_request_count || 1))}) | MIM:${escapeHtml(String(syncStatus.request_task_id || '-'))} | TOD:${escapeHtml(String(syncStatus.result_request_id || '-'))}`
          : '<br>Sync: aligned (MIM and TOD request streams match)';
        const cadenceLine = cadence && cadence.recent
          ? `<br>Live Cadence: ${escapeHtml(cadence.beyondFunnel ? 'active beyond base funnel' : 'active')} | latest:${escapeHtml(cadence.taskId)} | MIM:${escapeHtml(cadence.requestAgeText)} | TOD:${escapeHtml(cadence.resultAgeText)}`
          : '';
        const progressSource = progress.source ? ` | Source: ${escapeHtml(progress.source)}` : '';
        const recoveryLine = recoveryWatchdog && recoveryWatchdog.available && recoveryWatchdog.state !== 'healthy'
          ? `<br>Watchdog: ${escapeHtml(recoveryWatchdog.state)} | issue:${escapeHtml(recoveryWatchdog.last_issue || '-')}`
          : '';
        const steadyStateLine = steadyState && steadyState.available
          ? `<br>Steady State: ${escapeHtml(String(steadyState.status || 'unknown'))} | ${escapeHtml(String(steadyState.summary || '-'))}`
          : '';
        const cadenceHealthLine = cadenceHealth && cadenceHealth.available
          ? `<br>Cadence Health: ${escapeHtml(String(cadenceHealth.severity || 'unknown'))} | p95:${escapeHtml(String((cadenceHealth.cadence && cadenceHealth.cadence.p95_sec !== undefined) ? cadenceHealth.cadence.p95_sec : '-'))}s | idle:${escapeHtml(String((cadenceHealth.stream && cadenceHealth.stream.loop_idle_sec !== undefined) ? cadenceHealth.stream.loop_idle_sec : '-'))}s | retry:${escapeHtml(String(Math.round((Number(cadenceHealth.cadence && cadenceHealth.cadence.retry_rate) || 0) * 100)))}%`
          : '';
        const sourceLine = dataSources && dataSources.project_status_mode
          ? `<br>Data Sources: ${escapeHtml(String(dataSources.project_status_mode))}${dataSources.state_warning ? ` | ${escapeHtml(String(dataSources.state_warning))}` : ''}`
          : '';
        const taskStateLine = recoveryWatchdog && recoveryWatchdog.available
          ? `<br>Task State: ${escapeHtml(recoveryWatchdog.task_state || 'idle')} | class:${escapeHtml(recoveryWatchdog.progress_classification || 'no_progress_but_heartbeats_present')}` +
            ` | hb:${escapeHtml(String(recoveryWatchdog.heartbeat_age_seconds ?? '-'))}s/${escapeHtml(String(recoveryWatchdog.stall_threshold_seconds ?? '-'))}s` +
            ` | recoveries:${escapeHtml(String(recoveryWatchdog.recovery_attempts ?? 0))} | freezes:${escapeHtml(String(recoveryWatchdog.consecutive_freezes ?? 0))}`
          : '';
        const listenerLine = listenerActivity && listenerActivity.latest_request_id
          ? `<br>Listener: ${escapeHtml(listenerActivity.latest_request_id)} | exec:${escapeHtml(listenerActivity.latest_execution_status || '-')}` +
            ` | gate:${String(listenerActivity.latest_review_gate_passed)}` +
            ` | validator:${String(listenerActivity.latest_validator_passed)}`
          : '';
        const statusText = syncStatus && syncStatus.is_mim_ahead
          ? `${status} (sync pending)`
          : (cadence && cadence.beyondFunnel && cadence.recent ? `${status} (live cadence active)` : status);
        const progressHeadline = cadence && cadence.beyondFunnel && cadence.recent
          ? `Base Funnel: ${taskCount}/${taskCount} | Live Task: ${escapeHtml(String(cadence.taskNumber || '-'))} (active)`
          : `Progress: ${percent}%`;
        projectMetaEl.innerHTML = `<strong>${title}</strong><br>ID: ${objectiveId}${remoteId}<br>Status: ${statusText} | Tasks: ${taskCount} | ${progressHeadline} ${trendHtml}${progressSource}${cadenceLine}${syncLine}${steadyStateLine}${sourceLine}${taskStateLine}${listenerLine}${cadenceHealthLine}${recoveryLine}`;
      } catch (err) {
        renderCadenceHealthChip(null);
        renderCadenceDetailSurface(null);
        renderSteadyStateChip(null);
        renderRegressionChip(null);
        renderBridgeStatus(null);
        renderMaintenanceStatus(null);
        renderRequestChip(null);
        renderVoiceChip(null);
        renderVoiceAdapterPanel(null);
        renderObjectiveDetailSurface(null, null);
        renderActionLiveStatus(null, null, null, null, null, null, null, null, null, null, null);
        projectMetaEl.textContent = err.message;
        try {
          const { res, data } = await fetchJsonSafe('/api/task-state');
          if (res.ok && data && data.ok) {
            const fallbackListener = {
              latest_request_id: data.latest_request_id || '',
              latest_execution_status: data.latest_execution_status || '',
              latest_timestamp: data.generated_at || ''
            };
            const fallbackProgress = {
              source: 'task_state_fallback',
              percent: 0,
              task_count: 0,
              completed_equivalent: 0
            };
            const fallbackWatchdog = {
              available: true,
              state: data.watchdog_state || 'unknown',
              task_state: data.current_state || 'idle',
              progress_classification: data.progress_classification || 'no_progress_but_heartbeats_present',
              heartbeat_age_seconds: Number.isFinite(Number(data.heartbeat_age_seconds)) ? Number(data.heartbeat_age_seconds) : -1,
              stall_threshold_seconds: Number.isFinite(Number(data.stall_threshold_seconds)) ? Number(data.stall_threshold_seconds) : -1,
              recovery_attempts: Number.isFinite(Number(data.recovery_attempts)) ? Number(data.recovery_attempts) : 0,
              consecutive_freezes: Number.isFinite(Number(data.consecutive_freezes)) ? Number(data.consecutive_freezes) : 0
            };

            renderRequestChip(fallbackListener);
            renderActionLiveStatus(fallbackListener, fallbackProgress, fallbackWatchdog);
            const markerFromTaskState = synthesizeMarkerFromListener(null, fallbackListener, '', null);
            renderObjectiveDetailSurface(markerFromTaskState, fallbackProgress);
            renderExecutiveSummary(markerFromTaskState, fallbackProgress, fallbackListener, fallbackWatchdog, null);

            if (fallbackListener.latest_request_id) {
              projectMetaEl.innerHTML = `Live fallback: request ${escapeHtml(String(fallbackListener.latest_request_id))} | exec ${escapeHtml(String(fallbackListener.latest_execution_status || '-'))} | watchdog ${escapeHtml(String(fallbackWatchdog.state || 'unknown'))}`;
            }
          }
        } catch {
          // Keep primary error text when fallback cannot be loaded.
        }
      }
    }

    async function run(payload) {
      runBtn.disabled = true;
      refreshBtn.disabled = true;
      setStatus('Running action...');

      try {
        const { res, data } = await fetchJsonSafe('/api/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Request failed (${res.status})`);
        }

        outputEl.textContent = JSON.stringify(data.result, null, 2);
        setStatus(`Done: ${payload.action}`);
      } catch (err) {
        setStatus(err.message, true);
      } finally {
        runBtn.disabled = false;
        refreshBtn.disabled = false;
      }
    }

    async function loadShareArtifacts() {
      refreshShareBtn.disabled = true;
      try {
        const { res, data } = await fetchJsonSafe('/api/share-artifacts');
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Share artifacts request failed (${res.status})`);
        }

        const artifacts = Array.isArray(data.artifacts) ? data.artifacts : [];
        if (artifacts.length === 0) {
          shareLinksEl.textContent = 'No share artifacts configured.';
          shareMetaEl.textContent = 'No share artifacts available.';
          return;
        }

        shareLinksEl.innerHTML = artifacts.map((item) => {
          const exists = item && item.exists === true;
          const title = escapeHtml(item && item.label ? item.label : (item && item.key ? item.key : 'artifact'));
          const fullPath = escapeHtml(item && item.path ? item.path : '');
          const updated = escapeHtml(item && item.last_write_time_utc ? item.last_write_time_utc : 'missing');
          const sizeText = Number.isFinite(Number(item && item.length)) ? `${Number(item.length)} bytes` : 'n/a';
          const downloadHref = escapeHtml(item && item.download_url ? item.download_url : '#');
          const openHref = escapeHtml(item && item.preview_url ? item.preview_url : (item && item.download_url ? item.download_url : '#'));

          if (!exists) {
            return `
              <div class="share-row">
                <div class="share-title">${title}</div>
                <div class="share-path">${fullPath}</div>
                <div class="share-actions">missing (generate/refresh needed)</div>
              </div>
            `;
          }

          return `
            <div class="share-row">
              <div class="share-title">${title}</div>
              <div class="share-path">${fullPath}</div>
              <div class="share-actions">
                <a href="${downloadHref}" download>download</a>
                <a href="${openHref}" target="_blank" rel="noopener">open</a>
                <span>updated: ${updated}</span>
                <span>size: ${sizeText}</span>
              </div>
            </div>
          `;
        }).join('');

        const generatedAt = data.generated_at ? new Date(data.generated_at).toLocaleString() : 'unknown';
        shareMetaEl.textContent = `Loaded ${artifacts.length} artifacts at ${generatedAt}`;
      } catch (err) {
        shareMetaEl.textContent = err.message;
        shareLinksEl.textContent = 'Unable to load share artifact links.';
      } finally {
        refreshShareBtn.disabled = false;
      }
    }

    function setStateBusValue(el, value, fallback = '-') {
      el.textContent = (value === undefined || value === null || String(value).trim() === '') ? fallback : String(value);
    }

    function setConfidenceValue(el, value) {
      el.classList.remove('conf-high', 'conf-medium', 'conf-low');
      el.classList.remove('has-tip');
      const numeric = Number(value);
      if (!Number.isFinite(numeric)) {
        el.textContent = '-';
        el.title = 'Confidence unavailable for this section.';
        return;
      }

      el.textContent = numeric.toFixed(2);
      el.classList.add('has-tip');
      if (numeric >= 0.85) {
        el.classList.add('conf-high');
        el.title = `High confidence (${numeric.toFixed(2)}). Threshold: >= 0.85.`;
        return;
      }
      if (numeric >= 0.65) {
        el.classList.add('conf-medium');
        el.title = `Medium confidence (${numeric.toFixed(2)}). Threshold: 0.65-0.84.`;
        return;
      }
      el.classList.add('conf-low');
      el.title = `Low confidence (${numeric.toFixed(2)}). Threshold: < 0.65.`;
    }

    function enrichConfidenceTooltip(el, value, contextText) {
      const numeric = Number(value);
      if (!Number.isFinite(numeric)) {
        el.title = 'Confidence unavailable for this section.';
        return;
      }

      const bandText = numeric >= 0.85
        ? 'High confidence'
        : (numeric >= 0.65 ? 'Medium confidence' : 'Low confidence');
      const detail = contextText && String(contextText).trim() !== ''
        ? ` Context: ${String(contextText)}.`
        : '';
      el.title = `${bandText} (${numeric.toFixed(2)}).${detail} Thresholds: high >= 0.85, medium 0.65-0.84, low < 0.65.`;
    }

    function renderBusList(el, items, mapFn, emptyText) {
      const list = Array.isArray(items) ? items : [];
      if (list.length === 0) {
        el.textContent = emptyText;
        return;
      }
      el.innerHTML = list.map(mapFn).join('<br>');
    }

    function renderScoreSparkline(el, scorecards) {
      const list = Array.isArray(scorecards) ? scorecards : [];
      if (!el) {
        return;
      }
      if (list.length < 2) {
        el.innerHTML = '<text x="8" y="38">No score trend yet.</text>';
        return;
      }

      const values = list
        .map(item => Number(item && item.score))
        .filter(value => Number.isFinite(value))
        .reverse();
      if (values.length < 2) {
        el.innerHTML = '<text x="8" y="38">No score trend yet.</text>';
        return;
      }

      const width = 260;
      const height = 70;
      const padX = 8;
      const padY = 8;
      const innerW = width - (padX * 2);
      const innerH = height - (padY * 2);
      const count = values.length;
      const stepX = count > 1 ? (innerW / (count - 1)) : innerW;

      const points = values.map((value, idx) => {
        const clamped = Math.max(0, Math.min(1, value));
        const x = padX + (idx * stepX);
        const y = padY + ((1 - clamped) * innerH);
        return { x, y };
      });

      const line = points
        .map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(2)},${p.y.toFixed(2)}`)
        .join(' ');
      const fill = `${line} L${(padX + innerW).toFixed(2)},${(padY + innerH).toFixed(2)} L${padX.toFixed(2)},${(padY + innerH).toFixed(2)} Z`;
      const first = values[0].toFixed(2);
      const last = values[values.length - 1].toFixed(2);

      el.innerHTML = `
        <path class="fill" d="${fill}"></path>
        <path class="series" d="${line}"></path>
        <text x="8" y="12">oldest ${first}</text>
        <text x="194" y="12">latest ${last}</text>
      `;
    }

    async function runQueryConsole(action, label) {
      const outputEl = document.getElementById('queryOutput');
      const metaEl = document.getElementById('queryMeta');
      outputEl.textContent = `Running ${label}...`;
      metaEl.textContent = '';
      const btns = document.querySelectorAll('.btn-query');
      btns.forEach(b => { b.disabled = true; });
      try {
        const payload = {
          action,
          top: document.getElementById('top').value,
          category: document.getElementById('category').value,
          engine: document.getElementById('engine').value,
          configPath: document.getElementById('configPath').value
        };
        const { res, data } = await fetchJsonSafe('/api/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        if (!res.ok || !data.ok) {
          outputEl.textContent = data.error || `Query failed (${res.status})`;
          return;
        }
        const result = data.result;
        outputEl.textContent = typeof result === 'object' ? JSON.stringify(result, null, 2) : String(result);
        metaEl.textContent = `${label} snapshot at ${new Date().toLocaleTimeString()}`;
      } catch (err) {
        outputEl.textContent = `Error: ${err.message}`;
      } finally {
        btns.forEach(b => { b.disabled = false; });
      }
    }

    function setOperatorChatMeta(message, isError = false) {
      if (!operatorChatMetaEl) {
        return;
      }
      operatorChatMetaEl.textContent = message;
      operatorChatMetaEl.classList.toggle('error', isError);
    }

    function formatOperatorChatIntentLabel(intent) {
      return String(intent || 'summarize_status').replace(/_/g, ' ');
    }

    function formatOperatorChatActionLabel(action) {
      return String(action || 'action').replace(/-/g, ' ');
    }

    function getOperatorChatAuditFilterState(overrides = {}) {
      return {
        ...operatorChatAuditFilters,
        ...overrides
      };
    }

    function applyOperatorChatAuditFilterState(filters) {
      operatorChatAuditFilters = getOperatorChatAuditFilterState(filters);
      if (operatorChatAuditSearchEl) {
        operatorChatAuditSearchEl.value = operatorChatAuditFilters.search || '';
      }
      if (operatorChatAuditActionFilterEl) {
        operatorChatAuditActionFilterEl.value = operatorChatAuditFilters.action || '';
      }
      if (operatorChatAuditOutcomeFilterEl) {
        operatorChatAuditOutcomeFilterEl.value = operatorChatAuditFilters.outcomeStatus || '';
      }
      if (operatorChatAuditPhaseFilterEl) {
        operatorChatAuditPhaseFilterEl.value = operatorChatAuditFilters.phase || '';
      }
    }

    function populateOperatorChatAuditActionFilter(entries) {
      if (!operatorChatAuditActionFilterEl) {
        return;
      }
      const currentValue = operatorChatAuditFilters.action || '';
      const knownActions = new Set(Array.from(GetCapabilitiesSafeAuditActions()));
      (Array.isArray(entries) ? entries : []).forEach((item) => {
        const action = String(item && item.action || '').trim();
        if (action) {
          knownActions.add(action);
        }
      });
      const options = ['<option value="">All Actions</option>'];
      Array.from(knownActions).sort().forEach((action) => {
        options.push(`<option value="${escapeHtml(action)}">${escapeHtml(formatOperatorChatActionLabel(action))}</option>`);
      });
      operatorChatAuditActionFilterEl.innerHTML = options.join('');
      operatorChatAuditActionFilterEl.value = currentValue;
    }

    function GetCapabilitiesSafeAuditActions() {
      return new Set([
        'get-reliability',
        'get-state-bus',
        'get-engineering-loop-summary',
        'get-engineering-signal',
        'show-reliability-dashboard',
        'refresh-share-links',
        'quick-refresh-reliability',
        'refresh-project-status',
        'recheck-bridge-diagnostics',
        'refresh-governance-snapshot',
        'refresh-bridge-alignment-bundle',
        'wait'
      ]);
    }

    function getOperatorChatResponseFlags(response) {
      const flags = Array.isArray(response && response.flags) ? response.flags : [];
      return flags.map((item) => {
        const key = String(item || '').trim().toLowerCase();
        switch (key) {
          case 'listener_telemetry_fallback':
            return {
              key,
              label: 'listener fallback',
              tone: 'notice',
              title: 'Dashboard is using listener telemetry fallback because full state.json is too large or unavailable.'
            };
          case 'recent_completion_baseline_fallback':
            return {
              key,
              label: 'baseline fallback',
              tone: 'warning',
              title: 'Requested last-successful-completion baseline was unavailable, so operator chat used a bounded recent-time window.'
            };
          case 'observe_before_act':
            return {
              key,
              label: 'observe before act',
              tone: 'notice',
              title: 'Use bounded read-only refresh steps before considering intervention.'
            };
          case 'action_succeeded':
            return {
              key,
              label: 'action succeeded',
              tone: '',
              title: 'The governed action completed successfully.'
            };
          case 'action_blocked':
            return {
              key,
              label: 'action blocked',
              tone: 'warning',
              title: 'The governed action was blocked by policy.'
            };
          case 'action_failed':
            return {
              key,
              label: 'action failed',
              tone: 'warning',
              title: 'The governed action failed during execution.'
            };
          case 'action_invalid_preview':
            return {
              key,
              label: 'invalid preview',
              tone: 'warning',
              title: 'The confirmation request did not match a live unconsumed preview.'
            };
          case 'action_invalid_request':
            return {
              key,
              label: 'invalid request',
              tone: 'warning',
              title: 'The governed action request did not satisfy the confirmation contract.'
            };
          case 'active_operator_commitment':
            return {
              key,
              label: 'active commitment',
              tone: 'notice',
              title: 'An operator commitment is already active for this objective.'
            };
          case 'mim_proposal_conflict_detected':
            return {
              key,
              label: 'proposal conflict',
              tone: 'warning',
              title: 'The live MIM proposal does not fully align with the current TOD objective or bridge posture.'
            };
          case 'mim_proposal_arbitrated':
            return {
              key,
              label: 'proposal arbitrated',
              tone: 'notice',
              title: 'TOD computed a bounded arbitration posture for the live MIM proposal.'
            };
          case 'mim_proposal_tod_priority':
            return {
              key,
              label: 'tod priority',
              tone: 'warning',
              title: 'Current arbitration keeps TOD priority until proposal evidence is revalidated.'
            };
          case 'mim_proposal_shared_priority':
            return {
              key,
              label: 'shared priority',
              tone: 'notice',
              title: 'Current arbitration treats the live MIM proposal as aligned context rather than a separate competing lane.'
            };
          case 'mim_proposal_merge_policy_available':
            return {
              key,
              label: 'merge policy',
              tone: 'notice',
              title: 'TOD computed a bounded merge policy for the live MIM proposal.'
            };
          case 'mim_proposal_merge_ready':
            return {
              key,
              label: 'merge ready',
              tone: 'notice',
              title: 'The live MIM proposal can be merged as bounded context for the current TOD objective.'
            };
          case 'mim_proposal_merge_deferred':
            return {
              key,
              label: 'merge deferred',
              tone: 'warning',
              title: 'The live MIM proposal should stay separate until bounded revalidation resolves the current posture.'
            };
          case 'mim_proposal_acknowledged':
            return {
              key,
              label: 'proposal acknowledged',
              tone: 'notice',
              title: 'TOD computed an explicit acknowledgment posture for the live MIM proposal.'
            };
          case 'mim_proposal_absorbed':
            return {
              key,
              label: 'proposal absorbed',
              tone: 'notice',
              title: 'TOD currently absorbs the live MIM proposal as bounded context for the active objective.'
            };
          case 'mim_proposal_ack_deferred':
            return {
              key,
              label: 'proposal deferred',
              tone: 'warning',
              title: 'TOD acknowledges the live MIM proposal but keeps it separate pending bounded revalidation.'
            };
          case 'mim_proposal_rejected':
            return {
              key,
              label: 'proposal rejected',
              tone: 'warning',
              title: 'TOD currently rejects the live MIM proposal as active context because bounded alignment checks still fail.'
            };
          case 'mim_proposal_closure_available':
            return {
              key,
              label: 'proposal closure',
              tone: 'notice',
              title: 'TOD derived proposal lifecycle status from governed audit and commitment history.'
            };
          case 'mim_proposal_open':
            return {
              key,
              label: 'proposal open',
              tone: 'notice',
              title: 'The live MIM proposal is still open and has not reached a terminal outcome.'
            };
          case 'mim_proposal_fulfilled':
            return {
              key,
              label: 'proposal fulfilled',
              tone: 'notice',
              title: 'The proposal reached a satisfied commitment outcome.'
            };
          case 'mim_proposal_abandoned':
            return {
              key,
              label: 'proposal abandoned',
              tone: 'warning',
              title: 'The latest proposal-linked commitment ended abandoned.'
            };
          case 'mim_proposal_superseded':
            return {
              key,
              label: 'proposal superseded',
              tone: 'warning',
              title: 'A newer proposal for the same objective superseded the earlier proposal before terminal completion.'
            };
          case 'mim_proposal_withdrawn':
            return {
              key,
              label: 'proposal withdrawn',
              tone: 'warning',
              title: 'The proposal is no longer live and no terminal commitment outcome was recorded.'
            };
          case 'operator_commitment_scope_shifted':
            return {
              key,
              label: 'commitment scope shifted',
              tone: 'warning',
              title: 'The latest operator commitment no longer matches the current objective, harness, or proposal posture.'
            };
          default:
            return {
              key,
              label: key.replace(/_/g, ' '),
              tone: '',
              title: key.replace(/_/g, ' ')
            };
        }
      });
    }

    function getOperatorChatCitationMeta(section, field) {
      const sectionKey = String(section || '').trim();
      const fieldKey = String(field || '').trim();

      const cardOnly = (cardId, cardLabel) => ({ cardId, cardLabel, targetId: cardId, targetLabel: cardLabel, field: fieldKey });
      const pointTo = (cardId, cardLabel, targetId, targetLabel) => ({ cardId, cardLabel, targetId, targetLabel, field: fieldKey });

      switch (sectionKey) {
        case 'marker':
          switch (fieldKey) {
            case 'objective_id':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'objectiveMarkerId', 'Objective ID');
            case 'status':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'objectiveMarkerStatus', 'Objective Status');
            case 'title':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'objectiveMarkerTitle', 'Objective Title');
            default:
              return cardOnly('projectMarkerCard', 'Current Project Marker');
          }
        case 'progress':
          switch (fieldKey) {
            case 'percent':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'progressPct', 'Progress Ring');
            default:
              return cardOnly('projectMarkerCard', 'Current Project Marker');
          }
        case 'steady_state':
          switch (fieldKey) {
            case 'status':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'steadyStateChip', 'Steady State');
            default:
              return cardOnly('projectMarkerCard', 'Current Project Marker');
          }
        case 'cadence_health':
          switch (fieldKey) {
            case 'severity':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'cadenceSeverityDetail', 'Cadence Severity');
            case 'governance.adjusted_severity':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'cadenceGovernanceSeverityDetail', 'Governance Severity');
            case 'stream.loop_idle_sec':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'cadenceIdleDetail', 'Loop Idle');
            case 'cadence.p95_sec':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'cadenceP95Detail', 'p95 Cycle');
            case 'cadence.retry_rate':
              return pointTo('projectMarkerCard', 'Current Project Marker', 'cadenceRetryDetail', 'Retry Rate');
            default:
              return cardOnly('projectMarkerCard', 'Current Project Marker');
          }
        case 'bridge_status':
          switch (fieldKey) {
            case 'status':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeHealth', 'Bridge Health');
            case 'status_reason':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeObjectiveDetail', 'Bridge Status Reason');
            case 'summary':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeStatusSummary', 'Bridge Summary');
            case 'canonical_mim_objective_id':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeCanonicalObjective', 'Canonical Objective');
            case 'task_request_objective_id':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeLiveObjective', 'Live Task Objective');
            case 'objective_mismatch':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeObjectiveSync', 'Objective Sync');
            case 'objective_mismatch_detail':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeObjectiveDetail', 'Mismatch Detail');
            case 'listener_cycle_age_seconds':
            case 'listener_fresh_threshold_seconds':
            case 'listener_freshness_state':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeHeartbeat', 'Listener Heartbeat');
            case 'sequence_state':
            case 'artifact_completeness':
            case 'missing_artifacts':
              return pointTo('bridgeStatusCard', 'Bridge Status', 'bridgeStatusSummary', 'Bridge Summary');
            default:
              return cardOnly('bridgeStatusCard', 'Bridge Status');
          }
        case 'self_health_maintenance':
          switch (fieldKey) {
            case 'overall_status':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceStatus', 'Maintenance Status');
            case 'overall_severity':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceSeverity', 'Maintenance Severity');
            case 'severity_reason':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceReason', 'Maintenance Reason');
            case 'invocation_mode':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceInvocation', 'Invocation Mode');
            case 'history.scheduled_fallback_runs_including_current':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceScheduledFallback', 'Scheduled Fallback');
            case 'history.window_hours':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceThresholdWindow', 'Threshold Window');
            case 'source_severity':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceSourceSeverity', 'Maintenance Source Severity');
            case 'generated_at':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceGeneratedAt', 'Last Report');
            case 'summary':
              return pointTo('maintenanceStatusCard', 'Maintenance Status', 'maintenanceSummary', 'Maintenance Summary');
            default:
              return cardOnly('maintenanceStatusCard', 'Maintenance Status');
          }
        case 'recovery_watchdog':
        case 'listener_activity':
          switch (fieldKey) {
            case 'latest_request_id':
            case 'summary':
              return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
            default:
              return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionTimeline', 'Action Timeline');
          }
        case 'mim_proposal':
          return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
        case 'mim_proposal_conflict':
          return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
        case 'mim_proposal_arbitration':
          return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
        case 'mim_proposal_merge_policy':
          return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
        case 'mim_proposal_acknowledgment':
          return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
        case 'mim_proposal_closure':
          return pointTo('actionWorkspaceCard', 'Action Workspace', 'actionLiveStatus', 'Action Live Status');
        case 'operator_action_audit':
          return pointTo('operatorChatCard', 'TOD Operator Chat', 'operatorChatAuditList', 'Governed Action Audit');
        case 'operator_action_reasoning':
          return pointTo('operatorChatCard', 'TOD Operator Chat', 'operatorChatThread', 'Operator Reasoning');
        case 'operator_commitment':
          return pointTo('operatorChatCard', 'TOD Operator Chat', 'operatorChatCommitmentList', 'Operator Commitments');
        default:
          return cardOnly('operatorChatCard', 'TOD Operator Chat');
      }
    }

    function appendOperatorChatUserEntry(text) {
      if (!operatorChatThreadEl) {
        return;
      }
      const entry = document.createElement('div');
      entry.className = 'operator-chat-entry user';
      entry.innerHTML = `
        <div class="operator-chat-role">Operator</div>
        <div class="operator-chat-bubble">${escapeHtml(text)}</div>
      `;
      operatorChatThreadEl.appendChild(entry);
      operatorChatThreadEl.scrollTop = operatorChatThreadEl.scrollHeight;
    }

    function buildOperatorChatCitationButton(section, field, className = 'operator-chat-citation-btn') {
      const meta = getOperatorChatCitationMeta(section, field);
      return `<button class="${escapeHtml(className)}" type="button" data-chat-citation-target="${escapeHtml(meta.targetId || meta.cardId)}" title="${escapeHtml(section)} :: ${escapeHtml(field)}">${escapeHtml(meta.targetLabel || meta.cardLabel)}</button>`;
    }

    function appendOperatorChatValidationHarness(params) {
      const query = params instanceof URLSearchParams ? params : new URLSearchParams();
      if (OPERATOR_CHAT_VALIDATION_HARNESS) {
        query.set('validation_harness', OPERATOR_CHAT_VALIDATION_HARNESS);
      }
      return query;
    }

    function buildOperatorChatEvidenceRows(evidence) {
      const items = Array.isArray(evidence) ? evidence : [];
      if (items.length === 0) {
        return '<div class="operator-chat-evidence-row"><span class="k">Evidence</span><span class="v">No structured evidence available.</span></div>';
      }

      return `<div class="operator-chat-evidence-grid">${items.map(item => `
        <div class="operator-chat-evidence-row">
          <div class="operator-chat-evidence-head"><span class="k">${escapeHtml(item.label || 'evidence')}</span></div>
          <span class="v">${escapeHtml(item.value || '-')}</span>
          ${buildOperatorChatCitationButton(String(item.section || 'section'), String(item.field || 'field'), 'operator-chat-evidence-jump')}
        </div>
      `).join('')}</div>`;
    }

    function buildOperatorChatSuggestedActionButtons(actions, options = {}) {
      const items = Array.isArray(actions) ? actions : [];
      if (items.length === 0) {
        return '';
      }

      const intent = String(options.intent || '');
      const query = String(options.query || '');
      const objectiveId = String(options.objectiveId || selectedObjectiveId || '');
      return `<div class="operator-chat-actions">${items.map((item) => {
        const action = String(item.action || '');
        const label = String(item.label || formatOperatorChatActionLabel(action));
        const reason = String(item.reason || '');
        const mode = String(item.mode || 'read_only');
        const proposalSource = String(item.proposal_source || '').trim();
        const proposalId = String(item.proposal_id || '').trim();
        const proposalObjectiveId = String(item.proposal_objective_id || '').trim();
        const proposalPriority = String(item.proposal_priority || '').trim();
        const proposalTitle = String(item.proposal_title || '').trim();
        const proposalSummary = String(item.proposal_summary || '').trim();
        const proposalConflictStatus = String(item.proposal_conflict_status || '').trim();
        const proposalConflictDetected = item.proposal_conflict_detected === true;
        const proposalConflictSummary = String(item.proposal_conflict_summary || '').trim();
        const proposalArbitrationStatus = String(item.proposal_arbitration_status || '').trim();
        const proposalArbitrationWinner = String(item.proposal_arbitration_winner || '').trim();
        const proposalArbitrationSummary = String(item.proposal_arbitration_summary || '').trim();
        const proposalMergePolicyStatus = String(item.proposal_merge_policy_status || '').trim();
        const proposalMergePolicyMode = String(item.proposal_merge_policy_mode || '').trim();
        const proposalMergePolicySummary = String(item.proposal_merge_policy_summary || '').trim();
        const proposalAcknowledgmentStatus = String(item.proposal_acknowledgment_status || '').trim();
        const proposalAcknowledgmentDisposition = String(item.proposal_acknowledgment_disposition || '').trim();
        const proposalAcknowledgmentSummary = String(item.proposal_acknowledgment_summary || '').trim();
        const proposalClosureStatus = String(item.proposal_closure_status || '').trim();
        const proposalClosureDisposition = String(item.proposal_closure_disposition || '').trim();
        const proposalClosureSummary = String(item.proposal_closure_summary || '').trim();
        const modeClass = mode === 'observe_only' ? 'observe-only' : '';
        const historyScore = Number.isFinite(Number(item.history_score)) ? Number(item.history_score) : null;
        const feedbackScore = Number.isFinite(Number(item.feedback_score)) ? Number(item.feedback_score) : null;
        const proposalOutcomeScore = Number.isFinite(Number(item.proposal_outcome_score)) ? Number(item.proposal_outcome_score) : null;
        const ineffectiveSignal = item.history_ineffective_signal === true;
        const ineffectiveBasis = String(item.history_ineffective_basis || '').trim();
        const ineffectivePenalty = Number.isFinite(Number(item.ineffective_penalty)) ? Number(item.ineffective_penalty) : null;
        const combinedScore = Number.isFinite(Number(item.combined_score)) ? Number(item.combined_score) : historyScore;
        const historySummary = String(item.history_same_intent_summary || item.history_summary || '').trim();
        const feedbackSummary = String(item.feedback_same_intent_summary || item.feedback_summary || '').trim();
        const proposalOutcomeSummary = String(item.proposal_outcome_same_intent_summary || item.proposal_outcome_summary || '').trim();
        const rankingExplanation = String(item.ranking_explanation || '').trim();
        const fitnessLabel = combinedScore === null ? '' : `fitness ${combinedScore >= 0 ? '+' : ''}${combinedScore}`;
        const historyLabel = historyScore === null ? '' : `history ${historyScore >= 0 ? '+' : ''}${historyScore}`;
        const feedbackLabel = feedbackScore === null ? '' : `feedback ${feedbackScore >= 0 ? '+' : ''}${feedbackScore}`;
        const proposalOutcomeLabel = proposalOutcomeScore === null ? '' : `proposal ${proposalOutcomeScore >= 0 ? '+' : ''}${proposalOutcomeScore}`;
        const ineffectivePenaltyLabel = ineffectivePenalty === null || ineffectivePenalty === 0 ? '' : `ineffective ${ineffectivePenalty}`;
        const metaParts = [];
        if (fitnessLabel) {
          metaParts.push(`<span class="operator-chat-action-fitness">${escapeHtml(fitnessLabel)}</span>`);
        }
        if (ineffectiveSignal) {
          metaParts.push('<span class="operator-chat-action-fitness">history ineffective</span>');
        }
        if (historyLabel) {
          metaParts.push(`<span>${escapeHtml(historyLabel)}</span>`);
        }
        if (ineffectivePenaltyLabel) {
          metaParts.push(`<span>${escapeHtml(ineffectivePenaltyLabel)}</span>`);
        }
        if (ineffectiveSignal) {
          metaParts.push('<span>refresh favored</span>');
        }
        if (feedbackLabel) {
          metaParts.push(`<span>${escapeHtml(feedbackLabel)}</span>`);
        }
        if (proposalOutcomeLabel) {
          metaParts.push(`<span>${escapeHtml(proposalOutcomeLabel)}</span>`);
        }
        if (historySummary) {
          metaParts.push(`<span>${escapeHtml(historySummary)}</span>`);
        }
        if (feedbackSummary) {
          metaParts.push(`<span>${escapeHtml(feedbackSummary)}</span>`);
        }
        if (proposalOutcomeSummary) {
          metaParts.push(`<span>${escapeHtml(proposalOutcomeSummary)}</span>`);
        }
        if (rankingExplanation) {
          metaParts.push(`<span>${escapeHtml(rankingExplanation)}</span>`);
        }
        if (proposalSource) {
          metaParts.push(`<span>${escapeHtml(proposalSource.toUpperCase())} proposal</span>`);
        }
        if (proposalObjectiveId) {
          metaParts.push(`<span>objective ${escapeHtml(proposalObjectiveId)}</span>`);
        }
        if (proposalPriority) {
          metaParts.push(`<span>priority ${escapeHtml(proposalPriority)}</span>`);
        }
        if (proposalConflictStatus) {
          metaParts.push(`<span>${escapeHtml(proposalConflictDetected ? `conflict ${proposalConflictStatus}` : `alignment ${proposalConflictStatus}`)}</span>`);
        }
        if (proposalArbitrationStatus) {
          metaParts.push(`<span>arbitration ${escapeHtml(proposalArbitrationStatus)}</span>`);
        }
        if (proposalArbitrationWinner) {
          metaParts.push(`<span>winner ${escapeHtml(proposalArbitrationWinner)}</span>`);
        }
        if (proposalMergePolicyStatus) {
          metaParts.push(`<span>merge ${escapeHtml(proposalMergePolicyStatus)}</span>`);
        }
        if (proposalMergePolicyMode) {
          metaParts.push(`<span>mode ${escapeHtml(proposalMergePolicyMode)}</span>`);
        }
        if (proposalAcknowledgmentStatus) {
          metaParts.push(`<span>ack ${escapeHtml(proposalAcknowledgmentStatus)}</span>`);
        }
        if (proposalAcknowledgmentDisposition) {
          metaParts.push(`<span>${escapeHtml(proposalAcknowledgmentDisposition)}</span>`);
        }
        if (proposalClosureStatus) {
          metaParts.push(`<span>closure ${escapeHtml(proposalClosureStatus)}</span>`);
        }
        if (proposalClosureDisposition) {
          metaParts.push(`<span>${escapeHtml(proposalClosureDisposition)}</span>`);
        }
        const titleParts = [reason];
        if (proposalTitle) {
          titleParts.push(`proposal: ${proposalTitle}`);
        }
        if (proposalSummary) {
          titleParts.push(proposalSummary);
        }
        if (proposalId) {
          titleParts.push(`task: ${proposalId}`);
        }
        if (proposalConflictSummary) {
          titleParts.push(proposalConflictSummary);
        }
        if (proposalArbitrationSummary) {
          titleParts.push(proposalArbitrationSummary);
        }
        if (proposalMergePolicySummary) {
          titleParts.push(proposalMergePolicySummary);
        }
        if (proposalAcknowledgmentSummary) {
          titleParts.push(proposalAcknowledgmentSummary);
        }
        if (proposalClosureSummary) {
          titleParts.push(proposalClosureSummary);
        }
        if (proposalOutcomeSummary) {
          titleParts.push(proposalOutcomeSummary);
        }
        if (historySummary) {
          titleParts.push(historySummary);
        }
        if (feedbackSummary) {
          titleParts.push(feedbackSummary);
        }
        if (ineffectiveBasis) {
          titleParts.push(ineffectiveBasis);
        }
        if (fitnessLabel) {
          titleParts.push(fitnessLabel);
        }
        return `<div class="operator-chat-action-stack"><button class="operator-chat-action-btn ${escapeHtml(modeClass)}" type="button" data-chat-action="${escapeHtml(action)}" data-chat-label="${escapeHtml(label)}" data-chat-reason="${escapeHtml(reason)}" data-chat-mode="${escapeHtml(mode)}" data-chat-intent="${escapeHtml(intent)}" data-chat-query="${escapeHtml(query)}" data-chat-objective="${escapeHtml(objectiveId)}" title="${escapeHtml(titleParts.filter(Boolean).join(' | '))}"><span class="operator-chat-action-primary">${escapeHtml(label)}</span>${metaParts.length > 0 ? `<span class="operator-chat-action-meta">${metaParts.join(' Â· ')}</span>` : ''}</button><div class="operator-chat-feedback-row"><button class="operator-chat-citation-btn" type="button" data-chat-feedback-action="${escapeHtml(action)}" data-chat-feedback-polarity="positive" data-chat-feedback-intent="${escapeHtml(intent)}" data-chat-feedback-query="${escapeHtml(query)}" data-chat-feedback-objective="${escapeHtml(objectiveId)}">Helpful</button><button class="operator-chat-citation-btn" type="button" data-chat-feedback-action="${escapeHtml(action)}" data-chat-feedback-polarity="negative" data-chat-feedback-intent="${escapeHtml(intent)}" data-chat-feedback-query="${escapeHtml(query)}" data-chat-feedback-objective="${escapeHtml(objectiveId)}">Not Helpful</button></div></div>`;
      }).join('')}</div>`;
    }

    function getOperatorChatEvidencePosture(payload, response, flags, suggestedActions) {
      const flagKeys = new Set(flags.map((item) => item.key));
      const postureLines = [];
      const evidenceSummary = flagKeys.size > 0
        ? `Evidence posture stays bounded by ${Array.from(flagKeys).map((item) => item.replace(/_/g, ' ')).join(', ')}.`
        : 'Evidence posture is using the current live dashboard snapshot with no explicit fallback flags.';
      postureLines.push({ label: 'Evidence Posture', text: evidenceSummary });

      const staleParts = [];
      if (flagKeys.has('listener_telemetry_fallback')) {
        staleParts.push('full state.json is unavailable, so the answer is grounded in listener telemetry fallback');
      }
      if (flagKeys.has('recent_completion_baseline_fallback')) {
        staleParts.push('requested recent-change baseline fell back to a bounded recent-time window');
      }
      postureLines.push({
        label: 'Staleness Risk',
        text: staleParts.length > 0 ? staleParts.join('; ') + '.' : 'No explicit freshness degradation flags are active for this answer.'
      });

      const observeFirst = flagKeys.has('observe_before_act');
      const boundedActions = (Array.isArray(suggestedActions) ? suggestedActions : [])
        .slice(0, 2)
        .map((item) => String(item.label || 'action'));
      postureLines.push({
        label: 'Action Posture',
        text: observeFirst
          ? `Observe before acting. Start with ${boundedActions.join(' and ') || 'bounded read-only refreshes'} before intervention.`
          : 'Suggested next moves stay within read-only or existing UI-safe control paths.'
      });

      return postureLines;
    }

    function appendOperatorChatResponse(payload) {
      if (!operatorChatThreadEl) {
        return;
      }

      const response = payload && payload.response ? payload.response : {};
      const evidence = Array.isArray(response.evidence) ? response.evidence : [];
      const suggestedActions = Array.isArray(response.suggested_actions) ? response.suggested_actions : [];
      const limitations = Array.isArray(response.limitations) ? response.limitations : [];
      const citations = Array.isArray(response.citations) ? response.citations : [];
      const flags = getOperatorChatResponseFlags(response);
      const postureLines = getOperatorChatEvidencePosture(payload, response, flags, suggestedActions);
      const confidence = String(response.confidence || 'medium').toUpperCase();
      const generatedAt = payload && payload.generated_at ? new Date(payload.generated_at).toLocaleTimeString() : new Date().toLocaleTimeString();
      const objectiveId = payload && payload.objective_id ? String(payload.objective_id) : '-';
      const intentLabel = formatOperatorChatIntentLabel(payload && payload.intent);

      const evidenceHtml = evidence.length > 0
        ? buildOperatorChatEvidenceRows(evidence)
        : '<div class="operator-chat-evidence-row"><span class="k">Evidence</span><span class="v">No structured evidence available.</span></div>';

      const postureHtml = postureLines.length > 0
        ? `<div class="operator-chat-posture">${postureLines.map(item => `<div class="operator-chat-posture-line"><strong>${escapeHtml(item.label)}:</strong> ${escapeHtml(item.text)}</div>`).join('')}</div>`
        : '';

      const actionsHtml = buildOperatorChatSuggestedActionButtons(suggestedActions, {
        intent: String(payload && payload.intent || ''),
        query: String(payload && payload.query || ''),
        objectiveId
      });

      const limitationsHtml = limitations.length > 0
        ? `<div class="operator-chat-limitations">${limitations.map(item => `<div>${escapeHtml(item)}</div>`).join('')}</div>`
        : '';

      const flagTagsHtml = flags.length > 0
        ? flags.map((item) => `<span class="operator-chat-tag ${escapeHtml(item.tone || '')}" title="${escapeHtml(item.title || item.label)}">${escapeHtml(item.label)}</span>`).join('')
        : '';

      const citationsHtml = citations.length > 0
        ? `<div class="operator-chat-tags">${citations.map(item => buildOperatorChatCitationButton(String(item.section || 'section'), String(item.field || 'field'))).join('')}</div>`
        : '';

      const entry = document.createElement('div');
      entry.className = 'operator-chat-entry system';
      entry.innerHTML = `
        <div class="operator-chat-role">TOD Operator Console</div>
        <div class="operator-chat-bubble">
          <div class="operator-chat-summary">${escapeHtml(response.summary || 'No summary available.')}</div>
          <div class="operator-chat-rail">
            ${postureHtml}
            ${evidenceHtml}
            <div class="operator-chat-next-step"><strong>Next:</strong> ${escapeHtml(response.recommended_next_step || 'No next step recorded.')}</div>
            ${actionsHtml}
            <div class="operator-chat-tags">
              ${flagTagsHtml}
              <span class="operator-chat-tag">intent :: ${escapeHtml(intentLabel)}</span>
              <span class="operator-chat-tag">objective :: ${escapeHtml(objectiveId)}</span>
              <span class="operator-chat-tag">confidence :: ${escapeHtml(confidence)}</span>
              <span class="operator-chat-tag">generated :: ${escapeHtml(generatedAt)}</span>
            </div>
            ${limitationsHtml}
            ${citationsHtml}
          </div>
        </div>
      `;
      operatorChatThreadEl.appendChild(entry);
      operatorChatThreadEl.scrollTop = operatorChatThreadEl.scrollHeight;
    }

    function appendOperatorChatActionProposal(payload) {
      if (!operatorChatThreadEl) {
        return;
      }

      const evidence = Array.isArray(payload.evidence) ? payload.evidence : [];
      const flags = getOperatorChatResponseFlags({ flags: payload.flags || [] });
      const limitations = Array.isArray(payload.limitations) ? payload.limitations : [];
      const citations = Array.isArray(payload.citations) ? payload.citations : [];
      const alternatives = Array.isArray(payload.alternative_actions) ? payload.alternative_actions : [];
      const previewId = String(payload.preview_id || '');
      const auditId = String(payload.audit && payload.audit.audit_id ? payload.audit.audit_id : 'pending');
      const reasoningBundleId = String(payload.reasoning_bundle && payload.reasoning_bundle.reasoning_bundle_id ? payload.reasoning_bundle.reasoning_bundle_id : (payload.audit && payload.audit.reasoning_bundle_id ? payload.audit.reasoning_bundle_id : 'pending'));
      const expiresAt = payload.preview_expires_at ? new Date(payload.preview_expires_at).toLocaleTimeString() : 'not retained';
      const evidenceHtml = buildOperatorChatEvidenceRows(evidence);
      const flagHtml = flags.length > 0
        ? flags.map((item) => `<span class="operator-chat-tag ${escapeHtml(item.tone || '')}" title="${escapeHtml(item.title || item.label)}">${escapeHtml(item.label)}</span>`).join('')
        : '';
      const citationsHtml = citations.length > 0
        ? `<div class="operator-chat-tags">${citations.map(item => buildOperatorChatCitationButton(String(item.section || 'section'), String(item.field || 'field'))).join('')}</div>`
        : '';
      const limitationsHtml = limitations.length > 0
        ? `<div class="operator-chat-limitations">${limitations.map(item => `<div>${escapeHtml(item)}</div>`).join('')}</div>`
        : '';
      const actionButtonsHtml = payload.allowed
        ? `<div class="operator-chat-actions"><button class="operator-chat-action-btn commit" type="button" data-chat-commit-preview="${escapeHtml(String(payload.preview_id || ''))}" data-chat-commit-state="committed">Commit Decision</button><button class="operator-chat-action-btn commit-timebox" type="button" data-chat-commit-preview="${escapeHtml(String(payload.preview_id || ''))}" data-chat-commit-state="timeboxed" data-chat-commit-duration="15">Commit 15m</button><button class="operator-chat-action-btn commit-condition" type="button" data-chat-commit-preview="${escapeHtml(String(payload.preview_id || ''))}" data-chat-commit-state="until_evidence_change">Commit Until Evidence Change</button><button class="operator-chat-action-btn confirm" type="button" data-chat-confirm-preview="${escapeHtml(String(payload.preview_id || ''))}">Confirm ${escapeHtml(String(payload.action_label || payload.action || 'action'))}</button><button class="operator-chat-action-btn cancel" type="button" data-chat-cancel-preview="${escapeHtml(String(payload.preview_id || ''))}">Cancel</button></div>`
        : `<div class="operator-chat-actions"><button class="operator-chat-action-btn blocked" type="button" data-chat-cancel-preview="${escapeHtml(String(payload.preview_id || ''))}">Dismiss Blocked Action</button></div>`;
      const alternativeHtml = buildOperatorChatSuggestedActionButtons(alternatives, {
        intent: String(payload.audit && payload.audit.intent || ''),
        query: String(payload.audit && payload.audit.query || ''),
        objectiveId: String(payload.audit && payload.audit.objective_id || selectedObjectiveId || '')
      });

      const entry = document.createElement('div');
      entry.className = 'operator-chat-entry system';
      entry.innerHTML = `
        <div class="operator-chat-role">TOD Action Gate</div>
        <div class="operator-chat-bubble">
          <div class="operator-chat-summary">${escapeHtml(payload.allowed ? `Proposed action: ${payload.action_label}. ${payload.policy_reason}` : `Blocked action: ${payload.action_label}. ${payload.policy_reason}`)}</div>
          <div class="operator-chat-rail">
            <div class="operator-chat-posture">
              <div class="operator-chat-posture-line"><strong>Why TOD recommends it:</strong> ${escapeHtml(String(payload.suggested_reason || 'No recommendation reason recorded.'))}</div>
              <div class="operator-chat-posture-line"><strong>Why confirmation is required:</strong> ${escapeHtml(String(payload.confirmation_reason || 'Confirmation is required for governed actions.'))}</div>
              <div class="operator-chat-posture-line"><strong>Expected impact:</strong> ${escapeHtml(String(payload.expected_impact || 'Bounded operator action.'))}</div>
              <div class="operator-chat-posture-line"><strong>Audit ID:</strong> ${escapeHtml(auditId)}</div>
              <div class="operator-chat-posture-line"><strong>Reasoning Bundle:</strong> ${escapeHtml(reasoningBundleId)}</div>
              <div class="operator-chat-posture-line"><strong>Preview ID:</strong> ${escapeHtml(previewId || 'not retained')}</div>
              <div class="operator-chat-posture-line"><strong>Preview expiry:</strong> ${escapeHtml(expiresAt)}</div>
              <div class="operator-chat-posture-line"><strong>If blocked:</strong> ${escapeHtml(String(payload.policy_remediation || 'Request a bounded alternative instead of retrying this action.'))}</div>
            </div>
            ${evidenceHtml}
            <div class="operator-chat-tags">${flagHtml}</div>
            ${actionButtonsHtml}
            ${alternativeHtml}
            ${limitationsHtml}
            ${citationsHtml}
          </div>
        </div>
      `;
      operatorChatThreadEl.appendChild(entry);
      operatorChatThreadEl.scrollTop = operatorChatThreadEl.scrollHeight;
    }

    function appendOperatorChatActionOutcome(payload) {
      const status = String(payload.action_status || 'unknown').toLowerCase();
      const flags = Array.isArray(payload.flags) ? payload.flags.slice() : [];
      flags.push(`action_${status}`);
      const evidence = Array.isArray(payload.evidence) ? payload.evidence.slice() : [];
      if (payload.audit && payload.audit.preview_id) {
        evidence.push({ label: 'Preview ID', value: String(payload.audit.preview_id), section: 'operator_action_audit', field: 'preview_id' });
      }
      if (payload.audit && payload.audit.audit_id) {
        evidence.push({ label: 'Audit ID', value: String(payload.audit.audit_id), section: 'operator_action_audit', field: 'audit_id' });
      }
      if (payload.audit && payload.audit.reasoning_bundle_id) {
        evidence.push({ label: 'Reasoning Bundle', value: String(payload.audit.reasoning_bundle_id), section: 'operator_action_reasoning', field: 'reasoning_bundle_id' });
      }
      if (payload.commitment && payload.commitment.commitment_id) {
        evidence.push({ label: 'Commitment ID', value: String(payload.commitment.commitment_id), section: 'operator_commitment', field: 'commitment_id' });
      }

      appendOperatorChatResponse({
        query: '',
        intent: `action_${status}`,
        objective_id: payload.audit && payload.audit.objective_id ? String(payload.audit.objective_id) : (selectedObjectiveId || '-'),
        generated_at: payload.audit && payload.audit.timestamp_utc ? String(payload.audit.timestamp_utc) : new Date().toISOString(),
        response: {
          summary: `${String(payload.action_label || payload.action || 'Action')}: ${String(payload.summary || 'No action summary available.')}`,
          evidence,
          recommended_next_step: String(payload.recommended_next_step || 'Review the refreshed evidence and continue with bounded operator steps only if still justified.'),
          suggested_actions: Array.isArray(payload.alternative_actions) ? payload.alternative_actions : [],
          confidence: status === 'succeeded' ? 'high' : (status === 'blocked' ? 'medium' : 'low'),
          flags,
          limitations: [],
          citations: Array.isArray(payload.citations) ? payload.citations : []
        }
      });
    }

    function appendOperatorChatReasoningBundle(bundle) {
      if (!operatorChatThreadEl || !bundle) {
        return;
      }

      const evidence = Array.isArray(bundle.evidence) ? bundle.evidence : [];
      const citations = Array.isArray(bundle.citations) ? bundle.citations : [];
      const alternatives = Array.isArray(bundle.alternative_actions) ? bundle.alternative_actions : [];
      const generatedAt = bundle.generated_at_utc ? new Date(bundle.generated_at_utc).toLocaleTimeString() : new Date().toLocaleTimeString();
      const evidenceHtml = buildOperatorChatEvidenceRows(evidence);
      const citationsHtml = citations.length > 0
        ? `<div class="operator-chat-tags">${citations.map(item => buildOperatorChatCitationButton(String(item.section || 'section'), String(item.field || 'field'))).join('')}</div>`
        : '';
      const alternativeHtml = buildOperatorChatSuggestedActionButtons(alternatives, {
        intent: String(bundle.intent || ''),
        query: String(bundle.query || ''),
        objectiveId: String(bundle.objective_id || selectedObjectiveId || '')
      });

      const entry = document.createElement('div');
      entry.className = 'operator-chat-entry system';
      entry.innerHTML = `
        <div class="operator-chat-role">TOD Reasoning Bundle</div>
        <div class="operator-chat-bubble">
          <div class="operator-chat-summary">${escapeHtml(String(bundle.action_label || bundle.action || 'Action'))} reasoning bundle ${escapeHtml(String(bundle.reasoning_bundle_id || '-'))}</div>
          <div class="operator-chat-rail">
            <div class="operator-chat-posture">
              <div class="operator-chat-posture-line"><strong>Allow Reason:</strong> ${escapeHtml(String(bundle.allow_reason || bundle.blocked_reason || 'No policy reasoning recorded.'))}</div>
              <div class="operator-chat-posture-line"><strong>Suggested Reason:</strong> ${escapeHtml(String(bundle.suggested_reason || 'No operator recommendation reason recorded.'))}</div>
              <div class="operator-chat-posture-line"><strong>Expected Impact:</strong> ${escapeHtml(String(bundle.expected_impact || 'No expected impact recorded.'))}</div>
              <div class="operator-chat-posture-line"><strong>Confirmation Reason:</strong> ${escapeHtml(String(bundle.confirmation_reason || 'No confirmation rationale recorded.'))}</div>
              <div class="operator-chat-posture-line"><strong>Generated:</strong> ${escapeHtml(generatedAt)}</div>
            </div>
            ${evidenceHtml}
            <div class="operator-chat-next-step"><strong>Next:</strong> ${escapeHtml(String(bundle.recommended_next_step || 'Use the linked evidence before changing action or scope.'))}</div>
            ${alternativeHtml}
            ${citationsHtml}
          </div>
        </div>
      `;
      operatorChatThreadEl.appendChild(entry);
      operatorChatThreadEl.scrollTop = operatorChatThreadEl.scrollHeight;
    }

    function appendOperatorChatCommitmentOutcome(payload) {
      if (!payload || !payload.commitment) {
        return;
      }

      const commitmentState = String(payload.commitment.state || '-');
      const terminalState = String(payload.commitment.terminal_state || '').trim();
      let nextStep = 'Confirm the committed action when you are ready to execute it, or clear the commitment if context changes.';
      switch (terminalState || commitmentState) {
        case 'satisfied':
          nextStep = 'Refresh bounded evidence before selecting the next action after the satisfied commitment.';
          break;
        case 'abandoned':
          nextStep = 'Re-ground on fresh status before switching away from the abandoned commitment.';
          break;
        case 'superseded':
          nextStep = 'Refresh status before treating the earlier commitment as still live or recommitting to it.';
          break;
        case 'ineffective':
          nextStep = 'Refresh bounded evidence before retrying an action pattern that recent outcomes marked ineffective.';
          break;
        case 'cleared':
          nextStep = 'Re-evaluate the latest bounded proposal before acting again.';
          break;
        case 'timeboxed':
          nextStep = 'Confirm the committed action inside the timebox, or refresh status if the timebox expires before execution.';
          break;
        case 'until_evidence_change':
          nextStep = 'Confirm the committed action while evidence still supports it, or revalidate if evidence changes.';
          break;
        default:
          break;
      }
      const commitmentFlag = terminalState
        ? 'operator_commitment_terminal'
        : (commitmentState === 'cleared'
        ? 'operator_commitment_cleared'
        : ((commitmentState === 'satisfied' || commitmentState === 'abandoned')
          ? 'operator_commitment_terminal'
          : 'active_operator_commitment'));

      appendOperatorChatResponse({
        query: '',
        intent: 'operator_commitment',
        objective_id: String(payload.commitment.objective_id || selectedObjectiveId || '-'),
        generated_at: String(payload.commitment.timestamp_utc || new Date().toISOString()),
        response: {
          summary: String(payload.summary || 'Operator commitment recorded.'),
          evidence: [
            { label: 'Commitment ID', value: String(payload.commitment.commitment_id || '-'), section: 'operator_commitment', field: 'commitment_id' },
            { label: 'Committed Action', value: String(payload.commitment.action_label || payload.commitment.action || '-'), section: 'operator_commitment', field: 'action_label' },
            { label: 'State', value: String(payload.commitment.state || '-'), section: 'operator_commitment', field: 'state' },
            { label: 'Lifecycle', value: String(payload.commitment.lifecycle_status || '-'), section: 'operator_commitment', field: 'lifecycle_status' },
            { label: 'Terminal State', value: String(payload.commitment.terminal_state || '-'), section: 'operator_commitment', field: 'terminal_state' },
            { label: 'Release', value: String(payload.commitment.release_condition || '-'), section: 'operator_commitment', field: 'release_condition' },
            { label: 'Evidence Delta Count', value: String(Number.isFinite(payload.commitment.evidence_delta_count) ? payload.commitment.evidence_delta_count : 0), section: 'operator_commitment', field: 'evidence_delta_count' },
            { label: 'Reasoning Bundle', value: String(payload.commitment.reasoning_bundle_id || '-'), section: 'operator_action_reasoning', field: 'reasoning_bundle_id' }
          ],
          recommended_next_step: String(nextStep),
          suggested_actions: [],
          confidence: 'high',
          flags: [commitmentFlag],
          limitations: [],
          citations: []
        }
      });
    }

    function clearOperatorChatTrustChainInspector() {
      operatorChatTrustChainSelection = { auditId: '', previewId: '', bundleId: '', commitmentId: '' };
      if (operatorChatTrustChainMetaEl) {
        operatorChatTrustChainMetaEl.classList.remove('error');
        operatorChatTrustChainMetaEl.textContent = 'Select an audit or commitment row to inspect audit, reasoning, and linked evidence together.';
      }
      if (operatorChatTrustChainDetailEl) {
        operatorChatTrustChainDetailEl.innerHTML = '<div class="operator-chat-audit-entry"><div class="operator-chat-audit-summary">Trust-chain inspection will appear here after you inspect a governed action or commitment row.</div></div>';
      }
    }

    function renderOperatorChatTrustChain(data) {
      if (!operatorChatTrustChainMetaEl || !operatorChatTrustChainDetailEl) {
        return;
      }

      const audit = data && data.audit ? data.audit : null;
      const bundle = data && data.reasoning_bundle ? data.reasoning_bundle : null;
      const commitments = Array.isArray(data && data.commitments) ? data.commitments : [];
      const citations = Array.isArray(bundle && bundle.citations) ? bundle.citations : [];
      const evidence = Array.isArray(bundle && bundle.evidence) ? bundle.evidence : [];
      const evidenceDeltaCount = Number.isFinite(data && data.evidence_delta_count) ? data.evidence_delta_count : 0;
      const comparison = data && data.comparison ? data.comparison : null;
      const proposalClosure = data && data.proposal_closure ? data.proposal_closure : null;
      const harnessLabel = String(comparison && (comparison.validation_harness_label || comparison.validation_harness) || '');
      const evidenceHtml = buildOperatorChatEvidenceRows(evidence);
      const citationsHtml = citations.length > 0
        ? `<div class="operator-chat-tags">${citations.map(item => buildOperatorChatCitationButton(String(item.section || 'section'), String(item.field || 'field'))).join('')}</div>`
        : '';
      const commitmentHtml = commitments.length > 0
        ? commitments.map((item) => {
            const lifecycle = String(item.lifecycle_status || 'unknown');
            const terminalState = String(item.terminal_state || '').trim();
            const terminalDetail = String(item.terminal_detail || '').trim();
            const expiresAt = item.expires_at ? new Date(item.expires_at).toLocaleTimeString() : '';
            const deltaRows = Array.isArray(item.evidence_deltas) && item.evidence_deltas.length > 0
              ? `<div class="operator-chat-posture-line"><strong>Evidence Delta:</strong></div>${item.evidence_deltas.map((delta) => `<div class="operator-chat-posture-line">${escapeHtml(String(delta.label || delta.field || 'Field'))}: ${escapeHtml(String(delta.before || '-'))} -> ${escapeHtml(String(delta.after || '-'))}</div>`).join('')}`
              : '';
            return `<div class="operator-chat-posture-line"><strong>${escapeHtml(String(item.action_label || item.action || 'Commitment'))}:</strong> ${escapeHtml(String(item.state || 'unknown'))} :: ${escapeHtml(lifecycle)}${terminalState ? ` :: terminal ${escapeHtml(terminalState)}` : ''}${expiresAt ? ` :: expires ${escapeHtml(expiresAt)}` : ''}${deltaRows ? ` :: delta ${escapeHtml(String(Number.isFinite(item.evidence_delta_count) ? item.evidence_delta_count : 0))}` : ''}</div>${terminalDetail ? `<div class="operator-chat-posture-line"><strong>Terminal Detail:</strong> ${escapeHtml(terminalDetail)}</div>` : ''}${deltaRows}`;
          }).join('')
        : '<div class="operator-chat-posture-line"><strong>Commitments:</strong> No linked commitment record.</div>';
      const summary = String(data && data.summary ? data.summary : 'Trust-chain inspection loaded.');
      const chainStatus = String(data && data.chain_status ? data.chain_status : 'unknown');
      const actionLabel = audit ? String(audit.action_label || audit.action || 'Action') : String(bundle && (bundle.action_label || bundle.action) || 'Action');
      operatorChatTrustChainMetaEl.classList.remove('error');
      operatorChatTrustChainMetaEl.textContent = summary;
      operatorChatTrustChainDetailEl.innerHTML = `
        <div class="operator-chat-audit-entry">
          <div class="operator-chat-audit-summary">${escapeHtml(actionLabel)} :: trust-chain ${escapeHtml(chainStatus)}</div>
          <div class="operator-chat-audit-meta-row">
            <span class="operator-chat-tag">audit :: ${escapeHtml(String(audit && audit.audit_id || '-'))}</span>
            <span class="operator-chat-tag">preview :: ${escapeHtml(String((audit && audit.preview_id) || (data && data.identifiers && data.identifiers.preview_id) || '-'))}</span>
            <span class="operator-chat-tag">reasoning :: ${escapeHtml(String((bundle && bundle.reasoning_bundle_id) || (data && data.identifiers && data.identifiers.reasoning_bundle_id) || '-'))}</span>
            <span class="operator-chat-tag">evidence :: ${escapeHtml(String(data && Number.isFinite(data.evidence_count) ? data.evidence_count : evidence.length))}</span>
            <span class="operator-chat-tag">delta :: ${escapeHtml(String(evidenceDeltaCount))}</span>
            ${comparison && comparison.applied ? `<span class="operator-chat-tag">provenance :: ${escapeHtml(String(comparison.label || comparison.source || 'compare'))}${comparison.objective_id ? ` ${escapeHtml(String(comparison.objective_id))}` : ''}</span>` : ''}
          </div>
          <div class="operator-chat-posture">
            <div class="operator-chat-posture-line"><strong>Audit Summary:</strong> ${escapeHtml(String(audit && audit.outcome_summary || 'No audit summary recorded.'))}</div>
            <div class="operator-chat-posture-line"><strong>Policy Reason:</strong> ${escapeHtml(String(bundle && (bundle.allow_reason || bundle.blocked_reason) || 'No policy reasoning recorded.'))}</div>
            <div class="operator-chat-posture-line"><strong>Suggested Reason:</strong> ${escapeHtml(String(bundle && bundle.suggested_reason || 'No recommendation rationale recorded.'))}</div>
            <div class="operator-chat-posture-line"><strong>Expected Impact:</strong> ${escapeHtml(String(bundle && bundle.expected_impact || 'No expected impact recorded.'))}</div>
            ${comparison && comparison.summary ? `<div class="operator-chat-posture-line"><strong>Comparison:</strong> ${escapeHtml(String(comparison.summary || ''))}</div>` : ''}
            ${harnessLabel ? `<div class="operator-chat-posture-line"><strong>Harness:</strong> ${escapeHtml(harnessLabel)}</div>` : ''}
            ${proposalClosure && proposalClosure.available ? `<div class="operator-chat-posture-line"><strong>Proposal Closure:</strong> ${escapeHtml(String(proposalClosure.status || 'unknown'))} :: ${escapeHtml(String(proposalClosure.summary || ''))}</div>` : ''}
            ${commitmentHtml}
          </div>
          ${evidenceHtml}
          ${citationsHtml}
        </div>`;
      focusDashboardCardById('operatorChatCard');
    }

    async function loadOperatorChatTrustChain({ auditId = '', previewId = '', bundleId = '', commitmentId = '' } = {}) {
      if (!operatorChatTrustChainMetaEl || !operatorChatTrustChainDetailEl || operatorChatTrustChainPending) {
        return;
      }

      operatorChatTrustChainPending = true;
      operatorChatTrustChainSelection = { auditId, previewId, bundleId, commitmentId };
      operatorChatTrustChainMetaEl.classList.remove('error');
      operatorChatTrustChainMetaEl.textContent = 'Loading trust chain...';
      try {
        const params = appendOperatorChatValidationHarness(new URLSearchParams());
        if (String(auditId || '').trim()) params.set('audit_id', String(auditId).trim());
        if (String(previewId || '').trim()) params.set('preview_id', String(previewId).trim());
        if (String(bundleId || '').trim()) params.set('bundle_id', String(bundleId).trim());
        if (String(commitmentId || '').trim()) params.set('commitment_id', String(commitmentId).trim());
        const query = params.toString();
        const { res, data } = await fetchJsonSafe(`/api/operator-chat-action-trust-chain${query ? `?${query}` : ''}`);
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Trust-chain load failed (${res.status})`);
        }
        renderOperatorChatTrustChain(data);
      } catch (err) {
        operatorChatTrustChainMetaEl.textContent = err.message;
        operatorChatTrustChainMetaEl.classList.add('error');
      } finally {
        operatorChatTrustChainPending = false;
      }
    }

    async function loadOperatorChatActionAudit({ limit = OPERATOR_CHAT_AUDIT_LIMIT, previewId = '', action = '', outcomeStatus = '', phase = '', search = '' } = {}) {
      if (!operatorChatAuditListEl || !operatorChatAuditMetaEl || operatorChatAuditPending) {
        return;
      }

      operatorChatAuditPending = true;
      const requestToken = operatorChatAuditLoadToken + 1;
      operatorChatAuditLoadToken = requestToken;
      operatorChatAuditMetaEl.classList.remove('error');
      operatorChatAuditMetaEl.textContent = 'Loading governed action audit...';
      try {
        applyOperatorChatAuditFilterState({ limit, previewId, action, outcomeStatus, phase, search });
        const params = new URLSearchParams();
        params.set('limit', String(operatorChatAuditFilters.limit || OPERATOR_CHAT_AUDIT_LIMIT));
        if (String(operatorChatAuditFilters.previewId || '').trim()) {
          params.set('preview_id', String(operatorChatAuditFilters.previewId).trim());
        }
        if (String(operatorChatAuditFilters.action || '').trim()) {
          params.set('action', String(operatorChatAuditFilters.action).trim());
        }
        if (String(operatorChatAuditFilters.outcomeStatus || '').trim()) {
          params.set('outcome_status', String(operatorChatAuditFilters.outcomeStatus).trim());
        }
        if (String(operatorChatAuditFilters.phase || '').trim()) {
          params.set('phase', String(operatorChatAuditFilters.phase).trim());
        }
        if (String(operatorChatAuditFilters.search || '').trim()) {
          params.set('search', String(operatorChatAuditFilters.search).trim());
        }

        const { res, data } = await fetchJsonSafe(`/api/operator-chat-action-audit?${params.toString()}`);
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Governed action audit load failed (${res.status})`);
        }

        if (requestToken !== operatorChatAuditLoadToken) {
          return;
        }

        const entries = Array.isArray(data.entries) ? data.entries : [];
        const proposalLifecycle = data && data.proposal_lifecycle ? data.proposal_lifecycle : null;
        populateOperatorChatAuditActionFilter(entries);
        const activeFilters = [];
        if (operatorChatAuditFilters.action) activeFilters.push(`action=${operatorChatAuditFilters.action}`);
        if (operatorChatAuditFilters.outcomeStatus) activeFilters.push(`outcome=${operatorChatAuditFilters.outcomeStatus}`);
        if (operatorChatAuditFilters.phase) activeFilters.push(`phase=${operatorChatAuditFilters.phase}`);
        if (operatorChatAuditFilters.previewId) activeFilters.push(`preview=${operatorChatAuditFilters.previewId}`);
        if (operatorChatAuditFilters.search) activeFilters.push(`search="${operatorChatAuditFilters.search}"`);
        operatorChatAuditMetaEl.textContent = entries.length > 0
          ? `Showing ${entries.length} governed action event${entries.length === 1 ? '' : 's'}${activeFilters.length > 0 ? ` | filters: ${activeFilters.join(', ')}` : ''}.`
          : `No governed action audit entries match${activeFilters.length > 0 ? ` | filters: ${activeFilters.join(', ')}` : ' yet'}.`;
        const lifecycleHtml = proposalLifecycle && proposalLifecycle.available
          ? `<div class="operator-chat-audit-entry"><div class="operator-chat-audit-summary">Proposal Lifecycle :: ${escapeHtml(String(proposalLifecycle.status || 'unknown'))} :: ${escapeHtml(String(proposalLifecycle.summary || 'No lifecycle summary available.'))}</div><div class="operator-chat-audit-meta-row"><span class="operator-chat-tag">proposal :: ${escapeHtml(String(proposalLifecycle.proposal_id || '-'))}</span><span class="operator-chat-tag">disposition :: ${escapeHtml(String(proposalLifecycle.disposition || '-'))}</span></div>${Array.isArray(proposalLifecycle.journal) && proposalLifecycle.journal.length > 0 ? proposalLifecycle.journal.slice(0, 3).map((entry) => `<div class="operator-chat-posture-line"><strong>${escapeHtml(String(entry.proposal_title || entry.proposal_id || 'proposal'))}:</strong> ${escapeHtml(String(entry.status || 'unknown'))} :: ${escapeHtml(String(entry.summary || ''))}</div>`).join('') : ''}</div>`
          : '';
        operatorChatAuditListEl.innerHTML = entries.length > 0 || lifecycleHtml
          ? `${lifecycleHtml}${entries.map((item) => {
              const actionLabel = String(item.action_label || item.action || 'Action');
              const outcome = String(item.outcome_status || 'unknown');
              const phase = String(item.phase || 'phase');
              const summary = String(item.outcome_summary || 'No audit summary available.');
              const ts = item.timestamp_utc ? new Date(item.timestamp_utc).toLocaleTimeString() : '-';
              return `
                <div class="operator-chat-audit-entry">
                  <div class="operator-chat-audit-summary">${escapeHtml(actionLabel)} :: ${escapeHtml(outcome)} :: ${escapeHtml(summary)}</div>
                  <div class="operator-chat-audit-meta-row">
                    <span class="operator-chat-tag">phase :: ${escapeHtml(phase)}</span>
                    <span class="operator-chat-tag">time :: ${escapeHtml(ts)}</span>
                    <span class="operator-chat-tag">preview :: ${escapeHtml(String(item.preview_id || '-'))}</span>
                    <span class="operator-chat-tag">audit :: ${escapeHtml(String(item.audit_id || '-'))}</span>
                    <span class="operator-chat-tag">reasoning :: ${escapeHtml(String(item.reasoning_bundle_id || '-'))}</span>
                    ${item.proposal_id ? `<span class="operator-chat-tag">proposal :: ${escapeHtml(String(item.proposal_id || '-'))}</span>` : ''}
                    ${item.reasoning_bundle_id ? `<button class="operator-chat-citation-btn" type="button" data-chat-show-reasoning="${escapeHtml(String(item.reasoning_bundle_id || ''))}">Show Reasoning</button>` : ''}
                    <button class="operator-chat-citation-btn" type="button" data-chat-inspect-chain="1" data-chat-inspect-audit="${escapeHtml(String(item.audit_id || ''))}" data-chat-inspect-preview="${escapeHtml(String(item.preview_id || ''))}" data-chat-inspect-bundle="${escapeHtml(String(item.reasoning_bundle_id || ''))}">Inspect Chain</button>
                  </div>
                </div>`;
            }).join('')}`
          : '<div class="operator-chat-audit-entry"><div class="operator-chat-audit-summary">Governed action audit will appear here after the first preview or confirm event.</div></div>';
      } catch (err) {
        if (requestToken !== operatorChatAuditLoadToken) {
          return;
        }
        operatorChatAuditMetaEl.textContent = err.message;
        operatorChatAuditMetaEl.classList.add('error');
      } finally {
        operatorChatAuditPending = false;
      }
    }

    async function loadOperatorChatCommitments({ limit = OPERATOR_CHAT_COMMITMENT_LIMIT, objectiveId = selectedObjectiveId || '' } = {}) {
      if (!operatorChatCommitmentMetaEl || !operatorChatCommitmentListEl || operatorChatCommitmentPending) {
        return;
      }

      operatorChatCommitmentPending = true;
      operatorChatCommitmentMetaEl.classList.remove('error');
      operatorChatCommitmentMetaEl.textContent = 'Loading operator commitments...';
      try {
        const params = appendOperatorChatValidationHarness(new URLSearchParams());
        params.set('limit', String(limit || OPERATOR_CHAT_COMMITMENT_LIMIT));
        if (String(objectiveId || '').trim()) {
          params.set('objective_id', String(objectiveId).trim());
        }
        const { res, data } = await fetchJsonSafe(`/api/operator-chat-commitments?${params.toString()}`);
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Commitment load failed (${res.status})`);
        }
        const entries = Array.isArray(data.entries) ? data.entries : [];
        operatorChatCommitmentMetaEl.textContent = entries.length > 0
          ? `Showing ${entries.length} operator commitment${entries.length === 1 ? '' : 's'}.`
          : 'No operator commitments recorded yet.';
        operatorChatCommitmentListEl.innerHTML = entries.length > 0
          ? entries.map((item) => {
              const state = String(item.state || 'unknown');
              const actionLabel = String(item.action_label || item.action || 'Action');
              const ts = item.timestamp_utc ? new Date(item.timestamp_utc).toLocaleTimeString() : '-';
              const lifecycle = String(item.lifecycle_status || 'unknown');
              const terminalState = String(item.terminal_state || '').trim();
              const terminalDetail = String(item.terminal_detail || '').trim();
              const release = String(item.release_condition || 'manual_clear');
              const expiresAt = item.expires_at ? new Date(item.expires_at).toLocaleTimeString() : '';
              const evidenceDeltaCount = Number.isFinite(item.evidence_delta_count) ? item.evidence_delta_count : 0;
              const terminalHistory = item && item.terminal_history ? item.terminal_history : null;
              const terminalSummary = terminalHistory && terminalHistory.summary
                ? String(terminalHistory.summary)
                : 'No recent terminal outcome history recorded for this action.';
              const sameIntentSummary = terminalHistory && terminalHistory.same_intent_summary
                ? String(terminalHistory.same_intent_summary)
                : '';
              const latestTerminalAt = terminalHistory && terminalHistory.recent_terminal_at
                ? new Date(terminalHistory.recent_terminal_at).toLocaleTimeString()
                : '';
              const scopeStatus = String(item.scope_status || 'in_scope');
              const scopeSummary = String(item.scope_summary || '').trim();
              const scopeKind = String(item.scope_kind || 'objective_wide');
              const currentScopeKind = String(item.current_scope_kind || scopeKind || 'objective_wide');
              const scopeResolution = String(item.scope_conflict_resolution || 'active');
              const scopeOverlap = String(item.scope_overlap_status || 'exact');
              const scopeConflictReason = String(item.scope_conflict_reason || '').trim();
              const scopeInfluenceSummary = String(item.scope_influence_summary || '').trim();
              const proposalId = String(item.proposal_id || '').trim();
              const proposalTitle = String(item.proposal_title || '').trim();
              const proposalDisposition = String(item.proposal_acknowledgment_disposition || '').trim();
              const provenanceSource = String(item.trust_chain_provenance_source || '');
              const provenanceLabel = String(item.trust_chain_provenance_label || provenanceSource || '');
              const provenanceObjectiveId = String(item.trust_chain_compare_objective_id || '');
              const provenanceSummary = String(item.trust_chain_provenance_summary || '');
              const clearBtn = item.active && item.preview_id
                ? `<button class="operator-chat-citation-btn" type="button" data-chat-update-commitment="${escapeHtml(String(item.preview_id || ''))}" data-chat-update-commitment-state="cleared">Clear Commitment</button>`
                : '';
              const satisfiedBtn = item.active && item.preview_id
                ? `<button class="operator-chat-citation-btn" type="button" data-chat-update-commitment="${escapeHtml(String(item.preview_id || ''))}" data-chat-update-commitment-state="satisfied">Mark Satisfied</button>`
                : '';
              const abandonedBtn = item.active && item.preview_id
                ? `<button class="operator-chat-citation-btn" type="button" data-chat-update-commitment="${escapeHtml(String(item.preview_id || ''))}" data-chat-update-commitment-state="abandoned">Mark Abandoned</button>`
                : '';
              return `
                <div class="operator-chat-audit-entry">
                  <div class="operator-chat-audit-summary">${escapeHtml(actionLabel)} :: ${escapeHtml(state)} :: ${escapeHtml(String(item.summary || 'No commitment summary available.'))}</div>
                  ${proposalId ? `<div class="operator-chat-posture-line"><strong>Proposal:</strong> ${escapeHtml(proposalTitle || proposalId)}${proposalDisposition ? ` :: ${escapeHtml(proposalDisposition)}` : ''}</div>` : ''}
                  <div class="operator-chat-posture-line"><strong>Outcome History:</strong> ${escapeHtml(terminalSummary)}</div>
                  ${terminalDetail ? `<div class="operator-chat-posture-line"><strong>Terminal Detail:</strong> ${escapeHtml(terminalDetail)}</div>` : ''}
                  ${sameIntentSummary ? `<div class="operator-chat-posture-line"><strong>Intent Fitness:</strong> ${escapeHtml(sameIntentSummary)}</div>` : ''}
                  ${scopeSummary ? `<div class="operator-chat-posture-line"><strong>Scope:</strong> ${escapeHtml(scopeSummary)}</div>` : ''}
                  ${scopeInfluenceSummary ? `<div class="operator-chat-posture-line"><strong>Scope Influence:</strong> ${escapeHtml(scopeInfluenceSummary)}</div>` : ''}
                  ${scopeConflictReason ? `<div class="operator-chat-posture-line"><strong>Scope Conflict:</strong> ${escapeHtml(scopeConflictReason)}</div>` : ''}
                  ${provenanceSummary ? `<div class="operator-chat-posture-line"><strong>Trust-Chain Provenance:</strong> ${escapeHtml(provenanceSummary)}</div>` : ''}
                  <div class="operator-chat-audit-meta-row">
                    <span class="operator-chat-tag">time :: ${escapeHtml(ts)}</span>
                    <span class="operator-chat-tag">lifecycle :: ${escapeHtml(lifecycle)}</span>
                    ${terminalState ? `<span class="operator-chat-tag">terminal :: ${escapeHtml(terminalState)}</span>` : ''}
                    <span class="operator-chat-tag">scope :: ${escapeHtml(scopeStatus)}</span>
                    <span class="operator-chat-tag">scope kind :: ${escapeHtml(scopeKind)}</span>
                    <span class="operator-chat-tag">current scope :: ${escapeHtml(currentScopeKind)}</span>
                    <span class="operator-chat-tag">scope resolution :: ${escapeHtml(scopeResolution)}</span>
                    <span class="operator-chat-tag">scope overlap :: ${escapeHtml(scopeOverlap)}</span>
                    <span class="operator-chat-tag">release :: ${escapeHtml(release)}</span>
                    <span class="operator-chat-tag">delta :: ${escapeHtml(String(evidenceDeltaCount))}</span>
                    ${proposalId ? `<span class="operator-chat-tag">proposal :: ${escapeHtml(proposalId)}</span>` : ''}
                    ${provenanceSource ? `<span class="operator-chat-tag">provenance :: ${escapeHtml(provenanceLabel)}${provenanceObjectiveId ? ` ${escapeHtml(provenanceObjectiveId)}` : ''}</span>` : ''}
                    ${terminalHistory ? `<span class="operator-chat-tag">satisfied :: ${escapeHtml(String(Number.isFinite(terminalHistory.satisfied_count) ? terminalHistory.satisfied_count : 0))}</span>` : ''}
                    ${terminalHistory ? `<span class="operator-chat-tag">abandoned :: ${escapeHtml(String(Number.isFinite(terminalHistory.abandoned_count) ? terminalHistory.abandoned_count : 0))}</span>` : ''}
                    ${terminalHistory ? `<span class="operator-chat-tag">fitness :: ${escapeHtml(String(Number.isFinite(terminalHistory.recent_fitness_score) ? terminalHistory.recent_fitness_score : 0))}</span>` : ''}
                    ${latestTerminalAt ? `<span class="operator-chat-tag">latest terminal :: ${escapeHtml(latestTerminalAt)}</span>` : ''}
                    ${expiresAt ? `<span class="operator-chat-tag">expires :: ${escapeHtml(expiresAt)}</span>` : ''}
                    <span class="operator-chat-tag">commitment :: ${escapeHtml(String(item.commitment_id || '-'))}</span>
                    <span class="operator-chat-tag">reasoning :: ${escapeHtml(String(item.reasoning_bundle_id || '-'))}</span>
                    ${item.reasoning_bundle_id ? `<button class="operator-chat-citation-btn" type="button" data-chat-show-reasoning="${escapeHtml(String(item.reasoning_bundle_id || ''))}">Show Reasoning</button>` : ''}
                    <button class="operator-chat-citation-btn" type="button" data-chat-inspect-chain="1" data-chat-inspect-preview="${escapeHtml(String(item.preview_id || ''))}" data-chat-inspect-bundle="${escapeHtml(String(item.reasoning_bundle_id || ''))}" data-chat-inspect-commitment="${escapeHtml(String(item.commitment_id || ''))}">Inspect Chain</button>
                    ${satisfiedBtn}
                    ${abandonedBtn}
                    ${clearBtn}
                  </div>
                </div>`;
            }).join('')
          : '<div class="operator-chat-audit-entry"><div class="operator-chat-audit-summary">Operator commitments will appear here after the first committed proposal.</div></div>';
      } catch (err) {
        operatorChatCommitmentMetaEl.textContent = err.message;
        operatorChatCommitmentMetaEl.classList.add('error');
      } finally {
        operatorChatCommitmentPending = false;
      }
    }

    async function previewOperatorChatSuggestedAction(meta) {
      if (operatorChatActionPending) {
        setOperatorChatMeta('Another governed action request is already running.');
        return;
      }

      operatorChatActionPending = true;
      setOperatorChatMeta(`Preparing governed action preview for ${String(meta.label || meta.action || 'action')}...`);
      try {
        const { res, data } = await fetchJsonSafe('/api/operator-chat-action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            phase: 'preview',
            action: meta.action,
            intent: meta.intent,
            objective_id: meta.objectiveId || selectedObjectiveId || '',
            query: meta.query,
            window_minutes: 10,
            operator_id: OPERATOR_CHAT_ACTOR_ID,
            suggested_reason: meta.reason,
            mode: meta.mode
          })
        });

        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Governed action preview failed (${res.status})`);
        }

        operatorChatActionPreviews.set(String(data.preview_id || ''), {
          previewId: String(data.preview_id || ''),
          action: meta.action,
          intent: meta.intent,
          objectiveId: meta.objectiveId || selectedObjectiveId || '',
          query: meta.query,
          reason: meta.reason,
          mode: meta.mode,
          label: meta.label
        });
        appendOperatorChatActionProposal(data);
        await loadOperatorChatActionAudit();
        await loadOperatorChatCommitments();
        setOperatorChatMeta(`Governed action preview ready for ${String(data.action_label || meta.label || meta.action)}.`);
      } catch (err) {
        setOperatorChatMeta(err.message, true);
      } finally {
        operatorChatActionPending = false;
      }
    }

    async function confirmOperatorChatAction(previewId) {
      const key = String(previewId || '');
      const preview = operatorChatActionPreviews.get(key);
      if (!preview) {
        setOperatorChatMeta('Governed action preview expired. Request a new preview.');
        return;
      }

      if (operatorChatActionPending) {
        setOperatorChatMeta('Another governed action request is already running.');
        return;
      }

      operatorChatActionPending = true;
      setOperatorChatMeta(`Confirming governed action ${String(preview.label || preview.action)}...`);
      try {
        const { res, data } = await fetchJsonSafe('/api/operator-chat-action', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            phase: 'confirm',
            preview_id: key,
            action: preview.action,
            intent: preview.intent,
            objective_id: preview.objectiveId || selectedObjectiveId || '',
            query: preview.query,
            window_minutes: 10,
            operator_id: OPERATOR_CHAT_ACTOR_ID,
            suggested_reason: preview.reason,
            mode: preview.mode
          })
        });

        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Governed action confirm failed (${res.status})`);
        }

        operatorChatActionPreviews.delete(key);
        appendOperatorChatActionOutcome(data);
        await applyOperatorChatActionUiRefresh(data.action, data.action_status);
        await loadOperatorChatCommitments();
        await loadOperatorChatTrustChain({
          auditId: String(data.audit && data.audit.audit_id || ''),
          previewId: String(data.audit && data.audit.preview_id || key),
          bundleId: String(data.audit && data.audit.reasoning_bundle_id || ''),
          commitmentId: String(data.commitment && data.commitment.commitment_id || '')
        });
        setOperatorChatMeta(`Governed action ${String(data.action_label || preview.label || preview.action)} ${String(data.action_status || 'completed')}.`);
      } catch (err) {
        setOperatorChatMeta(err.message, true);
      } finally {
        operatorChatActionPending = false;
      }
    }

    async function setOperatorChatCommitment(previewId, state = 'committed', durationMinutes = 15) {
      const key = String(previewId || '');
      if (!key) {
        setOperatorChatMeta('Commitment requires a live preview.', true);
        return;
      }
      if (operatorChatActionPending) {
        setOperatorChatMeta('Another governed action request is already running.');
        return;
      }

      operatorChatActionPending = true;
      const stateLabel = state === 'cleared'
        ? 'Clearing'
        : (state === 'satisfied'
          ? 'Marking commitment satisfied'
          : (state === 'abandoned' ? 'Marking commitment abandoned' : 'Recording operator commitment'));
      setOperatorChatMeta(`${stateLabel}...`);
      try {
        const { res, data } = await fetchJsonSafe('/api/operator-chat-commitment', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            preview_id: key,
            objective_id: selectedObjectiveId || '',
            operator_id: OPERATOR_CHAT_ACTOR_ID,
            state,
            duration_minutes: durationMinutes,
            validation_harness: OPERATOR_CHAT_VALIDATION_HARNESS || ''
          })
        });
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Commitment request failed (${res.status})`);
        }
        appendOperatorChatCommitmentOutcome(data);
        await loadOperatorChatCommitments();
        await loadOperatorChatActionAudit();
        await loadOperatorChatTrustChain({
          previewId: String(data.commitment && data.commitment.preview_id || key),
          bundleId: String(data.commitment && data.commitment.reasoning_bundle_id || ''),
          commitmentId: String(data.commitment && data.commitment.commitment_id || '')
        });
        setOperatorChatMeta(String(data.summary || 'Operator commitment updated.'));
      } catch (err) {
        setOperatorChatMeta(err.message, true);
      } finally {
        operatorChatActionPending = false;
      }
    }

    async function showOperatorChatReasoningBundle(bundleId) {
      const key = String(bundleId || '').trim();
      if (!key) {
        return;
      }
      setOperatorChatMeta(`Loading reasoning bundle ${key}...`);
      try {
        const { res, data } = await fetchJsonSafe(`/api/operator-chat-action-reasoning?bundle_id=${encodeURIComponent(key)}&limit=1`);
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Reasoning bundle load failed (${res.status})`);
        }
        const entries = Array.isArray(data.entries) ? data.entries : [];
        if (!entries.length) {
          throw new Error('Reasoning bundle was not found.');
        }
        appendOperatorChatReasoningBundle(entries[0]);
        setOperatorChatMeta(`Reasoning bundle ${key} loaded.`);
      } catch (err) {
        setOperatorChatMeta(err.message, true);
      }
    }

    async function submitOperatorChatActionFeedback(meta) {
      const action = String(meta && meta.action || '').trim();
      const polarity = String(meta && meta.polarity || '').trim().toLowerCase();
      if (!action || !polarity) {
        return;
      }

      setOperatorChatMeta(`Recording ${polarity} feedback for ${action}...`);
      try {
        const { res, data } = await fetchJsonSafe('/api/operator-chat-feedback', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action,
            polarity,
            intent: String(meta && meta.intent || ''),
            query: String(meta && meta.query || ''),
            objective_id: String(meta && meta.objectiveId || selectedObjectiveId || ''),
            operator_id: OPERATOR_CHAT_ACTOR_ID
          })
        });

        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Operator feedback request failed (${res.status})`);
        }

        setOperatorChatMeta(String(data.summary || 'Operator feedback recorded.'));
        if (operatorChatLastRequest && (operatorChatLastRequest.query || operatorChatLastRequest.intent)) {
          await runOperatorChatQuery({
            query: operatorChatLastRequest.query,
            intent: operatorChatLastRequest.intent,
            windowMinutes: operatorChatLastRequest.windowMinutes,
            echoUser: false
          });
        }
      } catch (err) {
        setOperatorChatMeta(err.message, true);
      }
    }

    function cancelOperatorChatAction(previewId) {
      const key = String(previewId || '');
      const preview = operatorChatActionPreviews.get(key);
      operatorChatActionPreviews.delete(key);
      setOperatorChatMeta(`Governed action ${preview && preview.label ? preview.label : 'preview'} cancelled.`);
      appendOperatorChatUserEntry(`Action confirmation cancelled for ${preview && preview.label ? preview.label : 'preview'}.`);
    }

    async function runOperatorChatRefreshPlan(actionKey) {
      const key = String(actionKey || '').toLowerCase();
      const plan = OPERATOR_CHAT_ACTION_REFRESH_PLAN[key] || OPERATOR_CHAT_ACTION_REFRESH_PLAN.default;
      for (const step of plan) {
        await step(key);
      }
    }

    async function applyOperatorChatActionUiRefresh(action, status) {
      if (String(status || '').toLowerCase() !== 'succeeded') {
        await loadOperatorChatActionAudit();
        return;
      }

      await runOperatorChatRefreshPlan(action);
    }

    async function dispatchOperatorChatSuggestedAction(action) {
      const key = String(action || '').trim().toLowerCase();
      if (!key) {
        return;
      }

      switch (key) {
        case 'wait':
          setStatus('Operator chat recommendation: no immediate action needed. Continue observing bounded signals.');
          return;
        default:
          setStatus(`Operator chat suggested unsupported action: ${key}`, true);
      }
    }

    async function runOperatorChatQuery({ query = '', intent = '', windowMinutes = 10, echoUser = true } = {}) {
      const trimmedQuery = String(query || '').trim();
      const trimmedIntent = String(intent || '').trim();
      if (!trimmedQuery && !trimmedIntent) {
        setOperatorChatMeta('Enter a question or use a guided prompt.', true);
        return;
      }

      if (operatorChatPending) {
        setOperatorChatMeta('Operator chat is already processing a request.');
        return;
      }

      operatorChatPending = true;
      operatorChatLastRequest = { query: trimmedQuery, intent: trimmedIntent, windowMinutes };
      if (operatorChatSubmitEl) {
        operatorChatSubmitEl.disabled = true;
      }
      operatorChatPresetEls.forEach(btn => { btn.disabled = true; });
      setOperatorChatMeta(`Asking TOD about ${trimmedIntent ? formatOperatorChatIntentLabel(trimmedIntent) : 'current operational state'}...`);

      if (echoUser) {
        appendOperatorChatUserEntry(trimmedQuery || formatOperatorChatIntentLabel(trimmedIntent));
      }

      try {
        const { res, data } = await fetchJsonSafe('/api/operator-chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            query: trimmedQuery,
            intent: trimmedIntent,
            objective_id: selectedObjectiveId || '',
            window_minutes: windowMinutes,
            validation_harness: OPERATOR_CHAT_VALIDATION_HARNESS
          })
        });

        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Operator chat request failed (${res.status})`);
        }

        appendOperatorChatResponse(data);
        setOperatorChatMeta(`Operator answer ready at ${new Date().toLocaleTimeString()}.`);
      } catch (err) {
        setOperatorChatMeta(err.message, true);
        appendOperatorChatUserEntry(`Operator chat error: ${err.message}`);
      } finally {
        operatorChatPending = false;
        if (operatorChatSubmitEl) {
          operatorChatSubmitEl.disabled = false;
        }
        operatorChatPresetEls.forEach(btn => { btn.disabled = false; });
      }
    }

    function handleTodOperatorChatSubmit(evt) {
      if (evt && typeof evt.preventDefault === 'function') {
        evt.preventDefault();
      }
      const query = operatorChatInputEl ? (operatorChatInputEl.value || '') : '';
      runOperatorChatQuery({ query, intent: '' }).then(() => {
        if (operatorChatInputEl) {
          operatorChatInputEl.value = '';
        }
      });
      return false;
    }

    function handleTodOperatorChatPreset(buttonEl) {
      const source = buttonEl || null;
      const query = source && source.getAttribute ? (source.getAttribute('data-query') || '') : '';
      const intent = source && source.getAttribute ? (source.getAttribute('data-intent') || '') : '';
      runOperatorChatQuery({ query, intent, windowMinutes: 10 });
      return false;
    }

    function renderSystemPosture(posture) {
      const data = posture || {};
      setAlertTone(data.current_alert_state);
      setStateBusValue(postureAgentEl, data.agent_state);
      setStateBusValue(postureAlertEl, data.current_alert_state);
      setStateBusValue(postureGoalsEl, Number.isFinite(Number(data.active_goal_count)) ? Number(data.active_goal_count) : 0, '0');
      setStateBusValue(postureExecutionsEl, Number.isFinite(Number(data.active_execution_count)) ? Number(data.active_execution_count) : 0, '0');
      setStateBusValue(posturePendingEl, Number.isFinite(Number(data.pending_confirmations)) ? Number(data.pending_confirmations) : 0, '0');
      setStateBusValue(postureBlockedEl, Number.isFinite(Number(data.blocked_items)) ? Number(data.blocked_items) : 0, '0');
      setStateBusValue(postureCapabilitiesEl, Number.isFinite(Number(data.registered_capabilities)) ? Number(data.registered_capabilities) : 0, '0');
      setStateBusValue(postureHealthEl, data.current_executor_health);
      postureSummaryEl.textContent = data.summary || 'SYSTEM POSTURE | No summary available.';
      if (postureLegendEl) {
        const goals = Number.isFinite(Number(data.active_goal_count)) ? Number(data.active_goal_count) : 0;
        const executions = Number.isFinite(Number(data.active_execution_count)) ? Number(data.active_execution_count) : 0;
        const pending = Number.isFinite(Number(data.pending_confirmations)) ? Number(data.pending_confirmations) : 0;
        const blocked = Number.isFinite(Number(data.blocked_items)) ? Number(data.blocked_items) : 0;
        if (goals === 0 && executions === 0 && pending === 0 && blocked === 0) {
          postureLegendEl.textContent = 'All counters are zero: system is likely between task handoffs (idle/steady state).';
        } else {
          postureLegendEl.textContent = 'Counters represent live workload pressure: goals, executions, confirmations waiting, and blocked items.';
        }
      }
    }

    function renderEngineeringLoopPanel(loop) {
      const data = loop || {};
      const currentRun = data.current_run && data.current_run.run_id ? String(data.current_run.run_id) : '-';
      const lastCycle = data.last_cycle_result && data.last_cycle_result.cycle_id ? String(data.last_cycle_result.cycle_id) : '-';

      setStateBusValue(loopCurrentRunEl, currentRun);
      setStateBusValue(loopLastCycleEl, lastCycle);
      setStateBusValue(loopThresholdStateEl, data.stop_threshold_state || '-');
      setStateBusValue(loopMaturityBandEl, data.maturity_band || '-');
      setStateBusValue(loopApprovalPendingEl, data.approval_pending_flag ? 'yes' : 'no');
      setStateBusValue(loopApprovalCountEl, Number.isFinite(Number(data.pending_approval_count)) ? Number(data.pending_approval_count) : 0, '0');

      renderBusList(
        loopTopPenaltiesEl,
        data.top_penalties || [],
        item => {
          const reason = item && item.reason ? String(item.reason) : 'unknown';
          const value = item && Number.isFinite(Number(item.value)) ? Number(item.value).toFixed(2) : '0.00';
          const detail = item && item.detail ? String(item.detail) : '';
          return `${reason} (${value})${detail ? ` | ${detail}` : ''}`;
        },
        'No active penalties.'
      );

      const phases = data.phase_trends || {};
      const phaseNames = ['create', 'plan', 'implement', 'test', 'manage'];
      const rows = [];
      for (const name of phaseNames) {
        const samples = Array.isArray(phases[name]) ? phases[name] : [];
        if (samples.length === 0) {
          rows.push(`${name}: no samples`);
          continue;
        }
        const first = Number(samples[0].score);
        const last = Number(samples[samples.length - 1].score);
        const delta = Number.isFinite(first) && Number.isFinite(last) ? (last - first) : 0;
        const trend = delta > 0.03 ? 'up' : (delta < -0.03 ? 'down' : 'flat');
        rows.push(`${name}: ${Number.isFinite(last) ? last.toFixed(2) : '0.00'} (${trend} ${delta.toFixed(2)})`);
      }
      renderBusList(loopPhaseTrendsEl, rows, item => String(item), 'No phase trend samples yet.');
    }

    async function loadStateBus() {
      loadBusBtn.disabled = true;
      try {
        const payload = {
          action: 'get-state-bus',
          top: document.getElementById('top').value,
          category: document.getElementById('category').value,
          engine: document.getElementById('engine').value,
          configPath: document.getElementById('configPath').value
        };

        const { res, data } = await fetchJsonSafe('/api/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (!res.ok || !data.ok) {
          throw new Error(data.error || `State bus request failed (${res.status})`);
        }

        const bus = data.result || {};
        const agent = bus.agent_state || {};
        const intent = bus.intent_state || {};
        const exec = bus.execution_state || {};
        const rel = bus.reliability_state || {};
        const loop = bus.engineering_loop_state || {};
        const blocks = bus.blocks || {};
        const posture = bus.system_posture || {};
        const source = bus.source_of_truth || {};
        const confidence = bus.section_confidence || {};
        const now = new Date().toLocaleTimeString();

        setStateBusValue(busModeEl, agent.mode);
        setStateBusValue(busEngineEl, agent.active_engine);
        setStateBusValue(busAlertEl, rel.current_alert_state || agent.current_alert_state);
        setStateBusValue(busEngineeringStatusEl, loop.status || posture.engineering_loop_status);
        setStateBusValue(busObjectiveEl, intent.objective_id || bus.objective_id);
        setStateBusValue(busTaskTotalEl, intent.task_funnel && Number.isFinite(Number(intent.task_funnel.total)) ? Number(intent.task_funnel.total) : 0, '0');
        setStateBusValue(busPendingReviewEl, Number.isFinite(Number(intent.pending_review_count)) ? Number(intent.pending_review_count) : 0, '0');
        setStateBusValue(busExecutionsEl, Array.isArray(exec.execution_ids) ? exec.execution_ids.length : 0, '0');
        setStateBusValue(busEngineerRunsEl, Number.isFinite(Number(loop.run_history_count)) ? Number(loop.run_history_count) : 0, '0');
        setStateBusValue(busScorecardsEl, Number.isFinite(Number(loop.scorecard_history_count)) ? Number(loop.scorecard_history_count) : 0, '0');
        setStateBusValue(busLatestScoreEl, Number.isFinite(Number(loop.latest_score)) ? Number(loop.latest_score).toFixed(2) : '-');
        setStateBusValue(busScoreTrendEl, loop.trend_direction ? `${loop.trend_direction} (${Number.isFinite(Number(loop.trend_delta)) ? Number(loop.trend_delta).toFixed(2) : '0.00'})` : '-');
        setStateBusValue(busWarningsEl, Number.isFinite(Number(rel.drift_warning_count)) ? Number(rel.drift_warning_count) : 0, '0');
        setStateBusValue(busBlocksEl, Number.isFinite(Number(blocks.routing_guardrail_block_candidates)) ? Number(blocks.routing_guardrail_block_candidates) : 0, '0');
        setStateBusValue(busWorldSourceEl, source.world_state);
        setStateBusValue(busExecutionSourceEl, source.execution_state);
        setStateBusValue(busReliabilitySourceEl, source.reliability_state);
        setConfidenceValue(busConfWorldEl, confidence.world_state);
        setConfidenceValue(busConfExecutionEl, confidence.execution_state);
        setConfidenceValue(busConfReliabilityEl, confidence.reliability_state);
        enrichConfidenceTooltip(busConfWorldEl, confidence.world_state, source.world_state);
        enrichConfidenceTooltip(busConfExecutionEl, confidence.execution_state, source.execution_state);
        enrichConfidenceTooltip(busConfReliabilityEl, confidence.reliability_state, source.reliability_state);

        renderBusList(
          busUncertaintiesEl,
          blocks.uncertainties,
          item => `- ${String(item)}`,
          'No uncertainties.'
        );

        renderBusList(
          busRoutingEl,
          (exec.recent_routing || []).slice(0, 8),
          item => {
            const taskId = item && item.task_id ? String(item.task_id) : '?';
            const engine = item && item.selected_engine ? String(item.selected_engine) : 'unknown';
            const outcome = item && item.final_outcome ? String(item.final_outcome) : 'unknown';
            return `task:${taskId} | engine:${engine} | outcome:${outcome}`;
          },
          'No routing records.'
        );

        renderBusList(
          busEngineerRunHistoryEl,
          (loop.recent_runs || []).slice(0, 8),
          item => {
            const runId = item && item.run_id ? String(item.run_id) : '?';
            const taskId = item && item.task_id ? String(item.task_id) : 'none';
            const category = item && item.task_category ? String(item.task_category) : 'unknown';
            const status = item && item.implement_status ? String(item.implement_status) : 'unknown';
            return `run:${runId} | task:${taskId} | category:${category} | implement:${status}`;
          },
          'No engineer runs recorded.'
        );

        renderBusList(
          busScoreHistoryEl,
          (loop.recent_scorecards || []).slice(0, 8),
          item => {
            const score = item && Number.isFinite(Number(item.score)) ? Number(item.score).toFixed(2) : '0.00';
            const band = item && item.band ? String(item.band) : 'unknown';
            const window = item && Number.isFinite(Number(item.window)) ? Number(item.window) : 0;
            return `score:${score} | band:${band} | window:${window}`;
          },
          'No scorecard samples recorded.'
        );
        renderScoreSparkline(busScoreSparklineEl, loop.recent_scorecards || []);

        renderSystemPosture(posture);
        renderEngineeringLoopPanel(loop);
        setLoopIndicator(loop.status || posture.engineering_loop_status, loop.latest_score, loop.trend_direction);

        busMetaEl.textContent = `State bus refreshed at ${now} (${bus.generated_at || 'unknown timestamp'})`;
      } catch (err) {
        setLoopIndicator('idle', null, 'flat');
        busMetaEl.textContent = err.message;
      } finally {
        loadBusBtn.disabled = false;
      }
    }

    function endpointFromUri(uri) {
      if (!uri || typeof uri !== 'string') return '';
      try {
        const parsed = new URL(uri);
        return parsed.pathname + (parsed.search || '');
      } catch {
        return uri;
      }
    }

    function getLogEntryKey(entry) {
      const req = entry && entry.request ? entry.request : {};
      return `${entry && entry.timestamp_utc ? entry.timestamp_utc : ''}|${req.method || ''}|${req.uri || ''}|${entry && entry.elapsed_ms ? entry.elapsed_ms : ''}`;
    }

    function updateMimIndicator() {
      const active = Date.now() < mimActiveUntilMs;
      mimIndicatorEl.classList.toggle('active', active);
      mimIndicatorTextEl.textContent = active ? 'MIM Link Active' : 'MIM Link Idle';
      compactMimBtn.classList.toggle('live', active);

      const activePresetBtn = compactModeEnabled
        ? (compactProfile === 'ops' ? compactOpsBtn : compactMimBtn)
        : compactFullBtn;
      activePresetBtn.classList.toggle('live', active);

      const otherButtons = [compactFullBtn, compactMimBtn, compactOpsBtn].filter(btn => btn !== activePresetBtn);
      for (const btn of otherButtons) {
        if (btn !== compactMimBtn || !active) {
          btn.classList.remove('live');
        }
      }
    }

    function updateTodIndicator() {
      const active = Date.now() < todActiveUntilMs;
      todIndicatorEl.classList.toggle('active', active);
      todIndicatorTextEl.textContent = active ? 'TOD Active' : 'TOD Idle';
    }

    function markMimActivity() {
      mimActiveUntilMs = Date.now() + 4500;
      updateMimIndicator();
    }

    function markTodActivity() {
      todActiveUntilMs = Date.now() + 3500;
      updateTodIndicator();
    }

    // â”€â”€ ARM indicator & health card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    function updateArmIndicator() {
      if (!armIndicatorEl || !armIndicatorTextEl) return;
      const active = Date.now() < armActiveUntilMs;
      armIndicatorEl.classList.remove('arm-active', 'arm-online', 'arm-degraded', 'arm-offline');
      if (active) {
        armIndicatorEl.classList.add('arm-active');
        armIndicatorTextEl.textContent = 'ARM Active';
      } else {
        armIndicatorTextEl.textContent = 'ARM Idle';
      }
    }

    function markArmActivity() {
      armActiveUntilMs = Date.now() + 8000;
      updateArmIndicator();
    }

    function renderArmHealthCard(entries) {
      if (!armStatusBadgeEl || !armCmdListEl) return;

      const list = Array.isArray(entries) ? entries : [];
      const nowMs = Date.now();
      const t5m = nowMs - 300000;   // 5 minutes
      const t30s = nowMs - 30000;   // 30 seconds
      const t60s = nowMs - 60000;   // 60 seconds

      // ARM endpoints detected in the MIM Flask logs
      const ARM_MOVE_PATHS = ['/move', '/servo'];
      const ARM_PING_PATHS = ['/ping', '/status', '/arm_status'];

      const armEntries = list.filter(e => {
        const uri = String((e && e.request && e.request.uri) || '');
        return ARM_MOVE_PATHS.some(p => uri.includes(p)) || ARM_PING_PATHS.some(p => uri.includes(p));
      });

      const moveEntries = list.filter(e => {
        const uri = String((e && e.request && e.request.uri) || '');
        return ARM_MOVE_PATHS.some(p => uri.includes(p));
      });

      const pingEntries = list.filter(e => {
        const uri = String((e && e.request && e.request.uri) || '');
        return ARM_PING_PATHS.some(p => uri.includes(p));
      });

      // ARM utilization â€” /move calls in last 30s
      const recentMoves = moveEntries.filter(e => {
        const tsMs = e && e.timestamp_utc ? Date.parse(e.timestamp_utc) : NaN;
        return Number.isFinite(tsMs) && tsMs >= t30s;
      });
      const moves5m = moveEntries.filter(e => {
        const tsMs = e && e.timestamp_utc ? Date.parse(e.timestamp_utc) : NaN;
        return Number.isFinite(tsMs) && tsMs >= t5m;
      }).length;

      // ARM health â€” determine from ping recency
      const latestPing = pingEntries.length > 0 ? pingEntries[pingEntries.length - 1] : null;
      const latestMove = moveEntries.length > 0 ? moveEntries[moveEntries.length - 1] : null;
      const latestPingMs = latestPing && latestPing.timestamp_utc ? Date.parse(latestPing.timestamp_utc) : NaN;
      const latestMoveMs = latestMove && latestMove.timestamp_utc ? Date.parse(latestMove.timestamp_utc) : NaN;

      // Status: online if ping within 60s, degraded if 1-5m, offline otherwise
      let armStatus = 'unknown';
      let armStatusClass = 'is-unknown';
      if (armEntries.length === 0) {
        armStatus = 'unknown';
        armStatusClass = 'is-unknown';
      } else {
        const latestArmMs = Math.max(
          Number.isFinite(latestPingMs) ? latestPingMs : 0,
          Number.isFinite(latestMoveMs) ? latestMoveMs : 0
        );
        const ageMs = nowMs - latestArmMs;
        if (ageMs < 60000) {
          armStatus = 'online';
          armStatusClass = 'is-online';
        } else if (ageMs < 300000) {
          armStatus = 'degraded';
          armStatusClass = 'is-degraded';
        } else {
          armStatus = 'offline';
          armStatusClass = 'is-offline';
        }
      }

      // Update status badge
      armStatusBadgeEl.className = `arm-status-badge ${armStatusClass}`;
      if (armStatusTextEl) armStatusTextEl.textContent = `ARM: ${armStatus.toUpperCase()}`;

      // Update ARM header indicator colour to reflect health when idle
      if (armIndicatorEl) {
        const armCurrentlyMoving = Date.now() < armActiveUntilMs;
        if (!armCurrentlyMoving) {
          armIndicatorEl.classList.remove('arm-active', 'arm-online', 'arm-degraded', 'arm-offline');
          if (armStatus !== 'unknown') {
            armIndicatorEl.classList.add(`arm-${armStatus}`);
          }
        }
      }

      // Update active light
      const armIsUsing = recentMoves.length > 0;
      if (armActiveLightEl) {
        armActiveLightEl.classList.toggle('is-using', armIsUsing);
      }
      if (armActiveLightTextEl) {
        armActiveLightTextEl.textContent = armIsUsing
          ? `ARM in use â€” ${recentMoves.length} move${recentMoves.length === 1 ? '' : 's'} in last 30s`
          : 'ARM idle â€” no recent commands';
      }

      // Update stats
      const pingAgeText = Number.isFinite(latestPingMs)
        ? `${Math.round((nowMs - latestPingMs) / 1000)}s ago`
        : 'â€”';
      const moveAgeText = Number.isFinite(latestMoveMs)
        ? `${Math.round((nowMs - latestMoveMs) / 1000)}s ago`
        : 'â€”';

      if (armStatusDetailEl) armStatusDetailEl.textContent = armStatus.toUpperCase();
      if (armLastPingEl) armLastPingEl.textContent = pingAgeText;
      if (armLastMoveEl) armLastMoveEl.textContent = moveAgeText;
      if (armMoves5mEl) armMoves5mEl.textContent = String(moves5m);

      // Summary line
      if (armHealthSummaryEl) {
        if (armEntries.length === 0) {
          armHealthSummaryEl.textContent = 'No ARM endpoint calls visible in current telemetry window. MIM may not have used the arm recently, or the log window is too small.';
        } else {
          const statusNote = armStatus === 'online'
            ? `ARM appears online â€” last activity ${pingAgeText}.`
            : armStatus === 'degraded'
            ? `ARM may be degraded â€” last activity was ${pingAgeText}. Check serial connection.`
            : armStatus === 'offline'
            ? `ARM appears offline â€” last seen ${pingAgeText}. Verify Flask server on 192.168.1.90 is running.`
            : 'ARM status cannot be determined from current telemetry.';
          const moveNote = moves5m > 0
            ? ` MIM sent ${moves5m} servo move command${moves5m === 1 ? '' : 's'} in the last 5 minutes.`
            : ' No servo moves recorded in the last 5 minutes.';
          armHealthSummaryEl.textContent = statusNote + moveNote;
        }
      }

      // Recent ARM cmd list (last 8, newest first, arm-relevant endpoints only)
      const recentArm = armEntries.slice().reverse().slice(0, 8);
      if (armCmdListEl) {
        if (recentArm.length === 0) {
          armCmdListEl.innerHTML = '<span style="color:var(--muted)">No ARM commands detected in current telemetry window.</span>';
        } else {
          armCmdListEl.innerHTML = recentArm.map(e => {
            const req = e && e.request ? e.request : {};
            const resp = e && e.response ? e.response : {};
            const ts = e.timestamp_utc ? new Date(e.timestamp_utc).toLocaleTimeString() : '';
            const uri = endpointFromUri(String(req.uri || ''));
            const statusCode = Number(resp.status_code);
            const statusClass = statusCode >= 500 ? 'status-bad' : (statusCode >= 400 ? 'status-warn' : 'status-ok');
            const elapsed = Number.isFinite(Number(e.elapsed_ms)) ? `${Number(e.elapsed_ms)}ms` : '';
            const bodySnippet = (() => {
              try {
                if (req.body) {
                  const b = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
                  if (b.servo !== undefined && b.angle !== undefined) return `servo ${b.servo} â†’ ${b.angle}Â°`;
                  const keys = Object.keys(b).slice(0, 3).map(k => `${k}:${b[k]}`).join(' ');
                  return keys || '';
                }
              } catch { /* empty */ }
              return '';
            })();
            const detail = [bodySnippet, statusCode && !isNaN(statusCode) ? `<span class="${statusClass}">${statusCode}</span>` : '', elapsed].filter(Boolean).join(' ');
            return `<div class="arm-cmd-row"><span class="arm-cmd-time">${ts}</span><span class="arm-cmd-endpoint">${escapeHtml(uri)}</span><span class="arm-cmd-detail">${detail}</span></div>`;
          }).join('');
        }
      }

      // Trigger arm activity indicator if arm is moving
      if (armIsUsing) {
        markArmActivity();
      }
    }

    function setProbeReadout(mode, text) {
      probeReadoutEl.classList.remove('awake', 'degraded', 'offline');
      if (mode) {
        probeReadoutEl.classList.add(mode);
      }
      probeReadoutEl.textContent = text;
    }

    async function runAwakeProbe() {
      probeBtn.disabled = true;
      setProbeReadout('', 'MIM probe: probing...');

      try {
        const start = performance.now();
        const payload = { action: 'ping-mim' };
        const { res, data } = await fetchJsonSafe('/api/run', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        const elapsedMs = Math.round(performance.now() - start);
        const timestamp = new Date().toLocaleTimeString();

        if (!res.ok || !data.ok) {
          setProbeReadout('offline', `MIM probe: offline | ${elapsedMs}ms | ${timestamp}`);
          return;
        }

        const reachable = data.result && data.result.reachable === true;
        if (reachable) {
          setProbeReadout('awake', `MIM probe: awake | ${elapsedMs}ms | ${timestamp}`);
          markMimActivity();
        } else {
          setProbeReadout('degraded', `MIM probe: degraded | ${elapsedMs}ms | ${timestamp}`);
        }
      } catch {
        const timestamp = new Date().toLocaleTimeString();
        setProbeReadout('offline', `MIM probe: offline | ${timestamp}`);
      } finally {
        probeBtn.disabled = false;
      }
    }

    function renderCallsTable(entries) {
      callsBodyEl.innerHTML = '';
      const list = Array.isArray(entries) ? entries : [];
      const recent = list.slice(-20).reverse();

      for (const e of recent) {
        const req = e && e.request ? e.request : {};
        const resp = e && e.response ? e.response : {};
        const statusCode = Number(resp.status_code);
        const statusClass = statusCode >= 500 ? 'status-bad' : (statusCode >= 400 ? 'status-warn' : 'status-ok');
        const hasError = resp.error ? 'yes' : 'no';
        const ts = e.timestamp_utc ? new Date(e.timestamp_utc).toLocaleTimeString() : '';

        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${ts}</td>
          <td>${req.method || ''}</td>
          <td>${endpointFromUri(req.uri || '')}</td>
          <td class="${statusClass}">${Number.isFinite(statusCode) ? statusCode : ''}</td>
          <td>${Number.isFinite(Number(e.elapsed_ms)) ? Number(e.elapsed_ms) : ''}</td>
          <td>${hasError}</td>
        `;
        callsBodyEl.appendChild(tr);
      }

      if (recent.length === 0) {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td colspan="6">No calls in current window.</td>';
        callsBodyEl.appendChild(tr);
      }
    }

    function computeApiHealth(entries) {
      const list = Array.isArray(entries) ? entries : [];
      const nowMs = Date.now();
      const oneMinuteAgo = nowMs - 60000;
      const fiveMinutesAgo = nowMs - 300000;

      let requestsPerMinute = 0;
      let latencyCount = 0;
      let latencyTotal = 0;
      let errors5m = 0;
      let slow5m = 0;

      for (const e of list) {
        const tsMs = e && e.timestamp_utc ? Date.parse(e.timestamp_utc) : NaN;
        const in1m = Number.isFinite(tsMs) && tsMs >= oneMinuteAgo;
        const in5m = Number.isFinite(tsMs) && tsMs >= fiveMinutesAgo;
        const elapsed = Number(e && e.elapsed_ms);
        const statusCode = Number(e && e.response ? e.response.status_code : NaN);
        const hasError = Boolean(e && e.response && e.response.error);

        if (in1m) {
          requestsPerMinute += 1;
        }

        if (Number.isFinite(elapsed)) {
          latencyCount += 1;
          latencyTotal += elapsed;
          if (in5m && elapsed > 200) {
            slow5m += 1;
          }
        }

        if (in5m && (hasError || (Number.isFinite(statusCode) && statusCode >= 400))) {
          errors5m += 1;
        }
      }

      const avgLatency = latencyCount > 0 ? Math.round(latencyTotal / latencyCount) : 0;

      reqPerMinEl.textContent = String(requestsPerMinute);
      avgLatencyEl.textContent = `${avgLatency}ms`;
      err5mEl.textContent = String(errors5m);
      slow5mEl.textContent = String(slow5m);
    }

    function renderExecutionEvents(entries) {
      const list = Array.isArray(entries) ? entries : [];
      const events = [];

      for (const e of list) {
        const req = e && e.request ? e.request : {};
        const uri = String(req.uri || '');
        if (!uri.includes('/gateway/capabilities/executions/')) {
          continue;
        }

        let body = req.body;
        if (typeof body === 'string') {
          try {
            body = JSON.parse(body);
          } catch {
            body = {};
          }
        }

        const status = body && body.status ? String(body.status) : 'unknown';
        const details = body && body.details ? body.details : {};
        const capability = details && details.capability ? String(details.capability) : 'execution';
        const ts = e.timestamp_utc ? new Date(e.timestamp_utc).toLocaleTimeString() : '--:--:--';

        events.push({ ts, text: `${capability} ${status}` });
      }

      const recent = events.slice(-20).reverse();
      if (recent.length === 0) {
        execEventsEl.textContent = 'No execution events in current window.';
        return;
      }

      execEventsEl.innerHTML = recent.map(ev => `<div class="exec-row"><span class="exec-time">${ev.ts}</span><span class="exec-text">${ev.text}</span></div>`).join('');
    }

    async function loadLogs() {
      const tail = Number.parseInt(tailEl.value, 10) || 80;
      loadLogsBtn.disabled = true;
      try {
        const { res, data } = await fetchJsonSafe(`/api/logs?tail=${encodeURIComponent(tail)}`);
        if (!res.ok || !data.ok) {
          throw new Error(data.error || `Log request failed (${res.status})`);
        }

        const entries = data.entries || [];
        const latest = entries.length > 0 ? entries[entries.length - 1] : null;
        const latestKey = latest ? getLogEntryKey(latest) : '';
        if (latestKey) {
          if (lastSeenLogKey && latestKey !== lastSeenLogKey) {
            markMimActivity();
          }
          lastSeenLogKey = latestKey;
        }

        renderCallsTable(entries);
        computeApiHealth(entries);
        renderExecutionEvents(entries);
        renderArmHealthCard(entries);
        const newestFirstEntries = entries.slice().reverse();
        logsEl.textContent = JSON.stringify(newestFirstEntries, null, 2);
        logsEl.scrollTop = 0;
        const now = new Date().toLocaleTimeString();
        logMetaEl.textContent = `Loaded ${data.count || 0} entries from ${data.log_path} at ${now}`;
      } catch (err) {
        logMetaEl.textContent = err.message;
      } finally {
        loadLogsBtn.disabled = false;
        updateMimIndicator();
        updateArmIndicator();
      }
    }

    function setLogsAutoRefresh() {
      if (logsTimer) {
        clearInterval(logsTimer);
        logsTimer = null;
      }
      if (autoRefreshEl.value === 'on') {
        logsTimer = setInterval(loadLogs, 3000);
      }
      syncSettingsPanelState();
    }

    function setProjectAutoRefresh() {
      if (projectTimer) {
        clearInterval(projectTimer);
        projectTimer = null;
      }
      if (projectAutoRefreshEnabled) {
        projectTimer = setInterval(loadProjectStatus, 5000);
      }
      syncSettingsPanelState();
    }

    async function quickRefreshDashboard() {
      refreshBtn.disabled = true;
      setStatus('Refreshing dashboard snapshots...');
      try {
        await Promise.all([
          loadProjectStatus(),
          loadLogs(),
          loadShareArtifacts(),
          loadOperatorChatCommitments()
        ]);
        setStatus('Dashboard refreshed (safe mode, no TOD action run).');
      } catch (err) {
        setStatus(err && err.message ? err.message : 'Dashboard refresh failed.', true);
      } finally {
        refreshBtn.disabled = false;
      }
    }

    async function safeLoadStateBus() {
      const state = String(lastKnownTaskState || 'idle').toLowerCase();
      const maybeBusy = state.includes('run') || state.includes('exec') || state.includes('progress') || state.includes('active') || state.includes('queue');
      const prompt = maybeBusy
        ? `Task state is ${state}. State bus refresh is read-only but can be heavy while work is active. Continue?`
        : 'Refresh shared state bus snapshot now?';
      if (!window.confirm(prompt)) {
        busMetaEl.textContent = 'State bus refresh cancelled by operator.';
        return;
      }
      await loadStateBus();
    }

    objectiveSelectEl.addEventListener('change', () => {
      selectedObjectiveId = objectiveSelectEl.value || '';
      previousProjectPercent = null;
      loadProjectStatus();
    });

    runBtn.addEventListener('click', () => run(buildPayload(false)));
    refreshBtn.addEventListener('click', () => quickRefreshDashboard());
    loadLogsBtn.addEventListener('click', () => loadLogs());
    loadBusBtn.addEventListener('click', () => safeLoadStateBus());
    autoRefreshEl.addEventListener('change', () => {
      const enabled = String(autoRefreshEl.value || 'on') === 'on';
      setLogsAutoRefreshPreference(enabled);
    });
    refreshShareBtn.addEventListener('click', () => loadShareArtifacts());
    operatorChatFormEl.addEventListener('submit', (evt) => {
      evt.preventDefault();
      const query = operatorChatInputEl.value || '';
      runOperatorChatQuery({ query, intent: '' }).then(() => {
        operatorChatInputEl.value = '';
      });
    });
    operatorChatPresetEls.forEach((btn) => {
      btn.addEventListener('click', () => {
        const query = btn.getAttribute('data-query') || '';
        const intent = btn.getAttribute('data-intent') || '';
        runOperatorChatQuery({ query, intent, windowMinutes: 10 });
      });
    });
    operatorChatAuditRefreshBtnEl.addEventListener('click', () => loadOperatorChatActionAudit());
    operatorChatCommitmentRefreshBtnEl.addEventListener('click', () => loadOperatorChatCommitments());
    operatorChatTrustChainClearBtnEl.addEventListener('click', () => clearOperatorChatTrustChainInspector());
    operatorChatAuditSearchEl.addEventListener('keydown', (evt) => {
      if (evt.key === 'Enter') {
        evt.preventDefault();
        loadOperatorChatActionAudit({ search: operatorChatAuditSearchEl.value || '' });
      }
    });
    operatorChatAuditActionFilterEl.addEventListener('change', () => loadOperatorChatActionAudit({ action: operatorChatAuditActionFilterEl.value || '' }));
    operatorChatAuditOutcomeFilterEl.addEventListener('change', () => loadOperatorChatActionAudit({ outcomeStatus: operatorChatAuditOutcomeFilterEl.value || '' }));
    operatorChatAuditPhaseFilterEl.addEventListener('change', () => loadOperatorChatActionAudit({ phase: operatorChatAuditPhaseFilterEl.value || '' }));
    operatorChatAuditClearBtnEl.addEventListener('click', () => {
      applyOperatorChatAuditFilterState({ ...OPERATOR_CHAT_AUDIT_DEFAULT_FILTERS });
      loadOperatorChatActionAudit({ ...OPERATOR_CHAT_AUDIT_DEFAULT_FILTERS });
    });
    operatorChatThreadEl.addEventListener('click', (evt) => {
      const actionTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-action]') : null;
      if (actionTarget) {
        previewOperatorChatSuggestedAction({
          action: actionTarget.getAttribute('data-chat-action') || '',
          label: actionTarget.getAttribute('data-chat-label') || '',
          reason: actionTarget.getAttribute('data-chat-reason') || '',
          mode: actionTarget.getAttribute('data-chat-mode') || '',
          intent: actionTarget.getAttribute('data-chat-intent') || '',
          query: actionTarget.getAttribute('data-chat-query') || '',
          objectiveId: actionTarget.getAttribute('data-chat-objective') || ''
        });
        return;
      }

      const feedbackTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-feedback-action]') : null;
      if (feedbackTarget) {
        submitOperatorChatActionFeedback({
          action: feedbackTarget.getAttribute('data-chat-feedback-action') || '',
          polarity: feedbackTarget.getAttribute('data-chat-feedback-polarity') || '',
          intent: feedbackTarget.getAttribute('data-chat-feedback-intent') || '',
          query: feedbackTarget.getAttribute('data-chat-feedback-query') || '',
          objectiveId: feedbackTarget.getAttribute('data-chat-feedback-objective') || ''
        });
        return;
      }

      const confirmTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-confirm-preview]') : null;
      if (confirmTarget) {
        const previewId = confirmTarget.getAttribute('data-chat-confirm-preview') || '';
        confirmOperatorChatAction(previewId);
        return;
      }

      const commitTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-commit-preview]') : null;
      if (commitTarget) {
        const previewId = commitTarget.getAttribute('data-chat-commit-preview') || '';
        const state = commitTarget.getAttribute('data-chat-commit-state') || 'committed';
        const duration = Number.parseInt(commitTarget.getAttribute('data-chat-commit-duration') || '15', 10);
        setOperatorChatCommitment(previewId, state, Number.isFinite(duration) ? duration : 15);
        return;
      }

      const cancelTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-cancel-preview]') : null;
      if (cancelTarget) {
        const previewId = cancelTarget.getAttribute('data-chat-cancel-preview') || '';
        cancelOperatorChatAction(previewId);
        return;
      }

      const reasoningTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-show-reasoning]') : null;
      if (reasoningTarget) {
        const bundleId = reasoningTarget.getAttribute('data-chat-show-reasoning') || '';
        showOperatorChatReasoningBundle(bundleId);
        return;
      }

      const inspectTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-inspect-chain]') : null;
      if (inspectTarget) {
        loadOperatorChatTrustChain({
          auditId: inspectTarget.getAttribute('data-chat-inspect-audit') || '',
          previewId: inspectTarget.getAttribute('data-chat-inspect-preview') || '',
          bundleId: inspectTarget.getAttribute('data-chat-inspect-bundle') || '',
          commitmentId: inspectTarget.getAttribute('data-chat-inspect-commitment') || ''
        });
        return;
      }

      const citationTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-citation-target]') : null;
      if (citationTarget) {
        const cardId = citationTarget.getAttribute('data-chat-citation-target') || '';
        focusDashboardCardById(cardId);
      }
    });
    operatorChatCommitmentListEl.addEventListener('click', (evt) => {
      const reasoningTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-show-reasoning]') : null;
      if (reasoningTarget) {
        const bundleId = reasoningTarget.getAttribute('data-chat-show-reasoning') || '';
        showOperatorChatReasoningBundle(bundleId);
        return;
      }

      const inspectTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-inspect-chain]') : null;
      if (inspectTarget) {
        loadOperatorChatTrustChain({
          auditId: inspectTarget.getAttribute('data-chat-inspect-audit') || '',
          previewId: inspectTarget.getAttribute('data-chat-inspect-preview') || '',
          bundleId: inspectTarget.getAttribute('data-chat-inspect-bundle') || '',
          commitmentId: inspectTarget.getAttribute('data-chat-inspect-commitment') || ''
        });
        return;
      }

      const updateTarget = evt.target && evt.target.closest ? evt.target.closest('[data-chat-update-commitment]') : null;
      if (updateTarget) {
        const previewId = updateTarget.getAttribute('data-chat-update-commitment') || '';
        const state = updateTarget.getAttribute('data-chat-update-commitment-state') || 'cleared';
        setOperatorChatCommitment(previewId, state);
      }
    });
    uiHelpBtnEl.addEventListener('click', () => openUiHelp());
    uiSettingsBtnEl.addEventListener('click', (evt) => {
      evt.preventDefault();
      evt.stopPropagation();
      toggleSettingsPanel();
    });
    settingsRefreshBtnEl.addEventListener('click', () => {
      closeSettingsPanel();
      quickRefreshDashboard();
    });
    settingsHelpBtnEl.addEventListener('click', () => {
      closeSettingsPanel();
      openUiHelp();
    });
    settingsLogsToggleEl.addEventListener('change', () => setLogsAutoRefreshPreference(settingsLogsToggleEl.checked));
    settingsProjectToggleEl.addEventListener('change', () => setProjectAutoRefreshPreference(settingsProjectToggleEl.checked));
    settingsPresetFullEl.addEventListener('click', () => applyCompactPreset('off'));
    settingsPresetMimEl.addEventListener('click', () => applyCompactPreset('mim'));
    settingsPresetOpsEl.addEventListener('click', () => applyCompactPreset('ops'));
    uiHelpCloseBtnEl.addEventListener('click', () => closeUiHelp());
    uiHelpModalEl.addEventListener('click', (evt) => {
      if (evt.target === uiHelpModalEl) {
        closeUiHelp();
      }
    });
    document.addEventListener('click', (evt) => {
      if (!uiSettingsPanelEl || !uiSettingsPanelEl.classList.contains('open')) {
        return;
      }
      if (evt.target && evt.target.closest && evt.target.closest('.settings-anchor')) {
        return;
      }
      closeSettingsPanel();
    });
    probeBtn.addEventListener('click', (evt) => {
      evt.preventDefault();
      runAwakeProbe();
    });
    compactFullBtn.addEventListener('click', () => applyCompactPreset('off'));
    compactMimBtn.addEventListener('click', () => applyCompactPreset('mim'));
    compactOpsBtn.addEventListener('click', () => applyCompactPreset('ops'));
    quickShareBtn.addEventListener('click', () => jumpToShareArtifacts());
    window.addEventListener('keydown', handleKeyboardShortcuts);

    quickRefreshDashboard();
    loadStateBus();
    applyOperatorChatAuditFilterState({ ...OPERATOR_CHAT_AUDIT_DEFAULT_FILTERS });
    loadOperatorChatActionAudit();
    loadOperatorChatCommitments();
    clearOperatorChatTrustChainInspector();
    setLogsAutoRefresh();
    setProjectAutoRefresh();
    initializeConsoleSettings();
    initUiBuildMeta();
    runAwakeProbe();
    initializeCompactMode();
    initializeActionWorkspaceSplit();
    updateTodIndicator();
    setInterval(updateMimIndicator, 400);
    setInterval(updateTodIndicator, 400);
  
