# MIM Studio Training Page V1

Generated: 2026-06-02

## Summary

`/studio/training` is now implemented as the training command surface for MIM and TOD.

The page is designed to answer quickly:

- what MIM is training on
- what TOD is training on
- whether training is producing outcome improvement
- what is blocked or weak
- what the current scorecards say
- which evidence documents support the answer

## Key Behavior

- Adds a top-level MIM Training Summary.
- Shows MIM and TOD training focus, progress, blockers, weaknesses, and next actions.
- Includes the hourly reflection verdict directly on the page.
- Includes MIM and TOD scorecard tables.
- Shows training problems and stale/outcome warnings.
- Links training evidence documents into the Studio Documents library.

## Evidence Documents Registered

- MIM/TOD Training Scoreboard
- MIM/TOD Continuous Training Directive
- MIM/TOD Hourly Reflection
- MIM Durability Smoke V2
- MIM Typo-Tolerant Intent Smoke
- TOD Blocker Resolution Operator Summary

## Validation

- `/health` returned OK.
- `/studio/training` rendered:
  - MIM Training Summary
  - Outcome Reflection
  - MIM Scorecard
  - TOD Scorecard
  - Evidence Documents
- `/studio/api/documents/state` returned 6 training documents.
- Training documents include the scoreboard record.

## Operator Outcome

Dave can now open `/studio/training` and see both training status and outcome truth in one place.

This helps prevent the failure mode where MIM reports "training is going great" while the reflection layer says outcomes are not improving.
