# MIM Studio Settings Continuity Control V1

Generated: 2026-06-02

## Objective

Turn `/studio/settings` from a placeholder into the control page for access, providers, credentials, policies, behavior, voice, notifications, backups, billing, and continuity.

## What Changed

- Added Settings page state builder and renderer.
- Added provider inventory for Render, PythonAnywhere, Squarespace, OpenAI, Email/SMTP, and GitHub.
- Expanded provider inventory around the actual `.env` service surface:
  - MIM/TOD access
  - Gemini / Google AI
  - Postmark / inbound mail
  - Twilio
  - Zoom Phone
  - Stripe
  - Google Calendar / Search
  - Social OAuth
  - RunPod / Paperspace
- Added credential presence map without exposing raw secret values.
- Added TOD environment key inventory support with category counts and no secret values.
- Added continuity / survival mode rules for MIM and TOD.
- Added access policy summary for Dave-only primary operation.
- Added policy summary:
  - ethical solution design
  - material implementation proof
  - no-op rejection
  - H.A.L. escalation
  - freshness/yellow-state resolution
- Added MIM voice settings planning surface.
- Added MIM/TOD behavior rules.
- Added notification, backup/recovery, and billing/cost control summaries.
- Added DB/app context counts.

## Important Behavior

The page should not dump credentials. It should show:

- what provider exists
- what it is used for
- login/recovery path
- whether credentials are present
- continuity rule

## Continuity Principle

MIM and TOD should know how to keep the ecosystem alive if Dave is unavailable:

- preserve data
- preserve source history
- keep survival-critical services online
- reduce optional cost when needed
- document autonomous actions
- escalate only when credentials, decisions, or physical-world checks are required

## Verification

- Local route compile required before deployment.
- Live `/studio/settings` should show Continuity / Survival Mode, Providers, Credential Map, Policies, MIM Voice, MIM / TOD Behavior, Notifications, Backups / Recovery, Billing / Costs, and DB / App Context.
- `TOD_ENV_KEY_INVENTORY.latest.json` should show key names, categories, and presence only.
