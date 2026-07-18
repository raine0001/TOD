# Learned Capability: Research Document Library Metadata Boundary V1

Capability Name: Research document library metadata boundary and supporting-document browse.

Trigger: A research chat or Observatory page needs to discuss files, drawings, images, specifications, certifications, or other source material that exists in a project archive but whose file bodies have not yet been opened or extracted.

Reality: The SolAir project library has a metadata index with hundreds of files. The index proves file existence, names, paths relative to the archive, extensions, sizes, timestamps, and likely evidence families. It does not prove the contents of any file body.

Observation: MIM correctly refused final claims from metadata-only evidence, but the Observatory lacked a supporting-document browse area and MIM's detail-question classifier missed motor/specification/drawing requests.

Root Cause: The research object had evidence entries that mentioned source artifacts, but it did not yet expose supporting documents as first-class research objects. Chat grounding could see the index, but document interaction and source-body boundaries were not visible enough to the user.

Blocker Class: capability_blocker plus evidence_boundary_gap.

Decomposition Ladder:
1. Confirm metadata index shape and avoid leaking raw workstation paths.
2. Add supporting_documents to the Research Initiative object.
3. Create a reusable research document loader from source artifact metadata.
4. Render a Supporting Documents panel on the investigation page.
5. Render a document browser with search and category filtering.
6. Preserve metadata_only / source_body_not_reviewed status in UI and tests.
7. Expand research chat detail classification for motor, specs, and drawings.
8. Validate local tests, remote tests, live page, live document route, and live chat prompt.

Smallest Successful Rung: A SolAir document-browser route showed motor/drawing metadata without exposing raw `F:\` paths and without claiming source-body review.

Implementation Summary: Added `core/research_documents.py`, connected supporting document metadata to the Observatory research object, added `/observatory/investigations/{id}/documents`, added a Supporting Documents panel to research pages, and updated research chat context to derive source artifacts from the initiative rather than a hardcoded SolAir-only artifact list. Added `scripts/research_document_assimilator.py` so available project material can produce an assimilation artifact with observation status, evidence status, topics, relationship opportunities, and unknowns.

Validation: Local and remote tests passed for research documents, Observatory routes, public research context, and public chat research-session context. Live checks confirmed the SolAir page shows Supporting Documents, the document browser returns observed status results without raw `F:\` path leakage, and MIM answers "show me the motor specs and engineering drawings" with metadata-level source matches, assimilation-pass awareness, and a source-review boundary. The first SolAir assimilation artifact observed 708 indexed records: 132 observed_text, 186 observed_metadata, 385 queued_specialized_extraction, 4 missing_source, and 1 extract_failed.

General Rule Learned: A document index is a library catalog, not document understanding. MIM may use metadata to choose what to inspect, but it may not cite file-body claims until the relevant source is opened, mirrored, extracted, and promoted into accepted evidence.

Prevention Rule: Any research answer that depends on file contents must name whether the evidence is metadata_only, observed_text, observed_metadata, queued_specialized_extraction, source_body_reviewed, extracted_text_reviewed, or accepted_evidence. Metadata-only and observed-preview results must route the user toward Supporting Documents and source review instead of final claims.

Reuse Trigger: Reuse this capability when a user asks MIM to show files, drawings, images, documents, specs, certifications, installation notes, manufacturing records, datasets, or project-library material in any Research Initiative.

Dependent Capabilities: source body mirroring, document download/open controls, per-user visibility policy, extracted-text review, evidence promotion, MIM source citation behavior.

Capability Confidence: 7.5/10 for document browsing, assimilation status, and source-boundary behavior. 4/10 for full source-body display/download workflow because that is not implemented yet.

Independent Pass Rate: Not yet proven for TOD. This slice was implemented by Codex under escalation after repeated MIM/TOD source-boundary and packet-authoring blockers. TOD should repeat the pattern independently on a second research initiative before this becomes a 9/10 capability.

Date Frozen: 2026-07-06.

Separate Debt: Add real source-body open/download/share controls after visibility rules and mirror/extraction status are connected. Add specialized extraction for PDF, CAD, legacy Office binaries, LabVIEW VI, and large workbook formats. Add a TOD-authored simulation where TOD builds the same document-library and assimilation slice from a different research project without Codex authoring.

Generalized Principle: Research systems must distinguish catalog evidence from content evidence. Readers and UI layers should make that boundary visible so uncertainty becomes part of the workflow instead of a hidden failure.
