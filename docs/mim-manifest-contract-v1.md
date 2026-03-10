# MIM Manifest Contract v1

This document defines the initial response model for MIM synchronization manifest.

## Endpoint
- Method: GET
- Path: /manifest
- Success: 200 OK
- Content-Type: application/json

## Response Model

```json
{
  "system_name": "string",
  "system_version": "string",
  "contract_version": "string",
  "schema_version": "string",
  "repo_signature": "string",
  "capabilities": ["string"],
  "recent_changes": [
    {
      "id": "string",
      "summary": "string",
      "timestamp": "string"
    }
  ],
  "last_updated_at": "string",
  "generated_at": "string"
}
```

## Field Notes
- system_version: Runtime or service release version exposed by MIM.
- system_name: Stable system identifier, expected value "MIM".
- contract_version: Version of TOD-MIM object/endpoint contract.
- schema_version: Manifest schema version for forward-compatible parsing.
- repo_signature: Deterministic signature for current repository state.
- capabilities: Feature flags or operation names supported by MIM.
- recent_changes: Latest compatibility-relevant deltas.
- last_updated_at: Last compatibility-impacting update time.
- generated_at: UTC timestamp when the manifest was produced.

## Compatibility Rules
- New optional fields can be added without a breaking change.
- Existing required field removals or type changes are breaking changes.
- TOD should treat missing required fields as drift warnings or errors depending on policy.
