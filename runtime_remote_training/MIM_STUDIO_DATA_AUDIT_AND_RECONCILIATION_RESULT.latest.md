# Studio Data Audit And Reconciliation V1

- Status: passed_with_watch
- Generated: 2026-06-04T19:59:56Z
- Context-sync validation: passed
- Latest TOD task: objective-3458-task-1780598281 / succeeded

## Pages

### training
- Route: /studio/training
- Status: source_traceable
- Source Trust: Mixed
- Source: Training Scoreboard :: artifact :: runtime_remote_training/MIM_TOD_TRAINING_SCOREBOARD.latest.json :: needs_attention_with_training_active
- Source: Hourly Reflection :: artifact :: runtime_remote_training/MIM_TOD_HOURLY_REFLECTION.latest.json :: available
- Source: Context Sync Validation :: artifact :: tod/out/context-sync/listener/MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json :: passed
- Source: TOD Validation Result :: artifact :: runtime_remote_training/TOD_VALIDATION_RESULT.latest.json :: passed

### health
- Route: /studio/health
- Status: source_traceable
- Source Trust: Fresh
- Source: Context Sync Status :: artifact :: tod/out/context-sync/MIM_CONTEXT_SYNC_STATUS.latest.json :: available
- Source: Context Sync Validation :: artifact :: tod/out/context-sync/listener/MIM_CONTEXT_SYNC_DATA_ACCURACY_VALIDATION.latest.json :: passed
- Source: TOD Integration Status :: artifact :: tod/out/context-sync/listener/TOD_INTEGRATION_STATUS.latest.json :: available
- Source: TOD Latest Result :: artifact :: tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json :: succeeded

### projects
- Route: /studio/projects
- Status: source_traceable
- Source Trust: Fresh
- Source: Studio Projects Table :: database_table :: studio_projects :: queried_by_page
- Source: Studio Project Events Table :: database_table :: studio_project_events :: queried_by_page
- Source: TOD Latest Result :: artifact :: tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json :: succeeded

### apps
- Route: /studio/apps
- Status: source_traceable
- Source Trust: Stale
- Source: App Source Registry :: code_registry :: tmp_remote_mim/core/routers/studio.py::APP_SOURCE_REGISTRY :: registered
- Source: TOD App Source Scan :: artifact :: runtime_remote_training/MIM_TOD_APP_SOURCE_SCAN.latest.json :: available
- Source: AgentMIM Verification :: artifact :: shared_state/agentmim/comm_app_verification.latest.json :: available

### reports
- Route: /studio/reports
- Status: source_traceable
- Source Trust: Watched
- Source: Report Dataset Registry :: code_registry :: tmp_remote_mim/core/routers/studio.py::REPORT_DATASETS :: registered
- Source: Report Canvases Table :: database_table :: studio_report_canvases :: queried_by_page
