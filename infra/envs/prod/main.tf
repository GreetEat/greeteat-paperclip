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

  # Pure data-lookup module: validates that bootstrap-master-key.sh,
  # bootstrap-better-auth-secret.sh, and bootstrap-gcs-hmac.sh have all
  # run. IAM bindings on these secrets are created by the compute module
  # in Phase 3 (the runtime SA's IAM lives there to break a circular
  # reference between secrets ↔ compute).

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

  # The runtime SA's reader binding lives in the compute module (Phase 3)
  # to break a circular reference.
  github_actions_service_account_email = module.workload_identity.service_account_email

  depends_on = [module.apis]
}

# -----------------------------------------------------------------------------
# Phase 3 — User Story 1 (wired in T032)
# -----------------------------------------------------------------------------

module "database" {
  source = "../../modules/database"

  project_id                      = var.project_id
  region                          = var.region
  vpc_id                          = module.network.vpc_id
  private_service_connection_id   = module.network.private_service_connection_id
  cloud_sql_tier                  = var.cloud_sql_tier
  cloud_sql_availability_type     = var.cloud_sql_availability_type
  cloud_sql_backup_retention_days = var.cloud_sql_backup_retention_days

  depends_on = [module.apis, module.network]
}

module "storage" {
  source = "../../modules/storage"

  project_id = var.project_id
  region     = var.region

  depends_on = [module.apis]
}

module "compute" {
  source = "../../modules/compute"

  project_id = var.project_id
  region     = var.region
  domain     = var.domain

  paperclip_image_url    = "${module.artifact_registry.repository_url}/paperclip"
  paperclip_image_digest = var.paperclip_image_digest

  cloud_run_min_instances = var.cloud_run_min_instances
  cloud_run_max_instances = var.cloud_run_max_instances
  cloud_run_cpu           = var.cloud_run_cpu
  cloud_run_memory        = var.cloud_run_memory

  vpc_connector_id = module.network.connector_id

  artifact_registry_repository_id = module.artifact_registry.repository_id
  storage_bucket_name             = module.storage.bucket_name

  master_key_secret_id           = module.secrets.master_key_secret_id
  better_auth_secret_secret_id   = module.secrets.better_auth_secret_secret_id
  database_url_secret_id         = module.database.database_url_secret_id
  s3_access_key_id_secret_id     = module.secrets.s3_access_key_id_secret_id
  s3_secret_access_key_secret_id = module.secrets.s3_secret_access_key_secret_id

  depends_on = [
    module.apis,
    module.network,
    module.secrets,
    module.artifact_registry,
    module.database,
    module.storage,
  ]
}

module "edge" {
  source = "../../modules/edge"

  project_id             = var.project_id
  region                 = var.region
  domain                 = var.domain
  cloud_run_service_name = module.compute.service_name

  depends_on = [module.apis, module.compute]
}

# -----------------------------------------------------------------------------
# Phase 3 enabling — bootstrap-ceo Cloud Run Job
# -----------------------------------------------------------------------------
# Front-loaded from Phase 6 (T044) so the seed-operator bootstrap (T034) can
# run immediately after the first Phase 3 apply. The module currently hosts
# only paperclipai-bootstrap-ceo; paperclipai-doctor lands in Phase 6.
#
# The job runs as the compute module's runtime SA, mounts the same secrets,
# and uses the same VPC connector — so it inherits all the IAM the live
# service has, no extra bindings required. depends_on = module.compute makes
# the IAM-binding ordering explicit.

module "jobs" {
  source = "../../modules/jobs"

  project_id = var.project_id
  region     = var.region
  domain     = var.domain

  paperclip_image_url    = "${module.artifact_registry.repository_url}/paperclip"
  paperclip_image_digest = var.paperclip_image_digest

  vpc_connector_id              = module.network.connector_id
  runtime_service_account_email = module.compute.service_account_email

  master_key_secret_id         = module.secrets.master_key_secret_id
  better_auth_secret_secret_id = module.secrets.better_auth_secret_secret_id
  database_url_secret_id       = module.database.database_url_secret_id

  depends_on = [
    module.apis,
    module.network,
    module.secrets,
    module.artifact_registry,
    module.database,
    module.compute,
  ]
}

# -----------------------------------------------------------------------------
# Phase 8 — User Story 6 (added in T058)
# -----------------------------------------------------------------------------
# module "scheduler" { ... }
# module "observability" { ... }
