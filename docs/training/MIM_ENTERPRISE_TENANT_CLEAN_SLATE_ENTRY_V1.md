# MIM Enterprise Tenant Clean Slate Entry V1

Owner: MIM

Implementer: TOD

Codex role: coach and validator only

## Problem

The Enterprise Demo account currently lands on `/observatory`, but `/observatory` is the public Research Observatory home.

That means an enterprise user sees public research categories, public MIM questions, public initiative cards, and `Begin Investigation` instead of an enterprise-scoped clean slate.

This is not just a visual issue. It is a tenant-boundary issue.

## Product Principle

For Enterprise accounts, MIM is the application.

The enterprise home should start with:

1. Enterprise/company identity.
2. MIM as the primary front door.
3. Conversation tied to enterprise data, permissions, and workspaces.
4. MIM routing the user to the correct workspace based on intent.

Public Research Observatory content should be available only when MIM or the user intentionally opens that workspace.

## Enterprise Entry Model

Enterprise -> MIM -> Conversation -> Intent -> Workspace -> Data -> Action

Not:

Enterprise -> Public Observatory -> User hunts through public research cards.

## Users

- Customers ask about products, services, pricing, support, or public company information.
- Employees work with internal data, research, applications, documents, and objectives.
- Partners and shareholders access approved enterprise summaries and reports.
- Department workers ask objective-driven questions for accounting, engineering, marketing, planning, support, or app creation.

Each should begin at MIM and be routed by intent.

## Required Fix

TOD must inspect the current `/observatory` route, Enterprise Demo account metadata, and session/cookie flow.

Then TOD must produce the smallest safe route-boundary repair so:

- public visitors still see the public Research Observatory;
- enterprise users see an enterprise-scoped MIM entry;
- public content is not mixed into enterprise-private home by default.

## Acceptance

- Enterprise Demo login no longer shows public Research Observatory inventory by default.
- Enterprise landing shows enterprise identity and MIM-first clean-slate entry.
- Public `/observatory` remains public for non-enterprise visitors.
- Tests prove public and enterprise sessions diverge correctly.
- Remote live smoke proves both routes.
