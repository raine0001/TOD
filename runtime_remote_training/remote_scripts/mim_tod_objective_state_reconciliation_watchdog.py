#!/usr/bin/env python3
"""Reconcile stale MIM/TOD objective and task lifecycle rows.

This watchdog is deliberately conservative: fresh non-terminal tasks keep their
objective active, while objectives whose child tasks are all terminal are
promoted to an honest terminal state.
"""

from __future__ import annotations

import asyncio
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SHARED_DIR = ROOT / "runtime" / "shared"
OBJECTIVE_ID = "MIM-TOD-OBJECTIVE-STATE-RECONCILIATION-WATCHDOG-V1"

TERMINAL_SUCCESS = {
    "completed_with_evidence",
    "completed_with_email_summary_bound",
    "implementation_completed_with_local_validation",
}
TERMINAL_BLOCKED = {
    "blocked_with_evidence",
    "blocked_with_inspection",
    "blocked_missing_executor",
    "blocked_with_reason",
}
TERMINAL = TERMINAL_SUCCESS | TERMINAL_BLOCKED
NON_TERMINAL = {"queued", "pending", "ready", "running", "active", "in_progress", "waiting_on_human"}


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_dotenv() -> None:
    env_path = ROOT / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def db_url() -> str:
    value = os.environ.get("DATABASE_URL", "")
    if value.startswith("postgresql+asyncpg://"):
        return "postgresql://" + value.split("://", 1)[1]
    return value


def json_default(value: Any) -> str:
    if isinstance(value, datetime):
        return iso(value)
    return str(value)


def terminal_status(task: Any) -> str:
    return str(task["dispatch_status"] or task["state"] or "").strip()


async def main() -> int:
    load_dotenv()
    import asyncpg

    now = utc_now()
    stale_cutoff = now - timedelta(seconds=int(os.environ.get("MIM_TOD_RECONCILE_STALE_TASK_SECONDS", "86400")))
    fresh_window = now - timedelta(seconds=int(os.environ.get("MIM_TOD_RECONCILE_FRESH_ACTIVE_SECONDS", "1800")))
    minimum_objective_id = int(os.environ.get("MIM_TOD_RECONCILE_MIN_OBJECTIVE_ID", "0"))

    conn = await asyncpg.connect(db_url())
    report: dict[str, Any] = {
        "packet_type": "mim-tod-objective-state-reconciliation-watchdog-v1",
        "objective_id": OBJECTIVE_ID,
        "generated_at": iso(now),
        "source": "mim_tod_objective_state_reconciliation_watchdog",
        "policy": {
            "stale_task_cutoff": iso(stale_cutoff),
            "fresh_active_cutoff": iso(fresh_window),
            "minimum_objective_id": minimum_objective_id,
            "never_overwrite_fresh_active_execution": True,
        },
        "summary": {
            "completed_with_evidence": 0,
            "blocked_with_evidence": 0,
            "running": 0,
            "stale_fixed": 0,
            "objectives_reconciled": 0,
            "stale_tasks_marked_blocked_with_inspection": 0,
            "fresh_active_preserved": 0,
        },
        "objective_updates": [],
        "task_updates": [],
        "preserved_fresh_active": [],
        "dispatcher_idle_health": {},
        "operator_summary": "",
    }

    objectives = await conn.fetch(
        """
        select id,title,state,priority,created_at,metadata_json
        from objectives
        where id >= $1
        order by id
        """,
        minimum_objective_id,
    )

    for obj in objectives:
        tasks = await conn.fetch(
            """
            select id,objective_id,title,state,readiness,start_now,dispatch_status,
                   assigned_to,created_at,metadata_json
            from tasks
            where objective_id=$1
            order by created_at desc, id desc
            """,
            obj["id"],
        )
        if not tasks:
            continue

        fresh_active = [
            task
            for task in tasks
            if task["created_at"] and task["created_at"] >= fresh_window
            and (terminal_status(task) not in TERMINAL)
            and str(task["state"] or "") in NON_TERMINAL
        ]
        if fresh_active:
            report["summary"]["fresh_active_preserved"] += 1
            report["preserved_fresh_active"].append(
                {
                    "objective_id": obj["id"],
                    "title": obj["title"],
                    "task_ids": [task["id"] for task in fresh_active],
                }
            )
            continue

        statuses = [terminal_status(task) for task in tasks]
        all_terminal = all(status in TERMINAL for status in statuses)
        if all_terminal:
            latest = tasks[0]
            latest_status = terminal_status(latest)
            if latest_status in TERMINAL_SUCCESS:
                new_state = "completed_with_evidence"
                report["summary"]["completed_with_evidence"] += 1
            else:
                new_state = "blocked_with_evidence"
                report["summary"]["blocked_with_evidence"] += 1

            if obj["state"] != new_state:
                metadata = obj["metadata_json"] or {}
                if not isinstance(metadata, dict):
                    metadata = {}
                history = metadata.get("state_reconciliation_history") or []
                history.append(
                    {
                        "at": iso(now),
                        "source": "state_reconciliation_watchdog",
                        "from": obj["state"],
                        "to": new_state,
                        "latest_task_id": latest["id"],
                        "latest_task_status": latest_status,
                    }
                )
                metadata["state_reconciliation_history"] = history[-10:]
                metadata["last_state_reconciliation"] = history[-1]
                await conn.execute(
                    "update objectives set state=$1, metadata_json=$2 where id=$3",
                    new_state,
                    json.dumps(metadata, default=json_default),
                    obj["id"],
                )
                report["summary"]["objectives_reconciled"] += 1
                report["summary"]["stale_fixed"] += 1
                report["objective_updates"].append(
                    {
                        "objective_id": obj["id"],
                        "title": obj["title"],
                        "old_state": obj["state"],
                        "new_state": new_state,
                        "latest_task_id": latest["id"],
                        "latest_task_status": latest_status,
                    }
                )
        else:
            report["summary"]["running"] += 1

    stale_tasks = await conn.fetch(
        """
        select id,objective_id,title,state,readiness,dispatch_status,assigned_to,created_at,metadata_json
        from tasks
        where created_at < $1
          and (
            state in ('queued','in_progress','running')
            or readiness in ('queued','in_progress','running')
            or dispatch_status in ('pending','queued','running')
          )
        order by created_at asc, id asc
        """,
        stale_cutoff,
    )
    for task in stale_tasks:
        status = terminal_status(task)
        if status in TERMINAL:
            continue
        metadata = task["metadata_json"] or {}
        if not isinstance(metadata, dict):
            metadata = {}
        metadata["stale_reconciliation"] = {
            "at": iso(now),
            "source": "state_reconciliation_watchdog",
            "reason": "stale_nonterminal_task_without_fresh_heartbeat",
            "old_state": task["state"],
            "old_readiness": task["readiness"],
            "old_dispatch_status": task["dispatch_status"],
        }
        await conn.execute(
            """
            update tasks
               set state='blocked_with_inspection',
                   readiness='blocked',
                   dispatch_status='blocked_with_inspection',
                   metadata_json=$1
             where id=$2
            """,
            json.dumps(metadata, default=json_default),
            task["id"],
        )
        report["summary"]["stale_tasks_marked_blocked_with_inspection"] += 1
        report["summary"]["stale_fixed"] += 1
        report["task_updates"].append(
            {
                "task_id": task["id"],
                "objective_id": task["objective_id"],
                "title": task["title"],
                "old_state": task["state"],
                "old_readiness": task["readiness"],
                "old_dispatch_status": task["dispatch_status"],
                "new_state": "blocked_with_inspection",
            }
        )

    ready_tasks = await conn.fetch(
        """
        select id,objective_id,title,state,readiness,start_now,dispatch_status,assigned_to,created_at
        from tasks
        where start_now=true
          and state='queued'
          and readiness='ready'
          and coalesce(dispatch_status,'pending') in ('pending','queued')
          and assigned_to='mim'
        order by created_at asc
        limit 20
        """
    )
    report["dispatcher_idle_health"] = {
        "ready_mim_start_now_task_count": len(ready_tasks),
        "ready_candidates": [dict(row) for row in ready_tasks],
        "idle_is_healthy_when_no_ready_tasks": len(ready_tasks) == 0,
    }
    if ready_tasks:
        report["operator_summary"] = f"Reconciliation complete: {len(ready_tasks)} ready executable MIM task(s) remain."
    else:
        report["operator_summary"] = (
            "MIM/TOD is idle but healthy: no ready executable MIM task exists, "
            "stale states were reconciled, and dispatcher idle is not a failure."
        )

    SHARED_DIR.mkdir(parents=True, exist_ok=True)
    latest = SHARED_DIR / "MIM_TOD_OBJECTIVE_STATE_RECONCILIATION_WATCHDOG.latest.json"
    latest.write_text(json.dumps(report, indent=2, default=json_default) + "\n", encoding="utf-8")
    legacy = SHARED_DIR / "MIM_TOD_STALE_OBJECTIVE_DIRECT_RECONCILIATION.latest.json"
    legacy.write_text(json.dumps(report, indent=2, default=json_default) + "\n", encoding="utf-8")

    await conn.close()
    print(json.dumps({"status": "completed_with_evidence", "artifact": str(latest), "summary": report["summary"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
