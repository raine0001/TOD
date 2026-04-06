import argparse
import hashlib
import json
from pathlib import Path

import jsonschema
import yaml


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yaml", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--signature", required=True)
    args = parser.parse_args()

    yaml_path = Path(args.yaml)
    schema_path = Path(args.schema)
    signature_path = Path(args.signature)

    result = {
        "passed": False,
        "yaml_path": str(yaml_path),
        "schema_path": str(schema_path),
        "signature_path": str(signature_path),
        "actual_sha256": "",
        "expected_sha256": "",
        "checksum_match": False,
        "schema_valid": False,
        "version_ok": False,
        "contract_version": "",
        "signature_version": "",
        "schema_version": "",
        "contract_name": "",
        "errors": [],
    }

    try:
        yaml_bytes = yaml_path.read_bytes()
        result["actual_sha256"] = hashlib.sha256(yaml_bytes).hexdigest()
    except Exception as exc:
        result["errors"].append(f"yaml_read_failed: {exc}")
        print(json.dumps(result))
        return 0

    try:
        signature = json.loads(signature_path.read_text(encoding="utf-8"))
    except Exception as exc:
        result["errors"].append(f"signature_read_failed: {exc}")
        print(json.dumps(result))
        return 0

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except Exception as exc:
        result["errors"].append(f"schema_read_failed: {exc}")
        print(json.dumps(result))
        return 0

    try:
        contract = yaml.safe_load(yaml_bytes.decode("utf-8"))
    except Exception as exc:
        result["errors"].append(f"yaml_parse_failed: {exc}")
        print(json.dumps(result))
        return 0

    result["expected_sha256"] = str(signature.get("sha256", ""))
    result["checksum_match"] = result["actual_sha256"] == result["expected_sha256"]
    result["contract_version"] = str(contract.get("contract_version", ""))
    result["signature_version"] = str(signature.get("version", ""))
    result["schema_version"] = str(contract.get("schema_version", ""))
    result["contract_name"] = str(contract.get("contract_name", ""))

    if not result["checksum_match"]:
        result["errors"].append("checksum_mismatch")

    try:
        jsonschema.validate(instance=contract, schema=schema)
        result["schema_valid"] = True
    except jsonschema.ValidationError as exc:
        result["errors"].append(f"schema_validation_failed: {exc.message}")

    result["version_ok"] = (
        result["contract_version"] == "v1"
        and result["signature_version"] == "v1"
    )
    if not result["version_ok"]:
        result["errors"].append("contract_version_mismatch")

    result["passed"] = (
        result["checksum_match"]
        and result["schema_valid"]
        and result["version_ok"]
    )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())