from __future__ import annotations

import copy
import ast
import json
from pathlib import Path

import pytest


def _load_contract_helpers() -> dict:
    source_path = Path(__file__).parents[1] / "runtime_remote_training" / "creative_remote_app.py"
    tree = ast.parse(source_path.read_text(encoding="utf-8"), filename=str(source_path))
    selected = []
    names = {
        "REVIEW_SCORE_KEYS",
        "REVIEW_HARD_FAILURES",
        "_normalized_context_text",
        "_decode_review_content",
        "_validated_review_payload",
        "_bind_review_required_element_labels",
    }
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id in names for target in node.targets
        ):
            selected.append(node)
        elif isinstance(node, ast.FunctionDef) and node.name in names:
            selected.append(node)
    namespace = {"json": json}
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(source_path), "exec"), namespace)
    return namespace


_HELPERS = _load_contract_helpers()
REVIEW_SCORE_KEYS = _HELPERS["REVIEW_SCORE_KEYS"]
_decode_review_content = _HELPERS["_decode_review_content"]
_validated_review_payload = _HELPERS["_validated_review_payload"]
_bind_review_required_element_labels = _HELPERS["_bind_review_required_element_labels"]


def _review(required: list[str]) -> dict:
    return {
        "scores": {key: 82 for key in REVIEW_SCORE_KEYS},
        "hard_failures": [],
        "detected_text": [],
        "observations": ["A visible subject occupies the center of the image."],
        "required_elements": [
            {"element": label, "present": True, "evidence": f"Visible {label}."}
            for label in required
        ],
        "scene_description": "A coherent visible scene.",
        "summary": "The image is usable.",
    }


def test_decode_review_content_accepts_plain_json_and_json_fence():
    payload = _review(["cat", "desk"])
    encoded = json.dumps(payload)
    assert _decode_review_content(encoded) == payload
    assert _decode_review_content(f"```json\n{encoded}\n```") == payload


def test_decode_review_content_rejects_truncated_or_trailing_content():
    with pytest.raises(ValueError, match="image_review_response_invalid"):
        _decode_review_content('{"scores":')
    with pytest.raises(ValueError, match="image_review_response_invalid"):
        _decode_review_content('{"scores": {}} trailing prose')


def test_review_contract_requires_exact_supplied_element_labels_and_order():
    source = {"required_elements": ["cat", "desk"]}
    assert _validated_review_payload(_review(["cat", "desk"]), source_payload=source)

    invented = _review(["cat", "desk", "modern atmosphere"])
    with pytest.raises(ValueError, match="image_review_required_elements_contract_invalid"):
        _validated_review_payload(invented, source_payload=source)

    renamed = _review(["desk", "cat"])
    with pytest.raises(ValueError, match="image_review_required_elements_contract_invalid"):
        _validated_review_payload(renamed, source_payload=source)


def test_review_contract_does_not_mutate_supplied_required_elements():
    payload = _review(["cat"])
    original = copy.deepcopy(payload)
    _validated_review_payload(payload, source_payload={"required_elements": ["cat"]})
    assert payload == original


def test_review_element_transport_labels_are_rebound_without_changing_evidence():
    payload = {
        "required_elements": [
            {"element": "Requirement one", "present": True, "evidence": "A cat is visible."},
            {"element": "second", "present": False, "evidence": ""},
        ]
    }

    rebound = _bind_review_required_element_labels(payload, ["R1", "R2"])

    assert rebound["required_elements"] == [
        {"element": "R1", "present": True, "evidence": "A cat is visible."},
        {"element": "R2", "present": False, "evidence": ""},
    ]


def test_review_element_transport_ignores_unsolicited_extra_rows():
    payload = {
        "required_elements": [
            {"element": "R1", "present": True, "evidence": "A cat is visible."},
            {"element": "invented", "present": True, "evidence": "A desk is visible."},
        ]
    }

    rebound = _bind_review_required_element_labels(payload, ["R1"])

    assert rebound["required_elements"] == [
        {"element": "R1", "present": True, "evidence": "A cat is visible."}
    ]


def test_pixel_reviewer_keeps_local_vision_model_resident():
    source_path = Path(__file__).parents[1] / "runtime_remote_training" / "creative_remote_app.py"
    source = source_path.read_text(encoding="utf-8")

    assert source.count('"keep_alive": -1') == 2
    assert '"keep_alive": 0' not in source


def test_pixel_reviewer_separates_unprompted_pixels_from_requirement_relation():
    source_path = Path(__file__).parents[1] / "runtime_remote_training" / "creative_remote_app.py"
    source = source_path.read_text(encoding="utf-8")

    assert source.count("/api/chat") == 2
    assert 'review_stage = "relation"' in source
    assert "You are not being told what the image was supposed to show" in source
    assert "Pixel-visible fields have first authority" in source
    assert "evidence not in normalized_observations" in source
