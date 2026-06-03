# MIM Studio Document Library DB-Backed V1

## Implemented

Studio Documents now has DB-backed records for:

- `studio_documents`
- `studio_document_links`

## Purpose

Documents are MIM's library: documents, spreadsheets, notes, media, links, references, artifacts, policies, research, and useful context that may not be a project yet.

## Document Associations

Documents can be associated with:

- apps
- projects
- project signals
- tasks
- objectives
- reports
- status updates
- conversations
- vendors
- people
- systems
- lab / robotics work

## API Surface

- `GET /studio/api/documents/state`
- `POST /studio/api/documents`
- `POST /studio/api/documents/{document_id}/links`

## Policy

MIM should not depend on third-party webpages remaining available.

Preservation states:

- `reference`: keep the link/record only.
- `snapshot_when_important`: preserve if it becomes important to a project, system, training, or maintenance.
- `local_copy_required`: local copy or local artifact should exist.

## Validated

- `GET /studio/api/documents/state` returns DB-backed document rows.
- `/studio/documents` renders DB-backed library state.
- Seed records created for project evidence, Documents Library project reference, and external-reference preservation policy.
- Created real document: `Documents Library Operator Notes`.
- Linked that document to the `Documents Library` project.
- Health endpoint returned OK after deployment.

## Next

- Upload endpoint and local file storage.
- URL fetch/snapshot worker.
- Search/index path for MIM retrieval.
- MIM-created documents: reports, wiki notes, project briefs, status summaries, and evidence packets.
