# =============================================================================
# Module: jobs
# =============================================================================
# Cloud Run Jobs that share the Paperclip container image, runtime SA, VPC
# connector, and env / secret wiring with the Cloud Run service in the
# compute module — but override the container CMD to run a one-shot CLI
# instead of the HTTP server.
#
# Why Cloud Run Jobs (and not exec into the service):
#   Cloud Run v2 services do NOT support `gcloud run services exec`. There is
#   no way to shell into the running paperclip service. The only way to run
#   `paperclipai auth bootstrap-ceo` (which needs DATABASE_URL,
#   BETTER_AUTH_SECRET, PAPERCLIP_SECRETS_MASTER_KEY, and private VPC access
#   to Cloud SQL) inside the same image with the same env is a Cloud Run Job.
#
# Phase 3 ships only the bootstrap-ceo job (required by T034 — seed operator
# bootstrap is the MVP gate). Phase 6 (T044) adds paperclipai-doctor in this
# same module for the deploy gate + daily Cloud Scheduler trigger.
# =============================================================================

resource "google_cloud_run_v2_job" "bootstrap_ceo" {
  name     = "paperclipai-bootstrap-ceo"
  location = var.region
  project  = var.project_id

  labels = {
    service = "paperclip"
  }

  template {
    template {
      service_account = var.runtime_service_account_email

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      max_retries = 0 # bootstrap is non-idempotent in success case (creates the seed admin); fail-fast on error

      timeout = "300s"

      containers {
        image = "${var.paperclip_image_url}@${var.paperclip_image_digest}"

        # CMD override: run the bootstrap-ceo CLI instead of the HTTP server.
        # The command is non-interactive — confirmed against
        # cli/src/index.ts:152-160 in the post-Phase-2 source-code audit.
        # Paperclip's package.json wires `paperclipai` as a binary, so `pnpm`
        # isn't needed; the binary is on PATH inside the upstream image.
        command = ["paperclipai"]
        args = [
          "auth",
          "bootstrap-ceo",
          "--base-url",
          var.public_url,
        ]

        # Same env shape as the Cloud Run service (compute module). The
        # bootstrap-ceo CLI loads the same Paperclip startup code path as
        # the server, so it needs the same secrets/env to initialize the
        # config + DB connection.

        # ----- Plain env vars -----
        env {
          name  = "PAPERCLIP_HOME"
          value = "/paperclip"
        }
        env {
          name  = "PAPERCLIP_INSTANCE_ID"
          value = "prod"
        }
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
        env {
          name  = "PAPERCLIP_AUTH_DISABLE_SIGN_UP"
          value = "true"
        }
        env {
          name  = "PAPERCLIP_SECRETS_STRICT_MODE"
          value = "true"
        }

        # ----- Secret-mounted env vars -----
        # Bootstrap-ceo writes the seed admin row to Postgres via Drizzle
        # and prints a one-time invite URL signed with BETTER_AUTH_SECRET.
        # It needs DATABASE_URL + BETTER_AUTH_SECRET + the master key
        # (Paperclip's startup refuses to boot without the master key in
        # strict mode). It does NOT touch GCS, so the AWS_* secrets are
        # omitted to keep the blast radius minimal.
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
      }
    }
  }

  # IAM bindings on the mounted secrets live in the compute module (the
  # canonical owner of the runtime SA's IAM). The prod env composition
  # adds an explicit `depends_on = [module.compute]` so those bindings
  # exist before this job is created — Cloud Run Jobs validates secret
  # access at execution time, but the explicit ordering prevents an
  # operator from racing the bootstrap-ceo job ahead of IAM propagation.
}
