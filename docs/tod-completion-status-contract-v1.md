# TOD Completion Status Contract v1

## Purpose

Define the machine-readable and human-readable status response that proves TOD understood the request and acted on it.

## Artifact

- `shared_state/tod_autonomy_status.latest.json`

## Required Fields

```json
{
  "tod_got_this": "string",
  "tod_did_this": "string",
  "tod_next_action": "string",
  "mim_next_action": "string",
  "current_tod_state": "waiting|executing|thinking|blocked|training|reconciling",
  "current_mim_state": "waiting|executing|reviewing|stale|unknown",
  "last_mim_request_sent_seconds_ago": 0,
  "last_tod_action_observed_seconds_ago": 0,
  "confidence": "confirmed|inferred|pending_verification",
  "blockers": ["string"]
}
```

## Interpretation

- `tod_got_this`: what TOD has taken ownership of
- `tod_did_this`: latest completed action
- `tod_next_action`: immediate no-stall continuation step
- `mim_next_action`: what MIM should do if responsive
- `current_tod_state`: actual execution posture
- `current_mim_state`: best-known MIM posture
- `last_mim_request_sent_seconds_ago`: age of the open MIM solicitation if one exists
- `last_tod_action_observed_seconds_ago`: age of the latest daemon or guard update

## Rule

This artifact should be refreshed by TOD guard or daemon activity so status stays objective rather than conversational.
