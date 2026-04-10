# Data Model: Deploy Paperclip to GCP in Public Authentication Mode

**Date**: 2026-04-09
**Last updated**: 2026-04-10
**Spec**: [spec.md](./spec.md)
**Plan**: [plan.md](./plan.md)

This document models two layers:

1. **Deployed-resource model** — the GCP resources Terraform manages
   inside the dedicated `paperclip-492823` project.
2. **Application entities** — the entities the spec defines (board
   operator, invitation, agent, etc.) and how the deployment hosts them.
   These are owned by Paperclip's own database; the deployment provides
   the substrate.

---

## Layer 1 — Resources in the dedicated `paperclip-492823` project

Single environment. Single dedicated project. No co-tenant workloads.
**The only resource Paperclip explicitly avoids is the project's
default Compute service account** (`233990667256-compute@developer.gserviceaccount.com`),
which exists in every GCP project with broad legacy privileges and
should never be attached to a Paperclip workload — Paperclip uses its
own narrowly-scoped `paperclip-runtime-sa` instead.

### Paperclip resources (managed by Terraform in `infra/`)

Single environment. Resources are prefixed `paperclip-` or
`paperclipai-` (good practice for IAM hygiene and quick filtering,
not required for collision avoidance now that the project is
dedicated). All resources carry the label `service=paperclip` for
cost attribution.

```text
GCP Project: paperclip-492823 (existing, shared)
├── APIs Paperclip enables (via infra/modules/apis/)
│   ├── run.googleapis.com               (Cloud Run)
│   ├── sqladmin.googleapis.com          (Cloud SQL)
│   ├── compute.googleapis.com           (Compute, needed for VPC)
│   ├── secretmanager.googleapis.com     (Secret Manager)
│   ├── dns.googleapis.com               (Cloud DNS)
│   ├── vpcaccess.googleapis.com         (Serverless VPC Connector)
│   ├── iam.googleapis.com               (project IAM)
│   ├── iamcredentials.googleapis.com    (for project-scoped WIF)
│   └── (already-enabled, no-op):
│       artifactregistry.googleapis.com, cloudscheduler.googleapis.com,
│       monitoring.googleapis.com, logging.googleapis.com,
│       aiplatform.googleapis.com (Vertex AI — enabled 2026-04-10),
│       sql-component.googleapis.com, storage.googleapis.com
│
├── Paperclip-managed network
│   ├── VPC: paperclip-vpc
│   │   └── Subnet: paperclip-subnet (private, /28 reserved for VPC connector)
│   ├── Serverless VPC Connector: paperclip-connector
│   │   └── Allows Cloud Run egress into paperclip-subnet
│   └── Private Services Access (peering with Google services for Cloud SQL)
│
├── Database
│   └── Cloud SQL Instance: paperclip-pg (PostgreSQL 17)
│       ├── Tier: db-custom-2-7680 (2 vCPU, 7.5 GiB)
│       ├── Availability: REGIONAL (HA)
│       ├── IP: PRIVATE only (no public IP)
│       ├── Database: paperclip
│       ├── User: paperclip (password from Secret Manager)
│       ├── Backups: enabled, 7-day point-in-time recovery
│       └── Maintenance window: declared in tfvars
│
├── Object storage
│   └── GCS Bucket: paperclip-492823-uploads
│       ├── Location: regional (us-central1)
│       ├── Uniform bucket-level access: ENFORCED
│       ├── Public access prevention: ENFORCED
│       ├── Versioning: ON
│       ├── Lifecycle: abort multipart uploads after 7 days
│       ├── Labels: service=paperclip
│       └── Service Account: paperclip-storage-sa
│           └── HMAC key: stored in Secret Manager (interop credentials)
│
├── Secret Manager secrets (each with label service=paperclip)
│   ├── paperclip-master-key
│   ├── paperclip-database-url
│   ├── paperclip-s3-access-key-id
│   └── paperclip-s3-secret-access-key
│   (no paperclip-anthropic-api-key — Vertex Claude uses
│    paperclip-runtime-sa's roles/aiplatform.user; verified 2026-04-10)
│
├── Artifact Registry
│   └── Repository: paperclip (Docker format, us-central1)
│       └── Image: paperclip
│           └── Identified by digest in tfvars
│
├── Workload Identity Federation (project-scoped)
│   └── Pool: paperclip-github
│       └── Provider: github (OIDC)
│           └── Subject mapping: assertion.sub from token.actions.githubusercontent.com
│
├── Compute
│   ├── Service Account: paperclip-runtime-sa@paperclip-492823.iam.gserviceaccount.com
│   │   └── Roles (scoped):
│   │       ├── secretmanager.secretAccessor on the 4–5 paperclip-* secrets above
│   │       ├── storage.objectUser on paperclip-492823-uploads
│   │       ├── cloudsql.client on paperclip-pg
│   │       ├── aiplatform.user (Vertex Claude calls)
│   │       └── logging.logWriter project-wide
│   │   └── ❌ NEVER attached to Paperclip Cloud Run service:
│   │       roles/owner, roles/editor, roles/iam.serviceAccountUser on
│   │       any other service account
│   ├── Cloud Run Service: paperclip
│   │   ├── Image: digest-pinned
│   │   ├── min-instances: 2
│   │   ├── max-instances: declared in tfvars
│   │   ├── CPU: 2 | Memory: 2Gi
│   │   ├── VPC connector: paperclip-connector
│   │   ├── Service account: paperclip-runtime-sa
│   │   ├── Labels: service=paperclip
│   │   ├── Env (plain):
│   │   │     PORT (injected), HOST=0.0.0.0, PAPERCLIP_DEPLOYMENT_MODE=public,
│   │   │     PAPERCLIP_PUBLIC_URL=https://<your-domain>,
│   │   │     PAPERCLIP_SECRETS_STRICT_MODE=true,
│   │   │     PAPERCLIP_INSTANCE_ID=prod,
│   │   │     S3_ENDPOINT=https://storage.googleapis.com,
│   │   │     S3_BUCKET=paperclip-492823-uploads,
│   │   │     S3_REGION=auto, LOG_LEVEL=info, LOG_FORMAT=json,
│   │   │     CLAUDE_CODE_USE_VERTEX=1,
│   │   │     CLOUD_ML_REGION=global,
│   │   │     ANTHROPIC_VERTEX_PROJECT_ID=paperclip-492823,
│   │   │     ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6
│   │   └── Secrets (mounted from Secret Manager): the 4–5 paperclip-* secrets
│   └── Cloud Run Job: paperclipai-doctor
│       ├── Same image as the service
│       ├── Same service account, secrets, env
│       ├── Labels: service=paperclip
│       └── Override command: ["paperclipai", "doctor"]
│
├── Edge / DNS
│   ├── Cloud DNS Zone: paperclip-greeteat-zone
│   │   └── Records: A/AAAA/CNAME pointing the deployment hostname at
│   │              Cloud Run's ghs.googlehosted.com
│   └── Cloud Run domain mapping: hostname → service
│
├── Schedules
│   └── Cloud Scheduler Job: paperclipai-doctor-daily
│       ├── Region: us-central1 (same as the existing firebase-schedule-* jobs)
│       └── Triggers Cloud Run Job execution once per day
│
└── Observability
    ├── Log Bucket: paperclip-app-logs (default retention)
    ├── Log Bucket: paperclip-audit-logs (90-day retention)
    ├── Log Router (Sink): auth-events filter `service="paperclip" AND event="auth"`
    │                       → paperclip-audit-logs
    ├── Alerting Policies (each filtered to service=paperclip):
    │   ├── Cloud Run paperclip 5xx rate
    │   ├── Cloud Run paperclip instance count = 0 (should never happen)
    │   ├── Cloud SQL paperclip-pg CPU
    │   ├── Cloud SQL paperclip-pg connections
    │   ├── Cloud SQL paperclip-pg free disk
    │   ├── GCS paperclip-492823-uploads error rate
    │   ├── Daily doctor job failure
    │   └── Uptime Check failure
    └── Uptime Check: GET /health, every 1 min, from multiple regions

(Terraform state lives in a fifth managed resource:)
└── GCS Bucket: paperclip-tf-state
    ├── Object versioning: ON
    ├── Public access prevention: ENFORCED
    └── IAM: only Victor's user and the GitHub WIF SA
```

### Resource lifecycle and state transitions

| Resource | Created when | Modified when | Destroyed when |
|---|---|---|---|
| Enabled APIs | First `terraform apply` | Almost never | If Paperclip is decommissioned (and the API isn't used by other workloads) |
| paperclip-vpc + subnet + connector | First `terraform apply` | Almost never | Paperclip teardown |
| paperclip-pg Cloud SQL instance | First `terraform apply` | Tier/HA changes (in-place), version bumps (planned outage) | Never automatically (`prevent_destroy=true`) |
| paperclip-492823-uploads GCS bucket | First `terraform apply` | Lifecycle/versioning changes (safe) | Never automatically (`prevent_destroy=true`) |
| paperclip-* Secret Manager entries | Bootstrap scripts (`bootstrap-master-key.sh`, `bootstrap-gcs-hmac.sh`), then Terraform | New versions added on rotation | Old versions disabled, never deleted |
| paperclip Cloud Run Service | First `terraform apply` | Every deploy (new revision) | Never automatically |
| Cloud Run revisions | Every deploy | Immutable | Cloud Run retains the most recent N revisions; older ones GC'd by Cloud Run |
| paperclipai-doctor Cloud Run Job | First `terraform apply` | Image bumps follow service | Never automatically |
| paperclip Cloud DNS zone + records | First `terraform apply` | Hostname changes | Hostname changes |
| Cloud Run domain mapping | First `terraform apply` | Hostname changes | Hostname changes |
| paperclip Artifact Registry repo | First `terraform apply` | Almost never | Paperclip teardown |
| paperclip-github WIF pool | First `terraform apply` | New providers added | Paperclip teardown |
| Alerting policies | First `terraform apply` | Threshold tuning | Paperclip teardown |
| paperclip-tf-state GCS bucket | One-time, before first apply (manual) | Never | Paperclip teardown (last) |

### Validation rules (enforced by Terraform / module variables / CI)

- `paperclip_image_digest` MUST match `^sha256:[a-f0-9]{64}$`. Tag-only
  references are rejected at plan time.
- `cloud_run_min_instances` MUST be ≥ 2 (single-env, no cold starts allowed).
- `cloud_sql_availability_type` MUST equal `REGIONAL` (single-env is
  treated as production; HA is non-negotiable).
- `gcs_uniform_bucket_level_access` MUST be `true`. Variable has no
  override.
- `gcs_public_access_prevention` MUST be `enforced`. Variable has no
  override.
- `cloud_run_service_account` MUST NOT be the project's default Compute
  service account (`233990667256-compute@…`). Variable rejects it.
- `paperclip_deployment_mode` MUST equal `public`. The compute module
  hardcodes this; it cannot be set to `local_trusted` or `private` from
  tfvars.
- **Every Paperclip-managed resource MUST carry the `service=paperclip`
  label.** Enforced by a checkov / tflint rule in CI; PRs that introduce
  unlabeled resources fail PR checks.
- **Every Paperclip-managed resource MUST have a name prefixed
  `paperclip-` or `paperclipai-`** (or `greeteat-paperclip-` for the
  GCS bucket where the org prefix is helpful for global uniqueness).
  Enforced by a CI rule.
- `cloud_run_service_account` MUST NOT have any role outside the
  five listed in the Compute section above. Enforced by an integration
  check that compares the actual IAM bindings against the allowlist.

---

## Layer 2 — Application entities (owned by Paperclip)

These are the spec's Key Entities, hosted inside Paperclip's own database
on Cloud SQL `paperclip-pg`. The deployment provides the database
substrate; the schema itself is managed by Paperclip's Drizzle migrations.

### Board Operator

| Attribute | Notes |
|---|---|
| Identity | Better Auth user record (UUID, identifier, hashed credential) |
| Session | Database-backed Better Auth session row, cookie-bound |
| Permissions | Scoped to one or more companies via membership rows |
| Created via | Invitation claim (no other path) |
| Revoked via | Operator-callable endpoint that deletes sessions and disables the user record; takes effect on the next request |

### Invitation

| Attribute | Notes |
|---|---|
| Token | Opaque, single-use, ~10 minute TTL |
| Issuer | Foreign key to Board Operator |
| Target | Identifier (email or arbitrary string), purely informational |
| Status | `pending` / `claimed` / `expired` / `revoked` |
| Claim URL | `https://<deployment-domain>/api/invites/<token>` (returned to inviter, auto-copied to clipboard) |
| Delivery | Out-of-band by the inviter — the deployment ships no email |

State transitions:

```text
[create] → pending
pending  → claimed   (POST/PUT /api/invites/:token/claim)
pending  → expired   (TTL elapsed)
pending  → revoked   (operator action)
claimed  → (terminal)
expired  → (terminal)
revoked  → (terminal)
```

### Agent

| Attribute | Notes |
|---|---|
| Identity | Paperclip agent record, scoped to a Company |
| Credentials | Short-lived JWT (heartbeat-delivered) OR long-lived API key (per-agent, hashed at rest) |
| Authorization | Company-scoped — cannot access another company's resources |
| Revoked via | Operator action; effective within seconds against the live deployment |
| LLM backend | Vertex AI Claude Sonnet 4.6, via Claude Code spawned by `claude_local` adapter, authenticated via `paperclip-runtime-sa` |

### Company

| Attribute | Notes |
|---|---|
| Identity | Paperclip company record |
| Members | Set of Board Operators via membership rows |
| Resources | Owns Agents, Goals, Tasks, Budgets |
| Authorization boundary | Cross-company access is denied at the application layer (FR-008) |

### Authentication Event

| Attribute | Notes |
|---|---|
| Type | sign-up / sign-in / sign-in-failure / lockout / invitation-issued / session-revoked |
| Actor | Board Operator or anonymous |
| Timestamp | UTC, monotonic |
| Source | IP, user agent (where applicable) |
| Outcome | success / failure / blocked |
| Correlation ID | Joins this event to subsequent agent activity |
| **Storage** | Paperclip emits a structured log line tagged `service=paperclip event=auth`; the deployment's Log Router routes it to the `paperclip-audit-logs` log bucket with 90-day retention (FR-020) |

### Agent Run

| Attribute | Notes |
|---|---|
| Identity | Paperclip run record |
| Initiated by | A heartbeat or event |
| Correlation ID | Joins to authentication events and to tool-invocation log lines |
| **Storage** | `paperclip-pg` for state; Cloud Logging for activity stream |

---

## Cross-layer relationships

| Application entity | Hosted on / depends on |
|---|---|
| Board Operator, Invitation, Agent, Company, Agent Run | `paperclip-pg` Cloud SQL Postgres, Drizzle-managed schema |
| Authentication Event | Cloud Logging → routed to `paperclip-audit-logs` log bucket |
| Uploaded files (attachments) | `paperclip-492823-uploads` GCS bucket via S3 interop API |
| Master encryption key | `paperclip-master-key` Secret Manager → injected into Cloud Run service env |
| LLM provider (Anthropic Claude) | **Vertex AI Model Garden** in `paperclip-492823`, called by Claude Code at runtime, authenticated via `paperclip-runtime-sa`'s `roles/aiplatform.user`. **No long-lived Anthropic API key.** |
| GCS HMAC interop credentials | `paperclip-s3-access-key-id` + `paperclip-s3-secret-access-key` Secret Manager entries → injected into Cloud Run service env, consumed by Paperclip's S3 storage backend |
