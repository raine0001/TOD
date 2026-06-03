# MIM-UNIVERSAL-PRESENCE-CONTEXT-V1

Generated: 2026-06-02

## Goal

Put the "one Dave, one MIM, many interfaces" architecture into play.

MIM should be a continuous presence across Studio, `/mim`, MIM Wall, phone, project portal, and lab/robotics surfaces. TOD remains a focused execution service.

## Current Implementation Slice

- Add canonical presence artifact: `runtime/shared/MIM_UNIVERSAL_PRESENCE.latest.json`.
- Add MIM Presence card to `/studio`.
- Use one primary Studio conversation identity: `dave-primary-mim-thread`.
- Keep page context as metadata instead of creating a separate MIM per page.
- Update training directive so MIM trains universal presence continuity.

## Presence Fields

- current conversation
- active project
- last interaction surface
- current focus
- memory context
- pending follow-up
- primary conversation id
- known surfaces

## Product Rule

`/mim` is deep conversation mode.

`/tod` is focused execution mode.

Studio and future apps use a universal MIM panel that knows page context while preserving one MIM identity.

## Success Criteria

- `/studio` shows MIM Presence.
- Studio chat sends `conversation_session_id=dave-primary-mim-thread`.
- Studio chat also sends page context metadata.
- `MIM_UNIVERSAL_PRESENCE.latest.json` is created or refreshed.
- MIM training directive names universal presence continuity as active training.
