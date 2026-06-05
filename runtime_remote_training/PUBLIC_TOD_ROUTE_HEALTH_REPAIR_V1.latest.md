# PUBLIC-TOD-ROUTE-HEALTH-REPAIR-V1

Status: queued

Goal: make public `/tod` and `/tod/ui/state` resolve correctly or intentionally redirect/disable with a clear status.

Known evidence:
- `https://www.agentmim.com/tod` returns 404.
- `https://www.agentmim.com/tod/ui/state` returns 404.
- Local TOD UI is healthy.

Acceptance:
- Public `/tod` resolves correctly, redirects intentionally, or reports deliberate disabled status.
- Public `/tod/ui/state` resolves correctly, redirects intentionally, or reports deliberate disabled status.
- Route health no longer reports ambiguous public TOD blockers.
- This repair remains separate from the Needs Review drain.

First driving task: inspect public route ownership and deployment path, then produce the smallest safe repair or intentional-disable plan.
