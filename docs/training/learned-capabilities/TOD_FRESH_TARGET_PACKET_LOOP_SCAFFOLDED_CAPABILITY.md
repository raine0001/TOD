# TOD Fresh Target Packet Loop Scaffolded Capability

## Capability
TOD can run a scaffolded fresh-target packet loop: observe a current source anchor, synthesize a bounded Python packet artifact, apply the packet through the local executor, validate the edit, and clean up the harmless training change.

## Source Objective
TOD-INDEPENDENT-FRESH-TARGET-PACKET-LOOP-V1

## Training Evidence
- `TSK-TOD-INDEPENDENT-FRESH-PACKET-MATERIALIZATION-V1-R2` first published a precise blocker because the packet formation attempt could not find an exact current source anchor.
- `TSK-TOD-PUBLIC-CHAT-SOURCE-ANCHOR-OBSERVATION-V1-R2` then published `runtime_remote_training/read_only_audit_artifacts/TOD_PUBLIC_CHAT_SOURCE_ANCHOR_OBSERVATION.latest.json` with `matched=true`, `source_file=tmp_remote_mim/core/routers/public_chat.py`, and exact anchor text.
- `TSK-TOD-INDEPENDENT-FRESH-PACKET-MATERIALIZATION-V1-R3` published `runtime_remote_training/tod_independent_resolution_attempts/TOD_INDEPENDENT_FRESH_PUBLIC_CHAT_PACKET.latest.json` with `packet_candidate_ready=true`, exact `old_text`, different `new_text`, validation command, closure evidence, prevention lesson, and `dave_needed=no`.
- `TSK-TOD-INDEPENDENT-FRESH-PACKET-APPLY-V1-R2` applied the packet through the local executor and changed `tmp_remote_mim/core/routers/public_chat.py`.
- `TSK-TOD-INDEPENDENT-FRESH-PACKET-CLEANUP-V1-R1` exposed a reverse-packet cleanup weakness: the cleanup attempt was blocked as wrapper-only/no execution.
- `TSK-TOD-INDEPENDENT-FRESH-PACKET-CLEANUP-V1-R2` backed down to an exact bounded cleanup edit, removed the harmless marker, and validated `tmp_remote_mim/core/routers/public_chat.py`.

## Validation
- `python -m py_compile tmp_remote_mim/core/routers/public_chat.py`
- `tests/TOD.BoundedEditMaterialization.Tests.ps1`
- `tests/TOD.IntakeArbitration.Tests.ps1`
- `tests/TOD.LocalFallbackExecutor.Tests.ps1`

## Prevention Lesson
TOD must not treat packet artifact creation as equivalent to implementation. The full proof requires source-anchor observation, packet synthesis, apply, validation, cleanup, and an honest credit boundary. When reverse-packet cleanup cannot prove execution, TOD should back down to exact current-code cleanup instead of leaving source residue.

## Current Status
Scaffolded pass. Codex repaired packet-formation artifact materialization and shared-artifact write retry behavior first, and Codex supplied the source-anchor directives for the successful observation rung. TOD demonstrated execution after coaching, but the capability is not independent or retired yet.

## Next Independent Demonstration Required
TOD must select a fresh harmless target, discover the source anchor itself, synthesize the packet, apply it, validate it, clean it up, and publish evidence without Codex selecting the target, providing exact anchor directives, or repairing another control-plane path.
