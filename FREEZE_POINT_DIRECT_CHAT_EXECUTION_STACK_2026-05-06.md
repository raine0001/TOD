# TOD Direct-Chat Execution Stack Freeze Point

Generated: 2026-05-06

## Commit State

- Latest commit: `f8eecf371751abbe458cea4e558d617cb72d6133`
- Short hash: `f8eecf3`
- Commit date: `2026-05-05 20:11:52 -0700`
- Commit subject: `Sync local TOD runtime state and routing changes`
- Upstream comparison: `origin/main`
- Ahead/behind upstream: `0 / 0`
- Freeze-point note: no committed changes are ahead of the last pushed branch tip; the current freeze state is a dirty working tree on top of `origin/main`.

## Files Changed Since Last Push

Because `HEAD` matches `origin/main`, the files changed since last push are the current working-tree changes.

### Source and test changes to preserve

- `scripts/Invoke-TODConversationalReply.ps1`
- `scripts/Start-TOD-UI.ps1`
- `scripts/TOD.ps1`
- `scripts/engines/LocalExecutionEngine.ps1`
- `tests/TOD.ConversationalReply.Tests.ps1`
- `tests/TOD.LocalFallbackExecutor.Tests.ps1`
- `tests/TOD.StartUiConversationRoute.Tests.ps1`
- `tests/TOD.BoundedEditMaterialization.Tests.ps1` (untracked)

### Generated or runtime changes mixed into the tree

- `shared_state/watchdog-repair/MIM_TOD_TASK_REQUEST.latest.json`
- `tod/data/engineering-memory.json`
- `tod/knowledge/engineering-memory/engine_performance_memory.json`
- `tod/knowledge/engineering-memory/routing_decision_memory.json`
- `scripts/chat-local-dispatch-ebf1954df46a4310b24224d127fa81b9.ps1` (untracked bounded smoke artifact)

## Tests Passing

Validated on 2026-05-06 with focused direct-chat stack suites.

- `tests/TOD.StartUiConversationRoute.Tests.ps1`: 9 passed
- `tests/TOD.ConversationalReply.Tests.ps1`: 10 passed
- `tests/TOD.LocalFallbackExecutor.Tests.ps1`: 9 passed
- Total: 28 passed, 0 failed, 0 skipped, 0 pending, 0 inconclusive

## Live Smoke Task IDs

Latest runtime worker artifacts in `tod/out/background-chat` show these recent smoke tasks:

- `TSKCHAT-7E2D06622DDA`: completed via `local`; summary: validated bounded target in `scripts/TOD.ps1` and published execution evidence
- `TSKCHAT-F87A3303D328`: completed via `local`; summary: bounded local fallback completed for `scripts/chat-local-dispatch-0cc66493be9e4953ad0a2386d36b6bab.ps1`
- `TSKCHAT-407C2B7FF0E6`: blocked as expected; `reason_code=blocked_missing_bounded_edit_mode`
- `TSKCHAT-DF878E25C010`: blocked as expected; `reason_code=blocked_missing_bounded_edit_mode`
- `TSKCHAT-9FAB99B5EA46`: blocked as expected; `reason_code=blocked_missing_bounded_edit_mode`
- `TSKCHAT-5125C9B54211`: freshest empty stdout artifact; treat as non-authoritative until a matching persisted state or populated log is inspected

## Known Working Paths

- UI route backend queues structured TOD direct-chat requests immediately for background execution.
- Activity fallback prefers persisted terminal state over stale queued direct-chat heads.
- Conversational direct-chat requests classify bounded code-change work to `local` without codex fallback when the request is locally supported.
- Bounded local code-change requests complete through `LocalExecutionEngine` and publish execution evidence.
- Validation-only direct-chat requests remain local-first and do not require file mutation.
- Abstract async direct-chat requests without a single bounded target file persist a terminal blocker with `reason_code=blocked_missing_bounded_edit_mode` instead of hanging queued.
- Async worker startup failures persist readable terminal blocked state instead of leaving tasks queued forever.
- Canonical objective truth is preferred over stale durable memory during fallback and status responses.

## Known Limitations

- Bounded edit materialization still requires exactly one explicit target file before `LocalExecutionEngine` can proceed.
- The localhost TOD Command Console page currently shows repeated `404` and `ERR_CONNECTION_RESET` noise, so browser-console output is not a reliable smoke authority for freeze decisions.
- One recent worker artifact, `TSKCHAT-5125C9B54211`, has an empty stdout log and should not be used as the sole evidence source.
- The working tree is not clean; source edits and runtime artifacts are currently interleaved.
- No freeze commit has been created for the current stack state yet.

## Generated and Runtime Files To Exclude

Exclude these from design diffs, review scope, and any clean freeze commit unless explicitly needed:

- `tod/out/**`
- `shared_state/watchdog-repair/*.latest.json`
- `tod/data/engineering-memory.json`
- `tod/knowledge/engineering-memory/*.json`
- `scripts/chat-local-dispatch-*.ps1`
- temporary fixture directories under `tod/out/tests/tmp-*`
- background worker logs under `tod/out/background-chat/*`

## Safe To Continue To Message-Ledger Design?

Yes, with two caveats.

- Technical readiness: the direct-chat execution stack is currently stable enough to continue into message-ledger design because the focused route, async terminal-state, blocker, and local fallback paths are all green.
- Operational caution: continue from the current source/test changes, but keep runtime artifacts out of the design diff and capture a clean checkpoint before broadening scope if you want a durable rollback point.

## Freeze Summary

This is a reasonable freeze point for message-ledger design work. The core direct-chat stack behavior is validated, the expected blocker path is explicit instead of silent, and the remaining issues are mostly hygiene and runtime-noise concerns rather than unresolved execution-path regressions.