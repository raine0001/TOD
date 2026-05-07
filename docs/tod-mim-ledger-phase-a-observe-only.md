# TOD/MIM Ledger Phase A Observe-Only

## Current posture

Phase A remains observe-only. The live MIM PostgreSQL database is the target ledger store, but TOD does not connect to PostgreSQL directly. Instead, TOD uses the MIM SSH boundary to apply schema or append shadow rows on the MIM host.

This preserves the current authority model:

- JSON surfaces remain the active read path.
- The ledger path is write-only.
- Observer failures must not become execution blockers when listener hooks are added.

## Database target

The readiness check on 2026-05-06 confirmed:

- live engine: PostgreSQL 16
- live database: `mim`
- live role: `mim`
- listener: `127.0.0.1:5432` only
- proposed prefix: `agent_ledger_*`
- collision check: no existing `agent_ledger_*` tables
- backup coverage: `mim-backup-prod.timer` runs daily at 02:30 and calls `scripts/backup_prod.sh`

Because PostgreSQL is localhost-only on the MIM host, direct TOD-to-DB writes are not currently supported. The observe-only path therefore runs on the MIM host through SSH.

## Files added for this phase

- `db/migrations/20260506_tod_mim_message_ledger_phase_a_observe_only.sql`
  - local SQLite-compatible schema for narrow local validation
- `db/migrations/20260506_tod_mim_message_ledger_phase_a_observe_only.postgres.sql`
  - PostgreSQL rollout schema for the live MIM database
- `scripts/tod_mim_message_ledger.py`
  - local helper for schema initialization and idempotent append validation against SQLite
- `scripts/Invoke-TODMimLedgerObserveWrite.ps1`
  - TOD-side SSH wrapper for remote schema rollout and observe-only ledger appends on the MIM host

## Remote wrapper usage

Dry-run schema rollout:

```powershell
.\scripts\Invoke-TODMimLedgerObserveWrite.ps1 -Operation initialize -DryRun
```

Apply schema on the MIM host:

```powershell
.\scripts\Invoke-TODMimLedgerObserveWrite.ps1 -Operation initialize
```

Append a message shadow row using a local JSON payload file:

```powershell
.\scripts\Invoke-TODMimLedgerObserveWrite.ps1 `
  -Operation append_message `
  -PayloadFile runtime\tmp\ledger-message.json
```

The wrapper writes a local status artifact at `runtime/shared/TOD_MIM_LEDGER_OBSERVE_STATUS.latest.json`.

## Payload expectations

The wrapper currently supports these operations:

- `append_message`
- `append_event`
- `append_claim`
- `append_result`
- `append_heartbeat`
- `append_delivery_attempt`
- `append_dead_letter`

Each payload file is expected to contain a single JSON object. The object fields match the current helper contract in `scripts/tod_mim_message_ledger.py`.

## Remaining work

This slice prepares the storage and transport path only. It does not yet:

- hook listener lifecycle points
- change any read authority
- change stale-guard behavior
- add fallback/export logic from DB back into JSON
- add focused tests for the new PowerShell wrapper

The next implementation step is to add best-effort listener hooks that call the wrapper in observe-only mode and treat failures as non-blocking status signals.
