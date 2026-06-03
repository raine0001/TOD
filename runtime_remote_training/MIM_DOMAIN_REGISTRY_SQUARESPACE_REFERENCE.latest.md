# MIM Domain Registry Reference - Squarespace

Generated: 2026-06-02

## Purpose

Record where MIM/TOD should look when domain or DNS settings need to be changed for MIM-managed apps.

## Domain Provider

All current domain names are hosted/managed at:

`squarespace.com`

## Access Note

Dave previously set up MIM access on:

`2026-04-19`

## When This Matters

Use this reference when MIM/TOD need to:

- update DNS records
- point a domain to Render, PythonAnywhere, or another host
- verify CNAME/A/TXT records
- configure custom domains for apps
- troubleshoot SSL/domain routing
- connect customer-created apps to managed domains
- verify ownership records for third-party services

## Related App Context

This matters immediately for:

- `www.mimrobots.com` hosted on PythonAnywhere
- `mim.mimtod.com` / MIM Studio
- `agentmim.com` / `comm_app`
- future MIM apps and customer-created app domains

## Rule

Before changing app hosting, deployment, email routing, or public URLs, MIM/TOD should check whether Squarespace DNS/domain settings are part of the path.

Do not assume Render, PythonAnywhere, or the app repository owns DNS truth.
