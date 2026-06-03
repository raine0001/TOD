# MIM Studio Training Chat Attention Fix V1

Generated: 2026-06-03T05:44:00Z

## Issue

On the Studio Training page, Dave asked: "what needs attention MIM?"

MIM correctly reported that judgment-mode selection was weak, but the page chat still answered by dumping the raw training scoreboard. That repeated the failure being measured: status reporting instead of recommendation, explanation, demonstration, consultative discovery, or problem analysis.

## Fix

Updated `/home/testpilot/mim/core/routers/studio.py` and the local mirror at `tmp_remote_mim/core/routers/studio.py`.

Behavior added:

- Studio chat now tries `/studio/api/mim/chat` before falling back to `/gateway/intake`.
- Training page prompts are handled with page-aware training context.
- Attention, priority, recommendation, weakness, stuck, problem, or next-action prompts now receive a prioritized recommendation reply.
- The reply ranks:
  1. MIM judgment-mode repair.
  2. Outcome reflection and stale artifact cleanup.
  3. TOD validation-baseline tightening.

New local regression test:

- `tmp_remote_mim/tests/test_studio_training_chat.py`

## Remote Deployment

Remote backup created before upload:

- `/home/testpilot/mim/core/routers/studio.py.bak.20260603T053628Z`

Remote service restarted:

- `mim-mobile-web.service`

## Validation

Local validation:

- `python -m py_compile tmp_remote_mim/core/routers/studio.py tmp_remote_mim/tests/test_studio_training_chat.py`
- `python -m unittest tmp_remote_mim.tests.test_studio_training_chat`

Remote validation:

- `cd /home/testpilot/mim && .venv/bin/python -m py_compile core/routers/studio.py`
- `systemctl --user restart mim-mobile-web.service`
- `systemctl --user is-active mim-mobile-web.service`
- POST to `http://127.0.0.1:18001/studio/api/mim/chat` with prompt `what needs attention MIM?`

Observed remote response:

- `source`: `studio_training_context`
- `response_mode`: `recommendation`
- reply starts: `Three things need attention, Dave.`

## Follow-up

The page-specific chat route is now ready to expand to other Studio pages, but Training was the active failure and should stay the focused validation target first.
