# =============================================================================
# Module: compute
# =============================================================================
# Creates the runtime service account, all of its IAM bindings (project
# level + per-resource), and the Cloud Run v2 service that runs Paperclip.
#
# This module is the canonical owner of every IAM binding the runtime SA
# needs. Other modules (secrets, artifact-registry, database) expose their
# resource IDs as outputs and this module creates the bindings, which
# breaks what would otherwise be a circular reference between secrets ↔
# compute and artifact-registry ↔ compute.
#
# See contracts/container-image.md for the canonical env var list and the
# secret-name → env-var-name mapping table.
# =============================================================================

# -----------------------------------------------------------------------------
# Runtime service account
# -----------------------------------------------------------------------------

resource "google_service_account" "runtime_sa" {
  account_id   = "paperclip-runtime-sa"
  display_name = "Paperclip Cloud Run runtime"
  description  = "Cloud Run runtime SA. Narrow grants for Cloud SQL, logging, secrets, AR, Vertex. NEVER reuse the default Compute SA."
  project      = var.project_id

  # Note: account_id is a hardcoded literal above, so the
  # never-the-default-Compute-SA invariant is enforced at config time
  # (an earlier lifecycle.precondition was a tautology and used `self.*`
  # which Terraform only allows in postconditions — removed).
}

# -----------------------------------------------------------------------------
# Project-level IAM grants
# -----------------------------------------------------------------------------

# Cloud SQL connection (defensive: even though we connect via private IP
# without IAM auth, granting cloudsql.client makes the SA capable of using
# any future Cloud SQL connection libraries that need it).
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.runtime_sa.email}"
}

# Cloud Logging writer for Cloud Run's awslogs-equivalent.
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.runtime_sa.email}"
}

# Vertex AI user — required for Claude Code (spawned by Paperclip's
# claude_local adapter) to call Vertex Claude. Verified end-to-end on
# 2026-04-10 (Phase B).
resource "google_project_iam_member" "aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.runtime_sa.email}"
}

# -----------------------------------------------------------------------------
# Per-resource IAM grants (the runtime SA's access to resources owned by
# other modules — created here to break the module-level circular reference)
# -----------------------------------------------------------------------------

# Read-write access to the state bucket (GCS FUSE mount at /paperclip).
# objectUser includes create, read, update, delete, list — everything
# GCS FUSE needs for a read-write mount.
resource "google_storage_bucket_iam_member" "state_bucket_access" {
  bucket = var.state_bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.runtime_sa.email}"
}

# Image pull from the paperclip Artifact Registry repository
resource "google_artifact_registry_repository_iam_member" "image_pull" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.runtime_sa.email}"
}

# Secret Manager access for each secret the Cloud Run service mounts.
# Five entries: master-key, better-auth, database-url, s3-access-key-id,
# s3-secret-access-key. Each binding must exist BEFORE the Cloud Run
# service is created — Cloud Run validates secret access at task launch.
resource "google_secret_manager_secret_iam_member" "master_key_access" {
  secret_id = var.master_key_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "better_auth_secret_access" {
  secret_id = var.better_auth_secret_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "database_url_access" {
  secret_id = var.database_url_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "s3_access_key_id_access" {
  secret_id = var.s3_access_key_id_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "s3_secret_access_key_access" {
  secret_id = var.s3_secret_access_key_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime_sa.email}"
}

# -----------------------------------------------------------------------------
# Cloud Run v2 service
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_service" "paperclip" {
  name     = "paperclip"
  location = var.region
  project  = var.project_id

  ingress = "INGRESS_TRAFFIC_ALL" # public ingress; Better Auth gates everything inside

  # The google provider 6.x defaults this to TRUE for Cloud Run v2 services,
  # which prevents Terraform from destroying the service even when it needs
  # to recreate it (e.g. on a failed-then-retried apply, where the resource
  # is in state but in a broken revision). We rely on Cloud Run revision
  # rollback (deploy.sh + rollback.sh in Phase 6/7) for safety, not on
  # delete-protection — Cloud Run keeps prior revisions around and rolling
  # traffic back is the recovery primitive, not "the service object cannot
  # be deleted".
  #
  # Caught the hard way during the second Phase 3 apply: terraform decided
  # to replace the service after the first apply died at health-check, and
  # the destroy step failed with:
  #   Error: cannot destroy service without setting deletion_protection=false
  deletion_protection = false

  labels = {
    service = "paperclip"
  }

  template {
    service_account = google_service_account.runtime_sa.email

    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "PRIVATE_RANGES_ONLY" # only RFC1918 + Google APIs go via the connector
    }

    # GCS FUSE volume — persistent /paperclip filesystem shared across all
    # instances. Without this, /paperclip is a per-instance ephemeral tmpfs
    # and agents lose instructions, memory, and workspace files on every
    # instance recycle. See research.md Decision 21.
    volumes {
      name = "paperclip-state"
      gcs {
        bucket    = var.state_bucket_name
        read_only = false
      }
    }

    containers {
      image = "${var.paperclip_image_url}@${var.paperclip_image_digest}"

      ports {
        container_port = 3100 # Paperclip's default; matches upstream Dockerfile EXPOSE
      }

      volume_mounts {
        name       = "paperclip-state"
        mount_path = "/paperclip"
      }

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }

      # ----- Plain env vars (not from Secret Manager) -----
      env {
        name  = "HOST"
        value = "0.0.0.0"
      }
      env {
        name  = "SERVE_UI"
        value = "true"
      }
      env {
        name  = "PAPERCLIP_HOME"
        value = "/paperclip"
      }
      env {
        name  = "PAPERCLIP_INSTANCE_ID"
        value = "prod"
      }

      # Deployment mode + exposure (TWO separate env vars per the
      # post-Phase-2 source-code audit; allowed values from
      # packages/shared/src/constants.ts in the Paperclip source)
      env {
        name  = "PAPERCLIP_DEPLOYMENT_MODE"
        value = "authenticated"
      }
      env {
        name  = "PAPERCLIP_DEPLOYMENT_EXPOSURE"
        value = "public"
      }
      env {
        name  = "PAPERCLIP_PUBLIC_URL"
        value = var.public_url
      }

      # Invitation-only enforcement (FR-004 / US2)
      env {
        name  = "PAPERCLIP_AUTH_DISABLE_SIGN_UP"
        value = "true"
      }

      env {
        name  = "PAPERCLIP_SECRETS_STRICT_MODE"
        value = "true"
      }

      # Storage (S3-compatible interop against GCS)
      env {
        name  = "PAPERCLIP_STORAGE_PROVIDER"
        value = "s3"
      }
      env {
        name  = "PAPERCLIP_STORAGE_S3_BUCKET"
        value = var.storage_bucket_name
      }
      env {
        name  = "PAPERCLIP_STORAGE_S3_ENDPOINT"
        value = "https://storage.googleapis.com"
      }
      env {
        name  = "PAPERCLIP_STORAGE_S3_REGION"
        value = var.region
      }
      env {
        name  = "PAPERCLIP_STORAGE_S3_FORCE_PATH_STYLE"
        value = "true"
      }

      # Vertex AI Claude — these flow through to the spawned `claude`
      # subprocess via env inheritance. Verified end-to-end in Phase B.
      env {
        name  = "CLAUDE_CODE_USE_VERTEX"
        value = "1"
      }
      env {
        name  = "CLOUD_ML_REGION"
        value = "global"
      }
      env {
        name  = "ANTHROPIC_VERTEX_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "ANTHROPIC_DEFAULT_SONNET_MODEL"
        value = "claude-sonnet-4-6"
      }

      # ----- Secret-mounted env vars -----
      env {
        name = "PAPERCLIP_SECRETS_MASTER_KEY"
        value_source {
          secret_key_ref {
            secret  = var.master_key_secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "BETTER_AUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = var.better_auth_secret_secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = var.database_url_secret_id
            version = "latest"
          }
        }
      }
      # Standard AWS SDK env var names — Paperclip's S3 provider uses the
      # AWS SDK's default credential chain (server/src/storage/s3-provider.ts)
      env {
        name = "AWS_ACCESS_KEY_ID"
        value_source {
          secret_key_ref {
            secret  = var.s3_access_key_id_secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "AWS_SECRET_ACCESS_KEY"
        value_source {
          secret_key_ref {
            secret  = var.s3_secret_access_key_secret_id
            version = "latest"
          }
        }
      }
    }

    timeout = "300s"
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # Cloud Run validates secret + image-pull access at task launch, so all
  # the IAM bindings above MUST exist before the service is created.
  depends_on = [
    google_secret_manager_secret_iam_member.master_key_access,
    google_secret_manager_secret_iam_member.better_auth_secret_access,
    google_secret_manager_secret_iam_member.database_url_access,
    google_secret_manager_secret_iam_member.s3_access_key_id_access,
    google_secret_manager_secret_iam_member.s3_secret_access_key_access,
    google_artifact_registry_repository_iam_member.image_pull,
    google_storage_bucket_iam_member.state_bucket_access,
    google_project_iam_member.cloudsql_client,
    google_project_iam_member.logging_writer,
    google_project_iam_member.aiplatform_user,
  ]
}

# Make the service publicly invokable (Better Auth gates everything inside).
resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = google_cloud_run_v2_service.paperclip.project
  location = google_cloud_run_v2_service.paperclip.location
  name     = google_cloud_run_v2_service.paperclip.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
