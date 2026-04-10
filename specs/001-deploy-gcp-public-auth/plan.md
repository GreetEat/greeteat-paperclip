# Implementation Plan: Deploy Paperclip to GCP in Public Authentication Mode

**Branch**: `001-deploy-gcp-public-auth` | **Date**: 2026-04-09 | **Last updated**: 2026-04-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `specs/001-deploy-gcp-public-auth/spec.md`
**Constraints**: GCP-native, no AWS, no Supabase, no email infrastructure,
**hosted in the dedicated `paperclip-492823` project** (no co-tenant
workloads), **single environment** for v1, **Claude via Vertex AI**
with no long-lived Anthropic API key, **CI-only deployment** (no local
Terraform workflow planned).

## Summary

Deploy a single GreetEat instance of Paperclip's open-source control plane
inside the **existing `paperclip-492823` GCP project** (project number
`233990667256`, parented to the `greeteat.com` organization). The project
already has billing attached (`01BCB7-61A725-D6A2B5`) and Victor holds
`roles/owner`, so the deployment can proceed without further org-level
escalation.

The Paperclip Node.js process runs as a **Cloud Run service** with
`min-instances=2` (always warm, no cold start, rolling deploys never drain
to zero), fronted by Cloud Run's built-in HTTPS endpoint mapped to a
custom domain via **Cloud Run domain mappings** with a Google-managed
TLS certificate. State lives in **Cloud SQL for PostgreSQL 17 (regional
HA)**; uploaded files live in **Google Cloud Storage** accessed via the
S3-compatible interop API; secrets live in **GCP Secret Manager** mounted
into the Cloud Run service at deploy time.

The Paperclip container image is built from a pinned upstream Paperclip
release in **GitHub Actions**, authenticated to GCP via **project-scoped
Workload Identity Federation** (no service account JSON keys), and
pushed to **Artifact Registry** with an immutable digest reference; the
digest is the only thing the Terraform service definition trusts.

The LLM provider is **Anthropic Claude via Vertex AI Model Garden** —
Claude Sonnet 4.6 was confirmed live in this project on 2026-04-10 with
a successful predict call. Authentication is via the Cloud Run service
account's `roles/aiplatform.user` permission, so **no long-lived
Anthropic API key sits in Secret Manager** (one open verification: see
the Followups in `research.md` for whether Paperclip's `claude_local`
adapter preflight requires `ANTHROPIC_API_KEY` to be set as a stub).

After every deploy, `paperclipai doctor` runs as a one-shot **Cloud Run
Job** against the same image and resolved secrets; the job's exit code
is the deploy gate. **Cloud Scheduler** re-runs the doctor job daily,
and **Cloud Monitoring** alerts on any failure. The deployment ships
**no email infrastructure** — board operator invitations are URL-based.

This plan documents an explicit departure from constitutional Principle
II (Environment Parity): we deploy a single environment instead of two,
justified in the Complexity Tracking section below.

## Technical Context

**Hosting project**: `paperclip-492823` (dedicated, display name
`paperclip`). Project number `233990667256`. Parent: `greeteat.com`
org `768469506142`. Billing: `01BCB7-61A725-D6A2B5` (attached
2026-04-10). **No co-tenant workloads**. Paperclip resources are
prefixed `paperclip-*` / `paperclipai-*` and labeled
`service=paperclip` as good practice for cost attribution and IAM
hygiene.

**Region**: `us-central1` (matches the operator's gcloud default).

**Runtime (deployed application)**: Paperclip — Node.js + Express.js +
React (Vite) UI, served from a single process on a configured port.
Pinned to a known Paperclip release tag (set in
`infra/envs/prod/versions.tfvars`).

**Database**: GCP Cloud SQL for PostgreSQL 17, **regional HA** (single
instance, treated as production), private IP only, accessed from Cloud
Run via a Serverless VPC Connector. Drizzle ORM migrations applied by
Paperclip on container boot.

**Object storage**: One private GCS bucket (`paperclip-492823-uploads`)
with uniform bucket-level access enforced and public access prevention
enabled. Versioning enabled. Accessed by Paperclip via the **GCS S3
interop API** using HMAC keys stored in Secret Manager.

**Secrets**: GCP Secret Manager. Stores `PAPERCLIP_SECRETS_MASTER_KEY`,
`DATABASE_URL`, the GCS interop HMAC access ID and secret. **Notably
absent**: no `ANTHROPIC_API_KEY` (Vertex Claude uses service account
auth — verified end-to-end on 2026-04-10) and no `OPENAI_API_KEY`
(OpenAI/Codex agents are out of scope). Cloud Run mounts these as env
vars at deploy time. Strict secret mode
(`PAPERCLIP_SECRETS_STRICT_MODE=true`) is set in the service env.

**Application host**: GCP Cloud Run (fully managed). One service,
`min-instances=2` so the service is always warm and rolling deploys
never drain to zero. Cloud Run injects `PORT` at launch, and Paperclip's
documented `PORT` env var honors it directly. Container listens on
`0.0.0.0:$PORT` (set `HOST=0.0.0.0` in the service env, since Paperclip
defaults to `127.0.0.1`).

**LLM provider**: Anthropic Claude via Vertex AI Model Garden.
Claude Sonnet 4.6 verified live on `paperclip-492823` on 2026-04-10
with a `200 OK` predict response. Cloud Run service env carries
`CLAUDE_CODE_USE_VERTEX=1`, `CLOUD_ML_REGION=global`,
`ANTHROPIC_VERTEX_PROJECT_ID=paperclip-492823`,
`ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6`. The service
account holds `roles/aiplatform.user`. Paperclip's `claude_local`
adapter spawns Claude Code, which inherits the service env and uses
Vertex auth — no Anthropic API key needed at runtime.
**Verified end-to-end on 2026-04-10**: a local Paperclip instance
configured against Vertex Claude Sonnet 4.6 (with no `ANTHROPIC_API_KEY`
set anywhere) successfully ran multi-turn Claude agent tasks. Every
Vertex message ID in the agent's run log had the `msg_vrtx_*` prefix
and `apiKeySource: "none"`, conclusively proving Paperclip's preflight
accepts the unset state and the spawned Claude Code authenticates
purely via Vertex.

**Public edge**: Cloud Run **domain mapping** with a Google-managed TLS
certificate, plus a Cloud DNS hosted zone for the deployment domain.
HTTP-to-HTTPS is automatic on Cloud Run. A Global External HTTPS Load
Balancer + Cloud Armor is deferred to a follow-up — domain mappings
are sufficient for the spec's requirements.

**Email**: None. Out of scope per spec assumption "Email infrastructure".

**IaC tool**: Terraform with the `google` and `google-beta` providers,
state in a GCS bucket inside `paperclip-492823` (`paperclip-tf-state`),
object versioning on for state safety, provider versions pinned in
`.terraform.lock.hcl`. GCS-backed Terraform state has built-in
object-level locking via the Google provider, so no external lock
service is needed.

**Container image build**: GitHub Actions workflow builds from a pinned
Paperclip git tag, runs Trivy and Hadolint, authenticates to GCP via
**project-scoped** Workload Identity Federation, and pushes to a new
`paperclip` repository in Artifact Registry inside `paperclip-492823`
with `<paperclip-version>` and `<git-sha>` tags plus the immutable
digest. Terraform pins the digest, never a tag.

**Testing for deployment artifacts**: `terraform validate`, `tflint`
with the Google ruleset, `checkov` (security/compliance scan), Hadolint
on the Dockerfile, Trivy image scan, and a post-deploy smoke test that
exercises the spec's P1 acceptance scenarios against the deployed
environment.

**Target Platform**: GCP, single region (`us-central1`), single
environment. No multi-region failover for v1.

**Project Type**: Deployment configuration / infrastructure-as-code.
This repo deploys an external open-source application; it does not
contain the application source code itself.

**Performance Goals (from spec success criteria)**:
- 99.5% public-endpoint availability (SC-001)
- < 10s sign-in latency (SC-002)
- < 30 min rollback recovery time (SC-005)
- < 2 min observability ingestion latency (SC-006)

**Constraints**:
- Constitutional principles I, III, IV, V (II is intentionally violated;
  see Constitution Check + Complexity Tracking below)
- Resource ceilings per FR-026 (compute, memory, per-agent budget)
- Monthly cost ceiling per FR-027 (declared at deploy time, not in spec)
- GCP-native only (user constraint)
- No Supabase (user constraint)
- No email infrastructure (Paperclip design)
- No long-lived Anthropic API key (resolved by Vertex; preflight
  verified end-to-end on 2026-04-10)
- **Dedicated GCP project** — no co-tenant workloads. Resource prefixes
  (`paperclip-` / `paperclipai-`) and `service=paperclip` labels are
  still applied as good practice for cost attribution and IAM hygiene.
- **Single environment** — Principle II departure; see Complexity Tracking

**Scale/Scope**: Single tenant (GreetEat). ≤ 50 board operators
initially, moderate agent count, single region, single environment.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-evaluated after Phase 1 design.*

| Principle | Pre-research check | Post-design check |
|-----------|--------------------|---|
| **I. Configuration as Code (NON-NEGOTIABLE)** | ✅ Terraform manages every Paperclip-introduced GCP resource (APIs enabled, VPC, Cloud SQL, GCS, Secret Manager, Cloud Run service, domain mapping, Cloud DNS, Artifact Registry, Cloud Monitoring). Image digest pinned in TF state. Secret values referenced (not embedded). Zero GCP console steps in the deploy procedure. **One exception**: enabling Claude in Vertex AI Model Garden is an inherently console-only step on GCP today; documented in `quickstart.md` as a one-time prerequisite, already done on 2026-04-10. | ✅ Confirmed by Phase 1 design — see `infra/` layout below. |
| **II. Environment Parity** | ❌ **Intentional violation.** Single environment for v1. See Complexity Tracking below for the justification, the risks, and the simpler-alternative-rejected reasoning. | ❌ Same as pre-check; mitigations in place (full doctor on every deploy, full smoke test, mandatory rollback gate). |
| **III. Reversible Deployments** | ✅ Cloud Run preserves prior revisions and supports `gcloud run services update-traffic --to-revision` for instant traffic shift back to a previous revision. Terraform state in GCS with object versioning. Rollback procedure documented and time-bounded by SC-005. **Compensating control for the Principle II departure**: doctor + smoke test gates are mandatory (`--skip-doctor` / `--skip-smoke` flags removed from `deploy.sh` entirely). | ✅ Confirmed — see `quickstart.md` rollback section and `contracts/rollback-cli.md`. |
| **IV. Secrets Discipline** | ✅ All secrets in Secret Manager. Cloud Run mounts them at deploy. Master key bootstrapped via one-shot script and never persisted to disk in the build context, the image, or the runtime container filesystem. Strict secret mode (`PAPERCLIP_SECRETS_STRICT_MODE=true`) set in the service env. Workload Identity Federation eliminates long-lived service account keys in CI. **Vertex Claude eliminates the long-lived Anthropic API key entirely** (one fewer secret) — modulo the preflight stub. | ✅ Confirmed — see `data-model.md` secret entities and `contracts/container-image.md`. |
| **V. Observability by Default** | ✅ Cloud Run automatically ships container stdout/stderr to Cloud Logging. Cloud Monitoring metrics + alerting policies provisioned in the same TF apply for: Cloud Run 5xx, instance count, Cloud SQL CPU and connections, Cloud Storage error rate, daily doctor failure. Cloud Monitoring **Uptime Check** runs cross-region against `/health`. Audit logs (auth events) routed to a separate log bucket with 90-day retention. | ✅ Confirmed — see `infra/modules/observability` layout below. |

**Operational Constraints check:**
- **Resource ceilings**: Cloud Run service declares CPU + memory + max
  instances; Cloud SQL instance tier capped in tfvars; per-agent monthly
  budget enforced inside Paperclip itself. ✅
- **Agent sandboxing**: Cloud Run service runs as a per-deployment
  service account `paperclip-runtime-sa` that has only:
  `roles/secretmanager.secretAccessor` on its own secrets,
  `roles/storage.objectUser` on its own bucket,
  `roles/cloudsql.client` on its own DB,
  `roles/aiplatform.user` for Vertex Claude calls, and
  `roles/logging.logWriter` project-wide. **Crucially: never the
  default Compute service account**, which exists in `paperclip-492823`
  with broad legacy privileges. ✅
- **Change blast radius**: One Terraform module per logical concern.
  PRs touch one concern at a time. Dedicated project means no risk
  of Paperclip changes affecting unrelated workloads. ✅
- **Dependency pinning**: Paperclip release tag pinned in tfvars;
  Artifact Registry image referenced by digest in service spec; Cloud SQL
  engine version pinned; Terraform provider versions pinned in lockfile.
  Claude Code's Sonnet model pinned via `ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6`. ✅

**Result: PASS with one documented violation** (Principle II — see
Complexity Tracking).

## Project Structure

### Documentation (this feature)

```text
specs/001-deploy-gcp-public-auth/
├── spec.md                  # Feature specification
├── plan.md                  # This file (Phase 0/1 output)
├── research.md              # Phase 0 output — locked decisions + rationale
├── data-model.md            # Phase 1 output — deployed-resource model
├── quickstart.md            # Phase 1 output — operator first-deploy guide
├── contracts/               # Phase 1 output — deployment interface contracts
│   ├── container-image.md
│   ├── deploy-cli.md
│   ├── rollback-cli.md
│   └── public-endpoint.md
├── checklists/
│   └── requirements.md      # Spec quality checklist
└── tasks.md                 # Phase 2 output (NOT created by /speckit-plan)
```

### Source Code (repository root)

This is a deployment-configuration repo, not an application repo.

```text
infra/
├── modules/                          # Reusable Terraform modules
│   ├── apis/                         # Enable required APIs in paperclip-492823
│   ├── network/                      # paperclip-vpc, subnet, Serverless VPC Connector
│   ├── database/                     # paperclip-pg (Cloud SQL Postgres 17), private IP, backups
│   ├── storage/                      # paperclip-uploads bucket, HMAC service account, lifecycle
│   ├── secrets/                      # paperclip-* secrets in Secret Manager + IAM bindings
│   ├── compute/                      # paperclip Cloud Run service, paperclip-runtime-sa, IAM
│   ├── edge/                         # Cloud Run domain mapping, Cloud DNS records
│   ├── jobs/                         # paperclipai-doctor Cloud Run Job
│   ├── scheduler/                    # paperclipai-doctor-daily Cloud Scheduler trigger
│   ├── artifact-registry/            # paperclip Artifact Registry repo + IAM
│   ├── workload-identity/            # Project-scoped WIF pool + GitHub provider
│   └── observability/                # Log routers, metric alerts, uptime check
├── envs/
│   └── prod/                         # Single environment for v1
│       ├── main.tf                   # Composes modules
│       ├── backend.tf                # GCS state backend (paperclip-492823/paperclip-tf-state)
│       ├── terraform.tfvars          # Region, domain, paperclip_version, image_digest, sizing
│       └── versions.tfvars           # paperclip_version + paperclip_image_digest
├── docker/
│   ├── Dockerfile                    # Multi-stage build of pinned Paperclip release
│   └── entrypoint.sh                 # Boot script: env validation → migrations → server
└── scripts/
    ├── bootstrap-master-key.sh       # One-time: generate 32-byte key → Secret Manager
    ├── bootstrap-gcs-hmac.sh         # One-time: create HMAC for GCS interop → Secret Manager
    ├── deploy.sh                     # plan + apply + run doctor job + smoke test
    ├── rollback.sh                   # gcloud run services update-traffic --to-revision <prev>
    └── doctor.sh                     # Wrap gcloud run jobs execute paperclipai-doctor

.github/
└── workflows/
    ├── build-image.yml               # Build + scan + push paperclip image to Artifact Registry
    ├── terraform-plan.yml            # PR-time: terraform plan against prod
    └── deploy.yml                    # On main merge (or manual): deploy.sh
```

**Structure Decision**: Single deployment repo with one Terraform module
tree (`infra/modules/`) instantiated **once** in `infra/envs/prod/`
(single environment). `infra/envs/staging` is intentionally absent —
single environment per the Complexity Tracking entry. Each module
corresponds to one logical concern, satisfying the constitution's
"one logical concern per change" rule. The `apis/` module enables
the Paperclip-required APIs in the existing project (project create
itself is a manual operator prerequisite per the quickstart). The
`workload-identity/` module sets up project-scoped WIF for GitHub
Actions — project-scoped because the operator does not hold org-level
WIF permissions and project-scoped pools work identically for the
GitHub → GCP path.

## Phase 0 → research.md

All major technology decisions are locked in [research.md](./research.md).
12 decisions are recorded, each with rationale and rejected alternatives:
Cloud Run vs alternatives, Terraform vs CDKtf/Pulumi, Cloud SQL Postgres
17, GCS + S3 interop, Secret Manager + master-key bootstrap, Cloud Run
domain mapping vs Global LB, Workload Identity Federation for GitHub
Actions → Artifact Registry (project-scoped), `paperclipai doctor` as a
Cloud Run Job, Cloud Logging + Monitoring + Uptime checks, the
shared-project decision (replacing the earlier multi-project plan),
image build inputs and version pinning, and the explicit "no email
infrastructure" decision. The Vertex Claude path is locked as the LLM
provider with empirical verification recorded. No `NEEDS CLARIFICATION`
items remain. Open follow-ups (e.g. master-key rotation cadence,
schema-drift CI gate, SBOM generation, Global LB + WAF for production
traffic) are recorded as `Followups` and do not block Phase 1. The
Paperclip `claude_local` preflight verification followup has been
resolved as of 2026-04-10 — see research.md Decision 5.

## Phase 1 → data-model.md, contracts/, quickstart.md

- [data-model.md](./data-model.md) — Models the deployed GCP resource
  graph inside the shared `paperclip-492823` project, the application-level
  entities the spec defines (Board Operator, Invitation, Agent, Company,
  Authentication Event, Agent Run), and the persistence rules +
  lifecycle/state transitions for each.
- [contracts/](./contracts/) — Four interface contracts the deployment
  exposes to its operators and to the running Paperclip process:
  - `container-image.md` — env-var inputs (including the new Vertex env
    vars) and port output
  - `deploy-cli.md` — `./scripts/deploy.sh` arguments, env, exit codes
    (single-env, no `--skip-doctor` / `--skip-smoke` flags)
  - `rollback-cli.md` — `./scripts/rollback.sh` arguments and behavior
    (single-env, `--reason` always required)
  - `public-endpoint.md` — externally observable behavior of the public
    HTTPS URL (auth flows, error responses, health endpoint)
- [quickstart.md](./quickstart.md) — Operator's first-deploy walkthrough,
  from "shared `paperclip-492823` project with billing" to "US1/US2/US3
  acceptance scenarios pass."

## Complexity Tracking

> **Constitutional violations that must be justified.** This section is
> normally empty. The single-environment departure below is the only
> entry.

| Violation | Why needed | Simpler alternative rejected because |
|-----------|------------|-------------------------------------|
| **Single-environment deployment** (departs from Principle II — Environment Parity, which requires "at least two environments — staging and production") | (a) **User direction**: the operator explicitly scoped this to a single environment ("we only need prod") on 2026-04-09 and confirmed it again on 2026-04-10 after the original billing-access blocker was resolved. (b) **Bounded blast radius**: GreetEat's operator group is small (≤ 50), Paperclip is an internal admin tool, not a customer-facing product. A bad single-env deploy affects internal operators only, not paying customers. (c) **Cost**: a second environment doubles the cloud-spend baseline (Cloud SQL HA is the dominant cost) for an internal admin tool that would otherwise have very low ongoing cost. (d) **Operational shape**: the deployment is rolled out from CI via WIF, doctor + smoke gates run on every deploy, and rollback is a one-command Cloud Run revision shift. The "implicit early-warning" benefit two-env normally provides is replaced by stronger gating and a daily live-environment doctor sweep. | Two environments via two GCP projects: doubles ongoing Cloud SQL + Cloud Run baseline cost for marginal benefit at this operator scale. Two environments via two distinct deployments inside the same project: defeats the isolation goal that motivates the principle (a misconfig in the "staging" deployment could affect the "production" deployment) and doubles the IAM/resource bookkeeping. Two environments where staging is a smaller/cheaper Cloud Run instance pointing at the same Cloud SQL: couples the data layer and creates the worst kind of false-isolation. |

**Mitigations to compensate for the missing staging environment:**

1. **Mandatory doctor + smoke gates on every deploy.** `deploy.sh` no
   longer accepts `--skip-doctor` or `--skip-smoke` flags at all (not
   even hidden behind a confirm). Every deploy runs both gates against
   the live service before traffic is shifted.
2. **Cloud Run revision-pinned rollback** is the primary recovery path
   instead of "promote staging again." Rollback target is always the
   immediately previous live revision and is verified to be reachable
   via the Cloud Run API at preflight time.
3. **`paperclipai doctor` runs daily** via Cloud Scheduler against the
   live deployment, with a Cloud Monitoring alert on failure. This
   replaces the implicit "we'd notice it in staging first" detection
   that two-env normally provides.
4. **Image upgrades are gated through PR review** of the pinned digest
   in `versions.tfvars`. The CI build runs Trivy + Hadolint + a smoke
   test of the image before the digest is even available for the
   tfvars bump. This catches integration issues at build time rather
   than at deploy time.
5. **Schema migrations are flagged for manual coordination** until the
   schema-drift CI gate (research.md Decision 3 followup) is built.
   Until then, any deploy that includes a Drizzle migration must be
   announced to all operators and reviewed against the rollback plan.
6. **`/speckit-clarify` bookmark**: when GreetEat scales beyond ≤ 50
   operators, or Paperclip becomes customer-facing, this Complexity
   Tracking entry should be revisited. The fix is "create a second
   GCP project (`paperclip-staging`) with billing attached, copy the
   Terraform module set into a parallel `infra/envs/staging/`, and
   pin a smaller Cloud SQL tier." The data-model document and
   contracts already enumerate everything that would need to be
   instantiated for a second environment.

**Re-evaluation trigger**: This Complexity Tracking entry MUST be
revisited if any of: (a) GreetEat operator count exceeds 50,
(b) Paperclip becomes customer-facing for GreetEat in any way,
(c) a second GreetEat tenant emerges that needs isolated Paperclip
access, (d) the user explicitly requests a staging environment.
Any of these conditions makes the cost of maintaining the Principle II
departure higher than the cost of standing up a second environment.
