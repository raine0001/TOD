# Codex Result Format v1

Purpose:
Define the structured payload TOD expects from implementation execution before posting results and reviews to MIM.

## Required Fields
```json
{
  "task_id": "string",
  "summary": "string",
  "files_changed": ["string"],
  "tests_run": ["string"],
  "test_results": ["string"],
  "failures": ["string"],
  "recommendations": ["string"],
  "needs_escalation": false
}
```

## Field Notes
- task_id: MIM task ID in remote or hybrid mode.
- summary: concise implementation summary.
- files_changed: repo-relative changed files.
- tests_run: test commands or suites executed.
- test_results: normalized results, e.g. pass/fail with short detail.
- failures: unresolved issues or failing checks.
- recommendations: next steps for TOD decision engine.
- needs_escalation: true when human review is required.

## TOD Mapping
- add-result uses:
  - task_id
  - summary
  - files_changed
  - tests_run
  - test_results
  - failures
  - recommendations
- review-task decision guidance:
  - if needs_escalation=true -> decision=escalate
  - else if failures has items -> decision=revise
  - else -> decision=pass

## Validation Rules
- task_id must be present.
- summary must be non-empty.
- files_changed/tests_run/test_results/failures/recommendations should be arrays (empty allowed).
- needs_escalation must be boolean.
