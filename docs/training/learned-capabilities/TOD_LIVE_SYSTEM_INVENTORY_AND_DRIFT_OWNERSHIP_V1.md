# Learned Capability: TOD Live System Inventory and Drift Ownership V1

## Capability Name

Live infrastructure inventory, evidence retrieval, and configuration-drift ownership.

## Trigger

An operator asks TOD which host service, tunnel, model, endpoint, or dependency owns an AgentMIM/MIM capability, or a TODBOX configuration changes.

## Reality

AgentMIM reaches local MIM capabilities through a stable managed tunnel hostname. TODBOX LAN addressing is deterministic host infrastructure and is not an AgentMIM application endpoint.

## Observation

On 2026-08-25, live evidence showed `cloudflared-todbox-hosting.service` enabled and active, `https://mim.mimtod.com/health` returning HTTP 200, and AgentMIM `/ready` reporting `endpoint_host=mim.mimtod.com`, `endpoint_mode=managed_tunnel`, and `status=reachable`. Earlier TOD answers restarted discovery and invented an unproved tunnel ID and origin mapping.

## Root Cause

TOD had recurring probes but no durable infrastructure schema exposed to its evidence query. Unstructured observations were not retained as current facts, and missing fields were filled by model inference.

## Blocker Class

`capability_blocker`: live infrastructure evidence was not projected into a reusable TOD-owned inventory and query boundary.

## Decomposition Ladder

1. Reject invented tunnel ID, name, origin, ports, and paths.
2. Locate the existing boot and 15-minute TODBOX connectivity verifier.
3. Extend that verifier instead of creating a disconnected static inventory.
4. Derive endpoint, mode, service state, dependencies, model lanes, and unit hashes from live evidence.
5. Mark unavailable origin mapping as unasserted.
6. Write an atomic latest inventory and configuration fingerprint.
7. Write history only when that fingerprint changes.
8. Expose the inventory to TOD's evidence query.
9. Ask an unseen natural-language tunnel question and grade factual grounding.
10. Correct ambiguous freshness and ownership field names, then retest.

## Smallest Successful Rung

TOD answered an unseen image-generation tunnel question from a fresh inventory with the correct operational owner, stable endpoint, tunnel service, health, timestamp, maximum age, and unproved-origin boundary.

## Implementation Summary

- `todbox-startup-connectivity-verify` now publishes `/var/lib/todbox-connectivity/system-inventory.latest.json` every boot and every 15 minutes.
- Configuration-only changes create records under `/var/lib/todbox-connectivity/inventory-changes/`; unchanged patrols create no duplicate record.
- `todbox-system-inventory-query` retrieves capability-specific connection evidence.
- The workstation query reads its SSH/API address from `tod/config/todbox-connection.json`, which is owned by TOD, rather than from a Python literal.
- AgentMIM uses the managed tunnel hostname and rejects numeric non-loopback gateway endpoints.

## Validation

- AgentMIM combined gateway/forum regression: 462 passed.
- TODBOX inventory tests: 8 passed.
- Live inventory installer completed with rollback backup.
- Timer: enabled and active.
- Verifier result: success, exit 0.
- Latest inventory was 74 seconds old against a 900-second maximum during audit.
- Secret scan found only the boolean key `authority.secret_material_included=false`.
- A repeated unchanged patrol kept history count at 2 and reported `drift.changed=false`.
- TOD natural-language acceptance answer named `TOD`, `cloudflared-todbox-hosting.service`, `https://mim.mimtod.com`, `managed_tunnel`, reachable health, timestamp, 900-second maximum age, and `origin_mapping_proven=false`.

## General Rule Learned

TOD may answer infrastructure questions only from a fresh authoritative inventory. Missing mappings remain explicitly unproved; they are never reconstructed from plausibility.

## Prevention Rule

Every infrastructure change must be followed by the existing verifier, a refreshed inventory fingerprint, change-only history when configuration differs, and one capability query. Agent applications consume stable DNS tunnel endpoints, never TODBOX LAN addresses.

## Reuse Trigger

Reuse when asked which tunnel, service, model, port, route, dependency, or owner serves an MIM/TOD capability, and after network, systemd, model, tunnel, or gateway configuration changes.

## Dependent Capabilities

- TOD Technical Operations patrol.
- Startup connectivity verification.
- AgentMIM readiness reporting.
- Systemd service evidence.
- Managed tunnel health.
- Evidence-grounded TOD query composition.

## Capability Confidence

High for current tunnel inventory retrieval and drift detection; bounded to the discovered services and fields in schema version 1.

## Independent Pass Rate

`0/1` independent. The live acceptance passed with Codex-authored inventory scaffolding after two TOD attempts invented evidence. This is a `scaffolded_pass`, not independent TOD implementation credit.

## Date Frozen

2026-08-25.

## Separate Debt

- TOD must independently extend schema version 1 for a fresh, previously unseen service change.
- The Cloudflare-managed origin mapping remains unproved and must stay unasserted until an authoritative source is available.
- The `.10` SSH host key was not accepted for the configured `tod` key in this session; protected password fallback worked, but key deployment should be revalidated separately.

## Generalized Principle

Operational memory is a continuously re-derived evidence product, not a model recollection. Inventory plus freshness plus drift history turns repeated rediscovery into a bounded lookup while preserving uncertainty honestly.
