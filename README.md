# greeteat-paperclip

Reference implementation for deploying [Paperclip](https://github.com/paperclipai/paperclip) — the open-source AI agent orchestration platform — to **Google Cloud Run** with Vertex AI Claude.

## What's here

This is a **deployment-configuration repo**, not application code. It contains everything needed to run Paperclip in a production GCP environment:

- **Terraform modules** for Cloud Run, Cloud SQL (PostgreSQL 17), Cloud Storage, Secret Manager, VPC, DNS, Workload Identity Federation, Artifact Registry, and Cloud Run Jobs
- **GitHub Actions workflows** for building the upstream Paperclip image and pushing to Artifact Registry
- **Bootstrap scripts** for one-time secret generation (master key, Better Auth secret, GCS HMAC keys)
- **A full deployment spec** with 60+ tasks, 20 research decisions, and an operator quickstart

## Architecture

```
Internet → Cloud Run service (paperclip, min_instances=2)
             ├─ VPC connector → Cloud SQL (PG17, private IP, HA)
             ├─ GCS FUSE mount → persistent agent state (/paperclip)
             ├─ Secrets from Secret Manager (5 mounted env vars)
             └─ Vertex AI Claude (Opus 4.6 / Sonnet 4.6 / Haiku 4.5)

Cloud Run Job (bootstrap-ceo) — seed operator bootstrap
GitHub Actions (build-image.yml) — WIF auth, upstream Dockerfile, Trivy scan
```

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Compute | Cloud Run v2 (not GKE) | Simplest serverless option; min_instances=2 for zero cold starts |
| Database | Cloud SQL PostgreSQL 17 (private IP, REGIONAL HA) | Managed Postgres with automated backups + PITR |
| LLM | Vertex AI Claude (no Anthropic API key) | Runs on GCP's infrastructure; authenticates via service account |
| State | GCS FUSE mount at `/paperclip` | Paperclip assumes a persistent local filesystem; GCS FUSE bridges the gap |
| Secrets | GCP Secret Manager + bootstrap scripts | No secrets in code or env; mounted at runtime via Cloud Run secret refs |
| CI auth | Workload Identity Federation (no JSON key files) | GitHub OIDC → GCP SA impersonation, no long-lived credentials |
| Image | Upstream Paperclip Dockerfile (not custom) | Inherits upstream's multi-workspace build + global CLI installs |

## Cloud deployment guide

Paperclip was designed for local developer use. Deploying it to stateless compute (Cloud Run) requires workarounds for 7 categories of local-first assumptions. The full guide with code snippets:

**[docs/cloud-deployment-guide.md](docs/cloud-deployment-guide.md)**

Condensed version as a GitHub Gist: [Deploying Paperclip to Google Cloud Run — Lessons from Production](https://gist.github.com/vsima/2d799684ba147acb4e2e975155c8e126)

## Repo structure

```
infra/
  modules/
    apis/                # GCP API enablement (16 APIs)
    network/             # VPC, subnet, connector, Private Services Access
    secrets/             # Secret Manager data lookups (4 bootstrap secrets)
    artifact-registry/   # Docker image repository
    workload-identity/   # GitHub Actions WIF pool + SA
    database/            # Cloud SQL PG17 + paperclip user + DB URL secret
    storage/             # GCS uploads bucket + state bucket (FUSE mount)
    compute/             # Cloud Run service + runtime SA + all IAM bindings
    edge/                # Cloud DNS + domain mapping (optional, skipped without domain)
    jobs/                # Cloud Run Jobs (bootstrap-ceo, future: doctor)
  envs/
    prod/                # Root composition wiring all modules together
  scripts/               # Bootstrap scripts (master-key, better-auth, gcs-hmac)

.github/workflows/
  build-image.yml        # Clone upstream Paperclip, build, Trivy scan, push to AR

specs/001-deploy-gcp-public-auth/
  spec.md                # Requirements (6 user stories, 27 functional requirements)
  plan.md                # Implementation plan + tech stack
  research.md            # 21 locked decisions with rationale
  tasks.md               # 60+ tasks across 9 phases (39 done, MVP complete)
  quickstart.md          # Operator first-deploy walkthrough + troubleshooting
  data-model.md          # GCP resource graph + Paperclip entity model
  contracts/             # Interface contracts (container image, deploy CLI, rollback CLI)

docs/
  cloud-deployment-guide.md  # Condensed lessons for the Paperclip community
```

## Getting started

See **[specs/001-deploy-gcp-public-auth/quickstart.md](specs/001-deploy-gcp-public-auth/quickstart.md)** for the full operator walkthrough, including:

1. GCP project prerequisites
2. Bootstrap secrets
3. First image build
4. Terraform apply (phased: foundation → stateful core → bootstrap)
5. The bootstrap dance (first user creation with `disableSignUp` flip)
6. Verification smoke tests

## Local environment setup

Deployment-specific values (like your Cloud Run URL) are **not committed to git**. After cloning, create a local override file:

```sh
cd infra/envs/prod
cp terraform.tfvars.local.example terraform.tfvars.local
# Edit terraform.tfvars.local with your real Cloud Run URL
```

Then always apply with the override:

```sh
terraform apply -var-file=terraform.tfvars.local
```

The `*.tfvars.local` pattern is gitignored. See `terraform.tfvars` for inline documentation on what each variable does.

## Built with

- [Paperclip](https://github.com/paperclipai/paperclip) — AI agent orchestration
- [Claude Code](https://claude.ai/code) (Anthropic) — AI pair programming for all infrastructure code
- [Terraform](https://www.terraform.io/) — infrastructure as code
- [Google Cloud Platform](https://cloud.google.com/) — Cloud Run, Cloud SQL, Vertex AI, Secret Manager, GCS

## License

This repo is published as a reference implementation for the Paperclip community. The infrastructure patterns and deployment guide are freely reusable. Paperclip itself is licensed under its own terms at [paperclipai/paperclip](https://github.com/paperclipai/paperclip).

---

*Deployed and operated by [GreetEat Corp](https://greeteat.com) (OTC: GEAT)*
