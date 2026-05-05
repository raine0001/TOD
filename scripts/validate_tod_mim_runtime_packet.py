import argparse
import json
from pathlib import Path
import re

import yaml


def append_error(result: dict, code: str, detail: str) -> None:
    result["errors"].append({"code": code, "detail": detail})


def require_non_empty_string(result: dict, packet: dict, field_name: str) -> None:
    value = packet.get(field_name)
    if not isinstance(value, str) or not value.strip():
        append_error(result, "missing_or_empty_field", field_name)


def require_positive_int(result: dict, value, field_name: str) -> None:
    if not isinstance(value, int) or value <= 0:
        append_error(result, "invalid_positive_integer", field_name)


def require_object_fields(result: dict, packet: dict, field_name: str, required_fields: list[str]) -> None:
    value = packet.get(field_name)
    if not isinstance(value, dict):
        append_error(result, "missing_object", field_name)
        return
    for key in required_fields:
        child = value.get(key)
        if not isinstance(child, str) or not child.strip():
            append_error(result, "missing_or_empty_object_field", f"{field_name}.{key}")


def normalize_text(value) -> str:
    if isinstance(value, str):
        return value.strip()
    if value is None:
        return ""
    return str(value).strip()


def normalize_objective_id(value) -> str:
    text = normalize_text(value)
    if not text:
        return ""
    match = re.match(r"(?i)^objective-(?P<objective>\d+)$", text)
    if match:
        return match.group("objective")
    return text


def extract_objective_from_task_ref(value) -> str:
    text = normalize_text(value)
    if not text:
        return ""
    match = re.match(r"(?i)^objective-(?P<objective>\d+)-task-.+$", text)
    if match:
        return match.group("objective")
    return ""


def require_exact_identity_match(result: dict, expected: str, actual, field_path: str) -> None:
    expected_text = normalize_text(expected)
    actual_text = normalize_text(actual)
    if not expected_text or not actual_text:
        return
    if actual_text != expected_text:
        append_error(result, "embedded_identity_mismatch", f"{field_path}={actual_text} expected={expected_text}")


def require_objective_identity_match(result: dict, expected: str, actual, field_path: str) -> None:
    expected_text = normalize_objective_id(expected)
    actual_text = normalize_objective_id(actual)
    if not expected_text or not actual_text:
        return
    if actual_text != expected_text:
        append_error(result, "embedded_identity_mismatch", f"{field_path}={actual_text} expected={expected_text}")


def validate_packet_identity_consistency(result: dict, packet: dict) -> dict:
    request_id = normalize_text(packet.get("request_id"))
    task_id = normalize_text(packet.get("task_id"))
    objective_id = normalize_objective_id(packet.get("objective_id"))
    correlation_id = normalize_text(packet.get("correlation_id"))

    if request_id and task_id and request_id.lower().startswith("objective-") and task_id.lower().startswith("objective-") and request_id != task_id:
        append_error(result, "task_id_mismatch", f"request_id={request_id} task_id={task_id}")

    request_objective = extract_objective_from_task_ref(request_id)
    task_objective = extract_objective_from_task_ref(task_id)
    if request_objective and objective_id and request_objective != objective_id:
        append_error(result, "objective_id_mismatch", f"request_id={request_id} objective_id={packet.get('objective_id')}")
    if task_objective and objective_id and task_objective != objective_id:
        append_error(result, "objective_id_mismatch", f"task_id={task_id} objective_id={packet.get('objective_id')}")

    return {
        "request_id": request_id,
        "task_id": task_id,
        "objective_id": objective_id,
        "correlation_id": correlation_id,
    }


def validate_bridge_runtime(result: dict, packet: dict, expected: dict) -> None:
    bridge_runtime = packet.get("bridge_runtime")
    if not isinstance(bridge_runtime, dict):
        return

    current_processing = bridge_runtime.get("current_processing")
    if not isinstance(current_processing, dict):
        append_error(result, "missing_object", "bridge_runtime.current_processing")
        return

    require_exact_identity_match(result, expected["task_id"], current_processing.get("task_id"), "bridge_runtime.current_processing.task_id")
    require_exact_identity_match(result, expected["correlation_id"], current_processing.get("correlation_id"), "bridge_runtime.current_processing.correlation_id")
    if "request_id" in current_processing:
        require_exact_identity_match(result, expected["request_id"], current_processing.get("request_id"), "bridge_runtime.current_processing.request_id")
    if "objective_id" in current_processing:
        require_objective_identity_match(result, expected["objective_id"], current_processing.get("objective_id"), "bridge_runtime.current_processing.objective_id")


def validate_embedded_request_scope(result: dict, node, path: str, expected: dict) -> None:
    if isinstance(node, dict):
        exact_fields = {
            "request_id": expected["request_id"],
            "task_id": expected["task_id"],
            "correlation_id": expected["correlation_id"],
            "active_task_id": expected["task_id"],
            "selected_task_id": expected["task_id"],
            "current_task_id": expected["task_id"],
            "target_dispatch_task_id": expected["task_id"],
        }
        objective_fields = {
            "objective_id": expected["objective_id"],
            "requested_objective_id": expected["objective_id"],
            "normalized_objective_id": expected["objective_id"],
            "tod_current_objective": expected["objective_id"],
            "mim_objective_active": expected["objective_id"],
            "objective_active": expected["objective_id"],
        }

        for key, field_expected in exact_fields.items():
            if key in node:
                require_exact_identity_match(result, field_expected, node.get(key), f"{path}.{key}")

        for key, field_expected in objective_fields.items():
            if key in node:
                require_objective_identity_match(result, field_expected, node.get(key), f"{path}.{key}")

        for key, child in node.items():
            child_path = f"{path}.{key}"
            validate_embedded_request_scope(result, child, child_path, expected)
        return

    if isinstance(node, list):
        for index, child in enumerate(node):
            validate_embedded_request_scope(result, child, f"{path}[{index}]", expected)


def validate_semantic_embeds(result: dict, packet: dict, expected: dict, kind: str) -> None:
    validate_bridge_runtime(result, packet, expected)

    if kind == "ack":
        return

    for root_name in ("validator", "integration"):
        root_value = packet.get(root_name)
        if isinstance(root_value, (dict, list)):
            validate_embedded_request_scope(result, root_value, root_name, expected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--packet", required=True)
    parser.add_argument("--kind", required=True, choices=["ack", "result"])
    args = parser.parse_args()

    result = {
        "binding_active": False,
        "receipt_verified": False,
        "passed": False,
        "packet_kind": args.kind,
        "contract_version": "",
        "schema_version": "",
        "checksum_sha256": "",
        "packet_path": str(Path(args.packet)),
        "errors": [],
    }

    try:
        contract = yaml.safe_load(Path(args.contract).read_text(encoding="utf-8"))
    except Exception as exc:
        append_error(result, "contract_read_failed", str(exc))
        print(json.dumps(result))
        return 0

    try:
        receipt = json.loads(Path(args.receipt).read_text(encoding="utf-8"))
    except Exception as exc:
        append_error(result, "receipt_read_failed", str(exc))
        print(json.dumps(result))
        return 0

    try:
        packet = json.loads(Path(args.packet).read_text(encoding="utf-8"))
    except Exception as exc:
        append_error(result, "packet_read_failed", str(exc))
        print(json.dumps(result))
        return 0

    result["contract_version"] = str(contract.get("contract_version", ""))
    result["schema_version"] = str(contract.get("schema_version", ""))
    result["checksum_sha256"] = str(receipt.get("checksum_sha256", ""))

    receipt_ok = (
        str(receipt.get("acceptance_status", "")).lower() == "accepted"
        and bool(receipt.get("checksum_match"))
        and bool(receipt.get("no_reinterpretation_confirmed"))
        and str(receipt.get("contract_version", "")) == result["contract_version"]
        and str(receipt.get("schema_version", "")) == result["schema_version"]
    )
    result["receipt_verified"] = receipt_ok
    result["binding_active"] = receipt_ok
    if not receipt_ok:
        append_error(result, "receipt_not_verified", "accepted contract receipt is missing or invalid")

    required_fields = contract.get("message_envelope", {}).get("required_fields", [])
    for field_name in required_fields:
        if field_name == "source_identity":
            require_object_fields(result, packet, "source_identity", ["actor", "host", "service", "instance_id"])
            continue
        if field_name == "transport":
            require_object_fields(result, packet, "transport", ["transport_id", "surface"])
            continue
        if field_name == "sequence":
            require_positive_int(result, packet.get("sequence"), "sequence")
            continue
        require_non_empty_string(result, packet, field_name)

    expected_identity = validate_packet_identity_consistency(result, packet)

    if str(packet.get("contract_version", "")) != result["contract_version"]:
        append_error(result, "contract_version_mismatch", "packet.contract_version")
    if str(packet.get("schema_version", "")) != result["schema_version"]:
        append_error(result, "schema_version_mismatch", "packet.schema_version")
    if str(packet.get("checksum_sha256", "")) != result["checksum_sha256"]:
        append_error(result, "contract_checksum_mismatch", "packet.checksum_sha256")

    authoritative_surface = str(
        contract.get("transport_layer", {})
        .get("primary_transport", {})
        .get("authority_surface", "")
    )
    if str(packet.get("authoritative_surface", "")) != authoritative_surface:
        append_error(result, "authoritative_surface_mismatch", "packet.authoritative_surface")

    message_kind = contract.get("message_kinds", {}).get(args.kind, {})
    expected_packet_type = str(message_kind.get("packet_type", ""))
    allowed_status_values = [str(item) for item in message_kind.get("status_values", [])]
    status_value = str(packet.get("status", ""))
    result["expected_packet_type"] = expected_packet_type
    result["allowed_status_values"] = allowed_status_values

    if str(packet.get("message_kind", "")) != args.kind:
        append_error(result, "message_kind_mismatch", "packet.message_kind")
    if str(packet.get("packet_type", "")) != expected_packet_type:
        append_error(result, "packet_type_mismatch", "packet.packet_type")
    if status_value not in allowed_status_values:
        append_error(result, "invalid_status", f"packet.status={status_value}")

    if args.kind == "ack":
        if str(packet.get("ack_status", "")) != status_value:
            append_error(result, "ack_status_mismatch", "packet.ack_status")
        require_non_empty_string(result, packet, "ack_reason_code")
        require_positive_int(result, packet.get("acknowledged_trigger_sequence"), "acknowledged_trigger_sequence")
    elif args.kind == "result":
        if str(packet.get("result_status", "")) != status_value:
            append_error(result, "result_status_mismatch", "packet.result_status")
        if packet.get("terminal") is not True:
            append_error(result, "terminal_not_true", "packet.terminal")
        if not isinstance(packet.get("execution_outcome"), dict):
            append_error(result, "missing_execution_outcome", "packet.execution_outcome")
        require_non_empty_string(result, packet, "result_reason_code")

    validate_semantic_embeds(result, packet, expected_identity, args.kind)

    result["passed"] = receipt_ok and not result["errors"]
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())