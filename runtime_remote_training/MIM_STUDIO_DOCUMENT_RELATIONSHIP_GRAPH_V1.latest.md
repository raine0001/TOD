# MIM Studio Document Relationship Graph V1

Generated: 2026-06-02

## Summary

Studio Documents now have a DB-backed relationship graph.

Documents are no longer just library records. They can be attached to meaningful Studio objects such as projects, project signals, tasks, objectives, conversations, status updates, apps, reports, systems, lab resources, and training runs.

## Implemented

- Added document relationship state to `/studio/api/documents/state`.
- Added direct document detail API:
  - `GET /studio/api/documents/{document_id}`
- Added relationship query API:
  - `GET /studio/api/document-links`
  - supports `document_id`, `target_type`, and `target_id` filters.
- Added relationship seeding for existing Studio evidence:
  - training documents -> current MIM/TOD training run
  - training documents -> `/studio/training`
  - Documents Library Project -> Documents Library project
  - Studio project evidence -> implementation report
  - Studio training page evidence -> `/studio/training`
- Updated `/studio/documents` with:
  - relationship count
  - Relationship Graph section
  - recent relationships
  - selected-document relationship panel via `?document_id=...`

## Validation

- `/health` returned OK.
- `/studio/documents` rendered:
  - Relationship Graph
  - Recent Relationships
- `/studio/api/documents/state` returned:
  - 11 documents
  - 18 relationships
  - 7 training-run links
  - 8 page links
  - 2 project links
- `/studio/api/document-links?target_type=training_run&target_id=current_mim_tod_training` returned 7 links.
- `/studio/api/documents/{document_id}` returned document details and relationship links.
- `/studio/documents?document_id=11` rendered the selected document and its relationships.

## Operator Outcome

Documents can now become MIM's reference memory instead of a flat file drawer.

The next step is surfacing related documents from each object page, such as project detail, training runs, objectives, reports, systems, and apps.
