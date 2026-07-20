# TOD Apprenticeship Registry

Status: active

Purpose: record every borrowed capability created by a Codex emergency repair until TOD independently demonstrates, freezes, and retires the capability debt.

This registry is not a scorecard. It is a debt ledger. A borrowed capability remains open until TOD proves it can perform the capability on a fresh analogous case without Codex field scaffolding.

## Required Fields

Every entry must include:

- Borrowed From
- Reason
- Incident
- Capability
- Current Apprentice
- Progress
- Independent Demonstration
- Freeze
- Retirement

## State Meanings

- `borrowed`: emergency repair completed, capability not yet acquired.
- `assimilating`: TOD is studying the repair and building an internal representation.
- `scaffolded_pass`: TOD reproduced the reasoning or artifact with coaching/scaffolded evidence.
- `independent_demo_pending`: TOD has not passed a fresh analogous case without Codex field scaffolding.
- `independent_demo_passed`: TOD passed an unseen analogous case from discovered evidence.
- `frozen`: learned capability artifact exists with validation evidence.
- `retired`: capability is no longer borrowed because TOD can perform and maintain it independently.

## Proficiency Ladder

Borrowed-capability state records whether the debt is open or retired. Proficiency records how much trust MIM can place in TOD for that capability.

- `observed`: TOD has seen the pattern and has evidence of how it was done, but has not reproduced it.
- `understood`: TOD can explain the pattern, risks, validation steps, and when to reuse it from evidence.
- `guided`: TOD can perform the pattern with a provided target, explicit anchors, or Codex/MIM scaffolding.
- `independent`: TOD can perform the pattern on a fresh analogous task without Codex writing the packet or patch.
- `reliable`: TOD has repeated the pattern successfully across multiple analogous tasks with validation and no material regression.
- `teaches_others`: TOD can turn the pattern into a reusable lesson, detect recurrence, coach MIM/operator expectations, and improve the control plane without losing safety.

Progression rule: one successful independent demonstration can advance a capability to `independent`, but not to `reliable`. Reliability requires repeated successful demonstrations across changed context.

## Active Entries

### APP-TOD-024: Research Observatory Conversation Evolution Routing

Borrowed From: Codex emergency repair.

Reason: The live Research Observatory conversation repeated the static Observation-Driven Intelligence initiative envelope when the operator made a meta-research observation about prior conversation quality, understanding, and response learning. This violated MIM's research-evolution training and made the page behave like retrieval instead of living research.

Incident: `MIM-OBSERVATORY-RESEARCH-EVOLUTION-STATIC-ENVELOPE-20260716`

Capability: Recognize when a Research Observatory turn changes the research object, rejects the current frame, identifies a conversation-derived observation, or proposes future action; route that turn before static envelope retrieval; validate the live public chat path without hardcoding Dave's exact wording.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/public_research_context.py`, added regression coverage in `tmp_remote_mim/tests/test_public_research_context.py`, deployed both files to the MIM Box, restarted `mim-mobile-web.service`, and proved the live `/public/chat/message` endpoint returns a research-evolution response for the failed Observation-Driven Intelligence prompt.

Independent Demonstration: `pending`; TOD must diagnose a fresh analogous Observatory conversation failure from live prompt evidence, identify whether the root is marker-gate ordering, missing research-evolution intent, static envelope fallthrough, or downstream mutation, then produce a bounded repair and validation evidence without Codex-authored code.

Freeze: open; no learned capability exists yet for Research Observatory conversation-evolution routing.

Retirement: open.

### APP-TOD-027: Public Homepage Structured Reply Rendering Boundary

Borrowed From: Codex emergency production repair.

Reason: The live public `mimtod.com` homepage rendered `[object Object]` in MIM chat bubbles because the homepage JavaScript passed the structured `/public/chat/message` `reply` object directly into the visible message renderer instead of extracting `reply.content` or `reply.text`.

Incident: `MIM-PUBLIC-HOMEPAGE-OBJECT-REPLY-RENDERING-20260720`

Capability: When a public MIM surface consumes a structured response contract, TOD must verify the UI display boundary extracts operator-visible text deterministically, preserves the semantic answer, and does not concatenate raw objects or metadata into the human chat transcript.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/routers/public_chat.py`, added a homepage-shell regression assertion in `tmp_remote_mim/tests/test_public_homepage_enterprise_shell.py`, deployed the router to `/home/testpilot/mim/core/routers/public_chat.py`, restarted `mim-mobile-web.service`, and proved the live homepage HTML includes `replyText(payload)` while the old `payload.reply || payload.message` object-rendering path is absent.

Independent Demonstration: `pending`; TOD must inspect a fresh MIM UI surface that receives a structured response, identify the display-text extraction boundary, add or validate a regression guard, and publish evidence without Codex selecting the exact target or patch.

Freeze: open; requires a learned-capability note after TOD demonstrates the structured-response display-boundary pattern on a fresh analogous surface.

Retirement: open.

### APP-TOD-028: Public Enterprise Product Question Routing

Borrowed From: Codex emergency production repair.

Reason: The live public `mimtod.com` MIM chat answered "what is an enterprise account?" with the generic conversation-purpose exploration fallback: "My first working hypothesis...". That was wrong because the Enterprise front door already defines the product context, setup flow, pricing guidance, and clean private Observatory value proposition.

Incident: `MIM-PUBLIC-ENTERPRISE-PRODUCT-QUESTION-ROUTING-20260720`

Capability: When a public MIM visitor asks about a visible product, account type, setup flow, pricing, or business benefit, TOD must ensure product-context authority is checked before generic exploration or structural-reasoning fallback. Product questions should answer from the product surface context and only ask discovery follow-ups after providing a useful explanation.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/routers/public_chat.py` so Enterprise product questions use the Enterprise product-context branch before `build_conversation_purpose_reply()`, added focused direct-answer regression checks in `tmp_remote_mim/tests/test_public_chat_direct_answers.py`, deployed the router to `/home/testpilot/mim/core/routers/public_chat.py`, restarted `mim-mobile-web.service`, and proved live `/public/chat/message` answers both "what is an enterprise account?" and "how could my business benefit from the enterprise account" without the generic hypothesis fallback.

Independent Demonstration: `pending`; TOD must inspect a fresh public product/context question that is being preempted by generic exploration, identify the correct authoritative content source, add the smallest routing or authority fix, validate with a live prompt, and publish evidence without Codex selecting the exact target or answer text.

Freeze: open; requires a learned-capability note after TOD demonstrates product-context authority on a fresh analogous public-surface question.

Retirement: open.

### APP-TOD-029: Observatory Service Knowledge Product Context Certification

Borrowed From: Codex emergency product-knowledge repair.

Reason: The public MIM chat needed to describe `/observatory` services 10/10, but Observatory and Enterprise product questions were still vulnerable to the generic exploration fallback. The live failure mode was visible as an answer beginning with "My first working hypothesis..." when the visitor asked for a basic product explanation.

Incident: `MIM-OBSERVATORY-SERVICES-CERTIFICATION-20260720`

Capability: When a visitor asks about Observatory services, Enterprise accounts, setup, tenant isolation, documents, integrations, MIM/TOD roles, or business value, MIM must answer from the current product/service context before generic exploration fallback. It must distinguish proven capabilities from setup-dependent integrations and avoid hallucinating live connections.

Current Apprentice: TOD

Progress: `borrowed`; Codex added an Observatory service catalog and product-context reply boundary in `tmp_remote_mim/core/routers/public_chat.py`, added a 10-question Observatory service certification smoke in `tmp_remote_mim/tests/test_public_chat_direct_answers.py`, separated Enterprise pricing questions from general Enterprise definition answers, deployed the router to `/home/testpilot/mim/core/routers/public_chat.py`, restarted `mim-mobile-web.service`, redesigned `/studio/auditor` as an Executive Truth surface with `/studio/auditor/lab` as the protected Behavior Lab, and proved the live `/public/chat/message` endpoint answers both "what is an enterprise account?" and "how much is an enterprise account?" in distinct modes.

Independent Demonstration: `pending`; TOD must independently inspect a fresh Observatory/Enterprise service question class, identify the authoritative service context, extend the certification set or auditor without Codex selecting the exact answer boundary, deploy safely, and prove live behavior.

Freeze: partial; evidence is recorded in `runtime_remote_training/read_only_audit_artifacts/MIM_OBSERVATORY_SERVICES_CERTIFICATION_V1.latest.json`, and the protected `/studio/auditor` certification run produced `runtime_remote_training/read_only_audit_artifacts/STUDIO_AUDITOR_OBSERVATORY_CERTIFICATION_V1.latest.json` with 10/10 passed. The Auditor UI now separates Executive Truth from Behavioral Testing and removes the default MIM chat panel. Full freeze requires expanding the auditor into the broader certification suite.

Retirement: open.

### APP-TOD-030: AgentMIM Visible Page-Context Fast Path Before Generic Chat

Borrowed From: Codex emergency production repair.

Reason: AgentMIM sidebar chat timed out on the Clients page when Dave asked what visible `bonus` records were. The page showed the relevant rows, but the backend did not receive structured visible-row context and therefore fell into the slower generic assistant path.

Incident: `AGENTMIM-CLIENTS-VISIBLE-RECORDS-SIDEBAR-TIMEOUT-20260720`

Capability: When a user asks a factual question about records currently visible on an AgentMIM page, TOD must ensure the page publishes enough structured context for MIM to answer deterministically before generic chat. The pattern includes identifying the visible data source, publishing `window.mimPageContext` for that surface, adding the smallest deterministic fast path, validating that generic chat is not called, and deploying safely.

Current Apprentice: TOD

Progress: `borrowed`; Codex added `window.mimPageContext.clients` to the Clients page, added `_maybe_answer_visible_client_records_request` before slower assistant paths, added regression tests, pushed commit `739bbcc5d88471da9376f7a121886ed082c2e4e8`, triggered Render deploy `dep-d9f4rgb7uimc73amaong`, and verified GitHub fast checks plus production `/health`. Live Chrome then showed inline page context was not reliable enough, so Codex added shared assistant send-time Clients table context collection in commit `8776e505a22c3b2cf321b771ea065a2bd2f7d974` and deployed `dep-d9f565b7uimc73ams4q0`. The first live sidebar smoke no longer timed out but answered too broadly, so Codex added named-row matching in commit `1bd202e626163e6f03f5d9d425b9357797150aaf`, passed the 11-test focused regression suite, and deployed `dep-d9f598jrjlhs73dj654g`. Final post-deploy Chrome smoke remains pending because the browser session refreshed back to the AgentMIM login page and the stale pre-refresh send hit a CSRF-session-token error.

Proficiency: `observed`; TOD has not yet independently inspected, materialized, implemented, and validated this class.

Independent Demonstration: `pending`; TOD must inspect a fresh AgentMIM page where sidebar MIM times out or ignores visible data, identify the missing page-context or deterministic answer boundary, produce a bounded implementation, validate that generic chat is bypassed, deploy, and publish evidence without Codex authoring the fix.

Freeze: partial; evidence is recorded in `runtime_remote_training/read_only_audit_artifacts/AGENTMIM_CLIENTS_VISIBLE_RECORDS_FAST_PATH_V1.latest.json`.

Retirement: open.

### APP-TOD-026: AgentMIM Deterministic App-Data Answer Before LLM Fallback

Borrowed From: Codex emergency AgentMIM production repair.

Reason: AgentMIM sidebar chat timed out on a deterministic client-data question from a live client page. The user asked what total carrier-paid commissions existed for a client across all data, but the assistant fell through the general MIM/LLM path instead of answering directly from page context plus stored commission rows.

Incident: `AGENTMIM-CLIENT-COMMISSION-TOTAL-SIDEBAR-TIMEOUT-20260718`

Capability: When a user asks a factual question that can be answered from current app data, page context, or already-loaded records, TOD must help MIM route the request through a deterministic data answer before LLM fallback. The pattern includes publishing reliable page context, identifying the data-backed intent, querying the authoritative records, returning a concise answer, and preserving the slower conversational path only for questions that truly need reasoning.

Current Apprentice: TOD

Progress: `borrowed`; Codex repaired `E:\comm_app` and pushed commit `24e59e6d Fix MIM client commission total timeout`. The repair added a `viewClient` page-context payload, a deterministic pre-LLM client commission-total fast path, and regression tests proving the fast path answers from the database without requiring generic assistant generation.

Proficiency: `observed`; TOD has not yet independently inspected, materialized, implemented, and validated this class.

Independent Demonstration: `pending`; TOD must inspect the pushed AgentMIM repair, identify one fresh analogous deterministic app-data assistant question on another live AgentMIM surface, publish a current-code bounded packet or precise blocker, execute or block through the approved TOD path, validate with tests that the deterministic path answers without generic timeout-prone chat, and publish evidence.

Freeze: open; the production symptom is repaired, but the engineering pattern is not TOD-owned until an independent demonstration succeeds.

Retirement: open.

### APP-TOD-012: AgentMIM Carrier Commission Parser Contract Repair

Borrowed From: Codex emergency repair.

Reason: AgentMIM June commission uploads were blocked for live business files. Dickerson staging returned a server error because parser header normalization assumed every Excel header was a string, and Humana SpreadsheetML files with a real `PaidAmount` column were being treated as policy-agent roster files instead of carrier-paid commission statements.

Incident: `AGENTMIM-JUNE-2026-HUMANA-DICKERSON-UPLOAD-BLOCKER-20260715`

Capability: Inspect real carrier commission workbook shapes, distinguish roster guards from commission-dollar evidence, repair bounded parser/mapping contracts, preserve legacy carrier behavior, validate focused regressions, and prove real-file staging with a dry-run report.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `E:\comm_app` parser normalization, Humana true-paid-amount recognition, and Dickerson mapping aliases, then validated focused tests and a real-file dry run against Dave's June upload folder.

Independent Demonstration: `pending`; TOD must handle a fresh analogous carrier upload failure by inspecting the real file headers and parser path, identifying the smallest parser or mapping contract repair, adding regression coverage, running focused tests, and proving the actual file stages without Codex patching.

Freeze: open; no learned capability exists yet for carrier commission parser contract repair.

Retirement: open.

### APP-TOD-023: Optional Selection Source Field StrictMode Recovery

Borrowed From: Codex emergency control-plane repair.

Reason: After TOD successfully published a ready packet-formation artifact, the next selector cycle crashed before promotion because `Resolve-TodNextTaskSelectionTask` read `selection_source_task_id` from a task creation spec that did not define that optional field. StrictMode converted a missing optional field into a hard control-plane failure.

Incident: `TOD-SELECTION-SOURCE-OPTIONAL-FIELD-20260716`

Capability: TOD selector and materializer code must treat optional metadata fields as optional under StrictMode, using guarded property reads and empty defaults so task-shape variance becomes evidence or blocker output instead of a crash.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `scripts/TOD.ps1` so created selection tasks add `selection_source_task_id` only through a guarded local value. This restores the selector path but does not count as TOD implementation progress.

Independent Demonstration: `pending`; TOD must promote a packet-derived task with missing optional metadata, execute or precisely block it, and prove no StrictMode optional-field crash occurs.

Freeze: open; requires parser validation and a fresh selector retry.

Retirement: open.

### APP-TOD-011: Executor Binding Blocker Self-Recovery

Borrowed From: Codex emergency repair.

Reason: `/studio/tod` reported `Binding Required` because task identity was repaired but no local executor binding was visible. Codex traced the blocker to a stale `TOD_EXECUTOR_BINDING_REPAIR.latest.json` marker suppressing republish even though `MIM_TOD_TASK_REQUEST.latest.json` had been overwritten and no longer contained the local binding.

Incident: `TOD-EXECUTOR-BINDING-ALREADY-ATTEMPTED-STALE-MARKER-20260715`

Capability: Detect a missing-component blocker, compare old repair markers against the current authoritative request, republish the smallest valid local executor binding when current proof is absent, validate both serving lanes, and explain the blocker to the operator in plain context rather than route telemetry.

Current Apprentice: TOD

Progress: `borrowed`; Codex repaired the stale-marker replay guard, validated focused tests, deployed to the MIM BOX, and proved `/tod/ui/state` reports `binding=ready` on both `18001` and `18021`.

Independent Demonstration: `pending`; TOD must handle a fresh analogous missing-component blocker by inspecting current artifacts, identifying whether a marker is stale, materializing the missing component, validating the live state, and publishing a human-readable operator explanation without Codex patching.

Freeze: partial; `docs/training/learned-capabilities/TOD_EXECUTOR_BINDING_BLOCKER_SELF_RECOVERY_LEARNED_CAPABILITY.md` exists, but independent pass rate is not proven.

Retirement: open.

### APP-TOD-001: Cross-Surface Conversation Purpose Routing

Borrowed From: Codex emergency repair.

Reason: The real operator surface returned an operational action contract while the direct Studio API recognized the reflective prompt. MIM/TOD could not complete the routing diagnosis independently.

Incident: `MIM-CONVERSATION-SURFACE-TRACE-V1`

Capability: Trace a user-visible conversation failure across UI surface, endpoint, gateway, conversation purpose engine, formatter, and final response; distinguish internal API success from real operator-surface success.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD produced `runtime/shared/TOD_EMERGENCY_REPAIR_APPRENTICESHIP_SELF_REPORT.latest.json` from scaffolded evidence and repaired supporting drill blockers.

Independent Demonstration: `pending`; TOD must diagnose a fresh cross-surface routing split without Codex-provided field scaffolding.

Freeze: partial; `docs/training/learned-capabilities/CROSS_SURFACE_CONVERSATION_PURPOSE_ROUTING_LEARNED_CAPABILITY.md` exists, but independent pass rate is not proven.

Retirement: open.

### APP-TOD-002: Evidence-Derived Numeric Research Answer

Borrowed From: Codex emergency repair.

Reason: MIM had SolAir BOM evidence but answered a specific build-cost question with a generic manufacturing-discovery fallback. Codex repaired the evidence path before MIM/TOD independently demonstrated the capability.

Incident: `MIM-NUMERIC-ANSWER-FROM-EVIDENCE-BACKFILL-001`

Capability: Convert a specific numeric research question into source selection, field extraction, deterministic calculation, uncertainty boundary, source citation, fallback rejection, and live-route validation.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD produced `runtime/shared/TOD_NUMERIC_ANSWER_BACKFILL_SELF_REPORT.latest.json` from scaffolded evidence.

Independent Demonstration: `pending`; TOD must handle a fresh numeric research prompt or unfamiliar artifact schema without Codex-provided field labels.

Freeze: partial; `docs/training/learned-capabilities/MIM_RESEARCH_NUMERIC_ANSWER_FROM_EVIDENCE_LEARNED_CAPABILITY.md` exists, but independent pass rate is not proven.

Retirement: open.

### APP-TOD-003: Homepage Rollback and Conversation-Intent Safety

Borrowed From: Codex emergency repair.

Reason: MIM misclassified a curriculum prompt as homepage implementation, the public homepage regressed to an older business-software/create surface, and MIM could not preserve rollback context when asked to undo the unintended change. The gateway also computed a conversation-purpose reply without publishing it, allowing homepage fast paths to preempt curriculum recognition.

Incident: `MIM-HOMEPAGE-CURRICULUM-MISROUTE-20260711`

Capability: Trace and repair a public-site regression caused by conversation-context failure; restore the intended route/artifact safely; verify the live page; repair cross-surface conversation-purpose route ordering; then convert the repair into MIM/TOD training on active context, curriculum recognition, exploratory reasoning, intent verification before code changes, and action reversibility.

Current Apprentice: TOD

Progress: `lower_rung_packet_body_synthesis_passed`; Codex identified the fallback-route failure, repaired the homepage route/artifact, repaired the authenticated gateway purpose branch, added the public-chat purpose gate, deployed to the MIM box, restarted `mim-mobile-web.service`, and validated the live homepage, public chat exploration, authenticated gateway exploration, and authenticated gateway curriculum probes. TOD then passed lower rungs for one-file read-only audit publication, exact source-anchor observation, and bounded packet-body synthesis from that anchor. TOD has not independently demonstrated the full repair pattern because Codex still selected the case and bounded fields.

Independent Demonstration: `pending`; TOD must diagnose a fresh UI or conversation-surface regression from live route evidence, select the case and fields itself, identify whether the source is route fallback, artifact lookup, stale service, redirect context, or purpose-engine preemption, and publish a bounded repair/validation packet without Codex field scaffolding.

Freeze: open; no learned capability exists yet for homepage rollback and conversation-intent safety.

Retirement: open.

### APP-TOD-004: Self-Evolution Schema Drift Recovery

Borrowed From: Codex emergency repair.

Reason: During MIM cognitive-loop training, the self-evolution `briefing` and `next-action` routes returned 500 errors because live ORM code expected `assumptions_json` columns that were missing from existing workspace-improvement tables. MIM/TOD could not report or select the active training continuation until the route recovered.

Incident: `self_evolution_reporting_route_500_during_cognitive_loop_training`

Capability: Diagnose a live route 500 from logs, identify additive schema drift between ORM expectations and database tables, apply the smallest non-destructive compatibility migration, validate the affected routes, and record the borrowed capability without treating emergency repair as learned competence.

Current Apprentice: TOD

Progress: `borrowed`; Codex applied additive `assumptions_json` columns to the affected tables and validated that self-evolution `progress`, `briefing`, and `next-action` routes returned 200.

Independent Demonstration: `pending`; TOD must diagnose a fresh route/schema drift failure from logs and table inspection, propose the additive repair, validate routes, and publish rollback/verification evidence without Codex field scaffolding.

Freeze: open; no learned capability exists yet for self-evolution schema drift recovery.

Retirement: open.

### APP-TOD-005: Dialog Response Contract Projection And Focus-Review Derivation

Borrowed From: Codex emergency repair.

Reason: During the 1,000-conversation cognitive-development loop, MIM could acknowledge focus-review handoffs but could not reliably publish the required decision-quality response fields or derive a training focus from calibration/progress artifacts. The responder path was preserving generic ACK behavior instead of producing an evidence-derived development review.

Incident: `MIM-COGNITIVE-DEVELOPMENT-LOOP-FOCUS-REVIEW-CONTRACT-20260711`

Capability: Trace dialog response-contract failures through request parsing, response projection, artifact projection, source-artifact lookup, and derived focus selection; repair the smallest responder path so MIM can publish a complete focus-review artifact from evidence without Codex prefilled output payloads.

Current Apprentice: TOD

Progress: `borrowed`; Codex repaired the MIM dialog responder, added focused tests, validated local syntax and behavior, deployed the responder to the MIM box, restarted the dialog inbox consumer, and proved an unscaffolded handoff produced `MIM_COGNITIVE_DEVELOPMENT_LOOP_DEVELOPMENT_REVIEW.latest.json` with the required focus-review fields.

Independent Demonstration: `pending`; TOD must diagnose a fresh dialog response-contract projection failure, identify the missing projection or source-artifact derivation path, propose a bounded repair and validation plan, and prove the responder publishes required fields without Codex-authored field scaffolding.

Freeze: open; no learned capability exists yet for dialog response-contract projection and evidence-derived focus selection.

Retirement: open.

### APP-TOD-006: Studio Active Context Transition Routing

Borrowed From: Codex emergency repair.

Reason: During the MIM cognitive-development loop, live Studio chat prompts that were follow-ups, corrections, repair asks, and status checks were intercepted by simple-direct or conversation-purpose routes before MIM inspected recent thread evidence. MIM could not preserve the active thread reliably enough to run the 1,000-conversation training loop.

Incident: `MIM-ACTIVE-CONTEXT-TRANSITION-BEFORE-EXPLORATION-20260711`

Capability: Trace live Studio route ordering, identify when active-thread evidence must be read before response-purpose classification, add the smallest route gate, and validate with live correction/status/follow-up probes against the real operator surface.

Current Apprentice: TOD

Progress: `borrowed`; Codex added the active-context transition gate, validated focused local tests, deployed to the MIM box, and proved the live fair active-context probe passed 9/9.

Independent Demonstration: `pending`; TOD must diagnose a fresh route-ordering failure where a follow-up/correction is swallowed by an earlier route, identify the route gate from source evidence, propose a bounded repair, and validate against the real operator surface without Codex-authored field scaffolding.

Freeze: open; no learned capability exists yet for Studio active-context transition routing.

Retirement: open.

### APP-TOD-007: Self-Evolution Status Reporting Before Generic Exploration

Borrowed From: Codex emergency repair.

Reason: After active-context routing improved, MIM still misrouted “current self-evolution learning focus” and planning-continuity follow-ups through generic exploration. The training ledger had the evidence, but Studio chat did not consult it before the conversation-purpose engine.

Incident: `MIM-SELF-EVOLUTION-STATUS-FOCUS-ROUTE-20260711`

Capability: Recognize self-evolution status/focus prompts, hydrate active natural-language training progress from the self-evolution ledger, report current slice/proof/pass gate/not-claim boundaries, and preserve planning-continuity follow-ups through live Studio chat.

Current Apprentice: TOD

Progress: `borrowed`; Codex added the self-evolution status/focus route gate, validated focused local tests, deployed to the MIM box, and proved live Planning Continuity, Decision Flow, Escalation Recovery, Accountability Reporting, and Reflection/Memory probes. Follow-on emergency route repairs added failed-probe repair-status, after-pass continuation, why-continuation, recovery-status, and no-metadata operator training/status prompts to the self-evolution ledger path so they do not fall into Reports, generic exploration, problem-analysis, or direct-answer fallback.

Independent Demonstration: `pending`; TOD must diagnose a fresh training-ledger visibility failure, identify the missing status/progress route, validate the route with live operator-surface probes, and publish proof without Codex selecting all probe fields.

Freeze: open; no learned capability exists yet for self-evolution status reporting before generic exploration.

Retirement: open.

### APP-TOD-008: Optional Shared Helper Route Tolerance

Borrowed From: Codex emergency repair.

Reason: During the second MIM cognitive-development cycle, the live Studio chat route returned HTTP 500 while MIM was asked to report its failed-slice repair focus. Logs showed `studio.py` called `gateway_router._mim_tod_visitor_stats_diagnostic_reply`, but the loaded gateway module did not expose that optional helper. This blocked self-evolution reporting and therefore blocked the training loop.

Incident: `MIM-STUDIO-OPTIONAL-GATEWAY-HELPER-500-20260711`

Capability: Diagnose a live route 500 from service logs, distinguish required dependencies from optional shared helpers, apply the smallest compatibility guard, validate the live route, and preserve the incident as apprenticeship debt rather than learned TOD competence.

Current Apprentice: TOD

Progress: `borrowed`; Codex guarded the optional visitor-stats helper lookup so a missing gateway helper returns no visitor diagnostic instead of crashing Studio chat.

Independent Demonstration: `pending`; TOD must diagnose a fresh missing-helper route 500, identify whether the dependency is optional or required, propose a bounded compatibility repair, validate route recovery, and publish rollback/verification evidence without Codex-authored code.

Freeze: open; no learned capability exists yet for optional shared helper route tolerance.

Retirement: open.

### APP-TOD-009: Cross-Service Live Surface Verification And Serving-Lane Restart

Borrowed From: Codex emergency repair.

Reason: MIM's no-metadata operator status prompt repair passed local tests and the `mim-mobile-web.service` lane on port `18001`, but Dave's real `/studio/mim` browser surface still returned generic exploratory text. The live operator surface was using the separate `mim-training-web.service` lane on port `18021`, which had not been restarted since before the repair.

Incident: `MIM-STUDIO-OPERATOR-STATUS-SERVING-LANE-DRIFT-20260712`

Capability: Trace a user-visible behavior mismatch across source file, local unit test, internal backend port, alternate serving port, service process age, and authenticated/public browser route; identify stale serving lanes; restart the exact affected service; validate the same prompt on every serving lane before claiming production repair.

Current Apprentice: TOD

Progress: `borrowed`; Codex inspected the remote `studio.py` markers, proved port `18001` returned `studio_self_evolution_status`, proved port `18021` still returned stale non-ledger behavior, identified `mim-training-web.service` as the stale serving lane, restarted it, and validated both `18001` and `18021` now return `self_evolution_operator_status` without `exploration question` leakage. Follow-on repair added the broader self-directed learning invitation class after Dave's prompt `hi MIM what would you like to work on or learn today?` still fell into generic exploration; Codex validated that exact prompt and the prior `what are you working on MIM?` prompt on both serving lanes. 2026-07-13 update: Dave's live prompt `Hi MIM what are you working on` exposed another greeting-order variant. Codex added focused status-intent coverage, deployed `core/routers/studio.py`, restarted both `mim-mobile-web.service` and `mim-training-web.service`, and validated ports `18001` and `18021` return `source=studio_self_evolution_status`, `response_mode=self_evolution_operator_status`, and `leak=False`.

Independent Demonstration: `pending`; TOD must diagnose a fresh case where local tests and one backend port pass but the operator-visible route still fails, map the live route to the correct service/port/process, restart or repair only the affected lane, and publish proof from the same surface class Dave used.

Freeze: open; no learned capability exists yet for cross-service live surface verification and serving-lane restart.

Retirement: open.

### APP-TOD-010: Hardcoded MIM Answer Detection And Replacement

Borrowed From: Codex escalation after TOD attempt.

Reason: Dave asked to verify that MIM was not hardcoding answers. Audit found the exact live self-evolution prompt was not hardcoded in production core, but `_build_exploratory_reasoning_reply` contained canned exploratory answer bodies that returned repeated generic reasoning for different prompts.

Incident: `MIM-HARDCODED-ANSWER-AUDIT-AND-REPLACEMENT-20260713`

Capability: Detect hardcoded answer bodies, distinguish acceptable routing scaffolds from unacceptable canned reasoning, replace fixed answer bodies with prompt-grounded response composition, and validate with no-hardcode source scans plus varied-prompt behavioral tests.

Current Apprentice: TOD

Progress: `borrowed`; TOD attempted the bounded repair through `execute-chat-task`, but the local execution lane materialized the request as validation-only and published `blocked_missing_local_executor_result` with no changed files. Codex then performed a narrow escalation repair, deployed the corrected purpose engine to the MIM box, restarted `mim-mobile-web.service` and `mim-training-web.service`, validated `/studio/api/mim/chat` on ports `18001` and `18021`, and created `docs/training/MIM_HARDCODED_ANSWER_AUDIT_AND_REPLACEMENT_V1.md`.

Independent Demonstration: `pending`; TOD must find a fresh canned-answer body or repeated-response regression, classify the difference between routing scaffolding and hardcoded answer logic, produce a bounded patch without Codex-authored text, validate varied prompt outputs, and publish a prevention lesson.

Freeze: open; focused local tests passed, but TOD has not independently demonstrated the capability.

Retirement: open.

### APP-TOD-011: Response Contract Envelope Scope Repair

Borrowed From: Codex emergency repair.

Reason: MIM acknowledged a TOD blocker with a response containing top-level `summary` and `finding_positions`, but then marked those same fields as missing inside the individual finding. This prevented MIM from closing the acknowledgement contract for TOD's artifact-body synthesis blocker.

Incident: `MIM-RESPONSE-CONTRACT-ENVELOPE-SCOPE-20260713`

Capability: Distinguish response-envelope fields from per-finding response fields, validate the contract scope on the real MIM/TOD dialog lane, restart only affected MIM services, and prove the same request no longer becomes `request_missing_data`.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `tmp_remote_mim/core/next_step_dialog_service.py`, added a focused regression test in `tmp_remote_mim/tests/test_next_step_dialog_service.py`, deployed the service file to the MIM box, validated the regression remotely, restarted `mim-watch-tod-dialog-inbox-consumer.service` and `mim-mobile-web.service`, and proved a fresh live dialog response resolved with owner `tod` and no missing `summary` or `finding_positions`.

Independent Demonstration: `pending`; TOD must diagnose a fresh response-contract scope failure, identify whether each required field belongs to the envelope or finding level, propose a bounded repair, validate it with a live MIM/TOD dialog probe, and publish evidence without Codex-authored code.

Freeze: open; no learned capability exists yet for response-envelope/per-finding contract scope.

Retirement: open.

### APP-TOD-012: Read-Only Audit Extraction For Artifact-Write Blockers

Borrowed From: Codex escalation after TOD attempt.

Reason: TOD successfully used the read-only audit artifact lane, but the generated artifact was generic and did not extract the specific blocker fields from `local_execution_artifact_write_blocker` evidence such as `status=blocked_missing_artifact_content` and `missing_anchor_or_field=new_text`.

Incident: `TOD-READONLY-AUDIT-ARTIFACT-WRITE-BLOCKER-EXTRACTION-20260713`

Capability: Inspect a generated blocker artifact, recognize its schema, extract the fields that explain why execution is blocked, classify the blocker sharply, and rerun the same training rung to prove the artifact changed from generic review to specific blocker diagnosis.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD ran `TOD-READONLY-AUDIT-BODY-SYNTHESIS-001` and produced a generic read-only audit artifact. Codex then patched `scripts/engines/LocalExecutionEngine.ps1` so the read-only audit lane understands `local_execution_artifact_write_blocker` evidence. TOD reran the same task and produced `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT_BODY_SYNTHESIS_001.latest.json` with classification `artifact_body_synthesis_missing` and blockers `artifact_body_synthesis_missing` plus `new_text_artifact_body_missing`.

Independent Demonstration: `pending`; TOD must apply the same read-only audit extraction pattern to a fresh generated blocker artifact that Codex has not pre-selected, then validate specific blocker fields and continuation action.

Freeze: open; no learned capability exists yet for artifact-write blocker extraction in read-only audits.

Retirement: open.

### APP-TOD-013: Semantic Source-Audit Body Synthesis From Source Anchors

Borrowed From: Codex escalation after TOD attempt.

Reason: TOD produced source-anchor evidence and a generic read-only audit, but the original semantic root-cause audit artifact still lacked the required body fields: `observed_blocker`, `suspected_root_cause`, `evidence_checked`, `evidence_missing`, `why_forward_motion_is_blocked`, `smallest_diagnostic_step`, `confidence`, and `no_phrase_patch_rule`.

Incident: `TOD-SEMANTIC-AUDIT-BODY-FROM-SOURCE-ANCHORS-001`

Capability: Convert bounded source-anchor artifacts into a field-complete semantic audit body, validate required field readback, preserve no-code/no-phrase-patch boundaries, and route final proof to MIM for decision-quality acknowledgement.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD first proved the failure with `TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT_BODY_SYNTHESIS_001.latest.json`, then captured source anchors for `_derive_capability_model_status`, `_collect_contract_output_fields`, and `_contract_candidate_sources`. Codex added the bounded `Invoke-LocalExecutionSemanticSourceAudit` lane after the TOD attempt, and TOD reran the original task to produce `runtime_remote_training/read_only_audit_artifacts/TOD_SEMANTIC_ROOT_CAUSE_PRODUCER_AUDIT.latest.json` with all required fields, `no_phrase_patch_rule=true`, and `no_code_changes=true`.

Independent Demonstration: `pending`; TOD must synthesize a fresh semantic audit body from different source-anchor artifacts without Codex preselecting the source fields or writing the body template.

Freeze: partial; `docs/training/learned-capabilities/TOD_SEMANTIC_SOURCE_AUDIT_BODY_SYNTHESIS_LEARNED_CAPABILITY.md` records the learned capability, but the independent pass is not yet proven.

Retirement: open.

### APP-TOD-015: Source-Evidence Artifact Body Synthesis and Closure

Borrowed From: Codex escalation after TOD attempted `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002C` and produced a precise `blocked_missing_artifact_content` artifact.

Reason: TOD could bind a single bounded output target, but could not synthesize the requested artifact body from source evidence without a supplied `New Text` directive. After TOD produced the blocker, Codex added a bounded source-evidence demonstration lane and repaired the closure gate so validated artifact writes count as authoritative evidence when the artifact is the target.

Incident: `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002C` through `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002E`

Capability: Read a source evidence artifact, discover relevant fields, preserve the authority boundary between conflicting evidence lanes, write a required-field proof artifact, and close the execution contract from validated artifact-write evidence.

Current Apprentice: TOD

Progress: `scaffolded_pass`; TOD first exposed the missing body with `runtime/shared/TOD_INDEPENDENT_UNSEEN_APPRENTICESHIP_DEMONSTRATION_002.latest.json` as `blocked_missing_artifact_content`. Codex added `Invoke-LocalExecutionResearchEvidenceDemonstration`, selector coverage for hyphen/underscore concept forms, and a closure-gate repair in `Get-TodMaterialImplementationProofAssessment`. TOD reran `TOD-INDEPENDENT-UNSEEN-APPRENTICESHIP-DEMONSTRATION-002E` and published a valid SolAir power-output proof artifact from `runtime/shared/SOLAIR_POWER_CURVE_OBSERVATION.latest.json`. A follow-up BOM attempt, `TOD-INDEPENDENT-SOURCE-EVIDENCE-ARTIFACT-BODY-DEMONSTRATION-003B`, correctly remained blocked instead of false-completing when TOD produced a `local_execution_artifact_write_blocker`.

Independent Demonstration: `blocked`; TOD tried the different source artifact `runtime/shared/SOLAIR_PARTS_BOM_OBSERVATION.latest.json`, but still could not synthesize the BOM proof body without a dedicated source-evidence synthesis path. The next rung is generalized structured-source evidence synthesis from arrays/rows, not another SolAir-power-specific lane.

Freeze: partial; `docs/training/learned-capabilities/TOD_SOURCE_EVIDENCE_ARTIFACT_BODY_SYNTHESIS_AND_CLOSURE_LEARNED_CAPABILITY.md` records the learned capability and remaining independent-demonstration boundary.

Retirement: open.

### APP-TOD-014: MIM Dialog ACK Contract Field Projection

Borrowed From: Codex emergency repair and active response-contract coaching.

Reason: MIM can close the transport-level reply expectation and can publish an `approve` decision inside `finding_positions`, but the latest final-proof response omitted requested acknowledgement fields such as `received`, `owner`, `expected_evidence`, `blocker_state`, and `continuation_action`.

Incident: `MIM-ACK-CONTRACT-FIELD-PROJECTION-20260713`

Capability: Preserve arbitrary required acknowledgement fields from a TOD handoff request through MIM response generation, distinguish transport receipt from decision-quality ACK, and publish same-session owner/evidence/blocker/continuation fields without generic receipt fallback.

Current Apprentice: MIM with TOD as validator

Progress: `scaffolded_pass`; TOD delivered the final semantic audit proof in session `tod-mim-semantic-audit-body-final-proof-001`, observed the incomplete MIM response, and sent a corrected same-session `status_request` naming the missing fields and required repair path. Codex applied a bounded protocol-compatibility repair to `core/next_step_dialog_service.py`, deployed it to the MIM box, restarted `mim-watch-tod-dialog-inbox-consumer.service`, and TOD proved a fresh live dialog response in session `tod-mim-ack-contract-projection-proof-001` now projects `received`, `decision`, `owner`, `expected_evidence`, `blocker_state`, `continuation_action`, `blocker_class`, and `smallest_repair_step` at both envelope and payload scope. TOD then found and validated a narrower follow-on blocker where `resolution_notice` messages with `requires_reply=true` were not consumed; the generic requires-reply fallback repair closed session `tod-mim-ack-contract-projection-resolution-001` with no missing ACK fields.

Independent Demonstration: `pending`; MIM/TOD must pass a fresh analogous request where TOD derives the required ACK fields from the protocol/task context without Codex preselecting the exact field list.

Freeze: partial; see `docs/training/learned-capabilities/MIM_ACK_CONTRACT_FIELD_PROJECTION_LEARNED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-016: Existing-Bridge Remediation Materialization

Borrowed From: Codex emergency repair after active bridge audit.

Reason: MIM and TOD were already communicating through the established shared bridge, but MIM was publishing `acknowledge_and_remediate_system_alerts` as `task_class=diagnostic_only` with `validation_only=true` and `changed_files_required_for_success=false`. TOD correctly refused to treat that as executable implementation work, which left the system talking without producing a bounded repair.

Incident: `MIM-STALE-REMEDIATION-MATERIALIZATION-20260714`

Capability: Distinguish a live transport/channel problem from a request-shape problem, preserve the existing MIM/TOD bridge, and materialize code-remediation decisions as implementation-shaped `MIM_TOD_TASK_REQUEST.latest.json` packets with target file, minimal patch plan, validation plan, changed-files gate, and no new SSH/transport path.

Current Apprentice: MIM with TOD as validator

Progress: `borrowed`; Codex inspected the existing bridge artifacts and found the current authoritative request was diagnostic-only despite the remediation action. Codex tightened the TOD coordination publisher so follow-up requests demand a bounded implementation packet over the existing channel, added listener regression coverage, patched the MIM workbench `autonomy_driver_service.py` so stale-prevention pass 4 publishes a bounded implementation request when code modification is recommended, added `test_autonomy_stale_remediation_dispatch.py`, and recorded deploy payload `MIM_STALE_REMEDIATION_MATERIALIZATION_DEPLOY_PATCH_20260714T0330Z`. 2026-07-14 update: Codex inspected the live `recover_trigger_ack_bridge` wrapper and proved the existing SSH/SFTP channel was alive while the wrapper had dropped `target_file`, implementation class, and patch/validation fields. Codex added a TOD listener guard that rejects stale bridge-recovery diagnostic wrappers with `diagnostic_wrapper_missing_bounded_implementation_packet` instead of executing them, refreshed the decision artifact to `republish_existing_channel_bounded_implementation_request`, and validated `tests/TOD.PacketListenerOrdering.Tests.ps1` at 22/22 passing. 2026-07-14 follow-up: MIM then emitted a valid bounded implementation packet for `core/handoff_intake_service.py`, but replaced it with an `acknowledge_and_remediate_system_alerts` diagnostic wrapper. The running listener, still on the old policy, marked that wrapper `succeeded` while `runtime/shared/TOD_EXECUTION_RESULT.latest.json` remained `blocked_missing_bounded_edit_mode`. Codex added the second listener guard so system-alert diagnostic wrappers without `target_file` are rejected as `diagnostic_wrapper_missing_bounded_implementation_packet`, and validated `tests/TOD.PacketListenerOrdering.Tests.ps1` at 23/23 passing. Codex also repaired the local Studio mode-selection mirror so operator-impact failure prompts route through the existing conversation-mode guard before generic exploratory reasoning; focused Studio tests passed. 2026-07-14 task-class-loss correction: Codex then inspected the exact live packet and found `task_class` had been dropped, so the guard was broadened to reject diagnostic-wrapper identity plus `execute-chat-task` plus empty `target_file` even when `task_class` is blank. `tests/TOD.PacketListenerOrdering.Tests.ps1` now passes at 24/24, including the field-loss regression. 2026-07-14 local command-path correction: Codex traced the no-target wrapper into `Invoke-ExecuteChatTaskRequest` and added a second guard so diagnostic implementation/system-alert/bridge-recovery requests cannot supersede or dispatch without exactly one bounded `target_file`; `tests/TOD.IntakeArbitration.Tests.ps1` proves bounded admin repair still supersedes active MIM work while no-target diagnostic repair returns `diagnostic_repair_missing_bounded_target` and preserves the active lane. 2026-07-14 blocked-result closure correction: MIM replied to the materialization correction with a generic catchup/system-alert status and replaced the bounded `core/handoff_intake_service.py` request with a no-target `blocked-result-closure-diagnostic` packet. Codex added listener and local command-path guards for `resolve_blocked_task_result` / `blocked-result-closure-diagnostic`; `tests/TOD.PacketListenerOrdering.Tests.ps1` passes at 25/25 and `tests/TOD.IntakeArbitration.Tests.ps1` proves the closure diagnostic is blocked without displacing the active lane. The active live listener still needs to reload through the existing startup path before listener-side repair can be proven live. This is still borrowed capability, not TOD credit.

2026-07-14 source-producer diagnosis: Codex followed Dave's correction not to add another SSH channel and traced the latest no-target `blocked-result-closure-diagnostic` packet to the direct-chat task producer shape, not transport. The live packet had `source=direct_chat`, `assigned_executor=codex`, empty `target_file`, and `blocked_missing_bounded_edit_mode`. The source-side guard belongs in `tmp_remote_mim/core/routers/tod_ui.py::_publish_task_execution_request`: no-target closure diagnostics must return `diagnostic_repair_missing_bounded_target` and preserve the existing bounded request instead of writing `MIM_TOD_TASK_REQUEST.latest.json`. Current sandbox identity cannot write that mirror file (`icacls` grants BUILTIN\Users read/execute only), so Codex materialized the source-side repair as deploy packet `runtime_remote_training/deploy_payloads/MIM_DIRECT_CHAT_CLOSURE_DIAGNOSTIC_GUARD_DEPLOY_PATCH_20260714T0545Z.json` / `.md`; evidence is in `runtime_remote_training/codex_training_interventions/CODEX_MIM_TOD_EXISTING_CHANNEL_SOURCE_PRODUCER_DIAGNOSIS_20260714T0535Z.latest.json`.

Independent Demonstration: `pending`; MIM must produce a fresh live implementation-shaped request on `/home/testpilot/mim/runtime/shared/MIM_TOD_TASK_REQUEST.latest.json` for a stale/remediation case without Codex writing the packet. TOD must then inspect the target file, make or precisely block the bounded change, validate, publish evidence, and avoid proposing another channel.

Freeze: open; local workbench tests pass, but live deployment and independent MIM/TOD demonstration are not proven.

Retirement: open.

### APP-TOD-017: Blocker Policy Communication From Current Evidence

Borrowed From: Codex emergency repair after TOD operator-chat regression.

Reason: TOD answered `are you blocked TOD, do you need to escalate?` and `should you back up to a smaller task? what is your policy for blockers?` with the same stale blocked/stalled execution paragraph. The operator needed blocker-handling policy and a smaller-step decision, not another copy of the active-lane diagnostic.

Incident: `TOD-BLOCKER-POLICY-COMMUNICATION-20260715`

Capability: Detect blocker-policy intent, read current evidence, distinguish current blocker from blocker policy, back up to the smallest proof step when stalled, suppress stale binding language when the binding is already ready, and explain escalation criteria in human terms without route telemetry or canned phrase patches.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched the TOD Studio chat composer in `tmp_remote_mim/core/routers/tod_ui.py`, added focused regression coverage in `tmp_remote_mim/tests/integration/test_tod_ui_console.py`, deployed the exact files to the MIM Box, and live-smoked ports 18001 and 18021. The reply now says TOD should back up to a smaller task, names the blocker policy, names the smallest next task, gives an escalation rule, and avoids stale `local execution binding missing` wording when current binding evidence is ready.

Independent Demonstration: `pending`; TOD must answer a fresh blocker-policy question for a different blocker by inspecting current state, choosing status vs policy vs diagnostics, and publishing the smallest-step recovery recommendation without Codex changing the composer.

Freeze: partial; see `docs/training/learned-capabilities/TOD_BLOCKER_POLICY_COMMUNICATION_LEARNED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-018: Unique-Anchor Bounded Edit Materialization

Borrowed From: Codex escalation after TOD attempt.

Reason: TOD audited `tmp_remote_mim/core/routers/studio.py` for hardcoded Studio MIM responses and attempted to materialize a bounded edit for objective-progress prompts, but the `replace_text` packet used a non-unique old-text anchor: `return _studio_operator_contract_fallback_reply(prompt, page_context)`. The local engine reported completion, yet the replacement landed at the first matching fallback inside the Studio chat route, placed the new branch after an already-returned mode guard, and introduced an early fallback that made later route logic unreachable.

Incident: `STUDIO-PY-HARDCODED-RESPONSE-AUDIT-BOUNDED-EDIT-ANCHOR-COLLISION-20260715`

Capability: Before publishing a bounded edit packet, TOD must inspect the target file, prove the old text or anchor is unique in the intended scope, include surrounding context when repeated text exists, validate that the changed hunk landed at the intended location, and reject wrapper success when syntax passes but behavior is unreachable or inserted under the wrong branch.

Current Apprentice: TOD

Progress: `scaffolded_positive`; TOD produced the original source-anchor audit artifacts and attempted the bounded edit through the local execution lane. Codex then inspected the diff, found the anchor collision, removed the misplaced branch, reinserted the objective-progress branch immediately before the true final fallback, and validated `python -m py_compile tmp_remote_mim/core/routers/studio.py`. 2026-07-15 follow-up: on fresh fixture `tod/out/tests/app-tod-018-unique-anchor-fresh/target_config.py`, TOD completed the scaffolded sequence `TSK-APP-TOD-018-OBSERVE2` -> `TSK-APP-TOD-018-SYNTHESIZE` -> `TSK-APP-TOD-018-APPLY`: it published a beta-only source-anchor artifact, synthesized a ready exact old_text/new_text packet, applied the packet through LocalExecutionEngine, and validated `python -m py_compile` plus structural checks proving `tod_unique_anchor` exists only in beta. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/APP_TOD_018_UNIQUE_ANCHOR_FRESH_POSITIVE_RESULT.latest.json`. 2026-07-15 real-lane follow-up: TOD proved the default `execute-chat-task` smoke artifact at `runtime_remote_training/learned_capabilities/TOD_EXECUTE_CHAT_TASK_ASYNC_DEFAULT_RESMOKE_20260715.live_smoke.json`, then correctly backed down from overbroad `TSK-0029` to current-code source-anchor tasks `TSK-0027` and `TSK-0028`; both passed and wrote fresh anchor artifacts. Retried `TSK-0029` still blocked because no packet artifact was synthesized. Evidence: `runtime_remote_training/tod_independent_resolution_attempts/APP_TOD_018_REAL_PACKET_SYNTHESIS_BLOCKER.latest.json`.

Independent Demonstration: `blocked`; TOD now has a positive sub-skill result on current-code source-anchor recovery, but the independent demonstration is blocked at packet-body synthesis. TOD must produce a single-output packet artifact from the fresh anchors with non-empty current `old_text`, different `new_text`, validation command, rollback, closure evidence, and prevention lesson before it can attempt the less-artificial edit without Codex selecting packet fields.

Freeze: partial; see `docs/training/learned-capabilities/TOD_UNIQUE_ANCHOR_BOUNDED_EDIT_MATERIALIZATION_LEARNED_CAPABILITY.md`.

Retirement: open.

### APP-TOD-019: AgentMIM Production Repair Assimilation

Borrowed From: Codex emergency repair during fast AgentMIM production stabilization.

Reason: Dave needed production-facing AgentMIM fixes completed quickly across quotes, client identity merge, commission upload/audit, and MIM side-assistant repair paths. Codex performed the implementation work directly in `E:\comm_app` to keep the product moving. Under `CODEX.md`, this is borrowed capability, not TOD progress, until TOD can inspect the committed repairs, reconstruct the failure classes, and complete a fresh analogous repair without Codex authoring the patch.

Incident: `AGENTMIM-FAST-STABILIZATION-20260715`

Capability: Audit an AgentMIM user-visible failure from screenshots/chat symptoms, locate the real route/model/template/parser path, make the smallest behavior-changing repair, validate with focused tests and/or real-file smoke data, preserve unrelated dirty work, commit only intended hunks, and report evidence in human terms.

Current Apprentice: TOD

Progress: `borrowed`; Codex pushed the current AgentMIM repair stack, including quote workbook cleanup/enrollment accuracy, quote cover profile-data requirements, client identity merge/policy preservation, MIM client-assignment repair audit, and upload-audit missing-commission-gap visibility. Current `E:\comm_app` pushed commits include `1d7af560`, `cb81cd79`, `1ac242a8`, `4438fd5e`, `72c10938`, and `c881916f`. This stabilized the app but does not prove TOD can manage this class of work.

Independent Demonstration: `pending`; TOD must choose one fresh AgentMIM issue from current evidence, inspect the relevant `E:\comm_app` files, produce a bounded repair plan, change real application behavior, run focused validation, and publish evidence without Codex selecting the final hunk or writing the patch.

Freeze: open; the pushed `E:\comm_app` commits are a production freeze point, but the TOD workspace remains dirty and the borrowed capability has not been assimilated.

Retirement: open.

### APP-TOD-020: Terminal Lane Projection And Supersession Hygiene

Borrowed From: Codex emergency control-plane repair during TOD workspace freeze/training cleanup.

Reason: TOD completed `TSK-0068` and `TSK-0069`, but the shared latest artifacts regressed to showing `TSK-0068` as active/blocked while the canonical active execution lane and local execution artifacts showed `TSK-0069` completed. A later operator objective superseded `TSK-0069`, but the visible latest surfaces did not reconcile that terminal/superseded truth.

Incident: `TOD-TERMINAL-LANE-PROJECTION-20260715`

Capability: When the active execution lane reaches a terminal state and no eligible queued successor is promoted, TOD must project that terminal state to `TOD_ACTIVE_TASK.latest.json`, `TOD_ACTIVE_OBJECTIVE.latest.json`, `TOD_EXECUTION_RESULT.latest.json`, `TOD_VALIDATION_RESULT.latest.json`, and `TOD_EXECUTION_TRUTH.latest.json`; stale selected-for-dispatch payloads for the same terminal task must be blocked instead of becoming visible truth.

Current Apprentice: TOD

Progress: `borrowed`; Codex added a terminal active-lane projection helper in `scripts/TOD.ps1`, invoked it from the no-eligible-queued-task drain path, tightened the latest-artifact publish gate so a terminal canonical task cannot be reselected for dispatch, and validated the repair with `PSParser`, `repair-missing-active-lane`, and artifact readback. Current shared latest artifacts now show `TSK-0069` as `completed` / validation `passed` instead of stale `TSK-0068` active/blocked.

Independent Demonstration: `pending`; TOD must encounter a fresh completed-or-superseded active lane, detect stale latest projection without Codex, reconcile it through the canonical lane/queue truth, and publish evidence that no stale active task remains visible.

Freeze: partial; the current workspace is safer to inspect because the latest TOD surfaces match the canonical terminal lane, but this was still Codex-authored control-plane repair.

Retirement: open.

## Active Continuation

Current Dave-away priority overlay:

1. Prove `APP-TOD-016` live: MIM must emit a fresh implementation-shaped request on the existing shared bridge, and TOD must execute or precisely block it with inspected evidence.
2. Continue generalized structured-source evidence synthesis from array/row artifacts.
3. Do not award TOD independent-resolution credit for Codex-authored bridge/materialization repairs; credit starts only after TOD owns the inspect-change-validate-close loop on a fresh task.

Train generalized structured-source evidence synthesis from array/row artifacts.

Current sharp blocker: TOD can synthesize the scaffolded SolAir power-curve proof, but cannot yet inspect a different structured evidence artifact such as `runtime/shared/SOLAIR_PARTS_BOM_OBSERVATION.latest.json`, discover row groups, choose representative evidence, and assemble the required proof body without a dedicated lane.

### APP-TOD-021: Missing Objective Prompt Packaging Recovery

Borrowed From: Codex emergency control-plane repair.

Reason: TOD had a synchronized active task whose local task record already contained a materialization blocker (`blocked_missing_bounded_edit_mode`, missing `target_file`), but `run-task` could not reach that blocker because no packaged prompt existed. The normal `package-task` action also failed because the task's `objective_id` did not exist in the local objective table.

Incident: `TOD-MIM-SYNCED-TASK-MISSING-OBJECTIVE-PACKAGE-20260716`

Capability: When a MIM-synced task exists without a local objective row, TOD should still be able to package the task from task-local context, preserve the missing-objective fact as evidence, and then let `run-task` publish the real execution blocker instead of crashing before classification.

Current Apprentice: TOD

Progress: `borrowed`; Codex patched `scripts/TOD.ps1` so `package-task` creates a minimal recovered objective context only for packaging when the objective row is missing, and records `objective_record_recovered` in the package journal payload. This does not solve the task or infer missing bounded-edit fields; it only restores TOD's ability to classify the existing malformed packet.

Independent Demonstration: `pending`; TOD must encounter a fresh MIM-synced task with missing local objective context, package it without Codex, publish the real blocker or corrected execution path, and prove the active lane is not mutated by an unexecutable task.

Freeze: open; requires focused validation plus a fresh analogous TOD-owned demonstration.

Retirement: open.

### APP-TOD-022: Packet Formation Artifact Materialization Recovery

Borrowed From: Codex emergency control-plane repair.

Reason: TOD created a packet-formation task to publish a current-code packet candidate or precise blocker, but the local executor treated it as a generic `artifact_write` and blocked because no literal `New Text` payload was present. The existing `New-LocalExecutionPacketCandidateArtifact` capability could already inspect the prompt/current code and build the packet/blocker artifact, but it was orphaned from the artifact-write execution path.

Incident: `TOD-PACKET-FORMATION-ARTIFACT-WRITE-20260716`

Capability: When TOD selects a `packet_formation` artifact target, the local executor should materialize the packet/blocker artifact from inspected current code instead of requiring TOD to pre-render JSON as `New Text`.

Current Apprentice: TOD

Progress: `borrowed`; Codex reconnected packet-formation artifact writes in `scripts/engines/LocalExecutionEngine.ps1` so `TOD_PACKET_FORMATION_*` targets call the existing packet-candidate artifact builder when no explicit `New Text` is provided. This restores TOD's ability to publish packet/blocker evidence, but it is still control-plane repair, not an independent TOD implementation.

Follow-up: Codex also added `closure_evidence` to generated packet candidates after the live selector rejected a newly generated packet for missing that field. Direct validation proved a packet-formation smoke now publishes `packet_candidate_ready=true` with `closure_evidence` present.

Independent Demonstration: `pending`; TOD must rerun the packet-formation task, publish a `packet_candidate_ready` or precise inspected blocker artifact through the local executor, then use that evidence to select or block the next real behavior-changing task without Codex writing the patch.

Freeze: open; requires focused local-engine validation and a live TOD retry.

Retirement: open.

### APP-TOD-025: Enterprise Foundation Minimal Remote Deployment Pattern

Borrowed From: Codex emergency/product-continuation bridge.

Reason: The Enterprise Foundation shell needed to reach the MIM Box, but the local `tmp_remote_mim` mirror was ignored and dirty, `models.py` contained unrelated research-model changes, and remote hashes differed from local files. Whole-file copy would have risked dragging unrelated mirror edits into production.

Incident: `ENT-001-ENTERPRISE-DATABASE-FOUNDATION-DEPLOY-20260717`

Capability: When deploying MIM Box changes from a dirty ignored mirror, TOD must inspect local intended changes and remote anchors, avoid whole-file upload of dirty shared files, apply only minimal idempotent patches, validate with the remote app virtualenv, restart only after compile/import tests pass, run live smoke tests, and record whether the capability is borrowed or independently demonstrated.

Current Apprentice: TOD

Progress: `borrowed`; Codex deployed the Enterprise model, schemas, service, router, router registration, `/observatory/enterprise` shell, and `ent_demo` / `mimtod` login path through a minimal remote patch approach. Live smoke passed and evidence was recorded in `runtime_remote_training/tod_independent_resolution_attempts/ENT_001_ENTERPRISE_DATABASE_FOUNDATION_PROGRESS.latest.json`.

Proficiency: `observed`; TOD has evidence of the Enterprise deployment pattern and a capability freeze, but has not yet reproduced the pattern independently.

Independent Demonstration: `pending`; TOD must complete `TOD-ENTERPRISE-PATTERN-ASSIMILATION-V1` by inspecting the Enterprise implementation, identifying the deployment pattern, creating one harmless bounded addition, deploying it independently, validating remote compile/import/live smoke, and publishing evidence without Codex-written deployment packets or manual bridge edits.

Freeze: partial; `docs/training/learned-capabilities/ENT_001_CAPABILITY_FREEZE.latest.md` records the architecture, deployed evidence, deployment pattern, and reuse triggers. Retirement remains blocked until TOD repeats the pattern independently.

Retirement: open.
