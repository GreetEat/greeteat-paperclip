<!--
SYNC IMPACT REPORT
==================
Version change: (template) → 1.0.0
Bump rationale: Initial ratification. All placeholders replaced with concrete values;
first formal version of the constitution.

Modified principles:
  - [PRINCIPLE_1_NAME]        → I. Configuration as Code (NON-NEGOTIABLE)
  - [PRINCIPLE_2_NAME]        → II. Environment Parity
  - [PRINCIPLE_3_NAME]        → III. Reversible Deployments
  - [PRINCIPLE_4_NAME]        → IV. Secrets Discipline
  - [PRINCIPLE_5_NAME]        → V. Observability by Default

Added sections:
  - Operational Constraints (new: replaces [SECTION_2_NAME])
  - Deployment Workflow       (new: replaces [SECTION_3_NAME])
  - Governance                (filled from template)

Removed sections: none (template stubs resolved, not removed)

Templates requiring updates:
  - ✅ .specify/templates/plan-template.md — Constitution Check section is
       principle-agnostic; no edit required. Verified alignment with new
       principles (gates map cleanly onto IaC concerns).
  - ✅ .specify/templates/spec-template.md — template is generic; no edit
       required. Deployment specs will naturally exercise the new principles.
  - ✅ .specify/templates/tasks-template.md — generic task categories; no edit
       required. Rollback/observability tasks fall under existing categories.
  - ✅ .specify/templates/checklist-template.md — generic; no edit required.

Follow-up TODOs: none. All placeholders resolved.
-->

# Paperclip GreetEat Deployment Constitution

This constitution governs the **GreetEat** deployment of Paperclip, an agentic
orchestration system. It applies to all infrastructure, configuration, and
runtime artifacts in this repository.

## Core Principles

### I. Configuration as Code (NON-NEGOTIABLE)
All infrastructure, environment state, runtime configuration, and deployment
manifests MUST live in version control. Manual changes made via consoles,
dashboards, or ad-hoc shell sessions are prohibited; if an emergency change is
made out-of-band, it MUST be reconciled back into the repository within the
same working day and documented in the incident record.

**Rationale:** Agentic systems produce state that is already hard to reason
about. Without a single declarative source of truth, drift between repo and
reality compounds silently and destroys the ability to reproduce, audit, or
roll back deployments.

### II. Environment Parity
Non-production environments (local, staging, pre-prod) MUST mirror production
in topology, tooling, and configuration shape. Differences MUST be explicit,
narrow, and declared in configuration (not implicit through "we just didn't
enable it there"). Any divergence MUST be listed in the deployment spec that
introduces it, with an expiry date or a justification for permanence.

**Rationale:** Production incidents in agent-driven systems frequently trace
back to hidden environment divergence — a flag set differently, a secret
missing, a model tier swapped. Parity by default makes these surprises rare
and legible when they occur.

### III. Reversible Deployments
Every change MUST have a known, tested rollback path before it is applied to
production. Destructive operations (data deletion, schema drops, irreversible
migrations, credential rotations without grace windows) require an explicit
recovery plan recorded in the change spec and acknowledged by a second
reviewer. Forward-only migrations are permitted ONLY when paired with a
documented compensating procedure.

**Rationale:** Agents can take unexpected actions against live infrastructure.
The ability to undo a bad deployment — quickly and without guesswork — is the
primary safety mechanism protecting both Paperclip and the GreetEat
environment.

### IV. Secrets Discipline
Credentials, API keys, tokens, and other sensitive configuration MUST NEVER
appear in source code, committed files, git history, build logs, CI variables
that echo output, or unencrypted local files. Secrets are resolved at runtime
from a designated secret manager using least-privilege access. Suspected
leaks MUST trigger rotation before any other remediation.

**Rationale:** Deployment repositories are high-value targets. A single
leaked key for an agentic orchestration system can authorize the agent to
take destructive action at scale. Prevention is cheaper than recovery.

### V. Observability by Default
Every deployed component — orchestrator, worker, sidecar, scheduled job —
MUST emit structured logs, health signals, and operational metrics from the
first deployment. Components without observability MUST NOT be promoted past
staging. Agent decisions and tool invocations MUST be traceable end-to-end
with correlation identifiers.

**Rationale:** You cannot operate, debug, or trust a system you cannot see.
For agentic orchestration this is doubly true: without per-step traces, the
difference between "the agent made a correct but surprising choice" and "the
agent is broken" is unknowable.

## Operational Constraints

The following constraints apply to all deployments in this repository and
are enforced at review time:

- **Resource ceilings:** Every deployed component MUST declare CPU, memory,
  and (where applicable) cost/token budgets. Unbounded resources are
  prohibited.
- **Agent sandboxing:** Agent runtimes MUST execute with the minimum
  privileges required. Broad credentials (cloud-admin, DB-superuser) MUST
  NOT be attached to agent runtimes; scoped, short-lived credentials are
  required instead.
- **Change blast radius:** A single deployment change MUST be scoped to one
  logical concern. Bundling unrelated changes is prohibited because it
  destroys the rollback guarantees of Principle III.
- **Dependency pinning:** External images, charts, modules, and models MUST
  be pinned to an immutable reference (digest, version, or hash). Floating
  tags (`latest`, `main`, `stable`) are prohibited in anything that reaches
  staging or production.

## Deployment Workflow

All work in this repository follows the spec-driven workflow provided by
speckit (`.specify/` directory). The flow is:

1. **Constitution check** — proposed changes are first checked against the
   principles above. If a principle appears to block the change, the change
   spec MUST either justify the exception or amend the constitution first.
2. **Spec** — a specification is authored in `.specify/` describing the
   problem, the proposed change, acceptance criteria, and the rollback plan
   (per Principle III).
3. **Plan & tasks** — implementation plan and tasks are generated from the
   spec using the speckit templates. The plan MUST surface any principle
   trade-offs.
4. **Implement** — changes are applied to configuration, not to live
   infrastructure directly (per Principle I).
5. **Review** — at least one reviewer other than the author MUST verify
   principle compliance, observability coverage, and rollback feasibility
   before merge.
6. **Promote** — changes move through environments in order (local → staging
   → production). Skipping staging is prohibited except for declared
   emergency fixes, which MUST be retroactively spec'd within the same day.

## Governance

This constitution supersedes informal practice, tribal knowledge, and
individual preference within this repository. When a conflict arises between
this document and any other guidance, this document wins until it is
formally amended.

**Amendment procedure:**
- Amendments are proposed via the `/speckit-constitution` skill, which
  updates this file and runs the consistency propagation checks against
  `.specify/templates/`.
- Every amendment MUST include a Sync Impact Report (the HTML comment at the
  top of this file), a version bump, and an updated `Last Amended` date.
- Amendments that remove or materially weaken a principle require explicit
  acknowledgement from the project owner.

**Versioning policy (semantic):**
- **MAJOR** — backward-incompatible governance change: a principle is
  removed, materially redefined, or the governance procedure itself changes.
- **MINOR** — a new principle or section is added, or existing guidance is
  materially expanded.
- **PATCH** — clarifications, wording fixes, typo corrections, or
  non-semantic refinements.

**Compliance review:** Every pull request MUST confirm in its description
(or via an automated check) that the change has been evaluated against the
Core Principles. Unjustified complexity MUST be challenged in review.
Runtime development guidance lives in the agent-specific guidance files at
the repository root (e.g. `CLAUDE.md` if present) and MUST stay consistent
with this constitution.

**Version**: 1.0.0 | **Ratified**: 2026-04-09 | **Last Amended**: 2026-04-09
