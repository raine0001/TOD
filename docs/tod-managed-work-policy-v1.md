# TOD Managed Work Policy v1

This policy defines how TOD manages unstaged changes before the next guarded-write loop.

Principles:

- Product code, tests, docs, and config inside the allowed TOD patch surface remain in the managed patch set.
- Tracked runtime memory and engineering-memory files are evidence, not product patch content.
- Disposable support artifacts are deleted only when they are untracked and match explicit TOD cleanup patterns.
- Cleanup must leave a machine-readable record so TOD can explain what it archived, restored, and removed.

Procedure:

1. Run `./scripts/Invoke-TODManagedWork.ps1 -EmitJson` to classify the current worktree.
2. Review `shared_state/agentmim/tod_managed_work.latest.json`.
3. If blocked tracked runtime-memory files are present, run `./scripts/Invoke-TODManagedWork.ps1 -ApplyCleanup -EmitJson`.
4. TOD archives each blocked tracked file under `shared_state/agentmim/managed-work-archives/<timestamp>/...` before cleanup.
5. TOD restores those blocked tracked files from `HEAD` so the working tree is reset to product-edit scope.
6. TOD removes only untracked support artifacts matched by the TOD managed-work policy.
7. Review `shared_state/agentmim/tod_managed_work_cleanup.latest.json` and the refreshed `shared_state/agentmim/tod_managed_work.latest.json`.

Current TOD blocked runtime-memory surfaces:

- `tod/data/engineering-memory.json`
- `tod/knowledge/engineering-memory/engine_performance_memory.json`
- `tod/knowledge/engineering-memory/routing_decision_memory.json`

Current TOD support-artifact cleanup patterns:

- `tmp_`
- `raw-sweep`

Operational rule:

- If a blocked tracked file reappears as modified, TOD should archive and restore it again before continuing product edits.
- If cleanup or classification leaves the repo ready for managed patch work, TOD should route further direction through TOD-MIM consensus artifacts and dialog rather than asking the operator for next steps.