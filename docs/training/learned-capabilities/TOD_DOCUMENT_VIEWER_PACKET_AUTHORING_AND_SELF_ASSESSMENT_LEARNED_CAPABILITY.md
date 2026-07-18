# Learned Capability: TOD Document Viewer Packet Authoring and Self Assessment V1

Capability Name: Document viewer implementation from source anchors, with evidence-only self assessment.

Trigger: A user asks for browser-openable research documents, images, drawings, PDFs, or source files from an Observatory project, and TOD is expected to implement the viewer or mirror workflow.

Reality: The SolAir Observatory had a metadata document browser, but users could not open document bodies from the browser. Source files lived under the approved SolAir workstation root and needed safe mirroring before the public MIM site could display them.

Observation: TOD accepted the document-viewer objective but blocked on bounded edit materialization. A second rung failed because TOD treated multiple candidate files as unresolved. A third rung compiled the target file and reported completion, but did not produce the requested source-anchor packet fields. Codex escalated after TOD attempts and implemented the smallest viewer slice.

Root Cause: TOD can recognize that broad feature work requires bounded edit packets, but it cannot yet reliably transform a broad feature into source-anchored old/new or anchor/snippet directives. TOD also lacks a clean non-code reporting lane for post-task self assessment, causing reflection tasks to be routed through the code executor.

Blocker Class: capability_blocker, packet_authoring_gap, self_assessment_lane_gap.

Decomposition Ladder:
1. Identify whether the request is product implementation, packet authoring, validation only, or self assessment.
2. If implementation, identify exactly one target file and one existing function.
3. Extract an exact current anchor from the existing function.
4. State the missing behavior without inventing function names.
5. Produce the smallest packet shell from the real anchor.
6. Add validation command and expected evidence.
7. Apply only after packet fields are complete and source anchored.
8. Report from evidence only after execution.
9. If the report itself cannot be routed, classify the reporting-lane blocker instead of claiming completion.

Smallest Successful Rung: The product implementation was validated after escalation: `/observatory/investigations/solair/documents?q=drawing` exposes viewer links, `/observatory/investigations/solair/documents/881c6169bfa0523e/viewer` renders a mirrored image, and `/observatory/investigations/solair/documents/881c6169bfa0523e/content` returns `image/jpeg` with length `104999`.

Implementation Summary: Added backend-only source path preservation in `core/research_documents.py`. Added safe mirrored file resolution, document viewer routes, content serving, and mirror-request creation in `core/routers/observatory.py`. The viewer serves only files mirrored under MIM runtime station files and does not expose raw workstation paths in public HTML.

Validation:
- `python -m py_compile tmp_remote_mim\core\routers\observatory.py tmp_remote_mim\core\research_documents.py`
- Local render probe confirmed Open viewer link, viewer route, mirror request action, no raw `F:\` in HTML, and backend-only source path retention.
- Remote py_compile passed on MIM.
- Public document browser returned HTTP 200 with viewer links and no raw `F:\` path leakage.
- Public viewer returned HTTP 200 with `Document Viewer`, mirror request action, and no raw `F:\` path leakage.
- TOD station-file mirror fulfilled a viewer request for `001.jpg`.
- Public content endpoint returned HTTP 200, `image/jpeg`, byte length `104999`.

General Rule Learned: A successful compile is not feature completion. Feature completion requires the expected user-visible behavior, evidence that the route or UI works, and proof that safety boundaries still hold.

Prevention Rule: TOD must not claim completion from validation-only execution when the objective required a behavior change. If the requested output is a report or self assessment, TOD must use an artifact/report lane instead of forcing the work through a code executor.

Reuse Trigger: Reuse this capability when TOD must implement or review document viewers, source-body display, mirror/download controls, PDF/image/browser-open workflows, or any broad UI feature that starts from a real source function.

Dependent Capabilities: exact source-anchor extraction, old/new packet authoring, route-level validation, mirrored-source evidence promotion, non-code self-assessment reporting lane, source-body acceptance workflow.

Capability Confidence: 8/10 for the product viewer slice after escalation. 4/10 for TOD independent implementation because TOD did not author the successful packet or final implementation.

Independent Pass Rate: Not proven. TOD made three attempts and did not independently produce the source-anchor packet or self-assessment report. TOD must pass the drills below before this becomes an independent capability.

Date Frozen: 2026-07-07.

Separate Debt: TOD needs a report-only execution lane for evidence synthesis and post-task self assessment. The current direct-chat execution path can incorrectly demand a target file even when the task is explicitly non-code.

Generalized Principle: Broad features become executable only when translated into bounded source-anchored changes. Reflection and reporting are not code edits and need their own authoritative artifact lane.

## Addendum: Mirror Registry Continuity

Trigger: Users opened multiple Observatory documents and saw the metadata fallback for most of them, even after one document was mirrored successfully.

Reality: `MIM_STATION_FILE_MIRROR.latest.json` is a single latest pointer. It can prove one mirrored file, but it cannot preserve the browser-open state for every previously mirrored file.

Observation: `Stip_DyoCore.docx` opened after mirroring, but a previously mirrored image regressed because the viewer only had a latest pointer. A later no-upload mirror run could also overwrite the local registry entry for an uploaded file with an empty remote path.

Root Cause: The mirror workflow lacked a persistent mirror registry and the viewer only checked the latest manifest.

Blocker Class: infrastructure_blocker plus evidence_persistence_gap.

Smallest Successful Rung: Add `MIM_STATION_FILE_MIRROR_INDEX.latest.json`, make the viewer search the registry and latest pointer, and prevent no-upload local mirror runs from erasing an existing uploaded remote path.

Validation: Live viewer proof passed for `Stip_DyoCore.docx` and `001.jpg` at the same time. The DOCX content endpoint returned `application/vnd.openxmlformats-officedocument.wordprocessingml.document` length `12437`; the JPG content endpoint returned `image/jpeg` length `104999`; neither viewer leaked raw `F:\` paths.

Prevention Rule: Any mirror workflow that supports browser-openable project documents must maintain a durable registry, not only a latest pointer. Local cache-only runs must not downgrade previously uploaded remote evidence.

Separate Debt: Add a TOD-owned batch mirror job for browser-friendly source types. The current SolAir candidate set is 386 files, about 321 MB, covering PDF, image, DOC/DOCX, TXT, and XLS files under 25 MB.

## Addendum: Source Identity and Safe Download Coverage

Trigger: The browser viewer worked for selected mirrored examples, but the broader SolAir library still had metadata-only pages for engineering files, duplicate source files, and motor-spec PDFs whose indexed filenames were mojibake.

Reality: Source files may have three different identities: the actual workstation path, the indexed path stored in project metadata, and the mirrored remote path used by MIM. Those identities can diverge when filenames are encoded incorrectly or when duplicate files share the same content hash.

Observation: The motor-spec PDF `26风力铁心组件-Model.pdf` existed on disk, but the index stored a mojibake variant. Duplicate files with identical hashes also collapsed into one mirror entry, leaving some document rows unable to prove their source even though the bytes had transferred.

Root Cause: The mirror registry deduped by content hash only and did not preserve indexed identity aliases. The mirror utility also treated exact path failure as terminal before trying reversible UTF-8 mojibake repair.

Blocker Class: source_identity_blocker, legacy_encoding_blocker, mirror_registry_alias_gap.

Decomposition Ladder:
1. Prove a normal mirrored document can open.
2. Prove a document fails because the source path is encoded differently from the filesystem name.
3. Repair the source resolver to tolerate reversible UTF-8 mojibake.
4. Preserve indexed path/name in the mirror manifest.
5. Repair viewer matching to accept actual source identity or indexed identity.
6. Repair registry dedupe to preserve per-document aliases instead of collapsing only by content hash.
7. Batch mirror browser-friendly documents.
8. Expand to safe download/open engineering file types while excluding executable/database/temp/script assets.
9. Validate live routes across representative file classes.

Smallest Successful Rung: The repaired motor-spec PDF document id `544ed09c9d249c95` opened live with HTTP 200, `mirrored_source_available`, and `application/pdf` content length `166448`.

Implementation Summary: `Invoke-MIMStationFileMirror.ps1` now resolves reversible mojibake source paths, stores indexed path/name metadata, and preserves mirror registry aliases by source identity. `core/routers/observatory.py` now matches documents to mirrors through actual source path, indexed path, indexed relative path, or indexed name.

Validation:
- Local py_compile passed for `tmp_remote_mim\core\routers\observatory.py` and `tmp_remote_mim\core\research_documents.py`.
- Remote py_compile passed on MIM.
- Remote web workers restarted and were observed running.
- Browser-friendly SolAir candidate coverage: 386 candidates, 0 missing.
- Safe SolAir download/open coverage: 604 candidates, 0 missing after excluding temporary Office lock files and executable/database/temp/script/source-web assets.
- Live HTTP validation passed for PDF, DOCX, JPG, BMP, DWG, SKP, ZIP, XLSX, and MP4 document ids.
- Proof artifact published: `runtime/shared/SOLAIR_DOCUMENT_VIEWER_MIRROR_PROOF.latest.json`.

General Rule Learned: A mirror registry must preserve document identity, not only file content identity. A file can be byte-identical to another file and still be a distinct source document in a research archive.

Prevention Rule: Before declaring a research document viewer complete, validate at least one browser-native document, one image, one spreadsheet or document, one engineering/download file, and one legacy-encoding file if the archive contains non-ASCII filenames.

Reuse Trigger: Apply this capability when source archives contain duplicate files, non-ASCII filenames, generated metadata indexes, CAD files, archives, or any file type that must be opened/downloaded from a public research page.

Dependent Capabilities: source index repair, safe mirror policy, download authorization, evidence promotion, source-body extraction, accepted-evidence review.

Capability Confidence: 9/10 for the SolAir source viewer/mirror path after validation. TOD still needs independent packet authoring practice before this is a fully independent TOD capability.

Date Frozen: 2026-07-07.
