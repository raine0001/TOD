# MIM Enterprise Experience V1

Owner: MIM

Implementer: TOD

Codex role: coach, reviewer, validator, escalation path only

## Vision

Every organization receives its own branded MIM.

Not another SaaS dashboard. Not another chatbot. A living digital Chief of Staff that represents the enterprise.

When someone visits the enterprise site, they should feel like they are walking into the company's headquarters and being personally welcomed.

The conversation is the interface.

Applications are workspaces that MIM opens automatically.

## Primary Goal

Replace application-first navigation with conversation-first navigation.

The user should never have to wonder which page they need. They should tell MIM what they are trying to accomplish, and MIM should decide the workspace.

## Enterprise Identity

Each enterprise receives a branded home, such as:

- `acme.mimtod.com`
- `solair.mimtod.com`
- `daveraine.mimtod.com`
- optionally `mim.acme.com` or `ai.acme.com`

The enterprise controls:

- branding
- colors
- logo
- welcome message
- company knowledge
- terminology
- permissions

MIM remains the intelligence underneath.

## First Visitor Experience

The first impression should feel alive:

1. Fade or present company logo plus `Powered by MIM`.
2. Transition to company mission and short welcome message.
3. Transition into the MIM conversation.

No dashboard. No overwhelming menus. MIM begins naturally.

Example:

> Hello. I'm MIM. Welcome to Acme Manufacturing. Before we begin, what's your name?

## Returning Visitor Experience

If the visitor is recognized, MIM should greet them personally and preserve continuity.

Example:

> Welcome back Dave. Last time we worked on your inventory automation project. Would you like to continue where we left off?

## User Types

MIM should recognize different conversation goals:

- Customers want products, services, pricing, meetings, or support.
- Employees want to work with internal data, documents, apps, and objectives.
- Executives want health, risks, opportunities, and decisions requiring attention.
- Engineering wants projects, CAD, simulations, objectives, commits, and documentation.
- Accounting wants reports, budgets, subscriptions, invoices, and financial operations.
- Marketing wants campaigns, analytics, assets, social content, and messaging.

Each starts with MIM. Workspaces open because MIM routes the user by intent.

## Enterprise Knowledge

Each enterprise has its own knowledge boundary:

- policies
- employee handbook
- contracts
- product documentation
- marketing assets
- pricing
- CRM
- accounting
- engineering
- documents
- applications
- research

MIM answers from enterprise knowledge and permission context.

## Enterprise Onboarding

Onboarding should be conversational instead of form-first.

MIM asks what the company does, how many employees it has, what software it uses, which documents matter, and what the first useful workspace should be. MIM builds the enterprise profile from the conversation.

## Enterprise Observatory Rule

Enterprise Observatory must not initially display MIM's public research.

The initial state should be enterprise-scoped:

> Welcome. Your enterprise currently has 0 investigations, 0 imported documents, and 0 connected systems. Let's create your first investigation.

Community/public research is optional and opened intentionally.

## Product Philosophy

Old software:

User -> Application -> Data

Enterprise MIM:

User -> Conversation -> Understanding -> Workspace -> Application -> Data -> Action

## Phase 1 Roadmap

1. Enterprise Gateway
   - enterprise entry page
   - create account
   - login
   - about Enterprise
   - pricing
   - MIM-first landing page
2. Enterprise Provisioning
   - branded subdomains
   - custom logo, colors, and welcome message
   - company profile and knowledge base
3. Conversation-Driven Navigation
   - MIM routes users into the correct workspace
   - context persists across workspaces
4. Enterprise Onboarding
   - conversational setup
   - software integrations
   - initial document import
   - organization profile creation
5. Workspace Ecosystem
   - projects
   - accounting
   - engineering
   - marketing
   - documents
   - analytics
   - research
   - administration
6. Executive Experience
   - daily executive briefing
   - enterprise health
   - risks
   - opportunities
   - decisions requiring attention

## Current Phase 1 Child Objectives

- `MIM-ENTERPRISE-TENANT-CLEAN-SLATE-ENTRY-V1`
- `MIM-ENTERPRISE-OBSERVATORY-FIRST-REAL-WORKFLOW-V1`

The tenant clean-slate entry must happen before deeper workflow work, because Enterprise MIM must begin from the correct tenant boundary.

## Success Criteria

- A new visitor immediately understands they are talking to the organization, not navigating generic software.
- Employees no longer search menus to perform work.
- Customers receive guided conversations instead of static pages.
- Executives receive decisions rather than dashboards.
- Applications open automatically from conversation.
- Every enterprise feels like it has its own MIM.

## Ownership

MIM owns:

- enterprise experience
- conversation flow
- workspace selection
- onboarding
- proactive interaction
- product prioritization

TOD owns:

- bounded UI slices
- workspace routing
- enterprise provisioning
- navigation implementation
- integrations
- validation evidence

Codex does not become the primary designer, product owner, or implementer.
