# TOD Document Viewer Authoring Training Plan

Objective: Train TOD to independently convert a broad document-viewer feature request into bounded, source-anchored work without Codex authoring the patch.

Rules:
- TOD does the work.
- Codex coaches, validates, and backs down rungs when TOD fails.
- No hardcoded answers or hidden route shortcuts.
- No completion claim from compile-only validation.
- Every rung reports from evidence only.

Current Blockers:
1. TOD cannot reliably author exact source-anchor packets from broad UI objectives.
2. TOD can misclassify compile-only validation as feature completion.
3. TOD cannot consistently produce post-task self assessment through a non-code lane.
4. TOD has not independently proven document mirror request fulfillment and content-route validation.

Drill 001: Function Discovery
- Input: one target file and one function name.
- Required TOD output: target file exists, function exists, exact anchor snippet, current behavior, missing behavior.
- Pass condition: all named functions exist in source and no invented function names appear.

Drill 002: Packet Shell
- Input: passed Drill 001 output.
- Required TOD output: target file, edit mode, anchor, safe fix direction, validation command, rollback note, prevention lesson.
- Pass condition: packet is reviewable without implementation.

Drill 003: Viewer Validation Design
- Input: document viewer requirements and one test document id.
- Required TOD output: browser route to test, content route to test, raw-path leakage check, status-code check, content-type check.
- Pass condition: validation commands are executable and prove user-visible behavior.

Drill 004: Mirror Request Fulfillment
- Input: one document selected through the viewer.
- Required TOD output: request artifact path, source path validation against approved root, mirror script command, manifest proof, content endpoint proof.
- Pass condition: mirrored file opens through browser and manifest policy is present.

Drill 005: Evidence-Only Self Assessment
- Input: actual run evidence.
- Required TOD output: what was attempted, what passed, what failed, what not to claim, missing capability, active continuation.
- Pass condition: no invented success, no stale context, no claims that TOD implemented work it did not implement.

Graduation Test:
TOD repeats the full document-viewer process on a second research document family without Codex writing old/new text or implementation code.
