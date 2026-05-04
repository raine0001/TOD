# TOD Conversational Implementation Request v1

## Request Type
- `implementation_request`

## Objective
- Give TOD a direct conversational lane so it can speak to the operator as a collaborator, not only publish status artifacts or route the human to MIM.

## Current Communication Skills Audit
- TOD Operator Chat:
  - read-only bounded summaries and recommendations over live dashboard state
  - strong evidence and audit posture
  - not a full direct conversation lane
- MIM Command Panel:
  - human-to-MIM live dialog session path
  - TOD is secondary and bounded in this lane
- TOD-MIM Dialog Channel:
  - structured session messaging, request/reply, and bounded coordination
  - optimized for system-to-system coordination, not direct natural conversation with TOD
- Local Conversation Provider:
  - `scripts/Invoke-TODConversationProvider.ps1`
  - local-first chat model support already exists
  - not currently exposed as the primary browser conversation surface
- Voice Listener / Speech:
  - `scripts/Start-TODVoiceListener.ps1`
  - wake phrase, command recognition, and spoken replies already exist
  - optimized for command/query routing more than rich direct conversation
- Conversation Evaluation Harness:
  - TOD already has simulation, drift, PR, soak, and coaching harnesses for conversation quality
  - this is a quality gate, not the live UI conversation surface itself

## Diagnosis
- TOD does not lack communication primitives.
- TOD lacks one primary, direct, conversational surface that unifies:
  - current work context
  - implementation understanding
  - bounded next steps
  - natural-language response generation

## Bounded Implementation Steps
1. Add a direct TOD conversation endpoint backed by the local conversation provider with bounded fallback behavior.
2. Expose that lane in the browser UI as a first-class `TOD Direct` panel instead of only `MIM First` interaction.
3. Build a reusable context pack for TOD conversation replies from current work, maintenance, watchdog, and `mim_wall` integration state.
4. Classify implementation-oriented requests explicitly so TOD can answer with development posture, bounded steps, and what is working vs blocked.
5. Add a focused regression test for the conversational reply engine so future UI or provider changes do not collapse the lane back into status-only output.

## Implemented In This Slice
- Added a dedicated conversational reply engine:
  - `scripts/Invoke-TODConversationalReply.ps1`
- Added a live UI host route:
  - `POST /api/tod-conversation`
- Added a direct browser panel:
  - `TOD Conversation` in `ui/index.html`
- Added a focused regression test:
  - `tests/TOD.ConversationalReply.Tests.ps1`

## Not Yet Complete Beyond This Slice
- TOD does not yet persist a long-running direct conversation memory thread for browser conversations.
- TOD does not yet blend operator commitments, reasoning bundles, and direct conversation into one unified conversational memory model.
- Voice and browser conversation are still adjacent lanes, not one merged stateful conversation system.
- Conversation quality gates exist, but the new TOD-direct lane is not yet included in a dedicated live sweep harness.