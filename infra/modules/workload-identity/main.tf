# =============================================================================
# Module: workload-identity
# =============================================================================
# Project-scoped Workload Identity Federation for GitHub Actions to
# authenticate to GCP without long-lived service account JSON keys.
#
# Project-scoped (not org-scoped) because the operator does not hold the
# org-level WIF permissions. Project-scoped pools work identically for the
# GitHub OIDC -> GCP path.
#
# Resources:
#   - paperclip-github                : Workload Identity Pool
#   - github (provider)               : OIDC provider for token.actions.githubusercontent.com
#   - paperclip-github-actions (SA)   : service account that GitHub Actions impersonates
#   - WIF binding                     : allows the GitHub repo's OIDC tokens to impersonate the SA
#   - Project IAM grants              : roles the SA needs to push images and run terraform apply
#
# WARNING: the v1 IAM grants below include `roles/editor` which is broad.
# Constitutional principle IV (secrets discipline) and the operational
# constraint on agent sandboxing both push toward narrower roles. T065-T067
# in the Polish phase track narrowing this to a custom role.
# =============================================================================

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "paperclip-github"
  display_name              = "Paperclip GitHub Actions"
  description               = "WIF pool for GitHub Actions deploying Paperclip to GCP. Created by infra/modules/workload-identity (T018)."
  project                   = var.project_id
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"
  description                        = "GitHub Actions OIDC provider for the paperclip-github WIF pool. Restricted to assertions from var.github_repository."
  project                            = var.project_id

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
    "attribute.ref"        = "assertion.ref"
  }

  # Hard restriction: only the configured GitHub repo can mint tokens via
  # this provider. Without this condition, ANY GitHub repo could exchange
  # an OIDC token here.
  attribute_condition = "assertion.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions" {
  account_id   = "paperclip-github-actions"
  display_name = "Paperclip GitHub Actions deploy"
  description  = "Service account impersonated by GitHub Actions via the paperclip-github WIF pool. Used by build-image.yml to push container images and by deploy.yml to run terraform apply."
  project      = var.project_id
}

# Allow the GitHub repo (via WIF) to impersonate the SA
resource "google_service_account_iam_member" "github_wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Project-level IAM grants for the SA. v1 uses broad roles for simplicity;
# T065-T067 in the Polish phase narrow this to a custom role.
locals {
  github_actions_roles = [
    "roles/editor",
    "roles/iam.serviceAccountUser",         # required to attach paperclip-runtime-sa to Cloud Run
    "roles/iam.workloadIdentityPoolAdmin",  # required for terraform to manage WIF resources via this same SA in subsequent applies
    "roles/secretmanager.admin",             # editor doesn't include this
    "roles/cloudsql.admin",                  # editor doesn't include this
    "roles/run.admin",                       # editor doesn't include this
    "roles/monitoring.admin",                # editor doesn't include this
    "roles/logging.admin",                   # editor doesn't include this
  ]
}

resource "google_project_iam_member" "github_actions_grants" {
  for_each = toset(local.github_actions_roles)

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
