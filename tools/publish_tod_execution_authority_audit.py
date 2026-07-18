from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "runtime" / "shared"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(name: str, payload: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n", encoding="utf-8")


def write_md(name: str, text: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(text.rstrip() + "\n", encoding="utf-8")


def load_json(path: str) -> dict:
    target = ROOT / path
    if not target.exists():
        return {}
    return json.loads(target.read_text(encoding="utf-8-sig", errors="replace"))


def outlet(
    name: str,
    trigger: str,
    source: str,
    normalizer: str,
    authority: str,
    executor: str,
    result_writer: str,
    visible_surface: str,
    can_create_task: bool,
    can_select_task: bool,
    can_execute: bool,
    can_recover: bool,
    can_publish_result: bool,
    can_override_active_lane: bool,
    obeys_single_execution_contract: str,
    classification: str,
    evidence: list[str],
) -> dict:
    return {
        "outlet_name": name,
        "trigger_or_route": trigger,
        "source_file_or_artifact": source,
        "input_normalizer": normalizer,
        "decision_authority": authority,
        "executor": executor,
        "result_writer": result_writer,
        "operator_visible_surface": visible_surface,
        "can_create_task": can_create_task,
        "can_select_task": can_select_task,
        "can_execute": can_execute,
        "can_recover_or_reissue": can_recover,
        "can_publish_result": can_publish_result,
        "can_override_active_lane": can_override_active_lane,
        "obeys_single_execution_contract": obeys_single_execution_contract,
        "authority_classification": classification,
        "evidence": evidence,
    }


def main() -> None:
    generated_at = now_iso()
    request = load_json("runtime/shared/MIM_TOD_TASK_REQUEST.latest.json")
    result = load_json("runtime/shared/TOD_EXECUTION_RESULT.latest.json")
    lane = load_json("runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json")
    truth = load_json("runtime/shared/TOD_EXECUTION_TRUTH.latest.json")
    autonomy = load_json("shared_state/tod_autonomy_status.latest.json")
    watchdog = load_json("shared_state/tod_recovery_watchdog.latest.json")
    bridge = load_json("shared_state/TOD_MIM_BRIDGE_SMOKE.latest.json")

    outlets = [
        outlet(
            "MIM bridge task request",
            "runtime/shared/MIM_TOD_TASK_REQUEST.latest.json",
            "MIM Box runtime/shared task request mirrored locally",
            "scripts/TOD.ps1 run-bridge-request / execute-chat-task request parser",
            "MIM request writer plus TOD bridge arbitration",
            "scripts/TOD.ps1 execute-chat-task -> run-task",
            "Publish-LocalExecutionArtifacts",
            "runtime/shared TOD_* latest artifacts and Studio/TOD UI",
            True,
            True,
            True,
            False,
            True,
            True,
            "partial: accepts contract, but latest packet lacked target_file while bounded_edit_mode=true",
            "Duplicate Intake Authority",
            [
                "MIM_TOD_TASK_REQUEST.latest.json has tod_action=execute-chat-task.",
                "Latest request has target_file empty and bounded_edit_mode true.",
            ],
        ),
        outlet(
            "TOD.ps1 action dispatcher",
            "scripts/TOD.ps1 -Action ...",
            "scripts/TOD.ps1",
            "PowerShell action switch and task/state loaders",
            "scripts/TOD.ps1 action switch",
            "run-task, execute-chat-task, run-bridge-request, add-result, review-task, select-next-task-loop",
            "state.json plus runtime/shared publication helpers",
            "CLI output, runtime/shared artifacts, MIM bridge",
            True,
            True,
            True,
            True,
            True,
            True,
            "stronger than other paths; this is closest to canonical executor",
            "Primary Execution Authority Candidate",
            [
                "scripts/TOD.ps1 contains run-task, execute-chat-task, run-bridge-request, add-result, review-task.",
                "Latest result source is tod.local.run-task.",
            ],
        ),
        outlet(
            "LocalExecutionEngine",
            "scripts/engines/LocalExecutionEngine.ps1::Invoke-LocalExecutionEngine",
            "scripts/engines/LocalExecutionEngine.ps1",
            "bounded edit materialization requirements",
            "engine contract and Resolve-TaskBoundedEditMaterialization",
            "local bounded file edit and validation command runner",
            "TOD_EXECUTION_RESULT.latest.json via TOD.ps1 publisher",
            "runtime/shared execution result/truth",
            False,
            False,
            True,
            False,
            False,
            False,
            "strong: refused malformed bounded edit instead of fake success",
            "Deterministic Execution Boundary",
            [
                "Latest blocker reason_code=blocked_missing_bounded_edit_mode.",
                "Blocker names scripts/TOD.ps1::Resolve-TaskBoundedEditMaterialization and LocalExecutionEngine binding.",
            ],
        ),
        outlet(
            "TOD active execution lane",
            "runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json",
            "runtime/shared/TOD_ACTIVE_EXECUTION_LANE.latest.json",
            "active lane artifact writer",
            "active-lane preservation/override logic",
            "none directly; controls queue protection",
            "TOD_ACTIVE_EXECUTION_LANE.latest.json",
            "TOD UI and reflection",
            False,
            True,
            False,
            True,
            True,
            True,
            "partial: can preserve or conflict with queued work",
            "Coordination Authority",
            [
                "Latest lane relation_to_previous_active=conflicts.",
                "Latest lane terminal_event_type=bounded_edit_mode_missing.",
            ],
        ),
        outlet(
            "Recovery watchdog",
            "scheduled/task script Start-TODRecoveryWatchdog.ps1",
            "scripts/Start-TODRecoveryWatchdog.ps1 and shared_state/tod_recovery_watchdog.latest.json",
            "watchdog issue classifier",
            "watchdog recovery policy",
            "listener restart, remote publish repair, emergency request generation",
            "shared_state/tod_recovery_watchdog.latest.json and remote/local repair packets",
            "TOD status/reflection",
            True,
            True,
            False,
            True,
            True,
            True,
            "weak: can create remediation/repair requests and recurse when listener_not_running persists",
            "Duplicate Recovery Authority",
            [
                "Current watchdog state=error, last_issue=listener_not_running.",
                "Recovery attempts are high and last_recovery_ok=false.",
            ],
        ),
        outlet(
            "Autonomous training daemon",
            "Start-TODAutonomousTrainingDaemon.ps1 / scheduled daemon",
            "tod/out/training/autonomous-campaign/daemon/autonomous-training-daemon-state.json",
            "daemon idle/runtime activity detector",
            "daemon training profile selection",
            "runtime-safe training fallback/simulation",
            "tod_training_status and daemon state artifacts",
            "Studio training/reflection",
            True,
            True,
            False,
            False,
            True,
            False,
            "weak: currently training fallback is active, but not authoritative implementation",
            "Training Authority",
            [
                "Autonomy status says last_training_profile=packet_materialization_pressure.",
                "Daemon log shows repeated runtime-safe training fallback starts/stops.",
            ],
        ),
        outlet(
            "Autonomy guard/status writer",
            "Write-TODCompletionStatus.ps1",
            "shared_state/tod_autonomy_status.latest.json",
            "reads daemon, training, public route health, scheduled task state",
            "status synthesis",
            "none",
            "tod_autonomy_status.latest.json",
            "operator status",
            False,
            False,
            False,
            False,
            True,
            False,
            "surface/status only if it does not choose work",
            "Allowed Status Adapter",
            [
                "Autonomy status current_tod_state=executing.",
                "Reports blockers and scheduled task states.",
            ],
        ),
        outlet(
            "TOD UI operator chat",
            "POST /tod/ui/chat/message and /chat/ui/message",
            "tmp_remote_mim/core/routers/tod_ui.py",
            "chat payload session/mode/message",
            "_compose_tod_reply and _compose_operator_reply",
            "operator action/handoff helpers, not canonical code executor",
            "TOD console chat artifacts",
            "TOD web UI",
            True,
            True,
            False,
            True,
            True,
            True,
            "partial: can create handoffs and operator actions outside TOD.ps1 canonical execution",
            "Duplicate Operator Intake Authority",
            [
                "tod_ui.py exposes /tod/ui/chat/message and /chat/ui/message.",
                "tod_ui.py has _compose_tod_reply/_compose_operator_reply.",
            ],
        ),
        outlet(
            "MIM gateway bounded TOD dispatcher",
            "gateway bounded TOD dispatch branches",
            "tmp_remote_mim/core/routers/gateway.py and core/bounded_action_registry.py",
            "MIM conversation -> bounded action registry",
            "MIM gateway routing and bounded_action_registry",
            "dispatch_bounded_tod_* request writers",
            "MIM_TOD_TASK_REQUEST and synchronized result artifacts",
            "MIM UI / Studio",
            True,
            True,
            False,
            True,
            True,
            True,
            "partial: can create TOD work before TOD canonical contract proves target_file/materialization readiness",
            "Duplicate Upstream Task Authority",
            [
                "bounded_action_registry maps tod_status_check, tod_remediation_dispatch, recent changes, warning, and objective summary actions.",
                "gateway can dispatch bounded TOD status/recent/remediation requests.",
            ],
        ),
        outlet(
            "State bus MIM/TOD reactions",
            "POST /state-bus/consumers/mim-core/step and /state-bus/reactions/mim-tod/step",
            "tmp_remote_mim/core/routers/state_bus.py",
            "state bus events and reactions",
            "state_bus_service reaction logic",
            "reaction step, not local file executor",
            "state bus records and visible summaries",
            "Studio/TOD status surfaces",
            True,
            True,
            False,
            True,
            True,
            True,
            "not proven as canonical; should be event transport only",
            "Duplicate Coordination Authority",
            [
                "state_bus.py exposes mim-core consumer step and mim-tod reaction step.",
            ],
        ),
        outlet(
            "MIM ARM / hardware execution to TOD",
            "MIM ARM execution request artifacts",
            "tmp_remote_mim/core/tod_mim_contract.py canonical writer registry",
            "contract-normalized execution request",
            "MIM ARM writer and TOD/MIM contract",
            "hardware-specific executor/arm loop",
            "MIM_ARM_* and TOD/MIM result artifacts",
            "MIM ARM status surfaces",
            True,
            True,
            True,
            True,
            True,
            True,
            "specialized lane; must remain explicit non-general TOD executor or adopt same final contract",
            "Specialized Execution Authority",
            [
                "tod_mim_contract.py lists MIM ARM writer as execution_request writer.",
            ],
        ),
    ]

    active_failure = {
        "request_id": request.get("request_id") or request.get("task_id"),
        "objective_id": request.get("objective_id"),
        "tod_action": request.get("tod_action"),
        "bounded_edit_mode": request.get("bounded_edit_mode"),
        "target_file": request.get("target_file"),
        "target_files": request.get("target_files"),
        "result_status": result.get("status"),
        "reason_code": result.get("reason_code"),
        "summary": result.get("summary"),
        "lane_status": lane.get("status"),
        "lane_terminal_reason_code": lane.get("terminal_reason_code"),
        "truth_summary": truth.get("summary"),
        "watchdog_state": watchdog.get("state"),
        "watchdog_last_issue": watchdog.get("last_issue"),
        "bridge_status": bridge.get("status"),
        "autonomy_state": autonomy.get("current_tod_state"),
    }

    counts = {
        "tod_authority_outlets_mapped": len(outlets),
        "task_creation_authorities": sum(1 for item in outlets if item["can_create_task"]),
        "task_selection_authorities": sum(1 for item in outlets if item["can_select_task"]),
        "execution_authorities": sum(1 for item in outlets if item["can_execute"]),
        "recovery_authorities": sum(1 for item in outlets if item["can_recover_or_reissue"]),
        "result_publishers": sum(1 for item in outlets if item["can_publish_result"]),
        "active_lane_override_risks": sum(1 for item in outlets if item["can_override_active_lane"]),
    }

    duplicate_debt = [
        {
            "component": item["source_file_or_artifact"],
            "classification": item["authority_classification"],
            "why": item["obeys_single_execution_contract"],
            "must_become": (
                "surface/status adapter"
                if item["authority_classification"].startswith("Allowed")
                else "producer of canonical TODExecutionRequest only, or retire as an executor/selector"
            ),
        }
        for item in outlets
        if item["authority_classification"] not in {"Primary Execution Authority Candidate", "Deterministic Execution Boundary", "Allowed Status Adapter"}
    ]

    provenance = {
        "objective_id": "TOD-UNIFIED-EXECUTION-AUTHORITY-AUDIT-V1",
        "generated_at": generated_at,
        "required_runtime_provenance_schema": {
            "tod_identity": "TOD",
            "surface": "",
            "source": "",
            "request_id": "",
            "objective_id": "",
            "task_id": "",
            "task_creation_source": "",
            "task_selection_source": "",
            "normalizer_source": "",
            "execution_authority": "",
            "engine_source": "",
            "recovery_authority": "",
            "result_writer": "",
            "active_lane_source": "",
            "final_status_source": "",
            "validation_source": "",
            "fallback_used": False,
            "reissue_or_recovery_used": False,
            "material_change_authorized": False,
        },
        "active_failure_provenance": active_failure,
    }

    write_json(
        "TOD_EXECUTION_AUTHORITY_OUTLET_MAP.latest.json",
        {
            "objective_id": "TOD-UNIFIED-EXECUTION-AUTHORITY-AUDIT-V1",
            "generated_at": generated_at,
            "counts": counts,
            "active_failure": active_failure,
            "outlets": outlets,
        },
    )
    write_json(
        "TOD_DUPLICATE_EXECUTION_AUTHORITIES.latest.json",
        {
            "objective_id": "TOD-UNIFIED-EXECUTION-AUTHORITY-AUDIT-V1",
            "generated_at": generated_at,
            "counts": counts,
            "duplicate_or_specialized_authorities": duplicate_debt,
        },
    )
    write_json("TOD_EXECUTION_PROVENANCE_AUDIT.latest.json", provenance)

    graph = f"""# TOD Execution Authority Graph

Generated: {generated_at}

## Current Read

TOD is less personality-split than MIM, but it is not single-authority yet.

Mapped outlets: {counts['tod_authority_outlets_mapped']}.
Task creation authorities: {counts['task_creation_authorities']}.
Task selection authorities: {counts['task_selection_authorities']}.
Execution authorities: {counts['execution_authorities']}.
Recovery/reissue authorities: {counts['recovery_authorities']}.
Active-lane override risks: {counts['active_lane_override_risks']}.

## Active Failure Path

```text
MIM/Gateway/direct chat
  -> MIM_TOD_TASK_REQUEST.latest.json
  -> tod_action=execute-chat-task
  -> scripts/TOD.ps1
  -> Resolve-TaskBoundedEditMaterialization
  -> LocalExecutionEngine required one target_file
  -> target_file was empty
  -> TOD_EXECUTION_RESULT.latest.json blocked_missing_bounded_edit_mode
```

This is good executor behavior and bad intake behavior. TOD did not fake a validated edit; it blocked with evidence.

## Current Competing Authorities

- MIM gateway and bounded action registry can create TOD work.
- TOD UI chat can create handoffs/operator actions.
- Watchdog can create recovery/remediation work.
- Autonomous daemon can create/simulate training work.
- State bus can run MIM/TOD reaction steps.
- MIM ARM has a specialized execution lane.
- `scripts/TOD.ps1` is the closest canonical executor.
- `LocalExecutionEngine.ps1` is the strongest deterministic execution boundary.

## Architectural Risk

TOD does not look like it has multiple personalities in the conversational sense. The risk is different: multiple task creators and recovery systems can issue malformed or recursive work to the same executor.

## Best Single Authority Boundary

Canonical path should be:

```text
Any TOD request source
  -> TODExecutionRequest schema
  -> TOD intake normalizer
  -> one active-lane arbiter
  -> scripts/TOD.ps1 run-task
  -> one execution engine selected by policy
  -> validation
  -> one result publisher
```

Everything else becomes a source adapter, not an executor.
"""
    write_md("TOD_EXECUTION_AUTHORITY_GRAPH.latest.md", graph)

    plan = f"""# TOD Single Execution Authority Consolidation Plan

Generated: {generated_at}

## Diagnosis

TOD's current problem is not the same as MIM's personality split. TOD has one reasonably strong executor boundary, but too many upstream systems can create, reissue, recover, or select work.

The latest failure proves the issue:

- Request said `bounded_edit_mode=true`.
- Request had no `target_file`.
- `LocalExecutionEngine` refused to proceed.
- Result was blocked with `blocked_missing_bounded_edit_mode`.

That is the correct refusal. The malformed task should have been rejected before it became active work.

## Sole Authority Target

`scripts/TOD.ps1 run-task` plus `LocalExecutionEngine.ps1` should become the canonical execution authority for implementation tasks.

All other systems must output a canonical `TODExecutionRequest` and pass a preflight gate before they can affect the active lane.

## Required Canonical Request Fields

- `request_id`
- `objective_id`
- `task_id`
- `task_class`
- `tod_action`
- `target_file` or `validation_only=true`
- `bounded_edit_mode`
- `expected_behavior_change`
- `validation_command`
- `result_artifact_targets`
- `recovery_policy`

## Smallest Safe Consolidation Sequence

1. Add audit provenance to every TOD request/result: task_creation_source, task_selection_source, execution_authority, engine_source, recovery_authority, active_lane_source, final_status_source.
2. Add a pre-active-lane gate: if `bounded_edit_mode=true` and `validation_only=false`, reject before active-lane publication unless exactly one `target_file` exists.
3. Demote watchdog recovery into request source only. It may propose a canonical request; it may not recursively create active remediation without preflight.
4. Demote MIM gateway bounded-action dispatch into request source only. It may not bypass TOD request preflight.
5. Demote TOD UI chat into operator intake only. Handoffs/actions must become canonical requests or non-execution notes.
6. Keep `LocalExecutionEngine` as deterministic boundary and make its refusal visible as intake-quality feedback, not repeated recovery churn.
7. Add a scorecard metric: malformed TOD requests blocked before active lane.

## Immediate Next Nudge

Do not ask TOD to execute another broad remediation. Ask TOD to form one clean canonical request for the current blocker:

`target_file=scripts/TOD.ps1`, behavior change: reject malformed bounded edit requests before active-lane publication, validation: a focused PowerShell dry run or existing TOD intake/preflight test.

Dave needed: no.
"""
    write_md("TOD_SINGLE_EXECUTION_AUTHORITY_CONSOLIDATION_PLAN.latest.md", plan)

    print(json.dumps({"generated_at": generated_at, "counts": counts, "artifacts": [
        "runtime/shared/TOD_EXECUTION_AUTHORITY_OUTLET_MAP.latest.json",
        "runtime/shared/TOD_EXECUTION_AUTHORITY_GRAPH.latest.md",
        "runtime/shared/TOD_DUPLICATE_EXECUTION_AUTHORITIES.latest.json",
        "runtime/shared/TOD_EXECUTION_PROVENANCE_AUDIT.latest.json",
        "runtime/shared/TOD_SINGLE_EXECUTION_AUTHORITY_CONSOLIDATION_PLAN.latest.md",
    ]}, indent=2))


if __name__ == "__main__":
    main()
