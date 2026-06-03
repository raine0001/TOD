# MIM-DURABILITY-SMOKE-V2

Status: active_training_objective

Goal: improve MIM judgment by training against the failed V1 prompts plus the repeated demonstration prompts that are now common in project work.

## Diagnosis

MIM's weakness is not basic language generation. The failure pattern shows a judgment problem:

Question -> provide status

instead of:

Question -> interpret intent -> choose response mode -> recommend, explain, demonstrate, discover, or analyze

## Training Scope

Do not expand to 100 prompts yet. Train only the focused V2 suite until mode selection improves.

## Groups

### Recommendation Mode

- What should we work on next?
- What is highest priority?
- What would create the most value?

Expected behavior: make a recommendation, explain why, name tradeoffs/blockers, and state the next action.

### Explanation Mode

- Explain it to a non-technical user.
- Summarize the proposal.
- What did we learn?
- What changed today?
- What is TOD working on?
- What do you need from Dave?

Expected behavior: answer the request directly, explain plainly, avoid generic reprompts, and give useful next context.

### Demonstration Mode

- Show me a sample.
- What would this look like?
- Can I see an example?
- Show me the interface.

Expected behavior: provide a visible/reviewable sample, artifact card, link, screenshot, prototype, or honest missing-sample reason with the next creation step.

### Consultative Discovery

- Build me an accounting app.
- I need inventory management.
- I want an app like Connecteam.

Expected behavior: reframe the real business need, identify hidden requirements, ask 2-4 useful questions, avoid cloning, and propose a discovery next step.

### Problem Analysis

- Are you stuck?
- Why did this objective fail?
- How do we prevent this again?
- What is the biggest problem right now?

Expected behavior: state the problem, cause, learned prevention, next repair action, and whether Dave is needed.

## Success Criteria

- V2 pass rate reaches at least 80% before adding more prompts.
- No task IDs, objective IDs, lifecycle states, packet names, or raw commands unless explicitly asked.
- Recommendation questions produce recommendations, not generic status.
- Discovery prompts uncover hidden requirements before building.
- Failure prompts produce cause, lesson, prevention, and next action.

## Test Harness

Run:

```powershell
python scripts/run_mim_durability_smoke_v2.py --base-url http://192.168.1.120:18001 --out-dir runtime_remote_training
```

Latest result:

`runtime_remote_training/MIM_DURABILITY_SMOKE_V2.latest.md`
