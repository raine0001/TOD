# TOD AgentMIM Deterministic App-Data Fast Path Apprenticeship V1

## Purpose

Teach TOD the repair pattern behind the AgentMIM client-page timeout without letting the emergency Codex patch count as TOD progress.

## Borrowed Incident

AgentMIM sidebar chat timed out when the user asked for total carrier-paid commissions for a visible client. The answer was already available from app data, but the request entered the generic assistant path.

## Pattern TOD Must Learn

1. Inspect the live user-facing symptom and the route/template providing context.
2. Decide whether the question is answerable from stored app data before LLM fallback.
3. Publish reliable page context for the assistant surface.
4. Add the smallest deterministic answer path before generic composition.
5. Validate with tests that prove the answer uses authoritative data and does not require slow generic chat.
6. Preserve the generic conversational path for non-deterministic questions.

## Independent Demonstration

TOD must choose a fresh analogous target, inspect current source, synthesize a bounded packet or precise blocker, and validate the result. Codex may coach and validate, but may not write the patch if TOD is to receive independent credit.

## Prevention Lesson

Factual app-data questions should not wait for a general-purpose language response when the application already has the needed records. MIM can still explain the answer, but the data retrieval path must be deterministic, scoped, and testable.
