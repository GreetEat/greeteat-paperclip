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
# Public hostname
# -----------------------------------------------------------------------------
# TODO(operator): set the actual hostname Paperclip should be reachable at
# under a domain you control. Cloud DNS zone + Cloud Run domain mapping
# will be created by module.edge in Phase 3.
domain = "paperclip.greeteat.example"

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
