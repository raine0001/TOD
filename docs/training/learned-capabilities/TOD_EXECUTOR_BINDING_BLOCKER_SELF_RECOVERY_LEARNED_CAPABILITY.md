# TOD Executor Binding Blocker Self-Recovery Learned Capability

Capability Name: TOD executor binding blocker self-recovery

Trigger: TOD reports that task identity is repaired but no executor binding exists for the queued next step.

Reality: The active execution lane may have a valid task, while older shared truth or stale repair markers still point at a blocked task. A stale `TOD_EXECUTOR_BINDING_REPAIR.latest.json` marker can suppress republishing even when the current request no longer contains the local executor binding.

Observation: `/tod/ui/state` showed `Binding Required` with `executor_binding_already_attempted`, but `MIM_TOD_TASK_REQUEST.latest.json` had been overwritten by a different MIM coordination request and no longer carried `selected_executor=local`, `active_engine=local`, or the `LocalExecutionEngine` binding.

Root Cause: TOD treated an old attempted repair marker as terminal proof instead of checking whether the current authoritative task request still contained the materialized local executor binding.

Blocker Class: coordination_blocker plus data_blocker.

Decomposition Ladder:

1. Verify whether the visible blocker is real by reading `/tod/ui/state`.
2. Check whether `executor_binding.status` is `missing`, `ready`, or stale.
3. Read `TOD_EXECUTOR_BINDING_REPAIR.latest.json` and confirm whether it proves a current publish, not merely an old attempt.
4. Read `MIM_TOD_TASK_REQUEST.latest.json` and verify `objective_id`, `task_id`, `selected_executor`, `active_engine`, and `executor_binding`.
5. If the marker is old and the current request lacks the binding, republish exactly one local executor binding request.
6. Validate both serving lanes report `binding=ready`.
7. Continue to the next blocker only after binding is no longer the active blocker.

Smallest Successful Rung: Treat `executor_binding_already_attempted` as stale unless the current task request still proves the local binding.

Implementation Summary: The replay guard now suppresses republish only when the previous marker is published and the current task request still matches the same objective/task with `selected_executor=local`, `active_engine=local`, and `scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine`.

Validation:

- `python -m py_compile tmp_remote_mim/core/routers/tod_ui.py`
- `python -m unittest` focused TOD UI binding tests
- Remote MIM BOX compile passed
- Remote `/tod/ui/state` on ports `18001` and `18021` reported `binding=ready`

General Rule Learned: A repair marker is not proof unless the current authoritative request still contains the repaired fields.

Prevention Rule: Before reporting a missing-component blocker as already attempted, TOD must compare the stale marker to the current authoritative request and republish only when the repair evidence is absent.

Reuse Trigger: Any blocker using language like `already_attempted`, `missing binding`, `missing component`, `missing executor`, `missing engine`, or `repair marker exists` should run the marker-versus-current-request proof check.

Dependent Capabilities:

- active-lane authority selection
- stale marker detection
- local executor binding materialization
- operator-facing blocker communication

Capability Confidence: medium; Codex performed the emergency repair, but the evidence path is now explicit for TOD to reproduce.

Independent Pass Rate: pending; TOD must demonstrate this on a fresh missing-component blocker without Codex patching the control plane.

Date Frozen: 2026-07-15

Separate Debt: TOD still needs independent demonstration that it can detect, classify, repair, validate, and communicate a missing-component blocker without Codex implementation.

Generalized Principle: Do not confuse a prior attempt with current proof. The current authoritative state must contain the repaired component before a blocker can be considered resolved.
