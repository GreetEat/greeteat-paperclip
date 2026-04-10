# Specification Quality Checklist: Deploy Paperclip to GCP in Public Authentication Mode

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-04-09
**Last validated**: 2026-04-10 (after shared-project pivot, Vertex Claude verified live)
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

### Revision history

- **First draft**: assumed consumer-facing user model with self-signup
  via an external IdP (Cognito assumed). Rejected after Paperclip docs
  review.
- **Second draft (post-docs review)**: rewrote to reflect Paperclip's
  real user model — board operators, invitation-only, Better Auth built
  into Paperclip. AWS-flavored, with data layer deferred to planning.
- **Third draft (post-pivot to GCP)**: same six user stories, same
  spec scope; the cloud constraint changed from AWS to GCP mid-planning.
  An additional investigation (prompted by user) confirmed Paperclip's
  invitation flow is URL-based with no email infrastructure required,
  which removed an entire decision (and its implementation cost) from
  the plan.
- **Current draft (post-pivot to shared project + Vertex Claude)**: a
  dedicated `paperclip` project was created but couldn't have billing
  attached (Victor doesn't hold `roles/billing.user` on the billing
  account). After comprehensive permission testing on the existing
  GreetEat projects, we pivoted to host Paperclip inside the existing
  `greeteat-staging` project — Victor is owner, billing is already
  attached, and a clean inspection confirmed there are no naming
  conflicts with the Firebase / App Engine workloads already there.
  The shared-project pivot also collapses the two-environment plan
  into a single environment (the shared project hosts the one
  Paperclip deployment), requiring a Complexity Tracking entry in
  `plan.md` justifying the departure from constitutional principle II.
  Vertex AI Claude Sonnet 4.6 was confirmed live with a successful
  predict call on 2026-04-10. Paperclip's `claude_local` adapter
  preflight was then verified end-to-end the same day with a local
  Paperclip instance running multi-turn agent tasks against Vertex
  Claude Sonnet 4.6 — every message ID had the `msg_vrtx_*` prefix
  and `apiKeySource: "none"`, with no `ANTHROPIC_API_KEY` set anywhere.
  The LLM provider question is fully resolved: Vertex Claude, no
  Anthropic API key in any form.

### Open coverage

- Six user stories cover: operator sign-in (P1), invitation-only
  registration (P1), agent authentication (P1), reproducible deploy
  (P1), rollback (P2), observability (P2).
- Tech-stack mentions in FR-015/FR-016/FR-017 are unavoidable
  architectural constraints (long-lived process, hosted Postgres,
  S3-compatible object store) imposed by Paperclip's runtime
  requirements, not implementation choices.
- "GCP" appears in the title and FR-001 because it is a user-given
  deployment-target constraint. Sub-component choices within GCP
  (Cloud Run, Cloud SQL, GCS, Secret Manager, etc.) are resolved in
  `plan.md` and `research.md`.
- All P1 user stories must pass before the deployment is considered
  ready for promotion to production.
- `/speckit-plan` is complete, has been re-validated post-pivot, AND
  the Paperclip preflight verification experiment landed successfully
  on 2026-04-10. **Ready for `/speckit-tasks`.**
