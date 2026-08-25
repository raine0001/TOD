#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


DEFAULT_INVENTORY = Path(
    "/var/lib/todbox-connectivity/system-inventory.latest.json"
)


def query_inventory(inventory: dict[str, Any], capability: str) -> dict[str, Any]:
    connections = inventory.get("connections")
    connections = connections if isinstance(connections, dict) else {}
    normalized = str(capability or "").strip().lower().replace(" ", "_")
    matches = []
    for name, connection in connections.items():
        if not isinstance(connection, dict):
            continue
        capabilities = [str(value).lower() for value in connection.get("declared_capabilities") or []]
        if not normalized or normalized in capabilities or normalized in str(name).lower():
            matches.append({"connection": name, **connection})
    return {
        "generated_at": inventory.get("generated_at"),
        "owner": (inventory.get("authority") or {}).get("owner"),
        "configuration_fingerprint": inventory.get("configuration_fingerprint"),
        "matches": matches,
        "models": inventory.get("models") or [],
        "inferences": inventory.get("inferences") or {},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("capability", nargs="?", default="")
    parser.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    args = parser.parse_args()
    if not args.inventory.is_file():
        print(json.dumps({"status": "unavailable", "reason": "inventory_missing"}))
        return 1
    inventory = json.loads(args.inventory.read_text(encoding="utf-8"))
    print(json.dumps(query_inventory(inventory, args.capability), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
