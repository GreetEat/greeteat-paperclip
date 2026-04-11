# =============================================================================
# Terraform variables for the GreetEat Paperclip prod environment.
# =============================================================================
# This file IS committed (no secrets here). Secrets live in Secret Manager
# and are mounted into Cloud Run by the compute module.
#
# Pinned Paperclip version + image digest live in the sibling versions.tfvars
# file so version bumps are a separate, reviewable diff.

# -----------------------------------------------------------------------------
# Project & region (locked)
# -----------------------------------------------------------------------------
project_id = "paperclip-492823"
region     = "us-central1"

# -----------------------------------------------------------------------------
# Public URL — TWO-PASS BOOTSTRAP for the no-domain deployment
# -----------------------------------------------------------------------------
# We don't have a custom domain yet, so the deployment uses Cloud Run's
# *.run.app URL directly. This requires a two-pass apply:
#
#   Pass 1 (this state):
#     domain              = ""    -> edge module skipped, no DNS / domain mapping
#     public_url_override = ""    -> compute uses a placeholder PAPERCLIP_PUBLIC_URL
#     `terraform apply`           -> creates the Cloud Run service; emits service_uri
#
#   Pass 2 (after first apply):
#     terraform output service_uri    -> e.g. https://paperclip-abc123-uc.a.run.app
#     public_url_override = "<that exact URL>"
#     `terraform apply`               -> rolls a new revision with the right PUBLIC_URL
#
# Without Pass 2, Better Auth's trustedOrigins check rejects sign-ins
# because PUBLIC_URL won't match the request origin.
#
# When you eventually have a domain, set `domain = "paperclip.greeteat.com"`
# (full hostname, no scheme) and clear `public_url_override`. The edge
# module will then provision Cloud DNS + the domain mapping and PUBLIC_URL
# becomes `https://${domain}`.
domain              = ""
public_url_override = ""

# -----------------------------------------------------------------------------
# GitHub repository for WIF
# -----------------------------------------------------------------------------
# TODO(operator): set the GitHub repository slug (owner/repo) that owns
# this deployment-spec repository. The WIF provider's attribute_condition
# is restricted to assertions from this exact repo, so Actions in any
# other repo cannot mint tokens against the paperclip-github WIF pool.
github_repository = "GreetEat/greeteat-paperclip"

# -----------------------------------------------------------------------------
# Cloud SQL sizing
# -----------------------------------------------------------------------------
cloud_sql_tier                  = "db-custom-2-7680" # 2 vCPU, 7.5 GiB
cloud_sql_availability_type     = "REGIONAL"         # HA — required for single-env
cloud_sql_backup_retention_days = 7

# -----------------------------------------------------------------------------
# Cloud Run sizing
# -----------------------------------------------------------------------------
cloud_run_min_instances = 2
cloud_run_max_instances = 10
cloud_run_cpu           = "2"
cloud_run_memory        = "2Gi"

# -----------------------------------------------------------------------------
# Cost ceiling
# -----------------------------------------------------------------------------
# TODO(operator): set the monthly USD budget that will trigger an alert.
# Conservative starting point for low-traffic single-env workloads.
monthly_budget_usd = 500
