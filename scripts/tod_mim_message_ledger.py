import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any, Dict


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB_PATH = REPO_ROOT / 'runtime' / 'shared' / 'TOD_MIM_MESSAGE_LEDGER.sqlite3'
DEFAULT_MIGRATION_PATH = REPO_ROOT / 'db' / 'migrations' / '20260506_tod_mim_message_ledger_phase_a_observe_only.sql'
THREADS_TABLE = 'agent_ledger_conversation_threads'
MESSAGES_TABLE = 'agent_ledger_messages'
MESSAGE_EVENTS_TABLE = 'agent_ledger_message_events'
TASK_CLAIMS_TABLE = 'agent_ledger_task_claims'
TASK_RESULTS_TABLE = 'agent_ledger_task_results'
HEARTBEATS_TABLE = 'agent_ledger_heartbeats'
DELIVERY_ATTEMPTS_TABLE = 'agent_ledger_delivery_attempts'
DEAD_LETTERS_TABLE = 'agent_ledger_dead_letters'


def utc_text(value: Any, fallback: str = '') -> str:
	if value is None:
		return fallback
	return str(value)


def load_json_file(path: Path) -> Dict[str, Any]:
	text = path.read_text(encoding='utf-8')
	if not text.strip():
		return {}
	data = json.loads(text)
	if isinstance(data, dict):
		return data
	raise ValueError(f'payload must be a JSON object: {path}')


def json_text(payload: Any) -> str:
	return json.dumps(payload, ensure_ascii=True, separators=(',', ':'), sort_keys=True)


def ensure_parent(path: Path) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)


def connect(db_path: Path) -> sqlite3.Connection:
	ensure_parent(db_path)
	conn = sqlite3.connect(str(db_path))
	conn.row_factory = sqlite3.Row
	conn.execute('PRAGMA foreign_keys = ON')
	conn.execute('PRAGMA journal_mode = WAL')
	return conn


def apply_migration(conn: sqlite3.Connection, migration_path: Path) -> None:
	sql = migration_path.read_text(encoding='utf-8')
	conn.executescript(sql)
	conn.commit()


def ensure_thread(conn: sqlite3.Connection, payload: Dict[str, Any]) -> None:
	thread_id = utc_text(payload.get('thread_id'))
	if not thread_id:
		return
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_conversation_threads (
			thread_id, thread_type, root_message_id, created_by_agent, created_at, closed_at, thread_state
		) VALUES (?, ?, ?, ?, ?, ?, ?)
		''',
		(
			thread_id,
			utc_text(payload.get('thread_type')),
			utc_text(payload.get('root_message_id')) or None,
			utc_text(payload.get('created_by_agent')),
			utc_text(payload.get('created_at')),
			utc_text(payload.get('closed_at')) or None,
			utc_text(payload.get('thread_state')),
		),
	)


def append_message(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	ensure_thread(conn, payload)
	message_id = utc_text(payload.get('message_id'))
	if not message_id:
		raise ValueError('message_id is required')
	existed = conn.execute(f'SELECT 1 FROM {MESSAGES_TABLE} WHERE message_id = ?', (message_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_messages (
			message_id, thread_id, from_agent, to_agent, task_id, correlation_id, message_type,
			payload_json, status, created_at, acknowledged_at, completed_at, expires_at,
			superseded_by_message_id, source_surface, observed_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		''',
		(
			message_id,
			utc_text(payload.get('thread_id')) or None,
			utc_text(payload.get('from_agent')),
			utc_text(payload.get('to_agent')),
			utc_text(payload.get('task_id')) or None,
			utc_text(payload.get('correlation_id')) or None,
			utc_text(payload.get('message_type')),
			json_text(payload.get('payload', payload)),
			utc_text(payload.get('status')),
			utc_text(payload.get('created_at')),
			utc_text(payload.get('acknowledged_at')) or None,
			utc_text(payload.get('completed_at')) or None,
			utc_text(payload.get('expires_at')) or None,
			utc_text(payload.get('superseded_by_message_id')) or None,
			utc_text(payload.get('source_surface')),
			utc_text(payload.get('observed_at')),
		),
	)
	return {'table': MESSAGES_TABLE, 'id': message_id, 'inserted': not existed, 'idempotent': existed}


def append_event(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	event_id = utc_text(payload.get('event_id'))
	message_id = utc_text(payload.get('message_id'))
	if not event_id or not message_id:
		raise ValueError('event_id and message_id are required')
	existed = conn.execute(f'SELECT 1 FROM {MESSAGE_EVENTS_TABLE} WHERE event_id = ?', (event_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_message_events (
			event_id, message_id, event_type, event_status, event_payload_json, created_at, actor_agent, source_surface
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		''',
		(
			event_id,
			message_id,
			utc_text(payload.get('event_type')),
			utc_text(payload.get('event_status')),
			json_text(payload.get('payload', payload)),
			utc_text(payload.get('created_at')),
			utc_text(payload.get('actor_agent')),
			utc_text(payload.get('source_surface')),
		),
	)
	return {'table': MESSAGE_EVENTS_TABLE, 'id': event_id, 'inserted': not existed, 'idempotent': existed}


def append_claim(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	claim_id = utc_text(payload.get('claim_id'))
	if not claim_id:
		raise ValueError('claim_id is required')
	existed = conn.execute(f'SELECT 1 FROM {TASK_CLAIMS_TABLE} WHERE claim_id = ?', (claim_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_task_claims (
			claim_id, task_id, message_id, claimed_by_agent, claim_status, created_at, released_at, payload_json
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		''',
		(
			claim_id,
			utc_text(payload.get('task_id')),
			utc_text(payload.get('message_id')) or None,
			utc_text(payload.get('claimed_by_agent')),
			utc_text(payload.get('claim_status')),
			utc_text(payload.get('created_at')),
			utc_text(payload.get('released_at')) or None,
			json_text(payload.get('payload', payload)),
		),
	)
	return {'table': TASK_CLAIMS_TABLE, 'id': claim_id, 'inserted': not existed, 'idempotent': existed}


def append_result(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	result_id = utc_text(payload.get('result_id'))
	if not result_id:
		raise ValueError('result_id is required')
	existed = conn.execute(f'SELECT 1 FROM {TASK_RESULTS_TABLE} WHERE result_id = ?', (result_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_task_results (
			result_id, task_id, message_id, correlation_id, result_status, result_payload_json, created_at
		) VALUES (?, ?, ?, ?, ?, ?, ?)
		''',
		(
			result_id,
			utc_text(payload.get('task_id')),
			utc_text(payload.get('message_id')) or None,
			utc_text(payload.get('correlation_id')) or None,
			utc_text(payload.get('result_status')),
			json_text(payload.get('payload', payload)),
			utc_text(payload.get('created_at')),
		),
	)
	return {'table': TASK_RESULTS_TABLE, 'id': result_id, 'inserted': not existed, 'idempotent': existed}


def append_heartbeat(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	heartbeat_id = utc_text(payload.get('heartbeat_id'))
	if not heartbeat_id:
		raise ValueError('heartbeat_id is required')
	existed = conn.execute(f'SELECT 1 FROM {HEARTBEATS_TABLE} WHERE heartbeat_id = ?', (heartbeat_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_heartbeats (
			heartbeat_id, agent_id, status, heartbeat_payload_json, created_at, expires_at, source_surface
		) VALUES (?, ?, ?, ?, ?, ?, ?)
		''',
		(
			heartbeat_id,
			utc_text(payload.get('agent_id')),
			utc_text(payload.get('status')),
			json_text(payload.get('payload', payload)),
			utc_text(payload.get('created_at')),
			utc_text(payload.get('expires_at')) or None,
			utc_text(payload.get('source_surface')),
		),
	)
	return {'table': HEARTBEATS_TABLE, 'id': heartbeat_id, 'inserted': not existed, 'idempotent': existed}


def append_delivery_attempt(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	attempt_id = utc_text(payload.get('attempt_id'))
	if not attempt_id:
		raise ValueError('attempt_id is required')
	existed = conn.execute(f'SELECT 1 FROM {DELIVERY_ATTEMPTS_TABLE} WHERE attempt_id = ?', (attempt_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_delivery_attempts (
			attempt_id, message_id, attempt_number, delivery_target, attempt_status,
			error_code, error_detail, attempted_at, payload_json
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		''',
		(
			attempt_id,
			utc_text(payload.get('message_id')),
			int(payload.get('attempt_number', 1)),
			utc_text(payload.get('delivery_target')),
			utc_text(payload.get('attempt_status')),
			utc_text(payload.get('error_code')) or None,
			utc_text(payload.get('error_detail')) or None,
			utc_text(payload.get('attempted_at')),
			json_text(payload.get('payload', payload)),
		),
	)
	return {'table': DELIVERY_ATTEMPTS_TABLE, 'id': attempt_id, 'inserted': not existed, 'idempotent': existed}


def append_dead_letter(conn: sqlite3.Connection, payload: Dict[str, Any]) -> Dict[str, Any]:
	dead_letter_id = utc_text(payload.get('dead_letter_id'))
	if not dead_letter_id:
		raise ValueError('dead_letter_id is required')
	existed = conn.execute(f'SELECT 1 FROM {DEAD_LETTERS_TABLE} WHERE dead_letter_id = ?', (dead_letter_id,)).fetchone() is not None
	conn.execute(
		'''
		INSERT OR IGNORE INTO agent_ledger_dead_letters (
			dead_letter_id, message_id, dead_letter_reason, final_status, moved_at, recovery_hint_json, payload_json
		) VALUES (?, ?, ?, ?, ?, ?, ?)
		''',
		(
			dead_letter_id,
			utc_text(payload.get('message_id')),
			utc_text(payload.get('dead_letter_reason')),
			utc_text(payload.get('final_status')),
			utc_text(payload.get('moved_at')),
			json_text(payload.get('recovery_hint', {})),
			json_text(payload.get('payload', payload)),
		),
	)
	return {'table': DEAD_LETTERS_TABLE, 'id': dead_letter_id, 'inserted': not existed, 'idempotent': existed}


OPERATIONS = {
	'append_message': append_message,
	'append_event': append_event,
	'append_claim': append_claim,
	'append_result': append_result,
	'append_heartbeat': append_heartbeat,
	'append_delivery_attempt': append_delivery_attempt,
	'append_dead_letter': append_dead_letter,
}


def table_counts(conn: sqlite3.Connection) -> Dict[str, int]:
	result: Dict[str, int] = {}
	for table in (
		MESSAGES_TABLE,
		MESSAGE_EVENTS_TABLE,
		TASK_CLAIMS_TABLE,
		TASK_RESULTS_TABLE,
		HEARTBEATS_TABLE,
		THREADS_TABLE,
		DELIVERY_ATTEMPTS_TABLE,
		DEAD_LETTERS_TABLE,
	):
		row = conn.execute(f'SELECT COUNT(*) AS count FROM {table}').fetchone()
		result[table] = int(row['count'])
	return result


def write_status(path: Path, status: Dict[str, Any]) -> None:
	ensure_parent(path)
	path.write_text(json.dumps(status, ensure_ascii=True, indent=2) + '\n', encoding='utf-8')


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument('--db', default=str(DEFAULT_DB_PATH))
	parser.add_argument('--migration', default=str(DEFAULT_MIGRATION_PATH))
	parser.add_argument('--status-path', required=True)
	parser.add_argument('--mode', default='observe_only')
	parser.add_argument('--operation', choices=['initialize', *OPERATIONS.keys()], required=True)
	parser.add_argument('--payload-file')
	args = parser.parse_args()

	db_path = Path(args.db)
	migration_path = Path(args.migration)
	status_path = Path(args.status_path)

	payload: Dict[str, Any] = {}
	if args.payload_file:
		payload = load_json_file(Path(args.payload_file))

	try:
		conn = connect(db_path)
		try:
			apply_migration(conn, migration_path)
			operation_result: Dict[str, Any]
			if args.operation == 'initialize':
				operation_result = {'table': 'schema', 'id': 'initialize', 'inserted': True, 'idempotent': False}
			else:
				operation_result = OPERATIONS[args.operation](conn, payload)
			conn.commit()
			status = {
				'generated_at': payload.get('observed_at') or payload.get('created_at') or payload.get('attempted_at') or payload.get('moved_at') or '',
				'mode': args.mode,
				'enabled': args.mode == 'observe_only',
				'db_path': str(db_path),
				'migration_path': str(migration_path),
				'last_operation': args.operation,
				'last_operation_result': operation_result,
				'counts': table_counts(conn),
				'ok': True,
			}
			write_status(status_path, status)
			sys.stdout.write(json.dumps(status, ensure_ascii=True))
			return 0
		finally:
			conn.close()
	except Exception as exc:
		status = {
			'generated_at': payload.get('observed_at') or payload.get('created_at') or '',
			'mode': args.mode,
			'enabled': args.mode == 'observe_only',
			'db_path': str(db_path),
			'migration_path': str(migration_path),
			'last_operation': args.operation,
			'ok': False,
			'error': str(exc),
		}
		write_status(status_path, status)
		sys.stdout.write(json.dumps(status, ensure_ascii=True))
		return 1


if __name__ == '__main__':
	raise SystemExit(main())
