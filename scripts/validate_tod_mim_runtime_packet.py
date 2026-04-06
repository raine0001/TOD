import argparse
import json
from pathlib import Path

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

    result["passed"] = receipt_ok and not result["errors"]
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())