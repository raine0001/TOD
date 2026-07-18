# TOD Unique-Anchor Bounded Edit Materialization Learned Capability

Capability Name: Unique-anchor bounded edit materialization.

Trigger: TOD needs to change a source file through a bounded edit packet and the old text or insertion anchor may appear more than once.

Reality: `tmp_remote_mim/core/routers/studio.py` contained multiple `return _studio_operator_contract_fallback_reply(prompt, page_context)` lines in different control-flow contexts.

Observation: TOD's bounded edit packet used that repeated line as the full old text. The local engine reported completion, but the edit landed at the first matching occurrence, after an already-returned mode guard, and created an early fallback that made later Studio chat logic unreachable.

Root Cause: TOD treated a syntactically valid replacement as a successful behavioral edit without proving that the anchor was unique or that the resulting hunk landed in the intended control-flow position.

Blocker Class: capability_blocker.

Decomposition Ladder:

1. Broad failure: hardcoded Studio MIM fallback remained visible to Dave.
2. Smaller proof: TOD audited the target file and found the fallback source anchors.
3. Failed rung: TOD attempted a bounded replace using repeated old text.
4. Corrective rung: inspect all occurrences of the old text before editing.
5. Smaller successful rung: include surrounding unique context or a structured insertion scope.
6. Validation rung: prove syntax, prove occurrence count, and prove the changed branch sits before the intended final fallback.

Smallest Successful Rung: Before applying any bounded edit, run an occurrence check for `old_text` or `anchor_or_old_text`. If count is not exactly one, TOD must widen the anchor with surrounding context or switch to a structured update that names the containing function/block.

Implementation Summary: Codex removed the misplaced objective-progress branch, inserted it immediately before the true final Studio fallback, and left the bad edit as apprenticeship debt rather than independent TOD credit.

Validation: `python -m py_compile tmp_remote_mim/core/routers/studio.py` passed after the correction. Source search shows one `studio_objective_progress_context` branch located directly before the final fallback.

General Rule Learned: A bounded edit is not valid just because a file changed and compiles. TOD must prove the edit landed at the intended semantic location.

Prevention Rule: For `replace_text` packets, TOD must record the occurrence count of the old text. Repeated old text requires a unique scoped anchor. Completion evidence must include post-edit placement evidence, not only command success.

Reuse Trigger: Any future bounded edit packet where the target file contains repeated fallback calls, repeated helper names, repeated closing blocks, repeated route returns, or repeated UI strings.

Dependent Capabilities: source-anchor audit, bounded edit packet synthesis, post-edit behavioral placement validation.

Capability Confidence: high for recognizing this failure pattern; not yet independent for TOD until a fresh analogous case passes without Codex packet fields.

Independent Pass Rate: 0/1.

Date Frozen: 2026-07-15.

Separate Debt: TOD still needs a fresh independent demonstration where it inspects a target file, discovers repeated anchors, selects unique edit scope, applies the edit, validates placement, and closes the task without Codex patching.

Generalized Principle: Implementation evidence must prove intent, not just mutation. A changed file plus a green compiler can still be the wrong change.
