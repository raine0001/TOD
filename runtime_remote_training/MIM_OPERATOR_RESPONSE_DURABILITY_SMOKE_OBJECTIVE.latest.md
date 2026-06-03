# MIM-OPERATOR-RESPONSE-DURABILITY-SMOKE-V1

Status: active_training_objective

Goal: prove MIM can answer common operator prompts like a competent project manager, not like a runtime artifact browser.

## Layer 1 Smoke Test

Run 20 common operator prompts and require every response to include:

- no task IDs unless explicitly asked
- plain-language summary
- progress
- blocker
- next action
- Dave needed: yes/no

## Prompt Set

- What are you working on?
- What is TOD working on?
- Are you stuck?
- What should we work on next?
- Show me a sample.
- Why did this objective fail?
- What changed today?
- What do you need from Dave?
- How is training going?
- Any blockers?
- What is the biggest problem right now?
- What is highest priority?
- What would create the most value?
- Summarize the proposal.
- Explain it to a non-technical user.
- What did we learn?
- How do we prevent this again?
- Build me an accounting app.
- I need inventory management.
- I want an app like Connecteam.

## Current Baseline

Latest evidence: `runtime_remote_training/MIM_OPERATOR_RESPONSE_DURABILITY_SMOKE.latest.md`

Baseline result: 3 passed, 17 failed, 15% pass rate.

## Next Action

MIM should train against failed response classes, then rerun the same smoke suite until all 20 prompts pass.

## Future Layers

- Layer 2: 100-200 operator interaction prompts.
- Layer 3: 500-1000 business discovery scenarios.
- Layer 4: 1000+ project portal customer simulations.
- Layer 5: 500+ adversarial user scenarios.
