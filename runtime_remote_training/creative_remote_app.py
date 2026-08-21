from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import json
import logging
import time
import uuid
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from PIL import Image, UnidentifiedImageError

from .admission import AdmissionController
from .auth import require_api_key
from .config import Settings, get_settings
from .models import (
    ALLOWED_INTENTS,
    Envelope,
    ErrorPayload,
    GenerateImageJobRequest,
    JobAcceptedResponse,
    JobResponse,
    OutcomeStatus,
    ReadyPayload,
)
from .queue_manager import QueueFullError, QueueManager
from .runtime import build_runtime
from .storage import StorageManager


logger = logging.getLogger("mim_creative_worker")

REVIEW_SCORE_KEYS = (
    "prompt_adherence",
    "subject_accuracy",
    "composition",
    "anatomy_quality",
    "object_integrity",
    "text_cleanliness",
    "visual_quality",
    "professional_usability",
)
REVIEW_HARD_FAILURES = (
    "broken_anatomy",
    "broken_object",
    "corrupt_image",
    "duplicate_subject",
    "missing_required_subject",
    "prompt_mismatch",
    "readable_text",
    "severe_crop",
    "unsafe_content",
)
REVIEW_MEDIA_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_REVIEW_IMAGE_BYTES = 12 * 1024 * 1024


def _review_schema() -> dict:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "scores",
            "hard_failures",
            "detected_text",
            "observations",
            "required_elements",
            "scene_description",
            "summary",
        ],
        "properties": {
            "scores": {
                "type": "object",
                "additionalProperties": False,
                "required": list(REVIEW_SCORE_KEYS),
                "properties": {
                    key: {"type": "number", "minimum": 0, "maximum": 100}
                    for key in REVIEW_SCORE_KEYS
                },
            },
            "hard_failures": {
                "type": "array",
                "items": {"type": "string", "enum": list(REVIEW_HARD_FAILURES)},
            },
            "detected_text": {
                "type": "array",
                "maxItems": 12,
                "items": {"type": "string", "maxLength": 80},
            },
            "observations": {
                "type": "array",
                "maxItems": 8,
                "items": {"type": "string", "maxLength": 300},
            },
            "required_elements": {
                "type": "array",
                "maxItems": 20,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["element", "present", "evidence"],
                    "properties": {
                        "element": {"type": "string", "maxLength": 20},
                        "present": {"type": "boolean"},
                        "evidence": {"type": "string", "maxLength": 300},
                    },
                },
            },
            "scene_description": {"type": "string", "maxLength": 600},
            "summary": {"type": "string", "maxLength": 600},
        },
    }


def _validated_review_image(payload: dict) -> tuple[bytes, str]:
    media_type = str(payload.get("media_type") or "").strip().lower()
    encoded = str(payload.get("image_base64") or "").strip()
    if media_type not in REVIEW_MEDIA_TYPES:
        raise ValueError("unsupported_image_media_type")
    if not encoded or len(encoded) > (MAX_REVIEW_IMAGE_BYTES * 4 // 3) + 16:
        raise ValueError("invalid_image_payload")
    try:
        image_bytes = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise ValueError("invalid_image_payload") from exc
    if not image_bytes or len(image_bytes) > MAX_REVIEW_IMAGE_BYTES:
        raise ValueError("invalid_image_payload")
    try:
        with Image.open(BytesIO(image_bytes)) as image:
            image.verify()
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise ValueError("invalid_image_payload") from exc
    return image_bytes, encoded


def _normalized_context_text(value: object) -> str:
    return " ".join(str(value or "").casefold().split())


def _decode_review_content(content: object) -> dict:
    text = str(content or "").strip()
    if text.startswith("```") and text.endswith("```"):
        lines = text.splitlines()
        if lines and lines[0].strip().casefold() in {"```", "```json"}:
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines).strip()
    try:
        decoded = json.loads(text)
    except json.JSONDecodeError:
        decoder = json.JSONDecoder()
        object_start = text.find("{")
        if object_start < 0:
            raise ValueError("image_review_response_invalid") from None
        try:
            decoded, end = decoder.raw_decode(text[object_start:])
        except json.JSONDecodeError as exc:
            raise ValueError("image_review_response_invalid") from exc
        if text[object_start + end :].strip().strip("`").strip():
            raise ValueError("image_review_response_invalid")
    if not isinstance(decoded, dict):
        raise ValueError("image_review_response_invalid")
    return decoded


def _validated_review_payload(value: object, *, source_payload: dict | None = None) -> dict:
    if not isinstance(value, dict):
        raise ValueError("image_review_response_invalid")
    scores = value.get("scores")
    if not isinstance(scores, dict) or set(scores) != set(REVIEW_SCORE_KEYS):
        raise ValueError("image_review_response_invalid")
    numeric_scores: list[float] = []
    for score in scores.values():
        if isinstance(score, bool) or not isinstance(score, (int, float)):
            raise ValueError("image_review_response_invalid")
        numeric_score = float(score)
        if numeric_score < 0 or numeric_score > 100:
            raise ValueError("image_review_response_invalid")
        numeric_scores.append(numeric_score)
    # Some local vision models ignore the schema range and return probabilities.
    # Normalize the complete 0..1 scale atomically; never mix two score scales.
    if numeric_scores and max(numeric_scores) <= 1.0:
        value["scores"] = {key: round(float(score) * 100.0, 2) for key, score in scores.items()}
    elif numeric_scores == [float(index) for index in range(len(REVIEW_SCORE_KEYS))]:
        # This is schema-position imitation, not an image-quality judgment.
        raise ValueError("image_review_score_contract_invalid")
    failures = value.get("hard_failures")
    required = value.get("required_elements")
    if not isinstance(failures, list) or any(item not in REVIEW_HARD_FAILURES for item in failures):
        raise ValueError("image_review_response_invalid")
    if not isinstance(required, list):
        raise ValueError("image_review_response_invalid")
    for item in required:
        if not isinstance(item, dict) or set(item) != {"element", "present", "evidence"}:
            raise ValueError("image_review_response_invalid")
        if not isinstance(item.get("present"), bool):
            raise ValueError("image_review_response_invalid")
    source_payload = source_payload or {}
    source_required = source_payload.get("required_elements")
    if not isinstance(source_required, list):
        source_required = []
    expected_labels = [str(item).strip() for item in source_required if str(item).strip()]
    returned_labels = [str(item.get("element") or "").strip() for item in required]
    if returned_labels != expected_labels:
        raise ValueError("image_review_required_elements_contract_invalid")
    for key in ("detected_text", "observations"):
        if not isinstance(value.get(key), list):
            raise ValueError("image_review_response_invalid")
    if not isinstance(value.get("scene_description"), str) or not isinstance(value.get("summary"), str):
        raise ValueError("image_review_response_invalid")
    context_values = [
        _normalized_context_text(source_payload.get("title")),
        _normalized_context_text(source_payload.get("body")),
        _normalized_context_text(source_payload.get("prompt")),
    ]
    pixel_text: list[str] = []
    for item in value.get("detected_text") or []:
        text = str(item or "").strip()
        normalized = _normalized_context_text(text)
        if not normalized:
            continue
        # Long strings copied from request metadata are not pixel evidence.
        if len(normalized) >= 8 and any(
            normalized in context or context in normalized
            for context in context_values
            if context
        ):
            continue
        pixel_text.append(text[:80])
    value["detected_text"] = pixel_text[:20]
    return value


def _bind_review_required_element_labels(value: object, expected_labels: list[str]) -> dict:
    """Restore caller-owned transport labels without changing review evidence."""
    if not isinstance(value, dict):
        raise ValueError("image_review_response_invalid")
    required = value.get("required_elements")
    if not isinstance(required, list) or len(required) < len(expected_labels):
        raise ValueError("image_review_required_elements_contract_invalid")
    rebound: list[dict] = []
    for item, label in zip(required[: len(expected_labels)], expected_labels, strict=True):
        if not isinstance(item, dict) or set(item) != {"element", "present", "evidence"}:
            raise ValueError("image_review_response_invalid")
        rebound.append({**item, "element": label})
    value["required_elements"] = rebound
    return value


@dataclass
class ServiceContext:
    settings: Settings
    admission: AdmissionController
    runtime: object
    storage: StorageManager
    queue: QueueManager
    loop_ok: bool = True
    runtime_warm: bool = False


async def _url_ready(url: str) -> bool:
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            resp = await client.get(url)
        return resp.status_code == 200
    except httpx.HTTPError:
        return False


def _new_request_id() -> str:
    return str(uuid.uuid4())


def _err(
    request_id: str,
    status_code: int,
    outcome: OutcomeStatus,
    code: str,
    message: str,
    headers: dict[str, str] | None = None,
) -> HTTPException:
    detail = {
        "request_id": request_id,
        "status": outcome.value,
        "error": ErrorPayload(code=code, message=message).model_dump(),
    }
    if headers:
        detail["headers"] = headers
    return HTTPException(status_code=status_code, detail=detail)


def create_app() -> FastAPI:
    settings = get_settings()
    admission = AdmissionController(settings)
    runtime = build_runtime(settings)
    storage = StorageManager(
        root=settings.output_root,
        retention_days=settings.retention_days,
        quota_gib=settings.storage_quota_gib,
        cleanup_target_ratio=settings.storage_cleanup_target_ratio,
        hard_reject_ratio=settings.storage_hard_reject_ratio,
    )
    queue = QueueManager(settings, admission, runtime, storage)

    app = FastAPI(title="mim-creative-worker", version="1.1.0")
    app.state.ctx = ServiceContext(settings=settings, admission=admission, runtime=runtime, storage=storage, queue=queue)

    security = require_api_key(settings)

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
        headers = None
        if isinstance(exc.detail, dict):
            headers = exc.detail.pop("headers", None)
        return JSONResponse(status_code=exc.status_code, content=exc.detail, headers=headers)

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        body = {
            "request_id": "00000000-0000-0000-0000-000000000000",
            "status": OutcomeStatus.rejected_invalid.value,
            "error": {
                "code": "invalid_request",
                "message": str(exc),
            },
        }
        return JSONResponse(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, content=body)

    @app.on_event("startup")
    async def startup() -> None:
        logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
        storage.ensure_root()
        await queue.start()

        async def retention_loop() -> None:
            while True:
                try:
                    removed = await asyncio.to_thread(storage.cleanup)
                    if removed:
                        logger.info({"event": "retention_cleanup", "removed": removed})
                except Exception as exc:  # pragma: no cover
                    logger.warning({"event": "retention_cleanup_error", "error": str(exc)})
                await asyncio.sleep(24 * 3600)

        app.state.retention_task = asyncio.create_task(retention_loop(), name="creative_retention")

    @app.on_event("shutdown")
    async def shutdown() -> None:
        task = getattr(app.state, "retention_task", None)
        if task is not None:
            task.cancel()
        await queue.stop()

    @app.get("/health", dependencies=[security], response_model=Envelope)
    async def health() -> Envelope:
        return Envelope(request_id=_new_request_id(), status=OutcomeStatus.completed, error=None)

    @app.get("/ready", dependencies=[security], response_model=ReadyPayload)
    async def ready() -> JSONResponse:
        req_id = _new_request_id()
        blocked_by = None

        if not settings.bearer_token_is_strong():
            blocked_by = "weak_auth_token"

        runtime_ok = await runtime.health()
        assets_ok, asset_reason = await runtime.validate_assets()
        if not runtime_ok:
            blocked_by = blocked_by or "runtime_unavailable"
        if not assets_ok:
            blocked_by = blocked_by or (asset_reason or "runtime_assets_invalid")

        storage.ensure_root()
        storage_decision = storage.check_capacity_for_new_job()
        if not storage_decision.allowed:
            blocked_by = blocked_by or storage_decision.code

        resident_ready = await _url_ready(settings.resident_mim_ready_url) and await _url_ready(settings.resident_tod_ready_url)
        if not resident_ready:
            blocked_by = blocked_by or "resident_models_not_ready"

        queue_depth = await queue.queue_depth()
        queue_has_space = queue_depth < settings.queue_max_waiting
        if not queue_has_space:
            blocked_by = blocked_by or "queue_full"

        admission = await app.state.ctx.admission.can_start_job()
        execution_available = admission.allowed
        if not admission.allowed:
            blocked_by = blocked_by or admission.blocked_by

        payload = ReadyPayload(
            status="ready" if blocked_by is None else "not_ready",
            runtime="available" if runtime_ok and assets_ok else "unavailable",
            warm_state="warm" if app.state.ctx.runtime_warm else "cold",
            queue_depth=queue_depth,
            queue_capacity=settings.queue_max_waiting,
            execution_available=execution_available,
            blocked_by=blocked_by,
            request_id=req_id,
        )

        code = status.HTTP_200_OK if blocked_by is None else status.HTTP_503_SERVICE_UNAVAILABLE
        return JSONResponse(status_code=code, content=payload.model_dump())

    @app.post(
        "/v1/images/jobs",
        dependencies=[security],
        response_model=JobAcceptedResponse,
        status_code=status.HTTP_202_ACCEPTED,
    )
    async def create_job(request: GenerateImageJobRequest) -> JobAcceptedResponse:
        if request.intent_object.intent not in ALLOWED_INTENTS:
            raise _err(
                request.request_id,
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                OutcomeStatus.rejected_unsupported,
                "unsupported_intent",
                "Intent is not supported by Phase 1 creative worker.",
            )

        storage_decision = storage.check_capacity_for_new_job()
        if not storage_decision.allowed:
            raise _err(
                request.request_id,
                status.HTTP_507_INSUFFICIENT_STORAGE,
                OutcomeStatus.rejected_policy,
                storage_decision.code or "storage_hard_limit",
                storage_decision.message or "Storage hard limit reached.",
            )

        try:
            job = await queue.enqueue(request)
        except QueueFullError:
            raise _err(
                request.request_id,
                status.HTTP_429_TOO_MANY_REQUESTS,
                OutcomeStatus.overloaded,
                "queue_full",
                "Creative queue is full. Retry later.",
                headers={"Retry-After": "30"},
            )

        return JobAcceptedResponse(request_id=request.request_id, status=OutcomeStatus.accepted, error=None, job_id=job.job_id)

    @app.post("/v1/image-reviews", dependencies=[security])
    async def review_image(payload: dict) -> dict:
        request_id = _new_request_id()
        try:
            image_bytes, encoded = _validated_review_image(payload)
        except ValueError as exc:
            raise _err(
                request_id,
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                OutcomeStatus.rejected_invalid,
                str(exc),
                "The image review payload is invalid.",
            ) from exc

        required_elements = payload.get("required_elements")
        if not isinstance(required_elements, list):
            required_elements = []
        required_labels = [str(item).strip() for item in required_elements[:20] if str(item).strip()]
        required_contract = [
            {"element": f"R{index}", "requirement": label}
            for index, label in enumerate(required_labels, start=1)
        ]
        grounding_prompt = (
            "Inspect only the supplied image pixels. You are not being told what the image was supposed to show. "
            "Describe only objects, subjects, actions, layout, defects, and literal text that are visibly present. "
            "Never infer a product, story, purpose, brand, or topic that is not established by the pixels. "
            "Return the exact requested JSON structure with required_elements as an empty array. "
            "In detected_text, quote only literal glyphs visibly rendered inside the image. "
            "Write concrete standalone observation sentences. Judge visual quality conservatively with genuine "
            "0 to 100 scores. Do not invent visible evidence."
        )
        try:
            review_stage = "grounding"
            async with httpx.AsyncClient(timeout=settings.vision_review_timeout_seconds) as client:
                grounding_response = await client.post(
                    f"{settings.vision_review_base_url.rstrip('/')}/api/chat",
                    json={
                        "model": settings.vision_review_model,
                        "stream": False,
                        # Keep the local vision model resident. Unloading it after
                        # each review makes the next cold review exceed the public
                        # gateway's synchronous request ceiling.
                        "keep_alive": -1,
                        "format": _review_schema(),
                        "messages": [{"role": "user", "content": grounding_prompt, "images": [encoded]}],
                        "options": {
                            "temperature": 0,
                            "num_ctx": 4096,
                            "num_predict": 1200,
                            "num_thread": settings.vision_review_threads,
                        },
                    },
                )
                grounding_response.raise_for_status()
                grounding_envelope = grounding_response.json()
                grounding_content = str(
                    ((grounding_envelope.get("message") or {}).get("content")) or ""
                ).strip()
                grounding_decoded = _bind_review_required_element_labels(
                    _decode_review_content(grounding_content),
                    [],
                )
                pixel_review = _validated_review_payload(
                    grounding_decoded,
                    source_payload={"required_elements": []},
                )
                review_stage = "relation"
                evidence_packet = {
                    "observations": list(pixel_review.get("observations") or []),
                    "scene_description": str(pixel_review.get("scene_description") or ""),
                    "detected_text": list(pixel_review.get("detected_text") or []),
                    "pixel_quality_scores": dict(pixel_review.get("scores") or {}),
                }
                relation_prompt = (
                    "Compare the immutable pixel evidence packet to the requested visual requirements. "
                    "The evidence packet was produced without seeing the requirements. Do not add, rewrite, or infer "
                    "anything not stated in that packet. Return the exact requested JSON structure. Copy observations, "
                    "scene_description, and detected_text exactly from the packet. Return one required_elements row for "
                    "each R-number below, in order. Set present=true only when evidence repeats one complete observation "
                    "sentence verbatim; otherwise set present=false with an empty evidence string. Score prompt adherence "
                    "and subject accuracy from the comparison; preserve the pixel quality scores for the other quality "
                    "dimensions. Use prompt_mismatch or missing_required_subject when the packet does not establish the "
                    "requirements.\n"
                    f"Immutable pixel evidence: {json.dumps(evidence_packet, ensure_ascii=True)}\n"
                    f"Visual requirements: {json.dumps(required_contract, ensure_ascii=True)}"
                )
                relation_response = await client.post(
                    f"{settings.vision_review_base_url.rstrip('/')}/api/chat",
                    json={
                        "model": settings.vision_review_model,
                        "stream": False,
                        "keep_alive": -1,
                        "format": _review_schema(),
                        "messages": [{"role": "user", "content": relation_prompt}],
                        "options": {
                            "temperature": 0,
                            "num_ctx": 4096,
                            "num_predict": 1200,
                            "num_thread": settings.vision_review_threads,
                        },
                    },
                )
                relation_response.raise_for_status()
                relation_envelope = relation_response.json()
                relation_content = str(
                    ((relation_envelope.get("message") or {}).get("content")) or ""
                ).strip()
                relation_decoded = _bind_review_required_element_labels(
                    _decode_review_content(relation_content),
                    [item["element"] for item in required_contract],
                )
                review = _validated_review_payload(
                    relation_decoded,
                    source_payload={"required_elements": [item["element"] for item in required_contract]},
                )
                # Pixel-visible fields have first authority. The relation pass
                # may compare them to requirements but may never rewrite them.
                review["observations"] = list(pixel_review.get("observations") or [])
                review["scene_description"] = str(pixel_review.get("scene_description") or "")
                review["detected_text"] = list(pixel_review.get("detected_text") or [])
                normalized_observations = [
                    _normalized_context_text(item)
                    for item in review.get("observations") or []
                    if str(item or "").strip()
                ]
                for item, label in zip(review["required_elements"], required_labels, strict=True):
                    evidence = _normalized_context_text(item.get("evidence"))
                    if item.get("present") and evidence not in normalized_observations:
                        item["present"] = False
                        item["evidence"] = ""
                    item["element"] = label
                if any(not item["present"] for item in review["required_elements"]):
                    review["hard_failures"] = list(
                        dict.fromkeys([*review["hard_failures"], "missing_required_subject"])
                    )
                envelope = {
                    "prompt_eval_count": int(grounding_envelope.get("prompt_eval_count") or 0)
                    + int(relation_envelope.get("prompt_eval_count") or 0),
                    "eval_count": int(grounding_envelope.get("eval_count") or 0)
                    + int(relation_envelope.get("eval_count") or 0),
                }
        except (httpx.HTTPError, json.JSONDecodeError, ValueError, TypeError) as exc:
            logger.warning(
                {
                    "event": "image_review_failed",
                    "error_type": type(exc).__name__,
                    "error_code": str(exc)[:120],
                    "review_stage": str(locals().get("review_stage", "unknown"))[:24],
                    "content_length": len(locals().get("grounding_content", "")),
                    "finish_reason": str(
                        locals().get("grounding_envelope", {}).get("done_reason")
                        or ""
                    )[:40],
                }
            )
            raise _err(
                request_id,
                status.HTTP_503_SERVICE_UNAVAILABLE,
                OutcomeStatus.transient_failure,
                "local_vision_review_unavailable",
                "The local pixel-visible reviewer could not complete the review.",
            ) from exc

        return {
            "status": "completed",
            "contract_version": "forum-image-quality-v1",
            "request_id": request_id,
            "provider_request_id": "",
            "provider": "mim_creative_local",
            "model": settings.vision_review_model,
            "external_provider_used": False,
            "image_sha256": hashlib.sha256(image_bytes).hexdigest(),
            "review": review,
            "usage": {
                "input_tokens": int(envelope.get("prompt_eval_count") or 0),
                "output_tokens": int(envelope.get("eval_count") or 0),
                "total_tokens": int(envelope.get("prompt_eval_count") or 0)
                + int(envelope.get("eval_count") or 0),
            },
        }

    @app.get("/v1/jobs/queue", dependencies=[security])
    async def queue_state() -> dict:
        snap = await queue.queue_snapshot()
        return {
            "request_id": _new_request_id(),
            "status": OutcomeStatus.completed.value,
            "error": None,
            **snap,
            "timestamp": int(time.time()),
        }

    @app.get("/v1/jobs/{job_id}", dependencies=[security], response_model=JobResponse)
    async def get_job(job_id: str) -> JobResponse:
        job = await queue.get_job(job_id)
        if job is None:
            raise _err(
                request_id="00000000-0000-0000-0000-000000000000",
                status_code=status.HTTP_404_NOT_FOUND,
                outcome=OutcomeStatus.rejected_invalid,
                code="job_not_found",
                message="Unknown job_id.",
            )

        if job.status == OutcomeStatus.completed:
            app.state.ctx.runtime_warm = True

        return JobResponse(
            request_id=job.request.request_id,
            status=job.status,
            error=job.error,
            job_id=job.job_id,
            image_paths=job.image_paths,
            metadata=job.metadata,
        )

    @app.get("/v1/jobs/{job_id}/artifacts/{artifact_index}", dependencies=[security])
    async def get_job_artifact(job_id: str, artifact_index: int) -> FileResponse:
        job = await queue.get_job(job_id)
        if job is None:
            raise _err(
                request_id="00000000-0000-0000-0000-000000000000",
                status_code=status.HTTP_404_NOT_FOUND,
                outcome=OutcomeStatus.rejected_invalid,
                code="job_not_found",
                message="Unknown job_id.",
            )
        if job.status != OutcomeStatus.completed:
            raise _err(
                request_id=job.request.request_id,
                status_code=status.HTTP_409_CONFLICT,
                outcome=OutcomeStatus.rejected_policy,
                code="artifact_not_ready",
                message="Job has not completed.",
            )
        if artifact_index < 0 or artifact_index >= len(job.image_paths):
            raise _err(
                request_id=job.request.request_id,
                status_code=status.HTTP_404_NOT_FOUND,
                outcome=OutcomeStatus.rejected_invalid,
                code="artifact_not_found",
                message="Artifact index does not exist.",
            )

        output_root = settings.output_root.resolve()
        artifact = Path(job.image_paths[artifact_index]).resolve()
        try:
            artifact.relative_to(output_root)
        except ValueError as exc:
            raise _err(
                request_id=job.request.request_id,
                status_code=status.HTTP_403_FORBIDDEN,
                outcome=OutcomeStatus.rejected_policy,
                code="artifact_outside_output_root",
                message="Artifact path is outside the configured output root.",
            ) from exc
        if not artifact.is_file():
            raise _err(
                request_id=job.request.request_id,
                status_code=status.HTTP_404_NOT_FOUND,
                outcome=OutcomeStatus.rejected_invalid,
                code="artifact_missing",
                message="Artifact file is missing.",
            )
        media_type = "image/png" if artifact.suffix.lower() == ".png" else "application/octet-stream"
        return FileResponse(path=artifact, media_type=media_type, filename=artifact.name)

    return app
