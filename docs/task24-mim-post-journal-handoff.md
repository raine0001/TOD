# Task 24 Handoff: MIM POST /journal

## Goal
Enable durable sync/lifecycle event logging from TOD to MIM by implementing `POST /journal` on MIM.

## Current Behavior (Before MIM Change)
- TOD already attempts remote journal writes in `sync-mim`.
- On current server, `POST /journal` returns `405 Method Not Allowed`.
- TOD falls back safely and records:
  - local TOD journal entry
  - engineering memory note
  - `remote_journal_logged = false`

## Required MIM Endpoint Contract
- Method: `POST`
- Path: `/journal`
- Request body (JSON):

```json
{
  "actor": "tod",
  "action": "sync_mim",
  "target_type": "sync_state",
  "target_id": "sync_state",
  "summary": "sync-mim decision=ok status=none actions="
}
```

- Response body (JSON): should normalize to existing JournalEntry shape:

```json
{
  "entry_id": "string or int",
  "actor": "string",
  "action": "string",
  "target_type": "string",
  "target_id": "string",
  "summary": "string",
  "timestamp": "ISO-8601"
}
```

## OpenAPI Requirement
Expose `/journal` for both:
- `GET /journal`
- `POST /journal`

## Acceptance Verification
1. Call `POST /journal` directly against MIM and confirm `2xx`.
2. Confirm entry persistence in MIM storage.
3. Confirm OpenAPI includes `POST /journal`.
4. Run from TOD:

```powershell
.\scripts\TOD.ps1 -Action sync-mim -ConfigPath .\tod\config\tod-config.json
```

Expected after MIM fix:
- `remote_journal_logged` is `true` in sync-mim output.

## TOD-Side Integration Already Present
- Client call: `New-MimJournalEntry` in `client/mim_api_client.ps1`.
- Request mapper: `Convert-ToMimJournalEntry` in `client/mim_api_helpers.ps1`.
- Sync path caller: `Try-LogSyncToMimJournal` in `scripts/TOD.ps1`.

## Notes
- No TOD-side behavior change is required after MIM enables `POST /journal`; re-run `sync-mim` to validate closure of the gap.
