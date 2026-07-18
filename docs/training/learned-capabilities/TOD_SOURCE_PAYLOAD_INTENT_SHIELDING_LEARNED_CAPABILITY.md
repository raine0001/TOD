# Learned Capability: Source Payload Intent Shielding

## Capability Name

TOD source-payload intent shielding for source-anchored packet authoring.

## Trigger

TOD is asked to draft or inspect a source-anchored packet that includes raw source text, `old_text`, `new_text`, HTML labels, code paths, or document excerpts.

## Reality

Source payloads can legitimately contain words that look like operator intent, such as `Status:`, `conversation`, `change`, `create`, or file paths containing conversational script names.

## Observation

TOD tried to draft a document-reader packet for `_document_viewer_panel`.

The prompt contained raw source text with an embedded `Status:` label.

`Invoke-TODConversationalReply.ps1` classified the request as `status_request` and returned stale current-work text instead of packet fields.

## Root Cause

`Get-RequestKind` applied implementation/status intent regexes to the entire query, including structured evidence and source payloads.

The classifier did not separate operator instruction text from source material.

## Blocker Class

`capability_blocker`

## Decomposition Ladder

1. Prove TOD can extract target file and function from explicit evidence.
2. Retry packet drafting with raw source.
3. Observe classifier hijack from source payload text.
4. Add a generic source-payload shielding helper before intent regex checks.
5. Add evidence-report field passthrough for explicit supplied fields.
6. Validate with focused conversational reply tests.
7. Retry source-anchored packet drafting and product validation.

## Smallest Successful Rung

TOD correctly extracted:

- `target_file=tmp_remote_mim/core/routers/observatory.py`
- `target_function=_document_viewer_panel`

after the evidence-report prompt used the exact supported contract.

## Implementation Summary

`scripts/Invoke-TODConversationalReply.ps1` now:

- removes structured payload sections from intent classification text before implementation/status regex checks,
- keeps evidence-report detection on the full query,
- supports `Fields:` lists without requiring colons,
- passes explicit evidence values through for requested fields,
- maps `quality_result` or `validation_result` into `pass_or_fail`,
- honors explicit `what_not_to_claim`.

## Validation

`Invoke-Pester -Path tests\TOD.ConversationalReply.Tests.ps1`

Result: `15 passed, 0 failed`.

Added tests:

- explicit evidence fields copy without stale status fallback,
- embedded source payload labels do not become operator intent or dispatch.

## General Rule Learned

Classify the operator instruction, not the quoted/source payload.

Raw source text is evidence, not intent.

## Prevention Rule

Any parser that accepts source text, extracted document bodies, quoted messages, or patch anchors must shield that payload before applying operator-intent routing.

## Reuse Trigger

Use this capability when TOD:

- drafts patch packets,
- handles `old_text` / `new_text`,
- receives extracted document text,
- receives quoted MIM/TOD dialog history,
- sees source code containing words that match routing triggers.

## Dependent Capabilities

- exact old_text packet authoring
- evidence-only reporting
- document-reader packet authoring
- no-hardcoded-answer enforcement
- source-body research assimilation

## Capability Confidence

8/10

## Independent Pass Rate

Not yet proven. The repair was Codex emergency repair after TOD control-plane failure.

TOD must repeat source-payload packet drafting in a later independent drill.

## Date Frozen

2026-07-07

## Generalized Principle

Readers of mixed instruction-and-evidence payloads must distinguish instruction from evidence before reasoning or routing.

If source material can affect routing, the system is letting the evidence drive the control plane instead of the task contract.
