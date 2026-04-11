# =============================================================================
# Root composition for the GreetEat Paperclip prod (single) environment.
# =============================================================================
#
# Target project: paperclip-492823 (dedicated, no co-tenant workloads)
# Region:         us-central1
# Single environment for v1 — see plan.md Complexity Tracking entry.
#
# Module instantiations are added phase-by-phase as user stories are
# implemented:
#
#   Phase 2 (Foundational):
#     - module.apis              (T014, T022)
#     - module.network           (T015, T022)
#     - module.secrets           (T016, T022)
#     - module.artifact_registry (T017, T022)
#     - module.workload_identity (T018, T022)
#
#   Phase 3 (US1 — operator sign-in):
#     - module.database          (T027, T032)
#     - module.storage           (T028, T032)
#     - module.compute           (T029, T030, T032)
#     - module.edge              (T031, T032)
#
#   Phase 6 (US4 — reproducible deploy):
#     - module.jobs              (T044, T049)
#
#   Phase 8 (US6 — observability):
#     - module.scheduler         (T054, T058)
#     - module.observability     (T055, T056, T057, T058)
#
# Until each module is created, its `module "..." {}` block stays
# commented out below. Uncommenting + filling args is part of the
# corresponding user-story phase.
# =============================================================================

terraform {
  required_version = "~> 1.10.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Phase 2 — Foundational modules (wired in T022)
# -----------------------------------------------------------------------------

module "apis" {
  source     = "../../modules/apis"
  project_id = var.project_id
}

module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  region     = var.region

  depends_on = [module.apis]
}

module "secrets" {
  source     = "../../modules/secrets"
  project_id = var.project_id

  # runtime_service_account_email is null in Phase 2 — the data lookups
  # validate that bootstrap-master-key.sh and bootstrap-gcs-hmac.sh have
  # been run, but no IAM bindings are created. Phase 3 (T032) updates this
  # to pass module.compute.runtime_service_account_email.
  runtime_service_account_email = null

  depends_on = [module.apis]
}

module "workload_identity" {
  source            = "../../modules/workload-identity"
  project_id        = var.project_id
  github_repository = var.github_repository

  depends_on = [module.apis]
}

module "artifact_registry" {
  source     = "../../modules/artifact-registry"
  project_id = var.project_id
  region     = var.region

  github_actions_service_account_email = module.workload_identity.service_account_email

  # runtime_service_account_email is null in Phase 2; Phase 3 (T032) updates
  # this to pass module.compute.runtime_service_account_email so the runtime
  # SA can pull images from the repository.
  runtime_service_account_email = null

  depends_on = [module.apis]
}

# -----------------------------------------------------------------------------
# Phase 3 — User Story 1 (added in T032)
# -----------------------------------------------------------------------------
# module "database" { ... }
# module "storage" { ... }
# module "compute" { ... }
# module "edge" { ... }

# -----------------------------------------------------------------------------
# Phase 6 — User Story 4 (added in T049)
# -----------------------------------------------------------------------------
# module "jobs" { ... }

# -----------------------------------------------------------------------------
# Phase 8 — User Story 6 (added in T058)
# -----------------------------------------------------------------------------
# module "scheduler" { ... }
# module "observability" { ... }
