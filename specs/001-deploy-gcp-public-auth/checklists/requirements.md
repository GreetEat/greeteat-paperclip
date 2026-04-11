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
- **Fourth draft (brief shared-project intermezzo)**: a dedicated
  `paperclip` project was created on 2026-04-09 but couldn't have
  billing attached (Victor lacked `roles/billing.user` on the billing
  account). After comprehensive permission testing on the existing
  GreetEat projects, the plan briefly pivoted to host Paperclip inside
  the existing `greeteat-staging` project where billing was already
  attached. The shared-project pivot also collapsed the two-environment
  plan into a single environment, requiring a Complexity Tracking entry
  in `plan.md`. Phase B verification of Vertex Claude ran in this
  shared project. Vertex AI Claude Sonnet 4.6 was confirmed live with
  a successful predict call on 2026-04-10, and Paperclip's `claude_local`
  adapter preflight was verified end-to-end the same day with a local
  Paperclip instance running multi-turn agent tasks against Vertex
  Claude Sonnet 4.6 — every message ID had the `msg_vrtx_*` prefix
  and `apiKeySource: "none"`. The LLM provider question is fully
  resolved: Vertex Claude, no Anthropic API key in any form.
- **Current draft (post-pivot back to dedicated project)**: on
  2026-04-10 the operator obtained the missing billing-account grant
  and attached billing (`01BCB7-61A725-D6A2B5`) to the dedicated
  `paperclip-492823` project. The plan was re-targeted from the
  shared `greeteat-staging` project back to the dedicated
  `paperclip-492823` project, eliminating all co-tenant /
  shared-resource concerns from the Phase A/B drafts. Single
  environment is retained per user direction; the Complexity Tracking
  entry was rewritten so single-env is now justified by user choice
  + cost trade-off + small operator group, not by a billing-constraint
  workaround. Local-dev workflow recommendations were dropped from
  `quickstart.md` per the user's CI-only-deployment direction. Vertex
  Claude Model Garden access on `paperclip-492823` is enabled
  separately by the operator (per-project subscription).
- **Sixth draft (post-Phase-2 source-code audit)**: while implementing
  Phase 2 of `/speckit-implement`, an audit of the cloned Paperclip
  source surfaced multiple env-var and Dockerfile assumptions in the
  earlier drafts that were factually wrong. Specifically:
  Paperclip uses TWO env vars (`PAPERCLIP_DEPLOYMENT_MODE=authenticated`
  + `PAPERCLIP_DEPLOYMENT_EXPOSURE=public`) not one;
  storage credentials are read by the AWS SDK from `AWS_ACCESS_KEY_ID`
  / `AWS_SECRET_ACCESS_KEY` not `S3_*`; storage backend env vars are
  `PAPERCLIP_STORAGE_S3_*` not `S3_*`; `BETTER_AUTH_SECRET` is REQUIRED
  for any authenticated deployment (we had no secret for it);
  `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` is the invitation-only
  enforcement mechanism; the default port is 3100 not 8080; and the
  `paperclipai auth bootstrap-ceo` command exists for non-interactive
  first-admin invite creation. The audit also revealed that Paperclip
  ships its own non-trivial multi-workspace Dockerfile, so the custom
  Dockerfile + entrypoint we wrote in Phase 2 (T019, T020) were
  unnecessary and potentially wrong — they were deleted and the build
  workflow was rewritten to clone upstream and build from upstream's
  official Dockerfile. A new bootstrap script
  `bootstrap-better-auth-secret.sh` was added (sibling of
  `bootstrap-master-key.sh`), the secrets module was extended with a
  fourth data lookup, and the contracts/container-image.md spec was
  rewritten end-to-end with the correct env var names and the
  upstream-Dockerfile inheritance approach. Phase 2 commits remain
  in history; the corrections land in a `fix(infra)` commit on top.

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
