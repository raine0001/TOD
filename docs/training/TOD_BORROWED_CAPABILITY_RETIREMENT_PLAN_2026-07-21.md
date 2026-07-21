# TOD Borrowed Capability Retirement Plan - 2026-07-21

## Mission

Reduce TOD's borrowed-capability ratio by training capability families, not isolated incidents. Each borrowed registry entry remains open until TOD proves the relevant capability on a fresh analogous case with evidence.

Current baseline:

- Registry entries: 36
- Borrowed or unknown: 35
- Independent: 1
- Retired: 0
- Borrowed capability ratio: 97.2%
- Independent ratio: 2.8%
- Registry integrity issue: duplicate apprenticeship IDs exist and must be cleaned before per-entry retirement math can be fully trusted.

## Training Strategy

Many registry entries are symptoms of the same missing skills. Retiring them one at a time would create busywork. The training cycle should group related entries into shared drills where one proof can advance multiple debts, as long as the proof is fresh and the capability truly generalizes.

## Priority Families

## Registry Integrity Training Debt

The current registry contains duplicate IDs with different capability names. This must be treated as evidence hygiene debt, not ignored.

Known duplicate IDs from current parsing:

- `APP-TOD-011`
- `APP-TOD-012`

Training requirement:

- Preserve every duplicate entry during grouping.
- Assign unique IDs before retiring any affected debt.
- Never allow a scorecard parser to collapse separate debts because they reused an ID.

Proof artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_APPRENTICESHIP_REGISTRY_ID_INTEGRITY_PROOF.latest.json`

### Priority 1: Read-Only Assessment And Authority Classification

Why first:

TOD already has momentum here. `APP-TOD-034` is `independent_demo_passed`, so the fastest way to reduce borrowed debt is to reuse that proven lane against adjacent read-only and authority-classification debts.

Registry entries:

- `APP-TOD-034`: Patch Evidence Ingestion For Read-Only Audits
- `APP-TOD-033`: Direct Chat Read-Only Task Mode Preservation
- `APP-TOD-032`: Route Experiment Authority Classification
- `APP-TOD-012`: Read-Only Audit Extraction For Artifact-Write Blockers

Training proof:

- TOD receives one fresh read-only route/authority/audit target.
- TOD classifies task mode without requiring bounded edit fields.
- TOD inspects the target evidence.
- TOD publishes a structured artifact.
- TOD does not modify product source.
- TOD validates that malformed edit packets are still rejected.

Pass artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_READ_ONLY_AUTHORITY_CLASSIFICATION_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Move `APP-TOD-033`, `APP-TOD-032`, and `APP-TOD-012` toward `independent_demo_passed`.
- Keep `APP-TOD-034` open until one more future fresh pass proves reliability.

### Priority 2: Current-Code Bounded Packet Materialization

Why second:

This is the largest independence blocker. Until TOD can inspect current code and synthesize a valid old/new or anchor/snippet packet, Codex remains the real implementer for many tasks.

Registry entries:

- `APP-TOD-031`: Fresh Target Packet Loop Materialization
- `APP-TOD-018`: Unique-Anchor Bounded Edit Materialization
- `APP-TOD-021`: Missing Objective Prompt Packaging Recovery
- `APP-TOD-022`: Packet Formation Artifact Materialization Recovery
- `APP-TOD-016`: Existing-Bridge Remediation Materialization

Training proof:

- TOD selects one harmless current-code target.
- TOD inspects the file.
- TOD identifies one unique anchor.
- TOD writes a bounded packet with target file, edit mode, old text or anchor, new text or snippet, validation command, rollback note, and prevention lesson.
- TOD applies the packet.
- TOD validates the exact changed behavior.
- TOD cleans up or leaves the intended change with evidence.

Pass artifact:

- `runtime_remote_training/tod_independent_resolution_attempts/TOD_CURRENT_CODE_PACKET_MATERIALIZATION_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Move packet-materialization debts from borrowed/scaffolded toward independent demonstration.

### Priority 3: Recovery That Produces Executable Retry Shape

Why third:

TOD can often say why it is blocked. It still struggles to turn the diagnosis into the next executable attempt.

Registry entries:

- `APP-TOD-011`: Executor Binding Blocker Self-Recovery
- `APP-TOD-023`: Optional Selection Source Field StrictMode Recovery
- `APP-TOD-004`: Self-Evolution Schema Drift Recovery
- `APP-TOD-020`: Terminal Lane Projection And Supersession Hygiene

Training proof:

- TOD receives or discovers a real blocker.
- TOD classifies the blocker.
- TOD identifies the exact missing requirement.
- TOD produces a corrected retry payload or a smaller diagnostic step.
- TOD validates that the blocker condition changed.
- TOD resumes the original objective or records the remaining external dependency.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_EXECUTABLE_RECOVERY_SHAPE_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Improve recovery quality, blocker honesty, and autonomous recovery rate.

### Priority 4: Response Authority And MIM Cognition Boundary

Why fourth:

These are high-impact but more dangerous. They touch MIM's public behavior, so TOD should not attempt them until read-only classification and bounded packet materialization are stable.

Registry entries:

- `APP-TOD-001`: Cross-Surface Conversation Purpose Routing
- `APP-TOD-006`: Studio Active Context Transition Routing
- `APP-TOD-007`: Self-Evolution Status Reporting Before Generic Exploration
- `APP-TOD-010`: Hardcoded MIM Answer Detection And Replacement
- `APP-TOD-024`: Research Observatory Conversation Evolution Routing
- `APP-TOD-027`: Public Homepage Structured Reply Rendering Boundary
- `APP-TOD-028`: Public Enterprise Product Question Routing
- `APP-TOD-029`: Observatory Service Knowledge Product Context Certification

Training proof:

- TOD audits one response-authority path.
- TOD identifies whether it is process support or prohibited final-answer authority.
- TOD proposes a service-level or instrumentation repair, not a phrase route.
- TOD validates cognitive interpretation, composed response, and final visible response remain aligned.

Pass artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_RESPONSE_AUTHORITY_BOUNDARY_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Reduce MIM hardcoded route debt without making more hardcoded routes.

### Priority 5: Evidence-Derived Research And Product Answers

Why fifth:

MIM must derive answers from inspected evidence instead of static text. This is central to Observatory and Enterprise product mastery.

Registry entries:

- `APP-TOD-002`: Evidence-Derived Numeric Research Answer
- `APP-TOD-013`: Semantic Source-Audit Body Synthesis From Source Anchors
- `APP-TOD-015`: Source-Evidence Artifact Body Synthesis and Closure
- `APP-TOD-029`: Observatory Service Knowledge Product Context Certification

Training proof:

- TOD selects one evidence-backed question.
- TOD locates source evidence.
- TOD extracts the relevant fields.
- TOD distinguishes fact, inference, estimate, and missing evidence.
- TOD publishes a derived answer artifact and validation.

Pass artifact:

- `runtime_remote_training/read_only_audit_artifacts/TOD_EVIDENCE_DERIVED_ANSWER_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Strengthens Auditor, Observatory, and Enterprise product mastery.

### Priority 6: MIM/TOD Coordination Contract And Status Truth

Why sixth:

TOD and MIM still drift between chat claims, hourly summaries, active lanes, and execution evidence. This family makes the system explain what is actually happening.

Registry entries:

- `APP-TOD-005`: Dialog Response Contract Projection And Focus-Review Derivation
- `APP-TOD-014`: MIM Dialog ACK Contract Field Projection
- `APP-TOD-017`: Blocker Policy Communication From Current Evidence
- `APP-TOD-020`: Terminal Lane Projection And Supersession Hygiene
- `APP-TOD-011`: Response Contract Envelope Scope Repair

Training proof:

- TOD publishes a blocker.
- MIM acknowledges it.
- Ownership, next action, evidence, and wait-state become visible.
- Stale artifacts do not override live execution truth.
- Status surfaces show one coherent plain-language state.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_COORDINATION_STATUS_TRUTH_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Directly improves Dave's ability to work with MIM and TOD.

### Priority 7: Cross-Service Live Verification And Deployment Pattern

Why seventh:

These skills are operationally important but should wait until TOD can classify, materialize, and recover with less Codex support.

Registry entries:

- `APP-TOD-009`: Cross-Service Live Surface Verification And Serving-Lane Restart
- `APP-TOD-025`: Enterprise Foundation Minimal Remote Deployment Pattern

Training proof:

- TOD selects a harmless live surface.
- TOD inspects local and remote anchors.
- TOD applies minimal idempotent change or read-only verification.
- TOD validates local, remote, and user-visible behavior.
- TOD records rollback and deployment evidence.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_DEPLOYMENT_PATTERN_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Moves Enterprise deployment from borrowed toward guided or independent.

### Priority 8: AgentMIM Production Assimilation

Why eighth:

AgentMIM matters, but it has many product-specific moving parts. TOD should first improve general packet, recovery, and evidence skills, then apply those to AgentMIM.

Registry entries:

- `APP-TOD-019`: AgentMIM Production Repair Assimilation
- `APP-TOD-026`: AgentMIM Deterministic App-Data Answer Before LLM Fallback
- `APP-TOD-030`: AgentMIM Visible Page-Context Fast Path Before Generic Chat
- `APP-TOD-012`: AgentMIM Carrier Commission Parser Contract Repair

Training proof:

- TOD inspects one AgentMIM production fix already made by Codex.
- TOD reconstructs the failure class.
- TOD selects a fresh analogous defect.
- TOD fixes it with validation and no Codex patch authorship.

Pass artifact:

- `runtime_remote_training/tod_result_artifacts/TOD_AGENTMIM_ASSIMILATION_RETIREMENT_PROOF.latest.json`

Potential retirement effect:

- Converts recent production repair debt into reusable TOD skill.

## 12-Hour Execution Order

1. Run Priority 1 to move adjacent read-only/authority debts toward independent demonstration.
2. Run Priority 2 until TOD passes one current-code bounded packet proof.
3. Run Priority 3 against the next real blocker that appears.
4. If the first three pass, run Priority 6 because communication/status truth affects every later objective.
5. If time remains, begin Priority 4 as read-only audit only.

Do not spend the 12-hour cycle on broad product building until packet materialization and recovery are stronger.

## Proof Rules

Every training proof must include:

- unique objective id
- inspected files or evidence artifacts
- changed files or meaningful artifact write
- validation command
- validation result
- rollback note
- prevention lesson
- borrowed-capability registry entries affected
- whether the pass was independent, guided, scaffolded, or borrowed
- no wrapper-only completion

## Automatic Next Objective

`TOD-BORROWED-CAPABILITY-RETIREMENT-CYCLE-V1`

Mission:

TOD reduces borrowed capability ratio by executing the priority families above, starting with read-only assessment and authority classification, then current-code bounded packet materialization.

First task:

`TOD-READONLY-AUTHORITY-CLASSIFICATION-RETIREMENT-PROOF-V1`

Acceptance:

TOD independently performs a fresh read-only authority classification without source-code mutation, publishes evidence, validates the artifact, and identifies which apprenticeship entries can advance.
