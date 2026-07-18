from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import zipfile
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from xml.etree import ElementTree


TEXT_EXTENSIONS = {".txt", ".md", ".csv", ".tsv", ".json", ".xml", ".htm", ".html", ".url", ".css", ".js", ".sh"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".webp"}
OFFICE_XML_EXTENSIONS = {".docx", ".xlsx"}
SPECIALIZED_EXTENSIONS = {".pdf", ".dwg", ".dxf", ".stl", ".skp", ".skb", ".vi", ".bak", ".db", ".doc", ".xls"}

TOPIC_RULES = {
    "engineering": ("engineering", "drawing", "drawings", "dwg", "cad", "spec", "specification", "stl", "blade", "motor"),
    "manufacturing": ("manufacturing", "manufacture", "assembly", "tooling", "fixture", "production", "mold"),
    "certification": ("certification", "certified", "cec", "met lab", "iec", "standard", "eligible", "testing"),
    "installation": ("install", "installation", "mount", "roof", "training", "tiletrac", "rooftrac"),
    "performance": ("performance", "power curve", "wind speed", "output", "testing", "data", "metering"),
    "business": ("cost", "grant", "marketing", "business", "price", "customer", "sales", "market"),
    "support": ("support", "manual", "service", "warranty", "troubleshoot", "training"),
    "solar_integration": ("solar", "hybrid", "controller", "inverter", "xantrex", "photovoltaic"),
}


def utc_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def compact(text: object, limit: int = 1200) -> str:
    value = " ".join(str(text or "").replace("\x00", " ").split())
    if len(value) <= limit:
        return value
    return value[: limit - 3].rstrip() + "..."


def doc_id(relative_path: str, artifact_name: str) -> str:
    return hashlib.sha256(f"{artifact_name}\n{relative_path}".encode("utf-8", errors="ignore")).hexdigest()[:16]


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def records_from_payload(payload: object) -> list[dict[str, Any]]:
    if not isinstance(payload, dict):
        return []
    records: list[dict[str, Any]] = []
    for key in ("files", "recent_files"):
        value = payload.get(key)
        if isinstance(value, list):
            records.extend(item for item in value if isinstance(item, dict))
    primary = payload.get("primary_working_context")
    if isinstance(primary, dict):
        for key in ("arm_component_candidates", "recent_files"):
            value = primary.get(key)
            if isinstance(value, list):
                records.extend(item for item in value if isinstance(item, dict))
    return records


def extract_text_file(path: Path, max_bytes: int) -> str:
    data = path.read_bytes()[:max_bytes]
    for encoding in ("utf-8", "utf-16", "cp1252", "latin-1"):
        try:
            text = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        text = data.decode("utf-8", errors="replace")
    if path.suffix.lower() in {".htm", ".html"}:
        text = re.sub(r"<script\b[^>]*>.*?</script>", " ", text, flags=re.IGNORECASE | re.DOTALL)
        text = re.sub(r"<style\b[^>]*>.*?</style>", " ", text, flags=re.IGNORECASE | re.DOTALL)
        text = re.sub(r"<[^>]+>", " ", text)
        text = html.unescape(text)
    return compact(text, max_bytes)


def extract_docx(path: Path, max_chars: int) -> str:
    with zipfile.ZipFile(path) as archive:
        try:
            xml_bytes = archive.read("word/document.xml")
        except KeyError:
            return ""
    root = ElementTree.fromstring(xml_bytes)
    texts = [node.text or "" for node in root.iter() if node.tag.endswith("}t") and node.text]
    return compact(" ".join(texts), max_chars)


def extract_xlsx(path: Path, max_chars: int) -> str:
    texts: list[str] = []
    with zipfile.ZipFile(path) as archive:
        try:
            shared = archive.read("xl/sharedStrings.xml")
        except KeyError:
            shared = b""
        if shared:
            root = ElementTree.fromstring(shared)
            texts.extend(node.text or "" for node in root.iter() if node.tag.endswith("}t") and node.text)
        sheet_names = [name for name in archive.namelist() if name.startswith("xl/worksheets/sheet") and name.endswith(".xml")]
        for sheet_name in sheet_names[:3]:
            root = ElementTree.fromstring(archive.read(sheet_name))
            for node in root.iter():
                if node.tag.endswith("}v") and node.text:
                    texts.append(node.text)
                if len(" ".join(texts)) > max_chars:
                    break
    return compact(" ".join(texts), max_chars)


def image_metadata(path: Path) -> str:
    try:
        from PIL import Image

        with Image.open(path) as image:
            return f"image {image.format or path.suffix.lower()} {image.width}x{image.height} mode {image.mode}"
    except Exception as exc:  # pragma: no cover - depends on image plugins and source files
        return f"image metadata unavailable: {type(exc).__name__}"


def extract_available_text(path: Path, *, max_bytes: int, max_chars: int) -> tuple[str, str, str]:
    suffix = path.suffix.lower()
    if suffix in TEXT_EXTENSIONS:
        return ("observed_text", "extractable_text", extract_text_file(path, max_bytes))
    if suffix == ".docx":
        return ("observed_text", "extractable_office_xml", extract_docx(path, max_chars))
    if suffix == ".xlsx":
        if path.stat().st_size > max_bytes * 4:
            return ("queued_specialized_extraction", "large_workbook_skipped", "")
        return ("observed_text", "extractable_office_xml", extract_xlsx(path, max_chars))
    if suffix in IMAGE_EXTENSIONS:
        return ("observed_metadata", "image_metadata", image_metadata(path))
    if suffix in SPECIALIZED_EXTENSIONS:
        return ("queued_specialized_extraction", "specialized_extractor_required", "")
    return ("observed_metadata", "metadata_only", "")


def infer_topics(relative_path: str, extracted: str) -> list[str]:
    haystack = f"{relative_path}\n{extracted}".lower()
    topics = [topic for topic, terms in TOPIC_RULES.items() if any(term in haystack for term in terms)]
    return topics or ["unclassified"]


def observation_confidence(extraction_status: str, extracted_text: str) -> float:
    if extraction_status == "observed_text" and len(extracted_text) > 80:
        return 0.72
    if extraction_status == "observed_text":
        return 0.58
    if extraction_status == "observed_metadata":
        return 0.38
    return 0.22


def evidence_status(extraction_status: str, topics: list[str]) -> str:
    if extraction_status == "observed_text" and topics != ["unclassified"]:
        return "pending_review"
    if extraction_status == "observed_metadata":
        return "metadata_observed"
    return "needs_extraction"


def relationship_opportunities(topics: list[str]) -> list[str]:
    opportunities = []
    if "engineering" in topics and "performance" in topics:
        opportunities.append("engineering decisions -> measured performance")
    if "certification" in topics and "engineering" in topics:
        opportunities.append("certification constraints -> engineering design")
    if "manufacturing" in topics and "business" in topics:
        opportunities.append("manufacturing cost -> business viability")
    if "installation" in topics and "support" in topics:
        opportunities.append("installation process -> field support")
    if "solar_integration" in topics:
        opportunities.append("wind system -> solar/hybrid integration")
    return opportunities


def unknowns_for_document(extraction_status: str, relative_path: str) -> list[str]:
    if extraction_status == "queued_specialized_extraction":
        return [f"Source body still needs a specialized extractor or manual review: {Path(relative_path).name}"]
    if extraction_status == "observed_metadata":
        return [f"Only metadata has been observed for {Path(relative_path).name}; content meaning is still unknown."]
    return []


def assimilate(index_path: Path, *, initiative_id: str, artifact_name: str, max_documents: int, max_bytes: int, max_chars: int) -> dict[str, Any]:
    payload = read_json(index_path)
    records = records_from_payload(payload)
    seen: set[str] = set()
    documents: list[dict[str, Any]] = []
    status_counts: Counter[str] = Counter()
    topic_counts: Counter[str] = Counter()
    evidence_counts: Counter[str] = Counter()
    relationship_counts: Counter[str] = Counter()

    for record in records:
        relative_path = compact(record.get("relative_path") or record.get("name") or record.get("path"), 2000)
        source_path = compact(record.get("path"), 4000)
        if not relative_path or relative_path.lower() in seen:
            continue
        seen.add(relative_path.lower())
        path = Path(source_path)
        suffix = path.suffix.lower()
        extraction_status = "missing_source"
        extraction_method = "source_path_missing_or_unreadable"
        extracted_text = ""
        if source_path and path.exists() and path.is_file():
            try:
                extraction_status, extraction_method, extracted_text = extract_available_text(
                    path,
                    max_bytes=max_bytes,
                    max_chars=max_chars,
                )
            except Exception as exc:
                extraction_status = "extract_failed"
                extraction_method = type(exc).__name__
                extracted_text = ""
        topics = infer_topics(relative_path, extracted_text)
        confidence = observation_confidence(extraction_status, extracted_text)
        status = evidence_status(extraction_status, topics)
        relationships = relationship_opportunities(topics)
        unknowns = unknowns_for_document(extraction_status, relative_path)
        status_counts[extraction_status] += 1
        evidence_counts[status] += 1
        for topic in topics:
            topic_counts[topic] += 1
        for relationship in relationships:
            relationship_counts[relationship] += 1
        documents.append(
            {
                "document_id": doc_id(relative_path, artifact_name),
                "initiative_id": initiative_id,
                "relative_path": relative_path,
                "name": compact(record.get("name") or path.name, 500),
                "extension": suffix or compact(record.get("extension"), 40),
                "size_bytes": int(record.get("size_bytes") or 0),
                "last_write_time_utc": compact(record.get("last_write_time_utc"), 80),
                "extraction_status": extraction_status,
                "extraction_method": extraction_method,
                "evidence_status": status,
                "observation_confidence": confidence,
                "topics": topics,
                "relationship_opportunities": relationships,
                "unknowns": unknowns,
                "extracted_text_preview": compact(extracted_text, max_chars),
            }
        )
        if len(documents) >= max_documents:
            break

    top_topics = dict(topic_counts.most_common(12))
    top_relationships = dict(relationship_counts.most_common(10))
    return {
        "packet_type": "research-document-assimilation-v1",
        "generated_at": utc_now(),
        "initiative_id": initiative_id,
        "source_index": str(index_path),
        "documents_total_in_index": len(records),
        "documents_observed": len(documents),
        "summary": {
            "extraction_status_counts": dict(status_counts),
            "evidence_status_counts": dict(evidence_counts),
            "topic_counts": top_topics,
            "relationship_opportunity_counts": top_relationships,
            "source_boundary": "Extracted previews support observations and review queues. Accepted facts require source review and promotion into evidence.",
        },
        "initiative_update_seed": {
            "current_understanding": "SolAir source material is now partially observed beyond metadata. Text-like files, URLs, Office XML files, and image metadata can seed observations; PDFs, drawings, legacy binary workbooks, and CAD files remain queued for specialized extraction or manual review.",
            "current_observation": "The project contains engineering, certification, performance, installation, business, and hybrid solar/wind integration material that should be reviewed as separate evidence lanes.",
            "current_unknown": "Which source bodies contain authoritative engineering, manufacturing, certification, and field-performance facts remains unresolved until specialized extraction and review complete.",
            "desired_next_observation": "Promote one source family from extracted preview to reviewed evidence, then update relationships and confidence from that source.",
        },
        "documents": documents,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a research document assimilation artifact from a project-library index.")
    parser.add_argument("--index", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--initiative-id", default="solair")
    parser.add_argument("--artifact-name", default="SOLAIR_PROJECT_LIBRARY_INDEX.latest.json")
    parser.add_argument("--max-documents", type=int, default=10_000)
    parser.add_argument("--max-bytes", type=int, default=1_500_000)
    parser.add_argument("--max-chars", type=int, default=4_000)
    args = parser.parse_args()
    result = assimilate(
        args.index,
        initiative_id=args.initiative_id,
        artifact_name=args.artifact_name,
        max_documents=args.max_documents,
        max_bytes=args.max_bytes,
        max_chars=args.max_chars,
    )
    write_json(args.output, result)
    print(json.dumps({"output": str(args.output), "documents_observed": result["documents_observed"], "summary": result["summary"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
