# paperclip-greeteat Development Guidelines

This is the **GreetEat Paperclip deployment-configuration repo**. It contains
Terraform infrastructure-as-code and CI workflows that deploy the open-source
[Paperclip](https://github.com/paperclipai/paperclip) AI agent orchestration
platform to GCP Cloud Run. There is no application source code here — only
infrastructure, specs, and deployment scripts.

## Key Facts

- **GCP project**: `paperclip-492823` (dedicated, `greeteat.com` org)
- **Region**: `us-central1`
- **Public URL**: https://paperclip-280667224791.us-central1.run.app
- **Terraform state**: GCS bucket `paperclip-492823-tf-state`
- **Persistent state**: GCS bucket `paperclip-492823-state` mounted at `/paperclip` via GCS FUSE

## Active Technologies

- Terraform (`google` + `google-beta` providers), GCS state backend
- GitHub Actions CI (build-image, terraform-plan, deploy workflows)
- GCP Cloud Run, Cloud SQL (PostgreSQL 17), Secret Manager, Artifact Registry
- Workload Identity Federation (keyless CI auth)
- Vertex AI Claude Sonnet 4.6 (LLM provider, no Anthropic API key)

## Project Structure

```text
infra/
├── modules/               # Reusable Terraform modules
│   ├── apis/              # Enable required GCP APIs
│   ├── network/           # VPC, subnet, Serverless VPC Connector
│   ├── secrets/           # Secret Manager entries + IAM
│   ├── artifact-registry/ # Docker image repo + IAM
│   ├── workload-identity/ # WIF pool for GitHub Actions
│   ├── database/          # Cloud SQL PostgreSQL 17 (HA)
│   ├── storage/           # GCS buckets (uploads + persistent state)
│   ├── compute/           # Cloud Run service + runtime SA
│   ├── edge/              # Domain mapping + Cloud DNS
│   ├── jobs/              # Cloud Run Jobs (doctor, bootstrap-ceo)
│   ├── scheduler/         # Cloud Scheduler (daily doctor)
│   └── observability/     # Log routing, alerts, uptime check
├── envs/
│   └── prod/              # Single environment composition
│       ├── main.tf        # Composes all modules
│       ├── variables.tf   # Typed input variables
│       ├── terraform.tfvars
│       ├── versions.auto.tfvars
│       ├── outputs.tf
│       └── backend.tf     # GCS state backend
└── scripts/               # Bootstrap and deploy shell scripts

specs/001-deploy-gcp-public-auth/   # Deployment spec (plan, tasks, research, etc.)
.github/workflows/                  # CI: build-image, terraform-plan, deploy
docs/                               # Cloud deployment guide
.trivyignore                        # CVE allowlist for image scanning
```

## Commands

```bash
# Deploy (from repo root)
./infra/scripts/deploy.sh

# Terraform operations (from infra/envs/prod/)
cd infra/envs/prod && terraform plan
cd infra/envs/prod && terraform apply

# Bootstrap scripts (one-time, from repo root)
./infra/scripts/bootstrap-master-key.sh
./infra/scripts/bootstrap-better-auth-secret.sh
./infra/scripts/bootstrap-gcs-hmac.sh

# Rollback
./infra/scripts/rollback.sh --reason "description"
```

## Code Style

- Terraform: follow HashiCorp conventions, one module per logical concern
- All resources labeled `service=paperclip`, prefixed `paperclip-` or `paperclipai-`
- Image references by digest only, never tags

## Important Notes

- This is a **deployment-spec repo** — no application code lives here
- The Paperclip application image is built from upstream `paperclipai/paperclip`
- Single environment (no staging) — see plan.md Complexity Tracking for rationale

## Recent Changes

- 001-deploy-gcp-public-auth: Full GCP deployment with public auth mode

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
