# Research: Deploy Paperclip to GCP in Public Authentication Mode

**Date**: 2026-04-09
**Last updated**: 2026-04-10
**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)
**Constraints**: GCP-native, no AWS, no Supabase, no email infrastructure,
shared `paperclip-492823` project, single environment, Vertex Claude.

This document records the technology decisions that resolve the Phase 0
unknowns and the rationale + alternatives for each. Every decision below
is binding unless explicitly amended.

---

## Decision 1 — Application host: Cloud Run

**Decision**: Run the Paperclip container as a managed **Cloud Run service**
inside the shared `paperclip-492823` project. `min-instances=2` so the
service is always warm and rolling deploys never drain the live revision
to zero. Container concurrency = 80 (Cloud Run default), CPU = 2 vCPU,
memory = 2 GiB (revisited at first cost review). Egress to Cloud SQL
routed through a Serverless VPC Connector into the project VPC. Service
named `paperclip` (not `paperclip-prod`) — the single-environment plan
makes the suffix unnecessary.

**Rationale**:
- Paperclip is a single long-lived Node.js process whose state lives in
  Postgres + GCS — no local-disk dependence — which makes it a clean fit
  for Cloud Run's stateless container model.
- Cloud Run is the lowest-toil GCP option: no nodes, no node pools, no
  cluster upgrades, automatic HTTPS termination, native Secret Manager
  integration, native VPC connector, native Cloud Logging/Monitoring
  integration.
- `min-instances=2` eliminates cold starts for the public dashboard and
  lets Cloud Run roll new revisions in without traffic landing on a
  zero-instance pool. (Earlier drafts had `min-instances=1` for staging
  and `min-instances=2` for prod; with single-env we go straight to 2.)
- Cloud Run preserves prior revisions and supports
  `gcloud run services update-traffic --to-revision REV --to-traffic 100`
  for instant rollback — directly satisfies constitutional principle III
  AND is the primary mitigation for the Principle II single-env departure.
- Per-instance CPU + memory ceilings are first-class — satisfies the
  operational constraint on resource ceilings without extra tooling.

**Alternatives considered**:
- **GKE Autopilot** — managed Kubernetes pays a control-plane cost
  ($73/month minimum) and adds Kubernetes operational surface area for
  one container. Massive overkill at this scale. Rejected.
- **GKE Standard** — even more operational overhead than Autopilot.
  Rejected.
- **Compute Engine + a managed instance group** — we'd manage VMs,
  patching, image baking, and Ops Agent ourselves. Contradicts the
  "managed everything" stance of the rest of the stack. Rejected.
- **App Engine Flex** — older serverless container product, less
  active development than Cloud Run, similar but worse integration with
  modern GCP services. Rejected.
- **Cloud Functions / 2nd gen** — invocation model is per-request and
  ephemeral, incompatible with a long-lived stateful Express server, and
  forbidden by spec FR-015. Rejected.

**Followups**:
- Revisit CPU + memory sizing at first cost review.
- Cloud Run does not support sticky sessions; verify Better Auth's
  session storage is database-backed (it should be — Drizzle ORM is in
  the stack). If Better Auth ever uses in-memory sessions, this plan
  must be revisited.
- Cloud Run's max request body is 32 MiB on HTTP/1; Paperclip uploads
  may need HTTP/2 to exceed this. Confirm before the first production
  upload.

---

## Decision 2 — IaC tool: Terraform

**Decision**: Terraform with the `google` and `google-beta` providers,
state in a GCS backend bucket inside `paperclip-492823` named
`paperclip-tf-state` (with object versioning enabled), provider versions
pinned in `.terraform.lock.hcl`. No external lock service required —
the GCS backend uses object-level locking via the Google provider.

**Rationale**:
- Plain HCL is reviewable in PRs without a TypeScript build step in the
  loop.
- Plan/apply with explicit, persisted state is the easiest model for the
  constitution's "Configuration as Code" and "Reversible Deployments"
  principles — `terraform plan` is the dry run, GCS object versioning
  is the audit trail, and rolling back is `terraform apply` against an
  older pinned configuration.
- Wide ecosystem and a mature `google` provider with first-class support
  for every GCP resource we use.
- No language coupling — anyone can read it without learning a framework.

**Alternatives considered**:
- **CDK for Terraform (CDKtf) in TypeScript** — adds an indirection
  layer (CDKtf synthesizes HCL/JSON which Terraform then applies).
  Drift diagnosis becomes a three-layer puzzle. Rejected.
- **Pulumi** — multi-language IaC, smaller GCP-pattern library than
  Terraform, fewer reviewers familiar with it. Rejected.
- **Google Cloud Deployment Manager** — deprecated for new projects;
  Google now points users to Terraform via their Cloud Foundation
  Toolkit. Rejected (deprecated).
- **Config Connector / KCC** — Kubernetes-style declarative resource
  management on GKE. Requires a GKE cluster we otherwise don't need.
  Rejected.
- **gcloud scripts** — imperative, no state, no plan, no rollback story.
  Violates constitutional principle I. Rejected.

**Followups**: None.

---

## Decision 3 — Database: Cloud SQL for PostgreSQL 17

**Decision**: GCP Cloud SQL for PostgreSQL, engine version 17,
**Regional HA**, single instance treated as production.
`db-custom-2-7680` (2 vCPU, 7.5 GiB) — revisited at first cost review.
Private IP only (no public IP), accessed from Cloud Run via a
Serverless VPC Connector. Automated backups with 7-day point-in-time
recovery. Connection via password authentication; password stored in
Secret Manager and rotated manually for v1. IAM database authentication
enabled **only** for emergency operator break-glass access.

The single-environment plan removes the previous staging-vs-prod sizing
distinction (`db-g1-small` for staging is no longer needed). The single
instance is sized for production workload.

**Rationale**:
- Paperclip's docs explicitly call for hosted PostgreSQL; PG 17 is the
  version they target. PG 17 is generally available on Cloud SQL.
- Regional HA gives sub-minute failover and is the standard HA story
  for a stateful single-database app. Especially important under the
  single-environment plan, where there is no second environment to
  catch issues before they hit production.
- Drizzle migrations are run by Paperclip itself on container boot, so
  the deployment doesn't need a separate migrate step — but the
  entrypoint script MUST refuse to start the server if migrations fail.
- Private IP eliminates public-internet exposure of the database.
  Combined with Serverless VPC Connector, Cloud Run can reach Cloud SQL
  privately without the Cloud SQL Auth Proxy.

**Alternatives considered**:
- **Cloud Spanner** — relational at planet scale but enormously more
  expensive at small scale, Postgres-compatible only via the Spanner
  PostgreSQL interface (subset of PG features). Overkill and
  incompatible with Paperclip's stock Postgres expectations. Rejected.
- **AlloyDB for PostgreSQL** — Google's premium Postgres-compatible
  service, more expensive, optimized for analytics and high QPS.
  Revisit if read load grows substantially. Rejected for v1.
- **Self-managed Postgres on GCE** — violates the goal of avoiding
  node management. Rejected.
- **Embedded PGlite** — explicitly forbidden by the spec (FR-016) and
  by Paperclip's own docs for production. Rejected.
- **Supabase Postgres** — explicitly excluded by user constraint.
- **Reuse the existing Firestore in `paperclip-492823`** — Firestore is
  document-oriented, not relational. Paperclip needs Postgres.
  Rejected.

**Followups**:
- Script Cloud SQL password rotation as a Cloud Run Job triggered by
  Cloud Scheduler before first production-impacting rotation.
- Decide on a schema-change CI gate (Drizzle drift detection in PR-time
  CI) before the first production migration. **This is especially
  important under single-env**: there is no staging migration to catch
  drift first. The Complexity Tracking entry in `plan.md` lists schema
  coordination as a manual gate until this CI is built.

---

## Decision 4 — Object storage: Google Cloud Storage with S3 interop

**Decision**: One private GCS bucket named
`paperclip-492823-uploads`, with **uniform bucket-level access**
and **public access prevention** both enforced. SSE encryption at rest
(default Google-managed keys; customer-managed CMEK is a follow-up).
**Object versioning enabled**. Lifecycle rule: abort incomplete
multipart uploads after 7 days. Paperclip accesses the bucket via the
**GCS S3 interop API** at `storage.googleapis.com` using HMAC keys.
The HMAC key is created against a dedicated `paperclip-storage-sa`
service account with `roles/storage.objectUser` scoped to its own
bucket only, and the access ID + secret are stored in Secret Manager.

The bucket name is explicitly distinct from the existing
`paperclip-492823.appspot.com`, `staging.paperclip-492823.appspot.com`,
`us.artifacts.paperclip-492823.appspot.com`, and
`gcf-sources-280667224791-us-central1` buckets that already live in
`paperclip-492823` (no collision possible).

**Rationale**:
- Paperclip's storage backend supports "S3-compatible" providers
  (its docs explicitly list AWS S3, MinIO, R2). GCS's interop API
  exposes the S3 protocol against GCS buckets and supports the
  operations Paperclip needs (PUT/GET/HEAD/LIST/DELETE/multipart, AWS
  Sig v4 presigned URLs).
- Bucket-per-deployment keeps blast radius narrow even within a shared
  project.
- Uniform bucket-level access + public access prevention closes the
  most common GCS misconfiguration foot-guns by construction.
- Versioning satisfies "Reversible Deployments" for user-uploaded data.
- HMAC key on a dedicated narrow-scoped service account is the
  minimum-privilege equivalent of an IAM role for S3 access.

**Alternatives considered**:
- **Filestore (managed NFS)** — block-storage semantics, expensive,
  Paperclip doesn't need POSIX. Rejected.
- **Use Cloud Run service account directly with the GCS native API** —
  not possible because Paperclip's storage backend speaks S3, not the
  native GCS API. Rejected (forced).
- **Serve uploads through Cloud CDN** — Paperclip serves uploads
  through its own access-controlled endpoints; bypassing that with a
  CDN would defeat per-user authorization. Rejected.

**Followups**:
- Decide retention/lifecycle for old non-current versions before the
  first cleanup pass.
- Consider CMEK for the bucket if compliance requirements emerge.

---

## Decision 5 — Secrets: GCP Secret Manager + bootstrap scripts

**Decision**: All sensitive values live in GCP Secret Manager in
`paperclip-492823`. The Paperclip Cloud Run service mounts each secret
as an environment variable at deploy time via the service spec's
`env.value_source.secret_key_ref` field. Five secrets:
`paperclip-master-key`, `paperclip-better-auth-secret`,
`paperclip-database-url`, `paperclip-s3-access-key-id`,
`paperclip-s3-secret-access-key`. **There is no `paperclip-anthropic-api-key`
and no `paperclip-openai-api-key`** — Vertex Claude eliminates the
Anthropic key and OpenAI/Codex agents are out of scope. Strict secret
mode (`PAPERCLIP_SECRETS_STRICT_MODE=true`) is set in the service env.

**Note on env var names**: Cloud Run mounts each secret to the env var
name Paperclip's source code actually reads, which differs from the
secret name in some cases. `paperclip-master-key` →
`PAPERCLIP_SECRETS_MASTER_KEY`. `paperclip-better-auth-secret` →
`BETTER_AUTH_SECRET`. `paperclip-s3-access-key-id` →
**`AWS_ACCESS_KEY_ID`** and `paperclip-s3-secret-access-key` →
**`AWS_SECRET_ACCESS_KEY`** — Paperclip's S3 storage provider creates
an `S3Client` without explicit credentials, so the AWS SDK reads the
standard AWS env var names from the environment. The Secret Manager
secret names are kept descriptive (`paperclip-s3-*`) but the env var
mounts use the AWS SDK names. See `contracts/container-image.md` for
the complete env var mapping.

**Verified on 2026-04-10**: a local Paperclip instance running with
`CLAUDE_CODE_USE_VERTEX=1` and no `ANTHROPIC_API_KEY` successfully
spawned Claude Code, which authenticated to Vertex AI via ADC and
ran multi-turn agent tasks. Paperclip's preflight check accepts the
unset state (it logs "ANTHROPIC_API_KEY is not set; subscription-based
auth can be used if Claude is logged in") and the spawned Claude
Code's runtime auth path is purely Vertex — every message ID in the
agent run log had the `msg_vrtx_*` prefix and `apiKeySource: "none"`.
**No `ANTHROPIC_API_KEY` is needed in any form, stub or real.**

The master key is generated once by `scripts/bootstrap-master-key.sh`
(`openssl rand -base64 32` →
`gcloud secrets create paperclip-master-key --data-file=-`) and is
**never** written to disk in the build context, the image, or the
runtime container filesystem. The Better Auth signing secret is
generated the same way by `scripts/bootstrap-better-auth-secret.sh`
(sibling script, identical pattern, separate Secret Manager entry).
The GCS HMAC credential is generated once by
`scripts/bootstrap-gcs-hmac.sh` and stored as two Secret Manager
secrets (access ID + secret). All three bootstrap scripts are
idempotent in the safe direction — they refuse to overwrite existing
secrets.

**Rationale**:
- Native Cloud Run integration: no sidecar, no init container, no CSI
  driver. Cloud Run resolves Secret Manager references at deploy time
  and re-resolves on revision deploys.
- Per-secret IAM scoping is straightforward: the Cloud Run service
  account is granted `roles/secretmanager.secretAccessor` only on the
  specific secrets it needs.
- Two operator-run pre-deploy scripts (`bootstrap-master-key.sh` and
  `bootstrap-gcs-hmac.sh`) are idempotent and auditable.
- **Vertex Claude eliminates an entire long-lived secret category**
  (the Anthropic API key), which is a strict win against constitutional
  principle IV.

**Alternatives considered**:
- **HashiCorp Vault** — adds a service we'd have to operate. No.
- **Cloud KMS only** — KMS encrypts data, but the actual secret
  storage and rotation flows on GCP go through Secret Manager. KMS is
  used by Secret Manager under the hood. Not an alternative, a
  prerequisite.
- **Mount secrets as files instead of env vars** — possible and
  recommended for very large secrets, but Paperclip reads its config
  from env vars per its docs. Stick with env-var injection.
- **Service account JSON keys for cross-cloud access** — explicitly
  rejected: long-lived static credentials violate principle IV.
- **`ANTHROPIC_API_KEY` in Secret Manager (the original plan)** —
  superseded by Vertex Claude. Vertex was confirmed live on
  `paperclip-492823` on 2026-04-10 with a successful predict call,
  eliminating the long-lived Anthropic credential.

**Followups**:
- **Master key rotation cadence** — Paperclip's master-key rotation
  story is not yet documented; we'll resolve before first production
  rotation. Until then, treat the master key as long-lived and protect
  it accordingly.
- ✅ **Paperclip preflight verification** — RESOLVED 2026-04-10. See
  the verification note above.
- Add an automated weekly check that the secret values are still
  resolvable by the Cloud Run service account.

---

## Decision 6 — Public edge: Cloud Run domain mapping (no Global LB for v1)

**Decision**: Cloud Run **domain mapping** binds a custom domain
(e.g. `paperclip.greeteat.example`, set in tfvars by the operator) to
the Cloud Run service. Google manages the TLS certificate automatically
(Let's Encrypt-class managed cert). Cloud DNS hosts the zone for the
deployment domain, and Terraform creates the CNAME or A/AAAA records
pointing to Cloud Run's `ghs.googlehosted.com`. HTTP requests are
automatically redirected to HTTPS by Cloud Run.

**Rationale**:
- Domain mappings are the lowest-config path to a custom HTTPS domain
  for a Cloud Run service. Zero certificate operator toil.
- Cloud DNS in the same project keeps DNS scoped to the right
  environment without cross-project delegation.
- A single domain mapping is sufficient — no multi-region, no global
  edge needs at v1, no Cloud CDN required to satisfy the spec.

**Alternatives considered**:
- **Global External HTTPS Load Balancer + Serverless NEG → Cloud Run** —
  more powerful: supports Cloud CDN, Cloud Armor (managed WAF rules),
  IAP, multi-region serverless NEGs, and richer URL routing. Adds
  meaningful Terraform surface area and a recurring forwarding-rule
  cost. Rejected for v1; revisit when we want WAF, CDN, IAP, or
  geographic latency improvements.
- **Cloud Run direct *.run.app URL** — works but exposes a
  Google-branded URL we don't want to use for the GreetEat dashboard.
  Rejected for production; usable as a fallback during bring-up.
- **External CDN (Cloudflare in front of Cloud Run)** — would
  introduce a non-GCP vendor, contrary to the user's "GCP-native"
  constraint. Rejected.

**Followups**: Add Global LB + Cloud Armor managed rule sets in front
of Cloud Run once the deployment carries production traffic and a
WAF is required.

---

## Decision 7 — Email: NONE

**Decision**: The deployment ships **no email infrastructure**. No SMTP,
no Workspace SMTP relay, no SendGrid, no SES, no Resend, no Mailgun.

**Rationale**:
- The investigation of Better Auth and Paperclip's source confirmed
  that **Better Auth ships zero built-in email sending** — it generates
  an invitation token and delegates delivery to a developer-implemented
  callback.
- Paperclip's environment variables, deployment docs, developer guide,
  and secrets API all contain **zero references** to SMTP, email, or
  any sendInvitationEmail-style configuration.
- Paperclip's release notes and API confirm invitations are
  **URL-based with auto-copy-to-clipboard** and a 10-minute TTL,
  exposed via `GET /api/invites/:token`,
  `/api/invites/:token/onboarding`, and
  `/api/invites/:token/onboarding.txt`.
- The inviter shares the URL out-of-band through whatever channel
  they prefer (Slack, Signal, in person). This is Paperclip's
  intentional design.
- For an invite-only admin tool with a small operator group, this is
  not just acceptable, it is the right shape.

**Alternatives considered**:
- **Workspace SMTP relay** — initially considered. Eliminated by the
  investigation: there's nothing in Paperclip that would send via SMTP
  even if it were configured.
- **SendGrid / Resend / Mailgun / SES** — would introduce a third-party
  vendor for a feature Paperclip explicitly does not need. Rejected.

**Followups**: If a future feature introduces an email-dependent flow
(password reset, security alerts, account notifications, etc.), this
decision must be revisited and the spec amended before that feature is
built.

---

## Decision 8 — Container image build: GitHub Actions → Artifact Registry, with project-scoped Workload Identity Federation

**Decision**: GitHub Actions workflow `.github/workflows/build-image.yml`
builds the Paperclip image from a pinned upstream Paperclip git tag
(stored in `infra/envs/prod/versions.tfvars`), runs Trivy and Hadolint
against it, authenticates to GCP via **project-scoped Workload Identity
Federation** (no service account JSON keys), and pushes the image to a
new `paperclip` repository in **Artifact Registry** inside
`paperclip-492823` with two tags — the Paperclip release version and
the build's git SHA — and outputs the immutable digest. The Terraform
service spec references the digest, never a tag.

The WIF pool is project-scoped (created inside `paperclip-492823` via
the `infra/modules/workload-identity/` module) because Victor lacks
org-level WIF permissions. Project-scoped WIF works identically for
the GitHub Actions → GCP path; it just lives in a project rather than
at the org root.

**Rationale**:
- GitHub Actions is where the source already lives; no second CI to
  operate.
- Workload Identity Federation eliminates the long-lived service-account
  JSON key that would otherwise live in a GitHub secret. Eliminating
  static credentials is the strongest secret-discipline win available
  in CI/CD.
- Pinning to a Paperclip release tag at *build* time + a digest at
  *deploy* time satisfies "dependency pinning" (no floating tags reach
  production).
- Artifact Registry private repo means no public exposure of the image.
- Project-scoped WIF avoids the org-level escalation that would
  otherwise require a separate access grant.

**Alternatives considered**:
- **Cloud Build** — capable, GCP-native, but adds a GCP resource we
  don't otherwise need and a second place to manage CI config.
  Rejected.
- **Pull Paperclip's published image** — does not exist. Paperclip
  publishes no image to a public registry as of the spec date.
  Rejected (forced).
- **Container Registry (gcr.io)** — deprecated by Google in favor of
  Artifact Registry. Rejected (deprecated).
- **Service account JSON key in GitHub secret** — works but
  reintroduces the long-lived static credential WIF was created to
  eliminate. Rejected.

**Followups**: Add SBOM generation (Syft) at build time. Add
provenance attestation (SLSA) once Artifact Registry's
Binary Authorization is in scope.

---

## Decision 9 — `paperclipai doctor` invocation strategy: Cloud Run Job

**Decision**: `paperclipai doctor` runs as a one-shot **Cloud Run Job**
(named `paperclipai-doctor`) that uses the same image and resolved
secrets as the Cloud Run service. Two execution paths:
1. **Post-deploy gate** — `scripts/deploy.sh` runs
   `gcloud run jobs execute paperclipai-doctor --wait
    --region=us-central1` immediately after `terraform apply` succeeds.
   The script reads the job execution status and fails the deploy (and
   triggers rollback) if doctor exits non-zero.
2. **Daily scheduled check** — a **Cloud Scheduler** job
   (`paperclipai-doctor-daily`) fires once per day, triggering a Cloud
   Run Job execution via the Cloud Run admin API. Failures publish a
   Cloud Monitoring metric and alert.

Under the single-environment plan, daily doctor runs are doubly
important — they replace the implicit "we'd notice it in staging first"
detection that two-env normally provides.

**Rationale**:
- Cloud Run Jobs is the right primitive for run-to-completion work
  using the same image as a Cloud Run service. Unlike trying to exec
  into a running service container (which Cloud Run does not support),
  Jobs are first-class.
- Sharing the image and the secret references with the service means
  doctor sees exactly the same configuration the service would.
- Cloud Scheduler → Cloud Run Jobs is a standard, low-toil GCP pattern.

**Alternatives considered**:
- **Run doctor at container boot inside the service** — would either
  delay every cold start or be skipped after the first boot; less
  useful and breaks Cloud Run's startup probe budgets.
- **Sidecar in the Cloud Run service** — Cloud Run supports
  multi-container revisions but adds a permanently running container
  for a check that runs at most twice a day. Rejected.
- **External HTTP probe replacing doctor** — Paperclip's `/health`
  endpoint already covers basic liveness; doctor adds public-mode
  config validation that no HTTP endpoint exposes.

**Followups**: Confirm `paperclipai doctor`'s exit-code conventions
with upstream before first production deploy.

---

## Decision 10 — Observability: Cloud Logging + Cloud Monitoring + Uptime Checks

**Decision**:
- **Logs**: Cloud Run automatically ships container stdout/stderr to
  Cloud Logging in the same project. Paperclip is configured to emit
  structured JSON logs (severity, message, correlation ID), which
  Cloud Logging maps to its severity field automatically.
- **Audit logs**: A **Log Router** sink captures authentication-event
  log entries (filtered by a structured field — `service=paperclip`
  AND `event=auth`) and routes them to a separate **log bucket**
  named `paperclip-audit-logs` with 90-day retention to satisfy FR-020.
- **Metrics**: Cloud Run, Cloud SQL, and GCS all publish first-class
  metrics. The Terraform `observability/` module provisions
  **Alerting Policies** for: Cloud Run 5xx rate, Cloud Run instance
  count = 0 (should never happen with `min-instances=2`), Cloud SQL
  CPU, Cloud SQL connections, Cloud SQL free disk, Cloud Storage
  4xx/5xx rate, daily doctor job failure, Uptime Check failure.
- **External health monitor**: Cloud Monitoring **Uptime Check** hits
  the public `/health` endpoint every minute from multiple regions
  (cross-region observation), satisfying SC-001's external measurement
  requirement.
- **Tracing**: Cloud Trace is **out of scope for v1**; revisit when
  there's a concrete debugging need that logs + metrics can't answer.

**Rationale**:
- Cloud Logging + Cloud Monitoring is in-project, in-region, no extra
  vendor.
- Uptime Checks from a different region give true external uptime
  signal (an alarm based on internal metrics can't catch a
  region-wide failure).
- Splitting auth events into their own log bucket via the Log Router
  isolates retention and access control without forcing a third
  logging tool.
- Filtering by `service=paperclip` keeps reports scoped even if the
  project ever gains additional workloads in the future.

**Alternatives considered**:
- **Datadog / Honeycomb / Grafana Cloud** — better tooling for some
  use cases but introduces a non-GCP vendor and a billing relationship.
  Rejected for v1.
- **Self-hosted Prometheus + Loki** — operational toil contradicts
  the rest of the stack's "managed everything" stance. Rejected.

**Followups**: Add Cloud Trace once we have a real cross-component
debugging question. Add Cloud Monitoring dashboards as part of
Phase 2 tasks.

---

## Decision 11 — Hosting: dedicated `paperclip-492823` project, single environment

**Decision**: Paperclip is deployed inside the **dedicated**
`paperclip-492823` GCP project (display name `paperclip`, project
number `280667224791`, parented directly to `greeteat.com` org
`768469506142`). It is the **only** environment for Paperclip — there
is no separate staging instance — and it is the **only workload** in
the project (no Firebase, App Engine, Cloud Functions, or other
GreetEat workloads share it). Resource namespacing (`paperclip-*` /
`paperclipai-*`) and a `service=paperclip` label remain in place as
good practice for cost attribution and IAM hygiene, but they are no
longer required for collision avoidance.

**History**: The project was created manually by the operator on
2026-04-09, originally requested as `paperclip` but auto-suffixed to
`paperclip-492823` because GCP project IDs are globally unique and
the friendly ID was taken. Billing was not attached at create time
because the operator lacked `billing.resourceAssociations.create` on
the billing account. The plan briefly pivoted to hosting Paperclip
inside the existing `greeteat-staging` project (which already had
billing attached) and that hosting choice was used during Phase B
verification of Vertex Claude. On 2026-04-10 the operator obtained
the necessary billing grant and attached `01BCB7-61A725-D6A2B5` to
`paperclip-492823`, **eliminating the original shared-project
constraint**. The plan was then re-targeted to the dedicated
`paperclip-492823` project, where every constitutional principle
holds without the shared-project mitigations the previous draft had
to enumerate.

**Rationale**:
- **Hard isolation**. Dedicated GCP project = hard IAM, billing, and
  resource isolation by GCP's primary tenancy primitive. An IAM
  mistake in this project cannot affect any other GreetEat project.
- **Clean slate**. No co-tenant resources, no existing service
  accounts to avoid, no naming-collision risk, no quota sharing with
  unrelated workloads. The default Compute service account exists in
  every GCP project but is still excluded from Paperclip use as good
  practice.
- **Audit clarity**. Cost reports, audit logs, IAM bindings, and
  resource inventories filtered to one project = one workload. No
  filtering by label needed.
- **Rollback / decommission**. `terraform destroy` cleans up the
  Paperclip resources; if a full reset is ever needed, the project
  itself can be soft-deleted (`gcloud projects delete paperclip-492823`,
  30-day recovery window) without affecting any other GreetEat work.
- **Single environment** is a separate decision driven by user
  direction ("we only need prod") and operational scale, not by any
  billing or IAM constraint. See `plan.md` Complexity Tracking for
  the full justification and the compensating mitigations.

**Alternatives considered**:
- **Two GCP projects under a Folder** (the original v0 plan) —
  organisational pattern that gives independent staging + production
  with full isolation. Rejected because the user explicitly scoped
  this feature to a single environment; revisitable per the plan's
  Complexity Tracking re-evaluation triggers.
- **Reuse `greeteat-staging` (the Phase B verification project)** —
  this was the v1 plan during the brief period when billing was
  blocked on `paperclip-492823`. Rejected once billing was attached
  on the dedicated project on 2026-04-10. Sharing with the existing
  Firebase / App Engine workloads in `greeteat-staging` introduced
  unnecessary blast radius and IAM/cost-attribution overhead that
  the dedicated project avoids.
- **Reuse `greeteat-app`, `greeteat-cb454`, or `greeteat-web-qa`** —
  unverified, would mix concerns. Rejected.

**Followups**:
- **Audit `service=paperclip` label coverage** before first deploy —
  recommended for cost reports and resource queries; not strictly
  required for collision avoidance now that the project is dedicated.
- **Display name vs project ID** — the display name `paperclip` is
  what shows in the GCP console; the immutable project ID
  `paperclip-492823` is what `gcloud --project` and Terraform `project`
  attributes reference. Documentation uses the project ID; narrative
  prose can refer to "the `paperclip` project".
- **Stale `greeteat-staging` Vertex Model Garden enablement** — Claude
  Sonnet 4.6 was enabled in `greeteat-staging` during Phase B
  verification. It is now unused for this deployment. The operator
  may leave it enabled (no cost when unused) or disable it via the
  Model Garden console.

---

## Decision 12 — Image build inputs and Paperclip version pinning

**Decision**: A single source of truth for the Paperclip release tag
lives in `infra/envs/prod/versions.tfvars` (key: `paperclip_version`).
The GitHub Actions image build is parameterized by that tag; the
resulting image is digest-pinned in the same tfvars file
(`paperclip_image_digest`), and `terraform apply` uses the digest.
Promoting a build is a two-step diff: bump the version, then bump the
digest after CI publishes it.

**Rationale**:
- Two distinct, auditable diffs: "we want to upgrade to Paperclip
  vX.Y.Z" and "the build of X.Y.Z that landed in Artifact Registry
  has digest sha256:…".
- Prevents the classic "tag is mutable" foot-gun.

**Alternatives considered**: A single tfvars value with both version
and digest combined — rejected for losing the two-step audit story.

---

## Decision 13 — DATABASE_URL must include `?sslmode=require`

**Decision**: The `paperclip-database-url` Secret Manager entry created
by `infra/modules/database/main.tf` builds the connection string as

    postgres://paperclip:<pw>@<private_ip>:5432/paperclip?sslmode=require

with `?sslmode=require` explicit, NOT relying on the postgres client to
auto-negotiate TLS based on the server-side `ssl_mode = ENCRYPTED_ONLY`
setting.

**Rationale**: discovered the hard way during the first Phase 3 apply
(2026-04-11). The Cloud SQL instance is configured with `ssl_mode =
"ENCRYPTED_ONLY"` per Decision 5's secrets-discipline rationale, which
means Cloud SQL refuses any connection that doesn't begin a TLS
handshake. Paperclip uses the `postgres` npm package (postgres.js) for
its database client (verified at `node_modules/.pnpm/postgres@3.4.8/`
in the v2026.403.0 image). Unlike `node-postgres` (`pg`), postgres.js
does NOT auto-negotiate SSL on private-IP connections — it connects in
cleartext by default and Cloud SQL's `pg_hba.conf` rejects the auth
handshake with:

    PostgresError: pg_hba.conf rejects connection for host
      "10.8.0.x", user "paperclip", database "paperclip", no encryption

The Cloud Run service container exit(1)'d on this error, never bound
port 3100, and Cloud Run failed the deploy with a generic
"container failed to start" message. The actual cause was only visible
in `gcloud logging read` against the failed revision.

**`require` (encrypt without cert verification) is sufficient**: the
connection only ever happens over the VPC's private IP range, so MITM
is not in the threat model. `verify-ca` / `verify-full` would require
mounting Cloud SQL's server CA cert into the container, which adds
complexity without security benefit on a private network.

**Alternatives considered**:

- **Switch the postgres client**: would require forking Paperclip and
  maintaining a custom build. Out of scope.
- **Disable `ssl_mode` enforcement on Cloud SQL**: violates Decision 5
  + the constitution's secrets-discipline principle. Rejected.
- **Tunnel via Cloud SQL Auth Proxy**: adds a sidecar process inside
  the Cloud Run container. More moving parts than putting one query
  param in the URL. Rejected for v1.

---

## Decision 14 — Cloud Run service `deletion_protection = false`

**Decision**: `infra/modules/compute/main.tf` sets
`deletion_protection = false` explicitly on the
`google_cloud_run_v2_service` resource.

**Rationale**: Google provider 6.x defaults this field to `true`. It
is a CLIENT-SIDE check by the Terraform provider, not a GCP API
enforcement — the provider refuses to issue the DELETE call when
`deletion_protection = true` in state, but the underlying Cloud Run
v2 API has no such field at all (verified by curling the REST API
during recovery from a failed apply).

The setting bit us during the first Phase 3 apply: the initial
container start failed at the database connection step (Decision 13),
which left the Cloud Run service in state with the broken revision.
Terraform decided to replace the resource on the next apply, and the
destroy step failed with:

    Error: cannot destroy service without setting deletion_protection=false

We can't recover by flipping the bit in HCL because Terraform applies
the destroy BEFORE the in-place attribute update. We had to delete the
service via REST API directly, then `terraform state rm` it, then
re-apply.

**Our recovery primitive for Cloud Run mistakes is REVISION ROLLBACK**
(deploy.sh + rollback.sh, Phase 6/7) — not "the service object cannot
be deleted at all". Cloud Run keeps every prior revision around and
rolling traffic back is the right answer for bad deploys.

---

## Decision 15 — Bootstrap-ceo wrapper script materializes a minimal config.json

**Decision**: The `paperclipai-bootstrap-ceo` Cloud Run Job runs a
templated wrapper shell script
(`infra/modules/jobs/bootstrap-ceo-wrapper.sh.tftpl`) that creates a
minimal valid `/paperclip/instances/default/config.json` before
exec'ing the CLI:

    sh -c '<wrapper script that mkdir + cat > config.json + exec node ...>'

The job's `command` is left UNSET (so the upstream
`docker-entrypoint.sh` ENTRYPOINT stays in place and runs the args as
the `node` user via `gosu`); the actual CLI invocation lives in `args`
as `["sh", "-c", templatefile(...)]`.

**Rationale**: Paperclip's `paperclipai auth bootstrap-ceo` CLI checks
for a config file at `PAPERCLIP_CONFIG` (default
`/paperclip/instances/default/config.json`) on startup and bails
immediately if it's missing:

    if (!config) {
      p.log.error(`No config found at ${configPath}. Run paperclip onboard first.`);
      return;
    }

The CLI was designed for developer-laptop usage where `~/.paperclip`
persists across runs. Cloud Run Jobs start with empty filesystems on
every execution, so the file is never present on a clean deployment.
Even though the CLI later prefers env vars for `DATABASE_URL` and
`PAPERCLIP_PUBLIC_URL` (verified in
`cli/src/commands/auth-bootstrap-ceo.ts:resolveDbUrl/resolveBaseUrl`),
the early check forces a file to exist.

The wrapper's config file just needs to pass Paperclip's zod schema
validation with `server.deploymentMode = "authenticated"` — every
field's actual value comes from the env vars Cloud Run mounts.

**Alternatives considered**:

- **Run `paperclip onboard` first**: it's interactive, has no
  non-interactive flag, and Cloud Run Jobs have no TTY. Rejected.
- **Mount the config as a Secret Manager secret-as-file**: doable
  but adds an extra secret to manage, and Cloud Run secret volumes
  mount as read-only directories that conflict with Paperclip's
  expectation that `/paperclip/instances/default/` is writable for
  logs/backups. Rejected.
- **SQL-insert the bootstrap invite directly, skipping the CLI**:
  reimplements bootstrap-ceo's logic in a brittle script. Rejected.
- **Bake the config into the upstream image**: requires forking
  Paperclip's Dockerfile. Rejected (Decision 12: we inherit upstream
  byte-for-byte).
- **Open an upstream PR to make the CLI prefer env vars over config
  file existence**: filed as a Followup. The wrapper is the
  short-term workaround.

---

## Decision 16 — `paperclip_version` accepts a tag OR a commit SHA

**Decision**: The `paperclip_version` variable in
`infra/envs/prod/versions.auto.tfvars` accepts EITHER a release tag
(preferred for normal upgrades, e.g. `v2026.403.0`) OR a full 40-char
commit SHA (escape hatch for fixes that exist on master but haven't
been tagged yet, e.g. `ac664df8e48326135a913e97ee7ed937d913586b`).

The `build-image.yml` workflow auto-detects which one this is via a
regex match on `^[0-9a-f]{40}$`, and tags the resulting image as
`<tag>` for tags or `sha-<first-12-chars>` for SHAs (a full 40-char
hex tag would be ugly but Docker would accept it). The clone step
uses `git init + git fetch <ref> + git checkout FETCH_HEAD` instead of
`git clone --depth 1 --branch <ref>` because the latter only accepts
branches and tags, not arbitrary commit SHAs.

**Rationale**: GHSA-68qg-g8mg-6pr7 (CRITICAL unauthenticated RCE in
Paperclip) was published on 2026-04-10, four hours after the upstream
fix landed in commit `ac664df` on master. The latest tagged release
(`v2026.403.0`, 2026-04-04) does NOT contain the fix, and at the time
of our deploy upstream had not cut a new release yet. We needed
defense in depth (the `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true` env var
mitigates the chain at step 1, but shipping the actual fix is also
important) without waiting an indefinite time for upstream to tag.

Pinning a commit SHA preserves immutability (a SHA is just as
reproducible as a tag — more so, actually, because tags can be moved
upstream while SHAs can't) and gets us the fix immediately. The
escape hatch is documented as "use only when a needed fix is on
master but not yet tagged" — for normal upgrades, tags are still
preferred because they carry release notes and intent.

**Alternatives considered**:

- **Wait for upstream to tag a release**: indefinite blocker.
- **Allowlist the GHSA in `.trivyignore` and ship the unpatched
  code**: relies solely on the env-var mitigation. Defense in depth
  loses.
- **Build from `master` branch directly**: not immutable (next CI
  run might pull a different HEAD). SHA pinning is the right shape.

---

## Decision 17 — Operator runtime auth: avoid laptop ADC for long applies

**Decision**: For any `terraform apply` that touches resources with
long create operations (Cloud SQL, Service Networking Connection),
operators MUST use a Cloud Shell session or a service account key
file — NOT laptop ADC issued via `gcloud auth application-default
login`.

**Rationale**: Workspace-managed Google accounts have a "RAPT"
(Reauthentication Access Policy Token) enforcement that forces token
refresh every ~10-15 minutes. Any single Terraform operation that
takes longer than the token's remaining lifetime fails with:

    Error: Request had invalid authentication credentials. Expected
    OAuth 2 access token, login cookie or other valid authentication
    credential. ... oauth2: "invalid_grant" "reauth related error
    (invalid_rapt)"

We hit this twice during the first deploy: once on
`google_service_networking_connection.private_vpc_connection` (5+
minutes) and once mid-Phase-3 on `google_sql_user.paperclip` after
Cloud SQL provisioning (11+ minutes). Recovery is non-trivial because
the failed apply often leaves a stale state lock in GCS that requires
`terraform force-unlock` and an `errored.tfstate` file that needs
`terraform state push`.

Cloud Shell auth is sticky for the session (no RAPT enforcement);
service account keys never expire. Both are RAPT-immune.

**Alternatives considered**:

- **Run apply via GitHub Actions deploy.yml** (Phase 6): the cleanest
  long-term answer because it uses the same WIF auth path as
  `build-image.yml`, no key files. We'll get there in Phase 6, but
  the operator still needs a working laptop path for break-glass
  scenarios.
- **Increase RAPT lifetime via Workspace admin**: requires admin
  privileges we don't have, and would also weaken security for every
  other service.
- **Cloud SQL Auth Proxy + apply from a local SA-impersonated
  shell**: more setup complexity than just opening Cloud Shell.

---

## Decision 18 — Operator deployment uses Cloud Run *.run.app vanity URL (no custom domain for v1)

**Decision**: The first deployment runs without a custom DNS domain.
PAPERCLIP_PUBLIC_URL is set to the Cloud Run *.run.app vanity URL:

    https://paperclip-280667224791.us-central1.run.app

The edge module (Cloud DNS managed zone + Cloud Run domain mapping)
is wrapped with `count = var.domain != "" ? 1 : 0` and SKIPPED while
`var.domain = ""`.

**Rationale**: GreetEat does not yet have a domain to delegate to
Cloud DNS. We needed a working public endpoint immediately for the
MVP acceptance test (US1) without waiting for domain procurement.

**The vanity URL is deterministic** in Cloud Run v2: the format is
`https://<service>-<project_number>.<region>.run.app`. For
paperclip + project number 280667224791 + us-central1, that resolves
to `https://paperclip-280667224791.us-central1.run.app`. The URL is
stable for the lifetime of the project — it's derived from the
project NUMBER (which is permanent), not the project ID, and it
doesn't change even if the service is deleted and recreated.

We discovered the vanity URL by inspecting a broken first revision
via the REST API and pre-set `public_url_override` to it in
`terraform.tfvars`. This skips the otherwise-required two-pass apply
that the no-domain bootstrap would need (first apply with a
placeholder PUBLIC_URL → read service_uri output → set override →
re-apply).

When a custom domain becomes available, set `domain =
"paperclip.greeteat.example"` and clear `public_url_override`. The
edge module will then provision Cloud DNS + the domain mapping and
PUBLIC_URL becomes `https://${domain}`. The vanity URL continues to
work in parallel.

**Note about Cloud Run v2 having TWO URLs**: terraform's
`google_cloud_run_v2_service.uri` attribute returns the
random-subdomain URL (e.g.
`https://paperclip-jvvbmuixka-uc.a.run.app`) — a different URL than
the project-number vanity URL we use for PAPERCLIP_PUBLIC_URL. Both
route to the same service, but Better Auth's trustedOrigins check
compares the request `Origin` header against PAPERCLIP_PUBLIC_URL
exactly, so users MUST access via the vanity URL or sign-ins fail
CSRF protection. The deterministic vanity URL is the right choice
because the random URL would change on service recreation.

---

## Resolved spec deferrals

The spec's "Decisions deferred to planning" section listed six items;
this research resolves all six against the GCP-native + no-Supabase +
no-email + shared-project + single-env + Vertex-Claude constraint set:

| Spec deferral | Resolved decision |
|---|---|
| Application host | Decision 1: Cloud Run with `min-instances=2` |
| Managed PostgreSQL provider | Decision 3: Cloud SQL for PostgreSQL 17 (regional HA) |
| Object storage provider | Decision 4: GCS via S3 interop API |
| Secret store | Decision 5: GCP Secret Manager (no `ANTHROPIC_API_KEY`) |
| TLS / DNS edge | Decision 6: Cloud Run domain mapping + Cloud DNS |
| Container image build pipeline | Decision 8: GitHub Actions → Artifact Registry via project-scoped WIF |
| (added) LLM provider | Vertex AI Claude Sonnet 4.6 (verified live 2026-04-10) |
| (added) Hosting project | Decision 11: dedicated `paperclip-492823` |
| (added) Number of environments | Decision 11: single environment with Complexity Tracking entry |

## Followups (do not block Phase 1)

- ✅ **Paperclip preflight verification** — RESOLVED 2026-04-10. See
  Decision 5 verification note.
- **Upstream PR to `paperclipai/paperclip`** to make `paperclipai auth
  bootstrap-ceo` prefer env vars over a config-file existence check
  (see Decision 15). The wrapper script in `infra/modules/jobs/` is
  the workaround until this lands.
- **Upstream PR to `paperclipai/paperclip`** to refresh the stale
  `cli.github.com` keyring SHA in the Dockerfile (see Phase 3
  retrospective in `tasks.md`). The "Patch upstream Dockerfile"
  step in `build-image.yml` is the workaround.
- **Re-pin `paperclip_version` to a tagged release** when upstream
  cuts one that includes commit `ac664df` (the GHSA-68qg-g8mg-6pr7
  fix). Currently pinned to a SHA — see Decision 16. Drop matching
  CVE entries from `.trivyignore` once the package.json `version`
  field is bumped to a release that resolves the GHSA.
- **Re-tighten the Trivy gate** as upstream rebuilds the bundled
  developer-tooling layer with newer Go binaries. Currently
  `.trivyignore` carries 13 documented allowlist entries; re-review
  on every Paperclip version bump.
- **Master key rotation cadence and procedure** (Decision 5)
- **Cloud SQL password rotation script** (Decision 3)
- **Schema-drift CI gate** before first production migration
  (Decision 3) — especially important under single-env
- **Global External HTTPS LB + Cloud Armor** in front of Cloud Run
  when WAF/CDN is needed (Decision 6)
- **SBOM generation** in image build (Decision 8)
- **`paperclipai doctor` exit-code conventions** confirmation with
  upstream (Decision 9)
- **Cloud Trace** adoption when needed (Decision 10)
- **CMEK** for the GCS bucket if compliance requirements emerge
  (Decision 4)
- **Verify Better Auth uses database-backed sessions** (Decision 1)
- **Verify >32 MiB uploads work via HTTP/2** on Cloud Run
  (Decision 1)
- **Second-environment re-evaluation trigger**: when any of the
  conditions in Decision 11's "Re-evaluation trigger" section is hit
- **Decommission or document the orphaned `paperclip-492823` project**
  (Decision 11)
- **`service=paperclip` label coverage check** in CI (Decision 11)
