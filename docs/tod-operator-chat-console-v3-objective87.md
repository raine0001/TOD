# TOD Operator Chat Console v3

## Objective 87

Objective 87 starts the Operator + System Co-Decision Loop on top of Objective 84 reasoning, Objective 85 explanation, and Objective 86 governed preview or confirm control.

The first slice was intentionally small:

- system proposes a bounded action through the existing governed preview path
- TOD explains the policy and evidence through a durable reasoning bundle
- operator commits to that proposal before execution when needed
- the system adapts by surfacing the active commitment and biasing recommendations toward honoring or explicitly clearing it

The next hardening slice expands that contract so commitments can stay durable without becoming sticky forever.

## Initial Contract

Artifacts:

- `shared_state/tod_operator_chat_commitment.log.jsonl`
- `shared_state/tod_operator_chat_commitment.latest.json`

Endpoint:

- `POST /api/operator-chat-commitment`
- `GET /api/operator-chat-commitments?limit=N`

Current states:

- `committed`
- `timeboxed`
- `until_evidence_change`
- `cleared`
- `satisfied`
- `abandoned`

Additional fields now captured on commitment records:

- `release_condition`
- optional `duration_minutes`
- optional `expires_at`
- `evidence_fingerprint`
- `evidence_snapshot`
- derived `lifecycle_status`
- derived `revalidation_required`
- derived `evidence_delta_count`
- derived `evidence_deltas`

Additional derived terminalization fields now project how a commitment actually resolves even when the raw stored state was only an earlier active record:

- `is_terminal`
- `terminal_state`
  - `satisfied`
  - `abandoned`
  - `superseded`
  - `ineffective` when repeated abandoned terminal outcomes show the latest action pattern is no longer a good fit
- `terminal_detail`
- optional `terminal_successor_commitment_id` when a newer decision superseded an earlier one

Each commitment links to:

- `preview_id`
- `reasoning_bundle_id`
- action id and label
- operator id
- objective scope

## Intended Behavior

Objective 87 does not replace Objective 86 execution gates.

Instead, it inserts a durable decision record between proposal and execution so TOD can preserve shared operator intent across subsequent questions and refreshes.

Current adaptation behavior:

- active `committed` commitments suppress duplicate action churn until manually cleared
- active `timeboxed` commitments suppress churn but surface expiring-state warnings and revalidation prompts near expiry
- `until_evidence_change` commitments stay active only while the live evidence fingerprint still matches the commitment baseline
- `satisfied` commitments close the current decision loop and push TOD toward a bounded refresh before selecting the next action
- `abandoned` commitments close the current decision loop and push TOD toward re-grounding on fresh status before pivoting
- earlier non-terminal commitment rows are now projected as `superseded` once a newer commitment decision for the same bounded objective replaces them, so older commitments stop lingering as quasi-active background objects
- the most recent abandoned terminal row for an action can be projected as `ineffective` when repeated abandoned outcomes for the same action pattern outweigh successful reuse, which pushes TOD toward a governance refresh instead of retrying the same pattern immediately
- expired or evidence-changed commitments no longer suppress action selection and instead bias TOD toward a bounded revalidation step before recommitting
- warning and cadence explanations now treat active commitments as first-order operator constraints instead of burying them only in limitations

## Trust-Chain Inspector

Objective 87 now also depends on a compact trust-chain inspector in the dashboard.

Endpoint:

- `GET /api/operator-chat-action-trust-chain`

Supported lookup keys:

- `audit_id`
- `preview_id`
- `bundle_id`
- `commitment_id`
- optional `comparison_objective_id` for bounded alternate-objective validation
- optional `validation_mode=synthetic_drift` for explicit validation-only delta proving when only one live objective is available

The inspector returns the resolved audit entry, linked reasoning bundle, linked commitment records, the structured evidence set, and any evidence deltas between a commitment baseline and the current live posture so the operator can inspect the full chain in one place.

The current dashboard slice adds:

- inline commitment controls to mark active commitments as `satisfied` or `abandoned`
- trust-chain delta counts plus per-field before or after drilldown rows for evidence-bound commitments
- sweep coverage for the terminal outcomes and the new trust-chain evidence-delta fields

## Build b22 Expansion

Build `2026.03.24-b22` adds three practical Objective 87 refinements:

- commitment rows now surface recent terminal outcome history so operators can see whether an action was recently satisfied or abandoned before recommitting
- recommended bounded actions now carry lightweight outcome-aware ranking so repeated abandoned actions are demoted and recently satisfied actions are modestly favored
- the trust-chain endpoint and sweep now support deterministic evidence-delta validation through either a bounded `comparison_objective_id` or explicit `validation_mode=synthetic_drift`, with the validation mode clearly labeled as synthetic rather than live drift

The synthetic drift mode exists only to prove the evidence-delta plumbing end to end when the live host exposes just one objective. It changes the rendered trust-chain evidence posture for validation and does not mutate TOD state.

## Build b23 Expansion

Build `2026.03.24-b23` tightens those same seams rather than starting a new surface:

- commitment rows now expose trust-chain provenance before inspection, so the operator can see whether delta proving is currently `live compare` or `validation only`
- the trust-chain endpoint now auto-selects a bounded alternate live objective for evidence comparison when one is available, instead of requiring the caller to pass `comparison_objective_id` manually
- outcome learning now uses a weighted fitness score over repeated satisfied or abandoned terminal outcomes, with extra weight for same-intent history rather than only raw action-level counts

On single-objective hosts, the provenance badge should read `validation only`; on multi-objective hosts, the same row should upgrade naturally to `live compare <objective>`.

## Build b24 Expansion

Build `2026.03.24-b24` makes that live-compare path deterministic instead of ambient:

- `GET /api/project-status`, `GET /api/operator-chat-commitments`, and `GET /api/operator-chat-action-trust-chain` now accept `validation_harness=multi_objective_compare`, which injects one bounded alternate objective posture for validation without mutating TOD state
- the live sweep now binds itself to the resolved objective, requests the bounded harness explicitly, and verifies that provenance upgrades from `validation only` to `live compare` on the current single-objective host
- suggested operator actions now surface weighted fitness directly in the action rendering rather than hiding it only inside commitment metadata or trust-chain inspection

Live validation on port `8844` confirmed `b24`, preserved full governed-action coverage, and showed the harnessed commitment provenance source as `live_objective` with comparison objective `validation-live-compare`.

One known residual remains: the evidence-bound lifecycle evaluator can still fall back to static comparison on some paths, so the harness currently proves `live compare` provenance deterministically but does not yet force a positive live delta count the way `validation_mode=synthetic_drift` does.

## Build b25 Expansion

Build `2026.03.24-b25` hardens the compare path instead of widening scope:

- evidence-bound commitment entries now get a post-payload repair pass that recomputes current evidence snapshots, fingerprints, deltas, and lifecycle state even when a lower-level fallback path was taken during commitment evaluation
- bounded comparison support now includes dedicated profiles for bridge, cadence, and objective-status validation rather than only the original `multi_objective_compare` harness
- suggested actions now use weighted ranking from both terminal commitment outcomes and explicit operator feedback, with the dashboard surfacing history score, feedback score, and a short ranking explanation inline
- the dashboard can propagate `validation_harness` through project status, commitments, trust-chain, and operator-chat requests, and trust-chain inspection now renders the active harness label when compare mode is active
- a lightweight operator feedback loop is now available through `POST /api/operator-chat-feedback` and `GET /api/operator-chat-feedback`, which gives Objective 87 a bounded learning signal without bypassing Objective 86 governance
- the live sweep now splits stable contract checks from experimental compare checks, validates the feedback endpoint, and exercises all bounded comparison profiles
- repo-local restart and regression tooling now include `scripts/Restart-TODUIHost.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`

The remaining compare goal after `b25` is narrower: prove a reliably positive live delta under the repaired compare path on the real bounded harness, not just prove provenance and field availability.

Follow-up live validation on 2026-03-25 closed that residual on `http://localhost:8844/` without widening the surface area:

- evidence-bound commitment comparison now produces a non-null bounded live-compare snapshot instead of falling back to static evaluation
- the live `multi_objective_compare` harness now returns `comparison_source=live_objective` with `evidence_delta_count=10`
- focused regression coverage now requires both a non-null current evidence snapshot and a positive evidence delta for the harnessed commitments and trust-chain routes

Follow-up Objective 87 work on 2026-03-25 then completed the next bounded expansion from the list below without adding a parallel control plane:

- `GET /api/project-status` now exposes a shaped `mim_proposal` payload sourced from the live listener task-request packet when one is present
- `POST /api/operator-chat` now adds proposal-aware evidence, summary text, and proposal-tagged suggested action metadata while preserving Objective 86 preview and commitment governance
- the dashboard reuses existing suggested-action and action-live-status surfaces to render the ingested MIM proposal rather than introducing a separate proposal-only panel
- focused live regression coverage now includes `tests/TOD.OperatorChatMimProposal.Tests.ps1` alongside the existing commitments and trust-chain checks

The next bounded Objective 87 expansion on 2026-03-25 completed the first explicit MIM vs TOD proposal-conflict slice:

- `GET /api/project-status` now exposes `mim_proposal_conflict`, which compares the live MIM proposal objective against TOD's selected objective plus bridge and canonical MIM export posture
- `POST /api/operator-chat` now surfaces proposal-conflict evidence, summary text, and `mim_proposal_conflict_detected` response flags so conflict posture is visible through the existing governed chat contract
- suggested-action ranking now preserves proposal-aware action variants when duplicate action ids collide with generic recommendation or commitment-inserted rows, so MIM metadata survives the final top-action collapse
- the dashboard reuses existing suggested-action metadata, live-status text, and response-flag rendering to show conflict or alignment without adding a separate proposal arbitration surface
- focused live validation on port `8844` passed across `tests/TOD.OperatorChatMimProposal.Tests.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`

The next bounded Objective 87 expansion on 2026-03-25 completed the first explicit proposal-arbitration slice without opening a second decision plane:

- `GET /api/project-status` now exposes `mim_proposal_arbitration`, which converts proposal-conflict posture into a bounded winner, status, summary, recommended posture, and recommended action
- `POST /api/operator-chat` now surfaces proposal-arbitration evidence plus `mim_proposal_arbitrated`, `mim_proposal_tod_priority`, and `mim_proposal_shared_priority` flags so the operator can see whether TOD currently holds priority or treats the live MIM proposal as aligned context
- suggested-action ranking now includes a small arbitration bias on top of commitment history and operator feedback, so aligned MIM-tagged actions rise modestly and conflict states keep TOD-first refresh actions ahead without bypassing governed preview or commitment controls
- the dashboard reuses existing action-live-status, suggested-action metadata, citation, and response-flag rendering to show arbitration winner and summary inline
- focused live validation on port `8844` again passed across `tests/TOD.OperatorChatMimProposal.Tests.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`

The next bounded Objective 87 expansion on 2026-03-25 completed the first explicit proposal-merge-policy slice on top of arbitration:

- `GET /api/project-status` now exposes `mim_proposal_merge_policy`, which derives a bounded merge status, mode, summary, and recommended action from proposal conflict plus arbitration posture
- `POST /api/operator-chat` now surfaces merge-policy evidence plus `mim_proposal_merge_policy_available`, `mim_proposal_merge_ready`, and `mim_proposal_merge_deferred` flags so the operator can see whether the live MIM proposal should be merged as context or kept separate pending revalidation
- MIM-tagged suggested actions now carry merge-policy metadata alongside proposal, conflict, and arbitration metadata so the existing suggested-action surface can explain not just what the proposal is, but whether TOD is currently willing to merge it into the active objective posture
- the dashboard reuses existing action-live-status, suggested-action metadata, citations, and response flags to show merge policy inline
- focused live validation on port `8844` again passed across `tests/TOD.OperatorChatMimProposal.Tests.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`

The next bounded Objective 87 expansion on 2026-03-25 completed commitment-scoping hardening so active commitments stop steering decisions after scope drift:

- `POST /api/operator-chat-commitment` now persists validation-harness and proposal-scope identity on new commitment records, and `GET /api/operator-chat-commitments` now evaluates each record against the live objective, bounded harness, and proposal merge posture
- active commitment lookup now filters out commitments whose objective, validation harness, or proposal merge posture drifted out of scope, while operator-chat surfaces bounded scope-shift evidence through the existing governed response contract
- the dashboard reuses the existing commitments list and response-flag rendering to show `scope_status`, `scope_summary`, and the new `operator_commitment_scope_shifted` posture without adding a separate commitment-scope control plane
- focused live validation on port `8844` passed across `tests/TOD.OperatorChatMimProposal.Tests.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`, including a new live commitment write proving `validation_harness=multi_objective_compare` persists as in-scope commitment metadata

The next bounded Objective 87 expansion on 2026-03-25 completed explicit proposal acknowledgment on top of proposal merge policy:

- `GET /api/project-status` now exposes `mim_proposal_acknowledgment`, which derives a bounded acknowledgment status, disposition, summary, and recommended action from the live proposal, conflict posture, arbitration, and merge policy
- `POST /api/operator-chat` now surfaces proposal-acknowledgment evidence plus `mim_proposal_acknowledged`, `mim_proposal_absorbed`, `mim_proposal_ack_deferred`, and `mim_proposal_rejected` flags so the operator can tell whether TOD is absorbing, deferring, or rejecting the live MIM posture
- MIM-tagged suggested actions now carry proposal-acknowledgment metadata alongside proposal, conflict, arbitration, and merge policy metadata so the existing suggestion surface can explain how TOD is currently handling the proposal
- the dashboard reuses the existing action-live-status, suggested-action metadata, citations, and response flags to show acknowledgment inline without introducing a separate proposal-closure panel
- focused live validation on port `8844` again passed across `tests/TOD.OperatorChatMimProposal.Tests.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`

The next bounded Objective 87 expansion on 2026-03-25 completed proposal closure, closure-aware commitment scoping, lifecycle projection, and repeated-outcome learning without adding a parallel store:

- `GET /api/project-status` now exposes `mim_proposal_closure`, which derives open, fulfilled, abandoned, superseded, or withdrawn proposal lifecycle status from existing governed audit and commitment history
- `POST /api/operator-chat-action` now carries proposal identity through preview and audit records, and `POST /api/operator-chat-commitment` persists that proposal identity on commitment rows so proposal-linked outcomes can be recovered later without inventing a second control plane
- commitment scope evaluation now includes `proposal_id` in addition to objective, validation harness, and proposal merge posture, so an older proposal cannot keep steering the operator loop after a newer live proposal supersedes it
- governed action ranking now adds proposal-outcome learning on top of terminal commitment history, operator feedback, and arbitration bias, favoring repeated absorbed-and-satisfied proposal outcomes and demoting repeated abandoned ones
- the dashboard reuses the existing action-live-status, suggested-action metadata, governed audit list, commitments list, and trust-chain inspector to show closure and lifecycle state inline rather than adding a new proposal panel
- focused live regression coverage now checks `mim_proposal_closure`, proposal-backed audit projection, proposal-id commitment scope metadata, and trust-chain lifecycle projection across `tests/TOD.OperatorChatMimProposal.Tests.ps1`, `tests/TOD.OperatorChatCommitments.Tests.ps1`, and `tests/TOD.OperatorChatTrustChain.Tests.ps1`

The next hardening pass on 2026-03-25 tightened operational validation rather than widening the decision surface:

- bridge status now exposes explicit diagnostics for freshness classification, freshness threshold, sequence completeness, artifact completeness, and missing bridge artifacts so operators can distinguish startup lag from true stale-listener conditions
- `POST /api/operator-chat` with `intent=explain_bridge_status` now emits those bridge diagnostics as structured evidence and citations instead of leaving them available only in raw project-status payloads
- focused live validation now includes `tests/TOD.BridgeStatus.Tests.ps1` and a broader lifecycle smoke path in `tests/TOD.OperatorChatLifecycleRegression.Tests.ps1`
- `scripts/Invoke-TODOperatorChatSweep.ps1` now validates the current bridge-diagnostics contract instead of relying on an older fixed build-tag assumption

### Merge-Ready Checkpoint

Freeze this hardening slice as a narrow TOD checkpoint before widening the contract further.

Changed-file scope for this slice was intentionally explicit:

- `scripts/Start-TOD-UI.ps1`
- `ui/index.html`
- `scripts/Invoke-TODOperatorChatSweep.ps1`
- `tests/TOD.BridgeStatus.Tests.ps1`
- `tests/TOD.OperatorChatLifecycleRegression.Tests.ps1`
- `tests/TOD.OperatorChatMimProposal.Tests.ps1`
- `docs/TOD_Recovery_Plan.md`
- `docs/tod-operator-chat-console-v3-objective87.md`

Checkpoint summary:

- bridge observability is now explicit enough to distinguish startup lag, stale listener state, sequence gaps, and missing artifacts without inventing a parallel bridge panel
- operator-chat bridge explanation reuses the governed evidence contract instead of forcing operators to infer meaning from raw project-status payloads
- the live sweep now validates the stable bridge-diagnostics contract rather than pinning to an older build-tag assumption
- live proposal regression preserves the stable contract rather than a rank-order assumption, because non-MIM suggestions can legitimately outrank MIM-tagged rows while `mim_proposal_*` flags and metadata remain valid

Known upstream boundary:

- `source_of_truth.objective_active_source` remains upstream MIM-box territory; TOD now mirrors and explains live posture more clearly, but exporter-source semantics still need to be fixed on the canonical MIM host rather than here

The next bounded slice after this checkpoint is stricter commitment scoping, not a new control plane.

The next hardening pass on 2026-03-25 deepened commitment scoping precedence so proposal, commitment, and trust-chain views stay crisp under overlap instead of collapsing into flat in-scope or out-of-scope results:

- commitment scope evaluation now classifies rows as `proposal_specific` or `objective_wide`, detects nested overlap, and returns inspectable conflict fields for overlap status, conflict reason, conflict resolution, precedence rank, and scope influence summary
- active commitment lookup now honors scope precedence, so a narrower live proposal-specific commitment outranks an overlapping objective-wide commitment instead of whichever row happens to sort first in recency order
- objective-wide commitments remain visible when still valid, but they are explicitly downgraded beneath live proposal-specific scope instead of silently competing with it for arbitration weight
- operator-chat evidence and the commitments view now surface scope kind, scope resolution, and scope influence so operators can inspect why a commitment is active, downgraded, or blocked without reading raw logs
- focused live regression coverage now asserts the new scope-precedence fields across commitments, lifecycle projection, and trust-chain inspection on the live host

The next operational hardening pass on 2026-03-26 promoted the live sweep artifact smoke result into a first-class execution-readiness surface instead of treating it as only a debugging byproduct:

- `scripts/Test-TODOperatorChatSweepArtifact.ps1` now acts as the fast certification gate for Objective 87 operator-chat stability using the durable artifact `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json`
- `.\scripts\TOD.ps1 -Action get-execution-readiness` exposes that artifact as a normalized runtime signal, including readiness validity, artifact freshness, and policy metadata
- TOD policy wiring now uses that signal to block `run-task` when certification is invalid and to degrade `engineer-run -ApplyPlan` toward advisory mode rather than trusting an unstable host
- Objective 90 now treats this as an execution contract: execution must be gated by validated readiness signals with enforceable policy outcomes, including `block`, `degrade`, `stale`, `uncertain`, and conflicting-signal handling as the readiness surface expands
- shared-state sync now exports the same readiness signal into `execution_evidence.json`, `current_build_state.json`, and `contracts.json` so MIM can consume it as a formal capability rather than inferring state from ad hoc logs
- this capability is now tracked as `TOD Sweep Certification Capability`, which is the Objective 87 readiness checkpoint being carried forward into Objective 90 execution policy preparation

Direct live certification on 2026-03-27 then locked the proof surface on the real host without depending on the truncated Pester wrapper:

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-TODOperatorChatSweepArtifact.ps1 -WaitTimeoutSeconds 120 -EmitJson` completed with process exit code `0`
- the durable artifact `shared_state/tod_operator_chat_sweep_artifact_smoke.latest.json` recorded `passed_all = true`, `exit_code = 0`, and `13/13` certification checks passing
- supporting live suites remained green for commitments and trust-chain while the certification line moved to the direct artifact smoke result instead of terminal-wrapper formatting

## Next Expansion

Future Objective 87 work can add:

- stronger cross-session weighting once more proposal-linked terminal history accumulates on the live host
- tighter closure summaries that distinguish preview-only proposal activity from commitment-backed proposal outcomes when the journal is sparse
