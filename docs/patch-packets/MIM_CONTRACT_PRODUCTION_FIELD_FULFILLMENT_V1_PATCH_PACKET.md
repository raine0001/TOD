# MIM Contract Production Field Fulfillment V1 Patch Packet

## Packet Status

- status: review_requested
- authoring_role: codex_escalation_after_TOD_attempt
- reason_for_escalation: TOD restored its state and attempted packet authoring, but failed with `local_execution_scope_not_supported` and then drifted into an unrelated selector task. This packet is not TOD implementation credit.
- source_code_changed: no

## Target

- target_file: `tmp_remote_mim/core/next_step_dialog_service.py`
- target_function: `publish_contract_production_results`
- repair_type: generic contract production field fulfillment

## Diagnosis

`publish_contract_production_results` recognizes `contract_production_request` items and writes the requested output artifact, but it currently marks every contract result as `blocked_missing_data`.

The function reads `output_contract`, `required_fields`, and `status_allowed`, but does not attempt to fulfill required fields from structured request metadata or candidate payload fields. That makes approval and production look connected while still producing an empty blocked packet.

## Evidence

Source anchors from `tmp_remote_mim/core/next_step_dialog_service.py`:

```text
693: output_contract = metadata.get("output_contract") if isinstance(metadata.get("output_contract"), dict) else {}
694: required_fields = metadata.get("required_fields") if isinstance(metadata.get("required_fields"), list) else []
695: status_allowed = output_contract.get("status_allowed") if isinstance(output_contract.get("status_allowed"), list) else []
696: status = "blocked_missing_data" if "blocked_missing_data" in status_allowed or status_allowed else "blocked_missing_data"
713: "status": status,
714: "reason": "MIM approved the production contract, but no specialized producer populated the required fields.",
715: "required_fields": required_fields,
716: "missing_fields": required_fields,
```

Observed runtime result:

- artifact: `/home/testpilot/mim/runtime/shared/MIM_PROACTIVE_RESEARCH_CONVERSATION_TRAINING_V1_STATUS.latest.json`
- status: `blocked_missing_data`
- missing_fields: all requested fields
- useful lesson: approval alone is not production

## Required Behavior

When an approved MIM-owned `contract_production_request` contains required output fields and structured values for those fields, MIM should publish a draft production artifact instead of `blocked_missing_data`.

When required values are not present, MIM should continue publishing `blocked_missing_data` with exact missing fields.

The repair must be generic. It must not special-case:

- `MIM_PROACTIVE_RESEARCH_CONVERSATION_TRAINING_V1`
- `campaign`
- `first_training_rung`
- a specific Dave request
- a specific research page or SolAir prompt

## Safe Fix Direction

Use a generic field-fulfillment helper inside or near `publish_contract_production_results`.

Suggested logic:

1. Build a candidate source list from structured fields already present in the item:
   - `metadata_json.output_payload`
   - `metadata_json.contract_payload`
   - `metadata_json.proposed_output`
   - `metadata_json.training_status`
   - `metadata_json`
   - top-level item fields
2. For each `required_fields` entry, copy a value only if the field exists and is not blank.
3. Compute `missing_fields` from required fields that still have no value.
4. Set status:
   - `draft_ready` or first allowed success-like status when no required fields are missing.
   - `blocked_missing_data` when any required field is missing.
5. Preserve existing audit fields:
   - `packet_type`
   - `generated_at`
   - `source`
   - `response_authority`
   - `objective_id`
   - `task_id`
   - `session_id`
   - `step_id`
   - `required_fields`
   - `missing_fields`
   - `evidence_paths_or_commands`
   - `implementation_allowed`
   - `contract`
6. Include a reason that distinguishes fulfilled draft production from missing-data production.

## Validation Plan

Run focused tests that prove both branches:

```bash
cd /home/testpilot/mim && .venv/bin/python -m pytest -q tests/test_next_step_dialog_service.py
```

Required test cases:

- contract production with all required fields present publishes an artifact containing those fields.
- fulfilled artifact status is not `blocked_missing_data`.
- contract production with one required field missing publishes `blocked_missing_data`.
- missing-data artifact lists only the missing field, not all fields.
- no test hardcodes the proactive research campaign name as the only valid contract.

Runtime probe:

1. Send a dialog `handoff_request` with a MIM-owned `contract_production_request`.
2. Include `required_fields` and structured payload values for those fields.
3. Run `run_next_step_dialog_responder_cycle`.
4. Verify the named `*.latest.json` artifact contains the required fields and `missing_fields: []`.

## Rollback Note

Revert only the changes to `publish_contract_production_results` and any directly added focused tests. The previous behavior is safe but incomplete because it always publishes `blocked_missing_data`.

## Prevention Lesson

Approval, acknowledgement, and production are separate states. A producer must either create a field-complete draft artifact from structured data or publish a precise missing-data blocker. It must not mark a production contract complete because the request was approved.

## MIM Review Request

MIM should reply with one of:

- approve
- revise
- block

Required response fields:

- decision
- owner
- reason
- implementation_allowed
- required_revision_if_any
- validation_required
