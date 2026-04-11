# Feature Specification: Deploy Paperclip to GCP in Public Authentication Mode

**Feature Branch**: `001-deploy-gcp-public-auth`
**Created**: 2026-04-09
**Last updated**: 2026-04-10
**Status**: Draft
**Input**: User description: "we want to deploy paperclip to aws in public authentication mode" — corrected mid-planning to GCP, no Supabase. Investigation also confirmed Paperclip uses URL-based invitations (no email infrastructure required).

## Context

Paperclip is an open-source control plane for "zero-human companies": humans
("board operators") configure organizations of AI agents, set goals and
budgets, approve work, and observe activity through a web dashboard.
Agents (Claude Code, Codex, Gemini, etc.) execute tasks and report back
through a REST API.

Paperclip ships with three deployment modes:

| Mode | Network exposure | Authentication |
|------|------------------|----------------|
| `local_trusted` (default) | Localhost only | None — auto-created local user |
| `authenticated` + `private` | Private network (VPN, Tailscale, LAN) | Login required (Better Auth) |
| `authenticated` + `public` | Public internet | Login required (Better Auth), explicit public URL, stricter `doctor` checks |

The GreetEat deployment runs Paperclip in **`authenticated` + `public`** mode
on **Google Cloud Platform**, so its board operators can reach the dashboard
from anywhere on the public internet behind a real login. Paperclip handles
authentication internally via its built-in Better Auth integration; no
external identity provider is needed.

Paperclip uses **URL-based invitations** rather than email — when an
operator creates an invitation, the dashboard surfaces a one-time URL
(auto-copied to clipboard) which the inviter shares out-of-band through
their preferred channel (Slack, Signal, in person, etc.). No SMTP, no
email provider, and no transactional email infrastructure is required for
this deployment.

There is no Paperclip-published container image and no Paperclip-supplied
cloud install guide; the deployment is composed from Paperclip's documented
runtime requirements (Node.js process listening on a configured port,
PostgreSQL, S3-compatible object storage, an encryption master key, LLM
provider keys) plus GCP primitives chosen during planning.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Board operator signs in to manage GreetEat (Priority: P1)

A GreetEat board operator opens the public Paperclip URL from any
internet-connected browser, signs in via the Better Auth flow, and reaches
their dashboard, where they can view companies, manage agents, approve
work, and inspect activity.

**Why this priority**: This is the entire purpose of the deployment. If a
board operator cannot reach the public URL, log in, and see their dashboard,
nothing else about Paperclip is usable for GreetEat.

**Independent Test**: From an unprivileged network with no VPN, navigate to
the public URL, complete sign-in, and confirm the dashboard renders with
the operator's companies and agents visible. No localhost access, no
bastion, no port-forward.

**Acceptance Scenarios**:

1. **Given** an authorized board operator with valid credentials, **When**
   they navigate to the public URL and sign in, **Then** the dashboard
   loads scoped to their identity within the latency targets in SC-002.
2. **Given** an unauthenticated visitor, **When** they request any
   protected route, **Then** the deployment denies access and redirects
   them to the sign-in page without leaking protected information.
3. **Given** a board operator's session, **When** the session expires,
   **Then** the operator is prompted to re-authenticate and is returned
   to where they were after success, with no loss of unsaved state where
   feasible.

---

### User Story 2 - Operators are admitted by invitation only (Priority: P1)

Board operator accounts are created only by existing operators issuing
invitations. The public URL does not accept open self-registration; an
unsolicited internet visitor cannot create an account through any visible
flow.

**Why this priority**: The dashboard exposed at the public URL controls
GreetEat's entire AI workforce, agent budgets, and approvals. Allowing open
sign-up would put admin-grade access one form submission away from any
internet visitor. This is also the user-confirmed sign-up policy for this
deployment.

**Independent Test**: From an unauthenticated session, attempt to create a
new account through every visible flow (sign-up form, OAuth federation,
direct API). Confirm every path is refused. Then, signed in as an existing
operator, issue an invitation and confirm the invitee can complete sign-up.

**Acceptance Scenarios**:

1. **Given** an internet visitor with no invitation, **When** they attempt
   to register, **Then** the deployment refuses and returns a non-leaky
   message ("registration is by invitation only").
2. **Given** an authorized board operator, **When** they issue an
   invitation through the dashboard, **Then** they receive a one-time
   invitation URL (auto-copied to clipboard) that permits exactly one
   successful account creation when claimed.
3. **Given** an invitation has been used or has expired, **When** the same
   invitation link is replayed, **Then** the deployment refuses it.

---

### User Story 3 - Agents authenticate to the deployment (Priority: P1)

A configured agent runtime (Claude Code, Codex, Gemini, etc.) running on
behalf of one of GreetEat's companies can reach the public Paperclip API,
authenticate as its agent identity, and exchange the requests required to
pick up assignments and report results.

**Why this priority**: Without agent-side auth working against the public
endpoint, the dashboard has no work to display and the deployment is inert.
Equal priority to US1 because Paperclip's value depends on both surfaces.

**Independent Test**: Provision a test agent in the dashboard, configure
its runtime with the issued credential, trigger a heartbeat, and confirm
the agent reaches `/api/agents/me` successfully and processes a task end
to end. Verify the corresponding activity appears in the operator dashboard.

**Acceptance Scenarios**:

1. **Given** a configured agent with a valid credential, **When** the
   runtime calls the public API, **Then** the request is authenticated and
   scoped to the agent's company.
2. **Given** an agent with a missing or invalid credential, **When** it
   calls the API, **Then** the request is rejected and the failure is
   recorded in the audit log.
3. **Given** an agent attempts to access another company's resources,
   **When** the request is made, **Then** it is denied at the authorization
   layer (not only filtered at the UI).

---

### User Story 4 - Operator deploys and updates the stack reproducibly (Priority: P1)

A platform operator can deploy the GreetEat Paperclip stack from this
repository to GCP, and apply subsequent updates, using only configuration
that lives in the repo plus secrets resolved at runtime from the
designated secret store.

**Why this priority**: Required by constitutional principle I (Configuration
as Code). Without it, every change is manual and the constitution is
violated on day one.

**Independent Test**: From a clean target environment, run the documented
deploy procedure end-to-end and confirm US1, US2, and US3 all pass against
the resulting endpoint, with no manual console steps.

**Acceptance Scenarios**:

1. **Given** a clean target environment, **When** the operator runs the
   documented deploy procedure, **Then** the public Paperclip endpoint is
   reachable and US1/US2/US3 acceptance scenarios pass end to end.
2. **Given** the deploy procedure runs, **When** any required secret cannot
   be resolved from the secret store, **Then** the procedure refuses to
   apply and reports which secret is missing.
3. **Given** the deploy procedure runs, **When** Paperclip's `doctor`
   command reports a failure, **Then** the procedure refuses to mark the
   environment as promoted.

---

### User Story 5 - Operator can roll back a bad deployment (Priority: P2)

When a deployment introduces a regression, the operator can roll the
GreetEat Paperclip environment back to the previous known-good state
within a bounded recovery window.

**Why this priority**: Required by constitutional principle III (Reversible
Deployments). Critical, but conditional on US4 existing first.

**Independent Test**: Deploy a known-bad change to the staging environment,
execute the documented rollback, and confirm the environment returns to
the previous revision and US1/US2/US3 still pass.

**Acceptance Scenarios**:

1. **Given** a deployed regression, **When** the operator triggers the
   rollback procedure, **Then** the environment returns to the prior
   known-good revision within the window in SC-005.
2. **Given** a rollback completes, **When** US1/US2/US3 are re-tested,
   **Then** all acceptance scenarios pass.

---

### User Story 6 - Operator can observe the running deployment (Priority: P2)

A platform operator can see logs, metrics, and health signals for every
component of the deployment from a single observability surface, including
authentication events, agent activity, and infrastructure health.

**Why this priority**: Required by constitutional principle V (Observability
by Default). Without it, incidents are unresolvable and US5's rollback
trigger has no evidence base.

**Independent Test**: Generate a synthetic auth-failure burst and a
synthetic agent error. Confirm both events are visible in the operator's
observability surface within SC-006, with enough context to identify the
affected component, time window, and (where applicable) operator or agent
identity.

**Acceptance Scenarios**:

1. **Given** any deployed component, **When** it emits a log or metric,
   **Then** that signal appears in the operator's observability surface
   with correlation identifiers attached.
2. **Given** a sign-in failure burst, **When** the operator queries recent
   auth events, **Then** the burst is visible with source, count, and
   timing.
3. **Given** an agent invocation, **When** the operator traces it, **Then**
   the agent's heartbeats and tool invocations are inspectable end to end
   via correlation IDs.

---

### Edge Cases

- **Auth provider self-outage**: Better Auth runs inside the same Paperclip
  process as the rest of the app, so an "auth outage" implies the whole
  deployment is degraded. The deployment must fail closed rather than
  serving anonymous traffic.
- **Master encryption key missing or wrong** at boot: Paperclip cannot
  decrypt secret references; the deployment must refuse to start rather
  than starting half-functional.
- **Database is unreachable** mid-request: in-flight requests must fail
  cleanly with operator-visible errors; partial writes that leave the DB
  in an inconsistent state are unacceptable.
- **An invited operator never claims their invitation**: the invitation
  must expire and be revocable.
- **A board operator account is compromised**: the operator must be able
  to revoke active sessions and rotate the credential without redeploying.
- **An agent's credential leaks**: revoking it must take effect against
  the live deployment within seconds, not at the next deploy.
- **Sudden traffic spike** (e.g., a launch event): the deployment must
  scale or shed load gracefully, never serve corrupted state.
- **Secret rotation during a live deploy**: in-flight requests must not
  break, and the new secret must take effect within a bounded window.
- **`paperclipai doctor` fails post-deploy**: the deployment must surface
  the failure to operators and not be marked as promoted.

## Requirements *(mandatory)*

### Functional Requirements

**Public access & authentication**

- **FR-001**: The deployment MUST run Paperclip in `authenticated` + `public`
  deployment mode and MUST be reachable from the open internet at a single
  HTTPS URL configured per environment.
- **FR-002**: Authentication MUST be handled by Paperclip's built-in Better
  Auth integration. No external identity provider shall be introduced.
- **FR-003**: The deployment MUST require a successful Better Auth login
  before any board-operator route returns content.
- **FR-004**: Account creation MUST be invitation-only. Open self-service
  registration MUST be disabled at the application layer (not only hidden
  in the UI), and any registration attempt without a valid invitation MUST
  be rejected.
- **FR-005**: Existing board operators MUST be able to issue, list, revoke,
  and expire invitations from the dashboard, and MUST be able to revoke
  another operator's active sessions without a redeploy. Invitations are
  delivered as one-time URLs surfaced directly to the inviter (Paperclip's
  documented invitation flow); the deployment MUST NOT depend on email
  delivery for the invitation flow to work.
- **FR-006**: Unauthenticated requests to protected resources MUST receive
  responses that do not leak protected information (no enumerable IDs, no
  internal hostnames, no stack traces).

**Agent authentication**

- **FR-007**: Agent runtimes MUST be able to authenticate against the
  public API using Paperclip's documented credential mechanisms (short-lived
  JWTs delivered via the heartbeat envelope, or long-lived per-agent API
  keys), with no other auth path accepted.
- **FR-008**: Agents MUST be company-scoped at the authorization layer;
  cross-company access attempts MUST be rejected with a non-leaky response.
- **FR-009**: Operators MUST be able to revoke any agent credential and
  have the revocation take effect against the live deployment within
  seconds, without a redeploy.

**Deployment, change management, and rollback**

- **FR-010**: The deployment MUST be reproducible from this repository plus
  secrets resolved at runtime from a designated secret store; no manual
  console steps may be required for a clean deploy.
- **FR-011**: The deployment procedure MUST be runnable end-to-end by an
  authorized operator from a single documented entry point.
- **FR-012**: Every change to the deployment MUST have a documented and
  tested rollback path before it is applied to production.
- **FR-013**: The deployment procedure MUST refuse to apply if the source
  repository has uncommitted changes, if any required secret cannot be
  resolved, or if `paperclipai doctor` reports a failure against the target
  environment.
- **FR-014**: Because Paperclip does not publish a container image, the
  deployment pipeline MUST build a Paperclip container image from a pinned
  source revision and store it in a registry under an immutable reference
  (digest or version tag), and MUST refuse to deploy a floating tag.

**Runtime topology**

- **FR-015**: The Paperclip server process MUST be deployed as a long-lived
  containerized service exposed on its configured port behind an HTTPS
  termination layer; serverless execution models that do not support
  long-lived stateful processes (e.g., short-lived edge functions) MUST
  NOT be used to host the Paperclip process.
- **FR-016**: The deployment MUST use a managed PostgreSQL service capable
  of supporting Paperclip's published version requirements; the embedded
  development database MUST NOT be used for any environment past local.
- **FR-017**: The deployment MUST use an S3-compatible object store for
  Paperclip's uploaded files; the local-filesystem storage backend MUST
  NOT be used past local development.
- **FR-018**: The choice of managed PostgreSQL provider and object-store
  provider is a planning-phase decision and is intentionally not fixed by
  this spec; the chosen providers MUST satisfy the operational requirements
  in this section.

**Observability & operations**

- **FR-019**: Every deployed component MUST emit structured logs, health
  signals, and operational metrics from its first deployment.
- **FR-020**: Authentication events (sign-up, sign-in, sign-in failure,
  account lockout, invitation issuance, session revocation) MUST be
  recorded in an audit-grade log retained for at least 90 days.
- **FR-021**: Agent activity MUST be traceable end-to-end with correlation
  identifiers linking a heartbeat to its agent run, the tasks it touched,
  and the tool invocations it produced.
- **FR-022**: The deployment MUST report a single overall health status
  that an external monitor can query without authentication.

**Security & blast radius**

- **FR-023**: Credentials and secrets MUST never appear in source files,
  build logs, runtime logs, or container images at any verbosity level.
- **FR-024**: Paperclip's secret-encryption master key MUST be supplied
  from a managed secret store at boot and MUST NOT be persisted on the
  container image or in any unencrypted runtime location. Strict secret
  mode MUST be enabled for sensitive variables.
- **FR-025**: Paperclip and any sidecar processes MUST execute with the
  minimum privileges required to serve their role; broad administrative
  cloud credentials MUST NOT be attached to the Paperclip runtime.
- **FR-026**: The deployment MUST enforce documented resource ceilings
  (compute, memory, and per-agent monthly budget) and MUST refuse work
  that would exceed them rather than failing unbounded.
- **FR-027**: The deployment MUST be cost-bounded by an explicit monthly
  budget with alerting before forecasted spend reaches the ceiling.

### Key Entities

- **Board Operator**: A human authorized to configure GreetEat companies,
  manage agents, approve work, and observe activity. Authenticated via
  Better Auth (cookie session). Created by invitation only.
- **Invitation**: A one-time, expirable URL/token issued by an existing
  board operator that permits exactly one new operator to register. Carries
  issuer identity, target identifier, expiry, and audit trail. Delivered
  out-of-band by the inviter (not by Paperclip).
- **Agent**: An AI runtime registered to a company in Paperclip and
  authorized to call the API on that company's behalf. Authenticates via
  short-lived JWT or long-lived API key.
- **Company**: A logical Paperclip organization owned by board operators,
  containing agents, goals, tasks, and budgets. Authorization boundary for
  agent and operator access.
- **Deployment**: A specific running instance of GreetEat Paperclip on GCP,
  identified by environment name and a known revision corresponding to a
  commit in this repo.
- **Authentication Event**: A record of any sign-up, sign-in, sign-in
  failure, invitation issuance, account state change, or session
  revocation. Carries timestamp, source identifier, outcome, and
  correlation ID.
- **Agent Run**: A bounded unit of agent activity initiated by a heartbeat
  or event. Carries a correlation ID linking it to the requests it makes
  back into Paperclip and the tasks it touches.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The public URL is reachable and serving authenticated
  dashboard sessions at least 99.5% of any rolling 30-day window, measured
  by an external monitor.
- **SC-002**: A returning board operator can complete sign-in and reach
  their dashboard in under 10 seconds from landing on the public URL, on
  a typical broadband connection.
- **SC-003**: An invited new operator can complete their invitation flow
  and reach the dashboard for the first time in under 5 minutes from
  receiving the invitation URL.
- **SC-004**: From a clean target environment, an authorized operator can
  complete a full deploy producing a working public endpoint within a
  single working session, with no manual console steps.
- **SC-005**: An operator can roll back the production environment to the
  previous known-good revision within 30 minutes of triggering rollback,
  measured from rollback trigger to all P1 acceptance scenarios passing.
- **SC-006**: Any authentication or agent event is queryable in the
  observability surface within 2 minutes of occurring.
- **SC-007**: Zero confirmed incidents of unauthorized account creation,
  cross-company data exposure, or master-key exposure in any audit period.
- **SC-008**: Forecasted monthly spend stays within the declared budget
  ceiling; spend forecast is reviewed at least weekly and operators are
  alerted before the ceiling is reached, not after.
- **SC-009**: `paperclipai doctor` returns a clean result against
  production at least once per day, and any failure is surfaced to
  operators within the latency in SC-006.

## Assumptions

The following defaults are assumed in the absence of explicit direction.
Each is reversible by amending this spec.

- **Auth provider**: Paperclip's built-in Better Auth integration is the
  sole authentication mechanism. No third-party IdP (Cognito, Auth0,
  Google SSO, etc.) is in scope.
- **Sign-up policy**: Invitation-only, confirmed by the user. Open
  self-service registration is explicitly out of scope.
- **User shape**: All human users of this deployment are GreetEat board
  operators. There is no consumer-facing surface and no "end user" sign-up
  experience.
- **Agent runtimes**: Out of scope of this spec — agents are configured
  per company by board operators after the deployment exists. This spec
  only requires that the public API accepts authenticated agent traffic.
- **Region**: A single GCP region is assumed for the initial deployment.
  `us-central1` is the chosen region (matches the existing
  `paperclip-492823` project's defaults). Multi-region failover is out
  of scope.
- **Email infrastructure**: None. Paperclip's invitation flow is
  URL-based (auto-copied to clipboard, shared out-of-band by the inviter).
  No SMTP, no transactional email provider, and no Workspace SMTP relay
  is in scope. If a future feature introduces an email-dependent flow
  (password reset, security alerts, etc.), this spec MUST be amended
  before that feature is built.
- **LLM provider**: Anthropic Claude via **Vertex AI Model Garden**
  on `paperclip-492823`. Claude Sonnet 4.6 was confirmed live with a
  successful predict call on 2026-04-10. **Verified end-to-end on the
  same day** with a local Paperclip instance: an issue was assigned to
  a Claude agent, Paperclip's `claude_local` adapter spawned Claude
  Code, and the agent ran multi-turn tool calls against Vertex AI
  Claude Sonnet 4.6 — every message ID had the `msg_vrtx_*` Vertex
  prefix and `apiKeySource: "none"`. Authentication uses the Cloud Run
  service account's `roles/aiplatform.user` permission, so **no
  long-lived Anthropic API key in any form sits in Secret Manager** —
  Claude Code picks up the service account's identity automatically
  when `CLAUDE_CODE_USE_VERTEX=1` is set. OpenAI / Codex agents are
  out of scope for v1.
- **Tenancy**: Single-tenant deployment for GreetEat. Multi-tenant
  isolation between unrelated customers is out of scope.
- **Environments**: **Single environment** for v1. The single environment
  is treated as production from a process standpoint. This is an
  explicit, documented departure from constitutional principle II
  (Environment Parity), justified in `plan.md` Complexity Tracking by
  the size of the GreetEat operator group, the absence of a second
  tenant, and the billing-access constraint that originally drove the
  shared-project decision.
- **Hosting project**: The deployment lives in a dedicated GCP project
  `paperclip-492823` (display name `paperclip`, project number
  `280667224791`), parented to the `greeteat.com` organization. The
  project ID was auto-suffixed at creation because the friendly ID
  was taken globally. Billing (`01BCB7-61A725-D6A2B5`) was attached
  on 2026-04-10. **No other GreetEat workloads share the project.**
  Resource naming (`paperclip-*` / `paperclipai-*`) and the
  `service=paperclip` label remain in place as good practice for
  cost attribution and IAM hygiene, not as collision-avoidance
  requirements.
- **Compliance regime**: No specific regime (GDPR, HIPAA, SOC 2, etc.) is
  assumed to apply. If one does, this spec MUST be amended before
  implementation begins.
- **End-user device**: Modern desktop or mobile browser. Legacy browser
  support is out of scope.
- **Network reachability**: Public IPv4 reachability is required;
  IPv6-only access is out of scope for v1.
- **Budget ceiling**: An explicit monthly cost ceiling will be declared by
  the operator before the first production deploy; the exact figure is
  not fixed by this spec.

### Decisions resolved in planning

The constraint set evolved across several pivots: AWS → GCP, dedicated
project → shared `paperclip-492823` project, two environments → single
environment, Anthropic API key → Vertex AI Claude (no long-lived key),
external IdP → built-in Better Auth, email-based invitations → URL-based
invitations. Every sub-component choice is locked here against the
final constraint set:

- **Hosting project**: Dedicated `paperclip-492823` (display name
  `paperclip`), parented to greeteat.com org, billing
  `01BCB7-61A725-D6A2B5` attached 2026-04-10. No co-tenant workloads.
- **Environments**: One. Single-environment deployment, with a Complexity
  Tracking entry in `plan.md` documenting the departure from principle II.
- **Region**: `us-central1`.
- **Application host**: Cloud Run with `min-instances ≥ 2` (long-lived,
  managed serverless containers, native HTTPS, VPC connector to Cloud SQL).
- **Managed PostgreSQL provider**: Cloud SQL for PostgreSQL 17, regional
  HA, single instance.
- **Object storage provider**: Google Cloud Storage, accessed via its
  S3-compatible interop API to satisfy Paperclip's S3 storage backend.
  HMAC interop credentials in Secret Manager.
- **Secret store**: GCP Secret Manager, with secrets mounted into the
  Cloud Run service at deploy time.
- **TLS / DNS edge**: Cloud Run domain mapping (Google-managed cert) +
  Cloud DNS for the public hostname; Global HTTPS LB + Cloud Armor
  revisited in a follow-up if WAF/CDN is needed.
- **Container image build pipeline**: GitHub Actions → Artifact Registry,
  authenticated via project-scoped Workload Identity Federation (no
  service account JSON keys).
- **LLM provider**: Anthropic Claude via Vertex AI Model Garden (Sonnet
  4.6 confirmed live on 2026-04-10), authenticated via Cloud Run service
  account's `roles/aiplatform.user` — no long-lived Anthropic API key.
- **Email**: None. Paperclip uses URL-based invitations.
- **Resource namespacing**: All Paperclip-managed resources SHOULD use
  the `paperclip-` or `paperclipai-` prefix and carry the
  `service=paperclip` label for cost attribution and quick filtering
  in the GCP console. With a dedicated project this is no longer a
  collision-avoidance concern, but remains good operational hygiene.

Rationale and rejected alternatives for each are captured in `research.md`.
