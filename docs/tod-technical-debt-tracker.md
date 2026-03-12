# TOD Technical Debt Tracker

Track known, non-blocking issues that are intentionally deferred until they impact delivery or reliability.

## Open Items

### TD-2026-03-11-001: Media Pipeline Analyzer False Positive

- Status: deferred-safe
- Recorded: 2026-03-11
- Area: PowerShell static analysis
- File: scripts/Invoke-TODMediaPipeline.ps1
- Symptom: analyzer reports an automatic variable `profile` assignment warning near media profile extraction logic.
- Runtime impact: none observed
- Validation evidence:
  - Media dry-run succeeds for image generation.
  - Media execute succeeds for diagram/dashboard rendering.
  - TOD tests pass after related path/test updates.
- Decision:
  - Do not add suppression yet.
  - Keep current behavior because it is stable and policy-safe.
- Revisit trigger:
  - If this warning blocks CI quality gates, masks real diagnostics, or slows maintenance work.
- Planned follow-up options:
  1. Prefer structural refactor of media config parsing to eliminate warning source.
  2. If still false-positive, apply narrow rule suppression with explicit rationale.

### TD-2026-03-12-001: state.json Lock Contention During Repeated Test Runs

- Status: in-observation
- Recorded: 2026-03-12
- Area: test reliability under burn-in and training-loop repetition
- Files:
  - tests/TOD.Tests.ps1
  - scripts/Invoke-TODQualityGate.ps1
- Symptom:
  - Intermittent test failures mention state.json being used by another process.
- Runtime impact: none to core runtime behavior; affects confidence in repeated automated test runs.
- Mitigation applied:
  - Sandbox test paths changed to per-run GUID names to reduce cross-run collisions.
  - Added quality gate script that classifies failures into transient-lock vs deterministic.
- Current gate status:
  - Deterministic failures: 0 in latest gate run.
  - Transient lock failures: observed intermittently, tolerated up to configured threshold.
- Revisit trigger:
  - If transient lock failures exceed policy threshold or start appearing in CI-critical windows.
- Planned follow-up options:
  1. Add short retry wrapper around state writes in affected test/setup paths.
  2. Investigate exclusive file-handle usage around state save/update calls.
  3. Run gate on a quieter host profile to baseline non-contention behavior.
