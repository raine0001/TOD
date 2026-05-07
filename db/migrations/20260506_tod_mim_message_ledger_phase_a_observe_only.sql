PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS agent_ledger_conversation_threads (
    thread_id TEXT PRIMARY KEY,
    thread_type TEXT NOT NULL DEFAULT '',
    root_message_id TEXT DEFAULT NULL,
    created_by_agent TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    closed_at TEXT DEFAULT NULL,
    thread_state TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS agent_ledger_messages (
    message_id TEXT PRIMARY KEY,
    thread_id TEXT DEFAULT NULL,
    from_agent TEXT NOT NULL DEFAULT '',
    to_agent TEXT NOT NULL DEFAULT '',
    task_id TEXT DEFAULT NULL,
    correlation_id TEXT DEFAULT NULL,
    message_type TEXT NOT NULL DEFAULT '',
    payload_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    acknowledged_at TEXT DEFAULT NULL,
    completed_at TEXT DEFAULT NULL,
    expires_at TEXT DEFAULT NULL,
    superseded_by_message_id TEXT DEFAULT NULL,
    source_surface TEXT NOT NULL DEFAULT '',
    observed_at TEXT NOT NULL,
    FOREIGN KEY(thread_id) REFERENCES agent_ledger_conversation_threads(thread_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_messages_to_agent_status_created_at
    ON agent_ledger_messages(to_agent, status, created_at);
CREATE INDEX IF NOT EXISTS idx_agent_ledger_messages_correlation_id
    ON agent_ledger_messages(correlation_id);
CREATE INDEX IF NOT EXISTS idx_agent_ledger_messages_task_id
    ON agent_ledger_messages(task_id);
CREATE INDEX IF NOT EXISTS idx_agent_ledger_messages_thread_created_at
    ON agent_ledger_messages(thread_id, created_at);

CREATE TABLE IF NOT EXISTS agent_ledger_message_events (
    event_id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    event_status TEXT NOT NULL DEFAULT '',
    event_payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    actor_agent TEXT NOT NULL DEFAULT '',
    source_surface TEXT NOT NULL DEFAULT '',
    FOREIGN KEY(message_id) REFERENCES agent_ledger_messages(message_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_message_events_message_created_at
    ON agent_ledger_message_events(message_id, created_at);

CREATE TABLE IF NOT EXISTS agent_ledger_task_claims (
    claim_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    message_id TEXT DEFAULT NULL,
    claimed_by_agent TEXT NOT NULL,
    claim_status TEXT NOT NULL,
    created_at TEXT NOT NULL,
    released_at TEXT DEFAULT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    FOREIGN KEY(message_id) REFERENCES agent_ledger_messages(message_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_task_claims_task_id_created_at
    ON agent_ledger_task_claims(task_id, created_at);

CREATE TABLE IF NOT EXISTS agent_ledger_task_results (
    result_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    message_id TEXT DEFAULT NULL,
    correlation_id TEXT DEFAULT NULL,
    result_status TEXT NOT NULL,
    result_payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(message_id) REFERENCES agent_ledger_messages(message_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_task_results_task_id_created_at
    ON agent_ledger_task_results(task_id, created_at);

CREATE TABLE IF NOT EXISTS agent_ledger_heartbeats (
    heartbeat_id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    status TEXT NOT NULL,
    heartbeat_payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT DEFAULT NULL,
    source_surface TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_heartbeats_agent_created_at
    ON agent_ledger_heartbeats(agent_id, created_at);

CREATE TABLE IF NOT EXISTS agent_ledger_delivery_attempts (
    attempt_id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    attempt_number INTEGER NOT NULL DEFAULT 1,
    delivery_target TEXT NOT NULL DEFAULT '',
    attempt_status TEXT NOT NULL,
    error_code TEXT DEFAULT NULL,
    error_detail TEXT DEFAULT NULL,
    attempted_at TEXT NOT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    FOREIGN KEY(message_id) REFERENCES agent_ledger_messages(message_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_delivery_attempts_message_attempted_at
    ON agent_ledger_delivery_attempts(message_id, attempted_at);

CREATE TABLE IF NOT EXISTS agent_ledger_dead_letters (
    dead_letter_id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    dead_letter_reason TEXT NOT NULL,
    final_status TEXT NOT NULL,
    moved_at TEXT NOT NULL,
    recovery_hint_json TEXT DEFAULT NULL,
    payload_json TEXT NOT NULL DEFAULT '{}',
    FOREIGN KEY(message_id) REFERENCES agent_ledger_messages(message_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_ledger_dead_letters_message_id
    ON agent_ledger_dead_letters(message_id);
