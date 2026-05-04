import argparse
import html
import json
import math
import random
import re
import socket
import sys
import time
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


FIRST_NAMES = [
    "Alex", "Jordan", "Taylor", "Morgan", "Riley", "Casey", "Avery", "Cameron", "Drew", "Harper",
    "Quinn", "Parker", "Logan", "Sage", "Rowan", "Elliot", "Jamie", "Blair", "Emerson", "Skyler",
    "Micah", "Robin", "Ari", "Finley", "Reese", "Dakota", "Charlie", "Phoenix", "Milan", "Tatum",
    "Kendall", "Shiloh", "Devon", "Remy", "Noel", "Kieran", "Sam", "Bailey", "Kai", "River"
]
LAST_NAMES = [
    "Stone", "Rivera", "Cole", "Bennett", "Sloan", "Wells", "Brooks", "Morris", "Shaw", "Reed",
    "Hayes", "Perry", "Lane", "Cross", "Fields", "Pruitt", "Nolan", "Frost", "Parks", "Bell",
    "Turner", "Wallace", "Kim", "Patel", "Singh", "Murphy", "Figueroa", "Alvarez", "Owens", "Diaz",
    "Carter", "Nguyen", "Howard", "Russell", "Price", "Ward", "Jensen", "Ibarra", "Bishop", "Fox"
]
REGIONS = [
    "north_america", "south_america", "europe", "africa", "asia", "oceania", "middle_east"
]
OBJECT_MEMORY = [
    "red backpack", "ceramic mug", "small telescope", "folding bike", "yellow notebook", "travel camera",
    "ukulele", "desk lamp", "tea kettle", "field journal"
]
HUMOR_STYLE = ["dry", "punny", "gentle", "absurd", "observational"]
CONTACT_CHANNELS = ["voice", "text", "video", "group-chat", "async-note"]


@dataclass
class RunningStat:
    count: int = 0
    mean: float = 0.0
    m2: float = 0.0

    def add(self, value: float) -> None:
        self.count += 1
        delta = value - self.mean
        self.mean += delta / self.count
        delta2 = value - self.mean
        self.m2 += delta * delta2

    def variance(self) -> float:
        if self.count < 2:
            return 0.0
        return self.m2 / (self.count - 1)

    def stddev(self) -> float:
        return math.sqrt(self.variance())


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, round(value, 6)))


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_json(path: Path, payload: dict) -> None:
    ensure_dir(path.parent)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def write_markdown(path: Path, lines: list[str]) -> None:
    ensure_dir(path.parent)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def strip_html_to_text(text: str) -> str:
    without_scripts = re.sub(r"<script.*?</script>", " ", text, flags=re.IGNORECASE | re.DOTALL)
    without_styles = re.sub(r"<style.*?</style>", " ", without_scripts, flags=re.IGNORECASE | re.DOTALL)
    without_tags = re.sub(r"<[^>]+>", " ", without_styles)
    normalized = re.sub(r"\s+", " ", html.unescape(without_tags)).strip()
    return normalized


def fetch_live_grounding_probe(url: str, topic: str, domain_label: str, resource_case_id: str, timeout_seconds: float, max_chars: int) -> dict:
    request = Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
        },
    )
    started = time.time()
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            status_code = getattr(response, "status", 200)
            charset = response.headers.get_content_charset("utf-8")
            body = response.read(max_chars).decode(charset, errors="replace")
    except HTTPError as exc:
        return {
            "url": url,
            "ok": False,
            "status_code": exc.code,
            "duration_ms": round((time.time() - started) * 1000.0, 3),
            "error": f"http_error:{exc.code}",
            "relevance_score": 0.0,
            "grounding_score": 0.0,
        }
    except URLError as exc:
        return {
            "url": url,
            "ok": False,
            "status_code": None,
            "duration_ms": round((time.time() - started) * 1000.0, 3),
            "error": f"url_error:{exc.reason}",
            "relevance_score": 0.0,
            "grounding_score": 0.0,
        }
    except TimeoutError:
        return {
            "url": url,
            "ok": False,
            "status_code": None,
            "duration_ms": round((time.time() - started) * 1000.0, 3),
            "error": "timeout_error",
            "relevance_score": 0.0,
            "grounding_score": 0.0,
        }
    except socket.timeout:
        return {
            "url": url,
            "ok": False,
            "status_code": None,
            "duration_ms": round((time.time() - started) * 1000.0, 3),
            "error": "socket_timeout",
            "relevance_score": 0.0,
            "grounding_score": 0.0,
        }

    text = strip_html_to_text(body)
    lowered = text.lower()
    search_terms = [topic.lower(), domain_label.lower(), resource_case_id.replace("_", " ").lower()]
    hits = sum(1 for term in search_terms if term and term in lowered)
    relevance_score = clamp01(0.32 + hits * 0.23 + (0.08 if len(text) >= 120 else 0.0))
    grounding_score = clamp01(0.58 + relevance_score * 0.42)
    return {
        "url": url,
        "ok": True,
        "status_code": status_code,
        "duration_ms": round((time.time() - started) * 1000.0, 3),
        "error": None,
        "excerpt": text[:220],
        "relevance_score": relevance_score,
        "grounding_score": grounding_score,
    }


def probe_candidate_with_fallback(candidate: dict, timeout_seconds: float, max_chars: int) -> dict:
    attempted_urls = []
    for url in candidate.get("resource_options", [])[:3]:
        attempted_urls.append(url)
        probe = fetch_live_grounding_probe(
            url,
            candidate["topic"],
            candidate["domain_label"],
            candidate["resource_case_id"],
            timeout_seconds,
            max_chars,
        )
        if probe["ok"]:
            probe["attempted_urls"] = attempted_urls
            return probe

    probe["attempted_urls"] = attempted_urls
    return probe


def build_live_fetch_probe_summary(candidates: list[dict], max_samples: int, timeout_seconds: float, max_chars: int, rng: random.Random) -> dict:
    if max_samples <= 0 or not candidates:
        return {
            "enabled": True,
            "attempted": 0,
            "success_count": 0,
            "success_rate": None,
            "average_grounding_score": None,
            "average_relevance_score": None,
            "samples": [],
        }

    sampled = candidates[:] if len(candidates) <= max_samples else rng.sample(candidates, max_samples)
    samples = []
    success_count = 0
    total_grounding = 0.0
    total_relevance = 0.0
    for item in sampled:
        probe = probe_candidate_with_fallback(item, timeout_seconds, max_chars)
        sample = {
            "conversation_id": item["conversation_id"],
            "domain_id": item["domain_id"],
            "topic": item["topic"],
            "resource_case_id": item["resource_case_id"],
            **probe,
        }
        samples.append(sample)
        if probe["ok"]:
            success_count += 1
        total_grounding += probe["grounding_score"]
        total_relevance += probe["relevance_score"]

    attempted = len(samples)
    return {
        "enabled": True,
        "attempted": attempted,
        "success_count": success_count,
        "success_rate": round(success_count / attempted, 6) if attempted else None,
        "average_grounding_score": round(total_grounding / attempted, 6) if attempted else None,
        "average_relevance_score": round(total_relevance / attempted, 6) if attempted else None,
        "samples": samples,
    }


def resolve_checkpoint_interval(conversation_count: int, requested_interval: int) -> int:
    if requested_interval > 0:
        return requested_interval
    if conversation_count >= 20_000_000:
        return 250_000
    if conversation_count >= 5_000_000:
        return 100_000
    return 50_000


def build_catalog_lookup(items: list[dict]) -> dict[str, dict]:
    return {item["id"]: item for item in items}


def build_humans(count: int, domains: list[dict], social_styles: list[dict], memory_traits: list[dict], rng: random.Random) -> list[dict]:
    domain_ids = [item["id"] for item in domains]
    humans = []
    for index in range(count):
        first = FIRST_NAMES[index % len(FIRST_NAMES)]
        last = LAST_NAMES[(index * 3 + index // len(FIRST_NAMES)) % len(LAST_NAMES)]
        primary = domain_ids[(index * 5) % len(domain_ids)]
        secondary = domain_ids[(index * 7 + 3) % len(domain_ids)]
        style = social_styles[(index * 11) % len(social_styles)]
        memory_trait = memory_traits[(index * 13 + 5) % len(memory_traits)]
        humans.append(
            {
                "id": f"human-{index + 1:05d}",
                "name": f"{first} {last}",
                "display_handle": f"{first.lower()}-{last.lower()}-{index + 1:05d}",
                "region": REGIONS[index % len(REGIONS)],
                "primary_domain": primary,
                "secondary_domain": secondary,
                "favorite_object": OBJECT_MEMORY[index % len(OBJECT_MEMORY)],
                "humor_style": HUMOR_STYLE[index % len(HUMOR_STYLE)],
                "social_style": style["id"],
                "memory_trait": memory_trait["id"],
                "memory_focus": memory_trait["favorite_memory_kinds"][index % len(memory_trait["favorite_memory_kinds"])],
                "contact_channel": CONTACT_CHANNELS[index % len(CONTACT_CHANNELS)],
                "first_seen": 0,
            }
        )
    rng.shuffle(humans)
    return humans


def pick_human(humans: list[dict], rng: random.Random) -> tuple[int, dict]:
    hot_cutoff = max(200, len(humans) // 10)
    if rng.random() < 0.68:
        index = rng.randrange(0, hot_cutoff)
    else:
        index = rng.randrange(0, len(humans))
    return index, humans[index]


def pick_domain(domain_catalog: list[dict], human: dict, rng: random.Random) -> dict:
    if rng.random() < 0.42:
        preferred = human["primary_domain"] if rng.random() < 0.72 else human["secondary_domain"]
        for item in domain_catalog:
            if item["id"] == preferred:
                return item
    return domain_catalog[rng.randrange(0, len(domain_catalog))]


def pick_value_from_lookup(catalog_lookup: dict[str, dict], preferred_ids: list[str], rng: random.Random) -> dict:
    valid = [catalog_lookup[item_id] for item_id in preferred_ids if item_id in catalog_lookup]
    if not valid:
        values = list(catalog_lookup.values())
        return values[rng.randrange(0, len(values))]
    return valid[rng.randrange(0, len(valid))]


def pick_resource_case(resource_cases: list[dict], domain: dict, rng: random.Random) -> dict:
    eligible = [item for item in resource_cases if domain["id"] in item["domains"]]
    if not eligible:
        return {"id": "none_needed", "label": "None Needed", "weight": 0.1, "resource_bonus": 0.0, "resource_penalty": 0.0}
    total_weight = sum(float(item.get("weight", 0.0)) for item in eligible)
    threshold = rng.random() * total_weight
    cumulative = 0.0
    for item in eligible:
        cumulative += float(item.get("weight", 0.0))
        if cumulative >= threshold:
            return item
    return eligible[-1]


def generate_sample_text(human: dict, domain: dict, topic: str, requires_resource: bool, memory_reference: bool, ambiguity_pattern: dict, resource_case: dict, resource_source: str | None) -> dict:
    opener = f"{human['name']} asks about {topic} in {domain['label'].lower()} over {human['contact_channel']}."
    memory = (
        f" TOD recalls the {human['favorite_object']}, {human['humor_style']} humor preference, and {human['memory_focus']}."
        if memory_reference else ""
    )
    resource = f" External grounding is helpful via {resource_source} for {resource_case['label'].lower()}." if requires_resource and resource_source else ""
    ambiguity = f" Ambiguity pattern: {ambiguity_pattern['label'].lower()}." if ambiguity_pattern["id"] != "none" else ""
    return {
        "user_prompt": opener,
        "tod_response_shape": f"recognize human; adapt to {human['social_style']}; answer about {topic};{resource}{memory}{ambiguity}".strip(),
    }


def simulate_conversation(
    conversation_id: int,
    humans: list[dict],
    domain_catalog: list[dict],
    resource_catalog: dict,
    social_style_lookup: dict[str, dict],
    memory_trait_lookup: dict[str, dict],
    ambiguity_lookup: dict[str, dict],
    resource_cases: list[dict],
    domain_experience: Counter,
    human_experience: list[int],
    recognition_hits: list[int],
    memory_hits: list[int],
    resource_hits: Counter,
    style_counter: Counter,
    ambiguity_counter: Counter,
    memory_trait_counter: Counter,
    resource_case_counter: Counter,
    rng: random.Random,
) -> dict:
    human_index, human = pick_human(humans, rng)
    domain = pick_domain(domain_catalog, human, rng)
    topic = domain["topics"][rng.randrange(0, len(domain["topics"]))]
    social_style = social_style_lookup[human["social_style"]]
    memory_trait = memory_trait_lookup[human["memory_trait"]]
    ambiguity_pattern = pick_value_from_lookup(ambiguity_lookup, domain.get("ambiguity_patterns", []), rng) if rng.random() < 0.52 else {"id": "none", "label": "None", "severity": 0.0, "recognition_penalty": 0.0, "memory_penalty": 0.0, "resource_penalty": 0.0, "coherence_penalty": 0.0}
    resource_case = pick_resource_case(resource_cases, domain, rng)
    previous_human_experience = human_experience[human_index]
    previous_domain_experience = domain_experience[domain["id"]]

    recurring_human = previous_human_experience > 0
    memory_reference = recurring_human and rng.random() < (0.34 + min(previous_human_experience, 12) * 0.02 + memory_trait["memory_bias"] * 0.18)
    base_resource_need = 0.18 + (0.22 if domain["resource_helpful"] else 0.0) + float(resource_case.get("weight", 0.0)) * 0.22
    requires_resource = rng.random() < min(base_resource_need, 0.93) and resource_case["id"] != "none_needed"
    resource_options = resource_catalog.get(domain["id"], [])
    resource_source = resource_options[rng.randrange(0, len(resource_options))] if requires_resource and resource_options else None

    human_familiarity_bonus = min(previous_human_experience, 30) * 0.0085
    domain_experience_bonus = math.log1p(previous_domain_experience) * 0.029
    resource_experience_bonus = math.log1p(resource_hits[domain["id"]]) * 0.034
    memory_bonus = 0.03 if memory_reference else 0.0
    noise_penalty = rng.random() * 0.11 + float(ambiguity_pattern.get("severity", 0.0)) * 0.04
    style_recognition_bonus = social_style["recognition_bias"]
    style_memory_bonus = social_style["memory_bias"] + memory_trait["memory_bias"]
    style_resource_bonus = social_style["resource_bias"]
    ambiguity_recognition_penalty = float(ambiguity_pattern.get("recognition_penalty", 0.0))
    ambiguity_memory_penalty = float(ambiguity_pattern.get("memory_penalty", 0.0))
    ambiguity_resource_penalty = float(ambiguity_pattern.get("resource_penalty", 0.0))
    ambiguity_coherence_penalty = float(ambiguity_pattern.get("coherence_penalty", 0.0))
    resource_case_bonus = float(resource_case.get("resource_bonus", 0.0)) if requires_resource and resource_source else 0.0
    resource_case_penalty = float(resource_case.get("resource_penalty", 0.0)) if requires_resource and not resource_source else 0.0

    recognition_score = clamp01(
        0.58
        + domain["recognition_weight"] * 0.2
        + human_familiarity_bonus
        + (0.018 if recurring_human else 0.0)
        + style_recognition_bonus
        - ambiguity_recognition_penalty
        - noise_penalty * 0.36
    )
    memory_score = clamp01(
        0.52
        + domain["memory_weight"] * 0.22
        + human_familiarity_bonus
        + memory_bonus
        + style_memory_bonus
        - ambiguity_memory_penalty
        - noise_penalty * 0.5
    )
    resource_score = clamp01(
        0.48
        + domain["resource_weight"] * 0.26
        + (resource_experience_bonus if requires_resource else 0.07)
        + (0.04 if requires_resource and domain["id"] in resource_catalog else 0.0)
        + style_resource_bonus
        + resource_case_bonus
        - ambiguity_resource_penalty
        - resource_case_penalty
        - noise_penalty * 0.45
    )
    coherence_score = clamp01(0.61 + domain_experience_bonus + human_familiarity_bonus * 0.6 - ambiguity_coherence_penalty - noise_penalty * 0.52)
    warmth_score = clamp01(0.63 + human_familiarity_bonus * 0.7 + social_style["memory_bias"] * 0.35 + (0.04 if domain["id"] in {human['primary_domain'], human['secondary_domain']} else 0.0) - noise_penalty * 0.32)
    overall_score = clamp01((recognition_score + memory_score + resource_score + coherence_score + warmth_score) / 5.0)

    human_experience[human_index] += 1
    domain_experience[domain["id"]] += 1
    style_counter[social_style["id"]] += 1
    memory_trait_counter[memory_trait["id"]] += 1
    ambiguity_counter[ambiguity_pattern["id"]] += 1
    resource_case_counter[resource_case["id"]] += 1
    if recognition_score >= 0.67:
        recognition_hits[human_index] += 1
    if memory_reference and memory_score >= 0.68:
        memory_hits[human_index] += 1
    if requires_resource and resource_score >= 0.68:
        resource_hits[domain["id"]] += 1

    sample = generate_sample_text(human, domain, topic, requires_resource, memory_reference, ambiguity_pattern, resource_case, resource_source)

    return {
        "conversation_id": conversation_id,
        "human_id": human["id"],
        "human_name": human["name"],
        "domain_id": domain["id"],
        "domain_label": domain["label"],
        "topic": topic,
        "recognition_score": recognition_score,
        "memory_score": memory_score,
        "resource_score": resource_score,
        "coherence_score": coherence_score,
        "warmth_score": warmth_score,
        "overall_score": overall_score,
        "memory_reference": memory_reference,
        "resource_needed": requires_resource,
        "resource_catalog_available": domain["id"] in resource_catalog,
        "resource_case_id": resource_case["id"],
        "ambiguity_pattern_id": ambiguity_pattern["id"],
        "social_style_id": social_style["id"],
        "memory_trait_id": memory_trait["id"],
        "resource_source": resource_source,
        "sample": sample,
    }


def build_checkpoint(
    checkpoint_index: int,
    processed: int,
    interval_processed: int,
    interval_stat: RunningStat,
    overall_stat: RunningStat,
    interval_acc: dict,
    overall_acc: dict,
    domain_counter: Counter,
    style_counter: Counter,
    ambiguity_counter: Counter,
    memory_trait_counter: Counter,
    resource_case_counter: Counter,
    initial_baseline: dict | None,
    previous_checkpoint: dict | None,
    thresholds: dict,
    recent_samples: list[dict],
    warmup_checkpoint_count: int,
    live_fetch_summary: dict | None,
) -> dict:
    overall_average = overall_stat.mean
    interval_average = interval_stat.mean
    consistency_score = clamp01(1.0 - min(interval_stat.stddev() / 0.28, 1.0))
    memory_average = overall_acc["memory_total"] / processed
    recognition_average = overall_acc["recognition_total"] / processed
    resource_average = overall_acc["resource_total"] / processed
    resource_needed_rate = overall_acc["resource_needed_count"] / processed
    learning_delta = 0.0 if initial_baseline is None else overall_average - initial_baseline["overall_average"]
    memory_delta = 0.0 if initial_baseline is None else memory_average - initial_baseline["memory_average"]
    recognition_delta = 0.0 if initial_baseline is None else recognition_average - initial_baseline["recognition_average"]
    resource_delta = 0.0 if initial_baseline is None else resource_average - initial_baseline["resource_average"]
    interval_drift = 0.0 if previous_checkpoint is None else interval_average - previous_checkpoint["interval_average"]

    reasons = []
    if overall_average < thresholds["min_overall_score"]:
        reasons.append("overall_below_threshold")
    if memory_average < thresholds["min_memory_score"]:
        reasons.append("memory_below_threshold")
    if recognition_average < thresholds["min_recognition_score"]:
        reasons.append("recognition_below_threshold")
    if resource_average < thresholds["min_resource_score"]:
        reasons.append("resource_below_threshold")
    if consistency_score < thresholds["min_consistency_score"]:
        reasons.append("consistency_below_threshold")
    if previous_checkpoint is not None and learning_delta < thresholds["min_learning_delta"]:
        reasons.append("learning_enforcement_not_improving")
    if live_fetch_summary and live_fetch_summary.get("attempted", 0) > 0:
        success_rate = live_fetch_summary.get("success_rate")
        grounding_score = live_fetch_summary.get("average_grounding_score")
        if success_rate is not None and success_rate < thresholds["min_live_fetch_success_rate"]:
            reasons.append("live_fetch_success_below_threshold")
        if grounding_score is not None and grounding_score < thresholds["min_live_grounding_score"]:
            reasons.append("live_grounding_below_threshold")

    in_warmup = checkpoint_index <= warmup_checkpoint_count
    if in_warmup:
        reasons = []

    top_domains = [
        {"domain_id": domain_id, "count": count}
        for domain_id, count in domain_counter.most_common(8)
    ]
    top_styles = [{"social_style_id": style_id, "count": count} for style_id, count in style_counter.most_common(5)]
    top_ambiguities = [{"ambiguity_pattern_id": ambiguity_id, "count": count} for ambiguity_id, count in ambiguity_counter.most_common(5)]
    top_memory_traits = [{"memory_trait_id": trait_id, "count": count} for trait_id, count in memory_trait_counter.most_common(5)]
    top_resource_cases = [{"resource_case_id": case_id, "count": count} for case_id, count in resource_case_counter.most_common(5)]

    return {
        "checkpoint_index": checkpoint_index,
        "processed_conversations": processed,
        "interval_conversations": interval_processed,
        "overall_average": round(overall_average, 6),
        "interval_average": round(interval_average, 6),
        "consistency_score": round(consistency_score, 6),
        "memory_average": round(memory_average, 6),
        "recognition_average": round(recognition_average, 6),
        "resource_average": round(resource_average, 6),
        "resource_needed_rate": round(resource_needed_rate, 6),
        "learning_delta": round(learning_delta, 6),
        "memory_delta": round(memory_delta, 6),
        "recognition_delta": round(recognition_delta, 6),
        "resource_delta": round(resource_delta, 6),
        "interval_drift": round(interval_drift, 6),
        "top_domains": top_domains,
        "top_social_styles": top_styles,
        "top_ambiguity_patterns": top_ambiguities,
        "top_memory_traits": top_memory_traits,
        "top_resource_cases": top_resource_cases,
        "recent_samples": recent_samples[-5:],
        "live_fetch": live_fetch_summary,
        "warmup_phase": in_warmup,
        "pass": len(reasons) == 0,
        "reasons": reasons,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run large-scale TOD social conversation simulation.")
    parser.add_argument("--conversation-count", type=int, default=1_000_000)
    parser.add_argument("--checkpoint-interval", type=int, default=0)
    parser.add_argument("--human-count", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=86013)
    parser.add_argument("--domain-catalog", default="tod/conversation_eval/social_domain_catalog.json")
    parser.add_argument("--output-root", default="shared_state/conversation_eval/social-million")
    parser.add_argument("--include-domains", nargs="*", default=[])
    parser.add_argument("--min-overall-score", type=float, default=0.74)
    parser.add_argument("--min-memory-score", type=float, default=0.73)
    parser.add_argument("--min-recognition-score", type=float, default=0.72)
    parser.add_argument("--min-resource-score", type=float, default=0.71)
    parser.add_argument("--min-consistency-score", type=float, default=0.69)
    parser.add_argument("--min-learning-delta", type=float, default=0.015)
    parser.add_argument("--enable-live-fetch", action="store_true")
    parser.add_argument("--live-fetch-samples-per-checkpoint", type=int, default=3)
    parser.add_argument("--live-fetch-timeout-seconds", type=float, default=6.0)
    parser.add_argument("--live-fetch-max-chars", type=int, default=20000)
    parser.add_argument("--min-live-fetch-success-rate", type=float, default=0.66)
    parser.add_argument("--min-live-grounding-score", type=float, default=0.68)
    parser.add_argument("--warmup-checkpoints", type=int, default=2)
    parser.add_argument("--fail-on-threshold", action="store_true")
    parser.add_argument("--emit-json", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    catalog_path = Path(args.domain_catalog)
    if not catalog_path.is_absolute():
        catalog_path = repo_root / catalog_path
    output_root = Path(args.output_root)
    if not output_root.is_absolute():
        output_root = repo_root / output_root

    if args.conversation_count <= 0:
        raise ValueError("conversation-count must be > 0")
    if args.human_count <= 0:
        raise ValueError("human-count must be > 0")
    if args.warmup_checkpoints < 0:
        raise ValueError("warmup-checkpoints must be >= 0")
    if args.live_fetch_samples_per_checkpoint < 0:
        raise ValueError("live-fetch-samples-per-checkpoint must be >= 0")
    if args.live_fetch_timeout_seconds <= 0:
        raise ValueError("live-fetch-timeout-seconds must be > 0")
    if args.live_fetch_max_chars <= 0:
        raise ValueError("live-fetch-max-chars must be > 0")

    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    domains = catalog["domains"]
    resource_catalog = catalog.get("resource_catalog", {})
    social_styles = catalog.get("social_styles", [])
    memory_traits = catalog.get("memory_traits", [])
    ambiguity_patterns = catalog.get("ambiguity_patterns", [])
    resource_cases = catalog.get("resource_decision_cases", [])
    if not social_styles or not memory_traits or not ambiguity_patterns or not resource_cases:
        raise ValueError("Catalog must include social_styles, memory_traits, ambiguity_patterns, and resource_decision_cases")

    if args.include_domains:
        requested_domains = {item.strip() for item in args.include_domains if item.strip()}
        domains = [item for item in domains if item["id"] in requested_domains]
        if not domains:
            raise ValueError("No domains remain after applying include-domains filter")
        resource_catalog = {key: value for key, value in resource_catalog.items() if key in requested_domains}

    resolved_checkpoint_interval = resolve_checkpoint_interval(args.conversation_count, args.checkpoint_interval)

    run_id = "tod-social-sim-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    run_root = output_root / run_id
    ensure_dir(run_root)
    ensure_dir(run_root / "checkpoints")

    rng = random.Random(args.seed)
    humans = build_humans(args.human_count, domains, social_styles, memory_traits, rng)
    social_style_lookup = build_catalog_lookup(social_styles)
    memory_trait_lookup = build_catalog_lookup(memory_traits)
    ambiguity_lookup = build_catalog_lookup(ambiguity_patterns)
    human_experience = [0 for _ in range(args.human_count)]
    recognition_hits = [0 for _ in range(args.human_count)]
    memory_hits = [0 for _ in range(args.human_count)]
    domain_experience: Counter = Counter()
    resource_hits: Counter = Counter()
    domain_counter: Counter = Counter()
    style_counter: Counter = Counter()
    ambiguity_counter: Counter = Counter()
    memory_trait_counter: Counter = Counter()
    resource_case_counter: Counter = Counter()

    overall_stat = RunningStat()
    interval_stat = RunningStat()
    overall_acc = defaultdict(float)
    interval_acc = defaultdict(float)
    checkpoints = []
    recent_samples: list[dict] = []
    resource_needed_candidates: list[dict] = []
    initial_baseline = None
    previous_checkpoint = None
    live_fetch_overall = {
        "attempted": 0,
        "success_count": 0,
        "grounding_total": 0.0,
        "relevance_total": 0.0,
        "checkpoint_probe_count": 0,
    }

    thresholds = {
        "min_overall_score": args.min_overall_score,
        "min_memory_score": args.min_memory_score,
        "min_recognition_score": args.min_recognition_score,
        "min_resource_score": args.min_resource_score,
        "min_consistency_score": args.min_consistency_score,
        "min_learning_delta": args.min_learning_delta,
        "min_live_fetch_success_rate": args.min_live_fetch_success_rate,
        "min_live_grounding_score": args.min_live_grounding_score,
    }

    start_time = time.time()
    for conversation_id in range(1, args.conversation_count + 1):
        result = simulate_conversation(
            conversation_id,
            humans,
            domains,
            resource_catalog,
            social_style_lookup,
            memory_trait_lookup,
            ambiguity_lookup,
            resource_cases,
            domain_experience,
            human_experience,
            recognition_hits,
            memory_hits,
            resource_hits,
            style_counter,
            ambiguity_counter,
            memory_trait_counter,
            resource_case_counter,
            rng,
        )
        domain_counter[result["domain_id"]] += 1
        overall_stat.add(result["overall_score"])
        interval_stat.add(result["overall_score"])

        overall_acc["memory_total"] += result["memory_score"]
        overall_acc["recognition_total"] += result["recognition_score"]
        overall_acc["resource_total"] += result["resource_score"]
        overall_acc["resource_needed_count"] += 1 if result["resource_needed"] else 0

        interval_acc["memory_total"] += result["memory_score"]
        interval_acc["recognition_total"] += result["recognition_score"]
        interval_acc["resource_total"] += result["resource_score"]
        interval_acc["resource_needed_count"] += 1 if result["resource_needed"] else 0

        if len(recent_samples) >= 12:
            recent_samples.pop(0)
        recent_samples.append(
            {
                "conversation_id": result["conversation_id"],
                "human_id": result["human_id"],
                "human_name": result["human_name"],
                "domain_id": result["domain_id"],
                "topic": result["topic"],
                "overall_score": result["overall_score"],
                "memory_reference": result["memory_reference"],
                "resource_needed": result["resource_needed"],
                "resource_case_id": result["resource_case_id"],
                "ambiguity_pattern_id": result["ambiguity_pattern_id"],
                "social_style_id": result["social_style_id"],
                "memory_trait_id": result["memory_trait_id"],
                "sample": result["sample"],
            }
        )
        if result["resource_needed"] and result.get("resource_source"):
            resource_needed_candidates.append(
                {
                    "conversation_id": result["conversation_id"],
                    "domain_id": result["domain_id"],
                    "domain_label": result["domain_label"],
                    "topic": result["topic"],
                    "resource_case_id": result["resource_case_id"],
                    "resource_source": result["resource_source"],
                    "resource_options": resource_catalog.get(result["domain_id"], []),
                }
            )
            if len(resource_needed_candidates) > max(args.live_fetch_samples_per_checkpoint * 8, 24):
                resource_needed_candidates.pop(0)

        if conversation_id % resolved_checkpoint_interval == 0 or conversation_id == args.conversation_count:
            checkpoint_index = len(checkpoints) + 1
            live_fetch_summary = None
            if args.enable_live_fetch and checkpoint_index > args.warmup_checkpoints:
                live_fetch_summary = build_live_fetch_probe_summary(
                    resource_needed_candidates,
                    args.live_fetch_samples_per_checkpoint,
                    args.live_fetch_timeout_seconds,
                    args.live_fetch_max_chars,
                    rng,
                )
                attempted = live_fetch_summary.get("attempted", 0)
                if attempted:
                    live_fetch_overall["attempted"] += attempted
                    live_fetch_overall["success_count"] += live_fetch_summary.get("success_count", 0)
                    live_fetch_overall["grounding_total"] += float(live_fetch_summary.get("average_grounding_score") or 0.0) * attempted
                    live_fetch_overall["relevance_total"] += float(live_fetch_summary.get("average_relevance_score") or 0.0) * attempted
                    live_fetch_overall["checkpoint_probe_count"] += 1
            checkpoint = build_checkpoint(
                checkpoint_index,
                conversation_id,
                interval_stat.count,
                interval_stat,
                overall_stat,
                interval_acc,
                overall_acc,
                domain_counter,
                style_counter,
                ambiguity_counter,
                memory_trait_counter,
                resource_case_counter,
                initial_baseline,
                previous_checkpoint,
                thresholds,
                recent_samples,
                args.warmup_checkpoints,
                live_fetch_summary,
            )
            if initial_baseline is None:
                initial_baseline = {
                    "overall_average": checkpoint["overall_average"],
                    "memory_average": checkpoint["memory_average"],
                    "recognition_average": checkpoint["recognition_average"],
                    "resource_average": checkpoint["resource_average"],
                }
                checkpoint["learning_delta"] = 0.0
                checkpoint["memory_delta"] = 0.0
                checkpoint["recognition_delta"] = 0.0
                checkpoint["resource_delta"] = 0.0
                checkpoint["pass"] = True
                checkpoint["reasons"] = []
            checkpoints.append(checkpoint)
            write_json(run_root / "checkpoints" / f"checkpoint-{checkpoint_index:05d}.json", checkpoint)
            previous_checkpoint = checkpoint
            interval_stat = RunningStat()
            interval_acc = defaultdict(float)
            resource_needed_candidates = []

    duration_seconds = round(time.time() - start_time, 3)
    population_recognition_rate = sum(1 for value in recognition_hits if value > 0) / len(recognition_hits)
    population_memory_rate = sum(1 for value in memory_hits if value > 0) / len(memory_hits)
    population_seen_rate = sum(1 for value in human_experience if value > 0) / len(human_experience)
    final_checkpoint = checkpoints[-1]
    live_fetch_summary_overall = {
        "enabled": args.enable_live_fetch,
        "attempted": live_fetch_overall["attempted"],
        "success_count": live_fetch_overall["success_count"],
        "success_rate": round(live_fetch_overall["success_count"] / live_fetch_overall["attempted"], 6) if live_fetch_overall["attempted"] else None,
        "average_grounding_score": round(live_fetch_overall["grounding_total"] / live_fetch_overall["attempted"], 6) if live_fetch_overall["attempted"] else None,
        "average_relevance_score": round(live_fetch_overall["relevance_total"] / live_fetch_overall["attempted"], 6) if live_fetch_overall["attempted"] else None,
        "checkpoint_probe_count": live_fetch_overall["checkpoint_probe_count"],
    }

    summary = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": "tod-social-conversation-simulation-v1",
        "run_id": run_id,
        "config": {
            "conversation_count": args.conversation_count,
            "checkpoint_interval": resolved_checkpoint_interval,
            "human_count": args.human_count,
            "seed": args.seed,
            "domain_catalog": str(catalog_path),
            "include_domains": args.include_domains,
            "thresholds": thresholds,
            "enable_live_fetch": args.enable_live_fetch,
            "live_fetch_samples_per_checkpoint": args.live_fetch_samples_per_checkpoint,
            "live_fetch_timeout_seconds": args.live_fetch_timeout_seconds,
            "live_fetch_max_chars": args.live_fetch_max_chars,
            "warmup_checkpoints": args.warmup_checkpoints,
        },
        "summary": {
            "processed_conversations": args.conversation_count,
            "checkpoint_count": len(checkpoints),
            "duration_seconds": duration_seconds,
            "overall_average": final_checkpoint["overall_average"],
            "memory_average": final_checkpoint["memory_average"],
            "recognition_average": final_checkpoint["recognition_average"],
            "resource_average": final_checkpoint["resource_average"],
            "consistency_score": final_checkpoint["consistency_score"],
            "learning_delta": final_checkpoint["learning_delta"],
            "population_seen_rate": round(population_seen_rate, 6),
            "population_recognition_rate": round(population_recognition_rate, 6),
            "population_memory_rate": round(population_memory_rate, 6),
            "live_fetch_success_rate": live_fetch_summary_overall["success_rate"],
            "live_grounding_score": live_fetch_summary_overall["average_grounding_score"],
            "pass": all(item["pass"] for item in checkpoints),
        },
        "coverage": {
            "domain_distribution": dict(domain_counter),
            "social_style_distribution": dict(style_counter),
            "ambiguity_distribution": dict(ambiguity_counter),
            "memory_trait_distribution": dict(memory_trait_counter),
            "resource_case_distribution": dict(resource_case_counter),
            "resource_domains_used": {key: value for key, value in resource_hits.items() if value > 0},
        },
        "live_fetch": live_fetch_summary_overall,
        "checkpoints": checkpoints,
        "artifacts": {
            "run_root": str(run_root),
            "report_json": str(run_root / "social-simulation-report.json"),
            "report_markdown": str(run_root / "social-simulation-report.md"),
        },
    }

    write_json(run_root / "social-simulation-report.json", summary)
    write_markdown(
        run_root / "social-simulation-report.md",
        [
            "# TOD Social Conversation Simulation",
            "",
            f"- Run ID: {run_id}",
            f"- Conversations: {args.conversation_count}",
            f"- Checkpoints: {len(checkpoints)}",
            f"- Duration seconds: {duration_seconds}",
            f"- Overall average: {final_checkpoint['overall_average']}",
            f"- Memory average: {final_checkpoint['memory_average']}",
            f"- Recognition average: {final_checkpoint['recognition_average']}",
            f"- Resource average: {final_checkpoint['resource_average']}",
            f"- Consistency score: {final_checkpoint['consistency_score']}",
            f"- Learning delta: {final_checkpoint['learning_delta']}",
            f"- Live fetch success rate: {live_fetch_summary_overall['success_rate']}",
            f"- Live grounding score: {live_fetch_summary_overall['average_grounding_score']}",
            f"- Pass: {summary['summary']['pass']}",
        ],
    )

    if args.emit_json:
        json.dump(summary, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(json.dumps({
            "ok": summary["summary"]["pass"],
            "run_id": run_id,
            "processed_conversations": args.conversation_count,
            "report_json": str(run_root / "social-simulation-report.json"),
            "report_markdown": str(run_root / "social-simulation-report.md"),
        }, indent=2))

    if args.fail_on_threshold and not summary["summary"]["pass"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())