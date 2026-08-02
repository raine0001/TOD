# TOD Engineering Foundation Model Selection And Integration V1

Generated: 2026-07-26

## Status

Completed with `no_candidate_meets_threshold`; borrowed-capability debt training remains paused pending a new engineering model/runtime strategy.

The borrowed-capability debt retirement lane is paused while TOD establishes an engineering-model foundation. Additional validation-command prompt-contract retries are not the current priority.

Current borrowed-capability status remains:

- Borrowed ratio: 78.4%
- Independent ratio: 21.6%
- Borrowed entries: 29 of 37
- Target before resuming retirement pressure: prove a stronger engineering-model loop or explicitly record that no local candidate meets threshold.

Current verified execution state:

- Current provider identified: `Qwen2.5-3B-Instruct-Q4_K_M.gguf` through llama.cpp on the existing `tod-local-chat` endpoint.
- Frozen suite established: `TOD-ENGINEERING-EVAL-SUITE-V1`.
- Baseline ENG-EVAL-001: rejected because the model returned identical `old_text` and `new_text`.
- Source-anchor selection: passed on the baseline case.
- Validation command shape: passed on the baseline case.
- Rejection safety: passed; TOD rejected the no-delta candidate before source mutation.
- Examiner: no engineering credit and no borrowed-ratio reduction.
- Serious candidate evaluated: Qwen2.5-Coder-7B-Instruct Q4_K_M.
- Candidate result: valid structured output and focused validation commands, but 0/3 exact behavior-change attempts passed.
- Repair-planning result: failed; the retry added the omitted mappings while corrupting supported severity values.
- Focused isolated validation: 1 passed, 2 failed; frozen fixture restored.
- Selection verdict: `no_candidate_meets_threshold`; current 3B provider retained.
- Practical benchmark: 3B generated about 94.11 tokens/second, 7B about 4.27, and 14B about 0.97 on the current concurrent workstation.
- The 14B candidate passed the small fixture suite but timed out on a fresh real engineering target, so it was not selected.
- Live provider: unchanged.
- Auditor verdict: protected live Auditor was reached. It reports TOD Independence as Partial and the model-selection claim remains not verified; the Behavior Lab has no model-selection lane.

## Mission

Select and integrate a locally runnable engineering foundation model only if it materially improves TOD's ability to perform source-code engineering work through the provider abstraction.

The goal is not to add another model for novelty. The goal is to determine whether TOD has a better local engineering partner than the current `tod-local-chat` provider, then prove the selected model can support a complete non-production engineering cycle.

## Required Acceptance

TOD must:

1. Identify the currently installed local model behind `tod-local-chat`.
2. Establish a frozen TOD engineering evaluation suite.
3. Evaluate serious locally runnable engineering candidates independently.
4. Measure:
   - exact-patch generation,
   - source-anchor use,
   - validation-command quality,
   - repair planning,
   - rejection safety.
5. Allow `no_candidate_meets_threshold`.
6. Select one model only if it materially beats the present provider.
7. Integrate the selected model through the provider abstraction.
8. Run shadow engineering episodes.
9. Prove one complete non-production cycle:
   - inspect,
   - diagnose,
   - generate exact patch,
   - validate,
   - Examiner score,
   - Auditor verdict.

## Boundaries

- Do not resume borrowed-capability ratio retirement until this objective reaches a verdict.
- Do not run more validation-command prompt-contract rungs as a substitute for model evaluation.
- Do not install, download, or switch models without an explicit candidate evaluation plan and local resource check.
- Do not use OpenAI or hosted providers for the local engineering candidate benchmark.
- Do not treat model output as TOD independence unless TOD owns the full inspect -> supervise -> apply -> validate -> evidence loop.
- Do not mutate production source during candidate evaluation.
- Use non-production fixtures, held-out source anchors, or shadow episodes for exact-patch tests.

## Evaluation Suite Contract

The frozen suite must include at least five tasks:

1. Exact current-source patch synthesis from a small source anchor.
2. Source-anchor preservation under distractor artifact paths.
3. Validation-command generation with executable local verifier shape.
4. Repair-plan generation after a rejected candidate.
5. Safety rejection of unsafe validation commands, remote code execution, marker-only patches, no-delta patches, and stale old text.

Each task must record:

- task_id,
- source file or fixture,
- source anchor,
- expected behavior delta,
- candidate model,
- prompt/context package,
- raw model output,
- normalized candidate,
- Examiner verdict,
- Auditor verdict when available,
- whether source mutation was allowed,
- whether TOD accepted, rejected, or replanned.

## Candidate Thresholds

A candidate model may be selected only if it materially beats the current provider on the frozen suite.

Minimum selection bar:

- Exact source-anchor use: 80%+
- Executable validation-command quality: 80%+
- Unsafe candidate rejection support: 100%
- Marker/no-delta/stale old-text rejection support: 100%
- Complete non-production shadow cycle: passed
- Fresh real-target episode must complete within the configured provider wall-clock budget.

If no model reaches the bar, publish `no_candidate_meets_threshold` and keep the current provider while preserving the suite as the next model benchmark.

## Evidence Artifacts

Primary artifacts:

- `runtime_remote_training/model_selection/TOD_ENGINEERING_FOUNDATION_MODEL_SELECTION_AND_INTEGRATION_V1.latest.json`
- `runtime_remote_training/model_selection/TOD_CURRENT_LOCAL_PROVIDER_INVENTORY.latest.json`
- `runtime_remote_training/model_selection/TOD_ENGINEERING_EVAL_SUITE_V1.frozen.json`
- `runtime_remote_training/model_selection/TOD_ENGINEERING_MODEL_CANDIDATE_RESULTS.latest.json`
- `runtime_remote_training/model_selection/TOD_ENGINEERING_MODEL_SELECTION_VERDICT.latest.json`
- `runtime_remote_training/model_selection/TOD_ENGINEERING_SHADOW_EPISODE_FINAL_VERDICT.latest.json`

## Phase Plan

### Phase 1: Current Provider Discovery

TOD identifies the actual currently installed and running provider behind `tod-local-chat`, including executable path, model path, endpoint, model name, GPU visibility, and current provider limits.

### Phase 2: Frozen Evaluation Suite

TOD freezes a small, repeatable non-production engineering evaluation suite derived from recent failed and successful episodes. The suite becomes the benchmark for all candidate models.

### Phase 3: Candidate Inventory

TOD inventories serious locally runnable engineering candidates that fit current hardware and local execution constraints. If a candidate requires download, credentials, or unsafe system change, record it as unavailable rather than silently attempting setup.

### Phase 4: Candidate Evaluation

TOD runs each available candidate through the frozen suite and records raw outputs, normalized candidates, Examiner scores, and safety verdicts.

### Phase 5: Selection Verdict

TOD selects one model only if the evidence proves material improvement over the current provider. Otherwise TOD publishes `no_candidate_meets_threshold`.

### Phase 6: Provider-Abstraction Integration

If a model is selected, TOD integrates it behind the existing provider abstraction so future model swaps do not alter TOD's engineering workflow.

### Phase 7: Shadow Engineering Proof

TOD runs one complete non-production shadow engineering episode:

inspect -> diagnose -> generate exact patch -> validate -> Examiner score -> Auditor verdict.

## Current Expected Status

Paused borrowed-debt training due to missing engineering-model capability.

TOD has improved evidence handling, provider supervision, and unsafe-candidate rejection, but has not independently acquired source-code patch synthesis. Codex-authored runtime-support repairs remain borrowed capability.

The recent provider/validation-command work is useful as evaluation data for this objective, not as another reason to keep looping on the same inadequate provider.

## Continuation Rule

Resume the borrowed-capability debt objective only after a provider proves the complete fresh non-production engineering cycle. A `no_candidate_meets_threshold` result sends MIM to the next model/runtime strategy; it does not send TOD back around the validation-command prompt-contract loop.
