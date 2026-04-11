# =============================================================================
# Module: apis
# =============================================================================
# Enables the GCP APIs Paperclip needs in the target project. This is the
# foundation that all other modules implicitly depend on (other modules
# should declare `depends_on = [module.apis]` in main.tf).
#
# The list intentionally includes APIs that are technically already enabled
# on paperclip-492823 by default (compute.googleapis.com, etc.) — Terraform
# treats `google_project_service` as idempotent so this is safe.
# =============================================================================

locals {
  required_apis = [
    "run.googleapis.com",                  # Cloud Run service + jobs
    "sqladmin.googleapis.com",             # Cloud SQL admin API
    "compute.googleapis.com",              # VPC, subnet, firewalls (Cloud SQL needs this for private IP)
    "secretmanager.googleapis.com",        # Secret Manager
    "dns.googleapis.com",                  # Cloud DNS
    "vpcaccess.googleapis.com",            # Serverless VPC Connector (Cloud Run -> Cloud SQL)
    "iam.googleapis.com",                  # IAM resource manager
    "iamcredentials.googleapis.com",       # Service account token issuance (used by WIF)
    "aiplatform.googleapis.com",           # Vertex AI (Claude via Model Garden)
    "artifactregistry.googleapis.com",     # Container image storage
    "cloudscheduler.googleapis.com",       # Daily doctor trigger
    "monitoring.googleapis.com",           # Alerting policies, uptime checks
    "logging.googleapis.com",              # Cloud Logging
    "cloudbilling.googleapis.com",         # Billing budget alerts (FR-027)
    "servicenetworking.googleapis.com",    # Private Services Access (Cloud SQL private IP peering)
    "cloudresourcemanager.googleapis.com", # Project metadata, IAM policy management
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.required_apis)

  project = var.project_id
  service = each.key

  # Don't disable APIs on `terraform destroy` — they may still be in use by
  # other resources in the project, and re-enabling has propagation delays.
  disable_on_destroy = false

  # Don't fail if dependent services are present
  disable_dependent_services = false
}
