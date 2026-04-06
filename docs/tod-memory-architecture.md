# TOD Memory Architecture

## Why This Exists

TOD is already past the point where a single monolithic state document is safe as the primary memory surface.

Current observed storage shape in this repo:

- `tod/data/state.json`: about 1564 MiB
- `tod/data/engineering-memory.json`: about 21.8 MiB
- `shared_state/current_build_state.json`: about 0.08 MiB
- `shared_state/objectives.json`: about 0.02 MiB
- `tod/out/context-sync/listener/TOD_LOOP_JOURNAL.latest.json`: about 0.30 MiB

The system is already compensating for this by using listener-only fallbacks in the UI and shared-state sync paths. That means the real architecture has already started to split, but it is doing so defensively and inconsistently rather than intentionally.

## Current Problem

`tod/data/state.json` is being forced to serve too many roles at once:

- live state
- execution history
- communication surface
- fallback query surface
- partial audit trail

That creates four predictable failures:

- reads become expensive or impossible
- writes become high-risk and lock-prone
- every new feature is tempted to append instead of summarize
- retrieval becomes brute-force search instead of targeted activation

The fix is not to split files randomly. The fix is to define memory layers with different purposes, sizes, and write/read patterns.

## Target Model

TOD should use four memory layers.

### 1. Active Memory

Purpose: what the system is thinking with right now.

Requirements:

- small
- cheap to read on every loop
- replaceable
- explicitly current, not historical

TOD mapping:

- `shared_state/current_build_state.json`
- `shared_state/objectives.json`
- `tod/out/context-sync/listener/listener_state.json`
- `tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json`
- `tod/out/context-sync/listener/MIM_TOD_TASK_REQUEST.latest.json`

Rule:

- active memory should hold only current snapshots, latest status, and small per-objective summaries
- no append-only history belongs here

### 2. Episodic Memory

Purpose: raw, time-based record of what happened.

Requirements:

- append-only
- chunked by session/day/objective
- never loaded wholesale for routine UI or runtime decisions

TOD mapping:

- listener loop history
- operator chat interactions
- bridge request/result history
- execution evidence and review events

Recommended layout:

```text
tod/history/
  execution/YYYY/MM/DD/<objective-id>/<session-id>.jsonl
  operator-chat/YYYY/MM/DD/<session-id>.jsonl
  bridge/YYYY/MM/DD/<session-id>.jsonl
  maintenance/YYYY/MM/DD/<run-id>.jsonl
```

Rule:

- once an event is written to episodic storage, active memory gets only the current summary, not the full history copy

### 3. Semantic Memory

Purpose: distilled knowledge extracted from repeated events.

Requirements:

- compact
- durable
- curated or promoted from episodic evidence
- optimized for retrieval by topic, entity, or rule

TOD mapping:

- `tod/data/repo-index.json`
- `tod/data/module-summaries.json`
- `tod/data/engineering-memory.json`

Recommended evolution:

- split `engineering-memory.json` into domain-scoped knowledge files
- keep only distilled facts, patterns, rules, and stable discoveries

Current implementation direction:

- compatibility export remains at `tod/data/engineering-memory.json`
- split bucket files now live under `tod/knowledge/engineering-memory/`

Recommended layout:

```text
tod/knowledge/
  environment.json
  failures.json
  rules.json
  objectives.json
  communication.json
  preferences.json
  project-index.json
  engineering-memory/
    architecture_memory.json
    repo_memory.json
    decision_memory.json
    failure_memory.json
    pattern_memory.json
    test_memory.json
    packaging_lessons.json
    engine_performance_memory.json
    routing_decision_memory.json
```

Rule:

- semantic memory stores summaries and rules, not raw transcripts

### 4. Indexed Relational Links

Purpose: retrieval before reasoning.

Requirements:

- support lookup by objective, request, component, concept, outcome, and time
- cheap to update incrementally
- avoid full scans of episodic files

TOD mapping:

- today this is mostly implicit and ad hoc
- it should become explicit

Recommended implementation:

- first pass: small per-domain index JSON files
- durable pass: a lightweight SQLite index under `tod/index/memory.db`

Recommended indexed dimensions:

- entity: objective id, request id, task id, module, host
- concept: communication fault, validation failure, stale request, duplicate churn, UI startup
- outcome: completed, failed, deduplicated, superseded, repaired
- temporal: session, day, timestamp range
- relevance: score, recency, repeat count, severity

Rule:

- the system should retrieve a relevant slice first, then reason on that slice

## Concrete TOD Design

### Active Surfaces

Keep these small and authoritative:

- `shared_state/current_build_state.json`
- `shared_state/objectives.json`
- `tod/out/context-sync/listener/listener_state.json`
- `tod/out/context-sync/listener/TOD_MIM_COMMAND_STATUS.latest.json`
- `tod/out/context-sync/listener/TOD_MIM_TASK_RESULT.latest.json`

Add next:

- `shared_state/objectives/<objective-id>.json`
- `shared_state/runtime/<subsystem>.json`
- `shared_state/sessions/<session-id>.json`

These per-objective and per-session snapshots should replace the need to query `state.json` for current execution understanding.

### Episodic Surfaces

Move growth out of `state.json` into append-only chunks:

- listener loop records
- operator conversations
- maintenance runs
- validation receipts
- bridge execution events

Use JSONL or chunked JSON arrays with size caps. A single chunk should stay small enough to read without special handling.

### Semantic Surfaces

Promote repeated patterns into durable knowledge:

- repeated stale-guard failures become a rule or known issue
- repeated operator interventions become a workflow pattern
- stable environment facts become environment memory
- repeated module discoveries become project knowledge

This is where `engineering-memory.json` should evolve. It is currently too large to remain a single general-purpose catch-all.

### Retrieval Layer

Introduce a small retrieval API boundary:

- `Get-TODActiveContext`
- `Find-TODEpisodes`
- `Get-TODKnowledge`
- `Search-TODMemoryIndex`

No UI or runtime component should directly scan history files. They should ask the retrieval layer for a filtered result set.

## Design Rules

### Rule 1: No New History In `state.json`

`tod/data/state.json` should stop receiving append-only history. It can remain as a legacy compatibility surface during migration, but it should not continue as the long-term archive.

### Rule 2: Current State And History Must Be Separate

If a surface is read on every cycle, it must not also be the full historical record.

### Rule 3: Summaries Must Be First-Class Outputs

Every episodic stream should support promoted summaries:

- recent summary
- daily summary
- per-objective summary
- repeated-failure summary

### Rule 4: Compression Is A Feature

Low-value detail should age out of active memory and be compressed into summaries. High-frequency duplicate records should be coalesced into episode summaries instead of retained as equally weighted live context.

### Rule 5: Retrieval Before Reasoning

TOD should reason over:

- the selected objective
- current active runtime snapshots
- a narrow set of recent relevant episodes
- a compact set of semantic facts

It should not reason by loading the entire state archive.

## Migration Plan

### Phase 1: Stop The Bleeding

- treat `tod/data/state.json` as legacy compatibility state, not primary memory
- forbid new append-only history writes into it
- ensure UI, listener, watchdog, and training flows use active shared-state surfaces first
- keep oversized-state guards in place

### Phase 2: Create Episodic Logs

- introduce chunked execution logs under `tod/history/`
- move loop journal growth and conversation growth into append-only chunks
- keep only latest snapshots and summaries in `shared_state/`

### Phase 3: Split Semantic Memory

- replace `engineering-memory.json` with domain files under `tod/knowledge/`
- add promotion jobs that summarize repeated evidence into stable rules and discoveries

### Phase 4: Add Explicit Indexes

- start with JSON indexes if needed for speed of implementation
- move to SQLite when cross-domain lookups become common
- expose retrieval functions so callers do not scan history directly

### Phase 5: Retire Direct Monolith Reads

- gradually remove direct full-state assumptions from `TOD.ps1` and related scripts
- keep only narrow compatibility shims for legacy actions that still depend on `state.json`

## Immediate TOD Priorities

1. Stop storing new historical growth in `tod/data/state.json`.
2. Break `tod/data/engineering-memory.json` into domain-scoped semantic memory files.
3. Add chunked episodic execution and communication logs under `tod/history/`.
4. Introduce per-objective active snapshots under `shared_state/objectives/`.
5. Add a retrieval boundary so UI, listener, and operator flows ask for relevant context instead of reading bulk files.

## What Success Looks Like

TOD should be able to answer a live question by reading:

- one active objective snapshot
- one current runtime snapshot
- a handful of recent episodic chunks
- a few semantic memory records

It should not need to parse a multi-gigabyte state document to decide what is true right now.