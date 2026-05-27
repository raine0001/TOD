#!/usr/bin/env python3
import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path("/home/testpilot/mim")
SHARED = ROOT / "runtime" / "shared"
OBJECTIVE_ID = "AGENTMIM-FORUM-IMAGE-AUTO-QA-REMEDIATION-V1"


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_json(name: str, default):
    try:
        return json.loads((SHARED / name).read_text(encoding="utf-8"))
    except Exception:
        return default


def write_json(name: str, payload) -> str:
    path = SHARED / name
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    return f"runtime/shared/{name}"


def upsert_objective(container_name: str, objective: dict) -> str:
    data = read_json(container_name, {})
    objectives = data.setdefault("objectives", [])
    if not isinstance(objectives, list):
        objectives = []
        data["objectives"] = objectives
    replaced = False
    for idx, item in enumerate(objectives):
        if str(item.get("objective_id")) == OBJECTIVE_ID:
            existing = dict(item)
            existing.update(objective)
            objectives[idx] = existing
            replaced = True
            break
    if not replaced:
        objectives.append(objective)
    data["objective_count"] = len(objectives)
    data["generated_at"] = now_iso()
    data.setdefault("source", "mim-objectives-ui-v1")
    return write_json(container_name, data)


def main() -> int:
    generated_at = now_iso()
    research = {
        "packet_type": "agentmim-forum-image-prior-work-research-v1",
        "generated_at": generated_at,
        "objective_id": OBJECTIVE_ID,
        "status": "completed_research_for_objective",
        "prior_work_summary": [
            "docs/mim_forum_image_strategy.md defines intent routing, screenshot-backed compositions, generated scenes, and no/generated-text policy.",
            "docs/mim_image_development_reference.md defines the active forum-image source of truth, including review gates, retry/fallback policy, debug fields, and regression commands.",
            "scripts/debug_forum_image_generation.py can inspect or exercise a specific post's forum image pipeline.",
            "scripts/build_forum_image_golden_set.py and scripts/evaluate_forum_image_golden_set.py support accepted/rejected image dataset building and weekly quality trend evaluation.",
            "Recent commits added screenshot-backed routing, golden-set evals, OCR gates, adaptive RunPod model ladder, candidate ranking, targeted retry deltas, manual-review handling, and MIM opinion/mim_joke quality gates.",
            "routes/routes.py contains the main forum image pipeline: _forum_visual_family, _build_forum_image_prompt, _generate_forum_post_image, _review_forum_image_asset, and _build_forum_retry_image_prompt.",
        ],
        "failure_example": {
            "post_title": "MIM Opinion: Ubiquiti Patches Three Max Severity UniFi OS Vulnerabilities",
            "reported_asset": "forum/cards/b320cddd687e4420ad0159095ad1bce2.png",
            "reported_status": "ai_generated",
            "reported_provider": "runpod_forum_image_diffusion",
            "reported_family": "mim_opinion",
            "reported_review": "approved",
            "reported_candidate_score": 56.2,
            "operator_observed_problem": "The image is generic/low-relevance, text-heavy, and not meaningfully about Ubiquiti, UniFi OS, security patching, or vulnerability remediation despite being approved.",
            "root_hypothesis": "The review gate is accepting provider-valid art with weak post relevance and low semantic fit. Approval needs to require topic relevance, family fit, composition quality, and text policy, not only successful generation.",
        },
        "known_good_paths_to_reuse": [
            "forum image review scorecard and composite score",
            "candidate batch selection",
            "RunPod/OpenAI provider telemetry",
            "prompt variant and retry trace",
            "golden-set evaluation scripts",
            "manual-review queue and low-rating escalation path",
        ],
        "do_not_rebuild": [
            "Do not create a parallel forum image generator.",
            "Do not bypass _generate_forum_post_image.",
            "Do not mark success from image file creation alone.",
            "Do not let review=approved pass if semantic relevance is weak or composite score is below objective threshold.",
        ],
    }
    research_artifact = write_json("AGENTMIM_FORUM_IMAGE_PRIOR_WORK_RESEARCH.latest.json", research)

    objective = {
        "objective_id": OBJECTIVE_ID,
        "title": "AgentMIM forum image auto-generation QA and remediation",
        "priority": "P0",
        "owner": "MIM_TOD",
        "source": "Dave via Codex",
        "execution_mode": "auto",
        "auto_continue": True,
        "boundary_mode": "bounded",
        "created_at": generated_at,
        "updated_at": generated_at,
        "status": "queued",
        "description": "Fix agentmim.com/forum image generation so images are automatically created, evaluated for quality and post relevance, and regenerated or escalated when the image is poor, missing, generic, text-heavy, or semantically off-topic.",
        "goal": "Every eligible forum post gets an image automatically, and no image is marked successful unless it passes generation, file existence, semantic relevance, family-fit, composition, text-policy, and retry/remediation gates.",
        "constraints": [
            "Reuse existing forum image pipeline in E:/comm_app/routes/routes.py.",
            "Reuse existing docs, tests, golden-set scripts, review scorecards, candidate ranking, and RunPod/OpenAI telemetry.",
            "Do not create a competing image-generation path.",
            "Use the Ubiquiti/UniFi vulnerability post as a known failed-approved example.",
            "Do not claim completion from image creation alone.",
            "Publish operator-facing summaries in natural language.",
        ],
        "required_actions": [
            "Inspect prior forum image strategy, image development reference, golden-set scripts, debug script, and recent git history before changing code.",
            "Add or bind an auto-image creation sweep for eligible forum posts missing images or stuck in no_image/manual_review/regeneration failure states.",
            "Add a post-relevance QA gate that checks title/body/topic/family alignment against generated image review metadata and rejects generic/off-topic outputs.",
            "Raise production thresholds for mim_opinion and generated_only editorial images so candidate_score around 56 does not auto-approve without strong relevance evidence.",
            "When image QA fails, automatically retry with a stricter, shorter, topic-grounded prompt or route to screenshot/local family cover where applicable.",
            "Persist a QA artifact per generation with asset path, prompt source, provider, candidate score, relevance score, rejection reason, retry count, and next recovery action.",
            "Run focused tests for forum image review, candidate selection, retry, manual-review escalation, and golden-set evaluation where practical.",
            "Produce a remediation report for the Ubiquiti/UniFi example showing whether the original approved image is now rejected or replaced.",
        ],
        "success_criteria": [
            "A missing-image forum post is auto-generated without manual UI action.",
            "The Ubiquiti/UniFi vulnerability image example is not accepted at score 56.2 unless it has explicit semantic relevance evidence.",
            "Poor/generic/text-heavy images are rejected with a clear reason and retry/remediation action.",
            "At least one generated forum image has a QA artifact with relevance, composition, family_fit, text_cleanliness, provider, prompt, and candidate trace metadata.",
            "Forum list/detail paths do not silently show stale placeholder or failed assets as successful.",
            "MIM/TOD publishes AGENTMIM_FORUM_IMAGE_QA_REMEDIATION_STATUS.latest.json with completed, running, or blocked_with_evidence state.",
        ],
        "metadata_json": {
            "prior_work_research_artifact": research_artifact,
            "known_failed_approved_asset": "forum/cards/b320cddd687e4420ad0159095ad1bce2.png",
            "known_failed_approved_title": "MIM Opinion: Ubiquiti Patches Three Max Severity UniFi OS Vulnerabilities",
            "continuity_gate": {
                "required": True,
                "passed": True,
                "reason": "existing forum image generation and review pipeline found; objective must extend canonical path",
            },
        },
    }

    deck = {
        "packet_type": "agentmim-forum-image-auto-qa-objective-v1",
        "generated_at": generated_at,
        "status": "queued_for_mim_tod_execution",
        "success": True,
        "objective": objective,
        "research_artifact": research_artifact,
        "operator_facing_summary": "I created a focused MIM/TOD objective for the forum image problem. It reuses the existing forum image pipeline and treats the Ubiquiti/UniFi image as a failed-approved example that must be rejected, regenerated, or explained with evidence.",
        "next_recovery_action": "MIM/TOD should execute the objective by binding an auto-generation sweep and a stricter image QA/relevance gate.",
    }
    objective_artifact = write_json("AGENTMIM_FORUM_IMAGE_AUTO_QA_OBJECTIVE.latest.json", deck)

    upsert_objective("MIM_TOD_MANAGED_OBJECTIVES.latest.json", objective)
    upsert_objective("MIM_TOD_OBJECTIVE_INDEX.latest.json", objective)

    execution = read_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json", {})
    objectives = execution.setdefault("objectives", {})
    entry = {
        "objective_id": OBJECTIVE_ID,
        "title": objective["title"],
        "status": "queued",
        "reason_code": "forum_image_auto_qa_objective_created",
        "generated_at": generated_at,
        "artifact": objective_artifact,
        "operator_facing_summary": deck["operator_facing_summary"],
        "next_recovery_action": deck["next_recovery_action"],
    }
    objectives[OBJECTIVE_ID] = entry
    execution["latest_action"] = entry
    execution["generated_at"] = generated_at
    write_json("MIM_TOD_OBJECTIVE_EXECUTION_STATUS.latest.json", execution)

    implementation_request = {
        "packet_type": "mim-codex-implementation-request-v1",
        "generated_at": generated_at,
        "objective_id": OBJECTIVE_ID,
        "problem_class": "forum_images_missing_or_low_quality_despite_approved_status",
        "requested_action": "Extend the canonical forum image pipeline with auto-generation sweep, stricter QA/relevance gates, retry/remediation, and evidence artifacts.",
        "attempted_paths": [
            "prior docs inspected",
            "git history inspected",
            "canonical routes/routes.py image pipeline identified",
            "debug and golden-set scripts identified",
        ],
        "canonical_solutions_checked": [
            "docs/mim_forum_image_strategy.md",
            "docs/mim_image_development_reference.md",
            "scripts/debug_forum_image_generation.py",
            "scripts/build_forum_image_golden_set.py",
            "scripts/evaluate_forum_image_golden_set.py",
            "routes/routes.py::_generate_forum_post_image",
            "routes/routes.py::_review_forum_image_asset",
        ],
        "expected_files": [
            "E:/comm_app/routes/routes.py",
            "E:/comm_app/tests/test_forum_post_quality.py",
            "E:/comm_app/scripts/debug_forum_image_generation.py",
            "runtime/shared/AGENTMIM_FORUM_IMAGE_QA_REMEDIATION_STATUS.latest.json",
        ],
        "validation_requirements": objective["success_criteria"],
        "operator_facing_summary": deck["operator_facing_summary"],
    }
    request_artifact = write_json("MIM_CODEX_IMPLEMENTATION_REQUEST.agentmim_forum_image_auto_qa.latest.json", implementation_request)

    print(json.dumps({
        "success": True,
        "status": "queued_for_mim_tod_execution",
        "objective_id": OBJECTIVE_ID,
        "objective_artifact": objective_artifact,
        "research_artifact": research_artifact,
        "implementation_request_artifact": request_artifact,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
