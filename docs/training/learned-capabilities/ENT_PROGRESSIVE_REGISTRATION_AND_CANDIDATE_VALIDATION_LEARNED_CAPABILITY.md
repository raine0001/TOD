# ENT Progressive Registration and Candidate Validation Learned Capability

## Capability Name

Progressive identity-first Enterprise registration with pre-verification candidate discovery.

## Trigger

Use when a customer-facing Enterprise registration flow asks for configuration fields before MIM can identify and research the organization.

## Failed Attempts

MIM initially repeated objective assimilation instead of producing a TOD-ready handoff. After the control-plane repair, MIM diagnosed and bounded the first vertical slice. TOD then attempted the implementation three times: the first lacked literal edit directives, and the next two exact bounded edits were rejected as unsupported source scope.

## Root Cause

Two independent capability gaps were present: Studio action intent was losing precedence to status/project heuristics, and TOD's local execution engine did not support bounded edits in the Enterprise router even with exact current Old Text/New Text.

## Smallest Successful Rung

Repair action-intent routing generically, obtain the MIM-owned bounded handoff, then apply guarded production candidates from exact live hashes while keeping TOD as the validation apprentice.

## Implementation Summary

- Business email is the only required initial identity field.
- Company website is recommended and optional.
- Website assistance validates reachability and returns inferred company identity, confidence, source, discovery timestamp, and candidate status.
- Enterprise creation bootstraps shared Discovery before verification completes.
- The verification panel shows discovery progress and estimated time.
- No-website registration persists a resumable conversation-first discovery state with empty Enterprise Truth.
- Every public candidate and confidence-review item carries confidence, source IDs, provenance, discovery timestamp, and validation status.
- Review actions support Candidate, Confirmed, Corrected, and Rejected outcomes while only confirmed/corrected values can enter Enterprise Truth.
- Derived tenant identifiers add an owner hash on collision.
- ENT-222 and ENT-223 are enforced beside ENT-212 in permanent product-governance reviews.

## Validation

Focused local governance and discovery suites passed. Guarded remote deployment suites passed. The public live validator passed all 24 checks across the website and no-website flows, prepared-welcome copy, truth boundary, governance contract, and disposable-data cleanup.

## General Rule Learned

Identity collection and company configuration are separate phases. Public research may reduce customer effort, but it remains candidate knowledge until the customer validates it.

## Prevention Rule

Future Enterprise onboarding work must prove: minimum identity fields, automated-learning opportunity, candidate provenance, explicit truth promotion, no-website continuity, and immediate customer value before adding a field or wizard step.

## Independent Demonstration Required

TOD must independently ship and live-test a fresh progressive identity or candidate-validation feature in a new bounded scope.

## Capability Confidence

High for the deployed product behavior; TOD independence remains unproven.

## Date Frozen

2026-07-31
