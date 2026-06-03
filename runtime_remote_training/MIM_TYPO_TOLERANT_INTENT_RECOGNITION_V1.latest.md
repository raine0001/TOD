# MIM-TYPO-TOLERANT-INTENT-RECOGNITION-V1

Generated: 2026-06-02

## Goal

Teach MIM to understand operator intent when typed text contains typos, shorthand, misspellings, missing words, or rough phrasing.

This is not canned prompt matching. The goal is meaning recovery:

- Preserve the user's original words.
- Normalize noisy text only for routing and intent selection.
- Choose the right response mode before answering.
- Answer the real question without making Dave retype it perfectly.

## Why This Matters

Operators type fast, misspell words, use shorthand, and often phrase ideas while thinking. MIM should not require perfect English to understand:

- "montly update" means monthly update.
- "wat are you trainign on" means training status.
- "what shoud we werk on next" means recommendation mode.
- "build me an acounting app" means consultative discovery.
- "any blokers" means blocker status.

## Required Behavior

MIM should:

- Recover likely meaning from noisy typed input.
- Route to the right operator response mode.
- Avoid generic deflections.
- Avoid raw task IDs, packet names, request IDs, and lifecycle jargon unless asked.
- Ask for clarification only when the meaning is genuinely ambiguous.

## Validation

Run:

```powershell
python scripts/run_mim_typo_tolerant_intent_smoke.py --base-url http://192.168.1.120:18001
```

Expected artifacts:

- `runtime_remote_training/MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.json`
- `runtime_remote_training/MIM_TYPO_TOLERANT_INTENT_SMOKE.latest.md`

## Success Criteria

- 20 noisy-input smoke cases run against live MIM.
- Pass rate reaches at least 80%.
- Failed cases include exact missing checks.
- MIM/TOD training scoreboard includes noisy-input status in future iterations.
- MIM can answer misspelled operator questions without requiring Dave to retype.
